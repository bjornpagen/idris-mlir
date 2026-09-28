// The binary trees of bench/gate/suite/binarytrees/Main.idr, lowered by
// hand to what the compiler will emit:
// make', check, sumT and the output. binarytrees.mlir (experiment 2) and
// ptrees.mlir and pipe.mlir (experiment 3) add their main.
//
// data Tree = Tip | Node Tree Tree
//   Tip is the immediate 1; Node is tag 1 with two pointer fields, 24 bytes.
//
// What Lean's passes decide here:
// - make' returns a fresh tree: allocation only, no count operation.
// - check's parameter is borrowed (inferBorrow: it only reads it), so the
//   walk does no count operation.
// - sumT's tree dies right after check: one idr.drop, and the runtime frees
//   the whole tree iteratively through the headers.
// - pow2 is a shift, as LLVM makes of the recursion.

llvm.mlir.global internal constant @s_stretch("stretch tree of depth ") {addr_space = 0 : i32} : !llvm.array<22 x i8>
llvm.mlir.global internal constant @s_check("\09 check: ") {addr_space = 0 : i32} : !llvm.array<9 x i8>
llvm.mlir.global internal constant @s_trees("\09 trees of depth ") {addr_space = 0 : i32} : !llvm.array<17 x i8>
llvm.mlir.global internal constant @s_long("long lived tree of depth ") {addr_space = 0 : i32} : !llvm.array<25 x i8>

// make' n d
func.func private @make(%n: i64, %d: i64) -> !llvm.ptr {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %hdr = arith.constant 216736831578832897 : i64  // Node: tag 1, 2 pointers, 3 words
  %leaf = arith.cmpi eq, %d, %c0 : i64
  cf.cond_br %leaf, ^leaf, ^node
^leaf:
  %tip = llvm.inttoptr %c1 : i64 to !llvm.ptr
  %c = llvm.call @idr_alloc_24() : () -> !llvm.ptr
  llvm.store %hdr, %c : i64, !llvm.ptr
  %c_l = llvm.getelementptr %c[1] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %tip, %c_l : !llvm.ptr, !llvm.ptr
  %c_r = llvm.getelementptr %c[2] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %tip, %c_r : !llvm.ptr, !llvm.ptr
  return %c : !llvm.ptr
^node:
  %d1 = arith.subi %d, %c1 : i64
  %l = func.call @make(%n, %d1) : (i64, i64) -> !llvm.ptr
  %n1 = arith.addi %n, %c1 : i64
  %r = func.call @make(%n1, %d1) : (i64, i64) -> !llvm.ptr
  %p = llvm.call @idr_alloc_24() : () -> !llvm.ptr
  llvm.store %hdr, %p : i64, !llvm.ptr
  %p_l = llvm.getelementptr %p[1] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %l, %p_l : !llvm.ptr, !llvm.ptr
  %p_r = llvm.getelementptr %p[2] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %r, %p_r : !llvm.ptr, !llvm.ptr
  return %p : !llvm.ptr
}

// check t, with t borrowed.
func.func private @check(%t: !llvm.ptr) -> i64 {
  %cell = func.call @__is_cell(%t) : (!llvm.ptr) -> i1
  cf.cond_br %cell, ^node, ^tip
^tip:
  %c0 = arith.constant 0 : i64
  return %c0 : i64
^node:
  %t_l = llvm.getelementptr %t[1] : (!llvm.ptr) -> !llvm.ptr, i64
  %l = llvm.load %t_l : !llvm.ptr -> !llvm.ptr
  %t_r = llvm.getelementptr %t[2] : (!llvm.ptr) -> !llvm.ptr, i64
  %r = llvm.load %t_r : !llvm.ptr -> !llvm.ptr
  %cl = func.call @check(%l) : (!llvm.ptr) -> i64
  %cr = func.call @check(%r) : (!llvm.ptr) -> i64
  %c1 = arith.constant 1 : i64
  %s1 = arith.addi %c1, %cl : i64
  %s = arith.addi %s1, %cr : i64
  return %s : i64
}

// sumT d i t: a loop (a tail-recursive join point).
func.func private @sumT(%d: i64, %i0: i64, %t0: i64) -> i64 {
  cf.br ^loop(%i0, %t0 : i64, i64)
^loop(%i: i64, %t: i64):
  %c0 = arith.constant 0 : i64
  %done = arith.cmpi eq, %i, %c0 : i64
  cf.cond_br %done, ^exit, ^body
^body:
  %x = func.call @make(%i, %d) : (i64, i64) -> !llvm.ptr
  %c = func.call @check(%x) : (!llvm.ptr) -> i64
  func.call @__rc_dec(%x) : (!llvm.ptr) -> ()  // make' never returns Tip
  %t1 = arith.addi %t, %c : i64
  %c1 = arith.constant 1 : i64
  %i1 = arith.subi %i, %c1 : i64
  cf.br ^loop(%i1, %t1 : i64, i64)
^exit:
  return %t : i64
}

// out s depth c, with s already written.
func.func private @out_rest(%depth: i64, %c: i64) {
  %of = llvm.mlir.addressof @s_trees : !llvm.ptr
  %of_depth = llvm.getelementptr %of[7] : (!llvm.ptr) -> !llvm.ptr, i8  // " of depth "
  %n10 = arith.constant 10 : i64
  llvm.call @idr_put_str(%of_depth, %n10) : (!llvm.ptr, i64) -> ()
  llvm.call @idr_put_int(%depth) : (i64) -> ()
  %chk = llvm.mlir.addressof @s_check : !llvm.ptr
  %n9 = arith.constant 9 : i64
  llvm.call @idr_put_str(%chk, %n9) : (!llvm.ptr, i64) -> ()
  llvm.call @idr_put_int(%c) : (i64) -> ()
  %nl = arith.constant 10 : i32
  llvm.call @idr_put_char(%nl) : (i32) -> ()
  return
}

