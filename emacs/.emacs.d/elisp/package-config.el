;;; package-config.el --- Package declarations and configurations -*- lexical-binding: t; -*-

;;; Commentary:
;; This file declares and configures all packages used in the configuration.

;;; Code:

(require 'use-package)

;; ---------------------------------------------------------------------------
;; Persistent History - save command/search/kill-ring history across sessions
;; ---------------------------------------------------------------------------

(use-package savehist
  :straight (:type built-in)
  :init
  (savehist-mode 1)
  :config
  (setq savehist-file (expand-file-name "savehist" user-emacs-directory)
        history-length 10000
        history-delete-duplicates t
        savehist-save-minibuffer-history t
        savehist-additional-variables
        '(kill-ring
          search-ring
          regexp-search-ring
          extended-command-history
          file-name-history
          command-history
          shell-command-history
          compile-history
          minibuffer-history
          read-expression-history
          register-alist
          bookmark-alist)))

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
  :custom
  (conda-anaconda-home "/opt/anaconda3")
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

;; ---------------------------------------------------------------------------
;; Tag Headings by Level - useful with anki-editor for bulk tagging
;; ---------------------------------------------------------------------------

(defun my/tag-headings-at-level (level tag)
  "Tag all org headings at LEVEL within the region with TAG.
Interactively prompts for level (default: current heading level) and tag."
  (interactive
   (list
    (read-number "Heading level: "
                 (save-excursion
                   (when (org-at-heading-p)
                     (org-current-level))))
    (read-string "Tag: ")))
  (save-excursion
    (let ((beg (region-beginning))
          (end (region-end))
          (count 0))
      (goto-char beg)
      (while (re-search-forward org-heading-regexp end t)
        (when (= (org-current-level) level)
          (org-set-tags (cons tag (org-get-tags nil t)))
          (setq count (1+ count))))
      (message "Tagged %d headings at level %d with :%s:" count level tag))))

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
  ;; V = capture to date (creates note if needed, prompts for date)
  (define-key org-roam-dailies-map (kbd "V") #'org-roam-dailies-capture-date)
  ;; r = refresh recurring tasks in current daily
  (define-key org-roam-dailies-map (kbd "r") #'aj/refresh-daily-recurring)
  ;; C = insert/refresh calendar in current daily
  (define-key org-roam-dailies-map (kbd "C") #'my/insert-aj-day-calendar)

  ;; Dailies capture template with day of week
  ;; Recurring tasks and Calendar are inserted by hook (aj/dailies-reposition-entry)
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

  (cl-defmethod org-roam-node-directories ((node org-roam-node))
    (if-let ((dirs (file-name-directory (file-relative-name (org-roam-node-file node) org-roam-directory))))
        (format "(%s)" (car (split-string dirs "/")))
      ""))

  (cl-defmethod org-roam-node-backlinkscount ((node org-roam-node))
    (let ((count (caar (org-roam-db-query
                        [:select (funcall count source)
                         :from links
                         :where (= dest $s1)
                         :and (= type "id")]
                        (org-roam-node-id node)))))
      (if (> count 0)
          (format "[%d]" count)
        "")))

  ;; Combined display template
  (setq org-roam-node-display-template
        (concat "${directories:10} "
                "${type:15} "
                "${title:*} "
                (propertize "${tags:10}" 'face 'org-tag)
                " ${backlinkscount:6}")))

(with-eval-after-load 'org-roam
  (setq org-roam-capture-templates
        '(("r" "roam" plain "%?"
           :target (file+head "roam/${slug}.org"
                    ":PROPERTIES:\n:ID: %(org-id-uuid)\n:END:\n#+TITLE: ${title}\n#+EXPORT_FILE_NAME: ${slug}\n#+DATE: %<%Y-%m-%dT%H:%M:%S+11:00>\n")
           :unnarrowed t)
          ("p" "private" plain "%?"
           :target (file+head "private/${slug}.org"
                    ":PROPERTIES:\n:ID: %(org-id-uuid)\n:END:\n#+TITLE: ${title}\n#+EXPORT_FILE_NAME: ${slug}\n#+DATE: %<%Y-%m-%dT%H:%M:%S+11:00>\n")
           :unnarrowed t)
          ("b" "book" plain "%?"
           :target (file+head "words/library/books/${slug}.org"
                    ":PROPERTIES:\n:ID: %(org-id-uuid)\n:END:\n#+TITLE: ${title}\n#+EXPORT_FILE_NAME: ${slug}\n#+DATE: %<%Y-%m-%dT%H:%M:%S+11:00>\n#+hugo_layout: book\n#+hugo_custom_front_matter: :toc true :author \n#+hugo_tags: \n#+hugo_auto_set_lastmod: t\n#+toc: headlines 2\n")
           :unnarrowed t))))

