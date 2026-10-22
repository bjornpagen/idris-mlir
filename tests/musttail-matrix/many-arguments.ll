; More arguments than any target passes in registers: the tail call must
; pass the rest on the stack in the caller's own incoming area, which the
; callee pops, and still not grow the stack. The arguments rotate, so each
; is read at its new position.
define internal tailcc i64 @count(i64 %n, i64 %acc, i64 %a, i64 %b, i64 %c, i64 %d, i64 %e, i64 %f, i64 %g, i64 %h, i64 %i, i64 %j) {
entry:
  %done = icmp eq i64 %n, 0
  br i1 %done, label %out, label %more
out:
  ret i64 %acc
more:
  %n1 = sub i64 %n, 1
  %acc1 = add i64 %acc, %a
  %r = musttail call tailcc i64 @count(i64 %n1, i64 %acc1, i64 %b, i64 %c, i64 %d, i64 %e, i64 %f, i64 %g, i64 %h, i64 %i, i64 %j, i64 %a)
  ret i64 %r
}

@fmt = private constant [6 x i8] c"%lld\0A\00"
declare i32 @printf(ptr, ...)
declare i64 @atol(ptr)

define i32 @main(i32 %argc, ptr %argv) {
  %at = getelementptr ptr, ptr %argv, i64 1
  %text = load ptr, ptr %at
  %n = call i64 @atol(ptr %text)
  %r = call tailcc i64 @count(i64 %n, i64 0, i64 1, i64 2, i64 3, i64 4, i64 5, i64 6, i64 7, i64 8, i64 9, i64 10)
  %printed = call i32 (ptr, ...) @printf(ptr @fmt, i64 %r)
  ret i32 0
}
