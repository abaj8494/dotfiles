;;; daily-capture.el --- Capture templates & lifecycle for dailies -*- lexical-binding: t; -*-

;;; Commentary:
;; org-capture and org-roam-dailies capture templates targeting tasks.org
;; and the daily Capture section, plus the lifecycle hooks that run after
;; finalize: cookie stripping, target-heading prompting, file repositioning
;; (week transclude / structure ensure / recurring refresh / overdue
;; bring-forward), capture jump, and move-to-recurring relocation.

;;; Code:

(require 'daily-structure)
(require 'daily-week)
(require 'daily-recurring)

(declare-function org-capture-get "org-capture")
(declare-function org-capture-goto-last-stored "org-capture")
(declare-function org-roam-capture--find-or-create-olp "org-roam-capture")
(declare-function org-roam-dailies--capture "org-roam-dailies")
(declare-function org-link-display-format "ol")
(declare-function org-end-of-subtree "org")
(declare-function org-update-statistics-cookies "org")
(declare-function org-todo "org")
(declare-function org-id-get-create "org-id")
(declare-function aj/daily-file-open-hook "daily-config")

(defvar aj/--dailies-capture-file nil)

(defvar aj/--dailies-capture-heading nil
  "Heading text of the most recent dailies capture entry.")

(defvar aj/--dailies-capture-target nil
  "Target heading for current dailies capture.
\"Capture\" = default. Otherwise, raw heading text of a Recurring child.")

;; --- Capture templates (targeting tasks.org) --- ;;

;; ---------------------------------------------------------------------------

(defun aj/tasks-goto-heading ()
  "Prompt for a top-level heading in tasks.org and go to end of its subtree.
Used as a `file+function' target for capture templates."
  (let* ((headings '())
         (_ (save-excursion
              (goto-char (point-min))
              (while (re-search-forward "^\\* \\(.+\\)" nil t)
                (let ((raw (match-string-no-properties 1)))
                  ;; Strip org links to show clean names
                  (push (replace-regexp-in-string
                         "\\[\\[[^]]*\\]\\[\\([^]]*\\)\\]\\]" "\\1" raw)
                        headings)))))
         (chosen (completing-read "Under heading: " (nreverse headings) nil t)))
    ;; Find the chosen heading and go to end of its subtree
    (goto-char (point-min))
    (catch 'found
      (while (re-search-forward "^\\* \\(.+\\)" nil t)
        (let ((raw (match-string-no-properties 1)))
          (when (string= chosen
                         (replace-regexp-in-string
                          "\\[\\[[^]]*\\]\\[\\([^]]*\\)\\]\\]" "\\1" raw))
            ;; Stay inside the subtree so org-capture inserts at child level
            (org-end-of-subtree t)
            (throw 'found t)))))))

(setq org-capture-templates
      `(("r" "recurring templates")
        ("rd" "daily task" entry (file+function ,aj/tasks-file aj/tasks-goto-heading)
         "** TODO %?\nSCHEDULED: %(format-time-string \"<%Y-%m-%d %a ++1d>\")")
        ("rw" "weekly task" entry (file+function ,aj/tasks-file aj/tasks-goto-heading)
         "** TODO %?\nSCHEDULED: %(format-time-string \"<%Y-%m-%d %a +1w>\")")
        ("rm" "monthly task" entry (file+function ,aj/tasks-file aj/tasks-goto-heading)
         "** TODO %?\nSCHEDULED: %(format-time-string \"<%Y-%m-%d %a ++1m>\")")
        ("rc" "custom schedule" entry (file+function ,aj/tasks-file aj/tasks-goto-heading)
         "** TODO %?\nSCHEDULED: %^{Schedule}")
        ("t" "deferred task (one-off)" entry (file+function ,aj/tasks-file aj/tasks-goto-heading)
         "** TODO %?\nSCHEDULED: %^{When}t")
        ("l" "ledger templates")
        ("lc" "cash expense" plain
         (file+headline ,(concat "~/lattice/2-areas/finance/beancount/ledger/aayush/"
                                 (format-time-string "%Y") ".org")
                        "Cash")
         "%(format-time-string \"%Y-%m-%d\") * \"%^{Payee}\"\n  Expenses:%^{Category|Food:Groceries|Food:Dining|Food:Takeaway|Food:Coffee|Shopping:General|Transport:Fuel|Transport:PublicTransit|Health:Medical|Entertainment:Events|Gifts|Cash|Uncategorized}  %^{Amount} AUD\n  Assets:Cash\n"
         :empty-lines 1)
        ("li" "cash income" plain
         (file+headline ,(concat "~/lattice/2-areas/finance/beancount/ledger/aayush/"
                                 (format-time-string "%Y") ".org")
                        "Cash")
         "%(format-time-string \"%Y-%m-%d\") * \"%^{Source}\"\n  Assets:Cash  %^{Amount} AUD\n  Income:%^{Category|Other|Reimbursement|Tutoring}\n"
         :empty-lines 1)))

(defun aj/capture-prompt-jump-to-ledger ()
  "After a cash expense/income capture, offer to jump to the entry."
  (when (and (not org-note-abort)
             (member (org-capture-get :key) '("lc" "li"))
             (y-or-n-p "Jump to entry? "))
    (org-capture-goto-last-stored)))

(add-hook 'org-capture-after-finalize-hook #'aj/capture-prompt-jump-to-ledger)

;; --- Capture entry tracking & jump --- ;;

;; Helper for dailies time prefix - shows time only for today's captures
(defun aj/dailies-entry-prefix ()
  "Return time prefix for today's captures, empty string otherwise."
  (let* ((capture-time (org-capture-get :default-time))
         (today (format-time-string "%Y-%m-%d"))
         (capture-date (format-time-string "%Y-%m-%d" capture-time)))
    (if (equal today capture-date)
        (format-time-string "%I:%M%p " capture-time)
      "")))

;; Track dailies file for repositioning after capture
(defvar aj/--dailies-capture-file nil)

;; Track captured entry heading for optional jump (position gets stale after buffer modifications)
(defvar aj/--dailies-capture-heading nil
  "Heading text of the newly captured dailies entry.")

(defvar aj/--dailies-capture-target nil
  "Target heading for current dailies capture.
\"Capture\" = default. Otherwise, raw heading text of a Recurring child.")

(defun aj/dailies-store-capture-marker ()
  "Store identifier of the captured entry for optional jump.
Stores heading text instead of position since buffer modifications
(separator insertion, recurring task refresh) shift positions."
  (let* ((buf (org-capture-get :buffer))
         (file (and buf (buffer-file-name buf))))
    ;; Check if this is a dailies capture
    (when (and file
               (string-match-p "/daily/[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\.org$" file))
      (setq aj/--dailies-capture-file file)
      ;; Store the heading text to search for later
      (with-current-buffer buf
        (save-excursion
          (goto-char (org-capture-get :insertion-point))
          (when (org-at-heading-p)
            (setq aj/--dailies-capture-heading
                  (org-get-heading t t t t))))))))

(defun aj/dailies-prompt-jump-to-capture ()
  "Prompt user to jump to the newly captured dailies entry.
Searches for heading text instead of using stored position, since
buffer modifications (separator insertion, recurring task refresh)
shift positions after capture."
  (when (and aj/--dailies-capture-file aj/--dailies-capture-heading)
    (let ((file aj/--dailies-capture-file)
          (heading aj/--dailies-capture-heading)
          (target (or aj/--dailies-capture-target "Capture")))
      ;; Clear all state vars
      (setq aj/--dailies-capture-file nil
            aj/--dailies-capture-heading nil
            aj/--dailies-capture-target nil)
      (when (y-or-n-p "Jump to captured entry? ")
        (switch-to-buffer (find-file-noselect file))
        (widen)
        (goto-char (point-min))
        (if (equal target "Capture")
            ;; Search under * Capture section (original behavior)
            (if (re-search-forward "^\\* Capture\\b" nil t)
                (let ((section-end (save-excursion
                                     (if (re-search-forward "^\\* " nil t)
                                         (point)
                                       (point-max)))))
                  (if (re-search-forward
                       (format "^\\*\\* .*%s" (regexp-quote heading))
                       section-end t)
                      (progn
                        (beginning-of-line)
                        (org-reveal)
                        (recenter))
                    (message "Could not find captured entry: %s" heading)))
              (message "Could not find Capture section"))
          ;; Entry was moved to Recurring — search as demoted *** heading
          (if (or (re-search-forward
                   (format "^\\*\\*\\* .*%s" (regexp-quote heading)) nil t)
                  (progn (goto-char (point-min))
                         (re-search-forward
                          (format "^\\*+ .*%s" (regexp-quote heading)) nil t)))
              (progn
                (beginning-of-line)
                (org-reveal)
                (recenter))
            (message "Could not find captured entry: %s" heading)))))))

(defun aj/dailies-track-file ()
  "Track the dailies file being captured to."
  (let ((file (buffer-file-name (org-capture-get :buffer))))
    (when (and file
               (string-match-p "/daily/[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\.org$" file))
      (setq aj/--dailies-capture-file file))))

(defun aj/dailies-get-recurring-children (buf)
  "Return alist of (display-name . raw-heading) for ** children of * Recurring in BUF.
Uses `org-link-display-format' to strip links for display."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward "^\\* Recurring\\b" nil t)
          (let ((section-end (save-excursion
                               (if (re-search-forward "^\\* " nil t)
                                   (line-beginning-position)
                                 (point-max))))
                (children nil))
            (while (re-search-forward "^\\*\\* \\(.+\\)$" section-end t)
              (let* ((raw (match-string 1))
                     (display (org-link-display-format raw)))
                (push (cons display raw) children)))
            (nreverse children)))))))

(defun aj/dailies-prompt-target-heading ()
  "Prompt user to choose target heading for dailies capture.
Offers immediate ** children of * Recurring as alternatives to Capture."
  (let ((file (buffer-file-name (org-capture-get :buffer))))
    (when (and file
               (string-match-p "/daily/[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\.org$" file))
      (let* ((buf (org-capture-get :buffer))
             (children (aj/dailies-get-recurring-children buf))
             (options (append '("Capture")
                              (mapcar #'car children)))
             (choice (completing-read "Place under: " options nil t nil nil "Capture"))
             (target (if (equal choice "Capture")
                         "Capture"
                       (or (cdr (assoc choice children)) choice))))
        (setq aj/--dailies-capture-target target)))))

(defun aj/dailies-move-capture-to-recurring (target heading)
  "Move captured entry from * Capture to ** TARGET under * Recurring.
HEADING is the captured entry's heading text. Demotes from ** to ***."
  (save-excursion
    ;; Find the entry under * Capture
    (goto-char (point-min))
    (when (re-search-forward "^\\* Capture\\b" nil t)
      (let ((capture-end (save-excursion
                           (if (re-search-forward "^\\* " nil t)
                               (line-beginning-position)
                             (point-max)))))
        (when (re-search-forward
               (format "^\\*\\* .*%s" (regexp-quote heading))
               capture-end t)
          (beginning-of-line)
          (let* ((entry-start (point))
                 (entry-end (save-excursion
                              (org-end-of-subtree t t)
                              (point)))
                 (entry-text (buffer-substring entry-start entry-end)))
            ;; Delete entry from Capture
            (delete-region entry-start entry-end)
            ;; Clean up extra blank lines left behind
            (when (and (looking-at "\n") (save-excursion (forward-line -1) (looking-at "^$")))
              (delete-char 1))
            ;; Find target under * Recurring
            (goto-char (point-min))
            (when (re-search-forward "^\\* Recurring\\b" nil t)
              (let ((recurring-end (save-excursion
                                     (if (re-search-forward "^\\* " nil t)
                                         (line-beginning-position)
                                       (point-max)))))
                (when (re-search-forward
                       (format "^\\*\\* .*%s" (regexp-quote (org-link-display-format target)))
                       recurring-end t)
                  (let ((target-bol (line-beginning-position)))
                  (org-end-of-subtree t t)
                  ;; Demote: ** → ***, *** → ****, etc.
                  (let* ((demoted (replace-regexp-in-string
                                    "^\\(\\*+\\) " "*\\1 " entry-text))
                         ;; Strip trailing separators to avoid doubles
                         (demoted (replace-regexp-in-string
                                   "\\(\n*-+\n*\\)+\\'" "\n" demoted)))
                    ;; Ensure blank line before insertion
                    (unless (bolp) (insert "\n"))
                    (unless (save-excursion (forward-line -1) (looking-at "^$"))
                      (insert "\n"))
                    (insert demoted)
                    (unless (bolp) (insert "\n")))
                  ;; Remove any ----- lines between *** siblings in this subtree
                  (save-excursion
                    (goto-char target-bol)
                    (let ((sub-end (save-excursion (org-end-of-subtree t t) (point))))
                      (while (re-search-forward "^\\*\\*\\*+ " sub-end t)
                        (save-excursion
                          (forward-line -1)
                          (while (and (> (point) (point-min))
                                      (looking-at-p "^[ \t]*$"))
                            (forward-line -1))
                          (when (looking-at-p "^-+$")
                            (let ((sep-start (line-beginning-position))
                                  (sep-end (progn (forward-line 1)
                                                  (while (looking-at-p "^[ \t]*$")
                                                    (forward-line 1))
                                                  (point))))
                              (delete-region sep-start sep-end)
                              ;; Ensure a blank line remains between siblings
                              (unless (save-excursion (forward-line -1) (looking-at-p "^[ \t]*$"))
                                (insert "\n")
                                (setq sub-end (1+ sub-end)))
                              (setq sub-end (- sub-end (- sep-end sep-start)))))))))))))))))))

(defun aj/dailies-reposition-entry ()
  "Setup daily file after capture.
Inserts week transclude, ensures heading structure, and populates content.
Entries are placed under * Capture by the capture template."
  (when aj/--dailies-capture-file
    (let ((file aj/--dailies-capture-file))
      (with-current-buffer (find-file-noselect file)
        ;; 1. Insert week transclude if not present
        ;; Check both raw directive AND rendered heading (in case transclusion already active)
        (save-excursion
          (goto-char (point-min))
          (unless (or (re-search-forward "^#\\+transclude:" nil t)
                      (progn (goto-char (point-min))
                             (re-search-forward "^\\* \\(\\[\\[id:[^]]+\\]\\[\\)?Week [0-9]+" nil t)))
            (aj/insert-week-transclude)))
        ;; 2. Ensure all headings exist in correct order (with statistics cookies)
        (aj/ensure-daily-structure)
        ;; 3. Update statistics cookies (stripped before capture, restored here)
        (org-update-statistics-cookies t)
        ;; 4. Refresh recurring tasks
        (aj/refresh-daily-recurring)
        ;; 4b. Re-run heading separators after recurring content is inserted
        ;; (recurring tasks may have displaced the separators)
        (aj/ensure-heading-separators)
        (aj/ensure-recurring-separators)
        ;; 4c. Bring forward overdue captures from previous days
        (aj/bring-forward-overdue-captures)
        ;; 4d. Bring forward overdue priority tasks from previous days' Recurring
        (aj/bring-forward-overdue-recurring)
        (aj/ensure-recurring-separators)
        ;; 4e. Re-sweep #+LATEX: \newpage. Recurring/overdue inserts splice
        ;; content between canonical newpages and their headings, orphaning
        ;; the directive — symptom seen as a stranded `#+LATEX: \newpage'
        ;; between * Recurring and ** Shrine in capture-born files.
        (aj/ensure-heading-newpages)
        ;; 5. Move captured entry if user chose a Recurring target
        (when (and aj/--dailies-capture-target
                   aj/--dailies-capture-heading
                   (not (equal aj/--dailies-capture-target "Capture")))
          (aj/dailies-move-capture-to-recurring
           aj/--dailies-capture-target
           aj/--dailies-capture-heading)
          (aj/ensure-heading-separators)
          (aj/ensure-recurring-separators)
          (org-update-statistics-cookies t))
        ;; 5b. Insert calendar content
        (save-excursion
          (goto-char (point-min))
          ;; Only insert calendar content if heading is empty
          (when (re-search-forward "^\\* Calendar\\b" nil t)
            (let ((heading-end (line-end-position))
                  (next-heading (save-excursion
                                  (forward-line 1)
                                  (if (re-search-forward "^\\* " nil t)
                                      (line-beginning-position)
                                    (point-max)))))
              ;; Check if there's no content between Calendar and next heading
              (when (< (- next-heading heading-end) 5)
                (my/insert-aj-day-calendar)))))
        ;; 6. Activate org-transclusion-mode to render the transclude
        (when (and (fboundp 'org-transclusion-mode)
                   (not (bound-and-true-p org-transclusion-mode)))
          (org-transclusion-mode 1))
        (save-buffer)))))

;; --- Statistics-cookie strip advice for OLP matching --- ;;

;; Strip statistics cookies from olp headings in daily files before org-roam
;; does heading matching, so that "* Capture [4/4]" still matches olp "Capture".
;; Cookies are restored by aj/dailies-reposition-entry after capture finalize.
(defun aj/strip-cookies-for-olp (orig-fn olp)
  "Around advice: strip statistics cookies in daily files before OLP matching."
  (when (and buffer-file-name
             (string-match-p "/daily/" buffer-file-name))
    (save-excursion
      (dolist (heading olp)
        (goto-char (point-min))
        (let ((re (format "^\\(\\*+ %s\\) \\[[0-9]*[/%%][0-9]*\\]"
                          (regexp-quote heading))))
          (when (re-search-forward re nil t)
            (replace-match (match-string 1)))))))
  (funcall orig-fn olp))

;; --- Dailies capture template --- ;;

(setq org-roam-dailies-capture-templates
      '(("d" "default" entry
         "** %(aj/dailies-entry-prefix)%?"
         :target (file+head+olp "%<%Y-%m-%d>.org"
                                "#+title: %<%Y-%m-%d> | %<%A>\n#+EXPORT_FILE_NAME: %<%Y-%m-%d>\n"
                                ("Capture"))
         :empty-lines-before 1)))

