;;; ox-hugo-bindings.el --- Hugo source/output toggle bindings -*- lexical-binding: t; -*-

(defun ab/dired-org-hugo-export ()
  "Export marked Org files to Hugo Markdown via ox-hugo."
  (interactive)
  (dolist (file (dired-get-marked-files))
    (with-current-buffer (find-file-noselect file)
      (when (derived-mode-p 'org-mode)
        (org-hugo-export-wim-to-md)))))


(defun ab/toggle-hugo-source-output ()
  "Toggle between content-org source (.org) and content output (.md)."
  (interactive)
  (let ((file (buffer-file-name)))
    (unless file
      (user-error "Current buffer is not visiting a file"))
    (let* ((in-org (string-match-p "/content-org/" file))
           (target (if in-org
                       (replace-regexp-in-string
                        "/content-org/\\(.*\\)\\.org$"
                        "/content/\\1.md"
                        file)
                     (replace-regexp-in-string
                      "/content/\\(.*\\)\\.md$"
                      "/content-org/\\1.org"
                      file))))
      (if (and target (file-exists-p target))
          (find-file target)
        (message "Target not found: %s" target)))))

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
