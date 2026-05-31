;;; daily-config.el --- Daily note configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; Daily-notes entry point. Pulls in the focused submodules
;; (daily-structure, daily-week, daily-recurring, daily-capture,
;; daily-calendar, daily-garmin, daily-anki, daily-rmpp) and provides
;; the file-open lifecycle hook, navigation, refile-on-DONE / propagate-
;; DONE-to-tasks glue, and the `C-c d' / `C-c d r' keymaps.

;;; Code:

(require 'org-roam)
(require 'org-roam-dailies)
(require 'cl-lib)
(require 'daily-structure)
(require 'daily-week)
(require 'daily-recurring)
(require 'daily-capture)
(require 'daily-calendar)
(require 'daily-garmin)
(require 'daily-anki)
(require 'daily-rmpp)

;; ---------------------------------------------------------------------------
;; Shared state
;; ---------------------------------------------------------------------------

(defvar aj/daily-hook-suppress nil
  "When non-nil, `aj/daily-file-open-hook' is suppressed.
Used to prevent side-effects (overdue bring-forward, calendar refresh,
etc.) when files are opened during org-capture, and consulted by
`aj/propagate-done-to-tasks' so machine-driven CANCEL stamps from the
bring-forward path don't cascade into tasks.org.")

;; ---------------------------------------------------------------------------
;; Daily Lifecycle
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
      ;; Push today's/future priority items to Google Calendar (deferred to an
      ;; idle timer; no-op for past dailies or when nothing is pending).
      (when (fboundp 'aj/gcal-maybe-sweep-on-open)
        (aj/daily-time-step aj--timings "gcal-maybe-sweep"
          (aj/gcal-maybe-sweep-on-open)))
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

;; ---------------------------------------------------------------------------
;; Navigation
;; ---------------------------------------------------------------------------

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

(defun aj/tasks-entry-has-org-repeater-p ()
  "Non-nil if the planning line of the entry at point carries a real org
repeater (+N, ++N or .+N) in its SCHEDULED/DEADLINE timestamp.

Returns nil for diary-sexp schedules (`<%%(...)>', e.g. `diary-cyclic') and for
plain dates — neither of which `org-todo'/`org-auto-repeat-maybe' can advance.
Reads the planning line text directly: `org-entry-get' \"SCHEDULED\" returns
nil for a diary-sexp schedule, so it cannot be used to tell these apart."
  (save-excursion
    (org-back-to-heading t)
    (forward-line 1)
    (let ((line-end (line-end-position)))
      (and (looking-at-p "^[ \t]*\\(?:CLOSED\\|DEADLINE\\|SCHEDULED\\):")
           (re-search-forward
            "<[^>\n]*\\(?:\\+\\+?\\|\\.\\+\\)[0-9]+[dwmy][^>\n]*>"
            line-end t)
           t))))

(defun aj/propagate-done-to-tasks ()
  "When a heading is marked DONE/CANCEL under * Recurring in a daily note,
find the corresponding heading in tasks.org and advance it.

For tasks with a real org repeater (+N/++N/.+N) this marks the tasks.org entry
DONE, letting `org-auto-repeat-maybe' roll SCHEDULED forward and reset it to
TODO. For diary-sexp (`<%%(...)>') or plain-date schedules — which have no
repeater to advance — it only bumps LAST_REPEAT and leaves the state TODO, so
the task keeps recurring instead of getting stranded as DONE.

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
                (if (aj/tasks-entry-has-org-repeater-p)
                    ;; Real org repeater (+N/++N/.+N): let org advance
                    ;; SCHEDULED/LAST_REPEAT and reset the state. Auto-confirm
                    ;; the "N repeater intervals" prompt org shows when
                    ;; SCHEDULED is far behind today.
                    (cl-letf (((symbol-function 'y-or-n-p)
                               (lambda (&rest _) t)))
                      (org-todo "DONE"))
                  ;; No advanceable repeater — a diary-sexp (<%%(...)>) or a
                  ;; plain date. Marking it DONE would strand the task (nothing
                  ;; reverts it to TODO so it never recurs again). Bump
                  ;; LAST_REPEAT in-place and leave the state TODO so the
                  ;; schedule keeps re-surfacing it on its own days.
                  (org-entry-put (point) "LAST_REPEAT"
                                 (format-time-string
                                  (org-time-stamp-format t t))))
                (save-buffer)
                (message "Propagated completion to tasks.org: %s" heading-text)))))))))

(add-hook 'org-after-todo-state-change-hook #'aj/propagate-done-to-tasks)

;; Run aj/daily-file-open-hook each time a daily is opened.
(add-hook 'org-roam-dailies-find-file-hook #'aj/daily-file-open-hook)

;; ---------------------------------------------------------------------------
;; Date-prompt defaults — anchor schedule/deadline to the daily's date
;; ---------------------------------------------------------------------------

(defun aj/daily--file-date-time ()
  "Return the daily's filename date as a time value, or nil if not in a daily."
  (when (aj/daily-date-file-p)
    (let ((base (file-name-base (buffer-file-name))))
      (when (string-match "\\`\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)\\'" base)
        (encode-time 0 0 0
                     (string-to-number (match-string 3 base))
                     (string-to-number (match-string 2 base))
                     (string-to-number (match-string 1 base)))))))

(defun aj/daily--anchor-org-read-date (orig-fn &rest args)
  "Around advice: anchor `org-read-date' default to the daily's date.
When invoked from a heading inside a daily file (e.g. via `org-schedule'
right after a `C-c d c' capture), `org-read-date' would otherwise
default to today. Bind `org-overriding-default-time' to the daily's
parsed date so the calendar pops up on the day you're capturing into."
  (let ((daily-time (aj/daily--file-date-time)))
    (if daily-time
        (let ((org-overriding-default-time daily-time))
          (apply orig-fn args))
      (apply orig-fn args))))

(advice-add 'org-schedule :around #'aj/daily--anchor-org-read-date)
(advice-add 'org-deadline :around #'aj/daily--anchor-org-read-date)

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
;; p = push today's daily to the rMPP
(define-key org-roam-dailies-map (kbd "p") #'aj/rmpp-push-daily)

;; Create refresh keymap: C-c d r <key>
(defvar aj/daily-refresh-map (make-sparse-keymap)
  "Keymap for daily refresh operations under C-c d r.")
(define-key aj/daily-refresh-map (kbd "c")
  (lambda () (interactive)
    ;; Explicit refresh always bypasses the weather cache.
    (aj/refresh-daily-calendar t)
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
;; C-c d r j — refresh Garmin Self chart (C-u also forces a sync)
(define-key aj/daily-refresh-map (kbd "j") #'aj/garmin-refresh-and-jump)
;; C-c d r G — push the priority chore at point to the J calendar (red all-day)
(define-key aj/daily-refresh-map (kbd "G") #'aj/gcal-push-chore-at-point)
;; C-c d r g — sweep ALL priority headings in this daily to the J calendar
(define-key aj/daily-refresh-map (kbd "g") #'aj/gcal-sweep-daily-chores)
;; Bind refresh map to r in dailies map
(define-key org-roam-dailies-map (kbd "r") aj/daily-refresh-map)



(provide 'daily-config)

;;; daily-config.el ends here
