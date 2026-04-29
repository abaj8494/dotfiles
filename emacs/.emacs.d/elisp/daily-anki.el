;;; daily-anki.el --- Anki review chart for dailies -*- lexical-binding: t; -*-

;;; Commentary:
;; Inserts a 14-day Anki review-count chart under * TODO Anki in daily
;; notes via AnkiConnect + gnuplot. Refreshes automatically before
;; export and before magit-status when an Anki heading is present.

;;; Code:

(require 'daily-structure)

(declare-function magit-status "magit-status")

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


(provide 'daily-anki)

;;; daily-anki.el ends here
