; Integer and floating-point arguments mixed, in the two register files
; and each of four widths. Every value stays exact: a float counts to a
; million exactly, a double halves exactly.
define internal tailcc double @mix(i64 %n, double %x, i32 %k, float %f, i64 %acc) {
entry:
  %done = icmp eq i64 %n, 0
  br i1 %done, label %out, label %more
out:
  %accd = sitofp i64 %acc to double
  %fd = fpext float %f to double
  %s = fadd double %x, %accd
  %t = fadd double %s, %fd
  ret double %t
more:
  %n1 = sub i64 %n, 1
  %x1 = fadd double %x, 5.000000e-01
  %k64 = sext i32 %k to i64
  %acc1 = add i64 %acc, %k64
  %k1 = add i32 %k, 1
  %f1 = fadd float %f, 1.000000e+00
  %r = musttail call tailcc double @mix(i64 %n1, double %x1, i32 %k1, float %f1, i64 %acc1)
  ret double %r
}

@fmt = private constant [6 x i8] c"%lld\0A\00"
declare i32 @printf(ptr, ...)
declare i64 @atol(ptr)

define i32 @main(i32 %argc, ptr %argv) {
  %at = getelementptr ptr, ptr %argv, i64 1
  %text = load ptr, ptr %at
  %n = call i64 @atol(ptr %text)
  %d = call tailcc double @mix(i64 %n, double 0.000000e+00, i32 0, float 0.000000e+00, i64 0)
  %r = fptosi double %d to i64
  %printed = call i32 (ptr, ...) @printf(ptr @fmt, i64 %r)
  ret i32 0
}