;; Recurring tasks for dailies (daily, alternating, weekly, biweekly, monthly, yearly)
(defvar aj/daily-templates-dir
  (expand-file-name "templates" org-roam-directory)
  "Directory containing recurring task templates.")

(defun aj/read-template-file (subdir filename)
  "Read template from SUBDIR/FILENAME under `aj/daily-templates-dir' if it exists.
Returns the trimmed file contents, or nil if file doesn't exist."
  (let ((path (expand-file-name (concat subdir "/" filename) aj/daily-templates-dir)))
    (when (file-exists-p path)
      (with-temp-buffer
        (insert-file-contents path)
        (string-trim (buffer-string))))))

;; Phase calculation functions
(defun aj/epoch-day (&optional time)
  "Return the number of days since Unix epoch for TIME (default: now)."
  (floor (/ (float-time (or time (current-time))) 86400)))

(defun aj/alternating-phase (&optional time)
  "Return alternating phase ('a' or 'b') for TIME based on epoch day parity."
  (if (= 0 (% (aj/epoch-day time) 2)) "a" "b"))

(defun aj/iso-week-parity (&optional time)
  "Return ISO week parity ('odd' or 'even') for TIME."
  (let ((week-num (string-to-number (format-time-string "%V" (or time (current-time))))))
    (if (= 1 (% week-num 2)) "odd" "even")))

(defun aj/iso-week-number (&optional time)
  "Return ISO week number for TIME."
  (string-to-number (format-time-string "%V" (or time (current-time)))))

(defun aj/get-recurring-tasks-for-date (time)
  "Return recurring tasks string for TIME.
Combines templates from all recurring sources."
  (let* ((day-name (downcase (format-time-string "%A" time)))
         (day-of-month (format-time-string "%d" time))
         (month-day (format-time-string "%m-%d" time))
         (alt-phase (aj/alternating-phase time))
         (week-parity (aj/iso-week-parity time))
         (results (list
                   (aj/read-template-file "" "daily.org")
                   (aj/read-template-file "alternating" (concat alt-phase ".org"))
                   (aj/read-template-file "weekly" (concat day-name ".org"))
                   (aj/read-template-file (concat "biweekly/" week-parity) (concat day-name ".org"))
                   (aj/read-template-file "monthly" (concat day-of-month ".org"))
                   (aj/read-template-file "yearly" (concat month-day ".org")))))
    (string-join (delq nil (delq "" results)) "\n")))

(defun aj/daily-recurring-tasks ()
  "Return recurring tasks for the capture date.
Combines templates from:
  - daily.org (every day)
  - alternating/<a|b>.org (every other day, epoch-based)
  - weekly/<dayname>.org (e.g., wednesday.org)
  - biweekly/<odd|even>/<dayname>.org (fortnightly)
  - monthly/<day>.org (e.g., 14.org for 14th of month)
  - yearly/<mm-dd>.org (e.g., 01-14.org for January 14th)"
  (let* ((capture-time (org-capture-get :default-time))
         (combined (aj/get-recurring-tasks-for-date capture-time)))
    (if (string-empty-p combined)
        ""
      (concat "\n" combined "\n"))))

