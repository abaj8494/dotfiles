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

(provide 'aj-bindings)

;;; aj-bindings.el ends here
