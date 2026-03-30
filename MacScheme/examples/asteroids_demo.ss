(layout-set! 'focus-graphics)
(gfx-screen 640 360 2)
(gfx-reset)
(audio-init)
(sound-volume 0.6)

; A tiny Asteroids-style game written in plain Scheme.
; Controls: left/right rotate, up thrusts, space fires, escape quits.
; This file is intentionally commented like a tutorial so it's easier to tweak.

; Core tuning values for the playfield and asteroid splitting.
; Quick customization guide:
; - `bullet-life-max` makes shots travel farther or shorter.
; - `asteroid-count` controls how crowded the opening wave feels.
; - `large-threshold` / `medium-threshold` decide when rocks split.
; - `large-child-radius-scale` / `medium-child-radius-scale` control child rock size.
; - Sound and HUD colours are near the bottom of the file inside the draw/update code.
(define width 640.0)
(define height 360.0)
(define ship-radius 12.0)
(define bullet-life-max 44)
(define asteroid-count 6)
(define large-threshold 26.0)
(define medium-threshold 16.0)
(define large-child-radius-scale 0.72)
(define medium-child-radius-scale 0.58)
(define initial-seed 42424242)

(define (clamp n lo hi)
  (max lo (min hi n)))

(define (wrap value limit)
  (cond
    ((< value 0.0) (+ value limit))
    ((>= value limit) (- value limit))
    (else value)))

(define (distance x1 y1 x2 y2)
  (sqrt (+ (* (- x2 x1) (- x2 x1))
           (* (- y2 y1) (- y2 y1)))))

(define (rand-next seed)
  (modulo (+ (* seed 1664525) 1013904223) 4294967296))

(define (rand-int seed limit)
  (let ((next (rand-next seed)))
    (cons next (if (<= limit 0) 0 (modulo next limit)))))

(define (rand-range seed low high)
  (let* ((span (max 1 (+ 1 (- high low))))
         (rv (rand-int seed span)))
    (cons (car rv) (+ low (cdr rv)))))

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

(define (spawn-asteroid seed)
  ; New asteroids spawn just off-screen and drift into the arena.
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
         (raw-dx (/ (exact->inexact (cdr dx-rv)) 10.0))
         (dy-rv (rand-range seed-4 -22 22))
         (seed-5 (car dy-rv))
         (raw-dy (/ (exact->inexact (cdr dy-rv)) 10.0))
         (radius-rv (rand-range seed-5 16 34))
         (seed-6 (car radius-rv))
         (radius (exact->inexact (cdr radius-rv)))
         (angle-rv (rand-range seed-6 0 628))
         (seed-7 (car angle-rv))
         (angle (/ (exact->inexact (cdr angle-rv)) 100.0))
         (spin-rv (rand-range seed-7 -9 9))
         (seed-8 (car spin-rv))
         (spin (/ (exact->inexact (cdr spin-rv)) 200.0))
         (x (case edge
              ((0) -24.0)
              ((1) (+ width 24.0))
              (else random-x)))
         (y (case edge
              ((2) -24.0)
              ((3) (+ height 24.0))
              (else random-y)))
         (dx (if (< (abs raw-dx) 0.4) (if (<= raw-dx 0.0) -0.7 0.7) raw-dx))
         (dy (if (< (abs raw-dy) 0.4) (if (<= raw-dy 0.0) -0.7 0.7) raw-dy)))
    (cons seed-8 (make-asteroid x y dx dy radius angle spin))))

