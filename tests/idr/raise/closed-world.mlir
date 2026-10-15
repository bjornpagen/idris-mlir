// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-optimize -o %t.mlir
// RUN: FileCheck %s --implicit-check-not=.spec. < %t.mlir
// RUN: idris-mlir-opt %t.mlir --pass-pipeline='builtin.module(idr.program(idr.func(idr-tail-loops)))' -o %t.loops.mlir
// RUN: idris-mlir-opt %t.loops.mlir --idr-expect=holds=constant-stack=@Main.main -o /dev/null
// NEEDS-ACCEPTANCE: that no specialization of the loop is made on the constructors the literal count builds, as the binding times decide.
// The IO loop of io-loop.mlir, started with a literal. Each turn of the
// loop builds the next actions anew, so no parameter of it is fixed, and
// the loop is not unrolled at compile time one copy per count: no copy is
// made, and the loop runs as a loop, with no recursion left that grows
// the stack.
// CHECK: idr.func @Main.main(
!Unit = !idr.data<"Unit", plain [@MkUnit()]>
!IORes = !idr.data<"IORes", plain [@MkIORes(!Unit, !idr.world)]>
!IO = !idr.data<"IO", plain [@MkIO(!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)]>
idr.program @"closed-world" root(@Main.main) stage(higher) {
  idr.func @put(%n: i64, %w: !idr.world) -> !IORes attributes {total} {
    %w1 = idr.io.put_int signed %n, %w : i64
    %u = idr.con !Unit @MkUnit()
    %r = idr.con !IORes @MkIORes(%u : !Unit, %w1 : !idr.world)
    return %r : !IORes
  }
  idr.func @done(%w: !idr.world) -> !IORes attributes {total} {
    %u = idr.con !Unit @MkUnit()
    %r = idr.con !IORes @MkIORes(%u : !Unit, %w : !idr.world)
    return %r : !IORes
  }
  idr.func @countdown(%n: i64) -> !IO {
    %r = idr.match_lit %n : i64 -> (!IO) {
    case 0 {
      %k = idr.closure @done() : () -> !idr.fn<(!idr.world) -> (!IORes)>
      %k_lin = idr.lin.enter %k : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
      %io = idr.con !IO @MkIO(%k_lin : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
      idr.yield %io : !IO
    }
    default {
      %p = idr.closure @put(%n) : (i64) -> !idr.fn<(!idr.world) -> (!IORes)>
      %then = idr.closure @next(%n) : (i64) -> !idr.fn<(!Unit) -> (!IO)>
      %p_lin = idr.lin.enter %p : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
      %then_lin = idr.lin.enter %then : !idr.lin<!idr.fn<(!Unit) -> (!IO)>>
      %k = idr.closure @bind(%p_lin, %then_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>, !idr.lin<!idr.fn<(!Unit) -> (!IO)>>) -> !idr.fn<(!idr.world) -> (!IORes)>
      %k_lin = idr.lin.enter %k : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
      %io = idr.con !IO @MkIO(%k_lin : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
      idr.yield %io : !IO
    }
    }
    return %r : !IO
  }
  idr.func @next(%n: i64, %u: !Unit) -> !IO {
    %c1 = arith.constant 1 : i64
    %m = arith.subi %n, %c1 : i64
    %a = idr.call @countdown(%m) : (i64) -> !IO
    return %a : !IO
  }
  idr.func @bind(%a: !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>, %k: !idr.lin<!idr.fn<(!Unit) -> (!IO)>>, %w: !idr.world) -> !IORes attributes {total} {
    %a_use = idr.lin.use %a : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %r = idr.apply %a_use(%w) : !idr.fn<(!idr.world) -> (!IORes)>
    %u = idr.field %r : !IORes @MkIORes[0] -> !Unit
    %w1 = idr.field %r : !IORes @MkIORes[1] -> !idr.world
    %k_use = idr.lin.use %k : !idr.lin<!idr.fn<(!Unit) -> (!IO)>>
    %io = idr.apply %k_use(%u) : !idr.fn<(!Unit) -> (!IO)>
    %f = idr.field %io : !IO @MkIO[0] -> !idr.fn<(!idr.world) -> (!IORes)>
    %s = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!IORes)>
    return %s : !IORes
  }
  idr.func @Main.main(%w: !idr.world) -> !IORes {
    %n = arith.constant 3 : i64
    %a = idr.call @countdown(%n) : (i64) -> !IO
    %f = idr.field %a : !IO @MkIO[0] -> !idr.fn<(!idr.world) -> (!IORes)>
    %r = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!IORes)>
    return %r : !IORes
  }
}
