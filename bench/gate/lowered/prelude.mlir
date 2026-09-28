// What the lowering puts in every module that has a heap: the runtime
// prototype's entries (foreign/idr/bench/gate/runtime.h) and the fast paths of
// the count operations, which LLVM inlines. The programs here are appended to
// this file before lowering (lower.sh), as idr-lower copies
// Lower/Runtime.mlir.inc into a module today.
//
// A cell is an 8-byte header {i32 count, i8 kind, i8 tag, i8 pointer
// fields, i8 size in words}, then its pointer fields, then its scalars. A
// pointer field holds a cell or an immediate (a nullary constructor,
// tag << 1 | 1). A fresh cell's header is one i64 store:
//   1 | tag << 40 | nptr << 48 | nwords << 56.

llvm.func @idr_alloc_16() -> !llvm.ptr
llvm.func @idr_alloc_24() -> !llvm.ptr
llvm.func @idr_alloc_32() -> !llvm.ptr
llvm.func @idr_alloc_40() -> !llvm.ptr
llvm.func @idr_alloc_48() -> !llvm.ptr
llvm.func @idr_free_24(!llvm.ptr)
llvm.func @idr_free_32(!llvm.ptr)
llvm.func @idr_free_40(!llvm.ptr)
llvm.func @idr_inc_cold(!llvm.ptr)
llvm.func @idr_dec_cold(!llvm.ptr)
llvm.func @idr_free_cell(!llvm.ptr)
llvm.func @idr_send(!llvm.ptr)
llvm.func @idr_str_eq(!llvm.ptr, !llvm.ptr) -> i32
llvm.func @idr_read_int() -> i64
llvm.func @idr_put_int(i64)
llvm.func @idr_put_str(!llvm.ptr, i64)
llvm.func @idr_put_char(i32)

// True when v is a cell, false when it is an immediate.
func.func private @__is_cell(%v: !llvm.ptr) -> i1 {
  %i = llvm.ptrtoint %v : !llvm.ptr to i64
  %one = arith.constant 1 : i64
  %bit = arith.andi %i, %one : i64
  %zero = arith.constant 0 : i64
  %cell = arith.cmpi eq, %bit, %zero : i64
  return %cell : i1
}

// idr.dup on a cell: a plain increment while 0 < count < INT32_MAX. A
// persistent cell (count 0) is left alone without a call, as in Lean; the
// runtime handles shared and stuck counts.
func.func private @__rc_inc(%c: !llvm.ptr) {
  %rc = llvm.load %c : !llvm.ptr -> i32
  %one = arith.constant 1 : i32
  %lim = arith.constant 2147483646 : i32
  %t = arith.subi %rc, %one : i32
  %fast = arith.cmpi ult, %t, %lim : i32
  cf.cond_br %fast, ^inc, ^slow
^inc:
  %n = arith.addi %rc, %one : i32
  llvm.store %n, %c : i32, !llvm.ptr
  return
^slow:
  %zero = arith.constant 0 : i32
  %persistent = arith.cmpi eq, %rc, %zero : i32
  cf.cond_br %persistent, ^done, ^cold
^cold:
  llvm.call @idr_inc_cold(%c) : (!llvm.ptr) -> ()
  cf.br ^done
^done:
  return
}

// idr.drop on a cell: a plain decrement while 1 < count < INT32_MAX. A
// persistent cell is left alone; the runtime frees at 1 and handles shared
// and stuck counts.
func.func private @__rc_dec(%c: !llvm.ptr) {
  %rc = llvm.load %c : !llvm.ptr -> i32
  %two = arith.constant 2 : i32
  %lim = arith.constant 2147483645 : i32
  %t = arith.subi %rc, %two : i32
  %fast = arith.cmpi ult, %t, %lim : i32
  cf.cond_br %fast, ^dec, ^slow
^dec:
  %one = arith.constant 1 : i32
  %n = arith.subi %rc, %one : i32
  llvm.store %n, %c : i32, !llvm.ptr
  return
^slow:
  %zero = arith.constant 0 : i32
  %persistent = arith.cmpi eq, %rc, %zero : i32
  cf.cond_br %persistent, ^done, ^cold
^cold:
  llvm.call @idr_dec_cold(%c) : (!llvm.ptr) -> ()
  cf.br ^done
^done:
  return
}

// idr.dup and idr.drop on a value of a type with nullary constructors.
func.func private @__rc_dup(%v: !llvm.ptr) {
  %cell = func.call @__is_cell(%v) : (!llvm.ptr) -> i1
  cf.cond_br %cell, ^inc, ^done
^inc:
  func.call @__rc_inc(%v) : (!llvm.ptr) -> ()
  cf.br ^done
^done:
  return
}

func.func private @__rc_drop(%v: !llvm.ptr) {
  %cell = func.call @__is_cell(%v) : (!llvm.ptr) -> i1
  cf.cond_br %cell, ^dec, ^done
^dec:
  func.call @__rc_dec(%v) : (!llvm.ptr) -> ()
  cf.br ^done
^done:
  return
}

// The test of idr.reset.dyn (Lean's reset): is this the only reference?
func.func private @__rc_unique(%c: !llvm.ptr) -> i1 {
  %rc = llvm.load %c : !llvm.ptr -> i32
  %one = arith.constant 1 : i32
  %u = arith.cmpi eq, %rc, %one : i32
  return %u : i1
}
