// bench/gate/suite/deriv/Main.idr, lowered by hand to what the compiler
// will emit (experiment 2). The source
// binds everything at quantity omega: reuse is Lean's best effort, with a
// count test at every reset.
//
// data Expr = Val Int | Var String | Add Expr Expr | Mul Expr Expr
//           | Pow Expr Expr | Ln Expr
//   No nullary constructor, so every Expr is a cell. Tags 0 to 5.
//   Val: header, value (16 bytes). Var: header, string (16). Add, Mul, Pow:
//   header, two fields (24). Ln: header, one field (16).
//
// What Lean's passes and our cells decide here:
// - Closed terms are persistent static cells with count 0: the
//   string "x", Var "x", powr x x (which is Pow x x), and the results
//   Val 0, Val 1 and Val (-1). Counting them costs a load and a compare.
// - d and count borrow their expression (inferBorrow; Koka's deriv.kk
//   writes the same borrows by hand), so d duplicates a subterm each time it
//   passes it to add, mul, powr or ln, which own their arguments.
// - add, mul, powr and ln reuse a matched Val cell for the Val they build
//   (reset/reuse with a count test); a cell matched but not rebuilt is
//   freed, and its fields move to the locals.

llvm.mlir.global internal constant @str_x(dense<[216172786408751104, 1, 120]> : tensor<3xi64>) {addr_space = 0 : i32} : !llvm.array<3 x i64>
llvm.mlir.global internal constant @val_0(dense<[144115188075855872, 0]> : tensor<2xi64>) {addr_space = 0 : i32} : !llvm.array<2 x i64>
llvm.mlir.global internal constant @val_1(dense<[144115188075855872, 1]> : tensor<2xi64>) {addr_space = 0 : i32} : !llvm.array<2 x i64>
llvm.mlir.global internal constant @val_m1(dense<[144115188075855872, -1]> : tensor<2xi64>) {addr_space = 0 : i32} : !llvm.array<2 x i64>
llvm.mlir.global internal constant @var_x() {addr_space = 0 : i32} : !llvm.struct<(i64, ptr)> {
  %0 = llvm.mlir.undef : !llvm.struct<(i64, ptr)>
  %h = llvm.mlir.constant(144397762564194304 : i64) : i64
  %1 = llvm.insertvalue %h, %0[0] : !llvm.struct<(i64, ptr)>
  %s = llvm.mlir.addressof @str_x : !llvm.ptr
  %2 = llvm.insertvalue %s, %1[1] : !llvm.struct<(i64, ptr)>
  llvm.return %2 : !llvm.struct<(i64, ptr)>
}
llvm.mlir.global internal constant @pow_x_x() {addr_space = 0 : i32} : !llvm.struct<(i64, ptr, ptr)> {
  %0 = llvm.mlir.undef : !llvm.struct<(i64, ptr, ptr)>
  %h = llvm.mlir.constant(216740130113716224 : i64) : i64
  %1 = llvm.insertvalue %h, %0[0] : !llvm.struct<(i64, ptr, ptr)>
  %x = llvm.mlir.addressof @var_x : !llvm.ptr
  %2 = llvm.insertvalue %x, %1[1] : !llvm.struct<(i64, ptr, ptr)>
  %3 = llvm.insertvalue %x, %2[2] : !llvm.struct<(i64, ptr, ptr)>
  llvm.return %3 : !llvm.struct<(i64, ptr, ptr)>
}
llvm.mlir.global internal constant @s_count(" count: ") {addr_space = 0 : i32} : !llvm.array<8 x i8>

// ---- cells -------------------------------------------------------------------

