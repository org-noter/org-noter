;;; org-noter-pdf.el --- Modules for PDF-Tools and DocView mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2022  c1-g

;; Author: c1-g <char1iegordon@protonmail.com>
;; Keywords: multimedia

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:
(eval-when-compile (require 'subr-x))
(require 'cl-lib)
(require 'org-noter-core)
(eval-when-compile ; ensure that the compiled code knows about PDF-TOOLS, if installed
  (condition-case nil
      (require 'pdf-tools)
    (error (message "`pdf-tools' package not found"))))
(condition-case nil ; inform user at run time if pdf-tools is missing
    (require 'pdf-tools)
  (error (message "ATTENTION: org-noter-pdf has many featues that depend on the package `pdf-tools'")))

(push "pdf" org-noter--doc-extensions)
(cl-defstruct pdf-highlight page coords)

(defun org-noter-pdf--get-highlight ()
  "If there's an active pdf selection, returns a  that contains all
the relevant info (page, coordinates)

Otherwise returns nil"
    (if-let* ((_ (pdf-view-active-region-p))
               (page (image-mode-window-get 'page))
               (coords (pdf-view-active-region)))
       (make-pdf-highlight :page page :coords coords)
      nil))

(add-to-list 'org-noter--get-highlight-location-hook 'org-noter-pdf--get-highlight)

(defcustom org-noter-store-link-markup-annotation nil
  "Control the highlighting behaviour when storing a link to a PDF region.

This variable accepts three values:
- t       : Add a permanent highlight annotation to the PDF file.
            The link will also contain the region coordinates for robustness.
- 'flash  : Do NOT modify the PDF file. Instead, store the region coordinates
            inside the link itself. The region will flash when the link is opened.
- nil     : Do not annotate the PDF and do not store region coordinates.
            The link points to the location, but no flashing occurs.

Interactively, using a prefix argument (C-u) toggles this behaviour:
- If currently non-nil (t or 'flash), it forces behaviour to nil (off).
- If currently nil, it forces behaviour to t (annotate)."
  :group 'org-noter-insertion
  :type '(choice (const :tag "Annotate PDF (Permanent)" t)
                 (const :tag "Flash Region Only (No PDF mod)" flash)
                 (const :tag "No Highlight/Flash" nil)))

(defcustom org-noter-highlight-link-color "#00CFFF"
  "Color for link-based (pdf: link with edges) annotations."
  :type 'string
  :group 'org-noter)

(defcustom org-noter-highlight-rectangle-color "#FF69B4"
  "Color for rectangle-region (rect: prefix) annotations."
  :type 'string
  :group 'org-noter)

(defun org-noter-pdf--pretty-print-highlight (highlight-info)
  (format "%s" highlight-info))

(add-to-list 'org-noter--pretty-print-highlight-location-hook #'org-noter-pdf--pretty-print-highlight)

(defun org-noter-pdf--approx-location-cons (mode &optional precise-info _force-new-ref)
  "Return location as a cons cell.
Runs when MODE is `doc-view-mode' or `pdf-view-mode'

Returns page location as (page . 0).  When processing
PRECISE-INFO, return (page v-pos) or (page v-pos . h-pos)."
  (when (memq mode '(doc-view-mode pdf-view-mode))
    (cons (image-mode-window-get 'page) (if (or (numberp precise-info)
                                                (and (consp precise-info)
                                                     (numberp (car precise-info))
                                                     (numberp (cdr precise-info))))
                                            precise-info 0))))

(add-to-list 'org-noter--doc-approx-location-hook #'org-noter-pdf--approx-location-cons)

(defun org-noter-pdf--get-buffer-file-name (&optional _mode)
  "Return the file naming backing the document buffer.

MODE (unused) is required for this type of hook."
  (bound-and-true-p pdf-file-name))

(add-to-list 'org-noter-get-buffer-file-name-hook #'org-noter-pdf--get-buffer-file-name)

(defun org-noter-pdf--pdf-view-setup-handler (mode)
  (when (eq mode 'pdf-view-mode)
    ;; (setq buffer-file-name document-path)
    (pdf-view-mode)
    (add-hook 'pdf-view-after-change-page-hook 'org-noter--doc-location-change-handler nil t)
    t))

(add-to-list 'org-noter-set-up-document-hook #'org-noter-pdf--pdf-view-setup-handler)

(defun org-noter-pdf--doc-view-setup-handler (mode)
  (when (eq mode 'doc-view-mode)
    ;; (setq buffer-file-name document-path)
    (doc-view-mode)
    (advice-add 'doc-view-goto-page :after 'org-noter--location-change-advice)
    t))

(add-to-list 'org-noter-set-up-document-hook #'org-noter-pdf--doc-view-setup-handler)

(defun org-noter-pdf--no-sessions-remove-advice ()
  "Remove doc-view-specific advice when all sessions are closed."
  (advice-remove 'doc-view-goto-page 'org-noter--location-change-advice))

(add-to-list 'org-noter--no-sessions-remove-advice-hooks #'org-noter-pdf--no-sessions-remove-advice)

(defun org-noter-pdf--pretty-print-location (location)
  "Formats LOCATION with full precision for property drawers."
  (org-noter--with-valid-session
   (when (memq (org-noter--session-doc-mode session) '(doc-view-mode pdf-view-mode))
     (format "%s" (if (or (not (org-noter--get-location-top location)) (<= (org-noter--get-location-top location) 0))
                      (car location)
                    location)))))

(add-to-list 'org-noter--pretty-print-location-hook #'org-noter-pdf--pretty-print-location)

(defun org-noter-pdf--pretty-print-location-for-title (location)
  "Convert LOCATION to a human readable format.
With `pdf-view-mode', the format uses pagelabel and vertical and
horizontal percentages.  With `doc-view-mode', this falls back to
original pretty-print function."
  (org-noter--with-valid-session
   (let ((mode (org-noter--session-doc-mode session))
         (vpos (org-noter--get-location-top location))
         (hpos (org-noter--get-location-left location))
         (vtxt "") (htxt "")
         pagelabel)
     (cond ((eq mode 'pdf-view-mode) ; for default title, reference pagelabel instead of page
            (if (> hpos 0)
                (setq htxt (format " H: %d%%" (round (* 100 hpos)))))
            (if (or (> vpos 0) (> hpos 0))
                (setq vtxt (format " V: %d%%" (round (* 100 vpos)))))
            (select-window (org-noter--get-doc-window))
            (setq pagelabel (pdf-view-current-pagelabel))
            (select-window (org-noter--get-notes-window))
            (format "%s%s%s" pagelabel vtxt htxt))
           ((eq mode 'doc-view-mode) ; fall back to original pp for doc-mode
            (org-noter-pdf--pretty-print-location location))))))

(add-to-list 'org-noter--pretty-print-location-for-title-hook #'org-noter-pdf--pretty-print-location-for-title)

(defun org-noter-pdf--pdf-view-get-precise-info (mode window)
  (when (eq mode 'pdf-view-mode)
    (let (v-position h-position)
      (if (and (pdf-view-active-region-p)
	       (cadr (pdf-view-active-region))) ; ensure the edges are ACTUALLY populated (needed for pdf-tools v1.3.0)
          (let ((edges (cadr (pdf-view-active-region))))
            (setq v-position (min (nth 1 edges) (nth 3 edges))
                  h-position (min (nth 0 edges) (nth 2 edges))))

        ;; fallback
        (let ((event nil))
          (while (not (and (eq 'mouse-1 (car event))
                           (eq window (posn-window (event-start event)))))
            (setq event (read-event "Click where you want the start of the note to be!")))
          (let* ((col-row (posn-col-row (event-start event)))
                 (click-position (org-noter--conv-page-scroll-percentage
                                  (+ (window-vscroll) (cdr col-row))
                                  (+ (window-hscroll) (car col-row)))))
            (setq v-position (car click-position)
                  h-position (cdr click-position)))))
      (cons v-position h-position))))

(add-to-list 'org-noter--get-precise-info-hook #'org-noter-pdf--pdf-view-get-precise-info)

(defun org-noter-pdf--doc-view-get-precise-info (mode window)
  (when (eq mode 'doc-view-mode)
    (let ((event nil))
      (while (not (and (eq 'mouse-1 (car event))
                       (eq window (posn-window (event-start event)))))
        (setq event (read-event "Click where you want the start of the note to be!")))
      (org-noter--conv-page-scroll-percentage (+ (window-vscroll)
                                                 (cdr (posn-col-row (event-start event))))))))

(add-to-list 'org-noter--get-precise-info-hook #'org-noter-pdf--doc-view-get-precise-info)

(defun org-noter-pdf--goto-location (mode location window)
  (when (memq mode '(doc-view-mode pdf-view-mode))
    (let ((top (org-noter--get-location-top location))
          (left (org-noter--get-location-left location)))

      (if (eq mode 'doc-view-mode)
          (doc-view-goto-page (org-noter--get-location-page location))
        (pdf-view-goto-page (org-noter--get-location-page location))
        ;; NOTE(nox): This timer is needed because the tooltip may introduce a delay,
        ;; so syncing multiple pages was slow
        (when (>= org-noter-arrow-delay 0)
          (when org-noter--arrow-location (cancel-timer (aref org-noter--arrow-location 0)))
          (setq org-noter--arrow-location
                (vector (run-with-idle-timer org-noter-arrow-delay nil 'org-noter--show-arrow)
                        window
                        top
                        left))))
      (image-scroll-up (- (org-noter--conv-page-percentage-scroll top)
                          (floor (+ (window-vscroll) org-noter-vscroll-buffer)))))))

(add-to-list 'org-noter--doc-goto-location-hook #'org-noter-pdf--goto-location)

(defun org-noter-pdf--get-current-view (mode)
  (when (memq mode '(doc-view-mode pdf-view-mode))
    (vector 'paged (car (org-noter-pdf--approx-location-cons mode)))))

(add-to-list 'org-noter--get-current-view-hook #'org-noter-pdf--get-current-view)

(defun org-noter-pdf--get-selected-text (mode)
  (when (and (eq mode 'pdf-view-mode)
             (pdf-view-active-region-p))
    (mapconcat 'identity (pdf-view-active-region-text) ? )))

(add-to-list 'org-noter-get-selected-text-hook #'org-noter-pdf--get-selected-text)

;; NOTE(nox): From machc/pdf-tools-org
(defun org-noter-pdf--edges-to-region (edges)
  "Get 4-entry region (LEFT TOP RIGHT BOTTOM) from several EDGES."
  (when edges
    (let ((left0 (nth 0 (car edges)))
          (top0 (nth 1 (car edges)))
          (bottom0 (nth 3 (car edges)))
          (top1 (nth 1 (car (last edges))))
          (right1 (nth 2 (car (last edges))))
          (bottom1 (nth 3 (car (last edges)))))
      (list left0
            (+ top0 (/ (- bottom0 top0) 3))
            right1
            (- bottom1 (/ (- bottom1 top1) 3))))))

(defalias 'org-noter--pdf-tools-edges-to-region 'org-noter-pdf--edges-to-region
  "For ORG-NOTER-PDFTOOLS backward compatiblity.  The name of the
underlying function is currently under discussion")

(defun org-noter-pdf--create-skeleton (mode)
  "Create notes skeleton with the PDF outline or annotations."
  (when (eq mode 'pdf-view-mode)
    (org-noter--with-valid-session
     (let* ((ast (org-noter--parse-root))
            (top-level (or (org-element-property :level ast) 0))
            (options '(("Outline" . (outline))
                       ("Annotations" . (annots))
                       ("Both" . (outline annots))))
            answer output-data)
       (with-current-buffer (org-noter--session-doc-buffer session)
         (setq answer (assoc (completing-read "What do you want to import? " options nil t) options))

         (when (memq 'outline answer)
           (dolist (item (pdf-info-outline))
             (let ((type (alist-get 'type item))
                   (page (alist-get 'page item))
                   (depth (alist-get 'depth item))
                   (title (alist-get 'title item))
                   (top (alist-get 'top item)))
               (when (and (eq type 'goto-dest) (> page 0))
                 (push (vector title (cons page top) (1+ depth) nil) output-data)))))

         (when (memq 'annots answer)
           (let ((possible-annots (list '("Highlights" . highlight)
                                        '("Underlines" . underline)
                                        '("Squigglies" . squiggly)
                                        '("Text notes" . text)
                                        '("Strikeouts" . strike-out)
                                        '("Links" . link)
                                        '("ALL" . all)))
                 chosen-annots insert-contents pages-with-links)
             (while (> (length possible-annots) 1)
               (let* ((chosen-string (completing-read "Which types of annotations do you want? "
                                                      possible-annots nil t))
                      (chosen-pair (assoc chosen-string possible-annots)))
                 (cond ((eq (cdr chosen-pair) 'all)
                        (dolist (annot possible-annots)
                          (when (and (cdr annot) (not (eq (cdr annot) 'all)))
                            (push (cdr annot) chosen-annots)))
                        (setq possible-annots nil))
                       ((cdr chosen-pair)
                        (push (cdr chosen-pair) chosen-annots)
                        (setq possible-annots (delq chosen-pair possible-annots))
                        (when (= 1 (length chosen-annots)) (push '("DONE") possible-annots)))
                       (t
                        (setq possible-annots nil)))))

             (setq insert-contents (y-or-n-p "Should we insert the annotations contents? "))

             (dolist (item (pdf-info-getannots))
               (let* ((type (alist-get 'type item))
                      (page (alist-get 'page item))
                      (edges (or (org-noter-pdf--edges-to-region (alist-get 'markup-edges item))
                                 (alist-get 'edges item)))
                      (top (nth 1 edges))
                      (item-subject (alist-get 'subject item))
                      (item-contents (alist-get 'contents item))
                      name contents)
                 (when (and (memq type chosen-annots) (> page 0))
                   (if (eq type 'link)
                       (cl-pushnew page pages-with-links)
                     (setq name (cond ((eq type 'highlight) "Highlight")
                                      ((eq type 'underline) "Underline")
                                      ((eq type 'squiggly) "Squiggly")
                                      ((eq type 'text) "Text note")
                                      ((eq type 'strike-out) "Strikeout")))

                     (when insert-contents
                       (setq contents (cons (pdf-info-gettext page edges)
                                            (and (or (and item-subject (> (length item-subject) 0))
                                                     (and item-contents (> (length item-contents) 0)))
                                                 (concat (or item-subject "")
                                                         (if (and item-subject item-contents) "\n" "")
                                                         (or item-contents ""))))))

                     (push (vector (format "%s on page %d" name page) (cons page top) 'inside contents)
                           output-data)))))

             (dolist (page pages-with-links)
               (let ((links (pdf-info-pagelinks page))
                     type)
                 (dolist (link links)
                   (setq type (alist-get 'type link))
                   (unless (eq type 'goto-dest) ;; NOTE(nox): Ignore internal links
                     (let* ((edges (alist-get 'edges link))
                            (title (alist-get 'title link))
                            (top (nth 1 edges))
                            (target-page (alist-get 'page link))
                            target heading-text)

                       (unless (and title (> (length title) 0)) (setq title (pdf-info-gettext page edges)))

                       (cond
                        ((eq type 'uri)
                         (setq target (alist-get 'uri link)
                               heading-text (format "Link on page %d: [[%s][%s]]" page target title)))

                        ((eq type 'goto-remote)
                         (setq target (concat "file:" (alist-get 'filename link))
                               heading-text (format "Link to document on page %d: [[%s][%s]]" page target title))
                         (when target-page
                           (setq heading-text (concat heading-text (format " (target page: %d)" target-page)))))

                        (t (error "Unexpected link type")))

                       (push (vector heading-text (cons page top) 'inside nil) output-data))))))))


         (when output-data
           (if (memq 'annots answer)
               (setq output-data
                     (sort output-data
                           (lambda (e1 e2)
                             (or (not (aref e1 1))
                                 (and (aref e2 1)
                                      (org-noter--compare-locations '< (aref e1 1) (aref e2 1)))))))
             (setq output-data (nreverse output-data)))

           (push (vector "Skeleton" nil 1 nil) output-data)))

       (with-current-buffer (org-noter--session-notes-buffer session)
         ;; NOTE(nox): org-with-wide-buffer can't be used because we want to reset the
         ;; narrow region to include the new headings
         (widen)
         (save-excursion
           (goto-char (org-element-property :end ast))

           (let (last-absolute-level
                 title location relative-level contents
                 level)
             (dolist (data output-data)
               (setq title (aref data 0)
                     location (aref data 1)
                     relative-level (aref data 2)
                     contents (aref data 3))

               (if (symbolp relative-level)
                   (setq level (1+ last-absolute-level))
                 (setq last-absolute-level (+ top-level relative-level)
                       level last-absolute-level))

               (org-noter--insert-heading level title)

               (when location
                 (org-entry-put nil org-noter-property-note-location (org-noter--pretty-print-location location)))

               (when org-noter-doc-property-in-notes
                 (org-entry-put nil org-noter-property-doc-file (org-noter--session-property-text session))
                 (org-entry-put nil org-noter--property-auto-save-last-location "nil"))

               (when (car contents)
                 (org-noter--insert-heading (1+ level) "Contents")
                 (insert (car contents)))
               (when (cdr contents)
                 (org-noter--insert-heading (1+ level) "Comment")
                 (insert (cdr contents)))))

           (setq ast (org-noter--parse-root))
           (org-noter--narrow-to-root ast)
           (goto-char (org-element-property :begin ast))
           (outline-hide-subtree)
           (org-show-children 2)))
       output-data))))

(add-to-list 'org-noter-create-skeleton-functions #'org-noter-pdf--create-skeleton)

(defun org-noter-pdf--create-missing-annotation ()
  "Add a highlight from a selected note."
  (let ((location (org-noter--parse-location-property (org-noter--get-containing-element)))
        (window (org-noter--get-doc-window)))
    (org-noter-pdf--goto-location 'pdf-view-mode location window)
    (pdf-annot-add-highlight-markup-annotation (cdr location))))

(defun org-noter-pdf--highlight-location (mode precise-location)
  "Highlight a precise location in PDF."
  (message "---> %s %s" mode precise-location)
  (when (and (memq mode '(doc-view-mode pdf-view-mode))
             (pdf-view-active-region-p))
    (pdf-annot-add-highlight-markup-annotation (pdf-view-active-region))))

(add-to-list 'org-noter--add-highlight-hook #'org-noter-pdf--highlight-location)

(defun org-noter-pdf--convert-to-location-cons (location)
  "Encode precise LOCATION as a cons cell for note insertion ordering.
Converts (page v . h) precise locations to (page v') such that
v' represents the fractional distance through the page along
columns, so it takes values between 0 and the number of columns.
Each column is specified by its right edge as a fractional
horizontal position.  Output is nil for standard notes and (page
v') for precise notes."
  (if-let* ((_ (and (consp location) (consp (cdr location))))
            (column-edges-string (when (derived-mode-p 'org-mode) (org-entry-get nil "COLUMN_EDGES" t)))
            (right-edge-list (car (read-from-string column-edges-string)))
            ;;(ncol (length left-edge-list))
            (page (car location))
            (v-pos (cadr location))
            (h-pos (cddr location))
            (column-index (seq-position right-edge-list h-pos #'>=)))
      (cons page (+ v-pos column-index))))

(add-to-list 'org-noter--convert-to-location-cons-hook #'org-noter-pdf--convert-to-location-cons)

(defun org-noter-pdf--show-arrow ()
  ;; From `pdf-util-tooltip-arrow'.
  (pdf-util-assert-pdf-window)
  (let* (x-gtk-use-system-tooltips
         (arrow-top  (aref org-noter--arrow-location 2)) ; % of page
         (arrow-left (aref org-noter--arrow-location 3))
         (image-top  (if (floatp arrow-top)
                         (round (* arrow-top  (cdr (pdf-view-image-size)))))) ; pixel location on page (magnification-dependent)
         (image-left (if (floatp arrow-left)
                         (floor (* arrow-left (car (pdf-view-image-size))))))
         (dx (or image-left
                 (+ (or (car (window-margins)) 0)
                    (car (window-fringes)))))
         (dy (or image-top 0))
         (pos (list dx dy dx (+ dy (* 2 (frame-char-height)))))
         (vscroll (pdf-util-required-vscroll pos))
         (tooltip-frame-parameters
          `((border-width . 0)
            (internal-border-width . 0)
            ,@tooltip-frame-parameters))
         (tooltip-hide-delay 3))

    (when vscroll
      (image-set-window-vscroll vscroll))
    (setq dy (max 0 (- dy
                       (cdr (pdf-view-image-offset))
                       (window-vscroll nil t)
                       (frame-char-height))))
    (when (overlay-get (pdf-view-current-overlay) 'before-string)
      (let* ((e (window-inside-pixel-edges))
             (xw (pdf-util-with-edges (e) e-width))
             (display-left-margin (/ (- xw (car (pdf-view-image-size t))) 2)))
        (cl-incf dx display-left-margin)))
    (setq dx (max 0 (+ dx org-noter-arrow-horizontal-offset)))
    (pdf-util-tooltip-in-window
     (propertize
      " " 'display (propertize
                    "\u2192" ;; right arrow
                    'display '(height 2)
                    'face `(:foreground
                            ,org-noter-arrow-foreground-color
                            :background
                            ,(if (bound-and-true-p pdf-view-midnight-minor-mode)
                                 (cdr pdf-view-midnight-colors)
                               org-noter-arrow-background-color))))
     dx dy)))

(add-to-list 'org-noter--show-arrow-hook #'org-noter-pdf--show-arrow)

(defun org-noter-store-highlight-link ()
  "Store a link to the current location in the PDF.
Behaviour depends on `org-noter-store-link-markup-annotation':
- t:      Annotates PDF AND stores coordinates in link.
- 'flash: Stores coordinates in link for transient flashing (no PDF mod).
- nil:    No annotation or flashing.

Prefix arg (C-u) toggles the behaviour (Non-nil -> Nil; Nil -> T)."
  (when (eq major-mode 'pdf-view-mode)
    (let* ((file-path (buffer-file-name))
           (highlight (org-noter-pdf--get-highlight))
           ;; NOTE(hnvy): we must use cdr here due to pdf-tools update 1.3.0
           ;; Since that update, `pdf-view-active-region' now returns
           ;; page information along with coordination. But, ~cdr~ may
           ;; not be needed if we modify `org-noter-pdf--get-highlight' function to account for this?
           (has-region (and highlight
                            (pdf-highlight-coords highlight)
                            (cdr (pdf-highlight-coords highlight))))
           (page (if has-region
                     (pdf-highlight-page highlight)
                   (pdf-view-current-page)))
           ;; Detect if this is a rectangle selection
           (is-rectangle (and has-region
                              (bound-and-true-p pdf-view--have-rectangle-region)))
           ;; Determine effective mode based on config and prefix arg
           (mode (if current-prefix-arg
                     (if org-noter-store-link-markup-annotation nil t)
                   org-noter-store-link-markup-annotation))
           ;; decide on the annotation colour
           (highlight-color (if is-rectangle
                                org-noter-highlight-rectangle-color
                              org-noter-highlight-link-color)))

      ;; A way to handle PDF annotation (i.e., if we set `org-noter-store-link-markup-annotation' to t)
      (when (and has-region (eq mode t))
        (let* ((annot (pdf-annot-add-highlight-markup-annotation
                       (pdf-highlight-coords highlight))))
          (when annot
            (pdf-annot-put annot 'color highlight-color))))

      (let* ((link (if has-region
                       (let* ((coords (pdf-highlight-coords highlight))
                              (region (cadr coords))
                              (h (nth 0 region)) ; x1
                              (v (nth 1 region)) ; y1
                              ;; Storing the edges of the highlight (i.e., if we set `org-noter-store-link-markup-annotation' to 'flash OR t)
                              (edges-str (if mode
                                             (mapconcat (lambda (r)
                                                          (mapconcat (lambda (n) (format "%.3f" n)) r " "))
                                                        (cdr coords) " ")
                                           nil))
                              ;; Add a "rect:" prefix to edges if rectangle
                              (edges-str (when edges-str
                                           (if is-rectangle
                                               (concat "rect:" edges-str)
                                             edges-str))))
                         (if edges-str
                             (format "pdf:%s::(%d %.3f . %.3f %s)" file-path page v h edges-str)
                           (format "pdf:%s::(%d %.3f . %.3f)" file-path page v h)))
                     (format "pdf:%s::%d" file-path page)))
             ;; For rectangle selections, don't use the text as description
             (raw-text (when (and has-region (not is-rectangle))
                         (mapconcat #'identity (pdf-view-active-region-text) " ")))
             (clean-text (when raw-text
                           (string-trim (replace-regexp-in-string "[[:space:]\n\r]+" " " raw-text))))
             (max-len (if (boundp 'org-noter-max-short-selected-text-length)
                          org-noter-max-short-selected-text-length
                        80))
             (default-title (let ((template (if (boundp 'org-noter-default-heading-title)
                                                org-noter-default-heading-title
                                              "Notes for page $p$")))
                              (replace-regexp-in-string (regexp-quote "$p$")
                                                        (number-to-string page)
                                                        template t t)))
             (description (cond
                           (is-rectangle
                            (format "Rectangle on page %d" page))
                           ((and clean-text (<= (length clean-text) max-len))
                            clean-text)
                           (t default-title))))

        (org-link-store-props
         :type "pdf"
         :link link
         :description description)

        link))))

;; Scroll vertically only
  ;; NOTE(hnvy): Unsure if a horizontal scroll would also be useful? Doesn't seem
  ;; to be present in the default behaviour.
(defun org-noter-goto-precise-link-location (page v h &optional edges is-rectangle)
  "Go to PAGE, scroll to relative coordinate V, and flash matching annotation or EDGES.
If IS-RECTANGLE is non-nil, display the region as a rectangle."
  (when (and org-noter--arrow-location
             (vectorp org-noter--arrow-location)
             (> (length org-noter--arrow-location) 0)
             (not (timerp (aref org-noter--arrow-location 0))))
    (setq org-noter--arrow-location nil))

  (org-noter-pdf--goto-location 'pdf-view-mode (cons page (cons v h)) (selected-window))

  (if edges
      ;; If our link contains explicit edges (i.e., if we had set `org-noter-store-link-markup-annotation' to 'flash OR t).
      ;; Also check if our link is a rectangle
      (pdf-view-display-region (cons page edges) is-rectangle)

    ;; What to do if there are no edges
    (let ((annots (pdf-info-getannots page)))
      (catch 'found-annot
        (dolist (annot annots)
          (let ((type (alist-get 'type annot))
                (annot-edges (alist-get 'edges annot)))
            (when (eq type 'highlight)
              ;; Ensure edges is a list of regions
              (when (numberp (car annot-edges))
                (setq annot-edges (list annot-edges)))
              (dolist (r annot-edges)
                (when (and (>= (+ h 0.01) (nth 0 r))
                           (<= (- h 0.01) (nth 2 r))
                           (>= (+ v 0.01) (nth 1 r))
                           (<= (- v 0.01) (nth 3 r)))
                  ;; FLASH!!!
                  (pdf-view-display-region (cons page annot-edges))
                  (throw 'found-annot t))))))))))

(defun org-noter-pdf-link-open (link)
  "Open a PDF link, handling the custom (page v . h [edges]) format."
  (let* ((parts (split-string link "::"))
         (path (car parts))
         (option (cadr parts))
         (precise (and option
                       (string-match
                        "^(\\([0-9]+\\)[[:space:]]+\\([0-9.]+\\)[[:space:]]*\\.[[:space:]]*\\([0-9.]+\\)\\(?:[[:space:]]+\\(\\(?:rect:\\)?[0-9. ]+\\)\\)?)$"
                        option)))
         (page (cond
                (precise (string-to-number (match-string 1 option)))
                ((and option (string-match-p "^[0-9]+$" option))
                 (string-to-number option))
                (t nil)))
         (v (when precise (string-to-number (match-string 2 option))))
         (h (when precise (string-to-number (match-string 3 option))))
         (raw-edges-str (when precise (match-string 4 option)))
         ;; Detect rectangle flag
         (is-rectangle (and raw-edges-str (string-prefix-p "rect:" raw-edges-str)))
         (edges-str (when raw-edges-str
                      (if is-rectangle
                          (substring raw-edges-str 5) ; strip "rect:"
                        raw-edges-str)))
         (edges (when edges-str
                  (let ((nums (mapcar #'string-to-number (split-string edges-str)))
                        result)
                    (while nums
                      (push (list (pop nums) (pop nums) (pop nums) (pop nums)) result))
                    (nreverse result)))))

    (let ((doc-window (and (boundp 'org-noter--session)
                           org-noter--session
                           (org-noter--get-doc-window))))
      (if doc-window
          (progn
            (let ((location (if (and page v h)
                                (cons page (cons v h))
                              (when page (cons page 0)))))
              (when location
                (org-noter--doc-goto-location location)))

            (select-frame-set-input-focus (window-frame doc-window))
            (select-window doc-window)

            (when (and edges page)
              (pdf-view-display-region (cons page edges) is-rectangle)))

        ;; fallback
        (let* ((clean-path (expand-file-name path))
               (buf (find-file-noselect clean-path))
               (win (get-buffer-window buf)))
          (if win
              (select-window win)
            (switch-to-buffer-other-window buf))

          (when page
            (if (and v h)
                (org-noter-goto-precise-link-location page v h edges is-rectangle)
              (pdf-view-goto-page page))))))))

(defun org-noter-pdf-link-export (link description format)
  "Export the custom PDF LINK with DESCRIPTION for FORMAT.
Converts the custom (page v . h) format into standard
HTML #page=N links to make inline `org-noter' links usable in browsers."
  (let* ((parts (split-string link "::"))
         (raw-path (car parts))
         (option (cadr parts))
         ;; Extract page number from the option string
         (page (cond
                ((and option (string-match "^(\\([0-9]+\\)" option))
                 (match-string 1 option))
                ((and option (string-match "^[0-9]+$" option))
                 option)
                (t "1")))
         ;; escpe the path and ensure it's relative for export
         (path (if (fboundp 'org-export-file-uri)
                   (org-export-file-uri (org-link-escape raw-path))
                 raw-path)))
    (cond
     ((eq format 'html)
      (format "<a href=\"%s#page=%s\">%s</a>"
              path
              page
              (or description path)))
     ;; fallback
     (t (if description (format "%s (%s)" description path) path)))))

(org-link-set-parameters "pdf"
  :follow 'org-noter-pdf-link-open
  :store 'org-noter-store-highlight-link
  :export 'org-noter-pdf-link-export)

(defun org-noter-pdf-set-columns (num-columns)
  "Interactively set the COLUMN_EDGES property for the current heading.
NUM-COLUMNS can be given as an integer prefix or in the
minibuffer.  The user is then prompted to click on the right edge
of each column, except for the last one.  Subheadings of the
current heading inherit the COLUMN_EDGES property."
  (interactive "NEnter number of columns: ")
  (select-window (org-noter--get-doc-window))
  (let (event
        edge-list
        (window (car (window-list))))
    (dotimes (ii (1- num-columns))
      (while (not (and (eq 'mouse-1 (car event))
                       (eq window (posn-window (event-start event)))))
        (setq event (read-event (format "Click on the right boundary of column %d" (1+ ii)))))
      (let* ((col-row (posn-col-row (event-start event)))
             (click-position (org-noter--conv-page-scroll-percentage (+ (window-vscroll) (cdr col-row))
                                                                     (+ (window-hscroll) (car col-row))))
             (h-position (cdr click-position)))
        (setq event nil)
        (setq edge-list (append edge-list (list h-position)))))
    (setq edge-list (append edge-list '(1)))
    (select-window (org-noter--get-notes-window))
    (org-entry-put nil "COLUMN_EDGES" (format "%s" (princ edge-list)))))

;;; override some deleterious keybindings in pdf-view-mode.
(define-key org-noter-doc-mode-map (kbd "C-c C-c")
  (defun org-noter-pdf--execute-CcCc-in-notes ()
    "Override C-c C-c in pdf document buffer."
    (interactive)
    (select-window (org-noter--get-notes-window))
    (org-ctrl-c-ctrl-c)))

(define-key org-noter-doc-mode-map (kbd "C-c C-x")
  (defun org-noter-pdf--execute-CcCx-in-notes ()
    "Override C-c C-x <event> in pdf document buffer."
    (interactive)
    (let ((this-CxCc-cmd (vector (read-event))))
      (select-window (org-noter--get-notes-window))
      (execute-kbd-macro
       (vconcat (kbd "C-c C-x") this-CxCc-cmd)))))

(define-key pdf-view-mode-map (kbd "C-c l") 'org-store-link)

(provide 'org-noter-pdf)
;;; org-noter-pdf.el ends here
