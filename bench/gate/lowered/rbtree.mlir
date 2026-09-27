// bench/gate/suite/rbtree/Main.idr, lowered by hand to what the compiler
// will emit after M1 (docs/plan.md 4.4, experiment 2): main, after the tree
// of rbmap.mlir. Insert n keys, count the True values, then drop the tree,
// which the runtime frees iteratively.

func.func @idr_main() -> i32 {
  %n0 = llvm.call @idr_read_int() : () -> i64
  %one = arith.constant 1 : i64
  %zero = arith.constant 0 : i64
  %ten = arith.constant 10 : i64
  %leaf = llvm.inttoptr %one : i64 to !llvm.ptr
  cf.br ^loop(%n0, %leaf : i64, !llvm.ptr)
^loop(%n: i64, %t: !llvm.ptr):
  %done = arith.cmpi sle, %n, %zero : i64
  cf.cond_br %done, ^fin, ^step
^step:
  %n1 = arith.subi %n, %one : i64
  %rem = arith.remsi %n1, %ten : i64
  %isz = arith.cmpi eq, %rem, %zero : i64
  %v = arith.extui %isz : i1 to i8
  %t1 = func.call @insert(%t, %n1, %v) : (!llvm.ptr, i64, i8) -> !llvm.ptr
  cf.br ^loop(%n1, %t1 : i64, !llvm.ptr)
^fin:
  %c = func.call @count(%t, %zero) : (!llvm.ptr, i64) -> i64
  func.call @__rc_drop(%t) : (!llvm.ptr) -> ()
  llvm.call @idr_put_int(%c) : (i64) -> ()
  %nl = arith.constant 10 : i32
  llvm.call @idr_put_char(%nl) : (i32) -> ()
  %ok = arith.constant 0 : i32
  return %ok : i32
}
