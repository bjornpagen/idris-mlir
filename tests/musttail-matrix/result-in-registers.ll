; A result of two words returned in registers through every level.
define internal tailcc { i64, i64 } @pair(i64 %n, i64 %x, i64 %y) {
entry:
  %done = icmp eq i64 %n, 0
  br i1 %done, label %out, label %more
out:
  %s0 = insertvalue { i64, i64 } undef, i64 %x, 0
  %s1 = insertvalue { i64, i64 } %s0, i64 %y, 1
  ret { i64, i64 } %s1
more:
  %n1 = sub i64 %n, 1
  %x1 = add i64 %x, 1
  %y1 = add i64 %y, 2
  %r = musttail call tailcc { i64, i64 } @pair(i64 %n1, i64 %x1, i64 %y1)
  ret { i64, i64 } %r
}

@fmt = private constant [6 x i8] c"%lld\0A\00"
declare i32 @printf(ptr, ...)
declare i64 @atol(ptr)

define i32 @main(i32 %argc, ptr %argv) {
  %at = getelementptr ptr, ptr %argv, i64 1
  %text = load ptr, ptr %at
  %n = call i64 @atol(ptr %text)
  %p = call tailcc { i64, i64 } @pair(i64 %n, i64 0, i64 0)
  %x = extractvalue { i64, i64 } %p, 0
  %y = extractvalue { i64, i64 } %p, 1
  %r = add i64 %x, %y
  %printed = call i32 (ptr, ...) @printf(ptr @fmt, i64 %r)
  ret i32 0
}
