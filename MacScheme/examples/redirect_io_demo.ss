(define (demo-divider title)
  (newline)
  (display "--- ")
  (display title)
  (display " ---")
  (newline))

(demo-divider "display")
(display "Hello from display")
(newline)

(demo-divider "write")
(write '(alpha beta gamma))
(newline)

(demo-divider "printf")
(printf "2 + 3 = ~a~n" (+ 2 3))
(printf "factorial-ish sample: ~a~n" (apply * '(1 2 3 4 5)))

(demo-divider "current-error-port")
(fprintf (current-error-port) "This line is routed through current-error-port.~n")

(demo-divider "mixed output")
(display "About to return a final value after several side effects...")
(newline)

'io-demo-complete
