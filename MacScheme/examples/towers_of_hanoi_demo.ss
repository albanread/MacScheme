(layout-set! 'focus-graphics)
(gfx-screen 640 360 2)
(gfx-reset)

; Animated Towers of Hanoi Demo
; -----------------------------
; Watches the classic recursive solution play out with smooth disk motion.
; Space or Return restarts the puzzle. Escape quits.

(define width 640)
(define height 360)
(define disk-count 6)
(define disk-height 18)
(define base-y 308)
(define carry-y 92)
(define move-up-frames 8)
(define move-across-frames 14)
(define move-down-frames 8)
(define move-rest-frames 5)
(define move-frames (+ move-up-frames move-across-frames move-down-frames move-rest-frames))
(define solved-hold-frames 120)

(define peg-x0 140)
(define peg-x1 320)
(define peg-x2 500)

(define (peg-x index)
  (cond
    ((= index 0) peg-x0)
    ((= index 1) peg-x1)
    (else peg-x2)))

(define (disk-width size)
  (+ 42 (* size 24)))

(define (disk-fill-colour size)
  (+ 18 (modulo (* size 2) 10)))

(define (disk-outline-colour size)
  (+ 28 (modulo (* size 3) 4)))

(define (disk-highlight-colour size)
  (+ 24 (modulo size 5)))

(define (lerp a b t)
  (+ a (* (- b a) t)))

;; Disks are ordered top-to-bottom (smallest at front) so a peg acts as a proper stack.
(define (make-initial-disk-list count)
  (let loop ((i count) (lst '()))
    (if (= i 0) lst (loop (- i 1) (cons i lst)))))

(define (replace-peg pegs index new-peg)
  (list (if (= index 0) new-peg (list-ref pegs 0))
        (if (= index 1) new-peg (list-ref pegs 1))
        (if (= index 2) new-peg (list-ref pegs 2))))

(define (initial-pegs)
  (list (make-initial-disk-list disk-count) '() '()))

(define (hanoi-moves n from to spare)
  (if (= n 0)
    '()
    (append
      (hanoi-moves (- n 1) from spare to)
      (list (list from to))
      (hanoi-moves (- n 1) spare to from))))

(define solution-moves (hanoi-moves disk-count 0 2 1))
(define total-moves (length solution-moves))

(define (disk-top-y stack-height)
  (- base-y (* disk-height stack-height)))

(define (make-moving disk from to progress source-height target-height)
  (list disk from to progress source-height target-height))

(define (moving-disk moving)
  (list-ref moving 0))

(define (moving-from moving)
  (list-ref moving 1))

(define (moving-to moving)
  (list-ref moving 2))

(define (moving-progress moving)
  (list-ref moving 3))

(define (moving-source-height moving)
  (list-ref moving 4))

(define (moving-target-height moving)
  (list-ref moving 5))

(define (moving-start-y moving)
  (disk-top-y (moving-source-height moving)))

(define (moving-end-y moving)
  (disk-top-y (moving-target-height moving)))

(define (moving-x moving)
  (let* ((progress (moving-progress moving))
          (from-x (peg-x (moving-from moving)))
          (to-x (peg-x (moving-to moving))))
    (cond
      ((< progress move-up-frames) from-x)
      ((< progress (+ move-up-frames move-across-frames))
        (lerp from-x
          to-x
          (/ (- progress move-up-frames) move-across-frames)))
      (else to-x))))

(define (moving-y moving)
  (let* ((progress (moving-progress moving))
          (start-y (moving-start-y moving))
          (end-y (moving-end-y moving))
          (drop-start (+ move-up-frames move-across-frames)))
    (cond
      ((< progress move-up-frames)
        (lerp start-y carry-y (/ progress move-up-frames)))
      ((< progress drop-start) carry-y)
      ((< progress (+ drop-start move-down-frames))
        (lerp carry-y
          end-y
          (/ (- progress drop-start) move-down-frames)))
      (else end-y))))

(define (draw-background frame)
  (gfx-rect 0 0 width base-y 2)
  (gfx-rect 0 base-y width (- height base-y) 3))

(define (draw-peg index glow)
  (let* ((x (peg-x index))
          (label-y 320)
          (shine (if glow 24 20)))
    (gfx-rect (- x 64) 312 128 10 14)
    (gfx-rect-outline (- x 68) 308 136 18 29)
    (gfx-rect (- x 6) 128 12 184 shine)
    (gfx-rect-outline (- x 8) 124 16 188 31)
    (gfx-text-small (- x 18) label-y
      (string-append "peg " (number->string (+ index 1)))
      30)))

(define (draw-disk-center x y size active?)
  (let* ((disk-w (disk-width size))
          (left (- x (quotient disk-w 2)))
          (fill (disk-fill-colour size))
          (outline (disk-outline-colour size))
          (highlight (if active? 31 (disk-highlight-colour size))))
    (gfx-rect left y disk-w disk-height fill)
    (gfx-rect-outline left y disk-w disk-height outline)
    (gfx-line (+ left 4) (+ y 4) (- (+ left disk-w) 5) (+ y 4) highlight)
    (gfx-line (+ left 8) (+ y (- disk-height 5)) (- (+ left disk-w) 9) (+ y (- disk-height 5)) 14)))

(define (draw-peg-disks peg x)
  (let loop ((disks (reverse peg)) (level 0))
    (if (not (null? disks))
      (begin
        (draw-disk-center x
          (- base-y (* disk-height (+ level 1)))
          (car disks)
          #f)
        (loop (cdr disks) (+ level 1)))
      0)))

(define (draw-all-pegs pegs)
  (draw-peg 0 #f)
  (draw-peg 1 #f)
  (draw-peg 2 #f)
  (draw-peg-disks (list-ref pegs 0) (peg-x 0))
  (draw-peg-disks (list-ref pegs 1) (peg-x 1))
  (draw-peg-disks (list-ref pegs 2) (peg-x 2)))

(define (draw-moving-disk moving)
  (if moving
    (draw-disk-center (moving-x moving)
      (moving-y moving)
      (moving-disk moving)
      #t)
    0))

(define (draw-hud frame remaining moving solved-hold)
  (let* ((started (- total-moves (length remaining)))
          (shown-moves (if moving started (max 0 started)))
          (solved? (and (null? remaining) (not moving)))
          (pulse (+ 20 (modulo frame 6))))
    (gfx-rect 0 0 width 42 12)
    (gfx-text 16 10 "Animated Towers of Hanoi" 31)
    (gfx-text-small 18 30 "Recursive solution with smooth disk motion" 29)
    (gfx-text-small 18 50
      (string-append "moves " (number->string shown-moves) " / " (number->string total-moves))
      30)
    (gfx-text-small 18 68
      (string-append "disks " (number->string disk-count) "   space: restart   esc: quit")
      28)
    (if solved?
      (begin
        (gfx-text-small 360 30 "Solved! resetting soon..." pulse)
        (gfx-text-small 360 50
          (string-append "hold " (number->string solved-hold) " / " (number->string solved-hold-frames))
          27))
      (gfx-text-small 388 30 "watch the recursive pattern unfold" 26))))

(define (start-next-move pegs remaining)
  (let* ((move (car remaining))
          (from (car move))
          (to (cadr move))
          (from-peg (list-ref pegs from))
          (to-peg (list-ref pegs to))
          (disk (car from-peg)) ; Peg represents a stack (top is at the head)
          (source-height (length from-peg))
          (target-height (+ 1 (length to-peg)))
          (next-pegs (replace-peg pegs from (cdr from-peg)))) ; pop
    (values next-pegs
            (cdr remaining)
            (make-moving disk from to 0 source-height target-height))))

(define (advance-moving pegs remaining moving)
  (let ((next-progress (+ (moving-progress moving) 1)))
    (if (>= next-progress move-frames)
      (let* ((target (moving-to moving))
              (target-peg (list-ref pegs target))
              (next-pegs (replace-peg pegs target (cons (moving-disk moving) target-peg)))) ; push
        (values next-pegs remaining #f))
      (values pegs
              remaining
              (make-moving (moving-disk moving)
                           (moving-from moving)
                           (moving-to moving)
                           next-progress
                           (moving-source-height moving)
                           (moving-target-height moving))))))

; Setup palettes (sky and land)
(gfx-pal-gradient 0 2 0 base-y 40 100 240 160 210 255)
(gfx-pal-gradient 1 3 base-y height 120 180 80 40 100 40)

(let loop ((frame 0)
           (pegs (initial-pegs))
           (remaining solution-moves)
           (moving #f)
           (solved-hold 0))
  (let ((pressed-key (gfx-read-key)))
    (if (or (eq? pressed-key 'escape) (eq? pressed-key 'esc) (not (gfx-active?)))
      'done
      (begin
        (draw-background frame)
        (draw-all-pegs pegs)
        (draw-moving-disk moving)
        (draw-hud frame remaining moving solved-hold)
        (gfx-flip)
        (gfx-wait 1)
        (gfx-vsync)
        (if (or (eq? pressed-key 'space) (eq? pressed-key 'return))
          (loop 0 (initial-pegs) solution-moves #f 0)
          (cond
            (moving
              (call-with-values
                (lambda () (advance-moving pegs remaining moving))
                (lambda (next-pegs next-rem next-mov)
                  (loop (+ frame 1) next-pegs next-rem next-mov solved-hold))))
            ((pair? remaining)
              (call-with-values
                (lambda () (start-next-move pegs remaining))
                (lambda (next-pegs next-rem next-mov)
                  (loop (+ frame 1) next-pegs next-rem next-mov 0))))
            ((>= solved-hold solved-hold-frames)
              (loop 0 (initial-pegs) solution-moves #f 0))
            (else
              (loop (+ frame 1) pegs remaining #f (+ solved-hold 1)))))))))
