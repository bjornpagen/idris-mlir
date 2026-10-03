// idr.lower:tailCalls: idr-tail-calls: every call the program makes in
// tail position on a cycle of calls is a guaranteed tail call, so that a
// recursion through such calls runs in constant stack. Scheme mandates proper tail calls, so Idris's Chez
// backend has them, and an IO loop or a mutual recursion in tail position
// must not grow the stack here either; idr-tail-loops makes only a
// function's calls of itself loops.
//
// The pass runs last, on the LLVM dialect, where the control flow is final.
//
//   - Which calls. A call in tail position matters where its callee is on
//     its caller's cycle of calls: a recursion keeps a frame per round
//     unless each of its calls is a tail call. A call from one cycle to
//     another adds its caller's frame once at most, since the callee never
//     calls back, so it is left an ordinary call, which costs nothing. The
//     cycles are those of direct calls: no call through a pointer is a tail
//     call, so a cycle through one keeps that call's frame anyway.
//   - The calling convention. The caller and the callee of such a call take
//     LLVM's `tailcc`, and so do all their calls: fastcc's registers, with
//     the guarantee that a call in tail position is a tail call, whose stack
//     arguments the callee pops. The popping costs every call of such a
//     function (on x86-64 a slot that keeps the stack aligned, which the
//     callee pops even when there is no stack argument and the caller takes
//     back), so the other functions keep C's convention, which LLVM makes
//     fastcc. Only a function that only the module's own calls reach
//     (private, its address never taken) takes `tailcc`: @main,
//     @__idr_main, which the runtime's entry calls through a pointer, and
//     in compile-time evaluation the evaluator's entries and the code of
//     closures, which an apply calls through a pointer, keep C's. Calls of
//     the runtime's C functions stay calls of C: the runtime never calls
//     back, so no recursion runs through one.
//   - Tail position. A call of a `tailcc` function from one is in tail
//     position when the path from it decides, by what it sees alone, to
//     return the call's result unchanged: through extractvalue and
//     insertvalue that take the result apart and put it back together,
//     through branches whose block arguments carry it, past conditions the
//     path decides (the exit flag a loop's tail passes as a constant) and
//     past ops that only compute. The call becomes `musttail`, with the
//     return moved right after it: LLVM then emits a tail call or fails to
//     compile, never silently a call.
//   - Results the target returns in memory. A result that does not fit the
//     return registers would come back through a hidden pointer into the
//     caller's frame, and LLVM makes no tail call of such a call. What fits
//     is the target's own answer: LLVM's lowering of `tailcc` is asked, for
//     the module's #llvm.target. Each function on a tail call whose result
//     does not fit takes a pointer to write its result to instead, first,
//     and returns nothing: a tail call passes on the pointer its caller got,
//     any other call a slot of its own frame, which it reads back.
//   - A frame's cells. A call that may reach its caller's frame through what
//     it takes (a cell idr-stack put there, or memory that holds one) stays
//     a call, since the frame has to outlive the callee. idr-stack puts on
//     the stack no cell that a call in tail position on its caller's cycle
//     takes, so such a call is never a recursion's: its callee, off the
//     cycle, never calls back round, and adds its frame once.

export module idr.lower:tailCalls;

import idr.mlir;
import idr.graph;

import :frame;
import :passThroughMemory;
import :returnRegisters;
import :tailPosition;

using namespace mlir;

