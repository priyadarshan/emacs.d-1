;;; init.el --- Initialization file
;;; Commentary:
;;; Code:

(setq ff/emacs-start-time (current-time))

;; * Utilities

;; This section contains base utilities upon which the rest builds

;; ** Minimal base

;; *** Lisp utilities

(defmacro with-timer (title &rest forms)
  "Run the given FORMS, counting the elapsed time.
A message including the given TITLE and the corresponding elapsed
time is displayed."
  (declare (indent 1))
  (let* ((nowvar   (make-symbol "now"))
         (errorvar (make-symbol "error"))
         (body    `(progn
                     ,@forms
                     (setq ,errorvar nil))))
    `(let ((,nowvar   (current-time))
           (,errorvar t))
       (message "%s..." ,title)
       (unwind-protect ,body
         (let ((elapsed
                (float-time (time-subtract (current-time) ,nowvar))))
           (message "%s...%s (%.3fs)" ,title (if ,errorvar "FAILED" "done") elapsed))))))

(defmacro progn-safe (title &rest forms)
  "Run the given FORMS, gracefully demoting errors to warnings.
A TITLE is used to identify the block in the logs."
  (declare (indent 1))
  (let ((errvar (make-symbol "err")))
    `(condition-case-unless-debug ,errvar
         (progn
           ,@forms)
       (error
        (ignore
         (message "%s: FAILED" ,title)
         (display-warning
          'progn-safe
          (format "%s: %s" ,title ,errvar)
          :error))))))

(defmacro with-timer-safe (title &rest forms)
  "Fault-tolerant version of `with-timer'."
  (declare (indent 1))
  `(progn-safe ,title
     (with-timer ,title
       ,@forms)))

(progn-safe "Highlighting in *Messages* buffer (startup times & errors)"
  (font-lock-add-keywords
   'messages-buffer-mode
   '(("([[:digit:]]+.[[:digit:]]+s)" 0 font-lock-constant-face t)))
  (font-lock-add-keywords
   'messages-buffer-mode
   '(("FAILED" 0 font-lock-warning-face t)))
  (with-current-buffer "*Messages*"
    (font-lock-fontify-buffer)))

;; *** Filesystem hierarchy

(setq user-init-file (or load-file-name
                         (buffer-file-name)))
(setq user-emacs-directory (file-name-directory
                            user-init-file))

(defun ff/emacsd (name)
  "Path to a file named NAME in `user-emacs-directory'."
  (expand-file-name (concat user-emacs-directory name)))

(add-to-list 'load-path (ff/emacsd "lisp"))


;; **** Configuration files

(defun ff/load-configuration (name)
  "Load the configuration for package NAME.
This configuration is located in a file named `setup-NAME.el`
under `user-emacs-directory'."
  (load-file (ff/emacsd (concat "setup-" name ".el"))))

;; **** Persistency files

(defun ff/variable-file (name)
  "Path to a variable file of given NAME.
Variable files are located in the \"var\" subdirectory of `user-emacs-directory'"
  (expand-file-name (concat user-emacs-directory "var/" name)))


;; ** Packages management

;; *** Configuration

(eval-when-compile
  (add-to-list 'load-path (ff/emacsd "packages/use-package"))
  (require 'use-package)
  (setq use-package-verbose t))

(progn-safe "Disable deferring for testing purposes"
  (when debug-on-error
    (advice-add
     'use-package-handler/:config :before
     (lambda (name keyword arg rest state)
       (plist-put state :deferred nil)))))

(progn-safe "Highlighting in *Messages* buffer (use-package)"
  (font-lock-add-keywords
   'messages-buffer-mode
   '(("Could not load .*" 0 font-lock-warning-face t)))
  (with-current-buffer "*Messages*"
    (font-lock-fontify-buffer)))


;; *** Dependencies

(use-package package
  :init
  (defvar ff/updating-elpa-cache nil
    "True when updating the ELPA cache")
  (defvar ff/elpa-cache-file (ff/variable-file "elpa-cache.el")
    "Location of the ELPA cache")

  (setq package-archives
        '(("melpa" . "http://melpa.milkbox.net/packages/")
          ("gnu"   . "http://elpa.gnu.org/packages/"))))

(if ff/updating-elpa-cache
    (with-timer "Updating ELPA cache"
      ;; Update ELPA cache -- this is left unprotected as it is always run in
      ;; another process and we want errors to be reported
      (package-initialize)
      (with-temp-buffer
        (pp
         (apply
          #'list
          'progn
          `(setq package-alist ',package-alist)
          `(setq package--initialized t)
          (mapcar (lambda (dir)
                    `(add-to-list 'load-path ,dir))
                  load-path))
         (current-buffer))
        (write-file ff/elpa-cache-file)))

  (with-timer-safe "Configuring ELPA"
    ;; Try loading the cache for faster startup
    (defun ff/package-initialize ()
      (with-timer "Fully initializing ELPA"
        (package-initialize))

      (message "Starting ELPA cache update...")
      (setq ff/updating-elpa-cache (current-time))
      (let ((default-directory user-emacs-directory))
        (set-process-sentinel
         (start-process "elpa-cache" "*elpa-cache*"
                        "make" "elpa-update")
         (lambda (process event)
           (message "Starting ELPA cache update...%s"
                    (cond ((process-live-p process)
                           (format " live process received event `%s'" event))
                          ((eq 'signal (process-status process))
                           (format " process killed (%d)" (process-exit-status process)))
                          ((eq 'exit (process-status process))
                           (if (= 0 (process-exit-status process))
                               (format "complete (%.3fs)"
                                       (float-time (time-subtract (current-time)
                                                                  ff/updating-elpa-cache)))
                             (display-warning
                              'ff/package-initialize
                              (format
                               "failed to update ELPA cache; see buffer `%s' for details"
                               (process-buffer process))
                              :error)
                             (format "FAILED (%d)" (process-exit-status process))))
                          (t
                           (format " process received event `%s'" event))))))))

    (condition-case nil
        (progn
          (message "Trying fast ELPA setup...")
          (load ff/elpa-cache-file)
          (unless package--initialized
            (error "Package.el left uninitialized"))
          (run-with-idle-timer 5 nil #'ff/package-initialize)
          (message "Trying fast ELPA setup...done"))
      (error
       (message "Trying fast ELPA setup...FAILED")
       (ff/package-initialize)))))


;; ** Base tools

(use-package htmlize :ensure t :defer t)
(use-package f       :ensure t :defer t)
(use-package dash    :ensure t :defer t)
(use-package s       :ensure t :defer t)


;; *** Key bindings

(defun list-known-bindings (key &optional no-load)
  (interactive "kList known bindings for key: \nP")
  (when (and (not no-load)
             (yes-or-no-p (concat "Try to load every known library"
                                  " (this might take some resources)?")))
    (let ((nfeatures 0))
      (while (not (= nfeatures (length features)))
        (setq nfeatures (length features))
        (message "%d features loaded" nfeatures)
        (mapatoms (lambda (sym)
                    (when (and (boundp sym)
                               (autoloadp (symbol-function sym)))
                      (autoload-do-load (symbol-function sym))))))))
  (with-current-buffer (get-buffer-create "*known bindings*")
    (help-mode)
    (let ((buffer-read-only nil))
      (erase-buffer)
      (insert
       (format "Known bindings for key: %s\n\n" (key-description key))
       (format "%-40s %s" "Map" "Binding\n")
       (s-repeat 40 "-") " " (s-repeat 30 "-") "\n")
      (mapatoms (lambda (sym)
                  (when (or (eq sym 'global-map)
                            (and (boundp sym)
                                 (symbol-value sym)
                                 (s-ends-with-p "-mode-map" (symbol-name sym))
                                 (keymapp (symbol-value sym))))
                    (let ((binding (lookup-key (symbol-value sym) key t)))
                      (when (and binding
                                 (not (numberp binding)))
                        (insert (format "%-40s `%s'\n"
                                        (format "`%s'" sym)
                                        (if (keymapp binding)
                                            "KEYMAP"
                                          binding)))))))))
    (let ((help-xref-following t))
      (setq help-xref-stack         nil
            help-xref-forward-stack nil)
      (help-make-xrefs)
      (help-setup-xref (cons 'list-known-bindings (list key t)) t))
    (goto-char (point-min))
    (display-buffer (current-buffer))))

;; **** Custom global key bindings

;; Inspired from http://stackoverflow.com/q/683425
(progn-safe "Custom bindings"
  (define-minor-mode custom-bindings-mode
    "Install custom key bindings.

\\{custom-bindings-mode-map}"
    :global t
    :init-value t
    :keymap (make-sparse-keymap))

  (defun custom-set-key (key command)
    "Bind KEY to COMMAND in `custom-bindings-mode'."
    (define-key custom-bindings-mode-map key command))

  ;; Ensure `custom-bindings-mode' always has precendence
  (advice-add
   'load :after
   (defun custom-bindings--load-advice--promote (&rest args)
     "Make sure MODE appears first in `minor-mode-map-alist'.
This ensures no key bindings defined in MODE can be shadowed by
another minor-mode."
     (let* ((mode 'custom-bindings-mode)
            (cell (assq mode minor-mode-map-alist)))
       (setq minor-mode-map-alist
             (cons cell
                   (assq-delete-all mode minor-mode-map-alist)))))))



;; **** Repeatable commands

;; (http://stackoverflow.com/a/17310748/1225607)
(use-package repeat
  :config
  (defun make-repeatable-command (cmd)
    "Return a new command that is a repeatable version of CMD.
The new command is named CMD-repeat.  CMD should be a quoted
command.

This allows you to bind the command to a compound keystroke and
repeat it with just the final key.  For example:

  (global-set-key (kbd \"C-c a\") (make-repeatable-command 'foo))

will create a new command called foo-repeat.  Typing `C-c a' will
just invoke foo.  Typing `C-c a a a' will invoke foo three times,
and so on."
    (let ((repeatable-command (intern (concat (symbol-name cmd) "/repeat"))))
      (fset repeatable-command
            `(lambda ,(help-function-arglist cmd)
               ,(format "A repeatable version of `%s'." (symbol-name cmd))
               ,(interactive-form cmd)
               ;; see also repeat-message-function
               (setq last-repeatable-command ',cmd)
               (repeat nil)))
      repeatable-command)))


;; **** Hydra
(use-package hydra
  :ensure t)


;; *** Local rc files

(with-timer-safe "Loading local rc files"
  (let* ((fullhostname (system-name))
         (hostname     (substring fullhostname 0
                                  (progn
                                    (string-match "\\." (concat fullhostname ".domain"))
                                    (- (match-end 0) 1)))))
    (load (concat user-emacs-directory "host-" hostname) 'noerror)))


;; * General settings

;; This section contains everything which is not directly related to text
;; editing.

(progn-safe "General settings"
  ;; Customization file
  (setq custom-file (ff/variable-file "custom.el"))
  (with-timer "Loading custom file"
    (load custom-file 'noerror 'nomessage))

  ;; don't suspend emacs on C-z (but C-x C-z still works)
  (global-set-key (kbd "C-z") nil))

;; ** Look

;; *** Interface

(progn-safe "Interface"
  ;; Bare UI
  (menu-bar-mode   -1)
  (tool-bar-mode   -1)
  (scroll-bar-mode -1)

  ;; Startup
  (setq initial-scratch-message "")          ;; Empty scratch buffer
  (setq initial-major-mode 'fundamental-mode) ;;   ... in fundamental-mode
  (let ((scratch (get-buffer "*scratch*")))
    (when scratch
      (with-current-buffer scratch
        (funcall initial-major-mode))))
  (setq inhibit-splash-screen t) ;; No fancy splash screen

  ;; Show line and column numbers
  (column-number-mode 1)
  (line-number-mode 1)

  ;; Window title
  (setq-default frame-title-format (list "%b - Emacs"))

  ;; Fringes
  (setq-default indicate-buffer-boundaries 'left)

  ;; Margins
  (let ((m-w 1))
    (setq-default left-margin-width  m-w
                  right-margin-width m-w)))

;; *** GUI Theme

;; Tango color theme
(use-package naquadah-theme
  :ensure t
  :if window-system

  :config
  (load-theme 'naquadah t)
  (use-package term
    :defer  t
    :config
    (set-face-attribute 'term-color-red     nil :foreground "#ef2929")
    (set-face-attribute 'term-color-green   nil :foreground "#73d216")
    (set-face-attribute 'term-color-yellow  nil :foreground "#edd400")
    (set-face-attribute 'term-color-blue    nil :foreground "#729fcf")
    (set-face-attribute 'term-color-magenta nil :foreground "#ad7fa8")
    (set-face-attribute 'term-color-cyan    nil :foreground "#c17d11")
    (set-face-attribute 'term-color-white   nil :foreground "#babdb6")
    (set-face-attribute 'term-color-black   nil :background "#262b2c"))

  (custom-set-faces
   '(fringe ((t (:background "#1f2324")))))

  ;; Font
  (push '(font-backend . "xft")                default-frame-alist)
  (push '(font . "Bitstream Vera Sans Mono-9") default-frame-alist))


;; *** Mode line

(use-package smart-mode-line
  :ensure t
  :defer  2

  :config
  (setq mode-line-position nil)
  (sml/setup)

  ;; Shift `mode-line-misc-info' a bit to the left
  (add-to-list 'mode-line-misc-info "  " 'append))

(use-package diminish
  :ensure t)

(progn-safe "Rename major modes in the mode line"
  ;; From Magnar Sveen:
  ;;  http://whattheemacsd.com/appearance.el-01.html
  (defmacro rename-modeline (package-name mode new-name)
    `(eval-after-load ,package-name
       '(defadvice ,mode (after rename-modeline activate)
          (setq mode-name ,new-name))))

  (rename-modeline "lisp-mode" emacs-lisp-mode "EL"))


;; ** Windows management

;; *** Switch between windows

;; Use S-<arrows> to switch between windows
(use-package windmove
  :config
  (windmove-default-keybindings)
  (setq windmove-wrap-around t)

  ;; I tend to always lose track of the point when I switch between too many
  ;; windows
  (defun ff/show-pointer ()
    (interactive)
    (let ((overlay
           (make-overlay (point) (point))))
      (overlay-put overlay 'window (selected-window))
      (overlay-put overlay 'before-string
                   (propertize "*"
                               'face (list :foreground "red"
                                           :height 7.0)
                               'display '(raise -0.40)))
      (sit-for 1)
      (delete-overlay overlay)))

  (mapc
   (lambda (fun)
     (advice-add fun :after 'ff/show-pointer))
   '(windmove-left windmove-right windmove-up windmove-down)))

;; Reclaim S-<arrows> keys in org-related mode
(use-package org
  :defer  t

  :config
  ;; Left/Right are directly reclaimed
  (define-key org-mode-map (kbd "S-<left>")  nil)
  (define-key org-mode-map (kbd "S-<right>") nil)

  ;; Up/Down are kept for places where
  ;; they are useful (dates and such)
  (add-hook 'org-shiftup-final-hook   'windmove-up)
  (add-hook 'org-shiftdown-final-hook 'windmove-down)

  ;; Same thing for org-agenda
  (use-package org-agenda
    :defer  t
    :config
    (define-key org-agenda-mode-map (kbd "S-<left>")  nil)
    (define-key org-agenda-mode-map (kbd "S-<right>") nil)
    (define-key org-agenda-mode-map (kbd "S-<up>")    nil)
    (define-key org-agenda-mode-map (kbd "S-<down>")  nil)))

;; *** Manage window configurations

;; Navigate through window layouts with C-c <arrows>
(use-package winner
  :defer 2
  :config
  (winner-mode 1)
  (custom-set-key
   (kbd "C-c <left>")
   (make-repeatable-command #'winner-undo)))

;; *** Resize windows

(progn-safe "Resize windows"
  (custom-set-key (kbd "C-x {")
                  (make-repeatable-command 'shrink-window-horizontally))

  (custom-set-key (kbd "C-x }")
                  (make-repeatable-command 'enlarge-window-horizontally))

  ;; `make-repeatable-command' doesn't work with C functions
  (custom-set-key (kbd "C-x ^")
                  (make-repeatable-command
                   (defun ff/enlarge-window (size)
                     "Lisp wrapper around `enlarge-window'"
                     (interactive "p")
                     (enlarge-window size)))))

;; *** Swap windows

(progn-safe "Swap windows"
  ;; Adapted from Magnar Sveen:
  ;;   http://whattheemacsd.com/buffer-defuns.el-02.html
  (defun ff/rotate-windows (count)
    "Perform COUNT circular permutations of the windows."
    (interactive "p")
    (let* ((non-dedicated-windows (-remove 'window-dedicated-p (window-list)))
           (num-windows (length non-dedicated-windows))
           (i 0)
           (step (+ num-windows count)))
      (cond ((not (> num-windows 1))
             (message "You can't rotate a single window!"))
            (t
             (dotimes (counter (- num-windows 1))
               (let* ((next-i (% (+ step i) num-windows))
                      (w1 (elt non-dedicated-windows i))
                      (w2 (elt non-dedicated-windows next-i))

                      (b1 (window-buffer w1))
                      (b2 (window-buffer w2))

                      (s1 (window-start w1))
                      (s2 (window-start w2)))
                 (set-window-buffer w1 b2)
                 (set-window-buffer w2 b1)
                 (set-window-start w1 s2)
                 (set-window-start w2 s1)
                 (setq i next-i)))))))

  (defun ff/rotate-windows-backwards (count)
    "Perform COUNT circular permutations of the windows.
Rotation is done in the opposite order as `ff/rotate-windows'."
    (interactive "p")
    (ff/rotate-windows (- count)))

  (custom-set-key (kbd "H-<left>")  'ff/rotate-windows)
  (custom-set-key (kbd "H-<right>") 'ff/rotate-windows-backwards))

;; *** Hydra to wrap all this

(progn-safe "Window management hydra"
  (defvar ff/key² (kbd "²")
    "Key in the leftmost position of the number row.
Labeled `²' in French keyboards layouts.")

  (custom-set-key
   ff/key²
   (defhydra windows-hydra (:color amaranth)
     "
Resize windows ^^^^     Switch to  ^^    Window configuration
---------------^^^^     -----------^^    --------------------
^    _<kp-8>_     ^     _b_uffer         _0_: delete window
_<kp-4>_ ✜ _<kp-6>_     _f_ile           _1_: delete others
^    _<kp-5>_     ^     _r_ecent file    _2_: split above/below
^    ^      ^     ^     _B_ookmark       _3_: split left-right
_=_: balance^     ^     ^ ^              _u_ndo

"
     ;; Move
     ("S-<left>"  windmove-left               nil)
     ("<left>"    windmove-left               nil)
     ("S-<right>" windmove-right              nil)
     ("<right>"   windmove-right              nil)
     ("S-<up>"    windmove-up                 nil)
     ("<up>"      windmove-up                 nil)
     ("S-<down>"  windmove-down               nil)
     ("<down>"    windmove-down               nil)
     ("SPC"       other-window                nil)
     ;; Rotate windows
     ("H-<left>"  ff/rotate-windows           nil)
     ("H-<right>" ff/rotate-windows-backwards nil)
     ;; Resize windows
     ("<kp-4>"    shrink-window-horizontally  nil)
     ("<kp-6>"    enlarge-window-horizontally nil)
     ("<kp-8>"    shrink-window               nil)
     ("<kp-5>"    enlarge-window              nil)
     ("="         balance-windows             nil)
     ;; Change configuration
     ("<kp-0>"    delete-window               nil)
     ("0"         delete-window               nil)
     ("à"         delete-window               nil)
     ("<kp-1>"    delete-other-windows        nil)
     ("1"         delete-other-windows        nil)
     ("&"         delete-other-windows        nil)
     ("<kp-2>"    split-window-below          nil)
     ("2"         split-window-below          nil)
     ("é"         split-window-below          nil)
     ("<kp-3>"    split-window-right          nil)
     ("3"         split-window-right          nil)
     ("\""        split-window-right          nil)
     ("u"         winner-undo                 nil)
     ;; Switch buffers / files
     ("b"         ido-switch-buffer           nil)
     ("f"         ido-find-file               nil)
     ("r"         helm-recentf                nil)
     ("B"         bookmark-jump               nil)
     ;; Quit
     ("q" nil "quit" :color blue))))

;; ** Buffers management

;; *** Find-file and switch-to-buffer in other window

(progn-safe "Prefix argument for find-file & the like"
  (custom-set-key (kbd "C-x C-f") 'ff/find-file)
  (defun ff/find-file (&optional argp)
    "Use prefix argument to select where to find a file.

Without prefix argument ARGP, visit the file in the current window.
With a universal prefix arg, display the file in another window.
With two universal arguments, visit the file in another window."
    (interactive "p")
    (cond ((eq argp 1)
           (call-interactively 'find-file))
          ((eq argp 4)
           (call-interactively 'ido-display-file))
          ((eq argp 16)
           (call-interactively 'find-file-other-window))))

  (custom-set-key (kbd "C-x b") 'ff/switch-to-buffer)
  (defun ff/switch-to-buffer (&optional argp)
    "Use prefix argument to select where to switch to buffer.

Without prefix argument ARGP, switch the buffer in the current window.
With a universal prefix, display the buffer in another window.
With two universal arguments, switch the buffer in another window."
    (interactive "p")
    (cond ((eq argp 1)
           (call-interactively 'switch-to-buffer))
          ((eq argp 4)
           (call-interactively 'display-buffer))
          (t
           (call-interactively 'switch-to-buffer-other-window)))))

;; *** Uniquify buffer names

(use-package uniquify
  :config
  (setq uniquify-buffer-name-style 'post-forward
        uniquify-separator         ":"))

;; *** Buffer switching

;; If a buffer is displayed in another frame, raise it
(setq-default display-buffer-reuse-frames t)

(use-package ibuffer
  :defer    t
  :init     (defalias 'list-buffers 'ibuffer)
  :config   (ff/load-configuration "ibuffer"))

;; ** User interaction

(defalias 'yes-or-no-p 'y-or-n-p)   ;; Don't bother typing 'yes'

;; *** recursive minibuffer

(progn-safe "Recursive minibuffer"
  (setq enable-recursive-minibuffers t)
  (minibuffer-depth-indicate-mode 1))

;; *** ido

(use-package ido
  :config
  (ido-mode 1)
  (ido-everywhere 1)
  (put 'ido-exit-minibuffer 'disabled nil)
  (setq ido-enable-flex-matching               t)
  (setq ido-auto-merge-work-directories-length -1)
  (setq ido-create-new-buffer                  'always)
  (setq ido-use-filename-at-point              'guess)
  (setq ido-default-buffer-method              'selected-window))

(use-package ido-ubiquitous
  :ensure t
  :config
  (ido-ubiquitous-mode 1))

;; *** helm

(use-package helm
  :ensure t
  :defer t
  :init
  (custom-set-key (kbd "C-x C-h") 'helm-mini)
  (custom-set-key (kbd "C-x C-r") 'helm-recentf)
  (custom-set-key (kbd "C-x M-x") 'helm-M-x)
  (custom-set-key (kbd "C-x C-i") 'helm-imenu))

;; *** smex

(use-package smex
  :ensure t
  :defer  t
  :init
  (custom-set-key (kbd "M-x") 'smex)

  :config
  (smex-initialize))

;; *** Guide-key

(use-package guide-key
  :ensure   t
  :defer    5
  :commands guide-key/add-local-guide-key-sequence
  :diminish guide-key-mode

  :init
  (setq guide-key/guide-key-sequence
        '("C-x r"   ;; rectangles, registers and bookmarks
          "C-x 8"   ;; special characters
          "C-x RET" ;; coding system
          "C-x C-k" ;; keyboard macros
          ))

  :config
  (guide-key-mode 1))


;; *** "Toggle" and "Run" key maps

(progn-safe "Toggle keymap"
  ;; Adapted from Artur Malabara (Endless Parentheses)
  ;;   http://endlessparentheses.com/the-toggle-map-and-wizardry.html
  (define-prefix-command        'ff/toggle-map)
  (custom-set-key (kbd "C-c t") 'ff/toggle-map)
  (add-to-list 'guide-key/guide-key-sequence "C-c t")

  (define-key ff/toggle-map "e" #'emacs-lisp-mode)
  (define-key ff/toggle-map "o" #'org-mode)

  (define-key ff/toggle-map "l" #'linum-mode)
  (define-key ff/toggle-map "v" #'visual-line-mode)
  (define-key ff/toggle-map "d" #'toggle-debug-on-error))

(progn-safe "Run keymap"
  ;; Adapted from Artur Malabara (Endless Parentheses)
  ;;   http://endlessparentheses.com/launcher-keymap-for-standalone-features.html
  (define-prefix-command        'ff/run-map)
  (custom-set-key (kbd "C-c r") 'ff/run-map)
  (custom-set-key (kbd "M-r")   'ff/run-map)
  (add-to-list 'guide-key/guide-key-sequence "C-c r")
  (add-to-list 'guide-key/guide-key-sequence "M-r")

  (define-key ff/run-map "f" #'find-dired)
  (define-key ff/run-map "g" #'rgrep)
  (define-key ff/run-map "G" #'lgrep)
  (define-key ff/run-map "m" #'woman)
  (define-key ff/run-map "C" #'clone-indirect-buffer))


;; ** Persistency

;; *** Variable files

(progn-safe "Variable files"
  (setq url-configuration-directory (ff/variable-file "url/"))
  (setq auto-save-list-file-prefix  (ff/variable-file "auto-save-list/"))
  (setq tramp-persistency-file-name (ff/variable-file "tramp")))


;; *** Sessions

(use-package desktop+
  :load-path (lambda () (ff/emacsd "packages/desktop+"))
  :commands  (desktop-load
              desktop-create)

  :config
  (ido-ubiquitous-mode 1)
  (setq desktop-base-dir (ff/variable-file "desktops/")
        desktop-save t)

  (desktop+/special-buffer-handlers))


;; *** Recent files

(use-package recentf
  :defer 2

  :config
  (setq recentf-max-saved-items 1000)
  (setq recentf-auto-cleanup    60)
  (setq recentf-save-file (ff/variable-file "recentf"))
  (recentf-mode 1)

  ;; Add files already opened from the command-line to the recentf list
  ;; (this is only be necessary because of the deferred loading)
  (mapc (lambda (buffer)
          (when (buffer-file-name buffer)
            (recentf-push (buffer-file-name buffer))))
        (buffer-list))

  (require 'sync-recentf))

(use-package sync-recentf
  :ensure t
  :defer t

  :config
  (use-package helm-files
    :defer t
    :config
    (push `(candidates
            . ,(lambda ()
                 (--remove (string= it sync-recentf-marker)
                           recentf-list)))
          helm-source-recentf)))

;; *** Bookmarks

(use-package bookmark+
  :ensure t
  :defer  t

  :init
  (setq bookmark-default-file (ff/variable-file "bookmarks.el"))
  (setq bmkp-last-as-first-bookmark-file nil)
  (custom-set-key (kbd "C-x <kp-add>")
                  'bmkp-next-bookmark-this-file/buffer-repeat)
  (custom-set-key (kbd "C-x <kp-subtract>")
                  'bmkp-previous-bookmark-this-file/buffer-repeat)
  (custom-set-key (kbd "C-x p SPC")
                  (lambda ()
                    (interactive)
                    (bmkp-toggle-autonamed-bookmark-set/delete)
                    (bmkp-make-bookmark-temporary (bmkp-default-bookmark-name))))

  :config
  (require 'bookmark+-lit))

(use-package bookmark+-lit
  :defer t
  :config
  (setq bmkp-auto-light-when-jump      'all-in-buffer)
  (setq bmkp-auto-light-when-set       'all-in-buffer)
  (setq bmkp-light-style-autonamed     'lfringe)
  (setq bmkp-light-style-non-autonamed 'rfringe))


;; * Text editing

;; This section contains everything related to text editing in general, i.e. not
;; tied to a particular major mode.

;; ** Global configuration

;; *** Enable commands

(progn-safe "Enable commands"
  (put 'set-goal-column  'disabled nil) ;; (C-x C-n)
  (put 'narrow-to-region 'disabled nil) ;; (C-x n n)
  (put 'upcase-region    'disabled nil) ;; (C-x C-u)
  (put 'downcase-region  'disabled nil) ;; (C-x C-l)
  (put 'erase-buffer     'disabled nil))

;; *** General behaviour

(progn-safe "General editing behaviour"
  (setq-default visible-bell t)
  (show-paren-mode 1)                   ;; Parenthesis matching
  (setq-default show-paren-style 'mixed) ;; Show the whole expression if it is too large
  (setq-default shift-select-mode nil)   ;; No shift selection
  (setq-default diff-switches "-u")      ;; Unified diffs
  (define-coding-system-alias 'UTF-8 'utf-8)

  ;; Useful in combination with expand-region
  (pending-delete-mode 1))

;; *** Key bindings

(progn-safe "Editing key bindings"
  (custom-set-key (kbd "M-g")   'goto-line) ;; better keybinding for goto-line
  (custom-set-key (kbd "C-x g") 'revert-buffer)
  (custom-set-key (kbd "C-c q") (make-repeatable-command 'join-line)))

;; ** Point, mark & region handling

;; Easily cycle through the Mark Ring
(setq-default set-mark-command-repeat-pop t)

;; *** Move point

(progn-safe "VI-like movement with H-{h,j,k,l}"
  (custom-set-key (kbd "H-j")   #'next-line)
  (custom-set-key (kbd "H-k")   #'previous-line)
  (custom-set-key (kbd "H-h")   #'backward-char)
  (custom-set-key (kbd "H-l")   #'forward-char)
  (custom-set-key (kbd "H-M-j") #'forward-paragraph)
  (custom-set-key (kbd "H-M-k") #'backward-paragraph)
  (custom-set-key (kbd "H-M-h") #'backward-word)
  (custom-set-key (kbd "H-M-l") #'forward-word))

(progn-safe "Move between pages with M-pgUp / M-pgDn"
  (global-set-key (kbd "M-<next>")   #'forward-page)
  (global-set-key (kbd "M-<prior>")  #'backward-page))

(progn-safe "Move to BOL or indentation"
  (defun ff/move-beginning-of-line (arg)
    "Move point back to indentation of beginning of line.

Move point to the first non-whitespace character on this line.
If point is already there, move to the beginning of the line.
Effectively toggle between the first non-whitespace character and
the beginning of the line.

If ARG is not nil or 1, move forward ARG - 1 lines first.  If
point reaches the beginning or end of the buffer, stop there."
    (interactive "^p")
    (setq arg (or arg 1))

    ;; Move lines first
    (when (/= arg 1)
      (let ((line-move-visual nil))
        (forward-line (1- arg))))

    (let ((orig-point (point)))
      (back-to-indentation)
      (when (= orig-point (point))
        (move-beginning-of-line 1))))

  (global-set-key [remap move-beginning-of-line]
                  'ff/move-beginning-of-line))

;; *** Scroll

(progn-safe "Set mark before scrolling"
  (defadvice scroll-up (before set-mark activate)
    "Set the mark before scrolling."
    (push-mark))

  (defadvice scroll-down (before set-mark activate)
    "Set the mark before scrolling."
    (push-mark)))

;; *** Multiple cursors

(use-package multiple-cursors
  :ensure t
  :defer  t

  :init
  (setq mc/list-file (ff/variable-file "mc-lists.el"))

  (defalias 'mc 'mc/edit-lines)
  (custom-set-key (kbd "H-<")     'mc/mark-next-like-this)
  (custom-set-key (kbd "H->")     'mc/mark-previous-like-this)
  (custom-set-key (kbd "C-c H-<") 'mc/mark-all-like-this)
  (custom-set-key (kbd "H-SPC")   'set-rectangular-region-anchor))

;; *** Expand region

(use-package expand-region
  :ensure t
  :defer  t
  :init
  (custom-set-key (kbd "C-x SPC") 'er/expand-region))

;; ** Standard text manipulation

;; This section is for standard text manipulation features: copy/paste, undo, ...

;; *** Copy-pasting

;; Yank at point (like in a tty)
(setq-default mouse-yank-at-point t)

;; Browse the kill ring using M-y
(use-package browse-kill-ring
  :ensure t
  :defer 2
  :config
  (browse-kill-ring-default-keybindings))

(progn-safe "Invert `insert-register's default behaviour:"
  (custom-set-key [remap insert-register] #'ff/insert-register)

  ;; insert before point by default, after point if a prefix arg is given.
  (defun ff/insert-register (&optional arg)
    "Insert contents of a register.

Normally puts mark before and point after the inserted text.
If ARG is non-nil (i.e. when called with a prefix argument), puts point
before and mark after.

See `insert-register'."
    (interactive "P")
    (let ((current-prefix-arg (not arg)))
      (call-interactively #'insert-register))))

;; *** Undo

(progn-safe "Undo in regions"
  ;; Adapted from Magnar Sveen (What the .emacs.d!?)
  ;;   http://whattheemacsd.com/my-misc.el-02.html
  (defun ff/undo (&optional arg)
    "Call undo, improving the use of regions."
    (interactive "p")
    (if (use-region-p)
        (let ((m (set-marker (make-marker) (mark)))
              (p (set-marker (make-marker) (point)))
              (deactivate-mark nil))
          (undo arg)
          (goto-char p)
          (set-mark m)
          (set-marker p nil)
          (set-marker m nil))
      (undo arg)))
  (custom-set-key (kbd "C-_") #'ff/undo))

;; *** Search

;; **** Isearch

(progn-safe "Call `occur' from isearch"
  (define-key isearch-mode-map (kbd "C-o") 'isearch-occur))

(progn-safe "Better backspace during isearch"
  ;; from Drew Adams     (http://emacs.stackexchange.com/q/10359/221)
  ;;      John Mastro    (https://gist.github.com/johnmastro/508fb22a2b4e1ce754e0)
  ;;      Artur Malabara (http://endlessparentheses.com/better-backspace-during-isearch.html)
  (define-key isearch-mode-map [remap isearch-delete-char] #'isearch-delete-something)
  (defun isearch-delete-something ()
    "Delete non-matching text or the last character."
    (interactive)
    (if (= 0 (length isearch-string))
        (ding)
      (setq isearch-string
            (substring isearch-string
                       0
                       (or (isearch-fail-pos) (1- (length isearch-string)))))
      (setq isearch-message
            (mapconcat #'isearch-text-char-description isearch-string "")))
    (if isearch-other-end (goto-char isearch-other-end))
    (isearch-search)
    (isearch-push-state)
    (isearch-update)))

;; **** Helm swoop

(use-package helm-swoop
  :ensure t
  :defer  t

  :init
  (custom-set-key (kbd "M-i") 'helm-swoop)
  (define-key isearch-mode-map (kbd "C-i") 'helm-swoop-from-isearch)

  :config
  ;; Move up and down like isearch
  (define-key helm-swoop-map (kbd "C-r") 'helm-previous-line)
  (define-key helm-swoop-map (kbd "C-s") 'helm-next-line)
  (define-key helm-multi-swoop-map (kbd "C-r") 'helm-previous-line)
  (define-key helm-multi-swoop-map (kbd "C-s") 'helm-next-line))


;; *** Shuffle text

(progn-safe "Shuffle text around"
  (custom-set-key
   (kbd "C-S-<up>")
   (defun ff/move-line-up ()
     "Move up the current line."
     (interactive)
     (transpose-lines 1)
     (forward-line -2)
     (indent-according-to-mode)))

  (custom-set-key
   (kbd "C-S-<down>")
   (defun ff/move-line-down ()
     "Move down the current line."
     (interactive)
     (forward-line 1)
     (transpose-lines 1)
     (forward-line -1)
     (indent-according-to-mode)))

  (custom-set-key
   (kbd "ESC C-S-<up>")
   (defun ff/duplicate-line-up ()
     "Duplicate the current line upwards."
     (interactive)
     (ff/duplicate-line-down)
     (forward-line -1)))

  (custom-set-key
   (kbd "ESC C-S-<down>")
   (defun ff/duplicate-line-down ()
     "Duplicate the current line downwards."
     (interactive)
     (let ((line (buffer-substring (line-beginning-position) (line-end-position))))
       (forward-line 0)
       (insert line)
       (open-line 1)
       (forward-line 1)))))

;; *** Handle capitalization

(progn-safe "Handle capitalization"
  (custom-set-key
   (kbd "M-c")
   (defun ff/capitalize-word (arg)
     "Capitalize the last word.
With a universal prefix arg, capitalize from point to the end of
the word (default `capitalize-word' behaviour)"
     (interactive "P")
     (capitalize-word
      (cond ((null arg)       -1)
            ((equal arg '(4))  1)
            (t                 arg))))))


;; ** Save typing

;; This section contains all sorts of features allowing to save some typing by
;; automatically inserting text.

;; *** Abbreviations

(use-package abbrev
  :defer t
  :diminish abbrev-mode

  :init
  (defun ff/enable-abbrev ()
    "Turn `abbrev-mode' on."
    (abbrev-mode 1))

  :config
  (quietly-read-abbrev-file))

;; *** Snippets

(use-package yasnippet
  :ensure   t
  :commands yas-recompile-all
  :diminish (yas-minor-mode . " Y")

  :init
  (defun ff/enable-yasnippet ()
    "Turn `yas-minor-mode' on."
    (yas-minor-mode 1))

  :config
  (setq yas-snippet-dirs (list (ff/emacsd "snippets")))
  (yas-reload-all))

;; *** Auto completion

(use-package company
  :ensure   t
  :defer    2
  :diminish (company-mode . " c⇢")

  :config
  (global-company-mode 1))

;; *** Manipulate file names

(progn-safe "Manipulate file names"
  (custom-set-key (kbd "C-c f") 'ff/insert-file-name)
  (defun ff/insert-file-name (filename &optional argp)
    "Insert name of file FILENAME into buffer after point.

With a prefix argument ARGP, expand the file name to its fully
canonicalized path.  See `expand-file-name'.

The default with no prefix is to use the relative path to file
name from current directory, `default-directory'.  See
`file-relative-name'."
    (interactive "fInsert file name: \nP")
    (cond ((eq nil argp)
           (insert (file-relative-name filename)))
          (t
           (insert filename))))

  (custom-set-key (kbd "C-c F") 'ff/copy-file-name)
  (defun ff/copy-file-name ()
    "Copy the current buffer file name to the clipboard."
    (interactive)
    (let ((filename (if (equal major-mode 'dired-mode)
                        default-directory
                      (buffer-file-name))))
      (when filename
        (kill-new filename)
        (message "Copied buffer file name '%s' to the clipboard." filename)))))

;; *** Automatically pair braces and quotes

(use-package autopair
  :ensure   t
  :defer    2
  :diminish (autopair-mode . " 🄐")

  :config
  (autopair-global-mode 1)
  (add-hook 'autopair-mode-hook (lambda ()
                                  (when autopair-mode
                                    (ff/disable-paredit-mode)))))

(use-package paredit
  :ensure   t
  :defer    t
  :diminish (paredit-mode . " 🄟")

  :init
  (defun ff/disable-paredit-mode ())

  :config
  (defun ff/disable-paredit-mode ()
    (paredit-mode -1))

  (add-hook 'paredit-mode-hook (lambda ()
                                 (when paredit-mode
                                   (autopair-mode -1))))

  ;; Create a new paredit keymap
  (setq ff/paredit-mode-map
        (let ((map (make-sparse-keymap)))
          (set-keymap-parent map paredit-mode-map)
          map))
  ;; Replace the default one
  (setq minor-mode-map-alist
        (cons (cons 'paredit-mode ff/paredit-mode-map)
              (assq-delete-all 'paredit-mode minor-mode-map-alist)))
  ;; Remove all default bindings involving arrow keys
  (mapc (lambda (arrow)
          (mapc (lambda (mod)
                  (define-key ff/paredit-mode-map (kbd (concat mod arrow)) nil))
                '("M-" "C-" "S-" "M-C-" "ESC C-")))
        '("<left>" "<right>" "<up>" "<down>"))
  ;; Add our own
  (define-key ff/paredit-mode-map (kbd "s-<right>") #'paredit-forward-slurp-sexp)
  (define-key ff/paredit-mode-map (kbd "s-<left>")  #'paredit-forward-barf-sexp)
  (define-key ff/paredit-mode-map (kbd "s-<up>")    #'paredit-splice-sexp-killing-backward)
  (define-key ff/paredit-mode-map (kbd "s-<down>")  #'paredit-splice-sexp-killing-forward))

(progn-safe "Move by sexp"
  (defmacro ff/paredit-or-fallback (paredit-command fallback-command)
    (let ((fn-sym (intern (format "paredit-or-%s" (symbol-name fallback-command)))))
      `(defun ,fn-sym ()
         (interactive)
         (call-interactively (if (bound-and-true-p paredit-mode)
                                 #',paredit-command
                               #',fallback-command)))))
  (ff/paredit-or-fallback paredit-forward      forward-sexp)
  (ff/paredit-or-fallback paredit-backward     backward-sexp)
  (ff/paredit-or-fallback paredit-backward-up  backward-up-list)
  (ff/paredit-or-fallback paredit-forward-down down-list)

  (defhydra sexp-hydra (custom-bindings-mode-map "ESC")
    "Move by S-expression"
    ("C-<right>" paredit-or-forward-sexp)
    ("C-<left>"  paredit-or-backward-sexp)
    ("C-<up>"    paredit-or-backward-up-list)
    ("C-<down>"  paredit-or-down-list)))


;; *** Increment numbers at point

(progn-safe "Increment number at point"
  ;; This is useful as a complement / replacement of keyboard macro counters.
  ;; from http://www.danielehrman.com/blog/2014/5/25/11-must-haves-for-every-power-programmer
  (defun ff/increment-number-at-point (&optional count)
    (interactive "p")
    (setq count (or count 1))
    (skip-chars-backward "0-9")
    (when (looking-at "[0-9]+")
      (replace-match (number-to-string (+ count (string-to-number (match-string 0)))))))

  (custom-set-key (kbd "C-c +")
                  (make-repeatable-command #'ff/increment-number-at-point)))


;; ** Whitespace handling

;; *** Indentation

(setq-default indent-tabs-mode nil) ;; Indent with spaces

;; *** Trailing whitespace

(progn-safe "Delete trailing whitespace"

  (define-minor-mode auto-dtw-mode
    "Automatically delete trailing whitespace."
    :lighter    " ˽"
    :init-value nil
    (setq show-trailing-whitespace auto-dtw-mode))

  (add-to-list 'write-file-functions 'ff/auto-dtw)
  (defun ff/auto-dtw ()
    "Delete trailing whitespace, except on the current line if point is at EOL."
    (when auto-dtw-mode
      (let ((ws  (save-excursion
                   (if (and (eolp)
                            (looking-back "[[:space:]]"))
                       (let ((end (point))
                             (bol (- (line-beginning-position) 1)))
                         (search-backward-regexp "[^[:space:]]" nil t)
                         (when (< (point) bol)
                           (goto-char bol))
                         (buffer-substring (1+ (point)) end))
                     ""))))
        (delete-trailing-whitespace)
        (insert ws)))))

;; ** Lines handling

;; *** Highlight current line

(defun ff/highlight-line ()
  "Turn on `hl-line-mode'."
  (hl-line-mode 1))

;; *** Truncate long lines

(defun ff/truncate-lines ()
  "Truncate long lines."
  (toggle-truncate-lines 1))

;; *** Fill & unfill paragraphs

(setq-default fill-column 80) ;; Larger fill column

(defun unfill-paragraph ()
  "Unfill the paragraph at point."
  (interactive)
  (let ((fill-column (point-max)))
    (fill-paragraph)))

;; *** Visual lines and adaptive wrapping

(setq visual-line-fringe-indicators '(left-curly-arrow right-curly-arrow))

(use-package adaptive-wrap
  :ensure   t
  :diminish adaptive-wrap-prefix-mode
  :commands ff/activate-adaptive-wrap-prefix-mode

  :init
  (add-hook 'visual-line-mode-hook 'ff/activate-adaptive-wrap-prefix-mode)

  :config
  (defun ff/activate-adaptive-wrap-prefix-mode ()
    "Toggle `visual-line-mode' and `adaptive-wrap-prefix-mode' simultaneously."
    (adaptive-wrap-prefix-mode (if visual-line-mode 1 -1))))

(progn-safe "Auto filling and visual lines"
  (add-hook 'visual-line-mode-hook 'ff/no-auto-fill)
  (defun ff/no-auto-fill ()
    "Disable `auto-fill-mode' when `visual-line-mode' is active."
    (if visual-line-mode
        (auto-fill-mode -1)))

  (diminish 'auto-fill-function " ¶")
  (diminish 'visual-line-mode   " §"))

;; ** Special characters

;; *** Fall-back font for unicode characters

(progn-safe "Font for unicode characters"
  ;; Symbola font from http://users.teilar.gr/~g1951d/
  ;;
  ;; More documentation on `set-fontset-font':
  ;;   http://www.emacswiki.org/emacs/FontSets#toc1
  ;;
  (mapc (lambda (range)
          (set-fontset-font "fontset-default" range
                            (font-spec :size 13 :name "Symbola")))
        (list
         ;; Default choice for all unknown chars
         nil

         ;; Explicit font for unicode blocks:
         ;;   (http://en.wikipedia.org/wiki/Unicode_block)
         ;;
         ;; - block "Letterlike Symbols"
         (cons (decode-char 'ucs #x2100)
               (decode-char 'ucs #x214F))

         ;; - blocks "Arrows" to "Miscellaneous Symbols and Arrows"
         (cons (decode-char 'ucs #x2190)
               (decode-char 'ucs #x2BFF))

         ;; - blocks "Mahjong Tiles" to "Supplemental Symbols and Pictographs"
         (cons (decode-char 'ucs #x1F000)
               (decode-char 'ucs #x1F9FF)))))

;; *** Easily insert unicode

(progn-safe "Insert unicode characters with helm"
  (defun helm-insert-char ()
    (interactive)
    (require 'helm-match-plugin)
    (helm :prompt "Character: "
          :sources '((name . "Characters")
                     (init . (lambda ()
                               (with-current-buffer (helm-candidate-buffer 'global)
                                 (erase-buffer)
                                 (mapc (lambda (char)
                                         (insert-char (cdr char))
                                         (insert " ")
                                         (insert (car char))
                                         (newline))
                                       (ucs-names)))))
                     (candidates-in-buffer)
                     (action . (("insert character"
                                 . (lambda (candidate)
                                     (print candidate)
                                     (insert (substring candidate 0 1))))
                                ("insert name"
                                 . (lambda (candidate)
                                     (insert (substring candidate 2))))
                                ("insert code"
                                 . (lambda (candidate)
                                     (let* ((name (substring candidate 2))
                                            (code (cdr (assoc name ucs-names))))
                                       (insert (format "%d" code))))))))))
  (custom-set-key (kbd "C-x 8 RET") 'helm-insert-char))

(use-package iso-transl
  :defer t
  :config
  (mapc (lambda (cell)
          (let* ((key       (car cell))
                 (char-name (cdr cell))
                 (char      (cdr (assoc char-name (ucs-names)))))
            (define-key iso-transl-ctl-x-8-map
              (kbd key)
              (vector char))))
        '(("<right>"   . "RIGHTWARDS ARROW")
          ("<left>"    . "LEFTWARDS ARROW")
          ("<up>"      . "UPWARDS ARROW")
          ("<down>"    . "DOWNWARDS ARROW")
          ("S-<right>" . "RIGHTWARDS DOUBLE ARROW"))))


;; * Interaction with external tools

;; This section contains everything related to running external processes from
;; within Emacs, or calling emacs from external processes.

;; ** Shell

;; *** Server

(use-package server
  :defer 2
  :config
  (defvar ff/main-server-name "server")

  (funcall
   (defun ff/server-start ()
     "Start an emacs server using an automatically generated name.
If an emacs server is already running, it is restarted."
     (if (and (not (string= server-name ff/main-server-name))
              (boundp 'server-process)
              server-process
              (memq (process-status server-process) '(connect listen open run)))
         ;; There is already an instance running; just restart it
         (server-start)

       ;; Start a new server
       (setq server-name (format "server%d" (emacs-pid)))
       (when (server-running-p server-name)
         (server-force-delete))
       (message "Starting server with name `%s'." server-name)
       (server-start))

     (setenv "EMACS_SERVER" server-name)))

  (defun ff/main-server ()
    (interactive)
    (when (and (boundp 'server-process)
               server-process
               (memq (process-status server-process) '(connect listen open run))
               (not (string= server-name ff/main-server-name)))
      ;; There is already an instance running under a different name; kill it
      (server-force-delete)
      (delete-process server-process))

    (setq server-name ff/main-server-name)
    (message "Starting main emacs server with name `%s'." server-name)
    (server-start)
    (setenv "EMACS_SERVER" server-name)))

;; *** Bash commands

(progn-safe "Helpers for bash interaction"

  ;; Helper for the E-source shell function
  (defun ff/source (filename)
    "Update environment variables from a shell source file.

Source shell script FILENAME, recording any change made to the
environment.  These changes are then applied to Emacs' environment
in `process-environment'."
    (interactive "fSource file: ")

    (message "Sourcing environment from `%s'..." filename)
    (with-temp-buffer
      (shell-command (format "diff -u <(true; export) <(source %s; export)" filename)
                     (current-buffer))
      (goto-char (point-min))
      (let ((envvar-re "declare -x \\([^=]+\\)=\\(.*\\)$"))
        ;; Remove environment variables
        (while (search-forward-regexp (concat "^-" envvar-re) nil t)
          (let ((var (match-string 1)))
            (message "%s" (prin1-to-string `(setenv ,var nil)))
            (setenv var nil)))

        ;; Update environment variables
        (goto-char (point-min))
        (while (search-forward-regexp (concat "^+" envvar-re) nil t)
          (let ((var (match-string 1))
                (value (read (match-string 2))))
            (message "%s" (prin1-to-string `(setenv ,var ,value)))
            (setenv var value)))))
    (message "Sourcing environment from `%s'... done." filename))

  ;; Helper for the E-grep shell function
  (defun ff/grep (&rest args)
    (let* ((quote-arg
            (lambda (arg)
              (format " \"%s\"" arg)))
           (grep-command
            (-reduce-from 'concat
                          "grep -nH"
                          (-map quote-arg
                                args)))
           (grep-buffer
            (save-window-excursion
              (grep grep-command))))
      (winner-undo)
      (switch-to-buffer grep-buffer))))

;; *** Terminal

(use-package term
  :defer  t

  :config
  (setq term-buffer-maximum-size 100000)

  (defmacro ff/term-send-raw (binding string)
    `(define-key term-raw-map (kbd ,binding)
       (lambda ()
         ,(format "Send \"%s\" as raw characters to the terminal process." string)
         (interactive)
         (term-send-raw-string ,string))))
  (ff/term-send-raw "C-<right>"     "\e[1;5C")
  (ff/term-send-raw "C-<left>"      "\e[1;5D")
  (ff/term-send-raw "C-<backspace>" "\e\d")

  ;; Automatically yank the active region and go to the end of buffer
  ;; on line->char mode switch
  (define-key term-mode-map (kbd "C-c C-k") 'ff/term-char-mode)
  (defun ff/term-char-mode (argp)
    (interactive "P")
    (when (and argp
               (use-region-p))
      (kill-ring-save (min (point) (mark))
                      (max (point) (mark)))
      (goto-char (point-max))
      (yank))
    (term-char-mode)
    (term-send-right)))

(use-package multi-term
  :ensure t
  :defer  t

  :init
  (custom-set-key (kbd "<f2>")   'ff/multi-term)
  (custom-set-key (kbd "C-<f2>") 'multi-term-dedicated-toggle)

  (defun ff/multi-term (argp)
    "Open a new terminal or cycle among existing ones.

No prefix arg: cycle among terminals (open one if none exist)
C-u:           create new terminal
C-u C-u:       create new terminal and choose program"
    (interactive "P")
    (cond ((equal argp '(4))
           (let ((current-prefix-arg nil))
             (multi-term)))
          ((equal argp '(16))
           (let ((current-prefix-arg '(4)))
             (multi-term)))
          (t
           (call-interactively 'multi-term-next))))

  :config
  (setq multi-term-dedicated-select-after-open-p t)
  (setq term-bind-key-alist nil)

  (defun ff/multi-term-bind (key fun)
    (setq term-bind-key-alist
          (delq (assoc key term-bind-key-alist)
                term-bind-key-alist))
    (when fun
      (add-to-list 'term-bind-key-alist (cons key fun))))

  (defmacro ff/multi-term-raw (key)
    `(ff/multi-term-bind
      ,key
      (lambda ()
        ,(format "Send raw %s" key)
        (interactive)
        (term-send-raw-string (kbd ,key)))))

  (ff/multi-term-bind "C-c C-j" 'term-line-mode)
  (ff/multi-term-bind "C-c C-u" 'universal-argument)
  (ff/multi-term-bind "C-c C-c" 'term-interrupt-subjob)
  (ff/multi-term-bind "C-c C-e" 'term-send-esc)
  (ff/multi-term-raw  "C-z")
  (ff/multi-term-raw  "C-u")
  (ff/multi-term-raw  "C-k")
  (ff/multi-term-raw  "C-y")
  (ff/multi-term-raw  "C-x ~"))

;; *** Isend

(use-package isend-mode
  :ensure t
  :defer  t
  :config
  (add-hook 'isend-mode-hook 'isend-default-shell-setup)
  (add-hook 'isend-mode-hook 'isend-default-ipython-setup))

;; ** Filesystem

(use-package dired
  :defer  t
  :init
  (custom-set-key (kbd "C-x C-j") #'dired-jump)

  :config
  (add-hook 'dired-mode-hook 'ff/highlight-line)
  (add-hook 'dired-mode-hook 'ff/truncate-lines))

;; ** Version control tools

;; *** Auto-revert version-controlled files

(progn-safe "Auto-revert version-controlled files"
  (defadvice vc-find-file-hook (after ff/auto-revert-mode-for-vc activate)
    "Activate `auto-revert-mode' for vc-controlled files."
    (when vc-mode (auto-revert-mode 1))))

(use-package autorevert
  :defer t
  :diminish (auto-revert-mode . " ↻"))


;; *** Git

(use-package magit
  :ensure t
  :defer  t

  :init
  (custom-set-key (kbd "C-c v") #'magit-status))

(use-package git-gutter-fringe
  :ensure t
  :defer  t)

(use-package git-gutter
  :defer    t
  :diminish (git-gutter-mode . " ±")

  :init
  (define-key ff/toggle-map "g" #'git-gutter-mode)

  (defun ff/gg-first ()
    (interactive)
    (goto-char (point-min))
    (git-gutter:next-hunk 1))

  (defun ff/gg-last ()
    (interactive)
    (goto-char (point-max))
    (git-gutter:previous-hunk 1))

  (defun ff/gg-stage ()
    (interactive)
    (letf (((symbol-function 'yes-or-no-p)
            (lambda (msg) t)))
      (git-gutter:stage-hunk)
      (git-gutter:next-hunk 1)))

  (custom-set-key
   (kbd "C-c g")
   (defhydra git-gutter-hydra
     (:pre
      (progn (git-gutter-mode 1)
             (display-buffer (get-buffer-create "*git-gutter:diff*"))
             (sit-for 1)
             (git-gutter:previous-hunk 1)
             (git-gutter:next-hunk 1))
      :post
      (winner-undo))

     "
Git gutter:
  _j_: next hunk        _s_tage hunk     _q_uit
  _k_: previous hunk    _r_evert hunk    _Q_uit and deactivate git-gutter
  ^ ^                   _p_opup hunk
  _h_: first hunk
  _l_: last hunk        set start _R_evision
"
     ("j" git-gutter:next-hunk          nil)
     ("k" git-gutter:previous-hunk      nil)
     ("<home>" ff/gg-first              nil)
     ("h" ff/gg-first                   nil)
     ("<end>" ff/gg-last                nil)
     ("l" ff/gg-last                    nil)
     ("s" ff/gg-stage                   nil)
     ("r" git-gutter:revert-hunk        nil)
     ("p" git-gutter:popup-hunk         nil)
     ("R" git-gutter:set-start-revision nil)
     ("q" nil nil :color blue)
     ("Q" (progn (git-gutter-mode -1)
                 (sit-for 1)
                 (git-gutter:clear))
      nil :color blue)))

  :config
  (require 'git-gutter-fringe))

;; ** Various tools

;; *** grep

;; Make grep output editable
(use-package grep
  :defer t
  :config
  (use-package wgrep
    :ensure t
    :config
    (define-key grep-mode-map
      (kbd "C-x C-q") 'wgrep-change-to-wgrep-mode)))

;; *** a2ps

;; Print (part of) a buffer using a2ps
(use-package a2ps-multibyte
  :load-path (lambda () (ff/emacsd "packages/a2ps-multibyte"))
  :commands  (a2ps-buffer
              a2ps-region)

  :init
  (custom-set-key (kbd "<print>")    #'a2ps-buffer)
  (custom-set-key (kbd "C-<print>")  #'a2ps-region)

  :config
  (setq a2ps-command  "a2ps-view")
  (setq a2ps-switches '("-l" "100"))
  (add-hook 'a2ps-filter-functions
            (defun ff/a2ps-insert-page-breaks ()
              (ff/insert-page-breaks 76 5)))

  (defun ff/insert-page-breaks (page-size page-offset-max)
    (let ((try-move (lambda (f)
                      (let ((orig-pos  (point))
                            (orig-line (line-number-at-pos)))
                        (funcall f)
                        (unless (or (and (looking-at "\^L")
                                         (> page-size
                                            (- orig-line (line-number-at-pos))))
                                    (> page-offset-max
                                       (- orig-line (line-number-at-pos))))
                          (goto-char orig-pos))))))
      (goto-char (point-min))
      (while (= 0 (forward-line page-size))
        (funcall try-move 'backward-page)
        (funcall try-move 'backward-paragraph)
        (unless (looking-at "\^L")
          (insert "\^L"))
        (unless (eolp)
          (insert "\n"))))))

;; *** SLURM

(use-package slurm-mode
  :load-path (lambda () (ff/emacsd "packages/slurm"))
  :commands  slurm)

(use-package slurm-script-mode
  :load-path (lambda () (ff/emacsd "packages/slurm"))
  :commands  turn-on-slurm-script-mode
  :init
  (add-hook 'sh-mode-hook #'turn-on-slurm-script-mode))


;; * Authoring

;; ** Common features for text modes

;; *** Auto-filling
(add-hook 'text-mode-hook 'turn-on-auto-fill)

;; *** Spell check

(use-package flyspell
  :defer    t
  :diminish (flyspell-mode . " 🛪")

  :config
  ;; Arrange for the entire buffer to be checked when `flyspell-mode' is activated
  (defun ff/flyspell-buffer-after-activation ()
    "Run `flyspell-buffer' after `flyspell-mode' is activated."
    (when flyspell-mode
      (flyspell-buffer)))
  (add-hook 'flyspell-mode-hook 'ff/flyspell-buffer-after-activation)

  ;; Use <F1> to correct the word at point
  (define-key flyspell-mode-map (kbd "<f1>") 'flyspell-correct-word-before-point))


;; ** Org

(use-package org
  :defer t
  :config
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (C          . t)
     (python     . t)
     (maxima     . t)
     (gnuplot    . t)
     (sh         . t))))


;; ** Markdown

(use-package markdown-mode
  :mode ("\\.md\\'" . markdown-mode))

(use-package gmail-message-mode
  :ensure t
  :mode   ("[\\\\/]itsalltext[\\\\/]mail\\.google\\..*\\.md\\'"
           . gmail-message-mode))

;; ** LaTeX

(use-package latex
  :ensure auctex
  :defer  t

  :config
  (add-hook 'LaTeX-mode-hook 'turn-on-reftex)
  (add-hook 'LaTeX-mode-hook 'ff/enable-yasnippet)

  (add-hook 'LaTeX-mode-hook
            (defun ff/enable-latex-math-mode () (LaTeX-math-mode 1)))

  (add-hook 'LaTeX-mode-hook
            (defun ff/enable-TeX-PDF-mode () (TeX-PDF-mode 1)))

  (add-hook 'LaTeX-mode-hook
            (defun ff/guide-key-LaTeX ()
              (guide-key/add-local-guide-key-sequence "`")
              (guide-key/add-local-guide-key-sequence "` v"))))

;; *** Math symbols

(use-package latex
  :defer t
  :init
  ;; These must be defined before `latex.el` is loaded.
  ;; Otherwise, `LaTeX-math-initialize' must be called to update the list.
  (setq LaTeX-math-list
        '(("v l"       "ell"        nil nil)
          ("<"         "leqslant"   nil nil)
          (">"         "geqslant"   nil nil)
          ("<right>"   "rightarrow" nil nil)
          ("<left>"    "leftarrow"  nil nil)
          ("S-<right>" "Rightarrow" nil nil)
          ("="         "simeq"      nil nil))))

;; *** Abbreviations

(use-package latex
  :defer t
  :config
  (add-hook
   'TeX-mode-hook
   (defun ff/TeX-turn-on-abbrev ()
     (abbrev-mode 1)
     (setq local-abbrev-table TeX-mode-abbrev-table))))

;; *** Custom functions

(use-package latex
  :defer t
  :config
  (define-key LaTeX-mode-map (kbd "~")
    (defun ff/insert-tilde ()
      "Insert a tilde (~) character at point.

Potentially remove surrounding spaces around point, so that the
newly inserted character replaces them."
      (interactive)
      (skip-syntax-forward " ")
      (let ((end (point)))
        (skip-syntax-backward " ")
        (delete-region (point) end)
        (insert "~"))))

  (define-key LaTeX-mode-map (kbd "C-c a")
    (defun ff/align-latex-table ()
      "Align columns in a latex tabular environment."
      (interactive)
      (save-excursion
        (search-backward "\\begin{tabular}")
        (forward-line 1)
        (let ((beg (point)))
          (search-forward "\\end{tabular}")
          (backward-char)
          (align-regexp beg (point) "\\(\\s-*\\)&" 1 1 t)))))

  (defun ff/tex-replace-macro (macro body)
    (interactive
     (save-excursion
       (let (m b)
         (beginning-of-line)
         (search-forward "{")
         (let ((beg (point)))
           (backward-char)
           (forward-sexp)
           (setq m (buffer-substring beg (- (point) 1))))
         (search-forward "{")
         (let ((beg (point)))
           (backward-char)
           (forward-sexp)
           (setq b (buffer-substring beg (- (point) 1))))
         (list m b))))
    (save-excursion
      (query-replace (concat body " ") (concat macro "\\ ")))
    (save-excursion
      (query-replace body macro))))

;; *** Preview

(use-package preview
  :defer t
  :config
  ;; Fix incompatibility between latex-preview and gs versions
  (setq preview-gs-options '("-q" "-dNOSAFER" "-dNOPAUSE" "-DNOPLATFONTS"
                             "-dPrinted" "-dTextAlphaBits=4" "-dGraphicsAlphaBits=4")))

;; *** Manage references

(use-package reftex
  :defer t
  :config
  ;; Use \eqref for equation references
  (setq reftex-label-alist '(AMSTeX)))

;; *** Compile

(use-package compile
  :defer t

  :config
  ;; Parse LaTeX output to determine the source file
  (defun ff/compilation-error-latex-file ()
    "Analyse the LaTeX output to find the source file in which an error was reported."
    (condition-case nil
        (save-excursion
          (save-match-data
            (let ((found  nil)
                  (bound  (point))
                  beg
                  filename)
              (while (not found)
                ;; Search backward for an opening paren
                (search-backward "(" nil)

                ;; Try to find a matching closing paren
                (condition-case nil
                    (save-excursion
                      (goto-char (scan-sexps (point) 1))

                      (when (or (> (point) bound)         ;; Closing paren after the error message
                                (not (looking-back ")"))) ;; Non-matching closing delimiter
                        (setq found t)))

                  ;; Unbalanced expression
                  ((error)
                   (setq found t))))

              ;; Extract filename
              (setq beg (1+ (point)))
              (re-search-forward "[[:space:]]" nil)
              (setq filename (buffer-substring beg (- (point) 1)))
              (list filename))))

      ;; Unexpected error
      ((error)
       nil)))

  ;; Unfill "LaTeX Warning" lines
  (defun ff/compilation-LaTeX-filter ()
    (interactive)
    (save-excursion
      (goto-char (point-min))
      (setq buffer-read-only nil)
      (while (re-search-forward "^LaTeX Warning: " nil t)
        (while (not (re-search-forward "\\.$" (line-end-position) t))
          (end-of-line)
          (delete-char 1)
          (beginning-of-line)))
      (setq buffer-read-only t)))
  (add-hook 'compilation-filter-hook 'ff/compilation-LaTeX-filter)

  ;; Add LaTeX warnings detection to the list
  (add-to-list 'compilation-error-regexp-alist-alist
               '(latex-warning
                 "^LaTeX Warning: .* on input line \\([[:digit:]]+\\)\\.$" ;; Regular expression
                 ff/compilation-error-latex-file                           ;; Filename
                 1                                                         ;; Line number
                 nil                                                       ;; Column number
                 1))                                                       ;; Type (warning)
  (add-to-list 'compilation-error-regexp-alist 'latex-warning))

;; *** Aggressive sub/super-scripts

(progn-safe "Aggressive sub/superscripts"
  (defun TeX-aggressive-sub-super-script (arg)
    "Insert typed character ARG times and possibly a sub/super-script.
Sub/super-script insertion is done only in a (La)TeX math mode region.
The inserted sub/super-script is copied from the last occurence of a
sub/superscript for the token at point."
    (interactive "p")
    (self-insert-command arg)
    (when (texmathp)
      (let ((sub-super-script
             (save-excursion
               (let ((current-token (let ((end (point)))
                                      (backward-sexp 1)
                                      (buffer-substring-no-properties (point) end))))
                 (when (search-backward current-token nil t)
                   (search-forward current-token)
                   (let ((begin (point)))
                     (forward-sexp 1)
                     (buffer-substring-no-properties begin (point))))))))
        (when sub-super-script
          (set-mark (point))
          (insert sub-super-script)))))

  (define-minor-mode TeX-aggressive-sub-super-script-mode
    "Aggressively complete sub and superscripts in (La)TeX math mode."
    :lighter " ^"
    :init-value nil
    :keymap (let ((map (make-sparse-keymap)))
              (define-key map (kbd "_") #'TeX-aggressive-sub-super-script)
              (define-key map (kbd "^") #'TeX-aggressive-sub-super-script)
              map)))


;; * Programming

;; ** Common features for programming modes

;; *** Which function mode

;; From Sebastian Wiesner (https://github.com/lunaryorn/.emacs.d/blob/94ff67258d/init.el#L347-L358)
(use-package which-func
  :defer t
  :init
  (defun ff/turn-on-which-func ()
    (which-function-mode 1))
  (add-hook 'prog-mode-hook #'ff/turn-on-which-func)

  :config
  (let ((wf-format (assq 'which-func-mode mode-line-misc-info)))
    (setq which-func-unknown "???"
          which-func-format  `((:propertize (" ➤ " which-func-current)
                                            face which-func))
          header-line-format wf-format))
  (setq mode-line-misc-info
        (assq-delete-all 'which-func-mode mode-line-misc-info)))

;; *** Compilation

(use-package compile
  :defer t

  :config
  (defhydra next-error-hydra
    (custom-bindings-mode-map "C-x")
    "
Compilation errors:
_j_: next error        _h_: first error    _q_uit
_k_: previous error    _l_: last error
"
    ("`" next-error     nil)
    ("è" next-error     nil)
    ("j" next-error     nil :bind nil)
    ("k" previous-error nil :bind nil)
    ("h" first-error    nil :bind nil)
    ("l" (condition-case err
             (while t
               (next-error))
           (user-error t))
     nil :bind nil)
    ("q" nil            nil :color blue))

  ;; scroll compilation buffer until first error
  (setq compilation-scroll-output 'first-error)

  ;; ANSI coloring in compilation buffers
  (require 'ansi-color)
  (defun ff/ansi-colorize-buffer ()
    (setq buffer-read-only nil)
    (ansi-color-apply-on-region (point-min) (point-max))
    (setq buffer-read-only t))
  (add-hook 'compilation-filter-hook 'ff/ansi-colorize-buffer))

(use-package multi-compile
  :defer 2
  :load-path (lambda () (ff/emacsd "packages/multi-compile"))
  :commands list-compilation-buffers

  :config
  (multi-compile "compile5" :key (kbd "<f5>"))
  (multi-compile "compile6" :key (kbd "<f6>"))
  (multi-compile "compile7" :key (kbd "<f7>"))
  (multi-compile "compile8" :key (kbd "<f8>"))

  (require 's)
  (defun list-compilation-buffers ()
    (interactive)
    (with-current-buffer (get-buffer-create "*compilation-buffers*")
      (erase-buffer)
      (setq truncate-lines t)
      (cl-labels ((s-truncate-left
                   (len s)
                   (let ((truncated (if (> (string-width s) len)
                                        (s-concat "..." (s-right (- len 3) s))
                                      s)))
                     (s-pad-right len " " truncated))))
        (mapc (lambda (buffer)
                (when (with-current-buffer buffer (derived-mode-p 'compilation-mode))
                  (let ((name    (with-current-buffer buffer (buffer-name)))
                        (command (with-current-buffer buffer compilation-arguments))
                        (dir     (with-current-buffer buffer compilation-directory)))
                    (condition-case-unless-debug nil
                        (progn
                          (insert (s-truncate-left 20 name) "  ")
                          (insert (s-truncate-left 30 dir) "  ")
                          (insert (car command)))
                      (error t))
                    (newline))))
              (buffer-list))
        (sort-lines nil (point-min) (point-max))
        (goto-char (point-min))
        (insert (format "%-20s  " "NAME")
                (format "%-30s  " "DIRECTORY")
                "COMMAND")
        (newline)))
    (display-buffer "*compilation-buffers*"))

  (define-key ff/run-map "c" #'list-compilation-buffers))


;; *** Flycheck

(use-package flycheck
  :ensure   t
  :defer    t
  :diminish flycheck-mode

  :init
  (define-key ff/toggle-map (kbd "c") #'flycheck-mode)

  :config
  (defun ff/flycheck-next-error ()
    (interactive)
    (condition-case nil
        (flycheck-next-error)
      (user-error (flycheck-next-error nil 'reset))))

  (define-key flycheck-mode-map [remap flycheck-next-error] 'ff/flycheck-next-error)

  (defun flycheck-mode-line-status-verbose (&optional status)
    "Get a text describing STATUS for use in the mode line.

STATUS defaults to `flycheck-last-status-change' if omitted or
nil."
    (let ((text (pcase (or status flycheck-last-status-change)
                  (`not-checked "not checked")
                  (`no-checker "no checker")
                  (`running "running")
                  (`errored "error")
                  (`finished
                   (if flycheck-current-errors
                       (let ((error-counts (flycheck-count-errors
                                            flycheck-current-errors)))
                         (format "%s errors / %s warnings"
                                 (or (cdr (assq 'error error-counts)) 0)
                                 (or (cdr (assq 'warning error-counts)) 0)))
                     ""))
                  (`interrupted "interrupted")
                  (`suspicious "suspicious"))))
      (concat "FlyCheck: " text)))

  (setq flycheck-mode-line
        '(:eval
          (propertize (flycheck-mode-line-status-text)
                      'mouse-face 'mode-line-highlight

                      'help-echo (concat (flycheck-mode-line-status-verbose) "\n\n"
                                         "mouse-1: go to next error\n"
                                         "mouse-2: select checker\n"
                                         "mouse-3: go to previous error\n")

                      'local-map
                      (let ((map (make-sparse-keymap)))
                        (define-key map [mode-line mouse-1] 'ff/flycheck-next-error)
                        (define-key map [mode-line mouse-2] 'flycheck-select-checker)
                        (define-key map [mode-line mouse-3] 'flycheck-previous-error)
                        map))))

  (add-to-list 'mode-line-misc-info
               '(flycheck-mode ("" flycheck-mode-line " "))))

;; *** Executable scripts

(progn-safe "Make scripts executable"
  (add-hook 'after-save-hook
            'executable-make-buffer-file-executable-if-script-p))

;; *** TODO keywords

(progn-safe "Highlight TODO-like keywords"
  (defun ff/setup-todo-keywords ()
    "Highlight keywords like FIXME or TODO."
    (font-lock-add-keywords
     nil '(("\\<\\(FIXME\\|TODO\\|FIX\\|HACK\\|REFACTOR\\|NOCOMMIT\\)\\>"
            1 font-lock-warning-face t))))
  (add-hook 'prog-mode-hook 'ff/setup-todo-keywords))

;; *** Manage whitespace

(add-hook 'prog-mode-hook 'auto-dtw-mode)

;; *** Outline

(use-package org
  :defer t
  :diminish (orgstruct-mode . " 🖹")

  :init
  (add-hook 'prog-mode-hook #'turn-on-orgstruct)

  :config
  ;; Highlight outline
  (defun ff/orgstruct-setup ()
    (setq orgstruct-heading-prefix-regexp
          (cond ((derived-mode-p 'emacs-lisp-mode)
                 ";; ")
                (t
                 (concat comment-start "[[:space:]]*"))))
    (dotimes (i 8)
      (font-lock-add-keywords
       nil
       `((,(format "^%s\\(\\*\\{%d\\} .*\\)"
                   orgstruct-heading-prefix-regexp
                   (1+ i))
          1 ',(intern (format "outline-%d" (1+ i))) t)))))
  (add-hook 'orgstruct-mode-hook #'ff/orgstruct-setup)

  ;; Globally cycle visibility
  (defmacro define-orgstruct-wrapper (binding name command)
    `(progn
       (defun ,name ()
         (interactive)
         ;; This part is copied from `orgstruct-make-binding'
         (org-run-like-in-org-mode
          (lambda ()
            (interactive)
            (let* ((org-heading-regexp
                    (concat "^"
                            orgstruct-heading-prefix-regexp
                            "\\(\\*+\\)\\(?: +\\(.*?\\)\\)?[		]*$"))
                   (org-outline-regexp
                    (concat orgstruct-heading-prefix-regexp "\\*+ "))
                   (org-outline-regexp-bol
                    (concat "^" org-outline-regexp))
                   (outline-regexp org-outline-regexp)
                   (outline-heading-end-regexp "\n")
                   (outline-level 'org-outline-level)
                   (outline-heading-alist))
              (call-interactively ,command)))))
       (define-key orgstruct-mode-map ,binding (function ,name))))

  (define-orgstruct-wrapper (kbd "S-<iso-lefttab>") ff/orgstruct-global-cycle #'org-global-cycle)
  (define-orgstruct-wrapper (kbd "M-<next>")        ff/orgstruct-next-heading #'outline-next-heading)
  (define-orgstruct-wrapper (kbd "M-<prior>")       ff/orgstruct-next-heading #'outline-previous-heading))

;; *** Hide-show mode

(use-package hideshow
  :defer t
  :diminish (hs-minor-mode . " ℏ")

  :init
  (defun ff/enable-hideshow ()
    "Turn on Hide-Show mode"
    (hs-minor-mode 1))

  (add-hook 'prog-mode-hook 'ff/enable-hideshow)

  :config
  (defun ff/hs-show-block-nonrecursive ()
    "Show current block non-recursively (i.e. sub-blocks remain hidden)"
    (interactive)
    (hs-show-block)
    (hs-hide-level 0))

  (defun ff/hs-show (&optional arg)
    "Show block at point or if ARG is present, all blocks."
    (interactive "P")
    (if arg
        (hs-show-all)
      (hs-show-block)))

  (define-key hs-minor-mode-map (kbd "M-<right>") 'ff/hs-show-block-nonrecursive)
  (define-key hs-minor-mode-map (kbd "M-<left>")  'hs-hide-block)
  (define-key hs-minor-mode-map (kbd "M-<up>")    'hs-hide-all)
  (define-key hs-minor-mode-map (kbd "M-<down>")  'ff/hs-show))

;; *** Aggressive indentation

(use-package aggressive-indent
  :ensure   t
  :defer    t
  :diminish (aggressive-indent-mode . " ⭾"))

;; *** Debugging snippets

(progn-safe "Debugging snippets"
  (defvar ff/insert-debug-alist nil)
  (defun ff/insert-debug ()
    (interactive)
    (let ((cell (assq major-mode ff/insert-debug-alist)))
      (when cell
        (funcall (cdr cell)))))
  (custom-set-key (kbd "C-c d") #'ff/insert-debug))


;; ** LISP

(add-hook 'emacs-lisp-mode-hook #'enable-paredit-mode)
(add-hook 'emacs-lisp-mode-hook #'aggressive-indent-mode)

;; *** Imenu for top-level forms

;; from Jordon Biondo (https://gist.github.com/jordonbiondo/6385874a70420b05de18)
;; via  Jon Snader    (http://irreal.org/blog/?p=3979)
(use-package imenu
  :config
  (defun ff/imenu-top-level ()
    (add-to-list 'imenu-generic-expression
                 '("Used Packages"
                   "\\(^\\s-*(use-package +\\)\\(\\_<.+\\_>\\)" 2))
    (add-to-list 'imenu-generic-expression
                 '("Safe blocks"
                   "\\(^\\s-*(progn-safe +\\)\\(\".+\"\\)" 2))
    (add-to-list 'imenu-generic-expression
                 '("Safe blocks"
                   "\\(^\\s-*(with-timer-safe +\\)\\(\".+\"\\)" 2)))
  (add-hook 'emacs-lisp-mode-hook #'ff/imenu-top-level))

;; *** Documentation

(use-package eldoc
  :defer t
  :diminish eldoc-mode

  :init
  (add-hook 'emacs-lisp-mode-hook #'eldoc-mode))

(use-package helm-elisp
  :defer   t
  :defines helm-def-source--emacs-functions

  :init
  (custom-set-key (kbd "C-h a") 'helm-apropos)

  (custom-set-key
   (kbd "C-h f")
   (defun ff/helm-describe-function ()
     ""
     (interactive)
     (let ((helm-apropos-function-list
            '(helm-def-source--emacs-commands
              helm-def-source--emacs-functions)))
       (call-interactively #'helm-apropos))))

  (custom-set-key
   (kbd "C-h v")
   (defun ff/helm-describe-variable ()
     ""
     (interactive)
     (let ((helm-apropos-function-list
            '(helm-def-source--emacs-variables)))
       (call-interactively #'helm-apropos)))))

;; *** Inline evaluation

(progn-safe "Inline evaluation"
  (defun ff/eval-and-replace ()
    "Evaluate the sexp at point and replace it with its value."
    (interactive)
    (let ((value (eval-last-sexp nil)))
      (kill-sexp -1)
      (insert (format "%S" value))))

  (custom-set-key
   (kbd "C-x C-e")
   (defun ff/eval-last-sexp (&optional argp)
     "Evaluate sexp before point.
With a prefix argument, replace the sexp by its evaluation."
     (interactive "P")
     (if argp
         (call-interactively 'ff/eval-and-replace)
       (call-interactively 'eval-last-sexp)))))

;; *** Auto-compile

(use-package auto-compile
  :ensure t
  :commands turn-on-auto-compile-mode
  :init
  (add-hook 'emacs-lisp-mode-hook
            #'turn-on-auto-compile-mode))

;; *** Macrostep

(use-package macrostep
  :ensure t
  :defer t)

;; ** C/C++

;; *** Programming style

(use-package cc-mode
  :defer  t
  :config
  (c-add-style "my-c++-style"
               '("gnu"
                 (c-offsets-alist . ((innamespace . [0])))))
  (push '(c++-mode . "my-c++-style") c-default-style))

;; *** Snippets

(progn-safe "Yasnippet for C++"
  (add-hook 'c-mode-common-hook 'ff/enable-yasnippet))

(progn-safe "Debugging templates in C++"
  (push
   `(c++-mode
     . ,(lambda ()
          (let ((var
                 (if (use-region-p)
                     (buffer-substring-no-properties (point) (mark))
                   (substring-no-properties (thing-at-point 'symbol)))))
            (save-excursion
              (back-to-indentation)
              (forward-char 1)
              (c-beginning-of-statement 1)
              (open-line 1)
              (insert (format "std::cerr << \"%s = \" << %s << std::endl;" var var)))
            (c-indent-line))))
   ff/insert-debug-alist))

;; *** Switch between header and implementation files

(use-package cc-mode
  :defer t
  :config
  (define-key c-mode-map   (kbd "C-c o") 'ff-find-other-file)
  (define-key c++-mode-map (kbd "C-c o") 'ff-find-other-file))

;; *** Index sources with GNU/global

(use-package ggtags
  :ensure t
  :defer  t

  :init
  (defun ff/enable-gtags ()
    "Turn `ggtags-mode' on if a global tags file has been generated.

This function asynchronously runs 'global -u' to update global
tags. When the command successfully returns, `ggtags-mode' is
turned on."
    (let ((process (start-process "global -u"
                                  "*global output*"
                                  "global" "-u"))
          (buffer  (current-buffer)))
      (set-process-sentinel
       process
       `(lambda (process event)
          (when (and (eq (process-status process) 'exit)
                     (eq (process-exit-status process) 0))
            (with-current-buffer ,buffer
              (message "Activating gtags-mode")
              (ggtags-mode 1))))))))

(use-package cc-mode
  :defer t
  :config
  (add-hook 'c-mode-common-hook 'ff/enable-gtags))

;; ** Python

(use-package info
  :config
  ;; Python documentation as info files
  (use-package pydoc-info :ensure t)
  (add-to-list 'Info-additional-directory-list
               (ff/emacsd "share/info")))


;; ** Fortran

(use-package fortran
  :defer t
  :config
  (use-package fortran-index-args
    :load-path (lambda () (ff/emacsd "packages/fortran-index-args"))
    :config (define-key fortran-mode-map (kbd "C-c i") 'fia/toggle)))

;; ** Octave / Matlab

(use-package octave
  :mode        ("\\.m\\'" . octave-mode)
  :interpreter ("octave"  . octave-mode))

;; ** Maxima

(use-package maxima
  :mode        ("\\.mac\\'" . maxima-mode)
  :interpreter ("maxima"    . maxima-mode)
  :config
  (require 'imaxima))

;; ** Gnuplot

(use-package gnuplot
  :ensure t
  :mode        ("\\.gp\\'" . gnuplot-mode)
  :interpreter ("gnuplot" . gnuplot-mode)
  :config
  ;; don't display the gnuplot window
  (setq gnuplot-display-process nil))

;; * Postamble

(progn-safe "End of startup"
  (message "Emacs finished loading (%.3fs)."
           (float-time (time-subtract (current-time) ff/emacs-start-time))))

(provide 'init)
;;; init.el ends here
