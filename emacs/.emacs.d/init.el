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

;; Module loader: keep one module's failure from aborting the rest of init.
;; Without this, an error in any `require' below (e.g. straight failing to load
;; an optional package when the network isn't up yet right after a boot)
;; cascades — every module after it is silently skipped, disabling large parts
;; of the config. Log a visible warning and carry on so the editor degrades
;; gracefully instead of coming up half-configured.
(defvar aj/failed-modules nil
  "Features whose load threw during init, kept in load order for a deferred retry.")

(defun aj/safe-require (feature)
  "Require FEATURE without letting its failure abort the rest of init.
A mid-file error (commonly a transient boot race: straight still cloning
an optional package, the network not up yet, the build dir not on
load-path) otherwise truncates that file silently AND skips every module
required afterwards. Record the failure for `aj/retry-failed-modules' and
carry on, so the editor never comes up half-configured without saying so."
  (condition-case err
      (prog1 (require feature)
        (setq aj/failed-modules (delq feature aj/failed-modules)))
    (error
     (add-to-list 'aj/failed-modules feature t)
     (display-warning 'init
       (format "Failed to load %s: %S — will retry once init settles" feature err)
       :warning))))

(defun aj/retry-failed-modules ()
  "Re-attempt any module that lost a boot-time race in `aj/safe-require'.
Those races resolve within seconds (straight finishes, load-path settles),
and a truncated module never `provide'd its feature, so `require' reloads
the whole file from scratch — this time running it to completion. Anything
still broken afterwards is a real fault, surfaced loudly rather than left
to be discovered days later as a missing feature."
  (when aj/failed-modules
    (dolist (feature (copy-sequence aj/failed-modules))
      (aj/safe-require feature))
    (if aj/failed-modules
        (display-warning 'init
          (format "Modules still failing after retry: %S.
Inspect *Warnings* for the cause, then M-x aj/reload-config." aj/failed-modules)
          :emergency)
      (message "aj/retry-failed-modules: all previously-failed modules now loaded"))))

;; Load local elisp modules needed early
(aj/safe-require 'ob-markdown)
(aj/safe-require 'java-lsp)

;; Load package configurations (Helm, org-roam, gptel, etc.)
(aj/safe-require 'package-config)

;; Load UI configuration (theme, fonts, splash screen)
(aj/safe-require 'ui-config)

;; Load custom variables (custom-set-variables/faces live here)
(when (file-exists-p custom-file)
  (load custom-file))

;; Load Org-mode configuration (includes LaTeX/preview setup)
(aj/safe-require 'org-config)

;; Load daily note configuration (recurring tasks, calendar, weather)
(aj/safe-require 'daily-config)

;; Load Anki-editor configuration
(aj/safe-require 'anki-config)

;; Load auto-save configuration
(aj/safe-require 'auto-save-config)

;; Load magit and keybindings
(aj/safe-require 'magit)
(aj/safe-require 'magit-bindings)

;; Load ox-hugo keybindings
(aj/safe-require 'ox-hugo-bindings)

;; Load custom keybindings (C-c Y prefix)
(aj/safe-require 'aj-bindings)

;; Load email configuration (mu4e with mbsync)
(aj/safe-require 'email-config)

;; Retry any module that lost a boot-time race above, once the daemon has
;; settled (straight done, network up, load-path populated). Without this, a
;; transient miss leaves the config silently half-loaded until the next restart.
(run-at-time 5 nil #'aj/retry-failed-modules)

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