(defun aj/refresh-daily-recurring ()
  "Refresh recurring tasks in the current daily note.
Parses date from #+title: line, fetches all recurring templates,
and inserts/replaces content under * Recurring heading (placed before Calendar)."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward "^#\\+title: \\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" nil t)
        (let* ((date-str (match-string 1))
               (parts (split-string date-str "-"))
               (year (string-to-number (nth 0 parts)))
               (month (string-to-number (nth 1 parts)))
               (day (string-to-number (nth 2 parts)))
               (date-time (encode-time 0 0 0 day month year))
               (tasks-raw (aj/get-recurring-tasks-for-date date-time))
               ;; Convert * headings to ** (subheadings under * Recurring)
               (tasks (replace-regexp-in-string "^\\* " "** " tasks-raw)))
          (if (string-empty-p tasks)
              (message "No recurring tasks for %s" date-str)
            ;; Find or create * Recurring heading
            (goto-char (point-min))
            (if (re-search-forward "^\\* Recurring$" nil t)
                ;; Found - delete existing content under it
                (let ((heading-end (line-end-position))
                      (section-end (save-excursion
                                     (forward-line 1)
                                     (if (re-search-forward "^\\* " nil t)
                                         (line-beginning-position)
                                       (point-max)))))
                  (delete-region (1+ heading-end) section-end))
              ;; Not found - create BEFORE Calendar or at end of front matter
              (goto-char (point-min))
              (cond
               ((re-search-forward "^\\* Calendar$" nil t)
                ;; Insert before Calendar heading
                (goto-char (line-beginning-position)))
               ((re-search-forward "^#\\+EXPORT_FILE_NAME:.*\n" nil t)
                (goto-char (match-end 0))
                (insert "\n"))
               (t (goto-char (point-max))))
              (insert "* Recurring\n\n"))
            ;; Insert tasks
            (goto-char (point-min))
            (re-search-forward "^\\* Recurring$" nil t)
            (forward-line 1)
            (insert "\n" tasks "\n")
            (message "Refreshed recurring tasks for %s" date-str)))
      (message "Not a daily note (no date in title)"))))

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
  (let ((file (buffer-file-name (org-capture-get :buffer))))
    (when (and file
               (string-match-p "/daily/[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\.org$" file))
      (setq aj/--dailies-capture-file file))))

