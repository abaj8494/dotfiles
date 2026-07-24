;;; gruber-themes.el --- Gruber theme utilities and toggle -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Provides toggle functionality between gruber-darker and gruber-lighter themes,
;; along with ergonomic heading customizations for org-mode.

;;; Code:

(defgroup gruber-themes nil
  "Options for gruber-themes."
  :group 'faces)

(defcustom gruber-themes-headings-scale t
  "When non-nil, scale org/outline headings with larger sizes for higher levels."
  :type 'boolean
  :group 'gruber-themes)

;; ---------------------------------------------------------------------------
;; Ergonomic heading colors
;; ---------------------------------------------------------------------------
;; These colors are designed for visual hierarchy while reducing eye strain.
;; Less saturated than typical syntax highlighting colors.

(defvar gruber-themes-dark-heading-colors
  '((document-title . (:foreground "#efbf04" :weight bold))  ; Warm gold
    (outline-1 . (:foreground "#efbf04" :weight bold))       ; Warm gold
    (outline-2 . (:foreground "#8fa7c6" :weight bold))       ; Muted blue
    (outline-3 . (:foreground "#8bb664" :weight bold))       ; Soft green
    (outline-4 . (:foreground "#c9a066" :weight bold))       ; Muted amber
    (outline-5 . (:foreground "#a89cc8"))                    ; Soft lavender
    (outline-6 . (:foreground "#89a098"))                    ; Sage
    (outline-7 . (:foreground "#a0a0a0"))                    ; Neutral gray
    (outline-8 . (:foreground "#909090")))                   ; Lighter gray
  "Ergonomic heading colors for gruber-darker theme.")

(defvar gruber-themes-light-heading-colors
  '((document-title . (:foreground "#8a6200" :weight bold))  ; Deep gold
    (outline-1 . (:foreground "#8a6200" :weight bold))       ; Deep gold
    (outline-2 . (:foreground "#3d5a80" :weight bold))       ; Deep blue
    (outline-3 . (:foreground "#4a7c30" :weight bold))       ; Forest green
    (outline-4 . (:foreground "#8b5a2b" :weight bold))       ; Saddle brown
    (outline-5 . (:foreground "#6a5a8e"))                    ; Deep lavender
    (outline-6 . (:foreground "#5a6b62"))                    ; Deep sage
    (outline-7 . (:foreground "#606060"))                    ; Dark gray
    (outline-8 . (:foreground "#707070")))                   ; Medium gray
  "Ergonomic heading colors for gruber-lighter theme.")

;; ---------------------------------------------------------------------------
;; Org-transclusion face colors
;; ---------------------------------------------------------------------------
;; Subtle background tints to distinguish transcluded content.

(defvar gruber-themes-dark-transclusion-colors
  '((org-transclusion . (:background "#1c1a22" :extend t))   ; Subtle purple tint
    (org-transclusion-fringe . (:foreground "#9e95c7" :background unspecified)))
  "Transclusion face colors for gruber-darker theme.")

(defvar gruber-themes-light-transclusion-colors
  '((org-transclusion . (:background "#f5f2f8" :extend t))   ; Subtle purple tint
    (org-transclusion-fringe . (:foreground "#6a5a8e" :background unspecified)))
  "Transclusion face colors for gruber-lighter theme.")

