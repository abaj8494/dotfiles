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
          ;; Gmail labels
          (:name "Starred" :query "path:gmail-lieer/** and (tag:flagged or tag:YELLOW_STAR)" :key "f" :sort-order newest-first)
          (:name "Finance" :query "path:gmail-lieer/** and tag:Finance" :key "$" :sort-order newest-first)
          (:name "Orders" :query "path:gmail-lieer/** and tag:Orders" :key "o" :sort-order newest-first)
          (:name "Sent" :query "tag:sent or folder:abaj/Sent or folder:\"unsw/Sent Items\"" :key "s" :sort-order newest-first)
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
          "Aayush Bajaj <z5362216@zmail.unsw.edu.au>"))

  ;; FCC - save sent mail
  (setq notmuch-fcc-dirs
        '(("aayushbajaj7@gmail.com" . nil)  ; Gmail saves sent automatically
          ("j@abaj.ai" . "abaj/Sent")
          ("z5362216@zmail.unsw.edu.au" . "unsw/Sent Items")))

  ;; ---------------------------------------------------------------------------
  ;; Marking system for bulk operations
  ;; ---------------------------------------------------------------------------
  (defvar-local my/notmuch-marked-threads nil
    "List of marked thread IDs in current search buffer.")

  (defun my/notmuch-search-toggle-mark ()
    "Toggle mark on current thread."
    (interactive)
    (let ((thread-id (notmuch-search-find-thread-id)))
      (if (member thread-id my/notmuch-marked-threads)
          (progn
            (setq my/notmuch-marked-threads (delete thread-id my/notmuch-marked-threads))
            (notmuch-search-tag '("-marked")))
        (push thread-id my/notmuch-marked-threads)
        (notmuch-search-tag '("+marked"))))
    (notmuch-search-next-thread)
    (message "%d marked" (length my/notmuch-marked-threads)))

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
  (define-key notmuch-search-mode-map (kbd "x") 'my/notmuch-search-toggle-mark)
  (define-key notmuch-search-mode-map (kbd "U") 'my/notmuch-search-unmark-all)

  (define-key notmuch-search-mode-map (kbd "d")
    (lambda ()
      "Move to trash (marked or current)"
      (interactive)
      (if my/notmuch-marked-threads
          (my/notmuch-search-mark-action '("+trash" "-inbox" "-unread" "-marked"))
        (notmuch-search-tag '("+trash" "-inbox" "-unread"))
        (setq my/notmuch-pending-changes t)
        (notmuch-search-next-thread))))

  (define-key notmuch-search-mode-map (kbd "a")
    (lambda ()
      "Archive (marked or current)"
      (interactive)
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
           ((string-match "/unsw/" files) 'unsw)
           (t nil))))))

  (defun my/notmuch-move-to-folder (folder)
    "Move current IMAP message to FOLDER (for abaj/unsw only)."
    (let* ((file (notmuch-show-get-filename))
           (account (my/notmuch-get-message-account))
           (maildir (cond
                     ((eq account 'abaj) "~/Maildir/abaj")
                     ((eq account 'unsw) "~/Maildir/unsw")
                     (t nil))))
      (if (not maildir)
          (message "Move only works for IMAP accounts (abaj/unsw)")
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

;; =============================================================================
;; SMTP - Per-account sending
;; =============================================================================
(use-package smtpmail
  :straight (:type built-in)
  :config
  (setq smtpmail-debug-info nil
        smtpmail-debug-verb nil))

(use-package message
  :straight (:type built-in)
  :config
  (setq message-send-mail-function 'message-smtpmail-send-it
        message-kill-buffer-on-exit t)

  ;; Set SMTP based on From address
  (defun my/set-smtp-from-address ()
    "Set SMTP server based on From address."
    (let ((from (message-fetch-field "from")))
      (cond
       ((string-match "aayushbajaj7@gmail.com" from)
        (setq smtpmail-smtp-server "smtp.gmail.com"
              smtpmail-smtp-service 465
              smtpmail-stream-type 'ssl))
       ((string-match "j@abaj.ai" from)
        (setq smtpmail-smtp-server "mail.abaj.ai"
              smtpmail-smtp-service 465
              smtpmail-stream-type 'ssl))
       ((string-match "z5362216@zmail.unsw.edu.au" from)
        (setq smtpmail-smtp-server "smtp.office365.com"
              smtpmail-smtp-service 587
              smtpmail-stream-type 'starttls)))))

  (add-hook 'message-send-hook 'my/set-smtp-from-address))

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

;; =============================================================================
;; Email status tracking
;; =============================================================================
(defvar my/email-sync-process nil
  "Current email sync process.")

(defvar my/email-last-sync-time nil
  "Time of last email sync.")

(defvar my/notmuch-pending-changes nil
  "Non-nil if there are local tag changes not yet synced to remote.")

(defvar my/email-unread-counts nil
  "Alist of (account . unread-count).")

(defvar my/email-syncing nil
  "Non-nil when email sync is in progress.")

(defvar my/email-account-queries
  '((gmail . "path:gmail-lieer/** and tag:inbox")
    (abaj . "folder:abaj/Inbox")
    (unsw . "folder:unsw/Inbox"))
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
         '(gmail abaj unsw))))

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
  (let ((syncing my/email-syncing)
        (pending my/notmuch-pending-changes)
        (gmail (or (alist-get 'gmail my/email-unread-counts) 0))
        (abaj (or (alist-get 'abaj my/email-unread-counts) 0))
        (unsw (or (alist-get 'unsw my/email-unread-counts) 0)))
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
  ;; Don't start new sync if one is running
  (if (and my/email-sync-process (process-live-p my/email-sync-process))
      (unless quiet (message "Sync already in progress"))
    ;; Proceed with sync
    (email-sync-all--do-sync quiet)))

(defun email-sync-all--do-sync (&optional quiet)
  "Internal function to perform the actual sync."
  (setq my/email-syncing t)
  (setq my/email-last-sync-time (current-time))
  (force-mode-line-update t)
  (let ((old-unread (my/email-total-unread))
        (needs-push my/notmuch-pending-changes))
    ;; Build command: push first if needed, then pull, then run jobsync corrections scanner
    (let* ((base-cmd (if needs-push
                         "cd ~/Maildir/gmail-lieer && gmi push && gmi pull && SASL_PATH=~/.sasl2:/usr/lib/sasl2 mbsync -a && notmuch new"
                       "cd ~/Maildir/gmail-lieer && gmi pull && SASL_PATH=~/.sasl2:/usr/lib/sasl2 mbsync -a && notmuch new"))
           ;; Add jobsync corrections scanner (source config for API key)
           (cmd (concat base-cmd " && source ~/.jobsync/config && node ~/Documents/code-private/jobsync/scripts/jobsync-scan-corrections.js 2>&1 | tail -5")))
      (setq my/notmuch-pending-changes nil)
      (unless quiet (message (if needs-push "Syncing (pushing changes)..." "Syncing...")))
      (setq my/email-sync-process
            (start-process-shell-command "email-sync" "*email-sync*" cmd))
      (set-process-sentinel
       my/email-sync-process
       (lambda (proc event)
         (setq my/email-syncing nil)
         (when (string-match-p "finished" event)
           ;; Update unread count
           (my/email-update-unread-count)
           (let* ((total (my/email-total-unread))
                  (new-mail (- total old-unread)))
             ;; Refresh any open notmuch buffers
             (dolist (buf (buffer-list))
               (with-current-buffer buf
                 (when (derived-mode-p 'notmuch-search-mode 'notmuch-show-mode 'notmuch-hello-mode)
                   (ignore-errors (notmuch-refresh-this-buffer)))))
             ;; Notify
             (if (> new-mail 0)
                 (message "Sync: +%d new (%d unread)" new-mail total)
               (unless quiet
                 (message "Sync done (%d unread)" total)))))
         (force-mode-line-update t))))))

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
  "Sync email based on context - 1 min in notmuch, 30 min otherwise."
  (let* ((now (current-time))
         (elapsed (if my/email-last-sync-time
                      (float-time (time-subtract now my/email-last-sync-time))
                    most-positive-fixnum))
         (in-notmuch (my/email-in-notmuch-p))
         (interval (if in-notmuch 60 1800))) ; 1 min or 30 min
    (when (>= elapsed interval)
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
