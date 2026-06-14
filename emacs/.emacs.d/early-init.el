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

;; Prefer newer .el over a stale .elc. Without this, `load' always picks the
;; .elc when present even if the source is newer — so an out-of-date compiled
;; module silently shadows edits (this bit org-config.elc: a pre-guard-fix
;; bytecode kept throwing on ob-go long after the source was fixed).
(setq load-prefer-newer t)

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

;; ---------------------------------------------------------------------------
;; Frame chrome: drop the menu bar (and tool bar / scroll bars)
;; ---------------------------------------------------------------------------
;; Set via default-frame-alist in early-init so the bars are never drawn —
;; no startup flash — plus the *-mode calls cover frames created later.
;;
;; macOS caveat: on this Cocoa build (MacPorts emacs-app), `menu-bar-mode -1'
;; does NOT remove the menu bar at the very top of the SCREEN — that bar is
;; owned by macOS and always shown for the focused GUI app; only the OS can
;; hide it (System Settings ▸ Desktop & Dock ▸ "Automatically hide and show the
;; menu bar", or full-screen). What it (and tool-bar-mode) DO remove is the
;; in-window chrome at the top of the Emacs frame — most visibly the tool bar.
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)
(when (fboundp 'menu-bar-mode)   (menu-bar-mode -1))
(when (fboundp 'tool-bar-mode)   (tool-bar-mode -1))
(when (fboundp 'scroll-bar-mode) (scroll-bar-mode -1))

;;; early-init.el ends here
