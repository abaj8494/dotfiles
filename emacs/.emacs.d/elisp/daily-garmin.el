;;; daily-garmin.el --- Garmin chart, route maps, dashboard for dailies -*- lexical-binding: t; -*-

;;; Commentary:
;; ** Self section under * Journal in daily notes is rendered from
;; Garmin data: a sleep+stress chart (gnuplot from garmin.db), per-
;; activity route maps (matplotlib from garmin_activities.db), and a
;; per-activity HTML dashboard generated on demand. Also handles the
;; garmindb_cli.py async sync that backs all of this.

;;; Code:

(require 'daily-structure)

(declare-function gruber-themes--get-current-variant "gruber-themes")
(declare-function org-display-inline-images "org")
(declare-function org-table-align "org-table")
(declare-function magit-status "magit-status")

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

;; The C-c d r j binding lives in daily-config.el alongside the rest of
;; the aj/daily-refresh-map setup so the keymap is fully assembled in one
;; place — see `aj/garmin-refresh-and-jump' below for the binding's body.

(defun aj/garmin-refresh-and-jump (force)
  "Refresh the Garmin Self chart in the current daily note.
With prefix arg FORCE, also kick off a fresh garmindb sync regardless
of the cooldown. Offers to jump to the Self heading afterward."
  (interactive "P")
  (aj/insert-garmin-self-chart)
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
      (org-beginning-of-line))))

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


(provide 'daily-garmin)

;;; daily-garmin.el ends here
