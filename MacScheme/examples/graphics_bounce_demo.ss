(gfx-screen 256 160 3)
(gfx-reset)

(define (clamp-bounce pos delta low high radius)
  (let ((next (+ pos delta)))
    (cond
      ((< (- next radius) low) (values (+ low radius) (- delta)))
      ((> (+ next radius) high) (values (- high radius) (- delta)))
      (else (values next delta)))))

(let loop ((frame 0)
           (x 40.0)
           (y 36.0)
           (dx 2.4)
           (dy 1.7))
  (gfx-clear 6 10 22)
  (gfx-rect 0 118 256 42 10)
  (gfx-rect 0 0 256 18 4)
  (gfx-text 8 4 "MacScheme Bounce Demo" 21)
  (gfx-text-small 8 138 "watch the framebuffer redraw" 30)

  (do ((i 0 (+ i 1)))
      ((= i 8))
    (let ((bar-x (+ 12 (* i 30)))
          (bar-h (+ 8 (* 4 (modulo (+ frame i) 6)))))
      (gfx-rect bar-x (- 118 bar-h) 18 bar-h (+ 18 (modulo i 6)))))

  (gfx-circle x y 14 24)
  (gfx-circle-outline x y 18 17)
  (gfx-ellipse (- 256 x) (+ 20 (* 0.35 y)) 10 6 20)

  (gfx-flip)
  (gfx-wait 1)

  (if (< frame 480)
      (call-with-values
        (lambda () (clamp-bounce x dx 8 248 18))
        (lambda (nx ndx)
          (call-with-values
            (lambda () (clamp-bounce y dy 24 114 18))
            (lambda (ny ndy)
              (loop (+ frame 1) nx ny ndx ndy)))))
      'done))
