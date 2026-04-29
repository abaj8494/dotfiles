;;; daily-week.el --- Week transclude for daily notes -*- lexical-binding: t; -*-

;;; Commentary:
;; Each daily note opens with a transclude of its ISO-week heading from
;; the yearly file (twenty-twenty-six.org and friends). This module
;; resolves the week heading via the org-roam DB, inserts the transclude
;; directive, and folds the heading on file-open.

;;; Code:

(require 'daily-structure)

(declare-function org-roam-db-query "org-roam-db")
(declare-function org-fold-folded-p "org-fold")
(declare-function org-cycle "org")
(declare-function org-transclusion-mode "org-transclusion")

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
