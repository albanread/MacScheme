(layout-set! 'focus-graphics)
(gfx-screen 640 360 2)
(gfx-reset)
(audio-init)
(sound-volume 0.6)

; Asteroids v2: keeps the original demo's lightweight functional style,
; but adds real wave progression and a few classic-inspired mechanics.
; Controls: left/right rotate, up thrusts, space fires, H hyperspace, escape quits.

(define width 640.0)
(define height 360.0)
(define ship-radius 12.0)
(define bullet-life-max 44)
(define base-asteroid-count 6)
(define max-bullets 4)
(define extra-life-step 1000)
(define large-threshold 26.0)
(define medium-threshold 16.0)
(define large-child-radius-scale 0.72)
(define medium-child-radius-scale 0.58)
(define invuln-max 90)
(define respawn-delay-max 45)
(define wave-clear-delay 40)
(define hyperspace-cooldown-max 75)
(define hyperspace-failure-percent 12)
(define saucer-radius 16.0)
(define saucer-score 200)
(define saucer-bullet-life 70)
(define initial-seed 42424242)
(define pi 3.14159)

(define (wrap value limit)
  (cond
    ((< value 0.0) (+ value limit))
    ((>= value limit) (- value limit))
    (else value)))

(define (distance-squared x1 y1 x2 y2)
  (+ (* (- x2 x1) (- x2 x1))
     (* (- y2 y1) (- y2 y1))))

(define (rand-next seed)
  (modulo (+ (* seed 1664525) 1013904223) 4294967296))

(define (rand-int seed limit)
  (let ((next (rand-next seed)))
    (cons next (if (<= limit 0) 0 (modulo next limit)))))

(define (rand-range seed low high)
  (let* ((span (max 1 (+ 1 (- high low))))
         (rv (rand-int seed span)))
    (cons (car rv) (+ low (cdr rv)))))

(define (list-length items)
  (if (null? items)
      0
      (+ 1 (list-length (cdr items)))))

(define (ship-point x y angle distance)
  (cons (+ x (* (cos angle) distance))
        (+ y (* (sin angle) distance))))

(define (wave-asteroid-count wave)
  (min 12 (+ base-asteroid-count (- wave 1))))

(define (wave-speed-scale wave)
  (min 2.2 (+ 1.0 (* 0.08 (exact->inexact (- wave 1))))))

(define (schedule-saucer-spawn seed wave)
  (let* ((low (max 110 (- 320 (* 12 (- wave 1)))))
         (high (+ low 170))
         (rv (rand-range seed low high)))
    (cons (car rv) (cdr rv))))

(define (make-bullet x y dx dy life)
  (vector x y dx dy life))

(define (bullet-x bullet) (vector-ref bullet 0))
(define (bullet-y bullet) (vector-ref bullet 1))
(define (bullet-dx bullet) (vector-ref bullet 2))
(define (bullet-dy bullet) (vector-ref bullet 3))
(define (bullet-life bullet) (vector-ref bullet 4))

(define (make-asteroid x y dx dy radius angle spin)
  (vector x y dx dy radius angle spin))

(define (asteroid-x asteroid) (vector-ref asteroid 0))
(define (asteroid-y asteroid) (vector-ref asteroid 1))
(define (asteroid-dx asteroid) (vector-ref asteroid 2))
(define (asteroid-dy asteroid) (vector-ref asteroid 3))
(define (asteroid-radius asteroid) (vector-ref asteroid 4))
(define (asteroid-angle asteroid) (vector-ref asteroid 5))
(define (asteroid-spin asteroid) (vector-ref asteroid 6))

(define (make-puff x y radius life)
  (vector x y radius life))

(define (puff-x puff) (vector-ref puff 0))
(define (puff-y puff) (vector-ref puff 1))
(define (puff-radius puff) (vector-ref puff 2))
(define (puff-life puff) (vector-ref puff 3))

(define (make-shard x1 y1 x2 y2 dx dy life colour)
  (vector x1 y1 x2 y2 dx dy life colour))

(define (shard-x1 shard) (vector-ref shard 0))
(define (shard-y1 shard) (vector-ref shard 1))
(define (shard-x2 shard) (vector-ref shard 2))
(define (shard-y2 shard) (vector-ref shard 3))
(define (shard-dx shard) (vector-ref shard 4))
(define (shard-dy shard) (vector-ref shard 5))
(define (shard-life shard) (vector-ref shard 6))
(define (shard-colour shard) (vector-ref shard 7))

(define (make-saucer x y dx fire-cooldown)
  (vector x y dx fire-cooldown))

(define (saucer-x saucer) (vector-ref saucer 0))
(define (saucer-y saucer) (vector-ref saucer 1))
(define (saucer-dx saucer) (vector-ref saucer 2))
(define (saucer-fire-cooldown saucer) (vector-ref saucer 3))

(define (make-resolution asteroids bullets score puffs shards)
  (vector asteroids bullets score puffs shards))

(define (resolution-asteroids resolution) (vector-ref resolution 0))
(define (resolution-bullets resolution) (vector-ref resolution 1))
(define (resolution-score resolution) (vector-ref resolution 2))
(define (resolution-puffs resolution) (vector-ref resolution 3))
(define (resolution-shards resolution) (vector-ref resolution 4))

(define (spawn-asteroid seed speed-scale)
  ; Asteroids spawn just off-screen and drift inward.
  (let* ((edge-rv (rand-int seed 4))
         (seed-1 (car edge-rv))
         (edge (cdr edge-rv))
         (x-rv (rand-range seed-1 0 639))
         (seed-2 (car x-rv))
         (random-x (exact->inexact (cdr x-rv)))
         (y-rv (rand-range seed-2 0 359))
         (seed-3 (car y-rv))
         (random-y (exact->inexact (cdr y-rv)))
         (dx-rv (rand-range seed-3 -22 22))
         (seed-4 (car dx-rv))
         (raw-dx (* (/ (exact->inexact (cdr dx-rv)) 10.0) speed-scale))
         (dy-rv (rand-range seed-4 -22 22))
         (seed-5 (car dy-rv))
         (raw-dy (* (/ (exact->inexact (cdr dy-rv)) 10.0) speed-scale))
         (radius-rv (rand-range seed-5 16 34))
         (seed-6 (car radius-rv))
         (radius (exact->inexact (cdr radius-rv)))
         (angle-rv (rand-range seed-6 0 628))
         (seed-7 (car angle-rv))
         (angle (/ (exact->inexact (cdr angle-rv)) 100.0))
         (spin-rv (rand-range seed-7 -9 9))
         (seed-8 (car spin-rv))
         (spin (* (/ (exact->inexact (cdr spin-rv)) 200.0)
                  (+ 0.9 (* 0.15 speed-scale))))
         (x (case edge
              ((0) -24.0)
              ((1) (+ width 24.0))
              (else random-x)))
         (y (case edge
              ((2) -24.0)
              ((3) (+ height 24.0))
              (else random-y)))
         (dx (if (< (abs raw-dx) 0.45) (if (<= raw-dx 0.0) -0.8 0.8) raw-dx))
         (dy (if (< (abs raw-dy) 0.45) (if (<= raw-dy 0.0) -0.8 0.8) raw-dy)))
    (cons seed-8 (make-asteroid x y dx dy radius angle spin))))

(define (spawn-asteroids seed count speed-scale)
  (let loop ((n count) (seed seed) (items '()))
    (if (= n 0)
        (cons seed items)
        (let* ((made (spawn-asteroid seed speed-scale))
               (next-seed (car made))
               (asteroid (cdr made)))
          (loop (- n 1) next-seed (cons asteroid items))))))

(define (spawn-wave seed wave)
  (spawn-asteroids seed (wave-asteroid-count wave) (wave-speed-scale wave)))

(define (spawn-saucer seed wave)
  (let* ((side-rv (rand-int seed 2))
         (seed-1 (car side-rv))
         (from-left? (= (cdr side-rv) 0))
         (y-rv (rand-range seed-1 48 300))
         (seed-2 (car y-rv))
         (y (exact->inexact (cdr y-rv)))
         (cooldown-rv (rand-range seed-2 36 70))
         (seed-3 (car cooldown-rv))
         (fire-cooldown (cdr cooldown-rv))
         (speed (+ 1.45 (* 0.08 (exact->inexact (min 8 (- wave 1))))))
         (x (if from-left? -30.0 (+ width 30.0)))
         (dx (if from-left? speed (- speed))))
    (cons seed-3 (make-saucer x y dx fire-cooldown))))

(define (draw-backdrop)
  (gfx-clear 6 8 18)
  (gfx-circle 540 72 18 10)
  (gfx-circle 540 72 10 13))

(define (draw-ship x y angle thrust? invuln)
  (if (or (= invuln 0) (< (modulo invuln 8) 4))
      (let* ((nose (ship-point x y angle 14.0))
             (left (ship-point x y (+ angle 2.45) 11.0))
             (right (ship-point x y (- angle 2.45) 11.0)))
        (gfx-triangle-outline (car nose) (cdr nose)
                              (car left) (cdr left)
                              (car right) (cdr right)
                              31)
        (if thrust?
            (let ((tail (ship-point x y (+ angle pi) (+ 8.0 (* 3.0 (sin angle))))))
              (gfx-line (car left) (cdr left) (car tail) (cdr tail) 24)
              (gfx-line (car right) (cdr right) (car tail) (cdr tail) 20))
            0))
      0))

(define (draw-bullets-colour bullets colour)
  (if (null? bullets)
      0
      (begin
        (let ((bullet (car bullets)))
          (gfx-line (- (bullet-x bullet) (bullet-dx bullet))
                    (- (bullet-y bullet) (bullet-dy bullet))
                    (bullet-x bullet)
                    (bullet-y bullet)
                    colour))
        (draw-bullets-colour (cdr bullets) colour))))

(define (draw-bullets bullets)
  (draw-bullets-colour bullets 21))

(define (draw-saucer-bullets bullets)
  (draw-bullets-colour bullets 24))

(define (draw-saucer saucer)
  (if saucer
      (let* ((x (saucer-x saucer))
             (y (saucer-y saucer))
             (left (- x 14.0))
             (right (+ x 14.0))
             (mid-left (- x 8.0))
             (mid-right (+ x 8.0))
             (top (- y 6.0))
             (mid (- y 1.0))
             (bottom (+ y 5.0)))
        (gfx-line left bottom right bottom 31)
        (gfx-line (- x 18.0) mid left bottom 29)
        (gfx-line right bottom (+ x 18.0) mid 29)
        (gfx-line mid-left top mid-right top 29)
        (gfx-line (- x 12.0) mid mid-left top 29)
        (gfx-line mid-right top (+ x 12.0) mid 29)
        (gfx-line (- x 10.0) mid (+ x 10.0) mid 21))
      0))

(define (draw-asteroids asteroids)
  (if (null? asteroids)
      0
      (begin
        (let* ((asteroid (car asteroids))
               (x (asteroid-x asteroid))
               (y (asteroid-y asteroid))
               (r (asteroid-radius asteroid))
               (angle (asteroid-angle asteroid))
               (p1 (ship-point x y angle r))
               (p2 (ship-point x y (+ angle 1.4) (* r 0.82)))
               (p3 (ship-point x y (+ angle 2.7) (* r 1.08)))
               (p4 (ship-point x y (+ angle 4.1) (* r 0.78)))
               (p5 (ship-point x y (+ angle 5.3) (* r 0.96))))
          (gfx-line (car p1) (cdr p1) (car p2) (cdr p2) 29)
          (gfx-line (car p2) (cdr p2) (car p3) (cdr p3) 29)
          (gfx-line (car p3) (cdr p3) (car p4) (cdr p4) 29)
          (gfx-line (car p4) (cdr p4) (car p5) (cdr p5) 29)
          (gfx-line (car p5) (cdr p5) (car p1) (cdr p1) 29))
        (draw-asteroids (cdr asteroids)))))

(define (draw-puffs puffs)
  (if (null? puffs)
      0
      (begin
        (let* ((puff (car puffs))
               (life (puff-life puff))
               (colour (if (> life 10) 24 20)))
          (gfx-circle-outline (puff-x puff) (puff-y puff) (puff-radius puff) colour))
        (draw-puffs (cdr puffs)))))

(define (draw-shards shards)
  (if (null? shards)
      0
      (begin
        (let ((shard (car shards)))
          (gfx-line (shard-x1 shard)
                    (shard-y1 shard)
                    (shard-x2 shard)
                    (shard-y2 shard)
                    (shard-colour shard)))
        (draw-shards (cdr shards)))))

(define (draw-hud score lives wave bullet-count cooldown hyper-cooldown next-extra game-over?)
  (gfx-rect 0 0 640 36 4)
  (gfx-text 12 10 "MacScheme Asteroids v2" 3)
  (gfx-text-small 246 12 "Left/Right turn  Up thrust  Space fire  H hyperspace  Esc quit" 5)
  (gfx-text-small 12 340
                  (string-append "score " (number->string score)
                                 "   lives " (number->string lives)
                                 "   wave " (number->string wave)
                                 "   shots " (number->string bullet-count) "/" (number->string max-bullets)
                                 "   reload " (number->string cooldown)
                                 "   hyper " (number->string hyper-cooldown)
                                 "   bonus@" (number->string next-extra))
                  28)
  (if game-over?
      (begin
        (gfx-text 222 154 "GAME OVER" 24)
        (gfx-text-small 180 182 "press space to restart or escape to quit" 29))
      0))

(define (draw-banner title subtitle)
  (gfx-text 184 154 title 24)
  (gfx-text-small 154 182 subtitle 29))

(define (render-scene ship-active? ship-x ship-y angle thrust? invuln bullets saucer-bullets asteroids saucer puffs shards score lives wave cooldown hyper-cooldown next-extra game-over?)
  (draw-backdrop)
  (if ship-active?
      (draw-ship ship-x ship-y angle thrust? invuln)
      0)
  (draw-saucer saucer)
  (draw-asteroids asteroids)
  (draw-bullets bullets)
  (draw-saucer-bullets saucer-bullets)
  (draw-puffs puffs)
  (draw-shards shards)
  (draw-hud score lives wave (list-length bullets) cooldown hyper-cooldown next-extra game-over?))

(define (update-bullets bullets)
  (if (null? bullets)
      '()
      (let* ((bullet (car bullets))
             (next-life (- (bullet-life bullet) 1))
             (next-x (wrap (+ (bullet-x bullet) (bullet-dx bullet)) width))
             (next-y (wrap (+ (bullet-y bullet) (bullet-dy bullet)) height))
             (rest (update-bullets (cdr bullets))))
        (if (<= next-life 0)
            rest
            (cons (make-bullet next-x next-y (bullet-dx bullet) (bullet-dy bullet) next-life)
                  rest)))))

(define (update-asteroids asteroids)
  (if (null? asteroids)
      '()
      (let* ((asteroid (car asteroids))
             (next-x (wrap (+ (asteroid-x asteroid) (asteroid-dx asteroid)) width))
             (next-y (wrap (+ (asteroid-y asteroid) (asteroid-dy asteroid)) height))
             (next-angle (+ (asteroid-angle asteroid) (asteroid-spin asteroid))))
        (cons (make-asteroid next-x next-y
                             (asteroid-dx asteroid)
                             (asteroid-dy asteroid)
                             (asteroid-radius asteroid)
                             next-angle
                             (asteroid-spin asteroid))
              (update-asteroids (cdr asteroids))))))

(define (update-puffs puffs)
  (if (null? puffs)
      '()
      (let* ((puff (car puffs))
             (next-life (- (puff-life puff) 1))
             (rest (update-puffs (cdr puffs))))
        (if (<= next-life 0)
            rest
            (cons (make-puff (puff-x puff) (puff-y puff) (+ (puff-radius puff) 1.6) next-life)
                  rest)))))

(define (update-shards shards)
  (if (null? shards)
      '()
      (let* ((shard (car shards))
             (next-life (- (shard-life shard) 1))
             (rest (update-shards (cdr shards))))
        (if (<= next-life 0)
            rest
            (cons (make-shard (+ (shard-x1 shard) (shard-dx shard))
                              (+ (shard-y1 shard) (shard-dy shard))
                              (+ (shard-x2 shard) (shard-dx shard))
                              (+ (shard-y2 shard) (shard-dy shard))
                              (* (shard-dx shard) 0.985)
                              (* (shard-dy shard) 0.985)
                              next-life
                              (shard-colour shard))
                  rest)))))

(define (make-burst-shard cx cy move-angle line-angle speed length life colour)
  (let* ((half-len (/ length 2.0))
         (hx (* (cos line-angle) half-len))
         (hy (* (sin line-angle) half-len)))
    (make-shard (- cx hx)
                (- cy hy)
                (+ cx hx)
                (+ cy hy)
                (* (cos move-angle) speed)
                (* (sin move-angle) speed)
                life
                colour)))

(define (radial-fragment-velocity origin-x origin-y point-x point-y base-dx base-dy boost)
  (let ((dir (atan (- point-y origin-y) (- point-x origin-x))))
    (cons (+ base-dx (* (cos dir) boost))
          (+ base-dy (* (sin dir) boost)))))

(define (asteroid-explosion-puffs asteroid)
  (let* ((r (asteroid-radius asteroid))
         (x (asteroid-x asteroid))
         (y (asteroid-y asteroid))
         (tier (asteroid-tier asteroid)))
    (case tier
      ((large) (list (make-puff x y 6.0 12)
                     (make-puff x y 12.0 18)))
      ((medium) (list (make-puff x y 5.0 10)
                      (make-puff x y (* r 0.55) 14)))
      (else (list (make-puff x y 4.0 8))))))

(define (asteroid-explosion-shards asteroid)
  (let* ((x (asteroid-x asteroid))
         (y (asteroid-y asteroid))
         (base-angle (asteroid-angle asteroid))
         (tier (asteroid-tier asteroid)))
    (case tier
      ((large) (list (make-burst-shard x y (+ base-angle 0.2) (+ base-angle 0.6) 1.8 12.0 18 29)
                     (make-burst-shard x y (+ base-angle 1.5) (+ base-angle 1.9) 1.5 10.0 16 24)
                     (make-burst-shard x y (+ base-angle 2.9) (+ base-angle 3.3) 1.7 13.0 19 29)
                     (make-burst-shard x y (+ base-angle 4.4) (+ base-angle 4.8) 1.4 9.0 15 20)))
      ((medium) (list (make-burst-shard x y (+ base-angle 0.4) (+ base-angle 0.7) 1.6 9.0 15 29)
                      (make-burst-shard x y (+ base-angle 2.5) (+ base-angle 2.9) 1.4 8.0 14 24)
                      (make-burst-shard x y (+ base-angle 4.6) (+ base-angle 4.9) 1.3 7.0 13 20)))
      (else (list (make-burst-shard x y (+ base-angle 0.9) (+ base-angle 1.2) 1.2 6.0 11 24)
                  (make-burst-shard x y (+ base-angle 3.8) (+ base-angle 4.1) 1.0 5.0 10 20))))))

(define (saucer-explosion-puffs saucer)
  (list (make-puff (saucer-x saucer) (saucer-y saucer) 7.0 12)
        (make-puff (saucer-x saucer) (saucer-y saucer) 12.0 16)))

(define (saucer-explosion-shards saucer)
  (let ((x (saucer-x saucer))
        (y (saucer-y saucer)))
    (list (make-burst-shard x y 0.2 0.0 1.8 10.0 16 31)
          (make-burst-shard x y 1.8 1.4 1.6 8.0 15 29)
          (make-burst-shard x y 3.1 2.7 1.7 12.0 17 24)
          (make-burst-shard x y 4.3 4.0 1.5 8.0 15 20)
          (make-burst-shard x y 5.4 5.0 1.6 10.0 16 29))))

(define (ship-death-puffs ship-x ship-y)
  (list (make-puff ship-x ship-y 8.0 14)
        (make-puff ship-x ship-y 14.0 20)))

(define (ship-death-shards ship-x ship-y ship-dx ship-dy angle)
  (let* ((nose (ship-point ship-x ship-y angle 14.0))
         (left (ship-point ship-x ship-y (+ angle 2.45) 11.0))
         (right (ship-point ship-x ship-y (- angle 2.45) 11.0))
         (tail (ship-point ship-x ship-y (+ angle pi) 7.5))
         (vel-scale 1.5)
         (mid-a (cons (/ (+ (car nose) (car left)) 2.0)
                      (/ (+ (cdr nose) (cdr left)) 2.0)))
         (mid-b (cons (/ (+ (car nose) (car right)) 2.0)
                      (/ (+ (cdr nose) (cdr right)) 2.0)))
         (mid-c (cons (/ (+ (car left) (car right)) 2.0)
                      (/ (+ (cdr left) (cdr right)) 2.0)))
         (mid-d (cons (/ (+ (car tail) (car left)) 2.0)
                      (/ (+ (cdr tail) (cdr left)) 2.0)))
         (vel-a (radial-fragment-velocity ship-x ship-y (car mid-a) (cdr mid-a) ship-dx ship-dy (+ vel-scale 0.4)))
         (vel-b (radial-fragment-velocity ship-x ship-y (car mid-b) (cdr mid-b) ship-dx ship-dy (+ vel-scale 0.4)))
         (vel-c (radial-fragment-velocity ship-x ship-y (car mid-c) (cdr mid-c) ship-dx ship-dy (+ vel-scale 0.1)))
         (vel-d (radial-fragment-velocity ship-x ship-y (car mid-d) (cdr mid-d) ship-dx ship-dy vel-scale)))
    (list (make-shard (car nose) (cdr nose) (car left) (cdr left) (car vel-a) (cdr vel-a) 20 31)
          (make-shard (car nose) (cdr nose) (car right) (cdr right) (car vel-b) (cdr vel-b) 20 31)
          (make-shard (car left) (cdr left) (car right) (cdr right) (car vel-c) (cdr vel-c) 18 29)
          (make-shard (car tail) (cdr tail) (car left) (cdr left) (car vel-d) (cdr vel-d) 16 24))))

(define (update-saucer saucer)
  (if saucer
      (let* ((next-x (+ (saucer-x saucer) (saucer-dx saucer)))
             (next-cooldown (max 0 (- (saucer-fire-cooldown saucer) 1))))
        (if (or (< next-x -42.0) (> next-x (+ width 42.0)))
            #f
            (make-saucer next-x (saucer-y saucer) (saucer-dx saucer) next-cooldown)))
      #f))

(define (fire-saucer-bullet seed saucer ship-active? ship-x ship-y wave)
  (if (or (not saucer) (> (saucer-fire-cooldown saucer) 0))
      (vector seed saucer '())
      (let* ((base-angle (if ship-active?
                             (atan (- ship-y (saucer-y saucer))
                                   (- ship-x (saucer-x saucer)))
                             (if (> (saucer-dx saucer) 0.0) 0.0 pi)))
             (spread-size (max 4 (- 20 (* 2 (min 7 wave)))))
             (spread-rv (rand-range seed (- spread-size) spread-size))
             (seed-1 (car spread-rv))
             (spread (/ (exact->inexact (cdr spread-rv)) 100.0))
             (cooldown-low (max 18 (- 58 (* 3 (min 7 wave)))))
             (cooldown-rv (rand-range seed-1 cooldown-low (+ cooldown-low 24)))
             (seed-2 (car cooldown-rv))
             (next-cooldown (cdr cooldown-rv))
             (angle (+ base-angle spread))
             (speed (+ 3.5 (* 0.12 (exact->inexact (min 8 wave)))))
             (bullet (make-bullet (+ (saucer-x saucer) (* (cos angle) 14.0))
                                  (+ (saucer-y saucer) (* (sin angle) 14.0))
                                  (* (cos angle) speed)
                                  (* (sin angle) speed)
                                  saucer-bullet-life)))
        (play-generated-sound (sound-shoot 1.15 0.05))
        (vector seed-2
                (make-saucer (saucer-x saucer)
                             (saucer-y saucer)
                             (saucer-dx saucer)
                             next-cooldown)
                (list bullet)))))

(define (bullet-hit-asteroid? bullet asteroid)
  (< (distance-squared (bullet-x bullet) (bullet-y bullet)
                       (asteroid-x asteroid) (asteroid-y asteroid))
     (let ((radius (+ 4.0 (asteroid-radius asteroid))))
       (* radius radius))))

(define (ship-hit-asteroid? ship-x ship-y asteroid)
  (< (distance-squared ship-x ship-y (asteroid-x asteroid) (asteroid-y asteroid))
     (let ((radius (+ ship-radius (asteroid-radius asteroid))))
       (* radius radius))))

(define (bullet-hit-saucer? bullet saucer)
  (< (distance-squared (bullet-x bullet) (bullet-y bullet)
                       (saucer-x saucer) (saucer-y saucer))
     (let ((radius (+ 4.0 saucer-radius)))
       (* radius radius))))

(define (ship-hit-saucer? ship-x ship-y saucer)
  (< (distance-squared ship-x ship-y (saucer-x saucer) (saucer-y saucer))
     (let ((radius (+ ship-radius saucer-radius)))
       (* radius radius))))

(define (any-ship-hit-by-bullets? ship-x ship-y bullets)
  (if (null? bullets)
      #f
      (if (< (distance-squared ship-x ship-y
                               (bullet-x (car bullets))
                               (bullet-y (car bullets)))
             (let ((radius (+ ship-radius 4.0)))
               (* radius radius)))
          #t
          (any-ship-hit-by-bullets? ship-x ship-y (cdr bullets)))))

(define (point-too-close? x y asteroid padding)
  (< (distance-squared x y (asteroid-x asteroid) (asteroid-y asteroid))
     (let ((radius (+ padding (asteroid-radius asteroid))))
       (* radius radius))))

(define (respawn-area-clear? asteroids)
  (let loop ((remaining asteroids))
    (if (null? remaining)
        #t
        (if (point-too-close? (/ width 2.0) (/ height 2.0) (car remaining) 72.0)
            #f
            (loop (cdr remaining))))))

(define (asteroid-tier asteroid)
  (let ((radius (asteroid-radius asteroid)))
    (cond
      ((>= radius large-threshold) 'large)
      ((>= radius medium-threshold) 'medium)
      (else 'small))))

(define (asteroid-score asteroid)
  (case (asteroid-tier asteroid)
    ((large) 20)
    ((medium) 50)
    (else 100)))

(define (play-generated-sound sound-id)
  (if (> sound-id 0)
      (sound-play sound-id)
      0))

(define (play-asteroid-hit-sound asteroid)
  (play-generated-sound
    (case (asteroid-tier asteroid)
      ((large) (sound-explode 1.05 0.18))
      ((medium) (sound-small-explosion 1.0 0.16))
      (else (sound-click 1.1 0.05)))))

(define (split-asteroid asteroid)
  (let* ((tier (asteroid-tier asteroid))
         (scale (case tier
                  ((large) large-child-radius-scale)
                  ((medium) medium-child-radius-scale)
                  (else 0.0))))
    (if (= scale 0.0)
        '()
        (let* ((x (asteroid-x asteroid))
               (y (asteroid-y asteroid))
               (radius (max 10.0 (* (asteroid-radius asteroid) scale)))
               (base-angle (asteroid-angle asteroid))
               (dx (asteroid-dx asteroid))
               (dy (asteroid-dy asteroid))
               (launch (+ 0.9 (* radius 0.03)))
               (angle-a (+ base-angle 0.8))
               (angle-b (- base-angle 0.8)))
          (list
            (make-asteroid (wrap (+ x (* (cos angle-a) radius)) width)
                           (wrap (+ y (* (sin angle-a) radius)) height)
                           (+ dx (* (cos angle-a) launch))
                           (+ dy (* (sin angle-a) launch))
                           radius
                           (+ base-angle 0.35)
                           (+ (asteroid-spin asteroid) 0.025))
            (make-asteroid (wrap (+ x (* (cos angle-b) radius)) width)
                           (wrap (+ y (* (sin angle-b) radius)) height)
                           (+ dx (* (cos angle-b) launch))
                           (+ dy (* (sin angle-b) launch))
                           radius
                           (- base-angle 0.35)
                           (- (asteroid-spin asteroid) 0.025)))))))

(define (resolve-asteroids asteroids bullets score puffs shards)
  (if (null? asteroids)
      (make-resolution '() bullets score puffs shards)
      (let ((asteroid (car asteroids)))
        (let check-bullets ((remaining bullets) (kept '()))
          (if (null? remaining)
              (let ((resolved (resolve-asteroids (cdr asteroids) bullets score puffs shards)))
                (make-resolution (cons asteroid (resolution-asteroids resolved))
                                 (resolution-bullets resolved)
                                 (resolution-score resolved)
                                 (resolution-puffs resolved)
                                 (resolution-shards resolved)))
              (if (bullet-hit-asteroid? (car remaining) asteroid)
                  (let* ((_ (play-asteroid-hit-sound asteroid))
                         (fragments (split-asteroid asteroid))
                         (next-bullets (append (reverse kept) (cdr remaining)))
                         (resolved (resolve-asteroids (cdr asteroids)
                                                     next-bullets
                                                     (+ score (asteroid-score asteroid))
                                                     (append (asteroid-explosion-puffs asteroid) puffs)
                                                     (append (asteroid-explosion-shards asteroid) shards))))
                    (make-resolution (append fragments (resolution-asteroids resolved))
                                     (resolution-bullets resolved)
                                     (resolution-score resolved)
                                     (resolution-puffs resolved)
                                     (resolution-shards resolved)))
                  (check-bullets (cdr remaining) (cons (car remaining) kept))))))))

(define (resolve-saucer-hit saucer bullets score puffs shards)
  (if (not saucer)
      (vector #f bullets score puffs shards)
      (let loop ((remaining bullets) (kept '()))
        (if (null? remaining)
            (vector saucer bullets score puffs shards)
            (if (bullet-hit-saucer? (car remaining) saucer)
                (begin
                  (play-generated-sound (sound-explode 0.85 0.14))
                  (vector #f
                          (append (reverse kept) (cdr remaining))
                          (+ score saucer-score)
                          (append (saucer-explosion-puffs saucer) puffs)
                          (append (saucer-explosion-shards saucer) shards)))
                (loop (cdr remaining) (cons (car remaining) kept)))))))

(define (any-ship-collision? ship-x ship-y asteroids)
  (if (null? asteroids)
      #f
      (or (ship-hit-asteroid? ship-x ship-y (car asteroids))
          (any-ship-collision? ship-x ship-y (cdr asteroids)))))

(define (award-extra-lives score lives next-extra)
  (let loop ((lives lives) (threshold next-extra) (awarded? #f))
    (if (>= score threshold)
        (loop (+ lives 1) (+ threshold extra-life-step) #t)
        (vector lives threshold awarded?))))

(define (roll-hyperspace seed)
  (let* ((x-rv (rand-range seed 24 615))
         (seed-1 (car x-rv))
         (x (exact->inexact (cdr x-rv)))
         (y-rv (rand-range seed-1 24 335))
         (seed-2 (car y-rv))
         (y (exact->inexact (cdr y-rv)))
         (f-rv (rand-range seed-2 0 99))
         (seed-3 (car f-rv))
         (failure-roll (cdr f-rv)))
    (vector seed-3 x y (< failure-roll hyperspace-failure-percent))))

(let* ((spawned (spawn-wave initial-seed 1))
  (seed-1 (car spawned))
  (asteroids (cdr spawned))
  (scheduled (schedule-saucer-spawn seed-1 1))
  (seed (car scheduled))
  (saucer-spawn-timer (cdr scheduled)))
  (let loop ((ship-x (/ width 2.0))
        (ship-y (/ height 2.0))
        (ship-dx 0.0)
        (ship-dy 0.0)
        (angle -1.5708)
        (ship-active? #t)
        (invuln invuln-max)
        (respawn-delay 0)
        (bullets '())
        (saucer #f)
        (saucer-bullets '())
        (asteroids asteroids)
        (puffs '())
        (shards '())
        (seed seed)
        (score 0)
        (wave 1)
        (lives 3)
        (next-extra extra-life-step)
        (cooldown 0)
        (hyper-cooldown 0)
        (saucer-spawn-timer saucer-spawn-timer)
        (wave-clear-timer 0)
        (game-over? #f))
    (let* ((pressed-key (gfx-read-key))
      (left? (or (gfx-key-pressed? 'left) (gfx-key-pressed? 'a)))
      (right? (or (gfx-key-pressed? 'right) (gfx-key-pressed? 'd)))
      (thrust? (or (gfx-key-pressed? 'up) (gfx-key-pressed? 'w)))
      (fire? (gfx-key-pressed? 'space))
      (hyper? (or (gfx-key-pressed? 'h) (gfx-key-pressed? 'x))))
      (cond
   ((or (eq? pressed-key 'escape)
        (eq? pressed-key 'esc)
        (not (gfx-active?)))
    'done)

  (game-over?
   (render-scene #f ship-x ship-y angle #f 0 bullets saucer-bullets asteroids saucer puffs shards score lives wave cooldown hyper-cooldown next-extra #t)
    (gfx-flip)
    (gfx-wait 1)
    (if fire?
        (let* ((spawned (spawn-wave (rand-next seed) 1))
          (seed-1 (car spawned))
          (restart-asteroids (cdr spawned))
          (scheduled (schedule-saucer-spawn seed-1 1))
          (restart-seed (car scheduled))
          (restart-saucer-timer (cdr scheduled)))
     (loop (/ width 2.0)
      (/ height 2.0)
      0.0
      0.0
      -1.5708
      #t
      invuln-max
      0
      '()
      #f
      '()
      restart-asteroids
      '()
      '()
      restart-seed
      0
      1
      3
      extra-life-step
      0
      0
      restart-saucer-timer
      0
      #f))
        (loop ship-x ship-y ship-dx ship-dy angle ship-active? invuln respawn-delay bullets saucer saucer-bullets asteroids puffs shards seed score wave lives next-extra cooldown hyper-cooldown saucer-spawn-timer wave-clear-timer #t)))

  ((> wave-clear-timer 0)
   (let ((next-puffs (update-puffs puffs))
       (next-shards (update-shards shards)))
    (render-scene ship-active? ship-x ship-y angle #f invuln '() '() asteroids #f next-puffs next-shards score lives wave 0 hyper-cooldown next-extra #f)
      (draw-banner (string-append "WAVE " (number->string wave) " CLEARED")
         "stand by for the next asteroid field")
      (gfx-flip)
      (gfx-wait 1)
      (if (= wave-clear-timer 1)
     (let* ((next-wave (+ wave 1))
       (_ (play-generated-sound (sound-powerup 0.94 0.25)))
       (spawned (spawn-wave (rand-next seed) next-wave))
       (seed-1 (car spawned))
       (next-asteroids (cdr spawned))
       (scheduled (schedule-saucer-spawn seed-1 next-wave))
       (next-seed (car scheduled))
       (next-saucer-timer (cdr scheduled)))
       (loop (/ width 2.0)
        (/ height 2.0)
        0.0
        0.0
        -1.5708
        #t
        invuln-max
        0
        '()
        #f
        '()
        next-asteroids
        '()
        '()
        next-seed
        score
        next-wave
        lives
        next-extra
        0
        (max 0 (- hyper-cooldown 1))
        next-saucer-timer
        0
        #f))
    (loop ship-x ship-y ship-dx ship-dy angle ship-active? invuln respawn-delay '() #f '() asteroids next-puffs next-shards seed score wave lives next-extra 0 (max 0 (- hyper-cooldown 1)) saucer-spawn-timer (- wave-clear-timer 1) #f))))

   (else
    (let* ((aged-bullets (update-bullets bullets))
      (aged-saucer-bullets (update-bullets saucer-bullets))
      (updated-asteroids (update-asteroids asteroids))
      (updated-puffs (update-puffs puffs))
      (updated-shards (update-shards shards))
      (next-cooldown (max 0 (- cooldown 1)))
      (next-hyper-cooldown (max 0 (- hyper-cooldown 1)))
      (rotated-angle (if ship-active?
          (+ angle (if left? -0.09 0.0) (if right? 0.09 0.0))
          angle))
      (thrust-x (if (and ship-active? thrust?) (* (cos rotated-angle) 0.11) 0.0))
      (thrust-y (if (and ship-active? thrust?) (* (sin rotated-angle) 0.11) 0.0))
      (moved-ship-dx (if ship-active? (* (+ ship-dx thrust-x) 0.992) ship-dx))
      (moved-ship-dy (if ship-active? (* (+ ship-dy thrust-y) 0.992) ship-dy))
      (moved-ship-x (if ship-active? (wrap (+ ship-x moved-ship-dx) width) ship-x))
      (moved-ship-y (if ship-active? (wrap (+ ship-y moved-ship-dy) height) ship-y))
      (hyper-request? (and ship-active? hyper? (= next-hyper-cooldown 0)))
      (hyper-result (if hyper-request? (roll-hyperspace seed) #f))
      (seed-after-hyper (if hyper-request? (vector-ref hyper-result 0) seed))
      (hyper-x (if hyper-request? (vector-ref hyper-result 1) moved-ship-x))
      (hyper-y (if hyper-request? (vector-ref hyper-result 2) moved-ship-y))
      (hyper-failed? (if hyper-request? (vector-ref hyper-result 3) #f))
      (_ (if hyper-request?
        (play-generated-sound (if hyper-failed?
              (sound-big-explosion 1.05 0.18)
              (sound-powerup 1.1 0.12)))
        0))
      (ship-x* (if hyper-request? hyper-x moved-ship-x))
      (ship-y* (if hyper-request? hyper-y moved-ship-y))
      (ship-dx* (if hyper-request? 0.0 moved-ship-dx))
      (ship-dy* (if hyper-request? 0.0 moved-ship-dy))
      (invuln* (if (and ship-active? (> invuln 0)) (- invuln 1) 0))
      (hyper-cooldown* (if hyper-request? hyperspace-cooldown-max next-hyper-cooldown))
      (saucer-spawn-timer* (if saucer saucer-spawn-timer (max 0 (- saucer-spawn-timer 1))))
      (spawned-saucer (if (and (not saucer) (= saucer-spawn-timer* 0))
           (spawn-saucer seed-after-hyper wave)
           #f))
      (seed-after-saucer-spawn (if spawned-saucer (car spawned-saucer) seed-after-hyper))
      (saucer-0 (if spawned-saucer (cdr spawned-saucer) saucer))
      (updated-saucer (update-saucer saucer-0))
      (saucer-fire-result (fire-saucer-bullet seed-after-saucer-spawn updated-saucer ship-active? ship-x* ship-y* wave))
      (seed-after-saucer-fire (vector-ref saucer-fire-result 0))
      (saucer-1 (vector-ref saucer-fire-result 1))
      (active-saucer-bullets (append (vector-ref saucer-fire-result 2) aged-saucer-bullets))
      (can-fire? (and ship-active?
            (not hyper-request?)
            fire?
            (= next-cooldown 0)
            (< (list-length aged-bullets) max-bullets)))
      (_ (if can-fire?
        (play-generated-sound (sound-shoot 0.85 0.07))
        0))
      (fired-bullets (if can-fire?
          (cons (make-bullet (+ ship-x* (* (cos rotated-angle) 14.0))
                   (+ ship-y* (* (sin rotated-angle) 14.0))
                   (+ (* (cos rotated-angle) 7.0) (* ship-dx* 0.5))
                   (+ (* (sin rotated-angle) 7.0) (* ship-dy* 0.5))
                   bullet-life-max)
                aged-bullets)
          aged-bullets))
      (cooldown* (if can-fire? 8 next-cooldown))
      (resolved (resolve-asteroids updated-asteroids fired-bullets score updated-puffs updated-shards))
      (resolved-asteroids (resolution-asteroids resolved))
      (resolved-shards-a (resolution-shards resolved))
      (saucer-resolution (resolve-saucer-hit saucer-1
                   (resolution-bullets resolved)
                   (resolution-score resolved)
           (resolution-puffs resolved)
           resolved-shards-a))
      (resolved-saucer (vector-ref saucer-resolution 0))
      (resolved-bullets (vector-ref saucer-resolution 1))
      (resolved-score (vector-ref saucer-resolution 2))
      (resolved-puffs (vector-ref saucer-resolution 3))
      (resolved-shards (vector-ref saucer-resolution 4))
      (saucer-ended? (and saucer-0 (not resolved-saucer)))
      (scheduled (if saucer-ended?
           (schedule-saucer-spawn seed-after-saucer-fire wave)
           (cons seed-after-saucer-fire saucer-spawn-timer*)))
      (seed-final (car scheduled))
      (saucer-spawn-timer-final (if resolved-saucer 0 (cdr scheduled)))
      (award (award-extra-lives resolved-score lives next-extra))
      (lives* (vector-ref award 0))
      (next-extra* (vector-ref award 1))
      (_ (if (vector-ref award 2)
        (play-generated-sound (sound-powerup 1.16 0.18))
        0))
      (ship-hit? (or hyper-failed?
           (and ship-active?
           (= invuln* 0)
           (or (any-ship-collision? ship-x* ship-y* resolved-asteroids)
               (and resolved-saucer (ship-hit-saucer? ship-x* ship-y* resolved-saucer))
               (any-ship-hit-by-bullets? ship-x* ship-y* active-saucer-bullets))))))
      (if ship-hit?
     (let* ((remaining-lives (- lives* 1))
       (boom-puffs (append (ship-death-puffs ship-x* ship-y*) resolved-puffs))
       (boom-shards (append (ship-death-shards ship-x* ship-y* ship-dx* ship-dy* rotated-angle)
                            resolved-shards)))
       (if (not hyper-failed?)
      (play-generated-sound (sound-big-explosion 1.2 0.28))
      0)
      (render-scene #f (/ width 2.0) (/ height 2.0) rotated-angle #f 0 resolved-bullets active-saucer-bullets resolved-asteroids resolved-saucer boom-puffs boom-shards resolved-score remaining-lives wave cooldown* hyper-cooldown* next-extra* (<= remaining-lives 0))
       (if (> remaining-lives 0)
      (draw-banner "SHIP LOST" "waiting for a safe respawn window")
      0)
       (gfx-flip)
       (gfx-wait 1)
       (loop (/ width 2.0)
        (/ height 2.0)
        0.0
        0.0
        -1.5708
        #f
        0
        respawn-delay-max
        resolved-bullets
        resolved-saucer
        active-saucer-bullets
        resolved-asteroids
        boom-puffs
        boom-shards
        seed-final
        resolved-score
        wave
        remaining-lives
        next-extra*
        cooldown*
        hyper-cooldown*
        saucer-spawn-timer-final
        0
        (<= remaining-lives 0)))
     (let* ((respawn-delay* (if ship-active? 0 (max 0 (- respawn-delay 1))))
       (respawn-safe? (and (respawn-area-clear? resolved-asteroids)
            (or (not resolved-saucer)
                (not (ship-hit-saucer? (/ width 2.0) (/ height 2.0) resolved-saucer)))
            (not (any-ship-hit-by-bullets? (/ width 2.0) (/ height 2.0) active-saucer-bullets))))
       (respawn-now? (and (not ship-active?) (= respawn-delay* 0) respawn-safe?))
       (ship-active** (if respawn-now? #t ship-active?))
       (ship-x** (if respawn-now? (/ width 2.0) ship-x*))
       (ship-y** (if respawn-now? (/ height 2.0) ship-y*))
       (ship-dx** (if respawn-now? 0.0 ship-dx*))
       (ship-dy** (if respawn-now? 0.0 ship-dy*))
       (angle** (if respawn-now? -1.5708 rotated-angle))
       (invuln** (if respawn-now? invuln-max invuln*))
       (respawn-delay** (if respawn-now? 0 respawn-delay*)))
       (if (and (null? resolved-asteroids) (not resolved-saucer))
      (begin
        (render-scene ship-active** ship-x** ship-y** angle** #f invuln** '() '() resolved-asteroids #f resolved-puffs resolved-shards resolved-score lives* wave cooldown* hyper-cooldown* next-extra* #f)
        (draw-banner (string-append "WAVE " (number->string wave) " CLEARED")
           "stand by for the next asteroid field")
        (gfx-flip)
        (gfx-wait 1)
        (loop ship-x**
         ship-y**
         ship-dx**
         ship-dy**
         angle**
         ship-active**
         invuln**
         respawn-delay**
         '()
         #f
         '()
         resolved-asteroids
         resolved-puffs
        resolved-shards
         seed-final
         resolved-score
         wave
         lives*
         next-extra*
         0
         hyper-cooldown*
         saucer-spawn-timer-final
         wave-clear-delay
         #f))
      (begin
        (render-scene ship-active** ship-x** ship-y** angle** thrust? invuln** resolved-bullets active-saucer-bullets resolved-asteroids resolved-saucer resolved-puffs resolved-shards resolved-score lives* wave cooldown* hyper-cooldown* next-extra* #f)
        (if (and (not ship-active**) (= respawn-delay** 0))
            (draw-banner "RESPAWN BLOCKED" "center is still unsafe; wait for an opening")
            (if (not ship-active**)
           (draw-banner "RESPAWNING" "centering ship for a safe return")
           0))
        (gfx-flip)
        (gfx-wait 1)
        (loop ship-x**
         ship-y**
         ship-dx**
         ship-dy**
         angle**
         ship-active**
         invuln**
         respawn-delay**
         resolved-bullets
         resolved-saucer
         active-saucer-bullets
         resolved-asteroids
         resolved-puffs
        resolved-shards
         seed-final
         resolved-score
         wave
         lives*
         next-extra*
         cooldown*
         hyper-cooldown*
         saucer-spawn-timer-final
         0
         #f)))))))))))