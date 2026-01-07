;;; gruber-lighter-theme.el --- Light variant of Gruber theme -*- lexical-binding: t; -*-

;; Copyright (C) 2024 Aayush Bajaj
;; Based on gruber-darker-theme by Alexey Kutepov and Jason R. Blevins

;; Author: Aayush Bajaj
;; Version: 0.1

;;; Commentary:
;;
;; A light variant of the Gruber Darker theme, designed for comfortable
;; daytime reading while maintaining the same aesthetic.

;;; Code:

(deftheme gruber-lighter
  "Gruber Lighter - a warm light theme complementing gruber-darker")

;; Warm, ergonomic light palette
(let ((gruber-lighter-fg        "#2e2e2e")
      (gruber-lighter-fg+1      "#1a1a1a")
      (gruber-lighter-fg+2      "#3d3d3d")
      (gruber-lighter-white     "#ffffff")
      (gruber-lighter-black     "#000000")
      (gruber-lighter-bg-1      "#f8f5f0")  ; Slightly darker warm
      (gruber-lighter-bg        "#faf8f5")  ; Warm cream, not pure white
      (gruber-lighter-bg+1      "#f0ede8")  ; Selection/highlight
      (gruber-lighter-bg+2      "#e5e2dd")
      (gruber-lighter-bg+3      "#d8d5d0")
      (gruber-lighter-bg+4      "#ccc9c4")
      (gruber-lighter-red-1     "#b82a2d")
      (gruber-lighter-red       "#c23035")
      (gruber-lighter-red+1     "#d63a40")
      (gruber-lighter-green     "#4a7a1c")  ; Darker green for light bg
      (gruber-lighter-yellow    "#9a6e00")  ; Darker gold for light bg
      (gruber-lighter-brown     "#8b5a2b")  ; Darker brown for comments
      (gruber-lighter-quartz    "#5a6b62")
      (gruber-lighter-niagara-2 "#d8dce6")
      (gruber-lighter-niagara-1 "#7a8a9e")
      (gruber-lighter-niagara   "#4a6090")  ; Darker blue for light bg
      (gruber-lighter-wisteria  "#6a5a8e")  ; Darker purple for light bg
      )
  (custom-theme-set-variables
   'gruber-lighter
   '(frame-background-mode (quote light)))

  (custom-theme-set-faces
   'gruber-lighter

   ;; Basic Coloring
   `(border ((t (:background ,gruber-lighter-bg+2 :foreground ,gruber-lighter-bg+4))))
   `(cursor ((t (:background ,gruber-lighter-yellow))))
   `(default ((t (:foreground ,gruber-lighter-fg :background ,gruber-lighter-bg))))
   `(fringe ((t (:background nil :foreground ,gruber-lighter-bg+4))))
   `(vertical-border ((t (:foreground ,gruber-lighter-bg+3))))
   `(link ((t (:foreground ,gruber-lighter-niagara :underline t))))
   `(link-visited ((t (:foreground ,gruber-lighter-wisteria :underline t))))
   `(match ((t (:background ,gruber-lighter-bg+2))))
   `(shadow ((t (:foreground ,gruber-lighter-bg+4))))
   `(minibuffer-prompt ((t (:foreground ,gruber-lighter-niagara :weight bold))))
   `(region ((t (:background ,gruber-lighter-bg+2 :foreground nil))))
   `(secondary-selection ((t (:background ,gruber-lighter-bg+3 :foreground nil))))
   `(trailing-whitespace ((t (:foreground ,gruber-lighter-white :background ,gruber-lighter-red))))
   `(tooltip ((t (:background ,gruber-lighter-bg+1 :foreground ,gruber-lighter-fg))))

   ;; Compilation
   `(compilation-info ((t (:foreground ,gruber-lighter-green :inherit unspecified))))
   `(compilation-warning ((t (:foreground ,gruber-lighter-brown :bold t :inherit unspecified))))
   `(compilation-error ((t (:foreground ,gruber-lighter-red))))
   `(compilation-mode-line-fail ((t (:foreground ,gruber-lighter-red :weight bold :inherit unspecified))))
   `(compilation-mode-line-exit ((t (:foreground ,gruber-lighter-green :weight bold :inherit unspecified))))

   ;; Completion
   `(completions-annotations ((t (:inherit shadow))))

   ;; Custom
   `(custom-state ((t (:foreground ,gruber-lighter-green))))

   ;; Diff
   `(diff-removed ((t (:foreground ,gruber-lighter-red :background nil))))
   `(diff-added ((t (:foreground ,gruber-lighter-green :background nil))))

   ;; Dired
   `(dired-directory ((t (:foreground ,gruber-lighter-niagara :weight bold))))
   `(dired-ignored ((t (:foreground ,gruber-lighter-quartz :inherit unspecified))))

   ;; Font Lock
   `(font-lock-builtin-face ((t (:foreground ,gruber-lighter-yellow))))
   `(font-lock-comment-face ((t (:foreground ,gruber-lighter-brown))))
   `(font-lock-comment-delimiter-face ((t (:foreground ,gruber-lighter-brown))))
   `(font-lock-constant-face ((t (:foreground ,gruber-lighter-quartz))))
   `(font-lock-doc-face ((t (:foreground ,gruber-lighter-green))))
   `(font-lock-doc-string-face ((t (:foreground ,gruber-lighter-green))))
   `(font-lock-function-name-face ((t (:foreground ,gruber-lighter-niagara))))
   `(font-lock-keyword-face ((t (:foreground ,gruber-lighter-yellow :bold t))))
   `(font-lock-preprocessor-face ((t (:foreground ,gruber-lighter-quartz))))
   `(font-lock-reference-face ((t (:foreground ,gruber-lighter-quartz))))
   `(font-lock-string-face ((t (:foreground ,gruber-lighter-green))))
   `(font-lock-type-face ((t (:foreground ,gruber-lighter-quartz))))
   `(font-lock-variable-name-face ((t (:foreground ,gruber-lighter-fg+1))))
   `(font-lock-warning-face ((t (:foreground ,gruber-lighter-red))))

   ;; Flymake
   `(flymake-errline
     ((((supports :underline (:style wave)))
       (:underline (:style wave :color ,gruber-lighter-red)
                   :foreground unspecified :background unspecified :inherit unspecified))
      (t (:foreground ,gruber-lighter-red :weight bold :underline t))))
   `(flymake-warnline
     ((((supports :underline (:style wave)))
       (:underline (:style wave :color ,gruber-lighter-yellow)
                   :foreground unspecified :background unspecified :inherit unspecified))
      (t (:foreground ,gruber-lighter-yellow :weight bold :underline t))))
   `(flymake-infoline
     ((((supports :underline (:style wave)))
       (:underline (:style wave :color ,gruber-lighter-green)
                   :foreground unspecified :background unspecified :inherit unspecified))
      (t (:foreground ,gruber-lighter-green :weight bold :underline t))))

   ;; Flyspell
   `(flyspell-incorrect
     ((((supports :underline (:style wave)))
       (:underline (:style wave :color ,gruber-lighter-red) :inherit unspecified))
      (t (:foreground ,gruber-lighter-red :weight bold :underline t))))
   `(flyspell-duplicate
     ((((supports :underline (:style wave)))
       (:underline (:style wave :color ,gruber-lighter-yellow) :inherit unspecified))
      (t (:foreground ,gruber-lighter-yellow :weight bold :underline t))))

   ;; Helm
   `(helm-candidate-number ((t (:background ,gruber-lighter-bg+3 :foreground ,gruber-lighter-yellow :bold t))))
   `(helm-ff-directory ((t (:foreground ,gruber-lighter-niagara :background ,gruber-lighter-bg :bold t))))
   `(helm-ff-executable ((t (:foreground ,gruber-lighter-green))))
   `(helm-ff-file ((t (:foreground ,gruber-lighter-fg :inherit unspecified))))
   `(helm-ff-invalid-symlink ((t (:foreground ,gruber-lighter-white :background ,gruber-lighter-red))))
   `(helm-ff-symlink ((t (:foreground ,gruber-lighter-yellow :bold t))))
   `(helm-selection-line ((t (:background ,gruber-lighter-bg+1))))
   `(helm-selection ((t (:background ,gruber-lighter-bg+2 :underline nil))))
   `(helm-source-header ((t (:foreground ,gruber-lighter-yellow :background ,gruber-lighter-bg
                                         :box (:line-width -1 :style released-button)))))

   ;; Ido
   `(ido-first-match ((t (:foreground ,gruber-lighter-yellow :bold nil))))
   `(ido-only-match ((t (:foreground ,gruber-lighter-brown :weight bold))))
   `(ido-subdir ((t (:foreground ,gruber-lighter-niagara :weight bold))))

   ;; Info
   `(info-xref ((t (:foreground ,gruber-lighter-niagara))))
   `(info-visited ((t (:foreground ,gruber-lighter-wisteria))))

   ;; Line Highlighting
   `(highlight ((t (:background ,gruber-lighter-bg+1 :foreground nil))))
   `(highlight-current-line-face ((t (:background ,gruber-lighter-bg+1 :foreground nil))))

   ;; Line numbers
   `(line-number ((t (:inherit default :foreground ,gruber-lighter-bg+4))))
   `(line-number-current-line ((t (:inherit line-number :foreground ,gruber-lighter-yellow))))

   ;; Magit
   `(magit-branch ((t (:foreground ,gruber-lighter-niagara))))
   `(magit-diff-hunk-header ((t (:background ,gruber-lighter-bg+2))))
   `(magit-diff-file-header ((t (:background ,gruber-lighter-bg+3))))
   `(magit-log-sha1 ((t (:foreground ,gruber-lighter-red))))
   `(magit-log-author ((t (:foreground ,gruber-lighter-brown))))
   `(magit-log-head-label-remote ((t (:foreground ,gruber-lighter-green :background ,gruber-lighter-bg+1))))
   `(magit-log-head-label-local ((t (:foreground ,gruber-lighter-niagara :background ,gruber-lighter-bg+1))))
   `(magit-log-head-label-tags ((t (:foreground ,gruber-lighter-yellow :background ,gruber-lighter-bg+1))))
   `(magit-log-head-label-head ((t (:foreground ,gruber-lighter-fg :background ,gruber-lighter-bg+1))))
   `(magit-item-highlight ((t (:background ,gruber-lighter-bg+1))))
   `(magit-tag ((t (:foreground ,gruber-lighter-yellow :background ,gruber-lighter-bg))))
   `(magit-blame-heading ((t (:background ,gruber-lighter-bg+1 :foreground ,gruber-lighter-fg))))

   ;; Mode Line
   `(mode-line ((t (:background ,gruber-lighter-bg+2 :foreground ,gruber-lighter-fg))))
   `(mode-line-buffer-id ((t (:background ,gruber-lighter-bg+2 :foreground ,gruber-lighter-fg+1))))
   `(mode-line-inactive ((t (:background ,gruber-lighter-bg+1 :foreground ,gruber-lighter-quartz))))

   ;; Org Mode
   `(org-agenda-structure ((t (:foreground ,gruber-lighter-niagara))))
   `(org-column ((t (:background ,gruber-lighter-bg+1))))
   `(org-column-title ((t (:background ,gruber-lighter-bg+1 :underline t :weight bold))))
   `(org-done ((t (:foreground ,gruber-lighter-green))))
   `(org-todo ((t (:foreground ,gruber-lighter-red))))
   `(org-upcoming-deadline ((t (:foreground ,gruber-lighter-yellow))))

   ;; Outline (org headings inherit from these)
   `(outline-1 ((t (:foreground ,gruber-lighter-yellow :weight bold :height 1.3))))
   `(outline-2 ((t (:foreground ,gruber-lighter-niagara :weight bold :height 1.2))))
   `(outline-3 ((t (:foreground ,gruber-lighter-green :weight bold :height 1.1))))
   `(outline-4 ((t (:foreground ,gruber-lighter-brown :weight bold))))
   `(outline-5 ((t (:foreground ,gruber-lighter-wisteria))))
   `(outline-6 ((t (:foreground ,gruber-lighter-quartz))))
   `(outline-7 ((t (:foreground ,gruber-lighter-niagara-1))))
   `(outline-8 ((t (:foreground ,gruber-lighter-fg+2))))

   ;; Search
   `(isearch ((t (:foreground ,gruber-lighter-white :background ,gruber-lighter-yellow))))
   `(isearch-fail ((t (:foreground ,gruber-lighter-white :background ,gruber-lighter-red))))
   `(isearch-lazy-highlight-face ((t (:foreground ,gruber-lighter-fg :background ,gruber-lighter-bg+3))))

   ;; Show Paren
   `(show-paren-match-face ((t (:background ,gruber-lighter-bg+3))))
   `(show-paren-mismatch-face ((t (:background ,gruber-lighter-red-1))))

   ;; Speedbar
   `(speedbar-directory-face ((t (:foreground ,gruber-lighter-niagara :weight bold))))
   `(speedbar-file-face ((t (:foreground ,gruber-lighter-fg))))
   `(speedbar-highlight-face ((t (:background ,gruber-lighter-bg+1))))
   `(speedbar-selected-face ((t (:foreground ,gruber-lighter-red))))
   `(speedbar-tag-face ((t (:foreground ,gruber-lighter-yellow))))

   ;; Which Function
   `(which-func ((t (:foreground ,gruber-lighter-wisteria))))

   ;; Whitespace
   `(whitespace-space ((t (:background ,gruber-lighter-bg :foreground ,gruber-lighter-bg+2))))
   `(whitespace-tab ((t (:background ,gruber-lighter-bg :foreground ,gruber-lighter-bg+2))))
   `(whitespace-hspace ((t (:background ,gruber-lighter-bg :foreground ,gruber-lighter-bg+3))))
   `(whitespace-line ((t (:background ,gruber-lighter-bg+1 :foreground ,gruber-lighter-red))))
   `(whitespace-newline ((t (:background ,gruber-lighter-bg :foreground ,gruber-lighter-bg+3))))
   `(whitespace-trailing ((t (:background ,gruber-lighter-red :foreground ,gruber-lighter-red))))
   `(whitespace-empty ((t (:background ,gruber-lighter-yellow :foreground ,gruber-lighter-yellow))))
   `(whitespace-indentation ((t (:background ,gruber-lighter-yellow :foreground ,gruber-lighter-red))))
   `(whitespace-space-after-tab ((t (:background ,gruber-lighter-yellow :foreground ,gruber-lighter-yellow))))
   `(whitespace-space-before-tab ((t (:background ,gruber-lighter-brown :foreground ,gruber-lighter-brown))))

   ;; tab-bar
   `(tab-bar ((t (:background ,gruber-lighter-bg+1 :foreground ,gruber-lighter-bg+4))))
   `(tab-bar-tab ((t (:background nil :foreground ,gruber-lighter-yellow :weight bold))))
   `(tab-bar-tab-inactive ((t (:background nil))))

   ;; vterm / ansi-term
   `(term-color-black ((t (:foreground ,gruber-lighter-bg+3 :background ,gruber-lighter-bg+4))))
   `(term-color-red ((t (:foreground ,gruber-lighter-red :background ,gruber-lighter-red))))
   `(term-color-green ((t (:foreground ,gruber-lighter-green :background ,gruber-lighter-green))))
   `(term-color-blue ((t (:foreground ,gruber-lighter-niagara :background ,gruber-lighter-niagara))))
   `(term-color-yellow ((t (:foreground ,gruber-lighter-yellow :background ,gruber-lighter-yellow))))
   `(term-color-magenta ((t (:foreground ,gruber-lighter-wisteria :background ,gruber-lighter-wisteria))))
   `(term-color-cyan ((t (:foreground ,gruber-lighter-quartz :background ,gruber-lighter-quartz))))
   `(term-color-white ((t (:foreground ,gruber-lighter-fg :background ,gruber-lighter-fg))))

   ;; company-mode
   `(company-tooltip ((t (:foreground ,gruber-lighter-fg :background ,gruber-lighter-bg+1))))
   `(company-tooltip-annotation ((t (:foreground ,gruber-lighter-brown :background ,gruber-lighter-bg+1))))
   `(company-tooltip-annotation-selection ((t (:foreground ,gruber-lighter-brown :background ,gruber-lighter-bg+2))))
   `(company-tooltip-selection ((t (:foreground ,gruber-lighter-fg :background ,gruber-lighter-bg+2))))
   `(company-tooltip-mouse ((t (:background ,gruber-lighter-bg+2))))
   `(company-tooltip-common ((t (:foreground ,gruber-lighter-green))))
   `(company-tooltip-common-selection ((t (:foreground ,gruber-lighter-green))))
   `(company-scrollbar-fg ((t (:background ,gruber-lighter-bg+3))))
   `(company-scrollbar-bg ((t (:background ,gruber-lighter-bg+1))))
   `(company-preview ((t (:background ,gruber-lighter-green))))
   `(company-preview-common ((t (:foreground ,gruber-lighter-green :background ,gruber-lighter-bg+1))))

   ;; Orderless
   `(orderless-match-face-0 ((t (:foreground ,gruber-lighter-yellow :weight bold))))
   `(orderless-match-face-1 ((t (:foreground ,gruber-lighter-green :weight bold))))
   `(orderless-match-face-2 ((t (:foreground ,gruber-lighter-brown :weight bold))))
   `(orderless-match-face-3 ((t (:foreground ,gruber-lighter-quartz :weight bold))))
   ))

;;;###autoload
(when load-file-name
  (add-to-list 'custom-theme-load-path
               (file-name-as-directory (file-name-directory load-file-name))))

(provide-theme 'gruber-lighter)

;; Local Variables:
;; no-byte-compile: t
;; indent-tabs-mode: nil
;; eval: (when (fboundp 'rainbow-mode) (rainbow-mode +1))
;; End:

;;; gruber-lighter-theme.el ends here
