;;; org-config.el --- Org-mode configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; Comprehensive Org-mode setup including Babel, LaTeX preview, and templates.

;;; Code:

(require 'org)
(require 'ox-latex)
(require 'ob-markdown)

;; Extra LaTeX packages for previews and export (mathfrak, mathbb, etc.)
(add-to-list 'org-latex-packages-alist '("" "amssymb" t))
(add-to-list 'org-latex-packages-alist '("" "amsfonts" t))

;; ---------------------------------------------------------------------------
;; Auto-populate schedule time from heading
;; ---------------------------------------------------------------------------

(defun aj/normalize-time (time-str)
  "Convert time like '5:30PM' or '05:30pm' to 24-hour format '17:30'."
  (when time-str
    (let* ((time-str (string-trim time-str))
           (pm (string-match-p "[Pp][Mm]" time-str))
           (am (string-match-p "[Aa][Mm]" time-str))
           (clean (replace-regexp-in-string "[AaPpMm ]" "" time-str)))
      (when (string-match "\\([0-9]?[0-9]\\):\\([0-9][0-9]\\)" clean)
        (let ((hour (string-to-number (match-string 1 clean)))
              (min (match-string 2 clean)))
          (when pm (unless (= hour 12) (setq hour (+ hour 12))))
          (when am (when (= hour 12) (setq hour 0)))
          (format "%02d:%s" hour min))))))

(defun aj/heading-extract-time ()
  "Extract time or time range from heading (e.g., '04:35PM' or '05:30PM-7:00PM')."
  (when (org-at-heading-p)
    (let ((heading (org-get-heading t t t t)))
      ;; Match time range: 05:30PM-7:00PM or 17:30-19:00
      (cond
       ((string-match "\\([0-9]?[0-9]:[0-9][0-9]\\s-*[AaPpMm]*\\)\\s-*-\\s-*\\([0-9]?[0-9]:[0-9][0-9]\\s-*[AaPpMm]*\\)" heading)
        (let* ((start (aj/normalize-time (match-string 1 heading)))
               (end (aj/normalize-time (match-string 2 heading))))
          (cons start end)))
       ;; Match single time
       ((string-match "\\([0-9]?[0-9]:[0-9][0-9]\\s-*[AaPpMm]*\\)" heading)
        (aj/normalize-time (match-string 1 heading)))))))

(defun aj/org-schedule-with-heading-time (orig-fun &optional arg time)
  "Advise `org-schedule' to use time from heading as default."
  (if (or arg time)
      (funcall orig-fun arg time)
    (let ((heading-time (aj/heading-extract-time)))
      (if heading-time
          (let ((time-str (if (consp heading-time)
                              (format "%s-%s" (car heading-time) (cdr heading-time))
                            heading-time)))
            (funcall orig-fun nil time-str))
        (funcall orig-fun nil nil)))))

(advice-add 'org-schedule :around #'aj/org-schedule-with-heading-time)

;; ---------------------------------------------------------------------------
;; PATH setup (needed for external tools)
;; ---------------------------------------------------------------------------

(add-to-list 'exec-path "/opt/homebrew/bin/")
(setenv "PATH" (concat "/opt/homebrew/bin:" (getenv "PATH")))

(add-to-list 'exec-path "/opt/anaconda3/bin")
(setenv "PATH" (concat "/opt/anaconda3/bin:" (getenv "PATH")))

;; ---------------------------------------------------------------------------
;; Org Babel Configuration
;; ---------------------------------------------------------------------------

;; go-mode / ob-go are optional. A flaky boot (e.g. straight can't reach GitHub
;; because the network isn't up yet right after a reboot, or the build dir isn't
;; on load-path yet) must NOT abort the rest of org-config — and with it the
;; gcal section far below and every module init.el loads afterwards.
;; Degrade to "no go babel" and keep going.
;;
;; NB: `use-package' downgrades a load failure to its own warning and does NOT
;; re-signal, so the condition-case here never trips on a missing package — it
;; would still set the flag t, and the unguarded `(require 'ob-go)' inside
;; `org-babel-do-load-languages' below would then throw and truncate the file.
;; So gate the flag on the actual `require' results (noerror, so they can't
;; throw), not on use-package staying silent.
(defvar aj/ob-go-available nil)
(condition-case err
    (progn
      (use-package go-mode)
      (use-package ob-go
        :straight (:host github :repo "pope/ob-go"))
      (setq aj/ob-go-available
            (and (require 'go-mode nil t)
                 (require 'ob-go nil t))))
  (error
   (display-warning 'org-config
     (format "go-mode/ob-go unavailable, skipping go babel: %S" err)
     :warning)))

(org-babel-do-load-languages
 'org-babel-load-languages
 (append
  '((shell   . t)
    (python  . t)
    (markdown . t)
    (js . t)
    (jupyter . t)
    (latex   . t)
    (C       . t)
    (java    . t)
    (gnuplot . t))
  (when aj/ob-go-available '((go . t)))
  (when (bound-and-true-p aj/ob-R-available) '((R . t)))))

;; Python settings
(setq custom-tab-width 4)
(setq-default python-indent-offset custom-tab-width)
(setq org-babel-python-command "/opt/anaconda3/bin/python")
(setq-default indent-tabs-mode nil)

(add-hook 'python-mode-hook
          (lambda () (setq indent-tabs-mode nil)))

(add-hook 'org-src-mode-hook
          (lambda () (setq indent-tabs-mode nil)))

;;; LSP in Org python src blocks --------------------------------
;; Make Org's python edit buffer look like a real file so pyright can attach,
;; then turn on *semantic tokens* there for the class/function/variable colours
;; tree-sitter can't infer (it only sees calls, not what a name resolves to).
;;
;; Pyright sees only the single block — it has no cross-block context — so this
;; is deliberately colours-only:
;;   - completion stays with the jupyter kernel (it knows the live session;
;;     pyright on one block can't see symbols defined in other blocks);
;;   - diagnostics are off, else every cross-block symbol shows as an
;;     "undefined name" error;
;;   - where pyright can't resolve a symbol it simply emits no token, and the
;;     tree-sitter colours (incl. the CapWords->type rule above) show through.
;; `lsp-semantic-tokens-enable' is flipped buffer-locally: the global default
;; stays nil (see java-lsp.el) so Java sessions don't pay the token-streaming
;; cost.  lsp-mode advertises the client capability unconditionally, so the
;; per-buffer flag is enough for pyright to serve tokens here.
(with-eval-after-load 'org
  (defun aj/org-src-pyright-attach (&rest _)
    "Attach pyright to an Org python/jupyter src edit buffer for colours only."
    (let* ((org-dir (expand-file-name
                     (or (and (buffer-file-name)
                              (file-name-directory (buffer-file-name)))
                         default-directory)))
           (fake-file (expand-file-name ".org-src-OrgPython.py" org-dir)))
      (setq-local default-directory org-dir)
      (setq-local buffer-file-name fake-file)
      (setq-local lsp-buffer-uri (lsp--path-to-uri fake-file))
      (setq-local lsp-semantic-tokens-enable t)   ; the point of all this
      (setq-local lsp-completion-enable nil)       ; leave completion to the kernel
      (setq-local lsp-diagnostics-provider :none)  ; single-block view => noise
      (setq-local lsp-modeline-diagnostics-enable nil)
      (when (and (fboundp 'lsp-workspace-root)
                 (null (lsp-workspace-root org-dir)))
        (lsp-workspace-folders-add org-dir))
      (unless (bound-and-true-p lsp-mode)
        (require 'lsp-pyright)
        (lsp-deferred))))
  ;; `#+begin_src python' dispatches to org-babel-edit-prep:python directly …
  (defalias 'org-babel-edit-prep:python #'aj/org-src-pyright-attach)
  ;; … `jupyter-python' goes through emacs-jupyter's edit-prep, so piggy-back.
  (advice-add 'org-babel-edit-prep:jupyter :after #'aj/org-src-pyright-attach))

;;; AUCTeX completion in Org latex src blocks --------------------------------
;; Use AUCTeX's LaTeX-mode (not Emacs built-in latex-mode) for src blocks.
(add-to-list 'org-src-lang-modes '("latex" . LaTeX))

;; Load AUCTeX style hooks for packages from the parent org buffer,
;; and bind TAB to complete macros/environments.
(with-eval-after-load 'org
  (defun ab/org-babel-edit-prep:latex (_info)
    ;; Ensure we're in AUCTeX's LaTeX-mode, not Emacs built-in latex-mode
    (unless (derived-mode-p 'LaTeX-mode)
      (require 'latex)
      (LaTeX-mode)
      ;; Restore org-src-mode bindings clobbered by mode switch
      (org-src-mode))
    (setq TeX-master t)
    ;; Load style files for packages used in the parent org buffer's
    ;; #+LATEX_HEADER lines (e.g. amsthm, enumitem, mathtools, etc.)
    (when-let* ((org-buf (org-src-source-buffer))
                (headers (with-current-buffer org-buf
                           (org-collect-keywords '("LATEX_HEADER")))))
      (dolist (hdr (cdr (assoc "LATEX_HEADER" headers)))
        (when (string-match "\\\\usepackage\\(?:\\[.*?\\]\\)?{\\([^}]+\\)}" hdr)
          (dolist (pkg (split-string (match-string 1 hdr) ","))
            (TeX-run-style-hooks (string-trim pkg))))))
    (local-set-key (kbd "TAB") #'ab/latex-tab-complete))
  (defalias 'org-babel-edit-prep:latex #'ab/org-babel-edit-prep:latex))

(defun ab/latex-tab-complete ()
  "Complete TeX macro or environment at point, or indent."
  (interactive)
  (cond
   ;; Inside \begin{ or \end{ — complete environment name
   ((save-excursion
      (skip-chars-backward "a-zA-Z*")
      (looking-back "\\\\\\(begin\\|end\\){" (line-beginning-position)))
    (completion-at-point))
   ;; Partial \begin or \end — expand and open brace
   ((save-excursion
      (skip-chars-backward "a-zA-Z")
      (and (eq (char-before) ?\\)
           (looking-at-p "\\(beg\\|begin\\|en\\|end\\)\\>")))
    (let ((start (save-excursion (skip-chars-backward "a-zA-Z") (point)))
          (cmd (save-excursion
                 (skip-chars-backward "a-zA-Z")
                 (if (looking-at-p "b") "begin{" "end{"))))
      (delete-region start (point))
      (insert cmd)))
   ;; After backslash — complete macro
   ((save-excursion
      (skip-chars-backward "a-zA-Z@*")
      (eq (char-before) ?\\))
    (completion-at-point))
   ;; Default — indent
   (t (indent-for-tab-command))))

;; Jupyter-python mode mapping — use tree-sitter for richer fontification
;; (method calls, attribute access, variable uses), which needs font-lock
;; level 4 (see below).
;;
;; emacs-jupyter re-registers ("jupyter-python" . python) on *every* org
;; buffer via `org-babel-jupyter-make-local-aliases' (an `org-mode-hook'),
;; using `add-to-list' — which prepends that entry to the front whenever it's
;; absent.  `org-src-get-lang-mode' uses `assoc' (first match wins), so a lone
;; python-ts entry gets shadowed.  Force python-ts to the front AND keep the
;; python entry present, so jupyter's `add-to-list' is a permanent no-op and
;; the order never flips back.
(setq org-src-lang-modes
      (cons '("jupyter-python" . python-ts)
            (cons '("jupyter-python" . python)
                  (assoc-delete-all "jupyter-python" org-src-lang-modes))))
(add-to-list 'org-src-lang-modes '("chess" . latex))

;; Tree-sitter only emits the call/property/variable-use faces at level 4;
;; the default 3 leaves method calls uncolored.
(setq treesit-font-lock-level 4)

;; ---------------------------------------------------------------------------
;; Semantic-ish highlighting: colour CapWords constructor calls as types
;; ---------------------------------------------------------------------------
;; Tree-sitter is purely syntactic: it sees `Graph(graph)' as a *call* and
;; paints `Graph' with `font-lock-function-call-face', identical to any
;; function.  A language server would know `Graph' is a class.  As a cheap
;; stand-in, treat a call whose target is a CapWords identifier (PEP 8 class
;; convention) — `Graph(...)' or `module.Digraph(...)' — as a type, so
;; constructors get the class colour while ordinary `compute(...)' calls stay
;; function-coloured.  Appended as an *overriding* rule under its own
;; `aj-constructor' feature, after the built-in `function' feature so it wins,
;; and enabled at the top font-lock level.
;;
;; NB: this only lands where fontification goes through stock tree-sitter —
;; notably org's inline src-block fontification, where `indent-bars' is skipped
;; (see package-config.el).  In a live `python-ts-mode' file `indent-bars'
;; owns the region function and swallows the override; there `lsp-pyright'
;; semantic tokens are the real answer.
(defun aj/python-ts-semantic-types ()
  "Nudge `python-ts-mode' fontification toward VS Code \"2026 Dark\":
- CapWords constructor calls (`Graph(...)'/`mod.Digraph(...)') get the type
  face (green), matching VS Code's semantic highlighting of class constructors;
- `self'/`cls' get the constant face (blue) instead of `python-ts-mode's
  keyword face (which would make them red like def/class).
Ordinary keywords stay `font-lock-keyword-face' — 2026 Dark colours
def/class/return/if/… all the same red, so no per-keyword split is needed."
  (unless (memq 'aj-constructor (apply #'append treesit-font-lock-feature-list))
    (setq-local treesit-font-lock-settings
                (append treesit-font-lock-settings
                        (treesit-font-lock-rules
                         :language 'python
                         :feature 'aj-constructor
                         :override t
                         '((call function: (identifier) @font-lock-type-face
                                 (:match "\\`[A-Z]" @font-lock-type-face))
                           (call function:
                                 (attribute attribute: (identifier) @font-lock-type-face)
                                 (:match "\\`[A-Z]" @font-lock-type-face))
                           ((identifier) @font-lock-constant-face
                            (:match "\\`\\(?:self\\|cls\\)\\'" @font-lock-constant-face))))))
    (setq-local treesit-font-lock-feature-list
                (let ((fl (copy-tree treesit-font-lock-feature-list)))
                  (setf (car (last fl)) (append (car (last fl)) '(aj-constructor)))
                  fl))
    (treesit-font-lock-recompute-features)))
(add-hook 'python-ts-mode-hook #'aj/python-ts-semantic-types)

;; ---------------------------------------------------------------------------
;; VS Code "2026 Dark" palette — Python only (buffer-local, no global bleed)
;; ---------------------------------------------------------------------------
;; The fuller 2026 Dark syntax palette (red keywords, mauve functions, green
;; types, blue variables/self, aqua strings, gray comments) — foregrounds
;; sourced from VS Code's theme JSON (theme-defaults/themes/2026-dark.json).
;; Applied as a BUFFER-LOCAL face remap (`face-remap-add-relative') so it
;; colours only Python: real `python[-ts]-mode' buffers (.py files + the C-c '
;; src edit buffer) and org buffers (for the inline #+begin_src python view —
;; org renders src blocks with these same face symbols).  Kept OUT of the
;; global faces (see gruber-themes.el) so Elisp/shell/markdown/notmuch/etc.
;; stay gruber.  Caveat: the org remap is per-buffer, so a non-Python src block
;; in the same org file also picks up the palette; org prose is unaffected.
(defconst aj/vscode-2026-dark-code-colors
  '((font-lock-keyword-face           . "#ff7b72")   ; def/class/return/if/import — red
    (font-lock-escape-face            . "#ff7b72")
    (font-lock-function-name-face     . "#d2a8ff")   ; functions — mauve
    (font-lock-function-call-face     . "#d2a8ff")
    (font-lock-type-face              . "#7ee787")   ; classes / types — green
    (font-lock-constant-face          . "#79c0ff")   ; True/False/None — blue
    (font-lock-builtin-face           . "#79c0ff")
    (font-lock-number-face            . "#79c0ff")   ; numbers — blue
    (font-lock-variable-name-face     . "#79c0ff")   ; variables / params — blue
    (font-lock-variable-use-face      . "#79c0ff")
    (font-lock-property-name-face     . "#79c0ff")   ; attributes — blue
    (font-lock-property-use-face      . "#79c0ff")
    (font-lock-string-face            . "#a5d6ff")   ; strings — aqua
    (font-lock-doc-face               . "#a5d6ff")   ; docstrings — aqua
    (font-lock-doc-markup-face        . "#a5d6ff")
    (font-lock-comment-face           . "#8b949e")   ; comments — gray
    (font-lock-comment-delimiter-face . "#8b949e"))
  "VS Code \"2026 Dark\" foreground colours, keyed by font-lock face.")

(defvar-local aj/vscode-2026--cookies nil
  "Face-remap cookies added by `aj/vscode-2026-apply-local' in this buffer.")

(defun aj/vscode-2026-apply-local ()
  "Buffer-locally remap code faces to the VS Code \"2026 Dark\" palette.
Idempotent — drops any remaps a prior run added before re-adding, so a mode
re-init doesn't stack duplicates."
  (mapc #'face-remap-remove-relative aj/vscode-2026--cookies)
  (setq aj/vscode-2026--cookies
        (mapcar (lambda (e)
                  (face-remap-add-relative (car e) (list :foreground (cdr e))))
                aj/vscode-2026-dark-code-colors)))

(add-hook 'python-mode-hook    #'aj/vscode-2026-apply-local)
(add-hook 'python-ts-mode-hook #'aj/vscode-2026-apply-local)
(add-hook 'org-mode-hook       #'aj/vscode-2026-apply-local)

;;; Kernel-backed completion in jupyter src edit buffers (C-c ') -------------
;; emacs-jupyter's `org-babel-edit-prep:jupyter' enables
;; `jupyter-repl-interaction-mode', which already puts
;; `jupyter-completion-at-point' on `completion-at-point-functions' (live
;; introspection of the running kernel).  But it leaves TAB bound to plain
;; indentation, so completion was only reachable via M-TAB.  Letting TAB fall
;; through to `completion-at-point' once the line is indented routes TAB into
;; the jupyter kernel capf (no company/corfu installed; the default
;; *Completions* UI is used).  Advising the base `:jupyter' op covers
;; `:jupyter-python' too, since that name is a symbol-indirection defalias.
(with-eval-after-load 'ob-jupyter
  (defun aj/jupyter-edit-buffer-completion (&rest _)
    "Let TAB drive kernel completion in a jupyter src edit buffer."
    (setq-local tab-always-indent 'complete))
  (advice-add 'org-babel-edit-prep:jupyter :after
              #'aj/jupyter-edit-buffer-completion))

;; In the C-c ' edit buffer the major mode is `python-ts-mode' (a sibling of
;; `python-mode' under `python-base-mode'), which matches neither the
;; `org-mode' nor `jupyter-repl-mode' specialisation of
;; `jupyter-code-context' — so the *default* method fires and sends only the
;; current line to the kernel.  That's why `dot.at<TAB>' fails: the kernel
;; never sees the `dot = graphviz.Digraph(...)' line above, and (unless the
;; cell was executed) `dot' isn't a live object to introspect either.  Send
;; the whole edit buffer instead so the kernel's Jedi can infer types from the
;; definitions above point.  Scoped to org-src buffers; plain python files
;; fall through to the default line-context method.
(with-eval-after-load 'jupyter-client
  (cl-defmethod jupyter-code-context ((_type (eql completion))
                                      &context (major-mode python-base-mode))
    (if (bound-and-true-p org-src-mode)
        (list (buffer-substring-no-properties (point-min) (point-max))
              (- (point) (point-min)))
      (cl-call-next-method)))

  ;; The edit buffer / inline blocks now use `python-ts-mode', but emacs-jupyter
  ;; derives the kernel's language mode from the file extension via
  ;; `set-auto-mode' (-> `python-mode'), and `jupyter-repl-associate-buffer'
  ;; compares it with a strict `eq'.  Without this, association fails with
  ;; "Cannot associate buffer to REPL.  Wrong `major-mode'" and the kernel
  ;; completion capf is never installed.  Canonicalise the kernel language mode
  ;; to the tree-sitter variant so the comparison matches.
  (defun aj/jupyter-prefer-ts-mode (mode)
    (if (eq mode 'python-mode) 'python-ts-mode mode))
  (advice-add 'jupyter-kernel-language-mode :filter-return
              #'aj/jupyter-prefer-ts-mode))

;;; Prefer plain-text over HTML for org results ------------------------------
;; A bare `df.head()' emits both `text/html' and `text/plain'.  emacs-jupyter
;; picks the first mime type present in `jupyter-org-mime-types', whose default
;; order ranks `:text/html' above `:text/plain' — so DataFrames land in the org
;; buffer as a raw HTML table.  Reorder so `:text/plain' wins, giving pandas'
;; ASCII repr instead, while keeping images (plots) and LaTeX (sympy) ahead so
;; neither regresses.  Lets the source cell stay unmodified for ipynb paste-back.
(with-eval-after-load 'jupyter-org-client
  (setq jupyter-org-mime-types
        '(:text/org
          :image/svg+xml :image/jpeg :image/png
          :text/latex
          :text/plain
          :text/html :text/markdown)))

;; ---------------------------------------------------------------------------
;; Chess babel blocks - render LaTeX chess diagrams to images
;; ---------------------------------------------------------------------------
;; Usage:
;;   #+NAME: fig:opening
;;   #+CAPTION: King's Indian Opening
;;   #+BEGIN_SRC chess :exports results :file opening.png
;;   \setchessboard{boardfontsize=0.8cm}
;;   \chessboard[showmover=false]
;;   #+END_SRC
;;
;; Execute with C-c C-c to generate the image. ox-hugo exports the result.

(defvar aj/chess-latex-preamble
  "\\usepackage[LSBC4,T1]{fontenc}
\\usepackage{xskak}
\\usepackage{chessboard}
\\setboardfontencoding{LSBC4}
"
  "LaTeX preamble for chess diagrams.")

(defvar aj/chess-latex-docclass
  "\\documentclass[varwidth,border=2pt]{standalone}"
  "Document class for chess diagrams. varwidth allows line breaks.")

;; Default header args: result is a file link
(defvar org-babel-default-header-args:chess
  '((:results . "file link replace")
    (:exports . "results"))
  "Default header arguments for chess blocks.")

(defun org-babel-execute:chess (body params)
  "Execute a chess diagram block, rendering LaTeX to an image."
  (let* ((out-file (or (cdr (assq :file params))
                       (error "Chess block requires :file parameter")))
         (out-file-abs (expand-file-name out-file default-directory))
         (tex-content (concat
                       aj/chess-latex-docclass "\n"
                       aj/chess-latex-preamble
                       "\\begin{document}\n"
                       body
                       "\n\\end{document}\n"))
         (temporary-file-directory (expand-file-name "ltximg/" default-directory))
         (_mkdir (make-directory temporary-file-directory t))
         (tex-file (make-temp-file "chess-babel-" nil ".tex"))
         (pdf-file (concat (file-name-sans-extension tex-file) ".pdf"))
         (is-svg (string-suffix-p ".svg" out-file))
         (result nil))
    ;; Ensure directories exist
    (unless (file-directory-p temporary-file-directory)
      (make-directory temporary-file-directory t))
    (unless (file-directory-p (file-name-directory out-file-abs))
      (make-directory (file-name-directory out-file-abs) t))
    ;; Write tex file
    (with-temp-file tex-file
      (insert tex-content))
    ;; Compile LaTeX
    (let ((latex-exit (call-process "lualatex" nil nil nil
                                    "-interaction=nonstopmode"
                                    (format "-output-directory=%s" temporary-file-directory)
                                    tex-file)))
      (if (/= latex-exit 0)
          (error "LaTeX compilation failed. Check %s"
                 (concat (file-name-sans-extension tex-file) ".log"))
        ;; Convert to image
        (let ((convert-exit
               (if is-svg
                   (call-process "inkscape" nil nil nil
                                 "--pdf-poppler"
                                 "--export-text-to-path"
                                 "--export-plain-svg"
                                 "--export-area-drawing"
                                 (format "--export-filename=%s" out-file-abs)
                                 pdf-file)
                 (call-process "convert" nil nil nil
                               "-density" "300"
                               "-trim" "-antialias"
                               pdf-file
                               "-quality" "100"
                               out-file-abs))))
          (if (/= convert-exit 0)
              (error "Image conversion failed")
            (setq result out-file)))))
    ;; Return the file path for org-babel to use
    result))

;; ---------------------------------------------------------------------------
;; Org Core Settings
;; ---------------------------------------------------------------------------

(use-package org
  :straight nil
  :config
  (setq org-M-RET-may-split-line '((default . nil)))
  (setq org-insert-heading-respect-content t)
  (setq org-log-done 'time)
  (setq org-log-into-drawer t)
  (setq org-directory "/Users/aayushbajaj/lattice/notes/daily/")
  ;; problems.org is the uni spaced re-attempt queue (gcal.org is appended
  ;; further down by the org-gcal section). Everything else stays out of the
  ;; agenda deliberately — the dailies machinery has its own scanner.
  (setq org-agenda-files '("/Users/aayushbajaj/lattice/notes/uni/problems.org"))
  ;; C-c a u — the morning re-attempt queue, restricted to problems.org so
  ;; calendar entries don't drown it.
  (setq org-agenda-custom-commands
        '(("u" "Uni — re-attempt queue"
           ((agenda "" ((org-agenda-span 'day)
                        (org-agenda-overriding-header "Due today (blank page, zero AI)")))
            (todo "RETRY" ((org-agenda-overriding-header "In rotation (RETRY)")))
            (todo "NEW" ((org-agenda-overriding-header "Never attempted (NEW)"))))
           ((org-agenda-files '("/Users/aayushbajaj/lattice/notes/uni/problems.org"))))))
  (setq org-todo-keywords
        '((sequence "TODO(t)" "WAIT(w!)" "|" "CANCEL(c!)" "DONE(d!)")))

  ;; ---------------------------------------------------------------------------
  ;; Native Syntax Highlighting in Source Blocks
  ;; ---------------------------------------------------------------------------
  ;; This applies the language's major-mode font-lock to #+begin_src blocks
  (setq org-src-fontify-natively t)
  (setq org-src-tab-acts-natively t)
  (setq org-edit-src-content-indentation 0))

;; ---------------------------------------------------------------------------
;; Keep #+begin_src / #+end_src fences pinned to the block's own column
;; ---------------------------------------------------------------------------
;; With `org-src-tab-acts-natively', `org-indent-line' treats the fence lines
;; as code and indents them to the language's column — so hitting RET at the
;; start of #+end_src (electric-indent re-indents the line) shoves the fence
;; out to the last code line's indentation.  Just turning native indent off
;; doesn't help: org's fallback then indents the fence "like the line above"
;; (still the code column).  Pin fence lines to the indentation of their own
;; #+begin_src instead (column 0 for a top-level block).
(defun aj/org-indent-line--pin-src-fences (orig)
  "Around-advice: indent a #+begin_src/#+end_src fence to its block column."
  (if (let ((case-fold-search t))
        (save-excursion
          (forward-line 0)
          (looking-at-p "[ \t]*#\\+\\(?:begin\\|end\\)_src\\b")))
      (let ((col (ignore-errors
                   (save-excursion
                     (goto-char (org-element-property :begin (org-element-at-point)))
                     (current-indentation)))))
        ;; `indent-line-to' is documented to leave point at the end of the
        ;; indentation, i.e. BOL for a column-0 fence.  When this advice fires
        ;; during programmatic indentation (org-tempo's `<s'+TAB inserts a
        ;; `#+begin_src' fence then runs `indent-according-to-mode' mid-build),
        ;; that point-leak yanks point to BOL and the rest of the template gets
        ;; inserted *before* the fence — producing a reversed block.  Preserve
        ;; point; the re-indentation is a buffer edit and persists regardless.
        (save-excursion (indent-line-to (or col 0))))
    (funcall orig)))
(advice-add 'org-indent-line :around #'aj/org-indent-line--pin-src-fences)

;; ---------------------------------------------------------------------------
;; Auto-tangle on C-c C-c
;; ---------------------------------------------------------------------------
;; `C-c C-c' on a src block *executes* it; it does not tangle.  Wire tangling
;; onto the same key for blocks that declare a `:tangle' target, so the on-disk
;; file (e.g. Graph.py) stays in sync as you work.  `org-ctrl-c-ctrl-c-hook'
;; runs on the actual keypress (not on exports or programmatic execution) and,
;; because this returns nil, org still goes on to execute the block as usual.
;; Tangle the *whole buffer* (not just the block at point) so a target
;; assembled from several blocks is written completely rather than clobbered
;; down to the one block under point.  Guarded so a tangle error can never
;; block execution of the cell.
(defun aj/org-tangle-on-ctrl-c-ctrl-c ()
  "Tangle the buffer when C-c C-c runs on a src block with a `:tangle' target.
Returns nil so org still executes the block; a no-op elsewhere."
  (when (org-in-src-block-p)
    (let ((tangle (cdr (assq :tangle (nth 2 (org-babel-get-src-block-info t))))))
      (when (and tangle (not (equal tangle "no")))
        (condition-case err
            (org-babel-tangle)
          (error (message "Auto-tangle failed: %s" (error-message-string err)))))))
  nil)
(add-hook 'org-ctrl-c-ctrl-c-hook #'aj/org-tangle-on-ctrl-c-ctrl-c)

;; ---------------------------------------------------------------------------
;; Indent / dedent a whole src block from the org view (no C-c ')
;; ---------------------------------------------------------------------------
;; `org-src-tab-acts-natively' already makes TAB / `indent-region' indent code
;; natively inside an inline block.  These wrap that for the *whole block at
;; point* in one key, via `org-babel-do-in-edit-buffer' — the edit buffer is
;; spun up and synced back transiently, so you never leave the org buffer.
;;   C-c TAB        → re-indent (normalise) the block natively
;;   C-c S-TAB      → shift the block left one indentation level
(defun aj/org-indent-src-block ()
  "Re-indent the whole src block at point using its language's indentation.
Outside a src block fall back to `org-ctrl-c-tab', preserving org's
default on this key."
  (interactive)
  (if (org-in-src-block-p)
      (progn
        (org-babel-do-in-edit-buffer
         (indent-region (point-min) (point-max)))
        (message "Re-indented src block"))
    (call-interactively #'org-ctrl-c-tab)))

(defun aj/org-dedent-src-block ()
  "Shift the whole src block at point left by one indentation level.
Preserves relative structure; refuses (with a message) if any line is
already at the left margin, so the block's nesting is never flattened."
  (interactive)
  (if (not (org-in-src-block-p))
      (message "Not in a src block")
    (org-babel-do-in-edit-buffer
     (let ((step (if (and (boundp 'python-indent-offset) python-indent-offset)
                     python-indent-offset 4))
           (min-indent most-positive-fixnum))
       (save-excursion
         (goto-char (point-min))
         (while (not (eobp))
           (unless (looking-at-p "[ \t]*$")
             (setq min-indent (min min-indent (current-indentation))))
           (forward-line 1)))
       (if (>= min-indent step)
           (progn
             (indent-rigidly (point-min) (point-max) (- step))
             (message "Dedented src block one level"))
         (message "Can't dedent: a line is already at the left margin"))))))

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c TAB")       #'aj/org-indent-src-block)
  (define-key org-mode-map (kbd "C-c <backtab>") #'aj/org-dedent-src-block)
  (define-key org-mode-map (kbd "C-c S-TAB")     #'aj/org-dedent-src-block))

;; ---------------------------------------------------------------------------
;; Don't comma-escape *indented* code lines in src blocks
;; ---------------------------------------------------------------------------
;; On write-back from a src edit buffer (C-c ', or `org-babel-do-in-edit-
;; buffer'), org guards block content by prepending a comma to any line
;; beginning with `*' or `#+', so it can't be misread as a headline/keyword.
;; Its regexp allows leading whitespace, so it also escapes *indented* lines —
;; turning Python star-unpacking / `*args' (e.g. `    *evidence, query = xs')
;; into `    ,*evidence', which reads as broken.  (Org strips the comma again
;; on execute/tangle/export, so the code always *ran* fine — it just looked
;; wrong in the buffer.)  Only a column-0 `*'/`#+' can actually collide with
;; org syntax, so after the stock escaper runs, strip the comma it added to
;; indented lines; column-0 escaping is left intact.
(defun aj/org-escape-code-in-region--col0 (orig beg end)
  "Run ORIG region-escaping, then un-escape *indented* `*'/`#+' lines.
Leaves column-0 escaping — the only case that can be mistaken for a
headline/keyword — untouched."
  (let ((m (copy-marker end)))
    (funcall orig beg end)
    (save-excursion
      (goto-char beg)
      (while (re-search-forward "^[ \t]+\\(,\\),*\\(?:\\*\\|#\\+\\)" m t)
        (replace-match "" nil nil nil 1)))
    (set-marker m nil)))
(with-eval-after-load 'org-src
  (advice-add 'org-escape-code-in-region :around
              #'aj/org-escape-code-in-region--col0))

;; ---------------------------------------------------------------------------
;; Org Templates
;; ---------------------------------------------------------------------------

(with-eval-after-load 'org
  (require 'org-tempo)
  (setq org-babel-default-header-args:jupyter-python
        '((:session . "leet")))
  (add-to-list 'org-structure-template-alist '("sj" . "src jupyter-python"))
  (add-to-list 'org-structure-template-alist '("sp" . "src python"))
  (add-to-list 'org-structure-template-alist '("sr" . "src R")))

;; Org element compatibility shim for packages expecting Org 9.7 AST API
(with-eval-after-load 'org-element
  (unless (fboundp 'org-element--property)
    (defun org-element--property (property node &optional dflt _force-undefer)
      "Compatibility shim for Org 9.7's AST API."
      (or (org-element-property property node) dflt))))

;; ---------------------------------------------------------------------------
;; Org Capture Templates
;; ---------------------------------------------------------------------------

(setq org-export-coding-system 'utf-8)

;; Bind C-c c directly to org-capture
(global-set-key (kbd "C-c c") #'org-capture)

;; Org agenda
(global-set-key (kbd "C-c A") #'org-agenda)

;; ---------------------------------------------------------------------------
;; LaTeX Document Classes
;; ---------------------------------------------------------------------------

(with-eval-after-load 'ox-latex
  ;; Override default article to support 6 heading levels with custom formatting
  ;; Use Menlo for monospace to support Unicode box-drawing characters
  ;; Must delete first — add-to-list won't replace an existing "article" entry
  (setq org-latex-classes (assoc-delete-all "article" org-latex-classes))
  (push '("article"
                 "\\documentclass[11pt,a4paper]{article}
[NO-DEFAULT-PACKAGES]
\\usepackage{amsmath}
\\usepackage{amssymb}
\\usepackage{fontspec}
\\directlua{luaotfload.add_fallback(\"mainfallback\", {
  \"TeX Gyre Termes:mode=node;\",
  \"Hiragino Kaku Gothic ProN:mode=node;\",
  \"Apple Color Emoji:mode=node;\",
})}
\\setmainfont{Latin Modern Roman}[Ligatures=TeX, RawFeature={fallback=mainfallback}]
\\setmonofont{Menlo}[Scale=0.9]
\\usepackage{twemojis}  % weather/moon emoji rendered as TikZ (see aj/latex-filter-twemoji)
\\usepackage{graphicx}
\\usepackage{longtable}
\\usepackage{adjustbox}
\\usepackage{wrapfig}
\\usepackage{rotating}
\\usepackage[normalem]{ulem}
\\usepackage{capt-of}
\\usepackage[dvipsnames]{xcolor}
\\usepackage{hyperref}

% Paragraph heading formatting (for deep headline levels)
\\usepackage{titlesec}
\\titleformat{\\paragraph}{\\normalfont\\normalsize\\bfseries}{\\theparagraph}{1em}{}
\\titlespacing*{\\paragraph}{0pt}{2.5ex plus 1ex minus .2ex}{1ex plus .2ex}
\\setcounter{secnumdepth}{6}
\\setcounter{tocdepth}{6}

% Paragraph spacing (no indent, vertical skip between paragraphs)
\\usepackage[skip=10pt, indent=0pt]{parskip}

% Page margins
\\usepackage[top=20mm,bottom=20mm,left=20mm,right=20mm]{geometry}

% List formatting
\\usepackage{enumitem}
\\setlist[description]{leftmargin=!,labelwidth=1.5em,itemindent=0pt}
\\setlist[itemize]{leftmargin=1.5em,topsep=0pt}"
                 ("\\section{%s}" . "\\section*{%s}")
                 ("\\subsection{%s}" . "\\subsection*{%s}")
                 ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
                 ("\\paragraph{%s}" . "\\paragraph*{%s}")
                 ("\\subparagraph{%s}" . "\\subparagraph*{%s}"))
        org-latex-classes)
  (setq org-latex-classes (assoc-delete-all "standalone" org-latex-classes))
  (push '("standalone"
          "\\documentclass{standalone}"
          ("\\section{%s}" . "\\section*{%s}")
          ("\\subsection{%s}" . "\\subsection*{%s}")
          ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
          ("\\paragraph{%s}" . "\\paragraph*{%s}")
          ("\\subparagraph{%s}" . "\\subparagraph*{%s}"))
        org-latex-classes)
  (setq org-latex-classes (assoc-delete-all "scrartcl" org-latex-classes))
  (push '("scrartcl"
          "\\documentclass{scrartcl}"
          ("\\section{%s}" . "\\section*{%s}")
          ("\\subsection{%s}" . "\\subsection*{%s}")
          ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
          ("\\paragraph{%s}" . "\\paragraph*{%s}")
          ("\\subparagraph{%s}" . "\\subparagraph*{%s}"))
        org-latex-classes))

;; ---------------------------------------------------------------------------
;; LaTeX Preview Backends
;; ---------------------------------------------------------------------------

;; PDF->SVG via lualatex + inkscape (vector, crisp at any zoom)
(add-to-list 'org-preview-latex-process-alist
             '(ajlua
               :programs ("lualatex" "inkscape")
               :description "pdf > svg (vector)"
               :message "Requires lualatex and inkscape."
               :image-input-type "pdf"
               :image-output-type "svg"
               :image-size-adjust (1.7 . 1.7)
               :post-clean ("")
               :latex-compiler
               ("lualatex -interaction=nonstopmode --shell-escape --output-directory=%o %F")
               :image-converter
               ("inkscape --pdf-poppler --export-text-to-path --export-plain-svg --export-area-drawing --export-filename=%O %f")
               :transparent-image-converter
               ("inkscape --pdf-poppler --export-text-to-path --export-plain-svg --export-area-drawing --export-filename=%O %f")))

;; PDF->PNG via lualatex + imagemagick (raster, scalable via density)
(add-to-list 'org-preview-latex-process-alist
             '(luamagick
               :programs ("lualatex" "magick")
               :description "pdf > png (2x scale)"
               :message "Requires lualatex and imagemagick."
               :use-xcolor t
               :image-input-type "pdf"
               :image-output-type "png"
               :image-size-adjust (2.0 . 2.0)
               :latex-compiler
               ("lualatex -interaction nonstopmode -output-directory %o %f")
               :image-converter
               ;; ImageMagick 7+: use `magick' directly. The legacy `convert'
               ;; shim emits deprecation warnings and in some builds drops the
               ;; image silently, which breaks both org-fragtog previews and
               ;; org-msg LaTeX-fragment export.
               ("magick -density %D %f -trim -antialias -quality 100 %O")))

;; Default to PNG (raster, scalable)

(setq org-preview-latex-default-process 'luamagick)
(setq org-preview-latex-image-directory "ltximg/")
(setq org-startup-with-inline-images t)

(global-set-key (kbd "C-c L") #'aj/latex-preview-toggle)

;; ---------------------------------------------------------------------------
;; LaTeX Preview Toggle (SVG <-> PNG)
;; ---------------------------------------------------------------------------

(defun aj/latex-preview-use-svg ()
  "Use SVG (vector) for LaTeX previews. Crisp but fixed size."
  (interactive)
  (setq org-preview-latex-default-process 'ajlua)
  (message "LaTeX preview: SVG (vector, via inkscape)"))

(defun aj/latex-preview-use-png ()
  "Use PNG (raster) for LaTeX previews. Scalable, 2x size."
  (interactive)
  (setq org-preview-latex-default-process 'luamagick)
  (message "LaTeX preview: PNG (raster, 2x scale)"))

(defvar aj/latex-preview-scale 0.5
  "Display scale factor for custom LaTeX previews (aj/latex-preview-at-point).
Adjusts the `:scale' parameter passed to `create-image'.")

(defun aj/latex-preview-set-scale (factor)
  "Set the LaTeX preview display scale to FACTOR (e.g. 1.5, 2.0)."
  (setq aj/latex-preview-scale factor)
  (message "LaTeX preview scale: %.1fx" factor))

(defun aj/latex-preview-toggle (&optional arg)
  "Toggle between SVG and PNG LaTeX preview backends.
With prefix ARG (\\[universal-argument]), prompt for a PNG scale factor instead."
  (interactive "P")
  (if arg
      (let ((factor (read-number "LaTeX preview scale factor: " 2.0)))
        (aj/latex-preview-set-scale factor))
    (if (eq org-preview-latex-default-process 'ajlua)
        (aj/latex-preview-use-png)
      (aj/latex-preview-use-svg))))

(defun aj/latex-preview-status ()
  "Show current LaTeX preview backend."
  (interactive)
  (message "LaTeX preview: %s" org-preview-latex-default-process))

;; ---------------------------------------------------------------------------
;; Async Parallel LaTeX Preview
;; ---------------------------------------------------------------------------
;; Processes multiple LaTeX fragments concurrently instead of sequentially.

(defvar aj/latex-preview-parallel-jobs 4
  "Number of concurrent LaTeX preview processes.")


;; ---------------------------------------------------------------------------
;; LaTeX Preview at Point (works inside export blocks)
;; ---------------------------------------------------------------------------
;; Supports tikzpicture, algorithm, and other environments inside Hugo shortcodes.

(defvar aj/latex-preview-environments
  '(("tikzpicture" . (:packages ("\\usepackage{tikz}"
                                  "\\usepackage{pgfplots}"
                                  "\\pgfplotsset{compat=1.16}"
                                  "\\usetikzlibrary{shapes.geometric,shapes.multipart,positioning,arrows,arrows.meta,calc,chains,decorations.pathreplacing,backgrounds}")
                      :docclass "\\documentclass[tikz,border=2pt]{standalone}"))
    ("algorithm" . (:packages ("\\usepackage[ruled,lined]{algorithm2e}")
                    :docclass "\\documentclass[border=2pt]{standalone}")))
  "Alist of LaTeX environments to preview.
Each entry is (ENV-NAME . (:packages LIST :docclass STRING)).
When :use-buffer-preamble is t, the render function uses the buffer's
#+LATEX_HEADER lines as preamble instead of standalone docclass.")

;; Theorem-style environments: render using the buffer's own preamble
;; so that custom theorem styles, colors, and mdframed boxes work correctly
(dolist (env '("definition" "theorem" "lemma" "corollary" "proposition"
               "examples" "remark" "result" "proof"))
  (add-to-list 'aj/latex-preview-environments
               (cons env '(:use-buffer-preamble t))))

(defun aj/latex--extract-balanced-braces (start)
  "Extract content from START to matching closing brace, handling nesting."
  (save-excursion
    (goto-char start)
    (when (looking-at "{")
      (let ((depth 1)
            (end nil))
        (forward-char 1)
        (while (and (> depth 0) (not (eobp)))
          (cond
           ((looking-at "{") (setq depth (1+ depth)))
           ((looking-at "}") (setq depth (1- depth))))
          (forward-char 1))
        (when (= depth 0)
          (buffer-substring-no-properties start (point)))))))

(defun aj/latex--extract-preamble-commands (start-limit env-beg)
  "Extract preamble commands between START-LIMIT and ENV-BEG.
Extracts: \\usetikzlibrary, \\tikzstyle, \\tikzset, \\newcommand, \\def, \\renewcommand."
  (let ((commands ""))
    (save-excursion
      (goto-char start-limit)
      ;; Extract \usetikzlibrary{...}
      (while (re-search-forward "\\\\usetikzlibrary{[^}]+}" env-beg t)
        (setq commands (concat commands (match-string 0) "\n")))
      (goto-char start-limit)
      ;; Extract \tikzstyle{...}=... or \tikzstyle{...} ... (up to newline or next command)
      (while (re-search-forward "\\\\tikzstyle{[^}]+}\\s-*=\\s-*\\[[^]]*\\]" env-beg t)
        (setq commands (concat commands (match-string 0) "\n")))
      (goto-char start-limit)
      ;; Extract \tikzset{...} with balanced braces (handles nested braces)
      (while (re-search-forward "\\\\tikzset" env-beg t)
        (skip-chars-forward " \t\n")
        (when (looking-at "{")
          (let ((braces (aj/latex--extract-balanced-braces (point))))
            (when braces
              (setq commands (concat commands "\\tikzset" braces "\n"))))))
      (goto-char start-limit)
      ;; Extract \newcommand{\name}... and \newcommand*{\name}...
      (while (re-search-forward "\\\\\\(re\\)?newcommand\\*?" env-beg t)
        (let ((cmd-start (match-beginning 0))
              (cmd-name (match-string 0)))
          (skip-chars-forward " \t\n")
          (when (looking-at "{")
            ;; Get the command name braces
            (let ((name-braces (aj/latex--extract-balanced-braces (point))))
              (when name-braces
                (goto-char (+ (point) (length name-braces)))
                (skip-chars-forward " \t\n")
                ;; Optional argument count [n]
                (when (looking-at "\\[")
                  (re-search-forward "\\]" env-beg t)
                  (skip-chars-forward " \t\n"))
                ;; Optional default value [default]
                (when (looking-at "\\[")
                  (re-search-forward "\\]" env-beg t)
                  (skip-chars-forward " \t\n"))
                ;; The definition body
                (when (looking-at "{")
                  (let ((body-braces (aj/latex--extract-balanced-braces (point))))
                    (when body-braces
                      (setq commands (concat commands
                                             (buffer-substring-no-properties cmd-start (point))
                                             body-braces "\n"))))))))))
      (goto-char start-limit)
      ;; Extract \def\name... (simpler syntax, goes to end of line or next \def/\newcommand)
      (while (re-search-forward "\\\\def\\\\[a-zA-Z@]+" env-beg t)
        (let ((def-start (match-beginning 0)))
          ;; Find the definition body - could be {braces} or just tokens until newline
          (skip-chars-forward " \t#0-9")
          (if (looking-at "{")
              (let ((braces (aj/latex--extract-balanced-braces (point))))
                (when braces
                  (setq commands (concat commands
                                         (buffer-substring-no-properties def-start (point))
                                         braces "\n"))))
            ;; No braces - take until end of line
            (end-of-line)
            (setq commands (concat commands
                                   (buffer-substring-no-properties def-start (point)) "\n"))))))
    commands))

(defun aj/latex--find-block-start ()
  "Find the start of the enclosing export block, special block, or shortcode region."
  (save-excursion
    (or (and (re-search-backward "^#\\+BEGIN_EXPORT\\|^#\\+begin_" nil t) (point))
        (and (re-search-backward "{{<" nil t) (point))
        (point-min))))

(defun aj/latex--find-environment-at-point ()
  "Find which LaTeX environment point is inside.
Returns (ENV-NAME BEG END) or nil."
  (save-excursion
    (let ((pos (point))
          (case-fold-search nil)
          result)
      (dolist (env-spec aj/latex-preview-environments)
        (let ((env-name (car env-spec)))
          (save-excursion
            (goto-char pos)
            (when (re-search-backward (format "\\\\begin{%s}" env-name) nil t)
              (let ((beg (match-beginning 0)))
                (when (re-search-forward (format "\\\\end{%s}" env-name) nil t)
                  (let ((end (point)))
                    (when (and (<= beg pos) (<= pos end))
                      ;; Found it - check if it's closer than previous match
                      (when (or (null result) (> beg (nth 1 result)))
                        (setq result (list env-name beg end)))))))))))
      result)))

(defun aj/latex-preview-at-point ()
  "Preview LaTeX environment at point, even inside export blocks.
Supports tikzpicture, algorithm, and other configured environments.
Extracts the environment and renders it, ignoring surrounding document structure."
  (interactive)
  (let ((env-info (aj/latex--find-environment-at-point)))
    (if (not env-info)
        (message "No supported LaTeX environment found at point")
      (let* ((env-name (nth 0 env-info))
             (beg (nth 1 env-info))
             (end (nth 2 env-info))
             (block-start (save-excursion
                            (goto-char beg)
                            (aj/latex--find-block-start)))
             (extra-preamble (aj/latex--extract-preamble-commands block-start beg))
             (content (buffer-substring-no-properties beg end)))
        (aj/latex--render-preview env-name content beg end extra-preamble)))))

;; Keep old name as alias for compatibility
(defalias 'aj/tikz-preview-at-point 'aj/latex-preview-at-point)

(defvar aj/latex-preview-log-buffer "*Org LaTeX Preview Output*"
  "Buffer name for LaTeX preview compilation output.")

(defun aj/latex--show-error (tex-file log-file env-name)
  "Show LaTeX compilation error for TEX-FILE in a buffer.
LOG-FILE is the .log file, ENV-NAME is the environment type."
  (let ((log-content (when (file-exists-p log-file)
                       (with-temp-buffer
                         (insert-file-contents log-file)
                         (buffer-string))))
        (tex-content (when (file-exists-p tex-file)
                       (with-temp-buffer
                         (insert-file-contents tex-file)
                         (buffer-string)))))
    (with-current-buffer (get-buffer-create aj/latex-preview-log-buffer)
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (insert (format "\n%s\n" (make-string 70 ?=)))
        (insert (format "LaTeX compilation FAILED for %s\n" env-name))
        (insert (format "Time: %s\n" (current-time-string)))
        (insert (format "%s\n\n" (make-string 70 ?=)))
        (insert "=== TeX Source ===\n")
        (insert (or tex-content "(no tex file)"))
        (insert "\n\n=== Error Log ===\n")
        ;; Extract just the error portion from the log
        (if log-content
            (let ((error-start (string-match "^!" log-content)))
              (if error-start
                  (insert (substring log-content error-start
                                     (min (+ error-start 2000) (length log-content))))
                (insert (substring log-content
                                   (max 0 (- (length log-content) 2000))))))
          (insert "(no log file)"))
        (insert "\n")))
    (display-buffer aj/latex-preview-log-buffer)))

(defun aj/latex--fg-color-command ()
  "Return a LaTeX \\color{...} command matching the current Emacs foreground.
Returns e.g. \"\\color[HTML]{E4E4EF}\" for dark themes, or empty string for light."
  (let* ((fg (face-attribute 'default :foreground nil t))
         (rgb (color-values fg)))
    (if rgb
        (format "\\color[HTML]{%02X%02X%02X}\n"
                (/ (nth 0 rgb) 256)
                (/ (nth 1 rgb) 256)
                (/ (nth 2 rgb) 256))
      "")))

(defun aj/latex--render-preview (env-name content beg end &optional extra-preamble)
  "Render LaTeX CONTENT of environment ENV-NAME as preview overlay between BEG and END.
EXTRA-PREAMBLE contains additional preamble commands extracted from the block."
  (let* ((env-config (cdr (assoc env-name aj/latex-preview-environments)))
         (use-buf-preamble (plist-get env-config :use-buffer-preamble))
         (docclass (if use-buf-preamble nil
                     (or (plist-get env-config :docclass)
                         "\\documentclass[border=2pt]{standalone}")))
         (packages (unless use-buf-preamble
                     (or (plist-get env-config :packages) '())))
         (temporary-file-directory (expand-file-name "ltximg/" default-directory))
         (_mkdir (make-directory temporary-file-directory t))
         (tex-file (make-temp-file "latex-" nil ".tex"))
         (pdf-file (concat (file-name-sans-extension tex-file) ".pdf"))
         (log-file (concat (file-name-sans-extension tex-file) ".log"))
         (img-file (concat (file-name-sans-extension tex-file)
                           (if (eq org-preview-latex-default-process 'ajlua) ".svg" ".png")))
         (fg-cmd (aj/latex--fg-color-command))
         (preamble (if use-buf-preamble
                       (aj/latex--buffer-preview-preamble extra-preamble)
                     (concat
                      docclass "\n"
                      (mapconcat #'identity packages "\n") "\n"
                      "\\usepackage{xcolor}\n"
                      (or extra-preamble "")
                      "\\begin{document}\n")))
         (postamble "\n\\end{document}\n")
         (full-content (concat preamble fg-cmd content postamble)))
    ;; Ensure directory exists
    (unless (file-directory-p temporary-file-directory)
      (make-directory temporary-file-directory t))
    ;; Write tex file
    (with-temp-file tex-file
      (insert full-content))
    ;; Compile asynchronously
    (message "Rendering %s..." env-name)
    (let* ((default-directory temporary-file-directory)
           (process-name "latex-preview")
           (latex-cmd (format "lualatex -interaction=nonstopmode -output-directory=%s %s"
                              (shell-quote-argument temporary-file-directory)
                              (shell-quote-argument tex-file)))
           (convert-cmd (if (eq org-preview-latex-default-process 'ajlua)
                            (format "inkscape --pdf-poppler --export-text-to-path --export-plain-svg --export-area-drawing --export-filename=%s %s"
                                    (shell-quote-argument img-file)
                                    (shell-quote-argument pdf-file))
                          (format "magick -density 300 %s -trim -antialias -quality 100 %s"
                                  (shell-quote-argument pdf-file)
                                  (shell-quote-argument img-file))))
           (buf (current-buffer)))
      (set-process-sentinel
       (start-process-shell-command process-name nil latex-cmd)
       (lambda (proc _event)
         (when (eq (process-status proc) 'exit)
           (if (not (= (process-exit-status proc) 0))
               (progn
                 (message "LaTeX compilation failed for %s - see %s"
                          env-name aj/latex-preview-log-buffer)
                 (aj/latex--show-error tex-file log-file env-name))
             ;; Convert PDF to image
             (set-process-sentinel
              (start-process-shell-command "latex-convert" nil convert-cmd)
              (lambda (proc2 _event2)
                (when (eq (process-status proc2) 'exit)
                  (if (not (= (process-exit-status proc2) 0))
                      (message "Image conversion failed for %s" env-name)
                    ;; Create overlay with image
                    (when (and (file-exists-p img-file) (buffer-live-p buf))
                      (with-current-buffer buf
                        (aj/latex--create-overlay beg end img-file))
                      (message "%s preview complete" env-name)))))))))))))

(defun aj/latex--create-overlay (beg end img-file)
  "Create an overlay from BEG to END displaying IMG-FILE."
  ;; Remove existing overlays in region
  (dolist (ov (overlays-in beg end))
    (when (overlay-get ov 'aj-latex-preview)
      (delete-overlay ov)))
  ;; Create new overlay
  (let* ((img-type (if (string-suffix-p ".svg" img-file) 'svg nil))
         (ov (make-overlay beg end)))
    (overlay-put ov 'aj-latex-preview t)
    (overlay-put ov 'display
                 (create-image img-file img-type nil
                               :ascent 'center
                               :scale aj/latex-preview-scale))
    (overlay-put ov 'face 'default)
    (overlay-put ov 'evaporate t)))

(defun aj/latex-clear-previews ()
  "Clear all LaTeX environment preview overlays in buffer."
  (interactive)
  (dolist (ov (overlays-in (point-min) (point-max)))
    (when (overlay-get ov 'aj-latex-preview)
      (delete-overlay ov)))
  (message "LaTeX previews cleared"))

;; Keep old name as alias for compatibility
(defalias 'aj/tikz-clear-previews 'aj/latex-clear-previews)

;; ---------------------------------------------------------------------------
;; Chess Diagram Preview (using buffer #+LATEX_HEADER directives)
;; ---------------------------------------------------------------------------

(defun aj/latex--extract-buffer-headers ()
  "Extract all #+LATEX_HEADER lines from the buffer."
  (let ((headers ""))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^#\\+LATEX_HEADER:\\s-*\\(.+\\)$" nil t)
        (setq headers (concat headers (match-string 1) "\n"))))
    headers))

(defun aj/latex--buffer-preview-preamble (&optional extra-preamble)
  "Build a complete LaTeX preamble for previewing theorem-style environments.
Uses the buffer's #+LATEX_HEADER lines (filtered: no geometry commands)
plus base packages needed for article class rendering.
EXTRA-PREAMBLE is appended before \\begin{document}."
  (let* ((raw-headers (aj/latex--extract-buffer-headers))
         ;; Filter out geometry commands (we use our own for preview cropping)
         (filtered-headers
          (mapconcat
           #'identity
           (cl-remove-if
            (lambda (line)
              (or (string-match "\\\\geometry{" line)
                  (string-match "\\\\usepackage.*{geometry}" line)))
            (split-string raw-headers "\n" t))
           "\n")))
    (concat
     "\\documentclass[11pt]{article}\n"
     "\\usepackage[paperwidth=500pt,paperheight=5000pt,margin=10pt]{geometry}\n"
     "\\usepackage{fontspec}\n"
     "\\usepackage{amsmath,amssymb}\n"
     "\\usepackage[dvipsnames]{xcolor}\n"
     "\\usepackage{enumitem}\n"
     "\\usepackage{hyperref}\n"
     "\\hypersetup{colorlinks=false}\n"
     filtered-headers "\n"
     "\\pagestyle{empty}\n"
     (or extra-preamble "")
     "\\begin{document}\n"
     (aj/latex--fg-color-command))))

(defun aj/chess-preview-at-point ()
  "Toggle chessboard preview at point using buffer's #+LATEX_HEADER directives.
If preview exists, remove it. Otherwise, render it."
  (interactive)
  (let* ((block-bounds (aj/latex--find-export-block-at-point)))
    (if (not block-bounds)
        (message "No export block found at point")
      (let* ((beg (car block-bounds))
             (end (cdr block-bounds))
             ;; Check for existing overlay
             (existing (cl-some (lambda (ov) (overlay-get ov 'aj-latex-preview))
                                (overlays-in beg end))))
        (if existing
            ;; Toggle off - remove overlay
            (progn
              (dolist (ov (overlays-in beg end))
                (when (overlay-get ov 'aj-latex-preview)
                  (delete-overlay ov)))
              (message "Chess preview removed"))
          ;; Toggle on - render preview
          (let ((content (buffer-substring-no-properties beg end))
                (headers (aj/latex--extract-buffer-headers)))
            (aj/latex--render-chess-preview content beg end headers)))))))

(defun aj/latex--find-export-block-at-point ()
  "Find the LaTeX export block at point. Returns (BEG . END) of content."
  (save-excursion
    (let ((pos (point))
          beg end)
      ;; Find #+BEGIN_EXPORT latex
      (when (re-search-backward "^#\\+BEGIN_EXPORT\\s-+latex" nil t)
        (forward-line 1)
        (setq beg (point))
        ;; Find #+END_EXPORT
        (when (re-search-forward "^#\\+END_EXPORT" nil t)
          (forward-line 0)
          (setq end (point))
          (when (and (<= beg pos) (<= pos end))
            (cons beg end)))))))

(defun aj/latex--render-chess-preview (content beg end headers)
  "Render chess CONTENT with HEADERS as preamble."
  (let* ((temporary-file-directory (expand-file-name "ltximg/" default-directory))
         (_mkdir (make-directory temporary-file-directory t))
         (tex-file (make-temp-file "chess-" nil ".tex"))
         (pdf-file (concat (file-name-sans-extension tex-file) ".pdf"))
         (log-file (concat (file-name-sans-extension tex-file) ".log"))
         (img-file (concat (file-name-sans-extension tex-file)
                           (if (eq org-preview-latex-default-process 'ajlua) ".svg" ".png")))
         (full-content (concat
                        "\\documentclass[border=2pt]{standalone}\n"
                        headers
                        "\\begin{document}\n"
                        content
                        "\n\\end{document}\n"))
         (buf (current-buffer)))
    (unless (file-directory-p temporary-file-directory)
      (make-directory temporary-file-directory t))
    (with-temp-file tex-file
      (insert full-content))
    (message "Rendering chess diagram...")
    (let* ((default-directory temporary-file-directory)
           (latex-cmd (format "lualatex -interaction=nonstopmode -output-directory=%s %s"
                              (shell-quote-argument temporary-file-directory)
                              (shell-quote-argument tex-file)))
           (convert-cmd (if (eq org-preview-latex-default-process 'ajlua)
                            (format "inkscape --pdf-poppler --export-text-to-path --export-plain-svg --export-area-drawing --export-filename=%s %s"
                                    (shell-quote-argument img-file)
                                    (shell-quote-argument pdf-file))
                          (format "magick -density 300 %s -trim -antialias -quality 100 %s"
                                  (shell-quote-argument pdf-file)
                                  (shell-quote-argument img-file)))))
      (set-process-sentinel
       (start-process-shell-command "chess-preview" nil latex-cmd)
       (lambda (proc _event)
         (when (eq (process-status proc) 'exit)
           (if (/= (process-exit-status proc) 0)
               (aj/latex--show-error tex-file log-file "chessboard")
             (set-process-sentinel
              (start-process-shell-command "chess-convert" nil convert-cmd)
              (lambda (proc2 _event2)
                (when (eq (process-status proc2) 'exit)
                  (if (/= (process-exit-status proc2) 0)
                      (message "Chess image conversion failed")
                    (when (and (file-exists-p img-file) (buffer-live-p buf))
                      (with-current-buffer buf
                        (aj/latex--create-overlay beg end img-file))
                      (message "Chess preview complete")))))))))))))

;; Structure templates: <el + TAB, <sl + TAB, <ch + TAB
(with-eval-after-load 'org
  (add-to-list 'org-structure-template-alist '("el" . "export latex"))
  (add-to-list 'org-structure-template-alist '("sl" . "src latex"))
  (add-to-list 'org-structure-template-alist '("ch" . "src chess :file ")))

;; ---------------------------------------------------------------------------
;; Export filter: #+begin_src latex → raw LaTeX on export
;; ---------------------------------------------------------------------------
;; This allows using #+begin_src latex blocks for syntax highlighting in the
;; org buffer while still exporting the content as raw LaTeX (not code listings).

(defun aj/org-latex-src-to-export (backend)
  "Convert #+begin_src latex blocks to #+begin_export latex for LaTeX export.
This makes src latex blocks export as raw LaTeX instead of code listings,
while preserving syntax highlighting in the org buffer."
  (when (org-export-derived-backend-p backend 'latex)
    (goto-char (point-min))
    (while (re-search-forward "^\\([ \t]*\\)#\\+begin_src latex\\b.*$" nil t)
      (let ((indent (match-string 1)))
        (replace-match (concat indent "#+begin_export latex"))
        (when (re-search-forward
               (concat "^" (regexp-quote indent) "#\\+end_src\\b") nil t)
          (replace-match (concat indent "#+end_export")))))))

(add-hook 'org-export-before-processing-hook #'aj/org-latex-src-to-export)

;; ---------------------------------------------------------------------------
;; Comprehensive LaTeX Preview (standard fragments + export block environments)
;; ---------------------------------------------------------------------------

(defvar aj/latex-env-preview--queue nil
  "Queue of environments waiting to be rendered.")

(defvar aj/latex-env-preview--active 0
  "Number of currently active environment preview processes.")

(defvar aj/latex-env-preview--total 0
  "Total environments to process in current batch.")

(defvar aj/latex-env-preview--completed 0
  "Environments completed in current batch.")

(defvar aj/latex-env-preview--buffer nil
  "Buffer being processed for environment previews.")

(defun aj/latex--find-all-environments-in-buffer ()
  "Find all LaTeX environments in export/src blocks throughout the buffer.
Returns a list of (ENV-NAME BEG END EXTRA-PREAMBLE) for each environment found.
Also detects chess blocks (export blocks containing \\chessboard commands)."
  (let ((envs nil)
        (case-fold-search nil)
        (buffer-headers (aj/latex--extract-buffer-headers)))
    (save-excursion
      (goto-char (point-min))
      ;; Find all export blocks, src latex blocks, and special blocks
      (while (re-search-forward "^#\\+\\(?:BEGIN_EXPORT\\s-+latex\\|begin_src latex\\b\\)" nil t)
        (let* ((is-src (save-excursion
                         (goto-char (match-beginning 0))
                         (looking-at-p ".*begin_src")))
               (block-start (save-excursion (forward-line 1) (point)))
               (end-pattern (if is-src "^#\\+end_src" "^#\\+END_EXPORT"))
               (block-end (save-excursion
                            (when (re-search-forward end-pattern nil t)
                              (forward-line 0)
                              (point)))))
          (when block-end
            (let ((block-content (buffer-substring-no-properties block-start block-end)))
              ;; Check for chess content first (uses buffer headers)
              (if (string-match "\\\\chessboard\\|\\\\newchessgame\\|\\\\setchessboard" block-content)
                  (push (list "chess" block-start block-end buffer-headers) envs)
                ;; Otherwise search for standard environments
                (dolist (env-spec aj/latex-preview-environments)
                  (let ((env-name (car env-spec)))
                    (save-excursion
                      (goto-char block-start)
                      (while (re-search-forward
                              (format "\\\\begin{%s}" (regexp-quote env-name))
                              block-end t)
                        (let ((beg (match-beginning 0)))
                          (when (re-search-forward
                                 (format "\\\\end{%s}" (regexp-quote env-name))
                                 block-end t)
                            (push (list env-name beg (point) nil) envs)))))))))
            (goto-char block-end)))))
    (nreverse envs)))

(defun aj/latex-env-preview--update-status ()
  "Update minibuffer with environment preview progress."
  (if (= aj/latex-env-preview--completed aj/latex-env-preview--total)
      (message "Rendering complete: %d/%d environments done"
               aj/latex-env-preview--completed
               aj/latex-env-preview--total)
    (message "Rendering tikzpictures: %d/%d done, %d active"
             aj/latex-env-preview--completed
             aj/latex-env-preview--total
             aj/latex-env-preview--active)))

(defun aj/latex-env-preview--process-next ()
  "Process next environment from queue if slots available."
  (while (and aj/latex-env-preview--queue
              (< aj/latex-env-preview--active aj/latex-preview-parallel-jobs))
    (let* ((env-info (pop aj/latex-env-preview--queue))
           (env-name (nth 0 env-info))
           (beg (nth 1 env-info))
           (end (nth 2 env-info))
           (stored-preamble (nth 3 env-info)))  ; For chess, this contains buffer headers
      (when (and beg end (buffer-live-p aj/latex-env-preview--buffer))
        (cl-incf aj/latex-env-preview--active)
        (with-current-buffer aj/latex-env-preview--buffer
          (let* ((content (buffer-substring-no-properties beg end))
                 ;; For chess, use stored buffer headers; otherwise extract preamble commands
                 (extra-preamble (if (string= env-name "chess")
                                     stored-preamble
                                   (let ((block-start (save-excursion
                                                        (goto-char beg)
                                                        (aj/latex--find-block-start))))
                                     (aj/latex--extract-preamble-commands block-start beg)))))
            ;; Skip if already has overlay
            (if (cl-some (lambda (ov) (overlay-get ov 'aj-latex-preview))
                         (overlays-in beg end))
                (progn
                  (cl-decf aj/latex-env-preview--active)
                  (cl-incf aj/latex-env-preview--completed)
                  (aj/latex-env-preview--process-next))
              (aj/latex--render-preview-queued
               env-name content beg end extra-preamble))))))))

(defun aj/latex--render-preview-queued (env-name content beg end &optional extra-preamble)
  "Like `aj/latex--render-preview' but updates queue on completion.
For chess blocks, EXTRA-PREAMBLE contains buffer #+LATEX_HEADER lines to use as packages."
  (let* ((is-chess (string= env-name "chess"))
         (env-config (unless is-chess (cdr (assoc env-name aj/latex-preview-environments))))
         (use-buf-preamble (and env-config (plist-get env-config :use-buffer-preamble)))
         (docclass (cond
                    (is-chess "\\documentclass[border=2pt]{standalone}")
                    (use-buf-preamble nil)
                    (t (or (plist-get env-config :docclass)
                           "\\documentclass[border=2pt]{standalone}"))))
         (packages (unless (or is-chess use-buf-preamble)
                     (or (plist-get env-config :packages) '())))
         (temporary-file-directory (expand-file-name "ltximg/" default-directory))
         (_mkdir (make-directory temporary-file-directory t))
         (tex-file (make-temp-file "latex-" nil ".tex"))
         (pdf-file (concat (file-name-sans-extension tex-file) ".pdf"))
         (log-file (concat (file-name-sans-extension tex-file) ".log"))
         (img-file (concat (file-name-sans-extension tex-file)
                           (if (eq org-preview-latex-default-process 'ajlua) ".svg" ".png")))
         (preamble (cond
                    (is-chess
                     ;; Chess: use buffer headers directly
                     (concat docclass "\n"
                             (or extra-preamble "")
                             "\\begin{document}\n"))
                    (use-buf-preamble
                     ;; Theorem-style: use buffer's full preamble
                     (aj/latex--buffer-preview-preamble extra-preamble))
                    (t
                     ;; Standard: use environment packages + extra preamble
                     (concat docclass "\n"
                             (mapconcat #'identity packages "\n") "\n"
                             "\\usepackage{xcolor}\n"
                             (or extra-preamble "")
                             "\\begin{document}\n"))))
         (postamble "\n\\end{document}\n")
         (full-content (concat preamble content postamble))
         (buf aj/latex-env-preview--buffer))
    (unless (file-directory-p temporary-file-directory)
      (make-directory temporary-file-directory t))
    (with-temp-file tex-file
      (insert full-content))
    (let* ((default-directory temporary-file-directory)
           (latex-cmd (format "lualatex -interaction=nonstopmode -output-directory=%s %s"
                              (shell-quote-argument temporary-file-directory)
                              (shell-quote-argument tex-file)))
           (convert-cmd (if (eq org-preview-latex-default-process 'ajlua)
                            (format "inkscape --pdf-poppler --export-text-to-path --export-plain-svg --export-area-drawing --export-filename=%s %s"
                                    (shell-quote-argument img-file)
                                    (shell-quote-argument pdf-file))
                          (format "magick -density 300 %s -trim -antialias -quality 100 %s"
                                  (shell-quote-argument pdf-file)
                                  (shell-quote-argument img-file)))))
      (set-process-sentinel
       (start-process-shell-command "latex-preview-q" nil latex-cmd)
       (lambda (proc _event)
         (when (eq (process-status proc) 'exit)
           (if (not (= (process-exit-status proc) 0))
               (progn
                 (aj/latex--show-error tex-file log-file env-name)
                 (cl-decf aj/latex-env-preview--active)
                 (cl-incf aj/latex-env-preview--completed)
                 (aj/latex-env-preview--update-status)
                 (aj/latex-env-preview--process-next))
             (set-process-sentinel
              (start-process-shell-command "latex-convert-q" nil convert-cmd)
              (lambda (proc2 _event2)
                (when (eq (process-status proc2) 'exit)
                  (when (and (= (process-exit-status proc2) 0)
                             (file-exists-p img-file)
                             (buffer-live-p buf))
                    (with-current-buffer buf
                      (aj/latex--create-overlay beg end img-file)))
                  (cl-decf aj/latex-env-preview--active)
                  (cl-incf aj/latex-env-preview--completed)
                  (aj/latex-env-preview--update-status)
                  (aj/latex-env-preview--process-next)))))))))))

(defun aj/latex-preview-buffer ()
  "Preview all LaTeX in buffer: standard org fragments AND environments in export blocks.
This is a comprehensive replacement for `org-latex-preview' that also handles
tikzpicture, algorithm, and other environments inside Hugo shortcodes.
Processes environments asynchronously with max `aj/latex-preview-parallel-jobs' concurrent."
  (interactive)
  (message "Generating LaTeX previews...")
  ;; First, preview standard org LaTeX fragments
  (org-latex-preview '(16))  ; C-u prefix = preview buffer
  ;; Then, find and preview all environments in export blocks (queued)
  (let ((envs (aj/latex--find-all-environments-in-buffer)))
    (if (null envs)
        (message "Standard LaTeX previews done. No environments in export blocks found.")
      (setq aj/latex-env-preview--queue envs
            aj/latex-env-preview--active 0
            aj/latex-env-preview--total (length envs)
            aj/latex-env-preview--completed 0
            aj/latex-env-preview--buffer (current-buffer))
      (message "Rendering %d tikzpictures (max %d parallel)..."
               aj/latex-env-preview--total
               aj/latex-preview-parallel-jobs)
      (aj/latex-env-preview--process-next))))

;; Override C-c C-x C-l to use our comprehensive preview
(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c C-x C-l") #'aj/latex-preview-buffer))

;; ---------------------------------------------------------------------------
;; Region LaTeX Preview (compiles region as single document - refs work!)
;; ---------------------------------------------------------------------------

(defun aj/latex-preview-region ()
  "Preview selected region as a SINGLE LaTeX document.
This allows cross-references (\\label, \\ref, \\eqref) to work
because all fragments are compiled together."
  (interactive)
  (unless (use-region-p)
    (user-error "Select a region first"))
  (let* ((beg (region-beginning))
         (end (region-end))
         (content (buffer-substring-no-properties beg end))
         (temporary-file-directory (expand-file-name "ltximg/" default-directory))
         (_mkdir (make-directory temporary-file-directory t))
         (tex-file (make-temp-file "region-" nil ".tex"))
         (pdf-file (concat (file-name-sans-extension tex-file) ".pdf"))
         (img-file (concat (file-name-sans-extension tex-file)
                           (if (eq org-preview-latex-default-process 'ajlua) ".svg" ".png")))
         ;; Extract just the LaTeX parts, strip org markup
         (latex-content (aj/latex--extract-math-from-region content))
         (preamble (concat
                    "\\documentclass[12pt,border=5pt]{standalone}\n"
                    "\\usepackage{amsmath,amssymb,amsthm}\n"
                    "\\usepackage{tikz}\n"
                    "\\usepackage{pgfplots}\n"
                    "\\pgfplotsset{compat=1.16}\n"
                    "\\usetikzlibrary{shapes.geometric,positioning,arrows.meta,calc}\n"
                    "\\usepackage{xcolor}\n"
                    "\\begin{document}\n"))
         (postamble "\n\\end{document}\n")
         (full-content (concat preamble latex-content postamble))
         (buf (current-buffer)))
    ;; Ensure directory exists
    (unless (file-directory-p temporary-file-directory)
      (make-directory temporary-file-directory t))
    ;; Write tex file
    (with-temp-file tex-file
      (insert full-content))
    ;; Deactivate region
    (deactivate-mark)
    ;; Compile
    (message "Compiling region as single document (refs will resolve)...")
    (let* ((latex-cmd (format "lualatex -interaction=nonstopmode -output-directory=%s %s"
                              (shell-quote-argument temporary-file-directory)
                              (shell-quote-argument tex-file)))
           ;; Run twice for refs
           (latex-cmd-twice (concat latex-cmd " && " latex-cmd))
           (convert-cmd (if (eq org-preview-latex-default-process 'ajlua)
                            (format "inkscape --pdf-poppler --export-text-to-path --export-plain-svg --export-area-drawing --export-filename=%s %s"
                                    (shell-quote-argument img-file)
                                    (shell-quote-argument pdf-file))
                          (format "magick -density 300 %s -trim -antialias -quality 100 %s"
                                  (shell-quote-argument pdf-file)
                                  (shell-quote-argument img-file)))))
      (set-process-sentinel
       (start-process-shell-command "region-latex" nil latex-cmd-twice)
       (lambda (proc _event)
         (when (eq (process-status proc) 'exit)
           (if (not (= (process-exit-status proc) 0))
               (message "LaTeX compilation failed - check %s" tex-file)
             (set-process-sentinel
              (start-process-shell-command "region-convert" nil convert-cmd)
              (lambda (proc2 _event2)
                (when (eq (process-status proc2) 'exit)
                  (if (not (= (process-exit-status proc2) 0))
                      (message "Image conversion failed")
                    (when (and (file-exists-p img-file) (buffer-live-p buf))
                      (with-current-buffer buf
                        (aj/latex--create-region-overlay beg end img-file))
                      (message "Region preview complete (refs resolved)")))))))))))))

(defun aj/latex--extract-math-from-region (content)
  "Extract LaTeX math from CONTENT, preserving structure for refs.
Keeps equations, aligns, and inline math while stripping org syntax."
  (with-temp-buffer
    (insert content)
    ;; Remove org block markers but keep content
    (goto-char (point-min))
    (while (re-search-forward "^[ \t]*#\\+\\(begin\\|end\\)_[a-z0-9]+.*$" nil t)
      (replace-match ""))
    ;; Remove #+attr lines
    (goto-char (point-min))
    (while (re-search-forward "^[ \t]*#\\+attr_.*$" nil t)
      (replace-match ""))
    ;; Keep the math content
    (buffer-string)))

(defun aj/latex--create-region-overlay (beg end img-file)
  "Create overlay from BEG to END showing IMG-FILE."
  ;; Clear existing region overlays
  (dolist (ov (overlays-in beg end))
    (when (overlay-get ov 'aj-region-preview)
      (delete-overlay ov)))
  (let ((ov (make-overlay beg end)))
    (overlay-put ov 'aj-region-preview t)
    (overlay-put ov 'display
                 (create-image img-file nil nil
                               :ascent 'center
                               :scale 3.0))
    (overlay-put ov 'face 'default)
    (overlay-put ov 'evaporate t)))

(defun aj/latex-clear-region-previews ()
  "Clear all region preview overlays."
  (interactive)
  (dolist (ov (overlays-in (point-min) (point-max)))
    (when (overlay-get ov 'aj-region-preview)
      (delete-overlay ov)))
  (message "Region previews cleared"))

;; ---------------------------------------------------------------------------
;; tikzjax Preview (uses WebAssembly TeX - same as Hugo site)
;; ---------------------------------------------------------------------------
;; Provides fidelity with the Hugo site's tikzjax rendering.
;; Outputs SVG only. Use C-c C-x j for tikzjax preview at point.

(defvar aj/tikzjax-cli-path
  (expand-file-name "~/lattice/code/sites/new-site/static/code/tikzjax/cli.js")
  "Path to the tikzjax CLI script.")

(defvar aj/tikzjax-node-path "node"
  "Path to the node executable.")

(defun aj/tikzjax--extract-block-content ()
  "Extract the content between shortcode tags for tikzjax rendering.
Returns (CONTENT BEG END) where BEG/END span the entire export block."
  (save-excursion
    (let ((case-fold-search t)
          block-beg block-end content)
      ;; Find the enclosing export block or special block
      (when (re-search-backward "^#\\+BEGIN_EXPORT\\|^#\\+begin_" nil t)
        (setq block-beg (point))
        (when (re-search-forward "^#\\+END_EXPORT\\|^#\\+end_" nil t)
          (setq block-end (point))
          ;; Get raw content of the block (excluding the #+BEGIN/END lines)
          (goto-char block-beg)
          (forward-line 1)
          (let* ((content-start (point))
                 (content-end (save-excursion
                                (goto-char block-end)
                                (forward-line 0)
                                (point)))
                 (raw-content (buffer-substring-no-properties content-start content-end)))
            ;; Remove Hugo shortcode markers like {{< tikztwo >}} and {{< /tikztwo >}}
            (setq raw-content (replace-regexp-in-string "{{<[^>]*>}}" "" raw-content))
            ;; Remove any blank lines at start/end
            (setq raw-content (string-trim raw-content))
            ;; Check if content has \begin{document}, if not wrap it
            (if (string-match-p "\\\\begin{document}" raw-content)
                (setq content raw-content)
              ;; Wrap in document if not present
              (setq content (concat "\\begin{document}\n" raw-content "\n\\end{document}\n"))))))
      ;; Return result if we have content
      (when (and content (not (string-empty-p content)))
        (list content block-beg block-end)))))

(defun aj/tikzjax-preview-at-point ()
  "Preview tikzpicture at point using tikzjax (WebAssembly TeX).
Uses the same renderer as the Hugo site for guaranteed fidelity.
Output is always SVG."
  (interactive)
  (let ((block-info (aj/tikzjax--extract-block-content)))
    (if (not block-info)
        (message "No export block found at point")
      (let* ((content (nth 0 block-info))
             (beg (nth 1 block-info))
             (end (nth 2 block-info))
             (output-dir (expand-file-name "ltximg/tikzjax/" default-directory))
             (svg-file (expand-file-name
                        (format "tikzjax-%s.svg" (md5 content))
                        output-dir))
             (buf (current-buffer)))
        ;; Ensure output directory exists
        (unless (file-directory-p output-dir)
          (make-directory output-dir t))
        ;; Clear output buffer and show what we're sending
        (with-current-buffer (get-buffer-create "*tikzjax-output*")
          (erase-buffer)
          (insert "=== INPUT SENT TO TIKZJAX ===\n")
          (insert content)
          (insert "\n=== END INPUT ===\n\n"))
        ;; Run tikzjax CLI
        (message "Rendering with tikzjax...")
        (let ((process (make-process
                        :name "tikzjax-preview"
                        :buffer "*tikzjax-output*"
                        :command (list aj/tikzjax-node-path aj/tikzjax-cli-path)
                        :coding '(utf-8-unix . utf-8-unix)
                        :connection-type 'pipe
                        :sentinel (lambda (proc event)
                                    (when (eq (process-status proc) 'exit)
                                      (if (not (= (process-exit-status proc) 0))
                                          (progn
                                            (message "tikzjax rendering failed - see *tikzjax-output*")
                                            (display-buffer "*tikzjax-output*"))
                                        ;; Save SVG and create overlay
                                        (with-current-buffer "*tikzjax-output*"
                                          ;; Find the SVG in the output - extract only <svg>...</svg>
                                          (goto-char (point-min))
                                          (when (re-search-forward "<svg[^>]*>" nil t)
                                            (let ((svg-start (match-beginning 0)))
                                              (when (re-search-forward "</svg>" nil t)
                                                (write-region svg-start (point) svg-file nil 'silent)))))
                                        (when (and (file-exists-p svg-file) (buffer-live-p buf))
                                          (with-current-buffer buf
                                            (aj/latex--create-overlay beg end svg-file))
                                          (message "tikzjax preview complete"))))))))
          ;; Send content to process stdin
          (process-send-string process content)
          (process-send-eof process))))))

;; Keybindings
(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c C-x L") #'aj/latex-preview-buffer)
  ;; TikZ preview at point (lualatex)
  (define-key org-mode-map (kbd "C-c C-x t") #'aj/tikz-preview-at-point)
  (define-key org-mode-map (kbd "C-c C-x T") #'aj/tikz-clear-previews)
  ;; tikzjax preview at point (WebAssembly - site fidelity)
  (define-key org-mode-map (kbd "C-c C-x j") #'aj/tikzjax-preview-at-point)
  ;; Chess preview at point (uses #+LATEX_HEADER directives)
  (define-key org-mode-map (kbd "C-c C-x c") #'aj/chess-preview-at-point)
  ;; Region preview (refs work!) - select region then press this
  (define-key org-mode-map (kbd "C-c C-x r") #'aj/latex-preview-region)
  (define-key org-mode-map (kbd "C-c C-x R") #'aj/latex-clear-region-previews))

;; ---------------------------------------------------------------------------
;; Headline Export Filtering
;; ---------------------------------------------------------------------------
;; Filter to skip headlines deeper than a configurable level during export.
;; Toggle via #+BIND: my/max-headline-export-level 3 in org files.

(setq org-export-allow-bind-keywords t)

(defvar my/max-headline-export-level nil
  "If set, exclude headlines deeper than this level from export.")

(defun my/filter-deep-headlines (tree backend info)
  "Remove headlines deeper than `my/max-headline-export-level'.
Preserves #+LATEX: snippets from removed headlines by moving them up."
  (when my/max-headline-export-level
    (condition-case err
        (let ((to-remove nil)
              (preserved-count 0))
          ;; Collect headlines to remove (in document order)
          (org-element-map tree 'headline
            (lambda (hl)
              (when (> (org-element-property :level hl) my/max-headline-export-level)
                (push hl to-remove))))
          ;; Process in reverse order (deepest/last first)
          (dolist (hl to-remove)
            ;; Find LATEX keywords in this headline's own section
            (let ((latex-keywords nil)
                  (section (org-element-map hl 'section #'identity nil t)))
              (when section
                (org-element-map section 'keyword
                  (lambda (kw)
                    (when (string= (org-element-property :key kw) "LATEX")
                      (push (org-element-copy kw) latex-keywords)))
                  nil nil 'headline))
              ;; Insert keywords before next sibling or at end of parent
              (when latex-keywords
                (let* ((parent (org-element-property :parent hl))
                       (contents (and parent (org-element-contents parent)))
                       (hl-pos (and contents (cl-position hl contents :test #'eq)))
                       (next-sibling (and hl-pos (nth (1+ hl-pos) contents))))
                  (dolist (kw (nreverse latex-keywords))
                    (cl-incf preserved-count)
                    (if next-sibling
                        (org-element-insert-before kw next-sibling)
                      (when parent
                        (org-element-adopt-elements parent kw)))))))
            ;; Remove the headline
            (org-element-extract-element hl))
          (message "Headline filter: removed %d headlines, preserved %d #+LATEX snippets"
                   (length to-remove) preserved-count))
      (error (message "ERROR in headline filter: %s" err))))
  tree)

(add-hook 'org-export-filter-parse-tree-functions #'my/filter-deep-headlines)

;; ---------------------------------------------------------------------------
;; LaTeX Export Settings
;; ---------------------------------------------------------------------------

;; Global export options
(setq org-export-with-smart-quotes t)  ; #+OPTIONS: ':t
(setq org-export-headline-levels 6)    ; #+OPTIONS: H:6

;; Use latexmk for automatic reference/bibliography resolution.
;; Two invocations — the second guards against rare single-pass runs where
;; hyperref's `.out` wasn't read back, producing a PDF with 0 outline entries
;; (xochitl TOC drawer empty). Trigger: 2026-05-14 daily exported with 0
;; bookmarks despite byte-identical input producing 65 on retry. Mirror this
;; in scripts/batch-pdf-init.el (headless export) or the two pipelines drift.
(setq org-latex-pdf-process
      '("latexmk -f -lualatex -shell-escape -interaction=nonstopmode %f"
        "latexmk -f -lualatex -shell-escape -interaction=nonstopmode %f"))

;; Note: xcolor, amssymb, and fontspec are loaded in the article class definition
;; to ensure proper ordering and Unicode monospace font support (Menlo)

;; Configure hyperref link colors via #+LATEX_LINKCOLOR: directive
;; Usage: #+LATEX_LINKCOLOR: red-violet  (default)
;;        #+LATEX_LINKCOLOR: deep-navy

(defvar aj/latex-link-color-default 'red-violet
  "Default link color for LaTeX exports when not specified in file.")

(defun aj/latex--get-file-link-color ()
  "Get link color from #+LATEX_LINKCOLOR directive in current buffer."
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward "^#\\+LATEX_LINKCOLOR:\\s-*\\(\\S-+\\)" nil t)
        (let ((color (downcase (match-string 1))))
          (cond
           ((member color '("deep-navy" "deepnavy" "navy")) 'deep-navy)
           ((member color '("red-violet" "redviolet" "violet")) 'red-violet)
           (t aj/latex-link-color-default)))
      aj/latex-link-color-default)))

(defun aj/latex--hyperref-template-for-color (color)
  "Return hyperref template string for COLOR.
Always defines DeepNavy to ensure it's available for TOC on subsequent runs."
  (let ((color-name (if (eq color 'deep-navy) "DeepNavy" "RedViolet")))
    (concat "\\makeatletter\\@ifpackageloaded{xcolor}{}{\\usepackage{xcolor}}\\makeatother
\\definecolor{DeepNavy}{HTML}{00007B}
\\hypersetup{
 pdfauthor={%a},
 pdftitle={%t},
 pdfkeywords={%k},
 pdfsubject={%d},
 pdfcreator={%c},
 pdflang={%L},
 colorlinks=true,
 linkcolor=" color-name ",
 urlcolor=" color-name "
}")))

(defun aj/latex--set-link-color-before-export (backend)
  "Set hyperref template based on #+LATEX_LINKCOLOR before export.
Only applies to LaTeX-based backends."
  (when (org-export-derived-backend-p backend 'latex)
    (setq org-latex-hyperref-template
          (aj/latex--hyperref-template-for-color (aj/latex--get-file-link-color)))))

(add-hook 'org-export-before-processing-hook #'aj/latex--set-link-color-before-export)

;; Initialize with default
(setq org-latex-hyperref-template
      (aj/latex--hyperref-template-for-color aj/latex-link-color-default))

;; Auto-shrink oversized tables to page width on LaTeX export.
;; `tabular' environments that would overflow \linewidth are wrapped in
;; \adjustbox{max width=\linewidth}{...}; narrow tables are untouched.
;; `longtable' is skipped — it paginates natively.
(defun aj/latex-filter-table-autofit (text backend _info)
  "Wrap overflowing `tabular' blocks in `\\adjustbox{max width=\\linewidth}'."
  (when (and (org-export-derived-backend-p backend 'latex)
             (string-match-p "\\\\begin{tabular}" text)
             (not (string-match-p "\\\\begin{longtable}" text)))
    (replace-regexp-in-string
     "\\(\\\\begin{tabular}\\(?:.\\|\n\\)*?\\\\end{tabular}\\)"
     "\\\\adjustbox{max width=\\\\linewidth}{\\1}"
     text)))

(add-to-list 'org-export-filter-table-functions
             #'aj/latex-filter-table-autofit)

;; ── Twemoji LaTeX export filter ──────────────────────────────────────────
;; lualatex + luaotfload's node-mode fallback can't render Apple Color
;; Emoji (sbix format), so weather emoji in the daily calendar section come
;; out as monochrome silhouettes and moon-phase glyphs vanish entirely.
;; Map them to `\texttwemoji{CODEPOINT}' from the `twemojis' package, which
;; draws each glyph via TikZ — no font installation required, full colour.
;; The hex codepoint key is used (e.g. "1f327" for 🌧️) rather than the
;; name alias since it's unambiguous and matches the official Twemoji set.
;; The U+FE0F (VS-16) variation selector is stripped by listing both
;; with- and without-VS-16 forms; with-VS-16 entries come first so they
;; match before the bare codepoint would.
(defvar aj/latex-twemoji-map
  '(("☀️" . "2600")  ("☀" . "2600")
    ("☁️" . "2601")  ("☁" . "2601")
    ("🌦️" . "1f326") ("🌦" . "1f326")
    ("🌧️" . "1f327") ("🌧" . "1f327")
    ("⛈️" . "26c8")  ("⛈" . "26c8")
    ("❄️" . "2744")  ("❄" . "2744")
    ("🌫️" . "1f32b") ("🌫" . "1f32b")
    ("🌡️" . "1f321") ("🌡" . "1f321")
    ("🌑" . "1f311")
    ("🌒" . "1f312")
    ("🌓" . "1f313")
    ("🌔" . "1f314")
    ("🌕" . "1f315")
    ("🌖" . "1f316")
    ("🌗" . "1f317")
    ("🌘" . "1f318"))
  "Alist: emoji string → Twemoji hex codepoint, consumed by
`aj/latex-filter-twemoji' to produce \\texttwemoji{...} calls.")

(defun aj/latex-filter-twemoji (output backend _info)
  "Replace weather/moon emoji in OUTPUT with \\texttwemoji{...} calls."
  (when (org-export-derived-backend-p backend 'latex)
    (let ((s output))
      (dolist (entry aj/latex-twemoji-map)
        (setq s (replace-regexp-in-string
                 (regexp-quote (car entry))
                 (format "\\texttwemoji{%s}" (cdr entry))
                 s t t)))
      s)))

(add-to-list 'org-export-filter-final-output-functions
             #'aj/latex-filter-twemoji)

;; Open exported PDFs in sioyek
(with-eval-after-load 'org
  (add-to-list 'org-file-apps '("\\.pdf\\'" . "sioyek %s")))

;; LaTeX packages for inline previews only (not exports)
;; Exports use their own class templates; adding packages globally causes hyperref clashes
(setq org-format-latex-header
      (concat org-format-latex-header
              "\n\\usepackage{geometry}"
              "\n\\usepackage{tikz}"
              "\n\\usepackage{pgfplots}"
              "\n\\usepackage{xcolor}"
              "\n\\usetikzlibrary{shapes.geometric, positioning, arrows.meta, calc, decorations.pathreplacing}"
              "\n\\usepackage{tikz-uml}"
              "\n\\usetikzlibrary{arrows.meta,decorations.markings}"
              "\n\\pgfplotsset{compat=1.18}"))

;; AUCTeX settings
(setq org-latex-compiler "lualatex")
(setq TeX-engine "luatex")

(eval-after-load "tex"
  '(add-to-list 'TeX-command-list
                '("LuaLaTeXmk" "latexmk -pdf -pdflatex=\"lualatex %O %S\" %t"
                  TeX-run-TeX nil t)))
(setq TeX-command-default "LuaLaTeXmk")

;; ---------------------------------------------------------------------------
;; Custom Shortcode Highlighting (m3prob, m3subprob, m3subsol)
;; ---------------------------------------------------------------------------
;; Visual distinction for problem/subproblem/solution blocks

(defface aj/org-m3prob-face
  '((((background dark))
     :foreground "#efbf04" :weight bold :extend t)
    (((background light))
     :foreground "#8a6200" :weight bold :extend t))
  "Face for #+begin_m3prob / #+end_m3prob blocks (main problem)."
  :group 'org-faces)

(defface aj/org-m3subprob-face
  '((((background dark))
     :foreground "#8fa7c6" :weight bold :extend t)
    (((background light))
     :foreground "#3d5a80" :weight bold :extend t))
  "Face for #+begin_m3subprob / #+end_m3subprob blocks (sub-problem)."
  :group 'org-faces)

(defface aj/org-m3subsol-face
  '((((background dark))
     :foreground "#8bb664" :weight bold :extend t)
    (((background light))
     :foreground "#4a7c30" :weight bold :extend t))
  "Face for #+begin_m3subsol / #+end_m3subsol blocks (solution)."
  :group 'org-faces)

(defface aj/org-attr-shortcode-face
  '((((background dark))
     :foreground "#c9a066" :slant italic :extend t)
    (((background light))
     :foreground "#8b5a2b" :slant italic :extend t))
  "Face for #+attr_shortcode lines."
  :group 'org-faces)

(defface aj/org-transclude-face
  '((((background dark))
     :foreground "#9e95c7" :weight bold :extend t)
    (((background light))
     :foreground "#6a5a8e" :weight bold :extend t))
  "Face for #+transclude: lines (wisteria/purple)."
  :group 'org-faces)

(defun aj/org-add-shortcode-highlighting ()
  "Add font-lock rules for custom m3prob shortcode blocks."
  (font-lock-add-keywords
   nil
   '(;; Main problem blocks - gold
     ("^[ \t]*\\(#\\+begin_m3prob\\).*$" 1 'aj/org-m3prob-face t)
     ("^[ \t]*\\(#\\+end_m3prob\\).*$" 1 'aj/org-m3prob-face t)
     ;; Sub-problem blocks - blue
     ("^[ \t]*\\(#\\+begin_m3subprob\\).*$" 1 'aj/org-m3subprob-face t)
     ("^[ \t]*\\(#\\+end_m3subprob\\).*$" 1 'aj/org-m3subprob-face t)
     ;; Solution blocks - green
     ("^[ \t]*\\(#\\+begin_m3subsol\\).*$" 1 'aj/org-m3subsol-face t)
     ("^[ \t]*\\(#\\+end_m3subsol\\).*$" 1 'aj/org-m3subsol-face t)
     ;; attr_shortcode lines - amber italic
     ("^[ \t]*\\(#\\+attr_shortcode:.*\\)$" 1 'aj/org-attr-shortcode-face t)
     ;; transclude lines - wisteria/purple
     ("^[ \t]*\\(#\\+transclude:.*\\)$" 1 'aj/org-transclude-face t))
   t))

(add-hook 'org-mode-hook #'aj/org-add-shortcode-highlighting)

;; ---------------------------------------------------------------------------
;; Live LaTeX Preview (org-fragtog)
;; ---------------------------------------------------------------------------
;; Automatically preview LaTeX fragments when cursor leaves them,
;; and show source when cursor enters them.

(use-package org-fragtog
  :straight t
  :hook (org-mode . org-fragtog-mode)
  :config
  ;; Preview triggers when cursor leaves the fragment
  (setq org-fragtog-preview-delay 0.2))

;; ---------------------------------------------------------------------------
;; Extend org-fragtog to handle LaTeX environments inside export blocks
;; ---------------------------------------------------------------------------

(defvar-local aj/latex-fragtog--last-env nil
  "Tracks the last LaTeX environment point was in (buffer-local).
Value is (ENV-NAME BEG END) or nil.")

(defun aj/latex-fragtog--same-env-p (a b)
  "Return non-nil if A and B refer to the same environment.
Compares name and start position only (end shifts during edits)."
  (and a b
       (string= (nth 0 a) (nth 0 b))
       (= (nth 1 a) (nth 1 b))))

(defun aj/latex-fragtog--render-env (env buf)
  "Schedule a re-render of ENV in BUF after `org-fragtog-preview-delay'."
  (let ((beg-marker (copy-marker (nth 1 env)))
        (env-name (nth 0 env)))
    (run-with-timer
     org-fragtog-preview-delay nil
     (lambda ()
       (let ((beg (marker-position beg-marker)))
         (when (buffer-live-p buf)
           (with-current-buffer buf
             ;; Only render if the user's cursor isn't back inside this env
             (let ((user-env (aj/latex--find-environment-at-point)))
               (unless (and user-env
                            (aj/latex-fragtog--same-env-p
                             user-env (list env-name beg nil)))
                 (save-excursion
                   (goto-char (+ beg (length (format "\\begin{%s}" env-name))))
                   (aj/latex-preview-at-point)))))))
       (set-marker beg-marker nil)))))

(defun aj/latex-fragtog--clear-env (env)
  "Remove preview overlays for ENV."
  (dolist (ov (overlays-in (nth 1 env) (nth 2 env)))
    (when (overlay-get ov 'aj-latex-preview)
      (delete-overlay ov))))

(defun aj/latex-fragtog-hook ()
  "Toggle LaTeX environment preview when cursor enters/leaves.
Called from `post-command-hook'. Works with all environments in
`aj/latex-preview-environments'."
  (when (derived-mode-p 'org-mode)
    (let ((current-env (aj/latex--find-environment-at-point))
          (last-env aj/latex-fragtog--last-env))
      (unless (aj/latex-fragtog--same-env-p current-env last-env)
        ;; Left an environment: re-render it
        (when last-env
          (aj/latex-fragtog--render-env last-env (current-buffer)))
        ;; Entered an environment: clear its preview to show source
        (when current-env
          (aj/latex-fragtog--clear-env current-env)))
      (setq aj/latex-fragtog--last-env current-env))))

(add-hook 'org-mode-hook
          (lambda ()
            (add-hook 'post-command-hook #'aj/latex-fragtog-hook nil t)))

;; Make LaTeX previews larger and higher quality
(with-eval-after-load 'org
  (plist-put org-format-latex-options :scale 1.5)
  (plist-put org-format-latex-options :background "Transparent"))

;; ---------------------------------------------------------------------------
;; Pomodoro Timer
;; ---------------------------------------------------------------------------

(defvar aj/bell-sound (expand-file-name "sounds/bell.wav" user-emacs-directory)
  "Path to notification bell sound.")

(setq org-clock-sound aj/bell-sound)

(use-package org-pomodoro
  :straight (:host github :repo "abaj8494/org-pomodoro")
  :bind (("C-c p s" . org-pomodoro)              ; start
         ("C-c p p" . org-pomodoro-pause-or-resume) ; pause/resume
         ("C-c p k" . org-pomodoro-kill))        ; kill (logs to LOGBOOK)
  :config
  (setq org-pomodoro-start-sound aj/bell-sound
        org-pomodoro-finished-sound aj/bell-sound
        org-pomodoro-short-break-sound aj/bell-sound
        org-pomodoro-long-break-sound aj/bell-sound
        org-pomodoro-tts-backend 'edge-tts
        org-pomodoro-tts-enabled t
        org-pomodoro-skip-name-prompt t))

;; ---------------------------------------------------------------------------
;; Extract time from headings for scheduling
;; ---------------------------------------------------------------------------
;; Supports headings like "5:30PM-7:00PM Aldi Shop" or "17:30-19:00 Meeting"

(defun aj/normalize-time (time-str)
  "Convert time like '5:30PM' to 24-hour format '17:30'."
  (when time-str
    (let* ((time-str (string-trim time-str))
           (pm (string-match-p "[Pp][Mm]" time-str))
           (am (string-match-p "[Aa][Mm]" time-str))
           (clean (replace-regexp-in-string "[AaPpMm ]" "" time-str)))
      (when (string-match "\\([0-9]?[0-9]\\):\\([0-9][0-9]\\)" clean)
        (let ((hour (string-to-number (match-string 1 clean)))
              (min (match-string 2 clean)))
          (when pm (unless (= hour 12) (setq hour (+ hour 12))))
          (when am (when (= hour 12) (setq hour 0)))
          (format "%02d:%s" hour min))))))

(defun aj/heading-extract-time ()
  "Extract time or time range from current heading.
Returns a cons cell (START . END) for ranges, a string for single times, or nil."
  (when (org-at-heading-p)
    (let ((heading (substring-no-properties (org-get-heading t t t t))))
      (cond
       ;; Time range: 5:30PM-7:00PM or 17:30-19:00
       ((string-match "\\([0-9]?[0-9]:[0-9][0-9]\\s-*[AaPpMm]*\\)\\s-*-\\s-*\\([0-9]?[0-9]:[0-9][0-9]\\s-*[AaPpMm]*\\)" heading)
        ;; Capture both groups BEFORE calling normalize (which overwrites match data)
        (let ((start (match-string 1 heading))
              (end (match-string 2 heading)))
          (cons (aj/normalize-time start)
                (aj/normalize-time end))))
       ;; Single time: 5:30PM or 17:30
       ((string-match "\\([0-9]?[0-9]:[0-9][0-9]\\s-*[AaPpMm]*\\)" heading)
        (aj/normalize-time (match-string 1 heading)))))))

(defun aj/org-schedule-with-heading-time (orig-fun &optional arg time)
  "Advice for `org-schedule' to auto-populate time from heading.
Uses today's date with the time extracted from the heading."
  (if (or arg time)
      (funcall orig-fun arg time)
    (if-let ((heading-time (aj/heading-extract-time)))
        ;; We have a time in the heading - insert SCHEDULED directly
        (let* ((today (format-time-string "%Y-%m-%d %a"))
               (timestamp (if (consp heading-time)
                              (format "<%s %s-%s>" today (car heading-time) (cdr heading-time))
                            (format "<%s %s>" today heading-time))))
          (save-excursion
            ;; Stay on current line (the heading), go to end, insert SCHEDULED
            (end-of-line)
            ;; Check if next line is already SCHEDULED and remove it
            (save-excursion
              (forward-line 1)
              (when (looking-at "^SCHEDULED:")
                (delete-region (line-beginning-position) (1+ (line-end-position)))))
            ;; Insert new SCHEDULED line
            (insert "\nSCHEDULED: " timestamp))
          ;; Push to gcal if not in capture mode
          (unless (bound-and-true-p org-capture-mode)
            (aj/gcal-maybe-push-at-point)))
      ;; No time in heading - use normal org-schedule
      (funcall orig-fun nil nil))))

;; Remove old advice and re-add
(advice-remove 'org-schedule #'aj/org-schedule-with-heading-time)
(advice-add 'org-schedule :around #'aj/org-schedule-with-heading-time)

;; ---------------------------------------------------------------------------
;; Google Calendar Sync (org-gcal)
;; ---------------------------------------------------------------------------
;; Setup: Add to ~/.authinfo.gpg:
;;   machine calendar.google.com login YOUR_CLIENT_ID password YOUR_CLIENT_SECRET

(defvar aj/gcal-file (expand-file-name "gcal.org" org-directory)
  "File to store Google Calendar events.")
(defvar aj/gcal-id-personal "aayushbajaj7@gmail.com"
  "Personal Google Calendar ID.")
(defvar aj/gcal-id-J "437e8c9ab6b11de9d298569fcb54570982215d88b36512facbc8846b0c3317c1@group.calendar.google.com"
  "Shared 'J' calendar ID.")
(defvar aj/gcal-id-tasks "e3581335a338ae0cf988226d6bed357cfaff163c24f530be15d53e40ec544332@group.calendar.google.com"
  "Dedicated 'Tasks' calendar ID — receives the scheduled/moved chore sweep.
Distinct from the shared `aj/gcal-id-J' so personal task chores don't clutter
the shared calendar. Set this to the real calendar id (Google Calendar →
Settings for the Tasks calendar → Integrate calendar → Calendar ID).")
(defvar aj/gcal-credentials-loaded nil
  "Non-nil if org-gcal credentials have been loaded.")

(defun aj/gcal-load-credentials ()
  "Load org-gcal credentials from authinfo.gpg and initialize org-gcal."
  (unless aj/gcal-credentials-loaded
    (require 'auth-source)
    (let ((auth (car (auth-source-search :host "calendar.google.com" :max 1))))
      (when auth
        (setq org-gcal-client-id (plist-get auth :user)
              org-gcal-client-secret (let ((secret (plist-get auth :secret)))
                                       (if (functionp secret) (funcall secret) secret)))
        (when (and org-gcal-client-id org-gcal-client-secret)
          (require 'org-gcal)
          (org-gcal-reload-client-id-secret)
          (setq aj/gcal-credentials-loaded t)
          (message "org-gcal ready"))))))

(declare-function oauth2-auto--plstore-read "oauth2-auto")

(defun aj/gcal-prewarm-token-cache ()
  "Synchronously decrypt the org-gcal OAuth token store to warm gpg-agent.
Call this from an INTERACTIVE context (a command body or a find-file hook)
before launching any deferred org-gcal post — never from a deferred/timer.

Why: org-gcal reads the refresh token by decrypting `oauth2-auto.plist'
(plstore) on every token fetch (its plstore cache is disabled upstream). Emacs
runs under loopback pinentry (`epa-pinentry-mode' = loopback), so that decrypt's
passphrase prompt must land in the minibuffer — which is unusable from a
deferred/process-filter callback, where gpg then fails with \"Can't decrypt\".
One synchronous decrypt here unlocks the key; gpg-agent (max-cache-ttl 86400)
serves it to the later async decrypts with no prompt. No network, no re-auth —
just a plstore read."
  (when aj/gcal-credentials-loaded
    (require 'oauth2-auto)
    (condition-case err
        (dolist (id (list aj/gcal-id-tasks aj/gcal-id-J aj/gcal-id-personal))
          (ignore-errors (oauth2-auto--plstore-read id 'org-gcal)))
      (error (message "gcal token prewarm failed: %s"
                      (error-message-string err))))))

;; Wrapper commands - load credentials, then call org-gcal
(defun aj/gcal-sync ()
  "Sync with Google Calendar."
  (interactive)
  (aj/gcal-load-credentials)
  (when aj/gcal-credentials-loaded
    (org-gcal-sync)))

(defun aj/gcal-fetch ()
  "Fetch from Google Calendar."
  (interactive)
  (aj/gcal-load-credentials)
  (when aj/gcal-credentials-loaded
    (org-gcal-fetch)))

(defun aj/gcal-post-at-point ()
  "Push current entry to Google Calendar."
  (interactive)
  (aj/gcal-load-credentials)
  (when aj/gcal-credentials-loaded
    (org-gcal-post-at-point)))

(defun aj/gcal-delete-at-point ()
  "Delete current entry from Google Calendar."
  (interactive)
  (aj/gcal-load-credentials)
  (when aj/gcal-credentials-loaded
    (org-gcal-delete-at-point)))

(defun aj/gcal-toggle-auto-push ()
  "Toggle automatic pushing to Google Calendar."
  (interactive)
  (setq aj/gcal-auto-push (not aj/gcal-auto-push))
  (message "Google Calendar auto-push: %s" (if aj/gcal-auto-push "ON" "OFF")))

;; Keybindings (C-c G prefix to avoid conflict with magit's C-c g)
(global-set-key (kbd "C-c G s") #'aj/gcal-sync)
(global-set-key (kbd "C-c G f") #'aj/gcal-fetch)
(global-set-key (kbd "C-c G p") #'aj/gcal-post-at-point)
(global-set-key (kbd "C-c G d") #'aj/gcal-delete-at-point)
(global-set-key (kbd "C-c G t") #'aj/gcal-toggle-auto-push)

;; org-gcal package - defer loading until wrapper calls it
(use-package org-gcal
  :straight t
  :defer t
  :config
  (setq org-gcal-file-alist `((,aj/gcal-id-J . ,aj/gcal-file))
        org-gcal-recurring-events-mode 'nested
        org-gcal-remove-api-cancelled-events t
        org-gcal-auto-archive nil)
  (add-to-list 'org-agenda-files aj/gcal-file)

  ;; Strip org links and time info from title
  (defun aj/gcal-strip-links-from-headline (orig-fun)
    "Advice to strip org link markup and time info from headline."
    (let ((headline (funcall orig-fun)))
      (setq headline
            ;; Replace [[link][description]] with just description
            (replace-regexp-in-string
             "\\[\\[\\(?:[^]]+\\)\\]\\[\\([^]]+\\)\\]\\]"
             "\\1"
             ;; Also handle [[link]] without description - remove entirely
             (replace-regexp-in-string
              "\\[\\[\\([^]]+\\)\\]\\]"
              ""
              headline)))
      ;; Strip time patterns like "1:00PM-06:00PM " or "13:00-18:00 " from start
      (setq headline
            (replace-regexp-in-string
             "^[0-9]?[0-9]:[0-9][0-9]\\s-*[AaPpMm]*\\s-*-\\s-*[0-9]?[0-9]:[0-9][0-9]\\s-*[AaPpMm]*\\s-+"
             ""
             headline))
      ;; Also strip single time like "1:00PM " from start
      (setq headline
            (replace-regexp-in-string
             "^[0-9]?[0-9]:[0-9][0-9]\\s-*[AaPpMm]+\\s-+"
             ""
             headline))
      (string-trim headline)))
  (advice-add 'org-gcal--headline :around #'aj/gcal-strip-links-from-headline)

  ;; Include body content (outside :org-gcal: drawer) in description
  (defun aj/gcal-include-body-in-desc (orig-fun)
    "Advice to include entry body content in the event description."
    (let ((result (funcall orig-fun)))
      (save-excursion
        (org-back-to-heading t)
        (let* ((elem (org-element-at-point))
               (content-begin (org-element-property :contents-begin elem))
               (content-end (org-element-property :contents-end elem))
               body-text)
          (when (and content-begin content-end)
            (goto-char content-begin)
            ;; Skip SCHEDULED/DEADLINE/CLOSED lines
            (while (and (< (point) content-end)
                        (looking-at org-planning-line-re))
              (forward-line 1))
            ;; Skip property drawer
            (when (looking-at org-property-drawer-re)
              (goto-char (match-end 0))
              (forward-line 1))
            ;; Skip logbook drawer
            (when (looking-at "^[ \t]*:LOGBOOK:")
              (re-search-forward "^[ \t]*:END:" content-end t)
              (forward-line 1))
            ;; Skip org-gcal drawer
            (when (looking-at (format "^[ \t]*:%s:" org-gcal-drawer-name))
              (re-search-forward "^[ \t]*:END:" content-end t)
              (forward-line 1))
            ;; Get remaining body text (before any subheadings OR daily-file
            ;; structural markers — separator lines of dashes and `#+LATEX:'
            ;; directives are layout glue between sections, not user content,
            ;; and must not bleed into the gcal description / :org-gcal: drawer).
            (let* ((body-start (point))
                   (body-end (save-excursion
                               (let ((stop content-end))
                                 (dolist (re '("^\\*+ "
                                               "^-\\{3,\\}[ \t]*$"
                                               "^[ \t]*#\\+LATEX:"))
                                   (save-excursion
                                     (goto-char body-start)
                                     (when (re-search-forward re content-end t)
                                       (setq stop (min stop (match-beginning 0))))))
                                 stop))))
              (setq body-text (string-trim
                               (buffer-substring-no-properties body-start body-end)))))
          ;; Merge body into the description. The existing :desc comes from the
          ;; :org-gcal: drawer, which org-gcal REWRITES with the pushed
          ;; description after every successful post — so blindly appending
          ;; body to drawer-desc snowballs one duplicate copy per re-push
          ;; (the daily chore carry-forward re-pushes every day).
          (when (and body-text (not (string-empty-p body-text)))
            (let ((existing-desc (plist-get result :desc)))
              (plist-put result :desc
                         (cond
                          ;; org-managed entries: the body IS the description;
                          ;; the drawer is only an echo of the last push.
                          ;; Replacing (not appending) also self-heals drawers
                          ;; that already accumulated duplicates.
                          ((string= (or (org-entry-get nil "org-gcal-managed") "")
                                    "org")
                           body-text)
                          ;; gcal-managed: keep gcal's own desc, but don't
                          ;; re-append a body that's already at its tail.
                          ((and existing-desc
                                (string-suffix-p body-text
                                                 (string-trim existing-desc)))
                           existing-desc)
                          (existing-desc (concat existing-desc "\n\n" body-text))
                          (t body-text)))))))
      result))
  (advice-add 'org-gcal--get-time-and-desc :around #'aj/gcal-include-body-in-desc))

;; ---------------------------------------------------------------------------
;; Auto-push scheduled items to Google Calendar
;; ---------------------------------------------------------------------------

(defvar aj/gcal-auto-push t
  "When non-nil, automatically push scheduled/deadline items to Google Calendar.")

(defvar aj/--gcal-scheduled-during-capture nil
  "Non-nil if `org-schedule' was called during the current capture.")

(defun aj/gcal-maybe-push-at-point ()
  "Push current headline to Google Calendar if it has scheduling and isn't already synced."
  (when (and aj/gcal-auto-push
             (or (org-entry-get nil "SCHEDULED")
                 (org-entry-get nil "DEADLINE")))
    (unless (org-entry-get nil "calendar-id" t)
      (aj/gcal-load-credentials)
      (when aj/gcal-credentials-loaded
        (condition-case err
            (progn
              (org-gcal-post-at-point t)
              (message "Pushed to Google Calendar"))
          (error
           (message "Failed to push to gcal: %s" (error-message-string err))))))))

(defun aj/gcal-after-schedule (&rest _)
  "Hook to push to Google Calendar after scheduling."
  (if (bound-and-true-p org-capture-mode)
      ;; During capture, just record that org-schedule was used
      (setq aj/--gcal-scheduled-during-capture t)
    (aj/gcal-maybe-push-at-point)))

;; Push to gcal after capture finalization only if C-c C-s was used during capture
(defun aj/gcal-after-capture-finalize ()
  "Push newly captured item to Google Calendar if scheduled via `org-schedule'.
Credentials are loaded SYNCHRONOUSLY first (while the parent frame's
minibuffer is still alive) so the gpg-agent cache gets warmed by
pinentry/loopback. The actual push is deferred via a 0-delay timer so
it runs after the capture's dynamic context (windows, minibuffer state)
has fully unwound. Without the eager pre-load the deferred timer fires
in an async context with no live minibuffer, so loopback pinentry sends
an empty passphrase and the decrypt of ~/.authinfo.gpg or
oauth2-auto.plist aborts with \"Bad passphrase\" / \"Can't decrypt\"."
  (when aj/--gcal-scheduled-during-capture
    (setq aj/--gcal-scheduled-during-capture nil)
    (when (and aj/gcal-auto-push
               org-capture-last-stored-marker
               (marker-buffer org-capture-last-stored-marker))
      ;; Warm gpg-agent + load credentials NOW, while we still have a live
      ;; minibuffer. After this, subsequent decrypts (plstore/oauth2-auto)
      ;; piggyback on the agent's cache and don't reprompt.
      (condition-case err
          (aj/gcal-load-credentials)
        (error
         (message "gcal credential preload failed: %s" (error-message-string err))))
      (when aj/gcal-credentials-loaded
        (let ((marker org-capture-last-stored-marker))
          (run-at-time
           0 nil
           (lambda (m)
             (condition-case err
                 (when (marker-buffer m)
                   (with-current-buffer (marker-buffer m)
                     (save-excursion
                       (goto-char m)
                       (aj/gcal-maybe-push-at-point))))
               (error
                (message "org-gcal post failed: %s" (error-message-string err)))))
           marker))))))

(add-hook 'org-capture-after-finalize-hook #'aj/gcal-after-capture-finalize t)

;; Pre-warm gpg-agent + load gcal credentials when the capture buffer first
;; opens. At this point the user's frame minibuffer is fully free, so the
;; loopback pinentry prompt lands cleanly. By the time the capture is
;; finalized and we try to push, the agent's cache is warm and the post
;; runs without any prompt. Without this, the prompt fires from inside the
;; capture-finalize hook (or its run-at-time timer) where the minibuffer
;; state is unreliable, the callback returns empty, and gpg fails with
;; "No passphrase given" → "Can't decrypt".
(defun aj/gcal-prewarm-on-capture ()
  "Pre-load gcal credentials when entering a capture buffer.
No-op once credentials are loaded for the session."
  (when (and aj/gcal-auto-push (not aj/gcal-credentials-loaded))
    (condition-case err
        (aj/gcal-load-credentials)
      (error
       (message "gcal prewarm failed (will retry on next capture): %s"
                (error-message-string err))))))

(add-hook 'org-capture-mode-hook #'aj/gcal-prewarm-on-capture)

;; Add advice after org is loaded
(with-eval-after-load 'org
  (advice-add 'org-schedule :after #'aj/gcal-after-schedule)
  (advice-add 'org-deadline :after #'aj/gcal-after-schedule))

;; ---------------------------------------------------------------------------
;; Priority chores → red all-day events on the J calendar
;; ---------------------------------------------------------------------------
;; org-gcal has no native event-colour support: its POST payload
;; (org-gcal--post-event) hard-codes summary/location/source/description/
;; start/end and nothing else. We inject a Google `colorId' into that payload
;; via contained advice (rather than editing the straight checkout, which is
;; clobbered on update). colorId 11 = "Tomato" (red).

(defvar aj/gcal-chore-color "11"
  "Google Calendar colorId for auto-pushed chore events. 11 = Tomato (red).")

(defvar aj/gcal--inject-color nil
  "When bound to a colorId string, `org-gcal--post-event' tags its payload with it.
Dynamically `let'-bound around `org-gcal-post-at-point' by the chore pusher.")

(defvar aj/gcal--force-unconditional nil
  "When non-nil, strip the ETag from `org-gcal--post-event' so its PATCH carries
no `If-Match' header and overwrites the server event unconditionally.

Bound around chore pushes (`aj/gcal-push-chore-at-point',
`aj/gcal--prepare-and-post'). These events are org-managed — org is the sole
authority — so a stale ETag must not abort the push with HTTP 412. The ETag goes
stale routinely: the recurring carry-forward copies the `:PROPERTIES:' drawer
(incl. ETag) verbatim while the server event has already advanced, and an
overlapping open-hook sweep can PATCH the shared event id before this pass's
writeback lands. With `skip-import' set (the sweep passes it), org-gcal's own 412
branch is a silent no-op — it neither retries nor refreshes the ETag — so the
MOVE/update is dropped while `:gcal-synced-date:' is still stamped, hiding the
failure. Mirrors the etag=nil unconditional delete in `aj/gcal-hide-done-chore'.")

(defun aj/gcal--inject-color-advice (orig-fun &rest args)
  "Around advice on `org-gcal--post-event' for managed chore pushes.
When `aj/gcal--force-unconditional' is set, drop the ETag argument so the request
omits `If-Match' (no HTTP 412 on a stale/carried-forward ETag). When
`aj/gcal--inject-color' holds a colorId string, scope a temporary `json-encode'
redefinition to this call so only the event payload (the alist carrying a
\"summary\" key) is augmented with the colorId."
  (when (and aj/gcal--force-unconditional (> (length args) 9))
    ;; ETag is the 10th positional arg of `org-gcal--post-event'.
    (setq args (copy-sequence args))
    (setf (nth 9 args) nil))
  (if (not aj/gcal--inject-color)
      (apply orig-fun args)
    (let ((color aj/gcal--inject-color)
          (json-encode-orig (symbol-function 'json-encode)))
      (cl-letf (((symbol-function 'json-encode)
                 (lambda (obj)
                   (when (and (consp obj) (consp (car obj))
                              (assoc "summary" obj)
                              (not (assoc "colorId" obj)))
                     (setq obj (append obj (list (cons "colorId" color)))))
                   (funcall json-encode-orig obj))))
        (apply orig-fun args)))))

(with-eval-after-load 'org-gcal
  (advice-add 'org-gcal--post-event :around #'aj/gcal--inject-color-advice))

(defun aj/gcal--suppress-drawer-desc (args)
  "Filter-args advice on `org-gcal--update-entry' for Tasks-calendar chores.
Chore events live in dailies with their text as the entry BODY (below the
:org-gcal: drawer) — org is the sole authority, and
`aj/gcal-include-body-in-desc' feeds that body to every push. org-gcal's
default writeback would copy the posted description back into the drawer,
echoing the body immediately below it, so the daily shows the same text
twice. Strip :description from the event before the writeback runs so the
drawer stays empty. Scoped to `aj/gcal-id-tasks'; the J calendar's
gcal-managed entries keep their drawer description (their only copy)."
  (pcase-let ((`(,calendar-id ,event . ,rest) args))
    (if (and (equal calendar-id aj/gcal-id-tasks)
             (plist-get event :description))
        (cons calendar-id
              (cons (plist-put (copy-sequence event) :description nil) rest))
      args)))

(with-eval-after-load 'org-gcal
  (advice-add 'org-gcal--update-entry :filter-args #'aj/gcal--suppress-drawer-desc))

(defun aj/gcal--daily-title-date ()
  "Return the YYYY-MM-DD string from the current buffer's #+title:, or nil."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward
           "^#\\+title: \\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" nil t)
      (match-string 1))))

(defun aj/gcal-push-chore-at-point ()
  "Push the priority chore at point to the J calendar as a red all-day event.
Ensures `calendar-id' (J) and `org-gcal-managed' (org) properties, gives the
entry a date-only SCHEDULED stamp matching the daily's date (so it becomes an
all-day event) without tripping the auto-push-on-schedule advice, then posts
via org-gcal with red colour injected. Idempotent: org-gcal writes entry-id/
ETag back, so re-running updates -- and, if the date changed, moves -- the
same event rather than duplicating it."
  (interactive)
  (require 'deferred)
  (let ((date-str (aj/gcal--daily-title-date)))
    (unless date-str
      (user-error "Not in a daily note (no #+title date)"))
    (when (aj/gcal--sweep-active-p)
      ;; Same plstore-interleaving hazard as two concurrent sweeps — see the
      ;; concurrency-guard comment above `aj/gcal--sweep-active-since'.
      (user-error "gcal: a push chain is already in flight; retry shortly"))
    (aj/gcal-load-credentials)
    (unless aj/gcal-credentials-loaded
      (user-error "Google Calendar credentials unavailable"))
    (aj/gcal-prewarm-token-cache)
    (save-excursion
      (org-back-to-heading t)
      (unless (org-entry-get nil "calendar-id")
        (org-entry-put nil "calendar-id" aj/gcal-id-tasks))
      (unless (org-entry-get nil "org-gcal-managed")
        (org-entry-put nil "org-gcal-managed" "org"))
      ;; Date-only SCHEDULED = the daily's date. Suppress the gcal auto-push
      ;; advice on `org-schedule' so we don't double-post; we drive the
      ;; coloured push ourselves below.
      (unless (org-entry-get nil "SCHEDULED")
        (let ((aj/gcal-auto-push nil))
          (org-schedule nil date-str)))
      (let ((m (point-marker)))
        (setq aj/gcal--sweep-active-since (float-time))
        (deferred:nextc
          (deferred:try
            (let ((aj/gcal--inject-color aj/gcal-chore-color)
                  (aj/gcal--force-unconditional t))
              (org-gcal-post-at-point t))
            :catch (lambda (err)
                     (message "gcal chore push failed: %S" err)
                     'aj/gcal--post-failed))
          (lambda (res)
            (setq aj/gcal--sweep-active-since nil)
            (unless (eq res 'aj/gcal--post-failed)
              (aj/gcal--stamp-synced-date m date-str))
            nil)))
      (message "Pushing chore to Google Calendar (red, all-day %s)…" date-str))))

;; ---------------------------------------------------------------------------
;; Sweep: push ALL priority headings in a daily → red all-day events
;; ---------------------------------------------------------------------------
;; Matches any [#A-C] heading that is open (TODO/WAIT) OR has no TODO keyword
;; (so a plain `*** [#B] NSU Winter' lands on the calendar without becoming a
;; carried-forward chore). DONE/CANCEL items and the * Capture section (handled
;; by hand via C-c C-s) are excluded. org-gcal-post-at-point is async — its
;; entry-id/ETag writeback would race if several posts ran against the same
;; buffer at once — so the sweep chains the posts one at a time via deferred.

(defvar aj/gcal-auto-sweep-on-open t
  "When non-nil, opening today's (or a future) daily auto-sweeps its priority
items to Google Calendar. Past dailies are never auto-swept.")

;; Concurrency guard. One sweep chain is internally sequential, but TWO chains
;; (the daily-open hook can fire twice for the same daily — e.g. the midnight
;; daily-init capture and an interactive C-c d d landing together) interleave
;; freely: epg decrypts block in `accept-process-output', a reentrancy window
;; where the other chain's deferred callbacks run. Both chains touch
;; oauth2-auto.plist through plstore, and plstore shares ONE buffer per file
;; (`find-buffer-visiting') — so chain B's token-refresh plstore-save/close
;; lands mid-decrypt of chain A and the next decrypt hands gpg clobbered
;; ciphertext: `epg-error "Can't decrypt" "Exit"'. Two defenses:
;;   1. `aj/gcal-maybe-sweep-on-open' coalesces its idle timer per buffer, so
;;      a double hook fire schedules ONE sweep;
;;   2. `aj/gcal--sweep-active-since' is a mutex — a sweep (or single-chore
;;      push) that starts while another chain is in flight backs off. The
;;      timestamp auto-expires after 5 min so a chain that dies without
;;      reaching its cleanup can't wedge sweeps for the daemon's life.

(defvar aj/gcal--sweep-active-since nil
  "`float-time' when the in-flight gcal post chain started, nil when idle.")

(defvar aj/gcal--sweep-timer nil
  "Pending idle timer scheduled by `aj/gcal-maybe-sweep-on-open', if any.")

(defvar aj/gcal--sweep-timer-buffer nil
  "Buffer `aj/gcal--sweep-timer' was scheduled for.")

(defun aj/gcal--sweep-active-p ()
  "Non-nil if a gcal post chain is in flight (started within the last 5 min)."
  (and aj/gcal--sweep-active-since
       (< (- (float-time) aj/gcal--sweep-active-since) 300)))

(defun aj/gcal--stamp-synced-date (marker date-str)
  "Record DATE-STR as `gcal-synced-date' for the entry at MARKER, then save.
Called from a post deferred's success callback so the property reflects the
date the Google event actually sits on — the authority `aj/gcal--needs-push-p'
uses to decide whether a (carried-forward) item must be re-pushed/moved. Saving
also persists org-gcal's own entry-id/ETag writeback, which the post just made."
  (when (markerp marker)
    (let ((buf (marker-buffer marker)))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (save-excursion
            (goto-char marker)
            (org-back-to-heading t)
            (org-entry-put nil "gcal-synced-date" date-str))
          (when (buffer-modified-p) (save-buffer)))))))

(defun aj/gcal--needs-push-p (date-str)
  "Non-nil if the heading at point should be (re)pushed to gcal for DATE-STR.
Pushes when there is no `entry-id' yet; when there is no recorded
`gcal-synced-date' (so a pre-existing or carried-forward event re-syncs once);
or when `gcal-synced-date' differs from DATE-STR — the carried-forward case,
where the copied property still holds the OLD date and the Google event must
MOVE. An item whose `gcal-synced-date' already equals DATE-STR is skipped.

`gcal-synced-date' (not `SCHEDULED') is the authority here. SCHEDULED records
the date we WANT the event on, but only a completed push proves what date the
event actually sits on. Keying idempotency off SCHEDULED stranded carried-
forward events: the carry-forward (or the sweep's own re-anchor) rewrote
SCHEDULED to today before the move PATCH had landed, so every later sweep saw
SCHEDULED == today and skipped — leaving the event on the previous day."
  (let ((id (org-entry-get nil "entry-id"))
        (synced (org-entry-get nil "gcal-synced-date")))
    (cond
     ((null id) t)
     ((null synced) t)
     ((not (string= synced date-str)) t)
     (t nil))))

(defun aj/gcal--daily-priority-markers ()
  "Return BOL markers for pushable priority headings in the current buffer.
A heading qualifies if it carries a [#A-C] cookie and is either open
\(TODO/WAIT) or has no TODO keyword. The * Capture section is excluded;
DONE/CANCEL items are excluded by the match; headings inside org-transclusion
regions are excluded (they are live read-only mirrors of another file — their
identity writeback can't persist in this buffer, so every sweep would re-post
them as fresh duplicates; schedule those from their source file instead)."
  (let ((markers '())
        (cap-beg nil) (cap-end nil))
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward "^\\* Capture\\b" nil t)
        (setq cap-beg (line-beginning-position)
              cap-end (save-excursion
                        (if (re-search-forward "^\\* " nil t)
                            (line-beginning-position) (point-max)))))
      (goto-char (point-min))
      (while (re-search-forward
              "^\\*+ \\(?:\\(?:TODO\\|WAIT\\) \\)?\\[#[A-C]\\]" nil t)
        (let ((bol (line-beginning-position)))
          (unless (or (and cap-beg (>= bol cap-beg) (< bol cap-end))
                      (get-char-property bol 'org-transclusion-type))
            (push (copy-marker bol) markers)))))
    (nreverse markers)))

(defun aj/gcal--daily-has-pending-push-p ()
  "Cheaply (no network, no credential load) test if any priority heading in the
current daily still needs a gcal push."
  (let ((date-str (aj/gcal--daily-title-date)))
    (and date-str
         (cl-some (lambda (m)
                    (with-current-buffer (marker-buffer m)
                      (save-excursion
                        (goto-char m)
                        (aj/gcal--needs-push-p date-str))))
                  (aj/gcal--daily-priority-markers)))))

(defun aj/gcal--prepare-and-post (marker date-str)
  "At MARKER, ensure gcal identity + a date-only SCHEDULED for DATE-STR, then
post to the J calendar (red). Returns a deferred — a no-op deferred when the
entry is already correctly synced for DATE-STR."
  (with-current-buffer (marker-buffer marker)
    (save-excursion
      (goto-char marker)
      (org-back-to-heading t)
      (if (not (aj/gcal--needs-push-p date-str))
          (deferred:succeed nil)
        (unless (org-entry-get nil "calendar-id")
          (org-entry-put nil "calendar-id" aj/gcal-id-tasks))
        (unless (org-entry-get nil "org-gcal-managed")
          (org-entry-put nil "org-gcal-managed" "org"))
        ;; (Re)anchor a DATE-ONLY SCHEDULED to this daily's date so the event is
        ;; all-day and, if carried forward, MOVES rather than duplicates.
        ;; Re-anchor not only on a missing/wrong date but also when SCHEDULED
        ;; carries a time-of-day: a timed SCHEDULED (e.g. <2026-06-15 Mon 10:00>,
        ;; inherited by a carried-forward chore) otherwise slips through and
        ;; org-gcal pushes a *timed* event instead of the intended red all-day
        ;; chore — the malformed state behind the recurring gcal-sweep failures.
        ;; `org-schedule' with a date-only string reliably strips the time.
        (let ((sched (org-entry-get nil "SCHEDULED")))
          (when (or (null sched)
                    (not (string-match-p (regexp-quote date-str) sched))
                    (string-match-p "[0-9][0-9]:[0-9][0-9]" sched))
            (let ((aj/gcal-auto-push nil))
              (org-schedule nil date-str))))
        (deferred:nextc
          (let ((aj/gcal--inject-color aj/gcal-chore-color)
                (aj/gcal--force-unconditional t))
            (org-gcal-post-at-point t))
          (lambda (_)
            ;; Post landed — record the date the event now sits on so the next
            ;; sweep can tell "already synced for today" from "carried forward,
            ;; must move" without trusting SCHEDULED. See `aj/gcal--needs-push-p'.
            (aj/gcal--stamp-synced-date marker date-str)
            nil))))))

(defun aj/gcal--sweep-chain (markers date-str)
  "Post MARKERS to gcal sequentially (one finishes before the next starts)."
  (if (null markers)
      (progn
        (setq aj/gcal--sweep-active-since nil)
        (message "gcal sweep: done"))
    (let ((m (car markers)))
      (deferred:nextc
        (deferred:try
          (aj/gcal--prepare-and-post m date-str)
          :catch (lambda (err)
                   ;; Name the offending heading + the real error so a stuck
                   ;; item is diagnosable, instead of an anonymous "one item".
                   (message "gcal sweep: error on %S: %S"
                            (or (ignore-errors
                                  (with-current-buffer (marker-buffer m)
                                    (save-excursion
                                      (goto-char m)
                                      (org-get-heading t t t t))))
                                "?")
                            err)
                   nil))
        (lambda (_) (aj/gcal--sweep-chain (cdr markers) date-str))))))

(defun aj/gcal-sweep-daily-chores ()
  "Push every open priority heading in the current daily to the J calendar.
Includes keyword-less [#A-C] headings (e.g. NSU Winter); excludes the * Capture
section and DONE/CANCEL items. Each becomes a red all-day event on the daily's
date. Idempotent: items already synced for that date are skipped; carried items
whose date changed are moved. Posts run sequentially to avoid writeback races."
  (interactive)
  (require 'deferred)
  (let ((date-str (aj/gcal--daily-title-date)))
    (unless date-str
      (user-error "Not in a daily note (no #+title date)"))
    (if (aj/gcal--sweep-active-p)
        ;; Never run two chains at once — their plstore open/save/close
        ;; interleave via epg reentrancy and kill the token decrypt (see the
        ;; concurrency-guard comment above `aj/gcal--sweep-active-since').
        (message "gcal sweep: another push chain is in flight; skipped")
      (aj/gcal-load-credentials)
      (unless aj/gcal-credentials-loaded
        (user-error "Google Calendar credentials unavailable"))
      ;; Decrypt the token store now (interactive context) so the deferred posts
      ;; below don't hit a loopback-pinentry prompt they can't satisfy.
      (aj/gcal-prewarm-token-cache)
      (let ((markers (aj/gcal--daily-priority-markers)))
        (if (null markers)
            (message "gcal sweep: no priority items found")
          (setq aj/gcal--sweep-active-since (float-time))
          (message "gcal sweep: pushing up to %d priority item(s)…"
                   (length markers))
          (aj/gcal--sweep-chain markers date-str))))))

(defun aj/gcal-maybe-sweep-on-open ()
  "From a daily's open hook: schedule a gcal sweep of today/future priority items.
No-op when disabled, when not a dated daily, when the daily is in the past, or
when nothing is pending. The actual posting is deferred to an idle timer so it
never blocks file open; credentials load (and may prompt once) only when there
is something to push.

Credential load AND the token-store decrypt (`aj/gcal-prewarm-token-cache')
happen HERE, synchronously, while the open hook still runs in interactive
context — not inside the idle timer. Under loopback pinentry a passphrase prompt
fired from the timer's deferred posts can't reach the minibuffer and gpg fails
with \"Can't decrypt\"; warming the agent up front (cached 24h) avoids that."
  (when aj/gcal-auto-sweep-on-open
    (let ((date-str (aj/gcal--daily-title-date)))
      (when (and date-str
                 (not (string< date-str (format-time-string "%Y-%m-%d")))
                 (aj/gcal--daily-has-pending-push-p))
        (aj/gcal-load-credentials)
        (when aj/gcal-credentials-loaded
          (aj/gcal-prewarm-token-cache)
          (let ((buf (current-buffer)))
            ;; Coalesce: the open hook can fire twice for the same daily (the
            ;; midnight daily-init capture + an interactive visit). Two pending
            ;; timers would launch two concurrent sweep chains — the plstore
            ;; race behind the "Can't decrypt" failures. Replace, don't stack.
            (when (and (timerp aj/gcal--sweep-timer)
                       (eq aj/gcal--sweep-timer-buffer buf))
              (cancel-timer aj/gcal--sweep-timer))
            (setq aj/gcal--sweep-timer-buffer buf
                  aj/gcal--sweep-timer
                  (run-with-idle-timer
                   1 nil
                   (lambda ()
                     (setq aj/gcal--sweep-timer nil
                           aj/gcal--sweep-timer-buffer nil)
                     (when (buffer-live-p buf)
                       (with-current-buffer buf
                         (aj/gcal-sweep-daily-chores))))))))))))

;; ---------------------------------------------------------------------------
;; Hide completed chores: delete their calendar event on DONE/CANCEL
;; ---------------------------------------------------------------------------
;; When a priority chore on the J calendar is finished, its red all-day event
;; should disappear so the Home-Assistant kiosk calendar card only ever shows
;; outstanding chores. We delete the Google event but KEEP the org heading (now
;; DONE/CANCEL) — the daily's record stays, and the carry-forward state machine
;; in daily-recurring.el still sees the resolved keyword and won't resurrect it.
;;
;; We deliberately do NOT call `org-gcal-delete-at-point': it ends in
;; `org-gcal--handle-cancelled-entry' → `org-gcal--maybe-remove-entry', and with
;; `org-gcal-remove-api-cancelled-events' = t (set above) that DELETES the whole
;; org subtree. Its cleanup also runs in an async `:finally', so a `let'-binding
;; around the call can't neutralise it. Instead we drive `org-gcal--delete-event'
;; directly and strip the gcal drawer + identity properties ourselves.

(defvar org-state)
(defvar aj/daily-hook-suppress)
(declare-function aj/daily-date-file-p "daily-structure")
(declare-function org-gcal--get-id "org-gcal")
(declare-function org-gcal--delete-event "org-gcal")
(defvar org-gcal-drawer-name)
(defvar org-gcal-calendar-id-property)
(defvar org-gcal-entry-id-property)
(defvar org-gcal-etag-property)

(defun aj/gcal--strip-event-at-marker (marker)
  "Remove the :org-gcal: drawer and gcal identity properties at MARKER.
Mirrors the cleanup `org-gcal-delete-at-point' does on success, minus the
heading-deletion side effect. Leaves the heading text (and its DONE/CANCEL
keyword) intact."
  (when (buffer-live-p (marker-buffer marker))
    (org-with-point-at marker
      (org-back-to-heading t)
      (let ((bound (save-excursion (outline-next-heading) (point))))
        (save-excursion
          (when (re-search-forward
                 (format "^[ \t]*:%s:[^z-a]*?\n[ \t]*:END:[ \t]*\n?"
                         (regexp-quote org-gcal-drawer-name))
                 bound 'noerror)
            (replace-match "" 'fixedcase))))
      (org-entry-delete marker org-gcal-calendar-id-property)
      (org-entry-delete marker org-gcal-entry-id-property)
      (org-entry-delete marker org-gcal-etag-property)
      (org-entry-delete marker "gcal-synced-date")
      (org-entry-delete marker "org-gcal-managed"))))

(defun aj/gcal-delete-event-at-point ()
  "Delete the Google event for the entry at point WITHOUT removing the heading.
Returns a deferred. A no-op deferred when the entry has no event-id/calendar-id."
  (require 'org-gcal)
  (require 'deferred)
  (save-excursion
    (org-back-to-heading t)
    (let* ((marker (point-marker))
           (event-id (org-gcal--get-id (point)))
           (etag (org-entry-get (point) org-gcal-etag-property))
           (calendar-id (org-entry-get (point) org-gcal-calendar-id-property)))
      (if (not (and event-id calendar-id))
          (deferred:succeed nil)
        (deferred:nextc
          ;; org-gcal--delete-event destroys the marker it's given, so hand it a copy.
          (org-gcal--delete-event calendar-id event-id etag (copy-marker marker))
          (lambda (_)
            (aj/gcal--strip-event-at-marker marker)
            nil))))))

(defun aj/gcal-hide-done-chore (&rest _)
  "On DONE/CANCEL, delete the chore's calendar event so it leaves the calendar.
Hooked on `org-after-todo-state-change-hook'. No-op during suppressed state
changes (`aj/daily-hook-suppress' — e.g. the carry-forward source-CANCEL in
daily-recurring.el), so a carried-forward item MOVES forward rather than being
deleted off the calendar. Only fires for entries on the dedicated Tasks
calendar that actually carry an entry-id — events on the shared J calendar
are left in place when completed. Keeps the org heading; just removes the
event + gcal identity."
  (when (and (not (bound-and-true-p aj/daily-hook-suppress))
             (boundp 'org-state)
             (member org-state '("DONE" "CANCEL"))
             (buffer-file-name)
             (fboundp 'aj/daily-date-file-p)
             (aj/daily-date-file-p))
    (let ((cal (org-entry-get nil "calendar-id"))
          (id  (org-entry-get nil "entry-id")))
      (when (and id cal (equal cal aj/gcal-id-tasks))
        (condition-case err
            (progn
              (aj/gcal-load-credentials)
              (when aj/gcal-credentials-loaded
                (require 'deferred)
                ;; This hook fires synchronously from the user's DONE/CANCEL
                ;; command, but the delete's token decrypt happens in the
                ;; deferred below — warm the agent here so loopback pinentry
                ;; isn't summoned from that callback.
                (aj/gcal-prewarm-token-cache)
                (let ((buf (current-buffer)))
                  (deferred:$
                    (deferred:try
                      (aj/gcal-delete-event-at-point)
                      :catch (lambda (e)
                               (message "gcal hide-done: delete failed: %S" e) nil))
                    (deferred:nextc it
                      (lambda (_)
                        (when (buffer-live-p buf)
                          (with-current-buffer buf
                            (when (buffer-modified-p) (save-buffer))))
                        (message "gcal: completed chore removed from calendar")))))))
          (error
           (message "gcal hide-done error: %s" (error-message-string err))))))))

;; Pin this BEFORE the other todo-state hooks. `my/org-roam-copy-todo-to-today'
;; (daily-config.el) fires on DONE under * Recurring and leaks point onto the
;; * Tasks heading via its nested `org-roam-dailies--capture' (no save-excursion
;; around it). At the default depth `aj/gcal-hide-done-chore' ran *after* that
;; leak and read `entry-id' at the wrong heading (nil) -> the inner `when'
;; failed, so the calendar event was silently never deleted and completed
;; chores lingered on the J calendar. The negative depth runs the delete while
;; point is still on the chore (and before any earlier hook can error-abort the
;; chain via `run-hooks').
(add-hook 'org-after-todo-state-change-hook #'aj/gcal-hide-done-chore -50)

;; ---------------------------------------------------------------------------
;; Per-section local tables of contents (opt-in, course-agnostic)
;; ---------------------------------------------------------------------------
;; A level-1 section whose body starts on a fresh page shows just a heading and
;; whitespace — not helpful.  When enabled, LaTeX export drops a small
;; `\localtableofcontents' (via the etoc package) directly under each level-1
;; section that has subsections, then a page break — so the section's opening
;; page previews what follows.  Ideal for aggregated course docs (_index.org),
;; where each `* Week N' / `* Assignment N' gets its own mini contents.
;;
;; General by design: the filter is registered once but gated on
;; `aj/latex-local-toc-enabled', which a course opts into from its
;; `.export/styling.el' by calling `aj/latex-enable-local-toc' (see the styled
;; export advice below — it shadows the flag, so the effect is per-export).
(defvar aj/latex-local-toc-enabled nil
  "When non-nil, LaTeX export inserts a small local TOC (+ page break) under
every level-1 section that has subsections.  Opt in per course via
`aj/latex-enable-local-toc', typically from a `.export/styling.el'.")

(defconst aj/latex-local-toc-preamble
  "\\usepackage{etoc}
\\newcommand{\\ajlocaltoc}{\\etocsetnexttocdepth{subsubsection}{\\small\\localtableofcontents}}"
  "Raw preamble providing the `\\ajlocaltoc' per-section local-TOC macro.
Appended to `org-latex-packages-alist' as a verbatim string (needs etoc).")

(defun aj/latex-local-toc-filter (contents backend _info)
  "Insert `\\ajlocaltoc' (+ a page break) after each level-1 section.
Only fires for sections that actually have subsections, and is a no-op unless
`aj/latex-local-toc-enabled' is set.  If the section body already opens with a
`\\newpage' (e.g. a weekly file's own `#+latex: \\newpage'), no extra page
break is added, so no blank page results."
  (if (and aj/latex-local-toc-enabled
           (org-export-derived-backend-p backend 'latex)
           (stringp contents)
           (string-match
            "\\`\\([ \t\n]*\\\\section\\*?{.*}[ \t]*\n\\(?:\\\\label{[^}]*}[ \t]*\n\\)?\\)"
            contents)
           (string-match-p "\\\\subsection" contents))
      (let* ((head (match-string 1 contents))
             (rest (substring contents (match-end 1)))
             (page (if (string-match-p "\\`[ \t\n]*\\\\newpage" rest) "" "\\newpage\n")))
        (concat head "\\ajlocaltoc\n" page rest))
    contents))

(add-to-list 'org-export-filter-headline-functions #'aj/latex-local-toc-filter)

(defun aj/latex-enable-local-toc ()
  "Turn on per-section local TOCs for the current export and load etoc.
Call from a course's `.export/styling.el'."
  (setq aj/latex-local-toc-enabled t)
  (add-to-list 'org-latex-packages-alist aj/latex-local-toc-preamble t))

;; ---------------------------------------------------------------------------
;; Course notes: styled interactive PDF export
;; ---------------------------------------------------------------------------
;; Course note trees under ~/lattice/notes/uni/<course>/ get their look (minted
;; syntax highlighting, per-course accent, cached #+RESULTS with no re-run or
;; confirm prompts, local TOCs) from a per-course `.export/styling.el', which
;; the batch script make-pdfs.sh layers on top of init.el.  This advice reuses
;; that SAME styling.el for interactive `C-c C-e l o' (org-latex-export-to-pdf):
;; for any file under a course tree it finds the nearest `.export/styling.el'
;; and applies it; everything else (daily notes, etc.) exports normally.
;;
;; styling.el is loaded *inside* a `let' that shadows every variable it touches
;; (and the before-processing hook it removes), so all of its effects are
;; dynamically scoped to this one export and auto-restored afterwards.  Keeping
;; styling.el as the single source of truth means the batch script and the
;; interactive key stay in sync — and adding a new course is just dropping in a
;; `.export/styling.el' (no Emacs-config change needed).
(defvar aj/course-notes-root
  (expand-file-name "~/lattice/notes/uni/")
  "Root under which course note trees live.  Each course dir may carry a
`.export/styling.el' used for styled PDF export.")

(defun aj/course-styling-file-for (file)
  "Return the nearest `.export/styling.el' at or above FILE, or nil.
Search is confined to `aj/course-notes-root'."
  (when (and file (string-prefix-p aj/course-notes-root (expand-file-name file)))
    (let ((dir (file-name-directory (expand-file-name file)))
          found)
      (while (and dir (not found) (string-prefix-p aj/course-notes-root dir))
        (let ((cand (expand-file-name ".export/styling.el" dir)))
          (when (file-exists-p cand) (setq found cand)))
        (let ((parent (file-name-directory (directory-file-name dir))))
          (setq dir (unless (equal parent dir) parent))))
      found)))

(defun aj/course-export-with-styling (orig-fn &rest args)
  "Around advice: apply the nearest course `.export/styling.el' during export."
  (let ((styling (and buffer-file-name
                      (aj/course-styling-file-for buffer-file-name))))
    (if styling
        (let ((org-export-babel-evaluate org-export-babel-evaluate)
              (org-confirm-babel-evaluate org-confirm-babel-evaluate)
              (org-export-with-broken-links org-export-with-broken-links)
              (org-babel-default-header-args:jupyter-python
               org-babel-default-header-args:jupyter-python)
              (org-latex-src-block-backend org-latex-src-block-backend)
              (org-latex-minted-langs org-latex-minted-langs)
              (org-latex-minted-options org-latex-minted-options)
              (org-latex-packages-alist org-latex-packages-alist)
              (org-latex-hyperref-template org-latex-hyperref-template)
              (org-export-before-processing-hook org-export-before-processing-hook)
              (aj/latex-local-toc-enabled aj/latex-local-toc-enabled))
          (load styling nil t)
          (apply orig-fn args))
      (apply orig-fn args))))

(advice-add 'org-latex-export-to-pdf :around #'aj/course-export-with-styling)

;; ---------------------------------------------------------------------------
;; Answer blocks:  #+begin_answer … #+end_answer  (no-op LaTeX environment)
;; ---------------------------------------------------------------------------
;; Page separation is done with explicit `#+latex: \newpage' keywords, NOT here:
;;   - problems.org puts a \newpage before every reveal heading (Key move and
;;     Answer), so a problem's question statement sits ALONE on its page and the
;;     key move / why-missed / answer land on subsequent pages;
;;   - the daily's ** Problems block puts a \newpage before each transcluded
;;     question, isolating problems from one another.
;; The `answer' environment stays defined (so `#+begin_answer' blocks export)
;; but does nothing on its own.
(with-eval-after-load 'ox-latex
  (add-to-list 'org-latex-packages-alist
               "\\newenvironment{answer}{}{}"
               t))

(provide 'org-config)
;;; org-config.el ends here
