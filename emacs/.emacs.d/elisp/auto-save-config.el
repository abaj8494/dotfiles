;;; auto-save-config.el --- Automatic file saving configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; This file configures aggressive auto-saving to prevent data loss.
;; Files are automatically saved every minute.

;;; Code:

;; ---------------------------------------------------------------------------
;; Auto-save visited files (saves the actual file, not just #filename#)
;; ---------------------------------------------------------------------------

;; Enable auto-save-visited-mode globally
;; This saves the actual file (not a backup) at regular intervals
(auto-save-visited-mode 1)

;; Set the interval to 60 seconds (1 minute)
(setq auto-save-visited-interval 120)

;; ---------------------------------------------------------------------------
;; Configure standard auto-save behavior as backup
;; ---------------------------------------------------------------------------

;; Keep auto-save files (#filename#) as additional safety
(setq auto-save-default t)

;; Auto-save after 20 characters typed (default is 300)
;; This means you'll get more frequent auto-saves during active editing
(setq auto-save-interval 20)

;; Auto-save after 1 second of idle time
(setq auto-save-timeout 1)

;; Store auto-save files in a dedicated directory instead of cluttering
;; the working directory
(setq auto-save-file-name-transforms
      `((".*" ,(expand-file-name "auto-save/" user-emacs-directory) t)))

;; Create the auto-save directory if it doesn't exist
(let ((auto-save-dir (expand-file-name "auto-save/" user-emacs-directory)))
  (unless (file-exists-p auto-save-dir)
    (make-directory auto-save-dir t)))

;; ---------------------------------------------------------------------------
;; Optional: Show message when auto-saving
;; ---------------------------------------------------------------------------

;; Uncomment the following to see a message when files are auto-saved
;; (setq auto-save-visited-predicate
;;       (lambda ()
;;         (when (buffer-file-name)
;;           (message "Auto-saved: %s" (buffer-name))
;;           t)))

;; ---------------------------------------------------------------------------
;; Configure backup files
;; ---------------------------------------------------------------------------

;; Keep backup files in a dedicated directory
(setq backup-directory-alist
      `(("." . ,(expand-file-name "backups/" user-emacs-directory))))

;; Make backups by copying rather than renaming
;; This preserves file ownership and hard links
(setq backup-by-copying t)

;; Keep multiple versions of backup files
(setq delete-old-versions t
      kept-new-versions 6
      kept-old-versions 2
      version-control t)

;; Create the backups directory if it doesn't exist
(let ((backup-dir (expand-file-name "backups/" user-emacs-directory)))
  (unless (file-exists-p backup-dir)
    (make-directory backup-dir t)))

(provide 'auto-save-config)
;;; auto-save-config.el ends here

