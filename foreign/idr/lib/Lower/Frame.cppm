// idr.lower:frame: what of a function may point into its frame, which a
// call that may reach it keeps from being a tail call.

export module idr.lower:frame;

import idr.mlir;

using namespace mlir;

namespace idr::lower {

// What of a function may point into its frame: its slots (llvm.alloca, the
// cells idr-stack put there), what is computed from them, and what is read
// through them, since a slot may hold a pointer to another. A pointer into
// the frame may also have left it through memory, written somewhere that is
// not the frame: then any pointer a call takes may lead back to the frame.
// What a call does with a pointer it takes is idr-stack's to know: it puts on
// the stack only a cell that no callee keeps.
struct Frame {
  DenseSet<Value> bound;
  bool leaked = false;

  // Whether a value of `type` may hold a pointer: a pointer, or an
  // aggregate of anything that may (an array's view).
  static bool mayPoint(Type type) {
    if (isa<LLVM::LLVMPointerType>(type))
      return true;
    if (auto structure = dyn_cast<LLVM::LLVMStructType>(type))
      return llvm::any_of(structure.getBody(), mayPoint);
    if (auto array = dyn_cast<LLVM::LLVMArrayType>(type))
      return mayPoint(array.getElementType());
    return false;
  }

  explicit Frame(LLVM::LLVMFuncOp fn) {
    SmallVector<Value> work;
    auto add = [&](Value value) {
      if (value && bound.insert(value).second)
        work.push_back(value);
    };
    fn.walk([&](LLVM::AllocaOp slot) { add(slot.getResult()); });
    while (!work.empty()) {
      Value value = work.pop_back_val();
      for (OpOperand &use : value.getUses()) {
        Operation *user = use.getOwner();
        if (auto branch = dyn_cast<BranchOpInterface>(user)) {
          if (std::optional<BlockArgument> arg =
                  branch.getSuccessorBlockArgument(use.getOperandNumber()))
            add(*arg);
          continue;
        }
        if (auto load = dyn_cast<LLVM::LoadOp>(user)) {
          if (load.getAddr() == value && mayPoint(load.getType()))
            add(load.getResult());
          continue;
        }
        if (isa<LLVM::GEPOp, LLVM::AddrSpaceCastOp, LLVM::SelectOp, LLVM::InsertValueOp,
                LLVM::ExtractValueOp, LLVM::IntToPtrOp, LLVM::PtrToIntOp>(user))
          for (Value result : user->getResults())
            add(result);
      }
    }
    fn.walk([&](LLVM::StoreOp store) {
      leaked |= bound.contains(store.getValue()) && !bound.contains(store.getAddr());
    });
  }

  // Whether `call` may reach the frame through what it takes.
  bool reachedBy(LLVM::CallOp call) const {
    return leaked || llvm::any_of(call.getArgOperands(),
                                  [&](Value arg) { return bound.contains(arg); });
  }
};

} // namespace idr::lower
