;;; daily-config.el --- Daily note configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; All daily-note functionality: recurring tasks, weather, calendar,
;; capture templates, weekly transclusion, heading structure, navigation.

;;; Code:

(require 'org-roam)
(require 'org-roam-dailies)
(require 'cl-lib)

;; ---------------------------------------------------------------------------
;; Variables & Config
;; ---------------------------------------------------------------------------

(defvar aj/tasks-file
  (expand-file-name "daily/tasks.org" org-roam-directory)
  "Path to tasks.org file for recurring task scheduling.")

(defvar aj/daily-hook-suppress nil
  "When non-nil, `aj/daily-file-open-hook' is suppressed.
Used to prevent side-effects (overdue bring-forward, calendar refresh, etc.)
when files are opened during org-capture.")

;; Yearly file configuration for week transclusion
(defvar aj/yearly-file-ids
  '((2026 . "51fe6c3d-45e2-4655-bc1c-9358f989d02a"))
  "Alist mapping years to their yearly org file IDs.")

(defvar aj/yearly-file-names
  '((2026 . "twenty-twenty-six"))
  "Alist mapping years to their yearly org file display names.")

;; Desired order of level-1 headings in daily notes
(defvar aj/daily-heading-order
  '("Journal" "Recurring" "Calendar" "Capture" "Tasks")
  "Ordered list of level-1 headings for daily notes.")

(defvar aj/headings-with-statistics '("Capture" "Tasks")
  "Headings that should have [/] statistics cookies.")

;; Weather variables
(defvar aj/openweather-city "Sydney"
  "City for OpenWeatherMap queries.")

(defvar aj/weather-archive-remote "root@abaj.ai:/var/weather-archive/"
  "Remote path to weather archive on server.")

(defvar aj/weather-archive-local (expand-file-name "~/.cache/weather-archive/")
  "Local cache directory for weather archive.")

(defvar aj/weather-location-cache nil
  "Cached location data: (timestamp lat lon name).")

(defvar aj/weather-location-cache-duration 3600
  "How long to cache location data in seconds (default 1 hour).")

(defvar aj/weather-location-file (expand-file-name "~/.weather-location")
  "Optional file to manually set weather location.
Format: LAT LON NAME (e.g., -33.8148 151.1029 West Ryde)")

;; ---------------------------------------------------------------------------
;; Helpers (kept)
;; ---------------------------------------------------------------------------

(defun aj/iso-week-number (&optional time)
  "Return ISO week number for TIME."
  (string-to-number (format-time-string "%V" (or time (current-time)))))

;; ---------------------------------------------------------------------------
;; Capture Templates (targeting tasks.org)
;; ---------------------------------------------------------------------------

(defun aj/tasks-goto-heading ()
  "Prompt for a top-level heading in tasks.org and go to end of its subtree.
Used as a `file+function' target for capture templates."
  (let* ((headings '())
         (_ (save-excursion
              (goto-char (point-min))
              (while (re-search-forward "^\\* \\(.+\\)" nil t)
                (let ((raw (match-string-no-properties 1)))
                  ;; Strip org links to show clean names
                  (push (replace-regexp-in-string
                         "\\[\\[[^]]*\\]\\[\\([^]]*\\)\\]\\]" "\\1" raw)
                        headings)))))
         (chosen (completing-read "Under heading: " (nreverse headings) nil t)))
    ;; Find the chosen heading and go to end of its subtree
    (goto-char (point-min))
    (catch 'found
      (while (re-search-forward "^\\* \\(.+\\)" nil t)
        (let ((raw (match-string-no-properties 1)))
          (when (string= chosen
                         (replace-regexp-in-string
                          "\\[\\[[^]]*\\]\\[\\([^]]*\\)\\]\\]" "\\1" raw))
            ;; Stay inside the subtree so org-capture inserts at child level
            (org-end-of-subtree t)
            (throw 'found t)))))))

(setq org-capture-templates
      `(("r" "recurring templates")
        ("rd" "daily task" entry (file+function ,aj/tasks-file aj/tasks-goto-heading)
         "** TODO %?\nSCHEDULED: %(format-time-string \"<%Y-%m-%d %a ++1d>\")")
        ("rw" "weekly task" entry (file+function ,aj/tasks-file aj/tasks-goto-heading)
         "** TODO %?\nSCHEDULED: %(format-time-string \"<%Y-%m-%d %a +1w>\")")
        ("rm" "monthly task" entry (file+function ,aj/tasks-file aj/tasks-goto-heading)
         "** TODO %?\nSCHEDULED: %(format-time-string \"<%Y-%m-%d %a ++1m>\")")
        ("rc" "custom schedule" entry (file+function ,aj/tasks-file aj/tasks-goto-heading)
         "** TODO %?\nSCHEDULED: %^{Schedule}")
        ("t" "deferred task (one-off)" entry (file+function ,aj/tasks-file aj/tasks-goto-heading)
         "** TODO %?\nSCHEDULED: %^{When}t")
        ("l" "ledger templates")
        ("lc" "cash expense" plain
         (file+headline ,(concat "~/Documents/Finances/beancount/ledger/aayush/"
                                 (format-time-string "%Y") ".org")
                        "Cash")
         "%(format-time-string \"%Y-%m-%d\") * \"%^{Payee}\"\n  Expenses:%^{Category|Food:Groceries|Food:Dining|Food:Takeaway|Food:Coffee|Shopping:General|Transport:Fuel|Transport:PublicTransit|Health:Medical|Entertainment:Events|Gifts|Cash|Uncategorized}  %^{Amount} AUD\n  Assets:Cash\n"
         :empty-lines 1)
        ("li" "cash income" plain
         (file+headline ,(concat "~/Documents/Finances/beancount/ledger/aayush/"
                                 (format-time-string "%Y") ".org")
                        "Cash")
         "%(format-time-string \"%Y-%m-%d\") * \"%^{Source}\"\n  Assets:Cash  %^{Amount} AUD\n  Income:%^{Category|Other|Reimbursement|Tutoring}\n"
         :empty-lines 1)))

(defun aj/capture-prompt-jump-to-ledger ()
  "After a cash expense/income capture, offer to jump to the entry."
  (when (and (not org-note-abort)
             (member (org-capture-get :key) '("lc" "li"))
             (y-or-n-p "Jump to entry? "))
    (org-capture-goto-last-stored)))

(add-hook 'org-capture-after-finalize-hook #'aj/capture-prompt-jump-to-ledger)

;; ---------------------------------------------------------------------------
;; Daily File Detection
;; ---------------------------------------------------------------------------

(defun aj/daily-date-file-p (&optional file)
  "Return t if FILE matches YYYY-MM-DD.org pattern (actual daily note).
Excludes yearly files like twenty_twenty_six.org."
  (let ((path (or file (buffer-file-name))))
    (and path
         (string-match-p "/daily/[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\.org$" path))))

;; ---------------------------------------------------------------------------
;; Week Transclude
;; ---------------------------------------------------------------------------

(defun aj/get-week-heading-info (week-num year)
  "Get the ID and title of Week WEEK-NUM heading tagged with YEAR.
Returns (id . title) or nil if not found."
  (let* ((year-tag (number-to-string year))
         (title-pattern (format "Week %d%%" week-num))
         (result (org-roam-db-query
                  [:select [nodes:id nodes:title]
                   :from nodes
                   :left-join tags :on (= nodes:id tags:node-id)
                   :where (and (like nodes:title $s1)
                               (= tags:tag $s2))]
                  title-pattern year-tag)))
    (when result
      (let ((row (car result)))
        (cons (car row) (cadr row))))))

(defun aj/insert-week-transclude ()
  "Insert linked week heading and transclude directive.
Parses date from filename, calculates ISO week, inserts a heading
linking to the week node followed by transclude directive."
  (interactive)
  (save-excursion
    (when (and buffer-file-name
               (string-match "\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)\\.org$"
                             buffer-file-name))
      (let* ((year-str (match-string 1 buffer-file-name))
             (month-str (match-string 2 buffer-file-name))
             (day-str (match-string 3 buffer-file-name))
             (year (string-to-number year-str))
             (month (string-to-number month-str))
             (day (string-to-number day-str))
             (date-time (encode-time 0 0 0 day month year))
             (week-num (aj/iso-week-number date-time))
             (file-id (cdr (assoc year aj/yearly-file-ids)))
             (file-name (cdr (assoc year aj/yearly-file-names)))
             (week-info (aj/get-week-heading-info week-num year))
             (week-id (car week-info))
             (week-title (cdr week-info)))
        (when (and file-id file-name)
          (goto-char (point-min))
          ;; Find insertion point (after EXPORT_FILE_NAME line)
          (if (re-search-forward "^#\\+EXPORT_FILE_NAME:.*$" nil t)
              (progn
                (goto-char (match-end 0))
                (if (and week-id week-title)
                    ;; New format with linked heading
                    (insert (format "\n\n* [[id:%s][%s]]\n#+transclude: [[id:%s::* Week %d][%s]] :no-first-heading\n"
                                    week-id week-title file-id week-num file-name))
                  ;; Fallback without week heading ID (shouldn't happen normally)
                  (insert (format "\n\n* Week %d\n#+transclude: [[id:%s::* Week %d][%s]] :no-first-heading\n"
                                  week-num file-id week-num file-name))))
            ;; Fallback: insert at end of front matter
            (when (re-search-forward "^:END:$" nil t)
              (forward-line 1)
              (if (and week-id week-title)
                  (insert (format "\n* [[id:%s][%s]]\n#+transclude: [[id:%s::* Week %d][%s]] :no-first-heading\n"
                                  week-id week-title file-id week-num file-name))
                (insert (format "\n* Week %d\n#+transclude: [[id:%s::* Week %d][%s]] :no-first-heading\n"
                                week-num file-id week-num file-name))))))))))

;; ---------------------------------------------------------------------------
;; Recurring Task Management (tasks.org agenda-based)
;; ---------------------------------------------------------------------------

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

;; ---------------------------------------------------------------------------
;; Daily File Structure & Separators
;; ---------------------------------------------------------------------------

(defun aj/find-heading-insert-point (heading)
  "Find the correct insertion point for HEADING based on `aj/daily-heading-order'.
Returns the position where the heading should be inserted."
  (let* ((pos (cl-position heading aj/daily-heading-order :test 'equal))
         (later-headings (nthcdr (1+ pos) aj/daily-heading-order)))
    ;; Find the first existing heading that should come after this one
    (catch 'found
      (dolist (next-heading later-headings)
        (save-excursion
          (save-restriction
            (widen)
            (goto-char (point-min))
            (when (re-search-forward (format "^\\* %s\\b" (regexp-quote next-heading)) nil t)
              (throw 'found (line-beginning-position))))))
      ;; No later heading found, insert at end of buffer
      nil)))

(defun aj/ensure-heading-exists (heading)
  "Ensure HEADING exists in the daily note at the correct position.
Returns t if heading was created, nil if it already existed."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (unless (re-search-forward (format "^\\* %s\\b" (regexp-quote heading)) nil t)
        (let ((insert-point (aj/find-heading-insert-point heading))
              (heading-text (if (member heading aj/headings-with-statistics)
                                (format "* %s [/]\n\n" heading)
                              (format "* %s\n\n" heading))))
          (if insert-point
              (progn
                (goto-char insert-point)
                (insert heading-text))
            ;; Insert at end
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (insert (concat "\n" heading-text))))
        t))))

(defun aj/ensure-heading-has-statistics-cookie (heading)
  "Ensure HEADING has a [/] statistics cookie if it should have one.
Only modifies headings listed in `aj/headings-with-statistics'."
  (when (member heading aj/headings-with-statistics)
    (save-excursion
      (save-restriction
        (widen)
        (goto-char (point-min))
        (when (re-search-forward (format "^\\(\\* %s\\)\\([ \t]*\\)$" (regexp-quote heading)) nil t)
          ;; Heading exists without cookie - add it
          (goto-char (match-end 1))
          (insert " [/]"))))))

(defun aj/ensure-daily-structure ()
  "Ensure the daily note has all required headings in the correct order.
Order: Journal, Recurring, Calendar, Capture, Tasks."
  (interactive)
  (when (aj/daily-date-file-p)
    (save-excursion
      (dolist (heading aj/daily-heading-order)
        (aj/ensure-heading-exists heading))
      ;; Ensure statistics cookies on headings that need them
      (dolist (heading aj/headings-with-statistics)
        (aj/ensure-heading-has-statistics-cookie heading))
      ;; Ensure ----- separators between level-1 headings
      (aj/ensure-heading-separators)
      ;; Ensure #+LATEX: \newpage directive before each level-1 heading
      ;; (except the first) so `C-c C-e l o' paginates top-level sections.
      (aj/ensure-heading-newpages)
      (aj/ensure-recurring-separators)
      ;; Final pass: collapse any 2+ consecutive blank lines immediately
      ;; below a heading down to a single blank line. Self-heals drift
      ;; from accumulated refreshes / inserts that don't normalize spacing.
      (aj/normalize-heading-blank-lines))))

(defun aj/normalize-heading-blank-lines ()
  "Collapse 2+ consecutive blank lines immediately following any heading to 1.
Idempotent. Only touches the blank-line run directly under a heading;
blank lines elsewhere in body content are left alone."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (while (re-search-forward "^\\*+ " nil t)
        (forward-line 1)
        (let ((blank-start (point))
              (n 0))
          (while (and (not (eobp)) (looking-at-p "^[ \t]*$"))
            (forward-line 1)
            (setq n (1+ n)))
          (when (> n 1)
            (delete-region blank-start (point))
            (insert "\n")))))))

(defun aj/ensure-heading-separators ()
  "Ensure triple ----- separators immediately before each level-1 heading except the first.
If a separator was displaced (e.g. by a capture inserting after it),
removes all stale separators and inserts a fresh triple separator.
User-placed separators earlier in the section are preserved."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((headings nil))
        ;; Collect all level-1 heading positions
        (while (re-search-forward "^\\* " nil t)
          (push (line-beginning-position) headings))
        (setq headings (nreverse headings))
        (let ((len (length headings)))
          (when (>= len 2)
            ;; Process from bottom to top so position shifts don't affect
            ;; headings we haven't processed yet
            (dotimes (j (1- len))
              (let* ((i (- len 1 j))
                     (heading-bol (nth i headings))
                     (section-start (save-excursion
                                      (goto-char (nth (1- i) headings))
                                      (forward-line 1) (point))))
                ;; Check if triple ----- is right above heading (skip blank lines
                ;; and any `#+LATEX: \newpage' directive inserted by
                ;; `aj/ensure-heading-newpages').
                (goto-char heading-bol)
                (forward-line -1)
                (while (and (> (point) section-start)
                            (or (looking-at-p "^[ \t]*$")
                                (looking-at-p "^#\\+LATEX:[ \t]+\\\\newpage[ \t]*$")))
                  (forward-line -1))
                (let ((has-triple-sep
                       (and (looking-at-p "^-----$")
                            (save-excursion
                              (forward-line -1)
                              (and (looking-at-p "^-----$")
                                   (save-excursion
                                     (forward-line -1)
                                     (looking-at-p "^-----$")))))))
                  (unless has-triple-sep
                    ;; Remove ALL ----- lines in this section (stale singles or doubles)
                    (let ((positions nil))
                      (goto-char section-start)
                      (while (re-search-forward "^-----$" heading-bol t)
                        (push (cons (line-beginning-position)
                                    (min (1+ (line-end-position)) (point-max)))
                              positions))
                      ;; Delete from bottom to top so positions stay valid
                      (dolist (pos positions)
                        (delete-region (car pos) (cdr pos))
                        (setq heading-bol (- heading-bol (- (cdr pos) (car pos))))))
                    ;; Insert fresh triple separator before heading. If a
                    ;; `#+LATEX: \newpage' directive already sits directly
                    ;; above the heading, insert the separators above it so
                    ;; the canonical order (separators -> newpage -> heading)
                    ;; is preserved.
                    (let ((insert-pos heading-bol))
                      (save-excursion
                        (goto-char heading-bol)
                        (forward-line -1)
                        (when (looking-at-p "^#\\+LATEX:[ \t]+\\\\newpage[ \t]*$")
                          (setq insert-pos (line-beginning-position))))
                      (goto-char insert-pos)
                      (unless (save-excursion (forward-line -1) (looking-at-p "^[ \t]*$"))
                        (insert "\n"))
                      (insert "-----\n-----\n-----\n\n"))))))))))))

(defun aj/ensure-heading-newpages ()
  "Ensure `#+LATEX: \\newpage' sits immediately above each level-1 heading
except the first, so `C-c C-e l o' paginates top-level sections.

Self-healing: first sweeps out orphaned directives (those whose next
non-blank line is NOT a level-1 heading), then inserts canonical ones.
Orphaning happens when `aj/refresh-daily-recurring' or the overdue
bringers splice `** ' subtrees between a pre-existing directive and its
intended heading — the directive ends up stranded above the injected
subtree instead of above the heading it was meant for."
  (save-excursion
    (save-restriction
      (widen)
      ;; Phase 1: delete orphaned directives.
      (goto-char (point-min))
      (let ((to-delete nil))
        (while (re-search-forward "^#\\+LATEX:[ \t]+\\\\newpage[ \t]*$" nil t)
          (let ((line-start (line-beginning-position))
                (orphan-p
                 (save-excursion
                   (forward-line 1)
                   (while (and (not (eobp))
                               (looking-at-p "^[ \t]*$"))
                     (forward-line 1))
                   (not (looking-at-p "^\\* ")))))
            (when orphan-p
              (push (cons line-start
                          (save-excursion
                            (goto-char line-start)
                            (forward-line 1)
                            (point)))
                    to-delete))))
        ;; Delete bottom-to-top to keep earlier positions valid.
        (dolist (range to-delete)
          (delete-region (car range) (cdr range))))
      ;; Phase 2: insert canonical directives.
      (goto-char (point-min))
      (let ((headings nil))
        (while (re-search-forward "^\\* " nil t)
          (push (line-beginning-position) headings))
        (setq headings (nreverse headings))
        (let ((len (length headings)))
          (when (>= len 2)
            (dotimes (j (1- len))
              (let* ((i (- len 1 j))
                     (heading-bol (nth i headings)))
                (goto-char heading-bol)
                (unless (save-excursion
                          (forward-line -1)
                          (looking-at-p "^#\\+LATEX:[ \t]+\\\\newpage[ \t]*$"))
                  (insert "#+LATEX: \\newpage\n"))))))))))

(defun aj/fold-week-heading ()
  "Fold the Week heading if present.
Matches both linked format (* [[id:...][Week N ...]]) and plain format (* Week N)."
  (when (aj/daily-date-file-p)
    (save-excursion
      (goto-char (point-min))
      ;; Match either: * [[id:...][Week N...]] or * Week N
      (when (re-search-forward "^\\* \\(\\[\\[id:[^]]+\\]\\[\\)?Week [0-9]+" nil t)
        (goto-char (line-beginning-position))
        (when (not (org-fold-folded-p (line-end-position)))
          (org-cycle))))))

;; ---------------------------------------------------------------------------
;; Capture Entry Tracking & Jump
;; ---------------------------------------------------------------------------

;; Helper for dailies time prefix - shows time only for today's captures
(defun aj/dailies-entry-prefix ()
  "Return time prefix for today's captures, empty string otherwise."
  (let* ((capture-time (org-capture-get :default-time))
         (today (format-time-string "%Y-%m-%d"))
         (capture-date (format-time-string "%Y-%m-%d" capture-time)))
    (if (equal today capture-date)
        (format-time-string "%I:%M%p " capture-time)
      "")))

;; Track dailies file for repositioning after capture
(defvar aj/--dailies-capture-file nil)

;; Track captured entry heading for optional jump (position gets stale after buffer modifications)
(defvar aj/--dailies-capture-heading nil
  "Heading text of the newly captured dailies entry.")

(defvar aj/--dailies-capture-target nil
  "Target heading for current dailies capture.
\"Capture\" = default. Otherwise, raw heading text of a Recurring child.")

(defun aj/dailies-store-capture-marker ()
  "Store identifier of the captured entry for optional jump.
Stores heading text instead of position since buffer modifications
(separator insertion, recurring task refresh) shift positions."
  (let* ((buf (org-capture-get :buffer))
         (file (and buf (buffer-file-name buf))))
    ;; Check if this is a dailies capture
    (when (and file
               (string-match-p "/daily/[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\.org$" file))
      (setq aj/--dailies-capture-file file)
      ;; Store the heading text to search for later
      (with-current-buffer buf
        (save-excursion
          (goto-char (org-capture-get :insertion-point))
          (when (org-at-heading-p)
            (setq aj/--dailies-capture-heading
                  (org-get-heading t t t t))))))))

(defun aj/dailies-prompt-jump-to-capture ()
  "Prompt user to jump to the newly captured dailies entry.
Searches for heading text instead of using stored position, since
buffer modifications (separator insertion, recurring task refresh)
shift positions after capture."
  (when (and aj/--dailies-capture-file aj/--dailies-capture-heading)
    (let ((file aj/--dailies-capture-file)
          (heading aj/--dailies-capture-heading)
          (target (or aj/--dailies-capture-target "Capture")))
      ;; Clear all state vars
      (setq aj/--dailies-capture-file nil
            aj/--dailies-capture-heading nil
            aj/--dailies-capture-target nil)
      (when (y-or-n-p "Jump to captured entry? ")
        (switch-to-buffer (find-file-noselect file))
        (widen)
        (goto-char (point-min))
        (if (equal target "Capture")
            ;; Search under * Capture section (original behavior)
            (if (re-search-forward "^\\* Capture\\b" nil t)
                (let ((section-end (save-excursion
                                     (if (re-search-forward "^\\* " nil t)
                                         (point)
                                       (point-max)))))
                  (if (re-search-forward
                       (format "^\\*\\* .*%s" (regexp-quote heading))
                       section-end t)
                      (progn
                        (beginning-of-line)
                        (org-reveal)
                        (recenter))
                    (message "Could not find captured entry: %s" heading)))
              (message "Could not find Capture section"))
          ;; Entry was moved to Recurring — search as demoted *** heading
          (if (or (re-search-forward
                   (format "^\\*\\*\\* .*%s" (regexp-quote heading)) nil t)
                  (progn (goto-char (point-min))
                         (re-search-forward
                          (format "^\\*+ .*%s" (regexp-quote heading)) nil t)))
              (progn
                (beginning-of-line)
                (org-reveal)
                (recenter))
            (message "Could not find captured entry: %s" heading)))))))

(defun aj/dailies-track-file ()
  "Track the dailies file being captured to."
  (let ((file (buffer-file-name (org-capture-get :buffer))))
    (when (and file
               (string-match-p "/daily/[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\.org$" file))
      (setq aj/--dailies-capture-file file))))

(defun aj/dailies-get-recurring-children (buf)
  "Return alist of (display-name . raw-heading) for ** children of * Recurring in BUF.
Uses `org-link-display-format' to strip links for display."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward "^\\* Recurring\\b" nil t)
          (let ((section-end (save-excursion
                               (if (re-search-forward "^\\* " nil t)
                                   (line-beginning-position)
                                 (point-max))))
                (children nil))
            (while (re-search-forward "^\\*\\* \\(.+\\)$" section-end t)
              (let* ((raw (match-string 1))
                     (display (org-link-display-format raw)))
                (push (cons display raw) children)))
            (nreverse children)))))))

(defun aj/dailies-prompt-target-heading ()
  "Prompt user to choose target heading for dailies capture.
Offers immediate ** children of * Recurring as alternatives to Capture."
  (let ((file (buffer-file-name (org-capture-get :buffer))))
    (when (and file
               (string-match-p "/daily/[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\.org$" file))
      (let* ((buf (org-capture-get :buffer))
             (children (aj/dailies-get-recurring-children buf))
             (options (append '("Capture")
                              (mapcar #'car children)))
             (choice (completing-read "Place under: " options nil t nil nil "Capture"))
             (target (if (equal choice "Capture")
                         "Capture"
                       (or (cdr (assoc choice children)) choice))))
        (setq aj/--dailies-capture-target target)))))

(defun aj/dailies-move-capture-to-recurring (target heading)
  "Move captured entry from * Capture to ** TARGET under * Recurring.
HEADING is the captured entry's heading text. Demotes from ** to ***."
  (save-excursion
    ;; Find the entry under * Capture
    (goto-char (point-min))
    (when (re-search-forward "^\\* Capture\\b" nil t)
      (let ((capture-end (save-excursion
                           (if (re-search-forward "^\\* " nil t)
                               (line-beginning-position)
                             (point-max)))))
        (when (re-search-forward
               (format "^\\*\\* .*%s" (regexp-quote heading))
               capture-end t)
          (beginning-of-line)
          (let* ((entry-start (point))
                 (entry-end (save-excursion
                              (org-end-of-subtree t t)
                              (point)))
                 (entry-text (buffer-substring entry-start entry-end)))
            ;; Delete entry from Capture
            (delete-region entry-start entry-end)
            ;; Clean up extra blank lines left behind
            (when (and (looking-at "\n") (save-excursion (forward-line -1) (looking-at "^$")))
              (delete-char 1))
            ;; Find target under * Recurring
            (goto-char (point-min))
            (when (re-search-forward "^\\* Recurring\\b" nil t)
              (let ((recurring-end (save-excursion
                                     (if (re-search-forward "^\\* " nil t)
                                         (line-beginning-position)
                                       (point-max)))))
                (when (re-search-forward
                       (format "^\\*\\* .*%s" (regexp-quote (org-link-display-format target)))
                       recurring-end t)
                  (let ((target-bol (line-beginning-position)))
                  (org-end-of-subtree t t)
                  ;; Demote: ** → ***, *** → ****, etc.
                  (let* ((demoted (replace-regexp-in-string
                                    "^\\(\\*+\\) " "*\\1 " entry-text))
                         ;; Strip trailing separators to avoid doubles
                         (demoted (replace-regexp-in-string
                                   "\\(\n*-+\n*\\)+\\'" "\n" demoted)))
                    ;; Ensure blank line before insertion
                    (unless (bolp) (insert "\n"))
                    (unless (save-excursion (forward-line -1) (looking-at "^$"))
                      (insert "\n"))
                    (insert demoted)
                    (unless (bolp) (insert "\n")))
                  ;; Remove any ----- lines between *** siblings in this subtree
                  (save-excursion
                    (goto-char target-bol)
                    (let ((sub-end (save-excursion (org-end-of-subtree t t) (point))))
                      (while (re-search-forward "^\\*\\*\\*+ " sub-end t)
                        (save-excursion
                          (forward-line -1)
                          (while (and (> (point) (point-min))
                                      (looking-at-p "^[ \t]*$"))
                            (forward-line -1))
                          (when (looking-at-p "^-+$")
                            (let ((sep-start (line-beginning-position))
                                  (sep-end (progn (forward-line 1)
                                                  (while (looking-at-p "^[ \t]*$")
                                                    (forward-line 1))
                                                  (point))))
                              (delete-region sep-start sep-end)
                              ;; Ensure a blank line remains between siblings
                              (unless (save-excursion (forward-line -1) (looking-at-p "^[ \t]*$"))
                                (insert "\n")
                                (setq sub-end (1+ sub-end)))
                              (setq sub-end (- sub-end (- sep-end sep-start)))))))))))))))))))

(defun aj/dailies-reposition-entry ()
  "Setup daily file after capture.
Inserts week transclude, ensures heading structure, and populates content.
Entries are placed under * Capture by the capture template."
  (when aj/--dailies-capture-file
    (let ((file aj/--dailies-capture-file))
      (with-current-buffer (find-file-noselect file)
        ;; 1. Insert week transclude if not present
        ;; Check both raw directive AND rendered heading (in case transclusion already active)
        (save-excursion
          (goto-char (point-min))
          (unless (or (re-search-forward "^#\\+transclude:" nil t)
                      (progn (goto-char (point-min))
                             (re-search-forward "^\\* \\(\\[\\[id:[^]]+\\]\\[\\)?Week [0-9]+" nil t)))
            (aj/insert-week-transclude)))
        ;; 2. Ensure all headings exist in correct order (with statistics cookies)
        (aj/ensure-daily-structure)
        ;; 3. Update statistics cookies (stripped before capture, restored here)
        (org-update-statistics-cookies t)
        ;; 4. Refresh recurring tasks
        (aj/refresh-daily-recurring)
        ;; 4b. Re-run heading separators after recurring content is inserted
        ;; (recurring tasks may have displaced the separators)
        (aj/ensure-heading-separators)
        (aj/ensure-recurring-separators)
        ;; 4c. Bring forward overdue captures from previous days
        (aj/bring-forward-overdue-captures)
        ;; 4d. Bring forward overdue priority tasks from previous days' Recurring
        (aj/bring-forward-overdue-recurring)
        (aj/ensure-recurring-separators)
        ;; 5. Move captured entry if user chose a Recurring target
        (when (and aj/--dailies-capture-target
                   aj/--dailies-capture-heading
                   (not (equal aj/--dailies-capture-target "Capture")))
          (aj/dailies-move-capture-to-recurring
           aj/--dailies-capture-target
           aj/--dailies-capture-heading)
          (aj/ensure-heading-separators)
          (aj/ensure-recurring-separators)
          (org-update-statistics-cookies t))
        ;; 5b. Insert calendar content
        (save-excursion
          (goto-char (point-min))
          ;; Only insert calendar content if heading is empty
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
        ;; 6. Activate org-transclusion-mode to render the transclude
        (when (and (fboundp 'org-transclusion-mode)
                   (not (bound-and-true-p org-transclusion-mode)))
          (org-transclusion-mode 1))
        (save-buffer)))))

;; ---------------------------------------------------------------------------
;; Calendar & Weather
;; ---------------------------------------------------------------------------

(defun my/parse-cal-days (line)
  "Parse a cal output LINE into a list of 7 day values (nil for empty)."
  (let ((days '())
        (padded (concat line "                    ")))
    (dotimes (i 7)
      (let* ((start (* i 3))
             (day-str (string-trim (substring padded start (+ start 2)))))
        (push (if (string-empty-p day-str) nil (string-to-number day-str)) days)))
    (nreverse days)))

(defun my/format-day-cal-header (target-dow)
  "Format day names header with widened column for TARGET-DOW (0=Sun, 6=Sat).
Widened column: 6 chars (or 5 if last). Column before widened: no trailing space."
  (let ((day-names ["Su" "Mo" "Tu" "We" "Th" "Fr" "Sa"])
        (result "   "))
    (dotimes (dow 7)
      (let* ((name (aref day-names dow))
             (is-widened (= dow target-dow))
             (is-before-widened (and (> target-dow 0) (= dow (1- target-dow))))
             (is-last (= dow 6)))
        (setq result
              (concat result
                      (cond
                       ;; Widened column: "  XX  " (6) or "  XX " (5 if last)
                       (is-widened (if is-last (format "  %s " name) (format "  %s  " name)))
                       ;; Before widened: no trailing space (absorbed by widened)
                       (is-before-widened (format "%s" name))
                       ;; Normal last
                       (is-last name)
                       ;; Normal column
                       (t (format "%s " name)))))))
    result))

(defun my/format-day-cal-line (days target-day target-dow)
  "Format calendar data line with widened TARGET-DOW column and bolded TARGET-DAY.
DAYS is a list of 7 day numbers (nil for empty).
Widened column: 6 chars (or 5 if last). Column before widened: no trailing space."
  (let ((result "   "))
    (dotimes (dow 7)
      (let* ((day-val (nth dow days))
             (is-widened (= dow target-dow))
             (is-before-widened (and (> target-dow 0) (= dow (1- target-dow))))
             (is-target (and day-val (= day-val target-day)))
             (is-last (= dow 6)))
        (setq result
              (concat result
                      (cond
                       ;; Widened column: " *DD* " (6) or " *DD*" (5 if last)
                       (is-widened
                        (cond
                         ;; Bold last: " *7* " (5) or " *12*" (5)
                         ((and is-target is-last)
                          (if (< day-val 10) (format " *%d* " day-val) (format " *%d*" day-val)))
                         ;; Bold non-last: "  *7* " (6) or " *12* " (6)
                         (is-target
                          (if (< day-val 10) (format "  *%d* " day-val) (format " *%d* " day-val)))
                         ((and day-val is-last) (format "  %2d " day-val))
                         (day-val (format "  %2d  " day-val))
                         (is-last "     ")
                         (t "      ")))
                       ;; Before widened: no trailing space
                       (is-before-widened
                        (if day-val (format "%2d" day-val) "  "))
                       ;; Normal last column
                       (is-last (if day-val (format "%2d" day-val) "  "))
                       ;; Normal column
                       (t (if day-val (format "%2d " day-val) "   ")))))))
    result))

(defun my/format-number-with-commas (n)
  "Format integer N with comma thousand separators."
  (let ((s (number-to-string n)))
    (while (string-match "\\(.*[0-9]\\)\\([0-9]\\{3\\}\\)\\'" s)
      (setq s (concat (match-string 1 s) "," (match-string 2 s))))
    s))

(defun aj/ensure-daily-id (date-str)
  "Ensure daily note exists for DATE-STR (YYYY-MM-DD). Returns org-roam ID.
Creates a minimal file with just ID and title if it doesn't exist.
Does not run hooks or add headings - those are added when the file is opened."
  (require 'org-roam)
  (require 'org-id)
  (let* ((parts (split-string date-str "-"))
         (year (string-to-number (nth 0 parts)))
         (month (string-to-number (nth 1 parts)))
         (day (string-to-number (nth 2 parts)))
         (date-time (encode-time 0 0 0 day month year))
         (day-name (format-time-string "%A" date-time))
         (daily-dir (expand-file-name
                     (or org-roam-dailies-directory "daily")
                     org-roam-directory))
         (file-path (expand-file-name (concat date-str ".org") daily-dir)))
    ;; Create minimal file if it doesn't exist
    (unless (file-exists-p file-path)
      (let ((id (org-id-uuid)))
        (make-directory daily-dir t)
        (with-temp-file file-path
          ;; Naked file: just properties and title, no headings
          (insert (format ":PROPERTIES:\n:ID:       %s\n:END:\n#+title: %s | %s\n#+EXPORT_FILE_NAME: %s\n"
                          id date-str day-name date-str)))
        ;; Update org-roam database for new file
        (org-roam-db-update-file file-path)))
    ;; Get ID from org-roam database
    (caar (org-roam-db-query
           [:select id :from nodes :where (= file $s1)]
           file-path))))

(defun my/format-day-cell (day-num target-day year month)
  "Format a calendar day cell for org table with ID links.
DAY-NUM is the day number (or nil for empty).
TARGET-DAY is the current day (bolded, no link).
YEAR and MONTH are used to build the ID link."
  (if (null day-num)
      "   "
    (if (= day-num target-day)
        ;; Current day: bold, no link
        (if (< day-num 10)
            (format "*%d*  " day-num)
          (format "*%d* " day-num))
      ;; Other days: get/create daily and link by ID
      (let* ((date-str (format "%04d-%02d-%02d" year month day-num))
             (id (aj/ensure-daily-id date-str))
             (link (format "[[id:%s][%d]]" id day-num)))
        (if (< day-num 10)
            (format "%s  " link)
          (format "%s " link))))))

(defun my/insert-aj-day-calendar ()
  "Insert formatted calendar for a daily org-roam note with life stats.
Parses date from #+title: YYYY-MM-DD line.
Outputs an org table with links to daily files.
Σ column: Day of year (cumulative days elapsed in current year).
ω column: Days elapsed since December 26, 2001 (AJ's birthday)."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^#\\+title: \\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" nil t)
      (let* ((date-str (match-string 1))
             (parts (split-string date-str "-"))
             (year (string-to-number (nth 0 parts)))
             (month (string-to-number (nth 1 parts)))
             (day (string-to-number (nth 2 parts)))
             (date (encode-time 0 0 0 day month year))
             ;; Birthday: December 26, 2001
             (birthday (encode-time 0 0 0 26 12 2001))
             (cal-output (shell-command-to-string (format "cal %d %d" month year)))
             (lines (split-string cal-output "\n")))

        ;; Ensure Calendar heading exists at correct position
        (aj/ensure-heading-exists "Calendar")
        ;; Find it and clear existing content
        (goto-char (point-min))
        (when (re-search-forward "^\\* Calendar\\b" nil t)
          (let ((heading-end (line-end-position))
                (section-end (save-excursion
                               (forward-line 1)
                               (if (re-search-forward "^\\* " nil t)
                                   (line-beginning-position)
                                 (point-max)))))
            (delete-region (1+ heading-end) section-end))
          (goto-char (line-end-position))
          (insert "\n\n"))

        ;; Caption with month name
        (let ((month-name (format-time-string "%B %Y" date)))
          (insert (format "#+CAPTION: %s\n" month-name)))

        ;; Table header with top border
        (insert "|----+----+----+----+----+----+----+-------+--------|\n")
        (insert "| Su | Mo | Tu | We | Th | Fr | Sa | Σ(wk) | ω(dol) |\n")
        (insert "|----+----+----+----+----+----+----+-------+--------|\n")

        ;; Day rows
        (let ((week-num 0))
          (dolist (line (nthcdr 2 lines))
            (when (string-match "[0-9]" line)
              (setq week-num (1+ week-num))
              (let* ((days (my/parse-cal-days line))
                     (last-day (car (last (remq nil days))))
                     (date-end (encode-time 0 0 0 last-day month year))
                     ;; Days alive: difference from birthday to date-end
                     (days-alive (floor (/ (float-time (time-subtract date-end birthday)) 86400))))
                ;; Build table row with linked days
                (insert "|")
                (dotimes (dow 7)
                  (insert " " (my/format-day-cell (nth dow days) day year month) "|"))
                (insert (format " %5d | %s |\n" week-num (my/format-number-with-commas days-alive)))))))

        ;; Bottom border
        (insert "|----+----+----+----+----+----+----+-------+--------|\n")

        ;; Align the table - must be inside table, not on border
        (forward-line -2)
        (org-table-align)

        ;; Fetch weather asynchronously and insert when ready
        (aj/fetch-calendar-weather-async date-str (current-buffer))))))

;; ---------------------------------------------------------------------------
;; OpenWeatherMap for Calendar (uses API key from authinfo.gpg)
;; ---------------------------------------------------------------------------

(defun aj/get-location-from-file ()
  "Read location from ~/.weather-location if it exists.
Returns (lat lon name) or nil."
  (when (file-exists-p aj/weather-location-file)
    (with-temp-buffer
      (insert-file-contents aj/weather-location-file)
      (let ((content (string-trim (buffer-string))))
        (when (string-match "^\\(-?[0-9.]+\\)\\s-+\\(-?[0-9.]+\\)\\s-+\\(.+\\)$" content)
          (list (string-to-number (match-string 1 content))
                (string-to-number (match-string 2 content))
                (string-trim (match-string 3 content))))))))

(defun aj/get-location-from-ip ()
  "Get current location from IP geolocation (ip-api.com).
Returns (lat lon name) or nil on failure."
  (condition-case err
      (let ((url-request-method "GET")
            (url-show-status nil))
        (with-current-buffer
            (url-retrieve-synchronously "http://ip-api.com/json/?fields=lat,lon,city,regionName" t t 5)
          (goto-char (point-min))
          (when (re-search-forward "\n\n" nil t)
            (let* ((json-object-type 'alist)
                   (data (json-read))
                   (lat (alist-get 'lat data))
                   (lon (alist-get 'lon data))
                   (city (alist-get 'city data)))
              (when (and lat lon)
                (list lat lon (or city "Sydney")))))))
    (error
     (message "Location lookup failed: %s" err)
     nil)))

(defun aj/get-weather-location ()
  "Get weather location, preferring config file over IP geolocation.
Returns (lat lon name) or defaults to Sydney CBD."
  (let* ((now (float-time))
         (cache-valid (and aj/weather-location-cache
                           (< (- now (car aj/weather-location-cache))
                              aj/weather-location-cache-duration))))
    (if cache-valid
        (cdr aj/weather-location-cache)
      ;; Try config file first, then IP geolocation
      (let ((location (or (aj/get-location-from-file)
                          (aj/get-location-from-ip)
                          (list -33.8688 151.2093 "Sydney"))))
        (setq aj/weather-location-cache (cons now location))
        location))))

(defun aj/sync-weather-archive ()
  "Sync weather archive from remote server."
  (interactive)
  (make-directory aj/weather-archive-local t)
  (let ((proc (start-process "weather-sync" nil
                             "rsync" "-az"
                             aj/weather-archive-remote
                             aj/weather-archive-local)))
    (set-process-sentinel proc
                          (lambda (p e)
                            (when (string-match-p "finished" e)
                              (message "Weather archive synced"))))))

(defun aj/get-week-bounds (date-str)
  "Return (start-date . end-date) for the week containing DATE-STR.
Week runs Sunday to Saturday."
  (let* ((parts (split-string date-str "-"))
         (year (string-to-number (nth 0 parts)))
         (month (string-to-number (nth 1 parts)))
         (day (string-to-number (nth 2 parts)))
         (date (encode-time 0 0 0 day month year))
         (dow (string-to-number (format-time-string "%w" date)))
         (week-start (time-subtract date (days-to-time dow)))
         (week-end (time-add week-start (days-to-time 6))))
    (cons (format-time-string "%Y-%m-%d" week-start)
          (format-time-string "%Y-%m-%d" week-end))))

(defun aj/read-archive-weather (date-str)
  "Read archived weather for DATE-STR from local cache. Returns alist or nil."
  (let ((file (expand-file-name (concat date-str ".json") aj/weather-archive-local)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (let ((json-object-type 'alist)
              (json-array-type 'list))
          (condition-case nil
              (json-read)
            (error nil)))))))

(defun aj/read-weather-location-name ()
  "Read location name from cached location.json. Returns string or nil."
  (let ((file (expand-file-name "location.json" aj/weather-archive-local)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (let ((json-object-type 'alist))
          (condition-case nil
              (alist-get 'name (json-read))
            (error nil)))))))

(defun aj/get-openweather-api-key ()
  "Get OpenWeatherMap API key from authinfo.gpg."
  (require 'auth-source)
  (let ((auth (car (auth-source-search :host "api.openweathermap.org"
                                       :require '(:secret)))))
    (when auth
      (let ((secret (plist-get auth :secret)))
        (if (functionp secret)
            (funcall secret)
          secret)))))

(defun aj/openweather-icon (condition)
  "Map OpenWeatherMap weather condition to emoji."
  (pcase condition
    ("Clear" "☀️")
    ("Clouds" "☁️")
    ("Rain" "🌧️")
    ("Drizzle" "🌦️")
    ("Thunderstorm" "⛈️")
    ("Snow" "❄️")
    ((or "Mist" "Fog" "Haze" "Smoke" "Dust" "Sand" "Ash" "Squall" "Tornado") "🌫️")
    (_ "🌡️")))

(defun aj/calculate-moon-phase (year month day)
  "Calculate moon phase for given date. Returns string with emoji and name."
  (let* ((y (if (<= month 2) (1- year) year))
         (m (if (<= month 2) (+ month 12) month))
         (c (/ y 100))
         (e (+ (- 2 c) (/ c 4)))
         (jd (+ (floor (* 365.25 (+ y 4716)))
                (floor (* 30.6001 (+ m 1)))
                day e -1524.5))
         (phase-raw (mod (- jd 2451550.1) 29.530588853))
         (phase-idx (floor (* (/ phase-raw 29.530588853) 8))))
    (pcase phase-idx
      (0 "🌑 New Moon")
      (1 "🌒 Waxing Crescent")
      (2 "🌓 First Quarter")
      (3 "🌔 Waxing Gibbous")
      (4 "🌕 Full Moon")
      (5 "🌖 Waning Gibbous")
      (6 "🌗 Last Quarter")
      (7 "🌘 Waning Crescent")
      (_ "🌑 New Moon"))))

(defun aj/format-unix-time (unix-time format-string)
  "Format UNIX-TIME timestamp using FORMAT-STRING."
  (format-time-string format-string (seconds-to-time unix-time)))

(defun aj/parse-weather-week-from-cache (target-date)
  "Parse weather for the full week (Sun-Sat) containing TARGET-DATE.
Reads from local cache files synced from server.
The '<-- today' marker indicates TARGET-DATE (the file's date), not actual today."
  (let* ((bounds (aj/get-week-bounds target-date))
         (week-start (car bounds))
         (lines '())
         (current-date week-start))
    ;; Iterate through each day of the week (Sun-Sat)
    (dotimes (_ 7)
      (let* ((d-parts (split-string current-date "-"))
             (d-year (string-to-number (nth 0 d-parts)))
             (d-month (string-to-number (nth 1 d-parts)))
             (d-day (string-to-number (nth 2 d-parts)))
             (date-time (encode-time 0 0 0 d-day d-month d-year))
             (day-name (format-time-string "%a" date-time))
             ;; Mark the file's date, not actual today
             (is-file-date (string= current-date target-date))
             ;; Read from cache (server provides both historical and forecast)
             (archive (aj/read-archive-weather current-date))
             weather-info)
        (when archive
          (setq weather-info (list :temp (alist-get 'temp archive)
                                  :min (alist-get 'temp_min archive)
                                  :max (alist-get 'temp_max archive)
                                  :cond (alist-get 'condition archive))))
        ;; Format the line
        (if weather-info
            (let ((emoji (aj/openweather-icon (plist-get weather-info :cond)))
                  (today-marker (if is-file-date " ← today" "")))
              (push (format "- %s %d: %s %d°C (%d-%d°C)%s"
                            day-name d-day emoji
                            (floor (plist-get weather-info :temp))
                            (floor (plist-get weather-info :min))
                            (floor (plist-get weather-info :max))
                            today-marker)
                    lines))
          ;; No data available
          (push (format "- %s %d: —%s" day-name d-day (if is-file-date " ← today" "")) lines))
        ;; Move to next day
        (setq current-date
              (format-time-string "%Y-%m-%d"
                                 (time-add date-time (days-to-time 1))))))
    (string-join (nreverse lines) "\n")))

(defun aj/read-forecast-latest ()
  "Read the forecast-latest.json from local cache. Returns alist or nil."
  (let ((file (expand-file-name "forecast-latest.json" aj/weather-archive-local)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (let ((json-object-type 'alist)
              (json-array-type 'list))
          (condition-case nil
              (json-read)
            (error nil)))))))

(defun aj/insert-weather-from-cache (buffer date-str)
  "Insert weather content into BUFFER's Calendar section from local cache.
Weather is relative to DATE-STR (the file's date), not today's date."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward "^\\* Calendar\\b" nil t)
          (let ((section-end (copy-marker
                              (save-excursion
                                (forward-line 1)
                                (if (re-search-forward "^\\* " nil t)
                                    (1- (line-beginning-position))
                                  (point-max))))))
            ;; Remove existing weather lines
            (save-excursion
              (goto-char (point-min))
              (when (re-search-forward "^\\* Calendar\\b" nil t)
                (while (re-search-forward "^\\(.+ forecast:\\|forecast:\\|today:\\|sun:\\|moon:\\)" section-end t)
                  (let ((line-start (line-beginning-position)))
                    (forward-line 1)
                    (when (string-match-p "forecast:" (match-string 0))
                      (while (and (< (point) section-end)
                                  (looking-at "^\\(  \\|- \\)"))
                        (forward-line 1)))
                    (delete-region line-start (point))))))
            ;; Go to end of section
            (goto-char section-end)
            ;; Read from cache - only insert forecast (sun/moon/conditions now in hourly table)
            (let ((forecast-str (aj/parse-weather-week-from-cache date-str))
                  (location-name (or (aj/read-weather-location-name) "Sydney")))
              (unless (bolp) (insert "\n"))
              (insert (format "\n%s forecast:\n" location-name) forecast-str "\n"))))))))

(defun aj/fetch-calendar-weather-async (date-str buffer)
  "Fetch fresh weather from server and insert into BUFFER's Calendar section.
Detects location from ~/.weather-location or IP, runs weather script on server,
syncs data, then inserts."
  (let* ((location (aj/get-weather-location))
         (lat (number-to-string (nth 0 location)))
         (lon (number-to-string (nth 1 location)))
         (name (nth 2 location)))
    (message "Weather: fetching for %s (%s, %s)..." name lat lon)
    (make-directory aj/weather-archive-local t)
    ;; Step 1: Run weather script on server with location args
    (let ((fetch-proc (start-process "weather-fetch" "*weather-fetch*"
                                     "ssh" "root@abaj.ai"
                                     (format "/root/scripts/weather-archive.sh %s %s '%s'"
                                             lat lon name))))
      (set-process-sentinel
       fetch-proc
       (lambda (p e)
         (if (not (string-match-p "finished" e))
             (message "Weather: server fetch failed - %s" (string-trim e))
           (message "Weather: server updated, syncing...")
           ;; Step 2: Sync from server
           (let ((sync-proc (start-process "weather-sync" nil
                                           "rsync" "-az"
                                           aj/weather-archive-remote
                                           aj/weather-archive-local)))
             (set-process-sentinel
              sync-proc
              (lambda (p2 e2)
                (if (not (string-match-p "finished" e2))
                    (message "Weather: sync failed - %s" (string-trim e2))
                  (message "Weather: inserting into buffer...")
                  (when (buffer-live-p buffer)
                    (aj/insert-weather-from-cache buffer date-str)
                    (aj/insert-hourly-weather-table buffer date-str)
                    (with-current-buffer buffer
                      (aj/ensure-heading-separators)
                      (aj/ensure-recurring-separators)
                      ;; Weather insertion splices content between a
                      ;; pre-existing `#+LATEX: \newpage' and its heading,
                      ;; orphaning the directive inside the Calendar section.
                      ;; Re-run the sweeper so Phase 1 deletes the orphan
                      ;; and Phase 2 re-inserts canonically above the heading.
                      (aj/ensure-heading-newpages))
                    (message "Weather: done for %s ✓" name))))))))))))

(defun aj/fetch-calendar-weather-sync (date-str buffer)
  "Synchronous version of `aj/fetch-calendar-weather-async'.
Blocks until weather-archive.sh + rsync complete, then inserts weather
and the hourly table into BUFFER. Used by cron/batch export where the
buffer must be complete before `save-buffer' runs — the async variant
saves before the weather callback fires, so the weather never makes it
to disk.

On any step failure, falls back to whatever is already in the local
cache so the calendar still has the most recent available weather."
  (let* ((location (aj/get-weather-location))
         (lat  (number-to-string (nth 0 location)))
         (lon  (number-to-string (nth 1 location)))
         (name (nth 2 location)))
    (make-directory aj/weather-archive-local t)
    ;; Step 1: ask server for fresh data. Short SSH timeout so cron
    ;; doesn't hang if abaj.ai is unreachable.
    (let ((fetch-code
           (call-process "ssh" nil nil nil
                         "-o" "ConnectTimeout=5"
                         "root@abaj.ai"
                         (format "/root/scripts/weather-archive.sh %s %s '%s'"
                                 lat lon name))))
      (unless (zerop fetch-code)
        (message "Weather (sync): server fetch failed (exit %d) — using stale cache"
                 fetch-code)))
    ;; Step 2: rsync, regardless of fetch outcome (pulls whatever's there)
    (let ((sync-code
           (call-process "rsync" nil nil nil "-az"
                         aj/weather-archive-remote
                         aj/weather-archive-local)))
      (unless (zerop sync-code)
        (message "Weather (sync): rsync failed (exit %d) — using stale cache"
                 sync-code)))
    ;; Step 3: insert from cache (works even if the fetch/rsync failed)
    (when (buffer-live-p buffer)
      (aj/insert-weather-from-cache buffer date-str)
      (aj/insert-hourly-weather-table buffer date-str)
      (with-current-buffer buffer
        (aj/ensure-heading-separators)
        (aj/ensure-recurring-separators)
        ;; Weather insertion splices content between a pre-existing
        ;; `#+LATEX: \newpage' and its heading, orphaning the directive.
        ;; Re-sweep so the orphan is deleted and a canonical directive
        ;; is re-inserted above the next heading.
        (aj/ensure-heading-newpages)))))

(defun aj/refresh-daily-calendar-sync ()
  "Like `aj/refresh-daily-calendar' but blocks until weather is inserted.
Intended for batch/cron: call this from the emacsclient eval before
`save-buffer' so the exported PDF has the weather content, not just the
synchronously-inserted date table."
  (interactive)
  (unless (aj/daily-date-file-p)
    (user-error "Not in a daily note"))
  (my/insert-aj-day-calendar)                 ; inserts table + starts async fetch
  (let ((date-str (file-name-base (buffer-file-name))))
    (aj/fetch-calendar-weather-sync date-str (current-buffer))))

;; ---------------------------------------------------------------------------
;; Hourly Weather Table
;; ---------------------------------------------------------------------------

(defun aj/read-hourly-weather (date-str)
  "Read hourly weather for DATE-STR from local cache. Returns alist or nil."
  (let ((file (expand-file-name (concat "hourly-" date-str ".json") aj/weather-archive-local)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (let ((json-object-type 'alist)
              (json-array-type 'list))
          (condition-case nil
              (json-read)
            (error nil)))))))

(defun aj/insert-hourly-weather-table (buffer date-str)
  "Insert hourly weather table and conditions table into BUFFER's Calendar section.
Works for any date that has archived hourly data, plus today/tomorrow from live forecast."
  (let* ((today-str (format-time-string "%Y-%m-%d"))
         (tomorrow-str (format-time-string "%Y-%m-%d" (time-add nil (* 24 60 60))))
         (is-today (string= date-str today-str))
         (is-tomorrow (string= date-str tomorrow-str))
         ;; First try archived data for specific date, then fall back to today's forecast
         (data (or (aj/read-hourly-weather date-str)
                   (when (or is-today is-tomorrow) (aj/read-hourly-weather today-str))))
         (forecast-file (expand-file-name "forecast-latest.json" aj/weather-archive-local))
         (forecast-data (when (file-exists-p forecast-file)
                          (condition-case nil
                              (json-read-file forecast-file)
                            (error nil)))))
    (when data
      (let ((hourly (alist-get 'hourly data))
            (tz-offset (or (alist-get 'timezone_offset data) 39600)))
        (when hourly
          (with-current-buffer buffer
            (save-excursion
              (goto-char (point-min))
              (when (re-search-forward "^\\* Calendar\\b" nil t)
                (let ((section-end (copy-marker
                                    (save-excursion
                                      (forward-line 1)
                                      (if (re-search-forward "^\\* " nil t)
                                          (1- (line-beginning-position))
                                        (point-max))))))
                  ;; Remove existing hourly table and conditions table
                  (save-excursion
                    (goto-char (point-min))
                    (when (re-search-forward "^hourly:" section-end t)
                      (let ((start (line-beginning-position)))
                        (forward-line 1)
                        (while (and (< (point) section-end)
                                    (or (looking-at "^|") (looking-at "^$")))
                          (forward-line 1))
                        (delete-region start (point)))))
                  ;; Remove old sun:/moon:/today: lines
                  (save-excursion
                    (goto-char (point-min))
                    (re-search-forward "^\\* Calendar\\b" nil t)
                    (while (re-search-forward "^\\(sun:\\|moon:\\|today:\\)" section-end t)
                      (delete-region (line-beginning-position) (1+ (line-end-position)))))
                  ;; Find insertion point after forecast block
                  (goto-char (point-min))
                  (re-search-forward "^\\* Calendar\\b" nil t)
                  (let ((insert-point
                         (or (save-excursion
                               (when (re-search-forward "^forecast:" section-end t)
                                 (forward-line 1)
                                 (while (and (< (point) section-end)
                                             (not (looking-at "^\\* \\|^hourly:\\|^$")))
                                   (forward-line 1))
                                 (point)))
                             section-end)))
                    (goto-char insert-point)
                    (unless (bolp) (insert "\n"))
                    ;; Build hourly data and collect daily stats
                    (let ((am-emoji (make-vector 12 nil))
                          (am-temp (make-vector 12 nil))
                          (pm-emoji (make-vector 12 nil))
                          (pm-temp (make-vector 12 nil))
                          (max-pop 0)
                          (max-uvi 0)
                          (total-humidity 0)
                          (total-wind 0)
                          (hour-count 0))
                      (dolist (hour-entry hourly)
                        (let* ((dt (alist-get 'dt hour-entry))
                               (local-time (+ dt tz-offset))
                               (hour (mod (/ local-time 3600) 24))
                               (entry-date (format-time-string "%Y-%m-%d" (seconds-to-time dt)))
                               (temp (round (alist-get 'temp hour-entry)))
                               (weather (car (alist-get 'weather hour-entry)))
                               (condition (alist-get 'main weather))
                               (emoji (aj/openweather-icon condition))
                               (pop (or (alist-get 'pop hour-entry) 0))
                               (uvi (or (alist-get 'uvi hour-entry) 0))
                               (humidity (or (alist-get 'humidity hour-entry) 0))
                               (wind (or (alist-get 'wind_speed hour-entry) 0)))
                          (when (string= entry-date date-str)
                            (setq hour-count (1+ hour-count))
                            (setq max-pop (max max-pop pop))
                            (setq max-uvi (max max-uvi uvi))
                            (setq total-humidity (+ total-humidity humidity))
                            (setq total-wind (+ total-wind wind))
                            (if (< hour 12)
                                (progn
                                  (aset am-emoji hour emoji)
                                  (aset am-temp hour (number-to-string temp)))
                              (aset pm-emoji (- hour 12) emoji)
                              (aset pm-temp (- hour 12) (number-to-string temp))))))
                      ;; Calculate averages and get sun/moon data
                      (let* ((avg-humidity (if (> hour-count 0) (/ total-humidity hour-count) 0))
                             (avg-wind (if (> hour-count 0) (/ total-wind hour-count) 0))
                             (current (alist-get 'current forecast-data))
                             (sunrise (alist-get 'sunrise current))
                             (sunset (alist-get 'sunset current))
                             (d-parts (split-string date-str "-"))
                             (year (string-to-number (nth 0 d-parts)))
                             (month (string-to-number (nth 1 d-parts)))
                             (day (string-to-number (nth 2 d-parts)))
                             (moon (aj/calculate-moon-phase year month day)))
                        ;; Insert hourly table
                        (insert "\nhourly:\n")
                        (insert "|----")
                        (dotimes (_ 12) (insert "+----"))
                        (insert "|\n")
                        (insert "| AM |")
                        (dotimes (h 12)
                          (insert (format " %2d |" (if (= h 0) 12 h))))
                        (insert "\n|----")
                        (dotimes (_ 12) (insert "+----"))
                        (insert "|\n")
                        ;; AM emoji row (blank first column)
                        (insert "|    |")
                        (dotimes (h 12)
                          (insert (format " %s |" (or (aref am-emoji h) "  "))))
                        (insert "\n")
                        ;; AM temp row
                        (insert "|    |")
                        (dotimes (h 12)
                          (insert (format " %s |" (or (aref am-temp h) "  "))))
                        (insert "\n|----")
                        (dotimes (_ 12) (insert "+----"))
                        (insert "|\n")
                        (insert "| PM |")
                        (dotimes (h 12)
                          (insert (format " %2d |" (if (= h 0) 12 h))))
                        (insert "\n|----")
                        (dotimes (_ 12) (insert "+----"))
                        (insert "|\n")
                        ;; PM emoji row (blank first column)
                        (insert "|    |")
                        (dotimes (h 12)
                          (insert (format " %s |" (or (aref pm-emoji h) "  "))))
                        (insert "\n")
                        ;; PM temp row
                        (insert "|    |")
                        (dotimes (h 12)
                          (insert (format " %s |" (or (aref pm-temp h) "  "))))
                        (insert "\n|----")
                        (dotimes (_ 12) (insert "+----"))
                        (insert "|\n")
                        ;; Align hourly table
                        (forward-line -2)
                        (org-table-align)
                        ;; Move past hourly table for conditions table
                        (goto-char insert-point)
                        (when (re-search-forward "^hourly:" section-end t)
                          (while (and (< (point) section-end) (looking-at "\\|^|"))
                            (forward-line 1))
                          (forward-line 1)
                          (while (and (< (point) section-end) (looking-at "^|"))
                            (forward-line 1)))
                        ;; Insert conditions table
                        (insert "\n|----------+-------------------|\n")
                        (insert (format "| sun      | ↑ %s  ↓ %s |\n"
                                        (if sunrise (aj/format-unix-time sunrise "%H:%M") "--:--")
                                        (if sunset (aj/format-unix-time sunset "%H:%M") "--:--")))
                        (insert (format "| moon     | %s |\n" moon))
                        (insert "|----------+-------------------|\n")
                        (insert (format "| rain     | %3d%% |\n" (round (* 100 max-pop))))
                        (insert "|----------+-------------------|\n")
                        (insert (format "| UV       | %3d |\n" (round max-uvi)))
                        (insert "|----------+-------------------|\n")
                        (insert (format "| humidity | %3d%% |\n" (round avg-humidity)))
                        (insert "|----------+-------------------|\n")
                        (insert (format "| wind     | %3d km/h |\n" (round (* 3.6 avg-wind))))
                        (insert "|----------+-------------------|\n")
                        ;; Align conditions table
                        (forward-line -2)
                        (org-table-align)))))))))))))

;; ---------------------------------------------------------------------------
;; Daily Lifecycle & Navigation
;; ---------------------------------------------------------------------------

(defun aj/refresh-daily-week ()
  "Refresh the week transclude for the current daily note.
Ensures the transclude exists and re-folds the heading.
Weather is now part of the Calendar section - use C-c d r c to refresh."
  (interactive)
  (unless (aj/daily-date-file-p)
    (user-error "Not in a daily note"))
  ;; Ensure week transclude exists
  (save-excursion
    (goto-char (point-min))
    (unless (or (re-search-forward "^#\\+transclude:" nil t)
                (progn (goto-char (point-min))
                       (re-search-forward "^\\* \\(\\[\\[id:[^]]+\\]\\[\\)?Week [0-9]+" nil t)))
      (aj/insert-week-transclude)))
  ;; Ensure transclusion is active
  (when (and (fboundp 'org-transclusion-mode)
             (not (bound-and-true-p org-transclusion-mode)))
    (org-transclusion-mode 1))
  ;; Re-fold the week heading
  (aj/fold-week-heading)
  (message "Week transclude refreshed"))

(defun aj/refresh-daily-calendar ()
  "Refresh calendar section for the current daily note.
Inserts calendar table and fetches weather data (including hourly if available)."
  (interactive)
  (unless (aj/daily-date-file-p)
    (user-error "Not in a daily note"))
  (my/insert-aj-day-calendar)
  (message "Calendar refreshed"))

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

;; Strip statistics cookies from olp headings in daily files before org-roam
;; does heading matching, so that "* Capture [4/4]" still matches olp "Capture".
;; Cookies are restored by aj/dailies-reposition-entry after capture finalize.
(defun aj/strip-cookies-for-olp (orig-fn olp)
  "Around advice: strip statistics cookies in daily files before OLP matching."
  (when (and buffer-file-name
             (string-match-p "/daily/" buffer-file-name))
    (save-excursion
      (dolist (heading olp)
        (goto-char (point-min))
        (let ((re (format "^\\(\\*+ %s\\) \\[[0-9]*[/%%][0-9]*\\]"
                          (regexp-quote heading))))
          (when (re-search-forward re nil t)
            (replace-match (match-string 1)))))))
  (funcall orig-fn olp))

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

;; Create refresh keymap: C-c d r <key>
(defvar aj/daily-refresh-map (make-sparse-keymap)
  "Keymap for daily refresh operations under C-c d r.")
(defun aj/under-heading-p (heading-re)
  "Return non-nil if point is within the section of HEADING-RE."
  (save-excursion
    (let ((pos (point)))
      (goto-char (point-min))
      (and (re-search-forward heading-re nil t)
           (let* ((start (line-beginning-position))
                  (level (org-current-level))
                  (end-re (format "^\\*\\{1,%d\\} " level))
                  (end (save-excursion
                         (forward-line 1)
                         (if (re-search-forward end-re nil t)
                             (line-beginning-position)
                           (point-max)))))
             (and (>= pos start) (< pos end)))))))

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

;; Dailies capture template with day of week
;; Entries go under * Capture heading; other sections inserted by hook
(setq org-roam-dailies-capture-templates
      '(("d" "default" entry
         "** %(aj/dailies-entry-prefix)%?"
         :target (file+head+olp "%<%Y-%m-%d>.org"
                                "#+title: %<%Y-%m-%d> | %<%A>\n#+EXPORT_FILE_NAME: %<%Y-%m-%d>\n"
                                ("Capture"))
         :empty-lines-before 1)))

;; ---------------------------------------------------------------------------
;; Hooks & Advice
;; ---------------------------------------------------------------------------

(advice-add 'org-roam-capture--find-or-create-olp :around #'aj/strip-cookies-for-olp)

;; Suppress daily-file-open-hook during org-capture to prevent side-effects
;; (e.g. bring-forward-overdue cancelling source items while capturing).
;; Only suppressed for actual captures, not goto (C-c d d) operations.
(defun aj/suppress-daily-hook-during-capture (orig-fn &rest args)
  "Advise org-capture to suppress `aj/daily-file-open-hook'."
  (let ((aj/daily-hook-suppress t))
    (apply orig-fn args)))
(advice-add 'org-capture :around #'aj/suppress-daily-hook-during-capture)

(defun aj/suppress-daily-hook-during-roam-capture (orig-fn time &optional goto-p &rest args)
  "Advise `org-roam-dailies--capture' to suppress hook only for captures, not gotos."
  (if goto-p
      (apply orig-fn time goto-p args)
    (let ((aj/daily-hook-suppress t))
      (apply orig-fn time goto-p args))))
(advice-add 'org-roam-dailies--capture :around #'aj/suppress-daily-hook-during-roam-capture)

(add-hook 'org-capture-before-finalize-hook #'aj/dailies-track-file)
(add-hook 'org-capture-before-finalize-hook #'aj/dailies-store-capture-marker)
(add-hook 'org-capture-before-finalize-hook #'aj/dailies-prompt-target-heading t)
(add-hook 'org-capture-after-finalize-hook #'aj/dailies-reposition-entry)
(add-hook 'org-capture-after-finalize-hook #'aj/dailies-prompt-jump-to-capture t)
;; Fold Week heading when opening daily files
(add-hook 'org-roam-dailies-find-file-hook #'aj/daily-file-open-hook)

;; ---------------------------------------------------------------------------
;; Mode-line Weather Display (fully async)
;; ---------------------------------------------------------------------------

(defvar aj/wttr-location "Sydney"
  "Location for weather forecast (city name).")

(defun aj/wttr-icon (description)
  "Return a weather icon based on DESCRIPTION string."
  (let ((desc (downcase description)))
    (cond
     ((string-match-p "thunder\\|storm" desc) "⛈️")
     ((string-match-p "snow\\|sleet\\|blizzard" desc) "🌨️")
     ((string-match-p "heavy.*rain\\|pour\\|torrential" desc) "🌧️")
     ((string-match-p "rain\\|drizzle\\|shower" desc) "🌦️")
     ((string-match-p "fog\\|mist\\|haze" desc) "🌫️")
     ((string-match-p "cloudy\\|overcast" desc) "☁️")
     ((string-match-p "partly\\|partial" desc) "⛅")
     ((string-match-p "clear\\|sunny\\|sun" desc) "☀️")
     (t "🌡️"))))

(defvar aj/modeline-weather-cache nil
  "Cached weather data: (date-str . formatted-string).")

(defvar aj/modeline-weather-cache-time nil
  "Time when weather cache was last updated.")

(defvar aj/modeline-weather-cache-duration 600
  "Seconds to cache weather data (default 10 minutes).")

(defvar aj/modeline-weather-fetching nil
  "Non-nil when weather fetch is in progress.")

(defun aj/parse-wttr-modeline-data (data target-date)
  "Parse wttr.in DATA and return formatted modeline string for TARGET-DATE."
  (let ((today (format-time-string "%Y-%m-%d"))
        (weather-days (alist-get 'weather data)))
    (if (string= target-date today)
        ;; Today: use current conditions
        (let* ((current (car (alist-get 'current_condition data)))
               (temp (alist-get 'temp_C current))
               (desc (alist-get 'weatherDesc current))
               (weather-desc (alist-get 'value (car desc)))
               (icon (aj/wttr-icon weather-desc))
               (today-forecast (car weather-days))
               (min-temp (alist-get 'mintempC today-forecast))
               (max-temp (alist-get 'maxtempC today-forecast)))
          (format "%s %s°C (%s-%s)" icon temp min-temp max-temp))
      ;; Other date: look in forecast
      (let ((result nil))
        (dolist (day weather-days)
          (when (string= (alist-get 'date day) target-date)
            (let* ((max-temp (alist-get 'maxtempC day))
                   (min-temp (alist-get 'mintempC day))
                   (hourly (alist-get 'hourly day))
                   (midday (or (nth 4 hourly) (nth 2 hourly) (car hourly)))
                   (desc (alist-get 'weatherDesc midday))
                   (weather-desc (alist-get 'value (car desc)))
                   (icon (aj/wttr-icon weather-desc)))
              (setq result (format "%s %s°C (%s-%s)" icon max-temp min-temp max-temp)))))
        result))))

(defun aj/modeline-weather-date ()
  "Return the date to show weather for.
In daily files: returns that file's date.
Otherwise: returns today's date."
  (if (and buffer-file-name (aj/daily-date-file-p))
      (save-excursion
        (goto-char (point-min))
        (if (re-search-forward "^#\\+title: \\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" nil t)
            (match-string-no-properties 1)
          (format-time-string "%Y-%m-%d")))
    (format-time-string "%Y-%m-%d")))

(defun aj/modeline-weather-update ()
  "Fetch weather asynchronously and update cache."
  (unless aj/modeline-weather-fetching
    (setq aj/modeline-weather-fetching t)
    (let ((target-date (format-time-string "%Y-%m-%d"))
          (url (format "https://wttr.in/%s?format=j1"
                       (url-hexify-string aj/wttr-location))))
      (url-retrieve
       url
       (lambda (status target-date)
         (unwind-protect
             (unless (plist-get status :error)
               (goto-char (point-min))
               (when (re-search-forward "\n\n" nil t)
                 (condition-case nil
                     (let* ((json-object-type 'alist)
                            (json-array-type 'list)
                            (data (json-read))
                            (weather (aj/parse-wttr-modeline-data data target-date)))
                       (when weather
                         (setq aj/modeline-weather-cache (cons target-date weather))
                         (setq aj/modeline-weather-cache-time (float-time))
                         (force-mode-line-update t)))
                   (error nil))))
           (setq aj/modeline-weather-fetching nil)
           (kill-buffer)))
       (list target-date)
       t t))))

(defun aj/modeline-weather ()
  "Return weather string for modeline, using cache when possible."
  (let* ((target-date (aj/modeline-weather-date))
         (now (float-time))
         (cache-valid (and aj/modeline-weather-cache
                           aj/modeline-weather-cache-time
                           (string= (car aj/modeline-weather-cache) target-date)
                           (< (- now aj/modeline-weather-cache-time)
                              aj/modeline-weather-cache-duration))))
    (if cache-valid
        (concat " " (cdr aj/modeline-weather-cache))
      ;; Trigger background fetch if not already running
      (unless aj/modeline-weather-fetching
        (run-with-idle-timer 1 nil #'aj/modeline-weather-update))
      ;; Return cached value (possibly stale) or empty while fetching
      (if aj/modeline-weather-cache
          (concat " " (cdr aj/modeline-weather-cache))
        ""))))

(defvar aj/modeline-weather-construct
  '(:eval (aj/modeline-weather))
  "Mode line construct for weather display.")

;; Ensure global-mode-string is a list before pushing
(unless (listp global-mode-string)
  (setq global-mode-string (list global-mode-string)))

;; Add to global mode line (like email)
(unless (member aj/modeline-weather-construct global-mode-string)
  (push aj/modeline-weather-construct global-mode-string))

;; Fetch weather on startup (like email updates counts on load)
(aj/modeline-weather-update)

;; ---------------------------------------------------------------------------
;; Current Hour Highlighting in Hourly Weather Table
;; ---------------------------------------------------------------------------

(defface aj/current-hour-face
  '((t :background "#2e7d32" :extend t))
  "Face for highlighting the current hour in the weather table.")

(defvar-local aj/hour-overlays nil
  "List of overlays for current hour highlighting.")

(defun aj/highlight-current-hour ()
  "Highlight the current hour column in the hourly weather table.
Only works for today's daily note."
  (when (aj/daily-date-file-p)
    (let* ((filename (file-name-sans-extension
                      (file-name-nondirectory (buffer-file-name))))
           (today-str (format-time-string "%Y-%m-%d")))
      ;; Only highlight if this is today's daily
      (when (string= filename today-str)
        ;; Remove old overlays
        (mapc #'delete-overlay aj/hour-overlays)
        (setq aj/hour-overlays nil)
        (save-excursion
          (goto-char (point-min))
          (when (re-search-forward "^hourly:" nil t)
            (let* ((now-hour (string-to-number (format-time-string "%H")))
                   (is-pm (>= now-hour 12))
                   (display-hour (mod now-hour 12))  ; 0-11, where 0 = 12 o'clock
                   (col-index (+ 2 display-hour))    ; +2 for AM/PM label + blank column
                   (table-start (point))
                   (table-end (save-excursion
                                (if (re-search-forward "^[^|]" nil t)
                                    (line-beginning-position)
                                  (point-max)))))
              ;; Find the right section (AM or PM)
              (when (re-search-forward (if is-pm "^| PM |" "^| AM |") table-end t)
                ;; Highlight header row (hour number), emoji row, and temp row
                ;; Row offsets: 0=header, 1=separator(skip), 2=emoji, 3=temp
                (dolist (row-offset '(0 2 3))
                  (beginning-of-line)
                  (forward-line row-offset)
                  (let ((line-end (line-end-position))
                        (col 0)
                        cell-start cell-end)
                    ;; Find the nth cell (col-index)
                    (goto-char (line-beginning-position))
                    (while (and (< col col-index) (< (point) line-end))
                      (when (search-forward "|" line-end t)
                        (setq col (1+ col))))
                    ;; Now point is after the | before our target cell
                    ;; Include the | to capture org-modern's table decoration
                    (when (= col col-index)
                      (setq cell-start (1- (point)))  ; include preceding |
                      (when (search-forward "|" line-end t)
                        (setq cell-end (point))       ; include trailing |
                        (let ((ov (make-overlay cell-start cell-end)))
                          (overlay-put ov 'face 'aj/current-hour-face)
                          (overlay-put ov 'priority 100)
                          (push ov aj/hour-overlays)))))
                  ;; Go back to header row for next iteration
                  (goto-char (line-beginning-position))
                  (forward-line (- row-offset)))))))))))

(defun aj/highlight-current-hour-if-daily ()
  "Highlight current hour if this is a daily org file."
  (when (and (derived-mode-p 'org-mode)
             (buffer-file-name)
             (aj/daily-date-file-p))
    (aj/highlight-current-hour)))

;; Add to daily file open hook
(add-hook 'org-roam-dailies-find-file-hook #'aj/highlight-current-hour)

;; Add to after-save-hook (buffer-local, only for daily files)
(defun aj/setup-hour-highlight-on-save ()
  "Set up current hour highlighting on save for daily files."
  (when (aj/daily-date-file-p)
    (add-hook 'after-save-hook #'aj/highlight-current-hour nil t)))

(add-hook 'org-roam-dailies-find-file-hook #'aj/setup-hour-highlight-on-save)

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
