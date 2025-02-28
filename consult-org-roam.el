;;; consult-org-roam.el --- Consult integration for org-roam  -*- lexical-binding: t; -*-
;; Copyright (C) 2022 jgru

;; Author: jgru <https://github.com/jgru>
;; Created: March 3rd, 2022
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Version: 0.1
;; Homepage: https://github.com/jgru/consult-org-roam
;; Package-Requires: ((emacs "27.1") (org-roam "2.2.0") (consult "0.16"))

;;; Commentary:

;; This is a set of functions to use org-roam with consult.
;; This packages replaces org-roam's own completing read functions
;; with equivalent versions utilizing consult's internal API. By doing so,
;; one gains all advantages of consult which enhances Emacs' own
;; completing-read funcionality.

;;; Code:

;; ============================================================================
;;;; Dependencies
;; ============================================================================

(require 'org-roam)
(require 'consult)

;; ============================================================================
;;;; Customize definitions
;; ============================================================================

(defgroup consult-org-roam nil
  "Consult interface for org-roam."
  :group 'org
  :group 'convenience
  :prefix "consult-org-roam-")

(defcustom consult-org-roam-grep-func #'consult-ripgrep
  "Function for searching files."
   :type 'function
   :group 'consult-org-roam)

;; ============================================================================
;;;; Functions
;; ============================================================================

(defun consult-org-roam-search (&optional initial)
  "Search org-roam directory using `consult-ripgrep' with live-preview.
With an option for INITIAL input when called non-interactively."
  (interactive)
  (if initial
      (funcall consult-org-roam-grep-func org-roam-directory (format "%s" initial))
    (funcall consult-org-roam-grep-func org-roam-directory)))

(defun consult-org-roam--select-file (&optional prompt list)
  "Wrapper around `consult--read' to select an org-roam file.
Offers candidates withing `org-roam-directory', or from LIST when
supplied. Can take a PROMPT argument."
  (let* ((files (if list list
                  (org-roam-list-files)))
         (prompt (if prompt prompt
                 "Select File: ")))
    (consult--read
     files
     :prompt prompt
     :sort t
     :require-match t
     :state (consult--file-preview))))

(defun consult-org-roam--ids-to-files (ids)
  "Take a bunch of IDS of org-roam-nodes and convert those into file paths."
  (mapcar (lambda (id)
              (org-roam-node-file (org-roam-node-from-id (car id))))
         ids))

;;;###autoload
(defun consult-org-roam-backlinks ()
  "Select from list of all notes that link to the current note."
  (interactive)
  (let* ((node (org-roam-node-at-point))
         (ids (mapcar (lambda (el) (car el))(org-roam-db-query
            [:select [source]
                     :from links
                     :where (= dest $s1)
                     :and (= type "id")]
            (if node
                (org-roam-node-id (org-roam-node-at-point))
              (user-error "Buffer does not contain org-roam-nodes"))))))
    (if ids
        (consult-org-roam-node-read "" (lambda (n)
                                 (if (org-roam-node-p n)
                                     (if (member (org-roam-node-id n) ids)
                                         t
                                       nil))))
      (user-error "No backlinks found"))))

;;;###autoload
(defun consult-org-roam-forward-links ()
  "Select a forward link contained in the current buffer."
  (interactive)
  (let ((id-links '()))
    (org-element-map (org-element-parse-buffer) 'link
      (lambda (link)
        (when (string= (org-element-property :type link) "id")
          (push
           (org-element-property :path link) id-links))))
    (if id-links
        (consult-org-roam-node-read "" (lambda (n)
                                 (if (org-roam-node-p n)
                                     (if (member (org-roam-node-id n) id-links)
                                         t
                                       nil))))
      (user-error "No forward links found"))))

;;;###autoload
(defun consult-org-roam-file-find ()
  "Find org-roam node with preview."
  (interactive "")
  (find-file (consult-org-roam--select-file "Node: ")))

;; Completing-read interface using consult. Override
;; `org-roam-node-read' so that each an every completing function
;; resorts to consult
(defun consult-org-roam-node-read (&optional initial-input filter-fn sort-fn
                                     require-match prompt)
  "Read and return an `org-roam-node' with the help of consult.
INITIAL-INPUT is the initial minibuffer prompt value.
FILTER-FN is a function to filter out nodes: it takes an `org-roam-node',
and when nil is returned the node will be filtered out.
SORT-FN is a function to sort nodes. See `org-roam-node-read-sort-by-file-mtime'
for an example sort function.filter-fn sort-fn
If REQUIRE-MATCH, the minibuffer prompt will require a match.
PROMPT is a string to show at the beginning of the mini-buffer,
defaulting to \"Node: \""
  (let* ((nodes (org-roam-node-read--completions filter-fn sort-fn)) ;;
         (prompt (or prompt "Node: "))
         ;; Sets state-func only when there are nodes to avoid errors
         ;; with empty roam-dirs
         (state-func (when nodes
                       (consult-org-roam--node-preview)))
         (node
          (consult--read
           nodes
           :prompt prompt
           :initial initial-input
           :sort sort-fn
           :require-match require-match
           :category 'org-roam-node
           ;;:history 'org-roam-node-history
           :state state-func
           ;; Uses the DEFAULT argument of alist-get to return input in case the input is not found as key.
           :lookup (lambda (selected candidates input narrow) (alist-get selected candidates input nil #'equal)))))
    (if (org-roam-node-p node) (progn node)
      (progn (org-roam-node-create :title node)))))

(defun consult-org-roam--node-preview ()
  "Create preview function for nodes."
  (let ((open (consult--temporary-files))
        (preview (consult--buffer-preview)))
    (lambda (action cand)
      (when (eq action 'exit)
        (funcall open))
      (if (org-roam-node-p cand)
          (funcall preview action
                   (and cand
                        (eq action 'preview)
                        (set-window-start
                         (selected-window)
                         (org-roam-node-point cand))
                        (funcall open (org-roam-node-file cand))))))))

;; Completing-read interface for references using consult. Override
;; `org-roam-ref-read' so that each an every completing function
;; regarding refs resorts to consult
(defun consult-org-roam-ref-read (&optional initial-input filter-fn)
  "Read a ref and return its `org-roam-node' with the help of consult.
INITIAL-INPUT is the initial prompt value.
FILTER-FN is a function to filter out nodes: it takes an `org-roam-node',
and when nil is returned the node will be filtered out.
filtered out."
  (let* ((refs (org-roam-ref-read--completions))
         (refs (cl-remove-if-not (lambda (n)
                                   (if filter-fn (funcall filter-fn (cdr n)) t)) refs))
         (ref (consult--read
                refs
                :prompt "Refs: "
                :initial initial-input
                :predicate filter-fn
                :require-match t
                :category 'org-roam-ref
                :history 'org-roam-ref-history
                :state (consult-org-roam--node-preview)
                :lookup #'consult--lookup-cdr)))
    (progn ref)))

;;;###autoload
(define-minor-mode consult-org-roam-mode
  "Toggle `consult-org-roam-mode' to integrate consult with org-roam.
By enabling `consult-org-roam-mode' the functions `org-roam-node-read' and
`org-roam-ref-read' are overriden by consults-org-roam's equivalents. Optional
argument ARG indicates whether the mode should be enabled or disabled."
  :lighter " cor"
  ;; Add or remove advice when enabled respectively disabled
  (if consult-org-roam-mode
      (progn
        (advice-add #'org-roam-node-read :override #'consult-org-roam-node-read)
        (advice-add #'org-roam-ref-read :override #'consult-org-roam-ref-read))
    (progn
      (advice-remove #'org-roam-node-read #'consult-org-roam-node-read)
      (advice-remove #'org-roam-ref-read #'consult-org-roam-ref-read))))

(provide 'consult-org-roam)
;;; consult-org-roam.el ends here
