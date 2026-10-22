; A result returned through memory: each level forwards the caller's
; result slot to the next, and the last writes it.
%big = type { i64, i64, i64, i64, i64 }

define internal tailcc void @fill(ptr sret(%big) %out, i64 %n, i64 %acc) {
entry:
  %done = icmp eq i64 %n, 0
  br i1 %done, label %store, label %more
store:
  %first = getelementptr %big, ptr %out, i32 0, i32 0
  store i64 %acc, ptr %first
  %last = getelementptr %big, ptr %out, i32 0, i32 4
  %twice = mul i64 %acc, 2
  store i64 %twice, ptr %last
  ret void
more:
  %n1 = sub i64 %n, 1
  %acc1 = add i64 %acc, 3
  musttail call tailcc void @fill(ptr sret(%big) %out, i64 %n1, i64 %acc1)
  ret void
}

@fmt = private constant [6 x i8] c"%lld\0A\00"
declare i32 @printf(ptr, ...)
declare i64 @atol(ptr)

define i32 @main(i32 %argc, ptr %argv) {
  %at = getelementptr ptr, ptr %argv, i64 1
  %text = load ptr, ptr %at
  %n = call i64 @atol(ptr %text)
  %slot = alloca %big, align 8
  call tailcc void @fill(ptr sret(%big) %slot, i64 %n, i64 0)
  %first = getelementptr %big, ptr %slot, i32 0, i32 0
  %f0 = load i64, ptr %first
  %last = getelementptr %big, ptr %slot, i32 0, i32 4
  %f4 = load i64, ptr %last
  %r = add i64 %f0, %f4
  %printed = call i32 (ptr, ...) @printf(ptr @fmt, i64 %r)
  ret i32 0
}
