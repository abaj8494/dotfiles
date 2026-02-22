;;; anki-config.el --- Anki-editor configuration and customizations -*- lexical-binding: t; -*-

;;; Commentary:
;; This file configures anki-editor with custom functionality for
;; HTML export, image handling, and Cloze note management.

;;; Code:

(require 'anki-editor)
(require 'ansi-color)
(require 'ob-core)
(require 'cl-lib)

;; ---------------------------------------------------------------------------
;; Anki Editor Mode Auto-Enable
;; ---------------------------------------------------------------------------

(defun my/ensure-anki-editor-mode (note)
  "Ensure `anki-editor-mode' is enabled before pushing notes."
  (unless anki-editor-mode
    (anki-editor-mode 1)))
(advice-add #'anki-editor--push-note :before #'my/ensure-anki-editor-mode)

;; ---------------------------------------------------------------------------
;; Strip ANSI Codes from Babel Results
;; ---------------------------------------------------------------------------

(defun aj/org-babel-strip-ansi-from-result ()
  "Strip ANSI colour escape codes from the last Org Babel result.

Only does anything when `anki-editor-mode' is enabled in the current buffer."
  (when (and (derived-mode-p 'org-mode)
             (bound-and-true-p anki-editor-mode))
    (let ((beg (org-babel-where-is-src-block-result nil nil)))
      (when beg
        (save-excursion
          (goto-char beg)
          ;; Skip the `#+RESULTS:' line
          (forward-line 1)
          (let ((content-beg (point))
                (content-end (org-babel-result-end)))
            (ansi-color-filter-region content-beg content-end)))))))

(add-hook 'org-babel-after-execute-hook #'aj/org-babel-strip-ansi-from-result)

;; ---------------------------------------------------------------------------
;; Patch Anki-Editor Image Handling
;; ---------------------------------------------------------------------------

(with-eval-after-load 'anki-editor
  ;; If we had an older version of this advice, remove it first to avoid stacking.
  (ignore-errors
    (advice-remove 'org-html-link #'anki-editor--ox-html-link))

  (defun anki-editor--ox-html-link (oldfun link desc info)
    "Export Org file links as Anki media (images & audio) when :anki-editor-mode is set."
    (let* ((type     (org-element-property :type link))
           (raw-path (org-element-property :path link)))
      (if (and (plist-get info :anki-editor-mode)
               (string= type "file"))
          (let* ((abs-path (expand-file-name
                            raw-path
                            (or (and (buffer-file-name)
                                     (file-name-directory (buffer-file-name)))
                                default-directory)))
                 (stored   (anki-editor-api--store-media-file abs-path)))
            (cond
             ;; Audio file → [sound:...] syntax
             ((cl-some (lambda (ext)
                         (string-suffix-p ext stored t))
                       anki-editor--audio-extensions)
              (format "[sound:%s]" stored))

             ;; Inline image → <img src="...">
             ((org-export-inline-image-p
               link (plist-get info :html-inline-image-rules))
              (format "<img src=\"%s\" alt=\"%s\" />"
                      stored
                      (file-name-sans-extension
                       (file-name-nondirectory raw-path))))

             ;; Other file links → fall back to default HTML behavior
             (t
              (funcall oldfun link desc info))))
        ;; Non-file links → just use Org's default HTML exporter
        (funcall oldfun link desc info))))

  (advice-add 'org-html-link :around #'anki-editor--ox-html-link))

;; ---------------------------------------------------------------------------
;; HTML Source Block Export for Anki
;; ---------------------------------------------------------------------------

(with-eval-after-load 'ox-html
  (defun aj/org-html-src-block-to-pre-code (text backend info)
    "Wrap HTML src blocks in <pre><code> for highlight.js / Anki.

TEXT is the HTML for a single src-block."
    (if (and (org-export-derived-backend-p backend 'html)
             (string-match "\\`<pre class=\"src src-\\([^\"\n]+\\)\">" text))
        (let* ((lang (match-string 1 text))
               (body-start (match-end 0))
               (body-end   (string-match "</pre>\\'" text))
               (body       (substring text body-start body-end)))
          (format "<pre><code class=\"language-%s\">%s</code></pre>"
                  lang body))
      text))

  (add-to-list 'org-export-filter-src-block-functions
               #'aj/org-html-src-block-to-pre-code))

;; ---------------------------------------------------------------------------
;; Allow Duplicates in Specific Decks
;; ---------------------------------------------------------------------------

(with-eval-after-load 'anki-editor
  (defun aj/anki-editor-api--note-allow-dups-for-selected-decks (orig note)
    "Wrap `anki-editor-api--note' to allow duplicates in specific decks."
    (let* ((res  (funcall orig note))
           (deck (anki-editor-note-deck note)))
      (when (and deck
                 (member deck '("Default::people"
                                "Default::artworks")))
        (let ((options (plist-get res :options)))
          ;; Force :allowDuplicate t for these decks only
          (setq options (plist-put options :allowDuplicate t))
          (plist-put res :options options)))
      res))

  (advice-add 'anki-editor-api--note :around
              #'aj/anki-editor-api--note-allow-dups-for-selected-decks))

;; ---------------------------------------------------------------------------
;; Prepend Heading into Cloze Text Fields
;; ---------------------------------------------------------------------------

(with-eval-after-load 'anki-editor
  ;; Core helper: operate on the *current note* (the heading with ANKI properties)
  (defun aj/anki--prepend-heading-into-this-cloze-text ()
    "For the current note, prepend heading into the Text field
if this is a Cloze note with :ANKI_PREPEND_HEADING: t."
    (save-excursion
      (save-restriction
        (widen)
        ;; Make sure we are at the note's main heading (** 200, Number of Islands ...)
        (org-back-to-heading t)
        (let* ((note-type (org-entry-get nil "ANKI_NOTE_TYPE" t))
               (prepend   (org-entry-get nil "ANKI_PREPEND_HEADING" t)))
          (when (and note-type prepend
                     (string-match-p "cloze" (downcase note-type))
                     (string= (downcase prepend) "t"))
            (let* ((heading    (org-get-heading t t t t)) ; "200, Number of Islands"
                   (note-level (org-outline-level))
                   (text-level (1+ note-level))
                   (text-stars (make-string text-level ?*))
                   (text-re    (concat "^" text-stars " Text\\b")))
              (org-narrow-to-subtree)
              (goto-char (point-min))
              (when (re-search-forward text-re nil t)
                ;; Now at the *** Text headline
                (forward-line 1)
                (let ((subtree-end (save-excursion (org-end-of-subtree t t))))
                  ;; skip blank lines after *** Text
                  (while (and (< (point) subtree-end)
                              (looking-at "^[ \t]*$"))
                    (forward-line 1))
                  (if (>= (point) subtree-end)
                      ;; Empty Text subtree: just insert heading
                      (insert heading "\n\n")
                    (let* ((ls   (line-beginning-position))
                           (le   (line-end-position))
                           (line (buffer-substring-no-properties ls le)))
                      (cond
                       ;; already has heading
                       ((string= line heading) nil)
                       ;; literal 'Text' placeholder → replace it
                       ((string-match-p "^Text[ \t]*$" line)
                        (delete-region ls (min (1+ le) subtree-end))
                        (insert heading "\n\n"))
                       ;; otherwise, insert heading above current first content line
                       (t
                        (beginning-of-line)
                        (insert heading "\n\n"))))))
              (widen))))))))

  ;; Public command: current note vs whole file
  (defun aj/anki-prepend-heading-into-cloze-text (&optional scope)
    "Prepend headings into Cloze Text fields.

Without prefix arg, operate only on the current note.
With prefix arg (C-u), process all notes in the file that have
ANKI_NOTE_TYPE=\"Cloze\" and ANKI_PREPEND_HEADING=\"t\"."
    (interactive "P")
    (if scope
        ;; whole file
        (org-map-entries
         #'aj/anki--prepend-heading-into-this-cloze-text
         "+ANKI_NOTE_TYPE=\"Cloze\"+ANKI_PREPEND_HEADING=\"t\""
         'file)
      ;; just current note
      (aj/anki--prepend-heading-into-this-cloze-text)))

  ;; Wrap push commands so they always run the fixer first
  (defun aj/anki-push-notes-with-heading (&optional arg)
    "Prepend headings into Cloze Text fields, then push notes."
    (interactive "P")
    (aj/anki-prepend-heading-into-cloze-text t) ; whole file
    (let ((current-prefix-arg arg))
      (call-interactively #'anki-editor-push-notes)))

  (defun aj/anki-push-note-at-point-with-heading (&optional arg)
    "Prepend heading into this Cloze note's Text field, then push it."
    (interactive "P")
    (aj/anki-prepend-heading-into-cloze-text nil) ; current note
    (let ((current-prefix-arg arg))
      (call-interactively #'anki-editor-push-note-at-point)))) ; Close call-interactively, let, defun

;; ---------------------------------------------------------------------------
;; Async Push Notes
;; ---------------------------------------------------------------------------

(defvar aj/anki-push-async-process nil
  "Current async process for anki-editor-push-notes.")

(defvar aj/anki-push-log-interval 200
  "Log progress every N notes during push operations.")

(defun aj/anki-push-notes-async (&optional scope)
  "Push notes to Anki asynchronously with batch logging.
SCOPE is as in `anki-editor-push-notes'."
  (interactive (list (cond
                      ((region-active-p) 'region)
                      ((equal current-prefix-arg '(4)) 'tree)
                      ((equal current-prefix-arg '(16)) 'file)
                      ((equal current-prefix-arg '(64)) 'agenda)
                      (t nil))))
  (when (and aj/anki-push-async-process
             (process-live-p aj/anki-push-async-process))
    (user-error "Anki push already in progress"))
  (let ((file (buffer-file-name)))
    (unless file
      (user-error "Buffer must be visiting a file"))
    ;; Run heading prepend synchronously first
    (aj/anki-prepend-heading-into-cloze-text t)
    (save-buffer)
    ;; Count notes to push
    (let ((note-count 0))
      (save-excursion
        (anki-editor-map-note-entries
         (lambda () (cl-incf note-count))
         nil scope))
      (if (= note-count 0)
          (message "No notes to push")
        ;; Confirm
        (when (yes-or-no-p (format "Push %d notes to Anki asynchronously? " note-count))
          (message "Anki: pushing %d notes asynchronously..." note-count)
          (setq aj/anki-push-async-process
                (async-start
                 `(lambda ()
                    ;; Auto-accept prompts
                    (fset 'yes-or-no-p (lambda (&rest _) t))
                    (fset 'y-or-n-p (lambda (&rest _) t))
                    (message "[anki-push-async] Starting...")
                    ;; Load config
                    (setq user-emacs-directory ,(expand-file-name user-emacs-directory))
                    (load ,(expand-file-name "init.el" user-emacs-directory) nil t)
                    (message "[anki-push-async] Config loaded. Opening file...")
                    ;; Open file
                    (find-file ,file)
                    (message "[anki-push-async] Pushing %d notes..." ,note-count)
                    ;; Override progress display with batch logging
                    (advice-add 'anki-editor--draw-progress-bar
                                :override
                                (lambda (title count total &rest _)
                                  (when (or (= count 1)
                                            (= (% count ,aj/anki-push-log-interval) 0)
                                            (= count total))
                                    (message "[anki-push-async] %s: %d/%d" title count total))))
                    (condition-case err
                        (progn
                          (anki-editor-push-notes ',scope)
                          (save-buffer)
                          (message "[anki-push-async] Done!")
                          (list 'success ,note-count))
                      (error
                       (message "[anki-push-async] ERROR: %s" (error-message-string err))
                       (list 'error (error-message-string err)))))
                 (lambda (result)
                   (setq aj/anki-push-async-process nil)
                   (pcase result
                     (`(success ,count)
                      (message "Anki: finished pushing %d notes." count)
                      (start-process "anki-done-sound" nil "afplay" "/System/Library/Sounds/Glass.aiff")
                      (when-let ((buf (find-buffer-visiting file)))
                        (with-current-buffer buf
                          (revert-buffer t t t))))
                     (`(error ,msg)
                      (start-process "anki-error-sound" nil "afplay" "/System/Library/Sounds/Basso.aiff")
                      (message "Anki push failed: %s" msg))
                     (_ (message "Anki push completed")))))))))))

(defun aj/anki-push-notes-with-heading-async (&optional arg)
  "Prepend headings into Cloze Text fields, then push notes asynchronously."
  (interactive "P")
  (let ((scope (cond
                ((region-active-p) 'region)
                ((equal arg '(4)) 'tree)
                ((equal arg '(16)) 'file)
                ((equal arg '(64)) 'agenda)
                (t nil))))
    (aj/anki-push-notes-async scope)))

;; ---------------------------------------------------------------------------
;; Anki-Editor Keybindings
;; ---------------------------------------------------------------------------

(with-eval-after-load 'org
  ;; anki-editor keybindings under "C-c a ..."
  (define-key org-mode-map (kbd "C-c a i") #'anki-editor-insert-note)
  (define-key org-mode-map (kbd "C-c a p") #'aj/anki-push-note-at-point-with-heading)
  (define-key org-mode-map (kbd "C-c a P") #'aj/anki-push-notes-with-heading-async)  ; Now async!
  (define-key org-mode-map (kbd "C-c a s") #'anki-editor-sync-collection)
  (define-key org-mode-map (kbd "C-c a m") #'anki-editor-mode)
  (define-key org-mode-map (kbd "C-c a D") #'anki-editor-delete-note-at-point)
  (define-key org-mode-map (kbd "C-c a d") #'anki-editor-set-deck)
  (define-key org-mode-map (kbd "C-c a h") #'anki-editor-toggle-prepend-heading)
  (define-key org-mode-map (kbd "C-c a c") #'anki-editor-cloze-region)
  (define-key org-mode-map (kbd "C-c a C") #'anki-editor-set-note-type))

(provide 'anki-config)
;;; anki-config.el ends here

