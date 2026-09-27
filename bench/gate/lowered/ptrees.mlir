// Parallel binary trees (docs/plan.md 4.4 experiment 3, 7.1): the
// binarytrees of experiment 1 with each depth's trees split into 8 work
// items that the cores take as idle cores take futures (Perceus's
// binarytrees.kk, Lean's binarytrees.lean). Its output is binarytrees'.
// After bintree.mlir.
//
// Nothing crosses cores but scalars: an item is (depth, range of seeds) and
// its result is an Int. So every count stays non-atomic: the stats build
// must show atomic-rc=0 and marked=0. The long-lived tree stays on core 0.

llvm.func @idr_parallel(i64, !llvm.ptr, !llvm.ptr, !llvm.ptr)

// The checks of the trees make' j d for j in (lo, hi].
func.func private @sum_range(%d: i64, %hi: i64, %lo: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  cf.br ^loop(%hi, %c0 : i64, i64)
^loop(%j: i64, %t: i64):
  %done = arith.cmpi sle, %j, %lo : i64
  cf.cond_br %done, ^exit, ^body
^body:
  %x = func.call @make(%j, %d) : (i64, i64) -> !llvm.ptr
  %c = func.call @check(%x) : (!llvm.ptr) -> i64
  func.call @__rc_dec(%x) : (!llvm.ptr) -> ()
  %t1 = arith.addi %t, %c : i64
  %j1 = arith.subi %j, %c1 : i64
  cf.br ^loop(%j1, %t1 : i64, i64)
^exit:
  return %t : i64
}