func.func private @tag(%c: !llvm.ptr) -> i8 {
  %p = llvm.getelementptr %c[5] : (!llvm.ptr) -> !llvm.ptr, i8
  %t = llvm.load %p : !llvm.ptr -> i8
  return %t : i8
}
func.func private @is(%c: !llvm.ptr, %t: i8) -> i1 {
  %x = func.call @tag(%c) : (!llvm.ptr) -> i8
  %b = arith.cmpi eq, %x, %t : i8
  return %b : i1
}
func.func private @fld0(%c: !llvm.ptr) -> !llvm.ptr {
  %p = llvm.getelementptr %c[1] : (!llvm.ptr) -> !llvm.ptr, i64
  %v = llvm.load %p : !llvm.ptr -> !llvm.ptr
  return %v : !llvm.ptr
}
func.func private @fld1(%c: !llvm.ptr) -> !llvm.ptr {
  %p = llvm.getelementptr %c[2] : (!llvm.ptr) -> !llvm.ptr, i64
  %v = llvm.load %p : !llvm.ptr -> !llvm.ptr
  return %v : !llvm.ptr
}
func.func private @val_of(%c: !llvm.ptr) -> i64 {
  %p = llvm.getelementptr %c[1] : (!llvm.ptr) -> !llvm.ptr, i64
  %v = llvm.load %p : !llvm.ptr -> i64
  return %v : i64
}
// Val c with value v? (c is any Expr.)
func.func private @is_val(%c: !llvm.ptr, %v: i64) -> i1 {
  %t0 = arith.constant 0 : i8
  %isv = func.call @is(%c, %t0) : (!llvm.ptr, i8) -> i1
  cf.cond_br %isv, ^val, ^no
^no:
  %f = arith.constant false
  return %f : i1
^val:
  %x = func.call @val_of(%c) : (!llvm.ptr) -> i64
  %b = arith.cmpi eq, %x, %v : i64
  return %b : i1
}

func.func private @new_val(%v: i64) -> !llvm.ptr {
  %c = llvm.call @idr_alloc_16() : () -> !llvm.ptr
  %h = arith.constant 144115188075855873 : i64
  llvm.store %h, %c : i64, !llvm.ptr
  %p = llvm.getelementptr %c[1] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %v, %p : i64, !llvm.ptr
  return %c : !llvm.ptr
}
// Add, Mul or Pow, by header.
func.func private @new_bin(%h: i64, %a: !llvm.ptr, %b: !llvm.ptr) -> !llvm.ptr {
  %c = llvm.call @idr_alloc_24() : () -> !llvm.ptr
  llvm.store %h, %c : i64, !llvm.ptr
  %pa = llvm.getelementptr %c[1] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %a, %pa : !llvm.ptr, !llvm.ptr
  %pb = llvm.getelementptr %c[2] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %b, %pb : !llvm.ptr, !llvm.ptr
  return %c : !llvm.ptr
}
func.func private @new_ln(%a: !llvm.ptr) -> !llvm.ptr {
  %c = llvm.call @idr_alloc_16() : () -> !llvm.ptr
  %h = arith.constant 144402160610705409 : i64
  llvm.store %h, %c : i64, !llvm.ptr
  %pa = llvm.getelementptr %c[1] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %a, %pa : !llvm.ptr, !llvm.ptr
  return %c : !llvm.ptr
}

// idr.reset.dyn on a Val: the token, or null after dropping it.
func.func private @reset_val(%c: !llvm.ptr) -> !llvm.ptr {
  %u = func.call @__rc_unique(%c) : (!llvm.ptr) -> i1
  cf.cond_br %u, ^hot, ^cold
^hot:
  return %c : !llvm.ptr
^cold:
  func.call @__rc_dec(%c) : (!llvm.ptr) -> ()
  %null = llvm.mlir.zero : !llvm.ptr
  return %null : !llvm.ptr
}
// idr.reset.dyn on a cell with two fields.
func.func private @reset_bin(%c: !llvm.ptr) -> !llvm.ptr {
  %u = func.call @__rc_unique(%c) : (!llvm.ptr) -> i1
  cf.cond_br %u, ^hot, ^cold
^hot:
  return %c : !llvm.ptr
^cold:
  %a = func.call @fld0(%c) : (!llvm.ptr) -> !llvm.ptr
  func.call @__rc_inc(%a) : (!llvm.ptr) -> ()
  %b = func.call @fld1(%c) : (!llvm.ptr) -> !llvm.ptr
  func.call @__rc_inc(%b) : (!llvm.ptr) -> ()
  func.call @__rc_dec(%c) : (!llvm.ptr) -> ()
  %null = llvm.mlir.zero : !llvm.ptr
  return %null : !llvm.ptr
}
// idr.reuse of a Val token as Val v; `same` when the cell already holds v.
func.func private @reuse_val(%tok: !llvm.ptr, %v: i64, %same: i1) -> !llvm.ptr {
  %null = llvm.mlir.zero : !llvm.ptr
  %fresh = llvm.icmp "eq" %tok, %null : !llvm.ptr
  cf.cond_br %fresh, ^new, ^old
^new:
  %n = func.call @new_val(%v) : (i64) -> !llvm.ptr
  return %n : !llvm.ptr
^old:
  cf.cond_br %same, ^done, ^store
^store:
  %p = llvm.getelementptr %tok[1] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %v, %p : i64, !llvm.ptr
  cf.br ^done
^done:
  return %tok : !llvm.ptr
}
// A 24-byte token that nothing reuses: its fields have moved, so only the
// cell is freed.
func.func private @free_token_24(%tok: !llvm.ptr) {
  %null = llvm.mlir.zero : !llvm.ptr
  %fresh = llvm.icmp "eq" %tok, %null : !llvm.ptr
  cf.cond_br %fresh, ^done, ^free
^free:
  llvm.call @idr_free_24(%tok) : (!llvm.ptr) -> ()
  cf.br ^done
^done:
  return
}

