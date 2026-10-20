// RUN: sed '/^\/\/ -----/,$d' %s > %t.first.mlir
// RUN: awk '/^\/\/ -----/ { n++; next } n == 1' %s > %t.second.mlir
// RUN: idris-mlir-opt %t.first.mlir --remove-dead-values --idr-expect=holds=matches=@get,applies=@get,\
// RUN: calls=@get:@fail,parameters-used=@get,parameters-used=@fail -o /dev/null
// RUN: idris-mlir-opt %t.first.mlir --inline --idr-expect=holds=never-calls=@Main.main:@get,applies=@Main.main -o /dev/null
// RUN: idris-mlir-opt %t.second.mlir --remove-dead-values --idr-expect=holds=parameters-used=@fail -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.first.mlir --idr-expect=holds=parameters-used=@fail,never-calls=@Main.main:@get,applies=@Main.main -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.second.mlir --idr-expect=holds=parameters-used=@fail -o /dev/null
// RUN: idris-mlir-opt %t.first.mlir --inline -o %t.first.inlined.mlir
// RUN: %differential %t.first.mlir %t.first.inlined.mlir
// RUN: idris-mlir-opt %t.second.mlir --remove-dead-values -o %t.second.dead.mlir
// RUN: %differential %t.second.mlir %t.second.dead.mlir
// RUN: idris-mlir-opt %s -split-input-file '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %t.first.mlir --remove-dead-values -o %t.first.dead.mlir
// RUN: %differential %t.first.mlir %t.first.dead.mlir
// BEFORE-DAG: expected parameters-used: {{.*}}@fail
// BEFORE-DAG: expected never-calls: @Main.main {{.*}}@get
// BEFORE-DAG: expected applies: {{.*}}@Main.main
// Upstream's remove-dead-values and inline work on matches and closures:
// inline takes @get, its match and its closure into @Main.main, where the
// apply stays. Remove-dead-values drops a parameter nothing reads and a
// result nothing uses, @fail's among them, though its body is a crash that
// ends in ub.unreachable, and keeps the match, its apply and its call.
// None of what each pass makes hold held before it, and each program
// prints after each pass what it printed before, crashing where it did:
// the first's root crashes in @fail on an even byte, the second's on
// every byte.

!Maybe = !idr.data<"Maybe">
#types = #idr.types<
  "Maybe" = plain [@Nothing(), @Just(i64)]
>
idr.program @"upstream-passes" root(@Main.main) stage(higher) types #types {
  idr.func @inc(%k: i64, %x: i64) -> i64
      attributes {total} {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  idr.func @fail(%x: i64) -> i64 {
    idr.crash "unhandled input for fail"
    ub.unreachable
  }
  idr.func @get(%m: !Maybe, %d: i64,
                         %unused: i64) -> (i64, i64) {
    %r, %s = idr.match %m : !Maybe -> (i64, i64) {
    case @Just(%x: i64) {
      %c = idr.closure @inc(%x) : (i64) -> !idr.fn<(i64) -> (i64)>
      %y = idr.apply %c(%d) : !idr.fn<(i64) -> (i64)>
      idr.yield %y, %unused : i64, i64
    }
    default(%d1: !Maybe) {
      %f = idr.call @fail(%d) : (i64) -> i64
      idr.yield %f, %d : i64, i64
    }
    }
    return %r, %s : i64, i64
  }
  // The program's root runs @get on what it reads: a Just of the byte, or
  // Nothing when it is even, which @fail crashes on.
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %c1 = arith.constant 1 : i64
    %bit = arith.andi %n, %c1 : i64
    %m = idr.match_lit %bit : i64 -> (!Maybe) {
    case 0 {
      %no = idr.con !Maybe @Nothing()
      idr.yield %no : !Maybe
    }
    default(%d: i64) {
      %j = idr.con !Maybe @Just(%n : i64)
      idr.yield %j : !Maybe
    }
    }
    %r, %s = idr.call @get(%m, %n, %n) : (!Maybe, i64, i64) -> (i64, i64)
    %w2 = idr.io.put_sint %r, %w1 : i64
    return %w2 : !idr.world
  }
}

// -----

idr.program @"upstream-passes" root(@Main.main) stage(first) types #idr.types<> {
  idr.func @fail(%x: i64) -> i64 {
    idr.crash "unhandled input for fail"
    ub.unreachable
  }
  idr.func @crash_inlined(%x: i64) -> i64 {
    %r = idr.match_lit %x : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default(%d: i64) {
      %f = idr.call @fail(%x) : (i64) -> i64
      idr.yield %f : i64
    }
    }
    return %r : i64
  }
  idr.func @crash_in_body(%x: i64) -> i64 {
    %f = idr.call @fail(%x) : (i64) -> i64
    %c1 = arith.constant 1 : i64
    %r = arith.addi %f, %c1 : i64
    return %r : i64
  }
  // The program's root, which runs both on what it reads.
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %a = idr.call @crash_inlined(%x) : (i64) -> i64
    %b = idr.call @crash_in_body(%a) : (i64) -> i64
    %w2 = idr.io.put_sint %b, %w1 : i64
    return %w2 : !idr.world
  }
}
