; An aggregate passed in memory (byval), its copy forwarded at each level
; in the caller's own incoming slot.
%quad = type { i64, i64, i64, i64 }

define internal tailcc i64 @quad(i64 %n, i64 %acc, ptr byval(%quad) align 8 %q) {
entry:
  %done = icmp eq i64 %n, 0
  br i1 %done, label %out, label %more
out:
  ret i64 %acc
more:
  %slot = and i64 %n, 3
  %at = getelementptr %quad, ptr %q, i32 0, i32 0
  %elem = getelementptr i64, ptr %at, i64 %slot
  %v = load i64, ptr %elem
  %acc1 = add i64 %acc, %v
  %n1 = sub i64 %n, 1
  %r = musttail call tailcc i64 @quad(i64 %n1, i64 %acc1, ptr byval(%quad) align 8 %q)
  ret i64 %r
}

@fmt = private constant [6 x i8] c"%lld\0A\00"
declare i32 @printf(ptr, ...)
declare i64 @atol(ptr)

define i32 @main(i32 %argc, ptr %argv) {
  %at = getelementptr ptr, ptr %argv, i64 1
  %text = load ptr, ptr %at
  %n = call i64 @atol(ptr %text)
  %q = alloca %quad, align 8
  store %quad { i64 1, i64 2, i64 3, i64 4 }, ptr %q
  %r = call tailcc i64 @quad(i64 %n, i64 0, ptr byval(%quad) align 8 %q)
  %printed = call i32 (ptr, ...) @printf(ptr @fmt, i64 %r)
  ret i32 0
}
