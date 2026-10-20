// RUN: idris-mlir-opt %s '--canonicalize=top-down=true region-simplify=disabled test-convergence=true' -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=builds-nothing=@pair_of -o /dev/null
// A consumer that would meet a value two matches down (a pair of the
// outer match's result and a constant, which folds to a constant where the
// inner match yields @Nothing) moves into the inner match in the one
// rewrite that moves it into the outer. Moved into the outer alone, the
// pair would rest as a constructor the outer match yields and its one
// reader only takes apart, which the match's own canonicalization splits
// back out, and the two would move it for ever: canonicalize converges,
// and the program prints after it what it printed before, on every byte.
// Where the pair rests it folds: @pair_of builds nothing.
!Maybe = !idr.data<"Maybe">
!Pair = !idr.data<"Pair">
#types = #idr.types<
  "Maybe" = plain [@Just(i64), @Nothing()],
  "Pair" = plain [@MkPair(!Maybe, i64)]
>
idr.program @"rests-where-it-meets" root(@root) stage(higher) types #types {
  idr.func @pair_of(%s: i64, %t: i64, %x: i64) -> i64 attributes {total} {
    %nothing = idr.constant !Maybe #idr.con<!Maybe, @Nothing, []>
    %seven = arith.constant 7 : i64
    %r = idr.match_lit %s : i64 -> (!Maybe) {
    case 0 {
      %j = idr.con !Maybe @Just(%x : i64)
      idr.yield %j : !Maybe
    }
    default(%d: i64) {
      %n = idr.match_lit %t : i64 -> (!Maybe) {
      case 0 {
        %k = idr.con !Maybe @Just(%t : i64)
        idr.yield %k : !Maybe
      }
      default(%e: i64) {
        idr.yield %nothing : !Maybe
      }
      }
      idr.yield %n : !Maybe
    }
    }
    %p = idr.con !Pair @MkPair(%r : !Maybe, %seven : i64)
    %m = idr.field %p : !Pair @MkPair[0] -> !Maybe
    %v = idr.match %m : !Maybe -> (i64) {
    case @Just(%f: i64) {
      idr.yield %f : i64
    }
    case @Nothing() {
      %none = arith.constant -1 : i64
      idr.yield %none : i64
    }
    }
    return %v : i64
  }
  // The byte's low bit chooses the outer case, its next bit the inner, and
  // the rest is the number.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %byte = arith.extui %ch : i32 to i64
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %s = arith.andi %byte, %c1 : i64
    %half = arith.shrui %byte, %c1 : i64
    %t = arith.andi %half, %c1 : i64
    %x = arith.shrui %byte, %c2 : i64
    %v = idr.call @pair_of(%s, %t, %x) : (i64, i64, i64) -> i64
    %w1 = idr.io.put_sint %v, %w0 : i64
    return %w1 : !idr.world
  }
}
