(audio-init)

(define fanfare
  (abc
    "X:1"
    "T:Fanfare"
    "M:4/4"
    "L:1/8"
    "Q:1/4=160"
    "K:C"
    "C2 E2 G2 c'2 | b2 g2 e2 c2 |"))

(define fanfare-sound
  (music-render fanfare))

(sound-play fanfare-sound 0.9)
(gfx-wait 90)
