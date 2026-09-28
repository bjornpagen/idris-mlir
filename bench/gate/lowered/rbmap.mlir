// The red-black tree of bench/gate/suite/rbtree/Main.idr (Perceus's
// rbtree.kk), lowered by hand to what the compiler will emit: the cells, reset
// and reuse, ins, insert and the fold that counts. rbtree.mlir (experiment 2)
// and shmap.mlir (experiment 3) add their main. The source binds its trees at
// quantity omega, so reuse is Lean's best effort: every reset tests the count
// at runtime (idr.reset.dyn).
//
// data Tree = Leaf | Node Color Tree Int Bool Tree
//   Leaf is the immediate 1. Node is tag 1, 40 bytes: header, l, r, key,
//   then color (Red 0, Black 1) and value as bytes at offsets 32 and 33.
//
// What Lean's passes decide here:
// - ins, insert and the balance functions own their tree arguments (reset
//   targets); fold's specialization borrows its tree.
// - balanceLeft and balanceRight are inlined into ins (one call site each),
//   so their constructors can reuse the cell of ins's argument.
// - A reset tests the count. Count 1: the cell becomes a token and its
//   fields move to the locals (no count operation). Otherwise the fields are
//   duplicated, the cell is dropped and the token is null.
// - A reuse of a token stores only the fields that change; a null token
//   allocates (the cold path).
// - The tree dies after the fold: one drop frees it iteratively.

// ---- cells -------------------------------------------------------------------

func.func private @node_l(%c: !llvm.ptr) -> !llvm.ptr {
  %p = llvm.getelementptr %c[1] : (!llvm.ptr) -> !llvm.ptr, i64
  %v = llvm.load %p : !llvm.ptr -> !llvm.ptr
  return %v : !llvm.ptr
}
func.func private @node_r(%c: !llvm.ptr) -> !llvm.ptr {
  %p = llvm.getelementptr %c[2] : (!llvm.ptr) -> !llvm.ptr, i64
  %v = llvm.load %p : !llvm.ptr -> !llvm.ptr
  return %v : !llvm.ptr
}
func.func private @node_key(%c: !llvm.ptr) -> i64 {
  %p = llvm.getelementptr %c[3] : (!llvm.ptr) -> !llvm.ptr, i64
  %v = llvm.load %p : !llvm.ptr -> i64
  return %v : i64
}
func.func private @node_color(%c: !llvm.ptr) -> i8 {
  %p = llvm.getelementptr %c[32] : (!llvm.ptr) -> !llvm.ptr, i8
  %v = llvm.load %p : !llvm.ptr -> i8
  return %v : i8
}
func.func private @node_val(%c: !llvm.ptr) -> i8 {
  %p = llvm.getelementptr %c[33] : (!llvm.ptr) -> !llvm.ptr, i8
  %v = llvm.load %p : !llvm.ptr -> i8
  return %v : i8
}

func.func private @node_new(%color: i8, %l: !llvm.ptr, %key: i64, %val: i8, %r: !llvm.ptr) -> !llvm.ptr {
  %c = llvm.call @idr_alloc_40() : () -> !llvm.ptr
  %hdr = arith.constant 360852019654688769 : i64  // tag 1, 2 pointers, 5 words
  llvm.store %hdr, %c : i64, !llvm.ptr
  %pl = llvm.getelementptr %c[1] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %l, %pl : !llvm.ptr, !llvm.ptr
  %pr = llvm.getelementptr %c[2] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %r, %pr : !llvm.ptr, !llvm.ptr
  %pk = llvm.getelementptr %c[3] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %key, %pk : i64, !llvm.ptr
  %pc = llvm.getelementptr %c[32] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.store %color, %pc : i8, !llvm.ptr
  %pv = llvm.getelementptr %c[33] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.store %val, %pv : i8, !llvm.ptr
  return %c : !llvm.ptr
}

