(audio-init)

(define theme
  (abc
    "X:1"
    "T:MacScheme Theme"
    "M:4/4"
    "L:1/8"
    "Q:1/4=144"
    "K:C"
    "V:1 name=Lead program=80"
    "V:2 name=Bass program=38"
    "[V:1] c2 e2 g2 c'2 | b2 a2 g2 e2 | f2 a2 g2 e2 | d2 e2 c4 |"
    "[V:2] C,2 z2 G,,2 z2 | A,,2 z2 E,,2 z2 | F,,2 z2 G,,2 z2 | C,2 z2 C,,4 |"))

(define theme-id (music-load theme))

(music-volume 0.75)
(music-play-id theme-id)
