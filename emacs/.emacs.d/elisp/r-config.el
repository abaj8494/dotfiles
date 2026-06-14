;;; r-config.el --- R / ESS + Org Babel support -*- lexical-binding: t; -*-

;;; Commentary:
;; Interactive R via ESS (M-x R) and literate R via Org Babel (ob-R), with
;; inline plot/image display in Org buffers.
;;
;; R itself is the CRAN install at /usr/local/bin/R (4.5.x) — NOT installed
;; here, just located. This GUI Emacs (MacPorts emacs-app, built +rsvg) renders
;; the PNG/SVG plots inline; a -nw terminal Emacs cannot, which is the whole
;; reason for experimenting in the GUI before porting to the reMarkable (where
;; the plan is to serve the images over HTTP, RMStream-style).
;;
;; Two ways to see a plot:
;;   1. Interactive ESS (M-x R): plot()/hist() pop a native Quartz device
;;      window — separate from Emacs, works because CRAN R has Quartz.
;;   2. Org Babel (preferred for inline-in-Emacs):
;;        #+begin_src R :results graphics file :file hist.png :width 600 :height 400
;;          hist(rnorm(1000))
;;        #+end_src
;;      C-c C-c renders the PNG and it appears inline (auto-redisplayed below).

;;; Code:

;; CRAN R lives in /usr/local/bin, which is NOT among the prefixes org-config
;; already puts on exec-path (/opt/homebrew, /opt/anaconda3). GUI Emacs doesn't
;; inherit the shell PATH, so make R findable for both ESS and ob-R.
(add-to-list 'exec-path "/usr/local/bin")
(setenv "PATH" (concat "/usr/local/bin:" (getenv "PATH")))

;; GUI Emacs doesn't inherit the shell's R_PROFILE_USER (set in .zshrc), so R
;; subprocesses started here — ESS and ob-R — would miss the stowed Rprofile and
;; hit "trying to use CRAN without setting a mirror" on install.packages. Point
;; them at the same stowed profile (~/.config/R/Rprofile → ~/dotfiles/r).
(setenv "R_PROFILE_USER" (expand-file-name "~/.config/R/Rprofile"))

;; Set non-nil once ESS loads, so org-config can enable the R babel language
;; defensively (same guard pattern as aj/ob-go-available) — a flaky boot where
;; straight can't fetch ESS then skips (R . t) instead of truncating org-config.
(defvar aj/ob-R-available nil
  "Non-nil when ESS is loaded and the R Org-Babel language is safe to enable.")

(use-package ess
  :straight t
  ;; Load eagerly (not deferred): ob-R's execute path needs ESS, and we want
  ;; aj/ob-R-available set true before org-config's babel block runs.
  :demand t
  :init
  (setq inferior-R-program "/usr/local/bin/R"
        ;; don't prompt for a working directory on every M-x R
        ess-ask-for-ess-directory nil
        ;; echo evaluated input into the process buffer, async (REPL-like)
        ess-eval-visibly 'nowait)
  :config
  (setq aj/ob-R-available t))

;; --- Org Babel R: inline plots ------------------------------------------
;; After any babel block runs, redisplay inline images so :results graphics
;; (and :file PNG/SVG outputs) appear without a manual C-c C-x C-v.
(with-eval-after-load 'org
  (setq org-startup-with-inline-images t)
  (add-hook 'org-babel-after-execute-hook #'org-redisplay-inline-images))

;; Default header args for R src blocks. NOTE: do NOT default to a shared
;; :session here — ob-R writes an EMPTY graphics file when a `:results graphics
;; file` block runs inside a session, so a global `:session *R*' silently breaks
;; inline plots. Default is session-less (each block self-contained, plots work).
;; For stateful multi-step analysis, opt in explicitly per file/subtree:
;;   #+PROPERTY: header-args:R :session *R*
;; and keep plotting blocks session-less (or :session none) so they render.
(with-eval-after-load 'ob-R
  (setq org-babel-default-header-args:R
        '((:results . "output")
          (:exports . "both"))))

(provide 'r-config)
;;; r-config.el ends here
