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
        '((sequence "TODO(t)" "WAIT(w!)" "|" "CANCEL(c!)" "DONE(d!)"))))

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

(setq org-capture-templates
      '(("t" "todo list item" entry
         (file+headline "~/Documents/new-site/static/doc/org/tasks.org" "Tasks")
         "* TODO %?\n %i\n %a")
        ("j" "journal entry" entry
         (file+datetree "~/Documents/new-site/static/doc/org/journal.org")
         "* %?\nEntered on %U\n %i\n %a")))

;; Main org prefix on C-c c
(define-prefix-command 'my/org-main-map)
(global-set-key (kbd "C-c c") #'my/org-main-map)
(define-key my/org-main-map (kbd "c") #'org-capture)

;; ---------------------------------------------------------------------------
;; LaTeX Document Classes
;; ---------------------------------------------------------------------------

(with-eval-after-load 'ox-latex
  (add-to-list 'org-latex-classes
               '("standalone"
                 "\\documentclass{standalone}"
                 ("\\section{%s}" . "\\section*{%s}")
                 ("\\subsection{%s}" . "\\subsection*{%s}")
                 ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
                 ("\\paragraph{%s}" . "\\paragraph*{%s}")
                 ("\\subparagraph{%s}" . "\\subparagraph*{%s}"))))

;; ---------------------------------------------------------------------------
;; LaTeX Preview Backends
;; ---------------------------------------------------------------------------

;; PDF->SVG via lualatex + inkscape (primary)
(setq ajlua2
      '(ajlua2
        :programs ("lualatex" "inkscape")
        :description "pdf > svg"
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
(add-to-list 'org-preview-latex-process-alist ajlua2)

(setq ajlua1
      '(ajlua1
        :programs ("lualatex" "inkscape")
        :description "pdf > svg (simple)"
        :message "Requires lualatex and inkscape."
        :image-input-type "pdf"
        :image-output-type "svg"
        :latex-compiler
        ("lualatex --interaction=nonstopmode --shell-escape --output-directory=%o %F")
        :image-converter
        ("inkscape --pdf-poppler --export-text-to-path --export-plain-svg --export-area-drawing --export-filename=%O %f")))
(add-to-list 'org-preview-latex-process-alist ajlua1)

;; PDF->PNG via lualatex + imagemagick (fallback)
(setq luamagick
      '(luamagick
        :programs ("lualatex" "magick")
        :description "pdf > png"
        :message "Requires lualatex and imagemagick."
        :use-xcolor t
        :image-input-type "pdf"
        :image-output-type "png"
        :image-size-adjust (1.0 . 1.0)
        :latex-compiler
        ("lualatex -interaction nonstopmode -output-directory %o %f")
        :image-converter
        ("convert -density %D -trim -antialias %f -quality 100 %O")))
(add-to-list 'org-preview-latex-process-alist luamagick)

;; Default preview process
(setq org-preview-latex-default-process 'ajlua2)
(setq org-preview-latex-image-directory "ltximg/")
(setq org-startup-with-inline-images t)

;; ---------------------------------------------------------------------------
;; LaTeX Export Settings
;; ---------------------------------------------------------------------------

(setq org-latex-pdf-process
      '("lualatex -shell-escape -interaction nonstopmode %f"
        "lualatex -shell-escape -interaction nonstopmode %f"))

;; Common LaTeX packages
(add-to-list 'org-latex-packages-alist '("" "tikz" t))
(add-to-list 'org-latex-packages-alist '("" "pgfplots" t))
(add-to-list 'org-latex-packages-alist '("" "luacode" t))
(add-to-list 'org-latex-packages-alist '("" "xcolor" t))

;; AUCTeX settings
(setq org-latex-compiler "lualatex")
(setq TeX-engine "luatex")

(eval-after-load "tex"
  '(add-to-list 'TeX-command-list
                '("LuaLaTeXmk" "latexmk -pdf -pdflatex=\"lualatex %O %S\" %t"
                  TeX-run-TeX nil t)))
(setq TeX-command-default "LuaLaTeXmk")

(provide 'org-config)
;;; org-config.el ends here
