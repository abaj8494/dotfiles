;;; custom-vars.el --- Emacs customization settings -*- lexical-binding: t; -*-

;;; Commentary:
;; This file is the designated location for Emacs customize system.
;; Set via (setq custom-file ...) in init.el.
;; Do not edit manually unless you know what you're doing.

;;; Code:

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(custom-safe-themes
   '("e27c9668d7eddf75373fa6b07475ae2d6892185f07ebed037eedf783318761d7"
     default))
 '(helm-ff-initial-sort-method 'newest)
 '(org-agenda-files nil)
 '(org-export-with-drawers nil)
 '(org-format-latex-options
   '(:foreground default :background "Transparent" :scale 1.5
                 :html-foreground "Black" :html-background
                 "Transparent" :html-scale 1.0 :matchers
                 ("begin" "$1" "$" "$$" "\\(" "\\[")))
 '(org-latex-default-class "article")
 '(org-latex-image-default-scale "")
 '(org-log-into-drawer "PROPERTIES")
 '(safe-local-variable-values
   '((eval setq org-preview-latex-default-process 'imagemagick)))
 '(tex-run-command "tex"))

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(default ((t (:family "Menlo" :foundry "nil" :slant normal :weight regular :height 180 :width normal)))))

(provide 'custom-vars)
;;; custom-vars.el ends here
