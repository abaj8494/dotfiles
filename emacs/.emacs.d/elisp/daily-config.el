;;; daily-config.el --- Daily note configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; All daily-note functionality: recurring tasks, weather, calendar,
;; capture templates, weekly transclusion, heading structure, navigation.

;;; Code:

(require 'org-roam)
(require 'org-roam-dailies)
(require 'cl-lib)
(require 'daily-structure)
(require 'daily-week)
(require 'daily-recurring)
(require 'daily-capture)
(require 'daily-calendar)

;; ---------------------------------------------------------------------------
;; Variables & Config
;; ---------------------------------------------------------------------------

(defvar aj/daily-hook-suppress nil
  "When non-nil, `aj/daily-file-open-hook' is suppressed.
Used to prevent side-effects (overdue bring-forward, calendar refresh, etc.)
when files are opened during org-capture.")




;; ---------------------------------------------------------------------------
;; OpenWeatherMap for Calendar (uses API key from authinfo.gpg)


;; ---------------------------------------------------------------------------
;; Daily Lifecycle & Navigation
;; ---------------------------------------------------------------------------


(defun aj/daily-needs-setup-p ()
  "Return t if current daily file needs full setup.
Checks if the file is missing the Journal heading (indicates bare template)."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (not (re-search-forward "^\\* Journal\\b" nil t)))))

(defun aj/setup-daily-file ()
  "Run full setup for a daily file.
Inserts transclude, ensures headings, populates recurring and calendar."
  ;; 1. Insert week transclude if not present
  (save-excursion
    (goto-char (point-min))
    (unless (or (re-search-forward "^#\\+transclude:" nil t)
                (progn (goto-char (point-min))
                       (re-search-forward "^\\* \\(\\[\\[id:[^]]+\\]\\[\\)?Week [0-9]+" nil t)))
      (aj/insert-week-transclude)))
  ;; 2. Ensure all headings exist in correct order (with statistics cookies)
  (aj/ensure-daily-structure)
  ;; 3. Refresh recurring tasks
  (aj/refresh-daily-recurring)
  ;; 3b. Bring forward overdue captures from previous days
  (aj/bring-forward-overdue-captures)
  ;; 3c. Bring forward overdue priority tasks from previous days' Recurring
  (aj/bring-forward-overdue-recurring)
  (aj/ensure-recurring-separators)
  ;; 3d. Re-sweep #+LATEX: \newpage. Inserting recurring/overdue subtrees
  ;; at section-end splices content between a canonical newpage and its
  ;; heading, orphaning the directive. Without this sweep, capture-born
  ;; files ship with the orphan baked in.
  (aj/ensure-heading-newpages)
  ;; 4. Update statistics cookies
  (save-excursion
    (dolist (heading aj/headings-with-statistics)
      (goto-char (point-min))
      (when (re-search-forward (format "^\\* %s\\b" (regexp-quote heading)) nil t)
        (org-update-statistics-cookies nil))))
  ;; 5. Insert calendar content
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^\\* Calendar\\b" nil t)
      (let ((heading-end (line-end-position))
            (next-heading (save-excursion
                            (forward-line 1)
                            (if (re-search-forward "^\\* " nil t)
                                (line-beginning-position)
                              (point-max)))))
        ;; Check if there's no content between Calendar and next heading
        (when (< (- next-heading heading-end) 5)
          (my/insert-aj-day-calendar)))))
  )

;; Hook for file open - sets up new files and enables transclusion
(defvar aj/daily-hook-log-threshold 0.5
  "If `aj/daily-file-open-hook' takes longer than this (seconds),
log per-step timings to *Messages*. Set to 0 to always log.")

(defvar aj/daily-hook-debug nil
  "When non-nil, always log per-step timings for `aj/daily-file-open-hook',
regardless of `aj/daily-hook-log-threshold'.")

(defmacro aj/daily-time-step (timings name &rest body)
  "Run BODY, push (NAME . elapsed-seconds) onto TIMINGS."
  (declare (indent 2))
  `(let ((aj--t0 (float-time)))
     (prog1 (progn ,@body)
       (push (cons ,name (- (float-time) aj--t0)) ,timings))))

(defun aj/daily-file-open-hook ()
  "Hook for opening daily files.
For new/bare files: runs full setup (transclude, headings, recurring, calendar).
For all files: enables transclusion, refreshes recurring tasks and calendar.
Skipped during org-capture to avoid side-effects (e.g. cancelling source items).

Per-step timings are logged to *Messages* when the total exceeds
`aj/daily-hook-log-threshold' or when `aj/daily-hook-debug' is non-nil."
  (when (and (aj/daily-date-file-p)
             (not aj/daily-hook-suppress))
    (let ((aj--hook-start (float-time))
          (aj--timings nil))
      ;; Check if this is a new file that needs setup
      (if (aj/daily-needs-setup-p)
          (aj/daily-time-step aj--timings "setup-daily-file"
            (aj/setup-daily-file))
        ;; For existing files, refresh recurring, overdue, and calendar content
        (aj/daily-time-step aj--timings "ensure-daily-structure"
          (aj/ensure-daily-structure))
        (aj/daily-time-step aj--timings "refresh-daily-recurring"
          (aj/refresh-daily-recurring))
        (aj/daily-time-step aj--timings "bring-forward-overdue-captures"
          (aj/bring-forward-overdue-captures))
        (aj/daily-time-step aj--timings "bring-forward-overdue-recurring"
          (aj/bring-forward-overdue-recurring))
        (aj/daily-time-step aj--timings "ensure-heading-separators"
          (aj/ensure-heading-separators))
        (aj/daily-time-step aj--timings "ensure-heading-newpages"
          (aj/ensure-heading-newpages))
        (aj/daily-time-step aj--timings "ensure-recurring-separators"
          (aj/ensure-recurring-separators))
        (aj/daily-time-step aj--timings "refresh-daily-calendar"
          (aj/refresh-daily-calendar)))
      ;; Enable org-transclusion-mode to render transcludes
      (when (and (fboundp 'org-transclusion-mode)
                 (not (bound-and-true-p org-transclusion-mode)))
        (aj/daily-time-step aj--timings "org-transclusion-mode"
          (org-transclusion-mode 1)))
      ;; Save if we did setup
      (when (buffer-modified-p)
        (aj/daily-time-step aj--timings "save-buffer"
          (save-buffer)))
      ;; Log timings if slow or debug is on
      (let ((total (- (float-time) aj--hook-start)))
        (when (or aj/daily-hook-debug
                  (>= total aj/daily-hook-log-threshold))
          (message "[daily-hook] %.3fs total for %s: %s"
                   total
                   (file-name-nondirectory (or buffer-file-name "?"))
                   (mapconcat (lambda (cell)
                                (format "%s=%.3fs" (car cell) (cdr cell)))
                              (nreverse aj--timings)
                              " ")))))))


(defun aj/org-roam-dailies-goto-next-day ()
  "Go to the next day's daily note, creating it if necessary.
Unlike `org-roam-dailies-goto-next-note', this always goes to the
chronologically next day, not just the next existing note."
  (interactive)
  (unless (org-roam-dailies--daily-note-p)
    (user-error "Not in a daily-note"))
  (let* ((filename (file-name-sans-extension
                    (file-name-nondirectory (buffer-file-name))))
         (current-time (org-time-string-to-time filename))
         (next-time (time-add current-time 86400))) ; 86400 seconds = 1 day
    (org-roam-dailies--capture next-time t)))

(defun aj/org-roam-dailies-goto-previous-day ()
  "Go to the previous day's daily note, creating it if necessary.
Unlike `org-roam-dailies-goto-previous-note', this always goes to the
chronologically previous day, not just the previous existing note."
  (interactive)
  (unless (org-roam-dailies--daily-note-p)
    (user-error "Not in a daily-note"))
  (let* ((filename (file-name-sans-extension
                    (file-name-nondirectory (buffer-file-name))))
         (current-time (org-time-string-to-time filename))
         (prev-time (time-add current-time -86400))) ; -86400 seconds = -1 day
    (org-roam-dailies--capture prev-time t)))

;; ---------------------------------------------------------------------------
;; Refile to Daily
;; ---------------------------------------------------------------------------

(defun my/org-roam-copy-todo-to-today ()
  "Refile the current heading to today's daily note under the 'Tasks' heading.
Preserves transclusion state in current buffer."
  (interactive)
  (let ((org-refile-keep t) ;; Set to nil to move instead of copy
        (org-after-refile-insert-hook #'save-buffer)
        (source-buffer (current-buffer))
        (source-transclusion-active (bound-and-true-p org-transclusion-mode))
        today-file
        pos)
    ;; Open today's daily and ensure "Tasks" heading exists
    (save-window-excursion
      (org-roam-dailies--capture (current-time) t)
      (setq today-file (buffer-file-name))
      ;; Create "Tasks" heading if it doesn't exist (for older dailies)
      (goto-char (point-min))
      (unless (re-search-forward "^\\* Tasks\\b" nil t)
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert "* Tasks [/]\n"))
      ;; Ensure cookie exists on Tasks heading
      (aj/ensure-heading-has-statistics-cookie "Tasks")
      ;; Get position of Tasks heading
      (goto-char (point-min))
      (re-search-forward "^\\* Tasks\\b" nil t)
      (setq pos (point))
      (save-buffer))

    ;; Only refile if the target file is different than the current file
    (unless (equal (file-truename today-file)
                   (file-truename (buffer-file-name)))
      (org-refile nil nil (list "Tasks" today-file nil pos))
      ;; Update statistics cookie in target file
      (with-current-buffer (find-file-noselect today-file)
        (save-excursion
          (goto-char (point-min))
          (when (re-search-forward "^\\* Tasks\\b" nil t)
            (org-update-statistics-cookies nil)))
        (save-buffer)))

    ;; Restore transclusion mode in source buffer if it was active
    (when (and source-transclusion-active
               (buffer-live-p source-buffer))
      (with-current-buffer source-buffer
        (unless (bound-and-true-p org-transclusion-mode)
          (org-transclusion-mode 1))))))

;; Copy DONE headings to today's Tasks — but ONLY when the state change
;; happens inside a daily file under * Recurring or * Capture.  Without
;; this guard the hook also fires when `aj/propagate-done-to-tasks' marks
;; the corresponding heading DONE in tasks.org, which parasitically copies
;; the tasks.org version back into the daily's * Tasks (wrong metadata,
;; duplicates, stale CLOSED dates from other days).
(add-hook 'org-after-todo-state-change-hook
          (lambda ()
            (when (and (equal org-state "DONE")
                       (aj/daily-date-file-p)
                       (or (aj/under-heading-p "^\\* Recurring\\b")
                           (aj/under-heading-p "^\\* Capture\\b")))
              (my/org-roam-copy-todo-to-today))))

;; ---------------------------------------------------------------------------
;; Propagate DONE to tasks.org
;; ---------------------------------------------------------------------------

(defun aj/propagate-done-to-tasks ()
  "When a heading is marked DONE/CANCEL under * Recurring in a daily note,
find the corresponding heading in tasks.org and mark it DONE there too.
This advances the repeater via org-mode's built-in `org-auto-repeat-maybe'.
Suppressed when `aj/daily-hook-suppress' is non-nil so that machine-driven
state changes (e.g. bring-forward source-CANCEL) don't cascade into
tasks.org."
  (when (and (not aj/daily-hook-suppress)
             (member org-state '("DONE" "CANCEL"))
             (aj/daily-date-file-p)
             (aj/under-heading-p "^\\* Recurring\\b"))
    (let* ((heading-text (org-get-heading t t t t))
           ;; Build parent chain for disambiguation
           (parent-chain
            (save-excursion
              (let ((chain (list heading-text)))
                (while (org-up-heading-safe)
                  (let ((h (org-get-heading t t t t)))
                    (unless (string= h "Recurring")
                      (push h chain))))
                chain)))
           (tasks-buf (find-file-noselect (expand-file-name aj/tasks-file))))
      (when tasks-buf
        (with-current-buffer tasks-buf
          (save-excursion
            (goto-char (point-min))
            (let ((found nil))
              ;; Try to find matching heading by walking the parent chain
              (if (= (length parent-chain) 1)
                  ;; Simple case: top-level child of Recurring (now * in tasks.org)
                  (when (re-search-forward
                         (format "^\\*+ \\(?:TODO \\|DONE \\|WAIT \\|CANCEL \\)?\\(?:\\[#[A-Z]\\] \\)?%s\\(?:[ \t]*$\\|[ \t]\\)"
                                 (regexp-quote heading-text))
                         nil t)
                    (setq found t))
                ;; Multi-level: walk the chain, constraining each step to the parent subtree
                (catch 'found
                  (goto-char (point-min))
                  (let ((search-end (point-max)))
                    (dolist (parent (butlast parent-chain))
                      (unless (re-search-forward
                               (format "^\\*+ \\(?:TODO \\|DONE \\|WAIT \\|CANCEL \\)?\\(?:\\[#[A-Z]\\] \\)?%s\\(?:[ \t]*$\\|[ \t]\\)"
                                       (regexp-quote parent))
                               search-end t)
                        (throw 'found nil))
                      (setq search-end (save-excursion (org-end-of-subtree t t) (point))))
                    (when (re-search-forward
                           (format "^\\*+ \\(?:TODO \\|DONE \\|WAIT \\|CANCEL \\)?\\(?:\\[#[A-Z]\\] \\)?%s\\(?:[ \t]*$\\|[ \t]\\)"
                                   (regexp-quote heading-text))
                           search-end t)
                      (setq found t)))))
              (when found
                (beginning-of-line)
                (let ((sched (org-entry-get (point) "SCHEDULED")))
                  (if (and sched (string-match-p "\\`<%%(" sched))
                      ;; Diary-sexp schedule: can't be advanced by a repeater,
                      ;; so bump LAST_REPEAT in-place and leave state as TODO.
                      (org-entry-put (point) "LAST_REPEAT"
                                     (format-time-string
                                      (org-time-stamp-format t t)))
                    ;; Standard repeater: let org advance SCHEDULED/LAST_REPEAT
                    ;; and reset state. Auto-confirm the "N repeater intervals"
                    ;; prompt org shows when SCHEDULED is far behind today.
                    (cl-letf (((symbol-function 'y-or-n-p)
                               (lambda (&rest _) t)))
                      (org-todo "DONE"))))
                (save-buffer)
                (message "Propagated DONE to tasks.org: %s" heading-text)))))))))

(add-hook 'org-after-todo-state-change-hook #'aj/propagate-done-to-tasks)

;; Run aj/daily-file-open-hook each time a daily is opened.
(add-hook 'org-roam-dailies-find-file-hook #'aj/daily-file-open-hook)

;; ---------------------------------------------------------------------------
;; Keybindings
;; ---------------------------------------------------------------------------

;; Add extra bindings to dailies map
(define-key org-roam-dailies-map (kbd "Y") #'org-roam-dailies-capture-yesterday)
(define-key org-roam-dailies-map (kbd "c") #'org-roam-dailies-capture-date)
(define-key org-roam-dailies-map (kbd "g") #'org-roam-dailies-goto-date)
(define-key org-roam-dailies-map (kbd "T") #'org-roam-dailies-capture-tomorrow)
(define-key org-roam-dailies-map (kbd "F") #'aj/org-roam-dailies-goto-next-day)
(define-key org-roam-dailies-map (kbd "B") #'aj/org-roam-dailies-goto-previous-day)
;; V = capture to date (creates note if needed, prompts for date)
(define-key org-roam-dailies-map (kbd "V") #'org-roam-dailies-capture-date)
;; w = insert week transclude in current daily
(define-key org-roam-dailies-map (kbd "w") #'aj/insert-week-transclude)

;; ---------------------------------------------------------------------------
;; rMPP push — pull highlights, then export + push today's daily to the device
;; ---------------------------------------------------------------------------

;; Log buffer is space-prefixed so it stays out of the normal buffer list.
;; View with `C-x b SPC *rmpp-push-daily* RET' when debugging.
(defconst aj/rmpp--log-buffer-name " *rmpp-push-daily*")
(defconst aj/rmpp--success-sound "/System/Library/Sounds/Glass.aiff")
(defconst aj/rmpp--failure-sound "/System/Library/Sounds/Basso.aiff")
(defconst aj/rmpp--edge-tts (expand-file-name "~/miniconda3/bin/edge-tts"))

(defun aj/rmpp--log-buffer ()
  "Return (creating if needed) the hidden log buffer for rmpp push."
  (get-buffer-create aj/rmpp--log-buffer-name))

(defun aj/rmpp--log (fmt &rest args)
  "Append a formatted line to the rmpp log buffer."
  (with-current-buffer (aj/rmpp--log-buffer)
    (goto-char (point-max))
    (insert (apply #'format fmt args))))

(defun aj/rmpp--play-sound (path)
  "Play PATH via `afplay' asynchronously. Silently no-op if missing."
  (when (file-exists-p path)
    (call-process "/usr/bin/afplay" nil 0 nil path)))

(defun aj/rmpp--speak (text)
  "Synthesise TEXT via `edge-tts' to a temp mp3 and play it with afplay.
Both steps run asynchronously so Emacs stays responsive."
  (when (file-executable-p aj/rmpp--edge-tts)
    (let ((mp3 (make-temp-file "rmpp-tts-" nil ".mp3")))
      (set-process-sentinel
       (start-process "rmpp-tts" nil aj/rmpp--edge-tts
                      "--text" text "--write-media" mp3)
       (lambda (_p event)
         (when (string-match-p "finished" event)
           (aj/rmpp--play-sound mp3)))))))

(defun aj/rmpp--tail-error ()
  "Return a short diagnostic string extracted from the tail of the log.
Prefers lines that look like errors; falls back to the last non-empty
line, or a generic message."
  (with-current-buffer (aj/rmpp--log-buffer)
    (save-excursion
      (goto-char (point-max))
      (let ((limit (max (point-min) (- (point) 4000)))
            err last-nonempty)
        (while (and (> (point) limit)
                    (not err))
          (forward-line -1)
          (let ((line (string-trim
                       (buffer-substring-no-properties
                        (line-beginning-position) (line-end-position)))))
            (unless (string-empty-p line)
              (unless last-nonempty (setq last-nonempty line))
              (when (string-match-p
                     "\\(?:ERROR\\|Error\\|unreachable\\|refused\\|timed out\\|No such\\|FAIL\\)"
                     line)
                (setq err line)))))
        (or err last-nonempty "unknown error")))))

(defun aj/rmpp--notify-success ()
  (aj/rmpp--log "=== SUCCESS ===\n")
  (aj/rmpp--play-sound aj/rmpp--success-sound)
  (message "rMPP: daily pushed ✓"))

(defun aj/rmpp--notify-failure (step)
  "Announce failure of STEP (a string, e.g. \"pull\" or \"push\").
Plays Basso, then speaks a short description extracted from the log."
  (let* ((reason (aj/rmpp--tail-error))
         (spoken (format "Remarkable %s failed. %s" step reason)))
    (aj/rmpp--log "=== FAILURE [%s]: %s ===\n" step reason)
    (aj/rmpp--play-sound aj/rmpp--failure-sound)
    (aj/rmpp--speak spoken)
    (message "rMPP: %s failed — %s" step reason)))

(defun aj/rmpp--run-step (label command on-success)
  "Run COMMAND (a list) into the hidden log buffer.
On exit 0, call ON-SUCCESS. On non-zero, announce failure labelled LABEL.

Re-establishes the miniconda PATH override for every spawn because
`process-environment' is a dynamic variable — a let-binding around the
outer call doesn't survive into sentinels, so the second step would
otherwise lose its custom PATH."
  (let* ((conda-bin (expand-file-name "~/miniconda3/bin"))
         (process-environment
          (cons (concat "PATH=" conda-bin ":" (getenv "PATH"))
                process-environment)))
    (aj/rmpp--log "\n--- %s: %s ---\n" label (mapconcat #'identity command " "))
    (make-process
     :name (format "rmpp-%s" label)
     :buffer (aj/rmpp--log-buffer)
     :command command
     :connection-type 'pipe
     :noquery t
     :sentinel
     (lambda (p _event)
       (when (memq (process-status p) '(exit signal))
         (let ((code (process-exit-status p)))
           (aj/rmpp--log "--- %s exit: %d ---\n" label code)
           (if (zerop code)
               (funcall on-success)
             (aj/rmpp--notify-failure label))))))))

(defun aj/rmpp-push-daily ()
  "Pull KOReader highlights from rMPP, then export + push today's daily.

Step 1 runs `make ferrari-pull' so any unpulled highlights on the
device are merged back into sioyek before we touch it further. Step 2
shells out to `scripts/sync-daily.sh' for the headless org→PDF export,
UUID lookup, scp, and xochitl registration. If step 1 fails, step 2 is
skipped and you hear about the pull failure specifically.

Log output is appended to the hidden buffer ` *rmpp-push-daily*' — view
with `C-x b SPC *rmpp-push-daily* RET' when debugging.

On success: plays Glass.aiff and flashes a success message.
On failure: plays Basso.aiff, speaks the failing step and a short reason
via `edge-tts' so you can react without switching windows."
  (interactive)
  (let ((project-dir (expand-file-name "~/Documents/remarkable/ferrari")))
    (with-current-buffer (aj/rmpp--log-buffer)
      (goto-char (point-max))
      (insert (format-time-string "\n=== [%F %T] rMPP push starting ===\n")))
    (message "rMPP: pulling highlights, then pushing today's daily…")
    (aj/rmpp--run-step
     "pull"
     (list "make" "-C" project-dir "ferrari-pull")
     (lambda ()
       (aj/rmpp--run-step
        "push"
        (list "bash"
              (expand-file-name "scripts/sync-daily.sh" project-dir))
        #'aj/rmpp--notify-success)))))

(define-key org-roam-dailies-map (kbd "p") #'aj/rmpp-push-daily)

(defun aj/ferrari-make ()
  "Run `make ferrari' in ~/Documents/remarkable/ferrari asynchronously.
Output goes to the same hidden log buffer as `aj/rmpp-push-daily'.
Plays Glass.aiff on success, Basso.aiff + edge-tts on failure."
  (interactive)
  (let ((project-dir (expand-file-name "~/Documents/remarkable/ferrari")))
    (with-current-buffer (aj/rmpp--log-buffer)
      (goto-char (point-max))
      (insert (format-time-string "\n=== [%F %T] make ferrari starting ===\n")))
    (message "ferrari: running make ferrari…")
    (aj/rmpp--run-step
     "ferrari"
     (list "make" "-C" project-dir "ferrari")
     (lambda ()
       (aj/rmpp--log "=== SUCCESS ===\n")
       (aj/rmpp--play-sound aj/rmpp--success-sound)
       (message "ferrari: make ferrari ✓")))))

;; Create refresh keymap: C-c d r <key>
(defvar aj/daily-refresh-map (make-sparse-keymap)
  "Keymap for daily refresh operations under C-c d r.")
(define-key aj/daily-refresh-map (kbd "c")
  (lambda () (interactive)
    (aj/refresh-daily-calendar)
    (unless (aj/under-heading-p "^\\* Calendar\\b")
      (when (y-or-n-p "Jump to Calendar heading?")
        (goto-char (point-min))
        (re-search-forward "^\\* Calendar\\b" nil t)
        (org-beginning-of-line)))))
(define-key aj/daily-refresh-map (kbd "r") #'aj/refresh-daily-recurring)
(define-key aj/daily-refresh-map (kbd "w") #'aj/refresh-daily-week)
(define-key aj/daily-refresh-map (kbd "o")
  (lambda () (interactive)
    (aj/bring-forward-overdue-captures)
    (aj/bring-forward-overdue-recurring)
    (aj/ensure-heading-separators)
    (aj/ensure-recurring-separators)
    (when (buffer-modified-p)
      (save-buffer))
    (message "Overdue items refreshed")))
(define-key aj/daily-refresh-map (kbd "a")
  (lambda () (interactive)
    (aj/insert-anki-review-chart)
    (unless (aj/under-heading-p "^\\*+ TODO Anki\\b")
      (when (y-or-n-p "Jump to Anki heading?")
        (goto-char (point-min))
        (re-search-forward "^\\*+ TODO Anki\\b" nil t)
        (org-beginning-of-line)))))
;; Bind refresh map to r in dailies map
(define-key org-roam-dailies-map (kbd "r") aj/daily-refresh-map)


;; ---------------------------------------------------------------------------
;; Hooks & Advice
;; ---------------------------------------------------------------------------


;; Suppress daily-file-open-hook during org-capture to prevent side-effects
;; (e.g. bring-forward-overdue cancelling source items while capturing).
;; Only suppressed for actual captures, not goto (C-c d d) operations.




;; ---------------------------------------------------------------------------
;; Anki Review Chart
;; ---------------------------------------------------------------------------

(defun aj/anki-review-chart-data ()
  "Fetch last 14 days of Anki review counts from AnkiConnect.
Returns alist of ((date-string . count) ...) sorted by date,
with zero-count days filled in for missing dates."
  (let* ((raw (let* ((url-request-method "POST")
                     (url-request-extra-headers '(("Content-Type" . "application/json")))
                     (url-request-data
                      (json-encode `((action . "getNumCardsReviewedByDay") (version . 6))))
                     (buffer (url-retrieve-synchronously "http://127.0.0.1:8765" t t 5)))
                (unless buffer
                  (error "Cannot connect to AnkiConnect. Is Anki running?"))
                (unwind-protect
                    (with-current-buffer buffer
                      (goto-char url-http-end-of-headers)
                      (let ((json-object-type 'alist))
                        (cdr (assoc 'result (json-read)))))
                  (kill-buffer buffer))))
         (today (current-time))
         (start (time-subtract today (days-to-time 13)))
         (result '()))
    ;; Build alist from raw data, filtering to last 14 days
    (let ((data-alist '()))
      (seq-doseq (entry raw)
        (let ((date-str (aref entry 0))
              (count (aref entry 1)))
          (push (cons date-str count) data-alist)))
      ;; Fill in all 14 days
      (dotimes (i 14)
        (let* ((day-time (time-add start (days-to-time i)))
               (day-str (format-time-string "%Y-%m-%d" day-time))
               (existing (assoc day-str data-alist)))
          (push (cons day-str (if existing (cdr existing) 0)) result))))
    (nreverse result)))

(defun aj/insert-anki-review-chart ()
  "Insert an Anki review chart under the Anki heading in the current daily note."
  (interactive)
  (unless (aj/daily-date-file-p)
    (user-error "Not in a daily note"))
  (let ((data (condition-case err
                  (aj/anki-review-chart-data)
                (error (user-error "Could not fetch Anki data: %s" (error-message-string err))))))
    (let* ((cache-dir (expand-file-name "~/.cache/emacs/"))
           (png-file (expand-file-name "anki-reviews.png" cache-dir))
           (dat-file (make-temp-file "anki-reviews-" nil ".dat"))
           (gp-file (make-temp-file "anki-reviews-" nil ".gp")))
      ;; Ensure cache dir exists
      (make-directory cache-dir t)
      ;; Write data file
      (with-temp-file dat-file
        (dolist (entry data)
          (insert (format "%s %d\n" (car entry) (cdr entry)))))
      ;; Write gnuplot script (colors adapt to current theme)
      (let* ((dark-p (eq (gruber-themes--get-current-variant) 'dark))
             (bg     (if dark-p "#181818" "#ffffff"))
             (fg     (if dark-p "#e4e4ef" "#333333"))
             (grid   (if dark-p "#333333" "#cccccc"))
             (border (if dark-p "#666666" "#999999"))
             (accent (if dark-p "#73c936" "#2266aa")))
        (with-temp-file gp-file
          (insert (format "set terminal pngcairo size 1600,600 font \"Helvetica,22\" background \"%s\"\n\
set output \"%s\"\n\
set xdata time\n\
set timefmt \"%%Y-%%m-%%d\"\n\
set format x \"%%d/%%m\"\n\
set xtics rotate by -45\n\
set yrange [0:*]\n\
set grid ytics lt 0 lw 0.5 lc rgb \"%s\"\n\
set border lc rgb \"%s\"\n\
set title \"Daily Anki Reviews\" tc rgb \"%s\"\n\
set xlabel \"Date\" tc rgb \"%s\"\n\
set ylabel \"Cards\" tc rgb \"%s\"\n\
set key off\n\
set style line 1 lc rgb \"%s\" lt 1 lw 4 pt 7 ps 1.2\n\
set tics textcolor rgb \"%s\"\n\
plot \"%s\" using 1:2 with linespoints ls 1\n"
                          bg png-file grid border fg fg fg accent fg dat-file))))
      ;; Run gnuplot
      (let ((exit-code (call-process "gnuplot" nil nil nil gp-file)))
        (unless (= exit-code 0)
          (user-error "gnuplot failed with exit code %d" exit-code)))
      ;; Clean up temp files
      (delete-file dat-file)
      (delete-file gp-file)
      ;; Insert into buffer under Anki heading
      (save-excursion
        (goto-char (point-min))
        (if (re-search-forward "^\\*+ TODO Anki\\b" nil t)
            (let ((heading-end (line-end-position))
                  (section-end (save-excursion
                                 (forward-line 1)
                                 (if (re-search-forward "^\\*+ " nil t)
                                     (line-beginning-position)
                                   (point-max)))))
              (delete-region (1+ heading-end) section-end)
              (goto-char (line-end-position))
              (insert "\n\n")
              (insert "#+ATTR_ORG: :width 600\n")
              (insert "#+ATTR_LATEX: :width 0.8\\linewidth\n")
              (insert (format "[[file:%s]]\n" png-file)))
          (user-error "No Anki heading found in this daily note")))
      ;; Render inline image
      (org-display-inline-images)
      (message "Anki review chart updated"))))

;; Refresh chart before org export
(defun aj/refresh-anki-chart-before-export (&rest _)
  "Refresh Anki review chart before export if in a daily note."
  (when (and (aj/daily-date-file-p)
             (save-excursion
               (goto-char (point-min))
               (re-search-forward "^\\*+ TODO Anki\\b" nil t)))
    (ignore-errors (aj/insert-anki-review-chart))))
(advice-add 'org-export-dispatch :before #'aj/refresh-anki-chart-before-export)

;; Refresh chart before magit
(with-eval-after-load 'magit
  (defun aj/refresh-anki-chart-before-magit (&rest _)
    "Refresh Anki chart before opening magit if in a daily note."
    (when (and (derived-mode-p 'org-mode)
               (aj/daily-date-file-p)
               (save-excursion
                 (goto-char (point-min))
                 (re-search-forward "^\\*+ TODO Anki\\b" nil t)))
      (ignore-errors (aj/insert-anki-review-chart))))
  (advice-add 'magit-status :before #'aj/refresh-anki-chart-before-magit))

;; ---------------------------------------------------------------------------
;; Garmin Self Chart
;; ---------------------------------------------------------------------------

(defvar aj/garmin-cli-path
  (expand-file-name "~/miniconda3/bin/garmindb_cli.py")
  "Path to garmindb_cli.py executable.")

(defvar aj/garmin-sync-process nil
  "Currently running garmindb sync process, or nil.")

(defvar aj/garmin-sync-buffer-name "*garmin-sync*"
  "Buffer name for garmindb async sync output.")

(defvar aj/garmin-route-map-script
  (expand-file-name "~/.emacs.d/scripts/garmin-route-map.py")
  "Path to garmin-route-map.py script.")

(defvar aj/garmin-dashboard-script
  (expand-file-name "~/.emacs.d/scripts/garmin-activity-dashboard.py")
  "Path to garmin-activity-dashboard.py script.")

(defvar aj/garmin-active-gear
  '((:name "Brooks Adrenaline GTS25" :sport "running" :start-date "2026-03-27"))
  "List of active gear plists. Each has :name, :sport, and :start-date (YYYY-MM-DD).
Mileage is computed by summing activity distance from :start-date onwards.")

(defun aj/garmin-gear-mileage (sport start-date date-str)
  "Return total distance (km) for SPORT from START-DATE up to DATE-STR (inclusive)."
  (let* ((db (expand-file-name "~/HealthData/DBs/garmin_activities.db"))
         (result (string-trim
                  (shell-command-to-string
                   (format "sqlite3 '%s' \"SELECT COALESCE(SUM(distance), 0) FROM activities WHERE sport = '%s' AND date(start_time) >= '%s' AND date(start_time) <= '%s';\""
                           db sport start-date date-str)))))
    (if (and result (not (string-empty-p result)))
        (string-to-number result)
      0.0)))

(defvar aj/garmin-sync-stderr-name "*garmin-sync-errors*"
  "Buffer name for garmindb async sync stderr.")

(defun aj/parse-garmin-time-to-minutes (time-str)
  "Parse a Garmin time string HH:MM:SS.000000 to total minutes."
  (if (and time-str (not (string-empty-p time-str)))
      (let* ((parts (split-string (car (split-string time-str "\\.")) ":"))
             (hours (string-to-number (nth 0 parts)))
             (mins (string-to-number (nth 1 parts))))
        (+ (* hours 60) mins))
    0))

(defun aj/format-minutes-as-hm (minutes)
  "Format MINUTES as Xh Ym string."
  (if (and minutes (> minutes 0))
      (format "%dh %02dm" (/ minutes 60) (mod minutes 60))
    "N/A"))

(defun aj/garmin-self-data (date-str)
  "Query Garmin SQLite DB for health data on DATE-STR (YYYY-MM-DD).
Returns a plist with sleep, vitals, and HRV data."
  (let* ((db (expand-file-name "~/HealthData/DBs/garmin.db"))
         (day-key (concat date-str " 00:00:00.000000"))
         (run-query (lambda (sql)
                      (string-trim
                       (shell-command-to-string
                        (format "sqlite3 '%s' \"%s\"" db sql)))))
         ;; Sleep data
         (sleep-raw (funcall run-query
                             (format "SELECT total_sleep, deep_sleep, light_sleep, rem_sleep, awake, score, qualifier, avg_spo2 FROM sleep WHERE day = '%s';" day-key)))
         ;; Daily summary
         (daily-raw (funcall run-query
                             (format "SELECT steps, rhr, hr_min, hr_max, stress_avg, floors_up, distance, bb_max, bb_min, spo2_avg FROM daily_summary WHERE day = '%s';" day-key)))
         ;; HRV
         (hrv-raw (funcall run-query
                           (format "SELECT weekly_avg, last_night_avg, status FROM hrv WHERE day = '%s';" day-key)))
         ;; Resting HR
         (rhr-raw (funcall run-query
                           (format "SELECT resting_heart_rate FROM resting_hr WHERE day = '%s';" day-key)))
         ;; Parse results
         (result (list :date date-str)))
    ;; Parse sleep
    (when (and sleep-raw (not (string-empty-p sleep-raw)))
      (let ((fields (split-string sleep-raw "|")))
        (setq result (plist-put result :total-sleep (nth 0 fields)))
        (setq result (plist-put result :deep-sleep (nth 1 fields)))
        (setq result (plist-put result :light-sleep (nth 2 fields)))
        (setq result (plist-put result :rem-sleep (nth 3 fields)))
        (setq result (plist-put result :awake (nth 4 fields)))
        (setq result (plist-put result :sleep-score (nth 5 fields)))
        (setq result (plist-put result :sleep-qualifier (nth 6 fields)))
        (setq result (plist-put result :sleep-spo2 (nth 7 fields)))))
    ;; Parse daily summary
    (when (and daily-raw (not (string-empty-p daily-raw)))
      (let ((fields (split-string daily-raw "|")))
        (setq result (plist-put result :steps (nth 0 fields)))
        (setq result (plist-put result :rhr (nth 1 fields)))
        (setq result (plist-put result :hr-min (nth 2 fields)))
        (setq result (plist-put result :hr-max (nth 3 fields)))
        (setq result (plist-put result :stress-avg (nth 4 fields)))
        (setq result (plist-put result :floors-up (nth 5 fields)))
        (setq result (plist-put result :distance (nth 6 fields)))
        (setq result (plist-put result :bb-max (nth 7 fields)))
        (setq result (plist-put result :bb-min (nth 8 fields)))
        (setq result (plist-put result :spo2-avg (nth 9 fields)))))
    ;; Parse HRV
    (when (and hrv-raw (not (string-empty-p hrv-raw)))
      (let ((fields (split-string hrv-raw "|")))
        (setq result (plist-put result :hrv-weekly (nth 0 fields)))
        (setq result (plist-put result :hrv-last-night (nth 1 fields)))
        (setq result (plist-put result :hrv-status (nth 2 fields)))))
    ;; Parse resting HR
    (when (and rhr-raw (not (string-empty-p rhr-raw)))
      (setq result (plist-put result :resting-hr rhr-raw)))
    result))

(defun aj/garmin-daily-img-dir (date-str)
  "Return the image directory for DATE-STR's daily note: daily/img/DATE-STR/.
Uses the buffer's file path to find the daily directory."
  (let* ((daily-dir (file-name-directory (buffer-file-name)))
         (img-dir (expand-file-name (concat "img/" date-str "/") daily-dir)))
    (make-directory img-dir t)
    img-dir))

(defun aj/garmin-self-generate-chart (date-str)
  "Generate a 7-day stacked sleep bar chart ending on DATE-STR.
Output to daily/img/DATE-STR/garmin-self.png."
  (let* ((db (expand-file-name "~/HealthData/DBs/garmin.db"))
         (cache-dir (aj/garmin-daily-img-dir date-str))
         (png-file (expand-file-name "garmin-self.png" cache-dir))
         (dat-file (make-temp-file "garmin-self-" nil ".dat"))
         (gp-file (make-temp-file "garmin-self-" nil ".gp"))
         ;; Query 7 days of sleep data
         (sleep-query (format "SELECT day, deep_sleep, light_sleep, rem_sleep, awake FROM sleep WHERE day <= '%s 00:00:00.000000' ORDER BY day DESC LIMIT 7;" date-str))
         (raw (string-trim
               (shell-command-to-string
                (format "sqlite3 '%s' \"%s\"" db sleep-query)))))
    (make-directory cache-dir t)
    (if (or (not raw) (string-empty-p raw))
        (progn
          (message "No sleep data found for chart")
          nil)
      ;; Write data file (reversed so oldest first)
      (with-temp-file dat-file
        (dolist (line (nreverse (split-string raw "\n" t)))
          (let* ((fields (split-string line "|"))
                 (day (substring (nth 0 fields) 5 10)) ; MM-DD
                 (deep (aj/parse-garmin-time-to-minutes (nth 1 fields)))
                 (light (aj/parse-garmin-time-to-minutes (nth 2 fields)))
                 (rem (aj/parse-garmin-time-to-minutes (nth 3 fields)))
                 (awake (aj/parse-garmin-time-to-minutes (nth 4 fields))))
            (insert (format "%s %d %d %d %d\n" day deep light rem awake)))))
      ;; Write gnuplot script
      (let* ((dark-p (eq (gruber-themes--get-current-variant) 'dark))
             (bg     (if dark-p "#181818" "#ffffff"))
             (fg     (if dark-p "#e4e4ef" "#333333"))
             (grid   (if dark-p "#333333" "#cccccc"))
             (border (if dark-p "#666666" "#999999"))
             (deep-c  (if dark-p "#1a5276" "#1a5276"))
             (light-c (if dark-p "#5dade2" "#5dade2"))
             (rem-c   (if dark-p "#8e44ad" "#8e44ad"))
             (awake-c (if dark-p "#e74c3c" "#e74c3c")))
        (with-temp-file gp-file
          (insert (format "set terminal pngcairo size 1600,600 font \"Helvetica,22\" background \"%s\"\n\
set output \"%s\"\n\
set style data histogram\n\
set style histogram rowstacked\n\
set style fill solid 0.9 border -1\n\
set boxwidth 0.7\n\
set yrange [0:*]\n\
set grid ytics lt 0 lw 0.5 lc rgb \"%s\"\n\
set border lc rgb \"%s\"\n\
set title \"Sleep Breakdown (7 days)\" tc rgb \"%s\"\n\
set ylabel \"Minutes\" tc rgb \"%s\"\n\
set tics textcolor rgb \"%s\"\n\
set xtics rotate by -30\n\
set key outside right top tc rgb \"%s\"\n\
plot \"%s\" using 2:xtic(1) title \"Deep\" lc rgb \"%s\", \
     '' using 3 title \"Light\" lc rgb \"%s\", \
     '' using 4 title \"REM\" lc rgb \"%s\", \
     '' using 5 title \"Awake\" lc rgb \"%s\"\n"
                          bg png-file grid border fg fg fg fg
                          dat-file deep-c light-c rem-c awake-c))))
      ;; Run gnuplot
      (let ((exit-code (call-process "gnuplot" nil nil nil gp-file)))
        (delete-file dat-file)
        (delete-file gp-file)
        (if (= exit-code 0)
            png-file
          (message "gnuplot failed with exit code %d" exit-code)
          nil)))))

(defun aj/garmin-self-generate-route-map (date-str)
  "Generate route map PNG(s) for GPS activities on DATE-STR.
Returns a list of plists ((:file PNG :sport SPORT :name NAME :activity-id ID) ...)
or nil if no activities."
  (let* ((dark-p (eq (gruber-themes--get-current-variant) 'dark))
         (route-file (expand-file-name "garmin-route.png"
                                       (aj/garmin-daily-img-dir date-str)))
         (output (string-trim
                  (shell-command-to-string
                   (format "%s %s %s --output %s %s 2>/dev/null"
                           (shell-quote-argument (expand-file-name "~/miniconda3/bin/python3"))
                           (shell-quote-argument aj/garmin-route-map-script)
                           (shell-quote-argument date-str)
                           (shell-quote-argument route-file)
                           (if dark-p "--dark" ""))))))
    (when (and output
               (not (string-empty-p output))
               (not (string= output "NO_ACTIVITY")))
      (let ((lines (split-string output "\n" t))
            (result nil))
        (dolist (line lines)
          (let ((parts (split-string line "|")))
            (push (list :file route-file
                        :sport (nth 1 parts)
                        :name (nth 2 parts)
                        :activity-id (nth 0 parts))
                  result)))
        (nreverse result)))))

(defun aj/garmin-self--insert-content (date-str)
  "Insert or replace ** Self content under * Journal for DATE-STR.
This is the synchronous core that queries the DB and writes into the buffer."
  (let* ((data (aj/garmin-self-data date-str))
         ;; Fall back to yesterday if no data for this date
         (using-yesterday (and (not (plist-get data :total-sleep))
                               (not (plist-get data :steps))))
         (data (if using-yesterday
                   (let ((yesterday (format-time-string
                                     "%Y-%m-%d"
                                     (time-subtract (date-to-time (concat date-str " 00:00:00"))
                                                    (days-to-time 1)))))
                     (aj/garmin-self-data yesterday))
                 data))
         (png-file (aj/garmin-self-generate-chart date-str))
         (png-rel (when png-file
                    (format "img/%s/garmin-self.png" date-str)))
         (routes (ignore-errors (aj/garmin-self-generate-route-map date-str)))
         (route-rel (when routes
                      (format "img/%s/garmin-route.png" date-str)))
         ;; Format values
         (or-na (lambda (val &optional suffix)
                  (if (and val (not (string-empty-p val)))
                      (if suffix (concat val suffix) val)
                    "N/A")))
         (sleep-score (let ((score (plist-get data :sleep-score))
                            (qual (plist-get data :sleep-qualifier)))
                        (if (and score (not (string-empty-p score)))
                            (format "%s (%s)" score (or qual ""))
                          "N/A")))
         (total-sleep (let ((m (aj/parse-garmin-time-to-minutes (plist-get data :total-sleep))))
                        (aj/format-minutes-as-hm m)))
         (deep (let ((m (aj/parse-garmin-time-to-minutes (plist-get data :deep-sleep))))
                 (aj/format-minutes-as-hm m)))
         (rem (let ((m (aj/parse-garmin-time-to-minutes (plist-get data :rem-sleep))))
                (aj/format-minutes-as-hm m)))
         (rhr (funcall or-na (plist-get data :rhr) " bpm"))
         (hrv-val (let ((weekly (plist-get data :hrv-weekly))
                        (status (plist-get data :hrv-status)))
                    (if (and weekly (not (string-empty-p weekly)))
                        (format "%s ms (%s)" weekly
                                (or (and status (substring status 0 3)) ""))
                      "N/A")))
         (steps (let ((s (plist-get data :steps)))
                  (if (and s (not (string-empty-p s)))
                      (replace-regexp-in-string
                       "\\([0-9]\\)\\([0-9]\\{3\\}\\)\\'" "\\1,\\2" s)
                    "N/A")))
         (stress (funcall or-na (plist-get data :stress-avg)))
         (bb (let ((mx (plist-get data :bb-max))
                   (mn (plist-get data :bb-min)))
               (if (and mx mn (not (string-empty-p mx)) (not (string-empty-p mn)))
                   (format "%s - %s" mn mx)
                 "N/A")))
         (spo2 (funcall or-na (plist-get data :spo2-avg) "%")))
    ;; Insert under * Journal as ** Self
    (save-excursion
      (goto-char (point-min))
      (if (re-search-forward "^\\* Journal\\b" nil t)
          (let* ((journal-end (line-end-position))
                 ;; Check for existing ** Self
                 (next-h1 (save-excursion
                            (forward-line 1)
                            (if (re-search-forward "^\\* " nil t)
                                (line-beginning-position)
                              (point-max))))
                 (existing-self (save-excursion
                                  (forward-line 1)
                                  (re-search-forward "^\\*\\* Self\\b" next-h1 t))))
            ;; If ** Self exists, clear its content. Also consume any blank
            ;; lines above the heading so the leading `\n' in the insert
            ;; below doesn't accumulate one extra blank under * Journal on
            ;; every refresh.
            (when existing-self
              (goto-char (match-beginning 0))
              (let* ((delete-start
                      (save-excursion
                        (let ((p (line-beginning-position)))
                          (forward-line -1)
                          (while (and (> (point) journal-end)
                                      (looking-at-p "^[ \t]*$"))
                            (setq p (line-beginning-position))
                            (forward-line -1))
                          p)))
                     (self-end (save-excursion
                                 (forward-line 1)
                                 (if (re-search-forward "^\\*\\*? " nil t)
                                     (line-beginning-position)
                                   (point-max)))))
                (delete-region delete-start self-end)))
            ;; Position: right after * Journal heading
            (unless existing-self
              (goto-char journal-end)
              (insert "\n"))
            ;; Insert ** Self content
            (insert "\n** Self\n\n")
            (when png-rel
              (insert "#+ATTR_ORG: :width 600\n")
              (insert "#+ATTR_LATEX: :width 0.8\\linewidth\n")
              (insert (format "[[file:%s]]\n\n" png-rel)))
            (when using-yesterday
              (insert "#+CAPTION: Yesterday's Data\n"))
            (let ((table-start (point)))
              (insert "| Metric       | Value |\n")
              (insert "|--------------+-------|\n")
              (insert (format "| Sleep Score  | %s |\n" sleep-score))
              (insert (format "| Total Sleep  | %s |\n" total-sleep))
              (insert (format "| Deep         | %s |\n" deep))
              (insert (format "| REM          | %s |\n" rem))
              (insert (format "| RHR          | %s |\n" rhr))
              (insert (format "| HRV          | %s |\n" hrv-val))
              (insert (format "| Steps        | %s |\n" steps))
              (insert (format "| Stress       | %s |\n" stress))
              (insert (format "| Body Battery | %s |\n" bb))
              (insert (format "| SpO2         | %s |\n" spo2))
              ;; Align the table
              (save-excursion
                (goto-char table-start)
                (org-table-align)))
            ;; Route maps if activities exist.
            ;;
            ;; Each image is a plain `[[file:...]]' link (no hyperlink
            ;; wrapper) so the LaTeX exporter produces a proper
            ;; `\begin{figure}\centering\includegraphics\caption{}\end{figure}'
            ;; — centered and captioned. Gear info for the sport becomes
            ;; `#+CAPTION:' attached to the image. Affiliated keywords
            ;; (ATTR_* and CAPTION) MUST precede the link element in org
            ;; for the exporter to pick them up, so emit them first even
            ;; though the visual reading order puts the caption below.
            (when routes
              (let ((gear-captions
                     (lambda (sport)
                       (let (caps)
                         (dolist (gear aj/garmin-active-gear)
                           (when (string= (plist-get gear :sport) sport)
                             (let ((km (aj/garmin-gear-mileage
                                        sport
                                        (plist-get gear :start-date)
                                        date-str)))
                               (push (format "#+CAPTION: *Gear: %s* --- %.1f km\n"
                                             (plist-get gear :name) km)
                                     caps))))
                         (nreverse caps)))))
                (if (= (length routes) 1)
                    ;; Single activity
                    (let* ((r (car routes))
                           (sport (plist-get r :sport)))
                      (insert (format "\n*** %s\n\n"
                                      (or (plist-get r :name)
                                          (capitalize (or sport "Activity")))))
                      (insert "#+ATTR_ORG: :width 600\n")
                      (insert "#+ATTR_LATEX: :width 0.7\\linewidth :placement [ht]\n")
                      (dolist (c (funcall gear-captions sport)) (insert c))
                      (insert (format "[[file:%s]]\n\n" route-rel))
                      (insert (format "[[elisp:(aj/garmin-open-activity-dashboard \"%s\")][View activity dashboard]]\n"
                                      (plist-get r :activity-id))))
                  ;; Multiple activities: composite grid image + per-activity links
                  (let ((sports (delete-dups
                                 (mapcar (lambda (r) (plist-get r :sport)) routes))))
                    (insert "\n*** Activities\n\n")
                    (insert "#+ATTR_ORG: :width 800\n")
                    (insert "#+ATTR_LATEX: :width 1.0\\linewidth :placement [ht]\n")
                    (dolist (sp sports)
                      (dolist (c (funcall gear-captions sp)) (insert c)))
                    (insert (format "[[file:%s]]\n\n" route-rel))
                    (dolist (r routes)
                      (insert (format "- [[elisp:(aj/garmin-open-activity-dashboard \"%s\")][%s]] (%s)\n"
                                      (plist-get r :activity-id)
                                      (or (plist-get r :name)
                                          (capitalize (or (plist-get r :sport) "Activity")))
                                      (plist-get r :sport))))))))
            ;; Separator before next heading
            (insert "\n-----\n"))
        (user-error "No Journal heading found in this daily note")))
    ;; Re-establish buffer-wide invariants. The deletion above (from `**
    ;; Self' through the next `* '/`** ' heading) eats any `-----'
    ;; separators and `#+LATEX: \newpage' directives that lived between
    ;; the old Self content and the following level-1 heading, so run
    ;; the self-healers before we're done.
    (aj/ensure-heading-separators)
    (aj/ensure-heading-newpages)
    ;; Render inline images
    (org-display-inline-images)))

(defun aj/garmin-open-activity-dashboard (activity-id)
  "Generate and open an HTML dashboard for ACTIVITY-ID in the browser."
  (interactive "sActivity ID: ")
  (let* ((dark-p (eq (gruber-themes--get-current-variant) 'dark))
         (output (string-trim
                  (shell-command-to-string
                   (format "%s %s --activity-id %s %s"
                           (shell-quote-argument (expand-file-name "~/miniconda3/bin/python3"))
                           (shell-quote-argument aj/garmin-dashboard-script)
                           (shell-quote-argument activity-id)
                           (if dark-p "--dark" ""))))))
    (if (and output (file-exists-p output))
        (browse-url (concat "file://" output))
      (user-error "Failed to generate dashboard for activity %s" activity-id))))

;; Register garmin-activity: org link type so C-c C-o on route map opens dashboard
;;
;; On export, we handle two description shapes:
;;   1. Plain text — renders as a hyperlink with that text.
;;   2. `file:path/to/image.png' — renders as an image that is itself a
;;      hyperlink to the Garmin activity page. This is how route-map
;;      inserts generate their links (see `aj/refresh-daily-recurring').
;;
;; `#+ATTR_LATEX' above the link is ignored by org for custom link types,
;; so the LaTeX width is hardcoded here. Change `aj/garmin-latex-img-width'
;; if the default 0.8\linewidth is wrong.
(defvar aj/garmin-latex-img-width "0.8\\linewidth"
  "LaTeX width used when exporting garmin-activity: links whose description
is a file: image reference.")

(defun aj/garmin--desc-image-path (desc)
  "If DESC is `file:PATH' to an image, return PATH. Otherwise nil."
  (when (and desc
             (string-match
              "\\`file:\\(.+\\.\\(?:png\\|jpe?g\\|gif\\|svg\\|pdf\\)\\)\\'"
              desc))
    (match-string 1 desc)))

(org-link-set-parameters
 "garmin-activity"
 :follow (lambda (activity-id _)
           (aj/garmin-open-activity-dashboard activity-id))
 :export (lambda (activity-id desc backend _info)
           (let* ((url (format "https://connect.garmin.com/modern/activity/%s"
                               activity-id))
                  (img (aj/garmin--desc-image-path desc)))
             (pcase backend
               ('html
                (if img
                    (format "<a href=\"%s\"><img src=\"%s\" alt=\"activity %s\"/></a>"
                            url img activity-id)
                  (format "<a href=\"%s\">%s</a>" url (or desc activity-id))))
               ('latex
                (if img
                    (format "\\href{%s}{\\includegraphics[width=%s]{%s}}"
                            url aj/garmin-latex-img-width img)
                  (format "\\href{%s}{%s}" url (or desc activity-id))))
               (_ (or desc url))))))

(defun aj/garmin-sync-running-p ()
  "Return non-nil if a garmindb sync process is currently running."
  (and aj/garmin-sync-process (process-live-p aj/garmin-sync-process)))

(defun aj/garmin-db-has-data-p (date-str)
  "Return non-nil if garmin.db already has sleep data for DATE-STR."
  (let* ((db (expand-file-name "~/HealthData/DBs/garmin.db"))
         (day-key (concat date-str " 00:00:00.000000"))
         (result (string-trim
                  (shell-command-to-string
                   (format "sqlite3 '%s' \"SELECT COUNT(*) FROM sleep WHERE day = '%s';\"" db day-key)))))
    (and result (not (string= result "0")))))

(defun aj/garmin-sync-and-refresh (&optional target-buffer force)
  "Run garmindb_cli.py async to download+import+analyze latest data.
When finished, re-insert the Self section in TARGET-BUFFER (or current buffer).
Skips if today's data already exists in the DB, unless FORCE is non-nil."
  (let* ((buf (or target-buffer (current-buffer)))
         (date-str (format-time-string "%Y-%m-%d")))
    (cond
     ((aj/garmin-sync-running-p)
      (message "Garmin sync already running, skipping"))
     ((and (not force) (aj/garmin-db-has-data-p date-str))
      (message "Garmin data for %s already in DB, skipping sync" date-str))
     (t
      (message "Garmin sync started (background)...")
      (let ((proc-buf (get-buffer-create aj/garmin-sync-buffer-name))
            (err-buf (get-buffer-create aj/garmin-sync-stderr-name)))
        (with-current-buffer proc-buf (erase-buffer))
        (with-current-buffer err-buf
          (erase-buffer)
          (setq-local buffer-read-only nil))
        (setq aj/garmin-sync-process
              (make-process
               :name "garmin-sync"
               :buffer proc-buf
               :stderr err-buf
               :command (list aj/garmin-cli-path
                              "--all" "--download" "--import" "--analyze" "--latest")
               :sentinel
               (lambda (proc event)
                 (setq aj/garmin-sync-process nil)
                 (cond
                  ((string-match-p "finished" event)
                   (start-process "garmin-done-sound" nil
                                  "afplay" "/System/Library/Sounds/Purr.aiff")
                   (message "Garmin sync finished, updating Self section...")
                   (when (buffer-live-p buf)
                     (with-current-buffer buf
                       (when (aj/daily-date-file-p)
                         (let ((date-str (file-name-sans-extension
                                          (file-name-nondirectory (buffer-file-name)))))
                           (ignore-errors
                             (aj/garmin-self--insert-content date-str)
                             (save-buffer)
                             (message "Garmin Self section updated with fresh data")))))))
                  (t
                   (start-process "garmin-error-sound" nil
                                  "afplay" "/System/Library/Sounds/Funk.aiff")
                   (message "Garmin sync failed: %s (see %s)"
                            (string-trim event) aj/garmin-sync-stderr-name)))))))))))

(defun aj/insert-garmin-self-chart ()
  "Insert Garmin Self section under * Journal in the current daily note.
Immediately inserts from existing DB data, then kicks off an async
garmindb sync to download latest data and refresh when done."
  (interactive)
  (unless (aj/daily-date-file-p)
    (user-error "Not in a daily note"))
  (let ((date-str (file-name-sans-extension
                   (file-name-nondirectory (buffer-file-name)))))
    ;; Immediately insert from current DB state
    (aj/garmin-self--insert-content date-str)
    (message "Garmin Self section inserted (syncing for updates...)")
    ;; Only auto-sync for today's note
    (when (string= date-str (format-time-string "%Y-%m-%d"))
      (aj/garmin-sync-and-refresh (current-buffer)))))

;; Keybinding: C-c d r j (prefix arg C-u C-c d r j forces sync)
(define-key aj/daily-refresh-map (kbd "j")
  (lambda (force) (interactive "P")
    (aj/insert-garmin-self-chart)
    ;; With prefix arg, force a sync regardless of cooldown
    (when (and force
               (aj/daily-date-file-p)
               (string= (file-name-sans-extension
                          (file-name-nondirectory (buffer-file-name)))
                         (format-time-string "%Y-%m-%d")))
      (aj/garmin-sync-and-refresh (current-buffer) t))
    (unless (aj/under-heading-p "^\\*+ Self\\b")
      (when (y-or-n-p "Jump to Self heading?")
        (goto-char (point-min))
        (re-search-forward "^\\*+ Self\\b" nil t)
        (org-beginning-of-line)))))

;; Refresh Garmin self chart before org export (sync, no async)
(defun aj/refresh-garmin-self-before-export (&rest _)
  "Refresh Garmin Self chart before export if in a daily note."
  (when (and (aj/daily-date-file-p)
             (save-excursion
               (goto-char (point-min))
               (re-search-forward "^\\*+ Self\\b" nil t)))
    (let ((date-str (file-name-sans-extension
                     (file-name-nondirectory (buffer-file-name)))))
      (ignore-errors (aj/garmin-self--insert-content date-str)))))
(advice-add 'org-export-dispatch :before #'aj/refresh-garmin-self-before-export)

;; Refresh Garmin self chart before magit
(with-eval-after-load 'magit
  (defun aj/refresh-garmin-self-before-magit (&rest _)
    "Refresh Garmin Self chart before opening magit if in a daily note."
    (when (and (derived-mode-p 'org-mode)
               (aj/daily-date-file-p)
               (save-excursion
                 (goto-char (point-min))
                 (re-search-forward "^\\*+ Self\\b" nil t)))
      (let ((date-str (file-name-sans-extension
                       (file-name-nondirectory (buffer-file-name)))))
        (ignore-errors (aj/garmin-self--insert-content date-str)))))
  (advice-add 'magit-status :before #'aj/refresh-garmin-self-before-magit))

(provide 'daily-config)

;;; daily-config.el ends here
