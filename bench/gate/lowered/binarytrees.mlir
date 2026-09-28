// bench/gate/suite/binarytrees/Main.idr, lowered by hand to what the
// compiler will emit (experiment 2): main, after
// the trees of bintree.mlir.

func.func @idr_main() -> i32 {
  %n = llvm.call @idr_read_int() : () -> i64
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %minN = arith.constant 4 : i64
  %six = arith.constant 6 : i64
  %big = arith.cmpi sgt, %six, %n : i64
  %maxN = arith.select %big, %six, %n : i64
  %stretchN = arith.addi %maxN, %c1 : i64

  %s = func.call @make(%stretchN, %stretchN) : (i64, i64) -> !llvm.ptr
  %cs = func.call @check(%s) : (!llvm.ptr) -> i64
  func.call @__rc_dec(%s) : (!llvm.ptr) -> ()
  %s_stretch = llvm.mlir.addressof @s_stretch : !llvm.ptr
  %len_stretch = arith.constant 12 : i64  // "stretch tree"
  llvm.call @idr_put_str(%s_stretch, %len_stretch) : (!llvm.ptr, i64) -> ()
  func.call @out_rest(%stretchN, %cs) : (i64, i64) -> ()

  %long = func.call @make(%maxN, %maxN) : (i64, i64) -> !llvm.ptr
  cf.br ^depths(%minN : i64)
^depths(%d: i64):
  %over = arith.cmpi sgt, %d, %maxN : i64
  cf.cond_br %over, ^end, ^iter
^iter:
  %e0 = arith.subi %maxN, %d : i64
  %e = arith.addi %e0, %minN : i64
  %k = arith.shli %c1, %e : i64
  %sum = func.call @sumT(%d, %k, %c0) : (i64, i64, i64) -> i64
  llvm.call @idr_put_int(%k) : (i64) -> ()
  %s_trees = llvm.mlir.addressof @s_trees : !llvm.ptr
  %len_trees = arith.constant 7 : i64  // "\t trees"
  llvm.call @idr_put_str(%s_trees, %len_trees) : (!llvm.ptr, i64) -> ()
  func.call @out_rest(%d, %sum) : (i64, i64) -> ()
  %d2 = arith.addi %d, %c2 : i64
  cf.br ^depths(%d2 : i64)
^end:
  %cl = func.call @check(%long) : (!llvm.ptr) -> i64
  %s_long = llvm.mlir.addressof @s_long : !llvm.ptr
  %len_long = arith.constant 15 : i64  // "long lived tree"
  llvm.call @idr_put_str(%s_long, %len_long) : (!llvm.ptr, i64) -> ()
  func.call @out_rest(%maxN, %cl) : (i64, i64) -> ()
  func.call @__rc_dec(%long) : (!llvm.ptr) -> ()
  %ok = arith.constant 0 : i32
  return %ok : i32
}
