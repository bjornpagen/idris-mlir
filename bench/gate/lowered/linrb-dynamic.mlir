// Reset and reuse as Lean's passes do them (docs/plan.md 4.2), for
// linrb.mlir: the best effort, which cannot rely on quantities.
// - idr.reset.dyn tests the count. Count 1: the cell is the token and its
//   fields move. Otherwise its fields are duplicated, the cell is dropped
//   and the token is null.
// - idr.reuse tests the token: null allocates, otherwise it stores the
//   fields that change.
// - a token nothing reuses is freed unless null.

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

