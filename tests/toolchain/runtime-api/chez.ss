;; rule: TC-RT-4, SEM-STR-2, SEM-INT-3
;; What Chez computes for the operations api.c runs, in the same format:
;; Integer's div and mod are blodwen-euclidDiv and blodwen-euclidMod of
;; Idris's Chez support code, and the string operations are those the Chez
;; backend uses (string-substr and string-cons as support.ss defines them).
(define out (transcoded-port (standard-output-port) (make-transcoder (utf-8-codec))))
(define (say . xs) (for-each (lambda (x) (display x out)) xs))
(define (euclid-div a b)
  (let ([q (quotient a b)] [r (remainder a b)])
    (if (< r 0) (if (> b 0) (- q 1) (+ q 1)) q)))
(define (euclid-mod a b)
  (let ([r (remainder a b)])
    (if (< r 0) (if (> b 0) (+ r b) (- r b)) r)))
(define (wrap64 n)
  (let ([m (modulo n (expt 2 64))]) (if (>= m (expt 2 63)) (- m (expt 2 64)) m)))
(define (string-substr off len s)
  (let* ([l (string-length s)] [b (max 0 off)] [x (max 0 len)] [end (min l (+ b x))])
    (if (> b l) "" (substring s b end))))
(define (quoted s) (string-append "\"" s "\""))
(define bigs
  '(0 1 -1 7 -7 2 -2 4611686018427387903 4611686018427387904 -4611686018427387904
    -4611686018427387905 9223372036854775807 9223372036854775808 -9223372036854775808
    18446744073709551616 123456789012345678901234567890 -98765432109876543210987654321
    340282366920938463463374607431768211457))
(define ops
  (list (cons "add" +) (cons "sub" -) (cons "mul" *) (cons "div" euclid-div)
        (cons "mod" euclid-mod) (cons "and" logand) (cons "or" logor) (cons "xor" logxor)))
(for-each
  (lambda (a)
    (for-each
      (lambda (b)
        (for-each
          (lambda (op)
            (unless (and (member (car op) '("div" "mod")) (= b 0))
              (say (car op) " " ((cdr op) a b) "\n")))
          ops)
        (say "compare " (cond [(< a b) -1] [(> a b) 1] [else 0]) "\n"))
      bigs)
    (say "neg " (- a) " to_int " (wrap64 a) " to_double " (number->string (exact->inexact a)) "\n"))
  bigs)
(for-each
  (lambda (x)
    (say "from_double " (exact (truncate x)) " show " (quoted (number->string x)) "\n"))
  '(0.0 -0.0 0.5 -0.5 123.9 -123.9 4.6e18 -1.5e19 1e300 2.5e-310))
(define strings
  (list "" "a" "hello" "h\xe9;llo w\xf6;rld" "\x65e5;\x672c;\x8a9e;" "\x1f600;x" "ab"))
(for-each
  (lambda (s)
    (let ([n (string-length s)])
      (say "length " n " chars")
      (for-each (lambda (c) (say " " (char->integer c))) (string->list s))
      (when (> n 0)
        (say " head " (char->integer (string-ref s 0)) " tail " (quoted (substring s 1 n))))
      (say " reverse " (quoted (list->string (reverse (string->list s))))
           " cons " (quoted (string-append (string (integer->char #xe9)) s)) "\n")
      (do ([start -2 (+ start 3)]) ((> start 7))
        (do ([len -1 (+ len 5)]) ((> len 9))
          (say "substr " (quoted (string-substr start len s)) "\n")))
      (say (quoted (string-substr 1 (- (expt 2 63) 1) s)) "\n")
      (for-each
        (lambda (t)
          (say "compare " (cond [(string<? s t) -1] [(string>? s t) 1] [else 0])
               " append " (quoted (string-append s t)) "\n"))
        strings)))
  strings)
(for-each
  (lambda (n)
    (say "show " (quoted (number->string n)) " " (quoted (number->string (modulo n (expt 2 64))))
         " " (quoted (string (integer->char (+ (logand n #xffff) #x41)))) "\n"))
  (list 0 5 -5 9223372036854775807 -9223372036854775808 255))
(flush-output-port out)
