;;; daily-rmpp.el --- rMPP daily push + ferrari rebuild -*- lexical-binding: t; -*-

;;; Commentary:
;; Async push of today's daily PDF to the reMarkable Paper Pro:
;; pulls KOReader highlights via `make ferrari-pull-highlights', then runs
;; scripts/sync-daily.sh to export and scp into xochitl. Plays
;; Glass.aiff / Basso.aiff + edge-tts for completion feedback.
;; Also exposes aj/ferrari-make for forcing a ferrari rebuild
;; through the same logging + audio plumbing.

;;; Code:

;; Log buffer is space-prefixed so it stays out of the normal buffer list.
;; View with `C-x b *rmpp-push-daily* RET' when debugging.
(defconst aj/rmpp--log-buffer-name "*rmpp-push-daily*")
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

Step 1 runs `make ferrari-pull-highlights' so any unpulled highlights on
the device are merged back into sioyek before we touch it further. Step 2
shells out to `scripts/sync-daily.sh' for the headless org→PDF export,
UUID lookup, scp, and xochitl registration. If step 1 fails, step 2 is
skipped and you hear about the pull failure specifically.

Log output is appended to the buffer `*rmpp-push-daily*' — view with
`C-x b *rmpp-push-daily* RET' when debugging.

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
     (list "make" "-C" project-dir "ferrari-pull-highlights")
     (lambda ()
       (aj/rmpp--run-step
        "push"
        (list "bash"
              (expand-file-name "scripts/sync-daily.sh" project-dir))
        #'aj/rmpp--notify-success)))))


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


(provide 'daily-rmpp)

;;; daily-rmpp.el ends here
