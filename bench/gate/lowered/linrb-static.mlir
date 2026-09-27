// Reset and reuse under MEM-LIN-1 (docs/plan.md 4.2), for linrb.mlir: every
// cell they are given is unique by proof, so
// - idr.reset is the cell itself: no count test, and its fields move;
// - idr.reuse stores the fields that change: no test for a null token, and
//   never an allocation;
// - a token nothing reuses is freed.
// Nothing here duplicates a value.

func.func private @reset_node(%x: !llvm.ptr) -> !llvm.ptr {
  return %x : !llvm.ptr
}

// idr.reuse of a token as Node color l key val r. The token's cell already
// holds the fields not in `changed` (1 color, 2 l, 4 key, 8 val, 16 r, a
// constant at every call).
func.func private @reuse(%tok: !llvm.ptr, %color: i8, %l: !llvm.ptr, %key: i64, %val: i8, %r: !llvm.ptr, %changed: i32) -> !llvm.ptr {
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

func.func private @free_token(%tok: !llvm.ptr) {
  llvm.call @idr_free_40(%tok) : (!llvm.ptr) -> ()
  return
}
