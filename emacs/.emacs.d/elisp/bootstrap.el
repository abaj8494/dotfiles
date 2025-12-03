;;; bootstrap.el --- Bootstrap straight.el package manager -*- lexical-binding: t; -*-

;;; Commentary:
;; This file handles the bootstrapping of straight.el and use-package.

;;; Code:

;; Make sure package.el does not auto-enable (extra safety; main one is early-init)
(setq package-enable-at-startup nil)

;; ---------------------------------------------------------------------------
;; Bootstrap straight.el + use-package
;; ---------------------------------------------------------------------------
(defvar bootstrap-version)
(let* ((bootstrap-file
        (expand-file-name "straight/repos/straight.el/bootstrap.el"
                          user-emacs-directory))
       (bootstrap-version 6))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/radian-software/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

(add-to-list 'straight-built-in-pseudo-packages 'org)

(straight-use-package 'use-package)
(setq straight-use-package-by-default t
      use-package-always-ensure nil)

;; Install critical packages EARLY so local code can require them
(straight-use-package 'lsp-mode)
(straight-use-package 'lsp-java)

(provide 'bootstrap)
;;; bootstrap.el ends here

