;;; -*- lexical-binding: t; -*-
;;
;; Tests for the three-value `org-noter-always-create-frame' contract added
;; in "Make org-noter-always-create-frame honest about nil".
;;
;; The frame decision lives inline in `org-noter--create-session'.  We never
;; want a spec to really pop a GUI frame under batch Emacs, so `make-frame' is
;; spied out and made to return the (live) selected frame.  That keeps every
;; session valid while letting us assert on *whether* a new frame was
;; requested for each value of the setting:
;;
;;   t              -> always create a new frame
;;   nil            -> always reuse the selected frame (even if busy)
;;   reuse-if-free  -> reuse the selected frame only when it is free,
;;                     otherwise create a new frame (the old nil behavior)

(add-to-list 'load-path "modules")
(require 'with-simulated-input)
(load-file "org-noter-test-utils.el")


(describe "org-noter-always-create-frame"
          (before-each
           (create-org-noter-test-session)
           ;; Stand in a real, live frame so `make-frame' never touches a
           ;; window system, yet the resulting session stays valid.
           (spy-on 'make-frame :and-return-value (selected-frame)))

          ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
          (describe "the customization contract"
                    (it "defaults to always creating a frame"
                        ;; Read the customize standard value rather than the
                        ;; live value, which the test harness sets to nil.
                        (expect (eval (car (get 'org-noter-always-create-frame
                                                'standard-value))
                                      t)
                                :to-be t))

                    (it "offers reuse-if-free as an explicit choice"
                        (expect (flatten-tree
                                 (get 'org-noter-always-create-frame 'custom-type))
                                :to-contain 'reuse-if-free)))

          ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
          (describe "t"
                    (it "always creates a new frame, even when the selected frame is free"
                        (with-mock-contents
                         mock-contents-simple-notes-file-with-a-single-note
                         (lambda ()
                           (setq org-noter-always-create-frame t)
                           (let ((org-noter--sessions nil))
                             (org-noter-core-test-create-session)
                             (expect 'make-frame :to-have-been-called))))))

          ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
          (describe "nil"
                    ;; This is the behavior the commit fixes: nil used to spawn
                    ;; a new frame whenever the selected frame already hosted a
                    ;; session.  It must now reuse the selected frame regardless.
                    (it "reuses the selected frame even when it already hosts another session"
                        (with-mock-contents
                         mock-contents-simple-notes-file-with-a-single-note
                         (lambda ()
                           (setq org-noter-always-create-frame nil)
                           ;; Pretend the selected frame is already busy with a
                           ;; stand-in session.  `:id' must be a number so
                           ;; `org-noter--get-new-id' can compare against it.
                           (let ((org-noter--sessions
                                  (list (make-org-noter--session
                                         :id 0 :frame (selected-frame)))))
                             (org-noter-core-test-create-session)
                             (expect 'make-frame :not :to-have-been-called)
                             (expect (org-noter--session-frame org-noter--session)
                                     :to-be (selected-frame)))))))

          ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
          (describe "reuse-if-free"
                    (it "reuses the selected frame when no session lives on it"
                        (with-mock-contents
                         mock-contents-simple-notes-file-with-a-single-note
                         (lambda ()
                           (setq org-noter-always-create-frame 'reuse-if-free)
                           (let ((org-noter--sessions nil))
                             (org-noter-core-test-create-session)
                             (expect 'make-frame :not :to-have-been-called)
                             (expect (org-noter--session-frame org-noter--session)
                                     :to-be (selected-frame))))))

                    (it "creates a new frame when the selected frame already hosts a session"
                        (with-mock-contents
                         mock-contents-simple-notes-file-with-a-single-note
                         (lambda ()
                           (setq org-noter-always-create-frame 'reuse-if-free)
                           ;; A stand-in session already owns the frame.  `:id'
                           ;; must be a number so `org-noter--get-new-id' can
                           ;; compare against it.
                           (let ((org-noter--sessions
                                  (list (make-org-noter--session
                                         :id 0 :frame (selected-frame)))))
                             (org-noter-core-test-create-session)
                             (expect 'make-frame :to-have-been-called)))))))
