(gfx-screen 320 240 2)
(gfx-reset)

; Escape quits.

(define width 320)
(define height 240)

(define (done? key)
  (or (eq? key 'escape)
      (eq? key 'esc)
      (not (gfx-active?))))

(define (cleanup)
  (gfx-cycle #f)
  (gfx-pal-stop-all)
  'done)

(gfx-pal 17 26 18 18)
(gfx-pal 18 56 38 28)
(gfx-pal 24 255 108 16)
(gfx-pal 25 255 164 36)
(gfx-pal 26 255 224 96)
(gfx-pal 27 255 255 210)
(gfx-pal-cycle 0 24 27 2 1)
(gfx-pal-pulse 1 27 3 255 228 130 255 255 220)
(gfx-pal-strobe 2 18 10 14 80 48 30 120 72 40)
(gfx-cycle #t)

(define (draw-bubble x y radius colour frame speed)
  (gfx-circle (+ x (* 6 (sin (* frame speed))))
              (+ y (* 3 (cos (* frame (* speed 1.7)))))
              radius
              colour))

(define (draw-scene frame)
  (gfx-rect 0 0 width height 17)
  (gfx-triangle 0 0 88 110 166 0 18)
  (gfx-triangle 120 0 222 92 319 0 18)
  (gfx-rect 0 150 width 90 24)
  (gfx-rect 0 144 width 8 18)
  (draw-bubble 58 186 10 25 frame 0.05)
  (draw-bubble 126 204 14 26 frame 0.03)
  (draw-bubble 214 176 9 25 frame 0.06)
  (draw-bubble 272 198 12 27 frame 0.04)
  (gfx-line 0 149 (- width 1) 149 27)
  (gfx-text 12 12 "MacScheme Lava Palette Demo" 27)
  (gfx-text-small 12 30 "cycled hot colours and a pulsing highlight drive the pool" 26)
  (gfx-text-small 12 222 "Escape quits" 27))

(let loop ((frame 0))
  (let ((pressed-key (gfx-read-key)))
    (if (done? pressed-key)
        (cleanup)
        (begin
          (draw-scene frame)
          (gfx-flip)
          (gfx-wait 1)
          (loop (+ frame 1))))))