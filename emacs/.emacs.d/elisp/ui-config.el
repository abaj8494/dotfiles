;;; ui-config.el --- UI and appearance configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; This file handles UI configuration including theme, fonts, and startup screen.

;;; Code:

;; ---------------------------------------------------------------------------
;; Theme and Fonts
;; ---------------------------------------------------------------------------

;; Load theme
(load-theme 'modus-vivendi t)

;; Custom font face
(custom-set-faces
 '(default ((t (:family "Menlo" :foundry "nil" :slant normal
                        :weight regular :height 180 :width normal)))))

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

