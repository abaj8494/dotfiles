;;; init.el --- Aayush's Emacs configuration (refactored) -*- lexical-binding: t; -*-

;;; Commentary:
;; This is the main init.el file that loads all configuration modules.
;; Functionality has been organized into separate files in the elisp/ directory.

;;; Code:

;; ---------------------------------------------------------------------------
;; Add elisp directory to load path
;; ---------------------------------------------------------------------------

(add-to-list 'load-path (expand-file-name "elisp" user-emacs-directory))

;; ---------------------------------------------------------------------------
;; Bootstrap straight.el package manager
;; ---------------------------------------------------------------------------

(require 'bootstrap)

;; ---------------------------------------------------------------------------
;; Load local elisp modules that need to be available early
;; ---------------------------------------------------------------------------

(require 'ob-markdown)
(require 'java-lsp)

;; ---------------------------------------------------------------------------
;; Load package configurations
;; ---------------------------------------------------------------------------

(require 'package-config)

;; ---------------------------------------------------------------------------
;; Load UI configuration (theme, fonts, splash screen)
;; ---------------------------------------------------------------------------

(require 'ui-config)

;; ---------------------------------------------------------------------------
;; Load custom variables and faces
;; ---------------------------------------------------------------------------

(require 'custom-vars)

;; ---------------------------------------------------------------------------
;; Load Org-mode configuration
;; ---------------------------------------------------------------------------

(require 'org-config)

;; ---------------------------------------------------------------------------
;; Load Org LaTeX configuration
;; ---------------------------------------------------------------------------

(require 'org-latex)

;; ---------------------------------------------------------------------------
;; Load Org TODO logging customizations
;; ---------------------------------------------------------------------------

;;(require 'org-todo-logging)

;; ---------------------------------------------------------------------------
;; Load Anki-editor configuration
;; ---------------------------------------------------------------------------

(require 'anki-config)

;; ---------------------------------------------------------------------------
;; Load auto-save configuration
;; ---------------------------------------------------------------------------

(require 'auto-save-config)


;; ---------------------------------------------------------------------------
;; Load magit configuration
;; ---------------------------------------------------------------------------

(require 'magit)
(require 'magit-bindings)

;; ---------------------------------------------------------------------------
;; Load ox-hugo configuration
;; ---------------------------------------------------------------------------

(require 'ox-hugo-bindings)


;;; init.el ends here
(add-to-list 'load-path "~/.emacs.d/elisp")
(require 'ob-markdown)

(setq elpy-shell-starting-directory 'current-directory) ;; default is 'project-root 

  
(require 'package)
(add-to-list 'package-archives
             '("melpa" . "https://melpa.org/packages/") t)


;; AUCTeX via straight.el
(use-package latex
  :straight auctex      ;; tell straight to install *auctex*, not tex
  :defer t
  :mode ("\\.tex\\'" . LaTeX-mode))


(use-package elpy
  :ensure t
  :init
  (elpy-enable))

(use-package org-roam
  :ensure t
  :custom
  (org-roam-directory (file-truename "~/Documents/new-site/content-org/"))
  :bind (("C-c n l" . org-roam-buffer-toggle)
         ("C-c n f" . org-roam-node-find)
         ("C-c n g" . org-roam-graph)
         ("C-c n i" . org-roam-node-insert)
         ("C-c n c" . org-roam-capture)
         ;; Dailies
         ("C-c n j" . org-roam-dailies-capture-today))
  :config
  ;; If you're using a vertical completion framework, you might want a more informative completion interface
  (org-roam-db-autosync-mode)
  ;; If using org-roam-protocol
  (require 'org-roam-protocol)

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
           :unnarrowed t))))

(require 'info)

(with-eval-after-load 'info
  (add-to-list 'Info-directory-list
               (expand-file-name "straight/build/org-roam/" user-emacs-directory)))

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(org-agenda-files '("/Users/aayushbajaj/Documents/org/tasks.org"))
 '(org-format-latex-options
   '(:foreground default :background "Transparent" :scale 1.0 :html-foreground "Black" :html-background "Transparent" :html-scale 1.0 :matchers
		 ("begin" "$1" "$" "$$" "\\(" "\\[")))
 '(org-latex-classes
   '(("standalone" "\\documentclass{standalone}"
      ("\\section{%s}" . "\\section*{%s}")
      ("\\subsection{%s}" . "\\subsection*{%s}")
      ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
      ("\\paragraph{%s}" . "\\paragraph*{%s}")
      ("\\subparagraph{%s}" . "\\subparagraph*{%s}"))
     ("article" "\\documentclass{standalone}")
     ("report" "\\documentclass[11pt]{report}"
      ("\\part{%s}" . "\\part*{%s}")
      ("\\chapter{%s}" . "\\chapter*{%s}")
      ("\\section{%s}" . "\\section*{%s}")
      ("\\subsection{%s}" . "\\subsection*{%s}")
      ("\\subsubsection{%s}" . "\\subsubsection*{%s}"))
     ("book" "\\documentclass[11pt]{book}"
      ("\\part{%s}" . "\\part*{%s}")
      ("\\chapter{%s}" . "\\chapter*{%s}")
      ("\\section{%s}" . "\\section*{%s}")
      ("\\subsection{%s}" . "\\subsection*{%s}")
      ("\\subsubsection{%s}" . "\\subsubsection*{%s}"))))
 '(org-latex-default-class "standalone")
 '(package-selected-packages '(auctex jupyter conda elpy ox-hugo magit))
 '(tex-run-command "tex"))

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(default ((t (:family "Menlo" :foundry "nil" :slant normal :weight regular :height 180 :width normal)))))

(require 'conda)
;; if you want interactive shell support, include:
(conda-env-initialize-interactive-shells)
;; if you want eshell support, include:
(conda-env-initialize-eshell)
;; if you want auto-activation (see below for details), include:
(conda-env-autoactivate-mode t)
;; if you want to automatically activate a conda environment on the opening of a file:
(add-hook 'find-file-hook (lambda () (when (bound-and-true-p conda-project-env-path)
                                          (conda-env-activate-for-buffer))))

(when (memq window-system '(mac ns x))
  (exec-path-from-shell-initialize))

(setenv "EMACS" "/Applications/Emacs.app/Contents/MacOS/Emacs")

(use-package jupyter
  :commands (jupyter-run-server-repl
             jupyter-run-repl
             jupyter-server-list-kernels)
  :init (eval-after-load 'jupyter-org-extensions 
          '(unbind-key "C-c h" jupyter-org-interaction-mode-map)))



(org-babel-do-load-languages 'org-babel-load-languages
   '(
     (shell . t)
     (python . t)
     (markdown . t)
     (jupyter . t)
     (latex . t)
     (C . t)
    )
)

(setq custom-tab-width 4)
(setq-default python-indent-offset custom-tab-width) ;; Python

;;(add-to-list 'org-latex-classes
;;	     '("scrartcl" "\\documentclass[11pt]{scrartcl}"
;;	       ("\\section{%s}" . "\\section*{%s}")
;;	       ("\\subsection{%s}" . "\\subsection*{%s}")
;;	       ("\\paragraph{%s}" . "\\paragraph*{%s}")))


;;(add-to-list 'org-latex-classes
;;         '("sendit" "\\documentclass{standalone}"))


(with-eval-after-load 'ox-latex
  (add-to-list 'org-latex-classes
               '("standalone"
                 "\\documentclass{standalone}"
                 ("\\section{%s}" . "\\section*{%s}")
                 ("\\subsection{%s}" . "\\subsection*{%s}")
                 ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
                 ("\\paragraph{%s}" . "\\paragraph*{%s}")
                 ("\\subparagraph{%s}" . "\\subparagraph*{%s}"))))
;;(setq org-latex-default-class "standalone")

;; my spin
(setq ajlua3
      '(ajlua3
	:programs ("lualatex" "inkscape")
	:description "pdf > svg"
	:message "you need to install the programs:lualatex and inkscape."
	:image-input-type "pdf"
	:image-output-type "svg"
;;	:latex-compiler ("echo straight fuck >> /Users/aayushbajaj/Documents/site/content/projects/dl/perceptron/debug.tex")
        :latex-compiler ("echo \"O is %O\n o is %o\n f is %f\n F is %F\" >> /Users/aayushbajaj/Documents/site/content/projects/dl/perceptron/debug.tex")
;;	:latex-compiler ("echo -e O is %O\n o is %o\n f is %f\n F is %F\n $(cat %f) > /Users/aayushbajaj/Documents/site/content/projects/dl/perceptron/debug.tex")
;;	:latex-compiler ("lualatex --interaction=nonstopmode --shell-escape --output-directory=%o %F")
;;	:image-converter ("echo -e 'O is %O\n o is %o\n f is %f\n F is %F\n' >> /Users/aayushbajaj/Documents/site/content/projects/dl/perceptron/debug.tex")))
	:image-compiler ("echo bullshit bro >> /Users/aayushbajaj/Documents/site/content/projects/dl/perceptron/debug.tex")))
;;	:image-converter ("inkscape --pdf-poppler --export-text-to-path --export-plain-svg --export-area-drawing --export-filename=out.svg %f")))
(add-to-list 'org-preview-latex-process-alist ajlua3)

(setq ajlua2
      '(ajlua2
	:programs ("lualatex" "inkscape")
	:description "pdf > svg"
	:message "you need to install the programs:lualatex and inkscape."
	:image-input-type "pdf"
	:image-output-type "svg"
	:post-clean ("")
	:latex-compiler ("lualatex -interaction=nonstopmode --shell-escape --output-directory=%o %F")
	:image-converter ("inkscape --pdf-poppler --export-text-to-path --export-plain-svg --export-area-drawing --export-filename=out.svg %f"
			  "echo image converter was run >> /Users/aayushbajaj/Documents/site/content/projects/dl/perceptron/debug.tex"
			  "inkscape --pdf-poppler --export-text-to-path --export-plain-svg --export-area-drawing --export-filename=%O %f")
	:transparent-image-converter ("inkscape --pdf-poppler --export-text-to-path --export-plain-svg --export-area-drawing --export-filename=%O %f"
			      "echo transparent was run >> /Users/aayushbajaj/Documents/site/content/projects/dl/perceptron/debug.tex")))
(add-to-list 'org-preview-latex-process-alist ajlua2)


(setq ajlua1
      '(ajlua1
	:programs ("lualatex" "inkscape")
	:description "pdf > svg"
	:message "you need to install the programs:lualatex and inkscape."
	:image-input-type "pdf"
	:image-output-type "svg"
	:latex-compiler ("lualatex --interaction=nonstopmode --shell-escape --output-directory=%o %F")
	:image-converter ("inkscape --pdf-poppler --export-text-to-path --export-plain-svg --export-area-drawing --export-filename=out.svg %f")))

(add-to-list 'org-preview-latex-process-alist ajlua1)
 
;; A non-raping PDF->PNG convert option for org-preview.
(setq luamagick
      '(luamagick
       :programs ("lualatex" "magick")
       :description "pdf > png"
       :message "you need to install lualatex and imagemagick."
       :use-xcolor t
       :image-input-type "pdf"
       :image-output-type "png"
       :image-size-andjust (1.0 . 1.0)
       :latex-compiler ("lualatex -interaction nonstopmode -output-directory %o %f")
       :image-converter ("convert -density %D -trim -antialias %f -quality 100 %O")))

(add-to-list 'org-preview-latex-process-alist luamagick)

;; some sane options:
(setq org-preview-latex-image-directory ".")

(org-toggle-inline-images)

(setq org-latex-create-formula-image-program "lualatex")

(setq org-latex-pdf-process
  '("lualatex -shell-escape -interaction nonstopmode %f"
    "lualatex -shell-escape -interaction nonstopmode %f"))


;; this produces PDF->SVG, but the sizing is incorrect.
;; note that the below does not append to the list, but overrides it.
;; (setq org-preview-latex-process-alist
;;   '((lualatex :programs ("lualatex" "inkscape")
;;                   :description "pdf > svg"
;;                   :message "you need to install the programs: lualatex and inkscape."
;;                   :image-input-type "pdf"
;;                   :image-output-type "svg"
;;                   :latex-compiler
;;                   ("lualatex --interaction=nonstopmode --shell-escape --output-format=pdf --output-directory=%o %f")
;;                   :image-converter
;; 		  ("inkscape --pdf-poppler --export-area-drawing --export-text-to-path --export-plain-svg --export-filename=%O %F"))))


;; DVI-SVG, but it won't work with tikz
;; also overrides the list.
;; (setq org-preview-latex-process-alist
;;   '((lualatex :programs ("lualatex" "pdf2svg")
;;                   :description "dvi > svg"
;;                   :message "you need to install the programs: lualatex and pdf2svg."
;;                   :image-input-type "pdf"
;;                   :image-output-type "svg"
;;                   :image-size-adjust (1.0 . 1.0)
;;                   :latex-compiler
;;                   ("lualatex --interaction=nonstopmode --shell-escape --output-format=pdf --output-directory=%o %f")
;;                   :image-converter
;; 		  ("pdf2svg %f %O"))))
;;                   ;; ("dvisvgm %f -n -b min -c %S -o %O"))))
;; (setq org-preview-latex-process 'lualatex)


;; auto adding tex packages, jury is still out.
(add-to-list 'org-latex-packages-alist '("" "tikz" t))
(add-to-list 'org-latex-packages-alist '("" "pgfplots" t))
(add-to-list 'org-latex-packages-alist '("" "luacode" t))
(add-to-list 'org-latex-packages-alist '("" "xcolor" t))
;;(add-to-list 'org-latex-packages-alist '("" "cancel" t))

;;(setq org-latex-packages-alist (eval (car (get 'org-latex-packages-alist 'standard-value))))



;;;;;;;;;;;;;;;;;
;; auctex options
(setq org-latex-compiler "lualatex")
(setq TeX-engine "luatex")

;;(setq org-preview-latex-default-process 'ajlua3)


;;(add-to-list 'org-latex-packages-alist '("" "preview" t))
;;(setq org-latex-packages-alist (eval (car (get 'org-latex-packages-alist 'standard-value))))

;;(setq org-latex-default-class 'scrartcl)
;;(setq org-latex-default-class (eval (car (get 'org-latex-default-class 'standard-value))))
(setq org-preview-latex-default-process 'ajlua2)

(add-to-list 'org-src-lang-modes '("jupyter-python" . python))


(use-package org
  :ensure nil
  :config
  (setq org-M-RET-may-split-line '((default . nil)))
  (setq org-insert-heading-respect-content t)
  (setq org-log-done 'time)
  (setq org-log-into-drawer t)

  (setq org-directory "/Users/aayushbajaj/Documents/org/")
  (setq org-agenda-files (list org-directory))

  (setq org-todo-keywords
	'((sequence "TODO(t)" "WAIT(w!)" "|" "CANCEL(c!)" "DONE(d!)"))))



(eval-after-load "tex"
  '(add-to-list 'TeX-command-list
                '("LuaLaTeXmk" "latexmk -pdf -pdflatex=\"lualatex %O %S\" %t"
                  TeX-run-TeX nil t)))
(setq TeX-command-default "LuaLaTeXmk")


(add-to-list 'exec-path "/opt/homebrew/bin/")
(setenv "PATH" (concat "/opt/homebrew/bin:" (getenv "PATH")))

(add-to-list 'exec-path "/opt/anaconda3/bin")
(setenv "PATH" (concat "/opt/anaconda3/bin:" (getenv "PATH")))

(setq org-babel-python-command "/opt/anaconda3/bin/python")