// ---- the program ---------------------------------------------------------------

func.func private @pown(%a: i64, %n: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %is0 = arith.cmpi eq, %n, %c0 : i64
  cf.cond_br %is0, ^one, ^n1
^one:
  return %c1 : i64
^n1:
  %is1 = arith.cmpi eq, %n, %c1 : i64
  cf.cond_br %is1, ^a, ^rec
^a:
  return %a : i64
^rec:
  %h = arith.divsi %n, %c2 : i64
  %b = func.call @pown(%a, %h) : (i64, i64) -> i64
  %bb = arith.muli %b, %b : i64
  %m = arith.remsi %n, %c2 : i64
  %even = arith.cmpi eq, %m, %c0 : i64
  %f = arith.select %even, %c1, %a : i64
  %r = arith.muli %bb, %f : i64
  return %r : i64
}

// add a b, owning both.
func.func private @add(%a: !llvm.ptr, %b: !llvm.ptr) -> !llvm.ptr {
  %tVal = arith.constant 0 : i8
  %tAdd = arith.constant 2 : i8
  %c0 = arith.constant 0 : i64
  %yes = arith.constant true
  %no = arith.constant false
  %hAdd = arith.constant 216737931090460673 : i64
  %aval = func.call @is(%a, %tVal) : (!llvm.ptr, i8) -> i1
  %bval = func.call @is(%b, %tVal) : (!llvm.ptr, i8) -> i1
  cf.cond_br %aval, ^a_val, ^a_other
^a_val:
  %n = func.call @val_of(%a) : (!llvm.ptr) -> i64
  cf.cond_br %bval, ^vv, ^a_val2
^vv:
  // add (Val n) (Val m) = Val (n + m)
  %m = func.call @val_of(%b) : (!llvm.ptr) -> i64
  %tok = func.call @reset_val(%a) : (!llvm.ptr) -> !llvm.ptr
  func.call @__rc_dec(%b) : (!llvm.ptr) -> ()
  %s = arith.addi %n, %m : i64
  %r1 = func.call @reuse_val(%tok, %s, %no) : (!llvm.ptr, i64, i1) -> !llvm.ptr
  return %r1 : !llvm.ptr
^a_val2:
  %n0 = arith.cmpi eq, %n, %c0 : i64
  cf.cond_br %n0, ^zero_l, ^a_val3
^zero_l:
  // add (Val 0) f = f
  func.call @__rc_dec(%a) : (!llvm.ptr) -> ()
  return %b : !llvm.ptr
^a_val3:
  %badd = func.call @is(%b, %tAdd) : (!llvm.ptr, i8) -> i1
  cf.cond_br %badd, ^a_val4, ^mk
^a_val4:
  %ba = func.call @fld0(%b) : (!llvm.ptr) -> !llvm.ptr
  %baval = func.call @is(%ba, %tVal) : (!llvm.ptr, i8) -> i1
  cf.cond_br %baval, ^fold5, ^mk
^fold5:
  // add (Val n) (Add (Val m) f) = add (Val (n + m)) f
  %m5 = func.call @val_of(%ba) : (!llvm.ptr) -> i64
  %f5 = func.call @fld1(%b) : (!llvm.ptr) -> !llvm.ptr
  func.call @__rc_inc(%f5) : (!llvm.ptr) -> ()
  func.call @__rc_dec(%b) : (!llvm.ptr) -> ()
  %tok5 = func.call @reset_val(%a) : (!llvm.ptr) -> !llvm.ptr
  %s5 = arith.addi %n, %m5 : i64
  %v5 = func.call @reuse_val(%tok5, %s5, %no) : (!llvm.ptr, i64, i1) -> !llvm.ptr
  %r5 = func.call @add(%v5, %f5) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  return %r5 : !llvm.ptr
^a_other:
  cf.cond_br %bval, ^b_val, ^b_other
^b_val:
  %m3 = func.call @val_of(%b) : (!llvm.ptr) -> i64
  %m30 = arith.cmpi eq, %m3, %c0 : i64
  cf.cond_br %m30, ^zero_r, ^swap
^zero_r:
  // add f (Val 0) = f
  func.call @__rc_dec(%b) : (!llvm.ptr) -> ()
  return %a : !llvm.ptr
^swap:
  // add f (Val n) = add (Val n) f: b's cell is the new Val n
  %tok4 = func.call @reset_val(%b) : (!llvm.ptr) -> !llvm.ptr
  %v4 = func.call @reuse_val(%tok4, %m3, %yes) : (!llvm.ptr, i64, i1) -> !llvm.ptr
  %r4 = func.call @add(%v4, %a) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  return %r4 : !llvm.ptr
^b_other:
  %badd6 = func.call @is(%b, %tAdd) : (!llvm.ptr, i8) -> i1
  cf.cond_br %badd6, ^b_add, ^a_add
^b_add:
  %ba6 = func.call @fld0(%b) : (!llvm.ptr) -> !llvm.ptr
  %ba6val = func.call @is(%ba6, %tVal) : (!llvm.ptr, i8) -> i1
  cf.cond_br %ba6val, ^case6, ^a_add
^case6:
  // add f (Add (Val n) g) = add (Val n) (add f g)
  %n6 = func.call @val_of(%ba6) : (!llvm.ptr) -> i64
  %g6 = func.call @fld1(%b) : (!llvm.ptr) -> !llvm.ptr
  %tb6 = func.call @reset_bin(%b) : (!llvm.ptr) -> !llvm.ptr
  %tv6 = func.call @reset_val(%ba6) : (!llvm.ptr) -> !llvm.ptr
  %v6 = func.call @reuse_val(%tv6, %n6, %yes) : (!llvm.ptr, i64, i1) -> !llvm.ptr
  func.call @free_token_24(%tb6) : (!llvm.ptr) -> ()
  %in6 = func.call @add(%a, %g6) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  %r6 = func.call @add(%v6, %in6) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  return %r6 : !llvm.ptr
^a_add:
  %aadd = func.call @is(%a, %tAdd) : (!llvm.ptr, i8) -> i1
  cf.cond_br %aadd, ^case7, ^mk
^case7:
  // add (Add f g) h = add f (add g h)
  %f7 = func.call @fld0(%a) : (!llvm.ptr) -> !llvm.ptr
  %g7 = func.call @fld1(%a) : (!llvm.ptr) -> !llvm.ptr
  %ta7 = func.call @reset_bin(%a) : (!llvm.ptr) -> !llvm.ptr
  func.call @free_token_24(%ta7) : (!llvm.ptr) -> ()
  %in7 = func.call @add(%g7, %b) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  %r7 = func.call @add(%f7, %in7) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  return %r7 : !llvm.ptr
^mk:
  // add f g = Add f g
  %r8 = func.call @new_bin(%hAdd, %a, %b) : (i64, !llvm.ptr, !llvm.ptr) -> !llvm.ptr
  return %r8 : !llvm.ptr
}