(define (spawn-asteroids seed count)
  (let loop ((n count) (seed seed) (items '()))
    (if (= n 0)
        (cons seed items)
        (let* ((made (spawn-asteroid seed))
               (next-seed (car made))
               (asteroid (cdr made)))
          (loop (- n 1) next-seed (cons asteroid items))))))

(define (ship-point x y angle distance)
  (cons (+ x (* (cos angle) distance))
        (+ y (* (sin angle) distance))))

(define (draw-ship x y angle thrust? invuln)
  ; The ship is just a triangle outline plus an optional flame line.
  (if (or (= invuln 0) (< (modulo invuln 8) 4))
      (let* ((nose (ship-point x y angle 14.0))
             (left (ship-point x y (+ angle 2.45) 11.0))
             (right (ship-point x y (- angle 2.45) 11.0)))
        (gfx-triangle-outline (car nose) (cdr nose)
                              (car left) (cdr left)
                              (car right) (cdr right)
                              31)
        (if thrust?
            (let ((tail (ship-point x y (+ angle 3.14159) (+ 8.0 (* 3.0 (sin angle))))))
              (gfx-line (car left) (cdr left) (car tail) (cdr tail) 24)
              (gfx-line (car right) (cdr right) (car tail) (cdr tail) 20))
            0))
      0))

(define (draw-bullets bullets)
  (if (null? bullets)
      0
      (begin
        (let ((bullet (car bullets)))
          (gfx-line (- (bullet-x bullet) (bullet-dx bullet))
                    (- (bullet-y bullet) (bullet-dy bullet))
                    (bullet-x bullet)
                    (bullet-y bullet)
                    21))
        (draw-bullets (cdr bullets)))))

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

(define (bullet-hit-asteroid? bullet asteroid)
  (< (distance (bullet-x bullet) (bullet-y bullet)
               (asteroid-x asteroid) (asteroid-y asteroid))
     (+ 4.0 (asteroid-radius asteroid))))

(define (ship-hit-asteroid? ship-x ship-y asteroid)
  (< (distance ship-x ship-y (asteroid-x asteroid) (asteroid-y asteroid))
     (+ ship-radius (asteroid-radius asteroid))))

(define (asteroid-tier asteroid)
  (let ((radius (asteroid-radius asteroid)))
    (cond
      ((>= radius large-threshold) 'large)
      ((>= radius medium-threshold) 'medium)
      (else 'small))))

(define (asteroid-score asteroid)
  (case (asteroid-tier asteroid)
    ((large) 20)
    ((medium) 35)
    (else 60)))

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
  ; Large rocks split into medium ones, medium rocks split into small ones,
  ; and small rocks disappear when hit.
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

(define (resolve-asteroids asteroids bullets seed score puffs)
  ; Check every asteroid against every bullet and rebuild the lists with
  ; split fragments, score updates, and explosion puffs.
  (if (null? asteroids)
      (list 'ok asteroids bullets seed score puffs)
      (let ((asteroid (car asteroids)))
        (let check-bullets ((remaining bullets) (kept '()))
          (if (null? remaining)
              (let ((resolved (resolve-asteroids (cdr asteroids) bullets seed score puffs)))
                (list 'ok
                      (cons asteroid (cadr resolved))
                      (caddr resolved)
                      (cadddr resolved)
                      (car (cddddr resolved))
                      (cadr (cddddr resolved))))
              (if (bullet-hit-asteroid? (car remaining) asteroid)
                (let* ((_ (play-asteroid-hit-sound asteroid))
                   (fragments (split-asteroid asteroid))
                   (next-bullets (append (reverse kept) (cdr remaining)))
                   (resolved (resolve-asteroids (cdr asteroids) next-bullets seed (+ score (asteroid-score asteroid))
                            (cons (make-puff (asteroid-x asteroid) (asteroid-y asteroid) 6.0 12) puffs))))
                    (list 'ok
                    (append fragments (cadr resolved))
                          (caddr resolved)
                          (cadddr resolved)
                          (car (cddddr resolved))
                          (cadr (cddddr resolved))))
                  (check-bullets (cdr remaining) (cons (car remaining) kept))))))))

(define (any-ship-collision? ship-x ship-y asteroids)
  (if (null? asteroids)
      #f
      (or (ship-hit-asteroid? ship-x ship-y (car asteroids))
          (any-ship-collision? ship-x ship-y (cdr asteroids)))))

(define (draw-hud score lives cooldown game-over?)
  (gfx-rect 0 0 640 36 4)
  (gfx-text 12 10 "MacScheme Asteroids" 3)
  (gfx-text-small 230 12 "Left/Right turn  Up thrust  Space fire  Esc quit" 5)
  (gfx-text-small 12 340
                  (string-append "score " (number->string score)
                                 "   lives " (number->string lives)
                                 "   reload " (number->string cooldown))
                  28)
  (if game-over?
      (begin
        (gfx-text 222 158 "GAME OVER" 24)
        (gfx-text-small 186 184 "press space to restart or escape to quit" 29))
      0))

(let* ((spawned (spawn-asteroids initial-seed asteroid-count))
       (seed (car spawned))
       (asteroids (cdr spawned)))
  ; Main game loop: read input, update state, draw frame, repeat.
  (let loop ((ship-x (/ width 2.0))
             (ship-y (/ height 2.0))
             (ship-dx 0.0)
             (ship-dy 0.0)
             (angle -1.5708)
             (bullets '())
             (asteroids asteroids)
             (puffs '())
             (seed seed)
             (score 0)
             (lives 3)
             (cooldown 0)
             (respawn 90)
             (game-over? #f))
    (let* ((pressed-key (gfx-read-key))
           (left? (or (gfx-key-pressed? 'left) (gfx-key-pressed? 'a)))
           (right? (or (gfx-key-pressed? 'right) (gfx-key-pressed? 'd)))
           (thrust? (or (gfx-key-pressed? 'up) (gfx-key-pressed? 'w)))
           (fire? (gfx-key-pressed? 'space)))
      (if (or (eq? pressed-key 'escape)
              (eq? pressed-key 'esc)
              (not (gfx-active?)))
          'done
        (if game-over?
          (begin
          (gfx-clear 6 8 18)
          (gfx-circle 540 72 18 10)
          (gfx-circle 540 72 10 13)
          (draw-asteroids asteroids)
          (draw-bullets bullets)
          (draw-puffs puffs)
          (draw-hud score lives cooldown #t)
          (gfx-flip)
          (gfx-wait 1)
          (if fire?
            (let* ((spawned (spawn-asteroids (rand-next seed) asteroid-count))
                 (restart-seed (car spawned))
                 (restart-asteroids (cdr spawned)))
              (loop (/ width 2.0)
                (/ height 2.0)
                0.0
                0.0
                -1.5708
                '()
                restart-asteroids
                '()
                restart-seed
                0
                3
                0
                90
                #f))
            (loop ship-x
                ship-y
                ship-dx
                ship-dy
                angle
                bullets
                asteroids
                puffs
                seed
                score
                lives
                cooldown
                respawn
                #t)))
          (let* ((next-angle (+ angle (if left? -0.09 0.0) (if right? 0.09 0.0)))
                 (thrust-x (if (and thrust? (not game-over?)) (* (cos next-angle) 0.11) 0.0))
                 (thrust-y (if (and thrust? (not game-over?)) (* (sin next-angle) 0.11) 0.0))
                 (next-ship-dx (* (+ ship-dx thrust-x) 0.992))
                 (next-ship-dy (* (+ ship-dy thrust-y) 0.992))
                 (next-ship-x (wrap (+ ship-x next-ship-dx) width))
                 (next-ship-y (wrap (+ ship-y next-ship-dy) height))
                 (next-cooldown (max 0 (- cooldown 1)))
                 (fired-bullets (if (and fire? (= next-cooldown 0) (not game-over?))
                                    (begin
                                      (play-generated-sound (sound-shoot 0.85 0.07))
                                      (cons (make-bullet (+ next-ship-x (* (cos next-angle) 14.0))
                                                         (+ next-ship-y (* (sin next-angle) 14.0))
                                                         (+ (* (cos next-angle) 7.0) (* next-ship-dx 0.5))
                                                         (+ (* (sin next-angle) 7.0) (* next-ship-dy 0.5))
                                                         bullet-life-max)
                                            bullets))
                                    bullets))
                 (reset-cooldown (if (and fire? (= next-cooldown 0) (not game-over?)) 8 next-cooldown))
                 (updated-bullets (update-bullets fired-bullets))
                 (updated-asteroids (update-asteroids asteroids))
                 (updated-puffs (update-puffs puffs))
                 (resolved (resolve-asteroids updated-asteroids updated-bullets seed score updated-puffs))
                 (resolved-asteroids (cadr resolved))
                 (resolved-bullets (caddr resolved))
                 (resolved-seed (cadddr resolved))
                 (resolved-score (car (cddddr resolved)))
                 (resolved-puffs (cadr (cddddr resolved)))
                 (next-respawn (max 0 (- respawn 1)))
                 (ship-hit? (and (not game-over?) (= next-respawn 0)
                                 (any-ship-collision? next-ship-x next-ship-y resolved-asteroids))))
            (if ship-hit?
                (let ((remaining-lives (- lives 1)))
                  (play-generated-sound (sound-big-explosion 1.2 0.28))
                  (gfx-clear 6 8 18)
                  (draw-asteroids resolved-asteroids)
                  (draw-bullets resolved-bullets)
                  (draw-puffs (cons (make-puff next-ship-x next-ship-y 8.0 14) resolved-puffs))
                  (draw-hud resolved-score remaining-lives reset-cooldown (<= remaining-lives 0))
                  (gfx-flip)
                  (gfx-wait 1)
                  (loop (/ width 2.0)
                        (/ height 2.0)
                        0.0
                        0.0
                        -1.5708
                        resolved-bullets
                        resolved-asteroids
                        (cons (make-puff next-ship-x next-ship-y 8.0 14) resolved-puffs)
                        resolved-seed
                        resolved-score
                        remaining-lives
                        reset-cooldown
                        90
                        (<= remaining-lives 0)))
                        (if (null? resolved-asteroids)
                        (let* ((_ (play-generated-sound (sound-powerup 0.9 0.25)))
                           (spawned (spawn-asteroids (rand-next resolved-seed) asteroid-count))
                           (restart-seed (car spawned))
                           (restart-asteroids (cdr spawned)))
                          (gfx-clear 6 8 18)
                          (gfx-text 188 158 "FIELD CLEARED" 24)
                          (gfx-text-small 174 184 "launching a fresh game..." 29)
                          (gfx-flip)
                          (gfx-wait 30)
                          (loop (/ width 2.0)
                            (/ height 2.0)
                            0.0
                            0.0
                            -1.5708
                            '()
                            restart-asteroids
                            '()
                            restart-seed
                            0
                            3
                            0
                            90
                            #f))
                        (begin
                          (gfx-clear 6 8 18)
                          (gfx-circle 540 72 18 10)
                          (gfx-circle 540 72 10 13)
                          (draw-ship next-ship-x next-ship-y next-angle thrust? next-respawn)
                          (draw-asteroids resolved-asteroids)
                          (draw-bullets resolved-bullets)
                          (draw-puffs resolved-puffs)
                          (draw-hud resolved-score lives reset-cooldown game-over?)
                          (gfx-flip)
                          (gfx-wait 1)
                          (loop next-ship-x
                            next-ship-y
                            next-ship-dx
                            next-ship-dy
                            next-angle
                            resolved-bullets
                            resolved-asteroids
                            resolved-puffs
                            resolved-seed
                            resolved-score
                            lives
                            reset-cooldown
                            next-respawn
                            game-over?))))))))))
