;;; aj-bindings.el --- Custom keybindings -*- lexical-binding: t; -*-

;;; Code:

(defvar my/yank-map
  (let ((map (make-sparse-keymap)))
    map)
  "Prefix keymap for yank commands.")

(define-key global-map (kbd "C-c Y") my/yank-map)

(defun my/yank-file-path ()
  "Copy the full path of the current file or directory to the clipboard.
In dired buffers, copies the current directory path."
  (interactive)
  (cond
   (buffer-file-name
    (kill-new buffer-file-name)
    (message "Copied: %s" buffer-file-name))
   ((derived-mode-p 'dired-mode)
    (let ((dir (dired-current-directory)))
      (kill-new dir)
      (message "Copied: %s" dir)))
   (t
    (message "Buffer is not visiting a file or directory"))))

(define-key my/yank-map (kbd "f") #'my/yank-file-path)

;; ---------------------------------------------------------------------------
;; Dired: open PDF in sioyek
;; ---------------------------------------------------------------------------

(defun aj/dired-open-in-sioyek ()
  "Open the file at point in sioyek."
  (interactive)
  (let ((file (dired-get-file-for-visit)))
    (start-process "sioyek" nil "sioyek" file)))

(with-eval-after-load 'dired
  (define-key dired-mode-map (kbd "V") #'aj/dired-open-in-sioyek))

;; ---------------------------------------------------------------------------
;; Beancount: instant deploy to ledger.abaj.ai
;; ---------------------------------------------------------------------------

(defconst aj/finances-dir "/Users/aayushbajaj/Documents/Finances/beancount/"
  "Root of the beancount ledger repository.")

(defun aj/beancount-deploy ()
  "Validate, commit, push, and trigger remote pull of the ledger.
Bypasses the hourly sync cron so ledger.abaj.ai updates immediately."
  (interactive)
  (save-some-buffers t
                     (lambda ()
                       (and buffer-file-name
                            (string-prefix-p aj/finances-dir buffer-file-name))))
  (let ((default-directory aj/finances-dir)
        (buf "*beancount-deploy*"))
    (with-current-buffer (get-buffer-create buf)
      (let ((inhibit-read-only t)) (erase-buffer)))
    (async-shell-command (concat aj/finances-dir "deploy.sh") buf)))

(define-key global-map (kbd "C-c b p") #'aj/beancount-deploy)

(provide 'aj-bindings)

;;; aj-bindings.el ends here
