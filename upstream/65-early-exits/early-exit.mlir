// The pull request's own inputs, upstream dialects only (`test.dead_op` is
// an unregistered op: -allow-unregistered-dialect).
//
// mlir-opt -allow-unregistered-dialect early-exit.mlir \
//   -pass-pipeline='builtin.module(func.func(sccp))'
// folds @early_exit_dead_code's comparison to false: the inner loop's one
// normal exit carries 5, and the exit that carries -5 leaves both loops.
//
// mlir-opt early-exit.mlir -convert-scf-to-cf
// lowers @loop_with_iter_args to a back edge carrying %arg and an exit
// block taking the break's value.

func.func @early_exit_dead_code(%cond: i1) -> i32 {
  %c0 = arith.constant 0 : i32
  %c5 = arith.constant 5 : i32
  %cm5 = arith.constant -5 : i32
  %outer = scf.loop token(%outer_token) -> i32 {
    %inner = scf.loop token(%inner_token) -> i32 {
      scf.if %cond {
        scf.break [%outer_token] %cm5 : i32
      }
      scf.break [%inner_token] %c5 : i32
    }
    %is_neg = arith.cmpi slt, %inner, %c0 : i32
    scf.if %is_neg {
      "test.dead_op"() : () -> ()
    }
    scf.break [%outer_token] %inner : i32
  }
  return %outer : i32
}

func.func @loop_with_iter_args(%init: i32, %cond: i1) -> i32 {
  %result = scf.loop token(%loop) iter_args(%arg = %init) : i32 -> i32 {
    scf.if %cond {
      scf.break [%loop] %arg : i32
    }
    scf.continue [%loop] %arg : i32
  }
  return %result : i32
}
