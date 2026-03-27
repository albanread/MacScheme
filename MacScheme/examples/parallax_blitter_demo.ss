(layout-set! 'focus-graphics)
(gfx-screen 640 360 2)
(gfx-reset)

; Parallax Blitter Demo
; ---------------------
; Buffers 3 and 4 hold two transparent tile layers.
; Buffers 5 and 6 hold blitter object art for the ship and alien orbs.
; Each frame we compose:
;   sky -> far layer -> near layer -> ship/orbs -> HUD -> flip.
;
; Controls:
; - Up / Down move the ship
; - Left / Right nudge the ship horizontally
; - Space engages a speed boost
; - Escape quits

(define width 640)
(define height 360)
(define buffer-width (gfx-buffer-width))
(define buffer-height (gfx-buffer-height))

(define far-buffer 3)
(define near-buffer 4)
(define ship-buffer 5)
(define orb-buffer 6)

(define ship-width 48)
(define ship-height 28)
(define orb-size 24)
(define orb-radius 12.0)

(define (toggle-back-buffer buffer)
  (if (= buffer 0) 1 0))

(define (clamp n lo hi)
  (max lo (min hi n)))

(define (wrap-int n limit)
  (modulo (+ (modulo n limit) limit) limit))

(define (pixel n)
  (inexact->exact (round n)))

(define (draw-star-band frame)
  (gfx-clear 4 6 16)
  (gfx-rect 0 0 width 120 17)
  (gfx-rect 0 120 width 120 18)
  (gfx-rect 0 240 width 120 19)
  (do ((i 0 (+ i 1)))
      ((= i 36))
    (let* ((x (wrap-int (+ (* i 71) frame (* i 3)) width))
           (y (wrap-int (+ 18 (* i 19) (quotient frame (+ 1 (modulo i 3)))) 210))
           (colour (if (= (modulo i 4) 0) 31 30)))
      (gfx-pset x (+ 12 y) colour)
      (if (= (modulo i 5) 0)
          (gfx-pset (wrap-int (+ x 1) width) (+ 12 y) 20)
          0))))

(define (draw-far-tile x y colour-a colour-b)
  (gfx-rect x y 32 18 colour-a)
  (gfx-rect-outline x y 32 18 colour-b)
  (gfx-line (+ x 4) (+ y 9) (+ x 28) (+ y 9) colour-b)
  (gfx-rect (+ x 6) (+ y 4) 6 4 20)
  (gfx-rect (+ x 20) (+ y 4) 6 4 20))

(define (draw-near-tile x y colour-a colour-b)
  (gfx-rect x y 32 24 colour-a)
  (gfx-rect-outline x y 32 24 colour-b)
  (gfx-rect (+ x 6) (+ y 5) 20 6 31)
  (gfx-line (+ x 6) (+ y 15) (+ x 26) (+ y 15) colour-b)
  (gfx-rect (+ x 10) (+ y 17) 12 4 24))

(define (draw-far-layer!)
  (gfx-set-target far-buffer)
  (gfx-cls 0)
  (do ((column 0 (+ column 1)))
      ((> (* column 96) (+ buffer-width 96)))
    (let* ((base-x (* column 96))
           (gap-kind (modulo column 5))
           (height-step (modulo column 4)))
      (if (or (= gap-kind 1) (= gap-kind 4))
          0
          (begin
            (draw-far-tile base-x (+ 148 (* height-step 8)) 17 20)
            (draw-far-tile (+ base-x 32) (+ 166 (* height-step 6)) 18 21)
            (if (even? column)
                (draw-far-tile (+ base-x 64) (+ 184 (* height-step 4)) 17 20)
                0)
            (gfx-circle (+ base-x 16) (+ 134 (* height-step 5)) 6 24)
            (gfx-circle-outline (+ base-x 16) (+ 134 (* height-step 5)) 10 30)))))
  (gfx-set-target 1))

(define (draw-near-layer!)
  (gfx-set-target near-buffer)
  (gfx-cls 0)
  (do ((column 0 (+ column 1)))
      ((> (* column 80) (+ buffer-width 80)))
    (let* ((base-x (* column 80))
           (gap-kind (modulo column 4))
           (rise (modulo column 3)))
      (if (= gap-kind 2)
          0
          (begin
            (draw-near-tile base-x (+ 222 (* rise 10)) 21 29)
            (draw-near-tile (+ base-x 24) (+ 246 (* rise 6)) 22 30)
            (draw-near-tile (+ base-x 48) (+ 270 (* rise 4)) 23 31)
            (gfx-rect (+ base-x 10) (+ 296 (* rise 2)) 44 28 24)
            (gfx-rect-outline (+ base-x 10) (+ 296 (* rise 2)) 44 28 31)))))
  (gfx-set-target 1))

(define (draw-object-buffers!)
  (gfx-set-target ship-buffer)
  (gfx-cls 0)
  (gfx-triangle 44 14 8 4 8 24 31)
  (gfx-triangle 36 14 12 7 12 21 29)
  (gfx-line 8 4 4 10 24)
  (gfx-line 8 24 4 18 24)
  (gfx-line 8 9 2 9 20)
  (gfx-line 8 19 2 19 20)
  (gfx-circle 28 14 5 20)
  (gfx-circle-outline 28 14 9 30)
  (gfx-rect 16 11 8 6 18)

  (gfx-set-target orb-buffer)
  (gfx-cls 0)
  (gfx-circle 12 12 10 24)
  (gfx-circle 12 12 6 20)
  (gfx-circle-outline 12 12 10 31)
  (gfx-line 2 12 22 12 30)
  (gfx-line 12 2 12 22 30)
  (gfx-line 5 5 19 19 29)
  (gfx-line 19 5 5 19 29)

  (gfx-set-target 1))

(define (blit-wrapped-layer dst src scroll-x y)
  (let* ((source-x (wrap-int scroll-x buffer-width))
         (first-width (min width (- buffer-width source-x))))
    (gfx-blit dst 0 y src source-x 0 first-width height)
    (if (< first-width width)
        (gfx-blit dst first-width y src 0 0 (- width first-width) height)
        0)))

(define (make-orb x y speed phase)
  (vector x y speed phase))

(define (orb-x orb) (vector-ref orb 0))
(define (orb-y orb) (vector-ref orb 1))
(define (orb-speed orb) (vector-ref orb 2))
(define (orb-phase orb) (vector-ref orb 3))

(define (orb-draw-y orb frame)
  (+ (orb-y orb)
     (* 10.0 (sin (+ (orb-phase orb) (* frame 0.05))))))

(define initial-orbs
  (list (make-orb 740.0 78.0 3.4 0.0)
        (make-orb 920.0 162.0 4.1 0.9)
        (make-orb 1110.0 238.0 3.8 1.7)
        (make-orb 1310.0 116.0 4.6 2.5)
        (make-orb 1500.0 286.0 4.0 3.2)))

(define (respawn-orb orb min-x frame index)
  (let* ((lane (modulo (+ frame (* index 17)) 5))
         (next-y (+ 66 (* lane 48)))
         (next-speed (+ 3.0 (/ (exact->inexact (modulo (+ frame (* index 11)) 18)) 10.0)))
         (next-phase (/ (exact->inexact (modulo (+ frame (* index 37)) 628)) 100.0)))
    (make-orb (+ min-x 180.0 (* index 54.0))
              (exact->inexact next-y)
              next-speed
              next-phase)))

(define (update-orbs orbs scroll-speed frame)
  (let loop ((remaining orbs) (index 0) (rebuilt '()) (spawn-anchor 760.0))
    (if (null? remaining)
        (reverse rebuilt)
        (let* ((orb (car remaining))
               (next-x (- (orb-x orb) (+ scroll-speed (orb-speed orb))))
               (updated (make-orb next-x (orb-y orb) (orb-speed orb) (+ (orb-phase orb) 0.03)))
               (final-orb (if (< next-x -40.0)
                              (respawn-orb updated spawn-anchor frame index)
                              updated))
               (next-anchor (if (< next-x -40.0)
                                (+ spawn-anchor 180.0)
                                spawn-anchor)))
          (loop (cdr remaining)
                (+ index 1)
                (cons final-orb rebuilt)
                next-anchor)))))

(define (draw-orbs dst orbs frame)
  (if (null? orbs)
      0
      (begin
        (let* ((orb (car orbs))
               (pulse (+ 2 (modulo frame 3)))
               (draw-x (pixel (orb-x orb)))
               (draw-y (pixel (orb-draw-y orb frame))))
          (gfx-blit dst draw-x draw-y orb-buffer 0 0 orb-size orb-size)
          (gfx-circle-outline (+ draw-x 12) (+ draw-y 12) (+ 11 pulse) 20))
        (draw-orbs dst (cdr orbs) frame))))

(define (orb-collides? ship-x ship-y orb frame)
  (let* ((dx (- (+ ship-x 24.0) (+ (orb-x orb) 12.0)))
         (dy (- (+ ship-y 14.0) (+ (orb-draw-y orb frame) 12.0)))
         (distance-squared (+ (* dx dx) (* dy dy)))
         (limit (+ 18.0 orb-radius)))
    (< distance-squared (* limit limit))))

(define (any-orb-collision? ship-x ship-y orbs frame)
  (if (null? orbs)
      #f
      (if (orb-collides? ship-x ship-y (car orbs) frame)
          #t
          (any-orb-collision? ship-x ship-y (cdr orbs) frame))))

(define (draw-ship dst ship-x ship-y flash-timer boost?)
  (if (or (= flash-timer 0) (< (modulo flash-timer 6) 3))
      (begin
        (gfx-blit dst (pixel ship-x) (pixel ship-y) ship-buffer 0 0 ship-width ship-height)
        (if boost?
            (begin
              (gfx-line (pixel ship-x) (+ (pixel ship-y) 10)
                        (- (pixel ship-x) 12) (+ (pixel ship-y) 8)
                        24)
              (gfx-line (pixel ship-x) (+ (pixel ship-y) 18)
                        (- (pixel ship-x) 12) (+ (pixel ship-y) 20)
                        20))
            0))
      0))

(define (draw-hud dst speed hits)
  (gfx-rect 0 0 width 30 21)
  (gfx-text 10 8 "Parallax Blitter Demo" 31)
  (gfx-text-small 238 10
                  (string-append "scroll " (number->string speed)
                                 "  hits " (number->string hits)
                                 "  up/down steer")
                  30))

(draw-far-layer!)
(draw-near-layer!)
(draw-object-buffers!)

(let loop ((frame 0)
           (back-buffer 1)
           (ship-x 96.0)
           (ship-y 176.0)
           (orbs initial-orbs)
           (far-scroll 0)
           (near-scroll 0)
           (flash-timer 0)
           (hit-count 0)
           (boosting? #f))
  (begin
    (gfx-set-target back-buffer)
    (draw-star-band frame)
    (blit-wrapped-layer back-buffer far-buffer far-scroll 0)
    (blit-wrapped-layer back-buffer near-buffer near-scroll 0)
    (draw-orbs back-buffer orbs frame)
    (draw-ship back-buffer ship-x ship-y flash-timer boosting?)
    (draw-hud back-buffer (if boosting? 6 4) hit-count)
    (gfx-flip)
    (gfx-vsync)
    (let* ((pressed-key (gfx-read-key))
           (left? (or (gfx-key-pressed? 'left) (gfx-key-pressed? 'a)))
           (right? (or (gfx-key-pressed? 'right) (gfx-key-pressed? 'd)))
           (up? (or (gfx-key-pressed? 'up) (gfx-key-pressed? 'w)))
           (down? (or (gfx-key-pressed? 'down) (gfx-key-pressed? 's)))
           (boost? (gfx-key-pressed? 'space))
           (ship-speed (if boost? 4.8 3.2))
           (scroll-speed (if boost? 6 4))
           (next-ship-x (clamp (+ ship-x (if left? (- ship-speed) 0.0)
                                        (if right? ship-speed 0.0))
                               48.0
                               200.0))
           (next-ship-y (clamp (+ ship-y (if up? (- ship-speed) 0.0)
                                        (if down? ship-speed 0.0))
                               46.0
                               304.0))
           (next-far-scroll (wrap-int (+ far-scroll 1 (if boost? 1 0)) buffer-width))
           (next-near-scroll (wrap-int (+ near-scroll scroll-speed) buffer-width))
           (next-orbs (update-orbs orbs scroll-speed frame))
           (collided? (and (= flash-timer 0)
                           (any-orb-collision? next-ship-x next-ship-y next-orbs frame)))
           (next-flash (if collided?
                           24
                           (max 0 (- flash-timer 1))))
           (next-hits (if collided? (+ hit-count 1) hit-count))
           (next-back-buffer (toggle-back-buffer back-buffer)))
      (if (or (eq? pressed-key 'escape)
              (eq? pressed-key 'esc)
              (not (gfx-active?)))
          'done
          (loop (+ frame 1)
                next-back-buffer
                next-ship-x
                next-ship-y
                next-orbs
                next-far-scroll
                next-near-scroll
                next-flash
                next-hits
                boost?)))))
