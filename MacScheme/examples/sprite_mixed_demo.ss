(gfx-screen 720 480 1)
(gfx-reset)

(define (midpoint n)
  (quotient n 2))

(define (make-ring-sprite! def-id size fill outline)
  (let ((center (midpoint size))
        (radius (- (midpoint size) 2)))
    (gfx-sprite-def def-id size size)
    (with-sprite-canvas def-id
      (gfx-cls 0)
      (gfx-circle center center radius fill)
      (gfx-circle center center (- radius 3) 0)
      (gfx-circle-outline center center (+ radius 1) outline))))

(define (make-starburst-sprite! def-id w h fill outline accent)
  (let ((cx (midpoint w))
        (cy (midpoint h)))
    (gfx-sprite-def def-id w h)
    (with-sprite-canvas def-id
      (gfx-cls 0)
      (gfx-triangle cx 1 1 (- h 3) (- w 2) (- h 3) fill)
      (gfx-line cx 0 cx (- h 1) accent)
      (gfx-line 1 cy (- w 2) cy accent)
      (gfx-line 2 2 (- w 3) (- h 3) accent)
      (gfx-line 2 (- h 3) (- w 3) 2 accent)
      (gfx-triangle-outline cx 0 0 (- h 1) (- w 1) (- h 1) outline))))

(sprite-from-rows! 0
  '("....22...."
    "...2332..."
    "..233332.."
    ".23333332."
    ".23322332."
    ".23333332."
    "..233332.."
    "...2332..."
    "....22...."))
(gfx-sprite-palette 0 2 255 220 80)
(gfx-sprite-palette 0 3 255 120 60)

(sprite-from-rows! 1
  '("....66...."
    "...6666..."
    "..665566.."
    ".66555566."
    "6655555566"
    ".66555566."
    "..665566.."
    "...6666..."
    "....66...."))
(gfx-sprite-palette 1 5 120 255 180)
(gfx-sprite-palette 1 6 40 180 255)

(make-ring-sprite! 2 22 4 2)
(gfx-sprite-palette 2 2 255 250 250)
(gfx-sprite-palette 2 4 255 120 220)

(make-starburst-sprite! 3 28 24 7 2 3)
(gfx-sprite-palette 3 2 255 255 255)
(gfx-sprite-palette 3 3 255 210 90)
(gfx-sprite-palette 3 7 140 180 255)

(gfx-sprite 0 0 84 96)
(gfx-sprite 1 1 160 144)
(gfx-sprite 2 2 320 100)
(gfx-sprite 3 3 460 170)
(gfx-sprite 4 0 580 120)
(gfx-sprite 5 2 620 250)

(gfx-sprite-scale 0 2.0 2.0)
(gfx-sprite-scale 1 1.6 1.6)
(gfx-sprite-scale 2 1.4 1.4)
(gfx-sprite-scale 3 1.3 1.3)
(gfx-sprite-scale 4 2.5 2.5)
(gfx-sprite-scale 5 1.8 1.8)

(define (bounce-axis pos delta low high radius)
  (let ((next (+ pos delta)))
    (cond
      ((< (- next radius) low) (values (+ low radius) (- delta)))
      ((> (+ next radius) high) (values (- high radius) (- delta)))
      (else (values next delta)))))

(define (update-actor frame actor)
  (let ((inst (vector-ref actor 0))
        (x (vector-ref actor 1))
        (y (vector-ref actor 2))
        (dx (vector-ref actor 3))
        (dy (vector-ref actor 4))
        (spin (vector-ref actor 5))
        (rx (vector-ref actor 6))
        (ry (vector-ref actor 7))
        (wobble (vector-ref actor 8)))
    (gfx-sprite-pos inst x (+ y (* wobble (sin (* frame 0.05)))))
    (gfx-sprite-rot inst (* frame spin))
    (call-with-values
      (lambda () (bounce-axis x dx 18 702 rx))
      (lambda (nx ndx)
        (call-with-values
          (lambda () (bounce-axis y dy 54 456 ry))
          (lambda (ny ndy)
            (vector inst nx ny ndx ndy spin rx ry wobble)))))))

(let loop ((frame 0)
           (actors (list (vector 0 84.0 96.0 1.8 1.2 2.5 14 14 6.0)
                         (vector 1 160.0 144.0 2.2 -1.0 -2.0 12 12 5.0)
                         (vector 2 320.0 100.0 -1.6 1.8 1.6 16 16 7.0)
                         (vector 3 460.0 170.0 1.4 1.5 -1.2 18 15 4.0)
                         (vector 4 580.0 120.0 -2.0 1.1 1.9 18 18 8.0)
                         (vector 5 620.0 250.0 -1.3 -1.7 -2.8 16 16 6.5))))
  (gfx-clear 8 14 30)
  (gfx-rect 0 0 720 44 17)
  (gfx-rect 0 404 720 76 26)
  (gfx-text 14 12 "MacScheme Mixed Sprite Demo" 21)
  (gfx-text-small 14 420 "row sprites on the left and right, primitive sprites in the middle" 30)
  (gfx-text-small 14 440 "mixing sprite-from-rows! with with-sprite-canvas drawing" 29)

  (let ((next-actors (map (lambda (actor) (update-actor frame actor)) actors)))
    (gfx-sprite-sync)
    (gfx-flip)
    (gfx-wait 1)
    (if (< frame 900)
        (loop (+ frame 1) next-actors)
        'done)))
