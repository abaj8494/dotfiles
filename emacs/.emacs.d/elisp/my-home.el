;; -*- lexical-binding: t; -*-

;;; --- Minimal Home Buffer (Vanilla) -------------------------------
(require 'cl-lib)


(defgroup my-home nil
  "Lightweight startup/home buffer."
  :group 'convenience)

(defface my-home-title
  '((t :height 1.4 :weight bold))
  "Face for the home title.")

(defface my-home-section
  '((t :height 1.1 :weight semi-bold :inherit font-lock-keyword-face))
  "Face for section headers.")

(defvar my-home--dirs
  '(("~/Documents"                     . "Documents")
    ("~/Documents/new-site"            . "New Site")
    ("~/Downloads"                     . "Downloads")
    ("~/Documents/code"                . "Code")
    ("~/Documents/new-site/static/doc/org/flashcards"   . "Flash Cards"))
  "List of (PATH . LABEL) for quick Dired.")

(defvar my-home-buffer-name "*Home*")


(define-derived-mode my-home-mode special-mode "Home"
  "Mode for the startup home buffer."
  (setq buffer-read-only t
        truncate-lines t
        mode-line-format '("  " mode-name))
  (setq-local cursor-type nil))

(defface my-home-focus
  '((t :inherit hl-line))
  "Face used to highlight the focused button.")

(defvar-local my-home--focus-ov nil)

(defun my-home--focus-update ()
  "Move a highlight overlay to the button at point."
  (when (derived-mode-p 'my-home-mode)
    (let ((btn (button-at (point))))
      (unless my-home--focus-ov
        (setq my-home--focus-ov (make-overlay (point) (point)))
        (overlay-put my-home--focus-ov 'priority 1000)
        (overlay-put my-home--focus-ov 'face 'my-home-focus))
      (if btn
          (move-overlay my-home--focus-ov (button-start btn) (button-end btn))
        (delete-overlay my-home--focus-ov)))))

(add-hook 'post-command-hook #'my-home--focus-update nil t)

;; Nice keys
(define-key my-home-mode-map (kbd "TAB")       #'forward-button)
(define-key my-home-mode-map (kbd "<backtab>") #'backward-button)
(define-key my-home-mode-map (kbd "RET")       #'push-button)
(define-key my-home-mode-map (kbd "n")         #'forward-button)
(define-key my-home-mode-map (kbd "p")         #'backward-button)
(define-key my-home-mode-map (kbd "j")         #'forward-button)
(define-key my-home-mode-map (kbd "k")         #'backward-button)
(define-key my-home-mode-map (kbd "g")         (lambda () (interactive) (my-home-buffer)))
(define-key my-home-mode-map (kbd "q")         #'quit-window)

;; Optional: digits 1..9 open the nth quick folder
(defun my-home--open-quick (n)
  (interactive "p")
  (let* ((idx (1- n)) (pair (nth idx my-home--dirs)))
    (when pair (dired (expand-file-name (car pair))))))

(dotimes (i 9)
  (define-key my-home-mode-map (kbd (number-to-string (1+ i)))
    (lambda () (interactive) (my-home--open-quick ,(1+ i)))))

;; Clean up overlay when leaving the buffer
(add-hook 'kill-buffer-hook
          (lambda () (when (overlayp my-home--focus-ov)
                       (delete-overlay my-home--focus-ov)))
          nil t)


(defun my-home--button (label fn &optional help-echo)
  (let ((f fn))
    (insert-text-button
     (format "%s" label)
     'follow-link t
     'help-echo (or help-echo "Open")
     'face 'link
     'action (lambda (_btn) (call-interactively f)))))

(defun my-home--button-cmd (label cmd &optional help-echo)
  (let ((f cmd))
    (insert-text-button
     (format "%s" label)
     'follow-link t
     'help-echo (or help-echo "Run")
     'face 'link
     'action (lambda (_btn) (funcall f)))))


(defun my-home--insert-section (title content-fn)
  (let ((inhibit-read-only t))
    (insert (propertize title 'face 'my-home-section) "\n")
    (funcall content-fn)
    (insert "\n")))

(defun my-home--insert-title ()
  (let ((inhibit-read-only t))
    (insert (propertize "Welcome, Aayush" 'face 'my-home-title))
    (insert "\n\n")))

(defun my-home--paths ()
  (dolist (pair my-home--dirs)
    (let* ((path (expand-file-name (car pair)))
           (label (cdr pair)))
      (when (file-directory-p path)
        (my-home--button-cmd
         (format "📁  %s" label)
         (lambda () (dired path))
         (format "Open Dired: %s" path))
        (insert "   ")))))


;; --- replace these two defs with the corrected versions ---

(defun my-home--org ()
  ;; Buttons: Agenda, Capture
  (my-home--button "⏱️  Agenda" #'org-agenda "Open Org Agenda")
  (insert "   ")
  (my-home--button "📝  Capture" #'org-capture "Start Org Capture")
  (insert "\n"))

(defun my-home--search ()
  ;; Prefer Affe if available; otherwise fall back.
  (cond
   ((and (fboundp 'affe-find) (fboundp 'affe-grep))
    (my-home--button "🔍  Affe Find (files)" #'affe-find "Fuzzy file finder")
    (insert "   ")
    (my-home--button "🔎  Affe Grep (content)" #'affe-grep "Fuzzy grep")
    (insert "\n"))
   (t
    (my-home--button-cmd
     "🔍  Search (rgrep)"
     (lambda () (call-interactively #'rgrep)))
    (insert "   ")
    (if (fboundp 'project-find-file)
        (my-home--button "📂  Project files" #'project-find-file "Built-in project file finder")
      (my-home--button "📂  Find file" #'find-file "Open a file"))
    (insert "\n"))))

(defun my-home--recentf ()
  (require 'recentf)
  (recentf-mode 1)
  (let ((count 0))
    (dolist (f recentf-list)
      (when (and f (file-exists-p f))
        (insert-text-button
         (format "• %s" (abbreviate-file-name f))
         'follow-link t
         'help-echo f
         'face 'link
         'my-file f
         'action (lambda (btn)
                   (find-file (button-get btn 'my-file))))
        (insert "\n")
        (setq count (1+ count))
        (when (>= count 40)
          (setq recentf-list nil)   ; break the loop without cl-return
          )))))

(defun my-home-buffer ()
  "Create or refresh the home buffer."
  (let ((buf (get-buffer-create my-home-buffer-name)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (my-home-mode)
        (my-home--insert-title)

        (my-home--insert-section "Quick Folders" #'my-home--paths)
        (my-home--insert-section "Org"           #'my-home--org)
        (my-home--insert-section "Search"        #'my-home--search)
        (my-home--insert-section "Recent Files"  #'my-home--recentf)
	(my-home--insert-section "Config" #'my-home--config)
        (insert "\n")
        (insert-text-button
         "↻ Refresh" 'follow-link t 'face 'shadow
         'action (lambda (_)
                   (interactive) (my-home-buffer)))
        (insert "    ")
        (insert-text-button
         "q Quit" 'follow-link t 'face 'shadow
         'action (lambda (_)
                   (interactive) (quit-window t)))
        (goto-char (point-min))))
    buf))

;; Show this buffer on startup:
(setq inhibit-startup-screen t)
(setq initial-buffer-choice #'my-home-buffer)

;; Handy global key to return to Home anytime:
(global-set-key (kbd "C-c h") (lambda () (interactive) (switch-to-buffer (my-home-buffer))))
;;; -----------------------------------------------------------------

(defun my-home--config ()
  "Buttons to jump to Emacs config."
  ;; ~/.emacs.d (Dired)
  (insert-text-button
   "🛠️  ~/.emacs.d (Dired)"
   'follow-link t
   'help-echo (expand-file-name user-emacs-directory)
   'face 'link
   'my-path (expand-file-name user-emacs-directory)
   'action (lambda (btn)
             (dired (button-get btn 'my-path))))
  (insert "   ")
  ;; init.el
  (let ((init-file (expand-file-name "init.el" user-emacs-directory)))
    (insert-text-button
     "📄  Open init.el"
     'follow-link t
     'help-echo init-file
     'face 'link
     'my-file init-file
     'action (lambda (btn)
               (find-file (button-get btn 'my-file)))))
  (insert "\n"))


(provide 'my-home)