(defun aj/dailies-reposition-entry ()
  "In dailies files, move any entries after * Tasks to before it.
Also inserts the day calendar if not already present."
  (when aj/--dailies-capture-file
    (let ((file aj/--dailies-capture-file))
      (setq aj/--dailies-capture-file nil)
      (with-current-buffer (find-file-noselect file)
        (save-excursion
          (goto-char (point-min))
          (when (re-search-forward "^\\* Tasks$" nil t)
            (let ((tasks-beg (line-beginning-position)))
              (goto-char (point-max))
              ;; Find any heading after Tasks
              (when (and (re-search-backward "^\\* " tasks-beg t)
                         (> (point) tasks-beg))
                (let* ((entry-beg (point))
                       (entry-end (save-excursion
                                    (forward-line 1)
                                    (if (re-search-forward "^\\* " nil t)
                                        (line-beginning-position)
                                      (point-max))))
                       (entry-text (buffer-substring entry-beg entry-end)))
                  (delete-region entry-beg entry-end)
                  (goto-char tasks-beg)
                  (insert entry-text))))))
        ;; Insert recurring and calendar if not present
        (save-excursion
          (goto-char (point-min))
          (unless (re-search-forward "^\\* Recurring$" nil t)
            (aj/refresh-daily-recurring)))
        (save-excursion
          (goto-char (point-min))
          (unless (re-search-forward "^\\* Calendar$" nil t)
            (my/insert-aj-day-calendar)))
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

(add-hook 'org-after-todo-state-change-hook
          (lambda ()
            (when (equal org-state "DONE")
              (my/org-roam-copy-todo-to-today))))


(defun my/insert-week-calendar ()
  "Insert formatted calendar under a Week N heading."
  (interactive)
  (save-excursion
    (org-back-to-heading t)
    (let* ((heading (org-get-heading t t t t))
           (week-num (and (string-match "Week \\([0-9]+\\)" heading)
                          (string-to-number (match-string 1 heading))))
           (base-year 2026)
           (month-greek ["α" "β" "γ" "δ" "ε" "ζ" "η" "θ" "ι" "κ" "λ" "μ"])
           (jan-4 (encode-time 0 0 0 4 1 base-year))
           (jan-4-dow (string-to-number (format-time-string "%u" jan-4)))
           (week-1-monday (time-subtract jan-4 (days-to-time (1- jan-4-dow))))
           (week-monday (time-add week-1-monday (days-to-time (* 7 (1- week-num)))))
           (week-thursday (time-add week-monday (days-to-time 3)))
           (cal-month (string-to-number (format-time-string "%m" week-thursday)))
           (cal-year (string-to-number (format-time-string "%Y" week-thursday)))
           (month-letter (aref month-greek (1- cal-month)))
           (cal-output (shell-command-to-string (format "cal %d %d" cal-month cal-year)))
           (lines (split-string cal-output "\n")))

      ;; Clean up after heading
      (org-end-of-meta-data t)
      (delete-horizontal-space)
      (when (looking-at "\n+")
        (replace-match ""))

      ;; Month title (centered over 31-char width to align with full header)
      (let* ((title (string-trim (car lines)))
             (padding (/ (- 31 (length title)) 2)))
        (insert (make-string padding ?\s) title "\n"))
      ;; Header: 5 spaces + day names (20 chars) + 6 spaces + Σ
      (insert (format "     %-20s      Σ   %s\n" (string-trim (nth 1 lines)) month-letter))

      ;; Day rows
      (let ((week-counter 1))
        (dolist (line (nthcdr 2 lines))
          (when (string-match "[0-9]" line)
            (let* ((trimmed (string-trim line))
                   (nums (split-string trimmed " " t))
                   (last-day (string-to-number (car (last nums))))
                   (date (encode-time 0 0 0 last-day cal-month cal-year))
                   (iso-wk (string-to-number (format-time-string "%V" date)))
                   (line-20 (substring (concat line "                    ") 0 20)))

              (if (= iso-wk week-num)
                  ;; Bold: (4 + first_digit_pos) leading spaces + *numbers*
                  (let* ((first-digit-pos (string-match "[0-9]" line-20))
                         (leading-count (+ 4 first-digit-pos))
                         (numbers (string-trim-right (substring line-20 first-digit-pos)))
                         (bold-line (concat (make-string leading-count ?\s) "*" numbers "*")))
                    ;; 26-char bold content + 4 spaces = position 30
                    (insert (format "%-26s    %2d   %d\n" bold-line iso-wk week-counter)))
                ;; Normal: 5 spaces + 20-char cal line + 5 spaces
                (insert (format "     %s     %2d   %d\n" line-20 iso-wk week-counter)))
              (setq week-counter (1+ week-counter)))))))))

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

(defun my/insert-day-calendar ()
  "Insert formatted calendar for a daily org-roam note.
Parses date from #+title: YYYY-MM-DD line, widens the day-of-week column,
and bolds the specific date."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^#\\+title: \\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" nil t)
      (let* ((date-str (match-string 1))
             (parts (split-string date-str "-"))
             (year (string-to-number (nth 0 parts)))
             (month (string-to-number (nth 1 parts)))
             (day (string-to-number (nth 2 parts)))
             (date (encode-time 0 0 0 day month year))
             (dow (string-to-number (format-time-string "%w" date)))
             (month-greek ["α" "β" "γ" "δ" "ε" "ζ" "η" "θ" "ι" "κ" "λ" "μ"])
             (month-letter (aref month-greek (1- month)))
             (cal-output (shell-command-to-string (format "cal %d %d" month year)))
             (lines (split-string cal-output "\n")))

        ;; Find or create * Calendar heading
        (goto-char (point-min))
        (if (re-search-forward "^\\* Calendar$" nil t)
            ;; Found it - go to end of heading, clear existing content
            (progn
              (org-end-of-meta-data t)
              (delete-horizontal-space)
              (when (looking-at "\n+")
                (replace-match "\n")))
          ;; Not found - create after front matter
          (goto-char (point-min))
          (if (re-search-forward "^#\\+EXPORT_FILE_NAME:.*\n" nil t)
              (goto-char (match-end 0))
            (goto-char (point-max)))
          (insert "\n* Calendar\n"))

        ;; Title line: centered over 25 chars, then Σ α headers
        (let* ((title (string-trim (car lines)))
               (title-len (length title))
               (center-width 25)
               (left-pad (/ (- center-width title-len) 2))
               (right-pad (- center-width left-pad title-len)))
          (insert (make-string left-pad ?\s) title (make-string right-pad ?\s))
          (insert (format "     Σ   %s\n" month-letter)))

        ;; Day names header with widened column
        (insert (my/format-day-cal-header dow) "\n")

        ;; Day rows
        (let ((week-counter 1))
          (dolist (line (nthcdr 2 lines))
            (when (string-match "[0-9]" line)
              (let* ((days (my/parse-cal-days line))
                     (last-day (car (last (remq nil days))))
                     (date-end (encode-time 0 0 0 last-day month year))
                     (iso-wk (string-to-number (format-time-string "%V" date-end)))
                     (formatted (my/format-day-cal-line days day dow)))
                (insert (format "%s     %d   %d\n" formatted iso-wk week-counter))
                (setq week-counter (1+ week-counter))))))))))

(defun my/format-number-with-commas (n)
  "Format integer N with comma thousand separators."
  (let ((s (number-to-string n)))
    (while (string-match "\\(.*[0-9]\\)\\([0-9]\\{3\\}\\)\\'" s)
      (setq s (concat (match-string 1 s) "," (match-string 2 s))))
    s))

(defun my/insert-aj-day-calendar ()
  "Insert formatted calendar for a daily org-roam note with life stats.
Parses date from #+title: YYYY-MM-DD line, widens the day-of-week column,
bolds the specific date.
Σ column: Day of year (cumulative days elapsed in current year).
ω column: Days elapsed since December 26, 2001 (AJ's birthday)."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^#\\+title: \\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" nil t)
      (let* ((date-str (match-string 1))
             (parts (split-string date-str "-"))
             (year (string-to-number (nth 0 parts)))
             (month (string-to-number (nth 1 parts)))
             (day (string-to-number (nth 2 parts)))
             (date (encode-time 0 0 0 day month year))
             (dow (string-to-number (format-time-string "%w" date)))
             ;; Birthday: December 26, 2001
             (birthday (encode-time 0 0 0 26 12 2001))
             (cal-output (shell-command-to-string (format "cal %d %d" month year)))
             (lines (split-string cal-output "\n")))

        ;; Find or create * Calendar heading
        (goto-char (point-min))
        (if (re-search-forward "^\\* Calendar$" nil t)
            ;; Found it - go to end of heading, clear existing content
            (progn
              (org-end-of-meta-data t)
              (delete-horizontal-space)
              (when (looking-at "\n+")
                (replace-match "\n")))
          ;; Not found - create after front matter
          (goto-char (point-min))
          (if (re-search-forward "^#\\+EXPORT_FILE_NAME:.*\n" nil t)
              (goto-char (match-end 0))
            (goto-char (point-max)))
          (insert "\n* Calendar\n"))

        ;; Title line: centered over 25 chars, then Σ ω headers
        ;; Σ is 3-char wide (max 366), ω is 6-char wide (e.g., "8,786")
        (let* ((title (string-trim (car lines)))
               (title-len (length title))
               (center-width 25)
               (left-pad (/ (- center-width title-len) 2))
               (right-pad (- center-width left-pad title-len)))
          (insert (make-string left-pad ?\s) title (make-string right-pad ?\s))
          (insert "   Σ       ω\n"))

        ;; Day names header with widened column
        (insert (my/format-day-cal-header dow) "\n")

        ;; Day rows
        (dolist (line (nthcdr 2 lines))
          (when (string-match "[0-9]" line)
            (let* ((days (my/parse-cal-days line))
                   (last-day (car (last (remq nil days))))
                   (date-end (encode-time 0 0 0 last-day month year))
                   ;; Day of year for last day in row
                   (day-of-year (string-to-number (format-time-string "%j" date-end)))
                   ;; Days alive: difference from birthday to date-end
                   (days-alive (floor (/ (float-time (time-subtract date-end birthday)) 86400)))
                   (formatted (my/format-day-cal-line days day dow)))
              (insert (format "%s %3d  %6s\n"
                              formatted
                              day-of-year
                              (my/format-number-with-commas days-alive))))))))))

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

(use-package org-side-tree
  :straight (:host github :repo "localauthor/org-side-tree")
  :after org
  :bind (("C-c o s" . org-side-tree)))

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


;; ---------------------------------------------------------------------------
;; Bytelocker - custom plugin; neovim port
;; ---------------------------------------------------------------------------
(use-package bytelocker
  :straight (:type git :host github :repo "abaj8494/bytelocker.el")
  :config
  (bytelocker-setup))


(provide 'package-config)
;;; package-config.el ends here
