// RUN: idris-mlir-opt %s --idr-expect=holds=matches=@takes,matches-nothing=@plain,forces=@forces,\
// RUN: forces-nothing=@plain,builds=@builds,builds-nothing=@plain,reads-fields=@reads,reads-no-fields=@takes,\
// RUN: applies=@applies,never-returns=@never,calls=@caller:@leaf,never-calls=@plain:@leaf,\
// RUN: calls-closed=@closed:@leaf -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=matches=@plain,matches-nothing=@takes,forces=@plain,\
// RUN: forces-nothing=@forces,builds=@plain,builds-nothing=@builds,reads-fields=@plain,reads-no-fields=@reads,\
// RUN: applies=@plain,never-returns=@plain,calls=@plain:@leaf,never-calls=@closed:@leaf,\
// RUN: calls-closed=@caller:@leaf -verify-diagnostics -o /dev/null
// What a function does when it runs, each stated of a function that does
// it and failing on one that does not: @plain only computes; the others
// each take a value apart, read a field, build a value, force, apply,
// crash, or call @leaf on what they are given or on a constant.
!Maybe = !idr.data<"Maybe">
!Pair = !idr.data<"Pair">
#types = #idr.types<
  "Maybe" = plain [@Nothing(), @Just(i64)],
  "Pair" = plain [@MkPair(i64, i64)]
>
idr.program @does root(@root) stage(higher) types #types {
  // expected-error @below {{expected matches: }}
  // expected-error @below {{expected forces: }}
  // expected-error @below {{expected builds: }}
  // expected-error @below {{expected reads-fields: }}
  // expected-error @below {{expected applies: }}
  // expected-error @below {{expected calls: }}
  idr.func @plain(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    // expected-error @below {{expected never-returns: }}
    return %y : i64
  }
  idr.func @takes(%m: !Maybe) -> i64 {
    // expected-error @below {{expected matches-nothing: }}
    %r = idr.match %m : !Maybe -> (i64) {
    case @Just(%x: i64) {
      idr.yield %x : i64
    }
    default(%d: !Maybe) {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @reads(%p: !Pair) -> i64 {
    // expected-error @below {{expected reads-no-fields: }}
    %a = idr.field %p : !Pair @MkPair[0] -> i64
    return %a : i64
  }
  idr.func @builds(%x: i64) -> !Pair {
    // expected-error @below {{expected builds-nothing: }}
    %p = idr.con !Pair @MkPair(%x : i64, %x : i64)
    return %p : !Pair
  }
  idr.func @forces(%t: !idr.lazy<i64>) -> i64 {
    // expected-error @below {{expected forces-nothing: }}
    %v = idr.force %t : !idr.lazy<i64> -> i64
    return %v : i64
  }
  idr.func @applies(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  idr.func @never(%x: i64) -> i64 {
    idr.crash "unhandled input for never"
    ub.unreachable
  }
  idr.func @leaf(%x: i64) -> i64 {
    %y = arith.muli %x, %x : i64
    return %y : i64
  }
  idr.func @caller(%x: i64) -> i64 {
    // expected-error @below {{expected calls-closed: }}
    %y = idr.call @leaf(%x) : (i64) -> i64
    return %y : i64
  }
  idr.func @closed() -> i64 {
    %c = arith.constant 7 : i64
    // expected-error @below {{expected never-calls: }}
    %y = idr.call @leaf(%c) : (i64) -> i64
    return %y : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