// idr.reset.dyn on a Node: the token, or null after duplicating its fields
// and dropping it.
func.func private @reset_node(%x: !llvm.ptr) -> !llvm.ptr {
  %u = func.call @__rc_unique(%x) : (!llvm.ptr) -> i1
  cf.cond_br %u, ^hot, ^cold
^hot:
  return %x : !llvm.ptr
^cold:
  %l = func.call @node_l(%x) : (!llvm.ptr) -> !llvm.ptr
  func.call @__rc_dup(%l) : (!llvm.ptr) -> ()
  %r = func.call @node_r(%x) : (!llvm.ptr) -> !llvm.ptr
  func.call @__rc_dup(%r) : (!llvm.ptr) -> ()
  func.call @__rc_dec(%x) : (!llvm.ptr) -> ()
  %null = llvm.mlir.zero : !llvm.ptr
  return %null : !llvm.ptr
}

// idr.reuse of a token as Node color l key val r. The token's cell already
// holds the fields not in `changed` (1 color, 2 l, 4 key, 8 val, 16 r, a
// constant at every call); a null token allocates.
func.func private @reuse(%tok: !llvm.ptr, %color: i8, %l: !llvm.ptr, %key: i64, %val: i8, %r: !llvm.ptr, %changed: i32) -> !llvm.ptr {
  %null = llvm.mlir.zero : !llvm.ptr
  %fresh = llvm.icmp "eq" %tok, %null : !llvm.ptr
  cf.cond_br %fresh, ^new, ^color
^new:
  %n = func.call @node_new(%color, %l, %key, %val, %r) : (i8, !llvm.ptr, i64, i8, !llvm.ptr) -> !llvm.ptr
  return %n : !llvm.ptr
^color:
  %z = arith.constant 0 : i32
  %m1 = arith.constant 1 : i32
  %b1 = arith.andi %changed, %m1 : i32
  %s1 = arith.cmpi ne, %b1, %z : i32
  cf.cond_br %s1, ^set_color, ^l
^set_color:
  %pc = llvm.getelementptr %tok[32] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.store %color, %pc : i8, !llvm.ptr
  cf.br ^l
^l:
  %m2 = arith.constant 2 : i32
  %b2 = arith.andi %changed, %m2 : i32
  %s2 = arith.cmpi ne, %b2, %z : i32
  cf.cond_br %s2, ^set_l, ^key
^set_l:
  %pl = llvm.getelementptr %tok[1] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %l, %pl : !llvm.ptr, !llvm.ptr
  cf.br ^key
^key:
  %m4 = arith.constant 4 : i32
  %b4 = arith.andi %changed, %m4 : i32
  %s4 = arith.cmpi ne, %b4, %z : i32
  cf.cond_br %s4, ^set_key, ^val
^set_key:
  %pk = llvm.getelementptr %tok[3] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %key, %pk : i64, !llvm.ptr
  cf.br ^val
^val:
  %m8 = arith.constant 8 : i32
  %b8 = arith.andi %changed, %m8 : i32
  %s8 = arith.cmpi ne, %b8, %z : i32
  cf.cond_br %s8, ^set_val, ^r
^set_val:
  %pv = llvm.getelementptr %tok[33] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.store %val, %pv : i8, !llvm.ptr
  cf.br ^r
^r:
  %m16 = arith.constant 16 : i32
  %b16 = arith.andi %changed, %m16 : i32
  %s16 = arith.cmpi ne, %b16, %z : i32
  cf.cond_br %s16, ^set_r, ^done
^set_r:
  %pr = llvm.getelementptr %tok[2] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %r, %pr : !llvm.ptr, !llvm.ptr
  cf.br ^done
^done:
  return %tok : !llvm.ptr
}

