// A pipeline passing trees between cores (experiment 3), after
// bintree.mlir. Cores pair up, 0 with 1, 2 with 3: the first of
// a pair builds `count` trees make' i depth and sends each on a channel;
// the second checks each tree and drops it. main prints the sum of the
// checks.
//
// The crossing: every tree is sent with idr_chan_send, whose move-or-mark
// walk finds every count at 1 and moves the tree with no atomic operation
// and no store. The consumer's drop frees cells that the producer's heap
// owns: remote frees, batched by snmalloc. The stats build must show
// atomic-rc=0, marked=0 and moved = the number of cells sent.
//
// The runtime's variants: `flush` sends
// the batched remote frees at the end of each consumer turn; `home` sends
// each dead root back to its producer, which drops it locally.

llvm.func @idr_cores() -> i64
llvm.func @idr_run_on_cores(i64, !llvm.ptr, !llvm.ptr)
llvm.func @idr_chan_new() -> !llvm.ptr
llvm.func @idr_home_new() -> !llvm.ptr
llvm.func @idr_chan_send(!llvm.ptr, !llvm.ptr)
llvm.func @idr_chan_recv(!llvm.ptr) -> !llvm.ptr
llvm.func @idr_drop_foreign(!llvm.ptr, !llvm.ptr)
llvm.func @idr_producer_turn(!llvm.ptr)
llvm.func @idr_producer_finish(!llvm.ptr, i64)
llvm.func @idr_turn_end()

func.func private @produce(%count: i64, %depth: i64, %chan: !llvm.ptr, %home: !llvm.ptr) {
  %c1 = arith.constant 1 : i64
  cf.br ^loop(%c1 : i64)
^loop(%i: i64):
  %done = arith.cmpi sgt, %i, %count : i64
  cf.cond_br %done, ^exit, ^body
^body:
  %t = func.call @make(%i, %depth) : (i64, i64) -> !llvm.ptr
  llvm.call @idr_producer_turn(%home) : (!llvm.ptr) -> ()
  llvm.call @idr_chan_send(%chan, %t) : (!llvm.ptr, !llvm.ptr) -> ()
  %i1 = arith.addi %i, %c1 : i64
  cf.br ^loop(%i1 : i64)
^exit:
  llvm.call @idr_producer_finish(%home, %count) : (!llvm.ptr, i64) -> ()
  llvm.call @idr_turn_end() : () -> ()
  return
}

func.func private @consume(%count: i64, %chan: !llvm.ptr, %home: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  cf.br ^loop(%c0, %c0 : i64, i64)
^loop(%i: i64, %s: i64):
  %done = arith.cmpi sge, %i, %count : i64
  cf.cond_br %done, ^exit, ^body
^body:
  %t = llvm.call @idr_chan_recv(%chan) : (!llvm.ptr) -> !llvm.ptr
  %c = func.call @check(%t) : (!llvm.ptr) -> i64
  llvm.call @idr_drop_foreign(%home, %t) : (!llvm.ptr, !llvm.ptr) -> ()
  llvm.call @idr_turn_end() : () -> ()
  %s1 = arith.addi %s, %c : i64
  %i1 = arith.addi %i, %c1 : i64
  cf.br ^loop(%i1, %s1 : i64, i64)
^exit:
  return %s : i64
}

// The body run on every core; env holds count, depth, pairs and the
// arrays of channels, homes and results.
llvm.func @body(%env: !llvm.ptr, %core: i64) {
  %p0 = llvm.getelementptr %env[0] : (!llvm.ptr) -> !llvm.ptr, i64
  %count = llvm.load %p0 : !llvm.ptr -> i64
  %p1 = llvm.getelementptr %env[1] : (!llvm.ptr) -> !llvm.ptr, i64
  %depth = llvm.load %p1 : !llvm.ptr -> i64
  %p3 = llvm.getelementptr %env[3] : (!llvm.ptr) -> !llvm.ptr, i64
  %chans = llvm.load %p3 : !llvm.ptr -> !llvm.ptr
  %p4 = llvm.getelementptr %env[4] : (!llvm.ptr) -> !llvm.ptr, i64
  %homes = llvm.load %p4 : !llvm.ptr -> !llvm.ptr
  %p5 = llvm.getelementptr %env[5] : (!llvm.ptr) -> !llvm.ptr, i64
  %res = llvm.load %p5 : !llvm.ptr -> !llvm.ptr
  %two = llvm.mlir.constant(2 : i64) : i64
  %zero = llvm.mlir.constant(0 : i64) : i64
  %pair = llvm.sdiv %core, %two : i64
  %role = llvm.srem %core, %two : i64
  %pc = llvm.getelementptr %chans[%pair] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.ptr
  %chan = llvm.load %pc : !llvm.ptr -> !llvm.ptr
  %ph = llvm.getelementptr %homes[%pair] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.ptr
  %home = llvm.load %ph : !llvm.ptr -> !llvm.ptr
  %producer = llvm.icmp "eq" %role, %zero : i64
  llvm.cond_br %producer, ^produce, ^consume
^produce:
  func.call @produce(%count, %depth, %chan, %home) : (i64, i64, !llvm.ptr, !llvm.ptr) -> ()
  llvm.return
^consume:
  %s = func.call @consume(%count, %chan, %home) : (i64, !llvm.ptr, !llvm.ptr) -> i64
  %slot = llvm.getelementptr %res[%pair] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %s, %slot : i64, !llvm.ptr
  llvm.return
}

