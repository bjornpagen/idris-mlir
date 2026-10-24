// RUN: idris-mlir-opt %s -split-input-file --pass-pipeline='builtin.module(idr-pipeline{from=first to=first},idr-expect{holds=folded=@main})' -verify-diagnostics -o /dev/null
// The folds that give a value of the program rather than a constant, each
// one condition over where a value lives, which reads the op that built an
// operand: after the first stage nothing in @main computes from constants
// alone but the one op no fold computes, whose operand each program makes
// a constant only if its fold gave the value it reads. In the first
// program the field given to an idr.data.con whose other field is a line
// read at run time, so no constant, is read back as the 3 it was given. In
// the second a word cast into a linear position and straight back is the
// word itself, 3. In the third a tie that names no axis, of an array
// with none dynamic, is the array, a constant whose element no fold of
// ours reads.
#P = #idr.family<"P" [] {
    @MkP (i64, !idr.str)
  }>
!MkP = !idr.data<#P @MkP>
!Str = !idr.graded<many, static, !idr.str>
idr.program @given root(@main) stage(first) {
  idr.func @main() {
    %line = idr.io.get_line : () -> !idr.str
    %three = arith.constant 3 : i64
    %p = idr.data.con(%three : i64, %line : !idr.str) : !MkP
    %first = idr.data.field %p[0] : !MkP -> i64
    %real = arith.sitofp %first : i64 to f64
    // expected-error @below {{expected folded: }}
    %e = math.exp %real : f64
    %text = idr.str.show_double %e : (f64) -> !Str
    idr.io.put_str %text : (!Str) -> ()
    idr.return
  }
}

// -----

!Once = !idr.graded<once, i64>
!Str = !idr.graded<many, static, !idr.str>
idr.program @casts root(@main) stage(first) {
  idr.func @main() {
    %three = arith.constant 3 : i64
    %once = idr.lin.cast %three : i64 -> !Once
    %back = idr.lin.cast %once : !Once -> i64
    %real = arith.sitofp %back : i64 to f64
    // expected-error @below {{expected folded: }}
    %e = math.exp %real : f64
    %text = idr.str.show_double %e : (f64) -> !Str
    idr.io.put_str %text : (!Str) -> ()
    idr.return
  }
}

// -----

!Str = !idr.graded<many, static, !idr.str>
idr.program @ties root(@main) stage(first) {
  idr.func @main() {
    %array = arith.constant dense<[1, 2, 3, 4]> : tensor<4xi64>
    %tied = idr.array.tie_shape %array axes [] dims() : tensor<4xi64> -> tensor<4xi64>
    %c0 = arith.constant 0 : index
    // expected-error @below {{expected folded: }}
    %x = tensor.extract %tied[%c0] : tensor<4xi64>
    %real = arith.sitofp %x : i64 to f64
    %text = idr.str.show_double %real : (f64) -> !Str
    idr.io.put_str %text : (!Str) -> ()
    idr.return
  }
}
