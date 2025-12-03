;;; org-config.el --- Org-mode basic configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; This file configures org-mode basics, babel, and source code blocks.

;;; Code:

(require 'org)
(require 'ob-markdown)

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

;; Python configuration
(setq custom-tab-width 4)
(setq-default python-indent-offset custom-tab-width)
(setq org-babel-python-command "/opt/anaconda3/bin/python")

;; Never use hard tabs in Python
(add-hook 'python-mode-hook
          (lambda ()
            (setq indent-tabs-mode nil)))

;; And when editing src blocks in Org
(add-hook 'org-src-mode-hook
          (lambda ()
            (setq indent-tabs-mode nil)))

;; controversial:
(setq-default indent-tabs-mode nil)

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

  (setq org-directory "/Users/aayushbajaj/Documents/new-site/static/doc/org/")
  (setq org-agenda-files (list org-directory))

  (setq org-todo-keywords
        '((sequence "TODO(t)" "WAIT(w!)" "|" "CANCEL(c!)" "DONE(d!)"))))

;; Add jupyter-python mode mapping
(add-to-list 'org-src-lang-modes '("jupyter-python" . python))

;; ---------------------------------------------------------------------------
;; Org Template Configuration
;; ---------------------------------------------------------------------------

(with-eval-after-load 'org
  (require 'org-tempo)
  
  (setq org-babel-default-header-args:jupyter-python
        '((:session . "leet")))
  ;; <sj TAB => jupyter-python block
  (add-to-list 'org-structure-template-alist
               '("sj" . "src jupyter-python"))
  ;; <sp TAB => python block
  (add-to-list 'org-structure-template-alist
               '("sp" . "src python")))

;; ---------------------------------------------------------------------------
;; Org Element Compatibility Shim
;; ---------------------------------------------------------------------------

(with-eval-after-load 'org-element
  ;; Org < 9.7 doesn't have `org-element--property`, but some packages
  ;; compiled against new Org call it directly. Provide a shim.
  (unless (fboundp 'org-element--property)
    (defun org-element--property (property node &optional dflt _force-undefer)
      "Compatibility shim for packages expecting Org 9.7's AST API.
Return DFLT when PROPERTY is not present."
      (or (org-element-property property node) dflt))))

;; ---------------------------------------------------------------------------
;; PATH Configuration
;; ---------------------------------------------------------------------------

(add-to-list 'exec-path "/opt/homebrew/bin/")
(setenv "PATH" (concat "/opt/homebrew/bin:" (getenv "PATH")))

(add-to-list 'exec-path "/opt/anaconda3/bin")
(setenv "PATH" (concat "/opt/anaconda3/bin:" (getenv "PATH")))

(provide 'org-config)
;;; org-config.el ends here