// mul a b, owning both.
func.func private @mul(%a: !llvm.ptr, %b: !llvm.ptr) -> !llvm.ptr {
  %tVal = arith.constant 0 : i8
  %tMul = arith.constant 3 : i8
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %yes = arith.constant true
  %no = arith.constant false
  %hMul = arith.constant 216739030602088449 : i64
  %aval = func.call @is(%a, %tVal) : (!llvm.ptr, i8) -> i1
  %bval = func.call @is(%b, %tVal) : (!llvm.ptr, i8) -> i1
  cf.cond_br %aval, ^a_val, ^a_other
^a_val:
  %n = func.call @val_of(%a) : (!llvm.ptr) -> i64
  cf.cond_br %bval, ^vv, ^a_val2
^vv:
  // mul (Val n) (Val m) = Val (n * m)
  %m = func.call @val_of(%b) : (!llvm.ptr) -> i64
  %tok = func.call @reset_val(%a) : (!llvm.ptr) -> !llvm.ptr
  func.call @__rc_dec(%b) : (!llvm.ptr) -> ()
  %p = arith.muli %n, %m : i64
  %r1 = func.call @reuse_val(%tok, %p, %no) : (!llvm.ptr, i64, i1) -> !llvm.ptr
  return %r1 : !llvm.ptr
^a_val2:
  %n0 = arith.cmpi eq, %n, %c0 : i64
  cf.cond_br %n0, ^zero, ^a_val3
^zero:
  // mul (Val 0) _ = Val 0, mul _ (Val 0) = Val 0: the static Val 0
  func.call @__rc_dec(%a) : (!llvm.ptr) -> ()
  func.call @__rc_dec(%b) : (!llvm.ptr) -> ()
  %z = llvm.mlir.addressof @val_0 : !llvm.ptr
  return %z : !llvm.ptr
^a_val3:
  %n1 = arith.cmpi eq, %n, %c1 : i64
  cf.cond_br %n1, ^one_l, ^a_val4
^one_l:
  // mul (Val 1) f = f
  func.call @__rc_dec(%a) : (!llvm.ptr) -> ()
  return %b : !llvm.ptr
^a_val4:
  %bmul = func.call @is(%b, %tMul) : (!llvm.ptr, i8) -> i1
  cf.cond_br %bmul, ^a_val5, ^mk
^a_val5:
  %ba = func.call @fld0(%b) : (!llvm.ptr) -> !llvm.ptr
  %baval = func.call @is(%ba, %tVal) : (!llvm.ptr, i8) -> i1
  cf.cond_br %baval, ^fold7, ^mk
^fold7:
  // mul (Val n) (Mul (Val m) f) = mul (Val (n * m)) f
  %m7 = func.call @val_of(%ba) : (!llvm.ptr) -> i64
  %f7 = func.call @fld1(%b) : (!llvm.ptr) -> !llvm.ptr
  func.call @__rc_inc(%f7) : (!llvm.ptr) -> ()
  func.call @__rc_dec(%b) : (!llvm.ptr) -> ()
  %tok7 = func.call @reset_val(%a) : (!llvm.ptr) -> !llvm.ptr
  %p7 = arith.muli %n, %m7 : i64
  %v7 = func.call @reuse_val(%tok7, %p7, %no) : (!llvm.ptr, i64, i1) -> !llvm.ptr
  %r7 = func.call @mul(%v7, %f7) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  return %r7 : !llvm.ptr
^a_other:
  cf.cond_br %bval, ^b_val, ^b_other
^b_val:
  %m3 = func.call @val_of(%b) : (!llvm.ptr) -> i64
  %m30 = arith.cmpi eq, %m3, %c0 : i64
  cf.cond_br %m30, ^zero, ^b_val2
^b_val2:
  %m31 = arith.cmpi eq, %m3, %c1 : i64
  cf.cond_br %m31, ^one_r, ^swap
^one_r:
  // mul f (Val 1) = f
  func.call @__rc_dec(%b) : (!llvm.ptr) -> ()
  return %a : !llvm.ptr
^swap:
  // mul f (Val n) = mul (Val n) f: b's cell is the new Val n
  %tok6 = func.call @reset_val(%b) : (!llvm.ptr) -> !llvm.ptr
  %v6 = func.call @reuse_val(%tok6, %m3, %yes) : (!llvm.ptr, i64, i1) -> !llvm.ptr
  %r6 = func.call @mul(%v6, %a) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  return %r6 : !llvm.ptr
^b_other:
  %bmul8 = func.call @is(%b, %tMul) : (!llvm.ptr, i8) -> i1
  cf.cond_br %bmul8, ^b_mul, ^a_mul
^b_mul:
  %ba8 = func.call @fld0(%b) : (!llvm.ptr) -> !llvm.ptr
  %ba8val = func.call @is(%ba8, %tVal) : (!llvm.ptr, i8) -> i1
  cf.cond_br %ba8val, ^case8, ^a_mul
^case8:
  // mul f (Mul (Val n) g) = mul (Val n) (mul f g)
  %n8 = func.call @val_of(%ba8) : (!llvm.ptr) -> i64
  %g8 = func.call @fld1(%b) : (!llvm.ptr) -> !llvm.ptr
  %tb8 = func.call @reset_bin(%b) : (!llvm.ptr) -> !llvm.ptr
  %tv8 = func.call @reset_val(%ba8) : (!llvm.ptr) -> !llvm.ptr
  %v8 = func.call @reuse_val(%tv8, %n8, %yes) : (!llvm.ptr, i64, i1) -> !llvm.ptr
  func.call @free_token_24(%tb8) : (!llvm.ptr) -> ()
  %in8 = func.call @mul(%a, %g8) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  %r8 = func.call @mul(%v8, %in8) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  return %r8 : !llvm.ptr
^a_mul:
  %amul = func.call @is(%a, %tMul) : (!llvm.ptr, i8) -> i1
  cf.cond_br %amul, ^case9, ^mk
^case9:
  // mul (Mul f g) h = mul f (mul g h)
  %f9 = func.call @fld0(%a) : (!llvm.ptr) -> !llvm.ptr
  %g9 = func.call @fld1(%a) : (!llvm.ptr) -> !llvm.ptr
  %ta9 = func.call @reset_bin(%a) : (!llvm.ptr) -> !llvm.ptr
  func.call @free_token_24(%ta9) : (!llvm.ptr) -> ()
  %in9 = func.call @mul(%g9, %b) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  %r9 = func.call @mul(%f9, %in9) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  return %r9 : !llvm.ptr
^mk:
  // mul f g = Mul f g
  %r10 = func.call @new_bin(%hMul, %a, %b) : (i64, !llvm.ptr, !llvm.ptr) -> !llvm.ptr
  return %r10 : !llvm.ptr
}

