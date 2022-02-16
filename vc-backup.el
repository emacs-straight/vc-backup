;;; vc-backup.el --- VC backend for versioned backups  -*- lexical-binding: t; -*-

;; Copyright (C) 2021  Free Software Foundation, Inc.

;; Author: Philip Kaludercic <philipk@posteo.net>
;; Maintainer: Philip Kaludercic <~pkal/public-inbox@lists.sr.ht>
;; URL: https://git.sr.ht/~pkal/vc-backup
;; Version: 1.1.0
;; Keywords: vc

;; vc-backup.el free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation, either version 3 of the License,
;; or (at your option) any later version.

;; vc-backup.el is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; For a copy of the license, please see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Find here a VC backend that uses backup files for versioning.  It
;; is recommended to enable `version-control' and related variables,
;; to make the most use of it.
;;
;; There is no need or ability to manually "commit" anything, as
;; backups should be generated automatically.  To force a backup, read
;; up on the documentation of `save-buffer'.  Backups can be viewed
;; using the command `vc-print-log'.

;;; Todo:

;; 1) Implement the rest of the vc interface.  See the comment at the
;; beginning of vc.el. The current status is:

;; FUNCTION NAME                                STATUS
;; BACKEND PROPERTIES
;; * revision-granularity                       OK
;; - update-on-retrieve-tag                     ??
;; STATE-QUERYING FUNCTIONS
;; * registered (file)                          OK
;; * state (file)                               OK
;; - dir-status-files (dir files update-function) ??
;; - dir-extra-headers (dir)                    ??
;; - dir-printer (fileinfo)                     ??
;; - status-fileinfo-extra (file)               ??
;; * working-revision (file)                    OK
;; * checkout-model (files)                     OK
;; - mode-line-string (file)                    ??
;; STATE-CHANGING FUNCTIONS
;; * create-repo ()                             ??
;; * register (files &optional comment)         ??
;; - responsible-p (file)                       OK
;; - receive-file (file rev)                    ??
;; - unregister (file)                          ??
;; * checkin (files comment &optional rev)      ??
;; * find-revision (file rev buffer)            OK
;; * checkout (file &optional rev)              OK
;; * revert (file &optional contents-done)      ??
;; - merge-file (file &optional rev1 rev2)      ??
;; - merge-branch ()                            ??
;; - merge-news (file)                          ??
;; - pull (prompt)                              ??
;; ? push (prompt)                              ??
;; - steal-lock (file &optional revision)       ??
;; - modify-change-comment (files rev comment)  ??
;; - mark-resolved (files)                      ??
;; - find-admin-dir (file)                      OK
;; HISTORY FUNCTIONS
;; * print-log (files buffer &optional shortlog start-revision limit) OK
;; * log-outgoing (buffer remote-location)      ??
;; * log-incoming (buffer remote-location)      ??
;; - log-search (buffer pattern)                ??
;; - log-view-mode ()                           OK
;; - show-log-entry (revision)                  ??
;; - comment-history (file)                     ??
;; - update-changelog (files)                   ??
;; * diff (files &optional rev1 rev2 buffer async) OK
;; - revision-completion-table (files)          OK
;; - annotate-command (file buf &optional rev)  ??
;; - annotate-time ()                           ??
;; - annotate-current-time ()                   ??
;; - annotate-extract-revision-at-line ()       ??
;; - region-history (file buffer lfrom lto)     ??
;; - region-history-mode ()                     ??
;; - mergebase (rev1 &optional rev2)            ??
;; TAG SYSTEM
;; - create-tag (dir name branchp)              ??
;; - retrieve-tag (dir name update)             ??
;; MISCELLANEOUS
;; - make-version-backups-p (file)              OK
;; - root (file)                                ??
;; - ignore (file &optional directory remove)   ??
;; - ignore-completion-table (directory)        ??
;; - previous-revision (file rev)               OK
;; - next-revision (file rev)                   OK
;; - log-edit-mode ()                           ??
;; - check-headers ()                           ??
;; - delete-file (file)                         OK
;; - rename-file (old new)                      OK
;; - find-file-hook ()                          ??
;; - extra-menu ()                              ??
;; - extra-dir-menu ()                          ??
;; - conflicted-files (dir)                     ??

;;; Code:

(eval-when-compile
  (require 'subr-x))

(require 'files)
(require 'cl-lib)
(require 'diff)
(require 'vc)
(require 'log-view)

;; Internal Functions

(defconst vc-backup--current-tag "real"
  "Tag used for the actual file.")

(defconst vc-backup--previous-tag "prev"
  "Tag used for unversioned backup.")

(defun vc-backup--get-real (file-or-backup)
  "Return the actual file behind FILE-OR-BACKUP."
  (if (backup-file-name-p file-or-backup)
      ;; FIXME: The user may overwrite
      ;; `make-backup-file-name-function' and use something else
      ;; besides exclamations points to save files.
      (replace-regexp-in-string
       "!!?"
       (lambda (rep)
         (if (= (length rep) 2) "!" "/"))
       (file-name-nondirectory
        (file-name-sans-versions file-or-backup)))
    file-or-backup))

