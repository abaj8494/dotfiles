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
  ;; Keybindings for search mode (email list)
  ;; ---------------------------------------------------------------------------
  (define-key notmuch-search-mode-map (kbd "d")
    (lambda ()
      "Move to trash"
      (interactive)
      (notmuch-search-tag '("+trash" "-inbox" "-unread"))
      (notmuch-search-next-thread)))

  (define-key notmuch-search-mode-map (kbd "a")
    (lambda ()
      "Archive (remove from inbox)"
      (interactive)
      (notmuch-search-archive-thread)
      (notmuch-search-next-thread)))

  (define-key notmuch-search-mode-map (kbd "u")
    (lambda ()
      "Toggle unread"
      (interactive)
      (notmuch-search-tag
       (if (member "unread" (notmuch-search-get-tags))
           '("-unread")
         '("+unread")))))

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

  ;; Move to labels (Gmail)
  (define-key notmuch-search-mode-map (kbd "m f")
    (lambda ()
      "Move to Finance"
      (interactive)
      (notmuch-search-tag '("+Finance" "-inbox"))
      (notmuch-search-next-thread)))

  (define-key notmuch-search-mode-map (kbd "m o")
    (lambda ()
      "Move to Orders"
      (interactive)
      (notmuch-search-tag '("+Orders" "-inbox"))
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
      "Toggle unread"
      (interactive)
      (notmuch-show-tag
       (if (member "unread" (notmuch-show-get-tags))
           '("-unread")
         '("+unread")))))

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

  ;; Move to labels (Gmail)
  (define-key notmuch-show-mode-map (kbd "m f")
    (lambda ()
      "Move to Finance"
      (interactive)
      (notmuch-show-tag '("+Finance" "-inbox"))))

  (define-key notmuch-show-mode-map (kbd "m o")
    (lambda ()
      "Move to Orders"
      (interactive)
      (notmuch-show-tag '("+Orders" "-inbox"))))

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
      (email-sync-all))))

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
;; Sync command
;; =============================================================================
(defun email-sync-all ()
  "Sync all email accounts and refresh notmuch."
  (interactive)
  (message "Syncing all email...")
  (async-shell-command
   "cd ~/Maildir/gmail-lieer && gmi push && gmi pull && SASL_PATH=~/.sasl2:/usr/lib/sasl2 mbsync -a && notmuch new"
   "*email-sync*")
  (message "Email sync started in background"))

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
