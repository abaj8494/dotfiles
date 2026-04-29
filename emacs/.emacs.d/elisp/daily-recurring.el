;;; daily-recurring.el --- tasks.org-driven recurring tasks for dailies -*- lexical-binding: t; -*-

;;; Commentary:
;; Recurring task management for daily notes. Queries tasks.org via the
;; org-agenda machinery to determine which tasks are due on a given date,
;; extracts their subtrees, strips scheduling noise, and inserts them
;; under * Recurring in the daily file. Also handles bring-forward of
;; overdue priority items from previous days' Capture / Recurring
;; sections, and the ----- separators between Recurring sub-headings.

;;; Code:

(require 'cl-lib)
(require 'daily-structure)

(declare-function org-agenda-get-day-entries "org-agenda")
(declare-function org-time-string-to-time "org")
(declare-function org-end-of-subtree "org")
(declare-function org-back-to-heading "org")
(declare-function org-at-heading-p "org")
(declare-function org-current-level "org")
(declare-function org-todo "org")
(declare-function calendar-check-holidays "holidays")

(defvar aj/tasks-file
  (expand-file-name "daily/tasks.org" org-roam-directory)
  "Path to tasks.org file for recurring task scheduling.")

(defun aj/date-is-repeat-occurrence-p (scheduled-str target-time)
  "Return non-nil if TARGET-TIME is an occurrence of the repeater in SCHEDULED-STR.
SCHEDULED-STR is the content of a SCHEDULED timestamp (e.g. \"<2026-03-17 Tue +2w>\").
Handles +Nd, +Nw, +Nm, +Ny repeaters (and ++ / .+ variants)."
  (when (string-match "<\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)[^>]*\\(?:\\+\\+\\|\\.\\+\\|\\+\\)\\([0-9]+\\)\\([dwmy]\\)>" scheduled-str)
    (let* ((sched-date-str (match-string 1 scheduled-str))
           (n (string-to-number (match-string 2 scheduled-str)))
           (unit (match-string 3 scheduled-str))
           (sched-time (org-time-string-to-time sched-date-str))
           (sched-decoded (decode-time sched-time))
           (target-decoded (decode-time target-time))
           (sched-day (nth 3 sched-decoded))
           (sched-month (nth 4 sched-decoded))
           (sched-year (nth 5 sched-decoded))
           (target-day (nth 3 target-decoded))
           (target-month (nth 4 target-decoded))
           (target-year (nth 5 target-decoded)))
      (cond
       ;; Daily: (target - scheduled) in days must be divisible by N
       ((string= unit "d")
        (let ((diff (- (time-to-days target-time) (time-to-days sched-time))))
          (and (>= diff 0) (= 0 (mod diff n)))))
       ;; Weekly: (target - scheduled) in days must be divisible by N*7
       ((string= unit "w")
        (let ((diff (- (time-to-days target-time) (time-to-days sched-time))))
          (and (>= diff 0) (= 0 (mod diff (* n 7))))))
       ;; Monthly: same day-of-month, month difference divisible by N
       ((string= unit "m")
        (and (= target-day sched-day)
             (let ((month-diff (+ (* 12 (- target-year sched-year))
                                  (- target-month sched-month))))
               (and (>= month-diff 0) (= 0 (mod month-diff n))))))
       ;; Yearly: same day and month, year difference divisible by N
       ((string= unit "y")
        (and (= target-day sched-day)
             (= target-month sched-month)
             (let ((year-diff (- target-year sched-year)))
               (and (>= year-diff 0) (= 0 (mod year-diff n))))))
       ;; Unknown unit: include to be safe
       (t t)))))

(defun aj/get-due-positions-for-date (date-time)
  "Return set of heading positions in tasks.org that are due on DATE-TIME.
Uses `org-agenda-get-day-entries' with :scheduled :sexp :deadline selectors.
Resolves markers to their parent heading positions."
  (let* ((file (expand-file-name aj/tasks-file))
         (date (decode-time date-time))
         (day (nth 3 date))
         (month (nth 4 date))
         (year (nth 5 date))
         (date-list (list month day year))
         (entries (org-agenda-get-day-entries file date-list :scheduled :sexp :deadline))
         (positions (make-hash-table :test 'eq)))
    (dolist (entry entries)
      (let ((marker (get-text-property 0 'org-marker entry))
            (entry-type (get-text-property 0 'type entry)))
        (when marker
          ;; Resolve marker to the heading that owns it
          (let ((heading-pos
                 (with-current-buffer (marker-buffer marker)
                   (save-excursion
                     (goto-char (marker-position marker))
                     (if (org-at-heading-p)
                         (line-beginning-position)
                       ;; Marker is on a body line (e.g. diary sexp) — find parent heading
                       (org-back-to-heading t)
                       (line-beginning-position))))))
            ;; For past-scheduled entries, verify the target date is an
            ;; actual occurrence of the repeat cycle (handles +, ++, .+).
            (when (or (not (equal entry-type "past-scheduled"))
                      (with-current-buffer (marker-buffer marker)
                        (save-excursion
                          (goto-char heading-pos)
                          (forward-line 1)
                          (when (looking-at "^SCHEDULED: \\(<[^>]+>\\)")
                            (aj/date-is-repeat-occurrence-p
                             (match-string 1)
                             date-time)))))
              (puthash heading-pos t positions))))))
    positions))

(defun aj/subtree-has-due-position-p (start end due-set)
  "Return non-nil if any position between START and END is in DUE-SET."
  (catch 'found
    (maphash (lambda (pos _)
               (when (and (>= pos start) (< pos end))
                 (throw 'found t)))
             due-set)
    nil))

(defun aj/extract-filtered-subtree (buf pos due-set date-time)
  "Extract filtered subtree from BUF at POS using DUE-SET.
DATE-TIME is the target date for birthday/holiday evaluation.
Returns content string with heading levels preserved as-is (relative to tasks.org)."
  (with-current-buffer buf
    (save-excursion
      (goto-char pos)
      (let* ((top-level (org-current-level))
             (subtree-end (save-excursion (org-end-of-subtree t t) (point)))
             (lines '()))
        ;; Include the top-level heading line itself
        (push (buffer-substring-no-properties (line-beginning-position) (line-end-position)) lines)
        (forward-line 1)
        ;; Include body text of top-level heading (everything before first child)
        (while (and (< (point) subtree-end)
                    (not (looking-at-p "^\\*+ ")))
          (let ((line (buffer-substring-no-properties (line-beginning-position) (line-end-position))))
            (push line lines))
          (forward-line 1))
        ;; Process children
        (while (< (point) subtree-end)
          (if (looking-at-p "^\\*+ ")
              (let* ((child-pos (point))
                     (child-end (save-excursion (org-end-of-subtree t t) (point)))
                     ;; Check if this child or any content in its subtree is due
                     (child-due-p (aj/subtree-has-due-position-p child-pos child-end due-set))
                     ;; Check if the child has a schedule at all (SCHEDULED, DEADLINE, or diary sexp)
                     (child-has-schedule-p
                      (save-excursion
                        (forward-line 1)
                        (or child-due-p
                            (looking-at-p "^SCHEDULED:")
                            (looking-at-p "^DEADLINE:")
                            (looking-at-p "^%%")))))
                (if (and child-has-schedule-p child-due-p)
                    ;; Child is due: recursively extract its subtree
                    (let ((child-content (aj/extract-filtered-subtree buf child-pos due-set date-time)))
                      (dolist (line (split-string child-content "\n"))
                        (push line lines)))
                  ;; Child not due or has no schedule: skip
                  )
                (goto-char child-end))
            (forward-line 1)))
        (string-join (nreverse lines) "\n")))))

(defun aj/strip-scheduling-noise (content &optional date-time)
  "Strip SCHEDULED lines without times, LAST_REPEAT, LOGBOOK drawers, PROPERTIES drawers.
Keep SCHEDULED lines that have HH:MM (useful reminders).
When DATE-TIME is provided, replace the date in kept SCHEDULED lines with it.
Keep PROPERTIES drawers that contain CATEGORY."
  (let ((lines (split-string content "\n"))
        (result '())
        (in-logbook nil)
        (in-properties nil)
        (properties-lines '())
        (properties-has-category nil))
    (dolist (line lines)
      (cond
       ;; Start of LOGBOOK drawer
       ((string-match-p "^:LOGBOOK:" line)
        (setq in-logbook t))
       ;; End of LOGBOOK drawer
       ((and in-logbook (string-match-p "^:END:" line))
        (setq in-logbook nil))
       ;; Inside LOGBOOK: skip
       (in-logbook nil)
       ;; Start of PROPERTIES drawer
       ((string-match-p "^:PROPERTIES:" line)
        (setq in-properties t
              properties-lines (list line)
              properties-has-category nil))
       ;; End of PROPERTIES drawer
       ((and in-properties (string-match-p "^:END:" line))
        (push line properties-lines)
        (setq in-properties nil)
        ;; Only keep if it has CATEGORY
        (when properties-has-category
          (dolist (pl (nreverse properties-lines))
            (push pl result))))
       ;; Inside PROPERTIES
       (in-properties
        (push line properties-lines)
        (when (string-match-p "^:CATEGORY:" line)
          (setq properties-has-category t)))
       ;; LAST_REPEAT lines
       ((string-match-p "^:LAST_REPEAT:" line) nil)
       ;; State change log lines (outside drawers)
       ((string-match-p "^- State \"" line) nil)
       ;; SCHEDULED without time: strip
       ((and (string-match-p "^SCHEDULED:" line)
             (not (string-match-p "[0-9]\\{2\\}:[0-9]\\{2\\}" line)))
        nil)
       ;; SCHEDULED with time: keep but strip repeater and update date for daily note
       ((string-match-p "^SCHEDULED:" line)
        (let ((cleaned (replace-regexp-in-string " \\.?\\+\\+?[0-9]+[dwmy]" "" line)))
          ;; Replace the date with the target date, preserving the time
          (when date-time
            (let ((target-date (format-time-string "%Y-%m-%d %a" date-time)))
              (setq cleaned (replace-regexp-in-string
                             "<[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [A-Za-z]\\{2,3\\}"
                             (concat "<" target-date)
                             cleaned))))
          (push cleaned result)))
       ;; DEADLINE lines: strip entirely for daily notes
       ((string-match-p "^DEADLINE:" line) nil)
       ;; Normal line: keep
       (t (push line result))))
    (string-join (nreverse result) "\n")))

(defun aj/evaluate-birthday-lines (body date-time)
  "Evaluate %%(org-anniversary ...) lines in BODY against DATE-TIME.
Replace diary sexp with evaluated text, omit lines that produce no output."
  (let ((date (decode-time date-time))
        (lines (split-string body "\n"))
        (result '()))
    (dolist (line lines)
      (if (string-match "^%%(org-anniversary \\([0-9]+\\)\\s-+\\([0-9]+\\)\\s-+\\([0-9]+\\))\\s-+\\(.*\\)" line)
          (let* ((year (string-to-number (match-string 1 line)))
                 (month (string-to-number (match-string 2 line)))
                 (day (string-to-number (match-string 3 line)))
                 (template (match-string 4 line))
                 (target-month (nth 4 date))
                 (target-day (nth 3 date))
                 (target-year (nth 5 date)))
            (when (and (= month target-month) (= day target-day))
              (let* ((age (- target-year year))
                     (text (replace-regexp-in-string "%d" (number-to-string age) template)))
                (push text result))))
        (push line result)))
    (string-join (nreverse result) "\n")))

(defun aj/evaluate-holidays-for-date (date-time)
  "Return list of holiday names for DATE-TIME using `calendar-check-holidays'."
  (require 'holidays)
  (let* ((date (decode-time date-time))
         (day (nth 3 date))
         (month (nth 4 date))
         (year (nth 5 date))
         (calendar-date (list month day year)))
    (calendar-check-holidays calendar-date)))

(defun aj/get-tasks-for-date (date-time)
  "Return list of (HEADING-NAME . CONTENT) for recurring tasks due on DATE-TIME.
Main orchestrator replacing `aj/get-recurring-tasks-grouped'."
  (let* ((file (expand-file-name aj/tasks-file))
         (due-set (aj/get-due-positions-for-date date-time))
         (buf (find-file-noselect file))
         (results '()))
    (with-current-buffer buf
      (save-excursion
        (goto-char (point-min))
        ;; Walk top-level headings
        (while (re-search-forward "^\\* " nil t)
          (let* ((heading-pos (line-beginning-position))
                 (heading-end (save-excursion (org-end-of-subtree t t) (point))))
            (when (gethash heading-pos due-set)
              (let* ((raw-content (aj/extract-filtered-subtree buf heading-pos due-set date-time))
                     ;; Strip scheduling noise, updating dates to target day
                     (cleaned (aj/strip-scheduling-noise raw-content date-time))
                     ;; Get heading name from first line
                     (first-line (car (split-string cleaned "\n")))
                     (heading-name (aj/extract-heading-name first-line)))
                ;; Special handling for headings with birthday/holiday content
                (when heading-name
                  (let ((processed cleaned))
                    ;; Evaluate birthday lines (replace diary sexps with text)
                    (when (string-match-p "%%(org-anniversary" processed)
                      (setq processed (aj/evaluate-birthday-lines processed date-time)))
                    ;; Evaluate holiday content (replace diary sexp with holiday names)
                    (when (string-match-p "%%(org-calendar-holiday)" processed)
                      (let ((holidays (aj/evaluate-holidays-for-date date-time)))
                        (if holidays
                            (setq processed
                                  (replace-regexp-in-string
                                   "%%(org-calendar-holiday).*"
                                   (string-join holidays "\n")
                                   processed))
                          ;; No holidays: strip the sexp line (keep rest of content)
                          (setq processed
                                (replace-regexp-in-string
                                 "%%(org-calendar-holiday).*\n?" ""
                                 processed)))))
                    (when processed
                      (push (cons heading-name processed) results))))))
            (goto-char heading-end)))))
    (nreverse results)))

(defun aj/get-carryforward-tasks (date-time)
  "Return list of (HEADING-NAME . CONTENT) for priority tasks missed before DATE-TIME.
A task is carried forward if it has [#A/B/C] priority and its LAST_REPEAT
is older than the previous scheduled occurrence."
  (let* ((file (expand-file-name aj/tasks-file))
         (buf (find-file-noselect file))
         (due-set (aj/get-due-positions-for-date date-time))
         (results '()))
    (with-current-buffer buf
      (save-excursion
        (goto-char (point-min))
        (while (re-search-forward "^\\*+ \\(?:TODO\\|WAIT\\) .*\\[#[A-C]\\]" nil t)
          (let* ((pos (line-beginning-position))
                 (heading-line (buffer-substring-no-properties pos (line-end-position))))
            ;; Skip if already due today
            (unless (gethash pos due-set)
              (save-excursion
                (goto-char pos)
                (forward-line 1)
                (when (looking-at "SCHEDULED: <\\([^>]+\\)>")
                  (let* ((sched-str (match-string 1))
                         ;; Check for LAST_REPEAT
                         (last-repeat
                          (save-excursion
                            (let ((subtree-end (save-excursion (org-end-of-subtree t t) (point))))
                              (when (re-search-forward ":LAST_REPEAT: \\[\\([^]]+\\)\\]" subtree-end t)
                                (match-string 1)))))
                         (heading-name (aj/extract-heading-name heading-line)))
                    ;; If there's a LAST_REPEAT, check if task was missed
                    (when (and last-repeat heading-name
                               (string-match-p "\\+[0-9]+[dwmy]" sched-str))
                      ;; Parse last repeat time
                      (let* ((last-time (org-time-string-to-time last-repeat))
                             (target-time date-time)
                             ;; If last repeat is before yesterday, task was likely missed
                             (yesterday (time-subtract target-time (days-to-time 1))))
                        (when (time-less-p last-time yesterday)
                          (let* ((raw-content (aj/extract-filtered-subtree buf pos due-set date-time))
                                 (cleaned (aj/strip-scheduling-noise raw-content date-time)))
                            (push (cons heading-name cleaned) results)))))))))))))
    ;; Tag carryforward headings with :overdue:
    (mapcar (lambda (pair)
              (cons (car pair)
                    (aj/tag-headings-overdue (cdr pair))))
            (nreverse results))))

(defun aj/tag-headings-overdue (content)
  "Add :overdue: tag to all heading lines in CONTENT."
  (let ((lines (split-string content "\n")))
    (string-join
     (mapcar (lambda (line)
               (if (string-match "^\\(\\*+ .+?\\)\\([ \t]*\\)$" line)
                   (let ((heading (match-string 1 line)))
                     (cond
                      ;; Already has :overdue: — leave as-is
                      ((string-match-p ":overdue:" heading) heading)
                      ;; Has other tags — prepend overdue
                      ((string-match-p ":[a-zA-Z_@]+:$" heading)
                       (replace-regexp-in-string
                        ":\\([a-zA-Z_@]+:\\)$"
                        ":overdue:\\1"
                        heading))
                      ;; No tags — append
                      (t (concat heading "  :overdue:"))))
                 line))
             lines)
     "\n")))

(defun aj/get-overdue-captures (date-str)
  "Return list of overdue TODO subtrees from * Capture in previous daily notes.
Scans backwards from the day before DATE-STR. Stops at the first day with
no Capture TODOs (assumes older days were already carried forward).
Returns list of (HEADING-TEXT . SUBTREE-CONTENT) pairs, tagged :overdue:."
  (let* ((parts (split-string date-str "-"))
         (year (string-to-number (nth 0 parts)))
         (month (string-to-number (nth 1 parts)))
         (day (string-to-number (nth 2 parts)))
         (current-time (encode-time 0 0 0 day month year))
         (daily-dir (expand-file-name
                     (or org-roam-dailies-directory "daily")
                     org-roam-directory))
         (results '())
         (days-back 0)
         (max-days 30))
    (while (< days-back max-days)
      (setq days-back (1+ days-back))
      (let* ((prev-time (time-subtract current-time (days-to-time days-back)))
             (prev-date (format-time-string "%Y-%m-%d" prev-time))
             (prev-file (expand-file-name (concat prev-date ".org") daily-dir)))
        (when (file-exists-p prev-file)
          (with-temp-buffer
            (insert-file-contents prev-file)
            (goto-char (point-min))
            (when (re-search-forward "^\\* Capture" nil t)
              (let ((section-end (save-excursion
                                   (if (re-search-forward "^\\* " nil t)
                                       (line-beginning-position)
                                     (point-max)))))
                (while (re-search-forward "^\\(\\*\\*+\\) \\(TODO\\|WAIT\\) " section-end t)
                  (let* ((stars (match-string 1))
                         (level (length stars))
                         (heading-start (line-beginning-position))
                         (subtree-end
                          (save-excursion
                            (forward-line 1)
                            ;; End at next heading at same or shallower level
                            (if (re-search-forward
                                 (format "^\\*\\{2,%d\\} " level)
                                 section-end t)
                                (line-beginning-position)
                              section-end)))
                         (subtree (string-trim-right
                                   (buffer-substring-no-properties heading-start subtree-end)))
                         ;; Promote headings to ** level
                         (subtree (if (> level 2)
                                      (let ((demote (- level 2)))
                                        (replace-regexp-in-string
                                         (format "^\\(\\*\\{%d,\\}\\)" level)
                                         (lambda (m)
                                           (make-string (- (length (match-string 1 m)) demote) ?*))
                                         subtree))
                                    subtree))
                         (heading-line (car (split-string subtree "\n")))
                         (heading-text (aj/extract-heading-name heading-line)))
                    (when heading-text
                      ;; Skip items with a SCHEDULED date strictly in the future
                      (let ((future-p
                             (and (string-match "SCHEDULED: <\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" subtree)
                                  (string> (match-string 1 subtree) date-str))))
                        (unless future-p
                          (let ((cleaned (replace-regexp-in-string
                                          "\\(\n*-+\n*\\)+\\'" "" subtree)))
                            (push (list heading-text (aj/tag-headings-overdue cleaned) prev-file)
                                  results)))))))))))))
    (nreverse results)))

(defun aj/capture-heading-exists-p (heading)
  "Check if HEADING already exists under * Capture.
Matches regardless of TODO state, priority, or tags."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^\\* Capture\\b" nil t)
      (let ((section-end (save-excursion
                           (if (re-search-forward "^\\* " nil t)
                               (line-beginning-position)
                             (point-max)))))
        (re-search-forward
         (format "^\\*\\*+ \\(?:TODO \\|DONE \\|WAIT \\|CANCEL \\)?\\(?:\\[#[A-Z]\\] \\)?%s"
                 (regexp-quote heading))
         section-end t)))))

(defun aj/bring-forward-overdue-captures ()
  "Bring forward TODO items from previous days' * Capture into today's * Capture.
Items are tagged :overdue: and only added if not already present.
No-op when the buffer's title date is in the future relative to real today —
otherwise opening a future daily would scan backward and CANCEL-stamp
present/past files."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^#\\+title: \\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" nil t)
      (let* ((date-str (match-string 1))
             (today (format-time-string "%Y-%m-%d")))
        (unless (string> date-str today)
          (let* ((overdue (aj/get-overdue-captures date-str))
                 (added 0))
            (when overdue
              (aj/ensure-heading-exists "Capture")
              (dolist (pair overdue)
                (let ((heading-text (car pair))
                      (content (nth 1 pair))
                      (source-file (nth 2 pair)))
                  (unless (aj/capture-heading-exists-p heading-text)
                    ;; Find end of Capture section to insert
                    (goto-char (point-min))
                    (when (re-search-forward "^\\* Capture" nil t)
                      (let ((section-end (save-excursion
                                           (forward-line 1)
                                           (if (re-search-forward "^\\* " nil t)
                                               (line-beginning-position)
                                             (point-max)))))
                        (goto-char section-end)
                        ;; Insert before next heading
                        (unless (bolp) (insert "\n"))
                        (unless (save-excursion (forward-line -1) (looking-at-p "^[ \t]*$"))
                          (insert "\n"))
                        (insert content "\n")
                        (setq added (1+ added))
                        ;; Mark source item as CANCEL to prevent re-scanning
                        (when source-file
                          (with-current-buffer (find-file-noselect source-file)
                            (save-excursion
                              (goto-char (point-min))
                              (when (re-search-forward "^\\* Capture" nil t)
                                (let ((src-end (save-excursion
                                                 (if (re-search-forward "^\\* " nil t)
                                                     (line-beginning-position)
                                                   (point-max)))))
                                  (when (re-search-forward
                                         (format "^\\*\\*+ \\(TODO\\|WAIT\\) \\(?:\\[#[A-Z]\\] \\)?%s"
                                                 (regexp-quote heading-text))
                                         src-end t)
                                    (beginning-of-line)
                                    (let ((aj/daily-hook-suppress t))
                                      (org-todo "CANCEL"))))))
                            (save-buffer)))))))))
            (when (> added 0)
              (message "Brought forward %d overdue capture(s) for %s" added date-str))))))))

(defun aj/get-overdue-recurring-tasks (date-str)
  "Return overdue priority TODO subtrees from * Recurring in previous daily notes.
Scans backwards from the day before DATE-STR up to 30 days.
Returns list of (PARENT-NAME HEADING-TEXT CONTENT SOURCE-FILE) tuples, tagged :overdue:."
  (let* ((parts (split-string date-str "-"))
         (year (string-to-number (nth 0 parts)))
         (month (string-to-number (nth 1 parts)))
         (day (string-to-number (nth 2 parts)))
         (current-time (encode-time 0 0 0 day month year))
         (daily-dir (expand-file-name
                     (or org-roam-dailies-directory "daily")
                     org-roam-directory))
         (results '())
         (days-back 0)
         (max-days 30))
    (while (< days-back max-days)
      (setq days-back (1+ days-back))
      (let* ((prev-time (time-subtract current-time (days-to-time days-back)))
             (prev-date (format-time-string "%Y-%m-%d" prev-time))
             (prev-file (expand-file-name (concat prev-date ".org") daily-dir)))
        (when (file-exists-p prev-file)
          (with-temp-buffer
            (insert-file-contents prev-file)
            (goto-char (point-min))
            (when (re-search-forward "^\\* Recurring\\b" nil t)
              (let ((section-end (save-excursion
                                   (forward-line 1)
                                   (if (re-search-forward "^\\* " nil t)
                                       (line-beginning-position)
                                     (point-max)))))
                ;; Walk ** parent headings
                (while (re-search-forward "^\\*\\* " section-end t)
                  (let* ((parent-start (line-beginning-position))
                         (parent-line (buffer-substring-no-properties
                                       parent-start (line-end-position)))
                         (parent-name (aj/extract-heading-name parent-line))
                         (parent-end (save-excursion
                                       (forward-line 1)
                                       (if (re-search-forward "^\\*\\* " section-end t)
                                           (line-beginning-position)
                                         section-end))))
                    ;; Find ***+ TODO/WAIT [#A-C] children within this parent
                    (save-excursion
                      (goto-char parent-start)
                      (while (re-search-forward
                              "^\\(\\*\\*\\*+\\) \\(TODO\\|WAIT\\) \\[#[A-C]\\]"
                              parent-end t)
                        (let* ((stars (match-string 1))
                               (level (length stars))
                               (heading-start (line-beginning-position))
                               (subtree-end
                                (save-excursion
                                  (forward-line 1)
                                  (if (re-search-forward
                                       (format "^\\*\\{2,%d\\} " level)
                                       parent-end t)
                                      (line-beginning-position)
                                    parent-end)))
                               (subtree (string-trim-right
                                         (buffer-substring-no-properties
                                          heading-start subtree-end)))
                               ;; Normalize to *** level if deeper
                               (subtree (if (> level 3)
                                            (let ((shift (- level 3)))
                                              (replace-regexp-in-string
                                               (format "^\\(\\*\\{%d,\\}\\)" level)
                                               (lambda (m)
                                                 (make-string (- (length (match-string 1 m)) shift) ?*))
                                               subtree))
                                          subtree))
                               (heading-line (car (split-string subtree "\n")))
                               (heading-text (aj/extract-heading-name heading-line)))
                          (when (and heading-text parent-name)
                            ;; Strip SCHEDULED lines, CLOSED lines, and trailing separators
                            (let ((cleaned subtree))
                              (setq cleaned (replace-regexp-in-string
                                             "\\(\n*-+\n*\\)+\\'" "" cleaned))
                              (setq cleaned (replace-regexp-in-string
                                             "\nSCHEDULED: <[^>]+>" "" cleaned))
                              (setq cleaned (replace-regexp-in-string
                                             "\nCLOSED: \\[[^]]+\\]" "" cleaned))
                              (push (list parent-name heading-text
                                          (aj/tag-headings-overdue cleaned)
                                          prev-file)
                                    results))))))))))))))
    (nreverse results)))

(defun aj/recurring-child-exists-p (parent-name child-heading)
  "Check if CHILD-HEADING exists under ** PARENT-NAME in * Recurring.
Matches regardless of TODO state, priority, or tags."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^\\* Recurring\\b" nil t)
      (let ((section-end (save-excursion
                           (forward-line 1)
                           (if (re-search-forward "^\\* " nil t)
                               (line-beginning-position)
                             (point-max)))))
        ;; Find the parent heading
        (when (re-search-forward
               (format "^\\*\\* \\(?:TODO \\|DONE \\|WAIT \\|CANCEL \\)?\\(?:\\[#[A-Z]\\] \\)?%s\\(?:[ \t]*$\\|[ \t]\\)"
                       (regexp-quote parent-name))
               section-end t)
          (let ((parent-end (save-excursion
                              (forward-line 1)
                              (if (re-search-forward "^\\*\\* " section-end t)
                                  (line-beginning-position)
                                section-end))))
            (re-search-forward
             (format "^\\*\\*\\*+ \\(?:TODO \\|DONE \\|WAIT \\|CANCEL \\)?\\(?:\\[#[A-Z]\\] \\)?%s\\(?:[ \t]*$\\|[ \t]\\)"
                     (regexp-quote child-heading))
             parent-end t)))))))

(defun aj/bring-forward-overdue-recurring ()
  "Bring forward priority TODO items from previous days' * Recurring sections.
Items are tagged :overdue: and placed under the same parent heading.
Source items are marked as CANCEL to prevent re-scanning.
No-op when the buffer's title date is in the future relative to real today —
otherwise opening a future daily would scan backward and CANCEL-stamp
present/past files."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^#\\+title: \\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" nil t)
      (let* ((date-str (match-string 1))
             (today (format-time-string "%Y-%m-%d")))
        (unless (string> date-str today)
          (let* ((overdue (aj/get-overdue-recurring-tasks date-str))
                 (added 0))
            (when overdue
              (dolist (entry overdue)
                (let ((parent-name (nth 0 entry))
                      (heading-text (nth 1 entry))
                      (content (nth 2 entry))
                      (source-file (nth 3 entry)))
                  (unless (aj/recurring-child-exists-p parent-name heading-text)
                    ;; Find parent heading under * Recurring
                    (goto-char (point-min))
                    (when (re-search-forward "^\\* Recurring\\b" nil t)
                      (let ((section-end (save-excursion
                                           (forward-line 1)
                                           (if (re-search-forward "^\\* " nil t)
                                               (line-beginning-position)
                                             (point-max)))))
                        (when (re-search-forward
                               (format "^\\*\\* \\(?:TODO \\|DONE \\|WAIT \\|CANCEL \\)?\\(?:\\[#[A-Z]\\] \\)?%s\\(?:[ \t]*$\\|[ \t]\\)"
                                       (regexp-quote parent-name))
                               section-end t)
                          ;; Find end of this parent's subtree
                          (let ((parent-end (save-excursion
                                              (forward-line 1)
                                              (if (re-search-forward "^\\*\\* " section-end t)
                                                  (line-beginning-position)
                                                section-end))))
                            (goto-char parent-end)
                            ;; Insert before next ** heading (separators will be cleaned up)
                            (unless (bolp) (insert "\n"))
                            (unless (save-excursion (forward-line -1) (looking-at-p "^[ \t]*$"))
                              (insert "\n"))
                            (insert content "\n")
                            (setq added (1+ added))
                            ;; Mark source item as CANCEL to prevent re-scanning
                            (when source-file
                              (with-current-buffer (find-file-noselect source-file)
                                (save-excursion
                                  (goto-char (point-min))
                                  (when (re-search-forward "^\\* Recurring\\b" nil t)
                                    (let ((src-end (save-excursion
                                                     (forward-line 1)
                                                     (if (re-search-forward "^\\* " nil t)
                                                         (line-beginning-position)
                                                       (point-max)))))
                                      (when (re-search-forward
                                             (format "^\\*\\*\\*+ \\(TODO\\|WAIT\\) \\(?:\\[#[A-Z]\\] \\)?%s"
                                                     (regexp-quote heading-text))
                                             src-end t)
                                        (beginning-of-line)
                                        (let ((aj/daily-hook-suppress t))
                                          (org-todo "CANCEL"))))))
                                (save-buffer))))))))))
              (when (> added 0)
                (message "Brought forward %d overdue recurring task(s) for %s" added date-str)))))))))

(defun aj/recurring-heading-exists-p (heading)
  "Check if HEADING already exists under * Recurring.
Matches regardless of TODO state (TODO/DONE/WAIT/CANCEL) or priority."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^\\* Recurring\\b" nil t)
      (let ((section-end (save-excursion
                           (if (re-search-forward "^\\* " nil t)
                               (line-beginning-position)
                             (point-max)))))
        (re-search-forward
         (format "^\\*\\* \\(?:TODO \\|DONE \\|WAIT \\|CANCEL \\)?\\(?:\\[#[A-Z]\\] \\)?%s\\(?:[ \t]*$\\|[ \t]\\)"
                 (regexp-quote heading))
         section-end t)))))

(defun aj/extract-heading-name (line)
  "Extract heading name from LINE, stripping TODO keywords, priority, and tags."
  (when (string-match "^\\*+ \\(?:TODO \\|DONE \\|WAIT \\|CANCEL \\)?\\(?:\\[#[A-Z]\\] \\)?\\(.+\\)$" line)
    (let ((name (match-string 1 line)))
      ;; Strip trailing org tags (e.g. " :overdue:" or "  :tag1:tag2:")
      (if (string-match "\\(.*?\\)\\s-+:[a-zA-Z_@:]+:\\s-*$" name)
          (match-string 1 name)
        (string-trim-right name)))))

(defun aj/extract-heading-order (tasks)
  "Extract ordered list of heading names from TASKS string."
  (let ((headings nil))
    (dolist (line (split-string tasks "\n"))
      (when (string-match "^\\*\\* \\(?:TODO \\|DONE \\|WAIT \\|CANCEL \\)?\\(?:\\[#[A-Z]\\] \\)?\\(.+\\)$" line)
        (push (match-string 1 line) headings)))
    (nreverse headings)))

(defvar aj/recurring-heading-order nil
  "Ordered list of recurring heading names, populated during refresh.")

(defun aj/clean-and-insert-recurring-separator (prev-heading-bol curr-heading-bol)
  "Clean existing separators between PREV-HEADING-BOL and CURR-HEADING-BOL.
Then insert a single ----- separator."
  (save-excursion
    (let ((zone-start (save-excursion
                        (goto-char prev-heading-bol)
                        (forward-line 1)
                        (point)))
          (positions nil))
      ;; Collect all ----- lines in the zone
      (goto-char zone-start)
      (while (re-search-forward "^-----$" curr-heading-bol t)
        (push (cons (line-beginning-position)
                    (min (1+ (line-end-position)) (point-max)))
              positions))
      ;; Delete from bottom to top
      (dolist (pos positions)
        (delete-region (car pos) (cdr pos))
        (setq curr-heading-bol (- curr-heading-bol (- (cdr pos) (car pos)))))
      ;; Insert single separator before curr heading
      (goto-char curr-heading-bol)
      ;; Walk backwards past blank lines
      (forward-line -1)
      (while (and (> (point) zone-start) (looking-at-p "^[ \t]*$"))
        (forward-line -1))
      (forward-line 1)
      ;; Remove excess blank lines
      (let ((blank-start (point)))
        (while (and (< (point) curr-heading-bol) (looking-at-p "^[ \t]*$"))
          (forward-line 1))
        (when (> (point) blank-start)
          (delete-region blank-start (point))))
      (insert "\n-----\n\n"))))

(defun aj/ensure-recurring-separators ()
  "Ensure single ----- separators between ** headings under * Recurring."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^\\* Recurring\\b" nil t)
      (let* ((section-start (line-end-position))
             (section-end (save-excursion
                            (forward-line 1)
                            (if (re-search-forward "^\\* " nil t)
                                (line-beginning-position)
                              (point-max))))
             (headings nil))
        ;; Collect all ** heading positions in the Recurring section
        (goto-char section-start)
        (while (re-search-forward "^\\*\\* \\(?:TODO \\|DONE \\|WAIT \\|CANCEL \\)?\\(?:\\[#[A-Z]\\] \\)?\\(.+?\\)[ \t]*$" section-end t)
          (push (cons (match-string 1) (line-beginning-position)) headings))
        (setq headings (nreverse headings))
        ;; Process from bottom to top (position stability)
        (let ((len (length headings)))
          (when (>= len 2)
            (dotimes (j (1- len))
              (let* ((i (- len 1 j))
                     (curr-bol (cdr (nth i headings))))
                (aj/clean-and-insert-recurring-separator
                 (cdr (nth (1- i) headings)) curr-bol)))))))))

(defun aj/find-recurring-insert-point (heading-name)
  "Find correct insertion point for HEADING-NAME under * Recurring.
Uses `aj/recurring-heading-order' to maintain template order."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^\\* Recurring\\b" nil t)
      (let* ((section-start (line-end-position))
             (section-end (save-excursion
                            (forward-line 1)
                            (if (re-search-forward "^\\* " nil t)
                                (line-beginning-position)
                              (point-max))))
             (pos (cl-position heading-name aj/recurring-heading-order :test 'equal))
             (later-headings (when pos (nthcdr (1+ pos) aj/recurring-heading-order))))
        ;; Find first existing heading that should come AFTER this one
        (catch 'found
          (dolist (next-heading later-headings)
            (goto-char section-start)
            (when (re-search-forward
                   (format "^\\*\\* \\(?:TODO \\|DONE \\|WAIT \\|CANCEL \\)?\\(?:\\[#[A-Z]\\] \\)?%s\\b"
                           (regexp-quote next-heading))
                   section-end t)
              (throw 'found (line-beginning-position))))
          ;; No later heading found, insert at end of section
          section-end)))))

(defun aj/insert-recurring-block (heading content-lines)
  "Insert HEADING and CONTENT-LINES at correct position under * Recurring.
Maintains template order by inserting before later headings.
Ensures exactly one blank line before the heading."
  (let* ((heading-name (aj/extract-heading-name heading))
         (insert-point (aj/find-recurring-insert-point heading-name)))
    (when insert-point
      (save-excursion
        (goto-char insert-point)
        ;; Ensure we're at beginning of line
        (unless (bolp) (insert "\n"))
        ;; Check if previous line is blank; if not, add one
        (when (save-excursion
                (forward-line -1)
                (not (looking-at-p "^[ \t]*$")))
          (insert "\n"))
        (insert heading "\n")
        ;; Insert all content lines, including blank lines for proper spacing
        (dolist (line content-lines)
          (insert line "\n"))))))

(defun aj/refresh-daily-recurring ()
  "Refresh recurring tasks in the current daily note.
Parses date from #+title: line, queries tasks.org via org-agenda.
Only ADDS new tasks - does not replace or modify existing ones.
Maintains template order even when some headings already exist."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward "^#\\+title: \\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" nil t)
        (let* ((date-str (match-string 1))
               (parts (split-string date-str "-"))
               (year (string-to-number (nth 0 parts)))
               (month (string-to-number (nth 1 parts)))
               (day (string-to-number (nth 2 parts)))
               (date-time (encode-time 0 0 0 day month year))
               (task-pairs (aj/get-tasks-for-date date-time))
               (carryforward (aj/get-carryforward-tasks date-time))
               (all-pairs (append task-pairs carryforward))
               (added-count 0))
          (if (null all-pairs)
              (message "No recurring tasks for %s" date-str)
            ;; Build tasks string: increment heading levels by 1 for each pair
            (let ((all-contents
                   (mapcar (lambda (pair)
                             (replace-regexp-in-string "^\\(\\*+\\) " "*\\1 " (cdr pair)))
                           all-pairs)))
              ;; Populate heading order for correct insertion positions
              (setq aj/recurring-heading-order
                    (mapcar #'car all-pairs))
              ;; Ensure Recurring heading exists at correct position
              (aj/ensure-heading-exists "Recurring")
              ;; Insert each task block if not already present
              (dolist (content all-contents)
                (let ((task-lines (split-string content "\n"))
                      (current-heading nil)
                      (current-block nil))
                  ;; Group lines by top-level (** level) heading
                  (dolist (line task-lines)
                    (cond
                     ((string-match "^\\*\\* " line)
                      ;; Process previous block
                      (when (and current-heading
                                 (not (aj/recurring-heading-exists-p
                                       (aj/extract-heading-name current-heading))))
                        (aj/insert-recurring-block current-heading (nreverse current-block))
                        (setq added-count (1+ added-count)))
                      (setq current-heading line
                            current-block nil))
                     (t (push line current-block))))
                  ;; Process final block
                  (when (and current-heading
                             (not (aj/recurring-heading-exists-p
                                   (aj/extract-heading-name current-heading))))
                    (aj/insert-recurring-block current-heading (nreverse current-block))
                    (setq added-count (1+ added-count)))))
              ;; Apply recurring separators
              (aj/ensure-recurring-separators)
              (if (> added-count 0)
                  (message "Added %d recurring task(s) for %s" added-count date-str)
                (message "All recurring tasks already present for %s" date-str)))))
      (message "Not a daily note (no date in title)"))))

(provide 'daily-recurring)

;;; daily-recurring.el ends here