// powr a b, owning both.
func.func private @powr(%a: !llvm.ptr, %b: !llvm.ptr) -> !llvm.ptr {
  %tVal = arith.constant 0 : i8
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %no = arith.constant false
  %hPow = arith.constant 216740130113716225 : i64
  %aval = func.call @is(%a, %tVal) : (!llvm.ptr, i8) -> i1
  %bval = func.call @is(%b, %tVal) : (!llvm.ptr, i8) -> i1
  %both = arith.andi %aval, %bval : i1
  cf.cond_br %both, ^vv, ^not_vv
^vv:
  // powr (Val m) (Val n) = Val (pown m n)
  %m = func.call @val_of(%a) : (!llvm.ptr) -> i64
  %n = func.call @val_of(%b) : (!llvm.ptr) -> i64
  %tok = func.call @reset_val(%a) : (!llvm.ptr) -> !llvm.ptr
  func.call @__rc_dec(%b) : (!llvm.ptr) -> ()
  %p = func.call @pown(%m, %n) : (i64, i64) -> i64
  %r1 = func.call @reuse_val(%tok, %p, %no) : (!llvm.ptr, i64, i1) -> !llvm.ptr
  return %r1 : !llvm.ptr
^not_vv:
  cf.cond_br %bval, ^b_val, ^a_zero
^b_val:
  %nb = func.call @val_of(%b) : (!llvm.ptr) -> i64
  %nb0 = arith.cmpi eq, %nb, %c0 : i64
  cf.cond_br %nb0, ^exp0, ^b_val1
^exp0:
  // powr _ (Val 0) = Val 1
  func.call @__rc_dec(%a) : (!llvm.ptr) -> ()
  func.call @__rc_dec(%b) : (!llvm.ptr) -> ()
  %one = llvm.mlir.addressof @val_1 : !llvm.ptr
  return %one : !llvm.ptr
^b_val1:
  %nb1 = arith.cmpi eq, %nb, %c1 : i64
  cf.cond_br %nb1, ^exp1, ^a_zero
^exp1:
  // powr f (Val 1) = f
  func.call @__rc_dec(%b) : (!llvm.ptr) -> ()
  return %a : !llvm.ptr
^a_zero:
  %a0 = func.call @is_val(%a, %c0) : (!llvm.ptr, i64) -> i1
  cf.cond_br %a0, ^base0, ^mk
^base0:
  // powr (Val 0) _ = Val 0
  func.call @__rc_dec(%a) : (!llvm.ptr) -> ()
  func.call @__rc_dec(%b) : (!llvm.ptr) -> ()
  %z = llvm.mlir.addressof @val_0 : !llvm.ptr
  return %z : !llvm.ptr
^mk:
  %r = func.call @new_bin(%hPow, %a, %b) : (i64, !llvm.ptr, !llvm.ptr) -> !llvm.ptr
  return %r : !llvm.ptr
}

