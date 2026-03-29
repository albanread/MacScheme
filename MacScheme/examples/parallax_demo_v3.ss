(layout-set! 'focus-graphics)
(gfx-screen 720 480 1)
(gfx-reset)
(audio-init)
(sound-volume 0.65)
(music-volume 0.55)

;;; Parallax Demo V3
;;; -----------------------------------------------------------------------
;;; Double-buffered: buffers 0 and 1 alternate as back buffer each frame
;;; so we never draw to the visible surface (fixes flicker).
;;;   Buffer 2 : pre-rendered static background (sky + ground gradients)
;;;   Buffer 3 : pre-rendered far building strip  (buf-w wide, transparent)
;;;   Buffer 4 : pre-rendered near building strip (buf-w wide, transparent)
;;; Hardware sprites:
;;;   Def 0 / Inst 0   : large fighter plane (64x32) – player
;;;   Def 1 / Inst 1-4 : large UFO enemies (48x48) – 4 colour variants
;;;   Def 2-4          : palette holder defs (1x1) for UFO colour variants
;;;   Def 5 / Inst 5-8 : ground crawler aliens (48x48, 6-frame walk cycle)
;;; Controls: WASD / Arrows = move   Space = boost   Z/X = fire   Escape = quit
;;; -----------------------------------------------------------------------

(define screen-w 720)
(define screen-h 480)
(define buf-w (gfx-buffer-width))
(define ground-y 330)
(define ship-max-y (- ground-y 18.0))

(define (play-generated-sound sound-id)
  (if (> sound-id 0)
      (sound-play sound-id)
      0))

(define alien-shot-sound-id (sound-shoot 0.78 0.08))
(define player-shot-sound-id (sound-shoot 1.15 0.05))
(define player-explode-sound-id (sound-big-explosion 1.05 0.20))
(define player-respawn-sound-id (sound-powerup 0.82 0.18))
(define saucer-explode-sound-id (sound-explode 0.62 0.10))
(define fire-saucer-explode-sound-id (sound-big-explosion 0.78 0.12))
(define acid-saucer-explode-sound-id (sound-explode 0.42 0.16))
(define gold-saucer-explode-sound-id (sound-explode 0.88 0.08))
(define crawler-explode-sound-id (sound-big-explosion 0.92 0.17))
(define orbiter-explode-sound-id (sound-explode 0.70 0.11))
(define boss-hit-sound-id (sound-big-explosion 0.62 0.10))
(define boss-explode-sound-id (sound-big-explosion 1.35 0.28))

(define saucer-score 100)
(define crawler-score 150)
(define boss-score 2000)
(define boss-hit-points 7)
(define boss-trigger-score 2500)
(define boss-trigger-min-frame 4500)
(define boss-trigger-max-frame 6000)
(define boss-inst 36)

(define game-start-theme
  (abc
    "X:1"
    "T:Parallax Patrol"
    "M:4/4"
    "L:1/16"
    "Q:1/4=188"
    "K:Em"
    "V:1 name=Lead program=81"
    "V:2 name=Bass program=39"
    "[V:1] e2g2 b2e'2 d'2b2 a2g2 | e'2d'2 b2a2 g2f#2 e2b2 | e2g2 b2e'2 d'2b2 a2g2 | b2a2 g2f#2 e4 z4 |"
    "[V:2] E,2B,,2 E,2B,,2 G,,2D,2 G,,2D,2 | E,2B,,2 E,2B,,2 C,2G,,2 B,,2F,,2 | E,2B,,2 E,2B,,2 G,,2D,2 G,,2D,2 | E,2B,,2 E,2B,,2 E,4 z4 |"))

(define game-start-theme-id (music-load game-start-theme))
(define boss-theme
  (abc
    "X:2"
    "T:Mothership Descent"
    "M:4/4"
    "L:1/16"
    "Q:1/4=126"
    "K:Em"
    "V:1 name=Lead program=81"
    "V:2 name=Bass program=39"
    "V:3 name=Pulse program=95"
    "[V:1] e2 z2 e2 g2 b2 g2 f#2 e2 | d2 z2 d2 f#2 a2 f#2 e2 d2 | e2 z2 e2 g2 b2 a2 g2 f#2 | e4 z4 e2 d2 b,4 z4 |"
    "[V:2] E,4 B,,4 E,4 B,,4 | D,4 A,,4 D,4 A,,4 | C,4 G,,4 B,,4 F,,4 | E,4 B,,4 E,4 z4 |"
    "[V:3] z8 b,,2 z2 b,,2 z2 | z8 a,,2 z2 a,,2 z2 | z8 g,,2 z2 f#,,2 z2 | e,,2 e,,2 z4 e,,2 z2 z4 |"))

(define boss-victory-theme
  (abc
    "X:3"
    "T:Alien Victory Parade"
    "M:4/4"
    "L:1/16"
    "Q:1/4=148"
    "K:Em"
    "V:1 name=Lead program=81"
    "V:2 name=Bass program=39"
    "V:3 name=Spark program=95"
    "[V:1] e2 e2 g2 b2 e'2 d'2 b2 g2 | a2 a2 c'2 b2 a2 g2 e2 z2 | b2 b2 d'2 e'2 d'2 b2 g2 e2 | e'2 d'2 b2 g2 e4 z4 |"
    "[V:2] E,4 E,4 G,4 G,4 | A,4 A,4 C4 B,4 | G,4 G,4 D4 E4 | E,4 B,,4 E,4 z4 |"
    "[V:3] z4 e'2 z2 e'2 z2 | z4 d'2 z2 d'2 z2 | z4 g'2 z2 f#'2 z2 | e'2 z2 e'2 z2 b2 z2 z4 |"))

(define boss-theme-id (music-load boss-theme))
(define boss-victory-theme-id (music-load boss-victory-theme))
(music-play-id game-start-theme-id)

;;; ---- Palette Setup ----
;; Gradient: sky (index 2) and ground (index 3)
(gfx-pal-gradient 0 2 0 ground-y 28 70 210 140 200 255)
(gfx-pal-gradient 1 3 ground-y screen-h 22 95 22 4 40 4)

;; Far buildings – soft pastels (indices 16-20)
(gfx-pal 16 195 175 215)    ; lavender body
(gfx-pal 17 140 120 160)    ; lavender shadow
(gfx-pal 18 245 235 175)    ; warm lit window
(gfx-pal 19 110 100 130)    ; dim window
(gfx-pal 20 222 215 240)    ; pale roof / antenna

;; Near buildings – vivid neon (indices 21-25)
(gfx-pal 21  40 215  70)    ; neon green main
(gfx-pal 22  18 130  40)    ; green shadow
(gfx-pal 23 255 240  40)    ; bright yellow lit window
(gfx-pal 24 255 100  20)    ; orange accent / roof
(gfx-pal 25  30 220 220)    ; cyan trim stripe

;; Ground and shared (indices 26-31)
(gfx-pal 26  12  64  12)    ; dark grass
(gfx-pal 27  75 165  48)    ; mid grass strip
(gfx-pal 28 200 255 200)    ; ground highlight
(gfx-pal 29 255 255 255)    ; white
(gfx-pal 30  28  28  28)    ; near-black
(gfx-pal 31 230  50  50)    ; red

;;; ---- Utilities ----
(define (clamp n lo hi) (max lo (min hi n)))
(define (wrap-int n limit) (modulo (+ (modulo n limit) limit) limit))
(define (toggle-buf b) (if (= b 0) 1 0))
(define (lcg s) (modulo (+ (* s 1103515245) 12345) 2147483648))
(define (rng s lo hi) (+ lo (modulo (quotient s 65536) (- hi lo))))

;;; ---- Window Grid Helper ----
(define (draw-windows! bx by bw bh lit dark row-h col-w)
  (let ry ((wy (+ by 5)))
    (if (< wy (- (+ by bh) row-h 2))
        (begin
          (let rx ((wx (+ bx 3)))
            (if (< wx (- (+ bx bw) col-w 1))
                (begin
                  (gfx-rect wx wy col-w row-h
                    (if (= (modulo (+ wx wy) 5) 0) lit dark))
                  (rx (+ wx col-w 2)))
                'done))
          (ry (+ wy row-h 2)))
        'done)))

;;; ---- Far Building Layer (buffer 3) ----
;;; Pastel silhouette city, lots of spires and antennas.
(define (draw-far-buildings! seed)
  (gfx-set-target 3)
  (gfx-cls 0)
  (let loop ((x 0) (s seed))
    (if (< x buf-w)
        (let* ((s1 (lcg s))
               (w  (rng s1 44 110))
               (s2 (lcg s1))
               (h  (rng s2 88 240))
               (s3 (lcg s2))
               (top (- ground-y h)))
          ;; Main body
          (gfx-rect x top w h 16)
          ;; Right-face shadow
          (gfx-rect (- (+ x w) 5) top 5 h 17)
          ;; Cornice shadow strip
          (gfx-rect x (- (+ top h) 5) w 5 17)
          ;; Windows
          (draw-windows! x top w h 18 19 8 8)
          ;; Flat roof with highlight band
          (gfx-rect (+ x 2) (- top 5) (- w 4) 5 20)
          ;; Antenna on some buildings
          (if (= (modulo s3 3) 0)
              (let ((ax (+ x (quotient w 2))))
                (gfx-line ax (- top 4) ax (- top 22) 20)
                (gfx-rect (- ax 2) (- top 24) 4 4 18))
              'done)
          (loop (+ x w 5) s3))
        'done))
  (gfx-set-target 1))

;;; ---- Near Building Layer (buffer 4) ----
;;; Vivid neon city with rooftop tanks and glowing windows.
(define (draw-near-buildings! seed)
  (gfx-set-target 4)
  (gfx-cls 0)
  (let loop ((x 0) (s seed))
    (if (< x buf-w)
        (let* ((s1 (lcg s))
               (w  (rng s1 80 200))
               (s2 (lcg s1))
               (h  (rng s2 70 180))
               (s3 (lcg s2))
               (top (- (+ ground-y 18) h))
               (accent (if (= (modulo s3 2) 0) 24 25)))
          ;; Main body
          (gfx-rect x top w h 21)
          ;; Left neon trim stripe
          (gfx-rect x top 5 h 25)
          ;; Right shadow face
          (gfx-rect (- (+ x w) 7) top 7 h 22)
          ;; Large lit windows
          (draw-windows! x top w h 23 22 13 11)
          ;; Roof accent band
          (gfx-rect x (- top 8) w 8 accent)
          ;; Rooftop tank with support leg
          (let ((cx (+ x (quotient w 2))))
            (gfx-circle cx (- top 14) 8 accent)
            (gfx-circle-outline cx (- top 14) 9 29)
            (gfx-line cx (- top 22) cx (- top 36) 29)
            (gfx-rect (- cx 4) (- top 38) 8 3 24))
          (loop (+ x w 8) s3))
        'done))
  (gfx-set-target 1))

;;; ---- Static Background (buffer 2) ----
(define (build-background!)
  (gfx-set-target 2)
  (gfx-rect 0 0 screen-w ground-y 2)
  (gfx-rect 0 ground-y screen-w (- screen-h ground-y) 3)
  (gfx-rect 0 (- ground-y 8) screen-w 8 2)    ; soft horizon haze
  (gfx-rect 0 (+ ground-y 8)  screen-w 4 26)  ; dark grass trim
  (gfx-rect 0 (+ ground-y 16) screen-w 4 27)  ; mid grass strip
  (gfx-set-target 1))

;;; ========================================================================
;;; Sprite Definitions
;;; ========================================================================

;;; --- Def 0: Fighter Plane 64 x 32 (nose faces right) ---
(gfx-sprite-def 0 64 32)
(with-sprite-canvas 0
  (gfx-cls 0)
  ;; Fuselage central tube
  (gfx-rect 8 13 46 6 2)
  (gfx-line 8 12 54 12 8)          ; top highlight line
  (gfx-line 8 20 54 20 3)          ; bottom shadow line
  ;; Main delta wings (sweep back from mid-fuselage)
  (gfx-triangle 18 16 38 16 26  1 2)   ; upper wing
  (gfx-triangle 18 16 38 16 26 31 2)   ; lower wing
  (gfx-line 18 16 26  0 3)             ; upper wing leading edge shadow
  (gfx-line 18 16 26 32 3)             ; lower wing leading edge shadow
  ;; Wing-tip accent lights
  (gfx-rect 23  0 7 4 7)
  (gfx-rect 23 28 7 4 7)
  ;; Engine nacelles under wings
  (gfx-rect 20  7 16 4 3)
  (gfx-rect 20 21 16 4 3)
  ;; Cockpit canopy
  (gfx-rect 42  8 14 8 4)
  (gfx-rect 43  7 12 3 8)          ; canopy glint
  ;; Nose cone
  (gfx-triangle 54 13 54 19 62 16 6)
  (gfx-line 55 14 61 16 8)         ; nose shine
  ;; Tail fins (vertical stabilisers)
  (gfx-triangle  8 15  8  5 17 15 3)
  (gfx-triangle  8 17  8 27 17 17 3)
  ;; Afterburner glow rings (left side)
  (gfx-circle  5 16 6 5)
  (gfx-circle  5 16 3 8)
  (gfx-circle  3 10 3 5)
  (gfx-circle  3 22 3 5)
  ;; Red fuselage trim stripe
  (gfx-line 28  9 54 13 6)
  (gfx-line 28 23 54 19 6))

(gfx-sprite-palette 0 2 202 212 222)  ; fuselage silver
(gfx-sprite-palette 0 3 100 110 118)  ; shadow grey
(gfx-sprite-palette 0 4  68 172 255)  ; cockpit blue
(gfx-sprite-palette 0 5 255 148   8)  ; afterburner orange
(gfx-sprite-palette 0 6 218  32  32)  ; red trim
(gfx-sprite-palette 0 7 255 232  48)  ; wing-tip yellow
(gfx-sprite-palette 0 8 244 252 255)  ; glint white

;;; --- Def 1: UFO Multi-frame (8 frames of 48x48 + 1 wrap-around buffer frame) ---
(gfx-sprite-def 1 432 48)
(with-sprite-canvas 1
  (gfx-cls 0)
  (let loop ((f 0))
    (if (< f 9)
        (let ((ox (* f 48)))
          ;; Saucer body (dark grey/purple)
          (gfx-rect (+ ox 6) 24 36 8 2)
          (gfx-rect (+ ox 10) 20 28 4 3)
          ;; Bottom hull
          (gfx-rect (+ ox 12) 32 24 4 2)
          ;; Dome (cyan glazing)
          (gfx-circle (+ ox 24) 16 10 4)
          (gfx-circle (+ ox 24) 16 8 5)
          ;; Inner alien silhouette
          (if (= (modulo f 2) 0)
              (gfx-rect (+ ox 22) 14 4 6 3)
              (gfx-rect (+ ox 22) 15 4 5 3))
          ;; Dome highlight
          (gfx-rect (+ ox 18) 10 6 4 8)
          ;; Base dark rim
          (gfx-line (+ ox 6) 28 (+ ox 42) 28 3)
          ;; Spinning trim/lights along the equator
          (let loop-p ((p 0))
            (if (< p 5)
                (let* ((angle (+ (* p 1.2566) (* f 0.7853)))
                       (lx (+ ox 24 (* 18 (cos angle))))
                       (ly (+ 26 (* 2 (sin angle)))))
                  (if (> (sin angle) -0.1) ; front facing
                      (begin
                        (gfx-rect (inexact->exact (round (- lx 2))) (inexact->exact (round ly)) 5 4 6)
                        (gfx-rect (inexact->exact (round (- lx 1))) (inexact->exact (round (+ ly 1))) 3 2 7))
                      'done)
                  (loop-p (+ p 1)))
                'done))
          ;; Pulsing Tractor beam or thrust engine
          (if (= (modulo f 2) 0)
              (begin
                (gfx-triangle (+ ox 16) 36 (+ ox 32) 36 (+ ox 24) 46 9)
                (gfx-triangle (+ ox 18) 36 (+ ox 30) 36 (+ ox 24) 44 8))
              (begin
                (gfx-triangle (+ ox 14) 36 (+ ox 34) 36 (+ ox 24) 48 9)
                (gfx-triangle (+ ox 16) 36 (+ ox 32) 36 (+ ox 24) 46 8)))
          (loop (+ f 1)))
        'done)))

(gfx-sprite-palette 1 2 155  72 218)  ; disc purple
(gfx-sprite-palette 1 3  95  32 152)  ; dark rim
(gfx-sprite-palette 1 4  68 238 238)  ; dome cyan
(gfx-sprite-palette 1 5 190 255 255)  ; dome highlight
(gfx-sprite-palette 1 6  48 255  48)  ; green port lights
(gfx-sprite-palette 1 7 255 238  68)  ; yellow equatorial stripe
(gfx-sprite-palette 1 8 178 220 255)  ; beam pale blue
(gfx-sprite-palette 1 9  48 188 255)  ; beam inner glow

;;; --- UFO Palette Variants ---
;;; Each is a 1×1 placeholder definition whose only purpose is to carry a
;;; palette slot.  gfx-sprite-pal-override points UFO instances at these
;;; instead of def 1's own palette, giving each saucer a unique colour.

;; Def 2 – Red fire saucer
(gfx-sprite-def 2 1 1)
(with-sprite-canvas 2 (gfx-cls 0))
(gfx-sprite-palette 2 2 210  40  40)  ; crimson disc
(gfx-sprite-palette 2 3 130  20  20)  ; dark red rim
(gfx-sprite-palette 2 4 255 140  40)  ; orange dome
(gfx-sprite-palette 2 5 255 220 160)  ; warm dome highlight
(gfx-sprite-palette 2 6 255 255  60)  ; yellow port lights
(gfx-sprite-palette 2 7 255  80  20)  ; orange stripe
(gfx-sprite-palette 2 8 255 180  80)  ; fire beam
(gfx-sprite-palette 2 9 255  80  10)  ; fire beam inner

;; Def 3 – Acid green saucer
(gfx-sprite-def 3 1 1)
(with-sprite-canvas 3 (gfx-cls 0))
(gfx-sprite-palette 3 2  30 160  30)  ; dark green disc
(gfx-sprite-palette 3 3  15  90  15)  ; very dark green rim
(gfx-sprite-palette 3 4 120 255  60)  ; lime dome
(gfx-sprite-palette 3 5 200 255 180)  ; pale lime highlight
(gfx-sprite-palette 3 6 255 255 255)  ; white port lights
(gfx-sprite-palette 3 7 200 255  60)  ; lime stripe
(gfx-sprite-palette 3 8 140 255 140)  ; green beam
(gfx-sprite-palette 3 9  60 220  60)  ; bright green beam inner

;; Def 4 – Gold chrome saucer
(gfx-sprite-def 4 1 1)
(with-sprite-canvas 4 (gfx-cls 0))
(gfx-sprite-palette 4 2 200 160  30)  ; gold disc
(gfx-sprite-palette 4 3 130 100  15)  ; dark gold rim
(gfx-sprite-palette 4 4 240 220 120)  ; pale gold dome
(gfx-sprite-palette 4 5 255 255 200)  ; bright dome highlight
(gfx-sprite-palette 4 6  60 160 255)  ; blue port lights
(gfx-sprite-palette 4 7 255 210  60)  ; gold stripe
(gfx-sprite-palette 4 8 200 240 255)  ; ice blue beam
(gfx-sprite-palette 4 9  80 180 255)  ; blue beam inner

;;; --- Def 5: Ground Crawler — 6-frame walk cycle (6×48 = 288px wide, 48px tall)
;;; Left-facing alien walker with segmented oval purple carapace, yellow ventral
;;; plates, bright cyan eye, and three stepping legs.
(gfx-sprite-def 5 288 48)
(with-sprite-canvas 5
  (gfx-cls 0)
  (let loop ((f 0))
    (if (< f 6)
        (let* ((ox (* f 48))
               (ph (modulo f 2))
               (bob (if (= (modulo f 3) 1) 1 0))
               (by (+ 13 bob))
               (body-x (+ ox 12))
               (roof (+ by 21))
               (head-x (+ ox 8))
               (eye-y (+ by (if (= ph 0) 7 8))))

          ;; antennae / feelers — clearly at the left/front
          (gfx-line (+ ox 12) (+ by 5) (+ ox 6) (+ by 1) 7)
          (gfx-line (+ ox 14) (+ by 8) (+ ox 5) (+ by 6) 7)
          (gfx-rect (+ ox 4) (+ by 0) 2 2 8)
          (gfx-rect (+ ox 3) (+ by 5) 2 2 8)

          ;; rear dorsal spines so silhouette reads left-facing
          (gfx-triangle (+ ox 31) (+ by 3) (+ ox 35) (- by 2) (+ ox 37) (+ by 6) 3)
          (gfx-triangle (+ ox 36) (+ by 4) (+ ox 40) (- by 1) (+ ox 42) (+ by 7) 3)

          ;; main body and segmented shell
          (gfx-circle (+ ox 18) (+ by 14) 7 3)
          (gfx-circle (+ ox 27) (+ by 12) 8 3)
          (gfx-circle (+ ox 35) (+ by 14) 7 3)
          (gfx-circle (+ ox 18) (+ by 14) 5 2)
          (gfx-circle (+ ox 27) (+ by 12) 6 2)
          (gfx-circle (+ ox 35) (+ by 14) 5 2)
          (gfx-rect (+ ox 13) (+ by 15) 25 7 2)
          (gfx-line (+ ox 15) (+ by 8) (+ ox 37) (+ by 9) 8)
          (gfx-line (+ ox 15) (+ by 18) (+ ox 37) (+ by 18) 9)
          (gfx-rect (+ ox 16) (+ by 20) 6 2 7)
          (gfx-rect (+ ox 24) (+ by 19) 6 2 7)
          (gfx-rect (+ ox 32) (+ by 20) 5 2 7)

          ;; head / jaw module on the left
          (gfx-rect head-x (+ by 8) 8 8 3)
          (gfx-circle (+ ox 10) (+ by 12) 5 3)
          (gfx-rect (+ ox 5) (+ by 10) 4 2 9)
          (gfx-rect (+ ox 5) (+ by 14) 4 2 9)
          (gfx-line (+ ox 9) (+ by 10) (+ ox 4) (+ by 8) 9)
          (gfx-line (+ ox 9) (+ by 14) (+ ox 4) (+ by 17) 9)

          ;; glowing eye
          (gfx-circle (+ ox 12) eye-y 4 5)
          (gfx-circle (+ ox 12) eye-y 2 6)

          ;; stepping legs — all below the body so they don't read upside-down
          (let* ((r1 (+ ox 16))
                 (r2 (+ ox 24))
                 (r3 (+ ox 32))
                 (knee-low (+ roof 7))
                 (knee-high (+ roof 4))
                 (foot-low (+ roof 13))
                 (foot-high (+ roof 10))
                 (front-down? (= ph 0))
                 (mid-down? (= ph 1))
                 (rear-down? (= ph 0)))
            (define (draw-leg! root-x down?)
              (let* ((knee-x (if down? (- root-x 6) (+ root-x 2)))
                     (knee-y (if down? knee-low knee-high))
                     (foot-x (if down? (- root-x 10) (+ root-x 3)))
                     (foot-y (if down? foot-low foot-high)))
                (gfx-line root-x roof knee-x knee-y 9)
                (gfx-line knee-x knee-y foot-x foot-y 9)
                (gfx-rect (- foot-x 1) foot-y 3 2 2)))
            (draw-leg! r1 front-down?)
            (draw-leg! r2 mid-down?)
            (draw-leg! r3 rear-down?))

          ;; tail stab / rear strut
          (gfx-line (+ ox 38) (+ by 14) (+ ox 44) (+ by 18) 9)
          (gfx-line (+ ox 37) (+ by 18) (+ ox 43) (+ by 24) 9)
          (gfx-rect (+ ox 40) (+ by 12) 3 3 7)

          (loop (+ f 1)))
        'done)))

(gfx-sprite-palette 5 2 246 214  64)  ; yellow ventral plate
(gfx-sprite-palette 5 3 102  34 146)  ; deep purple shell / shadow
(gfx-sprite-palette 5 5  70 235 255)  ; cyan eye glow outer
(gfx-sprite-palette 5 6 220 255 255)  ; bright eye core
(gfx-sprite-palette 5 7 255 240 108)  ; vent/antenna glow
(gfx-sprite-palette 5 8 196 120 255)  ; shell highlight
(gfx-sprite-palette 5 9 218 218 228)  ; steel legs / jaws

;;; --- Def 6: Player explosion — 6-frame blast (6×48 = 288px wide, 48px tall)
(gfx-sprite-def 6 288 48)
(with-sprite-canvas 6
  (gfx-cls 0)
  (let loop ((f 0))
    (if (< f 6)
        (let* ((ox (* f 48))
               (r1 (+ 6 (* f 2)))
               (r2 (+ 3 f))
               (spark (max 2 (- 7 f))))
          ;; outer fireball
          (gfx-circle (+ ox 24) 24 r1 2)
          ;; hot core
          (gfx-circle (+ ox 24) 24 r2 3)
          ;; white flash centre for first frames
          (if (< f 3)
              (gfx-circle (+ ox 24) 24 (- 4 f) 4)
              'done)
          ;; starburst rays
          (gfx-line (+ ox 24) 10 (+ ox 24) 38 5)
          (gfx-line (+ ox 10) 24 (+ ox 38) 24 5)
          (gfx-line (+ ox 14) 14 (+ ox 34) 34 5)
          (gfx-line (+ ox 14) 34 (+ ox 34) 14 5)
          ;; debris sparks
          (gfx-rect (+ ox 24 spark) (- 8 spark) 3 3 3)
          (gfx-rect (+ ox 36 spark) (+ 10 spark) 3 3 2)
          (gfx-rect (+ ox 34 spark) (+ 30 spark) 3 3 3)
          (gfx-rect (+ ox 8 (- 8 spark)) (+ 28 spark) 3 3 2)
          (gfx-rect (+ ox 6 (- 8 spark)) (+ 10 spark) 3 3 3)
          (loop (+ f 1)))
        'done)))

(gfx-sprite-palette 6 2 255 120  24)  ; outer orange
(gfx-sprite-palette 6 3 255 210  40)  ; hot yellow
(gfx-sprite-palette 6 4 255 255 255)  ; white core
(gfx-sprite-palette 6 5 255  70  24)  ; red flare

;;; --- Def 7: Saucer fireball — 4-frame ember shot (4×16 = 64px wide, 16px tall)
(gfx-sprite-def 7 64 16)
(with-sprite-canvas 7
  (gfx-cls 0)
  (let loop ((f 0))
    (if (< f 4)
        (let* ((ox (* f 16))
               (tail (+ 2 f)))
          ;; trailing flame to the right, hot core toward the front/left
          (gfx-rect (+ ox 7) 6 (+ 4 tail) 4 5)
          (gfx-circle (+ ox 7) 8 4 2)
          (gfx-circle (+ ox 6) 8 2 3)
          (gfx-circle (+ ox 5) 8 1 4)
          (gfx-line (+ ox 10) 8 (+ ox 14) 8 5)
          (loop (+ f 1)))
        'done)))

(gfx-sprite-palette 7 2 255 126  32)  ; orange shell
(gfx-sprite-palette 7 3 255 220  48)  ; yellow core
(gfx-sprite-palette 7 4 255 255 255)  ; white-hot tip
(gfx-sprite-palette 7 5 255  76  24)  ; flame trail

;;; --- Def 8: Crawler missile — 4-frame toxic bolt (4×16 = 64px wide, 16px tall)
(gfx-sprite-def 8 64 16)
(with-sprite-canvas 8
  (gfx-cls 0)
  (let loop ((f 0))
    (if (< f 4)
        (let* ((ox (* f 16))
               (tail (+ 1 f)))
          ;; front is upper-left, trailing glow falls back toward lower-right
          (gfx-line (+ ox 4) 5 (+ ox 10 tail) 11 5)
          (gfx-line (+ ox 5) 4 (+ ox 9 tail) 8 2)
          (gfx-circle (+ ox 4) 5 2 3)
          (gfx-circle (+ ox 3) 4 1 4)
          (gfx-circle (+ ox 8) 9 1 5)
          (loop (+ f 1)))
        'done)))

(gfx-sprite-palette 8 2  48 255 140)  ; neon green body
(gfx-sprite-palette 8 3 170 255 210)  ; bright core
(gfx-sprite-palette 8 4 235 255 245)  ; white-green tip
(gfx-sprite-palette 8 5  20 170  90)  ; darker trail

;;; --- Def 9: Player shot — 4-frame blue plasma arc (4×16 = 64px wide, 16px tall)
(gfx-sprite-def 9 64 16)
(with-sprite-canvas 9
  (gfx-cls 0)
  (let loop ((f 0))
    (if (< f 4)
        (let* ((ox (* f 16))
               (flare (+ 1 (modulo f 2))))
          (gfx-line (+ ox 2) 8 (+ ox 11) 8 5)
          (gfx-line (+ ox 4) 6 (+ ox 10) 6 2)
          (gfx-line (+ ox 4) 10 (+ ox 10) 10 2)
          (gfx-circle (+ ox 11) 8 3 3)
          (gfx-circle (+ ox 12) 8 1 4)
          (gfx-rect (+ ox 1) (- 8 flare) 2 (+ 1 (* flare 2)) 5)
          (loop (+ f 1)))
        'done)))

(gfx-sprite-palette 9 2  72 180 255)  ; electric blue
(gfx-sprite-palette 9 3 140 230 255)  ; bright plasma core
(gfx-sprite-palette 9 4 255 255 255)  ; white tip
(gfx-sprite-palette 9 5  34 110 255)  ; darker trail

;;; --- Def 10-14: Explosion palette variants for alien kills
(gfx-sprite-def 10 1 1)
(with-sprite-canvas 10 (gfx-cls 0))
(gfx-sprite-palette 10 2 220  92 255) ; purple outer
(gfx-sprite-palette 10 3 255 170 255) ; lavender core
(gfx-sprite-palette 10 4 255 255 255) ; white flash
(gfx-sprite-palette 10 5 120  48 200) ; violet flare

(gfx-sprite-def 11 1 1)
(with-sprite-canvas 11 (gfx-cls 0))
(gfx-sprite-palette 11 2 255 118  26) ; ember orange
(gfx-sprite-palette 11 3 255 214  72) ; hot gold
(gfx-sprite-palette 11 4 255 255 220) ; bright flash
(gfx-sprite-palette 11 5 220  54  20) ; red flare

(gfx-sprite-def 12 1 1)
(with-sprite-canvas 12 (gfx-cls 0))
(gfx-sprite-palette 12 2  70 255 124) ; acid green
(gfx-sprite-palette 12 3 202 255 180) ; toxic core
(gfx-sprite-palette 12 4 255 255 240) ; pale flash
(gfx-sprite-palette 12 5  24 178  76) ; dark acid flare

(gfx-sprite-def 13 1 1)
(with-sprite-canvas 13 (gfx-cls 0))
(gfx-sprite-palette 13 2 255 188  60) ; gold outer
(gfx-sprite-palette 13 3 255 236 140) ; bright gold core
(gfx-sprite-palette 13 4 255 255 245) ; white flash
(gfx-sprite-palette 13 5 204 122  24) ; amber flare

(gfx-sprite-def 14 1 1)
(with-sprite-canvas 14 (gfx-cls 0))
(gfx-sprite-palette 14 2 142 255  96) ; crawler green outer
(gfx-sprite-palette 14 3 255 214  96) ; heated inner
(gfx-sprite-palette 14 4 255 255 220) ; pale flash
(gfx-sprite-palette 14 5 144  62  22) ; rust flare

;;; --- Def 15: Boss mothership — giant saucer (96x96)
(gfx-sprite-def 15 96 96)
(with-sprite-canvas 15
  (gfx-cls 0)
  ;; outer hull
  (gfx-circle 48 56 32 2)
  (gfx-rect 16 50 64 14 2)
  (gfx-rect 20 52 56 10 3)
  ;; dome and upper superstructure
  (gfx-circle 48 36 20 4)
  (gfx-circle 48 34 16 5)
  (gfx-rect 32 42 32 8 2)
  ;; command spine
  (gfx-rect 44 18 8 12 7)
  (gfx-circle 48 16 5 8)
  ;; equatorial lights
  (gfx-circle 20 56 4 6)
  (gfx-circle 32 61 4 6)
  (gfx-circle 48 64 4 6)
  (gfx-circle 64 61 4 6)
  (gfx-circle 76 56 4 6)
  (gfx-circle 24 54 2 9)
  (gfx-circle 40 59 2 9)
  (gfx-circle 56 62 2 9)
  (gfx-circle 72 58 2 9)
  ;; side pods
  (gfx-circle 18 50 6 3)
  (gfx-circle 78 50 6 3)
  ;; lower weapons / tractor emitters
  (gfx-rect 30 66 10 5 8)
  (gfx-rect 56 66 10 5 8)
  (gfx-triangle 34 71 38 71 36 82 9)
  (gfx-triangle 58 71 62 71 60 82 9)
  ;; hull highlights
  (gfx-line 22 48 74 48 7)
  (gfx-line 30 30 66 30 8)
  (gfx-line 18 58 78 58 3)
  ;; alien viewport cluster
  (gfx-rect 42 32 4 6 3)
  (gfx-rect 50 32 4 6 3))

(gfx-sprite-palette 15 2 118  72 196) ; mothership body
(gfx-sprite-palette 15 3  68  26 132) ; shadow rim
(gfx-sprite-palette 15 4  92 250 255) ; dome cyan
(gfx-sprite-palette 15 5 208 255 255) ; dome highlight
(gfx-sprite-palette 15 6 255 214  64) ; lights
(gfx-sprite-palette 15 7 255 160  80) ; spine glow
(gfx-sprite-palette 15 8 255 110  60) ; weapon bank
(gfx-sprite-palette 15 9 160 220 255) ; beam tip

;;; ---- Sprite Instances ----
(gfx-sprite 0 0  80.0 210.0)          ; player

;; Setup multi-frame animation for UFOs
(gfx-sprite-frames 1 48 48 8)

(gfx-sprite 1 1 860.0  96.0)
(gfx-sprite 2 1 1060.0 172.0)
(gfx-sprite 3 1 1280.0 118.0)
(gfx-sprite 4 1 1480.0 210.0)
(gfx-sprite 37 1 1660.0 142.0)
(gfx-sprite 38 1 1840.0 188.0)

;; Animate saucer instances
(gfx-sprite-animate 1 0.15)
(gfx-sprite-animate 2 0.12)
(gfx-sprite-animate 3 0.18)
(gfx-sprite-animate 4 0.14)
(gfx-sprite-animate 37 0.16)
(gfx-sprite-animate 38 0.13)

;; Colour variants: inst 1 keeps default purple, 2=fire, 3=acid, 4=gold
(gfx-sprite-pal-override 2 2)
(gfx-sprite-pal-override 3 3)
(gfx-sprite-pal-override 4 4)
(gfx-sprite-pal-override 37 2)
(gfx-sprite-pal-override 38 4)

;; Crawlers — 6-frame walk cycle, ground level
(gfx-sprite-frames 5 48 48 6)

(gfx-sprite 5 5  140.0 378.0)   ; crawler A
(gfx-sprite 6 5  360.0 382.0)   ; crawler B
(gfx-sprite 7 5  580.0 376.0)   ; crawler C
(gfx-sprite 8 5  840.0 380.0)   ; crawler D
(gfx-sprite 9 6 -100.0 -100.0)  ; player explosion (hidden until crash)
(gfx-sprite 10 7 -100.0 -100.0) ; saucer fireball pool A
(gfx-sprite 11 7 -100.0 -100.0) ; saucer fireball pool B
(gfx-sprite 12 7 -100.0 -100.0) ; saucer fireball pool C
(gfx-sprite 13 7 -100.0 -100.0) ; saucer fireball pool D
(gfx-sprite 14 7 -100.0 -100.0) ; saucer fireball pool E
(gfx-sprite 15 7 -100.0 -100.0) ; saucer fireball pool F
(gfx-sprite 16 8 -100.0 -100.0) ; crawler missile pool A
(gfx-sprite 17 8 -100.0 -100.0) ; crawler missile pool B
(gfx-sprite 18 8 -100.0 -100.0) ; crawler missile pool C
(gfx-sprite 19 8 -100.0 -100.0) ; crawler missile pool D
(gfx-sprite 20 8 -100.0 -100.0) ; crawler missile pool E
(gfx-sprite 21 8 -100.0 -100.0) ; crawler missile pool F
(gfx-sprite 22 9 -100.0 -100.0) ; player shot pool A
(gfx-sprite 23 9 -100.0 -100.0) ; player shot pool B
(gfx-sprite 24 9 -100.0 -100.0) ; player shot pool C
(gfx-sprite 25 9 -100.0 -100.0) ; player shot pool D
(gfx-sprite 26 9 -100.0 -100.0) ; player shot pool E
(gfx-sprite 27 9 -100.0 -100.0) ; player shot pool F
(gfx-sprite 28 9 -100.0 -100.0) ; player shot pool G
(gfx-sprite 29 9 -100.0 -100.0) ; player shot pool H
(gfx-sprite 30 6 -100.0 -100.0) ; alien explosion pool A
(gfx-sprite 31 6 -100.0 -100.0) ; alien explosion pool B
(gfx-sprite 32 6 -100.0 -100.0) ; alien explosion pool C
(gfx-sprite 33 6 -100.0 -100.0) ; alien explosion pool D
(gfx-sprite 34 6 -100.0 -100.0) ; alien explosion pool E
(gfx-sprite 35 6 -100.0 -100.0) ; alien explosion pool F
(gfx-sprite 36 15 -140.0 -140.0) ; boss mothership

;; Collision groups: player=1, all aliens=2
(gfx-sprite-collide 0 1)
(gfx-sprite-collide 1 2)
(gfx-sprite-collide 2 2)
(gfx-sprite-collide 3 2)
(gfx-sprite-collide 4 2)
(gfx-sprite-collide 37 2)
(gfx-sprite-collide 38 2)
(gfx-sprite-collide 5 2)
(gfx-sprite-collide 6 2)
(gfx-sprite-collide 7 2)
(gfx-sprite-collide 8 2)
(gfx-sprite-collide 10 2)
(gfx-sprite-collide 11 2)
(gfx-sprite-collide 12 2)
(gfx-sprite-collide 13 2)
(gfx-sprite-collide 14 2)
(gfx-sprite-collide 15 2)
(gfx-sprite-collide 16 2)
(gfx-sprite-collide 17 2)
(gfx-sprite-collide 18 2)
(gfx-sprite-collide 19 2)
(gfx-sprite-collide 20 2)
(gfx-sprite-collide 21 2)
(gfx-sprite-collide 36 2)

;; Anchor walkers at their feet so they sit on the ground strip.
(gfx-sprite-anchor 5 0.5 1.0)
(gfx-sprite-anchor 6 0.5 1.0)
(gfx-sprite-anchor 7 0.5 1.0)
(gfx-sprite-anchor 8 0.5 1.0)
(gfx-sprite-anchor 9 0.5 0.5)
(gfx-sprite-anchor 10 0.5 0.5)
(gfx-sprite-anchor 11 0.5 0.5)
(gfx-sprite-anchor 12 0.5 0.5)
(gfx-sprite-anchor 13 0.5 0.5)
(gfx-sprite-anchor 14 0.5 0.5)
(gfx-sprite-anchor 15 0.5 0.5)
(gfx-sprite-anchor 16 0.5 0.5)
(gfx-sprite-anchor 17 0.5 0.5)
(gfx-sprite-anchor 18 0.5 0.5)
(gfx-sprite-anchor 19 0.5 0.5)
(gfx-sprite-anchor 20 0.5 0.5)
(gfx-sprite-anchor 21 0.5 0.5)
(gfx-sprite-anchor 22 0.5 0.5)
(gfx-sprite-anchor 23 0.5 0.5)
(gfx-sprite-anchor 24 0.5 0.5)
(gfx-sprite-anchor 25 0.5 0.5)
(gfx-sprite-anchor 26 0.5 0.5)
(gfx-sprite-anchor 27 0.5 0.5)
(gfx-sprite-anchor 28 0.5 0.5)
(gfx-sprite-anchor 29 0.5 0.5)
(gfx-sprite-anchor 30 0.5 0.5)
(gfx-sprite-anchor 31 0.5 0.5)
(gfx-sprite-anchor 32 0.5 0.5)
(gfx-sprite-anchor 33 0.5 0.5)
(gfx-sprite-anchor 34 0.5 0.5)
(gfx-sprite-anchor 35 0.5 0.5)
(gfx-sprite-anchor 36 0.5 0.5)
(gfx-sprite-anchor 37 0.5 0.5)
(gfx-sprite-anchor 38 0.5 0.5)

(gfx-sprite-animate 5 0.08)
(gfx-sprite-animate 6 0.06)
(gfx-sprite-animate 7 0.09)
(gfx-sprite-animate 8 0.07)
(gfx-sprite-animate 16 0.18)
(gfx-sprite-animate 17 0.16)
(gfx-sprite-animate 18 0.2)
(gfx-sprite-animate 19 0.17)
(gfx-sprite-animate 20 0.19)
(gfx-sprite-animate 21 0.15)

;; Start each crawler on a different frame so they don't all step in sync
(gfx-sprite-frame 6 2)
(gfx-sprite-frame 7 4)
(gfx-sprite-frame 8 1)

;; Explosion sprite setup
(gfx-sprite-frames 6 48 48 6)
(gfx-sprite-hide 9)

;; Fireball sprite setup
(gfx-sprite-frames 7 16 16 4)
(gfx-sprite-animate 10 0.22)
(gfx-sprite-animate 11 0.22)
(gfx-sprite-animate 12 0.22)
(gfx-sprite-animate 13 0.22)
(gfx-sprite-animate 14 0.22)
(gfx-sprite-animate 15 0.22)
(gfx-sprite-hide 10)
(gfx-sprite-hide 11)
(gfx-sprite-hide 12)
(gfx-sprite-hide 13)
(gfx-sprite-hide 14)
(gfx-sprite-hide 15)
(gfx-sprite-hide 16)
(gfx-sprite-hide 17)
(gfx-sprite-hide 18)
(gfx-sprite-hide 19)
(gfx-sprite-hide 20)
(gfx-sprite-hide 21)

;; Player shot sprite setup
(gfx-sprite-frames 9 16 16 4)
(gfx-sprite-animate 22 0.28)
(gfx-sprite-animate 23 0.28)
(gfx-sprite-animate 24 0.28)
(gfx-sprite-animate 25 0.28)
(gfx-sprite-animate 26 0.28)
(gfx-sprite-animate 27 0.28)
(gfx-sprite-animate 28 0.28)
(gfx-sprite-animate 29 0.28)
(gfx-sprite-hide 22)
(gfx-sprite-hide 23)
(gfx-sprite-hide 24)
(gfx-sprite-hide 25)
(gfx-sprite-hide 26)
(gfx-sprite-hide 27)
(gfx-sprite-hide 28)
(gfx-sprite-hide 29)

;; Alien explosion pool setup
(gfx-sprite-animate 30 0.42)
(gfx-sprite-animate 31 0.42)
(gfx-sprite-animate 32 0.42)
(gfx-sprite-animate 33 0.42)
(gfx-sprite-animate 34 0.42)
(gfx-sprite-animate 35 0.42)
(gfx-sprite-hide 30)
(gfx-sprite-hide 31)
(gfx-sprite-hide 32)
(gfx-sprite-hide 33)
(gfx-sprite-hide 34)
(gfx-sprite-hide 35)
(gfx-sprite-hide 36)
(gfx-sprite-hide 37)
(gfx-sprite-hide 38)



;;; ---- Build All Offscreen Buffers ----
(build-background!)
(draw-far-buildings! 42)
(draw-near-buildings! 999)

;;; ---- Blit Wrapped Layer (transparent) ----
;;; Blits src (a building strip wider than the screen) onto dst with horizontal
;;; wrap so the layer scrolls seamlessly.
(define (blit-layer dst src scroll-x)
  (let* ((ox (wrap-int scroll-x buf-w))
         (fw (min screen-w (- buf-w ox))))
    (gfx-blit dst 0 0 src ox 0 fw screen-h)
    (if (< fw screen-w)
        (gfx-blit dst fw 0 src 0 0 (- screen-w fw) screen-h)
        'done)))

;;; ---- Enemy Vectors ----
(define (make-enemy inst bx by spd ph)
  (vector inst bx by spd ph))
(define (ei e) (vector-ref e 0))   ; sprite instance id
(define (ebx e) (vector-ref e 1))  ; current x
(define (eby e) (vector-ref e 2))  ; base y (bobbing centre)
(define (espd e) (vector-ref e 3)) ; horizontal speed
(define (eph e) (vector-ref e 4))  ; bob phase offset

(define (update-enemies! enemies frame)
  (map
    (lambda (e)
      (let* ((nx (- (ebx e) (espd e)))
             (fx (if (< nx -60.0) (+ screen-w 200.0) nx))
             (dy (+ (eby e) (* 14.0 (sin (+ (eph e) (* frame 0.04)))))))
        (gfx-sprite-show (ei e))
        (gfx-sprite-pos (ei e) fx dy)
        (make-enemy (ei e) fx (eby e) (espd e) (eph e))))
    enemies))

;;; ---- Crawler Vectors ----
;;; Crawlers march left across the ground. Their total screen speed is the
;;; scene scroll speed plus their own gait speed, so they stay visually tied
;;; to the moving ground layer instead of drifting independently.
(define (make-crawler inst x y spd) (vector inst x y spd))
(define (cr-inst c) (vector-ref c 0))
(define (cr-x    c) (vector-ref c 1))
(define (cr-y    c) (vector-ref c 2))
(define (cr-spd  c) (vector-ref c 3))

(define (hit-near? x1 y1 x2 y2 rx ry)
  (and (< (abs (- x1 x2)) rx)
       (< (abs (- y1 y2)) ry)))

(define (respawn-enemy! e frame)
  (let* ((slot (modulo (+ frame (ei e)) 6))
         (nx (+ screen-w 150.0 (* 88.0 slot)))
         (ph (+ 0.6 (* 0.85 slot))))
    (gfx-sprite-pos (ei e) nx (eby e))
    (make-enemy (ei e) nx (eby e) (espd e) ph)))

(define (respawn-crawler! c frame)
  (let* ((slot (modulo (+ frame (cr-inst c)) 5))
         (nx (+ screen-w 110.0 (* 76.0 slot))))
    (gfx-sprite-pos (cr-inst c) nx (cr-y c))
    (make-crawler (cr-inst c) nx (cr-y c) (cr-spd c))))

(define (update-crawlers! crawlers world-spd frame)
  (map
    (lambda (c)
      (let* ((total-spd (+ world-spd (cr-spd c)))
             (nx (- (cr-x c) total-spd))
             (fx (if (< nx -72.0) (+ screen-w 72.0) nx))
             (phase (+ (* frame 0.20) (* (cr-inst c) 0.9)))
             (fy (+ (cr-y c) (* 1.4 (sin phase))))
             (pulse (+ 0.82 (* 0.18 (max 0.0 (sin (+ (* frame 0.28) (cr-inst c))))))))
        (gfx-sprite-show (cr-inst c))
        (gfx-sprite-alpha (cr-inst c) pulse)
        (gfx-sprite-pos (cr-inst c) fx fy)
        (make-crawler (cr-inst c) fx (cr-y c) (cr-spd c))))
    crawlers))

;;; ---- Fireball Vectors ----
(define (make-fireball inst x y spd active?) (vector inst x y spd active?))
(define (fb-inst f) (vector-ref f 0))
(define (fb-x    f) (vector-ref f 1))
(define (fb-y    f) (vector-ref f 2))
(define (fb-spd  f) (vector-ref f 3))
(define (fb-on?  f) (vector-ref f 4))

(define (reset-fireball! f)
  (gfx-sprite-hide (fb-inst f))
  (gfx-sprite-pos (fb-inst f) -100.0 -100.0)
  (make-fireball (fb-inst f) -100.0 -100.0 0.0 #f))

(define (update-fireballs! fireballs world-spd)
  (map
    (lambda (f)
      (if (not (fb-on? f))
          f
          (let* ((total-spd (+ world-spd (fb-spd f)))
                 (nx (- (fb-x f) total-spd)))
            (if (< nx -24.0)
                (reset-fireball! f)
                (begin
                  (gfx-sprite-pos (fb-inst f) nx (fb-y f))
                  (make-fireball (fb-inst f) nx (fb-y f) (fb-spd f) #t))))))
    fireballs))

(define (spawn-fireball! fireballs x y spd)
  (cond
    ((null? fireballs) '())
    ((not (fb-on? (car fireballs)))
     (let ((inst (fb-inst (car fireballs))))
       (play-generated-sound alien-shot-sound-id)
       (gfx-sprite-pos inst x y)
       (gfx-sprite-frame inst 0)
       (gfx-sprite-show inst)
       (cons (make-fireball inst x y spd #t) (cdr fireballs))))
    (else
     (cons (car fireballs) (spawn-fireball! (cdr fireballs) x y spd)))))

(define (maybe-spawn-fireball fireballs enemies frame)
  (if (or (not (= (modulo frame 84) 0))
          (null? enemies))
      fireballs
      (let* ((shot-index (modulo (quotient frame 84) (length enemies)))
             (shooter (list-ref enemies shot-index))
             (sx (- (ebx shooter) 18.0))
             (sy (+ (eby shooter) 16.0))
             (spd (+ 1.2 (* 0.35 (modulo shot-index 3)))))
        (if (or (< sx -40.0) (> sx (+ screen-w 40.0)))
            fireballs
            (spawn-fireball! fireballs sx sy spd)))))

;;; ---- Boss & Orbiter Vectors ----
(define (make-boss active? x y hp defeated?) (vector active? x y hp defeated?))
(define (boss-on? b) (vector-ref b 0))
(define (boss-x   b) (vector-ref b 1))
(define (boss-y   b) (vector-ref b 2))
(define (boss-hp  b) (vector-ref b 3))
(define (boss-defeated? b) (vector-ref b 4))

(define (initial-boss)
  (make-boss #f 860.0 132.0 boss-hit-points #f))

(define (spawn-boss)
  (make-boss #t 860.0 132.0 boss-hit-points #f))

(define (update-boss! boss frame)
  (if (not (boss-on? boss))
      boss
      (let* ((nx (max 560.0 (- (boss-x boss) 2.4)))
             (ny (+ 132.0 (* 32.0 (sin (* frame 0.032))))))
        (gfx-sprite-pos boss-inst nx ny)
        (gfx-sprite-show boss-inst)
        (make-boss #t nx ny (boss-hp boss) (boss-defeated? boss)))))

(define (update-boss-victory! boss frame)
  (if (not (boss-on? boss))
      boss
      (let* ((nx (+ 586.0 (* 34.0 (sin (* frame 0.06)))))
             (ny (+ 126.0 (* 46.0 (sin (* frame 0.11)))))
             (beam-flash? (< (modulo frame 48) 18)))
  (gfx-sprite-alpha boss-inst 1.0)
        (gfx-sprite-rot boss-inst (* 0.05 (sin (* frame 0.09))))
        (gfx-sprite-pos boss-inst nx ny)
        (gfx-sprite-show boss-inst)
        (if beam-flash?
            (begin
              (gfx-sprite-pal-override boss-inst 13)
              (gfx-line (inexact->exact (round (- nx 16.0)))
                        (inexact->exact (round (+ ny 28.0)))
                        (inexact->exact (round (- nx 38.0)))
                        (inexact->exact (round (+ ny 84.0)))
                        29)
              (gfx-line (inexact->exact (round (+ nx 16.0)))
                        (inexact->exact (round (+ ny 28.0)))
                        (inexact->exact (round (+ nx 38.0)))
                        (inexact->exact (round (+ ny 84.0)))
                        29))
            (gfx-sprite-pal-override boss-inst 0))
        (make-boss #t nx ny (boss-hp boss) (boss-defeated? boss)))))

(define (make-orbiter inst phase x y alive?) (vector inst phase x y alive?))
(define (orb-inst  o) (vector-ref o 0))
(define (orb-phase o) (vector-ref o 1))
(define (orb-x     o) (vector-ref o 2))
(define (orb-y     o) (vector-ref o 3))
(define (orb-on?   o) (vector-ref o 4))

(define (orbiter-pal-def inst)
  (cond
    ((or (= inst 2) (= inst 37)) 2)
    ((= inst 3) 3)
    ((or (= inst 4) (= inst 38)) 4)
    (else 0)))

(define (escort-slot-x-offset slot)
  (if (= (modulo slot 2) 0) -140.0 -104.0))

(define (escort-slot-y-offset slot)
  (let ((slot-1 (modulo slot 6)))
    (cond
      ((< slot-1 2) -40.0)
      ((< slot-1 4) 0.0)
      (else 40.0))))

(define (initial-orbiters)
  (list (make-orbiter 1 0.0    -100.0 -100.0 #t)
        (make-orbiter 2 1.0472 -100.0 -100.0 #t)
        (make-orbiter 3 2.0944 -100.0 -100.0 #t)
        (make-orbiter 4 3.1416 -100.0 -100.0 #t)
        (make-orbiter 37 4.1888 -100.0 -100.0 #t)
        (make-orbiter 38 5.2360 -100.0 -100.0 #t)))

(define (hide-orbiter-sprites! orbiters)
  (map (lambda (o) (gfx-sprite-hide (orb-inst o))) orbiters))

(define (orbiters-cleared? orbiters)
  (let loop ((rest orbiters))
    (if (null? rest)
        #t
        (and (not (orb-on? (car rest)))
             (loop (cdr rest))))))

(define (orbiter-count orbiters)
  (let loop ((rest orbiters) (count 0))
    (if (null? rest)
        count
        (loop (cdr rest)
              (+ count (if (orb-on? (car rest)) 1 0))))))

(define (update-orbiters! orbiters boss frame)
  (if (not (boss-on? boss))
      orbiters
      (let loop ((rest orbiters) (done '()) (alive-slot 0))
        (if (null? rest)
            (reverse done)
            (let ((o (car rest)))
              (if (not (orb-on? o))
                  (begin
                    (gfx-sprite-hide (orb-inst o))
                    (loop (cdr rest)
                          (cons (make-orbiter (orb-inst o) (orb-phase o) -100.0 -100.0 #f) done)
                          alive-slot))
                  (let* ((slot alive-slot)
                         (wave-phase (+ (* frame 0.055) (* 0.8 (orb-inst o))))
                         (drift-x (* 4.5 (sin wave-phase)))
                         (drift-y (* 7.0 (sin (+ wave-phase 0.9))))
                         (x (+ (boss-x boss) (escort-slot-x-offset slot) drift-x))
                         (y (+ (boss-y boss) (escort-slot-y-offset slot) drift-y)))
                    (gfx-sprite-pal-override (orb-inst o) (orbiter-pal-def (orb-inst o)))
                    (gfx-sprite-alpha (orb-inst o) 1.0)
                    (gfx-sprite-rot (orb-inst o) (* 0.04 (sin (+ wave-phase 0.4))))
                    (gfx-sprite-pos (orb-inst o) x y)
                    (gfx-sprite-show (orb-inst o))
                    (loop (cdr rest)
                          (cons (make-orbiter (orb-inst o) (orb-phase o) x y #t) done)
                          (+ alive-slot 1)))))))))

(define (update-orbiters-victory! orbiters boss frame)
  (if (not (boss-on? boss))
      orbiters
      (map
        (lambda (o)
          (if (not (orb-on? o))
              (begin
                (gfx-sprite-hide (orb-inst o))
                (make-orbiter (orb-inst o) (orb-phase o) -100.0 -100.0 #f))
              (let* ((breath-phase (+ (* frame 0.08) (* 0.5 (orb-inst o))))
                     (breath (+ 1.0 (* 0.30 (sin breath-phase))))
                (speed (+ 0.045 (* 0.010 (- 1.30 breath))))
                     (angle (+ (orb-phase o) (* frame speed)))
                     (radius-x (* breath (+ 118.0 (* 18.0 (sin (+ angle (* frame 0.04)))))))
                     (radius-y (* breath (+ 64.0 (* 8.0 (cos (+ angle (* frame 0.03)))))))
                     (x (+ (boss-x boss) (* radius-x (cos angle))))
                     (y (+ (boss-y boss) (* radius-y (sin angle))))
                     (pulse-def (cond
                                  ((= (modulo (+ frame (orb-inst o)) 18) 0) 13)
                                  ((= (modulo (+ frame (* 2 (orb-inst o))) 12) 0) 11)
                                  (else (orbiter-pal-def (orb-inst o))))))
                (gfx-sprite-pal-override (orb-inst o) pulse-def)
                   (gfx-sprite-alpha (orb-inst o) 1.0)
                 (gfx-sprite-rot (orb-inst o) (* 0.08 (sin (+ angle (* frame 0.07)))))
                (gfx-sprite-pos (orb-inst o) x y)
                (gfx-sprite-show (orb-inst o))
                (make-orbiter (orb-inst o) (orb-phase o) x y #t))))
        orbiters)))

(define (boss-spawn-ready? frame score boss)
  (and (not (boss-on? boss))
       (not (boss-defeated? boss))
       (or (and (>= frame boss-trigger-min-frame)
                (>= score boss-trigger-score))
           (>= frame boss-trigger-max-frame))))

(define (boss-escort-label orbiters)
  (string-append "Escorts: " (number->string (orbiter-count orbiters))))

(define (maybe-spawn-boss-fireballs fireballs boss orbiters frame)
  (let* ((fireballs-1
           (if (and (boss-on? boss)
                    (= (modulo (lcg (+ frame 701)) 33) 0))
               (spawn-fireball! fireballs
                                (- (boss-x boss) 52.0)
                                (+ (boss-y boss)
                                   (if (= (modulo frame 2) 0) -10.0 10.0))
                                2.35)
               fireballs)))
    (let loop ((rest orbiters) (shots fireballs-1))
      (if (null? rest)
          shots
          (let ((o (car rest)))
            (if (and (orb-on? o)
                     (< (orb-x o) (boss-x boss))
                     (= (modulo (lcg (+ frame (* 97 (orb-inst o)))) 31) 0))
                (loop
                  (cdr rest)
                  (spawn-fireball! shots
                                   (- (orb-x o) 20.0)
                                   (+ (orb-y o)
                                      (cond
                                        ((= (modulo (+ frame (orb-inst o)) 3) 0) -8.0)
                                        ((= (modulo (+ frame (* 2 (orb-inst o))) 4) 0) 8.0)
                                        (else 0.0)))
                                   (+ 1.7 (* 0.2 (modulo (+ frame (orb-inst o)) 3)))))
                (loop (cdr rest) shots)))))))

;;; ---- Crawler Missile Vectors ----
(define (make-missile inst x y dx dy active?) (vector inst x y dx dy active?))
(define (ms-inst m) (vector-ref m 0))
(define (ms-x    m) (vector-ref m 1))
(define (ms-y    m) (vector-ref m 2))
(define (ms-dx   m) (vector-ref m 3))
(define (ms-dy   m) (vector-ref m 4))
(define (ms-on?  m) (vector-ref m 5))

(define (reset-missile! m)
  (gfx-sprite-hide (ms-inst m))
  (gfx-sprite-pos (ms-inst m) -100.0 -100.0)
  (make-missile (ms-inst m) -100.0 -100.0 0.0 0.0 #f))

(define (update-missiles! missiles world-spd)
  (map
    (lambda (m)
      (if (not (ms-on? m))
          m
          (let* ((nx (- (ms-x m) (+ world-spd (ms-dx m))))
                 (ny (- (ms-y m) (ms-dy m))))
            (if (or (< nx -32.0)
                    (> nx (+ screen-w 32.0))
                    (< ny -24.0)
                    (> ny (+ screen-h 24.0)))
                (reset-missile! m)
                (begin
                  (gfx-sprite-pos (ms-inst m) nx ny)
                  (make-missile (ms-inst m) nx ny (ms-dx m) (ms-dy m) #t))))))
    missiles))

(define (spawn-missile! missiles x y dx dy)
  (cond
    ((null? missiles) '())
    ((not (ms-on? (car missiles)))
     (let ((inst (ms-inst (car missiles))))
       (play-generated-sound alien-shot-sound-id)
       (gfx-sprite-pos inst x y)
       (gfx-sprite-frame inst 0)
       (gfx-sprite-show inst)
       (cons (make-missile inst x y dx dy #t) (cdr missiles))))
    (else
     (cons (car missiles) (spawn-missile! (cdr missiles) x y dx dy)))))

(define (maybe-spawn-crawler-missile missiles crawlers frame)
  (if (or (not (= (modulo frame 96) 24))
          (null? crawlers))
      missiles
      (let* ((shot-index (modulo (quotient frame 96) (length crawlers)))
             (shooter (list-ref crawlers shot-index))
             (sx (- (cr-x shooter) 18.0))
             (sy (- (cr-y shooter) 18.0))
             (dx (+ 1.5 (* 0.25 (modulo shot-index 3))))
             (dy (+ 2.4 (* 0.3 (modulo (+ shot-index 1) 3)))))
        (if (or (< sx -40.0) (> sx (+ screen-w 40.0)))
            missiles
            (spawn-missile! missiles sx sy dx dy)))))

;;; ---- Player Shot Vectors ----
(define (make-player-shot inst x y dx dy active?) (vector inst x y dx dy active?))
(define (ps-inst p) (vector-ref p 0))
(define (ps-x    p) (vector-ref p 1))
(define (ps-y    p) (vector-ref p 2))
(define (ps-dx   p) (vector-ref p 3))
(define (ps-dy   p) (vector-ref p 4))
(define (ps-on?  p) (vector-ref p 5))

(define (reset-player-shot! p)
  (gfx-sprite-hide (ps-inst p))
  (gfx-sprite-pos (ps-inst p) -100.0 -100.0)
  (make-player-shot (ps-inst p) -100.0 -100.0 0.0 0.0 #f))

(define (update-player-shots! shots)
  (map
    (lambda (p)
      (if (not (ps-on? p))
          p
          (let* ((nx (+ (ps-x p) (ps-dx p)))
                 (ny (+ (ps-y p) (ps-dy p)))
                 (ndy (+ (ps-dy p) 0.28)))
            (if (or (< nx -24.0)
                    (> nx (+ screen-w 24.0))
                    (< ny -24.0)
                    (> ny (+ ground-y 34.0)))
                (reset-player-shot! p)
                (begin
                  (gfx-sprite-pos (ps-inst p) nx ny)
                  (make-player-shot (ps-inst p) nx ny (ps-dx p) ndy #t))))))
    shots))

(define (spawn-player-shot! shots x y dx dy)
  (cond
    ((null? shots) '())
    ((not (ps-on? (car shots)))
     (let ((inst (ps-inst (car shots))))
       (play-generated-sound player-shot-sound-id)
       (gfx-sprite-pos inst x y)
       (gfx-sprite-frame inst 0)
       (gfx-sprite-show inst)
       (cons (make-player-shot inst x y dx dy #t) (cdr shots))))
    (else
     (cons (car shots) (spawn-player-shot! (cdr shots) x y dx dy)))))

(define (maybe-spawn-player-shot shots ship-x ship-y fire? can-fire?)
  (if (and fire? can-fire?)
      (spawn-player-shot! shots (+ ship-x 34.0) (+ ship-y 2.0) 8.2 0.0)
      shots))

(define (enemy-burst-pal inst)
  (cond
    ((= (orbiter-pal-def inst) 2) 11)
    ((= (orbiter-pal-def inst) 3) 12)
    ((= (orbiter-pal-def inst) 4) 13)
    (else 10)))

(define (enemy-explosion-sound inst)
  (cond
    ((= (orbiter-pal-def inst) 2) fire-saucer-explode-sound-id)
    ((= (orbiter-pal-def inst) 3) acid-saucer-explode-sound-id)
    ((= (orbiter-pal-def inst) 4) gold-saucer-explode-sound-id)
    (else saucer-explode-sound-id)))

(define (crawler-burst-pal crawler)
  14)

(define (play-enemy-explosion! inst)
  (play-generated-sound (enemy-explosion-sound inst)))

(define (play-crawler-explosion!)
  (play-generated-sound crawler-explode-sound-id))

(define (play-orbiter-explosion!)
  (play-generated-sound orbiter-explode-sound-id))

(define (play-boss-hit!)
  (play-generated-sound boss-hit-sound-id))

(define (play-boss-explosion!)
  (play-generated-sound boss-explode-sound-id))

;;; ---- Alien Burst Vectors ----
(define (make-burst inst x y timer active?) (vector inst x y timer active?))
(define (burst-inst b) (vector-ref b 0))
(define (burst-x    b) (vector-ref b 1))
(define (burst-y    b) (vector-ref b 2))
(define (burst-timer b) (vector-ref b 3))
(define (burst-on?  b) (vector-ref b 4))

(define (reset-burst! b)
  (gfx-sprite-hide (burst-inst b))
  (gfx-sprite-pos (burst-inst b) -100.0 -100.0)
  (make-burst (burst-inst b) -100.0 -100.0 0 #f))

(define (update-bursts! bursts)
  (map
    (lambda (b)
      (if (not (burst-on? b))
          b
          (let ((next-timer (- (burst-timer b) 1)))
            (if (<= next-timer 0)
                (reset-burst! b)
                (make-burst (burst-inst b) (burst-x b) (burst-y b) next-timer #t)))))
    bursts))

(define (spawn-burst! bursts x y pal)
  (cond
    ((null? bursts) '())
    ((not (burst-on? (car bursts)))
     (let ((inst (burst-inst (car bursts))))
       (gfx-sprite-pal-override inst pal)
       (gfx-sprite-pos inst x y)
       (gfx-sprite-frame inst 0)
       (gfx-sprite-show inst)
       (cons (make-burst inst x y 14 #t) (cdr bursts))))
    (else
     (cons (car bursts) (spawn-burst! (cdr bursts) x y pal)))))

(define (spawn-crawler-burst! bursts x y pal)
  (let* ((base-y (+ y 8.0))
         (left-bursts (spawn-burst! bursts (- x 10.0) base-y pal)))
    (spawn-burst! left-bursts (+ x 10.0) (+ base-y 1.0) pal)))

(define (resolve-player-shot-hit shot enemies crawlers bursts frame)
  (if (not (ps-on? shot))
      (list shot enemies crawlers bursts 0)
      (let enemy-loop ((rest enemies) (done '()))
        (if (null? rest)
            (let crawler-loop ((c-rest crawlers) (c-done '()))
              (if (null? c-rest)
                  (list shot enemies crawlers bursts 0)
                  (let ((c (car c-rest)))
                    (if (hit-near? (ps-x shot) (ps-y shot) (cr-x c) (- (cr-y c) 20.0) 24.0 22.0)
                      (begin
                        (play-crawler-explosion!)
                        (list (reset-player-shot! shot)
                        enemies
                        (append (reverse c-done)
                          (cons (respawn-crawler! c frame) (cdr c-rest)))
                        (spawn-crawler-burst! bursts (cr-x c) (- (cr-y c) 22.0) (crawler-burst-pal c))
                        crawler-score))
                        (crawler-loop (cdr c-rest) (cons c c-done))))))
            (let ((e (car rest)))
              (if (hit-near? (ps-x shot) (ps-y shot) (ebx e) (eby e) 28.0 20.0)
                      (begin
                        (play-enemy-explosion! (ei e))
                        (list (reset-player-shot! shot)
                        (append (reverse done)
                          (cons (respawn-enemy! e frame) (cdr rest)))
                        crawlers
                        (spawn-burst! bursts (ebx e) (eby e) (enemy-burst-pal (ei e)))
                        saucer-score))
                  (enemy-loop (cdr rest) (cons e done))))))))

(define (resolve-player-shots! shots enemies crawlers bursts frame)
  (let loop ((rest shots) (done '()) (es enemies) (cs crawlers) (bs bursts) (score-gain 0))
    (if (null? rest)
        (list (reverse done) es cs bs score-gain)
        (let* ((result (resolve-player-shot-hit (car rest) es cs bs frame))
               (shot-1 (list-ref result 0))
               (enemies-1 (list-ref result 1))
               (crawlers-1 (list-ref result 2))
               (bursts-1 (list-ref result 3))
               (points (list-ref result 4)))
          (loop (cdr rest)
                (cons shot-1 done)
                enemies-1
                crawlers-1
                bursts-1
                (+ score-gain points))))))

(define (resolve-player-shot-boss-hit shot boss orbiters bursts)
  (if (not (ps-on? shot))
      (list shot boss orbiters bursts 0)
      (let orbiter-loop ((rest orbiters) (done '()))
        (if (null? rest)
            (if (and (boss-on? boss)
                     (orbiters-cleared? orbiters)
                     (hit-near? (ps-x shot) (ps-y shot) (boss-x boss) (boss-y boss) 56.0 34.0))
                (let* ((hp-left (- (boss-hp boss) 1))
                       (bursts-1 (spawn-burst! bursts (- (boss-x boss) 18.0) (boss-y boss) 13))
                       (bursts-2 (spawn-burst! bursts-1 (+ (boss-x boss) 18.0) (+ (boss-y boss) 6.0) 13)))
                  (if (<= hp-left 0)
                      (begin
                        (play-boss-explosion!)
                        (gfx-sprite-hide boss-inst)
                        (list (reset-player-shot! shot)
                              (make-boss #f (boss-x boss) (boss-y boss) 0 #t)
                              orbiters
                              (spawn-burst! bursts-2 (boss-x boss) (- (boss-y boss) 8.0) 13)
                              boss-score))
                      (begin
                        (play-boss-hit!)
                        (list (reset-player-shot! shot)
                              (make-boss #t (boss-x boss) (boss-y boss) hp-left #f)
                              orbiters
                              bursts-2
                              0))))
                (list shot boss orbiters bursts 0))
            (let ((o (car rest)))
              (if (and (orb-on? o)
                       (hit-near? (ps-x shot) (ps-y shot) (orb-x o) (orb-y o) 30.0 22.0))
                  (begin
                    (play-orbiter-explosion!)
                    (gfx-sprite-hide (orb-inst o))
                    (list (reset-player-shot! shot)
                          boss
                          (append (reverse done)
                                  (cons (make-orbiter (orb-inst o) (orb-phase o) (orb-x o) (orb-y o) #f)
                                        (cdr rest)))
                          (spawn-burst! bursts (orb-x o) (orb-y o) (enemy-burst-pal (orb-inst o)))
                          saucer-score))
                  (orbiter-loop (cdr rest) (cons o done))))))))

(define (resolve-player-shots-boss! shots boss orbiters bursts)
  (let loop ((rest shots) (done '()) (boss-state boss) (orbiter-state orbiters) (burst-state bursts) (score-gain 0))
    (if (null? rest)
        (list (reverse done) boss-state orbiter-state burst-state score-gain)
        (let* ((result (resolve-player-shot-boss-hit (car rest) boss-state orbiter-state burst-state))
               (shot-1 (list-ref result 0))
               (boss-1 (list-ref result 1))
               (orbiters-1 (list-ref result 2))
               (bursts-1 (list-ref result 3))
               (points (list-ref result 4)))
          (loop (cdr rest)
                (cons shot-1 done)
                boss-1
                orbiters-1
                bursts-1
                (+ score-gain points))))))

(define (initial-enemies)
  (list (make-enemy 1  860.0  96.0 3.2 0.0)
        (make-enemy 2 1060.0 172.0 4.0 1.6)
        (make-enemy 3 1280.0 118.0 3.6 3.2)
        (make-enemy 4 1480.0 210.0 4.8 4.8)))

(define (initial-crawlers)
  (list (make-crawler 5  140.0 378.0 1.2)
        (make-crawler 6  360.0 382.0 1.8)
        (make-crawler 7  580.0 376.0 1.4)
        (make-crawler 8  840.0 380.0 2.0)))

(define (initial-fireballs)
  (list (make-fireball 10 -100.0 -100.0 0.0 #f)
        (make-fireball 11 -100.0 -100.0 0.0 #f)
        (make-fireball 12 -100.0 -100.0 0.0 #f)
        (make-fireball 13 -100.0 -100.0 0.0 #f)
        (make-fireball 14 -100.0 -100.0 0.0 #f)
        (make-fireball 15 -100.0 -100.0 0.0 #f)))

(define (initial-missiles)
  (list (make-missile 16 -100.0 -100.0 0.0 0.0 #f)
        (make-missile 17 -100.0 -100.0 0.0 0.0 #f)
        (make-missile 18 -100.0 -100.0 0.0 0.0 #f)
        (make-missile 19 -100.0 -100.0 0.0 0.0 #f)
        (make-missile 20 -100.0 -100.0 0.0 0.0 #f)
        (make-missile 21 -100.0 -100.0 0.0 0.0 #f)))

(define (initial-player-shots)
  (list (make-player-shot 22 -100.0 -100.0 0.0 0.0 #f)
        (make-player-shot 23 -100.0 -100.0 0.0 0.0 #f)
        (make-player-shot 24 -100.0 -100.0 0.0 0.0 #f)
        (make-player-shot 25 -100.0 -100.0 0.0 0.0 #f)
        (make-player-shot 26 -100.0 -100.0 0.0 0.0 #f)
        (make-player-shot 27 -100.0 -100.0 0.0 0.0 #f)
        (make-player-shot 28 -100.0 -100.0 0.0 0.0 #f)
        (make-player-shot 29 -100.0 -100.0 0.0 0.0 #f)))

(define (initial-bursts)
  (list (make-burst 30 -100.0 -100.0 0 #f)
        (make-burst 31 -100.0 -100.0 0 #f)
        (make-burst 32 -100.0 -100.0 0 #f)
        (make-burst 33 -100.0 -100.0 0 #f)
        (make-burst 34 -100.0 -100.0 0 #f)
        (make-burst 35 -100.0 -100.0 0 #f)))

(define (apply-enemies! enemies)
  (map (lambda (e)
         (gfx-sprite-show (ei e))
         (gfx-sprite-pos (ei e) (ebx e) (eby e)))
       enemies))

(define (apply-crawlers! crawlers)
  (map (lambda (c)
         (gfx-sprite-show (cr-inst c))
         (gfx-sprite-alpha (cr-inst c) 1.0)
         (gfx-sprite-pos (cr-inst c) (cr-x c) (cr-y c)))
       crawlers))

(define (hide-enemy-sprites! enemies)
  (map (lambda (e) (gfx-sprite-hide (ei e))) enemies))

(define (hide-crawler-sprites! crawlers)
  (map (lambda (c) (gfx-sprite-hide (cr-inst c))) crawlers))

(define (hide-fireball-pool! fireballs)
  (map reset-fireball! fireballs))

(define (hide-missile-pool! missiles)
  (map reset-missile! missiles))

(define (hide-player-shot-pool! shots)
  (map reset-player-shot! shots))

(define (hide-burst-pool! bursts)
  (map reset-burst! bursts))

(define (hide-boss! orbiters)
  (gfx-sprite-hide boss-inst)
  (hide-orbiter-sprites! orbiters))

;;; ========================================================================
;;; Main Loop
;;; ========================================================================
(let main-loop
  ((frame    0)
   (back     1)           ; alternates 0 / 1 – we always draw to the back buffer
   (far-sc   0)
   (near-sc  0)
   (ship-x  80.0)
   (ship-y 210.0)
   (score    0)
   (lives    3)
   (crash-timer 0)
   (immune-timer 0)
   (fire-cooldown 0)
   (game-over? #f)
  (boss (initial-boss))
  (orbiters (initial-orbiters))
  (enemies (initial-enemies))
  (crawlers (initial-crawlers))
  (fireballs (initial-fireballs))
  (missiles (initial-missiles))
  (player-shots (initial-player-shots))
  (bursts (initial-bursts)))

  ;; -- Compose the back buffer --
  (gfx-set-target back)

  ;; 1. Full-screen background from pre-rendered cache (opaque blit)
  (gfx-blit back 0 0 2 0 0 screen-w screen-h)

  ;; 2. Far parallax buildings (transparent blit, slow scroll)
  (blit-layer back 3 far-sc)

  ;; 3. Near parallax buildings (transparent blit, fast scroll)
  (blit-layer back 4 near-sc)

  ;; 4. HUD overlay
  (gfx-rect 0 0 screen-w 26 30)
    (gfx-text 10 6 "SideCrawlers" 29)
    (gfx-text 180 6 (string-append "Score: " (number->string score)) 29)
    (gfx-text-small 318 8 "WASD / Arrows: move   Space: boost   Z/X: fire   Esc: quit" 20)
    (gfx-text 598 6 (string-append "Ships: " (number->string lives)) 29)
  (if (boss-on? boss)
      (if (orbiters-cleared? orbiters)
          (gfx-text 354 6 (string-append "Boss HP: " (number->string (boss-hp boss))) 23)
          (gfx-text 330 6 (boss-escort-label orbiters) 23))
      'done)
  (if (> immune-timer 0)
      (gfx-text 520 6 "IMMUNE" 23)
      'done)
  (if game-over?
      (if (and (boss-on? boss) (not (boss-defeated? boss)))
          (begin
            (gfx-rect 108 206 506 58 31)
            (gfx-text 128 220 "THE MOTHERSHIP TRIUMPHS!" 29)
            (gfx-text-small 150 242 "ESC TO QUIT OR SPACE TO START A NEW RUN" 20))
          (begin
            (gfx-rect 146 214 428 42 31)
            (gfx-text 156 226 "GAME OVER - ESC TO QUIT OR SPACE TO CONTINUE" 29)))
      'done)
  (if (boss-defeated? boss)
      (begin
        (gfx-rect 168 214 384 42 30)
        (gfx-text 182 226 "LEVEL CLEAR - ESC TO QUIT OR SPACE TO CONTINUE" 29))
      'done)

  ;; -- Show completed frame and wait for vsync --
  (gfx-flip)
  (gfx-vsync)

  ;; -- Input and state update --
  (let* ((key    (gfx-read-key))
         (up?    (or (gfx-key-pressed? 'up)    (gfx-key-pressed? 'w)))
         (down?  (or (gfx-key-pressed? 'down)  (gfx-key-pressed? 's)))
         (left?  (or (gfx-key-pressed? 'left)  (gfx-key-pressed? 'a)))
         (right? (or (gfx-key-pressed? 'right) (gfx-key-pressed? 'd)))
         (boost? (gfx-key-pressed? 'space))
         (fire?  (or (gfx-key-pressed? 'z) (gfx-key-pressed? 'x)))
         (spd    (if boost? 5.5 3.5))
         (sc-spd (if boost? 7 4))
         ;; clamp player to full screen width, keep fully above the ground band
         (nx (clamp (+ ship-x
                       (if right? spd 0.0)
                       (if left? (- spd) 0.0))
                    16.0
                    (- screen-w 80.0)))
         (ny (clamp (+ ship-y
                       (if down?  spd 0.0)
                       (if up?    (- spd) 0.0))
                    30.0
                    ship-max-y)))

    (if (> crash-timer 0)
        'done
        (gfx-sprite-pos 0 nx ny))
    (let* ((crashing? (> crash-timer 0))
           (immune? (> immune-timer 0))
          (victory? (boss-defeated? boss))
          (boss-celebrating? (and game-over? (boss-on? boss) (not (boss-defeated? boss))))
           (hit? (and (not crashing?)
                      (not immune?)
                      (not game-over?)
           (not victory?)
                      (gfx-sprite-overlap 1 2)))
           (lost-life? hit?)
           (next-lives (if lost-life? (max 0 (- lives 1)) lives))
           (next-game-over? (or game-over? (= next-lives 0)))
           (next-crash-timer (cond
                               (lost-life? 28)
                               ((> crash-timer 0) (- crash-timer 1))
                               (else 0)))
           (respawn? (and (= crash-timer 1) (not next-game-over?)))
         (next-immune-timer (cond
                  (respawn? 90)
                  ((> immune-timer 0) (- immune-timer 1))
                  (else 0)))
           (next-ship-x (cond
                          (respawn? 80.0)
                          (crashing? ship-x)
                          (else nx)))
           (next-ship-y (cond
                          (respawn? 210.0)
                          (crashing? ship-y)
                          (else ny)))
           (boss-start? (and (not next-game-over?)
                             (not victory?)
                             (boss-spawn-ready? frame score boss)))
           (boss-win-now? (and (not game-over?)
                               next-game-over?
                               (boss-on? boss)
                               (not (boss-defeated? boss))))
           (boss-transition (if boss-start?
                                (begin
                                  (music-play-id boss-theme-id)
                                  (hide-crawler-sprites! crawlers)
                                  (hide-fireball-pool! fireballs)
                                  (hide-missile-pool! missiles)
                                  1)
                                0))
           (next-boss-0 (cond
                          (boss-win-now? (begin
                                           (music-play-id boss-victory-theme-id)
                                           (hide-fireball-pool! fireballs)
                                           (hide-missile-pool! missiles)
                                           (hide-player-shot-pool! player-shots)
                                           (update-boss-victory! boss frame)))
                          (boss-start? (update-boss! (spawn-boss) frame))
                          (boss-celebrating? (update-boss-victory! boss frame))
                          ((boss-on? boss) (update-boss! boss frame))
                          (else boss)))
           (next-orbiters-0 (cond
                              (boss-win-now? (update-orbiters-victory! orbiters next-boss-0 frame))
                              (boss-start? (update-orbiters! (initial-orbiters) next-boss-0 frame))
                              (boss-celebrating? (update-orbiters-victory! orbiters next-boss-0 frame))
                              ((boss-on? next-boss-0) (update-orbiters! orbiters next-boss-0 frame))
                              (else orbiters)))
           (next-fire-cooldown-0 (if (> fire-cooldown 0)
                                     (- fire-cooldown 1)
                                     0))
           (next-enemies-0  (if (or next-game-over?
                                     (boss-on? next-boss-0)
                                     victory?)
                                enemies
                                (update-enemies! enemies frame)))
           (next-crawlers-0 (if (or next-game-over?
                                     (boss-on? next-boss-0)
                                     victory?)
                                crawlers
                                (update-crawlers! crawlers sc-spd frame)))
           (next-player-shots-0 (if (or next-game-over? victory? boss-celebrating?)
                                    player-shots
                                    (update-player-shots! player-shots)))
           (next-player-shots-1 (if (or crashing? game-over? hit?)
                                    next-player-shots-0
                                    (maybe-spawn-player-shot next-player-shots-0
                                                             next-ship-x
                                                             next-ship-y
                                                             fire?
                                                             (= next-fire-cooldown-0 0))))
           (next-bursts-0 (update-bursts! bursts))
                                     (normal-shot-resolution (if (or (boss-on? next-boss-0) victory?)
                                                   '()
                                                   (resolve-player-shots! next-player-shots-1
                                                              next-enemies-0
                                                              next-crawlers-0
                                                              next-bursts-0
                                                              frame)))
                                     (boss-shot-resolution (if (boss-on? next-boss-0)
                                                 (resolve-player-shots-boss! next-player-shots-1
                                                               next-boss-0
                                                               next-orbiters-0
                                                               next-bursts-0)
                                                 '()))
                                     (next-player-shots (if (boss-on? next-boss-0)
                                                (list-ref boss-shot-resolution 0)
                                                (if victory? next-player-shots-1 (list-ref normal-shot-resolution 0))))
                                     (next-enemies (if (boss-on? next-boss-0)
                                             next-enemies-0
                                             (if victory? enemies (list-ref normal-shot-resolution 1))))
                                     (next-crawlers (if (boss-on? next-boss-0)
                                              next-crawlers-0
                                              (if victory? crawlers (list-ref normal-shot-resolution 2))))
                                     (next-boss (if (boss-on? next-boss-0)
                                            (list-ref boss-shot-resolution 1)
                                            next-boss-0))
                                     (next-orbiters (if (boss-on? next-boss-0)
                                              (list-ref boss-shot-resolution 2)
                                              next-orbiters-0))
                                     (next-bursts (if (boss-on? next-boss-0)
                                            (list-ref boss-shot-resolution 3)
                                            (if victory? next-bursts-0 (list-ref normal-shot-resolution 3))))
                                     (score-gain (if (boss-on? next-boss-0)
                                             (list-ref boss-shot-resolution 4)
                                             (if victory? 0 (list-ref normal-shot-resolution 4))))
           (next-score (+ score score-gain))
           (next-victory? (boss-defeated? next-boss))
           (next-fire-cooldown (if (and fire?
                                        (= next-fire-cooldown-0 0)
                                        (not crashing?)
                                        (not game-over?)
                                                  (not victory?)
                                        (not hit?))
                    16
                                   next-fire-cooldown-0))
           (next-fireballs-0 (if boss-win-now?
                                 (initial-fireballs)
                                 (if boss-start?
                                 (initial-fireballs)
                                 (if (or next-game-over? victory?)
                                 fireballs
                                 (update-fireballs! fireballs sc-spd)))))
           (next-fireballs-1 (if (or crashing? game-over? hit?)
                               next-fireballs-0
                                               (if (boss-on? next-boss)
                                                 (maybe-spawn-boss-fireballs next-fireballs-0 next-boss next-orbiters frame)
                                                 (maybe-spawn-fireball next-fireballs-0 next-enemies frame))))
           (next-fireballs (if next-victory?
                               (begin
                                 (hide-fireball-pool! next-fireballs-1)
                                 (initial-fireballs))
                               next-fireballs-1))
           (next-missiles-0 (if boss-win-now?
                                (initial-missiles)
                                (if boss-start?
                                (initial-missiles)
                                (if (or next-game-over? victory?)
                                missiles
                                (update-missiles! missiles sc-spd)))))
           (next-missiles-1 (if (or crashing? game-over? hit?)
                              next-missiles-0
                                              (if (boss-on? next-boss)
                                                next-missiles-0
                                  (maybe-spawn-crawler-missile next-missiles-0 next-crawlers frame))))
           (next-missiles (if next-victory?
                              (begin
                                (hide-missile-pool! next-missiles-1)
                                (initial-missiles))
                              next-missiles-1))
           (next-player-shots-final (if (or next-victory? boss-win-now?)
                                        (begin
                                          (hide-player-shot-pool! next-player-shots)
                                          (initial-player-shots))
                                        next-player-shots)))
      (gfx-sprite-sync)

      (if (and (not crashing?) (> immune-timer 0))
          (gfx-sprite-alpha 0 (if (= (modulo frame 6) 0) 0.35 1.0))
          'done)

      (if hit?
          (begin
            (play-generated-sound player-explode-sound-id)
            (gfx-sprite-hide 0)
            (gfx-sprite-pos 9 ship-x ship-y)
            (gfx-sprite-frame 9 0)
            (gfx-sprite-animate 9 0.38)
            (gfx-sprite-show 9))
          'done)

      (if respawn?
          (begin
            (play-generated-sound player-respawn-sound-id)
            (gfx-sprite-hide 9)
            (gfx-sprite-show 0)
            (gfx-sprite-pos 0 80.0 210.0)
            (gfx-sprite-rot 0 0.0)
            (gfx-sprite-alpha 0 1.0))
          'done)

      (if (and (= next-immune-timer 0) immune?)
          (gfx-sprite-alpha 0 1.0)
          'done)

      (if (and next-game-over? (= next-crash-timer 0))
          (gfx-sprite-hide 9)
          'done)

      (if (or (eq? key 'esc)
              (eq? key 'escape)
              (not (gfx-active?)))
          'done
          (if (and (or game-over? victory?) boost?)
              (let ((restart-enemies (initial-enemies))
                    (restart-crawlers (initial-crawlers))
                    (restart-fireballs (initial-fireballs))
                    (restart-missiles (initial-missiles))
                    (restart-player-shots (initial-player-shots))
                    (restart-bursts (initial-bursts))
                    (restart-boss (initial-boss))
                    (restart-orbiters (initial-orbiters)))
                (music-play-id game-start-theme-id)
                (gfx-sprite-hide 9)
                (gfx-sprite-show 0)
                (gfx-sprite-pos 0 80.0 210.0)
                (gfx-sprite-rot 0 0.0)
                (gfx-sprite-alpha 0 1.0)
                (apply-enemies! restart-enemies)
                (apply-crawlers! restart-crawlers)
                (hide-fireball-pool! fireballs)
                (hide-missile-pool! missiles)
                (hide-player-shot-pool! player-shots)
                (hide-burst-pool! bursts)
                (hide-boss! orbiters)
                (main-loop
                  0
                  1
                  0
                  0
                  80.0
                  210.0
                  0
                  3
                  0
                  0
                  0
                  #f
                  restart-boss
                  restart-orbiters
                  restart-enemies
                  restart-crawlers
                  restart-fireballs
                  restart-missiles
                  restart-player-shots
                  restart-bursts))
              
          (main-loop
            (+ frame 1)
            (toggle-buf back)                     ; flip which buffer we draw to
            (wrap-int (+ far-sc 1)       buf-w)   ; far layer: 1px/frame
            (wrap-int (+ near-sc sc-spd) buf-w)   ; near layer: faster
            next-ship-x
            next-ship-y
            next-score
            next-lives
            next-crash-timer
            next-immune-timer
            next-fire-cooldown
            next-game-over?
            next-boss
            next-orbiters
            next-enemies
            next-crawlers
            next-fireballs
            next-missiles
            next-player-shots-final
            next-bursts))))))
