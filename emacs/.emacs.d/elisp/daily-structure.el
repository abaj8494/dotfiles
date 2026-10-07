;;; daily-structure.el --- Daily-note heading scaffolding -*- lexical-binding: t; -*-

;;; Commentary:
;; Heading-order detection, idempotent heading insertion, separator and
;; #+LATEX: \newpage maintenance, and blank-line normalization for daily
;; org-roam notes. Foundation module — every other daily-* module depends
;; on the helpers here.

;;; Code:

(require 'cl-lib)

(declare-function org-current-level "org")
(declare-function aj/ensure-recurring-separators "daily-recurring")

(defvar aj/daily-heading-order
  '("Journal" "Recurring" "Calendar" "Capture" "Tasks")
  "Ordered list of level-1 headings for daily notes.")

(defvar aj/headings-with-statistics '("Capture" "Tasks")
  "Headings that should have [/] statistics cookies.")

(defun aj/daily-date-file-p (&optional file)
  "Return t if FILE matches YYYY-MM-DD.org pattern (actual daily note).
Excludes yearly files like twenty_twenty_six.org."
  (let ((path (or file (buffer-file-name))))
    (and path
         (string-match-p "/daily/[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\.org$" path))))

(defun aj/under-heading-p (heading-re)
  "Return non-nil if point is within the section of HEADING-RE."
  (save-excursion
    (let ((pos (point)))
      (goto-char (point-min))
      (and (re-search-forward heading-re nil t)
           (let* ((start (line-beginning-position))
                  (level (org-current-level))
                  (end-re (format "^\\*\\{1,%d\\} " level))
                  (end (save-excursion
                         (forward-line 1)
                         (if (re-search-forward end-re nil t)
                             (line-beginning-position)
                           (point-max)))))
             (and (>= pos start) (< pos end)))))))

(defun aj/find-heading-insert-point (heading)
  "Find the correct insertion point for HEADING based on `aj/daily-heading-order'.
Returns the position where the heading should be inserted."
  (let* ((pos (cl-position heading aj/daily-heading-order :test 'equal))
         (later-headings (nthcdr (1+ pos) aj/daily-heading-order)))
    ;; Find the first existing heading that should come after this one
    (catch 'found
      (dolist (next-heading later-headings)
        (save-excursion
          (save-restriction
            (widen)
            (goto-char (point-min))
            (when (re-search-forward (format "^\\* %s\\b" (regexp-quote next-heading)) nil t)
              (throw 'found (line-beginning-position))))))
      ;; No later heading found, insert at end of buffer
      nil)))

(defun aj/ensure-heading-exists (heading)
  "Ensure HEADING exists in the daily note at the correct position.
Returns t if heading was created, nil if it already existed."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (unless (re-search-forward (format "^\\* %s\\b" (regexp-quote heading)) nil t)
        (let ((insert-point (aj/find-heading-insert-point heading))
              (heading-text (if (member heading aj/headings-with-statistics)
                                (format "* %s [/]\n\n" heading)
                              (format "* %s\n\n" heading))))
          (if insert-point
              (progn
                (goto-char insert-point)
                (insert heading-text))
            ;; Insert at end
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (insert (concat "\n" heading-text))))
        t))))

(defun aj/ensure-heading-has-statistics-cookie (heading)
  "Ensure HEADING has a [/] statistics cookie if it should have one.
Only modifies headings listed in `aj/headings-with-statistics'."
  (when (member heading aj/headings-with-statistics)
    (save-excursion
      (save-restriction
        (widen)
        (goto-char (point-min))
        (when (re-search-forward (format "^\\(\\* %s\\)\\([ \t]*\\)$" (regexp-quote heading)) nil t)
          ;; Heading exists without cookie - add it
          (goto-char (match-end 1))
          (insert " [/]"))))))

(defun aj/daily-today-or-later-p (&optional file)
  "Return non-nil if FILE (default: this buffer) is today's daily or a future one.
Past dailies are frozen: their PDFs may already carry reMarkable pen
strokes, and any edit that re-flows the page breaks orphans those."
  (let ((base (file-name-base (or file (buffer-file-name) ""))))
    (and (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" base)
         (not (string< base (format-time-string "%Y-%m-%d"))))))

(defvar aj/heading-scaffolding-re
  "\\`\\(?:[ \t]*\n\\|-----[ \t]*\n\\|#\\+LATEX:[ \t]+\\\\newpage[ \t]*\n\\)*\\'"
  "Matches a section body made up of nothing but structural scaffolding.
That is: blank lines, `-----' separators and `#+LATEX: \\newpage'
directives — everything `aj/ensure-heading-separators' and
`aj/ensure-heading-newpages' put there themselves. A body matching this
carries no content of the user's, so it counts as empty.")

(defun aj/delete-titleless-headings ()
  "Delete headings that carry no title text and no content.

A bare `* ' line (star, space, nothing after it) is not a section. It
exports as a blank page, and `aj/ensure-heading-separators' /
`aj/ensure-heading-newpages' keep decorating it with a fresh triple
separator and a \\newpage on every refresh, so it never goes away on its
own.

Only removed when the whole subtree is scaffolding (see
`aj/heading-scaffolding-re') — a titleless heading that somehow acquired
real content is left alone rather than silently taking that content with
it. Call this BEFORE the separator/newpage passes; they rebuild the
decoration this swallows on the way out.

Never touches a PAST daily. Removing a heading re-flows every page break
below it, which orphans the reMarkable pen strokes already drawn on that
day\'s PDF — the same reason `aj/insert-problems-due\' freezes the
Problems block once the day is over."
  (when (aj/daily-today-or-later-p)
    (save-excursion
      (save-restriction
        (widen)
        (let ((hits nil))
          (goto-char (point-min))
          (while (re-search-forward "^\\*+[ \t]*$" nil t)
            (push (line-beginning-position) hits))
          ;; Bottom-to-top: deletions cannot invalidate an unvisited position.
          (dolist (bol hits)
            (goto-char bol)
            (let* ((heading-eol (line-end-position))
                   (end (save-excursion (org-end-of-subtree t t) (point)))
                   (body (buffer-substring-no-properties
                          (min (1+ heading-eol) end) end)))
              (when (string-match-p aj/heading-scaffolding-re body)
                (let ((start bol))
                  (save-excursion
                    (goto-char start)
                    (forward-line -1)
                    (while (and (> (point) (point-min))
                                (or (looking-at-p "^[ \t]*$")
                                    (looking-at-p "^-----[ \t]*$")
                                    (looking-at-p "^#\\+LATEX:[ \t]+\\\\newpage[ \t]*$")))
                      (setq start (line-beginning-position))
                      (forward-line -1)))
                  (delete-region start end))))))))))

(defun aj/ensure-daily-structure ()
  "Ensure the daily note has all required headings in the correct order.
Order: Journal, Recurring, Calendar, Capture, Tasks."
  (interactive)
  (when (aj/daily-date-file-p)
    (save-excursion
      ;; Drop empty `* ' headings first, so the separator/newpage passes
      ;; below rebuild the decoration around the real headings instead of
      ;; re-decorating a blank one.
      (aj/delete-titleless-headings)
      (dolist (heading aj/daily-heading-order)
        (aj/ensure-heading-exists heading))
      ;; Ensure statistics cookies on headings that need them
      (dolist (heading aj/headings-with-statistics)
        (aj/ensure-heading-has-statistics-cookie heading))
      ;; Ensure ----- separators between level-1 headings
      (aj/ensure-heading-separators)
      ;; Ensure #+LATEX: \newpage directive before each level-1 heading
      ;; (except the first) so `C-c C-e l o' paginates top-level sections.
      (aj/ensure-heading-newpages)
      (aj/ensure-recurring-separators)
      ;; Final pass: collapse any 2+ consecutive blank lines immediately
      ;; below a heading down to a single blank line. Self-heals drift
      ;; from accumulated refreshes / inserts that don't normalize spacing.
      (aj/normalize-heading-blank-lines))))

(defun aj/normalize-heading-blank-lines ()
  "Collapse 2+ consecutive blank lines immediately following any heading to 1.
Idempotent. Only touches the blank-line run directly under a heading;
blank lines elsewhere in body content are left alone."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (while (re-search-forward "^\\*+ " nil t)
        (forward-line 1)
        (let ((blank-start (point))
              (n 0))
          (while (and (not (eobp)) (looking-at-p "^[ \t]*$"))
            (forward-line 1)
            (setq n (1+ n)))
          (when (> n 1)
            (delete-region blank-start (point))
            (insert "\n")))))))

(defun aj/ensure-heading-separators ()
  "Ensure triple ----- separators immediately before each level-1 heading except the first.
If a separator was displaced (e.g. by a capture inserting after it),
removes all stale separators and inserts a fresh triple separator.
User-placed separators earlier in the section are preserved."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((headings nil))
        ;; Collect all level-1 heading positions
        (while (re-search-forward "^\\* " nil t)
          (push (line-beginning-position) headings))
        (setq headings (nreverse headings))
        (let ((len (length headings)))
          (when (>= len 2)
            ;; Process from bottom to top so position shifts don't affect
            ;; headings we haven't processed yet
            (dotimes (j (1- len))
              (let* ((i (- len 1 j))
                     (heading-bol (nth i headings))
                     (section-start (save-excursion
                                      (goto-char (nth (1- i) headings))
                                      (forward-line 1) (point))))
                ;; Check if triple ----- is right above heading (skip blank lines
                ;; and any `#+LATEX: \newpage' directive inserted by
                ;; `aj/ensure-heading-newpages').
                (goto-char heading-bol)
                (forward-line -1)
                (while (and (> (point) section-start)
                            (or (looking-at-p "^[ \t]*$")
                                (looking-at-p "^#\\+LATEX:[ \t]+\\\\newpage[ \t]*$")))
                  (forward-line -1))
                (let ((has-triple-sep
                       (and (looking-at-p "^-----$")
                            (save-excursion
                              (forward-line -1)
                              (and (looking-at-p "^-----$")
                                   (save-excursion
                                     (forward-line -1)
                                     (looking-at-p "^-----$")))))))
                  (unless has-triple-sep
                    ;; Remove ALL ----- lines in this section (stale singles or doubles)
                    (let ((positions nil))
                      (goto-char section-start)
                      (while (re-search-forward "^-----$" heading-bol t)
                        (push (cons (line-beginning-position)
                                    (min (1+ (line-end-position)) (point-max)))
                              positions))
                      ;; Delete from bottom to top so positions stay valid
                      (dolist (pos positions)
                        (delete-region (car pos) (cdr pos))
                        (setq heading-bol (- heading-bol (- (cdr pos) (car pos))))))
                    ;; Insert fresh triple separator before heading. If a
                    ;; `#+LATEX: \newpage' directive already sits directly
                    ;; above the heading, insert the separators above it so
                    ;; the canonical order (separators -> newpage -> heading)
                    ;; is preserved.
                    (let ((insert-pos heading-bol))
                      (save-excursion
                        (goto-char heading-bol)
                        (forward-line -1)
                        (when (looking-at-p "^#\\+LATEX:[ \t]+\\\\newpage[ \t]*$")
                          (setq insert-pos (line-beginning-position))))
                      (goto-char insert-pos)
                      (unless (save-excursion (forward-line -1) (looking-at-p "^[ \t]*$"))
                        (insert "\n"))
                      (insert "-----\n-----\n-----\n\n"))))))))))))

(defun aj/ensure-heading-newpages ()
  "Ensure `#+LATEX: \\newpage' sits immediately above each level-1 heading
except the first, so `C-c C-e l o' paginates top-level sections.

Self-healing: first sweeps out orphaned directives (those whose next
non-blank line is NOT a level-1 heading), then inserts canonical ones.
Orphaning happens when `aj/refresh-daily-recurring' or the overdue
bringers splice `** ' subtrees between a pre-existing directive and its
intended heading — the directive ends up stranded above the injected
subtree instead of above the heading it was meant for."
  (save-excursion
    (save-restriction
      (widen)
      ;; Phase 1: delete orphaned directives. `case-fold-search' is bound nil
      ;; so only UPPERCASE `#+LATEX:' heading directives are swept — the
      ;; lowercase `#+latex:' newpages that `aj/insert-problems-due' places
      ;; before `** Problems' and each `#+transclude:' survive (their next line
      ;; is a transclude, not a `* ' heading, so they would otherwise be
      ;; mis-detected as orphans and deleted).
      (goto-char (point-min))
      (let ((to-delete nil) (case-fold-search nil))
        (while (re-search-forward "^#\\+LATEX:[ \t]+\\\\newpage[ \t]*$" nil t)
          (let ((line-start (line-beginning-position))
                (orphan-p
                 (save-excursion
                   (forward-line 1)
                   (while (and (not (eobp))
                               (looking-at-p "^[ \t]*$"))
                     (forward-line 1))
                   (not (looking-at-p "^\\* ")))))
            (when orphan-p
              (push (cons line-start
                          (save-excursion
                            (goto-char line-start)
                            (forward-line 1)
                            (point)))
                    to-delete))))
        ;; Delete bottom-to-top to keep earlier positions valid.
        (dolist (range to-delete)
          (delete-region (car range) (cdr range))))
      ;; Phase 2: insert canonical directives.
      (goto-char (point-min))
      (let ((headings nil))
        (while (re-search-forward "^\\* " nil t)
          (push (line-beginning-position) headings))
        (setq headings (nreverse headings))
        (let ((len (length headings)))
          (when (>= len 2)
            (dotimes (j (1- len))
              (let* ((i (- len 1 j))
                     (heading-bol (nth i headings)))
                (goto-char heading-bol)
                (unless (save-excursion
                          (forward-line -1)
                          (looking-at-p "^#\\+LATEX:[ \t]+\\\\newpage[ \t]*$"))
                  (insert "#+LATEX: \\newpage\n"))))))))))

(provide 'daily-structure)

;;; daily-structure.el ends here
