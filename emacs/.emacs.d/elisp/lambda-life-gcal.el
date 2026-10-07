;;; lambda-life-gcal.el --- Import phone-side DONE ticks from the Tasks calendar  -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; The Lambda Life Android app marks a chore done by renaming its Google
;; Calendar event on the Tasks calendar (`aj/gcal-id-tasks') to "✓ <title>"
;; (U+2713 + space).  The Tasks calendar is push-only from org — only the J
;; calendar is ever fetched — so nothing pulls that tick back on its own.
;;
;; `aj/gcal-import-phone-dones' closes the loop:
;;
;;   1. events.list on the Tasks calendar for yesterday 00:00 .. tomorrow
;;      24:00 (local), singleEvents, cancelled events excluded;
;;   2. for every "✓ " title, entry-id = "<event.id>/<aj/gcal-id-tasks>" and
;;      the heading is looked up by its :entry-id: property in today's daily
;;      first, then the previous `aj/gcal-phone-done-lookback-days' dailies,
;;      newest first.  The carry-forward reuses ONE event id across days (the
;;      event moves forward), so only the newest occurrence is acted on — see
;;      CLAUDE.md "Backlog reality";
;;   3. found and not yet DONE/CANCEL -> (org-todo "DONE") at that heading so
;;      every todo-state hook runs exactly as for C-c C-t: `aj/gcal-hide-done-chore'
;;      deletes the event and strips the gcal identity, the DONE-copy hook
;;      mirrors it into * Tasks.  NOTE: `(org-todo 'done)' would pick the
;;      FIRST done-type keyword of the sequence, which here is CANCEL — hence
;;      the explicit "DONE";
;;   4. found but already DONE/CANCEL, or not found at all -> the stray ticked
;;      event is deleted directly with `org-gcal--delete-event' and etag nil
;;      (unconditional; never `org-gcal-delete-at-point', which can remove the
;;      whole org subtree).
;;
;; Everything network-facing is async (request-deferred), events are handled
;; sequentially, each one under its own error guard, and one "lambda-life: "
;; line per action goes to *Messages*.  No prompts: this runs from a timer in
;; a headless daemon.  A pass backs off while a gcal push chain is in flight
;; (`aj/gcal--sweep-active-p') and while a previous import pass is still
;; running.
;;
;; Scheduling: a repeating timer (`aj/gcal-phone-done-timer', every 10 min,
;; re-created rather than stacked on reload) plus a coalesced 2 s idle timer
;; after `aj/daily-file-open-hook' runs for today's or a future daily.
;;
;; Depends on org-config.el's gcal section for `aj/gcal-id-tasks',
;; `aj/gcal-load-credentials', `aj/gcal-prewarm-token-cache' and
;; `aj/gcal--sweep-active-p', and on org-gcal's request/token internals.

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'subr-x)

(declare-function deferred:succeed "deferred")
(declare-function deferred:nextc "deferred")
(declare-function deferred:error "deferred")
(declare-function deferred:watch "deferred")
(declare-function request-deferred "request-deferred")
(declare-function request-response-status-code "request")
(declare-function request-response-data "request")
(declare-function request-response-error-thrown "request")
(declare-function org-gcal--get-access-token "org-gcal")
(declare-function org-gcal--delete-event "org-gcal")
(declare-function org-gcal--json-read "org-gcal")
(declare-function org-gcal-events-url "org-gcal")
(declare-function aj/gcal-load-credentials "org-config")
(declare-function aj/gcal-prewarm-token-cache "org-config")
(declare-function aj/gcal--sweep-active-p "org-config")
(declare-function aj/daily-date-file-p "daily-structure")
(declare-function aj/daily-today-or-later-p "daily-structure")

(defvar aj/gcal-id-tasks)
(defvar aj/gcal-credentials-loaded)
(defvar aj/daily-hook-suppress)
(defvar org-gcal-entry-id-property)
(defvar org-roam-directory)
(defvar org-roam-dailies-directory)
(defvar org-log-setup)
(defvar org-log-note-this-command)

(defconst aj/gcal-phone-done-prefix "✓ "
  "Title prefix the phone writes on a completed chore's calendar event.")

(defvar aj/gcal-phone-done-lookback-days 3
  "Past dailies (before today) to scan for a ticked event's heading.")

(defvar aj/gcal-phone-done-interval 600
  "Seconds between timer-driven import passes.")

(defvar aj/gcal-phone-done-timer nil
  "Repeating timer running `aj/gcal-import-phone-dones', or nil.")

(defvar aj/gcal-phone-done--open-timer nil
  "Pending idle timer scheduled by `aj/gcal-phone-done-on-daily-open', if any.")

(defvar aj/gcal-phone-done--active-since nil
  "`float-time' when the current import pass started, or nil when idle.
Auto-expires after 5 minutes so a pass that died mid-chain cannot wedge
the importer.")

(defun aj/gcal--phone-done-active-p ()
  "Non-nil while an import pass is in flight.
See `aj/gcal-phone-done--active-since'."
  (and aj/gcal-phone-done--active-since
       (< (- (float-time) aj/gcal-phone-done--active-since) 300)))

;; ---------------------------------------------------------------------------
;; Daily-file lookup
;; ---------------------------------------------------------------------------

(defun aj/gcal--daily-file-for-date (date-str)
  "Absolute path of the daily note for DATE-STR (YYYY-MM-DD), existing or not.
Mirrors the path construction in daily-calendar.el / daily-recurring.el."
  (let ((dir (if (bound-and-true-p org-roam-directory)
                 (expand-file-name (or (bound-and-true-p org-roam-dailies-directory)
                                       "daily")
                                   org-roam-directory)
               (expand-file-name "~/lattice/org-notes/daily/"))))
    (expand-file-name (concat date-str ".org") dir)))

(defun aj/gcal--phone-done-candidate-files ()
  "Existing daily files to search, newest first: today, then the previous days."
  (let (files)
    (dotimes (n (1+ aj/gcal-phone-done-lookback-days))
      (let ((file (aj/gcal--daily-file-for-date
                   (format-time-string "%Y-%m-%d"
                                       (time-subtract nil (* n 24 3600))))))
        (when (file-exists-p file)
          (push file files))))
    (nreverse files)))

(defun aj/gcal--find-heading-by-entry-id (entry-id)
  "Return a marker on the newest daily heading whose :entry-id: is ENTRY-ID.
Searches `aj/gcal--phone-done-candidate-files' in order and stops at the first
hit, so an id that is resolved on an old daily but live on a newer one
resolves to the live occurrence.  Returns nil when no daily carries it."
  (catch 'found
    (dolist (file (aj/gcal--phone-done-candidate-files))
      (with-current-buffer (find-file-noselect file)
        (org-with-wide-buffer
         (let ((pos (org-find-property org-gcal-entry-id-property entry-id)))
           (when pos
             (throw 'found (copy-marker pos)))))))
    nil))

;; ---------------------------------------------------------------------------
;; Calendar API: list the window, delete a stray
;; ---------------------------------------------------------------------------

(defun aj/gcal--phone-done-window ()
  "Return (TIME-MIN . TIME-MAX) as RFC 3339 strings with the local offset.
TIME-MIN is yesterday 00:00 local, TIME-MAX tomorrow 24:00 local, so an
all-day chore on any of those three days lands inside the window."
  (let* ((now (decode-time))
         (midnight (encode-time (list 0 0 0
                                      (decoded-time-day now)
                                      (decoded-time-month now)
                                      (decoded-time-year now)
                                      nil -1 nil)))
         (fmt "%Y-%m-%dT%H:%M:%S%:z"))
    (cons (format-time-string fmt (time-subtract midnight (* 24 3600)))
          (format-time-string fmt (time-add midnight (* 48 3600))))))

(defun aj/gcal--phone-done-list-events ()
  "Return a deferred yielding the Tasks-calendar events in the import window.
Each event is a plist as produced by `org-gcal--json-read'.  Rejects with an
error on a non-200 response so the caller's :catch can log it."
  (let ((window (aj/gcal--phone-done-window))
        (token (org-gcal--get-access-token aj/gcal-id-tasks)))
    (deferred:nextc
     (request-deferred
      (org-gcal-events-url aj/gcal-id-tasks)
      :type "GET"
      :headers `(("Accept" . "application/json")
                 ("Authorization" . ,(format "Bearer %s" token)))
      :params `(("timeMin" . ,(car window))
                ("timeMax" . ,(cdr window))
                ("singleEvents" . "true")
                ("showDeleted" . "false")
                ("maxResults" . "2500"))
      :parser 'org-gcal--json-read)
     (lambda (response)
       (let ((status (request-response-status-code response))
             (data (request-response-data response)))
         (unless (eq status 200)
           (error "events.list on the Tasks calendar failed: HTTP %s %S"
                  status (request-response-error-thrown response)))
         (when (plist-get data :nextPageToken)
           (message "lambda-life: window holds more than one page of events; only the first page was scanned"))
         (append (plist-get data :items) nil))))))

(defun aj/gcal--phone-done-event-p (event)
  "Non-nil when EVENT's summary carries the phone's done tick."
  (let ((summary (plist-get event :summary)))
    (and (stringp summary)
         (string-prefix-p aj/gcal-phone-done-prefix summary))))

(defun aj/gcal--phone-done-delete (event-id label dry-run)
  "Delete ticked EVENT-ID from the Tasks calendar; LABEL names it in the log.
Unconditional (etag nil), so the HTTP-412 branch of `org-gcal--delete-event'
— the only one that rewrites an org buffer — can never run; the marker it is
handed is a fresh detached one because that function unconditionally clears
it in its :finally.  HTTP 404/410 means the event is already gone and is
logged as such.  Returns a deferred; DRY-RUN only logs."
  (if dry-run
      (progn
        (message "lambda-life: [dry run] would delete ticked event: %s" label)
        (deferred:succeed nil))
    (deferred:nextc
     (deferred:error
      (org-gcal--delete-event aj/gcal-id-tasks event-id nil (make-marker))
      (lambda (err)
        (let ((text (format "%S" err)))
          (if (string-match-p "Got error 4\\(?:04\\|10\\)" text)
              (message "lambda-life: ticked event already gone: %s" label)
            (message "lambda-life: delete failed for %s: %s" label text)))
        'aj/gcal--delete-failed))
     (lambda (result)
       (unless (eq result 'aj/gcal--delete-failed)
         (message "lambda-life: deleted ticked event: %s" label))
       nil))))

;; ---------------------------------------------------------------------------
;; Marking the org heading DONE
;; ---------------------------------------------------------------------------

(defun aj/gcal--flush-pending-log-note ()
  "Store org's deferred state-change log line now.
`org-todo' with a \"!\" keyword only *schedules* the LOGBOOK line via
`post-command-hook' and `org-add-log-note', which from a timer fires at some
arbitrary later command (or never, if `this-command' has moved on).  Run it
here, inside `save-window-excursion', so the buffer ends up exactly as an
interactive C-c C-t would leave it."
  (when (and (bound-and-true-p org-log-setup)
             (memq 'org-add-log-note post-command-hook))
    (condition-case err
        (save-window-excursion
          (let ((this-command org-log-note-this-command))
            (org-add-log-note)))
      (error
       (remove-hook 'post-command-hook 'org-add-log-note)
       (setq org-log-setup nil)
       (message "lambda-life: could not store the state-change log line: %s"
                (error-message-string err))))))

(defun aj/gcal--phone-done-mark-done (marker)
  "Mark the heading at MARKER DONE with every todo-state hook, then save.
Point sits on the heading when `org-todo' runs, which `aj/gcal-hide-done-chore'
requires (it reads entry-id/calendar-id at point).  Clears MARKER."
  (let ((buf (marker-buffer marker)))
    (with-current-buffer buf
      (org-with-wide-buffer
       (goto-char marker)
       (org-back-to-heading t)
       ;; The phone's rename changed the event's ETag, so the one stored here
       ;; is stale by construction.  `aj/gcal-delete-event-at-point' (run by
       ;; hide-done) sends the stored ETag as If-Match; a stale one gets HTTP
       ;; 412 and org-gcal's 412 branch OVERWRITES this heading from the server
       ;; (title becomes the ticked one, CLOSED/LOGBOOK vanish) without ever
       ;; deleting the event.  Dropping the property makes that delete the
       ;; unconditional one it is documented to be.
       (org-entry-delete nil "ETag")
       (org-todo "DONE")
       (aj/gcal--flush-pending-log-note))
      (when (buffer-modified-p)
        (save-buffer)))
    (set-marker marker nil)))

;; ---------------------------------------------------------------------------
;; Per-event dispatch and the sequential chain
;; ---------------------------------------------------------------------------

(defun aj/gcal--phone-done-handle (event dry-run)
  "Act on one ticked EVENT.  Returns a deferred and never signals.
DRY-RUN only logs what would happen."
  (condition-case err
      (let* ((summary (plist-get event :summary))
             (event-id (plist-get event :id))
             (title (string-trim
                     (substring summary (length aj/gcal-phone-done-prefix))))
             (entry-id (format "%s/%s" event-id aj/gcal-id-tasks))
             (marker (aj/gcal--find-heading-by-entry-id entry-id))
             (state (and marker (org-with-point-at marker (org-get-todo-state))))
             (where (and marker
                         (file-name-nondirectory
                          (or (buffer-file-name (marker-buffer marker)) "")))))
        (cond
         ((null marker)
          (aj/gcal--phone-done-delete
           event-id
           (format "%s (no heading with entry-id %s in the last %d dailies)"
                   title entry-id (1+ aj/gcal-phone-done-lookback-days))
           dry-run))
         ((member state '("DONE" "CANCEL"))
          (set-marker marker nil)
          (aj/gcal--phone-done-delete
           event-id (format "%s (already %s in %s)" title state where) dry-run))
         (dry-run
          (set-marker marker nil)
          (message "lambda-life: [dry run] would mark DONE: %s (%s in %s)"
                   title (or state "keyword-less") where)
          (deferred:succeed nil))
         (t
          (aj/gcal--phone-done-mark-done marker)
          (message "lambda-life: marked DONE: %s (was %s in %s); hide-done is removing its event"
                   title (or state "keyword-less") where)
          (deferred:succeed nil))))
    (error
     (message "lambda-life: error on event %s: %s"
              (plist-get event :id) (error-message-string err))
     (deferred:succeed nil))))

(defun aj/gcal--phone-done-chain (events dry-run)
  "Handle EVENTS one after another (each waits for the previous delete).
Returns a deferred that resolves when the whole list has been processed."
  (if (null events)
      (deferred:succeed nil)
    (deferred:nextc
     (aj/gcal--phone-done-handle (car events) dry-run)
     (lambda (_)
       (aj/gcal--phone-done-chain (cdr events) dry-run)))))

;; ---------------------------------------------------------------------------
;; Entry point
;; ---------------------------------------------------------------------------

;;;###autoload
(defun aj/gcal-import-phone-dones (&optional dry-run)
  "Import phone-side ticks (\"✓ \" titles on the Tasks calendar) into org.
Ticked events whose heading is still open are marked DONE through
`org-todo' (so hide-done deletes the event); ticks on already-resolved or
unknown headings are deleted outright.  With DRY-RUN (interactively, a
prefix argument) only report what would be done.  Async; logs one
\"lambda-life: \" line per action to *Messages*.  Backs off while a gcal
push chain or a previous import pass is in flight."
  (interactive "P")
  (cond
   ((aj/gcal--phone-done-active-p)
    (message "lambda-life: an import pass is already in flight; skipping this one"))
   ((and (fboundp 'aj/gcal--sweep-active-p) (aj/gcal--sweep-active-p))
    (message "lambda-life: gcal push chain in flight; import backs off until the next pass"))
   (t
    (aj/gcal-load-credentials)
    (if (not (bound-and-true-p aj/gcal-credentials-loaded))
        (message "lambda-life: Google Calendar credentials unavailable; import skipped")
      (require 'org-gcal)
      (require 'deferred)
      (require 'request-deferred)
      (aj/gcal-prewarm-token-cache)
      (setq aj/gcal-phone-done--active-since (float-time))
      (condition-case err
          (deferred:nextc
           (deferred:error
            (deferred:nextc
             (aj/gcal--phone-done-list-events)
             (lambda (events)
               (let ((ticked (cl-remove-if-not #'aj/gcal--phone-done-event-p events)))
                 (message "lambda-life: %d event(s) in the Tasks window, %d ticked%s"
                          (length events) (length ticked)
                          (if dry-run " [dry run]" ""))
                 (aj/gcal--phone-done-chain ticked dry-run))))
            (lambda (err)
              (message "lambda-life: import failed: %S" err)
              nil))
           (lambda (_)
             (setq aj/gcal-phone-done--active-since nil)
             nil))
        (error
         ;; Synchronous failure before the chain existed (e.g. token fetch).
         (setq aj/gcal-phone-done--active-since nil)
         (message "lambda-life: import failed: %s" (error-message-string err))))
      nil))))

;; ---------------------------------------------------------------------------
;; Scheduling
;; ---------------------------------------------------------------------------

(defun aj/gcal-phone-done-start-timer ()
  "(Re)start the repeating import timer without stacking a second one."
  (when (timerp aj/gcal-phone-done-timer)
    (cancel-timer aj/gcal-phone-done-timer))
  (setq aj/gcal-phone-done-timer
        (run-with-timer 60 aj/gcal-phone-done-interval
                        #'aj/gcal-import-phone-dones))
  aj/gcal-phone-done-timer)

(defun aj/gcal-phone-done-on-daily-open (&rest _)
  "After `aj/daily-file-open-hook' on today's or a future daily, import soon.
Deferred to a 2 s idle timer (coalesced: a double hook fire schedules one
pass) so it runs after the daily's own sweep has had its 1 s slot.  No-op
during suppressed opens (`aj/daily-hook-suppress', e.g. org-capture)."
  (when (and (not (bound-and-true-p aj/daily-hook-suppress))
             (fboundp 'aj/daily-date-file-p)
             (aj/daily-date-file-p)
             (or (not (fboundp 'aj/daily-today-or-later-p))
                 (aj/daily-today-or-later-p)))
    (when (timerp aj/gcal-phone-done--open-timer)
      (cancel-timer aj/gcal-phone-done--open-timer))
    (setq aj/gcal-phone-done--open-timer
          (run-with-idle-timer
           2 nil
           (lambda ()
             (setq aj/gcal-phone-done--open-timer nil)
             (condition-case err
                 (aj/gcal-import-phone-dones)
               (error
                (message "lambda-life: import on daily open failed: %s"
                         (error-message-string err)))))))))

(aj/gcal-phone-done-start-timer)

;; `aj/daily-file-open-hook' is a function (the body of
;; `org-roam-dailies-find-file-hook'), not a hook variable, so hang off it
;; with after-advice; idempotent across reloads.
(when (fboundp 'aj/daily-file-open-hook)
  (advice-add 'aj/daily-file-open-hook :after #'aj/gcal-phone-done-on-daily-open))

(provide 'lambda-life-gcal)
;;; lambda-life-gcal.el ends here
