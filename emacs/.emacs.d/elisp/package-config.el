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

;; Enable visual-line-mode in text modes (including org-mode)
(add-hook 'text-mode-hook #'visual-line-mode)

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
  :straight (:host github :repo "anki-editor/anki-editor")
  :custom
  (anki-editor-latex-style 'mathjax))

;; ---------------------------------------------------------------------------
;; Fix inline src blocks to use same syntax highlighting as src blocks
;; ---------------------------------------------------------------------------

(defun aj/org-html-inline-src-block (inline-src-block _contents _info)
  "Export INLINE-SRC-BLOCK with proper syntax highlighting.
Fontifies directly with htmlize, bypassing org-babel entirely."
  (require 'htmlize)
  (let* ((lang (org-element-property :language inline-src-block))
         (code (org-element-property :value inline-src-block))
         (mode (and lang (org-src-get-lang-mode lang)))
         (fontified
          (if (and mode (fboundp mode))
              (with-temp-buffer
                ;; Insert code and fontify with the language's major mode
                (insert code)
                ;; delay-mode-hooks prevents any hooks (including babel) from running
                (delay-mode-hooks (funcall mode))
                (font-lock-ensure)
                ;; Convert fontified buffer to HTML via htmlize
                (let* ((htmlize-output-type 'inline-css)
                       (html (htmlize-region-for-paste (point-min) (point-max))))
                  ;; htmlize wraps in <pre>, strip it for inline use
                  (if (string-match "<pre[^>]*>\\(\\(?:.\\|\n\\)*?\\)</pre>" html)
                      (match-string 1 html)
                    html)))
            ;; Fallback: no highlighting
            (org-html-encode-plain-text code))))
    (format "<code class=\"src src-%s\">%s</code>"
            (or lang "")
            (string-trim fontified))))

(advice-add 'org-html-inline-src-block :override #'aj/org-html-inline-src-block)

;; Add \( \) and \[ \] to mathjax delimiters (upstream only handles $ and $$)
(with-eval-after-load 'anki-editor
  (setq anki-editor--mathjax-delimiters
        (append anki-editor--mathjax-delimiters
                (list (list (concat "^" (regexp-quote "\\("))
                            "\\("
                            (concat (regexp-quote "\\)") "$")
                            "\\)")
                      (list (concat "^" (regexp-quote "\\["))
                            "\\["
                            (concat (regexp-quote "\\]") "$")
                            "\\]")))))

;; Disable babel evaluation during anki-editor export (we want code, not results)
(with-eval-after-load 'anki-editor
  (advice-add 'anki-editor--export-string :around
              (lambda (orig-fn &rest args)
                "Disable babel evaluation during anki-editor export."
                (let ((org-export-use-babel nil)
                      (org-confirm-babel-evaluate nil))
                  (apply orig-fn args)))))

(use-package ankiorg
  :straight (:host github :repo "orgtre/ankiorg")
  :custom
  (ankiorg-sql-database
   "~/Library/Application Support/Anki2/j/collection.anki2")
  (ankiorg-media-directory
   "~/Library/Application Support/Anki2/j/collection.media/")
  :config
  ;; Use SQL mode when Anki is closed, AnkiConnect when Anki is open
  ;; Toggle with: (ankiorg-sql-minor-mode)
  ;; Currently using AnkiConnect (requires Anki running)

  ;; Disable the "risky!" nested-list HTML regex that causes
  ;; "Stack overflow in regexp matcher" on complex notes.
  ;; Pandoc handles malformed HTML fine without this pre-processing.
  (setq ankiorg-anki-replacements nil)

  ;; Preserve <iframe> tags through pandoc conversion as @@html:...@@
  (define-advice ankiorg--html-to-org-with-pandoc (:override (html) aj/preserve-iframes)
    "Convert HTML to org with pandoc, preserving iframes as @@html:...@@."
    (let ((iframes (make-hash-table :test 'equal))
          (counter 0))
      (with-temp-buffer
        (insert html)
        ;; Extract iframes before pandoc, replace with placeholders
        (goto-char (point-min))
        (while (re-search-forward "<iframe[^>]*>[^<]*</iframe>" nil t)
          (let ((placeholder (format "ANKIORG_IFRAME_%d" counter))
                (iframe (match-string 0)))
            (puthash placeholder iframe iframes)
            (replace-match placeholder t t)
            (setq counter (1+ counter))))
        ;; Run pandoc
        (ankiorg--clean-anki)
        (unless (zerop
                 (call-process-region (point-min) (point-max) "pandoc"
                                     t t nil
                                     "--wrap=none"
                                     "-f" "html-raw_html-native_divs" "-t" "org"))
          (error "pandoc failed"))
        (ankiorg--clean-pandoc-output)
        ;; Restore iframes as @@html:...@@
        (goto-char (point-min))
        (while (re-search-forward "ANKIORG_IFRAME_[0-9]+" nil t)
          (let ((iframe (gethash (match-string 0) iframes)))
            (when iframe
              (replace-match (concat "@@html:" iframe "@@") t t))))
        (buffer-string))))

  ;; Fix AnkiConnect query for deck names with special characters
  (define-advice ankiorg-ancon-note-ids (:override (&optional deck) aj/fix-special-chars)
    "Get note IDs via AnkiConnect, properly escaping deck names."
    (anki-editor-api-call-result
     'findNotes
     :query (if deck
                ;; Quote deck name to handle spaces, commas, parentheses
                (concat "\"deck:" deck "\"")
              "")))

  ;; Reduce logging verbosity - log every 200 notes instead of every note
  (defvar aj/ankiorg-log-interval 200
    "Log progress every N notes during ankiorg operations.")

  (define-advice ankiorg-create-org-notes (:override (note-ids &optional deck) aj/batch-logging)
    "Create org notes with batch logging every `aj/ankiorg-log-interval' notes."
    (setq notes (ankiorg-get-convert-notes-from-anki note-ids deck))
    (setq number-of-notes (length notes))
    (let ((i 1))
      (dolist (note notes)
        (when (or (= i 1)
                  (= (% i aj/ankiorg-log-interval) 0)
                  (= i number-of-notes))
          (message "Creating org note %d/%d from Anki." i number-of-notes))
        (ankiorg--create-org-note note)
        (setq i (1+ i))))
    (message "Done creating %d new org notes from Anki." number-of-notes))

  (define-advice ankiorg-update-org-notes (:override (note-ids &optional scope) aj/batch-logging)
    "Update org notes with batch logging every `aj/ankiorg-log-interval' notes."
    (setq notes (ankiorg-get-convert-notes-from-anki note-ids))
    (setq number-of-notes (length notes))
    (let ((i 1))
      (dolist (note notes)
        (when (or (= i 1)
                  (= (% i aj/ankiorg-log-interval) 0)
                  (= i number-of-notes))
          (message "Updating org note %d/%d from Anki." i number-of-notes))
        (ankiorg--update-org-note note scope)
        (setq i (1+ i))))
    (message "Done updating %d org notes from Anki." number-of-notes)))

;; ---------------------------------------------------------------------------
;; Async wrapper for ankiorg-pull-notes
;; ---------------------------------------------------------------------------
(use-package async
  :straight t)

(defvar ankiorg-pull-notes-async-process nil
  "Current async process for ankiorg-pull-notes.")

(defun ankiorg-pull-notes-async (deck &optional scope)
  "Run `ankiorg-pull-notes' asynchronously in a child Emacs process.
Analysis and confirmation happen synchronously in main Emacs.
Only the heavy lifting (delete/create/update) runs async.
DECK and SCOPE are as in `ankiorg-pull-notes'."
  (interactive (list (ankiorg-pick-deck)
                     (when current-prefix-arg
                       (ankiorg-pick-scope))))
  (when (and ankiorg-pull-notes-async-process
             (process-live-p ankiorg-pull-notes-async-process))
    (user-error "Ankiorg pull already in progress"))
  (let ((file (buffer-file-name)))
    (unless file
      (user-error "Buffer must be visiting a file"))

    ;; Phase 1: Synchronous analysis in main Emacs
    (message "Ankiorg: analyzing deck '%s'..." deck)
    (let* ((ids-in-org-deck (ankiorg-org-note-ids deck scope))
           (ids-in-org (ankiorg-all-org-note-ids))
           (ids-in-anki-deck (funcall ankiorg-anki-note-ids-function deck))
           (ids-in-anki (funcall ankiorg-anki-note-ids-function))
           ;; Compute what needs to be done
           (ids-in-org-deck-deduped (delete-dups (copy-sequence ids-in-org-deck)))
           (ids-deck-org-not-anki (cl-set-difference ids-in-org-deck-deduped ids-in-anki-deck))
           (ids-deck-changed-away (cl-intersection ids-deck-org-not-anki ids-in-anki))
           (ids-deck-deleted (cl-set-difference ids-deck-org-not-anki ids-in-anki))
           (ids-deck-anki-not-org (cl-set-difference ids-in-anki-deck ids-in-org-deck-deduped))
           (ids-deck-changed-to (cl-intersection ids-deck-anki-not-org ids-in-org))
           (ids-deck-created (cl-set-difference ids-deck-anki-not-org ids-in-org))
           (ids-deck-anki-org (cl-intersection ids-in-anki-deck ids-in-org-deck-deduped))
           (ids-to-update (append ids-deck-changed-away ids-deck-changed-to ids-deck-anki-org))
           ;; Build summary
           (summary-message
            (format
             (concat
              "The following changes to deck '%s' will be pulled from Anki:\n\n"
              "%d notes moved to another deck -- to be updated in org.\n"
              "%d notes deleted -- to be deleted in org.\n"
              "%d notes added from another deck -- to be updated in org.\n"
              "%d notes created -- to be created in org.\n"
              "%d notes unchanged in the above ways -- to be updated in org.\n")
             deck
             (length ids-deck-changed-away)
             (length ids-deck-deleted)
             (length ids-deck-changed-to)
             (length ids-deck-created)
             (length ids-deck-anki-org))))

      ;; Phase 2: Confirmation in main Emacs
      (unless (yes-or-no-p (concat summary-message "\nContinue? "))
        (user-error "Ankiorg pull cancelled"))

      ;; Phase 3: Async execution of heavy operations
      (message "Ankiorg: pulling deck '%s' asynchronously..." deck)
      (setq ankiorg-pull-notes-async-process
            (async-start
             `(lambda ()
                ;; Auto-accept prompts BEFORE loading config
                (fset 'yes-or-no-p (lambda (&rest _) (message "  [auto-yes]") t))
                (fset 'y-or-n-p (lambda (&rest _) (message "  [auto-y]") t))
                (fset 'read-char-choice (lambda (prompt chars &rest _) (car chars)))
                (message "[ankiorg-async] Starting subprocess...")
                ;; Load user's Emacs config
                (setq user-emacs-directory ,(expand-file-name user-emacs-directory))
                (message "[ankiorg-async] Loading init.el...")
                (load ,(expand-file-name "init.el" user-emacs-directory) nil t)
                (message "[ankiorg-async] Config loaded. Opening file...")
                ;; Open the file
                (find-file ,file)
                (message "[ankiorg-async] File opened. Starting operations...")
                (condition-case err
                    (progn
                      ;; Run the three operations with pre-computed ID lists
                      (message "[ankiorg-async] Deleting %d notes..." ,(length ids-deck-deleted))
                      (ankiorg-delete-org-notes ',ids-deck-deleted ',scope)
                      (message "[ankiorg-async] Creating %d notes..." ,(length ids-deck-created))
                      (ankiorg-create-org-notes ',ids-deck-created ,deck)
                      (message "[ankiorg-async] Updating %d notes..." ,(length ids-to-update))
                      (ankiorg-update-org-notes ',ids-to-update ',scope)
                      (message "[ankiorg-async] Saving buffer...")
                      (save-buffer)
                      (message "[ankiorg-async] Done!")
                      (list 'success ,deck
                            ,(length ids-deck-deleted)
                            ,(length ids-deck-created)
                            ,(length ids-to-update)))
                  (error
                   (message "[ankiorg-async] ERROR: %s" (error-message-string err))
                   (list 'error (error-message-string err)))))
             (lambda (result)
               (setq ankiorg-pull-notes-async-process nil)
               (pcase result
                 (`(success ,deck ,deleted ,created ,updated)
                  (start-process "ankiorg-done-sound" nil "afplay" "/System/Library/Sounds/Glass.aiff")
                  (message "Ankiorg: finished deck '%s' (deleted:%d created:%d updated:%d). Reverting..."
                           deck deleted created updated)
                  (revert-buffer t t t))
                 (`(error ,msg)
                  (start-process "ankiorg-error-sound" nil "afplay" "/System/Library/Sounds/Basso.aiff")
                  (message "Ankiorg pull failed: %s" msg))
                 (_ (message "Ankiorg pull completed")))))))))

;; ---------------------------------------------------------------------------
;; AnkiConnect: Pull Flagged Notes with Quickfix Navigation
;; ---------------------------------------------------------------------------

(defvar ankiorg-search-directories '("~/Documents/new-site/content-org/flashcards")
  "Directories to search for org files containing Anki note IDs.")

(defun ankiorg--anki-connect (action params)
  "Make an AnkiConnect request with ACTION and PARAMS."
  (let* ((url-request-method "POST")
         (url-request-extra-headers '(("Content-Type" . "application/json")))
         (url-request-data
          (json-encode `((action . ,action) (version . 6) (params . ,params))))
         (buffer (url-retrieve-synchronously "http://127.0.0.1:8765" t t 5)))
    (unless buffer
      (error "Cannot connect to AnkiConnect. Is Anki running?"))
    (unwind-protect
        (with-current-buffer buffer
          (goto-char url-http-end-of-headers)
          (let ((json-object-type 'alist))
            (cdr (assoc 'result (json-read)))))
      (kill-buffer buffer))))

(defun ankiorg-pull-flagged-notes (&optional flag)
  "Pull notes with FLAG from Anki and grep org files for quickfix navigation.
FLAG: 1=red, 2=orange, 3=green, 4=blue, 5=pink, 6=turquoise, 7=purple.
With prefix arg, prompts for flag number. Defaults to 1 (red)."
  (interactive
   (list (if current-prefix-arg
             (read-number "Flag (1=red 2=orange 3=green 4=blue): " 1)
           1)))
  (let* ((flag (or flag 1))
         (flag-names '((1 . "red") (2 . "orange") (3 . "green")
                       (4 . "blue") (5 . "pink") (6 . "turquoise") (7 . "purple")))
         (flag-name (cdr (assoc flag flag-names)))
         (note-ids (ankiorg--anki-connect "findNotes"
                                          `((query . ,(format "flag:%d" flag))))))
    (if (or (null note-ids) (= (length note-ids) 0))
        (message "No notes found with %s flag" flag-name)
      (let ((notes-info (ankiorg--anki-connect "notesInfo" `((notes . ,note-ids)))))
        (message "Found %d %s-flagged notes. Searching org files..."
                 (length notes-info) flag-name)
        (ankiorg--grep-for-notes notes-info flag-name)))))

(defun ankiorg--extract-search-term (note)
  "Extract a searchable term from NOTE's first field."
  (let* ((fields (cdr (assoc 'fields note)))
         (first-field (cdr (car fields)))
         (val (or (cdr (assoc 'value first-field)) "")))
    ;; Strip HTML
    (setq val (replace-regexp-in-string "<[^>]*>" "" val))
    (setq val (replace-regexp-in-string "&nbsp;" " " val))
    (setq val (replace-regexp-in-string "&lt;" "<" val))
    (setq val (replace-regexp-in-string "&gt;" ">" val))
    ;; Strip cloze markers like {{c1::...}}
    (setq val (replace-regexp-in-string "{{c[0-9]+::\\([^}]*\\)}}" "\\1" val))
    (setq val (string-trim val))
    (substring val 0 (min 60 (length val)))))

(defun ankiorg--grep-for-notes (notes-info flag-name)
  "Grep for NOTES-INFO in org files and display in quickfix buffer."
  (let* ((note-ids (mapcar (lambda (n) (cdr (assoc 'noteId n))) notes-info))
         (id-to-content
          (mapcar (lambda (n)
                    (cons (cdr (assoc 'noteId n))
                          (ankiorg--extract-search-term n)))
                  notes-info))
         (search-dir (expand-file-name (car ankiorg-search-directories))))
    (with-current-buffer (get-buffer-create "*Anki Flagged Notes*")
      (let ((inhibit-read-only t)
            (found-ids nil))
        (erase-buffer)
        (insert (format "-*- mode: grep; default-directory: \"%s\" -*-\n\n"
                        search-dir))
        (insert (format "Anki %s-flagged notes (%d total):\n\n" flag-name (length note-ids)))
        ;; Search for each note ID individually
        (dolist (note-id note-ids)
          (let ((grep-output
                 (shell-command-to-string
                  (format "grep -rn --include='*.org' '%s' %s 2>/dev/null"
                          (number-to-string note-id) search-dir))))
            (when (not (string-empty-p grep-output))
              (push note-id found-ids)
              (let ((content (cdr (assoc note-id id-to-content))))
                (dolist (line (split-string grep-output "\n" t))
                  (when (string-match "\\([^:]+\\):\\([0-9]+\\):" line)
                    (insert (format "%s:%s: %s\n"
                                    (match-string 1 line)
                                    (match-string 2 line)
                                    content))))))))
        ;; Show notes NOT found
        (let ((missing (seq-filter (lambda (id) (not (member id found-ids))) note-ids)))
          (when missing
            (insert (format "\n── Notes NOT FOUND in org files (%d) ──\n\n"
                            (length missing)))
            (dolist (id missing)
              (insert (format "  ID %s: %s\n" id (cdr (assoc id id-to-content))))))))
      (grep-mode)
      (goto-char (point-min))
      (condition-case nil
          (compilation-next-error 1 nil (point-min))
        (error (goto-char (point-min))))
      (switch-to-buffer (current-buffer))
      (message "Use M-g M-n / M-g M-p to navigate, RET to jump"))))

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
          (end (copy-marker (region-end)))
          (count 0))
      (goto-char beg)
      (while (re-search-forward org-heading-regexp end t)
        (when (= (org-current-level) level)
          (org-set-tags (cons tag (org-get-tags nil t)))
          (setq count (1+ count))))
      (set-marker end nil)
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
;; Interactive Ripgrep Search (async, depth-limited for safety)
;; ---------------------------------------------------------------------------

(defun aj/helm-rg-iterative (&optional arg)
  "Interactive ripgrep search with live fuzzy filtering.
Uses async process to avoid freezing Emacs.
With prefix ARG, search from current directory instead of project root."
  (interactive "P")
  (require 'helm-ag)
  (let* ((search-dir (if arg
                         default-directory
                       (aj/project-root)))
         (helm-ag-base-command "rg --no-heading --vimgrep --smart-case --max-depth 6 -g !*~ -g !public/ -g !node_modules/ -g !.git/ -g !build/ -g !dist/")
         (helm-ag-insert-at-point nil))
    (message "Searching in: %s" search-dir)
    (helm-do-ag search-dir)))

;; Unified search dispatcher - choose your search method
(defun aj/search-menu ()
  "Display a menu to choose between different search methods."
  (interactive)
  (let ((choice (read-char-choice
                 "Search: [f]d [g]rep(shallow) [i]nteractive [D]eep [l]ocate [q]uit:"
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
  (helm-mode 1)
  ;; Protect against pathological regex patterns (like \| which matches everywhere)
  (defun aj/pattern-matches-empty-p (pattern)
    "Return t if PATTERN matches the empty string (pathological)."
    (and pattern
         (not (string-empty-p pattern))
         (condition-case nil
             (string-match-p pattern "")
           (error nil))))
  ;; Hook into helm's update cycle to skip pathological patterns
  (defun aj/helm-occur-skip-pathological (orig-fun &rest args)
    "Skip re-search-forward if pattern matches empty string."
    (let ((pattern (car args)))
      (if (aj/pattern-matches-empty-p pattern)
          nil  ; Return nil to indicate no match
        (apply orig-fun args))))
  ;; Advise re-search-forward only during helm-occur
  (defvar aj/helm-occur-active nil)
  (defun aj/helm-occur-wrapper (orig-fun &rest args)
    "Run helm-occur with pathological pattern protection."
    (let ((aj/helm-occur-active t))
      (apply orig-fun args)))
  (advice-add 'helm-occur :around #'aj/helm-occur-wrapper)
  (defun aj/re-search-forward-safe (orig-fun pattern &rest args)
    "Block re-search-forward for pathological patterns during helm-occur."
    (if (and aj/helm-occur-active (aj/pattern-matches-empty-p pattern))
        nil
      (apply orig-fun pattern args)))
  (advice-add 're-search-forward :around #'aj/re-search-forward-safe))

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

(with-eval-after-load 'ox-hugo
  (defun my/org-hugo--generate-custom-id (heading)
    "Generate a CUSTOM_ID from HEADING text."
    (let ((id (downcase heading)))
      (setq id (replace-regexp-in-string "[^a-z0-9-]+" "-" id))
      (setq id (replace-regexp-in-string "-+" "-" id))
      (setq id (replace-regexp-in-string "^-\\|-$" "" id))
      id))

  ;; Fix resolution: strip ::* suffix so base ID resolves
  (defun my/org-export-resolve-id-link--strip-search (orig-fun link info)
    "Strip ::search suffix before resolving id: links."
    (let* ((path (org-element-property :path link))
           (parts (split-string path "::"))
           (id (car parts)))
      (when (cadr parts)
        ;; Has search suffix - temporarily strip it for resolution
        (org-element-put-property link :path id))
      (funcall orig-fun link info)))

  (advice-add 'org-export-resolve-id-link :around
              #'my/org-export-resolve-id-link--strip-search)

  ;; Fix transcoding: output correct link with anchor
  (defun my/org-hugo-link--handle-id-search (orig-fun link desc info)
    "Handle id:UUID::*heading links for ox-hugo."
    (let* ((type (org-element-property :type link))
           (path (org-element-property :path link))
           ;; Check for search in original raw-link since :path may be stripped
           (raw-link (org-element-property :raw-link link))
           (has-search (and raw-link (string-match-p "::" raw-link))))
      (if (and (string= type "id") has-search)
          (let* ((parts (split-string raw-link "::"))
                 (id (string-remove-prefix "id:" (car parts)))
                 (search (string-remove-prefix "*" (cadr parts)))
                 (location (org-id-find id)))
            (if location
                (let* ((target-file (car location))
                       (pos (cdr location))
                       (source-file (plist-get info :input-file))
                       (source-dir (file-name-directory source-file))
                       custom-id
                       relative-path)
                  (with-current-buffer (find-file-noselect target-file)
                    (org-with-wide-buffer
                     (goto-char pos)
                     (when (re-search-forward
                            (concat "^\\*+ +" (regexp-quote search))
                            nil t)
                       (beginning-of-line)
                       (setq custom-id (org-entry-get (point) "CUSTOM_ID"))
                       (unless custom-id
                         (setq custom-id (my/org-hugo--generate-custom-id search))
                         (org-set-property "CUSTOM_ID" custom-id)
                         (save-buffer)
                         (message "Created CUSTOM_ID '%s' for heading '%s' in %s"
                                  custom-id search target-file)))))
                  (if custom-id
                      (progn
                        (setq relative-path
                              (concat (file-name-sans-extension
                                       (file-relative-name target-file source-dir))
                                      ".md"))
                        (format "[%s]({{< relref \"%s#%s\" >}})"
                                (or desc search)
                                relative-path
                                custom-id))
                    (funcall orig-fun link desc info)))
              (funcall orig-fun link desc info)))
        (funcall orig-fun link desc info))))

  (advice-add 'org-hugo-link :around #'my/org-hugo-link--handle-id-search))

(use-package org-roam
  :ensure t
  :custom
  (org-roam-directory (file-truename "~/Documents/new-site/content-org/"))
  :bind (("C-c a" . org-agenda)
         ("C-c n l" . org-roam-buffer-toggle)
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
  (define-key org-roam-dailies-map (kbd "c") #'org-roam-dailies-capture-date)
  (define-key org-roam-dailies-map (kbd "g") #'org-roam-dailies-goto-date)
  (define-key org-roam-dailies-map (kbd "T") #'org-roam-dailies-capture-tomorrow)
  (define-key org-roam-dailies-map (kbd "F") #'aj/org-roam-dailies-goto-next-day)
  (define-key org-roam-dailies-map (kbd "B") #'aj/org-roam-dailies-goto-previous-day)
  ;; V = capture to date (creates note if needed, prompts for date)
  (define-key org-roam-dailies-map (kbd "V") #'org-roam-dailies-capture-date)
  ;; w = insert week transclude in current daily
  (define-key org-roam-dailies-map (kbd "w") #'aj/insert-week-transclude)

  ;; Create refresh keymap: C-c d r <key>
  (defvar aj/daily-refresh-map (make-sparse-keymap)
    "Keymap for daily refresh operations under C-c d r.")
  (define-key aj/daily-refresh-map (kbd "c") #'my/insert-aj-day-calendar)
  (define-key aj/daily-refresh-map (kbd "r") #'aj/refresh-daily-recurring)
  (define-key aj/daily-refresh-map (kbd "w") #'aj/refresh-daily-week)
  ;; Bind refresh map to r in dailies map
  (define-key org-roam-dailies-map (kbd "r") aj/daily-refresh-map)

  ;; Dailies capture template with day of week
  ;; Entries go under * Capture heading; other sections inserted by hook
  (setq org-roam-dailies-capture-templates
        '(("d" "default" entry
           "** %(aj/dailies-entry-prefix)%?"
           :target (file+head+olp "%<%Y-%m-%d>.org"
                                  "#+title: %<%Y-%m-%d> | %<%A>\n#+EXPORT_FILE_NAME: %<%Y-%m-%d>\n"
                                  ("Capture"))
           :empty-lines-before 1)))

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

;; Yearly file configuration for week transclusion
(defvar aj/yearly-file-ids
  '((2026 . "51fe6c3d-45e2-4655-bc1c-9358f989d02a"))
  "Alist mapping years to their yearly org file IDs.")

(defvar aj/yearly-file-names
  '((2026 . "twenty-twenty-six"))
  "Alist mapping years to their yearly org file display names.")

(defun aj/daily-date-file-p (&optional file)
  "Return t if FILE matches YYYY-MM-DD.org pattern (actual daily note).
Excludes yearly files like twenty_twenty_six.org."
  (let ((path (or file (buffer-file-name))))
    (and path
         (string-match-p "/daily/[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\.org$" path))))

(defun aj/get-week-heading-info (week-num year)
  "Get the ID and title of Week WEEK-NUM heading tagged with YEAR.
Returns (id . title) or nil if not found."
  (let* ((year-tag (number-to-string year))
         (title-pattern (format "Week %d%%" week-num))
         (result (org-roam-db-query
                  [:select [nodes:id nodes:title]
                   :from nodes
                   :left-join tags :on (= nodes:id tags:node-id)
                   :where (and (like nodes:title $s1)
                               (= tags:tag $s2))]
                  title-pattern year-tag)))
    (when result
      (let ((row (car result)))
        (cons (car row) (cadr row))))))

(defun aj/insert-week-transclude ()
  "Insert linked week heading and transclude directive.
Parses date from filename, calculates ISO week, inserts a heading
linking to the week node followed by transclude directive."
  (interactive)
  (save-excursion
    (when (and buffer-file-name
               (string-match "\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)\\.org$"
                             buffer-file-name))
      (let* ((year-str (match-string 1 buffer-file-name))
             (month-str (match-string 2 buffer-file-name))
             (day-str (match-string 3 buffer-file-name))
             (year (string-to-number year-str))
             (month (string-to-number month-str))
             (day (string-to-number day-str))
             (date-time (encode-time 0 0 0 day month year))
             (week-num (aj/iso-week-number date-time))
             (file-id (cdr (assoc year aj/yearly-file-ids)))
             (file-name (cdr (assoc year aj/yearly-file-names)))
             (week-info (aj/get-week-heading-info week-num year))
             (week-id (car week-info))
             (week-title (cdr week-info)))
        (when (and file-id file-name)
          (goto-char (point-min))
          ;; Find insertion point (after EXPORT_FILE_NAME line)
          (if (re-search-forward "^#\\+EXPORT_FILE_NAME:.*$" nil t)
              (progn
                (goto-char (match-end 0))
                (if (and week-id week-title)
                    ;; New format with linked heading
                    (insert (format "\n\n* [[id:%s][%s]]\n#+transclude: [[id:%s::* Week %d][%s]] :no-first-heading\n"
                                    week-id week-title file-id week-num file-name))
                  ;; Fallback without week heading ID (shouldn't happen normally)
                  (insert (format "\n\n* Week %d\n#+transclude: [[id:%s::* Week %d][%s]] :no-first-heading\n"
                                  week-num file-id week-num file-name))))
            ;; Fallback: insert at end of front matter
            (when (re-search-forward "^:END:$" nil t)
              (forward-line 1)
              (if (and week-id week-title)
                  (insert (format "\n* [[id:%s][%s]]\n#+transclude: [[id:%s::* Week %d][%s]] :no-first-heading\n"
                                  week-id week-title file-id week-num file-name))
                (insert (format "\n* Week %d\n#+transclude: [[id:%s::* Week %d][%s]] :no-first-heading\n"
                                week-num file-id week-num file-name))))))))))

(defun aj/read-template-file (subdir filename &optional time)
  "Read template from SUBDIR/FILENAME under `aj/daily-templates-dir' if it exists.
TIME is used to replace <TODAY ...> placeholders with actual dates.
Returns the file contents with trailing whitespace trimmed, or nil if file doesn't exist."
  (let ((path (expand-file-name
               (if (string-empty-p subdir)
                   filename
                 (concat subdir "/" filename))
               aj/daily-templates-dir)))
    (when (file-exists-p path)
      (with-temp-buffer
        (insert-file-contents path)
        ;; Only trim trailing whitespace to preserve internal blank lines
        (let ((content (string-trim-right (buffer-string))))
          (if time
              (aj/replace-date-placeholders content time)
            content))))))

(defun aj/replace-date-placeholders (content time)
  "Replace <TODAY ...> placeholders in CONTENT with actual org timestamps for TIME."
  (let ((date-str (format-time-string "%Y-%m-%d %a" time)))
    ;; Replace <TODAY HH:MM> with <YYYY-MM-DD Day HH:MM>
    (setq content (replace-regexp-in-string
                   "<TODAY \\([0-9]\\{2\\}:[0-9]\\{2\\}\\)>"
                   (lambda (match)
                     (format "<%s %s>" date-str (match-string 1 match)))
                   content))
    ;; Replace bare <TODAY> with <YYYY-MM-DD Day>
    (setq content (replace-regexp-in-string
                   "<TODAY>"
                   (format "<%s>" date-str)
                   content))
    content))

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

(defun aj/is-weekday-p (time)
  "Return t if TIME is a weekday (Monday-Friday), nil otherwise."
  (let ((dow (string-to-number (format-time-string "%u" time))))
    (<= dow 5)))

(defun aj/get-recurring-tasks-for-date (time)
  "Return recurring tasks string for TIME.
Combines templates from all recurring sources."
  (let* ((day-name (downcase (format-time-string "%A" time)))
         (day-of-month (format-time-string "%d" time))
         (month-day (format-time-string "%m-%d" time))
         (alt-phase (aj/alternating-phase time))
         (week-parity (aj/iso-week-parity time))
         (results (list
                   (aj/read-template-file "" "daily.org" time)
                   (when (aj/is-weekday-p time)
                     (aj/read-template-file "" "weekdays.org" time))
                   (aj/read-template-file "alternating" (concat alt-phase ".org") time)
                   (aj/read-template-file "weekly" (concat day-name ".org") time)
                   (aj/read-template-file (concat "biweekly/" week-parity) (concat day-name ".org") time)
                   (aj/read-template-file "monthly" (concat day-of-month ".org") time)
                   (aj/read-template-file "yearly" (concat month-day ".org") time))))
    (string-join (delq nil (delq "" results)) "\n\n")))

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

(defun aj/recurring-heading-exists-p (heading)
  "Check if HEADING already exists under * Recurring.
Matches regardless of TODO state (TODO/DONE/WAIT/CANCEL) or priority."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^\\* Recurring\\b" nil t)
      (let ((section-end (save-excursion
                           (if (re-search-forward "^\\* " nil t)
                               (line-beginning-position)
                             (point-max)))))
        (re-search-forward
         (format "^\\*\\* \\(?:TODO \\|DONE \\|WAIT \\|CANCEL \\)?\\(?:\\[#[A-Z]\\] \\)?%s\\(?:[ \t]*$\\|[ \t]\\)"
                 (regexp-quote heading))
         section-end t)))))

(defun aj/extract-heading-name (line)
  "Extract heading name from LINE, stripping TODO keywords and priority."
  (when (string-match "^\\*+ \\(?:TODO \\|DONE \\|WAIT \\|CANCEL \\)?\\(?:\\[#[A-Z]\\] \\)?\\(.+\\)$" line)
    (match-string 1 line)))

(defun aj/extract-heading-order (tasks)
  "Extract ordered list of heading names from TASKS string."
  (let ((headings nil))
    (dolist (line (split-string tasks "\n"))
      (when (string-match "^\\*\\* \\(?:TODO \\|DONE \\|WAIT \\|CANCEL \\)?\\(?:\\[#[A-Z]\\] \\)?\\(.+\\)$" line)
        (push (match-string 1 line) headings)))
    (nreverse headings)))

(defun aj/refresh-daily-recurring ()
  "Refresh recurring tasks in the current daily note.
Parses date from #+title: line, fetches all recurring templates.
Only ADDS new tasks - does not replace or modify existing ones.
Maintains template order even when some headings already exist."
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
               ;; Increment all heading levels by 1 (subheadings under * Recurring)
               (tasks (replace-regexp-in-string "^\\(\\*+\\) " "*\\1 " tasks-raw))
               (added-count 0))
          (if (string-empty-p tasks)
              (message "No recurring tasks for %s" date-str)
            ;; Populate heading order for correct insertion positions
            (setq aj/recurring-heading-order (aj/extract-heading-order tasks))
            ;; Ensure Recurring heading exists at correct position
            (aj/ensure-heading-exists "Recurring")
            ;; Parse each task block and only add if not already present
            (let ((task-lines (split-string tasks "\n"))
                  (current-heading nil)
                  (current-block nil))
              ;; Group lines by heading
              (dolist (line task-lines)
                (cond
                 ;; New heading found
                 ((string-match "^\\*\\* " line)
                  ;; Process previous block if exists
                  (when (and current-heading
                             (not (aj/recurring-heading-exists-p
                                   (aj/extract-heading-name current-heading))))
                    (aj/insert-recurring-block current-heading (nreverse current-block))
                    (setq added-count (1+ added-count)))
                  (setq current-heading line
                        current-block nil))
                 ;; Content line
                 (t (push line current-block))))
              ;; Process final block
              (when (and current-heading
                         (not (aj/recurring-heading-exists-p
                               (aj/extract-heading-name current-heading))))
                (aj/insert-recurring-block current-heading (nreverse current-block))
                (setq added-count (1+ added-count))))
            (if (> added-count 0)
                (message "Added %d recurring task(s) for %s" added-count date-str)
              (message "All recurring tasks already present for %s" date-str))))
      (message "Not a daily note (no date in title)"))))

(defvar aj/recurring-heading-order nil
  "Ordered list of recurring heading names, populated during refresh.")

(defun aj/find-recurring-insert-point (heading-name)
  "Find correct insertion point for HEADING-NAME under * Recurring.
Uses `aj/recurring-heading-order' to maintain template order."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^\\* Recurring\\b" nil t)
      (let* ((section-start (line-end-position))
             (section-end (save-excursion
                            (forward-line 1)
                            (if (re-search-forward "^\\* " nil t)
                                (line-beginning-position)
                              (point-max))))
             (pos (cl-position heading-name aj/recurring-heading-order :test 'equal))
             (later-headings (when pos (nthcdr (1+ pos) aj/recurring-heading-order))))
        ;; Find first existing heading that should come AFTER this one
        (catch 'found
          (dolist (next-heading later-headings)
            (goto-char section-start)
            (when (re-search-forward
                   (format "^\\*\\* \\(?:TODO \\|DONE \\|WAIT \\|CANCEL \\)?\\(?:\\[#[A-Z]\\] \\)?%s\\b"
                           (regexp-quote next-heading))
                   section-end t)
              (throw 'found (line-beginning-position))))
          ;; No later heading found, insert at end of section
          section-end)))))

(defun aj/insert-recurring-block (heading content-lines)
  "Insert HEADING and CONTENT-LINES at correct position under * Recurring.
Maintains template order by inserting before later headings.
Ensures exactly one blank line before the heading."
  (let* ((heading-name (aj/extract-heading-name heading))
         (insert-point (aj/find-recurring-insert-point heading-name)))
    (when insert-point
      (save-excursion
        (goto-char insert-point)
        ;; Ensure we're at beginning of line
        (unless (bolp) (insert "\n"))
        ;; Check if previous line is blank; if not, add one
        (when (save-excursion
                (forward-line -1)
                (not (looking-at-p "^[ \t]*$")))
          (insert "\n"))
        (insert heading "\n")
        ;; Insert all content lines, including blank lines for proper spacing
        (dolist (line content-lines)
          (insert line "\n"))))))

;; Helper for dailies time prefix - shows time only for today's captures
(defun aj/dailies-entry-prefix ()
  "Return time prefix for today's captures, empty string otherwise."
  (let* ((capture-time (org-capture-get :default-time))
         (today (format-time-string "%Y-%m-%d"))
         (capture-date (format-time-string "%Y-%m-%d" capture-time)))
    (if (equal today capture-date)
        (format-time-string "%I:%M%p " capture-time)
      "")))

;; Track dailies file for repositioning after capture
(defvar aj/--dailies-capture-file nil)

;; Track captured entry heading for optional jump (position gets stale after buffer modifications)
(defvar aj/--dailies-capture-heading nil
  "Heading text of the newly captured dailies entry.")

(defun aj/dailies-store-capture-marker ()
  "Store identifier of the captured entry for optional jump.
Stores heading text instead of position since buffer modifications
(separator insertion, recurring task refresh) shift positions."
  (let* ((buf (org-capture-get :buffer))
         (file (and buf (buffer-file-name buf))))
    ;; Check if this is a dailies capture
    (when (and file
               (string-match-p "/daily/[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\.org$" file))
      (setq aj/--dailies-capture-file file)
      ;; Store the heading text to search for later
      (with-current-buffer buf
        (save-excursion
          (goto-char (org-capture-get :insertion-point))
          (when (org-at-heading-p)
            (setq aj/--dailies-capture-heading
                  (org-get-heading t t t t))))))))

(defun aj/dailies-prompt-jump-to-capture ()
  "Prompt user to jump to the newly captured dailies entry.
Searches for heading text instead of using stored position, since
buffer modifications (separator insertion, recurring task refresh)
shift positions after capture."
  (when (and aj/--dailies-capture-file aj/--dailies-capture-heading)
    (let ((file aj/--dailies-capture-file)
          (heading aj/--dailies-capture-heading))
      (setq aj/--dailies-capture-heading nil)
      (when (y-or-n-p "Jump to captured entry? ")
        (switch-to-buffer (find-file-noselect file))
        (widen)
        (goto-char (point-min))
        ;; Search for the heading under * Capture section
        (if (re-search-forward "^\\* Capture\\b" nil t)
            (let ((section-end (save-excursion
                                 (if (re-search-forward "^\\* " nil t)
                                     (point)
                                   (point-max)))))
              (if (re-search-forward
                   (format "^\\*\\* .*%s" (regexp-quote heading))
                   section-end t)
                  (progn
                    (beginning-of-line)
                    (org-reveal)
                    (recenter))
                (message "Could not find captured entry: %s" heading)))
          (message "Could not find Capture section"))))))

(defun aj/dailies-track-file ()
  "Track the dailies file being captured to."
  (let ((file (buffer-file-name (org-capture-get :buffer))))
    (when (and file
               (string-match-p "/daily/[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\.org$" file))
      (setq aj/--dailies-capture-file file))))

(defun aj/dailies-reposition-entry ()
  "Setup daily file after capture.
Inserts week transclude, ensures heading structure, and populates content.
Entries are placed under * Capture by the capture template."
  (when aj/--dailies-capture-file
    (let ((file aj/--dailies-capture-file))
      (setq aj/--dailies-capture-file nil)
      (with-current-buffer (find-file-noselect file)
        ;; 1. Insert week transclude if not present
        ;; Check both raw directive AND rendered heading (in case transclusion already active)
        (save-excursion
          (goto-char (point-min))
          (unless (or (re-search-forward "^#\\+transclude:" nil t)
                      (progn (goto-char (point-min))
                             (re-search-forward "^\\* \\(\\[\\[id:[^]]+\\]\\[\\)?Week [0-9]+" nil t)))
            (aj/insert-week-transclude)))
        ;; 2. Ensure all headings exist in correct order (with statistics cookies)
        (aj/ensure-daily-structure)
        ;; 3. Update statistics cookies (stripped before capture, restored here)
        (org-update-statistics-cookies t)
        ;; 4. Refresh recurring tasks
        (aj/refresh-daily-recurring)
        ;; 4b. Re-run heading separators after recurring content is inserted
        ;; (recurring tasks may have displaced the separators)
        (aj/ensure-heading-separators)
        ;; 5. Insert calendar content
        (save-excursion
          (goto-char (point-min))
          ;; Only insert calendar content if heading is empty
          (when (re-search-forward "^\\* Calendar\\b" nil t)
            (let ((heading-end (line-end-position))
                  (next-heading (save-excursion
                                  (forward-line 1)
                                  (if (re-search-forward "^\\* " nil t)
                                      (line-beginning-position)
                                    (point-max)))))
              ;; Check if there's no content between Calendar and next heading
              (when (< (- next-heading heading-end) 5)
                (my/insert-aj-day-calendar)))))
        ;; 6. Activate org-transclusion-mode to render the transclude
        (when (and (fboundp 'org-transclusion-mode)
                   (not (bound-and-true-p org-transclusion-mode)))
          (org-transclusion-mode 1))
        (save-buffer)))))

;; Desired order of level-1 headings in daily notes
(defvar aj/daily-heading-order
  '("Journal" "Recurring" "Calendar" "Capture" "Tasks")
  "Ordered list of level-1 headings for daily notes.")

(defun aj/find-heading-insert-point (heading)
  "Find the correct insertion point for HEADING based on `aj/daily-heading-order'.
Returns the position where the heading should be inserted."
  (let* ((pos (cl-position heading aj/daily-heading-order :test 'equal))
         (later-headings (nthcdr (1+ pos) aj/daily-heading-order)))
    ;; Find the first existing heading that should come after this one
    (catch 'found
      (dolist (next-heading later-headings)
        (save-excursion
          (save-restriction
            (widen)
            (goto-char (point-min))
            (when (re-search-forward (format "^\\* %s\\b" (regexp-quote next-heading)) nil t)
              (throw 'found (line-beginning-position))))))
      ;; No later heading found, insert at end of buffer
      nil)))

(defvar aj/headings-with-statistics '("Capture" "Tasks")
  "Headings that should have [/] statistics cookies.")

(defun aj/ensure-heading-exists (heading)
  "Ensure HEADING exists in the daily note at the correct position.
Returns t if heading was created, nil if it already existed."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (unless (re-search-forward (format "^\\* %s\\b" (regexp-quote heading)) nil t)
        (let ((insert-point (aj/find-heading-insert-point heading))
              (heading-text (if (member heading aj/headings-with-statistics)
                                (format "* %s [/]\n\n" heading)
                              (format "* %s\n\n" heading))))
          (if insert-point
              (progn
                (goto-char insert-point)
                (insert heading-text))
            ;; Insert at end
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (insert (concat "\n" heading-text))))
        t))))

(defun aj/ensure-heading-has-statistics-cookie (heading)
  "Ensure HEADING has a [/] statistics cookie if it should have one.
Only modifies headings listed in `aj/headings-with-statistics'."
  (when (member heading aj/headings-with-statistics)
    (save-excursion
      (save-restriction
        (widen)
        (goto-char (point-min))
        (when (re-search-forward (format "^\\(\\* %s\\)\\([ \t]*\\)$" (regexp-quote heading)) nil t)
          ;; Heading exists without cookie - add it
          (goto-char (match-end 1))
          (insert " [/]"))))))

(defun aj/ensure-daily-structure ()
  "Ensure the daily note has all required headings in the correct order.
Order: Journal, Recurring, Calendar, Capture, Tasks."
  (interactive)
  (when (aj/daily-date-file-p)
    (save-excursion
      (dolist (heading aj/daily-heading-order)
        (aj/ensure-heading-exists heading))
      ;; Ensure statistics cookies on headings that need them
      (dolist (heading aj/headings-with-statistics)
        (aj/ensure-heading-has-statistics-cookie heading))
      ;; Ensure ----- separators between level-1 headings
      (aj/ensure-heading-separators))))

(defun aj/ensure-heading-separators ()
  "Ensure ----- separators immediately before each level-1 heading except the first.
If a separator was displaced (e.g. by a capture inserting after it),
removes the stale separator and inserts a fresh one.  User-placed
separators earlier in the section are preserved."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((headings nil))
        ;; Collect all level-1 heading positions
        (while (re-search-forward "^\\* " nil t)
          (push (line-beginning-position) headings))
        (setq headings (nreverse headings))
        (let ((len (length headings)))
          (when (>= len 2)
            ;; Process from bottom to top so position shifts don't affect
            ;; headings we haven't processed yet
            (dotimes (j (1- len))
              (let* ((i (- len 1 j))
                     (heading-bol (nth i headings))
                     (section-start (save-excursion
                                      (goto-char (nth (1- i) headings))
                                      (forward-line 1) (point))))
                ;; Check if ----- is right above heading (skip blank lines)
                (goto-char heading-bol)
                (forward-line -1)
                (while (and (> (point) section-start)
                            (looking-at-p "^[ \t]*$"))
                  (forward-line -1))
                (unless (looking-at-p "^-----$")
                  ;; Remove the LAST ----- in this section (the displaced
                  ;; structural separator); earlier user-placed ones stay
                  (let ((last-beg nil) (last-end nil))
                    (goto-char section-start)
                    (while (re-search-forward "^-----$" heading-bol t)
                      (setq last-beg (line-beginning-position)
                            last-end (min (1+ (line-end-position)) (point-max))))
                    (when last-beg
                      (delete-region last-beg last-end)
                      (setq heading-bol (- heading-bol (- last-end last-beg)))))
                  ;; Insert fresh separator before heading
                  (goto-char heading-bol)
                  (unless (save-excursion (forward-line -1) (looking-at-p "^[ \t]*$"))
                    (insert "\n"))
                  (insert "-----\n\n"))))))))))

(defun aj/fold-week-heading ()
  "Fold the Week heading if present.
Matches both linked format (* [[id:...][Week N ...]]) and plain format (* Week N)."
  (when (aj/daily-date-file-p)
    (save-excursion
      (goto-char (point-min))
      ;; Match either: * [[id:...][Week N...]] or * Week N
      (when (re-search-forward "^\\* \\(\\[\\[id:[^]]+\\]\\[\\)?Week [0-9]+" nil t)
        (goto-char (line-beginning-position))
        (when (not (org-fold-folded-p (line-end-position)))
          (org-cycle))))))

;; ---------------------------------------------------------------------------
;; Weather via wttr.in (no API key required, includes icons)
;; ---------------------------------------------------------------------------

(defvar aj/wttr-location "Sydney"
  "Location for weather forecast (city name).")

(defun aj/wttr-icon (description)
  "Return a weather icon based on DESCRIPTION string."
  (let ((desc (downcase description)))
    (cond
     ((string-match-p "thunder\\|storm" desc) "⛈️")
     ((string-match-p "snow\\|sleet\\|blizzard" desc) "🌨️")
     ((string-match-p "heavy.*rain\\|pour\\|torrential" desc) "🌧️")
     ((string-match-p "rain\\|drizzle\\|shower" desc) "🌦️")
     ((string-match-p "fog\\|mist\\|haze" desc) "🌫️")
     ((string-match-p "cloudy\\|overcast" desc) "☁️")
     ((string-match-p "partly\\|partial" desc) "⛅")
     ((string-match-p "clear\\|sunny\\|sun" desc) "☀️")
     (t "🌡️"))))

;; ---------------------------------------------------------------------------
;; Modeline Weather Display (fully async)
;; ---------------------------------------------------------------------------

(defvar aj/modeline-weather-cache nil
  "Cached weather data: (date-str . formatted-string).")

(defvar aj/modeline-weather-cache-time nil
  "Time when weather cache was last updated.")

(defvar aj/modeline-weather-cache-duration 600
  "Seconds to cache weather data (default 10 minutes).")

(defvar aj/modeline-weather-fetching nil
  "Non-nil when weather fetch is in progress.")

(defun aj/parse-wttr-modeline-data (data target-date)
  "Parse wttr.in DATA and return formatted modeline string for TARGET-DATE."
  (let ((today (format-time-string "%Y-%m-%d"))
        (weather-days (alist-get 'weather data)))
    (if (string= target-date today)
        ;; Today: use current conditions
        (let* ((current (car (alist-get 'current_condition data)))
               (temp (alist-get 'temp_C current))
               (desc (alist-get 'weatherDesc current))
               (weather-desc (alist-get 'value (car desc)))
               (icon (aj/wttr-icon weather-desc))
               (today-forecast (car weather-days))
               (min-temp (alist-get 'mintempC today-forecast))
               (max-temp (alist-get 'maxtempC today-forecast)))
          (format "%s %s°C (%s-%s)" icon temp min-temp max-temp))
      ;; Other date: look in forecast
      (let ((result nil))
        (dolist (day weather-days)
          (when (string= (alist-get 'date day) target-date)
            (let* ((max-temp (alist-get 'maxtempC day))
                   (min-temp (alist-get 'mintempC day))
                   (hourly (alist-get 'hourly day))
                   (midday (or (nth 4 hourly) (nth 2 hourly) (car hourly)))
                   (desc (alist-get 'weatherDesc midday))
                   (weather-desc (alist-get 'value (car desc)))
                   (icon (aj/wttr-icon weather-desc)))
              (setq result (format "%s %s°C (%s-%s)" icon max-temp min-temp max-temp)))))
        result))))

(defun aj/modeline-weather-date ()
  "Return the date to show weather for.
In daily files: returns that file's date.
Otherwise: returns today's date."
  (if (and buffer-file-name (aj/daily-date-file-p))
      (save-excursion
        (goto-char (point-min))
        (if (re-search-forward "^#\\+title: \\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" nil t)
            (match-string-no-properties 1)
          (format-time-string "%Y-%m-%d")))
    (format-time-string "%Y-%m-%d")))

(defun aj/modeline-weather-update ()
  "Fetch weather asynchronously and update cache."
  (unless aj/modeline-weather-fetching
    (setq aj/modeline-weather-fetching t)
    (let ((target-date (format-time-string "%Y-%m-%d"))
          (url (format "https://wttr.in/%s?format=j1"
                       (url-hexify-string aj/wttr-location))))
      (url-retrieve
       url
       (lambda (status target-date)
         (unwind-protect
             (unless (plist-get status :error)
               (goto-char (point-min))
               (when (re-search-forward "\n\n" nil t)
                 (condition-case nil
                     (let* ((json-object-type 'alist)
                            (json-array-type 'list)
                            (data (json-read))
                            (weather (aj/parse-wttr-modeline-data data target-date)))
                       (when weather
                         (setq aj/modeline-weather-cache (cons target-date weather))
                         (setq aj/modeline-weather-cache-time (float-time))
                         (force-mode-line-update t)))
                   (error nil))))
           (setq aj/modeline-weather-fetching nil)
           (kill-buffer)))
       (list target-date)
       t t))))

(defun aj/modeline-weather ()
  "Return weather string for modeline, using cache when possible."
  (let* ((target-date (aj/modeline-weather-date))
         (now (float-time))
         (cache-valid (and aj/modeline-weather-cache
                           aj/modeline-weather-cache-time
                           (string= (car aj/modeline-weather-cache) target-date)
                           (< (- now aj/modeline-weather-cache-time)
                              aj/modeline-weather-cache-duration))))
    (if cache-valid
        (concat " " (cdr aj/modeline-weather-cache))
      ;; Trigger background fetch if not already running
      (unless aj/modeline-weather-fetching
        (run-with-idle-timer 1 nil #'aj/modeline-weather-update))
      ;; Return cached value (possibly stale) or empty while fetching
      (if aj/modeline-weather-cache
          (concat " " (cdr aj/modeline-weather-cache))
        ""))))

(defvar aj/modeline-weather-construct
  '(:eval (aj/modeline-weather))
  "Mode line construct for weather display.")

;; Ensure global-mode-string is a list before pushing
(unless (listp global-mode-string)
  (setq global-mode-string (list global-mode-string)))

;; Add to global mode line (like email)
(unless (member aj/modeline-weather-construct global-mode-string)
  (push aj/modeline-weather-construct global-mode-string))

;; Fetch weather on startup (like email updates counts on load)
(aj/modeline-weather-update)

(defun aj/refresh-daily-week ()
  "Refresh the week transclude for the current daily note.
Ensures the transclude exists and re-folds the heading.
Weather is now part of the Calendar section - use C-c d r c to refresh."
  (interactive)
  (unless (aj/daily-date-file-p)
    (user-error "Not in a daily note"))
  ;; Ensure week transclude exists
  (save-excursion
    (goto-char (point-min))
    (unless (or (re-search-forward "^#\\+transclude:" nil t)
                (progn (goto-char (point-min))
                       (re-search-forward "^\\* \\(\\[\\[id:[^]]+\\]\\[\\)?Week [0-9]+" nil t)))
      (aj/insert-week-transclude)))
  ;; Ensure transclusion is active
  (when (and (fboundp 'org-transclusion-mode)
             (not (bound-and-true-p org-transclusion-mode)))
    (org-transclusion-mode 1))
  ;; Re-fold the week heading
  (aj/fold-week-heading)
  (message "Week transclude refreshed"))

(defun aj/refresh-daily-calendar ()
  "Refresh calendar section for the current daily note.
Inserts calendar table and fetches weather data (including hourly if available)."
  (interactive)
  (unless (aj/daily-date-file-p)
    (user-error "Not in a daily note"))
  (my/insert-aj-day-calendar)
  (message "Calendar refreshed"))

(defun aj/daily-needs-setup-p ()
  "Return t if current daily file needs full setup.
Checks if the file is missing the Journal heading (indicates bare template)."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (not (re-search-forward "^\\* Journal\\b" nil t)))))

(defun aj/setup-daily-file ()
  "Run full setup for a daily file.
Inserts transclude, ensures headings, populates recurring and calendar."
  ;; 1. Insert week transclude if not present
  (save-excursion
    (goto-char (point-min))
    (unless (or (re-search-forward "^#\\+transclude:" nil t)
                (progn (goto-char (point-min))
                       (re-search-forward "^\\* \\(\\[\\[id:[^]]+\\]\\[\\)?Week [0-9]+" nil t)))
      (aj/insert-week-transclude)))
  ;; 2. Ensure all headings exist in correct order (with statistics cookies)
  (aj/ensure-daily-structure)
  ;; 3. Refresh recurring tasks
  (aj/refresh-daily-recurring)
  ;; 4. Update statistics cookies
  (save-excursion
    (dolist (heading aj/headings-with-statistics)
      (goto-char (point-min))
      (when (re-search-forward (format "^\\* %s\\b" (regexp-quote heading)) nil t)
        (org-update-statistics-cookies nil))))
  ;; 5. Insert calendar content
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^\\* Calendar\\b" nil t)
      (let ((heading-end (line-end-position))
            (next-heading (save-excursion
                            (forward-line 1)
                            (if (re-search-forward "^\\* " nil t)
                                (line-beginning-position)
                              (point-max)))))
        ;; Check if there's no content between Calendar and next heading
        (when (< (- next-heading heading-end) 5)
          (my/insert-aj-day-calendar))))))

;; Hook for file open - sets up new files and enables transclusion
(defun aj/daily-file-open-hook ()
  "Hook for opening daily files.
For new/bare files: runs full setup (transclude, headings, recurring, calendar).
For all files: enables transclusion, refreshes recurring tasks and calendar."
  (when (aj/daily-date-file-p)
    ;; Check if this is a new file that needs setup
    (if (aj/daily-needs-setup-p)
        (aj/setup-daily-file)
      ;; For existing files, refresh recurring and calendar content
      (aj/ensure-daily-structure)
      (aj/refresh-daily-recurring)
      (aj/ensure-heading-separators)
      (aj/refresh-daily-calendar))
    ;; Enable org-transclusion-mode to render transcludes
    (when (and (fboundp 'org-transclusion-mode)
               (not (bound-and-true-p org-transclusion-mode)))
      (org-transclusion-mode 1))
    ;; Save if we did setup
    (when (buffer-modified-p)
      (save-buffer))))

;; Strip statistics cookies from olp headings in daily files before org-roam
;; does heading matching, so that "* Capture [4/4]" still matches olp "Capture".
;; Cookies are restored by aj/dailies-reposition-entry after capture finalize.
(defun aj/strip-cookies-for-olp (orig-fn olp)
  "Around advice: strip statistics cookies in daily files before OLP matching."
  (when (and buffer-file-name
             (string-match-p "/daily/" buffer-file-name))
    (save-excursion
      (dolist (heading olp)
        (goto-char (point-min))
        (let ((re (format "^\\(\\*+ %s\\) \\[[0-9]*[/%%][0-9]*\\]"
                          (regexp-quote heading))))
          (when (re-search-forward re nil t)
            (replace-match (match-string 1)))))))
  (funcall orig-fn olp))

(advice-add 'org-roam-capture--find-or-create-olp :around #'aj/strip-cookies-for-olp)

(add-hook 'org-capture-before-finalize-hook #'aj/dailies-track-file)
(add-hook 'org-capture-before-finalize-hook #'aj/dailies-store-capture-marker)
(add-hook 'org-capture-after-finalize-hook #'aj/dailies-reposition-entry)
(add-hook 'org-capture-after-finalize-hook #'aj/dailies-prompt-jump-to-capture)
;; Fold Week heading when opening daily files
(add-hook 'org-roam-dailies-find-file-hook #'aj/daily-file-open-hook)

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
  "Refile the current heading to today's daily note under the 'Tasks' heading.
Preserves transclusion state in current buffer."
  (interactive)
  (let ((org-refile-keep t) ;; Set to nil to move instead of copy
        (org-after-refile-insert-hook #'save-buffer)
        (source-buffer (current-buffer))
        (source-transclusion-active (bound-and-true-p org-transclusion-mode))
        today-file
        pos)
    ;; Open today's daily and ensure "Tasks" heading exists
    (save-window-excursion
      (org-roam-dailies--capture (current-time) t)
      (setq today-file (buffer-file-name))
      ;; Create "Tasks" heading if it doesn't exist (for older dailies)
      (goto-char (point-min))
      (unless (re-search-forward "^\\* Tasks\\b" nil t)
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert "* Tasks [/]\n"))
      ;; Ensure cookie exists on Tasks heading
      (aj/ensure-heading-has-statistics-cookie "Tasks")
      ;; Get position of Tasks heading
      (goto-char (point-min))
      (re-search-forward "^\\* Tasks\\b" nil t)
      (setq pos (point))
      (save-buffer))

    ;; Only refile if the target file is different than the current file
    (unless (equal (file-truename today-file)
                   (file-truename (buffer-file-name)))
      (org-refile nil nil (list "Tasks" today-file nil pos))
      ;; Update statistics cookie in target file
      (with-current-buffer (find-file-noselect today-file)
        (save-excursion
          (goto-char (point-min))
          (when (re-search-forward "^\\* Tasks\\b" nil t)
            (org-update-statistics-cookies nil)))
        (save-buffer)))

    ;; Restore transclusion mode in source buffer if it was active
    (when (and source-transclusion-active
               (buffer-live-p source-buffer))
      (with-current-buffer source-buffer
        (unless (bound-and-true-p org-transclusion-mode)
          (org-transclusion-mode 1))))))

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

        ;; Ensure Calendar heading exists at correct position
        (aj/ensure-heading-exists "Calendar")
        ;; Find it and clear existing content
        (goto-char (point-min))
        (when (re-search-forward "^\\* Calendar\\b" nil t)
          (let ((heading-end (line-end-position))
                (section-end (save-excursion
                               (forward-line 1)
                               (if (re-search-forward "^\\* " nil t)
                                   (line-beginning-position)
                                 (point-max)))))
            (delete-region (1+ heading-end) section-end))
          (goto-char (line-end-position))
          (insert "\n\n"))

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

(defun aj/ensure-daily-id (date-str)
  "Ensure daily note exists for DATE-STR (YYYY-MM-DD). Returns org-roam ID.
Creates a minimal file with just ID and title if it doesn't exist.
Does not run hooks or add headings - those are added when the file is opened."
  (require 'org-roam)
  (require 'org-id)
  (let* ((parts (split-string date-str "-"))
         (year (string-to-number (nth 0 parts)))
         (month (string-to-number (nth 1 parts)))
         (day (string-to-number (nth 2 parts)))
         (date-time (encode-time 0 0 0 day month year))
         (day-name (format-time-string "%A" date-time))
         (daily-dir (expand-file-name
                     (or org-roam-dailies-directory "daily")
                     org-roam-directory))
         (file-path (expand-file-name (concat date-str ".org") daily-dir)))
    ;; Create minimal file if it doesn't exist
    (unless (file-exists-p file-path)
      (let ((id (org-id-uuid)))
        (make-directory daily-dir t)
        (with-temp-file file-path
          ;; Naked file: just properties and title, no headings
          (insert (format ":PROPERTIES:\n:ID:       %s\n:END:\n#+title: %s | %s\n#+EXPORT_FILE_NAME: %s\n"
                          id date-str day-name date-str)))
        ;; Update org-roam database for new file
        (org-roam-db-update-file file-path)))
    ;; Get ID from org-roam database
    (caar (org-roam-db-query
           [:select id :from nodes :where (= file $s1)]
           file-path))))

(defun my/format-day-cell (day-num target-day year month)
  "Format a calendar day cell for org table with ID links.
DAY-NUM is the day number (or nil for empty).
TARGET-DAY is the current day (bolded, no link).
YEAR and MONTH are used to build the ID link."
  (if (null day-num)
      "   "
    (if (= day-num target-day)
        ;; Current day: bold, no link
        (if (< day-num 10)
            (format "*%d*  " day-num)
          (format "*%d* " day-num))
      ;; Other days: get/create daily and link by ID
      (let* ((date-str (format "%04d-%02d-%02d" year month day-num))
             (id (aj/ensure-daily-id date-str))
             (link (format "[[id:%s][%d]]" id day-num)))
        (if (< day-num 10)
            (format "%s  " link)
          (format "%s " link))))))

(defun my/insert-aj-day-calendar ()
  "Insert formatted calendar for a daily org-roam note with life stats.
Parses date from #+title: YYYY-MM-DD line.
Outputs an org table with links to daily files.
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
             ;; Birthday: December 26, 2001
             (birthday (encode-time 0 0 0 26 12 2001))
             (cal-output (shell-command-to-string (format "cal %d %d" month year)))
             (lines (split-string cal-output "\n")))

        ;; Ensure Calendar heading exists at correct position
        (aj/ensure-heading-exists "Calendar")
        ;; Find it and clear existing content
        (goto-char (point-min))
        (when (re-search-forward "^\\* Calendar\\b" nil t)
          (let ((heading-end (line-end-position))
                (section-end (save-excursion
                               (forward-line 1)
                               (if (re-search-forward "^\\* " nil t)
                                   (line-beginning-position)
                                 (point-max)))))
            (delete-region (1+ heading-end) section-end))
          (goto-char (line-end-position))
          (insert "\n\n"))

        ;; Caption with month name
        (let ((month-name (format-time-string "%B %Y" date)))
          (insert (format "#+CAPTION: %s\n" month-name)))

        ;; Table header with top border
        (insert "|----+----+----+----+----+----+----+-------+--------|\n")
        (insert "| Su | Mo | Tu | We | Th | Fr | Sa | Σ(wk) | ω(dol) |\n")
        (insert "|----+----+----+----+----+----+----+-------+--------|\n")

        ;; Day rows
        (let ((week-num 0))
          (dolist (line (nthcdr 2 lines))
            (when (string-match "[0-9]" line)
              (setq week-num (1+ week-num))
              (let* ((days (my/parse-cal-days line))
                     (last-day (car (last (remq nil days))))
                     (date-end (encode-time 0 0 0 last-day month year))
                     ;; Days alive: difference from birthday to date-end
                     (days-alive (floor (/ (float-time (time-subtract date-end birthday)) 86400))))
                ;; Build table row with linked days
                (insert "|")
                (dotimes (dow 7)
                  (insert " " (my/format-day-cell (nth dow days) day year month) "|"))
                (insert (format " %5d | %s |\n" week-num (my/format-number-with-commas days-alive)))))))

        ;; Bottom border
        (insert "|----+----+----+----+----+----+----+-------+--------|\n")

        ;; Align the table - must be inside table, not on border
        (forward-line -2)
        (org-table-align)

        ;; Fetch weather asynchronously and insert when ready
        (aj/fetch-calendar-weather-async date-str (current-buffer))))))

;; ---------------------------------------------------------------------------
;; OpenWeatherMap for Calendar (uses API key from authinfo.gpg)
;; ---------------------------------------------------------------------------

(defvar aj/openweather-city "Sydney"
  "City for OpenWeatherMap queries.")

(defvar aj/weather-archive-remote "root@abaj.ai:/var/weather-archive/"
  "Remote path to weather archive on server.")

(defvar aj/weather-archive-local (expand-file-name "~/.cache/weather-archive/")
  "Local cache directory for weather archive.")

(defvar aj/weather-location-cache nil
  "Cached location data: (timestamp lat lon name).")

(defvar aj/weather-location-cache-duration 3600
  "How long to cache location data in seconds (default 1 hour).")

(defvar aj/weather-location-file (expand-file-name "~/.weather-location")
  "Optional file to manually set weather location.
Format: LAT LON NAME (e.g., -33.8148 151.1029 West Ryde)")

(defun aj/get-location-from-file ()
  "Read location from ~/.weather-location if it exists.
Returns (lat lon name) or nil."
  (when (file-exists-p aj/weather-location-file)
    (with-temp-buffer
      (insert-file-contents aj/weather-location-file)
      (let ((content (string-trim (buffer-string))))
        (when (string-match "^\\(-?[0-9.]+\\)\\s-+\\(-?[0-9.]+\\)\\s-+\\(.+\\)$" content)
          (list (string-to-number (match-string 1 content))
                (string-to-number (match-string 2 content))
                (string-trim (match-string 3 content))))))))

(defun aj/get-location-from-ip ()
  "Get current location from IP geolocation (ip-api.com).
Returns (lat lon name) or nil on failure."
  (condition-case err
      (let ((url-request-method "GET")
            (url-show-status nil))
        (with-current-buffer
            (url-retrieve-synchronously "http://ip-api.com/json/?fields=lat,lon,city,regionName" t t 5)
          (goto-char (point-min))
          (when (re-search-forward "\n\n" nil t)
            (let* ((json-object-type 'alist)
                   (data (json-read))
                   (lat (alist-get 'lat data))
                   (lon (alist-get 'lon data))
                   (city (alist-get 'city data)))
              (when (and lat lon)
                (list lat lon (or city "Sydney")))))))
    (error
     (message "Location lookup failed: %s" err)
     nil)))

(defun aj/get-weather-location ()
  "Get weather location, preferring config file over IP geolocation.
Returns (lat lon name) or defaults to Sydney CBD."
  (let* ((now (float-time))
         (cache-valid (and aj/weather-location-cache
                           (< (- now (car aj/weather-location-cache))
                              aj/weather-location-cache-duration))))
    (if cache-valid
        (cdr aj/weather-location-cache)
      ;; Try config file first, then IP geolocation
      (let ((location (or (aj/get-location-from-file)
                          (aj/get-location-from-ip)
                          (list -33.8688 151.2093 "Sydney"))))
        (setq aj/weather-location-cache (cons now location))
        location))))

(defun aj/sync-weather-archive ()
  "Sync weather archive from remote server."
  (interactive)
  (make-directory aj/weather-archive-local t)
  (let ((proc (start-process "weather-sync" nil
                             "rsync" "-az"
                             aj/weather-archive-remote
                             aj/weather-archive-local)))
    (set-process-sentinel proc
                          (lambda (p e)
                            (when (string-match-p "finished" e)
                              (message "Weather archive synced"))))))

(defun aj/get-week-bounds (date-str)
  "Return (start-date . end-date) for the week containing DATE-STR.
Week runs Sunday to Saturday."
  (let* ((parts (split-string date-str "-"))
         (year (string-to-number (nth 0 parts)))
         (month (string-to-number (nth 1 parts)))
         (day (string-to-number (nth 2 parts)))
         (date (encode-time 0 0 0 day month year))
         (dow (string-to-number (format-time-string "%w" date)))
         (week-start (time-subtract date (days-to-time dow)))
         (week-end (time-add week-start (days-to-time 6))))
    (cons (format-time-string "%Y-%m-%d" week-start)
          (format-time-string "%Y-%m-%d" week-end))))

(defun aj/read-archive-weather (date-str)
  "Read archived weather for DATE-STR from local cache. Returns alist or nil."
  (let ((file (expand-file-name (concat date-str ".json") aj/weather-archive-local)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (let ((json-object-type 'alist)
              (json-array-type 'list))
          (condition-case nil
              (json-read)
            (error nil)))))))

(defun aj/read-weather-location-name ()
  "Read location name from cached location.json. Returns string or nil."
  (let ((file (expand-file-name "location.json" aj/weather-archive-local)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (let ((json-object-type 'alist))
          (condition-case nil
              (alist-get 'name (json-read))
            (error nil)))))))

(defun aj/get-openweather-api-key ()
  "Get OpenWeatherMap API key from authinfo.gpg."
  (require 'auth-source)
  (let ((auth (car (auth-source-search :host "api.openweathermap.org"
                                       :require '(:secret)))))
    (when auth
      (let ((secret (plist-get auth :secret)))
        (if (functionp secret)
            (funcall secret)
          secret)))))

(defun aj/openweather-icon (condition)
  "Map OpenWeatherMap weather condition to emoji."
  (pcase condition
    ("Clear" "☀️")
    ("Clouds" "☁️")
    ("Rain" "🌧️")
    ("Drizzle" "🌦️")
    ("Thunderstorm" "⛈️")
    ("Snow" "❄️")
    ((or "Mist" "Fog" "Haze" "Smoke" "Dust" "Sand" "Ash" "Squall" "Tornado") "🌫️")
    (_ "🌡️")))

(defun aj/calculate-moon-phase (year month day)
  "Calculate moon phase for given date. Returns string with emoji and name."
  (let* ((y (if (<= month 2) (1- year) year))
         (m (if (<= month 2) (+ month 12) month))
         (c (/ y 100))
         (e (+ (- 2 c) (/ c 4)))
         (jd (+ (floor (* 365.25 (+ y 4716)))
                (floor (* 30.6001 (+ m 1)))
                day e -1524.5))
         (phase-raw (mod (- jd 2451550.1) 29.530588853))
         (phase-idx (floor (* (/ phase-raw 29.530588853) 8))))
    (pcase phase-idx
      (0 "🌑 New Moon")
      (1 "🌒 Waxing Crescent")
      (2 "🌓 First Quarter")
      (3 "🌔 Waxing Gibbous")
      (4 "🌕 Full Moon")
      (5 "🌖 Waning Gibbous")
      (6 "🌗 Last Quarter")
      (7 "🌘 Waning Crescent")
      (_ "🌑 New Moon"))))

(defun aj/format-unix-time (unix-time format-string)
  "Format UNIX-TIME timestamp using FORMAT-STRING."
  (format-time-string format-string (seconds-to-time unix-time)))

(defun aj/parse-weather-week-from-cache (target-date)
  "Parse weather for the full week (Sun-Sat) containing TARGET-DATE.
Reads from local cache files synced from server.
The '<-- today' marker indicates TARGET-DATE (the file's date), not actual today."
  (let* ((bounds (aj/get-week-bounds target-date))
         (week-start (car bounds))
         (lines '())
         (current-date week-start))
    ;; Iterate through each day of the week (Sun-Sat)
    (dotimes (_ 7)
      (let* ((d-parts (split-string current-date "-"))
             (d-year (string-to-number (nth 0 d-parts)))
             (d-month (string-to-number (nth 1 d-parts)))
             (d-day (string-to-number (nth 2 d-parts)))
             (date-time (encode-time 0 0 0 d-day d-month d-year))
             (day-name (format-time-string "%a" date-time))
             ;; Mark the file's date, not actual today
             (is-file-date (string= current-date target-date))
             ;; Read from cache (server provides both historical and forecast)
             (archive (aj/read-archive-weather current-date))
             weather-info)
        (when archive
          (setq weather-info (list :temp (alist-get 'temp archive)
                                  :min (alist-get 'temp_min archive)
                                  :max (alist-get 'temp_max archive)
                                  :cond (alist-get 'condition archive))))
        ;; Format the line
        (if weather-info
            (let ((emoji (aj/openweather-icon (plist-get weather-info :cond)))
                  (today-marker (if is-file-date " <-- today" "")))
              (push (format "  %s %d: %s %d°C (%d-%d°C)%s"
                            day-name d-day emoji
                            (floor (plist-get weather-info :temp))
                            (floor (plist-get weather-info :min))
                            (floor (plist-get weather-info :max))
                            today-marker)
                    lines))
          ;; No data available
          (push (format "  %s %d: —%s" day-name d-day (if is-file-date " <-- today" "")) lines))
        ;; Move to next day
        (setq current-date
              (format-time-string "%Y-%m-%d"
                                 (time-add date-time (days-to-time 1))))))
    (string-join (nreverse lines) "\n")))

(defun aj/read-forecast-latest ()
  "Read the forecast-latest.json from local cache. Returns alist or nil."
  (let ((file (expand-file-name "forecast-latest.json" aj/weather-archive-local)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (let ((json-object-type 'alist)
              (json-array-type 'list))
          (condition-case nil
              (json-read)
            (error nil)))))))

(defun aj/insert-weather-from-cache (buffer date-str)
  "Insert weather content into BUFFER's Calendar section from local cache.
Weather is relative to DATE-STR (the file's date), not today's date."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward "^\\* Calendar\\b" nil t)
          (let ((section-end (copy-marker
                              (save-excursion
                                (forward-line 1)
                                (if (re-search-forward "^\\* " nil t)
                                    (1- (line-beginning-position))
                                  (point-max))))))
            ;; Remove existing weather lines
            (save-excursion
              (goto-char (point-min))
              (when (re-search-forward "^\\* Calendar\\b" nil t)
                (while (re-search-forward "^\\(.+ forecast:\\|forecast:\\|today:\\|sun:\\|moon:\\)" section-end t)
                  (let ((line-start (line-beginning-position)))
                    (forward-line 1)
                    (when (string-match-p "forecast:" (match-string 0))
                      (while (and (< (point) section-end)
                                  (looking-at "^  "))
                        (forward-line 1)))
                    (delete-region line-start (point))))))
            ;; Go to end of section
            (goto-char section-end)
            ;; Read from cache - only insert forecast (sun/moon/conditions now in hourly table)
            (let ((forecast-str (aj/parse-weather-week-from-cache date-str))
                  (location-name (or (aj/read-weather-location-name) "Sydney")))
              (unless (bolp) (insert "\n"))
              (insert (format "\n%s forecast:\n" location-name) forecast-str "\n"))))))))

(defun aj/fetch-calendar-weather-async (date-str buffer)
  "Fetch fresh weather from server and insert into BUFFER's Calendar section.
Detects location from ~/.weather-location or IP, runs weather script on server,
syncs data, then inserts."
  (let* ((location (aj/get-weather-location))
         (lat (number-to-string (nth 0 location)))
         (lon (number-to-string (nth 1 location)))
         (name (nth 2 location)))
    (message "Weather: fetching for %s (%s, %s)..." name lat lon)
    (make-directory aj/weather-archive-local t)
    ;; Step 1: Run weather script on server with location args
    (let ((fetch-proc (start-process "weather-fetch" "*weather-fetch*"
                                     "ssh" "root@abaj.ai"
                                     (format "/root/scripts/weather-archive.sh %s %s '%s'"
                                             lat lon name))))
      (set-process-sentinel
       fetch-proc
       (lambda (p e)
         (if (not (string-match-p "finished" e))
             (message "Weather: server fetch failed - %s" (string-trim e))
           (message "Weather: server updated, syncing...")
           ;; Step 2: Sync from server
           (let ((sync-proc (start-process "weather-sync" nil
                                           "rsync" "-az"
                                           aj/weather-archive-remote
                                           aj/weather-archive-local)))
             (set-process-sentinel
              sync-proc
              (lambda (p2 e2)
                (if (not (string-match-p "finished" e2))
                    (message "Weather: sync failed - %s" (string-trim e2))
                  (message "Weather: inserting into buffer...")
                  (when (buffer-live-p buffer)
                    (aj/insert-weather-from-cache buffer date-str)
                    (aj/insert-hourly-weather-table buffer date-str)
                    (message "Weather: done for %s ✓" name))))))))))))

;; ---------------------------------------------------------------------------
;; Hourly Weather Table (only for today's daily)
;; ---------------------------------------------------------------------------

(defun aj/read-hourly-weather (date-str)
  "Read hourly weather for DATE-STR from local cache. Returns alist or nil."
  (let ((file (expand-file-name (concat "hourly-" date-str ".json") aj/weather-archive-local)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (let ((json-object-type 'alist)
              (json-array-type 'list))
          (condition-case nil
              (json-read)
            (error nil)))))))

(defun aj/insert-hourly-weather-table (buffer date-str)
  "Insert hourly weather table and conditions table into BUFFER's Calendar section.
Works for any date that has archived hourly data, plus today/tomorrow from live forecast."
  (let* ((today-str (format-time-string "%Y-%m-%d"))
         (tomorrow-str (format-time-string "%Y-%m-%d" (time-add nil (* 24 60 60))))
         (is-today (string= date-str today-str))
         (is-tomorrow (string= date-str tomorrow-str))
         ;; First try archived data for specific date, then fall back to today's forecast
         (data (or (aj/read-hourly-weather date-str)
                   (when (or is-today is-tomorrow) (aj/read-hourly-weather today-str))))
         (forecast-file (expand-file-name "forecast-latest.json" aj/weather-archive-local))
         (forecast-data (when (file-exists-p forecast-file)
                          (condition-case nil
                              (json-read-file forecast-file)
                            (error nil)))))
    (when data
      (let ((hourly (alist-get 'hourly data))
            (tz-offset (or (alist-get 'timezone_offset data) 39600)))
        (when hourly
          (with-current-buffer buffer
            (save-excursion
              (goto-char (point-min))
              (when (re-search-forward "^\\* Calendar\\b" nil t)
                (let ((section-end (copy-marker
                                    (save-excursion
                                      (forward-line 1)
                                      (if (re-search-forward "^\\* " nil t)
                                          (1- (line-beginning-position))
                                        (point-max))))))
                  ;; Remove existing hourly table and conditions table
                  (save-excursion
                    (goto-char (point-min))
                    (when (re-search-forward "^hourly:" section-end t)
                      (let ((start (line-beginning-position)))
                        (forward-line 1)
                        (while (and (< (point) section-end)
                                    (or (looking-at "^|") (looking-at "^$")))
                          (forward-line 1))
                        (delete-region start (point)))))
                  ;; Remove old sun:/moon:/today: lines
                  (save-excursion
                    (goto-char (point-min))
                    (re-search-forward "^\\* Calendar\\b" nil t)
                    (while (re-search-forward "^\\(sun:\\|moon:\\|today:\\)" section-end t)
                      (delete-region (line-beginning-position) (1+ (line-end-position)))))
                  ;; Find insertion point after forecast block
                  (goto-char (point-min))
                  (re-search-forward "^\\* Calendar\\b" nil t)
                  (let ((insert-point
                         (or (save-excursion
                               (when (re-search-forward "^forecast:" section-end t)
                                 (forward-line 1)
                                 (while (and (< (point) section-end)
                                             (not (looking-at "^\\* \\|^hourly:\\|^$")))
                                   (forward-line 1))
                                 (point)))
                             section-end)))
                    (goto-char insert-point)
                    (unless (bolp) (insert "\n"))
                    ;; Build hourly data and collect daily stats
                    (let ((am-emoji (make-vector 12 nil))
                          (am-temp (make-vector 12 nil))
                          (pm-emoji (make-vector 12 nil))
                          (pm-temp (make-vector 12 nil))
                          (max-pop 0)
                          (max-uvi 0)
                          (total-humidity 0)
                          (total-wind 0)
                          (hour-count 0))
                      (dolist (hour-entry hourly)
                        (let* ((dt (alist-get 'dt hour-entry))
                               (local-time (+ dt tz-offset))
                               (hour (mod (/ local-time 3600) 24))
                               (entry-date (format-time-string "%Y-%m-%d" (seconds-to-time dt)))
                               (temp (round (alist-get 'temp hour-entry)))
                               (weather (car (alist-get 'weather hour-entry)))
                               (condition (alist-get 'main weather))
                               (emoji (aj/openweather-icon condition))
                               (pop (or (alist-get 'pop hour-entry) 0))
                               (uvi (or (alist-get 'uvi hour-entry) 0))
                               (humidity (or (alist-get 'humidity hour-entry) 0))
                               (wind (or (alist-get 'wind_speed hour-entry) 0)))
                          (when (string= entry-date date-str)
                            (setq hour-count (1+ hour-count))
                            (setq max-pop (max max-pop pop))
                            (setq max-uvi (max max-uvi uvi))
                            (setq total-humidity (+ total-humidity humidity))
                            (setq total-wind (+ total-wind wind))
                            (if (< hour 12)
                                (progn
                                  (aset am-emoji hour emoji)
                                  (aset am-temp hour (number-to-string temp)))
                              (aset pm-emoji (- hour 12) emoji)
                              (aset pm-temp (- hour 12) (number-to-string temp))))))
                      ;; Calculate averages and get sun/moon data
                      (let* ((avg-humidity (if (> hour-count 0) (/ total-humidity hour-count) 0))
                             (avg-wind (if (> hour-count 0) (/ total-wind hour-count) 0))
                             (current (alist-get 'current forecast-data))
                             (sunrise (alist-get 'sunrise current))
                             (sunset (alist-get 'sunset current))
                             (d-parts (split-string date-str "-"))
                             (year (string-to-number (nth 0 d-parts)))
                             (month (string-to-number (nth 1 d-parts)))
                             (day (string-to-number (nth 2 d-parts)))
                             (moon (aj/calculate-moon-phase year month day)))
                        ;; Insert hourly table
                        (insert "\nhourly:\n")
                        (insert "|----")
                        (dotimes (_ 12) (insert "+----"))
                        (insert "|\n")
                        (insert "| AM |")
                        (dotimes (h 12)
                          (insert (format " %2d |" (if (= h 0) 12 h))))
                        (insert "\n|----")
                        (dotimes (_ 12) (insert "+----"))
                        (insert "|\n")
                        ;; AM emoji row (blank first column)
                        (insert "|    |")
                        (dotimes (h 12)
                          (insert (format " %s |" (or (aref am-emoji h) "  "))))
                        (insert "\n")
                        ;; AM temp row
                        (insert "|    |")
                        (dotimes (h 12)
                          (insert (format " %s |" (or (aref am-temp h) "  "))))
                        (insert "\n|----")
                        (dotimes (_ 12) (insert "+----"))
                        (insert "|\n")
                        (insert "| PM |")
                        (dotimes (h 12)
                          (insert (format " %2d |" (if (= h 0) 12 h))))
                        (insert "\n|----")
                        (dotimes (_ 12) (insert "+----"))
                        (insert "|\n")
                        ;; PM emoji row (blank first column)
                        (insert "|    |")
                        (dotimes (h 12)
                          (insert (format " %s |" (or (aref pm-emoji h) "  "))))
                        (insert "\n")
                        ;; PM temp row
                        (insert "|    |")
                        (dotimes (h 12)
                          (insert (format " %s |" (or (aref pm-temp h) "  "))))
                        (insert "\n|----")
                        (dotimes (_ 12) (insert "+----"))
                        (insert "|\n")
                        ;; Align hourly table
                        (forward-line -2)
                        (org-table-align)
                        ;; Move past hourly table for conditions table
                        (goto-char insert-point)
                        (when (re-search-forward "^hourly:" section-end t)
                          (while (and (< (point) section-end) (looking-at "\\|^|"))
                            (forward-line 1))
                          (forward-line 1)
                          (while (and (< (point) section-end) (looking-at "^|"))
                            (forward-line 1)))
                        ;; Insert conditions table
                        (insert "\n|----------+-------------------|\n")
                        (insert (format "| sun      | ↑ %s  ↓ %s |\n"
                                        (if sunrise (aj/format-unix-time sunrise "%H:%M") "--:--")
                                        (if sunset (aj/format-unix-time sunset "%H:%M") "--:--")))
                        (insert (format "| moon     | %s |\n" moon))
                        (insert "|----------+-------------------|\n")
                        (insert (format "| rain     | %3d%% |\n" (round (* 100 max-pop))))
                        (insert "|----------+-------------------|\n")
                        (insert (format "| UV       | %3d |\n" (round max-uvi)))
                        (insert "|----------+-------------------|\n")
                        (insert (format "| humidity | %3d%% |\n" (round avg-humidity)))
                        (insert "|----------+-------------------|\n")
                        (insert (format "| wind     | %3d km/h |\n" (round (* 3.6 avg-wind))))
                        (insert "|----------+-------------------|\n")
                        ;; Align conditions table
                        (forward-line -2)
                        (org-table-align)))))))))))))

;; ---------------------------------------------------------------------------
;; Current Hour Highlighting in Hourly Weather Table
;; ---------------------------------------------------------------------------

(defface aj/current-hour-face
  '((t :background "#2e7d32" :extend t))
  "Face for highlighting the current hour in the weather table.")

(defvar-local aj/hour-overlays nil
  "List of overlays for current hour highlighting.")

(defun aj/highlight-current-hour ()
  "Highlight the current hour column in the hourly weather table.
Only works for today's daily note."
  (when (aj/daily-date-file-p)
    (let* ((filename (file-name-sans-extension
                      (file-name-nondirectory (buffer-file-name))))
           (today-str (format-time-string "%Y-%m-%d")))
      ;; Only highlight if this is today's daily
      (when (string= filename today-str)
        ;; Remove old overlays
        (mapc #'delete-overlay aj/hour-overlays)
        (setq aj/hour-overlays nil)
        (save-excursion
          (goto-char (point-min))
          (when (re-search-forward "^hourly:" nil t)
            (let* ((now-hour (string-to-number (format-time-string "%H")))
                   (is-pm (>= now-hour 12))
                   (display-hour (mod now-hour 12))  ; 0-11, where 0 = 12 o'clock
                   (col-index (+ 2 display-hour))    ; +2 for AM/PM label + blank column
                   (table-start (point))
                   (table-end (save-excursion
                                (if (re-search-forward "^[^|]" nil t)
                                    (line-beginning-position)
                                  (point-max)))))
              ;; Find the right section (AM or PM)
              (when (re-search-forward (if is-pm "^| PM |" "^| AM |") table-end t)
                ;; Highlight header row (hour number), emoji row, and temp row
                ;; Row offsets: 0=header, 1=separator(skip), 2=emoji, 3=temp
                (dolist (row-offset '(0 2 3))
                  (beginning-of-line)
                  (forward-line row-offset)
                  (let ((line-end (line-end-position))
                        (col 0)
                        cell-start cell-end)
                    ;; Find the nth cell (col-index)
                    (goto-char (line-beginning-position))
                    (while (and (< col col-index) (< (point) line-end))
                      (when (search-forward "|" line-end t)
                        (setq col (1+ col))))
                    ;; Now point is after the | before our target cell
                    ;; Include the | to capture org-modern's table decoration
                    (when (= col col-index)
                      (setq cell-start (1- (point)))  ; include preceding |
                      (when (search-forward "|" line-end t)
                        (setq cell-end (point))       ; include trailing |
                        (let ((ov (make-overlay cell-start cell-end)))
                          (overlay-put ov 'face 'aj/current-hour-face)
                          (overlay-put ov 'priority 100)
                          (push ov aj/hour-overlays)))))
                  ;; Go back to header row for next iteration
                  (goto-char (line-beginning-position))
                  (forward-line (- row-offset)))))))))))

(defun aj/highlight-current-hour-if-daily ()
  "Highlight current hour if this is a daily org file."
  (when (and (derived-mode-p 'org-mode)
             (buffer-file-name)
             (aj/daily-date-file-p))
    (aj/highlight-current-hour)))

;; Add to daily file open hook
(add-hook 'org-roam-dailies-find-file-hook #'aj/highlight-current-hour)

;; Add to after-save-hook (buffer-local, only for daily files)
(defun aj/setup-hour-highlight-on-save ()
  "Set up current hour highlighting on save for daily files."
  (when (aj/daily-date-file-p)
    (add-hook 'after-save-hook #'aj/highlight-current-hour nil t)))

(add-hook 'org-roam-dailies-find-file-hook #'aj/setup-hour-highlight-on-save)

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
  (org-transclusion-font-lock-mode +1)
  ;; Thin solid fringe bitmap (1 pixel wide)
  (define-fringe-bitmap 'org-transclusion-fringe-bitmap
    [#b10000000
     #b10000000
     #b10000000
     #b10000000
     #b10000000
     #b10000000
     #b10000000
     #b10000000]
    nil nil '(center t))
  ;; Apply theme-aware transclusion colors (defined in gruber-themes.el)
  (when (fboundp 'gruber-themes--apply-transclusion)
    (gruber-themes--apply-transclusion)))

(use-package org-side-tree
  :straight (:host github :repo "localauthor/org-side-tree")
  :after org
  :bind (("C-c o s" . org-side-tree))
  :config
  ;; Suppress errors from timer function when org-transclusion overlays cause issues
  (defun aj/org-side-tree-timer-ignore-errors (orig-fn &rest args)
    "Wrap org-side-tree-timer-function to ignore transclusion-related errors."
    (condition-case nil
        (apply orig-fn args)
      (error nil)))
  (advice-add 'org-side-tree-timer-function :around #'aj/org-side-tree-timer-ignore-errors)

  ;; Also protect org-side-tree-overlays-to-text which causes the actual error
  (defun aj/org-side-tree-overlays-ignore-errors (orig-fn &rest args)
    "Wrap org-side-tree-overlays-to-text to ignore invalid search bound errors."
    (condition-case nil
        (apply orig-fn args)
      (error nil)))
  (advice-add 'org-side-tree-overlays-to-text :around #'aj/org-side-tree-overlays-ignore-errors))

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
;; Org-modern - modern styling for org-mode
;; ---------------------------------------------------------------------------

(use-package org-modern
  :after org
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda))
  :config
  (setq org-modern-star '("◉" "○" "●" "○" "●" "○" "●")
        org-modern-list '((43 . "➤") (45 . "–") (42 . "•"))
        org-modern-checkbox '((?X . "☑") (?- . "◐") (?\s . "☐"))
        org-modern-table-vertical 1
        org-modern-table-horizontal 0.2
        org-modern-block-fringe nil
        org-modern-tag t
        org-modern-priority t
        org-modern-todo t
        org-modern-timestamp t))

;; ---------------------------------------------------------------------------
;; Org-download - drag and drop images into org
;; ---------------------------------------------------------------------------

(use-package org-download
  :after org
  :bind (:map org-mode-map
              ("C-c D y" . org-download-yank)
              ("C-c D s" . org-download-screenshot)
              ("C-c D c" . org-download-clipboard))
  :config
  (setq org-download-method 'directory
        org-download-image-dir "images"
        org-download-heading-lvl nil
        org-download-timestamp "%Y%m%d-%H%M%S_"))

;; ---------------------------------------------------------------------------
;; Org-super-agenda - group and filter agenda items
;; ---------------------------------------------------------------------------

(use-package org-super-agenda
  :after org-agenda
  :config
  ;; Enable the mode globally (it's a global minor mode, not buffer-local)
  (org-super-agenda-mode 1)
  (setq org-super-agenda-groups
        '((:name "Overdue"
           :deadline past
           :scheduled past
           :face (:foreground "red"))
          (:name "Today"
           :time-grid t
           :date today
           :scheduled today
           :deadline today)
          (:name "Important"
           :priority "A")
          (:name "Habits"
           :habit t)
          (:name "Upcoming"
           :deadline future
           :scheduled future))))

;; ---------------------------------------------------------------------------
;; Org-timeblock - visual time blocking
;; ---------------------------------------------------------------------------

(use-package org-timeblock
  :straight (:host github :repo "ichernyshovvv/org-timeblock")
  :after org
  :bind (("C-c o t" . org-timeblock))
  :config
  (setq org-timeblock-inbox-file (expand-file-name "inbox.org" org-directory)
        org-timeblock-show-future-repeats t
        org-timeblock-span 1))

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

;; ---------------------------------------------------------------------------
;; org-shop - shopping list management with price tracking
;; ---------------------------------------------------------------------------
(use-package org-shop
  :straight (:type git :host github :repo "abaj8494/org-shop")
  :after org
  :init
  (setq org-shop-keymap-prefix "C-c S")
  (setq org-shop-seasons-file "~/Documents/new-site/content-org/private/shops/seasons.org")
  :config
  (setq org-shop-directory "~/Documents/new-site/content-org/private/shops/")
  (org-shop-setup))


(provide 'package-config)
;;; package-config.el ends here
