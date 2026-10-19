// RUN: idris-mlir-opt %s --idr-lower '--idr-expect=holds=lowered,calls-only=@atom:[]' -o /dev/null
// A nullary boxed constructor that reaches idr-lower unfolded lowers to its
// static atom and its unpack to nothing, so @atom asks the runtime for
// nothing.
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @atom root(@Prog.main) stage(owned) {
  idr.func @atom() -> i64 {
    %n = idr.con !idr.own<!idr.box<!L>> @N()
    idr.unpack %n : !idr.own<!idr.box<!L>> @N -> ()
    %z = arith.constant 0 : i64
    return %z : i64
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
