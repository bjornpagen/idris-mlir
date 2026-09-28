;; rule: SEM-DBL-5
;; Prints number->string of each double whose bits (hex, one per line) are in
;; the file named by the first argument, one per line.
(let ([in (open-input-file (car (command-line-arguments)))]
      [bv (make-bytevector 8)])
  (let loop ()
    (let ([line (get-line in)])
      (unless (eof-object? line)
        (bytevector-u64-set! bv 0 (string->number line 16) 'little)
        (display (number->string (bytevector-ieee-double-ref bv 0 'little)))
        (newline)
        (loop)))))
