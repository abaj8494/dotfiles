;;; daily-calendar.el --- Calendar table, weather, hour highlighting -*- lexical-binding: t; -*-

;;; Commentary:
;; Calendar section of daily notes: monthly cal table with day links and
;; cumulative-day stats, the calendar-section weather block (synchronous
;; and asynchronous variants pulling from a remote cache via rsync, with
;; OpenWeather fallback), the hourly weather table, the mode-line wttr
;; widget, and current-hour highlighting overlays.

;;; Code:

(require 'daily-structure)

(declare-function org-id-get-create "org-id")
(declare-function org-table-align "org-table")
(declare-function gruber-themes--get-current-variant "gruber-themes")

;; --- Weather config defvars --- ;;

;; Weather variables
(defvar aj/openweather-city "Sydney"
  "City for OpenWeatherMap queries.")

(defvar aj/weather-archive-remote "root@abaj.ai:/var/weather-archive/"
  "Remote path to weather archive on server.")

(defvar aj/weather-archive-local (expand-file-name "~/.cache/weather-archive/")
  "Local cache directory for weather archive.")

(defvar aj/weather-cache-ttl 1800
  "Seconds. If the cached weather for the file's date is younger than this,
`aj/fetch-calendar-weather-async' skips the ssh+rsync round-trip and inserts
directly from the local cache. Set to 0 to always hit the network.")

(defvar aj/weather-location-cache nil
  "Cached location data: (timestamp lat lon name).")

(defvar aj/weather-location-cache-duration 3600
  "How long to cache location data in seconds (default 1 hour).")

(defvar aj/weather-location-file (expand-file-name "~/.weather-location")
  "Optional file to manually set weather location.
Format: LAT LON NAME (e.g., -33.8148 151.1029 West Ryde)")

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

(defun my/insert-aj-day-calendar (&optional force)
  "Insert formatted calendar for a daily org-roam note with life stats.
Parses date from #+title: YYYY-MM-DD line.
Outputs an org table with links to daily files.
Σ column: Day of year (cumulative days elapsed in current year).
ω column: Days elapsed since December 26, 2001 (AJ's birthday).

When FORCE is non-nil, the weather fetch ignores the local cache and
hits the server. Otherwise a fresh cache (see `aj/weather-cache-ttl')
short-circuits the ssh+rsync."
  (interactive "P")
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
        (aj/fetch-calendar-weather-async date-str (current-buffer) force)))))


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

(defun aj/weather-cache-fresh-p (date-str)
  "Return non-nil if the local weather cache for DATE-STR is fresh enough
to skip a server fetch. For today, requires the hourly file to exist and
to have been modified within `aj/weather-cache-ttl' seconds. For other
dates the cache is static (server only updates today/tomorrow), so any
existing cache file counts as fresh."
  (let* ((today-str (format-time-string "%Y-%m-%d"))
         (is-today (string= date-str today-str))
         (hourly (expand-file-name (concat "hourly-" date-str ".json")
                                   aj/weather-archive-local))
         (daily  (expand-file-name (concat date-str ".json")
                                   aj/weather-archive-local)))
    (cond
     ((<= aj/weather-cache-ttl 0) nil)
     (is-today
      (and (file-exists-p hourly)
           (< (- (float-time)
                 (float-time (file-attribute-modification-time
                              (file-attributes hourly))))
              aj/weather-cache-ttl)))
     (t (or (file-exists-p hourly) (file-exists-p daily))))))

(defun aj/--insert-weather-from-cache-and-finalize (buffer date-str)
  "Insert weather + hourly table into BUFFER for DATE-STR and re-sweep newpages.
Shared tail of the async/cache-hit paths."
  (when (buffer-live-p buffer)
    (aj/insert-weather-from-cache buffer date-str)
    (aj/insert-hourly-weather-table buffer date-str)
    (with-current-buffer buffer
      (aj/ensure-heading-separators)
      (aj/ensure-recurring-separators)
      ;; Weather insertion splices content between a pre-existing
      ;; `#+LATEX: \newpage' and its heading, orphaning the directive
      ;; inside the Calendar section. Re-run the sweeper so Phase 1
      ;; deletes the orphan and Phase 2 re-inserts canonically above
      ;; the heading.
      (aj/ensure-heading-newpages))))

(defun aj/fetch-calendar-weather-async (date-str buffer &optional force)
  "Fetch fresh weather from server and insert into BUFFER's Calendar section.
Detects location from ~/.weather-location or IP, runs weather script on server,
syncs data, then inserts.

When FORCE is nil (the default) and `aj/weather-cache-fresh-p' returns
non-nil for DATE-STR, skip the ssh+rsync round-trip and insert directly
from the local cache. Pass non-nil FORCE (e.g. from `C-c d r c') to
unconditionally hit the server."
  (if (and (not force)
           (aj/weather-cache-fresh-p date-str))
      (progn
        (message "Weather: cache hit for %s, skipping fetch" date-str)
        (aj/--insert-weather-from-cache-and-finalize buffer date-str))
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
         (lambda (_p e)
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
                (lambda (_p2 e2)
                  (if (not (string-match-p "finished" e2))
                      (message "Weather: sync failed - %s" (string-trim e2))
                    (message "Weather: inserting into buffer...")
                    (aj/--insert-weather-from-cache-and-finalize buffer date-str)
                    (when (buffer-live-p buffer)
                      (message "Weather: done for %s ✓" name)))))))))))))

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

(defun aj/refresh-daily-calendar (&optional force)
  "Refresh calendar section for the current daily note.
Inserts calendar table and fetches weather data (including hourly if available).
With prefix arg (or non-nil FORCE), bypasses the local weather cache and
re-fetches from the server."
  (interactive "P")
  (unless (aj/daily-date-file-p)
    (user-error "Not in a daily note"))
  (my/insert-aj-day-calendar force)
  (message "Calendar refreshed"))

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


(provide 'daily-calendar)

;;; daily-calendar.el ends here