// A work item: env holds (depth, hi, lo) triples.
llvm.func @ptask(%env: !llvm.ptr, %i: i64) -> i64 {
  %three = llvm.mlir.constant(3 : i64) : i64
  %one = llvm.mlir.constant(1 : i64) : i64
  %two = llvm.mlir.constant(2 : i64) : i64
  %k = llvm.mul %i, %three : i64
  %pd = llvm.getelementptr %env[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %d = llvm.load %pd : !llvm.ptr -> i64
  %k1 = llvm.add %k, %one : i64
  %ph = llvm.getelementptr %env[%k1] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %hi = llvm.load %ph : !llvm.ptr -> i64
  %k2 = llvm.add %k, %two : i64
  %pl = llvm.getelementptr %env[%k2] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %lo = llvm.load %pl : !llvm.ptr -> i64
  %r = func.call @sum_range(%d, %hi, %lo) : (i64, i64, i64) -> i64
  llvm.return %r : i64
}

func.func @idr_main() -> i32 {
  %n = llvm.call @idr_read_int() : () -> i64
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c8 = arith.constant 8 : i64
  %minN = arith.constant 4 : i64
  %six = arith.constant 6 : i64
  %big = arith.cmpi sgt, %six, %n : i64
  %maxN = arith.select %big, %six, %n : i64
  %stretchN = arith.addi %maxN, %c1 : i64

  %s = func.call @make(%stretchN, %stretchN) : (i64, i64) -> !llvm.ptr
  %cs = func.call @check(%s) : (!llvm.ptr) -> i64
  func.call @__rc_dec(%s) : (!llvm.ptr) -> ()
  %s_stretch = llvm.mlir.addressof @s_stretch : !llvm.ptr
  %len_stretch = arith.constant 12 : i64
  llvm.call @idr_put_str(%s_stretch, %len_stretch) : (!llvm.ptr, i64) -> ()
  func.call @out_rest(%stretchN, %cs) : (i64, i64) -> ()

  %long = func.call @make(%maxN, %maxN) : (i64, i64) -> !llvm.ptr

  // 8 items per depth: depths minN, minN+2, ... maxN.
  %span = arith.subi %maxN, %minN : i64
  %half = arith.divsi %span, %c2 : i64
  %ndepths = arith.addi %half, %c1 : i64
  %ntasks = arith.muli %ndepths, %c8 : i64
  %nslots = arith.muli %ntasks, %c3 : i64
  %tab = llvm.alloca %nslots x i64 : (i64) -> !llvm.ptr
  %res = llvm.alloca %ntasks x i64 : (i64) -> !llvm.ptr
  cf.br ^fill(%c0 : i64)
^fill(%t: i64):
  %filled = arith.cmpi sge, %t, %ntasks : i64
  cf.cond_br %filled, ^run, ^item
^item:
  %dk = arith.divsi %t, %c8 : i64
  %p = arith.remsi %t, %c8 : i64
  %d2 = arith.muli %dk, %c2 : i64
  %d = arith.addi %minN, %d2 : i64
  %e0 = arith.subi %maxN, %d : i64
  %e = arith.addi %e0, %minN : i64
  %count = arith.shli %c1, %e : i64
  %part = arith.divsi %count, %c8 : i64
  %lo = arith.muli %p, %part : i64
  %hi = arith.addi %lo, %part : i64
  %base = arith.muli %t, %c3 : i64
  %q0 = llvm.getelementptr %tab[%base] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %d, %q0 : i64, !llvm.ptr
  %b1 = arith.addi %base, %c1 : i64
  %q1 = llvm.getelementptr %tab[%b1] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %hi, %q1 : i64, !llvm.ptr
  %b2 = arith.addi %base, %c2 : i64
  %q2 = llvm.getelementptr %tab[%b2] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %lo, %q2 : i64, !llvm.ptr
  %t1 = arith.addi %t, %c1 : i64
  cf.br ^fill(%t1 : i64)
^run:
  %task = llvm.mlir.addressof @ptask : !llvm.ptr
  llvm.call @idr_parallel(%ntasks, %task, %tab, %res) : (i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  cf.br ^report(%c0 : i64)
^report(%k: i64):
  %over = arith.cmpi sge, %k, %ndepths : i64
  cf.cond_br %over, ^end, ^depth
^depth:
  %first = arith.muli %k, %c8 : i64
  cf.br ^sum(%c0, %c0 : i64, i64)
^sum(%j: i64, %acc: i64):
  %sdone = arith.cmpi sge, %j, %c8 : i64
  cf.cond_br %sdone, ^print, ^add
^add:
  %idx = arith.addi %first, %j : i64
  %pr = llvm.getelementptr %res[%idx] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %rv = llvm.load %pr : !llvm.ptr -> i64
  %acc1 = arith.addi %acc, %rv : i64
  %j1 = arith.addi %j, %c1 : i64
  cf.br ^sum(%j1, %acc1 : i64, i64)
^print:
  %dd2 = arith.muli %k, %c2 : i64
  %dd = arith.addi %minN, %dd2 : i64
  %ee0 = arith.subi %maxN, %dd : i64
  %ee = arith.addi %ee0, %minN : i64
  %cnt = arith.shli %c1, %ee : i64
  llvm.call @idr_put_int(%cnt) : (i64) -> ()
  %s_trees = llvm.mlir.addressof @s_trees : !llvm.ptr
  %len_trees = arith.constant 7 : i64
  llvm.call @idr_put_str(%s_trees, %len_trees) : (!llvm.ptr, i64) -> ()
  func.call @out_rest(%dd, %acc) : (i64, i64) -> ()
  %k1 = arith.addi %k, %c1 : i64
  cf.br ^report(%k1 : i64)
^end:
  %cl = func.call @check(%long) : (!llvm.ptr) -> i64
  %s_long = llvm.mlir.addressof @s_long : !llvm.ptr
  %len_long = arith.constant 15 : i64
  llvm.call @idr_put_str(%s_long, %len_long) : (!llvm.ptr, i64) -> ()
  func.call @out_rest(%maxN, %cl) : (i64, i64) -> ()
  func.call @__rc_dec(%long) : (!llvm.ptr) -> ()
  %ok = arith.constant 0 : i32
  return %ok : i32
}
