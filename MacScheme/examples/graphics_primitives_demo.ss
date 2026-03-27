(gfx-screen 320 160 3)
(gfx-reset)

(gfx-clear 10 18 34)

(gfx-rect 12 12 232 136 5)

(gfx-rect-outline 12 12 232 136 25)

(gfx-text 20 20 "MacScheme Graphics Demo" 21)
(gfx-text-small 20 40 "pixels, lines, shapes, fill, and text" 1)

(gfx-line 20 60 236 60 24)
(gfx-line 20 61 236 61 25)

(gfx-rect 24 72 40 24 18)
(gfx-rect-outline 72 72 40 24 21)
(gfx-circle 136 84 14 19)
(gfx-circle-outline 136 84 18 17)
(gfx-ellipse 188 84 22 14 20)
(gfx-ellipse-outline 188 84 26 18 17)
(gfx-triangle 48 132 20 104 76 104 23)
(gfx-triangle-outline 96 132 72 100 120 100 17)

(gfx-rect-outline 152 106 64 28 17)
(gfx-fill 184 120 22)
(gfx-text-int 24 112 2026 30)
(gfx-text-num-small 24 128 3.14159 28)

(do ((x 0 (+ x 1)))
    ((> x 15))
  (gfx-rect (+ 24 (* x 12)) 144 10 8 (+ 16 x)))

(gfx-flip)
