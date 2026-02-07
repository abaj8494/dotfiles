(defvar my/magit-map
  (let ((map (make-sparse-keymap)))
    map)
  "Prefix keymap for Magit commands.")

(define-key global-map (kbd "C-c g") my/magit-map)


(with-eval-after-load 'magit
  ;; Sound notifications for git operations
  (defvar my/magit-push-sound "/System/Library/Sounds/Blow.aiff"
    "Sound to play when git push completes.")
  (defvar my/magit-pull-sound "/System/Library/Sounds/Submarine.aiff"
    "Sound to play when git pull completes.")
  (defvar my/magit-commit-sound "/System/Library/Sounds/Glass.aiff"
    "Sound to play when git commit completes.")
  (defvar my/magit-stage-sound "/System/Library/Sounds/Pop.aiff"
    "Sound to play when staging files.")
  (defvar my/magit-unstage-sound "/System/Library/Sounds/Basso.aiff"
    "Sound to play when unstaging files.")

  (defun my/magit-play-sound (sound)
    "Play SOUND file asynchronously."
    (start-process "magit-sound" nil "afplay" sound))

  ;; Push/pull sounds via process sentinel
  (defun my/magit-process-sound-sentinel (process event)
    "Play sound when push/pull/fetch completes."
    (when (and (string-match-p "finished" event)
               (process-command process))
      (let ((args (process-command process)))
        (cond
         ((member "push" args)
          (my/magit-play-sound my/magit-push-sound))
         ((or (member "pull" args) (member "fetch" args))
          (my/magit-play-sound my/magit-pull-sound))))))

  (advice-add 'magit-process-sentinel :after #'my/magit-process-sound-sentinel)

  ;; Commit sound
  (defun my/magit-commit-sound-hook ()
    "Play sound after successful commit."
    (my/magit-play-sound my/magit-commit-sound))

  (add-hook 'git-commit-post-finish-hook #'my/magit-commit-sound-hook)

  ;; Stage/unstage sounds via magit hooks
  (defun my/magit-stage-sound-hook ()
    "Play sound when staging."
    (my/magit-play-sound my/magit-stage-sound))

  (defun my/magit-unstage-sound-hook ()
    "Play sound when unstaging."
    (my/magit-play-sound my/magit-unstage-sound))

  (add-hook 'magit-post-stage-hook #'my/magit-stage-sound-hook)
  (add-hook 'magit-post-unstage-hook #'my/magit-unstage-sound-hook)

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
