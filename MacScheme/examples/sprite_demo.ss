(gfx-screen 640 320  3)
(gfx-reset)

; `gfx-sprite` creates the instance and makes it visible immediately.

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

(gfx-sprite-palette 0 2 255 210 40)
(gfx-sprite-palette 0 3 255 120 40)

(gfx-sprite 0 0 32 60)
(gfx-sprite 1 0 96 84)
(gfx-sprite 2 0 160 52)
(gfx-sprite-scale 1 1.5 1.5)
(gfx-sprite-scale 2 2 2)
(gfx-sprite-alpha 2 0.85)

(let loop ((frame 0))
  (gfx-clear 8 12 28)
  (gfx-text 12 10 "MacScheme Sprite Demo" 21)
  (gfx-text-small 12 28 "row-authored sprites, scaling, motion, and sync" 30)

  (gfx-sprite-pos 0 (+ 24 (* 0.3 frame)) (+ 62 (* 10 (sin (* frame 0.08)))))
  (gfx-sprite-pos 1 (+ 110 (* 18 (sin (* frame 0.05)))) (+ 84 (* 6 (cos (* frame 0.09)))))
  (gfx-sprite-pos 2 (+ 184 (* 0.18 frame)) (+ 46 (* 14 (sin (* frame 0.04)))))
  (gfx-sprite-rot 1 (* frame 2))
  (gfx-sprite-rot 2 (* frame -1.2))
  (gfx-sprite-sync)
  (gfx-flip)
  (gfx-wait 1)
  (if (< frame 480)
      (loop (+ frame 1))
      'done))
