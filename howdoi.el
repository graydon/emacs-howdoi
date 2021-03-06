;;; howdoi.el --- instant coding answers via Emacs.

;; Copyright (C) 2013 Andrey Tykhonov
;; Free Software Foundation, Inc.

;; Author: Andrey Tykhonov <atykhonov at gmail.com>
;; Version: 0.2.0
;; Keywords: howdoi

;; This file is NOT part of GNU Emacs.

;; howdoi.el is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation, either version 3 of the License,
;; or (at your option) any later version.

;; howdoi.el is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with request.el.
;; If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Do you find yourself constantly Googling for how to do basic
;; programing tasks? Suppose you want to know how to format a date in
;; bash. Why open your browser and read through blogs when you can
;; just M-x howdoi-query RET format date bash
;;
;; This package was inspired by Tom (adatgyujto at gmail.com). It was
;; his idea to make a port of command line tool such as python's
;; `howdoi`: https://github.com/gleitz/howdoi
;;
;; Thank you, Tom!
;;
;; Commands:
;;
;; The following two commands show an answer in a pop up buffer:
;; M-x howdoi-query RET <your-query>
;; M-x howdoi-query-line-at-point ;; takes a query from a line at point
;;
;; To get an answer containing only code snippet you could use:
;; M-x howdoi-query-line-at-point-replace-by-code-snippet
;;     this command replaces current line with a code snippet
;;     parsed from an answer.
;;
;; In case of last command you could get situation when it returns not
;; good enough code snippet. Or may be after that command you would
;; like to get more details which relates to the original query. Then
;; you could use the following command:
;;
;; M-x howdoi-show-current-question
;;
;; This one will show (in a pop up buffer) full answer which contains
;; recently inserted code snippet. This command may help sometimes to
;; avoid additional googling when original query is a little bit
;; ambiguous.
;;
;; In the mentioned pop up buffer you could use C-c C-n and C-c C-p
;; key bindings to take a look at next and previous questions which
;; are similar to yours original one. Also, you could open current
;; question in a browser by means of C-c C-o key binding.
;;
;; By default pop up buffer displays only answers. You could change
;; `howdoi-display-question` custom variable to show also a question.

;;; Code:

