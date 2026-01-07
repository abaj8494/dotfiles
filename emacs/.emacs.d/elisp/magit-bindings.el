(defvar my/magit-map
  (let ((map (make-sparse-keymap)))
    map)
  "Prefix keymap for Magit commands.")

(define-key global-map (kbd "C-c g") my/magit-map)


(with-eval-after-load 'magit
  (keymap-set my/magit-map "g" #'magit-status)
  (keymap-set my/magit-map "s" #'magit-status)
  (keymap-set my/magit-map "d" #'magit-dispatch)
  (keymap-set my/magit-map "f" #'magit-file-dispatch)

  (keymap-set my/magit-map "c" #'magit-commit)
  (keymap-set my/magit-map "p" #'magit-push)
  (keymap-set my/magit-map "F" #'magit-fetch)
  (keymap-set my/magit-map "P" #'magit-pull)
  (keymap-set my/magit-map "r" #'magit-rebase)
  (keymap-set my/magit-map "m" #'magit-merge)

  (keymap-set my/magit-map "l" #'magit-log-current)
  (keymap-set my/magit-map "L" #'magit-log-all)
  (keymap-set my/magit-map "b" #'magit-blame))


(provide 'magit-bindings)
