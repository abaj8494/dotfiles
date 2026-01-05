;;; ui-config.el --- UI and appearance configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; This file handles UI configuration including theme, fonts, and startup screen.

;;; Code:

;; ---------------------------------------------------------------------------
;; Theme and Fonts
;; ---------------------------------------------------------------------------

;; Load theme
;;(load-theme 'modus-vivendi t)



;; Add custom theme directories
(add-to-list 'custom-theme-load-path "~/.emacs.d/custom-themes/gruber-darker-theme/")
(add-to-list 'custom-theme-load-path "~/.emacs.d/custom-themes/")

;; Custom font face
(custom-set-faces
 '(default ((t (:family "Menlo" :foundry "nil" :slant normal
                        :weight regular :height 180 :width normal)))))

;; Load gruber-themes for toggle and ergonomic headings
(require 'gruber-themes)

;; Load default theme
(load-theme 'gruber-darker t)

;; Keybinding for theme toggle (similar to modus-themes)
(global-set-key (kbd "C-c T") #'gruber-toggle)

(global-set-key (kbd "C-c e i") (lambda () (interactive) (find-file "~/.emacs.d/init.el")))
(global-set-key (kbd "C-c e d") (lambda () (interactive) (find-file "~/.emacs.d/elisp/")))

;; ---------------------------------------------------------------------------
;; Splash screen / my-home
;; ---------------------------------------------------------------------------

(require 'my-home)

(setq inhibit-startup-screen t)
(setq initial-buffer-choice #'my-home-buffer)

(global-set-key (kbd "C-c h")
                (lambda ()
                  (interactive)
                  (switch-to-buffer (my-home-buffer))))

;; Key binding for opening home in a new tab
(global-set-key (kbd "C-x t h")
  (lambda ()
    (interactive)
    (tab-bar-new-tab)
    (switch-to-buffer (my-home-buffer))))

(provide 'ui-config)
;;; ui-config.el ends here

