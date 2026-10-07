;;; daily-week.el --- Week transclude for daily notes -*- lexical-binding: t; -*-

;;; Commentary:
;; Each daily note opens with a transclude of its ISO-week heading from
;; the yearly file (twenty-twenty-six.org and friends). This module
;; resolves the week heading via the org-roam DB, inserts the transclude
;; directive, and folds the heading on file-open.

;;; Code:

(require 'daily-structure)
(require 'calendar)
(require 'cal-iso)

(declare-function org-roam-db-query "org-roam-db")
(declare-function org-roam-db-update-file "org-roam-db")
(declare-function org-fold-folded-p "org-fold")
(declare-function org-cycle "org")
(declare-function org-transclusion-mode "org-transclusion")
(declare-function org-id-find "org-id")
(declare-function org-id-get-create "org-id")
(declare-function org-set-tags "org")
(declare-function org-get-heading "org")
(declare-function org-table-align "org-table")

(defvar aj/yearly-file-ids
  '((2026 . "51fe6c3d-45e2-4655-bc1c-9358f989d02a"))
  "Alist mapping years to their yearly org file IDs.")

(defvar aj/yearly-file-names
  '((2026 . "twenty-twenty-six"))
  "Alist mapping years to their yearly org file display names.")

(defun aj/iso-week-number (&optional time)
  "Return ISO week number for TIME."
  (string-to-number (format-time-string "%V" (or time (current-time)))))

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

;; ---------------------------------------------------------------------------
;; Creating the week heading in the yearly file
;; ---------------------------------------------------------------------------
;; The transclude a daily carries points at `* Week N' inside the yearly file.
;; That heading used to be added by hand, so the first daily of a new week
;; opened onto a dangling link and org-transclusion reported
;;   (user-error "Org-transclusion: `org-link-open' cannot open link, id:…::* Week N")
;; on every visit until the heading was written. (Seen 2026-08-18: the yearly
;; file stopped at Week 31 while the dailies had moved on to Week 34.)
;; `aj/ensure-week-heading' creates it instead, in the same shape as the ones
;; already there: the heading tagged with the year, an ID so it is an org-roam
;; node the daily can link to by name, and the month's calendar table with this
;; week's row bolded. Regenerating Weeks 27/30/31 with this code reproduces the
;; hand-written tables byte for byte.
;;
;; All the date arithmetic goes through calendar.el's absolute day numbers, not
;; `time-add'/`days-to-time': adding 86400-second days across the April DST
;; change lands on 23:00 of the day before, which silently shifted the bolded
;; row off by one.

(defun aj/week--monday-absolute (week-num year)
  "Absolute day number of the Monday that starts ISO week WEEK-NUM of YEAR."
  (let* ((jan4 (list 1 4 year))              ; Jan 4 is always in ISO week 1
         (dow (calendar-day-of-week jan4))   ; 0 = Sunday
         (iso-dow (if (= dow 0) 7 dow)))     ; 1 = Monday … 7 = Sunday
    (+ (calendar-absolute-from-gregorian jan4)
       (- 1 iso-dow)
       (* 7 (1- week-num)))))

(defun aj/week--month-table-rows (week-num year)
  "Return (CAPTION ROWS) for the yearly-file table of ISO week WEEK-NUM of YEAR.
The grid is the calendar month containing that week's Sunday, Sunday-first.
Each element of ROWS is nine strings: Su…Sa, the row's ISO week number, and
the row's index within the grid.  The cells of WEEK-NUM's own row are bolded."
  (let* ((sunday (1- (aj/week--monday-absolute week-num year)))
         (greg (calendar-gregorian-from-absolute sunday))
         (gm (nth 0 greg))
         (gy (nth 2 greg))
         (first (calendar-absolute-from-gregorian (list gm 1 gy)))
         (lead (calendar-day-of-week (list gm 1 gy)))
         (ndays (calendar-last-day-of-month gm gy))
         (nrows (ceiling (+ lead ndays) 7))
         rows)
    (dotimes (r nrows)
      (let* ((start (+ first (- lead) (* 7 r)))
             (boldp (= start sunday))
             cells)
        (dotimes (i 7)
          (let ((day (+ (- start first) i 1)))
            (push (cond ((or (< day 1) (> day ndays)) "")
                        (boldp (format "*%d*" day))
                        (t (number-to-string day)))
                  cells)))
        (push (append (nreverse cells)
                      (list (number-to-string
                             (car (calendar-iso-from-absolute (1+ start))))
                            (number-to-string (1+ r))))
              rows)))
    (list (format "%s %d" (calendar-month-name gm) gy) (nreverse rows))))

(defun aj/week--insert-month-table (week-num year)
  "Insert (and align) the calendar table for ISO week WEEK-NUM of YEAR at point."
  (pcase-let ((`(,caption ,rows) (aj/week--month-table-rows week-num year)))
    (let ((table-start (point)))
      (insert "#+CAPTION: " caption "\n"
              "| Su | Mo | Tu | We | Th | Fr | Sa | Σ | ζ |\n"
              "|----|\n"
              (mapconcat (lambda (row)
                           (concat "| " (mapconcat #'identity row " | ") " |"))
                         rows "\n")
              "\n")
      (save-excursion
        (goto-char table-start)
        (forward-line 1)
        (org-table-align)))))

(defun aj/week--yearly-file (year)
  "Return the path of YEAR's yearly file, or nil if there isn't one."
  (let ((file-id (cdr (assoc year aj/yearly-file-ids))))
    (when file-id
      (car (org-id-find file-id)))))

(defun aj/ensure-week-heading (week-num year)
  "Ensure `* Week WEEK-NUM' exists in YEAR's yearly file.  Return (ID . TITLE).
Creates the heading — tagged with YEAR, given an ID, and followed by the
month's calendar table — when it is missing, keeping the file's newest-week-
first ordering.  Returns nil if YEAR has no yearly file."
  (let ((file (aj/week--yearly-file year)))
    (when file
      (with-current-buffer (find-file-noselect file)
        ;; Plain save-excursion/save-restriction rather than
        ;; `org-with-wide-buffer': that macro is not defined at byte-compile
        ;; time here (this file doesn't require org), so it would compile to a
        ;; bare function call and fail at runtime.
        (save-excursion
         (save-restriction
          (widen)
          (goto-char (point-min))
         (unless (re-search-forward (format "^\\* Week %d\\(?:[ \t]\\|$\\)" week-num)
                                    nil t)
           ;; Weeks are listed newest first: land before the first heading for
           ;; an earlier week, so a gap in the sequence still sorts correctly.
           (goto-char (point-min))
           (let ((insert-at
                  (catch 'found
                    (while (re-search-forward "^\\* Week \\([0-9]+\\)" nil t)
                      (when (< (string-to-number (match-string 1)) week-num)
                        (throw 'found (line-beginning-position))))
                    ;; No earlier week: this is the oldest, so append.
                    (point-max))))
             (goto-char insert-at)
             (save-excursion
               ;; Leading blank line: `org-id-get-create' drops the property
               ;; drawer in between, and the existing entries separate it from
               ;; the table with an empty line.
               (insert (format "* Week %d\n\n" week-num))
               (aj/week--insert-month-table week-num year)
               (insert "\n\n"))
             (org-set-tags (list (number-to-string year)))
             (org-id-get-create))
           (save-buffer)
           (when (fboundp 'org-roam-db-update-file)
             (org-roam-db-update-file file)))
          ;; Re-find: the heading either already existed or was just written.
          (goto-char (point-min))
          (when (re-search-forward (format "^\\* Week %d\\(?:[ \t]\\|$\\)" week-num)
                                   nil t)
            (cons (org-id-get-create)
                  (org-get-heading t t t t)))))))))

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
             ;; Prefer the org-roam DB (no file I/O); fall back to opening the
             ;; yearly file, which both creates a missing week heading and
             ;; recovers one the DB simply hasn't indexed yet. Either way the
             ;; `id:…::* Week N' search below now has something to land on.
             (week-info (or (aj/get-week-heading-info week-num year)
                            (aj/ensure-week-heading week-num year)))
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

(provide 'daily-week)

;;; daily-week.el ends here
