;;; email-config.el --- mu4e email configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; mu4e configuration for multiple email accounts with mbsync.
;; Accounts: Gmail, abaj.ai, UNSW Microsoft 365

;;; Code:

(use-package mu4e
  :straight (:type built-in)
  :load-path "/opt/homebrew/share/emacs/site-lisp/mu/mu4e/"
  :commands (mu4e mu4e-compose-new)
  :bind (("C-c m m" . mu4e)
         ("C-c m c" . mu4e-compose-new)
         ("C-c m u" . mu4e-update-mail-and-index))
  :init
  (setq mu4e-update-interval (* 5 60))
  :config
  (setq mu4e-maildir "~/Maildir"
        mu4e-attachment-dir "~/Downloads"
        mu4e-get-mail-command "SASL_PATH=~/.sasl2:/usr/lib/sasl2 mbsync -a"
        mu4e-change-filenames-when-moving t
        mu4e-view-show-addresses t
        mu4e-view-show-images t
        mu4e-compose-signature-auto-include nil
        mu4e-compose-dont-reply-to-self t
        mu4e-headers-skip-duplicates t)

  (setq mail-user-agent 'mu4e-user-agent)
  (setq message-kill-buffer-on-exit t)

  ;; Account contexts
  (setq mu4e-contexts
        (list
         ;; Gmail
         (make-mu4e-context
          :name "Gmail"
          :match-func (lambda (msg)
                        (when msg
                          (string-prefix-p "/gmail" (mu4e-message-field msg :maildir))))
          :vars '((user-mail-address      . "aayushbajaj7@gmail.com")
                  (user-full-name         . "Aayush Bajaj")
                  (mu4e-drafts-folder     . "/gmail/[Gmail]/Drafts")
                  (mu4e-sent-folder       . "/gmail/[Gmail]/Sent Mail")
                  (mu4e-trash-folder      . "/gmail/[Gmail]/Trash")
                  (mu4e-refile-folder     . "/gmail/[Gmail]/All Mail")
                  (smtpmail-smtp-server   . "smtp.gmail.com")
                  (smtpmail-smtp-service  . 465)
                  (smtpmail-stream-type   . ssl)))

         ;; Abaj.ai
         (make-mu4e-context
          :name "Abaj"
          :match-func (lambda (msg)
                        (when msg
                          (string-prefix-p "/abaj" (mu4e-message-field msg :maildir))))
          :vars '((user-mail-address      . "j@abaj.ai")
                  (user-full-name         . "Aayush Bajaj")
                  (mu4e-drafts-folder     . "/abaj/Drafts")
                  (mu4e-sent-folder       . "/abaj/Sent")
                  (mu4e-trash-folder      . "/abaj/Trash")
                  (mu4e-refile-folder     . "/abaj/Archive")
                  (smtpmail-smtp-server   . "mail.abaj.ai")
                  (smtpmail-smtp-service  . 465)
                  (smtpmail-stream-type   . ssl)))

         ;; UNSW
         (make-mu4e-context
          :name "UNSW"
          :match-func (lambda (msg)
                        (when msg
                          (string-prefix-p "/unsw" (mu4e-message-field msg :maildir))))
          :vars '((user-mail-address      . "z5362216@zmail.unsw.edu.au")
                  (user-full-name         . "Aayush Bajaj")
                  (mu4e-drafts-folder     . "/unsw/Drafts")
                  (mu4e-sent-folder       . "/unsw/Sent Items")
                  (mu4e-trash-folder      . "/unsw/Deleted Items")
                  (mu4e-refile-folder     . "/unsw/Archive")
                  (smtpmail-smtp-server   . "smtp.office365.com")
                  (smtpmail-smtp-service  . 587)
                  (smtpmail-stream-type   . starttls)))))

  (setq mu4e-context-policy 'pick-first
        mu4e-compose-context-policy 'ask-if-none)

  ;; Bookmarks
  (setq mu4e-bookmarks
        '((:name "Unread" :query "flag:unread AND NOT flag:trashed" :key ?u)
          (:name "Today" :query "date:today..now" :key ?t)
          (:name "Last 7 days" :query "date:7d..now" :key ?w)
          (:name "Gmail" :query "maildir:/gmail/Inbox" :key ?g)
          (:name "Abaj" :query "maildir:/abaj/Inbox" :key ?a)
          (:name "UNSW" :query "maildir:/unsw/Inbox" :key ?n)))

  ;; Headers
  (setq mu4e-headers-fields
        '((:human-date . 12)
          (:flags . 6)
          (:from . 22)
          (:subject . nil))))

;; SMTP
(use-package smtpmail
  :straight (:type built-in)
  :config
  (setq send-mail-function 'smtpmail-send-it
        message-send-mail-function 'smtpmail-send-it
        smtpmail-debug-info t
        smtpmail-debug-verb t))

;; GnuTLS settings for SMTP
(use-package gnutls
  :straight (:type built-in)
  :config
  (setq gnutls-algorithm-priority "NORMAL:%COMPAT"
        gnutls-min-prime-bits 1024))

;; Auth source
(use-package auth-source
  :straight (:type built-in)
  :config
  (setq auth-sources '("~/.authinfo.gpg")))

(provide 'email-config)
;;; email-config.el ends here
