
;; flashcards
(add-to-list 'load-path "~/.emacs.d/src/org-fc/")

(require 'org-fc)
(require 'org-fc-hydra)

(setq org-fc-directories '("~/Documents/new-site/static/doc/org/flashcards/"))

(setq org-format-latex-options (plist-put org-format-latex-options :scale 2.0))

(defun my/org-fc-setup-latex ()
  ;; Only affect the current buffer, not all of Emacs:
  (setq-local org-preview-latex-image-directory "./ob-jupyter/")
  (setq-local org-preview-latex-default-process 'imagemagick))

(with-eval-after-load 'org-fc
  ;; 'append makes sure this runs *after* any functions org-fc itself
  ;; has already put on org-fc-before-setup-hook.
  (add-hook 'org-fc-before-setup-hook #'my/org-fc-setup-latex 'append))


;;; --- org-fc card type selection ----------------------------------------

(defvar my/org-fc-card-types
  '("normal" "double" "text-input" "cloze")
  "Card types I can initialize with org-fc-type-*-init.")

(defvar my/org-fc-last-type "normal"
  "Last org-fc card type I used.")

(defun my/org-fc-choose-card-type ()
  "Prompt for an org-fc card type and remember it."
  (setq my/org-fc-last-type
        (completing-read "org-fc card type: "
                         my/org-fc-card-types
                         nil t nil nil my/org-fc-last-type)))

(defun my/org-fc-init-current-card ()
  "Initialize the current capture entry as an org-fc card.

Called from a capture template via :before-finalize.
Uses `my/org-fc-last-type` to decide which init fn to call."
  (when my/org-fc-last-type
    (save-excursion
      ;; Be on the heading before calling the init fn
      (org-back-to-heading t)
      (let* ((type my/org-fc-last-type)
             (fn   (intern (format "org-fc-type-%s-init" type))))
        (unless (fboundp fn)
          (user-error "No init function for org-fc card type %S" type))
        (funcall fn)))))


;; org-capture

(setq org-export-coding-system 'utf-8)

(setq org-capture-templates
      '(("t" "todo list item" entry (file+headline "~/Documents/new-site/static/doc/org/tasks.org"  "Tasks")
	 "* TODO %?\n %i\n %a")
	("j" "journal entry" entry (file + datetree "~/Documents/new-site/static/doc/org/journal.org")
	 "* %?\nEntered on %U\n %i\n %a")))

;;(global-set-key (kbd "C-c H") 'org-fc-hydra/body)

(add-to-list 'org-fc-custom-contexts
             '(math . (:paths ("~/Documents/new-site/static/doc/org/flashcards/math.org"))))
(add-to-list 'org-fc-custom-contexts
             '(stats . (:paths ("~/Documents/new-site/static/doc/org/flashcards/stats.org"))))
(add-to-list 'org-fc-custom-contexts
             '(ml . (:paths ("~/Documents/new-site/static/doc/org/flashcards/machine-learning.org"))))
(add-to-list 'org-fc-custom-contexts
             '(quant . (:paths ("~/Documents/new-site/static/doc/org/flashcards/quant.org"))))
(add-to-list 'org-fc-custom-contexts
             '(soft-eng . (:paths ("~/Documents/new-site/static/doc/org/flashcards/soft-eng.org"))))

(defvar my/org-fc-dir "~/Documents/new-site/static/doc/org/flashcards"
  "Base directory for my org-fc decks.")


(defconst my/org-fc-math-file
  (expand-file-name "math.org" my/org-fc-dir))
(defconst my/org-fc-stats-file
  (expand-file-name "stats.org" my/org-fc-dir))
(defconst my/org-fc-softeng-file
  (expand-file-name "soft-eng.org" my/org-fc-dir))
(defconst my/org-fc-quant-file
  (expand-file-name "quant.org" my/org-fc-dir))
(defconst my/org-fc-ml-file
  (expand-file-name "machine-learning.org" my/org-fc-dir))


(with-eval-after-load 'org-capture
  (make-directory my/org-fc-dir t)

  ;; 1 – Mathematics
  (add-to-list 'org-capture-templates
               `("1" "Math flashcard" entry
                 (file+headline ,my/org-fc-math-file "Inbox")
                 "* %^{Question}\n** Back\n%^{Answer}\n"
                 :empty-lines 1
                 :before-finalize my/org-fc-init-current-card)
               'append)

  ;; 2 – Statistics
  (add-to-list 'org-capture-templates
               `("2" "Statistics flashcard" entry
                 (file+headline ,my/org-fc-stats-file "Inbox")
                 "* %^{Question}\n** Back\n%^{Answer}\n"
                 :empty-lines 1
                 :before-finalize my/org-fc-init-current-card)
               'append)

  ;; 3 – Software Engineering
  (add-to-list 'org-capture-templates
               `("3" "Soft-eng flashcard" entry
                 (file+headline ,my/org-fc-softeng-file "Inbox")
                 "* %^{Question}\n** Back\n%^{Answer}\n"
                 :empty-lines 1
                 :before-finalize my/org-fc-init-current-card)
               'append)

  ;; 4 – Quant
  (add-to-list 'org-capture-templates
               `("4" "Quant flashcard" entry
                 (file+headline ,my/org-fc-quant-file "Inbox")
                 "* %^{Question}\n** Back\n%^{Answer}\n"
                 :empty-lines 1
                 :before-finalize my/org-fc-init-current-card)
               'append)

  ;; 5 – Machine Learning
  (add-to-list 'org-capture-templates
               `("5" "ML flashcard" entry
                 (file+headline ,my/org-fc-ml-file "Inbox")
                 "* %^{Question}\n** Back\n%^{Answer}\n"
                 :empty-lines 1
                 :before-finalize my/org-fc-init-current-card)
               'append))


;; Main org prefix on C-c c
(define-prefix-command 'my/org-main-map)
(global-set-key (kbd "C-c c") #'my/org-main-map)

;; Normal org-capture: C-c c c
(define-key my/org-main-map (kbd "c") #'org-capture)

;; org-fc hydra: C-c c h
(with-eval-after-load 'org-fc-hydra
  (define-key my/org-main-map (kbd "h") #'org-fc-hydra/body))

;; Flashcard prefix: C-c c f
(define-prefix-command 'my/org-fc-map)
(define-key my/org-main-map (kbd "f") #'my/org-fc-map)


;;; --- Flashcard capture commands used under C-c c f --------------------

(defun my/org-fc-capture-with-type (template-key)
  "Prompt for org-fc card type, then run `org-capture` with TEMPLATE-KEY."
  (interactive)
  (my/org-fc-choose-card-type)
  (org-capture nil template-key))

(defun my/org-fc-capture-math ()
  (interactive)
  (my/org-fc-capture-with-type "1"))

(defun my/org-fc-capture-stats ()
  (interactive)
  (my/org-fc-capture-with-type "2"))

(defun my/org-fc-capture-softeng ()
  (interactive)
  (my/org-fc-capture-with-type "3"))

(defun my/org-fc-capture-quant ()
  (interactive)
  (my/org-fc-capture-with-type "4"))

(defun my/org-fc-capture-ml ()
  (interactive)
  (my/org-fc-capture-with-type "5"))

;; Bind under the flashcard prefix: C-c c f 1..5
(define-key my/org-fc-map (kbd "1") #'my/org-fc-capture-math)
(define-key my/org-fc-map (kbd "2") #'my/org-fc-capture-stats)
(define-key my/org-fc-map (kbd "3") #'my/org-fc-capture-softeng)
(define-key my/org-fc-map (kbd "4") #'my/org-fc-capture-quant)
(define-key my/org-fc-map (kbd "5") #'my/org-fc-capture-ml)



(add-to-list
 'org-fc-back-heading-titles
 "Answer")