namespace idr::lower {

namespace {

using LLVM::cconv::CConv;
using LLVM::tailcallkind::TailCallKind;

// The cycle of direct calls each function with a body is on: the index of
// its strongly connected component, which two functions share when each
// calls the other through any number of calls.
DenseMap<Operation *, unsigned> cyclesOf(ModuleOp module, SymbolTable &symbols) {
  SmallVector<Operation *> fns;
  for (auto fn : module.getOps<LLVM::LLVMFuncOp>())
    if (!fn.isExternal())
      fns.push_back(fn);
  auto callees = [&](Operation *fn) {
    SmallVector<Operation *> out;
    fn->walk([&](LLVM::CallOp call) {
      if (FlatSymbolRefAttr name = call.getCalleeAttr())
        if (Operation *callee = symbols.lookup(name.getAttr()))
          out.push_back(callee);
    });
    return out;
  };
  DenseMap<Operation *, unsigned> cycleOf;
  unsigned index = 0;
  for (const SmallVector<Operation *> &members :
       idr::graph::stronglyConnected<Operation *>(fns, callees)) {
    for (Operation *fn : members)
      cycleOf[fn] = index;
    ++index;
  }
  return cycleOf;
}

} // namespace

// What idr-tail-calls did, for its statistics: the calls in tail position
// that stay calls since they may reach their caller's frame, the functions
// whose result goes through memory, and the tail calls made.
export struct TailCallCounts {
  uint64_t frameBound = 0;
  uint64_t inMemory = 0;
  uint64_t tailCalls = 0;
};

// idr-tail-calls on `module`, counting into `counts` what it does. Fails
// when there is no machine for the module's target to ask what fits the
// return registers.
export LogicalResult makeTailCalls(ModuleOp module, TailCallCounts &counts) {
  MLIRContext *ctx = module.getContext();
  IRRewriter rewriter(ctx);

  // The functions only the module's calls reach.
  DenseSet<Operation *> internal;
  for (auto fn : module.getOps<LLVM::LLVMFuncOp>()) {
    if (fn.isExternal() || !fn.isPrivate() || fn.isVarArg())
      continue;
    std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(fn, module);
    if (!uses || llvm::any_of(*uses, [&](const SymbolTable::SymbolUse &use) {
          auto call = dyn_cast<LLVM::CallOp>(use.getUser());
          return !call || call.getCalleeAttr() != use.getSymbolRef();
        }))
      continue;
    internal.insert(fn);
  }
  SymbolTable symbols(module);
  auto calleeIn = [&](LLVM::CallOp call,
                      const DenseSet<Operation *> &among) -> LLVM::LLVMFuncOp {
    FlatSymbolRefAttr name = call.getCalleeAttr();
    auto callee = name ? symbols.lookup<LLVM::LLVMFuncOp>(name.getAttr()) : LLVM::LLVMFuncOp();
    return callee && among.contains(callee) ? callee : LLVM::LLVMFuncOp();
  };

  // The calls in tail position among them that leave the caller's frame
  // alone.
  SmallVector<LLVM::CallOp> candidates;
  for (auto fn : module.getOps<LLVM::LLVMFuncOp>()) {
    if (!internal.contains(fn))
      continue;
    std::optional<Frame> frame;
    fn.walk([&](LLVM::CallOp call) {
      if (!calleeIn(call, internal) || !inTailPosition(call, fn))
        return;
      if (!frame)
        frame.emplace(fn);
      if (frame->reachedBy(call)) {
        ++counts.frameBound;
        return;
      }
      candidates.push_back(call);
    });
  }

  // The callers and callees of those on a cycle take tailcc, and so do
  // their calls; each call in tail position between two of them becomes
  // a tail call.
  DenseMap<Operation *, unsigned> cycleOf = cyclesOf(module, symbols);
  DenseSet<Operation *> tail;
  for (LLVM::CallOp call : candidates) {
    Operation *caller = call->getParentOfType<LLVM::LLVMFuncOp>();
    Operation *callee = calleeIn(call, internal);
    if (cycleOf.lookup(caller) == cycleOf.lookup(callee)) {
      tail.insert(caller);
      tail.insert(callee);
    }
  }
  for (Operation *op : tail)
    cast<LLVM::LLVMFuncOp>(op).setCConv(CConv::Tail);
  module.walk([&](LLVM::CallOp call) {
    if (calleeIn(call, tail))
      call.setCConv(CConv::Tail);
  });
  auto calleeOf = [&](LLVM::CallOp call) { return calleeIn(call, tail); };
  SmallVector<LLVM::CallOp> tails;
  for (LLVM::CallOp call : candidates)
    if (tail.contains(call->getParentOfType<LLVM::LLVMFuncOp>()) && calleeOf(call))
      tails.push_back(call);
  // The return right after each. What only the rest of a call's block led
  // to is unreachable then, and goes, with any call in tail position there.
  SetVector<Region *> split;
  for (LLVM::CallOp call : tails) {
    Block *block = call->getBlock();
    rewriter.splitBlock(block, std::next(call->getIterator()));
    rewriter.setInsertionPointToEnd(block);
    LLVM::ReturnOp::create(rewriter, call.getLoc(), call.getResults());
    split.insert(block->getParent());
  }
  DenseSet<Block *> reachable;
  for (Region *region : split) {
    SmallVector<Block *> work{&region->front()};
    while (!work.empty())
      if (Block *block = work.pop_back_val(); reachable.insert(block).second)
        llvm::append_range(work, block->getSuccessors());
  }
  llvm::erase_if(tails, [&](LLVM::CallOp call) {
    return split.contains(call->getParentRegion()) && !reachable.contains(call->getBlock());
  });
  for (Region *region : split)
    (void)eraseUnreachableBlocks(rewriter, *region);

  // The results that do not fit the return registers go through memory,
  // in every function on a tail call.
  SetVector<Operation *> onTails;
  for (LLVM::CallOp call : tails) {
    onTails.insert(call->getParentOfType<LLVM::LLVMFuncOp>());
    onTails.insert(calleeOf(call));
  }
  ReturnRegisters registers(module);
  SetVector<Operation *> inMemory;
  for (Operation *op : onTails) {
    auto fn = cast<LLVM::LLVMFuncOp>(op);
    std::optional<bool> fits = registers.fit(fn.getFunctionType().getReturnType());
    if (!fits)
      return failure();
    if (!*fits)
      inMemory.insert(fn);
  }
  DenseSet<Operation *> tailCalls;
  for (LLVM::CallOp call : tails)
    tailCalls.insert(call);
  passThroughMemory(module, inMemory, tailCalls, rewriter);
  counts.inMemory += inMemory.size();

  module.walk([&](LLVM::CallOp call) {
    if (tailCalls.contains(call)) {
      call.setTailCallKind(TailCallKind::MustTail);
      ++counts.tailCalls;
    }
  });
  return success();
}

} // namespace idr::lower