// A token that no constructor reuses: its fields have moved, so only the
// cell is freed.
func.func private @free_token(%tok: !llvm.ptr) {
  %null = llvm.mlir.zero : !llvm.ptr
  %fresh = llvm.icmp "eq" %tok, %null : !llvm.ptr
  cf.cond_br %fresh, ^done, ^free
^free:
  llvm.call @idr_free_40(%tok) : (!llvm.ptr) -> ()
  cf.br ^done
^done:
  return
}

// isRed t, with t borrowed.
func.func private @is_red(%t: !llvm.ptr) -> i1 {
  %cell = func.call @__is_cell(%t) : (!llvm.ptr) -> i1
  cf.cond_br %cell, ^node, ^leaf
^leaf:
  %f = arith.constant false
  return %f : i1
^node:
  %c = func.call @node_color(%t) : (!llvm.ptr) -> i8
  %red = arith.constant 0 : i8
  %r = arith.cmpi eq, %c, %red : i8
  return %r : i1
}

// ---- the program ---------------------------------------------------------------

// ins t k v, with t owned.
func.func private @ins(%t: !llvm.ptr, %k: i64, %v: i8) -> !llvm.ptr {
  %red = arith.constant 0 : i8
  %black = arith.constant 1 : i8
  %one = arith.constant 1 : i64
  %cL = arith.constant 2 : i32
  %cV = arith.constant 8 : i32
  %cR = arith.constant 16 : i32
  %cColor = arith.constant 1 : i32
  %cColorL = arith.constant 3 : i32
  %cColorLR = arith.constant 19 : i32
  %cLR = arith.constant 18 : i32
  %cColorR = arith.constant 17 : i32
  %cell = func.call @__is_cell(%t) : (!llvm.ptr) -> i1
  cf.cond_br %cell, ^node, ^leaf
^leaf:
  %leaf = llvm.inttoptr %one : i64 to !llvm.ptr
  %n = func.call @node_new(%red, %leaf, %k, %v, %leaf) : (i8, !llvm.ptr, i64, i8, !llvm.ptr) -> !llvm.ptr
  return %n : !llvm.ptr
^node:
  %color = func.call @node_color(%t) : (!llvm.ptr) -> i8
  %kx = func.call @node_key(%t) : (!llvm.ptr) -> i64
  %vx = func.call @node_val(%t) : (!llvm.ptr) -> i8
  %l = func.call @node_l(%t) : (!llvm.ptr) -> !llvm.ptr
  %r = func.call @node_r(%t) : (!llvm.ptr) -> !llvm.ptr
  %lt = arith.cmpi slt, %k, %kx : i64
  %gt = arith.cmpi sgt, %k, %kx : i64
  %isred = arith.cmpi eq, %color, %red : i8
  cf.cond_br %isred, ^red, ^black
^red:
  %tr = func.call @reset_node(%t) : (!llvm.ptr) -> !llvm.ptr
  cf.cond_br %lt, ^red_lt, ^red_ge
^red_lt:
  %rl2 = func.call @ins(%l, %k, %v) : (!llvm.ptr, i64, i8) -> !llvm.ptr
  %rres1 = func.call @reuse(%tr, %red, %rl2, %kx, %vx, %r, %cL) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %rres1 : !llvm.ptr
^red_ge:
  cf.cond_br %gt, ^red_gt, ^red_eq
^red_gt:
  %rr2 = func.call @ins(%r, %k, %v) : (!llvm.ptr, i64, i8) -> !llvm.ptr
  %rres2 = func.call @reuse(%tr, %red, %l, %kx, %vx, %rr2, %cR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %rres2 : !llvm.ptr
^red_eq:
  %rres3 = func.call @reuse(%tr, %red, %l, %k, %v, %r, %cV) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %rres3 : !llvm.ptr

^black:
  cf.cond_br %lt, ^b_lt, ^b_ge
^b_lt:
  %lred = func.call @is_red(%l) : (!llvm.ptr) -> i1
  %tb = func.call @reset_node(%t) : (!llvm.ptr) -> !llvm.ptr
  %l1 = func.call @ins(%l, %k, %v) : (!llvm.ptr, i64, i8) -> !llvm.ptr
  cf.cond_br %lred, ^bl, ^b_lt_plain
^b_lt_plain:
  %bres1 = func.call @reuse(%tb, %black, %l1, %kx, %vx, %r, %cL) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %bres1 : !llvm.ptr

// balanceLeft l1 kx vx r, inlined; tb is the token of ins's Black cell.
^bl:
  %l1cell = func.call @__is_cell(%l1) : (!llvm.ptr) -> i1
  cf.cond_br %l1cell, ^bl_node, ^bl_leaf
^bl_leaf:
  func.call @free_token(%tb) : (!llvm.ptr) -> ()
  func.call @__rc_drop(%r) : (!llvm.ptr) -> ()
  return %l1 : !llvm.ptr
^bl_node:
  %ll = func.call @node_l(%l1) : (!llvm.ptr) -> !llvm.ptr
  %lr = func.call @node_r(%l1) : (!llvm.ptr) -> !llvm.ptr
  %ky = func.call @node_key(%l1) : (!llvm.ptr) -> i64
  %vy = func.call @node_val(%l1) : (!llvm.ptr) -> i8
  %llred = func.call @is_red(%ll) : (!llvm.ptr) -> i1
  cf.cond_br %llred, ^bl_1, ^bl_not1
^bl_1:
  // Node _ (Node Red lx kx2 vx2 rx) ky vy ry
  //   -> Node Red (Node Black lx kx2 vx2 rx) ky vy (Node Black ry kx vx r)
  %t1a = func.call @reset_node(%l1) : (!llvm.ptr) -> !llvm.ptr
  %lx = func.call @node_l(%ll) : (!llvm.ptr) -> !llvm.ptr
  %rx = func.call @node_r(%ll) : (!llvm.ptr) -> !llvm.ptr
  %kx2 = func.call @node_key(%ll) : (!llvm.ptr) -> i64
  %vx2 = func.call @node_val(%ll) : (!llvm.ptr) -> i8
  %t2a = func.call @reset_node(%ll) : (!llvm.ptr) -> !llvm.ptr
  %a1 = func.call @reuse(%t2a, %black, %lx, %kx2, %vx2, %rx, %cColor) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %b1 = func.call @reuse(%tb, %black, %lr, %kx, %vx, %r, %cL) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %root1 = func.call @reuse(%t1a, %red, %a1, %ky, %vy, %b1, %cColorLR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %root1 : !llvm.ptr
^bl_not1:
  %lrred = func.call @is_red(%lr) : (!llvm.ptr) -> i1
  cf.cond_br %lrred, ^bl_2, ^bl_3
^bl_2:
  // Node _ ly ky vy (Node Red lx kx2 vx2 rx)
  //   -> Node Red (Node Black ly ky vy lx) kx2 vx2 (Node Black rx kx vx r)
  %t1b = func.call @reset_node(%l1) : (!llvm.ptr) -> !llvm.ptr
  %lx_b = func.call @node_l(%lr) : (!llvm.ptr) -> !llvm.ptr
  %rx_b = func.call @node_r(%lr) : (!llvm.ptr) -> !llvm.ptr
  %kx2_b = func.call @node_key(%lr) : (!llvm.ptr) -> i64
  %vx2_b = func.call @node_val(%lr) : (!llvm.ptr) -> i8
  %t2b = func.call @reset_node(%lr) : (!llvm.ptr) -> !llvm.ptr
  %a2 = func.call @reuse(%t1b, %black, %ll, %ky, %vy, %lx_b, %cColorR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %b2 = func.call @reuse(%tb, %black, %rx_b, %kx, %vx, %r, %cL) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %root2 = func.call @reuse(%t2b, %red, %a2, %kx2_b, %vx2_b, %b2, %cLR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %root2 : !llvm.ptr
^bl_3:
  // Node _ lx kx2 vx2 rx -> Node Black (Node Red lx kx2 vx2 rx) kx vx r
  %t1c = func.call @reset_node(%l1) : (!llvm.ptr) -> !llvm.ptr
  %a3 = func.call @reuse(%t1c, %red, %ll, %ky, %vy, %lr, %cColor) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %root3 = func.call @reuse(%tb, %black, %a3, %kx, %vx, %r, %cL) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %root3 : !llvm.ptr

^b_ge:
  cf.cond_br %gt, ^b_gt, ^b_eq
^b_eq:
  %tbe = func.call @reset_node(%t) : (!llvm.ptr) -> !llvm.ptr
  %bres3 = func.call @reuse(%tbe, %black, %l, %k, %v, %r, %cV) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %bres3 : !llvm.ptr
^b_gt:
  %rred = func.call @is_red(%r) : (!llvm.ptr) -> i1
  %tg = func.call @reset_node(%t) : (!llvm.ptr) -> !llvm.ptr
  %r1 = func.call @ins(%r, %k, %v) : (!llvm.ptr, i64, i8) -> !llvm.ptr
  cf.cond_br %rred, ^br, ^b_gt_plain
^b_gt_plain:
  %bres2 = func.call @reuse(%tg, %black, %l, %kx, %vx, %r1, %cR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %bres2 : !llvm.ptr

// balanceRight l kx vx r1, inlined; tg is the token of ins's Black cell.
^br:
  %r1cell = func.call @__is_cell(%r1) : (!llvm.ptr) -> i1
  cf.cond_br %r1cell, ^br_node, ^br_leaf
^br_leaf:
  func.call @free_token(%tg) : (!llvm.ptr) -> ()
  func.call @__rc_drop(%l) : (!llvm.ptr) -> ()
  return %r1 : !llvm.ptr
^br_node:
  %rl = func.call @node_l(%r1) : (!llvm.ptr) -> !llvm.ptr
  %rr = func.call @node_r(%r1) : (!llvm.ptr) -> !llvm.ptr
  %ky_r = func.call @node_key(%r1) : (!llvm.ptr) -> i64
  %vy_r = func.call @node_val(%r1) : (!llvm.ptr) -> i8
  %rlred = func.call @is_red(%rl) : (!llvm.ptr) -> i1
  cf.cond_br %rlred, ^br_1, ^br_not1
^br_1:
  // Node _ (Node Red lx kx2 vx2 rx) ky vy ry
  //   -> Node Red (Node Black l kx vx lx) kx2 vx2 (Node Black rx ky vy ry)
  %u1a = func.call @reset_node(%r1) : (!llvm.ptr) -> !llvm.ptr
  %lx_c = func.call @node_l(%rl) : (!llvm.ptr) -> !llvm.ptr
  %rx_c = func.call @node_r(%rl) : (!llvm.ptr) -> !llvm.ptr
  %kx2_c = func.call @node_key(%rl) : (!llvm.ptr) -> i64
  %vx2_c = func.call @node_val(%rl) : (!llvm.ptr) -> i8
  %u2a = func.call @reset_node(%rl) : (!llvm.ptr) -> !llvm.ptr
  %ra1 = func.call @reuse(%tg, %black, %l, %kx, %vx, %lx_c, %cR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %rb1 = func.call @reuse(%u1a, %black, %rx_c, %ky_r, %vy_r, %rr, %cColorL) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %rroot1 = func.call @reuse(%u2a, %red, %ra1, %kx2_c, %vx2_c, %rb1, %cLR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %rroot1 : !llvm.ptr
^br_not1:
  %rrred = func.call @is_red(%rr) : (!llvm.ptr) -> i1
  cf.cond_br %rrred, ^br_2, ^br_3
^br_2:
  // Node _ lx kx2 vx2 (Node Red ly ky2 vy2 ry)
  //   -> Node Red (Node Black l kx vx lx) kx2 vx2 (Node Black ly ky2 vy2 ry)
  %u1b = func.call @reset_node(%r1) : (!llvm.ptr) -> !llvm.ptr
  %ly_d = func.call @node_l(%rr) : (!llvm.ptr) -> !llvm.ptr
  %ry_d = func.call @node_r(%rr) : (!llvm.ptr) -> !llvm.ptr
  %ky2_d = func.call @node_key(%rr) : (!llvm.ptr) -> i64
  %vy2_d = func.call @node_val(%rr) : (!llvm.ptr) -> i8
  %u2b = func.call @reset_node(%rr) : (!llvm.ptr) -> !llvm.ptr
  %ra2 = func.call @reuse(%tg, %black, %l, %kx, %vx, %rl, %cR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %rb2 = func.call @reuse(%u2b, %black, %ly_d, %ky2_d, %vy2_d, %ry_d, %cColor) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %rroot2 = func.call @reuse(%u1b, %red, %ra2, %ky_r, %vy_r, %rb2, %cColorLR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %rroot2 : !llvm.ptr
^br_3:
  // Node _ lx kx2 vx2 rx -> Node Black l kx vx (Node Red lx kx2 vx2 rx)
  %u1c = func.call @reset_node(%r1) : (!llvm.ptr) -> !llvm.ptr
  %ra3 = func.call @reuse(%u1c, %red, %rl, %ky_r, %vy_r, %rr, %cColor) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %rroot3 = func.call @reuse(%tg, %black, %l, %kx, %vx, %ra3, %cR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %rroot3 : !llvm.ptr
}

// insert t k v = setBlack (ins t k v)
func.func private @insert(%t: !llvm.ptr, %k: i64, %v: i8) -> !llvm.ptr {
  %t1 = func.call @ins(%t, %k, %v) : (!llvm.ptr, i64, i8) -> !llvm.ptr
  %cell = func.call @__is_cell(%t1) : (!llvm.ptr) -> i1
  cf.cond_br %cell, ^node, ^leaf
^leaf:
  return %t1 : !llvm.ptr
^node:
  %l = func.call @node_l(%t1) : (!llvm.ptr) -> !llvm.ptr
  %r = func.call @node_r(%t1) : (!llvm.ptr) -> !llvm.ptr
  %k1 = func.call @node_key(%t1) : (!llvm.ptr) -> i64
  %v1 = func.call @node_val(%t1) : (!llvm.ptr) -> i8
  %tok = func.call @reset_node(%t1) : (!llvm.ptr) -> !llvm.ptr
  %black = arith.constant 1 : i8
  %cColor = arith.constant 1 : i32
  %res = func.call @reuse(%tok, %black, %l, %k1, %v1, %r, %cColor) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %res : !llvm.ptr
}

// fold (\_, v, r => if v then r + 1 else r) t b, specialized; t borrowed.
func.func private @count(%t0: !llvm.ptr, %b0: i64) -> i64 {
  cf.br ^loop(%t0, %b0 : !llvm.ptr, i64)
^loop(%t: !llvm.ptr, %b: i64):
  %cell = func.call @__is_cell(%t) : (!llvm.ptr) -> i1
  cf.cond_br %cell, ^node, ^leaf
^leaf:
  return %b : i64
^node:
  %l = func.call @node_l(%t) : (!llvm.ptr) -> !llvm.ptr
  %bl = func.call @count(%l, %b) : (!llvm.ptr, i64) -> i64
  %v = func.call @node_val(%t) : (!llvm.ptr) -> i8
  %vi = arith.extui %v : i8 to i64
  %b1 = arith.addi %bl, %vi : i64
  %r = func.call @node_r(%t) : (!llvm.ptr) -> !llvm.ptr
  cf.br ^loop(%r, %b1 : !llvm.ptr, i64)
}
