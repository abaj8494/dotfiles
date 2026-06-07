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

(defconst aj/finances-dir "/Users/aayushbajaj/lattice/2-areas/finance/beancount/"
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

;; ---------------------------------------------------------------------------
;; Pull files from ~/Downloads into the current directory  (C-c M)
;; ---------------------------------------------------------------------------

(defvar aj/pull-source-dir (expand-file-name "~/Downloads/")
  "Default source directory for `aj/pull-from-downloads'.")

(defun aj/pull--source-files (dir)
  "Return basenames of non-dot entries in DIR, newest first."
  (let ((entries (directory-files dir t directory-files-no-dot-files-regexp t)))
    (mapcar #'file-name-nondirectory
            (sort entries
                  (lambda (a b)
                    (time-less-p
                     (file-attribute-modification-time (file-attributes b))
                     (file-attribute-modification-time (file-attributes a))))))))

(defun aj/pull-from-downloads (&optional copy)
  "Move file(s) from a source dir into the current directory.

Prompts for the source directory with `aj/pull-source-dir' (~/Downloads)
prefilled — hit RET to accept or edit/navigate to another dir. Then offers
that dir's entries newest-first in a Helm picker: mark several with \\`C-SPC',
RET to confirm. Destination is the dired directory when point is in dired
\(reverted afterward), otherwise `default-directory'. With prefix arg COPY,
copy instead of move."
  (interactive "P")
  (require 'helm)
  (let* ((src (file-name-as-directory
               (read-directory-name "Pull from: " aj/pull-source-dir
                                    aj/pull-source-dir t)))
         (dest (if (derived-mode-p 'dired-mode)
                   (dired-current-directory)
                 default-directory))
         (names (aj/pull--source-files src)))
    (unless names
      (user-error "No files in %s" src))
    (let ((chosen (helm-comp-read
                   (format "%s from %s → %s: "
                           (if copy "Copy" "Move")
                           (abbreviate-file-name src)
                           (abbreviate-file-name dest))
                   names
                   :marked-candidates t
                   :must-match t
                   :buffer "*helm pull files*"))
          (n 0))
      (dolist (name chosen)
        (let ((s (expand-file-name name src))
              (d (expand-file-name name dest)))
          (when (or (not (file-exists-p d))
                    (yes-or-no-p (format "%s exists in destination; overwrite? "
                                         name)))
            (if copy (copy-file s d t) (rename-file s d t))
            (setq n (1+ n)))))
      (when (derived-mode-p 'dired-mode)
        (revert-buffer))
      (message "%s %d file(s) into %s"
               (if copy "Copied" "Moved") n (abbreviate-file-name dest)))))

(define-key global-map (kbd "C-c M") #'aj/pull-from-downloads)

(provide 'aj-bindings)

;;; aj-bindings.el ends here
