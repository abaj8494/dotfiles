;;; aj-bindings.el --- Custom keybindings -*- lexical-binding: t; -*-

;;; Code:

(defvar my/yank-map
  (let ((map (make-sparse-keymap)))
    map)
  "Prefix keymap for yank commands.")

(define-key global-map (kbd "C-c Y") my/yank-map)

(defun my/yank-file-path ()
  "Copy the full path of the current file to the clipboard.
In dired, copies the path of the file at point.  On the `.' entry it
copies the full path of the current directory; on `..' it copies the
full path of the parent directory."
  (interactive)
  (cond
   (buffer-file-name
    (kill-new buffer-file-name)
    (message "Copied: %s" buffer-file-name))
   ((derived-mode-p 'dired-mode)
    (let ((name (dired-get-filename 'no-dir t))
          copied)
      (cond
       ((null name)
        (message "No file on this line"))
       ((string= name ".")
        (setq copied (directory-file-name (dired-current-directory))))
       ((string= name "..")
        (setq copied (directory-file-name
                      (file-name-directory
                       (directory-file-name (dired-current-directory))))))
       (t
        (setq copied (dired-get-filename nil t))))
      (when copied
        (kill-new copied)
        (message "Copied: %s" copied))))
   (t
    (message "Buffer is not visiting a file or directory"))))

(define-key my/yank-map (kbd "f") #'my/yank-file-path)

;; ---------------------------------------------------------------------------
;; System clipboard for terminal (TTY) frames  (`emacsclient -t' / the `et' alias)
;; ---------------------------------------------------------------------------
;; GUI frames sync the kill-ring with the macOS pasteboard natively via
;; `gui-select-text' / `gui-selection-value'.  On the shared daemon those are
;; the global `interprogram-cut-function' / `-paste-function', but they can't
;; reach the NS pasteboard from a *terminal* frame — so a kill in `et' never
;; lands on the system clipboard.  Route TTY cut/paste through pbcopy/pbpaste
;; while leaving GUI frames on their native path.  The branch is on
;; `display-graphic-p' of the *selected frame at call time*, so one daemon
;; serves both frame types correctly.  (Referencing `gui-select-text' /
;; `gui-selection-value' by name, not the current variable values, keeps a
;; `C-c R' reload from wrapping our own wrappers into infinite recursion.)
(defvar aj/interprogram--last-cut nil
  "Last text this process copied, so pbpaste-yank doesn't re-add our own kill.")

(defun aj/pbcopy (text)
  "Send TEXT to the macOS clipboard via pbcopy."
  (let ((process-connection-type nil))
    (let ((proc (start-process "pbcopy" nil "pbcopy")))
      (process-send-string proc text)
      (process-send-eof proc))))

(defun aj/pbpaste ()
  "Return the macOS clipboard contents via pbpaste."
  (shell-command-to-string "pbpaste"))

(defun aj/interprogram-cut (text)
  "Copy TEXT to the system clipboard, routed by frame type.
GUI frames use the native NS path; TTY frames shell out to pbcopy."
  (if (display-graphic-p)
      (gui-select-text text)
    (aj/pbcopy text)
    (setq aj/interprogram--last-cut text)))

(defun aj/interprogram-paste ()
  "Return the system clipboard, routed by frame type.
GUI frames use the native NS path; TTY frames shell out to pbpaste.  Returns
nil when the clipboard still holds our own last kill, so yank doesn't push a
duplicate onto the kill-ring."
  (if (display-graphic-p)
      (gui-selection-value)
    (let ((clip (aj/pbpaste)))
      (cond
       ((string= clip "") nil)
       ((string= clip aj/interprogram--last-cut) nil)
       (t clip)))))

(setq interprogram-cut-function #'aj/interprogram-cut
      interprogram-paste-function #'aj/interprogram-paste)

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

;; ---------------------------------------------------------------------------
;; Documentation at point — one key, routed to the right backend
;; ---------------------------------------------------------------------------
;; `C-c k' shows docs for the symbol at point in a separate buffer, picking the
;; backend that actually knows the symbol in this context:
;;   - org `jupyter-' src block → the block's live kernel
;;     (`jupyter-org-inspect-src-block'), the only path that works inside org
;;     itself (LSP has no backing file/workspace there);
;;   - a real source file under LSP → pyright hover docs in *lsp-help*;
;;   - any buffer with an attached Jupyter client (REPL, `C-c '' edit buffer)
;;     → the kernel's docstring (IPython `obj?').
;;   - org `R' src block → ESS help (`?symbol') from the block's live `:session'
;;     process (or any running R), mirroring how jupyter- blocks query a kernel.
(defun aj/ess-doc-at-point ()
  "Show R help for the symbol at point via this src block's ESS session.
Resolves the inferior R process from the block's `:session' header, or
falls back to any running ESS process, then queries it for `?symbol'."
  (let* ((info (org-babel-get-src-block-info t))
         (session (cdr (assq :session (nth 2 info))))
         (buf (and session (not (string= session "none"))
                   (org-babel-comint-buffer-livep session)))
         (proc (or (and buf (get-buffer-process buf))
                   (and (bound-and-true-p ess-process-name-list)
                        (get-process (caar ess-process-name-list))))))
    (unless proc
      (user-error "No live R session — run a block first (C-c C-c)"))
    (let ((ess-current-process-name (process-name proc)))
      (ess-display-help-on-object
       (or (thing-at-point 'symbol t)
           (ess-find-help-file "Help on"))))))

(defun aj/doc-at-point ()
  "Show documentation for the symbol at point in a separate buffer."
  (interactive)
  (cond
   ((and (derived-mode-p 'org-mode)
         (fboundp 'jupyter-org-inspect-src-block)
         (org-in-src-block-p)
         (string-prefix-p "jupyter-"
                          (or (car (org-babel-get-src-block-info t)) "")))
    (jupyter-org-inspect-src-block))
   ((and (derived-mode-p 'org-mode)
         (org-in-src-block-p)
         (member (car (org-babel-get-src-block-info t)) '("R" "r")))
    (aj/ess-doc-at-point))
   ((and (bound-and-true-p lsp-mode) (fboundp 'lsp-describe-thing-at-point))
    (lsp-describe-thing-at-point))
   ((and (fboundp 'jupyter-inspect-at-point)
         (bound-and-true-p jupyter-current-client))
    (jupyter-inspect-at-point))
   (t (user-error "No documentation backend (LSP or Jupyter) active here"))))

(define-key global-map (kbd "C-c k") #'aj/doc-at-point)

;; ---------------------------------------------------------------------------
;; VSCode-style region indent / outdent with TAB and Shift-TAB
;; ---------------------------------------------------------------------------
;; With an active region, TAB shifts every selected line right one indent
;; level and Shift-TAB shifts left — *rigidly* (whitespace only), so it works
;; even on code that doesn't parse yet, unlike Emacs's default syntactic
;; re-indent.  The region stays selected so you can press again.  With no
;; region, each key keeps its existing meaning in that mode (org folding,
;; python indent, hideshow toggle).
(defun aj/indent-step ()
  "One indentation step for the current buffer (python offset, else 4)."
  (or (and (boundp 'python-indent-offset) python-indent-offset) 4))

(defun aj/shift-region (cols)
  "Rigidly shift the active region by COLS columns, keeping it selected."
  (let* ((beg (save-excursion (goto-char (region-beginning))
                              (line-beginning-position)))
         (end (save-excursion (goto-char (region-end))
                              (if (bolp) (point) (line-beginning-position 2))))
         (deactivate-mark nil))
    (indent-rigidly beg end cols)))

(defun aj/region-tab (fallback)
  "Shift region right if active; else call FALLBACK interactively."
  (if (use-region-p) (aj/shift-region (aj/indent-step))
    (call-interactively fallback)))

(defun aj/region-backtab (fallback)
  "Shift region left if active; else call FALLBACK interactively."
  (if (use-region-p) (aj/shift-region (- (aj/indent-step)))
    (call-interactively fallback)))

(defun aj/python-tab () (interactive) (aj/region-tab #'indent-for-tab-command))
(defun aj/python-backtab () (interactive) (aj/region-backtab #'hs-toggle-hiding))
(defun aj/org-tab ()
  (interactive)
  (if (and (use-region-p) (org-in-src-block-p))
      (aj/shift-region (aj/indent-step))
    (call-interactively #'org-cycle)))
(defun aj/org-backtab ()
  (interactive)
  (if (and (use-region-p) (org-in-src-block-p))
      (aj/shift-region (- (aj/indent-step)))
    (call-interactively #'org-shifttab)))

;; python covers both real .py files and the `C-c '' edit buffer (python-ts).
;; `<backtab>' there is owned by hideshow's minor-mode map, so rebind it there.
(with-eval-after-load 'python
  (when (boundp 'python-base-mode-map)
    (define-key python-base-mode-map (kbd "<tab>") #'aj/python-tab))
  ;; Stop the "Can't guess python-indent-offset, using defaults: 4" chatter:
  ;; tiny snippets (src-block fontification / edit buffers) can't be guessed,
  ;; and we always use 4 anyway — silence the warning.
  (setq python-indent-guess-indent-offset-verbose nil))
(with-eval-after-load 'hideshow
  (define-key hs-minor-mode-map (kbd "<backtab>") #'aj/python-backtab))

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "<tab>")     #'aj/org-tab)
  (define-key org-mode-map (kbd "<backtab>") #'aj/org-backtab))

(provide 'aj-bindings)

;;; aj-bindings.el ends here
