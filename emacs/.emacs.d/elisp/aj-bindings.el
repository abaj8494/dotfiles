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

;; ---------------------------------------------------------------------------
;; Scan a single document → multi-page PDF in the current directory
;; ---------------------------------------------------------------------------

(defconst aj/scan-doc-script
  (expand-file-name "scripts/scan-doc.py" user-emacs-directory)
  "Path to the interactive single-document scan helper.")

(defun aj/scan-document (&optional arg)
  "Open a horizontal vterm split running the single-document scan helper.
Output PDF lands in the buffer's `default-directory' (or `$HOME' if the
buffer has none, e.g. *scratch*). Each ADF pass in the vterm appends
pages to the output; enter `q' in the prompt to finish and assemble.

Prefix args:
  no prefix           simplex, create a new PDF
  \\[universal-argument]               duplex, create a new PDF
  \\[universal-argument] \\[universal-argument]         simplex, append to an existing PDF (prompts for path)

Duplex can also be toggled mid-session with `d' at the script's prompt,
and append mode can be entered ad-hoc by typing `a' at the filename
prompt."
  (interactive "P")
  (let* ((duplex (and arg (not (equal arg '(16)))))
         (append-mode (equal arg '(16)))
         (dir (or (and default-directory
                       (file-directory-p default-directory)
                       (expand-file-name default-directory))
                  (expand-file-name "~")))
         (append-target
          (when append-mode
            (let ((chosen (read-file-name
                           "Append to PDF: " dir nil t nil
                           (lambda (name)
                             (or (file-directory-p name)
                                 (string-match-p "\\.pdf\\'" name))))))
              (unless (and chosen
                           (file-regular-p chosen)
                           (string-match-p "\\.pdf\\'" chosen))
                (user-error "Not a PDF file: %s" chosen))
              (expand-file-name chosen))))
         (cmd (format "python3 %s%s%s %s"
                      (shell-quote-argument aj/scan-doc-script)
                      (if duplex " --duplex" "")
                      (if append-target
                          (concat " --append "
                                  (shell-quote-argument append-target))
                        "")
                      (shell-quote-argument (directory-file-name dir)))))
    (unless (file-exists-p aj/scan-doc-script)
      (user-error "scan-doc.py not found at %s" aj/scan-doc-script))
    (let ((default-directory dir))
      (split-window-below)
      (other-window 1)
      (cond
       ((or (featurep 'vterm) (require 'vterm nil 'noerror))
        (vterm)
        (vterm-send-string cmd)
        (vterm-send-return))
       (t
        (compile cmd))))))

(define-key global-map (kbd "C-c s") #'aj/scan-document)

(provide 'aj-bindings)

;;; aj-bindings.el ends here
