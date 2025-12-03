;; -*- lexical-binding: t; -*-
(setq lsp-java-java-path
      (or (executable-find "java") ; if your PATH already has 17+/21+
          "/opt/homebrew/opt/openjdk@21/bin/java"))
;; Optional but helpful for jdtls:
(when (file-directory-p "/opt/homebrew/opt/openjdk@21")
  (setenv "JAVA_HOME" (file-truename "/opt/homebrew/opt/openjdk@21")))

;; --- JDT LS locations: make them explicit & consistent -------------
(setq lsp-server-install-dir (expand-file-name "~/.emacs.d/lsp-servers/"))
(setq lsp-java-server-install-dir (expand-file-name "eclipse.jdt.ls/" lsp-server-install-dir))
(setq lsp-java-workspace-dir (expand-file-name "~/.emacs.d/workspace/")) ;; where projects’ metadata goes


;; macOS GUI Emacs: import PATH so java is found
(when (memq window-system '(mac ns))
  (when (require 'exec-path-from-shell nil t)
    (exec-path-from-shell-initialize)))

;;;; --- lsp-mode perf essentials ---------------------------------
(setq read-process-output-max (* 4 1024 1024))   ;; 4MB
(setq gc-cons-threshold (* 128 1024 1024))
(setq gc-cons-percentage 0.3)

(setq lsp-use-plists nil)

(setq lsp-log-io nil
      lsp-file-watch-threshold 5000
      lsp-enable-file-watchers t)

;; Keep LSP completions as plain text (no snippet expansion)

;; Java: don't insert guessed method arguments/placeholders
(with-eval-after-load 'lsp-java
  (setq lsp-java-completion-guess-method-arguments nil))

;;;; Calm defaults for lsp + jdtls
;; Back off while typing; only talk to server after a pause.
(setq lsp-idle-delay 0.6)                   ; default 0.5 → a touch longer
(setq lsp-diagnostic-delay 0.6)             ; delay publishing diagnostics

;; Keep completions simple and cheaper.
(setq lsp-enable-snippet nil)               ; you already turned this off
(setq lsp-completion-enable-additional-text-edit nil)
(setq lsp-signature-auto-activate nil)      ; no live signature popups while typing

;; Disable heavy, non-essential features.
(setq lsp-semantic-tokens-enable nil)       ; token streaming can be expensive
(setq lsp-lens-enable nil)                  ; code lenses off
(setq lsp-inlay-hints-enable nil)           ; inlay hints off

;; File watching can be costly in big trees.
(setq lsp-enable-file-watchers t)
(setq lsp-file-watch-threshold 5000)        ; 5k files; lower if needed

;; jdtls-specific: stop background auto-builds & arg guessing.
(with-eval-after-load 'lsp-java
  (setq lsp-java-autobuild-enabled nil)               ; 🔥 disable auto builds
  (setq lsp-java-completion-guess-method-arguments nil)
  ;; If you’re not using Gradle/Maven here, also disable their auto-imports:
  ;; (setq lsp-java-import-gradle-enabled nil)
  ;; (setq lsp-java-maven-download-sources nil)
  )

;; Company: don’t complete on every keystroke; make it deliberate.
(with-eval-after-load 'company
  (setq company-idle-delay 0.25            ; or nil to require M-TAB/C-M-i
        company-minimum-prefix-length 2))


;; Core LSP + Java
(require 'lsp-mode)
(setq lsp-keymap-prefix "C-c l")
(add-hook 'java-mode-hook #'lsp-deferred)

(with-eval-after-load 'lsp-mode
  (require 'lsp-java)
  (setq lsp-java-format-enabled t
        lsp-java-save-actions-organize-imports t)
  (with-eval-after-load 'lsp-java
    (require 'dap-java)))

;; Org Babel: enable Java execution
(with-eval-after-load 'org
  (require 'ob-java)
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((java . t))))

;;;; LSP in Org java src blocks -----------------------------------
;; Make Org's java edit buffer look like a real file so jdtls can attach.
(with-eval-after-load 'org
  (defun ab/org-babel-edit-prep:java (_info)
    (let* ((org-dir (expand-file-name
                     (or (and (buffer-file-name)
                              (file-name-directory (buffer-file-name)))
                         default-directory)))
           (fake-file (expand-file-name ".org-src-OrgJava.java" org-dir)))
      (make-directory (file-name-directory fake-file) t)
      (setq-local default-directory org-dir)
      (setq-local buffer-file-name fake-file)
      (setq-local lsp-buffer-uri (lsp--path-to-uri fake-file))
      ;; Ensure the folder is a workspace (and thus not blacklisted)
      (when (and (fboundp 'lsp-workspace-root)
                 (null (lsp-workspace-root org-dir)))
        (lsp-workspace-folders-add org-dir))
      (unless (bound-and-true-p lsp-mode)
        (lsp-deferred))))
  (defalias 'org-babel-edit-prep:java #'ab/org-babel-edit-prep:java))

(message "%s" (shell-command-to-string (format "%s -version" lsp-java-java-path)))


(defun ab/lsp-quick-off ()
  "Hard stop LSP in this buffer (and its workspace)."
  (interactive)
  (when (bound-and-true-p lsp-mode)
    (lsp-disconnect)
    (lsp-workspace-shutdown)
    (message "LSP paused.")))

(defun ab/lsp-quick-on ()
  "Restart LSP in this buffer."
  (interactive)
  (lsp-deferred)
  (message "LSP resumed."))

(global-set-key (kbd "C-c C-l p") #'ab/lsp-quick-off)  ; p = pause
(global-set-key (kbd "C-c C-l r") #'ab/lsp-quick-on)   ; r = resume

(provide 'java-lsp)
