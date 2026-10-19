// RUN: idris-mlir-opt %s --idr-target --idr-tail-calls -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=tail-calls=@flag:@hub,tail-calls=@twice:@hub,convention=@flag:tailcc,convention=@twice:tailcc,convention=@hub:tailcc -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=tail-calls=@unknown:@hub -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=KEEPS < %t.err
// KEEPS: expected tail-calls: @unknown calls @hub and keeps its frame
// Whether a call is in tail position is read along the one path from it
// to a return, which the values the path knows decide. The path may enter
// a block again: it loops only when it comes back knowing what it knew
// the time before, the block's arguments and every value live into it.
// @flag goes round its loop once, its flag true and then false. @twice
// enters ^b twice, the second time with another value of the %d live into
// it. Both reach the return, so each call of @hub is a guaranteed tail
// call, and the caller and the callee take tailcc. @unknown's loop goes
// round as an argument says, which the path cannot know: its call keeps
// its frame. @hub calls each and is called back by each, so all are on one
// cycle of calls.
module {
  llvm.func @flag(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    %r = llvm.call @hub(%x) : (i64) -> i64
    %t = llvm.mlir.constant(true) : i1
    llvm.br ^bb1(%t : i1)
  ^bb1(%c: i1):
    llvm.cond_br %c, ^bb2, ^bb3
  ^bb2:
    %f = llvm.mlir.constant(false) : i1
    llvm.br ^bb1(%f : i1)
  ^bb3:
    llvm.return %r : i64
  }
  llvm.func @twice(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    %r = llvm.call @hub(%x) : (i64) -> i64
    %t = llvm.mlir.constant(true) : i1
    llvm.br ^h(%t, %t : i1, i1)
  ^h(%c: i1, %d: i1):
    llvm.cond_br %c, ^b, ^exit
  ^b:
    %f = llvm.mlir.constant(false) : i1
    llvm.br ^h(%d, %f : i1, i1)
  ^exit:
    llvm.return %r : i64
  }
  llvm.func @unknown(%x: i64, %go: i1) -> i64 attributes {sym_visibility = "private"} {
    %r = llvm.call @hub(%x) : (i64) -> i64
    llvm.br ^h
  ^h:
    llvm.cond_br %go, ^h, ^exit
  ^exit:
    llvm.return %r : i64
  }
  llvm.func @hub(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    %false = llvm.mlir.constant(false) : i1
    %a = llvm.call @flag(%x) : (i64) -> i64
    %b = llvm.call @twice(%a) : (i64) -> i64
    %c = llvm.call @unknown(%b, %false) : (i64, i1) -> i64
    %s = llvm.add %c, %x : i64
    llvm.return %s : i64
  }
  llvm.func @main(%x: i64) -> i64 {
    %r = llvm.call @hub(%x) : (i64) -> i64
    llvm.return %r : i64
  }
}
