// bench/gate/linear/linrb/Main.idr, lowered by hand (experiment 4). The same program under two lowerings, which differ only in
// the file placed before this one:
// - linrb-static.mlir, as the compiler will emit it under quantity 1: every
//   matched cell is unique by proof, so a reset is the cell itself (no
//   count test) and a reuse stores the fields that change (no null test).
//   No dup is emitted anywhere.
// - linrb-dynamic.mlir, Lean's best effort: a reset tests the count and, on
//   a shared cell, duplicates its fields and allocates on reuse.
// Both define @reset_node, @reuse and @free_token.
//
// data Tree = Leaf | Node Color (1 _ : Tree) Int Bool (1 _ : Tree)
//   As in rbmap.mlir: Leaf is the immediate 1; Node is tag 1, 40 bytes:
//   header, l, r, key, then color (Red 0, Black 1) and value as bytes at
//   offsets 32 and 33.
//
// balance1 and balance2 are inlined into ins (one call site each), so their
// constructors reuse the cells ins matched: every insert allocates only the
// new leaf. The `Node Red l k v r` that the red tests rebuild is its own
// cell, with nothing stored. count consumes the tree, freeing each cell
// once its fields are read.

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

// Is t a red Node? (t is only inspected.)
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

// ins kx vx t, with balance1 and balance2 inlined.
// Masks of @reuse: 1 color, 2 l, 4 key, 8 val, 16 r.
func.func private @ins(%kx: i64, %vx: i8, %t: !llvm.ptr) -> !llvm.ptr {
  %red = arith.constant 0 : i8
  %black = arith.constant 1 : i8
  %one = arith.constant 1 : i64
  %none = arith.constant 0 : i32
  %cC = arith.constant 1 : i32
  %cL = arith.constant 2 : i32
  %cV = arith.constant 8 : i32
  %cR = arith.constant 16 : i32
  %cCL = arith.constant 3 : i32
  %cCR = arith.constant 17 : i32
  %cLR = arith.constant 18 : i32
  %cCLR = arith.constant 19 : i32
  %leaf = llvm.inttoptr %one : i64 to !llvm.ptr
  %cell = func.call @__is_cell(%t) : (!llvm.ptr) -> i1
  cf.cond_br %cell, ^node, ^new_leaf
^new_leaf:
  // ins kx vx Leaf = Node Red Leaf kx vx Leaf
  %n0 = func.call @node_new(%red, %leaf, %kx, %vx, %leaf) : (i8, !llvm.ptr, i64, i8, !llvm.ptr) -> !llvm.ptr
  return %n0 : !llvm.ptr
^node:
  %color = func.call @node_color(%t) : (!llvm.ptr) -> i8
  %a = func.call @node_l(%t) : (!llvm.ptr) -> !llvm.ptr
  %ky = func.call @node_key(%t) : (!llvm.ptr) -> i64
  %vy = func.call @node_val(%t) : (!llvm.ptr) -> i8
  %b = func.call @node_r(%t) : (!llvm.ptr) -> !llvm.ptr
  %tok = func.call @reset_node(%t) : (!llvm.ptr) -> !llvm.ptr
  %lt = arith.cmpi slt, %kx, %ky : i64
  %eq = arith.cmpi eq, %kx, %ky : i64
  %isred = arith.cmpi eq, %color, %red : i8
  cf.cond_br %isred, ^red, ^black

^red:
  cf.cond_br %lt, ^red_lt, ^red_ge
^red_lt:
  // Node Red (ins kx vx a) ky vy b
  %a2 = func.call @ins(%kx, %vx, %a) : (i64, i8, !llvm.ptr) -> !llvm.ptr
  %r1 = func.call @reuse(%tok, %red, %a2, %ky, %vy, %b, %cL) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %r1 : !llvm.ptr
^red_ge:
  cf.cond_br %eq, ^red_eq, ^red_gt
^red_eq:
  // Node Red a kx vx b (kx is ky)
  %r2 = func.call @reuse(%tok, %red, %a, %kx, %vx, %b, %cV) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %r2 : !llvm.ptr
^red_gt:
  // Node Red a ky vy (ins kx vx b)
  %b2 = func.call @ins(%kx, %vx, %b) : (i64, i8, !llvm.ptr) -> !llvm.ptr
  %r3 = func.call @reuse(%tok, %red, %a, %ky, %vy, %b2, %cR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %r3 : !llvm.ptr

^black:
  cf.cond_br %lt, ^left, ^black_ge
^black_ge:
  cf.cond_br %eq, ^black_eq, ^right
^black_eq:
  // Node Black a kx vx b
  %r4 = func.call @reuse(%tok, %black, %a, %kx, %vx, %b, %cV) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %r4 : !llvm.ptr

// Black, kx < ky: the red test on a; tok holds Black _ ky vy b.
^left:
  %ared = func.call @is_red(%a) : (!llvm.ptr) -> i1
  cf.cond_br %ared, ^left_red, ^left_plain
^left_plain:
  // Node Black (ins kx vx a) ky vy b
  %a3 = func.call @ins(%kx, %vx, %a) : (i64, i8, !llvm.ptr) -> !llvm.ptr
  %r5 = func.call @reuse(%tok, %black, %a3, %ky, %vy, %b, %cL) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %r5 : !llvm.ptr
^left_red:
  // balance1 ky vy b (ins kx vx (Node Red l k v r)): the rebuilt node is a.
  %al = func.call @node_l(%a) : (!llvm.ptr) -> !llvm.ptr
  %ak = func.call @node_key(%a) : (!llvm.ptr) -> i64
  %av = func.call @node_val(%a) : (!llvm.ptr) -> i8
  %ar = func.call @node_r(%a) : (!llvm.ptr) -> !llvm.ptr
  %ta = func.call @reset_node(%a) : (!llvm.ptr) -> !llvm.ptr
  %a1 = func.call @reuse(%ta, %red, %al, %ak, %av, %ar, %none) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %n = func.call @ins(%kx, %vx, %a1) : (i64, i8, !llvm.ptr) -> !llvm.ptr
  %ncell = func.call @__is_cell(%n) : (!llvm.ptr) -> i1
  cf.cond_br %ncell, ^b1_node, ^b1_leaf
^b1_leaf:
  // balance1 kv vv t Leaf = Node Black Leaf kv vv t
  %r6 = func.call @reuse(%tok, %black, %n, %ky, %vy, %b, %cL) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %r6 : !llvm.ptr
^b1_node:
  %nl = func.call @node_l(%n) : (!llvm.ptr) -> !llvm.ptr
  %nr = func.call @node_r(%n) : (!llvm.ptr) -> !llvm.ptr
  %nk = func.call @node_key(%n) : (!llvm.ptr) -> i64
  %nv = func.call @node_val(%n) : (!llvm.ptr) -> i8
  %nlred = func.call @is_red(%nl) : (!llvm.ptr) -> i1
  cf.cond_br %nlred, ^b1_1, ^b1_not1
^b1_1:
  // Node _ (Node Red l kx vx r1) ky vy r2
  //   -> Node Red (Node Black l kx vx r1) ky vy (Node Black r2 kv vv t)
  %l_1 = func.call @node_l(%nl) : (!llvm.ptr) -> !llvm.ptr
  %k_1 = func.call @node_key(%nl) : (!llvm.ptr) -> i64
  %v_1 = func.call @node_val(%nl) : (!llvm.ptr) -> i8
  %r1_1 = func.call @node_r(%nl) : (!llvm.ptr) -> !llvm.ptr
  %t1_1 = func.call @reset_node(%n) : (!llvm.ptr) -> !llvm.ptr
  %t2_1 = func.call @reset_node(%nl) : (!llvm.ptr) -> !llvm.ptr
  %A1 = func.call @reuse(%t2_1, %black, %l_1, %k_1, %v_1, %r1_1, %cC) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %B1 = func.call @reuse(%tok, %black, %nr, %ky, %vy, %b, %cL) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %R1 = func.call @reuse(%t1_1, %red, %A1, %nk, %nv, %B1, %cCLR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %R1 : !llvm.ptr
^b1_not1:
  %nrred = func.call @is_red(%nr) : (!llvm.ptr) -> i1
  cf.cond_br %nrred, ^b1_2, ^b1_3
^b1_2:
  // Node _ l1 ky vy (Node Red l2 kx vx r)
  //   -> Node Red (Node Black l1 ky vy l2) kx vx (Node Black r kv vv t)
  %l2_2 = func.call @node_l(%nr) : (!llvm.ptr) -> !llvm.ptr
  %k_2 = func.call @node_key(%nr) : (!llvm.ptr) -> i64
  %v_2 = func.call @node_val(%nr) : (!llvm.ptr) -> i8
  %r_2 = func.call @node_r(%nr) : (!llvm.ptr) -> !llvm.ptr
  %t1_2 = func.call @reset_node(%n) : (!llvm.ptr) -> !llvm.ptr
  %t2_2 = func.call @reset_node(%nr) : (!llvm.ptr) -> !llvm.ptr
  %A2 = func.call @reuse(%t1_2, %black, %nl, %nk, %nv, %l2_2, %cCR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %B2 = func.call @reuse(%tok, %black, %r_2, %ky, %vy, %b, %cL) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %R2 = func.call @reuse(%t2_2, %red, %A2, %k_2, %v_2, %B2, %cLR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %R2 : !llvm.ptr
^b1_3:
  // Node _ l ky vy r -> Node Black (Node Red l ky vy r) kv vv t
  %t1_3 = func.call @reset_node(%n) : (!llvm.ptr) -> !llvm.ptr
  %A3 = func.call @reuse(%t1_3, %red, %nl, %nk, %nv, %nr, %cC) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %R3 = func.call @reuse(%tok, %black, %A3, %ky, %vy, %b, %cL) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %R3 : !llvm.ptr

// Black, kx > ky: the red test on b; tok holds Black a ky vy _.
^right:
  %bred = func.call @is_red(%b) : (!llvm.ptr) -> i1
  cf.cond_br %bred, ^right_red, ^right_plain
^right_plain:
  // Node Black a ky vy (ins kx vx b)
  %b3 = func.call @ins(%kx, %vx, %b) : (i64, i8, !llvm.ptr) -> !llvm.ptr
  %r7 = func.call @reuse(%tok, %black, %a, %ky, %vy, %b3, %cR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %r7 : !llvm.ptr
^right_red:
  // balance2 a ky vy (ins kx vx (Node Red l k v r)): the rebuilt node is b.
  %bl = func.call @node_l(%b) : (!llvm.ptr) -> !llvm.ptr
  %bk = func.call @node_key(%b) : (!llvm.ptr) -> i64
  %bv = func.call @node_val(%b) : (!llvm.ptr) -> i8
  %br = func.call @node_r(%b) : (!llvm.ptr) -> !llvm.ptr
  %tb = func.call @reset_node(%b) : (!llvm.ptr) -> !llvm.ptr
  %b1 = func.call @reuse(%tb, %red, %bl, %bk, %bv, %br, %none) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %m = func.call @ins(%kx, %vx, %b1) : (i64, i8, !llvm.ptr) -> !llvm.ptr
  %mcell = func.call @__is_cell(%m) : (!llvm.ptr) -> i1
  cf.cond_br %mcell, ^b2_node, ^b2_leaf
^b2_leaf:
  // balance2 t kv vv Leaf = Node Black t kv vv Leaf
  %r8 = func.call @reuse(%tok, %black, %a, %ky, %vy, %m, %cR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %r8 : !llvm.ptr
^b2_node:
  %ml = func.call @node_l(%m) : (!llvm.ptr) -> !llvm.ptr
  %mr = func.call @node_r(%m) : (!llvm.ptr) -> !llvm.ptr
  %mk = func.call @node_key(%m) : (!llvm.ptr) -> i64
  %mv = func.call @node_val(%m) : (!llvm.ptr) -> i8
  %mlred = func.call @is_red(%ml) : (!llvm.ptr) -> i1
  cf.cond_br %mlred, ^b2_1, ^b2_not1
^b2_1:
  // Node _ (Node Red l kx1 vx1 r1) ky vy r2
  //   -> Node Red (Node Black t kv vv l) kx1 vx1 (Node Black r1 ky vy r2)
  %l_3 = func.call @node_l(%ml) : (!llvm.ptr) -> !llvm.ptr
  %k_3 = func.call @node_key(%ml) : (!llvm.ptr) -> i64
  %v_3 = func.call @node_val(%ml) : (!llvm.ptr) -> i8
  %r1_3 = func.call @node_r(%ml) : (!llvm.ptr) -> !llvm.ptr
  %u1_1 = func.call @reset_node(%m) : (!llvm.ptr) -> !llvm.ptr
  %u2_1 = func.call @reset_node(%ml) : (!llvm.ptr) -> !llvm.ptr
  %C1 = func.call @reuse(%tok, %black, %a, %ky, %vy, %l_3, %cR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %D1 = func.call @reuse(%u1_1, %black, %r1_3, %mk, %mv, %mr, %cCL) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %S1 = func.call @reuse(%u2_1, %red, %C1, %k_3, %v_3, %D1, %cLR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %S1 : !llvm.ptr
^b2_not1:
  %mrred = func.call @is_red(%mr) : (!llvm.ptr) -> i1
  cf.cond_br %mrred, ^b2_2, ^b2_3
^b2_2:
  // Node _ l1 ky vy (Node Red l2 kx2 vx2 r2)
  //   -> Node Red (Node Black t kv vv l1) ky vy (Node Black l2 kx2 vx2 r2)
  %l2_4 = func.call @node_l(%mr) : (!llvm.ptr) -> !llvm.ptr
  %k_4 = func.call @node_key(%mr) : (!llvm.ptr) -> i64
  %v_4 = func.call @node_val(%mr) : (!llvm.ptr) -> i8
  %r2_4 = func.call @node_r(%mr) : (!llvm.ptr) -> !llvm.ptr
  %u1_2 = func.call @reset_node(%m) : (!llvm.ptr) -> !llvm.ptr
  %u2_2 = func.call @reset_node(%mr) : (!llvm.ptr) -> !llvm.ptr
  %C2 = func.call @reuse(%tok, %black, %a, %ky, %vy, %ml, %cR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %D2 = func.call @reuse(%u2_2, %black, %l2_4, %k_4, %v_4, %r2_4, %cC) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %S2 = func.call @reuse(%u1_2, %red, %C2, %mk, %mv, %D2, %cCLR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %S2 : !llvm.ptr
^b2_3:
  // Node _ l ky vy r -> Node Black t kv vv (Node Red l ky vy r)
  %u1_3 = func.call @reset_node(%m) : (!llvm.ptr) -> !llvm.ptr
  %C3 = func.call @reuse(%u1_3, %red, %ml, %mk, %mv, %mr, %cC) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  %S3 = func.call @reuse(%tok, %black, %a, %ky, %vy, %C3, %cR) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %S3 : !llvm.ptr
}

// insert k v t = setBlack (ins k v t)
func.func private @insert(%k: i64, %v: i8, %t: !llvm.ptr) -> !llvm.ptr {
  %t1 = func.call @ins(%k, %v, %t) : (i64, i8, !llvm.ptr) -> !llvm.ptr
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
  %cC = arith.constant 1 : i32
  %res = func.call @reuse(%tok, %black, %l, %k1, %v1, %r, %cC) : (!llvm.ptr, i8, !llvm.ptr, i64, i8, !llvm.ptr, i32) -> !llvm.ptr
  return %res : !llvm.ptr
}

// count t acc, consuming t: each cell is freed once its fields are read.
func.func private @count(%t0: !llvm.ptr, %acc0: i64) -> i64 {
  cf.br ^loop(%t0, %acc0 : !llvm.ptr, i64)
^loop(%t: !llvm.ptr, %acc: i64):
  %cell = func.call @__is_cell(%t) : (!llvm.ptr) -> i1
  cf.cond_br %cell, ^node, ^leaf
^leaf:
  return %acc : i64
^node:
  %l = func.call @node_l(%t) : (!llvm.ptr) -> !llvm.ptr
  %v = func.call @node_val(%t) : (!llvm.ptr) -> i8
  %r = func.call @node_r(%t) : (!llvm.ptr) -> !llvm.ptr
  %tok = func.call @reset_node(%t) : (!llvm.ptr) -> !llvm.ptr
  func.call @free_token(%tok) : (!llvm.ptr) -> ()
  %c = func.call @count(%l, %acc) : (!llvm.ptr, i64) -> i64
  %vi = arith.extui %v : i8 to i64
  %acc1 = arith.addi %c, %vi : i64
  cf.br ^loop(%r, %acc1 : !llvm.ptr, i64)
}

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
  %t1 = func.call @insert(%n1, %v, %t) : (i64, i8, !llvm.ptr) -> !llvm.ptr
  cf.br ^loop(%n1, %t1 : i64, !llvm.ptr)
^fin:
  %c = func.call @count(%t, %zero) : (!llvm.ptr, i64) -> i64
  llvm.call @idr_put_int(%c) : (i64) -> ()
  %nl = arith.constant 10 : i32
  llvm.call @idr_put_char(%nl) : (i32) -> ()
  %ok = arith.constant 0 : i32
  return %ok : i32
}
