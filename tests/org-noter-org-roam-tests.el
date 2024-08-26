;;; -*- lexical-binding: t; -*-

(require 'org-noter-test-utils)
(require 'org-noter-org-roam)

(describe "org-roam integration"
          (before-each
           (create-org-noter-test-session)
           )

          (describe "org-roam"
                    (before-each
                     ;; org-noter uses file-equal-p that looks at the filesystem. We need real files to verify this functionality.
                     (shell-command "mkdir -p /tmp/pubs/ && touch /tmp/pubs/solove-nothing-to-hide.pdf && touch /tmp/test.pdf"))

                    (describe "top level heading insertion"
                              (it "can insert a top level heading at the end of the file"
                                  (with-mock-contents
                                   mock-contents-simple-notes-file
                                   (lambda ()
                                      (org-noter--create-notes-heading "ADOCUMENT" "/tmp/file")
                                      (expect (string-match "ADOCUMENT" (buffer-string))  :not :to-be nil)
                                      (expect (string-match "/tmp/file" (buffer-string))  :not :to-be nil)
                                      ;; ADOCUMENT should come after solove-nothing-to-hide
                                      (expect (string-match "solove-nothing-to-hide" (buffer-string)) :to-be-less-than
                                              (string-match "ADOCUMENT" (buffer-string)))
                                      )))

                              (it "can find an existing heading without creating a new one"
                                  (with-mock-contents
                                   mock-contents-simple-notes-file
                                   (lambda ()
                                      (let* ((found-heading-pos (org-noter--find-create-top-level-heading-for-doc "/tmp/test.pdf" "solove-nothing-to-hide")))
                                      (goto-char found-heading-pos)
                                      (insert "!!")
                                      (expect found-heading-pos :to-be 141)))))


                              (it "can create a new heading"
                                  (with-mock-contents
                                   mock-contents-simple-notes-file
                                   (lambda ()
                                      (expect
                                       ;; org-noter-test-file is defined in test-utils.
                                       (org-noter--find-create-top-level-heading-for-doc "/tmp/some-other-pdf-file.pdf" "SOME HEADING")
                                       :to-be 162))))
                              )


                    (describe "identifying top level headlines"
                              (before-each
                               ;; org-noter uses file-equal-p that looks at the filesystem. We need real files to verify this functionality.
                               (shell-command "mkdir -p /tmp/pubs/ && touch /tmp/pubs/solove-nothing-to-hide.pdf")
                               )

                              (it "can find the top level headline for a specified document and return the position"
                                  (with-mock-contents
                                   mock-contents-simple-notes-file
                                   (lambda ()
                                      (insert "!!")
                                      (expect
                                       (org-noter--find-top-level-heading-for-document-path "/tmp/test.pdf")
                                       :to-be 143))))


                              (it "return nil for a non existent top level heading"
                                  (with-mock-contents
                                   mock-contents-simple-notes-file
                                   (lambda ()
                                      (expect
                                       (org-noter--find-top-level-heading-for-document-path "/FAKE/PATH/DOESNT/EXIST")
                                       :to-be nil))))
                              )




                    )


          (describe "org-noter integration"
                    (before-each
                     ;; org-noter uses file-equal-p that looks at the filesystem. We need real files to verify this functionality.
                     (shell-command "mkdir -p /tmp/pubs/ && touch /tmp/pubs/solove-nothing-to-hide.pdf"))

                    ;; mocking a lot of stuff, for integration sake.
                    ;; ideally we'd split up functions to be somewhat smaller to ease testing.
                    (it "executes org-noter"
                        (spy-on 'org-noter--find-create-top-level-heading-for-doc :and-call-fake (lambda (doc-path desired-heading) 1001))
                        (spy-on 'org-noter--get-filename-interactively :and-call-fake (lambda () "/tmp/pubs/notes.org"))
                        (spy-on 'org-noter)
                        (with-mock-contents
                         mock-contents-simple-notes-file
                         (lambda ()
                            (write-region (point-min) (point-max) "/tmp/pubs/notes.org")))
                        (org-noter--create-session-from-document-file-supporting-org-roam nil "/tmp/test.pdf")
                        (expect 'org-noter :to-have-been-called))


                    (it "asks for a node interactively when no existing node has been found"
                        ;; mock the function that would return the node to return nil
                        (spy-on 'org-noter--get-nodes-with-noter-document-property :and-call-fake (lambda (_) nil))
                        (spy-on 'org-noter--get-filename-interactively :and-call-fake (lambda () "/tmp/pubs/notes1.org"))
                        (spy-on 'org-noter)
                        (with-mock-contents
                         mock-contents-simple-notes-file
                         (lambda ()
                           (write-region (point-min) (point-max) "/tmp/pubs/notes1.org")))

                        (org-noter--create-session-from-document-file-supporting-org-roam nil "/tmp/test.pdf")
                        (expect 'org-noter--get-filename-interactively :to-have-been-called)
                        (expect 'org-noter :to-have-been-called))


                    (it "does NOT ask for a node interactively when an existing node has been found"
                        ;; mock the function that would return the node to return nil
                        (spy-on 'org-noter--find-existing-node-for-document :and-call-fake (lambda (_)  '("/tmp/pubs/notes2.org")))
                        (spy-on 'org-noter--get-filename-interactively :and-call-fake (lambda () "/tmp/pubs/notes2.org"))
                        (spy-on 'org-noter)
                        (with-mock-contents
                         mock-contents-simple-notes-file
                         (lambda ()
                           (write-region (point-min) (point-max) "/tmp/pubs/notes2.org")))
                        (org-noter--create-session-from-document-file-supporting-org-roam nil "/tmp/test.pdf")
                        (expect 'org-noter--get-filename-interactively :not :to-have-been-called))
                    )



          (it "sets the hook correctly when org-roam integration is enabled"
              (org-noter-enable-org-roam-integration)
              (expect org-noter-create-session-from-document-hook :to-equal '(org-noter--create-session-from-document-file-supporting-org-roam)))



)
