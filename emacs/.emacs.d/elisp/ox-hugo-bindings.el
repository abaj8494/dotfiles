;;; ox-hugo-bindings.el --- Hugo source/output toggle bindings -*- lexical-binding: t; -*-

(defun ab/dired-org-hugo-export ()
  "Export marked Org files to Hugo Markdown via ox-hugo."
  (interactive)
  (dolist (file (dired-get-marked-files))
    (with-current-buffer (find-file-noselect file)
      (when (derived-mode-p 'org-mode)
        (org-hugo-export-wim-to-md)))))


(defvar ab/notes-root (expand-file-name "~/lattice/notes/")
  "Org-roam / content source root (lattice-canonical).")
(defvar ab/hugo-content-root (expand-file-name "~/lattice/code/sites/new-site/content/")
  "Hugo markdown output root (new-site; update if new-site is cut over to lattice).")

(defun ab/toggle-hugo-source-output ()
  "Toggle between the Org source in lattice/notes and the Hugo .md output.
Also accepts the legacy /content-org/ path for files opened via the shim."
  (interactive)
  (let ((file (buffer-file-name)) target)
    (unless file
      (user-error "Current buffer is not visiting a file"))
    (cond
     ;; source (lattice/notes) -> output (.md)
     ((string-prefix-p ab/notes-root file)
      (setq target (concat ab/hugo-content-root
                           (file-name-sans-extension (substring file (length ab/notes-root)))
                           ".md")))
     ;; legacy source path via the Documents shim
     ((string-match-p "/content-org/" file)
      (setq target (replace-regexp-in-string "/content-org/\\(.*\\)\\.org$" "/content/\\1.md" file)))
     ;; output (.md) -> source (lattice/notes)
     ((string-prefix-p ab/hugo-content-root file)
      (setq target (concat ab/notes-root
                           (file-name-sans-extension (substring file (length ab/hugo-content-root)))
                           ".org"))))
    (if (and target (file-exists-p target))
        (find-file target)
      (message "Target not found: %s" target))))

(with-eval-after-load 'dired
  (define-key dired-mode-map
    (kbd "H") #'ab/dired-org-hugo-export))

;; Org mode
(with-eval-after-load 'org
  (keymap-set org-mode-map "C-c o o"
              #'ab/toggle-hugo-source-output))

;; Markdown + GFM
(with-eval-after-load 'markdown-mode
  (keymap-set markdown-mode-map "C-c o o"
              #'ab/toggle-hugo-source-output)
  (when (boundp 'gfm-mode-map)
    (keymap-set gfm-mode-map "C-c o o"
                #'ab/toggle-hugo-source-output)))

(provide 'ox-hugo-bindings)
