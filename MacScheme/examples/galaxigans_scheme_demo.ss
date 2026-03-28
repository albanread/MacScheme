(layout-set! 'focus-graphics)
(gfx-screen 640 360 2)
(gfx-reset)
(audio-init)
(sound-volume 0.7)
(music-volume 1.0)

(define alien-victory
  (abc
    "X:1"
    "T:Alien Victory"
    "M:4/4"
    "L:1/16"
    "Q:1/4=210"
    "V:1 program=80"
    "K:Cm"
    "G,8 _B,8|c8 _e8|_e4d4c4_B4|G,16|"
    "G,4G,4_A,4_B,4|c4_e4g4_e4|c8_B8|G,16|"
    "_E4F4G4_A4|_B4c4_e4g4|fedc_BA_AG|_E16|"))

(define perc-boom
  (abc
    "X:1"
    "T:Perc Boom"
    "M:4/4"
    "L:1/16"
    "Q:1/4=200"
    "K:C"
    "%%MIDI percussion"
    "V:1"
    "[B,,D,^CA]2 z2 [B,,D,]1 z1 z10 |"))

(define saucer-wooh
  (abc
    "X:1"
    "T:Saucer Wooh"
    "M:4/4"
    "L:1/16"
    "Q:1/4=160"
    "K:C"
    "%%MIDI program 91"
    "V:1"
    "G2 z2 G2 z2 | (GABc)(cBAG) ||"))

(define you-win
  (abc
    "X:1"
    "T:You Win!"
    "M:4/4"
    "L:1/16"
    "Q:1/4=234"
    "K:C"
    "%%MIDI program 9"
    "V:1"
    "c2e2g2c'2 e'2c'2b2a2 | g2e2c2G2 c4 z4 |"
    "f2a2c'2f'2 e'2d'2c'2b2 | c'16 |"))

(define stage-alert
  (abc
    "X:1"
    "T:Stage Alert"
    "M:4/4"
    "L:1/16"
    "Q:1/4=84"
    "K:Am"
    "%%MIDI program 52"
    "V:1"
    "z8 A,4 E4 | A4 c4 e4 d4 | c8 B8 | A16 |"))

(define player-explodes
  (abc
    "X:1"
    "T:Player Explodes"
    "M:4/4"
    "L:1/16"
    "Q:1/4=180"
    "K:C"
    "%%MIDI percussion"
    "V:1"
    "[B,,D,^CA]8 [B,,D,]2 [^C]4 z2 |"))

(define alien-boom
  (abc
    "X:1"
    "T:Alien Boom"
    "M:4/4"
    "L:1/16"
    "Q:1/4=200"
    "K:C"
    "%%MIDI percussion"
    "V:1"
    "[B,,C,E]4 z12 |"))

(define saucer-death
  (abc
    "X:1"
    "T:Saucer Death"
    "M:4/4"
    "L:1/16"
    "Q:1/4=160"
    "K:C"
    "%%MIDI percussion"
    "V:1"
    "[B,,^CA]8 [B,,D,]4 ^C4 |"
    "[B,,D,]4 ^C4 [B,,]4 ^C4 |"
    "^C8 z8 |"))

(define alien-victory-id (music-load alien-victory))
(define perc-boom-id (music-load perc-boom))
(define saucer-wooh-id (music-load saucer-wooh))
(define you-win-id (music-load you-win))
(define stage-alert-id (music-load stage-alert))
(define player-explodes-id (music-load player-explodes))
(define alien-boom-id (music-load alien-boom))
(define saucer-death-id (music-load saucer-death))

; Galaxigans-inspired arcade shooter for MacScheme.
; Controls: left/right or A/D move, space fires, return starts/restarts, escape quits.

(define width 640.0)
(define height 360.0)
(define player-y 324.0)
(define player-speed 4.4)
(define player-radius 12.0)
(define enemy-rows 4)
(define enemy-cols 8)
(define enemy-spacing-x 48.0)
(define enemy-spacing-y 36.0)
(define formation-start-x 152.0)
(define formation-start-y 74.0)
(define max-player-bullets 3)
(define max-bombs 8)
(define fire-cooldown-frames 10)
(define intro-duration 110)
(define respawn-duration 90)
(define stage-clear-duration 80)

(define (clamp n lo hi)
  (max lo (min hi n)))

(define (distance-squared x1 y1 x2 y2)
  (+ (* (- x2 x1) (- x2 x1))
     (* (- y2 y1) (- y2 y1))))

(define (rand-next seed)
  (modulo (+ (* seed 1664525) 1013904223) 4294967296))

(define (rand-int seed limit)
  (let ((next (rand-next seed)))
    (cons next (if (<= limit 0) 0 (modulo next limit)))))

(define (enemy-base-x col formation-x)
  (+ formation-start-x (* col enemy-spacing-x) formation-x))

(define (enemy-base-y row formation-y)
  (+ formation-start-y (* row enemy-spacing-y) formation-y))

(define (enemy-radius row)
  (case row
    ((0) 15.0)
    ((1) 13.0)
    ((2) 11.0)
    (else 10.0)))

(define (enemy-score row)
  (case row
    ((0) 50)
    ((1) 40)
    ((2) 30)
    (else 20)))

(define (make-star x y speed colour)
  (vector x y speed colour))

(define (star-x star) (vector-ref star 0))
(define (star-y star) (vector-ref star 1))
(define (star-speed star) (vector-ref star 2))
(define (star-colour star) (vector-ref star 3))

(define (make-player-bullet x y dx dy life)
  (vector x y dx dy life))

(define (bullet-x bullet) (vector-ref bullet 0))
(define (bullet-y bullet) (vector-ref bullet 1))
(define (bullet-dx bullet) (vector-ref bullet 2))
(define (bullet-dy bullet) (vector-ref bullet 3))
(define (bullet-life bullet) (vector-ref bullet 4))

(define (make-bomb x y dx dy life)
  (vector x y dx dy life))

(define (bomb-x bomb) (vector-ref bomb 0))
(define (bomb-y bomb) (vector-ref bomb 1))
(define (bomb-dx bomb) (vector-ref bomb 2))
(define (bomb-dy bomb) (vector-ref bomb 3))
(define (bomb-life bomb) (vector-ref bomb 4))

(define (make-explosion x y radius life colour)
  (vector x y radius life colour))

(define (explosion-x exp) (vector-ref exp 0))
(define (explosion-y exp) (vector-ref exp 1))
(define (explosion-radius exp) (vector-ref exp 2))
(define (explosion-life exp) (vector-ref exp 3))
(define (explosion-colour exp) (vector-ref exp 4))

(define (make-saucer x y dx hits cooldown)
  (vector x y dx hits cooldown))

(define (saucer-x saucer) (vector-ref saucer 0))
(define (saucer-y saucer) (vector-ref saucer 1))
(define (saucer-dx saucer) (vector-ref saucer 2))
(define (saucer-hits saucer) (vector-ref saucer 3))
(define (saucer-cooldown saucer) (vector-ref saucer 4))

(define (make-enemy row col mode x y t target-col)
  (vector row col mode x y t target-col))

(define (enemy-row enemy) (vector-ref enemy 0))
(define (enemy-col enemy) (vector-ref enemy 1))
(define (enemy-mode enemy) (vector-ref enemy 2))
(define (enemy-x enemy) (vector-ref enemy 3))
(define (enemy-y enemy) (vector-ref enemy 4))
(define (enemy-t enemy) (vector-ref enemy 5))
(define (enemy-target-col enemy) (vector-ref enemy 6))

(define (enemy-formation? enemy)
  (eq? (enemy-mode enemy) 'formation))

(define (enemy-dive? enemy)
  (eq? (enemy-mode enemy) 'dive))

(define (enemy-return? enemy)
  (eq? (enemy-mode enemy) 'return))

(define (enemy-position enemy formation-x formation-y)
  (if (enemy-formation? enemy)
    (cons (enemy-base-x (enemy-col enemy) formation-x)
          (enemy-base-y (enemy-row enemy) formation-y))
    (cons (enemy-x enemy) (enemy-y enemy))))

(define (build-enemies)
  (let outer ((row 0) (items '()))
    (if (= row enemy-rows)
      items
      (let inner ((col 0) (row-items items))
        (if (= col enemy-cols)
          (outer (+ row 1) row-items)
          (inner (+ col 1)
                 (cons (make-enemy row col 'formation 0.0 0.0 0.0 col) row-items)))))))

(define (build-stars seed count)
  (let loop ((n count) (seed seed) (items '()))
    (if (= n 0)
      (cons seed items)
      (let* ((x-rv (rand-int seed 640))
             (seed-1 (car x-rv))
             (y-rv (rand-int seed-1 360))
             (seed-2 (car y-rv))
             (speed-rv (rand-int seed-2 3))
             (seed-3 (car speed-rv))
             (colour-rv (rand-int seed-3 3))
             (seed-4 (car colour-rv)))
        (loop (- n 1)
              seed-4
              (cons (make-star (exact->inexact (cdr x-rv))
                               (exact->inexact (cdr y-rv))
                               (+ 0.5 (exact->inexact (cdr speed-rv)))
                               (+ 28 (cdr colour-rv)))
                    items))))))

(define (update-stars stars)
  (if (null? stars)
    '()
    (let* ((star (car stars))
           (next-y (+ (star-y star) (star-speed star)))
           (wrapped-y (if (> next-y height) 0.0 next-y)))
      (cons (make-star (star-x star) wrapped-y (star-speed star) (star-colour star))
            (update-stars (cdr stars))))))

(define (draw-stars stars)
  (if (null? stars)
    0
    (begin
      (let ((star (car stars)))
        (gfx-pset (star-x star) (star-y star) (star-colour star)))
      (draw-stars (cdr stars)))))

(define (draw-player x invuln frame)
  (if (or (= invuln 0) (< (modulo frame 8) 4))
    (begin
      (gfx-triangle x (- player-y 14) (- x 12) (+ player-y 10) (+ x 12) (+ player-y 10) 22)
      (gfx-triangle x (- player-y 8) (- x 8) (+ player-y 6) (+ x 8) (+ player-y 6) 29)
      (gfx-line (- x 14) (+ player-y 8) (- x 20) (+ player-y 13) 24)
      (gfx-line (+ x 14) (+ player-y 8) (+ x 20) (+ player-y 13) 24)
      (gfx-rect (- x 2) (+ player-y 1) 4 7 31))
    0))

(define (draw-bullets bullets)
  (if (null? bullets)
    0
    (begin
      (let ((bullet (car bullets)))
        (gfx-line (bullet-x bullet)
                  (+ (bullet-y bullet) 6)
                  (bullet-x bullet)
                  (bullet-y bullet)
                  21))
      (draw-bullets (cdr bullets)))))

(define (draw-bombs bombs)
  (if (null? bombs)
    0
    (begin
      (let ((bomb (car bombs)))
        (gfx-circle (bomb-x bomb) (bomb-y bomb) 3 24)
        (gfx-circle (bomb-x bomb) (bomb-y bomb) 1 30))
      (draw-bombs (cdr bombs)))))

(define (draw-explosions explosions)
  (if (null? explosions)
    0
    (begin
      (let ((exp (car explosions)))
        (gfx-circle-outline (explosion-x exp)
                            (explosion-y exp)
                            (explosion-radius exp)
                            (explosion-colour exp)))
      (draw-explosions (cdr explosions)))))

(define (draw-enemy-shape row x y flap)
  (case row
    ((0)
     (gfx-ellipse x y 16 10 19)
     (gfx-ellipse-outline x y 18 12 31)
     (gfx-rect (- x 10) (- y 2) 20 9 28)
     (gfx-line (- x 14) (+ y 2) (- x 20) (+ y (if flap 10 6)) 24)
     (gfx-line (+ x 14) (+ y 2) (+ x 20) (+ y (if flap 10 6)) 24)
     (gfx-rect (- x 3) (- y 7) 6 5 30))
    ((1)
     (gfx-triangle x (- y 12) (- x 15) (+ y 8) (+ x 15) (+ y 8) 23)
     (gfx-triangle x (- y 8) (- x 10) (+ y 5) (+ x 10) (+ y 5) 29)
     (gfx-line (- x 12) y (- x 18) (+ y (if flap 8 4)) 30)
     (gfx-line (+ x 12) y (+ x 18) (+ y (if flap 8 4)) 30)
     (gfx-rect (- x 2) (- y 4) 4 10 31))
    ((2)
     (gfx-circle x y 10 20)
     (gfx-circle-outline x y 12 31)
     (gfx-line (- x 10) (- y 2) (- x 16) (+ y (if flap 8 3)) 29)
     (gfx-line (+ x 10) (- y 2) (+ x 16) (+ y (if flap 8 3)) 29)
     (gfx-rect (- x 2) (- y 9) 4 5 30))
    (else
     (gfx-ellipse x y 11 8 18)
     (gfx-ellipse-outline x y 13 10 31)
     (gfx-line (- x 8) (+ y 4) (- x 14) (+ y (if flap 9 5)) 22)
     (gfx-line (+ x 8) (+ y 4) (+ x 14) (+ y (if flap 9 5)) 22)
     (gfx-line x (- y 8) x (+ y 7) 30))))

(define (draw-enemies enemies formation-x formation-y frame)
  (if (null? enemies)
    0
    (begin
      (let* ((enemy (car enemies))
             (pos (enemy-position enemy formation-x formation-y))
             (x (car pos))
             (y (cdr pos))
             (flap (< (modulo (+ frame (* 3 (enemy-row enemy)) (enemy-col enemy)) 16) 8)))
        (draw-enemy-shape (enemy-row enemy) x y flap))
      (draw-enemies (cdr enemies) formation-x formation-y frame))))

(define (draw-saucer saucer frame)
  (if saucer
    (let ((x (saucer-x saucer))
          (y (saucer-y saucer))
          (blink (< (modulo frame 12) 6)))
      (gfx-ellipse x y 24 10 27)
      (gfx-ellipse-outline x y 26 12 31)
      (gfx-rect (- x 14) (- y 2) 28 8 25)
      (gfx-circle (- x 10) y 3 (if blink 21 30))
      (gfx-circle x y 3 (if blink 22 30))
      (gfx-circle (+ x 10) y 3 (if blink 24 30)))
    0))

(define (count-list items)
  (if (null? items) 0 (+ 1 (count-list (cdr items)))))

(define (update-bullets bullets)
  (if (null? bullets)
    '()
    (let* ((bullet (car bullets))
           (next-life (- (bullet-life bullet) 1))
           (next-x (+ (bullet-x bullet) (bullet-dx bullet)))
           (next-y (+ (bullet-y bullet) (bullet-dy bullet)))
           (rest (update-bullets (cdr bullets))))
      (if (or (<= next-life 0) (< next-y -12.0) (< next-x -12.0) (> next-x (+ width 12.0)))
        rest
        (cons (make-player-bullet next-x next-y (bullet-dx bullet) (bullet-dy bullet) next-life)
              rest)))))

(define (update-bombs bombs)
  (if (null? bombs)
    '()
    (let* ((bomb (car bombs))
           (next-life (- (bomb-life bomb) 1))
           (next-x (+ (bomb-x bomb) (bomb-dx bomb)))
           (next-y (+ (bomb-y bomb) (bomb-dy bomb)))
           (rest (update-bombs (cdr bombs))))
      (if (or (<= next-life 0) (> next-y (+ height 14.0)) (< next-x -20.0) (> next-x (+ width 20.0)))
        rest
        (cons (make-bomb next-x next-y (bomb-dx bomb) (+ (bomb-dy bomb) 0.05) next-life)
              rest)))))

(define (update-explosions explosions)
  (if (null? explosions)
    '()
    (let* ((exp (car explosions))
           (next-life (- (explosion-life exp) 1))
           (rest (update-explosions (cdr explosions))))
      (if (<= next-life 0)
        rest
        (cons (make-explosion (explosion-x exp)
                              (explosion-y exp)
                              (+ (explosion-radius exp) 1.5)
                              next-life
                              (explosion-colour exp))
              rest)))))

(define (count-divers enemies)
  (if (null? enemies)
    0
    (+ (if (enemy-dive? (car enemies)) 1 0)
       (count-divers (cdr enemies)))))

(define (front-row enemies)
  (let loop ((items enemies) (best -1))
    (if (null? items)
      best
      (let ((enemy (car items)))
        (if (enemy-formation? enemy)
          (loop (cdr items) (max best (enemy-row enemy)))
          (loop (cdr items) best))))))

(define (front-row-candidates enemies row)
  (if (null? enemies)
    '()
    (let ((enemy (car enemies)))
      (if (and (= (enemy-row enemy) row) (enemy-formation? enemy))
        (cons enemy (front-row-candidates (cdr enemies) row))
        (front-row-candidates (cdr enemies) row)))))

(define (replace-one-enemy enemies original replacement)
  (if (null? enemies)
    '()
    (if (eq? (car enemies) original)
      (cons replacement (cdr enemies))
      (cons (car enemies) (replace-one-enemy (cdr enemies) original replacement)))))

(define (maybe-launch-diver enemies formation-x formation-y frame stage seed)
  (if (or (< (count-divers enemies) (min 3 (+ 1 (quotient stage 2))))
          #t)
    (let* ((rv (rand-int seed 100))
           (next-seed (car rv))
           (threshold (cdr rv))
           (launch-rate (max 10 (- 28 (* stage 2)))))
      (if (and (= (modulo frame 12) 0) (< threshold launch-rate))
        (let* ((row (front-row enemies))
               (candidates (front-row-candidates enemies row)))
          (if (null? candidates)
            (cons next-seed enemies)
            (let* ((pick-rv (rand-int next-seed (count-list candidates)))
                   (seed-2 (car pick-rv))
                   (picked (list-ref candidates (cdr pick-rv)))
                   (x (enemy-base-x (enemy-col picked) formation-x))
                   (y (enemy-base-y (enemy-row picked) formation-y))
                   (replacement (make-enemy (enemy-row picked)
                                            (enemy-col picked)
                                            'dive
                                            x
                                            y
                                            0.0
                                            (enemy-col picked))))
              (cons seed-2 (replace-one-enemy enemies picked replacement)))) )
        (cons next-seed enemies)))
    (cons seed enemies)))

(define (update-enemy enemy formation-x formation-y)
  (cond
    ((enemy-formation? enemy)
     enemy)
    ((enemy-dive? enemy)
     (let* ((next-t (+ (enemy-t enemy) 1.0))
            (curve (+ (* 3.0 (sin (+ (* next-t 0.19) (* (enemy-col enemy) 0.45))))
                      (* 1.2 (sin (* next-t 0.07)))))
            (next-x (+ (enemy-x enemy) curve))
            (next-y (+ (enemy-y enemy) (+ 2.6 (* 0.18 (enemy-row enemy))))) )
       (if (> next-y (+ height 26.0))
         (make-enemy (enemy-row enemy) (enemy-col enemy) 'return next-x -18.0 0.0 (enemy-target-col enemy))
         (make-enemy (enemy-row enemy) (enemy-col enemy) 'dive next-x next-y next-t (enemy-target-col enemy)))))
    (else
     (let* ((target-x (enemy-base-x (enemy-target-col enemy) formation-x))
            (target-y (enemy-base-y (enemy-row enemy) formation-y))
            (dx (- target-x (enemy-x enemy)))
            (dy (- target-y (enemy-y enemy)))
            (next-x (+ (enemy-x enemy) (* dx 0.16)))
            (next-y (+ (enemy-y enemy) (* dy 0.16))))
       (if (< (distance-squared next-x next-y target-x target-y) 18.0)
         (make-enemy (enemy-row enemy) (enemy-target-col enemy) 'formation 0.0 0.0 0.0 (enemy-target-col enemy))
         (make-enemy (enemy-row enemy) (enemy-col enemy) 'return next-x next-y 0.0 (enemy-target-col enemy)))))))

(define (update-enemies-list enemies formation-x formation-y)
  (if (null? enemies)
    '()
    (cons (update-enemy (car enemies) formation-x formation-y)
          (update-enemies-list (cdr enemies) formation-x formation-y))))

(define (next-formation formation-x formation-y formation-dir)
  (let* ((trial-x (+ formation-x (* 1.5 formation-dir)))
         (left (enemy-base-x 0 trial-x))
         (right (enemy-base-x (- enemy-cols 1) trial-x)))
    (if (> right 600.0)
      (list formation-x (+ formation-y 10.0) -1)
      (if (< left 40.0)
        (list formation-x (+ formation-y 10.0) 1)
        (list trial-x formation-y formation-dir)))))

(define (bomb-source-candidates enemies formation-x formation-y)
  (if (null? enemies)
    '()
    (let* ((enemy (car enemies))
           (pos (enemy-position enemy formation-x formation-y))
           (x (car pos))
           (y (cdr pos))
           (ok? (or (enemy-dive? enemy)
                    (and (enemy-formation? enemy) (> y 150.0)))))
      (if ok?
        (cons (cons x y) (bomb-source-candidates (cdr enemies) formation-x formation-y))
        (bomb-source-candidates (cdr enemies) formation-x formation-y)))))

(define (maybe-spawn-bomb bombs enemies formation-x formation-y stage frame seed)
  (if (>= (count-list bombs) max-bombs)
    (cons seed bombs)
    (let* ((rv (rand-int seed 100))
           (seed-1 (car rv))
           (chance (cdr rv))
           (limit (min 26 (+ 6 (* stage 2)))))
      (if (and (= (modulo frame 8) 0) (< chance limit))
        (let ((sources (bomb-source-candidates enemies formation-x formation-y)))
          (if (null? sources)
            (cons seed-1 bombs)
            (let* ((pick-rv (rand-int seed-1 (count-list sources)))
                   (seed-2 (car pick-rv))
                   (picked (list-ref sources (cdr pick-rv)))
                   (dx-rv (rand-int seed-2 7))
                   (seed-3 (car dx-rv))
                   (bomb (make-bomb (car picked)
                                    (+ (cdr picked) 8.0)
                                    (- (/ (exact->inexact (cdr dx-rv)) 3.0) 1.0)
                                    (+ 2.0 (* stage 0.15))
                                    180)))
                    (play-generated-sound (sound-click 0.8 0.03))
              (cons seed-3 (cons bomb bombs)))))
        (cons seed-1 bombs)))))

(define (hit-enemy? bullet enemy formation-x formation-y)
  (let* ((pos (enemy-position enemy formation-x formation-y))
         (x (car pos))
         (y (cdr pos))
         (r (+ 4.0 (enemy-radius (enemy-row enemy)))))
    (< (distance-squared (bullet-x bullet) (bullet-y bullet) x y) (* r r))))

(define (hit-saucer? bullet saucer)
  (if (not saucer)
    #f
    (< (distance-squared (bullet-x bullet) (bullet-y bullet) (saucer-x saucer) (saucer-y saucer))
       (* 18.0 18.0))))

(define (play-generated-sound sound-id)
  (if (> sound-id 0)
      (sound-play sound-id)
      0))

(define (process-bullet-hit-enemies bullet enemies formation-x formation-y)
  (if (null? enemies)
    (values #f '() 0 '())
    (let ((enemy (car enemies)))
      (if (hit-enemy? bullet enemy formation-x formation-y)
        (let* ((pos (enemy-position enemy formation-x formation-y))
               (row (enemy-row enemy)))
          (music-play-id alien-boom-id 0.9)
          (play-generated-sound (sound-explode 0.95 0.12))
          (values #t
                  (cdr enemies)
                  (enemy-score row)
                  (list (make-explosion (car pos) (cdr pos) 6.0 12 (+ 24 row)))))
        (call-with-values
          (lambda () (process-bullet-hit-enemies bullet (cdr enemies) formation-x formation-y))
          (lambda (hit? rest score gained-explosions)
            (values hit?
                    (cons enemy rest)
                    score
                    gained-explosions)))))))

(define (process-bullets bullets enemies formation-x formation-y saucer score explosions stage)
  (if (null? bullets)
    (values '() enemies saucer score explosions)
    (let ((bullet (car bullets)))
      (if (hit-saucer? bullet saucer)
        (let* ((hits-left (- (saucer-hits saucer) 1))
               (new-explosions (cons (make-explosion (bullet-x bullet) (bullet-y bullet) 5.0 10 30) explosions)))
          (if (<= hits-left 0)
            (begin
              (music-play-id saucer-death-id 1.0)
              (play-generated-sound (sound-big-explosion 1.0 0.18))
              (call-with-values
                (lambda () (process-bullets (cdr bullets) enemies formation-x formation-y #f (+ score (+ 150 (* stage 25)))
                                            (cons (make-explosion (saucer-x saucer) (saucer-y saucer) 10.0 16 24) new-explosions)
                                            stage))
                (lambda (rest-bullets next-enemies next-saucer next-score next-explosions)
                  (values rest-bullets next-enemies next-saucer next-score next-explosions))))
            (begin
              (play-generated-sound (sound-click 1.2 0.05))
              (call-with-values
                (lambda () (process-bullets (cdr bullets) enemies formation-x formation-y
                                            (make-saucer (saucer-x saucer) (saucer-y saucer) (saucer-dx saucer) hits-left (saucer-cooldown saucer))
                                            (+ score 25)
                                            new-explosions
                                            stage))
                (lambda (rest-bullets next-enemies next-saucer next-score next-explosions)
                  (values rest-bullets next-enemies next-saucer next-score next-explosions))))))
        (call-with-values
          (lambda () (process-bullet-hit-enemies bullet enemies formation-x formation-y))
          (lambda (hit? next-enemies gained-score gained-explosions)
            (if hit?
              (call-with-values
                (lambda () (process-bullets (cdr bullets) next-enemies formation-x formation-y saucer (+ score gained-score)
                                            (append gained-explosions explosions)
                                            stage))
                (lambda (rest-bullets final-enemies final-saucer final-score final-explosions)
                  (values rest-bullets final-enemies final-saucer final-score final-explosions)))
              (call-with-values
                (lambda () (process-bullets (cdr bullets) enemies formation-x formation-y saucer score explosions stage))
                (lambda (rest-bullets final-enemies final-saucer final-score final-explosions)
                  (values (cons bullet rest-bullets) final-enemies final-saucer final-score final-explosions))))))))))

(define (bomb-hit-player? bomb player-x)
  (< (distance-squared (bomb-x bomb) (bomb-y bomb) player-x player-y)
     (* (+ player-radius 5.0) (+ player-radius 5.0))))

(define (enemy-hit-player? enemies formation-x formation-y player-x)
  (if (null? enemies)
    #f
    (let* ((enemy (car enemies))
           (pos (enemy-position enemy formation-x formation-y))
           (x (car pos))
           (y (cdr pos))
           (r (+ player-radius (enemy-radius (enemy-row enemy)))))
      (or (< (distance-squared x y player-x player-y) (* r r))
          (enemy-hit-player? (cdr enemies) formation-x formation-y player-x)))))

(define (resolve-bombs-vs-player bombs player-x invuln explosions)
  (if (null? bombs)
    (values bombs #f explosions)
    (let ((bomb (car bombs)))
      (if (and (= invuln 0) (bomb-hit-player? bomb player-x))
        (begin
          (music-play-id player-explodes-id 1.0)
          (play-generated-sound (sound-big-explosion 0.95 0.15))
          (values (cdr bombs)
                  #t
                  (cons (make-explosion player-x player-y 8.0 16 24) explosions)))
        (call-with-values
          (lambda () (resolve-bombs-vs-player (cdr bombs) player-x invuln explosions))
          (lambda (rest hit? next-explosions)
            (values (cons bomb rest) hit? next-explosions)))))))

(define (update-saucer saucer frame seed stage)
  (if saucer
    (let* ((next-x (+ (saucer-x saucer) (saucer-dx saucer)))
           (next-cooldown (max 0 (- (saucer-cooldown saucer) 1))))
      (if (or (< next-x -40.0) (> next-x (+ width 40.0)))
        (values #f seed '())
        (if (and (= next-cooldown 0) (= (modulo frame 20) 0))
          (begin
            (play-generated-sound (sound-click 0.6 0.02))
            (values (make-saucer next-x (saucer-y saucer) (saucer-dx saucer) (saucer-hits saucer) (+ 22 (quotient stage 2)))
                    seed
                    (list (make-bomb next-x (+ (saucer-y saucer) 8.0) 0.0 (+ 2.2 (* stage 0.1)) 160))))
          (values (make-saucer next-x (saucer-y saucer) (saucer-dx saucer) (saucer-hits saucer) next-cooldown)
                  seed
                  '()))))
    (let* ((rv (rand-int seed 1000))
           (seed-1 (car rv))
           (chance (cdr rv)))
      (if (< chance 5)
        (let* ((dir-rv (rand-int seed-1 2))
               (seed-2 (car dir-rv))
               (from-left? (= (cdr dir-rv) 0)))
          (music-play-id saucer-wooh-id 0.9)
          (values (if from-left?
                    (make-saucer -26.0 42.0 2.2 2 (+ 24 stage))
                    (make-saucer (+ width 26.0) 42.0 -2.2 2 (+ 24 stage)))
                  seed-2
                  '()))
        (values #f seed-1 '())))))

(define (draw-hud state stage score lives bullets-left intro-timer)
  (gfx-rect 0 0 640 28 17)
  (gfx-text-small 10 8
                  (string-append "score " (number->string score)
                                 "   ships " (number->string lives)
                                 "   stage " (number->string stage)
                                 "   shots " (number->string bullets-left))
                  30)
  (cond
    ((eq? state 'intro)
     (gfx-text 172 110 "GALAXIGANS SCHEME" 31)
     (gfx-text-small 142 140 "classic formation shooter inspired by the Ed-BASIC demo" 29)
     (gfx-text-small 182 166 "left/right move   space fire" 30)
     (gfx-text-small 196 186 "press return to launch" (if (< (modulo intro-timer 24) 12) 21 30)))
    ((eq? state 'stage-clear)
     (gfx-text 232 140 "WAVE CLEAR" 21)
     (gfx-text-small 202 166 "next formation dropping in..." 30))
    ((eq? state 'game-over)
     (gfx-text 226 140 "GAME OVER" 24)
     (gfx-text-small 160 166 "press return to start over or escape to quit" 30))
    (else 0)))

(define initial-seed 90210)

(let* ((stars-built (build-stars initial-seed 42))
       (seed (car stars-built))
       (stars (cdr stars-built)))
  (let loop ((frame 0)
             (state 'intro)
             (state-timer intro-duration)
             (stage 1)
             (score 0)
             (lives 3)
             (player-x 320.0)
             (invuln 0)
             (cooldown 0)
             (fire-held #f)
             (formation-x 0.0)
             (formation-y 0.0)
             (formation-dir 1)
             (enemies (build-enemies))
             (bullets '())
             (bombs '())
             (explosions '())
             (stars stars)
             (saucer #f)
             (seed seed))
    (let* ((pressed-key (gfx-read-key))
           (left? (or (gfx-key-pressed? 'left) (gfx-key-pressed? 'a)))
           (right? (or (gfx-key-pressed? 'right) (gfx-key-pressed? 'd)))
           (fire? (gfx-key-pressed? 'space))
           (start? (or (eq? pressed-key 'return) (eq? pressed-key 'enter))))
      (if (or (eq? pressed-key 'escape) (eq? pressed-key 'esc) (not (gfx-active?)))
        'done
        (let* ((next-stars (update-stars stars))
               (next-explosions (update-explosions explosions))
               (bullets-left (- max-player-bullets (count-list bullets))))
          (cond
            ((eq? state 'intro)
             (gfx-clear 4 8 22)
             (draw-stars next-stars)
             (draw-enemies enemies formation-x formation-y frame)
             (draw-player player-x 0 frame)
             (draw-hud 'intro stage score lives bullets-left state-timer)
             (gfx-flip)
             (gfx-wait 1)
             (gfx-vsync)
             (if start?
               (begin
                 (music-stop)
                 (music-play-id stage-alert-id 0.9)
                 (loop (+ frame 1) 'playing 0 1 0 3 320.0 respawn-duration 0 fire? 0.0 0.0 1 (build-enemies) '() '() '() next-stars #f seed))
               (loop (+ frame 1) 'intro (max 0 (- state-timer 1)) stage score lives player-x invuln cooldown fire? formation-x formation-y formation-dir enemies bullets bombs next-explosions next-stars saucer seed)))
            ((eq? state 'stage-clear)
             (gfx-clear 4 8 22)
             (draw-stars next-stars)
             (draw-explosions next-explosions)
             (draw-player player-x invuln frame)
             (draw-hud 'stage-clear stage score lives bullets-left state-timer)
             (gfx-flip)
             (gfx-wait 1)
             (gfx-vsync)
             (if (<= state-timer 0)
               (begin
                 (music-stop)
                 (music-play-id stage-alert-id 0.9)
                 (loop (+ frame 1) 'playing 0 (+ stage 1) score lives player-x respawn-duration 0 fire? 0.0 0.0 1 (build-enemies) '() '() '() next-stars #f seed))
               (loop (+ frame 1) 'stage-clear (- state-timer 1) stage score lives player-x invuln cooldown fire? formation-x formation-y formation-dir enemies bullets bombs next-explosions next-stars saucer seed)))
            ((eq? state 'game-over)
             (gfx-clear 4 8 22)
             (draw-stars next-stars)
             (draw-explosions next-explosions)
             (draw-hud 'game-over stage score 0 bullets-left state-timer)
             (gfx-flip)
             (gfx-wait 1)
             (gfx-vsync)
             (if start?
               (begin
                 (music-stop)
                 (music-play-id stage-alert-id 0.9)
                 (loop (+ frame 1) 'playing 0 1 0 3 320.0 respawn-duration 0 fire? 0.0 0.0 1 (build-enemies) '() '() '() next-stars #f seed))
               (loop (+ frame 1) 'game-over state-timer stage score lives player-x invuln cooldown fire? formation-x formation-y formation-dir enemies bullets bombs next-explosions next-stars saucer seed)))
            (else
             (let* ((next-player-x (clamp (+ player-x (if left? (- player-speed) 0.0) (if right? player-speed 0.0)) 24.0 616.0))
                    (next-invuln (max 0 (- invuln 1)))
                    (next-cooldown (max 0 (- cooldown 1)))
                    (spawn-bullet? (and fire? (not fire-held) (= next-cooldown 0) (< (count-list bullets) max-player-bullets)))
                    (shot-bullets (if spawn-bullet?
                                    (begin
                                      (music-play-id perc-boom-id 0.65)
                                      (play-generated-sound (sound-shoot 0.9 0.06))
                                      (cons (make-player-bullet next-player-x (- player-y 18.0) 0.0 -6.8 90) bullets))
                                    bullets))
                    (shot-cooldown (if spawn-bullet? fire-cooldown-frames next-cooldown))
                    (updated-bullets (update-bullets shot-bullets))
                    (updated-bombs (update-bombs bombs))
                    (formation-step (next-formation formation-x formation-y formation-dir))
                    (step-x (list-ref formation-step 0))
                    (step-y (list-ref formation-step 1))
                    (step-dir (list-ref formation-step 2))
                    (launched (maybe-launch-diver enemies step-x step-y frame stage seed))
                    (seed-1 (car launched))
                    (launched-enemies (cdr launched))
                    (moved-enemies (update-enemies-list launched-enemies step-x step-y))
                    (bomb-spawned (maybe-spawn-bomb updated-bombs moved-enemies step-x step-y stage frame seed-1))
                    (seed-2 (car bomb-spawned))
                    (more-bombs (cdr bomb-spawned)))
               (call-with-values
                 (lambda () (update-saucer saucer frame seed-2 stage))
                 (lambda (next-saucer seed-3 saucer-bombs)
                   (call-with-values
                     (lambda () (process-bullets updated-bullets moved-enemies step-x step-y next-saucer score next-explosions stage))
                     (lambda (final-bullets final-enemies final-saucer final-score final-explosions)
                       (call-with-values
                         (lambda () (resolve-bombs-vs-player (append saucer-bombs more-bombs) next-player-x next-invuln final-explosions))
                         (lambda (final-bombs bomb-hit? bomb-explosions)
                           (let ((enemy-hit? (and (= next-invuln 0) (enemy-hit-player? final-enemies step-x step-y next-player-x))))
                             (cond
                               ((or bomb-hit? enemy-hit?)
                                (let ((remaining-lives (- lives 1)))
                                  (if enemy-hit? (music-play-id player-explodes-id 1.0) 0)
                                  (gfx-clear 4 8 22)
                                  (draw-stars next-stars)
                                  (draw-enemies final-enemies step-x step-y frame)
                                  (draw-bullets final-bullets)
                                  (draw-bombs final-bombs)
                                  (draw-explosions bomb-explosions)
                                  (draw-saucer final-saucer frame)
                                  (draw-hud 'playing stage final-score remaining-lives (- max-player-bullets (count-list final-bullets)) 0)
                                  (gfx-flip)
                                  (gfx-wait 1)
                                  (gfx-vsync)
                                  (if (<= remaining-lives 0)
                                    (begin
                                      (music-stop)
                                      (music-play-id alien-victory-id 1.0)
                                      (loop (+ frame 1) 'game-over 0 stage final-score 0 320.0 0 0 fire? step-x step-y step-dir final-enemies final-bullets final-bombs bomb-explosions next-stars final-saucer seed-3))
                                    (loop (+ frame 1) 'playing 0 stage final-score remaining-lives 320.0 respawn-duration shot-cooldown fire? step-x step-y step-dir final-enemies final-bullets final-bombs bomb-explosions next-stars final-saucer seed-3))))
                               ((null? final-enemies)
                                (music-stop)
                                (music-play-id you-win-id 1.0)
                                (play-generated-sound (sound-powerup 0.9 0.2))
                                (gfx-clear 4 8 22)
                                (draw-stars next-stars)
                                (draw-explosions bomb-explosions)
                                (draw-player next-player-x next-invuln frame)
                                (draw-hud 'stage-clear stage final-score lives (- max-player-bullets (count-list final-bullets)) stage-clear-duration)
                                (gfx-flip)
                                (gfx-wait 1)
                                (gfx-vsync)
                                (loop (+ frame 1) 'stage-clear stage-clear-duration stage final-score lives next-player-x next-invuln shot-cooldown fire? step-x step-y step-dir final-enemies final-bullets final-bombs bomb-explosions next-stars final-saucer seed-3))
                               (else
                                (gfx-clear 4 8 22)
                                (draw-stars next-stars)
                                (draw-enemies final-enemies step-x step-y frame)
                                (draw-player next-player-x next-invuln frame)
                                (draw-bullets final-bullets)
                                (draw-bombs final-bombs)
                                (draw-explosions bomb-explosions)
                                (draw-saucer final-saucer frame)
                                (draw-hud 'playing stage final-score lives (- max-player-bullets (count-list final-bullets)) 0)
                                (gfx-flip)
                                (gfx-wait 1)
                                (gfx-vsync)
                                (loop (+ frame 1) 'playing 0 stage final-score lives next-player-x next-invuln shot-cooldown fire? step-x step-y step-dir final-enemies final-bullets final-bombs bomb-explosions next-stars final-saucer seed-3))))))))))))))))))
