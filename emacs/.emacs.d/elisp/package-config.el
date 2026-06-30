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

;; ---------------------------------------------------------------------------
;; Auto-close brackets, quotes, parens
;; ---------------------------------------------------------------------------
(electric-pair-mode 1)

;; In org-mode, `<' / `>' are paren-matched in the syntax table (timestamps),
;; so electric-pair auto-inserts a `>' when you type `<' — which leaves a stray
;; `>' dangling after an org-tempo `<sr'+TAB block expansion.  Inhibit pairing
;; for `<' in org buffers so the template expands clean.
(add-hook 'org-mode-hook
          (lambda ()
            (setq-local electric-pair-inhibit-predicate
                        (let ((base electric-pair-inhibit-predicate))
                          (lambda (c)
                            (if (char-equal c ?<) t (funcall base c)))))))

;; ---------------------------------------------------------------------------
;; Indent guide lines (vertical bars at each indentation level)
;; ---------------------------------------------------------------------------
(use-package indent-bars
  :straight (indent-bars :host github :repo "jdtsmith/indent-bars")
  :preface
  ;; Org fontifies a #+begin_src block by enabling the language's major mode
  ;; in a throwaway buffer named " *org-src-fontification:LANG*" (leading
  ;; space).  That runs python-ts-mode-hook, so a bare `indent-bars-mode'
  ;; on the hook would turn indent-bars on *inside that buffer* and clobber
  ;; its `font-lock-fontify-region-function' — which silently drops the
  ;; tree-sitter faces org is trying to copy back, leaving src blocks
  ;; unhighlighted in the normal buffer (they still highlight under C-c ',
  ;; a real displayed buffer).  Skip the throwaway buffers by name.
  (defun aj/indent-bars-maybe-enable ()
    "Enable `indent-bars-mode' except in internal fontification buffers."
    (unless (string-prefix-p " " (buffer-name))
      (indent-bars-mode 1)))
  :hook ((python-mode python-ts-mode) . aj/indent-bars-maybe-enable)
  :config
  (setq indent-bars-no-descend-string t
        indent-bars-treesit-support t
        indent-bars-prefer-character t)
  (add-hook 'org-src-mode-hook #'indent-bars-mode))

