(gfx-screen 640 320 3)
(gfx-reset)

; Click the graphics pane/window if it needs focus.
; Arrow keys or WASD move the ship.
; Space lights it up, Escape quits.

(define (clamp n lo hi)
  (max lo (min hi n)))

(sprite-from-rows! 0
  '("....33....."
    "...3333...."
    "..336633..."
    ".33666633.."
    "3366666633."
    "...66.66..."
    "...22.22..."))

(gfx-sprite-palette 0 2 120 220 255)
(gfx-sprite-palette 0 3 255 245 160)
(gfx-sprite-palette 0 6 255 140 80)

(gfx-sprite 0 0 320 160)
(gfx-sprite-anchor 0 0.5 0.5)
(gfx-sprite-scale 0 2 2)
(gfx-sprite-priority 0 8)

(let loop ((x 320)
           (y 160)
           (tick 0)
           (last-key 'none))
  (let* ((pressed-key (gfx-read-key))
         (last-key (if pressed-key pressed-key last-key))
         (left? (or (gfx-key-pressed? 'left) (gfx-key-pressed? 'a)))
         (right? (or (gfx-key-pressed? 'right) (gfx-key-pressed? 'd)))
         (up? (or (gfx-key-pressed? 'up) (gfx-key-pressed? 'w)))
         (down? (or (gfx-key-pressed? 'down) (gfx-key-pressed? 's)))
         (fire? (gfx-key-pressed? 'space))
         (dx (+ (if left? -3 0) (if right? 3 0)))
         (dy (+ (if up? -3 0) (if down? 3 0)))
         (next-x (clamp (+ x dx) 16 624))
         (next-y (clamp (+ y dy) 16 304)))
    (if (or (eq? pressed-key 'escape) (eq? pressed-key 'esc) (not (gfx-active?)))
        'done
        (begin
          (gfx-clear 8 12 28)
          (gfx-text 14 10 "MacScheme Input Demo" 21)
          (gfx-text-small 14 28 "Move: arrows or WASD   Fire: space   Quit: escape" 30)
          (gfx-text-small 14 44 "If keys do nothing, click in the graphics pane/window once." 26)
          (gfx-text-small 14 68 (string-append "last key: " (symbol->string last-key)) 28)

          (gfx-sprite-pos 0 next-x next-y)
          (gfx-sprite-rot 0 (* 4 (sin (* tick 0.08))))

          (if fire?
              (begin
                (gfx-sprite-glow 0 4 1.8 255 180 90)
                (gfx-text-small 14 88 "fire: ON" 24))
              (begin
                (gfx-sprite-fx-off 0)
                (gfx-text-small 14 88 "fire: off" 18)))

          (gfx-text-small 14 108 (string-append "x=" (number->string next-x) "  y=" (number->string next-y)) 29)
          (gfx-sprite-sync)
          (gfx-flip)
          (gfx-wait 1)
          (loop next-x next-y (+ tick 1) last-key)))))
