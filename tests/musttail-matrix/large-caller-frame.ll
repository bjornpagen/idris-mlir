; A caller whose frame is far larger than its callee's, 16 KiB of locals,
; in a cycle with a callee of almost none: each tail call gives the large
; frame back before the small one is laid down, so a stack of a few pages
; holds the cycle.
define internal tailcc i64 @wide(i64 %n, i64 %acc) {
entry:
  %buf = alloca [16384 x i8], align 16
  %index = and i64 %n, 16383
  %cell = getelementptr [16384 x i8], ptr %buf, i64 0, i64 %index
  store volatile i8 1, ptr %cell
  %v = load volatile i8, ptr %cell
  %v64 = zext i8 %v to i64
  %done = icmp eq i64 %n, 0
  br i1 %done, label %out, label %more
out:
  ret i64 %acc
more:
  %n1 = sub i64 %n, 1
  %acc1 = add i64 %acc, %v64
  %r = musttail call tailcc i64 @narrow(i64 %n1, i64 %acc1)
  ret i64 %r
}

define internal tailcc i64 @narrow(i64 %n, i64 %acc) {
entry:
  %done = icmp eq i64 %n, 0
  br i1 %done, label %out, label %more
out:
  ret i64 %acc
more:
  %n1 = sub i64 %n, 1
  %acc1 = add i64 %acc, 1
  %r = musttail call tailcc i64 @wide(i64 %n1, i64 %acc1)
  ret i64 %r
}

@fmt = private constant [6 x i8] c"%lld\0A\00"
declare i32 @printf(ptr, ...)
declare i64 @atol(ptr)

define i32 @main(i32 %argc, ptr %argv) {
  %at = getelementptr ptr, ptr %argv, i64 1
  %text = load ptr, ptr %at
  %n = call i64 @atol(ptr %text)
  %r = call tailcc i64 @wide(i64 %n, i64 0)
  %printed = call i32 (ptr, ...) @printf(ptr @fmt, i64 %r)
  ret i32 0
}