;; ---------------------------------------------------------------------------
;; Rainbow parentheses — VSCode-style bracket-pair colourisation
;; ---------------------------------------------------------------------------
;; Brackets cycle colour by nesting depth.  The depth faces themselves are set
;; in gruber-themes.el (alongside the other code faces) so the light/dark
;; toggle carries through.  Hooked on `prog-mode' so it covers BOTH the `C-c ''
;; src-edit buffer (a real `python-ts-mode' buffer) AND org's throwaway
;; " *org-src-fontification:LANG*" buffer (also prog-mode-derived), whose face
;; text-properties org copies back into the inline block view.  Unlike
;; indent-bars, rainbow-delimiters only *adds font-lock keywords* (it doesn't
;; touch `font-lock-fontify-region-function'), so it's safe in the throwaway
;; fontification buffer and needs no by-name skip.
(use-package rainbow-delimiters
  :straight t
  :hook (prog-mode . rainbow-delimiters-mode))

(use-package htmlize
  :straight t
  :defer nil)      ;; load eagerly so exporters find it

(use-package tex
  :straight auctex)

;; Note: Not using consult/orderless since we're using Helm for completion


(use-package lsp-pyright
  :after lsp-mode
  :hook ((python-mode python-ts-mode) . (lambda ()
                                          (require 'lsp-pyright)
                                          (lsp-deferred))))

;; Make LSP semantic-token colours track the same palette as the tree-sitter
;; faces (see gruber-themes.el), so the C-c ' edit buffer (pyright tokens) and
;; the inline org view (tree-sitter) agree: classes teal, functions yellow,
;; variables/params/properties blue.  Inherit rather than hard-code hexes so a
;; theme toggle carries through.
(with-eval-after-load 'lsp-semantic-tokens
  (dolist (map '((lsp-face-semhl-class     . font-lock-type-face)
                 (lsp-face-semhl-type      . font-lock-type-face)
                 (lsp-face-semhl-enum      . font-lock-type-face)
                 (lsp-face-semhl-interface . font-lock-type-face)
                 (lsp-face-semhl-struct    . font-lock-type-face)
                 (lsp-face-semhl-function  . font-lock-function-call-face)
                 (lsp-face-semhl-method    . font-lock-function-call-face)
                 (lsp-face-semhl-variable  . font-lock-variable-use-face)
                 (lsp-face-semhl-parameter . font-lock-variable-use-face)
                 (lsp-face-semhl-property  . font-lock-property-use-face)))
    (when (facep (car map))
      (set-face-attribute (car map) nil :inherit (cdr map)
                          :foreground 'unspecified))))

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

;; ---------------------------------------------------------------------------
;; Corfu — modern, capf-native in-buffer completion popup
;; ---------------------------------------------------------------------------
;; As-you-type inline completion driven purely by
;; `completion-at-point-functions': LSP/pyright, elisp, and the jupyter kernel
;; capf all feed it.  `helm-mode' keeps owning the *minibuffer* (M-x,
;; find-file); corfu-mode sets a buffer-local `completion-in-region-function'
;; so in-buffer popups win wherever it's active.
(use-package corfu
  :straight t
  :init (global-corfu-mode)
  :custom
  (corfu-auto t)            ; pop up automatically
  (corfu-auto-prefix 2)     ; after 2 chars (matches company config)
  (corfu-auto-delay 0.15)
  (corfu-cycle t)
  (corfu-quit-no-match 'separator)
  (corfu-preselect 'prompt)
  :config
  ;; `ispell-completion-at-point' (a text-mode capf) auto-pops dictionary
  ;; words on any 2+ char prose, which (a) is noise and (b) hijacks TAB while
  ;; the popup is up — breaking org-tempo `<sj'+TAB expansion (TAB then accepts
  ;; "sjaak" instead of letting `org-cycle' expand the template).  Drop it so
  ;; corfu only auto-pops where a real capf exists (src blocks, links, roam).
  (defun aj/corfu-drop-ispell-capf ()
    (remove-hook 'completion-at-point-functions #'ispell-completion-at-point t))
  (add-hook 'text-mode-hook #'aj/corfu-drop-ispell-capf))

;; ---------------------------------------------------------------------------
;; Hideshow — fold functions/blocks in code buffers (incl. C-c ' src edits)
;; ---------------------------------------------------------------------------
;; The org `C-c '' edit buffer is a plain `python-mode' buffer, so hideshow
;; works there like any prog buffer.  Syntax-aware: folds defs, classes, and
;; bracketed blocks.
(use-package hideshow
  :straight (:type built-in)
  :hook (prog-mode . hs-minor-mode)
  :bind (:map hs-minor-mode-map
              ("<backtab>" . hs-toggle-hiding)   ; Shift-TAB: fold at point
              ("C-c f"     . hs-toggle-hiding)
              ("C-c F"     . hs-hide-all)
              ("C-c U"     . hs-show-all)))

(use-package sqlite3
  :straight (:host github :repo "pekingduck/emacs-sqlite3-api"))

;; Add gensymb for \degree and other unit symbols in inline LaTeX
(with-eval-after-load 'org
  (add-to-list 'org-latex-packages-alist '("" "gensymb" t)))

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

;; Export tikzpicture environments as [latex]...[/latex] instead of mathjax
(with-eval-after-load 'anki-editor
  (advice-add 'anki-editor--ox-latex :around
              (lambda (orig-fn latex contents info)
                "Use [latex] tags for tikzpicture environments instead of mathjax."
                (let ((code (org-remove-indentation (org-element-property :value latex))))
                  (if (and (eq (org-element-type latex) 'latex-environment)
                           (string-match-p "\\\\begin{tikzpicture}" code))
                      (let ((anki-editor-latex-style 'builtin))
                        (funcall orig-fn latex contents info))
                    (funcall orig-fn latex contents info))))))

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

(defvar ankiorg-search-directories '("~/lattice/notes/flashcards")
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
        helm-exit-idle-delay 0.05)
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
  (org-roam-directory (file-truename "~/lattice/notes/"))
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

  ;; If you're using a vertical completion framework, you might want a more informative completion interface
  (org-roam-db-autosync-mode)
  ;; If using org-roam-protocol
  (require 'org-roam-protocol)
  (setq find-file-visit-truename t)

  ;; Make `C-c n f' (org-roam-node-find) completion fully case-insensitive.
  ;; Helm's default `helm-case-fold-search' is 'smart — it flips to
  ;; case-SENSITIVE the moment the pattern contains an uppercase letter, so
  ;; typing a capital in a node title stops matching lowercase. Force both
  ;; helm's and completing-read's case folding on, scoped to this command only.
  (defun aj/org-roam-node-find-case-insensitive (orig-fn &rest args)
    (let ((helm-case-fold-search t)
          (completion-ignore-case t))
      (apply orig-fn args)))
  (advice-add 'org-roam-node-find :around #'aj/org-roam-node-find-case-insensitive)

  ;; Hide non-navigable link types from the graph. `elisp:' links with
  ;; embedded quotes (e.g. the Garmin dashboard links) otherwise produce a
  ;; .dot file with unescaped quotes in node ids, which dot(1) rejects with
  ;; a syntax error and silently writes an empty SVG.
  (with-eval-after-load 'org-roam-graph
    (dolist (type '("elisp" "http" "https" "mailto" "garmin-activity"))
      (add-to-list 'org-roam-graph-link-hidden-types type)))

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

  ;; Author accessor for `C-c n f' matching. Book notes carry their authors in
  ;; the `#+hugo_custom_front_matter' `:author' value (a quoted string or an
  ;; elisp-style list, e.g. :author '("Daphne Koller" "Nir Friedman")). org-roam
  ;; matches the completion pattern against the formatted display-template
  ;; string, so surfacing the author there makes node-find match on author too.
  (defvar aj/org-roam-author-cache (make-hash-table :test 'equal)
    "Cache of FILE -> (MTIME . AUTHOR-STRING) for org-roam author lookup.")

  (defun aj/org-roam--extract-author (file)
    "Return the author name(s) declared in FILE's hugo front matter, or \"\"."
    (with-temp-buffer
      (insert-file-contents file nil 0 8192)
      (goto-char (point-min))
      (if (re-search-forward "^#\\+hugo_custom_front_matter:" nil t)
          (let ((line (buffer-substring-no-properties (point) (line-end-position))))
            (if (string-match ":author[ \t]+" line)
                (let* ((after (substring line (match-end 0)))
                       ;; Stop at the next " :key" so a trailing property
                       ;; (e.g. :composed "2009") isn't slurped into the author.
                       (val (if (string-match "[ \t]+:[a-z_]+\\(?:[ \t]\\|$\\)" after)
                                (substring after 0 (match-beginning 0))
                              after))
                       (names '())
                       (start 0))
                  ;; Prefer quoted names (handles single string and '(...) list);
                  ;; otherwise fall back to the bare token, stripped of quoting.
                  (while (string-match "\"\\([^\"]*\\)\"" val start)
                    (push (match-string 1 val) names)
                    (setq start (match-end 0)))
                  (if names
                      (string-join (nreverse names) " ")
                    (string-trim (replace-regexp-in-string "[()'\"]" "" val))))
              ""))
        "")))

  (cl-defmethod org-roam-node-author ((node org-roam-node))
    "Return author name(s) for NODE, for `C-c n f' completion matching.
Only book notes are parsed (others would needlessly stat the whole
notes tree); results are cached and invalidated by file mtime."
    (let ((file (org-roam-node-file node)))
      (if (and file (string-match-p "/books/" file))
          (let ((mtime (file-attribute-modification-time (file-attributes file)))
                (cached (gethash file aj/org-roam-author-cache)))
            (if (and cached (equal (car cached) mtime))
                (cdr cached)
              (let ((author (aj/org-roam--extract-author file)))
                (puthash file (cons mtime author) aj/org-roam-author-cache)
                author)))
        "")))

  ;; Combined display template
  (setq org-roam-node-display-template
        (concat "${directories:10} "
                "${type:15} "
                "${title:*} "
                (propertize "${tags:10}" 'face 'org-tag)
                " ${backlinkscount:6}"
                (propertize " ${author}" 'face 'font-lock-comment-face))))

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
           :unnarrowed t)
          ("s" "shop" plain "%?"
           :target (file+head "private/shops/${slug}.org"
                              ":PROPERTIES:\n:ID: %(org-id-uuid)\n:END:\n#+TITLE: ${title}\n#+EXPORT_FILE_NAME: ${slug}\n#+DATE: %<%Y-%m-%dT%H:%M:%S+11:00>\n\n* next-shop\n\n- [ ] \n\n* inventory\n\n| next | product | price | quantity | last_bought |\n|------+---------+-------+----------+-------------|\n|      |         |       |          |             |\n|------+---------+-------+----------+-------------|\n| TOTAL |        |       |          |             |\n|------+---------+-------+----------+-------------|\n\n#+TBLFM: @>$3=vsum(@3..@-1)\n\n* history                                                        :noexport:\n|---------+------+-------+----------+-------|\n| product | date | count | discount | price |\n|---------+------+-------+----------+-------|\n|         |      |       |          |       |\n|---------+------+-------+----------+-------|\n| TOTAL   |      |       |          |       |\n|---------+------+-------+----------+-------|\n\n* one-offs\n\n| product | price | date (mm/yy) |\n|---------+-------+--------------|\n")
           :unnarrowed t))))


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
  (setq gptel-model 'claude-sonnet-4-6
        gptel-backend (gptel-make-anthropic "Claude"
                        :stream t
                        ;; gptel 0.9.9.3 ships a stale model list (its newest
                        ;; Anthropic entry is the now-retired Sonnet 4), so the
                        ;; `gptel-menu' switcher offers dead models.  Pin the
                        ;; current line-up explicitly until the package updates.
                        :models '(claude-opus-4-8
                                  claude-opus-4-7
                                  claude-sonnet-4-6
                                  claude-haiku-4-5)
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
  (setq org-shop-seasons-file "~/lattice/notes/private/shops/seasons.org")
  :config
  (setq org-shop-directory "~/lattice/notes/private/shops/")
  (org-shop-setup)
  ;; Personal receipt-ocr workflow glue (adds C-c S A → make org-shop in a
  ;; vsplit vterm). Lives in the receipt-ocr repo rather than upstream
  ;; org-shop because the path is bespoke to this machine.
  (load "~/lattice/code/private/receipt-ocr/emacs/receipt-ocr.el" nil 'nomessage))


;; ---------------------------------------------------------------------------
;; Beancount - plain-text double-entry accounting
;; ---------------------------------------------------------------------------
(use-package beancount
  :straight (:type git :host github :repo "beancount/beancount-mode")
  :mode ("\\.beancount\\'" . beancount-mode)
  :commands (beancount-check beancount-query beancount-insert-date
             beancount-insert-account beancount-transaction-clear
             beancount-transaction-flag beancount-align-numbers
             beancount-align-to-previous-number beancount-date-up-day
             beancount-date-down-day beancount-context beancount-linked
             beancount-fava)
  :init
  (defun aj/beancount-root-ledger ()
    "Return absolute path of the top-level ledger for the current buffer.
Visits to ledger/aayush.org, ledger/kiyomi.org, ledger/all.org return
themselves. Year files under ledger/<who>/<YYYY>.org route up to
ledger/<who>.org. Returns nil for buffers outside ledger/."
    (when buffer-file-name
      (let ((file (expand-file-name buffer-file-name)))
        (cond
         ;; Top-level ledger file (e.g. ledger/aayush.org)
         ((string-match "\\`\\(.*/beancount/ledger\\)/[^/]+\\.org\\'" file)
          file)
         ;; Year file under ledger/<who>/<year>.org → ledger/<who>.org
         ((string-match "\\`\\(.*/beancount/ledger\\)/\\([^/]+\\)/[^/]+\\.org\\'" file)
          (let ((root (concat (match-string 1 file) "/"
                              (match-string 2 file) ".org")))
            (and (file-exists-p root) root)))))))

  (defun aj/beancount-check ()
    "Run bean-check on the root ledger for the current buffer."
    (interactive)
    (require 'beancount)
    (let ((root (aj/beancount-root-ledger)))
      (unless (and root (file-exists-p root))
        (user-error "No root ledger resolved for %s" (or buffer-file-name "buffer")))
      (let ((default-directory (file-name-directory root))
            (compilation-read-command nil))
        (beancount--run beancount-check-program root))))

  (defun aj/beancount-query ()
    "Run bean-query interactively against the root ledger for the current buffer."
    (interactive)
    (require 'beancount)
    (let ((root (aj/beancount-root-ledger)))
      (unless (and root (file-exists-p root))
        (user-error "No root ledger resolved for %s" (or buffer-file-name "buffer")))
      (let* ((default-directory (file-name-directory root))
             (bufname (format "bean-query<%s>" (file-name-base root)))
             (buf (make-comint bufname beancount-query-program nil root)))
        (pop-to-buffer buf))))

  (defun aj/beancount-org-setup ()
    "Add beancount syntax highlighting and keybindings to org ledger files."
    (when (and buffer-file-name
               (string-match-p "/beancount/ledger/" buffer-file-name))
      (require 'beancount)
      ;; Add beancount font-lock keywords on top of org's
      (font-lock-add-keywords nil beancount-font-lock-keywords 'append)
      ;; Keybindings under C-c b prefix
      (let ((map (make-sparse-keymap)))
        (define-key map (kbd "c") #'aj/beancount-check)
        (define-key map (kbd "q") #'aj/beancount-query)
        (define-key map (kbd "d") #'beancount-insert-date)
        (define-key map (kbd "'") #'beancount-insert-account)
        (define-key map (kbd "*") #'beancount-transaction-clear)
        (define-key map (kbd "f") #'beancount-transaction-flag)
        (define-key map (kbd ";") #'beancount-align-to-previous-number)
        (define-key map (kbd ":") #'beancount-align-numbers)
        (define-key map (kbd "<left>") #'beancount-date-down-day)
        (define-key map (kbd "<right>") #'beancount-date-up-day)
        (define-key map (kbd "x") #'beancount-context)
        (define-key map (kbd "k") #'beancount-linked)
        (define-key map (kbd "v") #'beancount-fava)
        (local-set-key (kbd "C-c b") map))
      ;; Enable completion of account names
      (add-hook 'completion-at-point-functions
                #'beancount-completion-at-point nil t)))
  (add-hook 'org-mode-hook #'aj/beancount-org-setup))


;; ---------------------------------------------------------------------------
;; vterm
;; ---------------------------------------------------------------------------
(use-package vterm
  :ensure t)

(add-hook 'vterm-mode-hook
  (lambda ()
    (set (make-local-variable 'buffer-face-mode-face)
         '(:family "MonaspiceAr Nerd Font" :height 140))
    (buffer-face-mode t)))

(provide 'package-config)
;;; package-config.el ends here
