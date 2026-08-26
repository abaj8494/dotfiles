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
        ;; Start R sessions in `default-directory' (the file/org-block location),
        ;; NOT the VC project root.  `inferior-ess--get-startup-directory' (ess-inf.el)
        ;; falls back to `(project-current)'s root before `default-directory' when
        ;; both `ess-startup-directory' and this function are nil — so inside the
        ;; ~/lattice/org-notes git repo every R session was spawned at the repo root and
        ;; ESS sent `setwd("~/lattice/org-notes")' at startup, clobbering ob-R's `:dir'
        ;; (relative `read.table' paths then failed).  Returning `default-directory'
        ;; here is consulted *before* the project fallback and restores sane cwd.
        ess-startup-directory-function (lambda () default-directory)
        ;; echo evaluated input into the process buffer, async (REPL-like)
        ess-eval-visibly 'nowait
        ;; Don't column-align `#' comments. With fancy comments on, a single-`#'
        ;; comment auto-indents to `comment-column' (40), so pressing RET on a
        ;; line like `# closed form:' reindents it out with a wall of spaces.
        ;; nil → comments indent at code level like every other line.
        ess-indent-with-fancy-comments nil)
  :config
  (setq aj/ob-R-available t))

;; --- R completion inside Org `C-c '' edits (and .R buffers) --------------
;; ESS's object/function capf (`ess-r-object-completion') is process-driven:
;; it asks a *live* R for the symbol list and returns nothing unless the
;; editing buffer's `ess-local-process-name' names a running process. An Org
;; `C-c '' src-edit buffer is a fresh ess-r-mode buffer with no such link, so
;; completion silently does nothing even when *R* is up — you'd otherwise have
;; to `M-x R' then `C-c C-s' (ess-switch-process) in every edit buffer. Link
;; each ess-r-mode buffer to a single R process, starting one on demand, so
;; corfu pops with zero ceremony.
(defun aj/ess-r-link-process ()
  "Attach this `ess-r-mode' buffer to a live R process for completion.
Reuse an existing R if one is running, else cold-start one (the
inferior buffer is created without stealing the window)."
  (when (and (derived-mode-p 'ess-r-mode)
             (not (and ess-local-process-name
                       (get-process ess-local-process-name))))
    (unless ess-process-name-list
      (let ((ess-ask-for-ess-directory nil))
        (save-window-excursion (R))))
    (when ess-process-name-list
      (setq ess-local-process-name (caar ess-process-name-list)))))
(add-hook 'ess-r-mode-hook #'aj/ess-r-link-process)

;; Corfu auto-pops a completion query on every keystroke; if that fires while
;; R is busy (still booting from the cold-start above, or mid `C-c C-c'
;; evaluation), ESS's synchronous `ess-command' signals `user-error' "ESS
;; process not ready", which corfu surfaces as an error backtrace. Guard the
;; R capf so a busy/absent process yields *no candidates* instead of erroring;
;; completion just resumes once R is back at its prompt.
(defun aj/ess-r-completion-guard (orig &rest args)
  "Run ORIG (an ESS R capf) only when its R process is idle and ready."
  (let ((proc (and ess-local-process-name
                   (get-process ess-local-process-name))))
    (when (and proc
               (eq (process-status proc) 'run)
               (not (process-get proc 'busy)))
      (ignore-errors (apply orig args)))))
(with-eval-after-load 'ess-r-completion
  (advice-add 'ess-r-object-completion :around #'aj/ess-r-completion-guard)
  (advice-add 'ess-r-package-completion :around #'aj/ess-r-completion-guard))

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
