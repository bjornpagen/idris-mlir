// A shared read-mostly map (experiment 3), after
// rbmap.mlir. Core 0 builds a red-black tree of n keys (as rbtree), then
// every core runs, on its own version of it,
//
//   work local x j hits =
//     if j == q then hits
//     else let x' = xorshift x in
//          if j `mod` 1000 == 999
//            then work (insert local (-(core * q + j) - 1) True) x' (j + 1) hits
//            else work local x' (j + 1)
//                      (if lookup local (x' `mod` (2 * n)) == Just True
//                         then hits + 1 else hits)
//
// and main prints the sum of the hits. The inserted keys are negative, so
// the lookups, and the output, do not depend on them.
//
// The crossing: main takes one reference per core, and the walk
// of idr_send finds the root's count above 1, so it marks the whole map
// shared, once. Lookups borrow, so they count nothing. An insert into a
// core's version copies the shared part of its path: the dups of the
// shared siblings and the drop of the shared cell are atomic, and they are
// the only atomics. The stats build must show marked = n.

llvm.func @idr_cores() -> i64
llvm.func @idr_run_on_cores(i64, !llvm.ptr, !llvm.ptr)

// lookup t k, borrowing t: 0 when k is absent, else 1 + its value.
func.func private @lookup(%t0: !llvm.ptr, %k: i64) -> i8 {
  cf.br ^loop(%t0 : !llvm.ptr)
^loop(%t: !llvm.ptr):
  %cell = func.call @__is_cell(%t) : (!llvm.ptr) -> i1
  cf.cond_br %cell, ^node, ^absent
^absent:
  %z = arith.constant 0 : i8
  return %z : i8
^node:
  %key = func.call @node_key(%t) : (!llvm.ptr) -> i64
  %lt = arith.cmpi slt, %k, %key : i64
  cf.cond_br %lt, ^left, ^ge
^left:
  %l = func.call @node_l(%t) : (!llvm.ptr) -> !llvm.ptr
  cf.br ^loop(%l : !llvm.ptr)
^ge:
  %gt = arith.cmpi sgt, %k, %key : i64
  cf.cond_br %gt, ^right, ^found
^right:
  %r = func.call @node_r(%t) : (!llvm.ptr) -> !llvm.ptr
  cf.br ^loop(%r : !llvm.ptr)
^found:
  %v = func.call @node_val(%t) : (!llvm.ptr) -> i8
  %one = arith.constant 1 : i8
  %res = arith.addi %v, %one : i8
  return %res : i8
}

// work, for one core, owning `local`, which starts as the shared map.
func.func private @work(%map: !llvm.ptr, %n: i64, %q: i64, %core: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c7 = arith.constant 7 : i64
  %c13 = arith.constant 13 : i64
  %c17 = arith.constant 17 : i64
  %c999 = arith.constant 999 : i64
  %c1000 = arith.constant 1000 : i64
  %gold = arith.constant -7046029254386353131 : i64  // 0x9E3779B97F4A7C15
  %seed0 = arith.constant 88172645463325252 : i64
  %mix = arith.muli %core, %gold : i64
  %x0 = arith.addi %seed0, %mix : i64
  %two_n = arith.muli %n, %c2 : i64
  %true = arith.constant 1 : i8
  %hit = arith.constant 2 : i8
  cf.br ^loop(%map, %x0, %c0, %c0 : !llvm.ptr, i64, i64, i64)
^loop(%local: !llvm.ptr, %x: i64, %j: i64, %hits: i64):
  %done = arith.cmpi eq, %j, %q : i64
  cf.cond_br %done, ^exit, ^step
^step:
  %s1 = arith.shli %x, %c13 : i64
  %x1 = arith.xori %x, %s1 : i64
  %s2 = arith.shrui %x1, %c7 : i64
  %x2 = arith.xori %x1, %s2 : i64
  %s3 = arith.shli %x2, %c17 : i64
  %x3 = arith.xori %x2, %s3 : i64
  %j1 = arith.addi %j, %c1 : i64
  %m = arith.remsi %j, %c1000 : i64
  %isins = arith.cmpi eq, %m, %c999 : i64
  cf.cond_br %isins, ^insert, ^look
^insert:
  %cq = arith.muli %core, %q : i64
  %cqj = arith.addi %cq, %j : i64
  %neg = arith.subi %c0, %cqj : i64
  %key = arith.subi %neg, %c1 : i64
  %local2 = func.call @insert(%local, %key, %true) : (!llvm.ptr, i64, i8) -> !llvm.ptr
  cf.br ^loop(%local2, %x3, %j1, %hits : !llvm.ptr, i64, i64, i64)
^look:
  %k = arith.remui %x3, %two_n : i64
  %r = func.call @lookup(%local, %k) : (!llvm.ptr, i64) -> i8
  %h = arith.cmpi eq, %r, %hit : i8
  %hi = arith.extui %h : i1 to i64
  %hits1 = arith.addi %hits, %hi : i64
  cf.br ^loop(%local, %x3, %j1, %hits1 : !llvm.ptr, i64, i64, i64)
^exit:
  func.call @__rc_drop(%local) : (!llvm.ptr) -> ()
  return %hits : i64
}

