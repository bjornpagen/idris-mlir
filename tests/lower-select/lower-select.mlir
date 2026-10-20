// RUN: idris-mlir-opt %s --canonicalize --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,straight-line=@pick,calls-only=@pick:[]' -o /dev/null
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// canonicalize turns a match that only chooses between two values into
// arith.select, also of an idr type; that select chooses each component,
// on the one path, so a sum chosen by a condition is its components
// chosen, with no branch. Each component comes from the sum chosen: the
// root picks between A of the byte it reads and B by the byte's low bit,
// and the program, lowered and as written, prints the byte for an odd one
// and -1 (B) for an even one, as the reference at the end (REF), with no
// sum, does (%differential, on 0, 1, 254, 255 and the end of input).
// STDIN: \0000
// STDIN: \0001
// STDIN: \0376
// STDIN: \0377
// STDIN:
!T = !idr.data<"T">
#types = #idr.types<
  "T" = plain [@A(i64), @B()]
>
idr.program @select root(@Prog.main) stage(owned) types #types {
  idr.func @pick(%c: i1, %x: !T, %y: !T) -> !T {
    %r = arith.select %c, %x, %y : !T
    return %r : !T
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %odd = arith.trunci %c : i32 to i1
    %a = idr.con !T @A(%x : i64)
    %b = idr.con !T @B()
    %t = idr.call @pick(%odd, %a, %b) : (i1, !T, !T) -> !T
    %r = idr.match %t : !T -> (i64) {
    case @A(%v: i64) {
      idr.yield %v : i64
    }
    case @B() {
      %none = arith.constant -1 : i64
      idr.yield %none : i64
    }
    }
    %w2 = idr.io.put_sint %r, %w1 : i64
    return %w2 : !idr.world
  }
}
// The reference:
// REF: idr.program @ref root(@Prog.main) stage(higher) types #idr.types<> {
// REF:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REF:     %c, %w1 = idr.io.get_byte %w
// REF:     %x = arith.extui %c : i32 to i64
// REF:     %odd = arith.trunci %c : i32 to i1
// REF:     %none = arith.constant -1 : i64
// REF:     %r = arith.select %odd, %x, %none : i64
// REF:     %w2 = idr.io.put_sint %r, %w1 : i64
// REF:     return %w2 : !idr.world
// REF:   }
// REF: }
