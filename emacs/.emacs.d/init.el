;;; init.el --- Aayush's Emacs configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; Main init file that loads configuration modules from elisp/.
;; All custom-set-variables are stored in custom-vars.el.

;;; Code:

;; Redirect Emacs customizations to separate file (must be early)
(setq custom-file (expand-file-name "elisp/custom-vars.el" user-emacs-directory))

;; Add elisp directory to load path
(add-to-list 'load-path (expand-file-name "elisp" user-emacs-directory))

;; Add local info directory for manually built manuals (magit, etc.)
(with-eval-after-load 'info
  (add-to-list 'Info-additional-directory-list
               (expand-file-name "info" user-emacs-directory)))

;; Ensure TeX binaries are visible (macOS GUI Emacs doesn't inherit shell PATH)
(add-to-list 'exec-path "/Library/TeX/texbin")
(setenv "PATH" (concat "/Library/TeX/texbin:" (getenv "PATH")))

;; Load the obsolete `cl' compatibility shim so `incf'/`decf' (and friends)
;; resolve as macros at byte-compile time. jinx 2.7 still emits bare
;; `incf'/`decf' (jinx.el:505, 509, 1018, 1034, 1097) under only
;; `(eval-when-compile (require 'cl-lib))' — without `cl' loaded the
;; byte-compiler bakes them as runtime function calls and the idle
;; spell-check timer crashes with `invalid-function decf'. Loading `cl' here
;; covers the in-process byte-compiler; the async native-comp subprocesses
;; below (which don't load init.el) need the same shim via
;; `native-comp-async-env-modifier-form' so jinx-*.eln doesn't bake the
;; bare calls back in.
(with-suppressed-warnings ((obsolete cl))
  (require 'cl))
(setq native-comp-async-env-modifier-form
      '(with-suppressed-warnings ((obsolete cl)) (require 'cl)))

;; Bootstrap straight.el package manager
(require 'bootstrap)

;; Load local elisp modules needed early
(require 'ob-markdown)
(require 'java-lsp)

;; Load package configurations (Helm, org-roam, gptel, etc.)
(require 'package-config)

;; Load UI configuration (theme, fonts, splash screen)
(require 'ui-config)

;; Load custom variables (custom-set-variables/faces live here)
(when (file-exists-p custom-file)
  (load custom-file))

;; Load Org-mode configuration (includes LaTeX/preview setup)
(require 'org-config)

;; Load daily note configuration (recurring tasks, calendar, weather)
(require 'daily-config)

;; Load Anki-editor configuration
(require 'anki-config)

;; Load auto-save configuration
(require 'auto-save-config)

;; Load magit and keybindings
(require 'magit)
(require 'magit-bindings)

;; Load ox-hugo keybindings
(require 'ox-hugo-bindings)

;; Load custom keybindings (C-c Y prefix)
(require 'aj-bindings)

;; Load email configuration (mu4e with mbsync)
(require 'email-config)

;; Start Emacs server (for emacsclient) if not already running
(require 'server)
(unless (server-running-p)
  (server-start))

;; Reload Emacs configuration
(defun aj/reload-config ()
  "Reload Emacs configuration by re-evaluating init.el."
  (interactive)
  (load-file (expand-file-name "init.el" user-emacs-directory))
  (message "Emacs configuration reloaded!"))

(global-set-key (kbd "C-c R") #'aj/reload-config)

;;; init.el ends here
