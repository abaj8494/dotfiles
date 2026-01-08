;;; package-config.el --- Package declarations and configurations -*- lexical-binding: t; -*-

;;; Commentary:
;; This file declares and configures all packages used in the configuration.

;;; Code:

(require 'use-package)

;; ---------------------------------------------------------------------------
;; Core packages via use-package / straight
;; ---------------------------------------------------------------------------

(use-package htmlize
  :straight t
  :defer nil)      ;; load eagerly so exporters find it

(use-package tex
  :straight auctex)

;; Note: Not using consult/orderless since we're using Helm for completion


(use-package elpy
  :init
  (elpy-enable)
  :config
  (setq elpy-shell-starting-directory 'current-directory)) ;; default is 'project-root

(use-package conda
  :config
  ;; interactive shell support
  (conda-env-initialize-interactive-shells)
  ;; eshell support
  (conda-env-initialize-eshell)
  ;; auto-activation
  (conda-env-autoactivate-mode t)
  ;; automatically activate a conda env on opening a file
  (add-hook 'find-file-hook
            (lambda ()
              (when (bound-and-true-p conda-project-env-path)
                (conda-env-activate-for-buffer)))))

(use-package exec-path-from-shell
  :if (memq window-system '(mac ns x))
  :config
  (exec-path-from-shell-initialize))

;; some tools expect this env var on macOS
(setenv "EMACS" "/Applications/Emacs.app/Contents/MacOS/Emacs")

(use-package zmq
  :straight '(zmq :host github :repo "nnicandro/emacs-zmq")
  :demand t)

(use-package jupyter
  :commands (jupyter-run-server-repl
             jupyter-run-repl
             jupyter-server-list-kernels)
  :straight t
  :after zmq
  :init
  (eval-after-load 'jupyter-org-extensions
    '(unbind-key "C-c h" jupyter-org-interaction-mode-map)))

(use-package sqlite3
  :straight (:host github :repo "pekingduck/emacs-sqlite3-api"))

(use-package anki-editor  
  :straight (:host github :repo "anki-editor/anki-editor"))

(use-package ankiorg
  :straight (:host github :repo "orgtre/ankiorg")
  :custom
  (ankiorg-sql-database
   "~/Library/Application Support/Anki2/j/collection.anki2")
  (ankiorg-media-directory
   "~/Library/Application Support/Anki2/j/collection.media/"))

;; Other packages you had in package-selected-packages; keep them available
(use-package magit      :defer t)
(use-package lsp-mode   :defer t)
(use-package lsp-java   :after lsp-mode :defer t)

;; ---------------------------------------------------------------------------
;; Helm-based Fuzzy Finding with fd/fzf
;; ---------------------------------------------------------------------------

(defun aj/project-root ()
  "Return a sensible project root or `default-directory`."
  (require 'project)
  (or (when-let ((proj (project-current nil)))
        (car (project-roots proj)))
      default-directory))

;; Use async process for better performance on large directories
(defun aj/helm-fd-async ()
  "Use helm to fuzzy find files with fd ASYNCHRONOUSLY (fast on large dirs)."
  (interactive)
  (require 'helm-files)
  (let* ((default-directory (aj/project-root))
         (fd-cmd "fd --type f --hidden --follow --exclude .git --max-depth 8 --color never")
         (candidates nil))
    ;; Load files synchronously (fd is fast even with more files)
    (setq candidates (split-string (shell-command-to-string fd-cmd) "\n" t))
    (helm :sources
          (helm-build-in-buffer-source "fd (deep)"
            :data candidates
            :fuzzy-match t
            :action (lambda (candidate)
                      (find-file (expand-file-name candidate default-directory))))
          :buffer "*helm fd async*"
          :prompt "Find file: ")))

;; Fallback to helm-locate for system-wide searches using locate db
(defun aj/helm-locate-wrapper ()
  "Use helm-locate for fast system-wide file search using locate database."
  (interactive)
  (helm-locate nil))

;; Fast project-local search using helm-fd with sensible limits
(defun aj/helm-fd ()
  "Use helm to fuzzy find files with fd - limited depth for performance."
  (interactive)
  (require 'helm-files)
  (let* ((default-directory (aj/project-root))
         ;; Sensible depth limit to prevent hanging
         (max-depth (if (string-prefix-p (expand-file-name "~") default-directory)
                        5  ; Shallow search in home directory
                      8))  ; Deeper search in project directories
         (fd-cmd (format "fd --type f --hidden --follow --exclude .git --max-depth %d --color never"
                         max-depth))
         (candidates nil))
    ;; Load files synchronously (but fd is very fast with depth limits)
    (setq candidates (split-string (shell-command-to-string fd-cmd) "\n" t))
    (helm :sources
          (helm-build-in-buffer-source "fd"
            :data candidates
            :fuzzy-match t
            :action (lambda (candidate)
                      (find-file (expand-file-name candidate default-directory))))
          :buffer "*helm fd*"
          :prompt "Find file: ")))

(defun aj/helm-rg ()
  "Fast ripgrep search in project root (shallow, depth 3).
For deeper search use `aj/helm-rg-deep' or press C-c d in helm."
  (interactive)
  (require 'helm-ag)
  (let ((default-directory (aj/project-root))
        (helm-ag-base-command "rg --no-heading --vimgrep --smart-case --max-depth 3 -g !public/ -g !node_modules/ -g !.git/ -g !build/ -g !dist/"))
    (helm-ag default-directory)))

(defun aj/helm-rg-deep ()
  "Deep ripgrep search (no depth limit). Use sparingly on large repos."
  (interactive)
  (require 'helm-ag)
  (let ((default-directory (aj/project-root))
        (helm-ag-base-command "rg --no-heading --vimgrep --smart-case -g !public/ -g !node_modules/ -g !.git/ -g !build/ -g !dist/"))
    (helm-ag default-directory)))

;; ---------------------------------------------------------------------------
;; Iterative Deepening Search (throttled, CPU-friendly)
;; ---------------------------------------------------------------------------

(defvar aj/rg-iterative-max-depth 8
  "Maximum depth for iterative deepening search.")

(defun aj/helm-rg-iterative ()
  "Iterative deepening ripgrep search. Starts shallow, progressively deeper.
Prompts for max depth, then collects results level by level."
  (interactive)
  (require 'helm)
  (let* ((default-directory (aj/project-root))
         (pattern (read-string "Search pattern: "))
         (max-depth (read-number "Max depth (1-10): " 5))
         (all-results nil)
         (seen (make-hash-table :test 'equal)))
    (when (and pattern (not (string-empty-p pattern)))
      ;; Collect results depth by depth
      (dotimes (d max-depth)
        (let* ((depth (1+ d))
               (cmd (format "rg --no-heading --vimgrep --smart-case --max-depth %d -g !public/ -g !node_modules/ -g !.git/ -g !build/ -g !dist/ -- %s ."
                            depth
                            (shell-quote-argument pattern)))
               (output (shell-command-to-string cmd))
               (lines (split-string output "\n" t)))
          (message "Searching depth %d/%d... (%d results so far)"
                   depth max-depth (length all-results))
          (dolist (line lines)
            (unless (gethash line seen)
              (puthash line t seen)
              (push line all-results)))
          ;; Small delay to not hammer CPU
          (sit-for 0.1)))
      ;; Show results in helm
      (if (null all-results)
          (message "No results found for '%s'" pattern)
        (helm :sources
              (helm-build-sync-source (format "rg: %s" pattern)
                :candidates (nreverse all-results)
                :action (lambda (candidate)
                          (when (string-match "\\`\\([^:]+\\):\\([0-9]+\\):" candidate)
                            (find-file (expand-file-name (match-string 1 candidate)))
                            (goto-char (point-min))
                            (forward-line (1- (string-to-number (match-string 2 candidate))))))
                :persistent-action (lambda (candidate)
                                     (when (string-match "\\`\\([^:]+\\):\\([0-9]+\\):" candidate)
                                       (find-file-other-window (expand-file-name (match-string 1 candidate)))
                                       (goto-char (point-min))
                                       (forward-line (1- (string-to-number (match-string 2 candidate)))))))
              :buffer "*helm rg*")))))

;; Unified search dispatcher - choose your search method
(defun aj/search-menu ()
  "Display a menu to choose between different search methods."
  (interactive)
  (let ((choice (read-char-choice
                 "Search: [f]d [g]rep(shallow) [i]terative [D]eep [l]ocate [q]uit: "
                 '(?f ?g ?i ?D ?l ?q))))
    (pcase choice
      (?f (call-interactively #'aj/helm-fd))
      (?g (call-interactively #'aj/helm-rg))
      (?i (call-interactively #'aj/helm-rg-iterative))
      (?D (call-interactively #'aj/helm-rg-deep))
      (?l (call-interactively #'aj/helm-locate-wrapper))
      (?q (message "Search cancelled")))))


;; ---------------------------------------------------------------------------
;; Helm Configuration - Complete Fuzzy Finding System
;; ---------------------------------------------------------------------------

(use-package helm
  :straight t
  :demand t  ; Load immediately to avoid function definition errors
  :init
  (setq helm-mode-fuzzy-match t
        helm-completion-in-region-fuzzy-match t
        helm-M-x-fuzzy-match t
        helm-buffers-fuzzy-matching t
        helm-locate-fuzzy-match t
        helm-apropos-fuzzy-match t
        helm-lisp-fuzzy-completion t
        helm-recentf-fuzzy-match t
        helm-ff-fuzzy-matching t
        ;; Performance tuning
        helm-candidate-number-limit 500
        helm-input-idle-delay 0.01
        helm-exit-idle-delay 0)
  :bind (("M-x" . helm-M-x)
         ("C-x C-f" . helm-find-files)
         ("C-x b" . helm-mini)
         ("C-s" . helm-occur)
         ("C-x r b" . helm-filtered-bookmarks)
         ("s-f" . aj/helm-fd)              ; Command+F for fuzzy file finding (project)
         ("s-F" . aj/helm-fd-async)        ; Command+Shift+F for deep async search
         ("s-l" . aj/helm-locate-wrapper)  ; Command+L for system-wide locate
         ("s-g" . aj/helm-rg-iterative)    ; Command+G for iterative ripgrep (CPU-friendly)
         ("s-G" . aj/helm-rg-deep)         ; Command+Shift+G for deep ripgrep
         ("s-s" . aj/search-menu))         ; Command+S for search menu
  :config
  (helm-mode 1))

(use-package helm-ag
  :straight t
  :after helm
  :config
  (setq helm-ag-fuzzy-match t
        helm-ag-insert-at-point 'symbol))

(use-package helm-ls-git
  :straight t
  :after helm
  :commands helm-browse-project
  :bind (("C-x g" . helm-browse-project))
  :config
  (setq helm-ls-git-fuzzy-match t))

;; ---------------------------------------------------------------------------
;; OPTIONAL: Native fzf integration (uncomment if you prefer fzf)
;; ---------------------------------------------------------------------------
;; If you want to use native fzf instead of helm-fd, uncomment below and rebind s-f:
;;
;; (use-package fzf
;;   :straight t
;;   :bind (("s-f" . fzf-find-file)
;;          ("s-d" . fzf-directory))
;;   :config
;;   (setq fzf/args "-x --color bw --print-query --margin=1,0 --no-hscroll"
;;         fzf/executable "fzf"
;;         fzf/git-grep-args "-i --line-number %s"
;;         fzf/grep-command "grep -nrH"
;;         fzf/position-bottom t
;;         fzf/window-height 15))

(setq bookmark-save-flag 1)   ; save after every change

(use-package ox-hugo
  :straight t
  :after ox)

(use-package org-roam
  :ensure t
  :custom
  (org-roam-directory (file-truename "~/Documents/new-site/content-org/"))
  :bind (("C-c n l" . org-roam-buffer-toggle)
         ("C-c n f" . org-roam-node-find)
         ("C-c n g" . org-roam-graph)
         ("C-c n i" . org-roam-node-insert)
         ("C-c n c" . org-roam-capture)
         ("C-c n I" . org-roam-node-insert-immediate))
  :init
  ;; Load dailies module BEFORE :bind-keymap so the keymap exists
  (require 'org-roam-dailies)
  :bind-keymap
  ("C-c d" . org-roam-dailies-map)
  :config
  ;; Require cl-lib for cl-defmethod
  (require 'cl-lib)

  ;; Add extra bindings to dailies map
  (define-key org-roam-dailies-map (kbd "Y") #'org-roam-dailies-capture-yesterday)
  (define-key org-roam-dailies-map (kbd "T") #'org-roam-dailies-capture-tomorrow)
  (define-key org-roam-dailies-map (kbd "F") #'aj/org-roam-dailies-goto-next-day)
  (define-key org-roam-dailies-map (kbd "B") #'aj/org-roam-dailies-goto-previous-day)

  ;; Dailies capture template with day of week
  ;; * Tasks is created by refile function when needed, not in template
  (setq org-roam-dailies-capture-templates
        '(("d" "default" entry
           "* %(aj/dailies-entry-prefix)%?"
           :target (file+head "%<%Y-%m-%d>.org"
                              "#+title: %<%Y-%m-%d> | %<%A>\n#+EXPORT_FILE_NAME: %<%Y-%m-%d>\n"))))

  ;; If you're using a vertical completion framework, you might want a more informative completion interface
  (org-roam-db-autosync-mode)
  ;; If using org-roam-protocol
  (require 'org-roam-protocol)
  (setq find-file-visit-truename t)

  ;; Custom node type method - must be inside :config so org-roam-node class exists
  (cl-defmethod org-roam-node-type ((node org-roam-node))
    "Return the TYPE of NODE."
    (condition-case nil
        (file-name-nondirectory
         (directory-file-name
          (file-name-directory
           (file-relative-name (org-roam-node-file node) org-roam-directory))))
      (error "")))

  (setq org-roam-node-display-template
        (concat "${type:15} ${title:*} " (propertize "${tags:10}" 'face 'org-tag)))

  (setq org-roam-capture-templates
        '(("r" "roam" plain "%?"
           :target (file+head "roam/${slug}.org"
                    ":PROPERTIES:\n:ID: %(org-id-uuid)\n:END:\n#+TITLE: ${title}\n#+EXPORT_FILE_NAME: ${slug}\n#+DATE: %<%Y-%m-%dT%H:%M:%S+11:00>\n")
           :unnarrowed t)
          ("p" "private" plain "%?"
           :target (file+head "private/${slug}.org"
                    ":PROPERTIES:\n:ID: %(org-id-uuid)\n:END:\n#+TITLE: ${title}\n#+EXPORT_FILE_NAME: ${slug}\n#+DATE: %<%Y-%m-%dT%H:%M:%S+11:00>\n")
           :unnarrowed t))))

;; Helper for dailies time prefix - shows time only for today's captures
(defun aj/dailies-entry-prefix ()
  "Return time prefix for today's captures, empty string otherwise."
  (let* ((capture-time (org-capture-get :default-time))
         (today (format-time-string "%Y-%m-%d"))
         (capture-date (format-time-string "%Y-%m-%d" capture-time)))
    (if (equal today capture-date)
        (format-time-string "%I:%M%p | " capture-time)
      "")))

;; Track dailies file for repositioning after capture
(defvar aj/--dailies-capture-file nil)

(defun aj/dailies-track-file ()
  "Track the dailies file being captured to."
  (when (org-roam-dailies--daily-note-p)
    (setq aj/--dailies-capture-file (buffer-file-name))))

(defun aj/dailies-reposition-entry ()
  "In dailies files, move any entries after * Tasks to before it."
  (when aj/--dailies-capture-file
    (let ((file aj/--dailies-capture-file))
      (setq aj/--dailies-capture-file nil)
      (with-current-buffer (find-file-noselect file)
        (save-excursion
          (goto-char (point-min))
          (when (re-search-forward "^\\* Tasks$" nil t)
            (let ((tasks-beg (line-beginning-position)))
              (goto-char (point-max))
              (when (and (re-search-backward "^\\* " tasks-beg t)
                         (> (point) tasks-beg))
                (let* ((entry-beg (point))
                       (entry-end (save-excursion
                                    (if (re-search-forward "^\\* " nil t)
                                        (line-beginning-position)
                                      (point-max))))
                       (entry-text (buffer-substring entry-beg entry-end)))
                  (delete-region entry-beg entry-end)
                  (goto-char tasks-beg)
                  (insert entry-text))))))
        (save-buffer)))))

(add-hook 'org-capture-before-finalize-hook #'aj/dailies-track-file)
(add-hook 'org-capture-after-finalize-hook #'aj/dailies-reposition-entry)

(defun aj/org-roam-dailies-goto-next-day ()
  "Go to the next day's daily note, creating it if necessary.
Unlike `org-roam-dailies-goto-next-note', this always goes to the
chronologically next day, not just the next existing note."
  (interactive)
  (unless (org-roam-dailies--daily-note-p)
    (user-error "Not in a daily-note"))
  (let* ((filename (file-name-sans-extension
                    (file-name-nondirectory (buffer-file-name))))
         (current-time (org-time-string-to-time filename))
         (next-time (time-add current-time 86400))) ; 86400 seconds = 1 day
    (org-roam-dailies--capture next-time t)))

(defun aj/org-roam-dailies-goto-previous-day ()
  "Go to the previous day's daily note, creating it if necessary.
Unlike `org-roam-dailies-goto-previous-note', this always goes to the
chronologically previous day, not just the previous existing note."
  (interactive)
  (unless (org-roam-dailies--daily-note-p)
    (user-error "Not in a daily-note"))
  (let* ((filename (file-name-sans-extension
                    (file-name-nondirectory (buffer-file-name))))
         (current-time (org-time-string-to-time filename))
         (prev-time (time-add current-time -86400))) ; -86400 seconds = -1 day
    (org-roam-dailies--capture prev-time t)))

(defun org-roam-node-insert-immediate (arg &rest args)
    "Insert an org-roam node link with immediate finish.
  Prompts for which capture template to use."
    (interactive "P")
    (let* ((candidates (mapcar (lambda (tpl)
                                 (cons (format "%s - %s" (car tpl) (cadr tpl))
                                       (car tpl)))
                               org-roam-capture-templates))
           (selection (completing-read "Template: " (mapcar #'car candidates)))
           (template-key (cdr (assoc selection candidates)))
           (template (assoc template-key org-roam-capture-templates))
           (args (cons arg args))
           (org-roam-capture-templates (list (append template
                                                     '(:immediate-finish t)))))
      (apply #'org-roam-node-insert args)))


;; Copy completed TODOs to today's daily note
(defun my/org-roam-copy-todo-to-today ()
  "Refile the current heading to today's daily note under the 'Tasks' heading."
  (interactive)
  (let ((org-refile-keep t) ;; Set to nil to move instead of copy
        (org-after-refile-insert-hook #'save-buffer)
        today-file
        pos)
    ;; Open today's daily and ensure "Tasks" heading exists
    (save-window-excursion
      (org-roam-dailies--capture (current-time) t)
      (setq today-file (buffer-file-name))
      ;; Create "Tasks" heading if it doesn't exist (for older dailies)
      (goto-char (point-min))
      (unless (re-search-forward "^\\* Tasks$" nil t)
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert "* Tasks\n"))
      ;; Get position of Tasks heading
      (goto-char (point-min))
      (re-search-forward "^\\* Tasks$" nil t)
      (setq pos (point))
      (save-buffer))

    ;; Only refile if the target file is different than the current file
    (unless (equal (file-truename today-file)
                   (file-truename (buffer-file-name)))
      (org-refile nil nil (list "Tasks" today-file nil pos)))))

(add-to-list 'org-after-todo-state-change-hook
             (lambda ()
               (when (equal org-state "DONE")
                 (my/org-roam-copy-todo-to-today))))


;;(defun org-roam-node-insert-immediate (arg &rest args)
;;  (interactive "P")
;;  (let ((args (cons arg args))
;;        (org-roam-capture-templates (list (append (car org-roam-capture-templates)
;;                                                  '(:immediate-finish t)))))
;;    (apply #'org-roam-node-insert args)))

(require 'info)

(with-eval-after-load 'info
  (add-to-list 'Info-directory-list
               (expand-file-name "straight/build/org-roam/" user-emacs-directory)))



;; ---------------------------------------------------------------------------
;; Org-transclusion - get v2.0.0-rc from development branch
;; ---------------------------------------------------------------------------

(use-package org-transclusion
  :straight (:host github :repo "nobiot/org-transclusion")
  :after org
  :bind (("C-c t a" . org-transclusion-add)
         ("C-c t m" . org-transclusion-transient-menu)
         ("C-c t t" . org-transclusion-mode))
  :init
  ;; Define the variable if it doesn't exist to avoid "void variable" error
  (unless (boundp 'org-transclusion-indent-mode)
    (defvar org-transclusion-indent-mode nil
      "Whether to enable indent mode for transclusions."))
  :config
  ;; Font-lock mode is enabled by default, but we ensure it here
  (require 'org-transclusion-font-lock)
  ;; Custom face coloring for transclusion fringe
  (set-face-attribute
    'org-transclusion-fringe t
    :foreground "#73c936"
    :background "#73c936")
  (org-transclusion-font-lock-mode +1))

(use-package org-roam-ui
  :bind (("C-c n r" . org-roam-ui-mode))
  :straight
    (:host github :repo "org-roam/org-roam-ui" :branch "main" :files ("*.el" "out"))
    :after org-roam
;;         normally we'd recommend hooking orui after org-roam, but since org-roam does not have
;;         a hookable mode anymore, you're advised to pick something yourself
;;         if you don't care about startup time, use
;;  :hook (after-init . org-roam-ui-mode)
    :config
    (setq org-roam-ui-sync-theme t
          org-roam-ui-follow t
          org-roam-ui-update-on-save t
          org-roam-ui-open-on-start t))

;; ---------------------------------------------------------------------------
;; GPTel - LLM integration with Claude
;; ---------------------------------------------------------------------------

(use-package gptel
  :straight t
  :config
  (require 'auth-source)
  ;; Set Claude as the default backend
  (setq gptel-model 'claude-sonnet-4-20250514
        gptel-backend (gptel-make-anthropic "Claude"
                        :stream t
                        :key (auth-source-pick-first-password
                              :host "api.anthropic.com")))
  :bind (("C-c g g" . gptel)              ; Open gptel chat buffer
         ("C-c g s" . gptel-send)         ; Send region/buffer to LLM
         ("C-c g m" . gptel-menu)         ; Quick settings menu
         ("C-c g r" . gptel-rewrite)))


(provide 'package-config)
;;; package-config.el ends here
