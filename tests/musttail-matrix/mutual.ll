; Two functions in a cycle of tail calls.
define internal tailcc i64 @ping(i64 %n, i64 %acc) {
entry:
  %done = icmp eq i64 %n, 0
  br i1 %done, label %out, label %more
out:
  ret i64 %acc
more:
  %n1 = sub i64 %n, 1
  %acc1 = add i64 %acc, 1
  %r = musttail call tailcc i64 @pong(i64 %n1, i64 %acc1)
  ret i64 %r
}

define internal tailcc i64 @pong(i64 %n, i64 %acc) {
entry:
  %done = icmp eq i64 %n, 0
  br i1 %done, label %out, label %more
out:
  ret i64 %acc
more:
  %n1 = sub i64 %n, 1
  %acc1 = add i64 %acc, 2
  %r = musttail call tailcc i64 @ping(i64 %n1, i64 %acc1)
  ret i64 %r
}

@fmt = private constant [6 x i8] c"%lld\0A\00"
declare i32 @printf(ptr, ...)
declare i64 @atol(ptr)

define i32 @main(i32 %argc, ptr %argv) {
  %at = getelementptr ptr, ptr %argv, i64 1
  %text = load ptr, ptr %at
  %n = call i64 @atol(ptr %text)
  %r = call tailcc i64 @ping(i64 %n, i64 0)
  %printed = call i32 (ptr, ...) @printf(ptr @fmt, i64 %r)
  ret i32 0
}