(defun vc-backup--list-backups (file-or-list)
  "Generate a list of all backups for FILE-OR-LIST.
FILE-OR-LIST can either be a string or a list of strings.  This
function returns all backups for these files, in order of their
recency."
  (let (versions)
    (dolist (file (if (listp file-or-list) file-or-list (list file-or-list)))
      (let ((filename (thread-last (vc-backup--get-real file)
                        expand-file-name
                        make-backup-file-name
                        file-name-sans-versions)))
        (push (directory-files (file-name-directory filename) t
                               (concat (regexp-quote (file-name-nondirectory filename))
                                       file-name-version-regexp "\\'")
                               t)
              versions)))
    (sort (apply #'nconc versions) #'file-newer-than-file-p)))

(defun vc-backup--extract-version (file-or-backup)
  "Return a revision string for FILE-OR-BACKUP.
If FILE-OR-BACKUP is the actual file, the value of
`vc-backup--current-tag' is returned.  Otherwise, it returns the
version number as a string or the value of
`vc-backup--previous-tag' for unversioned backups."
  (cond ((not (backup-file-name-p file-or-backup)) vc-backup--current-tag)
        ((string-match (concat file-name-version-regexp "\\'") file-or-backup)
         (substring file-or-backup (match-beginning 0)))
        (t vc-backup--previous-tag)))

(defun vc-backup--list-backup-versions (file)
  "Return an association list of backup files and versions for FILE.
Each element of the list has the form (VERS . BACKUP), where VERS
is the version string as generated by
`vc-backup--extract-version' and BACKUP is the actual backup
file."
  (let (files)
    (dolist (backup (vc-backup--list-backups file))
      (push (cons (vc-backup--extract-version backup) backup)
            files))
    files))

(defun vc-backup--get-backup-file (file rev)
  "Return backup file for FILE of the version REV."
  (cond ((string= rev vc-backup--current-tag) file)
        ((string= rev vc-backup--previous-tag)
         (let ((prev (thread-last (expand-file-name file)
                       make-backup-file-name
                       file-name-sans-versions
                       (format "%~"))))
           (and (file-exists-p prev) prev)))
        ((cdr (assoc rev (vc-backup--list-backup-versions file))))))

(defun vc-backup--last-rev (file)
  "Return the revision of the last backup for FILE."
  (thread-last (vc-backup--list-backups file)
    car
    vc-backup--extract-version))

;; BACKEND PROPERTIES

(defun vc-backup-revision-granularity ()
  "Inform VC that this backend only operates on singular files."
  'file)

;; - update-on-retrieve-tag

;; STATE-QUERYING FUNCTIONS

;;;###autoload
(defun vc-backup-registered (file)
  "Inform VC that FILE will work if a backup can be found."
  (or (not (null (diff-latest-backup-file file)))
      (backup-file-name-p file)))

(defun vc-backup-state (_file)
  "Inform VC that there is no information about any file."
  nil)

;; - dir-status-files (dir files update-function)

;; - dir-extra-headers (dir)

;; - dir-printer (fileinfo)

;; - status-fileinfo-extra (file)

(defun vc-backup-working-revision (file)
  "Check if FILE is the real file or a backup."
  (vc-backup--extract-version file))

(defun vc-backup-checkout-model (_files)
  "Inform VC that files are not locked."
  'implicit)

;; - mode-line-string (file)

;; STATE-CHANGING FUNCTIONS

;; * create-repo ()

;; * register (files &optional comment)

;;;###autoload
(defun vc-backup-responsible-p (file)
  "Inform VC that this backend requires a backup for FILE."
  (not (null (diff-latest-backup-file file))))

;; - receive-file (file rev)

;; - unregister (file)

;; * checkin (files comment &optional rev)

(defun vc-backup-find-revision (file rev buffer)
  "Open a backup of the version REV for FILE in BUFFER."
  (with-current-buffer buffer
    (insert-file-contents (vc-backup--get-backup-file file rev))))

(defun vc-backup-checkout (file &optional rev)
  "Before copying an old version of FILE, force a backup.
If REV is non-nil, checkout that version."
  (cl-assert (= (length file) 1))
  (let ((backup-inhibited nil)
        (make-backup-files t))
    (with-current-buffer (find-file-noselect file)
      (backup-buffer)))
  (copy-file (vc-backup--get-backup-file file rev)
             file t))

;; * revert (file &optional contents-done)

;; - merge-file (file &optional rev1 rev2)

;; - merge-branch ()

;; - merge-news (file)

;; - pull (prompt)

;; ? push (prompt)

;; - steal-lock (file &optional revision)

;; - modify-change-comment (files rev comment)

;; - mark-resolved (files)

(defun vc-backup-find-admin-dir (file)
  "Inform VC that the FILE's backup directory is the administrative directory."
  (file-name-directory (diff-latest-backup-file file)))

;; HISTORY FUNCTIONS

(defun vc-backup-print-log (file buffer &optional _shortlog _start-revision _limit)
  "Generate a listing of old backup versions for FILE.
The results are written into BUFFER."
  (setq file (if (listp file) (car file) file))
  (with-current-buffer buffer
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert "Backups for " file "\n\n")
      (dolist (rev (nreverse (vc-backup--list-backup-versions file)))
        (let* ((attr (file-attributes (cdr rev)))
               (base (file-name-nondirectory file))
               (uid (file-attribute-user-id attr))
               (user (or (user-login-name uid) uid))
               (time (file-attribute-modification-time attr))
               (size (file-attribute-size attr))
               (date (format-time-string "%c" time)))
          (insert (format "%s%s\t%s (%s)\t%s\n" base (car rev) date user
                          (file-size-human-readable size nil " " "B"))))))
    (goto-char (point-min))
    (forward-line 2))
  'limit-unsupported)

;; * log-outgoing (buffer remote-location)

;; * log-incoming (buffer remote-location)

;; - log-search (buffer pattern)

(define-derived-mode vc-backup-log-view-mode log-view-mode "Backup Log"
  "VC-Log Mode for Backup."
  (setq-local log-view-file-re "\\`Backups for \\(.+\\)$")
  (setq-local log-view-message-re (concat "^.*?\\(" file-name-version-regexp "\\)")))

;; - show-log-entry (revision)

;; - comment-history (file)

;; - update-changelog (files)

(defun vc-backup-diff (files &optional rev1 rev2 buffer async)
  "Generate a diff for FILES between versions REV1 and REV2.
BUFFER and ASYNC as interpreted as specified in vc.el."
  (cl-assert (= (length files) 1))
  (setq rev1 (or rev1 vc-backup--current-tag))
  (setq rev2 (or rev2 (vc-backup--last-rev files)))
  (save-window-excursion
    (let ((dirty 0))
      (dolist (file files)
        (let ((diff (diff-no-select
                     (vc-backup--get-backup-file file rev2)
                     (vc-backup--get-backup-file file rev1)
                     (vc-switches 'Backup 'diff)
                     (not async)
                     (get-buffer (or buffer "*vc-diff*")))))
          (unless async
            (with-current-buffer diff
              (unless (search-forward "no differences" nil t)
                (setq dirty 1))))))
      dirty)))

(defun vc-backup-revision-completion-table (files)
  "Return a list of revisions for FILES."
  (cl-assert (= (length files) 1))
  (mapcar #'car (vc-backup--list-backup-versions (car files))))

;; - annotate-command (file buf &optional rev)

;; - annotate-time ()

;; - annotate-current-time ()

;; - annotate-extract-revision-at-line ()

;; - region-history (file buffer lfrom lto)

;; - region-history-mode ()

;; - mergebase (rev1 &optional rev2)

;; TAG SYSTEM

;; - create-tag (dir name branchp)

;; - retrieve-tag (dir name update)

;; MISCELLANEOUS

(defun vc-backup-make-version-backups-p (_file)
  "Always allow backup files to be made for this backend."
  t)

;; - root (file)

;; - ignore (file &optional directory remove)

;; - ignore-completion-table (directory)

(defun vc-backup-previous-revision (file rev)
  "Determine the revision before REV for FILE."
  (let* ((backups (vc-backup--list-backups file))
         (index (cl-position rev backups :key #'car)))
    (cond ((string= rev vc-backup--current-tag) (car backups))
          ((string= rev vc-backup--previous-tag) nil)
          ((and (natnump index) (> index 0))
           (car (nth (1- index) backups))))))

(defun vc-backup-next-revision (file rev)
  "Determine the revision after REV for FILE."
  (let* ((backups (vc-backup--list-backups file))
         (index (cl-position rev backups :key #'car)))
    (cond ((string= rev vc-backup--current-tag) nil)
          ((and (natnump index) (< index (length backups)))
           (car (nth (1+ index) backups)))
          (t vc-backup--current-tag))))

;; - log-edit-mode ()

;; - check-headers ()

(defun vc-backup-delete-file (file)
  "Delete FILE and all its backups."
  (dolist (backup (vc-backup--list-backups file))
    (delete-file backup))
  (delete-file file))

(defun vc-backup-rename-file (old-file new-file)
  "Rename OLD-FILE to NEW-FILE and all its backup accordingly."
  (rename-file old-file new-file)
  (let ((new-part (thread-last (expand-file-name new-file)
                    make-backup-file-name
                    file-name-sans-versions))
        (old-part (thread-last (expand-file-name old-file)
                    make-backup-file-name
                    file-name-sans-versions)))
    (dolist (backup (vc-backup--list-backups old-file))
      (let ((new-backup (concat new-part (substring backup (length old-part)))))
        (rename-file backup new-backup t)))))

;; - find-file-hook ()

;; - extra-menu ()

;; - extra-dir-menu ()

;; - conflicted-files (dir)

;;; This snippet enables the Backup VC backend so it will work once
;;; this file is loaded.  By also marking it for inclusion in the
;;; autoloads file, installing packaged versions of this should work
;;; without users having to monkey with their init files.

;;;###autoload
(add-to-list 'vc-handled-backends 'Backup t)

(provide 'vc-backup)

;;; vc-backup.el ends here
