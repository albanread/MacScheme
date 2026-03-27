; audio demo
;
(audio-init)

(define coin (sound-coin 1.1 0.1))
(define jump (sound-jump 0.9 0.14))
(define shoot (sound-shoot 1 0.08))
(define powerup (sound-powerup 1 0.3))

(sound-volume 0.8)

(sound-play coin)
(gfx-wait 15)
(sound-play coin)
(gfx-wait 15)
(sound-play jump)
(gfx-wait 30)
(sound-play shoot 0.7 -0.3)
(gfx-wait 20)
(sound-play powerup 0.9 0.2)
(gfx-wait 60)