// ln a, owning a.
func.func private @ln(%a: !llvm.ptr) -> !llvm.ptr {
  %c1 = arith.constant 1 : i64
  %a1 = func.call @is_val(%a, %c1) : (!llvm.ptr, i64) -> i1
  cf.cond_br %a1, ^zero, ^mk
^zero:
  // ln (Val 1) = Val 0
  func.call @__rc_dec(%a) : (!llvm.ptr) -> ()
  %z = llvm.mlir.addressof @val_0 : !llvm.ptr
  return %z : !llvm.ptr
^mk:
  %r = func.call @new_ln(%a) : (!llvm.ptr) -> !llvm.ptr
  return %r : !llvm.ptr
}

// d x e, borrowing x and e.
func.func private @d(%x: !llvm.ptr, %e: !llvm.ptr) -> !llvm.ptr {
  %t = func.call @tag(%e) : (!llvm.ptr) -> i8
  %m1 = llvm.mlir.addressof @val_m1 : !llvm.ptr
  %v0 = llvm.mlir.addressof @val_0 : !llvm.ptr
  %v1 = llvm.mlir.addressof @val_1 : !llvm.ptr
  %i = arith.extui %t : i8 to i32
  cf.switch %i : i32, [
    default: ^ln,
    0: ^val,
    1: ^var,
    2: ^add,
    3: ^mul,
    4: ^pow
  ]
^val:
  return %v0 : !llvm.ptr
^var:
  // x == y: the same string is equal without a call.
  %y = func.call @fld0(%e) : (!llvm.ptr) -> !llvm.ptr
  %ident = llvm.icmp "eq" %x, %y : !llvm.ptr
  cf.cond_br %ident, ^var_eq, ^var_cmp
^var_eq:
  return %v1 : !llvm.ptr
^var_cmp:
  %same = llvm.call @idr_str_eq(%x, %y) : (!llvm.ptr, !llvm.ptr) -> i32
  %zero32 = arith.constant 0 : i32
  %eq = arith.cmpi ne, %same, %zero32 : i32
  %r = arith.select %eq, %v1, %v0 : !llvm.ptr
  return %r : !llvm.ptr
^add:
  // add (d x f) (d x g)
  %af = func.call @fld0(%e) : (!llvm.ptr) -> !llvm.ptr
  %ag = func.call @fld1(%e) : (!llvm.ptr) -> !llvm.ptr
  %adf = func.call @d(%x, %af) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  %adg = func.call @d(%x, %ag) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  %ar = func.call @add(%adf, %adg) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  return %ar : !llvm.ptr
^mul:
  // add (mul f (d x g)) (mul g (d x f))
  %mf = func.call @fld0(%e) : (!llvm.ptr) -> !llvm.ptr
  %mg = func.call @fld1(%e) : (!llvm.ptr) -> !llvm.ptr
  func.call @__rc_inc(%mf) : (!llvm.ptr) -> ()
  %mdg = func.call @d(%x, %mg) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  %mm1 = func.call @mul(%mf, %mdg) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  func.call @__rc_inc(%mg) : (!llvm.ptr) -> ()
  %mdf = func.call @d(%x, %mf) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  %mm2 = func.call @mul(%mg, %mdf) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  %mr = func.call @add(%mm1, %mm2) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  return %mr : !llvm.ptr
^pow:
  // mul (powr f g) (add (mul (mul g (d x f)) (powr f (Val (-1))))
  //                     (mul (ln f) (d x g)))
  %pf = func.call @fld0(%e) : (!llvm.ptr) -> !llvm.ptr
  %pg = func.call @fld1(%e) : (!llvm.ptr) -> !llvm.ptr
  func.call @__rc_inc(%pf) : (!llvm.ptr) -> ()
  func.call @__rc_inc(%pg) : (!llvm.ptr) -> ()
  %p1 = func.call @powr(%pf, %pg) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  func.call @__rc_inc(%pg) : (!llvm.ptr) -> ()
  %pdf = func.call @d(%x, %pf) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  %pm1 = func.call @mul(%pg, %pdf) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  func.call @__rc_inc(%pf) : (!llvm.ptr) -> ()
  %pp2 = func.call @powr(%pf, %m1) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  %pm2 = func.call @mul(%pm1, %pp2) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  func.call @__rc_inc(%pf) : (!llvm.ptr) -> ()
  %pl = func.call @ln(%pf) : (!llvm.ptr) -> !llvm.ptr
  %pdg = func.call @d(%x, %pg) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  %pm3 = func.call @mul(%pl, %pdg) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  %pa = func.call @add(%pm2, %pm3) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  %pr = func.call @mul(%p1, %pa) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  return %pr : !llvm.ptr
^ln:
  // mul (d x f) (powr f (Val (-1)))
  %lf = func.call @fld0(%e) : (!llvm.ptr) -> !llvm.ptr
  %ldf = func.call @d(%x, %lf) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  func.call @__rc_inc(%lf) : (!llvm.ptr) -> ()
  %lp = func.call @powr(%lf, %m1) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  %lr = func.call @mul(%ldf, %lp) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  return %lr : !llvm.ptr
}

