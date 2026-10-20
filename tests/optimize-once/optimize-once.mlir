// RUN: idris-mlir-opt %s --idr-optimize --mlir-disable-threading --log-actions-to=%t.log -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: grep 'begins.*idr-optimize-node' %t.log | count 5
// RUN: grep 'begins.*idr-optimize-node' %t.log | sed -n 's/.*idr-optimize-node[^@]*@\([^(]*\)(.*/\1/p' | sort | uniq -d | count 0
// RUN: grep 'begins.*idr-optimize-node' %t.log | sed -n 's/.*idr-optimize-node[^@]*@\([^(]*\)(.*/\1/p' | sort -u | count 5
// The optimizer takes each function once, when every function it calls
// outside its own component is final: its first step is one action,
// idr-optimize-node, which begins once per node. Here five functions, a
// root, a pair that call each other, a leaf and a caller of the leaf, and
// no argument a specialization could take as static: five nodes, each
// begun once, whatever the bounded loop that follows a node does.
// The optimized program means what the program as written does: on every
// one-byte input n,  and  each end on n of each parity, and both
// print alike (%differential).
idr.program @once root(@Main.main) stage(first) types #idr.types<> {
  idr.func @leaf(%x: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  idr.func @twice(%x: i64) -> i64 attributes {total} {
    %a = idr.call @leaf(%x) : (i64) -> i64
    %b = idr.call @leaf(%a) : (i64) -> i64
    return %b : i64
  }
  idr.func @even(%n: i64, %x: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.call @odd(%m, %x) : (i64, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  idr.func @odd(%n: i64, %x: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.call @even(%m, %x) : (i64, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %a = idr.call @twice(%n) : (i64) -> i64
    %b = idr.call @even(%n, %a) : (i64, i64) -> i64
    %w2 = idr.io.put_sint %b, %w1 : i64
    return %w2 : !idr.world
  }
}
