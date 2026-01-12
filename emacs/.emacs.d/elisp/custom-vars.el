;;; custom-vars.el --- Emacs customization settings -*- lexical-binding: t; -*-

;;; Commentary:
;; This file is the designated location for Emacs customize system.
;; Set via (setq custom-file ...) in init.el.
;; Do not edit manually unless you know what you're doing.

;;; Code:

(custom-set-variables
 '(custom-safe-themes
   '("e27c9668d7eddf75373fa6b07475ae2d6892185f07ebed037eedf783318761d7"
     default))
 '(org-agenda-files
   '("/Users/aayushbajaj/Documents/new-site/content-org/daily/"))
 '(org-export-with-drawers nil)
 '(org-format-latex-options
   '(:foreground default :background "Transparent" :scale 2.0
                 :html-foreground "Black" :html-background "Transparent"
                 :html-scale 1.0
                 :matchers ("begin" "$1" "$" "$$" "\\(" "\\[")))
 '(org-latex-classes
   '(("standalone" "\\documentclass{standalone}"
      ("\\section{%s}" . "\\section*{%s}")
      ("\\subsection{%s}" . "\\subsection*{%s}")
      ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
      ("\\paragraph{%s}" . "\\paragraph*{%s}")
      ("\\subparagraph{%s}" . "\\subparagraph*{%s}"))
     ("article" "\\documentclass[11pt]{article}"
      ("\\section{%s}" . "\\section*{%s}")
      ("\\subsection{%s}" . "\\subsection*{%s}")
      ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
      ("\\paragraph{%s}" . "\\paragraph*{%s}")
      ("\\subparagraph{%s}" . "\\subparagraph*{%s}"))
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
 '(org-latex-default-class "article")
 '(org-latex-image-default-scale "1")
 '(org-log-into-drawer "PROPERTIES")
 '(safe-local-variable-values
   '((eval setq org-preview-latex-default-process 'imagemagick)))
 '(tex-run-command "tex"))

(custom-set-faces
 '(default ((t (:family "Menlo" :foundry "nil" :slant normal
                        :weight regular :height 180 :width normal)))))

(provide 'custom-vars)
;;; custom-vars.el ends here