// The body run on every core; env holds map, n, q and the results.
llvm.func @body(%env: !llvm.ptr, %core: i64) {
  %pm = llvm.getelementptr %env[0] : (!llvm.ptr) -> !llvm.ptr, i64
  %map = llvm.load %pm : !llvm.ptr -> !llvm.ptr
  %pn = llvm.getelementptr %env[1] : (!llvm.ptr) -> !llvm.ptr, i64
  %n = llvm.load %pn : !llvm.ptr -> i64
  %pq = llvm.getelementptr %env[2] : (!llvm.ptr) -> !llvm.ptr, i64
  %q = llvm.load %pq : !llvm.ptr -> i64
  %pr = llvm.getelementptr %env[3] : (!llvm.ptr) -> !llvm.ptr, i64
  %res = llvm.load %pr : !llvm.ptr -> !llvm.ptr
  %hits = func.call @work(%map, %n, %q, %core) : (!llvm.ptr, i64, i64, i64) -> i64
  %slot = llvm.getelementptr %res[%core] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %hits, %slot : i64, !llvm.ptr
  llvm.return
}

func.func @idr_main() -> i32 {
  %n = llvm.call @idr_read_int() : () -> i64
  %q = llvm.call @idr_read_int() : () -> i64
  %one = arith.constant 1 : i64
  %zero = arith.constant 0 : i64
  %ten = arith.constant 10 : i64
  %leaf = llvm.inttoptr %one : i64 to !llvm.ptr
  cf.br ^build(%n, %leaf : i64, !llvm.ptr)
^build(%i: i64, %t: !llvm.ptr):
  %built = arith.cmpi sle, %i, %zero : i64
  cf.cond_br %built, ^share, ^step
^step:
  %i1 = arith.subi %i, %one : i64
  %rem = arith.remsi %i1, %ten : i64
  %isz = arith.cmpi eq, %rem, %zero : i64
  %v = arith.extui %isz : i1 to i8
  %t1 = func.call @insert(%t, %i1, %v) : (!llvm.ptr, i64, i8) -> !llvm.ptr
  cf.br ^build(%i1, %t1 : i64, !llvm.ptr)
^share:
  // One reference per core, then the crossing: move-or-mark.
  %cores = llvm.call @idr_cores() : () -> i64
  cf.br ^dup(%zero : i64)
^dup(%c: i64):
  %duped = arith.cmpi sge, %c, %cores : i64
  cf.cond_br %duped, ^send, ^dup1
^dup1:
  func.call @__rc_dup(%t) : (!llvm.ptr) -> ()
  %c1 = arith.addi %c, %one : i64
  cf.br ^dup(%c1 : i64)
^send:
  llvm.call @idr_send(%t) : (!llvm.ptr) -> ()
  %four = arith.constant 4 : i64
  %env = llvm.alloca %four x i64 : (i64) -> !llvm.ptr
  %res = llvm.alloca %cores x i64 : (i64) -> !llvm.ptr
  %e0 = llvm.getelementptr %env[0] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %t, %e0 : !llvm.ptr, !llvm.ptr
  %e1 = llvm.getelementptr %env[1] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %n, %e1 : i64, !llvm.ptr
  %e2 = llvm.getelementptr %env[2] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %q, %e2 : i64, !llvm.ptr
  %e3 = llvm.getelementptr %env[3] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %res, %e3 : !llvm.ptr, !llvm.ptr
  %body = llvm.mlir.addressof @body : !llvm.ptr
  llvm.call @idr_run_on_cores(%cores, %body, %env) : (i64, !llvm.ptr, !llvm.ptr) -> ()
  cf.br ^sum(%zero, %zero : i64, i64)
^sum(%k: i64, %acc: i64):
  %summed = arith.cmpi sge, %k, %cores : i64
  cf.cond_br %summed, ^end, ^add
^add:
  %slot = llvm.getelementptr %res[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %h = llvm.load %slot : !llvm.ptr -> i64
  %acc1 = arith.addi %acc, %h : i64
  %k1 = arith.addi %k, %one : i64
  cf.br ^sum(%k1, %acc1 : i64, i64)
^end:
  func.call @__rc_drop(%t) : (!llvm.ptr) -> ()
  llvm.call @idr_put_int(%acc) : (i64) -> ()
  %nl = arith.constant 10 : i32
  llvm.call @idr_put_char(%nl) : (i32) -> ()
  %ok = arith.constant 0 : i32
  return %ok : i32
}
