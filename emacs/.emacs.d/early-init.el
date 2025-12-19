;;; early-init.el --- Early initialization -*- lexical-binding: t; -*-

;;; Commentary:
;; This file is loaded before the package system and GUI is initialized.
;; Used for performance optimizations and native compilation setup.

;;; Code:

;; ---------------------------------------------------------------------------
;; Performance: Increase GC threshold during startup
;; ---------------------------------------------------------------------------

(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

;; ---------------------------------------------------------------------------
;; Performance: Reduce file-name-handler-alist overhead during startup
;; ---------------------------------------------------------------------------

(defvar file-name-handler-alist-original file-name-handler-alist)
(setq file-name-handler-alist nil)

;; Restore after startup
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 16 1024 1024)  ; 16MB
                  gc-cons-percentage 0.1
                  file-name-handler-alist file-name-handler-alist-original)))

;; ---------------------------------------------------------------------------
;; Package Management: Disable package.el (using straight.el instead)
;; ---------------------------------------------------------------------------

(setq package-enable-at-startup nil)

;; ---------------------------------------------------------------------------
;; Native Compilation Setup for macOS (Apple Silicon)
;; ---------------------------------------------------------------------------

(when (and (fboundp 'native-comp-available-p)
           (native-comp-available-p)
           (eq system-type 'darwin))
  
  ;; MacPorts GCC paths for native compilation
  (setenv "LIBRARY_PATH"
          (string-join
           '("/opt/local/lib/gcc15"
             "/opt/local/lib/libgcc"
             "/opt/local/lib/gcc15/gcc/aarch64-apple-darwin25"
             "/opt/homebrew/lib")
           ":"))
  
  ;; Point to MacPorts GCC-15 explicitly
  (setenv "CC" "/opt/local/bin/gcc-mp-15")
  
  ;; Add MacPorts bin to PATH for gcc and other tools
  (let ((gcc-path "/opt/local/bin"))
    (unless (string-match-p gcc-path (getenv "PATH"))
      (setenv "PATH" (concat gcc-path ":" (getenv "PATH")))))
  
  ;; Native compilation settings
  (setq native-comp-speed 2                        ; Optimize for speed
        native-comp-async-report-warnings-errors nil ; Don't spam warnings
        native-comp-deferred-compilation t          ; Compile in background
        native-comp-enable-subr-trampolines nil))   ; Disable if causing issues

;;; early-init.el ends here
