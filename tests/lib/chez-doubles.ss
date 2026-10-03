;; Chez's text of a Double, read as this compiler writes it. The stock Chez
;; backend writes a Double with Chez's number->string, and so does Idris's
;; evaluator, which runs on Chez; this compiler writes the same digits but
;; where tests/lib/chez-divergences says the two differ:
;;
;;   double-special-text      Chez's +inf.0, -inf.0 and +nan.0 are inf, -inf
;;                            and nan;
;;   double-subnormal-suffix  Chez ends a subnormal with its precision in
;;                            bits, 5e-324|1, which this compiler does not;
;;   double-tie-even          where a double is exactly halfway between two
;;                            shortest texts that both read back as it, Chez
;;                            writes the one larger in magnitude and this
;;                            compiler the one whose last digit is even.
;;
;;   chezscheme --script tests/lib/chez-doubles.ss < OUTPUT
;;
;; copies OUTPUT, the output of a program the stock backend built or of the
;; evaluator, to standard output with each maximal run of the characters a
;; Chez flonum is written with that is exactly Chez's text of a double
;; replaced by this compiler's text of that double: a comparison with this
;; compiler's output then sees only what the classes do not explain.

;; This compiler's text of the double x, from Chez's.
(define (ours x)
  (cond
    [(nan? x) "nan"]
    [(infinite? x) (if (fl> x 0.0) "inf" "-inf")]
    [else (even-tie x (without-precision (number->string x)))]))

(define (index-of s c)
  (let loop ([i 0])
    (cond [(= i (string-length s)) #f]
          [(char=? (string-ref s i) c) i]
          [else (loop (+ i 1))])))

(define (without-precision s)
  (let ([bar (index-of s #\|)])
    (if bar (substring s 0 bar) s)))

;; s is Chez's text of the finite x, without a precision. Its last
;; significant digit is its last digit from 1 to 9, before any exponent;
;; where x is exactly half a unit of that digit below the value of s, and
;; one unit less reads back as x too, the digit is the larger candidate of
;; a tie, and an odd one becomes the even one below it.
(define (even-tie x s)
  (let* ([e-at (index-of s #\e)]
         [mantissa (if e-at (substring s 0 e-at) s)]
         [exponent (if e-at (string->number (substring s (+ e-at 1) (string-length s))) 0)]
         [point (or (index-of mantissa #\.) (string-length mantissa))]
         [last (let loop ([i (- (string-length mantissa) 1)])
                 (cond [(< i 0) #f]
                       [(memv (string-ref mantissa i) (string->list "123456789")) i]
                       [else (loop (- i 1))]))])
    (if (not last)
        s
        (let* ([unit (expt 10 (+ exponent point (- last) (if (< last point) -1 0)))]
               [magnitude (abs (string->number (string-append "#e" s)))]
               [digit (- (char->integer (string-ref mantissa last)) (char->integer #\0))])
          (if (and (odd? digit)
                   (= (abs (exact x)) (- magnitude (/ unit 2)))
                   (= (inexact (- magnitude unit)) (abs x)))
              (let ([t (string-copy s)])
                (string-set! t last (integer->char (+ (char->integer #\0) digit -1)))
                t)
              s)))))

;; The output is read and written as bytes, which copies any text as it is:
;; a flonum is written in ASCII.
(define flonum-bytes (map char->integer (string->list "0123456789.e+-|infa")))

;; A run that is exactly Chez's text of a double, as this compiler's text.
(define (read-run run)
  (let ([x (string->number run)])
    (if (and (flonum? x) (string=? (number->string x) run)) (ours x) run)))

(let ([in (standard-input-port)] [out (standard-output-port)])
  (let loop ([run '()])
    (let ([b (get-u8 in)])
      (cond
        [(and (not (eof-object? b)) (memv b flonum-bytes)) (loop (cons b run))]
        [else
         (unless (null? run)
           (let ([text (read-run (list->string (map integer->char (reverse run))))])
             (put-bytevector out (string->utf8 text))))
         (unless (eof-object? b)
           (put-u8 out b)
           (loop '()))])))
  (flush-output-port out))
