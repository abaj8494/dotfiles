;;; org-latex.el --- Org-mode LaTeX and preview configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; This file configures LaTeX export and preview for Org-mode.

;;; Code:

(require 'ox-latex)

;; ---------------------------------------------------------------------------
;; Org + LaTeX preview / export setup
;; ---------------------------------------------------------------------------

;; Custom LaTeX class for standalone documents
(with-eval-after-load 'ox-latex
  (add-to-list 'org-latex-classes
               '("standalone"
                 "\\documentclass{standalone}"
                 ("\\section{%s}" . "\\section*{%s}")
                 ("\\subsection{%s}" . "\\subsection*{%s}")
                 ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
                 ("\\paragraph{%s}" . "\\paragraph*{%s}")
                 ("\\subparagraph{%s}" . "\\subparagraph*{%s}"))))

;; Preview backends ----------------------------------------------------------
(setq ajlua3
      '(ajlua3
        :programs ("lualatex" "inkscape")
        :description "pdf > svg"
        :message "you need to install the programs:lualatex and inkscape."
        :image-input-type "pdf"
        :image-output-type "svg"
        :latex-compiler
        ("echo \"O is %O\n o is %o\n f is %f\n F is %F\" >> /Users/aayushbajaj/Documents/site/content/projects/dl/perceptron/debug.tex")
        :image-compiler
        ("echo bullshit bro >> /Users/aayushbajaj/Documents/site/content/projects/dl/perceptron/debug.tex")))

(add-to-list 'org-preview-latex-process-alist ajlua3)

(setq ajlua2
      '(ajlua2
        :programs ("lualatex" "inkscape")
        :description "pdf > svg"
        :message "you need to install the programs:lualatex and inkscape."
        :image-input-type "pdf"
        :image-output-type "svg"

        ;; scale factor: (BUFFER . HTML)
        :image-size-adjust (1.7 . 1.7)

        :post-clean ("")
        :latex-compiler
        ("lualatex -interaction=nonstopmode --shell-escape --output-directory=%o %F")
        :image-converter
        ("inkscape --pdf-poppler --export-text-to-path --export-plain-svg --export-area-drawing --export-filename=out.svg %f"
         "echo image converter was run >> /Users/aayushbajaj/Documents/site/content/projects/dl/perceptron/debug.tex"
         "inkscape --pdf-poppler --export-text-to-path --export-plain-svg --export-area-drawing --export-filename=%O %f")
        :transparent-image-converter
        ("inkscape --pdf-poppler --export-text-to-path --export-plain-svg --export-area-drawing --export-filename=%O %f")))

(add-to-list 'org-preview-latex-process-alist ajlua2)
(setq org-preview-latex-default-process 'ajlua2)

(setq ajlua1
      '(ajlua1
        :programs ("lualatex" "inkscape")
        :description "pdf > svg"
        :message "you need to install the programs:lualatex and inkscape."
        :image-input-type "pdf"
        :image-output-type "svg"
        :latex-compiler
        ("lualatex --interaction=nonstopmode --shell-escape --output-directory=%o %F")
        :image-converter
        ("inkscape --pdf-poppler --export-text-to-path --export-plain-svg --export-area-drawing --export-filename=out.svg %f")))

(add-to-list 'org-preview-latex-process-alist ajlua1)

(setq luamagick
      '(luamagick
        :programs ("lualatex" "magick")
        :description "pdf > png"
        :message "you need to install lualatex and imagemagick."
        :use-xcolor t
        :image-input-type "pdf"
        :image-output-type "png"
        :image-size-adjust (1.0 . 1.0)
        :latex-compiler
        ("lualatex -interaction nonstopmode -output-directory %o %f")
        :image-converter
        ("convert -density %D -trim -antialias %f -quality 100 %O")))

(add-to-list 'org-preview-latex-process-alist luamagick)

(setq org-preview-latex-image-directory ".")
(setq org-startup-with-inline-images t)

(setq org-latex-pdf-process
      '("lualatex -shell-escape -interaction nonstopmode %f"
        "lualatex -shell-escape -interaction nonstopmode %f"))

;; auto adding tex packages
(add-to-list 'org-latex-packages-alist '("" "tikz" t))
(add-to-list 'org-latex-packages-alist '("" "pgfplots" t))
(add-to-list 'org-latex-packages-alist '("" "luacode" t))
(add-to-list 'org-latex-packages-alist '("" "xcolor" t))

;; auctex options
(setq org-latex-compiler "lualatex")
(setq TeX-engine "luatex")

;; Additional TeX command for AUCTeX ----------------------------------------
(eval-after-load "tex"
  '(add-to-list 'TeX-command-list
                '("LuaLaTeXmk" "latexmk -pdf -pdflatex=\"lualatex %O %S\" %t"
                  TeX-run-TeX nil t)))
(setq TeX-command-default "LuaLaTeXmk")

(provide 'org-latex)
;;; org-latex.el ends here