;; --- Capture-side hook suppression --- ;;

(advice-add 'org-roam-capture--find-or-create-olp :around #'aj/strip-cookies-for-olp)

;; Suppress daily-file-open-hook during org-capture to prevent side-effects
;; (e.g. bring-forward-overdue cancelling source items while capturing).
;; Only suppressed for actual captures, not goto (C-c d d) operations.
(defun aj/suppress-daily-hook-during-capture (orig-fn &rest args)
  "Advise org-capture to suppress `aj/daily-file-open-hook'."
  (let ((aj/daily-hook-suppress t))
    (apply orig-fn args)))
(advice-add 'org-capture :around #'aj/suppress-daily-hook-during-capture)

(defun aj/suppress-daily-hook-during-roam-capture (orig-fn time &optional goto-p &rest args)
  "Advise `org-roam-dailies--capture' to suppress hook only for captures, not gotos."
  (if goto-p
      (apply orig-fn time goto-p args)
    (let ((aj/daily-hook-suppress t))
      (apply orig-fn time goto-p args))))
(advice-add 'org-roam-dailies--capture :around #'aj/suppress-daily-hook-during-roam-capture)

(add-hook 'org-capture-before-finalize-hook #'aj/dailies-track-file)
(add-hook 'org-capture-before-finalize-hook #'aj/dailies-store-capture-marker)
(add-hook 'org-capture-before-finalize-hook #'aj/dailies-prompt-target-heading t)
(add-hook 'org-capture-after-finalize-hook #'aj/dailies-reposition-entry)
(add-hook 'org-capture-after-finalize-hook #'aj/dailies-prompt-jump-to-capture t)


(provide 'daily-capture)

;;; daily-capture.el ends here