func.func @idr_main() -> i32 {
  %count = llvm.call @idr_read_int() : () -> i64
  %depth = llvm.call @idr_read_int() : () -> i64
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %cores = llvm.call @idr_cores() : () -> i64
  %half = arith.divsi %cores, %c2 : i64
  %few = arith.cmpi slt, %half, %c1 : i64
  %pairs = arith.select %few, %c1, %half : i64
  %six = arith.constant 6 : i64
  %env = llvm.alloca %six x i64 : (i64) -> !llvm.ptr
  %chans = llvm.alloca %pairs x !llvm.ptr : (i64) -> !llvm.ptr
  %homes = llvm.alloca %pairs x !llvm.ptr : (i64) -> !llvm.ptr
  %res = llvm.alloca %pairs x i64 : (i64) -> !llvm.ptr
  cf.br ^mk(%c0 : i64)
^mk(%p: i64):
  %made = arith.cmpi sge, %p, %pairs : i64
  cf.cond_br %made, ^run, ^mk1
^mk1:
  %ch = llvm.call @idr_chan_new() : () -> !llvm.ptr
  %pc = llvm.getelementptr %chans[%p] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.ptr
  llvm.store %ch, %pc : !llvm.ptr, !llvm.ptr
  %hm = llvm.call @idr_home_new() : () -> !llvm.ptr
  %ph = llvm.getelementptr %homes[%p] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.ptr
  llvm.store %hm, %ph : !llvm.ptr, !llvm.ptr
  %p1 = arith.addi %p, %c1 : i64
  cf.br ^mk(%p1 : i64)
^run:
  %e0 = llvm.getelementptr %env[0] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %count, %e0 : i64, !llvm.ptr
  %e1 = llvm.getelementptr %env[1] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %depth, %e1 : i64, !llvm.ptr
  %e2 = llvm.getelementptr %env[2] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %pairs, %e2 : i64, !llvm.ptr
  %e3 = llvm.getelementptr %env[3] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %chans, %e3 : !llvm.ptr, !llvm.ptr
  %e4 = llvm.getelementptr %env[4] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %homes, %e4 : !llvm.ptr, !llvm.ptr
  %e5 = llvm.getelementptr %env[5] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %res, %e5 : !llvm.ptr, !llvm.ptr
  %threads = arith.muli %pairs, %c2 : i64
  %body = llvm.mlir.addressof @body : !llvm.ptr
  llvm.call @idr_run_on_cores(%threads, %body, %env) : (i64, !llvm.ptr, !llvm.ptr) -> ()
  cf.br ^sum(%c0, %c0 : i64, i64)
^sum(%k: i64, %acc: i64):
  %summed = arith.cmpi sge, %k, %pairs : i64
  cf.cond_br %summed, ^end, ^add
^add:
  %slot = llvm.getelementptr %res[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %slot : !llvm.ptr -> i64
  %acc1 = arith.addi %acc, %v : i64
  %k1 = arith.addi %k, %c1 : i64
  cf.br ^sum(%k1, %acc1 : i64, i64)
^end:
  llvm.call @idr_put_int(%acc) : (i64) -> ()
  %nl = arith.constant 10 : i32
  llvm.call @idr_put_char(%nl) : (i32) -> ()
  %ok = arith.constant 0 : i32
  return %ok : i32
}
