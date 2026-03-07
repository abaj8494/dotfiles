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

(use-package go-mode)

(use-package ob-go
  :straight (:host github :repo "pope/ob-go"))
(org-babel-do-load-languages
 'org-babel-load-languages
 '((shell   . t)
   (python  . t)
   (markdown . t)
   (jupyter . t)
   (latex   . t)
   (C       . t)
   (java    . t)
   (go      . t)
   (gnuplot . t)))

;; Python settings
(setq custom-tab-width 4)
(setq-default python-indent-offset custom-tab-width)
(setq org-babel-python-command "/opt/anaconda3/bin/python")
(setq-default indent-tabs-mode nil)

(add-hook 'python-mode-hook
          (lambda () (setq indent-tabs-mode nil)))

(add-hook 'org-src-mode-hook
          (lambda () (setq indent-tabs-mode nil)))

;; Jupyter-python mode mapping
(add-to-list 'org-src-lang-modes '("jupyter-python" . python))
(add-to-list 'org-src-lang-modes '("chess" . latex))

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
  (setq org-directory "/Users/aayushbajaj/Documents/new-site/content-org/daily/")
  (setq org-agenda-files (list (expand-file-name "tasks.org" org-directory)))
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
;; Org Templates
;; ---------------------------------------------------------------------------

(with-eval-after-load 'org
  (require 'org-tempo)
  (setq org-babel-default-header-args:jupyter-python
        '((:session . "leet")))
  (add-to-list 'org-structure-template-alist '("sj" . "src jupyter-python"))
  (add-to-list 'org-structure-template-alist '("sp" . "src python")))

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
  \"Apple Color Emoji:mode=harf;\",
})}
\\setmainfont{Latin Modern Roman}[Ligatures=TeX, RawFeature={fallback=mainfallback}]
\\setmonofont{Menlo}[Scale=0.9]
\\usepackage{graphicx}
\\usepackage{longtable}
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
               ("convert -density %D -trim -antialias %f -quality 100 %O")))

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

(defvar aj/latex-preview-scale 1.0
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
         (tex-file (make-temp-file "latex-" nil ".tex"))
         (pdf-file (concat (file-name-sans-extension tex-file) ".pdf"))
         (log-file (concat (file-name-sans-extension tex-file) ".log"))
         (img-file (concat (file-name-sans-extension tex-file)
                           (if (eq org-preview-latex-default-process 'ajlua) ".svg" ".png")))
         (preamble (if use-buf-preamble
                       (aj/latex--buffer-preview-preamble extra-preamble)
                     (concat
                      docclass "\n"
                      (mapconcat #'identity packages "\n") "\n"
                      "\\usepackage{xcolor}\n"
                      (or extra-preamble "")
                      "\\begin{document}\n")))
         (postamble "\n\\end{document}\n")
         (full-content (concat preamble content postamble)))
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
                          (format "convert -density 300 -trim -antialias %s -quality 100 %s"
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
     "\\begin{document}\n")))

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
                          (format "convert -density 300 -trim -antialias %s -quality 100 %s"
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
                          (format "convert -density 300 -trim -antialias %s -quality 100 %s"
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
                          (format "convert -density 300 -trim -antialias %s -quality 100 %s"
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
  (expand-file-name "~/Documents/new-site/static/code/tikzjax/cli.js")
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

;; Use latexmk for automatic reference/bibliography resolution
(setq org-latex-pdf-process
      '("latexmk -f -lualatex -shell-escape -interaction=nonstopmode %f"))

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

;; Open exported PDFs in Chrome (new tab in existing window)
(defun aj/open-pdf-in-chrome (file)
  "Open FILE in Google Chrome."
  (start-process "chrome-pdf" nil "open" "-a" "Google Chrome" file))

(defun aj/org-latex-export-and-open-chrome ()
  "Export Org to PDF and open in Chrome."
  (interactive)
  (let ((pdf-file (org-latex-export-to-pdf)))
    (when pdf-file
      (aj/open-pdf-in-chrome pdf-file))))

;; Override PDF opening for org-export to use Chrome
(with-eval-after-load 'org
  (add-to-list 'org-file-apps '("\\.pdf\\'" . "open -a 'Google Chrome' %s")))

;; LaTeX packages for inline previews only (not exports)
;; Exports use their own class templates; adding packages globally causes hyperref clashes
(setq org-format-latex-header
      (concat org-format-latex-header
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

(defun aj/latex-fragtog-hook ()
  "Toggle LaTeX environment preview when cursor enters/leaves.
Called from `post-command-hook'. Works with all environments in
`aj/latex-preview-environments'."
  (when (derived-mode-p 'org-mode)
    (let ((current-env (aj/latex--find-environment-at-point)))
      (cond
       ;; Entered an environment: clear its preview to show source
       ((and current-env (not aj/latex-fragtog--last-env))
        (let ((beg (nth 1 current-env))
              (end (nth 2 current-env)))
          (dolist (ov (overlays-in beg end))
            (when (overlay-get ov 'aj-latex-preview)
              (delete-overlay ov)))))
       ;; Left an environment: render preview after delay
       ((and aj/latex-fragtog--last-env (not current-env))
        (let ((env aj/latex-fragtog--last-env)
              (buf (current-buffer)))
          (run-with-timer
           org-fragtog-preview-delay nil
           (lambda ()
             (when (buffer-live-p buf)
               (with-current-buffer buf
                 (save-excursion
                   (goto-char (nth 1 env))
                   ;; Only render if we're still outside the environment
                   (unless (aj/latex--find-environment-at-point)
                     (aj/latex-preview-at-point))))))))))
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
            ;; Get remaining body text (before any subheadings)
            (let ((body-start (point))
                  (body-end (save-excursion
                              (if (re-search-forward "^\\*+ " content-end t)
                                  (match-beginning 0)
                                content-end))))
              (setq body-text (string-trim
                               (buffer-substring-no-properties body-start body-end)))))
          ;; Append body to existing description
          (when (and body-text (not (string-empty-p body-text)))
            (let ((existing-desc (plist-get result :desc)))
              (plist-put result :desc
                         (if existing-desc
                             (concat existing-desc "\n\n" body-text)
                           body-text))))))
      result))
  (advice-add 'org-gcal--get-time-and-desc :around #'aj/gcal-include-body-in-desc))

;; ---------------------------------------------------------------------------
;; Auto-push scheduled items to Google Calendar
;; ---------------------------------------------------------------------------

(defvar aj/gcal-auto-push t
  "When non-nil, automatically push scheduled/deadline items to Google Calendar.")

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
  (unless (bound-and-true-p org-capture-mode)
    (aj/gcal-maybe-push-at-point)))

;; Push to gcal after capture finalization (appended so jump-prompt runs first)
(defun aj/gcal-after-capture-finalize ()
  "Push newly captured item to Google Calendar if it has scheduling."
  (condition-case err
      (when-let ((marker org-capture-last-stored-marker))
        (when (marker-buffer marker)
          (with-current-buffer (marker-buffer marker)
            (save-excursion
              (goto-char marker)
              (aj/gcal-maybe-push-at-point)))))
    (error
     (message "org-gcal post failed: %s" (error-message-string err)))))

(add-hook 'org-capture-after-finalize-hook #'aj/gcal-after-capture-finalize t)

;; Add advice after org is loaded
(with-eval-after-load 'org
  (advice-add 'org-schedule :after #'aj/gcal-after-schedule)
  (advice-add 'org-deadline :after #'aj/gcal-after-schedule))

(provide 'org-config)
;;; org-config.el ends here
