// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-rc-cells),idr-rc-stack,idr-rc-grades))' -o %t.plain.mlir
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-frames,idr.func(idr-rc-cells),idr-rc-stack,idr-rc-grades))' -o %t.framed.mlir
// RUN: %status 1 diff %t.plain.mlir %t.framed.mlir
// RUN: %differential %t.plain.mlir %t.framed.mlir
// A component whose members give different types: @f gives an i64 and
// @g an i32, each the label of its own closure sum (a sum's labels share
// one signature, which the two do not), and each runs the other's
// closure not in tail position, so each has a frame the other's return
// pops. Every run and resume then gives the one answer that holds
// either type: a value @g gives crosses @f's frame as its answer case,
// and the member the root called takes its own result out of the answer
// its run gave. The root prints f n and g n for the byte n it reads, so
// both members' entries run.
// STDIN: \0000
// STDIN: \0001
// STDIN: \0007
// STDIN: \0144
!fn64 = !idr.data<"fn64">
!fn32 = !idr.data<"fn32">
#types = #idr.types<
  "fn32" = closures [@g() label @g],
  "fn64" = closures [@f() label @f]
>
idr.program @"frames-answer-types" root(@root) stage(first) types #types {
  idr.func @f(%n: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    default(%m: i64) {
      %v = idr.call @g(%m) : (i64) -> i32
      %w = arith.extsi %v : i32 to i64
      %s = arith.addi %w, %m : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @g(%n: i64) -> i32 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i32) {
    case 0 {
      %zero = arith.constant 0 : i32
      idr.yield %zero : i32
    }
    default(%m: i64) {
      %one = arith.constant 1 : i64
      %p = arith.subi %m, %one : i64
      %v = idr.call @f(%p) : (i64) -> i64
      %t = arith.trunci %v : i64 to i32
      %one32 = arith.constant 1 : i32
      %s = arith.addi %t, %one32 : i32
      idr.yield %s : i32
    }
    }
    return %r : i32
  }
  // The closures @f and @g are labels of: built, never run.
  idr.func @labels64() -> !fn64 attributes {total} {
    %c = idr.con !fn64 @f()
    return %c : !fn64
  }
  idr.func @labels32() -> !fn32 attributes {total} {
    %c = idr.con !fn32 @g()
    return %c : !fn32
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %n = arith.extui %ch : i32 to i64
    %a = idr.call @f(%n) : (i64) -> i64
    %sa = idr.str.show_sint %a : i64
    %w1 = idr.io.put_str %sa, %w0
    %b = idr.call @g(%n) : (i64) -> i32
    %bw = arith.extsi %b : i32 to i64
    %sb = idr.str.show_sint %bw : i64
    %w2 = idr.io.put_str %sb, %w1
    return %w2 : !idr.world
  }
}
