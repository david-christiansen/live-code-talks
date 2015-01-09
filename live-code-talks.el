;;; live-code-talks.el --- Support for slides with live code in them  -*- lexical-binding: t; -*-

;; Copyright (C) 2015 David Raymond Christiansen

;; Author: David Raymond Christiansen <david@davidchristiansen.dk>
;; Keywords: docs, multimedia
;; Package-Requires: ((emacs "24") (cl-lib "0.5") (narrowed-page-navigation "0.1"))
;; Version: 0.1.0

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides a minor mode for formatting an Emacs buffer
;; as slides. This package relies on `narrowed-page-navigation-mode'
;; to actually navigate from slide to slide, and instead provides
;; syntax for comments that are rendered as slide elements.
;;
;; The syntax comes pre-configured for Idris or Haskell. For other
;; languages, set `live-code-talks-title-regexp',
;; `live-code-talks-image-regexp', and
;; `live-code-talks-comment-regexp', preferably as file variables.
;; For your presentation, consider also overriding
;; `face-remapping-alist' to get the proper fonts for your screen.
;;; Code:

(require 'cl-lib)
(require 'linum)
(require 'narrowed-page-navigation)

(defgroup live-code-talks ()
  "Settings for live code talks"
  :group 'multimedia)

(defface live-code-talks-title-face
  '((t (:height 2.0)))
  "Face for showing slide titles"
  :group 'live-code-talks)

(defvar live-code-talks-title-regexp "^\\s-*--\\s-*#\\s-*\\(.+\\)$"
  "The regexp to match for slide titles.  The contents of match group 1 will be highlighted.")
(make-variable-buffer-local 'live-code-talks-title-regexp)

(defun live-code-talks-highlight-titles (&optional buffer)
  "Place highlighting on all titles in BUFFER, or the current buffer if nil.

To change the format used for titles, set `live-code-talks-title-regexp'."
  (with-current-buffer (or buffer (current-buffer))
    (save-restriction
      (widen)
      (save-excursion
        (goto-char (point-min))
        (while (re-search-forward live-code-talks-title-regexp nil t)
          ;; First make an overlay applying the title face to the
          ;; actual title, in match group 1
          (let ((title-overlay (make-overlay (match-beginning 1) (match-end 1)))
                (title-area-overlay (make-overlay (match-beginning 0) (match-end 0))))
            (overlay-put title-overlay 'live-code-talks 'title)
            (overlay-put title-overlay 'face            'live-code-talks-title-face)
            (overlay-put title-overlay 'display         t)
            (overlay-put title-overlay 'intangible      'title)
            (overlay-put title-area-overlay 'live-code-talks 'title)
            (overlay-put title-area-overlay 'display         "")))))))

(defun live-code-talks-unhighlight (what &optional buffer)
  "Delete all WHAT highlighting in BUFFER, or the current buffer if nil.

 WHAT can be `title', `image', or `comment'."
  (with-current-buffer (or buffer (current-buffer))
    (save-restriction
      (widen)
      (save-excursion
        (let ((overlays (overlays-in (point-min) (point-max))))
          (cl-loop for overlay in overlays
                   when (eq (overlay-get overlay 'live-code-talks) what)
                   do (delete-overlay overlay)))))))

(defvar live-code-talks-image-regexp "^\\s-*--\\s-*\\[\\[\\[\\([^]]+\\)\\]\\]\\]\\s-*$"
  "A regexp to determine which images should be shown.  Group 1 should be the filename relative to the current buffer's file.")

(defun live-code-talks-show-images (&optional buffer)
  "Replace images matching `live-code-talks-image-regexp' with the actual image in BUFFER, or the current buffer if nil."
  (with-current-buffer (or buffer (current-buffer))
    (save-restriction
      (widen)
      (save-excursion
        (goto-char (point-min))
        (while (re-search-forward live-code-talks-image-regexp nil t)
          (let* ((file-name (expand-file-name (match-string 1) (file-name-directory (buffer-file-name buffer))))
                 (image `(image :type imagemagick
                                :file ,file-name
                                :max-height ,(floor (* 0.7 (window-pixel-height)))
                                :max-width ,(floor (* 0.9 (window-pixel-width)))))
                 (image-overlay (make-overlay (match-beginning 0) (match-end 0))))
            (overlay-put image-overlay 'live-code-talks 'image)
            (overlay-put image-overlay 'display         image)
            (overlay-put image-overlay 'intangible      'image)))))))

(defface live-code-talks-comment-face
  '((t (:inherit default)))
  "Face used for stripped-out comments"
  :group 'live-code-talks)

(defvar live-code-talks-comment-regexp "^ *--\\( *[^[ #].*\\| *\\)$"
  "The regexp to match for slide titles.  The contents of match group 1 will be highlighted.")
(make-variable-buffer-local 'live-code-talks-comment-regexp)

(defun live-code-talks-highlight-comments (&optional buffer)
  "Place highlighting on normal comments in BUFFER, or the current buffer if nil.

To change the format used for comments, set `live-code-talks-comment-regexp'."
  (with-current-buffer (or buffer (current-buffer))
    (save-restriction
      (widen)
      (save-excursion
        (goto-char (point-min))
        (while (re-search-forward live-code-talks-comment-regexp nil t)
          ;; First make an overlay applying the comment face to the
          ;; actual comment, in match group 1
          (let ((comment-overlay (make-overlay (match-beginning 1) (match-end 1)))
                (comment-area-overlay (make-overlay (match-beginning 0) (match-end 0))))
            (overlay-put comment-overlay 'live-code-talks 'comment)
            (overlay-put comment-overlay 'face            'live-code-talks-comment-face)
            (overlay-put comment-overlay 'display         t)
            (overlay-put comment-overlay 'intangible      'comment)
            (overlay-put comment-area-overlay 'read-only       t)
            (overlay-put comment-area-overlay 'live-code-talks 'comment)
            (overlay-put comment-area-overlay 'display         "")))))))


(defvar live-code-talks-restore-linum nil
  "Whether to re-enable linum on exit from slide mode.")
(make-variable-buffer-local 'live-code-talks-restore-linum)

(define-minor-mode live-code-talks-mode
  "A minor mode for presenting a code buffer as slides."
  nil "Talk" nil
  (if live-code-talks-mode
      (progn
        (setq live-code-talks-restore-linum linum-mode)
        (linum-mode -1)
        (live-code-talks-highlight-titles)
        (live-code-talks-show-images)
        (live-code-talks-highlight-comments)
        (narrow-to-page)
        (narrowed-page-navigation-mode 1))
    (progn
      (when live-code-talks-restore-linum (linum-mode 1))
      (widen)
      (narrowed-page-navigation-mode -1)
      (live-code-talks-unhighlight 'title)
      (live-code-talks-unhighlight 'image)
      (live-code-talks-unhighlight 'comment))))


(provide 'live-code-talks)
;;; live-code-talks.el ends here
