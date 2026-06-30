;;; email-config.el --- Email configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; All accounts use notmuch for unified tag-based email
;; Gmail: lieer (Gmail API) for sync
;; Abaj/UNSW: mbsync (IMAP) for sync

;;; Code:

;; =============================================================================
;; NOTMUCH - All accounts
;; =============================================================================
(use-package notmuch
  :straight t
  :commands (notmuch notmuch-search notmuch-hello)
  :bind (("C-c m m" . notmuch)
         ("C-c m s" . email-sync-all)
         ("C-c m c" . notmuch-mua-new-mail))
  :config
  ;; Browser for opening links
  (setq browse-url-browser-function 'browse-url-default-macosx-browser
        browse-url-chrome-program "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")

  ;; HTML rendering - use xwidget-webkit if available (best fidelity)
  ;; Otherwise fall back to shr with sensible defaults
  (if (featurep 'xwidget-internal)
      (setq mm-text-html-renderer 'shr  ; shr still used, but we add webkit option
            notmuch-show-text/html-blocked-images nil)
    (setq mm-text-html-renderer 'shr
          notmuch-show-text/html-blocked-images nil))

  ;; shr settings - cleaner rendering
  (setq shr-use-colors nil              ; Ignore HTML colors, use theme instead
        shr-use-fonts nil               ; Monospace only
        shr-max-width 100               ; Wider for better layout
        shr-indentation 2
        shr-inhibit-images nil
        shr-blocked-images nil
        shr-discard-aria-hidden t       ; Cleaner output
        shr-cookie-policy nil)          ; Privacy

  ;; Better color handling for HTML emails
  (setq shr-color-visible-luminance-min 70)  ; Ensure readable contrast

  ;; Prefer HTML (renders links properly with shr)
  (setq notmuch-multipart/alternative-discouraged '("text/plain"))

  (setq notmuch-search-oldest-first nil
        notmuch-show-logo nil
        notmuch-hello-thousands-separator ","
        notmuch-fcc-dirs nil
        notmuch-archive-tags '("-inbox" "-unread")
        notmuch-message-replied-tags '("+replied")
        notmuch-message-forwarded-tags '("+forwarded"))

  ;; Saved searches - mu4e style with single keys
  (setq notmuch-saved-searches
        '(;; Quick access (like mu4e bookmarks)
          (:name "Unread" :query "tag:unread" :key "u" :sort-order newest-first)
          (:name "Today" :query "date:today" :key "t" :sort-order newest-first)
          (:name "This Week" :query "date:7d.." :key "w" :sort-order newest-first)
          ;; Inboxes
          (:name "Gmail" :query "path:gmail-lieer/** and tag:inbox" :key "g" :sort-order newest-first)
          (:name "Abaj" :query "folder:abaj/Inbox" :key "b" :sort-order newest-first)
          (:name "UNSW" :query "folder:unsw/Inbox" :key "n" :sort-order newest-first)
          (:name "School" :query "folder:unsw-school/Inbox" :key "S" :sort-order newest-first)
          ;; Gmail labels
          (:name "Starred" :query "path:gmail-lieer/** and (tag:flagged or tag:YELLOW_STAR)" :key "f" :sort-order newest-first)
          (:name "Finance" :query "path:gmail-lieer/** and tag:Finance" :key "$" :sort-order newest-first)
          (:name "Orders" :query "path:gmail-lieer/** and tag:Orders" :key "o" :sort-order newest-first)
          (:name "Sent" :query "tag:sent or folder:abaj/Sent or folder:\"unsw/Sent Items\" or folder:\"unsw-school/Sent Items\"" :key "s" :sort-order newest-first)
          (:name "Trash" :query "tag:trash" :key "x" :sort-order newest-first)))

  ;; Show counts in hello screen
  (setq notmuch-hello-sections
        '(notmuch-hello-insert-header
          notmuch-hello-insert-saved-searches
          notmuch-hello-insert-search
          notmuch-hello-insert-alltags
          notmuch-hello-insert-footer))

  ;; Show message counts
  (setq notmuch-show-empty-saved-searches nil
        notmuch-column-control 1.0)

  ;; Identity handling for composing
  (setq notmuch-identities
        '("Aayush Bajaj <aayushbajaj7@gmail.com>"
          "Aayush Bajaj <j@abaj.ai>"
          "Aayush Bajaj <z5362216@zmail.unsw.edu.au>"
          "Aayush Bajaj <aayush.bajaj@student.unsw.edu.au>"))

  ;; FCC - save sent mail. Absolute paths are required because we disable
  ;; `notmuch-maildir-use-notmuch-insert' below (see that comment for why).
  ;; With insert disabled, Fcc routes through `notmuch-maildir-fcc-file-fcc'
  ;; which checks `notmuch-maildir-fcc-dir-is-maildir-p' on the raw header
  ;; string — relative paths would get resolved against `default-directory'
  ;; (= ~), not the notmuch mailstore.
  (setq notmuch-fcc-dirs
        `(("aayushbajaj7@gmail.com" . nil)  ; Gmail saves sent automatically
          ("j@abaj.ai" . ,(expand-file-name "~/Maildir/abaj/Sent"))
          ("z5362216@zmail.unsw.edu.au" . ,(expand-file-name "~/Maildir/unsw/Sent Items"))
          ("aayush.bajaj@student.unsw.edu.au" . ,(expand-file-name "~/Maildir/unsw-school/Sent Items"))))

  ;; Disable `notmuch insert' for Fcc. The insert path calls
  ;; `notmuch-maildir-fcc--split-fcc-header' which splits on spaces — so a
  ;; folder named "Sent Items" becomes folder "Sent" + tag "Items" and the
  ;; send fails with "Insert failed: (r)etry, (c)reate folder..." prompt.
  ;; File-fcc path handles spaces correctly; `notmuch new' on the next
  ;; sync will index the written message.
  (setq notmuch-maildir-use-notmuch-insert nil)

  ;; Address completion on To:/Cc:/Bcc: from notmuch db
  (setq notmuch-address-command 'internal
        notmuch-address-use-company nil
        notmuch-address-save-filename "~/.cache/notmuch-addresses")
  (notmuch-address-setup)

  ;; TAB address completion vs corfu. `notmuch-address-setup' registers
  ;; `notmuch-address-expand-name' on `message-completion-alist', and
  ;; `message-completion-function' (the compose-buffer capf) surfaces it by
  ;; returning a *function* — message.el's legacy "completion-in-region"
  ;; protocol. But `global-corfu-mode' advises `completion--capf-wrapper'
  ;; (`corfu--capf-wrapper-advice') to only accept capfs returning a
  ;; `(beg end table . plist)' list; the function form silently fails the
  ;; pcase and gets dropped. So plain `completion-at-point' — which is what
  ;; `message-tab' calls under Emacs 30 — never reaches notmuch, and TAB on a
  ;; To:/Cc:/Bcc: line does nothing. (`notmuch-address-expand-name' itself
  ;; works fine when called directly.) Rather than disable corfu in compose
  ;; buffers (losing its body completion), gate TAB: in an address header,
  ;; call notmuch directly; elsewhere defer to the mode's normal TAB.
  (defun aj/notmuch-in-address-header-p ()
    "Non-nil if point is within a To:/Cc:/Bcc:/From:… header line."
    (and (not (message-in-body-p))
         (save-excursion
           (beginning-of-line)
           ;; climb any continuation lines to the header field start
           (while (and (looking-at-p "[ \t]") (zerop (forward-line -1))))
           (let ((case-fold-search t))
             (looking-at-p notmuch-address-completion-headers-regexp)))))

  (defun aj/compose-tab ()
    "Address-aware TAB for compose buffers.
In an address header, complete via notmuch directly (corfu drops
message.el's function-returning capf, so `completion-at-point' never
reaches it). Elsewhere defer to the buffer's normal TAB."
    (interactive)
    (if (aj/notmuch-in-address-header-p)
        (notmuch-address-expand-name)
      (if (derived-mode-p 'org-msg-edit-mode)
          (org-msg-tab)
        (message-tab))))

  (define-key notmuch-message-mode-map (kbd "TAB") #'aj/compose-tab)
  (define-key notmuch-message-mode-map (kbd "<tab>") #'aj/compose-tab)

  ;; ---------------------------------------------------------------------------
  ;; Marking system for bulk operations
  ;; ---------------------------------------------------------------------------
  (defvar-local my/notmuch-marked-threads nil
    "List of marked thread IDs in current search buffer.")
  ;; Survive `notmuch-search-refresh-view' — refresh re-runs
  ;; `notmuch-search-mode' which would otherwise wipe the list via
  ;; `kill-all-local-variables'. Without this, marks placed during a sync
  ;; would disappear the moment the sync sentinel fires its refresh.
  (put 'my/notmuch-marked-threads 'permanent-local t)

  (defun my/notmuch-restore-marks-from-db ()
    "Rebuild `my/notmuch-marked-threads' from `tag:marked' in the notmuch DB.
The +marked tag persists across Emacs restart; the lisp cache doesn't.
Running this on `notmuch-search-mode-hook' makes `d'/`a' etc. see the
marks again after a fresh start (or any other cache wipe). Source of
truth is the DB tag; the lisp var is just a cache."
    (let ((output (string-trim
                   (shell-command-to-string
                    "notmuch search --output=threads tag:marked"))))
      (setq my/notmuch-marked-threads
            (and (> (length output) 0)
                 (split-string output "\n" t)))))

  (add-hook 'notmuch-search-mode-hook #'my/notmuch-restore-marks-from-db)

  (defun my/notmuch-search-toggle-mark ()
    "Toggle mark on current thread.
Works during sync — only the bulk action (d/a/etc.) waits for sync."
    (interactive)
    (setq my/notmuch-last-tag-time (current-time))
    (let ((thread-id (notmuch-search-find-thread-id)))
      (if (member thread-id my/notmuch-marked-threads)
          (progn
            (setq my/notmuch-marked-threads (delete thread-id my/notmuch-marked-threads))
            (notmuch-search-tag '("-marked")))
        (push thread-id my/notmuch-marked-threads)
        (notmuch-search-tag '("+marked"))))
    (notmuch-search-next-thread)
    (message "%d marked%s"
             (length my/notmuch-marked-threads)
             (if (my/email-sync-in-progress-p) " (syncing — action will apply once done)" "")))

  (defun my/notmuch-search-unmark-all ()
    "Unmark all threads."
    (interactive)
    (when my/notmuch-marked-threads
      ;; Use notmuch CLI to remove marked tag efficiently
      (call-process-shell-command
       (format "notmuch tag -marked -- tag:marked"))
      (setq my/notmuch-marked-threads nil)
      (notmuch-refresh-this-buffer)
      (message "All marks cleared")))

  (defun my/notmuch-search-mark-action (tag-changes &optional next-fn)
    "Apply TAG-CHANGES to marked threads, or current if none marked."
    (if my/notmuch-marked-threads
        (let* ((count (length my/notmuch-marked-threads))
               (tags (mapconcat #'identity tag-changes " "))
               (query (mapconcat #'shell-quote-argument my/notmuch-marked-threads " or ")))
          ;; Single CLI call for all marked threads
          (shell-command-to-string (format "notmuch tag %s -- %s" tags query))
          (setq my/notmuch-marked-threads nil)
          (setq my/notmuch-pending-changes t)
          (notmuch-refresh-this-buffer)
          (message "Applied to %d threads" count))
      ;; No marks - just tag current thread
      (notmuch-search-tag tag-changes)
      (setq my/notmuch-pending-changes t)
      (when next-fn (funcall next-fn))))

  ;; ---------------------------------------------------------------------------
  ;; Keybindings for search mode (email list)
  ;; ---------------------------------------------------------------------------
  (define-key notmuch-search-mode-map (kbd "SPC") 'my/notmuch-search-toggle-mark)
  (define-key notmuch-search-mode-map (kbd "x") 'my/notmuch-search-toggle-mark)
  (define-key notmuch-search-mode-map (kbd "U") 'my/notmuch-search-unmark-all)

  (define-key notmuch-search-mode-map (kbd "d")
    (lambda ()
      "Move to trash (marked or current)"
      (interactive)
      (when (my/email-sync-in-progress-p)
        (user-error "Sync in progress, please wait"))
      (setq my/notmuch-last-tag-time (current-time))
      (if my/notmuch-marked-threads
          (my/notmuch-search-mark-action '("+trash" "-inbox" "-unread" "-marked"))
        (notmuch-search-tag '("+trash" "-inbox" "-unread"))
        (setq my/notmuch-pending-changes t)
        (notmuch-search-next-thread))))

  (define-key notmuch-search-mode-map (kbd "a")
    (lambda ()
      "Archive (marked or current)"
      (interactive)
      (when (my/email-sync-in-progress-p)
        (user-error "Sync in progress, please wait"))
      (setq my/notmuch-last-tag-time (current-time))
      (if (and my/notmuch-marked-threads (> (length my/notmuch-marked-threads) 0))
          (progn
            (message "Archiving %d marked..." (length my/notmuch-marked-threads))
            (my/notmuch-search-mark-action '("-inbox" "-unread" "-marked")))
        (notmuch-search-tag '("-inbox" "-unread"))
        (setq my/notmuch-pending-changes t)
        (notmuch-search-next-thread))))

  (define-key notmuch-search-mode-map (kbd "u")
    (lambda ()
      "Undelete if trashed, otherwise toggle unread"
      (interactive)
      (when (my/email-sync-in-progress-p)
        (user-error "Sync in progress, please wait"))
      (setq my/notmuch-last-tag-time (current-time))
      (if (member "trash" (notmuch-search-get-tags))
          (progn
            (notmuch-search-tag '("-trash" "+inbox"))
            (message "Restored from trash"))
        (notmuch-search-tag
         (if (member "unread" (notmuch-search-get-tags))
             '("-unread")
           '("+unread"))))))

  (define-key notmuch-search-mode-map (kbd "f")
    (lambda ()
      "Toggle flagged/starred"
      (interactive)
      (when (my/email-sync-in-progress-p)
        (user-error "Sync in progress, please wait"))
      (setq my/notmuch-last-tag-time (current-time))
      (notmuch-search-tag
       (if (member "flagged" (notmuch-search-get-tags))
           '("-flagged")
         '("+flagged")))))

  (define-key notmuch-search-mode-map (kbd "S")
    (lambda ()
      "Sync all email"
      (interactive)
      (email-sync-all)))

  ;; ---------------------------------------------------------------------------
  ;; Move/Label system
  ;; ---------------------------------------------------------------------------
  ;; For Gmail: tags = labels, synced via lieer
  ;; For IMAP: tags are local; to move server-side, must move file

  (defun my/notmuch-get-message-account ()
    "Determine which account the current message belongs to."
    (let ((files (notmuch-show-get-filename)))
      (cond
       ((string-match "gmail-lieer" files) 'gmail)
       ((string-match "/abaj/" files) 'abaj)
       ((string-match "/unsw-school/" files) 'school)
       ((string-match "/unsw/" files) 'unsw)
       (t nil))))

  (defun my/notmuch-search-get-account ()
    "Determine account from current search thread."
    (let ((thread-id (notmuch-search-find-thread-id)))
      (when thread-id
        (let ((files (shell-command-to-string
                      (format "notmuch search --output=files %s | head -1"
                              (shell-quote-argument thread-id)))))
          (cond
           ((string-match "gmail-lieer" files) 'gmail)
           ((string-match "/abaj/" files) 'abaj)
           ((string-match "/unsw-school/" files) 'school)
           ((string-match "/unsw/" files) 'unsw)
           (t nil))))))

  (defun my/notmuch-move-to-folder (folder)
    "Move current IMAP message to FOLDER (for abaj/unsw/school only)."
    (let* ((file (notmuch-show-get-filename))
           (account (my/notmuch-get-message-account))
           (maildir (cond
                     ((eq account 'abaj) "~/Maildir/abaj")
                     ((eq account 'unsw) "~/Maildir/unsw")
                     ((eq account 'school) "~/Maildir/unsw-school")
                     (t nil))))
      (if (not maildir)
          (message "Move only works for IMAP accounts (abaj/unsw/school)")
        (let* ((dest-dir (expand-file-name (concat folder "/cur") maildir))
               (basename (file-name-nondirectory file))
               (dest-file (expand-file-name basename dest-dir)))
          (unless (file-directory-p dest-dir)
            (make-directory dest-dir t))
          (rename-file file dest-file)
          (notmuch-refresh-this-buffer)
          (message "Moved to %s" folder)))))

  (defun my/notmuch-add-label (label)
    "Add LABEL tag to current message. For Gmail, syncs as label."
    (interactive "sLabel: ")
    (notmuch-show-tag (list (concat "+" label)))
    (setq my/notmuch-pending-changes t)
    (message "Added label: %s" label))

  (defun my/notmuch-search-add-label (label)
    "Add LABEL tag in search mode."
    (interactive "sLabel: ")
    (notmuch-search-tag (list (concat "+" label)))
    (setq my/notmuch-pending-changes t)
    (notmuch-search-next-thread)
    (message "Added label: %s" label))

  ;; Quick label shortcuts for Gmail
  (define-key notmuch-search-mode-map (kbd "l") 'my/notmuch-search-add-label)
  (define-key notmuch-search-mode-map (kbd "m f")
    (lambda () (interactive)
      (notmuch-search-tag '("+Finance" "-inbox"))
      (setq my/notmuch-pending-changes t)
      (notmuch-search-next-thread)))
  (define-key notmuch-search-mode-map (kbd "m o")
    (lambda () (interactive)
      (notmuch-search-tag '("+Orders" "-inbox"))
      (setq my/notmuch-pending-changes t)
      (notmuch-search-next-thread)))

  (define-key notmuch-search-mode-map (kbd "m i")
    (lambda () (interactive)
      (notmuch-search-tag '("+invoice-pending" "-inbox"))
      (setq my/notmuch-pending-changes t)
      (notmuch-search-next-thread)))

  (define-key notmuch-search-mode-map (kbd "m O")
    (lambda () (interactive)
      (notmuch-search-tag '("+opal-pending" "-inbox"))
      (setq my/notmuch-pending-changes t)
      (notmuch-search-next-thread)))

  (define-key notmuch-search-mode-map (kbd "m u")
    (lambda () (interactive)
      "Undo move - restore to inbox"
      (notmuch-search-tag '("+inbox" "-Finance" "-Orders" "-invoice-pending" "-opal-pending"))
      (setq my/notmuch-pending-changes t)
      (notmuch-search-next-thread)))

  (define-key notmuch-search-mode-map (kbd "m U")
    (lambda () (interactive)
      "Strip every tag from the current thread."
      (let ((tags (notmuch-search-get-tags)))
        (when tags
          (notmuch-search-tag (mapcar (lambda (tag) (concat "-" tag)) tags))
          (setq my/notmuch-pending-changes t)
          (notmuch-search-next-thread)
          (message "Cleared %d tag(s)" (length tags))))))


  ;; ---------------------------------------------------------------------------
  ;; Keybindings for show mode (reading email)
  ;; ---------------------------------------------------------------------------
  (define-key notmuch-show-mode-map (kbd "d")
    (lambda ()
      "Move to trash"
      (interactive)
      (notmuch-show-tag '("+trash" "-inbox" "-unread"))
      (notmuch-show-next-thread-show)))

  (define-key notmuch-show-mode-map (kbd "a")
    (lambda ()
      "Archive"
      (interactive)
      (notmuch-show-archive-message-then-next-or-next-thread)))

  (define-key notmuch-show-mode-map (kbd "u")
    (lambda ()
      "Undelete if trashed, otherwise toggle unread"
      (interactive)
      (if (member "trash" (notmuch-show-get-tags))
          (progn
            (notmuch-show-tag '("-trash" "+inbox"))
            (message "Restored from trash"))
        (notmuch-show-tag
         (if (member "unread" (notmuch-show-get-tags))
             '("-unread")
           '("+unread"))))))

  (define-key notmuch-show-mode-map (kbd "f")
    (lambda ()
      "Toggle flagged/starred"
      (interactive)
      (notmuch-show-tag
       (if (member "flagged" (notmuch-show-get-tags))
           '("-flagged")
         '("+flagged")))))

  (define-key notmuch-show-mode-map (kbd "S")
    (lambda ()
      "Sync all email"
      (interactive)
      (email-sync-all)))

  ;; Link navigation and opening
  (define-key notmuch-show-mode-map (kbd "TAB") 'shr-next-link)
  (define-key notmuch-show-mode-map (kbd "<backtab>") 'shr-previous-link)
  (define-key notmuch-show-mode-map (kbd "o") 'shr-browse-url)
  (define-key notmuch-show-mode-map (kbd "C-c C-o") 'browse-url-at-point)

  ;; Navigation between messages/threads (ensure defaults work)
  (define-key notmuch-show-mode-map (kbd "n") 'notmuch-show-next-open-message)
  (define-key notmuch-show-mode-map (kbd "p") 'notmuch-show-previous-open-message)
  (define-key notmuch-show-mode-map (kbd "N") 'notmuch-show-next-thread-show)
  (define-key notmuch-show-mode-map (kbd "P") 'notmuch-show-previous-thread-show)

  ;; RET should open links if on one, otherwise toggle fold
  (define-key notmuch-show-mode-map (kbd "RET")
    (lambda ()
      "Open link at point, or toggle message fold."
      (interactive)
      (if (shr-url-at-point nil)
          (shr-browse-url)
        (notmuch-show-toggle-message))))

  ;; Helper to extract HTML from email
  (defun my/notmuch-get-html-file ()
    "Extract HTML part from current email to a temp file."
    (let* ((id (notmuch-show-get-message-id))
           (temp-file (make-temp-file "notmuch-email-" nil ".html")))
      (shell-command (format "notmuch show --format=mbox %s | python3 -c \"
import email
import sys
from email.policy import default
msg = email.message_from_binary_file(sys.stdin.buffer, policy=default)
for part in msg.walk():
    if part.get_content_type() == 'text/html':
        print(part.get_content())
        break
\" > %s" (shell-quote-argument id) temp-file))
      (when (> (file-attribute-size (file-attributes temp-file)) 0)
        temp-file)))

  ;; Open email in external browser
  (defun my/notmuch-show-open-in-browser ()
    "Open current email in external browser."
    (interactive)
    (if-let ((temp-file (my/notmuch-get-html-file)))
        (browse-url (concat "file://" temp-file))
      (message "No HTML content found")))

  ;; Open email in xwidget-webkit (best fidelity, in Emacs)
  (defun my/notmuch-show-open-in-webkit ()
    "Open current email in xwidget-webkit for best rendering."
    (interactive)
    (if (featurep 'xwidget-internal)
        (if-let ((temp-file (my/notmuch-get-html-file)))
            (xwidget-webkit-browse-url (concat "file://" temp-file))
          (message "No HTML content found"))
      (message "xwidget-webkit not available, using external browser")
      (my/notmuch-show-open-in-browser)))

  (define-key notmuch-show-mode-map (kbd "O") 'my/notmuch-show-open-in-browser)
  (define-key notmuch-show-mode-map (kbd "W") 'my/notmuch-show-open-in-webkit)

  ;; Clean up notmuch faces - less visual noise
  (custom-set-faces
   '(notmuch-message-summary-face ((t (:inherit default))))
   '(notmuch-search-date ((t (:inherit default))))
   '(notmuch-search-matching-authors ((t (:inherit default))))
   '(notmuch-search-subject ((t (:inherit default))))
   '(notmuch-tag-face ((t (:inherit font-lock-comment-face))))
   '(notmuch-tag-unread ((t (:inherit font-lock-keyword-face))))
   '(notmuch-tag-flagged ((t (:inherit warning))))
   ;; shr faces - cleaner links
   '(shr-link ((t (:inherit link :underline nil))))
   '(shr-h1 ((t (:inherit variable-pitch :weight bold :height 1.2))))
   '(shr-h2 ((t (:inherit variable-pitch :weight bold :height 1.1))))
   '(shr-h3 ((t (:inherit variable-pitch :weight bold)))))

  ;; Labels in show mode
  (define-key notmuch-show-mode-map (kbd "l") 'my/notmuch-add-label)
  (define-key notmuch-show-mode-map (kbd "m f")
    (lambda () (interactive)
      (notmuch-show-tag '("+Finance" "-inbox"))
      (setq my/notmuch-pending-changes t)))
  (define-key notmuch-show-mode-map (kbd "m o")
    (lambda () (interactive)
      (notmuch-show-tag '("+Orders" "-inbox"))
      (setq my/notmuch-pending-changes t)))

  (define-key notmuch-show-mode-map (kbd "m i")
    (lambda () (interactive)
      (notmuch-show-tag '("+invoice-pending" "-inbox"))
      (setq my/notmuch-pending-changes t)))

  (define-key notmuch-show-mode-map (kbd "m O")
    (lambda () (interactive)
      (notmuch-show-tag '("+opal-pending" "-inbox"))
      (setq my/notmuch-pending-changes t)))

  (define-key notmuch-show-mode-map (kbd "m u")
    (lambda () (interactive)
      "Undo move - restore to inbox"
      (notmuch-show-tag '("+inbox" "-Finance" "-Orders" "-invoice-pending" "-opal-pending"))
      (setq my/notmuch-pending-changes t)))

  (define-key notmuch-show-mode-map (kbd "m U")
    (lambda () (interactive)
      "Strip every tag from the current message."
      (let ((tags (notmuch-show-get-tags)))
        (when tags
          (notmuch-show-tag (mapcar (lambda (tag) (concat "-" tag)) tags))
          (setq my/notmuch-pending-changes t)
          (message "Cleared %d tag(s)" (length tags))))))

  ;; Move to IMAP folder (for abaj/unsw)
  (define-key notmuch-show-mode-map (kbd "M")
    (lambda ()
      "Move IMAP message to folder."
      (interactive)
      (let ((account (my/notmuch-get-message-account)))
        (if (eq account 'gmail)
            (message "Gmail uses labels, not folders. Use 'l' to add labels.")
          (let ((folder (read-string "Move to folder: ")))
            (my/notmuch-move-to-folder folder))))))

  ;; ---------------------------------------------------------------------------
  ;; File invoices on demand (Finances pipeline)
  ;; ---------------------------------------------------------------------------
  ;; `m i' just tags +invoice-pending; the actual classify-and-file step
  ;; (file-invoices.sh) otherwise only runs on the Thursday 07:05 cron. This
  ;; runs it now. Passes --no-pull (the email is already in the local notmuch
  ;; DB, and a second `gmi pull' would fight Emacs's auto-sync for the maildir
  ;; lock) and --push (commit + push the filed PDF so it reaches
  ;; ledger.abaj.ai on its next pull, not the next hourly sync.sh).
  (defvar my/finance-file-invoices-script
    (expand-file-name "~/lattice/2-areas/finance/beancount/file-invoices.sh")
    "Path to the invoice classify-and-file script.")

  (defvar my/finance-file-invoices-process nil
    "Running file-invoices subprocess, if any.")

  (defun my/finance-file-invoices ()
    "Classify and file all invoice-pending emails via file-invoices.sh.
Runs asynchronously; output streams to *file-invoices*. On finish,
refreshes notmuch buffers so the dropped invoice-pending tag shows."
    (interactive)
    (if (and my/finance-file-invoices-process
             (process-live-p my/finance-file-invoices-process))
        (message "file-invoices already running")
      (unless (file-exists-p my/finance-file-invoices-script)
        (user-error "Not found: %s" my/finance-file-invoices-script))
      (let ((buf (get-buffer-create "*file-invoices*")))
        (with-current-buffer buf
          (let ((inhibit-read-only t)) (erase-buffer))
          (unless (derived-mode-p 'special-mode) (special-mode)))
        (message "Filing invoices...")
        (setq my/finance-file-invoices-process
              (make-process
               :name "file-invoices"
               :buffer buf
               :command (list shell-file-name shell-command-switch
                              (format "%s --no-pull --push"
                                      (shell-quote-argument
                                       my/finance-file-invoices-script)))
               :sentinel
               (lambda (proc event)
                 (when (memq (process-status proc) '(exit signal))
                   (let ((ok (and (string-match-p "finished" event)
                                  (zerop (process-exit-status proc)))))
                     (dolist (b (buffer-list))
                       (with-current-buffer b
                         (when (derived-mode-p 'notmuch-search-mode
                                               'notmuch-show-mode
                                               'notmuch-hello-mode
                                               'notmuch-tree-mode)
                           (ignore-errors (notmuch-refresh-this-buffer)))))
                     (if ok
                         (message "file-invoices: done (C-x b *file-invoices*)")
                       (message "file-invoices FAILED — see *file-invoices*")
                       (display-buffer (process-buffer proc)))))))))))

  (define-key notmuch-search-mode-map (kbd "m I") #'my/finance-file-invoices)
  (define-key notmuch-show-mode-map   (kbd "m I") #'my/finance-file-invoices)
  (define-key notmuch-tree-mode-map   (kbd "m I") #'my/finance-file-invoices)

  ;; ---------------------------------------------------------------------------
  ;; JobSync classification rotation
  ;; ---------------------------------------------------------------------------
  (defvar my/jobsync-classifications
    '("job_application" "job_response" "interview" "rejection" "offer" "follow_up" "other")
    "List of JobSync classification types in rotation order.")

  (defun my/jobsync-get-current-classification (tags)
    "Extract current jobsync/* classification from TAGS list."
    (cl-loop for tag in tags
             when (string-prefix-p "jobsync/" tag)
             return (substring tag 8)))  ; Remove "jobsync/" prefix

  (defun my/jobsync-next-classification (current)
    "Get next classification after CURRENT in rotation."
    (let* ((idx (cl-position current my/jobsync-classifications :test #'string=))
           (next-idx (if idx
                         (mod (1+ idx) (length my/jobsync-classifications))
                       0)))
      (nth next-idx my/jobsync-classifications)))

  (defun my/jobsync-has-was-tag (tags)
    "Check if TAGS already contains a jobsync-was/* tag."
    (cl-some (lambda (tag) (string-prefix-p "jobsync-was/" tag)) tags))

  (defun my/jobsync-rotate-single-thread ()
    "Rotate JobSync classification for current thread.
Returns (current . next) classification pair, or nil if no classification."
    (let* ((tags (notmuch-search-get-tags))
           (current (my/jobsync-get-current-classification tags)))
      (when current
        (let* ((next (my/jobsync-next-classification current))
               (has-was (my/jobsync-has-was-tag tags))
               (tag-changes (if has-was
                                (list (concat "-jobsync/" current)
                                      (concat "+jobsync/" next))
                              (list (concat "-jobsync/" current)
                                    (concat "+jobsync/" next)
                                    (concat "+jobsync-was/" current)))))
          (notmuch-search-tag tag-changes)
          (cons current next)))))

  (defun my/jobsync-rotate-classification-search ()
    "Rotate JobSync classification for marked threads or current thread.
If threads are marked with 'x', rotates all marked threads.
Only adds jobsync-was/<original> on the FIRST rotation to track the original classification."
    (interactive)
    (if (and my/notmuch-marked-threads (> (length my/notmuch-marked-threads) 0))
        ;; Bulk rotation for marked threads
        (let ((count 0)
              (rotations '()))
          (save-excursion
            (goto-char (point-min))
            (while (not (eobp))
              (let ((thread-id (notmuch-search-find-thread-id)))
                (when (member thread-id my/notmuch-marked-threads)
                  (let ((result (my/jobsync-rotate-single-thread)))
                    (when result
                      (cl-incf count)
                      (push result rotations)))))
              (forward-line 1)))
          ;; Clear marks
          (call-process-shell-command "notmuch tag -marked -- tag:marked")
          (setq my/notmuch-marked-threads nil)
          (notmuch-refresh-this-buffer)
          ;; Summarize what happened
          (if (= count 0)
              (message "No jobsync classifications found in marked threads")
            (let ((summary (mapcar (lambda (r) (format "%s->%s" (car r) (cdr r))) rotations)))
              (message "JobSync rotated %d: %s" count (string-join (cl-remove-duplicates summary :test #'string=) ", ")))))
      ;; Single thread rotation
      (let ((result (my/jobsync-rotate-single-thread)))
        (if result
            (message "JobSync: %s -> %s" (car result) (cdr result))
          (message "No jobsync classification on this email")))))

  (defun my/jobsync-rotate-classification-show ()
    "Rotate JobSync classification for current message in show mode.
Only adds jobsync-was/<original> on the FIRST rotation to track the original classification."
    (interactive)
    (let* ((tags (notmuch-show-get-tags))
           (current (my/jobsync-get-current-classification tags)))
      (if (not current)
          (message "No jobsync classification on this email")
        (let* ((next (my/jobsync-next-classification current))
               (has-was (my/jobsync-has-was-tag tags))
               (tag-changes (if has-was
                                (list (concat "-jobsync/" current)
                                      (concat "+jobsync/" next))
                              (list (concat "-jobsync/" current)
                                    (concat "+jobsync/" next)
                                    (concat "+jobsync-was/" current)))))
          (notmuch-show-tag tag-changes)
          (message "JobSync: %s -> %s" current next)))))

  (define-key notmuch-search-mode-map (kbd "J") 'my/jobsync-rotate-classification-search)
  (define-key notmuch-show-mode-map (kbd "J") 'my/jobsync-rotate-classification-show)

  ;; ---------------------------------------------------------------------------
  ;; Keybindings for tree mode
  ;; ---------------------------------------------------------------------------
  (define-key notmuch-tree-mode-map (kbd "d")
    (lambda ()
      "Move to trash"
      (interactive)
      (notmuch-tree-tag '("+trash" "-inbox" "-unread"))
      (notmuch-tree-next-message)))

  (define-key notmuch-tree-mode-map (kbd "a")
    (lambda ()
      "Archive"
      (interactive)
      (notmuch-tree-tag '("-inbox" "-unread"))
      (notmuch-tree-next-message)))

  (define-key notmuch-tree-mode-map (kbd "S")
    (lambda ()
      "Sync all email"
      (interactive)
      (email-sync-all)))

  (defun my/jobsync-rotate-classification-tree ()
    "Rotate JobSync classification for current message in tree mode.
Only adds jobsync-was/<original> on the FIRST rotation to track the original classification."
    (interactive)
    (let* ((tags (notmuch-tree-get-tags))
           (current (my/jobsync-get-current-classification tags)))
      (if (not current)
          (message "No jobsync classification on this email")
        (let* ((next (my/jobsync-next-classification current))
               (has-was (my/jobsync-has-was-tag tags))
               (tag-changes (if has-was
                                (list (concat "-jobsync/" current)
                                      (concat "+jobsync/" next))
                              (list (concat "-jobsync/" current)
                                    (concat "+jobsync/" next)
                                    (concat "+jobsync-was/" current)))))
          (notmuch-tree-tag tag-changes)
          (message "JobSync: %s -> %s" current next)))))

  (define-key notmuch-tree-mode-map (kbd "J") 'my/jobsync-rotate-classification-tree))

;; Route Fcc through notmuch's maildir handler (not message.el's default
;; file-save, which writes a literal file and triggers the "Insert failed:
;; (r)etry, (c)reate folder..." prompt). Kept at top level so it always
;; applies on config reload, regardless of what's loaded first.
(setq message-fcc-handler-function 'notmuch-maildir-fcc-write-buffer-to-maildir)

;; =============================================================================
;; SMTP - Per-account sending
;; =============================================================================
(use-package smtpmail
  :straight (:type built-in)
  :config
  ;; Enable debug logging for SMTP
  (setq smtpmail-debug-info t
        smtpmail-debug-verb t))

(use-package message
  :straight (:type built-in)
  :config
  ;; Send via msmtp (external sendmail). msmtp's per-account `from` fields
  ;; in ~/.msmtprc match against the envelope From — so it selects the right
  ;; account (gmail/abaj/unsw/unsw-school) and auth method (app password or
  ;; XOAUTH2) on its own. Emacs just pipes the message to stdin.
  ;;
  ;; Why not smtpmail: `smtpmail-auth-supported' is (cram-md5 plain login) —
  ;; no XOAUTH2. Office365 student tenant (Conditional Access) blocks basic
  ;; SMTP auth, so smtpmail can't reach the PGrad mailbox at all.
  (setq message-send-mail-function 'message-send-mail-with-sendmail
        sendmail-program "/opt/local/bin/msmtp"
        message-sendmail-f-is-evil nil
        message-sendmail-envelope-from 'header
        mail-specify-envelope-from t
        mail-envelope-from 'header
        message-kill-buffer-on-exit t
        ;; Don't leak "MacBook-Pro.local.mail-host-address-is-not-set" into Message-IDs
        mail-host-address "abaj.ai")

  ;; ---------------------------------------------------------------------------
  ;; Identity configuration
  ;; ---------------------------------------------------------------------------
  (defvar my/email-identities
    `(("aayushbajaj7@gmail.com"
       :name "Aayush Bajaj"
       :smtp-server "smtp.gmail.com"
       :smtp-port 465
       :smtp-stream ssl
       :fcc nil)  ; Gmail saves sent automatically
      ("j@abaj.ai"
       :name "Aayush Bajaj"
       :smtp-server "mail.abaj.ai"
       :smtp-port 465
       :smtp-stream ssl
       :fcc ,(expand-file-name "~/Maildir/abaj/Sent"))
      ("z5362216@zmail.unsw.edu.au"
       :name "Aayush Bajaj"
       :smtp-server "smtp.office365.com"
       :smtp-port 587
       :smtp-stream starttls
       :fcc ,(expand-file-name "~/Maildir/unsw/Sent Items"))
      ("aayush.bajaj@student.unsw.edu.au"
       :name "Aayush Bajaj"
       :smtp-server "smtp.office365.com"
       :smtp-port 587
       :smtp-stream starttls
       :fcc ,(expand-file-name "~/Maildir/unsw-school/Sent Items")))
    "Email identity configurations. :fcc paths are absolute —
see the `notmuch-fcc-dirs' comment above for why.")

  (defun my/email-get-identity (email)
    "Get identity config for EMAIL address."
    (assoc email my/email-identities))

  (defun my/email-extract-address (from-field)
    "Extract email address from FROM-FIELD string."
    (when from-field
      (if (string-match "<\\([^>]+\\)>" from-field)
          (match-string 1 from-field)
        (string-trim from-field))))

  ;; ---------------------------------------------------------------------------
  ;; Identity switching (C-c C-i in compose buffer)
  ;; ---------------------------------------------------------------------------
  (defun my/email-cycle-identity ()
    "Cycle through email identities, updating From, Fcc, and SMTP settings."
    (interactive)
    (unless (derived-mode-p 'message-mode 'notmuch-message-mode 'org-msg-edit-mode)
      (user-error "Not in a compose buffer"))
    (let* ((current-from (message-fetch-field "from"))
           (current-email (my/email-extract-address current-from))
           (emails (mapcar #'car my/email-identities))
           (current-idx (or (cl-position current-email emails :test #'string=) -1))
           (next-idx (mod (1+ current-idx) (length emails)))
           (next-email (nth next-idx emails))
           (next-identity (my/email-get-identity next-email))
           (next-name (plist-get (cdr next-identity) :name))
           (next-fcc (plist-get (cdr next-identity) :fcc)))
      ;; Update From header
      (save-excursion
        (message-goto-from)
        (message-beginning-of-line)
        (delete-region (point) (line-end-position))
        (insert (format "%s <%s>" next-name next-email)))
      ;; Update or add Fcc header. After `re-search-forward "^Fcc: "' point
      ;; sits at the value start; don't call `message-beginning-of-line' —
      ;; it would jump to BOL and the delete-region would swallow the
      ;; "Fcc: " prefix, leaving an orphan bare-value line.
      (save-excursion
        (goto-char (point-min))
        (if (re-search-forward "^Fcc: " nil t)
            (progn
              (delete-region (point) (line-end-position))
              (if next-fcc
                  (insert next-fcc)
                (beginning-of-line)
                (delete-region (point) (1+ (line-end-position)))))
          ;; No Fcc header, add one if needed
          (when next-fcc
            (message-goto-from)
            (end-of-line)
            (insert (format "\nFcc: %s" next-fcc)))))
      (message "Switched to: %s (SMTP: %s, Fcc: %s)"
               next-email
               (plist-get (cdr next-identity) :smtp-server)
               (or next-fcc "none"))))

  ;; ---------------------------------------------------------------------------
  ;; Pre-send validation
  ;; ---------------------------------------------------------------------------
  (defun my/email-validate-before-send ()
    "Validate email configuration before sending."
    (let* ((from (message-fetch-field "from"))
           (to (message-fetch-field "to"))
           (subject (message-fetch-field "subject"))
           (email (my/email-extract-address from))
           (identity (my/email-get-identity email))
           (fcc (message-fetch-field "fcc")))
      ;; Check for empty To
      (unless (and to (not (string-empty-p (string-trim to))))
        (user-error "No recipient (To) specified"))
      ;; Check for empty subject
      (when (or (not subject) (string-empty-p (string-trim subject)))
        (unless (yes-or-no-p "Subject is empty. Send anyway? ")
          (user-error "Send cancelled - no subject")))
      ;; Check identity
      (unless identity
        (message "WARNING: Unknown identity '%s'" email))
      ;; Check Fcc for non-Gmail
      (when (and identity
                 (plist-get (cdr identity) :fcc)
                 (not fcc))
        (message "WARNING: No Fcc header but identity expects one. Adding...")
        (save-excursion
          (message-goto-from)
          (end-of-line)
          (insert (format "\nFcc: %s" (plist-get (cdr identity) :fcc)))))
      ;; Log what we're about to do
      (message "Sending from %s via %s..."
               email
               (or (plist-get (cdr identity) :smtp-server) "UNKNOWN"))))

  (add-hook 'message-send-hook 'my/email-validate-before-send)

  ;; Expand ~/.mailrc aliases on compose. notmuch's `internal' address
  ;; completion only echoes addresses already harvested from the mail DB, so
  ;; it can't surface a contact you haven't mailed yet (e.g. a freshly-issued
  ;; UNSW address). mail-abbrevs reads ~/.mailrc and expands the alias key
  ;; (type it + a separator) to the full "Name <addr>" — independent of, and
  ;; alongside, notmuch's completion. org-msg-edit-mode keeps its headers in
  ;; the same buffer, so hook it too.
  (add-hook 'message-mode-hook #'mail-abbrevs-setup)
  (add-hook 'org-msg-edit-mode-hook #'mail-abbrevs-setup)

  ;; Bind identity cycling in message-mode
  (add-hook 'message-mode-hook
            (lambda ()
              (local-set-key (kbd "C-c C-i") 'my/email-cycle-identity)))
  (add-hook 'notmuch-message-mode-hook
            (lambda ()
              (local-set-key (kbd "C-c C-i") 'my/email-cycle-identity))))

;; =============================================================================
;; Auth
;; =============================================================================
(use-package gnutls
  :straight (:type built-in)
  :config
  (setq gnutls-algorithm-priority "NORMAL:%COMPAT"
        gnutls-min-prime-bits 1024))

(use-package auth-source
  :straight (:type built-in)
  :config
  (setq auth-sources '("~/.authinfo.gpg")))

;; Use GPG key for all encryption (single passphrase cached by gpg-agent for 24h)
;; Loopback pinentry: Emacs prompts via its own minibuffer instead of pinentry-mac.
;; Why: pinentry-mac fails to land when EPG runs from async contexts (capture
;; finalize timers, oauth2 token refresh inside org-gcal post), producing
;; "Decrypting ~/.authinfo.gpg...0%" → "Can't decrypt". gpg-agent.conf already
;; has `allow-loopback-pinentry`. gpg-agent still caches the unlocked key for 24h.
(setq epg-user-id "aayushbajaj7@gmail.com"
      epg-pinentry-mode 'loopback)

;; Configure plstore to encrypt to GPG key (used by oauth2-auto for OAuth tokens)
(require 'plstore)
(setq plstore-encrypt-to "aayushbajaj7@gmail.com")

;; =============================================================================
;; Email status tracking
;; =============================================================================
(defvar my/email-new-mail-sound "/System/Library/Sounds/Glass.aiff"
  "Sound file to play when new mail arrives. Set to nil to disable.")

(defvar my/email-job-mail-sound "/System/Library/Sounds/Hero.aiff"
  "Sound file to play when job-related mail arrives at jobs.abaj.ai.")

(defun my/email-play-sound (sound-file)
  "Play SOUND-FILE if it exists."
  (when (and sound-file (file-exists-p sound-file))
    (start-process "email-sound" nil "afplay" sound-file)))

(defun my/email-check-new-job-mail ()
  "Check if there are new jobsync-classified emails (excluding 'other') from the last 5 minutes."
  (let ((count (string-to-number
                (string-trim
                 (shell-command-to-string
                  "notmuch count 'tag:unread and date:5min.. and (tag:jobsync/job_application or tag:jobsync/job_response or tag:jobsync/interview or tag:jobsync/rejection or tag:jobsync/offer or tag:jobsync/follow_up)'")))))
    (> count 0)))

(defun my/email-play-new-mail-sound ()
  "Play sound notification for new mail.
Plays job sound if new mail to jobs.abaj.ai, otherwise regular sound."
  (if (my/email-check-new-job-mail)
      (my/email-play-sound my/email-job-mail-sound)
    (my/email-play-sound my/email-new-mail-sound)))

(defvar my/email-sync-process nil
  "Current email sync process.")

(defvar my/email-last-sync-time nil
  "Time of last email sync.")

(defvar my/notmuch-pending-changes nil
  "Non-nil if there are local tag changes not yet synced to remote.")

(defvar my/notmuch-last-tag-time nil
  "Time of last tag operation, used to prevent sync during active marking.")

(defvar my/email-unread-counts nil
  "Alist of (account . unread-count).")

(defun my/email-sync-in-progress-p ()
  "Return non-nil if an email sync subprocess is currently running.
Single source of truth for sync state — derived from the process
itself, so it can't desync from reality if a sentinel fails to fire."
  (and my/email-sync-process (process-live-p my/email-sync-process)))

(defvar my/email-account-queries
  '((gmail . "path:gmail-lieer/** and tag:inbox")
    (abaj . "folder:abaj/Inbox")
    (unsw . "folder:unsw/Inbox")
    (school . "folder:unsw-school/Inbox"))
  "Notmuch queries for each account inbox.")

(defun my/email-update-unread-count ()
  "Update the unread email counts per account from notmuch."
  (setq my/email-unread-counts
        (mapcar
         (lambda (account)
           (let* ((query (alist-get account my/email-account-queries))
                  (cmd (format "notmuch count 'tag:unread and %s'" query)))
             (cons account
                   (string-to-number
                    (string-trim
                     (shell-command-to-string cmd))))))
         '(gmail abaj unsw school))))

(defun my/email-total-unread ()
  "Return total unread count."
  (apply #'+ (mapcar #'cdr my/email-unread-counts)))

(defun my/email-open-account (account)
  "Open notmuch search for ACCOUNT."
  (let ((query (alist-get account my/email-account-queries)))
    (notmuch-search query)))

(defun my/email-make-clickable (text account)
  "Make TEXT clickable to open ACCOUNT inbox."
  (propertize text
              'face 'font-lock-keyword-face
              'mouse-face 'highlight
              'help-echo (format "mouse-1: Open %s inbox" account)
              'local-map (let ((map (make-sparse-keymap)))
                           (define-key map [mode-line mouse-1]
                             (lambda () (interactive)
                               (my/email-open-account account)))
                           map)))

(defun my/email-mode-line ()
  "Return mode-line string for email status."
  (let ((syncing (my/email-sync-in-progress-p))
        (pending my/notmuch-pending-changes)
        (gmail (or (alist-get 'gmail my/email-unread-counts) 0))
        (abaj (or (alist-get 'abaj my/email-unread-counts) 0))
        (unsw (or (alist-get 'unsw my/email-unread-counts) 0))
        (school (or (alist-get 'school my/email-unread-counts) 0)))
    (concat
     (if syncing (propertize " SYNCING" 'face 'font-lock-comment-face) "")
     (if pending (propertize " *" 'face 'warning) "")
     ;; Only show accounts with unread mail, clickable
     (let ((parts nil))
       (when (> gmail 0)
         (push (my/email-make-clickable (format "G:%d" gmail) 'gmail) parts))
       (when (> abaj 0)
         (push (my/email-make-clickable (format "A:%d" abaj) 'abaj) parts))
       (when (> unsw 0)
         (push (my/email-make-clickable (format "U:%d" unsw) 'unsw) parts))
       (when (> school 0)
         (push (my/email-make-clickable (format "S:%d" school) 'school) parts))
       (if parts
           (concat " " (string-join (nreverse parts) " "))
         "")))))

(defvar my/email-mode-line-construct
  '(:eval (my/email-mode-line))
  "Mode line construct for email status.")

;; Add to global mode line
(unless (member my/email-mode-line-construct global-mode-string)
  (push my/email-mode-line-construct global-mode-string))

(defun email-sync-all (&optional quiet)
  "Sync all email accounts and refresh notmuch.
If QUIET is non-nil, don't show messages."
  (interactive)
  (if (my/email-sync-in-progress-p)
      (unless quiet (message "Sync already in progress"))
    (email-sync-all--do-sync quiet)))

(defun email-sync-all--do-sync (&optional quiet)
  "Internal function to perform the actual sync."
  (setq my/email-last-sync-time (current-time))
  (let ((old-unread (my/email-total-unread))
        (needs-push my/notmuch-pending-changes)
        (tag-time-at-start my/notmuch-last-tag-time))
    ;; Build command. `gmi sync' (push+pull in one op) and mbsync touch
    ;; independent maildirs, so we fan them out in parallel and `wait' before
    ;; notmuch new — drops wall-clock to max(gmi, mbsync). `wait $pid' surfaces
    ;; each subshell's exit status, so `&&' between waits keeps "any failure
    ;; aborts the chain".
    ;;
    ;; Use `gmi sync', NOT `gmi push && gmi pull'. A partial push — local tag
    ;; edits that collide with server-side changes ("remote has changed, will
    ;; not update") — is normal and self-heals on the next run. But as a
    ;; separate `gmi push &&' prefix its non-zero exit short-circuited the pull,
    ;; so a routine push backlog silently stalled ALL fetching until drained by
    ;; hand. `gmi sync' pushes first internally, tolerates a partial push
    ;; (exit 0, retries next run), and still completes the pull. `needs-push'
    ;; is kept only for the sentinel's pending-changes bookkeeping below.
    (let* ((parallel-sync
            (concat "cd ~/Maildir/gmail-lieer && "
                    "gmi sync & gmi_pid=$!; "
                    "SASL_PATH=~/.sasl2:/usr/lib/sasl2 mbsync -a & mbsync_pid=$!; "
                    "wait $gmi_pid && wait $mbsync_pid && "
                    "notmuch new"))
           ;; Add jobsync corrections scanner (source config for API key)
           (cmd (concat parallel-sync " && source ~/.jobsync/config && node ~/lattice/code/private/jobsync/scripts/jobsync-scan-corrections.js 2>&1 | tail -5")))
      (unless quiet (message (if needs-push "Syncing (pushing changes)..." "Syncing...")))
      ;; `make-process' with :sentinel attaches the handler atomically.
      ;; `start-process' + `set-process-sentinel' has a window where the
      ;; subprocess could exit and Emacs could lose the exit notification
      ;; before the sentinel is installed — that was the "stuck SYNCING"
      ;; bug.
      (setq my/email-sync-process
            (make-process
             :name "email-sync"
             :buffer "*email-sync*"
             :command (list shell-file-name shell-command-switch cmd)
             :sentinel
             (lambda (proc event)
               (when (memq (process-status proc) '(exit signal))
                 (let ((success (and (string-match-p "finished" event)
                                     (zerop (process-exit-status proc)))))
                   ;; Only clear pending-changes if push actually succeeded
                   ;; AND no new tag changes happened during the sync.
                   ;; Clearing optimistically at sync start (the old
                   ;; behaviour) silently dropped pending edits on push
                   ;; failure.
                   (when (and success needs-push
                              (equal my/notmuch-last-tag-time tag-time-at-start))
                     (setq my/notmuch-pending-changes nil))
                   (if success
                       (progn
                         (my/email-update-unread-count)
                         (let* ((total (my/email-total-unread))
                                (new-mail (- total old-unread)))
                           (dolist (buf (buffer-list))
                             (with-current-buffer buf
                               (when (derived-mode-p 'notmuch-search-mode 'notmuch-show-mode 'notmuch-hello-mode)
                                 (ignore-errors (notmuch-refresh-this-buffer)))))
                           (if (> new-mail 0)
                               (progn
                                 (my/email-play-new-mail-sound)
                                 (message "Sync: +%d new (%d unread)" new-mail total))
                             (unless quiet
                               (message "Sync done (%d unread)" total)))))
                     (unless quiet
                       (message "Sync failed: %s" (string-trim event))))
                   (force-mode-line-update t))))))
      (force-mode-line-update t))))

;; =============================================================================
;; Auto-sync timers
;; =============================================================================
(defvar my/email-auto-sync-timer nil
  "Timer for automatic email sync.")

(defun my/email-in-notmuch-p ()
  "Return t if current buffer is a notmuch buffer."
  (derived-mode-p 'notmuch-search-mode 'notmuch-show-mode
                  'notmuch-hello-mode 'notmuch-tree-mode))

(defun my/email-auto-sync-maybe ()
  "Sync email based on context - 1 min in notmuch, 30 min otherwise.
Skips sync if user was marking emails in the last 10 seconds."
  (let* ((now (current-time))
         (elapsed (if my/email-last-sync-time
                      (float-time (time-subtract now my/email-last-sync-time))
                    most-positive-fixnum))
         (tag-elapsed (if my/notmuch-last-tag-time
                          (float-time (time-subtract now my/notmuch-last-tag-time))
                        most-positive-fixnum))
         (in-notmuch (my/email-in-notmuch-p))
         (interval (if in-notmuch 60 1800))) ; 1 min or 30 min
    ;; Skip if user was actively marking in last 10 seconds
    (when (and (>= elapsed interval)
               (>= tag-elapsed 10))
      (email-sync-all t))))

(defun my/email-start-auto-sync ()
  "Start the auto-sync timer."
  (interactive)
  (my/email-stop-auto-sync)
  (setq my/email-auto-sync-timer
        (run-with-timer 60 60 #'my/email-auto-sync-maybe))
  (message "Email auto-sync enabled"))

(defun my/email-stop-auto-sync ()
  "Stop the auto-sync timer."
  (interactive)
  (when my/email-auto-sync-timer
    (cancel-timer my/email-auto-sync-timer)
    (setq my/email-auto-sync-timer nil))
  (message "Email auto-sync disabled"))

;; Start auto-sync and update count when config loads
(my/email-update-unread-count)
(my/email-start-auto-sync)

;; =============================================================================
;; Org-msg - Compose HTML emails with org syntax
;; =============================================================================
;; IMPORTANT: Set mail-user-agent BEFORE org-msg loads so it detects notmuch
(setq mail-user-agent 'notmuch-user-agent)

(use-package org-msg
  :straight t
  :after notmuch
  :config
  ;; `tex:luamagick' tells org-export's HTML backend to convert every LaTeX
  ;; fragment (\(...\), $...$, \[...\]) into a PNG using the `luamagick'
  ;; processor defined in org-config.el. The PNGs are embedded as inline
  ;; MIME parts so recipients see rendered math without running JavaScript.
  (setq org-msg-options "html-postamble:nil toc:nil author:nil email:nil tex:luamagick"
        org-msg-startup "hidestars indent inlineimages"
        org-msg-greeting-fmt nil  ; No automatic greeting
        org-msg-signature nil     ; Use notmuch signature instead
        org-msg-default-alternatives '((new . (text html))
                                       (reply-to-html . (text html))
                                       (reply-to-text . (text)))
        org-msg-convert-citation t)

  ;; Redirect generated LaTeX fragment PNGs to a dedicated cache directory so
  ;; they don't clutter the compose buffer's default-directory (usually ~/).
  ;; org-format-latex hashes fragment contents into the filename, so the
  ;; cache is reused across sends. Also bury the `*Org Preview LaTeX Output*'
  ;; buffer that `org-create-formula-image' pops up during export.
  (defun aj/org-msg-latex-cache-dir (orig-fn &rest args)
    "Redirect LaTeX fragment PNGs to a dedicated cache dir during org-msg export.
Also suppress the `*Org Preview LaTeX Output*' log buffer that
`org-create-formula-image' pops up while compiling fragments."
    (let ((org-preview-latex-image-directory
           (expand-file-name "org-msg-ltximg/" user-emacs-directory))
          ;; Prevent display of the LaTeX compilation log buffer.
          (display-buffer-alist
           (cons '("\\*Org Preview LaTeX Output\\*"
                   (display-buffer-no-window)
                   (allow-no-window . t))
                 display-buffer-alist)))
      (unwind-protect
          (apply orig-fn args)
        (when-let ((buf (get-buffer "*Org Preview LaTeX Output*")))
          (let ((win (get-buffer-window buf)))
            (when win (delete-window win)))
          (kill-buffer buf)))))
  (advice-add 'org-msg-org-to-xml :around #'aj/org-msg-latex-cache-dir)

  ;; Add message-mode header navigation keybindings to org-msg-edit-mode
  (with-eval-after-load 'org-msg
    (define-key org-msg-edit-mode-map (kbd "C-c C-f C-t") #'message-goto-to)
    (define-key org-msg-edit-mode-map (kbd "C-c C-f C-c") #'message-goto-cc)
    (define-key org-msg-edit-mode-map (kbd "C-c C-f C-b") #'message-goto-bcc)
    (define-key org-msg-edit-mode-map (kbd "C-c C-f C-s") #'message-goto-subject)
    (define-key org-msg-edit-mode-map (kbd "C-c C-f C-f") #'message-goto-from)
    (define-key org-msg-edit-mode-map (kbd "C-c C-i") #'my/email-cycle-identity)
    ;; Address-aware TAB (see `aj/compose-tab' in the notmuch block): org-msg
    ;; binds `<tab>' to `org-msg-tab', which routes header TAB into the same
    ;; corfu-broken `completion-at-point'. Override both event forms.
    (define-key org-msg-edit-mode-map (kbd "<tab>") #'aj/compose-tab)
    (define-key org-msg-edit-mode-map (kbd "TAB") #'aj/compose-tab))

  (org-msg-mode))

;; =============================================================================
;; Dired attachment support
;; =============================================================================
(use-package gnus-dired
  :straight (:type built-in)
  :after notmuch
  :config
  ;; Make gnus-dired use notmuch
  (setq gnus-dired-mail-mode 'notmuch-user-agent)

  ;; In dired, press C-c RET C-a to attach marked files to a compose buffer
  (add-hook 'dired-mode-hook 'turn-on-gnus-dired-mode))

(provide 'email-config)
;;; email-config.el ends here
