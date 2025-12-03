;;; custom-vars.el --- Custom variables and faces set by Emacs -*- lexical-binding: t; -*-

;;; Commentary:
;; This file contains custom variables and faces set by the Emacs customization system.

;;; Code:

;; ---------------------------------------------------------------------------
;; Custom variables (from Custom)
;; ---------------------------------------------------------------------------

(custom-set-variables
 '(org-agenda-files
   '("/Users/aayushbajaj/Documents/new-site/static/doc/org/tasks.org"))
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
 '(org-latex-image-default-scale "1")
 '(org-log-into-drawer "PROPERTIES")
 '(safe-local-variable-values
   '((eval setq org-preview-latex-default-process 'imagemagick)))
 '(tex-run-command "tex"))

(provide 'custom-vars)
;;; custom-vars.el ends here

