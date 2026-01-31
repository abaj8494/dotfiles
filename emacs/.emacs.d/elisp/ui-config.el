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

;; Font is set via custom-set-faces in custom-vars.el

;; Load gruber-themes for toggle and ergonomic headings
(require 'gruber-themes)

;; Load default theme
(load-theme 'gruber-darker t)

;; ---------------------------------------------------------------------------
;; Toggle keymap (C-c T)
;; ---------------------------------------------------------------------------

(defvar aj/toggle-map (make-sparse-keymap)
  "Keymap for toggle commands under C-c T.")

(global-set-key (kbd "C-c T") aj/toggle-map)

;; t = theme toggle
(define-key aj/toggle-map (kbd "t") #'gruber-toggle)

;; s = spell toggle (flyspell-mode)
(define-key aj/toggle-map (kbd "s") #'flyspell-mode)

;; Flyspell configuration - uses same backend as ispell
(with-eval-after-load 'flyspell
  ;; Use aspell if available (better suggestions than ispell)
  (when (executable-find "aspell")
    (setq ispell-program-name "aspell")
    (setq ispell-extra-args '("--sug-mode=ultra" "--lang=en_US")))
  ;; Speed up flyspell
  (setq flyspell-issue-message-flag nil))

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

