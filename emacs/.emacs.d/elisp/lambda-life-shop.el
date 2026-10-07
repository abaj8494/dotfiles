;;; lambda-life-shop.el --- Add captured shopping items to org-shop files  -*- lexical-binding: t; -*-

;;; Commentary:
;; Called by the Lambda Life service (emacsclient -e) when the phone captures
;; "buy X from <shop>".  Two writes, both inside the live buffer so nothing goes
;; stale under Emacs:
;;   list  → append "- [ ] X" under the `next shop' heading (org-shop's ad-hoc list)
;;   mark  → tick the `next' cell of the matching row in the `inventory' table
;; Returns a short string describing what happened; never prompts.

;;; Code:
(require 'org)
(require 'org-table)

(defun lambda-life-shop--goto-heading (name)
  "Move to heading NAME (case-insensitive, `-'/space alike); nil if absent."
  (goto-char (point-min))
  (let ((rx (concat "^\\*+[ \t]+" (replace-regexp-in-string "[-_ ]+" "[-_ ]+" (regexp-quote name)) "[ \t]*\\(:[^ \t]*:\\)?[ \t]*$")))
    (let ((case-fold-search t)) (re-search-forward rx nil t))))

(defun lambda-life-shop-add (file item &optional mode product heading)
  "Add ITEM to shop FILE.  MODE is \"list\" (default) or \"mark\" (PRODUCT row).
HEADING overrides the section: nil/empty means \"next shop\"; the special
value \"preamble\" appends to the bare checklist before the first heading
(the spurway.org convention)."
  (let ((buf (find-file-noselect (expand-file-name file))) (result "nothing"))
    (with-current-buffer buf
      (org-with-wide-buffer
       (cond
        ((equal mode "mark")
         (if (not (lambda-life-shop--goto-heading "inventory"))
             (setq result "no inventory heading")
           (let ((end (save-excursion (or (and (re-search-forward "^\\*" nil t) (line-beginning-position)) (point-max))))
                 (case-fold-search t) (done nil))
             (while (and (not done) (re-search-forward "^|[ \t]*\\[\\( \\|X\\)\\][ \t]*|[ \t]*\\([^|]*?\\)[ \t]*|" end t))
               (when (string= (downcase (match-string 2)) (downcase product))
                 (replace-match "X" t t nil 1)
                 (setq done t)))
             (setq result (if done (format "marked %s in inventory" product) (format "no inventory row for %s" product))))))
        ((equal heading "preamble")
         (goto-char (point-min))
         (let* ((first-heading (save-excursion (or (and (re-search-forward "^\\* " nil t) (line-beginning-position)) (point-max))))
                (last-item (save-excursion
                             (let (p) (while (re-search-forward "^[ \t]*- \\[[ X-]\\] .*\\S-.*$" first-heading t) (setq p (line-end-position))) p)))
                (line (format "- [ ] %s" (string-trim item))))
           (if (save-excursion (let ((case-fold-search t)) (re-search-forward (concat "^[ \t]*- \\[[ X]\\] " (regexp-quote (string-trim item)) "[ \t]*$") first-heading t)))
               (setq result (format "already listed: %s" item))
             (if last-item (progn (goto-char last-item) (insert "\n" line))
               (goto-char first-heading) (insert line "\n"))
             (setq result (format "added \"%s\" to the top checklist" item)))))
        (t
         (unless (lambda-life-shop--goto-heading (or (and heading (not (equal heading "")) heading) "next shop"))
           ;; create the heading before * inventory, or at the end
           (if (lambda-life-shop--goto-heading "inventory")
               (progn (beginning-of-line) (insert "* next shop\n\n\n") (forward-line -3))
             (goto-char (point-max)) (unless (bolp) (insert "\n")) (insert "\n* next shop\n") (forward-line -1))
           (lambda-life-shop--goto-heading "next shop"))
         (let* ((sec-end (save-excursion (or (and (re-search-forward "^\\*" nil t) (line-beginning-position)) (point-max))))
                (last-item (save-excursion
                             (let (p) (while (re-search-forward "^[ \t]*- \\[[ X-]\\] " sec-end t) (setq p (line-end-position))) p)))
                (line (format "- [ ] %s" (string-trim item))))
           (if (save-excursion (goto-char (line-end-position)) (let ((case-fold-search t)) (re-search-forward (concat "^[ \t]*- \\[[ X]\\] " (regexp-quote (string-trim item)) "[ \t]*$") sec-end t)))
               (setq result (format "already listed: %s" item))
             (if last-item
                 (progn (goto-char last-item) (insert "\n" line))
               (forward-line 1)
               (unless (looking-at "^[ \t]*$") (insert "\n") (forward-line -1))
               (forward-line 1)
               (insert line "\n"))
             (setq result (format "added \"%s\" under next shop" item))))))
       (when (buffer-modified-p) (save-buffer))))
    result))

(provide 'lambda-life-shop)
;;; lambda-life-shop.el ends here
