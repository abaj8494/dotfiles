;;; org-config.el --- Org-mode configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; Comprehensive Org-mode setup including Babel, LaTeX preview, and templates.

;;; Code:

(require 'org)
(require 'ox-latex)
(require 'ob-markdown)

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

(org-babel-do-load-languages
 'org-babel-load-languages
 '((shell   . t)
   (python  . t)
   (markdown . t)
   (jupyter . t)
   (latex   . t)
   (C       . t)
   (java    . t)))

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
  (setq org-agenda-files (list org-directory))
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

;; Helper functions for recurring template captures
(defvar aj/templates-base-dir "~/Documents/new-site/content-org/templates/"
  "Base directory for recurring task templates.")

(defun aj/capture-daily-file ()
  "Return the daily template file path."
  (expand-file-name "daily.org" aj/templates-base-dir))

(defun aj/capture-alternating-file ()
  "Prompt for alternating phase and return the template file path.
Shows current phase for reference."
  (let* ((current-phase (aj/alternating-phase))
         (phases '("a" "b"))
         (phase (completing-read
                 (format "Phase (today is '%s'): " current-phase)
                 phases nil t)))
    (expand-file-name (concat "alternating/" phase ".org") aj/templates-base-dir)))

(defun aj/capture-weekly-file ()
  "Prompt for day of week and return the template file path.
Shows current day for reference."
  (let* ((current-day (downcase (format-time-string "%A")))
         (days '("monday" "tuesday" "wednesday" "thursday" "friday" "saturday" "sunday"))
         (day (completing-read
               (format "Day of week (today is %s): " current-day)
               days nil t)))
    (expand-file-name (concat "weekly/" day ".org") aj/templates-base-dir)))

(defun aj/capture-biweekly-file ()
  "Prompt for week parity and day, return the template file path.
Shows current ISO week and parity for reference."
  (let* ((current-week (aj/iso-week-number))
         (current-parity (aj/iso-week-parity))
         (current-day (downcase (format-time-string "%A")))
         (parities '("odd" "even"))
         (days '("monday" "tuesday" "wednesday" "thursday" "friday" "saturday" "sunday"))
         (parity (completing-read
                  (format "Week parity (week %d is %s): " current-week current-parity)
                  parities nil t))
         (day (completing-read
               (format "Day of week (today is %s): " current-day)
               days nil t)))
    (expand-file-name (concat "biweekly/" parity "/" day ".org") aj/templates-base-dir)))

(defun aj/capture-monthly-file ()
  "Prompt for day of month and return the template file path.
Shows current day for reference."
  (let* ((current-dom (format-time-string "%d"))
         (days (mapcar (lambda (n) (format "%02d" n)) (number-sequence 1 31)))
         (day (completing-read
               (format "Day of month (today is %s): " current-dom)
               days nil t)))
    (expand-file-name (concat "monthly/" day ".org") aj/templates-base-dir)))

(defun aj/capture-yearly-file ()
  "Prompt for MM-DD and return the template file path.
Shows current date for reference."
  (let* ((current-date (format-time-string "%m-%d"))
         (date (read-string (format "Date MM-DD (today is %s): " current-date))))
    (expand-file-name (concat "yearly/" date ".org") aj/templates-base-dir)))

(setq org-capture-templates
      '(("r" "recurring templates")
        ("rd" "daily (every day)" plain
         (file aj/capture-daily-file)
         "* TODO %?"
         :empty-lines 0)
        ("ra" "alternating (every other day)" plain
         (file aj/capture-alternating-file)
         "* TODO %?"
         :empty-lines 0)
        ("rw" "weekly" plain
         (file aj/capture-weekly-file)
         "* TODO %?"
         :empty-lines 0)
        ("rb" "biweekly (fortnightly)" plain
         (file aj/capture-biweekly-file)
         "* TODO %?"
         :empty-lines 0)
        ("rm" "monthly" plain
         (file aj/capture-monthly-file)
         "* TODO %?"
         :empty-lines 0)
        ("ry" "yearly" plain
         (file aj/capture-yearly-file)
         "* TODO %?"
         :empty-lines 0)))

;; Bind C-c c directly to org-capture
(global-set-key (kbd "C-c c") #'org-capture)

;; Org agenda
(global-set-key (kbd "C-c a") #'org-agenda)

;; ---------------------------------------------------------------------------
;; LaTeX Document Classes
;; ---------------------------------------------------------------------------

(with-eval-after-load 'ox-latex
  ;; Override default article to support 5 heading levels (paragraph, subparagraph)
  (add-to-list 'org-latex-classes
               '("article"
                 "\\documentclass[11pt]{article}"
                 ("\\section{%s}" . "\\section*{%s}")
                 ("\\subsection{%s}" . "\\subsection*{%s}")
                 ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
                 ("\\paragraph{%s}" . "\\paragraph*{%s}")
                 ("\\subparagraph{%s}" . "\\subparagraph*{%s}")))
  (add-to-list 'org-latex-classes
               '("standalone"
                 "\\documentclass{standalone}"
                 ("\\section{%s}" . "\\section*{%s}")
                 ("\\subsection{%s}" . "\\subsection*{%s}")
                 ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
                 ("\\paragraph{%s}" . "\\paragraph*{%s}")
                 ("\\subparagraph{%s}" . "\\subparagraph*{%s}")))
  (add-to-list 'org-latex-classes
               '("scrartcl"
                 "\\documentclass{scrartcl}"
                 ("\\section{%s}" . "\\section*{%s}")
                 ("\\subsection{%s}" . "\\subsection*{%s}")
                 ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
                 ("\\paragraph{%s}" . "\\paragraph*{%s}")
                 ("\\subparagraph{%s}" . "\\subparagraph*{%s}"))))

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
               :description "pdf > png (3x scale)"
               :message "Requires lualatex and imagemagick."
               :use-xcolor t
               :image-input-type "pdf"
               :image-output-type "png"
               :image-size-adjust (3.0 . 3.0)
               :latex-compiler
               ("lualatex -interaction nonstopmode -output-directory %o %f")
               :image-converter
               ("convert -density %D -trim -antialias %f -quality 100 %O")))

;; Default to SVG

(setq org-preview-latex-default-process 'ajlua)
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
  "Use PNG (raster) for LaTeX previews. Scalable, 3x size."
  (interactive)
  (setq org-preview-latex-default-process 'luamagick)
  (message "LaTeX preview: PNG (raster, 3x scale)"))

(defun aj/latex-preview-toggle ()
  "Toggle between SVG and PNG LaTeX preview backends."
  (interactive)
  (if (eq org-preview-latex-default-process 'ajlua)
      (aj/latex-preview-use-png)
    (aj/latex-preview-use-svg)))

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

(defvar aj/latex-preview--queue nil
  "Queue of fragments waiting to be processed.")

(defvar aj/latex-preview--active 0
  "Number of currently active preview processes.")

(defvar aj/latex-preview--total 0
  "Total fragments to process in current batch.")

(defvar aj/latex-preview--completed 0
  "Fragments completed in current batch.")

(defun aj/latex-preview--update-status ()
  "Update modeline with preview progress."
  (message "LaTeX preview: %d/%d (active: %d)"
           aj/latex-preview--completed
           aj/latex-preview--total
           aj/latex-preview--active))

(defun aj/latex-preview--process-next ()
  "Process next fragment from queue if slots available."
  (while (and aj/latex-preview--queue
              (< aj/latex-preview--active aj/latex-preview-parallel-jobs))
    (let* ((fragment (pop aj/latex-preview--queue))
           (beg (car fragment))
           (end (cdr fragment)))
      (when (and beg end)
        (cl-incf aj/latex-preview--active)
        ;; Use org's preview on just this fragment, with a sentinel
        (let ((buf (current-buffer)))
          (run-with-timer
           0.01 nil
           (lambda ()
             (when (buffer-live-p buf)
               (with-current-buffer buf
                 (save-excursion
                   (goto-char beg)
                   (ignore-errors
                     (org-latex-preview nil)))
                 (cl-decf aj/latex-preview--active)
                 (cl-incf aj/latex-preview--completed)
                 (aj/latex-preview--update-status)
                 (aj/latex-preview--process-next))))))))))

(defun aj/latex-preview-async ()
  "Generate LaTeX previews for buffer ASYNCHRONOUSLY in parallel.
Processes multiple fragments concurrently for faster completion."
  (interactive)
  (require 'org)
  (let ((fragments nil))
    ;; Collect all LaTeX fragments
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward org-latex-regexp nil t)
        (push (cons (match-beginning 0) (match-end 0)) fragments))
      ;; Also find \[ \] and \begin{} \end{} environments (including tikzpicture)
      (goto-char (point-min))
      (while (re-search-forward "\\\\\\[\\|\\\\begin{\\(equation\\|align\\|gather\\|multline\\|tikzpicture\\)\\*?}" nil t)
        (let ((beg (match-beginning 0)))
          (when (ignore-errors
                  (goto-char beg)
                  (forward-sexp)
                  t)
            (push (cons beg (point)) fragments)))))
    ;; Remove duplicates and sort
    (setq fragments (cl-remove-duplicates fragments :test #'equal))
    (setq fragments (sort fragments (lambda (a b) (< (car a) (car b)))))

    ;; Initialize queue
    (setq aj/latex-preview--queue fragments
          aj/latex-preview--active 0
          aj/latex-preview--total (length fragments)
          aj/latex-preview--completed 0)

    (if (null fragments)
        (message "No LaTeX fragments found")
      (message "Starting async preview of %d fragments (%d parallel jobs)..."
               aj/latex-preview--total
               aj/latex-preview-parallel-jobs)
      ;; Start processing
      (aj/latex-preview--process-next))))

(defun aj/latex-preview-clear ()
  "Clear all LaTeX preview images in buffer."
  (interactive)
  (org-latex-preview '(64)))  ; C-u C-u prefix clears all

;; ---------------------------------------------------------------------------
;; TikZ Preview at Point (works inside export blocks)
;; ---------------------------------------------------------------------------

(defun aj/tikz-preview-at-point ()
  "Preview tikzpicture at point, even inside export blocks.
Extracts the tikzpicture environment and renders it, ignoring
surrounding document structure like \\begin{document}."
  (interactive)
  (save-excursion
    (let ((case-fold-search nil)
          beg end tikz-content)
      ;; Find \begin{tikzpicture}
      (if (not (re-search-backward "\\\\begin{tikzpicture}" nil t))
          (message "No tikzpicture found before point")
        (setq beg (point))
        ;; Find matching \end{tikzpicture}
        (if (not (re-search-forward "\\\\end{tikzpicture}" nil t))
            (message "No matching \\end{tikzpicture} found")
          (setq end (point))
          (setq tikz-content (buffer-substring-no-properties beg end))
          ;; Generate preview
          (aj/tikz--render-preview tikz-content beg end))))))

(defun aj/tikz--render-preview (tikz-content beg end)
  "Render TIKZ-CONTENT as a preview overlay between BEG and END."
  (let* ((temporary-file-directory (expand-file-name "ltximg/" default-directory))
         (tex-file (make-temp-file "tikz-" nil ".tex"))
         (pdf-file (concat (file-name-sans-extension tex-file) ".pdf"))
         (img-file (concat (file-name-sans-extension tex-file)
                           (if (eq org-preview-latex-default-process 'ajlua) ".svg" ".png")))
         (preamble (concat
                    "\\documentclass[tikz,border=2pt]{standalone}\n"
                    "\\usepackage{tikz}\n"
                    "\\usepackage{pgfplots}\n"
                    "\\pgfplotsset{compat=1.16}\n"
                    "\\usetikzlibrary{shapes.geometric,positioning,arrows.meta,calc,decorations.pathreplacing}\n"
                    "\\usepackage{xcolor}\n"
                    "\\begin{document}\n"))
         (postamble "\n\\end{document}\n")
         (full-content (concat preamble tikz-content postamble)))
    ;; Ensure directory exists
    (unless (file-directory-p temporary-file-directory)
      (make-directory temporary-file-directory t))
    ;; Write tex file
    (with-temp-file tex-file
      (insert full-content))
    ;; Compile asynchronously
    (message "Rendering tikzpicture...")
    (let* ((default-directory temporary-file-directory)
           (process-name "tikz-preview")
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
               (message "LaTeX compilation failed for tikzpicture")
             ;; Convert PDF to image
             (set-process-sentinel
              (start-process-shell-command "tikz-convert" nil convert-cmd)
              (lambda (proc2 _event2)
                (when (eq (process-status proc2) 'exit)
                  (if (not (= (process-exit-status proc2) 0))
                      (message "Image conversion failed for tikzpicture")
                    ;; Create overlay with image
                    (when (and (file-exists-p img-file) (buffer-live-p buf))
                      (with-current-buffer buf
                        (aj/tikz--create-overlay beg end img-file))
                      (message "TikZ preview complete")))))))))))))

(defun aj/tikz--create-overlay (beg end img-file)
  "Create an overlay from BEG to END displaying IMG-FILE."
  ;; Remove existing overlays in region
  (dolist (ov (overlays-in beg end))
    (when (overlay-get ov 'aj-tikz-preview)
      (delete-overlay ov)))
  ;; Create new overlay
  (let ((ov (make-overlay beg end)))
    (overlay-put ov 'aj-tikz-preview t)
    (overlay-put ov 'display
                 (create-image img-file nil nil
                               :ascent 'center
                               :scale 1.0))
    (overlay-put ov 'face 'default)
    (overlay-put ov 'evaporate t)))

(defun aj/tikz-clear-previews ()
  "Clear all tikz preview overlays in buffer."
  (interactive)
  (dolist (ov (overlays-in (point-min) (point-max)))
    (when (overlay-get ov 'aj-tikz-preview)
      (delete-overlay ov)))
  (message "TikZ previews cleared"))

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
                               :scale 1.0))
    (overlay-put ov 'face 'default)
    (overlay-put ov 'evaporate t)))

(defun aj/latex-clear-region-previews ()
  "Clear all region preview overlays."
  (interactive)
  (dolist (ov (overlays-in (point-min) (point-max)))
    (when (overlay-get ov 'aj-region-preview)
      (delete-overlay ov)))
  (message "Region previews cleared"))

;; Keybindings
(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c C-x C-S-l") #'aj/latex-preview-async)
  (define-key org-mode-map (kbd "C-c C-x L") #'aj/latex-preview-async)
  ;; TikZ preview at point
  (define-key org-mode-map (kbd "C-c C-x t") #'aj/tikz-preview-at-point)
  (define-key org-mode-map (kbd "C-c C-x T") #'aj/tikz-clear-previews)
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
  (message "DEBUG: filter called, max-level=%s" my/max-headline-export-level)
  (when my/max-headline-export-level
    (condition-case err
        (let ((to-remove nil)
              (preserved-count 0))
          ;; Collect headlines to remove (in document order)
          (org-element-map tree 'headline
            (lambda (hl)
              (when (> (org-element-property :level hl) my/max-headline-export-level)
                (push hl to-remove))))
          (message "DEBUG: found %d headlines to remove" (length to-remove))
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

;; Use latexmk for automatic reference/bibliography resolution
(setq org-latex-pdf-process
      '("latexmk -lualatex -shell-escape -interaction=nonstopmode %f"))

;; Configure hyperref options (org already loads hyperref, don't load it again)
;; Use \hypersetup in org files to customize colors per-file
(setq org-latex-hyperref-template
      "\\hypersetup{
 pdfauthor={%a},
 pdftitle={%t},
 pdfkeywords={%k},
 pdfsubject={%d},
 pdfcreator={%c},
 pdflang={%L},
 colorlinks=true
}")

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
  :straight t
  :bind ("C-c o p" . org-pomodoro)
  :config
  (setq org-pomodoro-start-sound aj/bell-sound
        org-pomodoro-finished-sound aj/bell-sound
        org-pomodoro-short-break-sound aj/bell-sound
        org-pomodoro-long-break-sound aj/bell-sound))

(provide 'org-config)
;;; org-config.el ends here