// count e, borrowing e.
func.func private @count(%e: !llvm.ptr) -> i64 {
  %t = func.call @tag(%e) : (!llvm.ptr) -> i8
  %one = arith.constant 1 : i64
  %i = arith.extui %t : i8 to i32
  cf.switch %i : i32, [
    default: ^two,
    0: ^leaf,
    1: ^leaf,
    5: ^ln
  ]
^leaf:
  return %one : i64
^ln:
  %f = func.call @fld0(%e) : (!llvm.ptr) -> !llvm.ptr
  %c = func.call @count(%f) : (!llvm.ptr) -> i64
  return %c : i64
^two:
  %a = func.call @fld0(%e) : (!llvm.ptr) -> !llvm.ptr
  %b = func.call @fld1(%e) : (!llvm.ptr) -> !llvm.ptr
  %ca = func.call @count(%a) : (!llvm.ptr) -> i64
  %cb = func.call @count(%b) : (!llvm.ptr) -> i64
  %s = arith.addi %ca, %cb : i64
  return %s : i64
}

// main: nestAux n n (powr x x), with deriv inlined.
func.func @idr_main() -> i32 {
  %s = llvm.call @idr_read_int() : () -> i64
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %x = llvm.mlir.addressof @str_x : !llvm.ptr
  %f0 = llvm.mlir.addressof @pow_x_x : !llvm.ptr
  cf.br ^loop(%s, %f0 : i64, !llvm.ptr)
^loop(%n: i64, %f: !llvm.ptr):
  %done = arith.cmpi eq, %n, %c0 : i64
  cf.cond_br %done, ^end, ^step
^step:
  // deriv (s - n) f
  %f1 = func.call @d(%x, %f) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  %i = arith.subi %s, %n : i64
  %i1 = arith.addi %i, %c1 : i64
  %cnt = func.call @count(%f1) : (!llvm.ptr) -> i64
  llvm.call @idr_put_int(%i1) : (i64) -> ()
  %lbl = llvm.mlir.addressof @s_count : !llvm.ptr
  %len = arith.constant 8 : i64
  llvm.call @idr_put_str(%lbl, %len) : (!llvm.ptr, i64) -> ()
  llvm.call @idr_put_int(%cnt) : (i64) -> ()
  %nl = arith.constant 10 : i32
  llvm.call @idr_put_char(%nl) : (i32) -> ()
  func.call @__rc_dec(%f) : (!llvm.ptr) -> ()
  %n1 = arith.subi %n, %c1 : i64
  cf.br ^loop(%n1, %f1 : i64, !llvm.ptr)
^end:
  func.call @__rc_dec(%f) : (!llvm.ptr) -> ()
  %ok = arith.constant 0 : i32
  return %ok : i32
}
