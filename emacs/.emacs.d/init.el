;;; init.el --- Aayush's Emacs configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; Main init file that loads configuration modules from elisp/.
;; All custom-set-variables are stored in custom-vars.el.

;;; Code:

;; Redirect Emacs customizations to separate file (must be early)
(setq custom-file (expand-file-name "elisp/custom-vars.el" user-emacs-directory))

;; Never let a stale .elc shadow an edited .el. The elisp/ modules here are
;; hand-edited config, and git/stow checkouts can restore a .el with an mtime
;; *older* than a previously byte-compiled .elc — so Emacs silently loads the
;; outdated compiled version with no staleness warning. That cost a real,
;; hard-to-see bug (2026-07-29): a stale org-config.elc meant the whole
;; `use-package org' :config block never applied, leaving `org-todo-keywords'
;; at the bare TODO/DONE default (so C-c C-t skipped the d/w/c fast-select
;; prompt and CANCEL was "not valid in this file"), and a stale
;; daily-recurring.elc likewise shadowed its source. Prefer source whenever
;; it's newer; the elisp/*.elc artifacts are gitignored and safe to delete.
(setq load-prefer-newer t)

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
;; `deferred' is here for exactly the same reason (added 2026-07-29). The gcal
;; push chain in org-config.el uses `deferred:try', which is a `cl-defmacro' —
;; but org-config.el only pulls `deferred' in at RUNTIME (inside the function
;; bodies), so the async native-comp subprocess, which never loads init.el and
;; had no `deferred' loaded, baked `deferred:try' in as a runtime *function*
;; call. Result: org-config-*.eln raised `invalid-function deferred:try' from
;; every deferred/timer callback — i.e. "Error running timer: (invalid-function
;; deferred:try)" — which silently broke the Google Calendar sweep chain.
;; Same failure shape as the jinx `decf' case above; same cure. If a future
;; module leans on another macro-only library, add it here too, and remember to
;; delete its stale .eln (eln-cache/*/NAME-*.eln) so it actually gets rebuilt.
(setq native-comp-async-env-modifier-form
      '(progn
         (with-suppressed-warnings ((obsolete cl)) (require 'cl))
         (require 'deferred nil t)))

;; Never async-native-compile our OWN elisp/ modules (added 2026-07-29).
;;
;; The async native-comp worker is a bare `emacs --batch' that does NOT load
;; init.el, so it has none of this session's macro providers — no straight/
;; use-package integration, no `deferred'. Macros therefore expand *differently*
;; there, and whatever it gets wrong is baked into the .eln that a later session
;; loads in preference to the source. The modifier form above can only patch
;; this one library at a time; the modules here lean on use-package + straight +
;; deferred + org, so the honest fix is to keep them out of that pipeline
;; entirely and let them load as source. They're config, not hot loops — the
;; lost native speedup is irrelevant next to silently-wrong code.
;;
;; Three separate bugs traced to this, all invisible at startup:
;;   * `(use-package go-mode)' expanded with no `:straight' handling (straight
;;     integration absent in the worker), so the build dir never landed on
;;     `load-path' → "Cannot load go-mode" every boot, and go babel silently off.
;;   * `deferred:try' baked in as a runtime *function* call instead of the macro
;;     it is → "Error running timer: (invalid-function deferred:try)" from every
;;     deferred callback, which killed the gcal push chain mid-flight and left
;;     its mutex set.
;;   * generally: any macro from a package the worker can't see.
;;
;; Regexp matches both the stowed path and the ~/.emacs.d symlink view.
;; NB: this only stops *compiling*; an already-built .eln is still preferred
;; over source, so when adding this you must also delete the stale ones
;; (eln-cache/*/{org,daily,package,anki}-config-*.eln etc).
;;
;; The variable lives in the lazily-loaded `comp-run', so it is void under
;; `emacs --batch' (where nothing gets jit-compiled anyway) — hence both the
;; eager set for a live session and the after-load hook for the general case.
(defconst aj/native-comp-deny-own-elisp "/\\.emacs\\.d/elisp/"
  "Regexp of files to keep out of async native-compilation.")
(when (boundp 'native-comp-jit-compilation-deny-list)
  (add-to-list 'native-comp-jit-compilation-deny-list
               aj/native-comp-deny-own-elisp))
(with-eval-after-load 'comp-run
  (add-to-list 'native-comp-jit-compilation-deny-list
               aj/native-comp-deny-own-elisp))

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

;; Load R/ESS + Org-Babel R support. BEFORE org-config so `aj/ob-R-available'
;; is set when its `org-babel-do-load-languages' block decides whether to
;; enable the R language.
(aj/safe-require 'r-config)

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

;; Ferrari (rMPP) dired push: `C-c F' in a dired buffer under ~/lattice/org-notes
;; rsyncs the marked files/dirs onto the device. The module lives off-repo in
;; the ferrari project; put its scripts dir on `load-path' so `aj/safe-require'
;; can pick it up (and degrade gracefully if that checkout is absent).
(add-to-list 'load-path
             (expand-file-name
              "~/lattice/2-areas/devices/remarkable/ferrari/scripts"))
(aj/safe-require 'ferrari-dired-push)

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
(defun aj/reload-config (&optional full)
  "Reload Emacs configuration.

By default, reload the config module shown in the current buffer — i.e.
the file you just edited.  This is the common case and the one the old
behaviour silently broke: init.el loads every module via `require'
\(through `aj/safe-require'), and `require' is a no-op once a feature is
loaded, so re-running init.el never re-evaluated an already-loaded
module.  Re-`load'ing the visited file forces a fresh evaluation, so the
edit actually takes effect.

With a prefix arg (C-u), or when the current buffer is not a config .el
under `user-emacs-directory', force a full reload: re-`load' every
locally provided module file in place, then re-run init.el for its own
top-level forms.  We `load' rather than `unload-feature' + `require' so
function definitions are overwritten in place and never pass through a
void window — otherwise the mode-line (which evals `my/email-mode-line'
and friends every redisplay) errors repeatedly during the reload gap."
  (interactive "P")
  (let ((file (buffer-file-name)))
    (if (and (not full)
             file
             (string-suffix-p ".el" file)
             (file-in-directory-p file (expand-file-name "elisp" user-emacs-directory)))
        (progn
          (load-file file)
          (message "Reloaded %s" (file-name-nondirectory file)))
      ;; Full reload: re-load each of our own elisp/ modules fresh (in
      ;; place, so no symbol is ever transiently void), leaving
      ;; straight-loaded package features untouched.  Then load init.el
      ;; for its top-level forms — its `require's are now no-ops, which is
      ;; fine since the modules were just reloaded above.
      (let ((dir (expand-file-name "elisp" user-emacs-directory)))
        (dolist (feature (copy-sequence features))
          (let ((f (locate-library (symbol-name feature))))
            (when (and f (file-in-directory-p f dir))
              (ignore-errors (load f nil t))))))
      (load-file (expand-file-name "init.el" user-emacs-directory))
      (message "Emacs configuration fully reloaded!"))))

(global-set-key (kbd "C-c R") #'aj/reload-config)

;;; init.el ends here
