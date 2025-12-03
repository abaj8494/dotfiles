;;; org-todo-logging.el --- Custom Org TODO logging in properties -*- lexical-binding: t; -*-

;;; Commentary:
;; This file implements custom TODO state change logging that keeps everything
;; inside the :PROPERTIES: drawer instead of creating LOGBOOK drawers.

;;; Code:

(require 'org)

;; ---------------------------------------------------------------------------
;; Org: keep CLOSED/notes inside :PROPERTIES:, no LOGBOOK/planning
;; ---------------------------------------------------------------------------

(with-eval-after-load 'org
  
  ;; Global defaults: stop Org from emitting planning/LOGBOOK logs on its own
  (setq org-log-done nil
        org-log-into-drawer nil
        org-log-redeadline nil
        org-log-reschedule nil
        org-log-repeat nil)

  ;; Reassert as buffer-local in every org buffer
  (add-hook 'org-mode-hook
            (lambda ()
              (setq-local org-log-done nil
                          org-log-into-drawer nil
                          org-log-redeadline nil
                          org-log-reschedule nil
                          org-log-repeat nil)))

  ;; Debug toggle
  (defvar my/org-debug nil)

  (defun my/org--dbg (fmt &rest args)
    (when my/org-debug
      (apply #'message (concat "[my/org] " fmt) args)))

  ;; Utilities
  (defun my/org--ts ()
    "Timestamp like [YYYY-MM-DD Day HH:MM]."
    (format-time-string "[%Y-%m-%d %a %H:%M]"))

  (defvar my/org-note-key "note"
    "Property key used for free-form notes inside :PROPERTIES:.")

  (defun my/org--ensure-prop-bounds ()
    "Return (BEG . END) of this heading's :PROPERTIES: block; create if missing."
    (save-excursion
      (org-back-to-heading t)
      (let ((pb (org-get-property-block nil t)))
        (unless pb
          ;; Insert after any planning lines
          (forward-line 1)
          (while (looking-at "^[ \t]*\\(CLOSED:\\|SCHEDULED:\\|DEADLINE:\\|CLOCK:\\)")
            (forward-line 1))
          (insert ":PROPERTIES:\n:END:\n")
          (setq pb (org-get-property-block nil t)))
        pb)))

  ;; PATCH: write KEY lines manually inside :PROPERTIES: (handles CLOSED)
  (defun my/org--prop-upsert-line (key value)
    "Upsert a \":KEY: VALUE\" line inside the current heading's :PROPERTIES: drawer."
    (save-excursion
      (pcase-let* ((`(,beg . ,end) (my/org--ensure-prop-bounds)))
        (let* ((case-fold-search t)
               (re (concat "^[ \t]*:" (regexp-quote key) ":[ \t]*.*$"))
               (indent (save-excursion (goto-char beg) (current-indentation)))
               (newline (format "%s:%s: %s\n" (make-string indent ?\s) key value)))
          (goto-char beg)
          (if (re-search-forward re end t)
              ;; Replace existing line
              (replace-match (string-trim-right newline) t t)
            ;; Insert just before :END:
            (goto-char end)
            (insert newline))))))

  (defun my/org--prop-set (key value)
    "Set/replace KEY line to VALUE in :PROPERTIES: (incl. CLOSED)."
    (my/org--prop-upsert-line key value))

  (defun my/org--prop-append (key value)
    "Append a KEY: VALUE line just before :END: in the drawer."
    (save-excursion
      (pcase-let ((`(,beg . ,end) (my/org--ensure-prop-bounds)))
        (goto-char end) ; beginning of :END:
        (let ((indent (save-excursion (goto-char beg) (current-indentation))))
          (insert (format "%s:%s: %s\n"
                          (make-string indent ?\s) key value))
          (my/org--dbg "Append %s: %s" key value)))))

  (defun my/org--delete-planning-closed-lines ()
    "Remove any planning CLOSED: lines under this heading."
    (save-excursion
      (org-back-to-heading t)
      (let ((end (save-excursion (org-end-of-subtree t t))))
        (forward-line 1)
        (while (re-search-forward "^[ \t]*CLOSED: \\[.+?\\][ \t]*$" end t)
          (my/org--dbg "Deleted stray planning CLOSED at %d" (line-beginning-position))
          (replace-match "" nil nil)
          (when (looking-at "^[ \t]*$")
            (delete-region (point) (line-end-position)))))))

  ;; Suppress Org's own logging while `org-todo` runs
  (defun my/org--around-org-todo-no-log (orig-fn &rest args)
    (let ((org-log-done nil)
          (org-log-into-drawer nil)
          (org-log-redeadline nil)
          (org-log-reschedule nil)
          (org-log-repeat nil)
          (org-todo-log-states nil))
      (apply orig-fn args)))
  (advice-remove 'org-todo #'my/org--around-org-todo-no-log)
  (advice-add    'org-todo :around #'my/org--around-org-todo-no-log)

  ;; After-state-change hook: write CLOSED + note inside drawer, then cleanup
  (defun my/org-after-todo-state-change ()
    ;; Be robust: fire for ANY done-state, not just exact "DONE"
    (when (and (stringp org-state)
               (member org-state org-done-keywords))
      (let* ((ts  (my/org--ts))
             (old (or org-last-state "TODO")))
        (my/org--dbg "Hook fired: %s <- %s" org-state old)
        ;; 1) CLOSED inside :PROPERTIES:
        (my/org--prop-set "CLOSED" ts)
        ;; 2) One-line state-change note inside :PROPERTIES:
        (my/org--prop-append my/org-note-key
                             (format "- State \"%s\" from \"%s\" %s"
                                     org-state old ts))
        ;; 3) Remove any planning CLOSED lines
        (my/org--delete-planning-closed-lines))))
  (remove-hook 'org-after-todo-state-change-hook #'my/org-after-todo-state-change)
  (add-hook    'org-after-todo-state-change-hook #'my/org-after-todo-state-change)

  ;; Manual quick-note: C-c C-z to append a two-line note inside drawer
  (defun my/org-add-note-as-property ()
    "Prompt for a one-line note and store it inside :PROPERTIES: as :note: lines."
    (interactive)
    (let ((txt (read-string "Note: "))
          (ts  (my/org--ts)))
      (my/org--prop-append my/org-note-key (format "- Note taken on %s \\\\" ts))
      (my/org--prop-append my/org-note-key txt)))
  (define-key org-mode-map (kbd "C-c C-z") #'my/org-add-note-as-property)

  ;; Re-assert the local overrides for any already-open Org buffers.
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (derived-mode-p 'org-mode)
        (setq-local org-log-done nil
                    org-log-into-drawer nil
                    org-log-redeadline nil
                    org-log-reschedule nil
                    org-log-repeat nil))))) ;; Close (with-eval-after-load 'org

(provide 'org-todo-logging)
;;; org-todo-logging.el ends here

