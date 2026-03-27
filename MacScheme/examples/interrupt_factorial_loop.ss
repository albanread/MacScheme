(define (factorial n)
  (let loop ((k n) (acc 1))
    (if (<= k 1)
        acc
        (loop (- k 1) (* acc k)))))

(let loop ((n 7))
  (display n)
  (display "! = ")
  (write (factorial n))
  (newline)
  (loop (+ n 1)))
