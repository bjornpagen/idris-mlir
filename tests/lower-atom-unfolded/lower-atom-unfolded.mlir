// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=lowered,calls-only=@atom:[] -o /dev/null
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// A nullary boxed constructor that reaches idr-lower unfolded lowers to its
// static atom and its unpack to nothing, so @atom asks the runtime for
// nothing. The root runs @atom: lowered and as written, the program ends
// with the status 0, as the reference at the end (REF) does
// (%differential, on the one input, none, since it reads none).
// STDIN:
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @atom root(@Prog.main) stage(owned) {
  idr.func @atom() -> i64 {
    %n = idr.con !idr.own<!idr.box<!L>> @N()
    idr.unpack %n : !idr.own<!idr.box<!L>> @N -> ()
    %z = arith.constant 0 : i64
    return %z : i64
  }
  idr.func @Prog.main() -> i64 {
    %z = idr.call @atom() : () -> i64
    return %z : i64
  }
}
// The reference:
// REF: idr.program @ref root(@Prog.main) stage(higher) {
// REF:   idr.func @Prog.main() -> i64 {
// REF:     %r = arith.constant 0 : i64
// REF:     return %r : i64
// REF:   }
// REF: }