(defcustom howdoi-display-question nil
  "Whether to display the question.
When non-nil, question is printed."
  :type 'boolean
  :group 'howdoi)

(defcustom howdoi-number-of-answers 1
  "Controls how many answers to return."
  :type 'integer
  :group 'howdoi)

(defvar howdoi-question-urls '()
  "Contains urls parsed from google.")

(defvar howdoi-current-question-num 0
  "Current question number.")

(defvar howdoi-display-callback nil
  "Display callback which uses to display questions and answers.")

(defvar howdoi-requests-cache (make-hash-table :test 'equal)
  "Keeps cached answers to avoid surplus http queries.")

(defvar howdoi-original-buffer nil)


(defun trim-string (string)
  "Remove white spaces in beginning and ending of STRING.
  White space here is any of: space, tab, emacs newline (line feed, ASCII 10)."
  (replace-regexp-in-string "\\`[ \t\n\r]*" ""
                            (replace-regexp-in-string "[ \t\n\r]*\\'" "" string)))

(defun howdoi-query-line-at-point ()
  "Take a line at point and make request.
Pop up a buffer displaying the answer."
  (interactive)
  (let ((query (buffer-substring-no-properties
                (line-beginning-position)
                (line-end-position))))
    (howdoi-request query 'howdoi-pop-answer-to-buffer-callback)))

(defun howdoi-query-line-at-point-replace-by-code-snippet ()
  "Take a line at the point, make request
and replace the line by a code snippet."
  (interactive)
  (let* ((query (buffer-substring-no-properties
                (line-beginning-position)
                (line-end-position))))
        (setq howdoi-original-buffer (current-buffer))
        (howdoi-request query
                        'howdoi-replace-line-at-point-callback)))

(defun howdoi-replace-line-at-point-callback (question answers snippets)
  "Callback which calls immediately after http request. It
replaces a line at point by code snippet."
  (with-current-buffer howdoi-original-buffer
    (move-beginning-of-line nil)
    (kill-line nil)
    (insert (nth 0 snippets))))

(defun howdoi-format-question-and-answers (question answers)
  "Format output of question and answers."
  (setq result (mapconcat (function (lambda (x)
                                      (trim-string x)))
                          answers "\n\n-------\n\n"))
  (when (and question howdoi-display-question)
    (setq result (format "%s\n\n=======\n\n%s" (trim-string question) result)))
  result)

(defun howdoi-pop-answer-to-buffer-callback (question answers snippets)
  "Callback which calls immediately after http request. Pop up a
buffer named *How do I* displaying the answer."
  (let ((howdoi-buffer (get-buffer-create "*How do I*")))
    (save-selected-window
      (with-current-buffer howdoi-buffer
        (howdoi-minor-mode)
        (erase-buffer)
        (insert (howdoi-format-question-and-answers question answers))
        (goto-char (point-min)))
      (pop-to-buffer howdoi-buffer))))

(defun howdoi-query (query)
  "Prompts for the query and makes howdoi query.
Pop up a buffer displaying the answer."
  (interactive "sQuery: ")
  (howdoi-request query 'howdoi-pop-answer-to-buffer-callback))

(defun howdoi-request (query callback &optional &key full-answer &key question)
  "Make http request to the Google. Use `query` as search
string. `Callback` calls after http request to display the
results."
  (setq howdoi-display-callback callback)
  (setq howdoi-current-question-num 0)
  (setq howdoi-requests-cache (make-hash-table :test 'equal))
  (let ((url-request-method "GET")
        (url "http://google.com/search")
        (args (concat "?q="
                      (url-hexify-string "site:stackoverflow.com ")
                      (url-hexify-string query))))
    (url-retrieve (concat url args)
                  (lambda (status)
                    (setq howdoi-question-urls (howdoi-retrive-links-from-google
                                                (current-buffer)))
                    (howdoi-stackoverflow-request (nth howdoi-current-question-num
                                                       howdoi-question-urls)))
                  nil t)))

(defun howdoi-retrive-links-from-google (buffer)
  "Retrieves links from a google search result page."
  (let ((result '()))
    (with-current-buffer buffer
      (goto-char (point-min))
      (while (search-forward "<h3 class=\"r\">" nil t)
        (when (search-forward-regexp "<a href=\"\\([^\"]*\\)\".*?>" nil t)
          (let ((str (match-string 1)))
            (setq str (nth 1 (split-string str "q=")))
            (setq str (nth 0 (split-string str "&")))
            (setq result (append result `(,str)))))))
    result))

(defun howdoi-stackoverflow-request (url)
  "Make http request to the stackoverflow."
  (let ((url-request-method "GET")
        (cache (gethash url howdoi-requests-cache)))
    (if cache
        (funcall howdoi-display-callback
                 (nth 0 cache)
                 (nth 1 cache)
                 (nth 2 cache))
      (progn
        (setq howdoi-current-stackoverflow-url url)
        (url-retrieve url
                      (lambda (status)
                        (let ((answers '()) (snippets '()) (question ""))
                          (setq answers (howdoi-stackoverflow-retrieve-answer))
                          (setq snippets (howdoi-stackoverflow-retrieve-code-snippets))
                          (when howdoi-display-question
                            (setq question (howdoi-stackoverflow-retrieve-question)))
                          (puthash howdoi-current-stackoverflow-url
                                   `(,question ,answers ,snippets) howdoi-requests-cache)
                          (message "Answer retrieved!")
                          (funcall howdoi-display-callback question answers snippets)))
                      nil t)))))

(defun howdoi-stackoverflow-retrieve-question ()
  "Retrieve a question from the stackoverflow."
  (goto-char (point-min))
  (let ((result ""))
    (when (search-forward-regexp "<div[^>]*?class=\"question" nil t)
      (when (search-forward-regexp "<td class=\"postcell\">" nil t)
        (when (search-forward-regexp "<div class=\"post-text\"[^>]*>\\(\\(.*?\n?\\)*\\)</div>" nil t)
          (let ((str (match-string 1)))
            (with-temp-buffer
              (erase-buffer)
              (insert str)
              (goto-char (point-min))
              (howdoi-strip-html-tags '("p" "pre" "code" "hr"))
              (html2text)
              (setq result (buffer-substring-no-properties
                            (point-min)
                            (point-max))))))))
    result))

(defun howdoi-stackoverflow-retrieve-answer ()
  "Retrieve an answer from the stackoverflow."
  (goto-char (point-min))
  (let ((result '()))
    (while (search-forward-regexp "<div[^>]*?class=\"answer" nil t)
      (when (search-forward-regexp "<td class=\"answercell\">" nil t)
        (when (search-forward-regexp "<div class=\"post-text\">\\(\\(.*?\n?\\)*\\)</div>" nil t)
          (let ((str (match-string 1)))
            (with-temp-buffer
              (erase-buffer)
              (insert str)
              (goto-char (point-min))
              (howdoi-strip-html-tags '("p" "pre" "code" "hr"))
              (html2text)
              (setq result (append result `(,(buffer-substring-no-properties (point-min) (point-max))))))))))
    result))

(defun howdoi-strip-html-tags (tags)
  (dolist (tagn tags)
    (dolist (tag `(,(format "<%s>" tagn) ,(format "</%s>" tagn)))
      (goto-char (point-min))
      (while (search-forward tag nil t)
        (replace-match "" nil t)))))

(defun howdoi-strip-html-entities (s)
  (s-replace-all html2text-replace-list s))

(defun howdoi-stackoverflow-retrieve-code-snippets ()
  "Retrieve code snippets from the stackoverflow."
  (goto-char (point-min))
  (let ((result '()))
    (while (search-forward-regexp "<div[^>]*?class=\"answer" nil t)
      (if (search-forward-regexp "<pre[^>]*>" nil t)
          (when (search-forward-regexp "<code>\\([^<]*?\\)</code>" nil t)
            (let ((str (howdoi-strip-html-entities (match-string 1))))
              (setq result (append result `(,str)))
              (setq not-found nil)))
        (when (search-forward-regexp "<code>\\(.*?\\)</code>" nil t)
          (let ((str (howdoi-strip-html-entities (match-string 1))))
            (setq result (append result `(,str)))))))
    result))

(defun howdoi-show-next-question ()
  "Show next question. The purpose of this function to use it in
the *How do I* pop up buffer to view next question."
  (interactive)
  (setq howdoi-display-callback 'howdoi-pop-answer-to-buffer-callback)
  (setq howdoi-current-question-num (+ howdoi-current-question-num 1))
  (when (> howdoi-current-question-num 10)
    (setq howdoi-current-question-num 10))
  (howdoi-stackoverflow-request (nth howdoi-current-question-num
                                     howdoi-question-urls)))

(defun howdoi-show-current-question ()
  "Pop up a buffer named *How do I* displaying the current found
question. It may be helpful to use after such command as
howdoi-query-line-at-point-replace-by-code-snippet to view more
details or to find more preferable code snippet."
  (interactive)
  (let* ((howdoi-buffer (get-buffer-create "*How do I*"))
         (url (nth howdoi-current-question-num howdoi-question-urls))
         (cache (gethash url howdoi-requests-cache)))
    (if cache
        (save-selected-window
          (with-current-buffer howdoi-buffer
            (howdoi-minor-mode)
            (erase-buffer)
            (insert (howdoi-format-question-and-answers (nth 0 cache) (nth 1 cache)))
            (goto-char (point-min)))
          (pop-to-buffer howdoi-buffer))
      (message "Current question not found"))))

(defun howdoi-show-previous-question ()
  "Show previous question. The purpose of this function to use it in
the *How do I* pop up buffer to view previous question."
  (interactive)
  (setq howdoi-display-callback 'howdoi-pop-answer-to-buffer-callback)
  (setq howdoi-current-question-num (- howdoi-current-question-num 1))
  (when (< howdoi-current-question-num 0)
      (setq howdoi-current-question-num 0))
  (howdoi-stackoverflow-request (nth howdoi-current-question-num
                                     howdoi-question-urls)))

(defun howdoi-browse-current-question ()
  "Ask a WWW browser to load current question."
  (interactive)
  (let ((url (nth howdoi-current-question-num howdoi-question-urls)))
    (browse-url url)))

(define-minor-mode howdoi-minor-mode
  "Toggle howdoi minor mode."
  :lighter " HowDoI"
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "C-c C-n") 'howdoi-show-next-question)
            (define-key map (kbd "C-c C-p") 'howdoi-show-previous-question)
            (define-key map (kbd "C-c C-o") 'howdoi-browse-current-question)
            map)
  :group 'howdoi)

(provide 'howdoi)

;;; howdoi.el ends here