;; ---------------------------------------------------------------------------
;; Code face colors — variables & methods
;; ---------------------------------------------------------------------------
;; The stock gruber faces render variable names / property accesses near-white
;; (#f4f4ff), which washes out against the default text.  Recolour the
;; identifier faces along VSCode semantic lines so call sites, variables and
;; types read distinctly.  These are GLOBAL (every prog mode); the fuller VS
;; Code "2026 Dark" palette (red keywords, mauve functions, …) is applied
;; buffer-locally to Python only — see `aj/vscode-2026' in org-config.el — so
;; it doesn't bleed into Elisp/shell/etc.
;;   - variable *bindings* (assignment targets / params) → deeper blue
;;   - variable *uses* / properties                      → light blue
;;   - functions / methods (defs and calls)              → yellow
;;   - classes / types                                   → teal

;; `defconst' (not `defvar') so editing these + `C-c R' actually re-applies —
;; `defvar' is a no-op once the symbol is bound, which would silently keep the
;; old palette on reload.
(defconst gruber-themes-dark-code-colors
  '((font-lock-variable-name-face  . (:foreground "#569cd6"))  ; bindings — deeper blue
    (font-lock-variable-use-face   . (:foreground "#9cdcfe"))  ; uses — VSCode light blue
    (font-lock-property-name-face  . (:foreground "#9cdcfe"))
    (font-lock-property-use-face   . (:foreground "#9cdcfe"))
    (font-lock-function-name-face  . (:foreground "#dcdcaa"))  ; VSCode function yellow
    (font-lock-function-call-face  . (:foreground "#dcdcaa"))
    (font-lock-type-face           . (:foreground "#4ec9b0"))  ; VSCode class/type teal
    ;; Crisp base text inside src blocks.  `org-block' inherits `shadow'
    ;; (#52494e), so in the inline block view every token without its own
    ;; font-lock colour — commas, periods, operators, numbers — falls back to
    ;; that grey (they look fine under `C-c '', which has no `org-block').  Pin
    ;; the foreground to the default so nothing in a block renders grey.
    (org-block                     . (:foreground "#e4e4ef"))
    ;; Bracket-pair colours, cycling gold/orchid/blue by nesting depth
    ;; (VSCode dark+ bracket-pair-colorization).  Applied to the
    ;; `rainbow-delimiters' depth faces; see package-config.el.
    (rainbow-delimiters-depth-1-face   . (:foreground "#ffd700"))  ; gold
    (rainbow-delimiters-depth-2-face   . (:foreground "#da70d6"))  ; orchid
    (rainbow-delimiters-depth-3-face   . (:foreground "#179fff"))  ; light blue
    (rainbow-delimiters-depth-4-face   . (:foreground "#ffd700"))
    (rainbow-delimiters-depth-5-face   . (:foreground "#da70d6"))
    (rainbow-delimiters-depth-6-face   . (:foreground "#179fff"))
    (rainbow-delimiters-depth-7-face   . (:foreground "#ffd700"))
    (rainbow-delimiters-depth-8-face   . (:foreground "#da70d6"))
    (rainbow-delimiters-depth-9-face   . (:foreground "#179fff"))
    (rainbow-delimiters-unmatched-face . (:foreground "#ff5555"))  ; stray paren — red
    (rainbow-delimiters-mismatched-face . (:foreground "#ff5555")))
  "Variable/method face colors for gruber-darker theme.")

(defconst gruber-themes-light-code-colors
  '((font-lock-variable-name-face  . (:foreground "#001080"))  ; bindings — deep navy
    (font-lock-variable-use-face   . (:foreground "#005cc5"))  ; uses — readable blue
    (font-lock-property-name-face  . (:foreground "#005cc5"))
    (font-lock-property-use-face   . (:foreground "#005cc5"))
    (font-lock-function-name-face  . (:foreground "#795e26"))  ; VSCode light function
    (font-lock-function-call-face  . (:foreground "#795e26"))
    (font-lock-type-face           . (:foreground "#267f99"))  ; VSCode light type teal
    ;; Crisp base text inside src blocks — pin `org-block' to the light
    ;; default foreground so no in-block token falls back to `shadow' grey.
    (org-block                     . (:foreground "#2e2e2e"))
    ;; Bracket-pair colours for light bg — same gold/orchid/blue cycle,
    ;; darkened for contrast against the lighter background.
    (rainbow-delimiters-depth-1-face   . (:foreground "#b58900"))  ; gold
    (rainbow-delimiters-depth-2-face   . (:foreground "#a626a4"))  ; orchid/purple
    (rainbow-delimiters-depth-3-face   . (:foreground "#005cc5"))  ; blue
    (rainbow-delimiters-depth-4-face   . (:foreground "#b58900"))
    (rainbow-delimiters-depth-5-face   . (:foreground "#a626a4"))
    (rainbow-delimiters-depth-6-face   . (:foreground "#005cc5"))
    (rainbow-delimiters-depth-7-face   . (:foreground "#b58900"))
    (rainbow-delimiters-depth-8-face   . (:foreground "#a626a4"))
    (rainbow-delimiters-depth-9-face   . (:foreground "#005cc5"))
    (rainbow-delimiters-unmatched-face . (:foreground "#d70000"))  ; stray paren — red
    (rainbow-delimiters-mismatched-face . (:foreground "#d70000")))
  "Variable/method face colors for gruber-lighter theme.")

(defun gruber-themes--get-current-variant ()
  "Return the current gruber theme variant: 'dark, 'light, or nil."
  (let ((theme (car custom-enabled-themes)))
    (cond
     ((eq theme 'gruber-darker) 'dark)
     ((eq theme 'gruber-lighter) 'light)
     (t nil))))

(defun gruber-themes--apply-headings ()
  "Apply ergonomic heading colors based on current theme variant."
  (let* ((variant (gruber-themes--get-current-variant))
         (colors (pcase variant
                   ('dark gruber-themes-dark-heading-colors)
                   ('light gruber-themes-light-heading-colors)
                   (_ nil))))
    (when colors
      ;; Document title
      (let ((title-spec (alist-get 'document-title colors)))
        (apply #'set-face-attribute 'org-document-title nil
               :height (if gruber-themes-headings-scale 1.4 1.0)
               (gruber-themes--plist-to-args title-spec)))

      ;; Outline levels 1-8
      (dolist (level '(1 2 3 4 5 6 7 8))
        (let* ((face (intern (format "outline-%d" level)))
               (spec (alist-get (intern (format "outline-%d" level)) colors))
               (height (if gruber-themes-headings-scale
                           (pcase level
                             (1 1.3)
                             (2 1.2)
                             (3 1.1)
                             (_ 1.0))
                         1.0)))
          (when spec
            (apply #'set-face-attribute face nil
                   :height height
                   (gruber-themes--plist-to-args spec))))))))

(defun gruber-themes--plist-to-args (plist)
  "Convert PLIST to a flat list of keyword arguments."
  (let (result)
    (while plist
      (push (car plist) result)
      (push (cadr plist) result)
      (setq plist (cddr plist)))
    (nreverse result)))

(defun gruber-themes--apply-transclusion ()
  "Apply transclusion face colors based on current theme variant."
  (let* ((variant (gruber-themes--get-current-variant))
         (colors (pcase variant
                   ('dark gruber-themes-dark-transclusion-colors)
                   ('light gruber-themes-light-transclusion-colors)
                   (_ nil))))
    (when (and colors (featurep 'org-transclusion))
      (dolist (entry colors)
        (let ((face (car entry))
              (spec (cdr entry)))
          (when (facep face)
            (apply #'set-face-attribute face nil
                   (gruber-themes--plist-to-args spec))))))))

(defun gruber-themes--apply-code-faces ()
  "Apply variable/method face colors based on current theme variant."
  (let* ((variant (gruber-themes--get-current-variant))
         (colors (pcase variant
                   ('dark gruber-themes-dark-code-colors)
                   ('light gruber-themes-light-code-colors)
                   (_ nil))))
    (when colors
      (dolist (entry colors)
        (let ((face (car entry))
              (spec (cdr entry)))
          (when (facep face)
            (apply #'set-face-attribute face nil
                   (gruber-themes--plist-to-args spec))))))))

(defun gruber-themes--on-theme-change (&optional _theme)
  "Hook function to apply customizations when theme changes."
  (gruber-themes--apply-headings)
  (gruber-themes--apply-transclusion)
  (gruber-themes--apply-code-faces))

;;;###autoload
(defun gruber-toggle ()
  "Toggle between gruber-darker and gruber-lighter themes."
  (interactive)
  (let ((current (gruber-themes--get-current-variant)))
    (pcase current
      ('dark
       (disable-theme 'gruber-darker)
       (load-theme 'gruber-lighter t)
       (message "Switched to gruber-lighter"))
      ('light
       (disable-theme 'gruber-lighter)
       (load-theme 'gruber-darker t)
       (message "Switched to gruber-darker"))
      (_
       ;; Default to dark if no gruber theme active
       (load-theme 'gruber-darker t)
       (message "Loaded gruber-darker")))))

;;;###autoload
(defun gruber-load-darker ()
  "Load the gruber-darker theme."
  (interactive)
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme 'gruber-darker t))

;;;###autoload
(defun gruber-load-lighter ()
  "Load the gruber-lighter theme."
  (interactive)
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme 'gruber-lighter t))

;; Register the hook
(add-hook 'enable-theme-functions #'gruber-themes--on-theme-change)

;; `rainbow-delimiters' usually loads *after* the theme is applied at startup
;; (it's deferred until the first prog-mode buffer), so its depth faces don't
;; exist yet when `gruber-themes--apply-code-faces' first runs and are skipped
;; by the `facep' guard — leaving rainbow-delimiters' own default colours.
;; Re-apply once the faces actually exist.
(with-eval-after-load 'rainbow-delimiters
  (gruber-themes--apply-code-faces))

(provide 'gruber-themes)
;;; gruber-themes.el ends here
