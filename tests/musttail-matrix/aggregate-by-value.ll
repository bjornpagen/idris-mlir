; An aggregate passed by value, ten words that no target passes all in
; registers: split across registers and the stack, and rotated at each
; level as many-arguments.ll rotates its words.
define internal tailcc i64 @agg(i64 %n, i64 %acc, [10 x i64] %a) {
entry:
  %done = icmp eq i64 %n, 0
  br i1 %done, label %out, label %more
out:
  ret i64 %acc
more:
  %n1 = sub i64 %n, 1
  %e0 = extractvalue [10 x i64] %a, 0
  %e1 = extractvalue [10 x i64] %a, 1
  %e2 = extractvalue [10 x i64] %a, 2
  %e3 = extractvalue [10 x i64] %a, 3
  %e4 = extractvalue [10 x i64] %a, 4
  %e5 = extractvalue [10 x i64] %a, 5
  %e6 = extractvalue [10 x i64] %a, 6
  %e7 = extractvalue [10 x i64] %a, 7
  %e8 = extractvalue [10 x i64] %a, 8
  %e9 = extractvalue [10 x i64] %a, 9
  %acc1 = add i64 %acc, %e0
  %r0 = insertvalue [10 x i64] undef, i64 %e1, 0
  %r1 = insertvalue [10 x i64] %r0, i64 %e2, 1
  %r2 = insertvalue [10 x i64] %r1, i64 %e3, 2
  %r3 = insertvalue [10 x i64] %r2, i64 %e4, 3
  %r4 = insertvalue [10 x i64] %r3, i64 %e5, 4
  %r5 = insertvalue [10 x i64] %r4, i64 %e6, 5
  %r6 = insertvalue [10 x i64] %r5, i64 %e7, 6
  %r7 = insertvalue [10 x i64] %r6, i64 %e8, 7
  %r8 = insertvalue [10 x i64] %r7, i64 %e9, 8
  %r9 = insertvalue [10 x i64] %r8, i64 %e0, 9
  %r = musttail call tailcc i64 @agg(i64 %n1, i64 %acc1, [10 x i64] %r9)
  ret i64 %r
}

@fmt = private constant [6 x i8] c"%lld\0A\00"
declare i32 @printf(ptr, ...)
declare i64 @atol(ptr)

define i32 @main(i32 %argc, ptr %argv) {
  %at = getelementptr ptr, ptr %argv, i64 1
  %text = load ptr, ptr %at
  %n = call i64 @atol(ptr %text)
  %r = call tailcc i64 @agg(i64 %n, i64 0, [10 x i64] [i64 1, i64 2, i64 3, i64 4, i64 5, i64 6, i64 7, i64 8, i64 9, i64 10])
  %printed = call i32 (ptr, ...) @printf(ptr @fmt, i64 %r)
  ret i32 0
}
