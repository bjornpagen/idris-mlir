// idr.defunctionalize:byname: which labels of the memo sums are `by_name`.
// A trusted library's effect happens where its value is demanded, so a cell
// whose label reaches an effect the program's outside can observe runs it at
// every force instead of keeping its value. A static constant's label keeps
// its value all the same: a top-level constant names one value of the
// program, evaluated once, so an effect in it is observed that once.
export module idr.defunctionalize:byname;

import idr.mlir;
import idr.dialect;

import :closures;

using namespace mlir;

namespace idr::defunctionalize {

// Whether `op` is an effect the program's outside can observe: output,
// input, a file, a clock. An array or a buffer is memory that only the
// program reads back, through its own ops; a forged world orders a chain
// without being an effect; an error's text is the C library's, the same at
// every call.
bool observable(Operation *op) {
  return op->hasTrait<idr::PerformsIO>() &&
         !isa<idr::ArrayNewOp, idr::ArrayGetOp, idr::ArraySetOp, idr::ArrayGenerateOp,
              idr::ArrayFoldOp, idr::BufferLoadOp, idr::BufferStoreOp, idr::BufferCopyOp,
              idr::BufferSetStringOp, idr::BufferGetStringOp, idr::WorldNewOp,
              idr::StrerrorOp>(op);
}

// Whether `label` reaches an observable effect through direct calls. A
// function without a body may do anything.
bool reaches(Module &module, StringAttr label) {
  llvm::DenseSet<StringAttr> visited;
  SmallVector<StringAttr> work{label};
  while (!work.empty()) {
    StringAttr name = work.pop_back_val();
    if (!visited.insert(name).second)
      continue;
    func::FuncOp fn = module.function(name);
    if (!fn || fn.isExternal())
      return true;
    WalkResult found = fn.walk([&](Operation *op) {
      if (observable(op))
        return WalkResult::interrupt();
      if (auto call = dyn_cast<func::CallOp>(op))
        work.push_back(call.getCalleeAttr().getAttr());
      return WalkResult::advance();
    });
    if (found.wasInterrupted())
      return true;
  }
  return false;
}

// Marks `by_name` each label constructor of a memo sum of the converted
// module whose function reaches an observable effect, unless a static
// constant names that label.
void markByName(Module &module) {
  llvm::DenseSet<StringAttr> memos, statics;
  for (idr::DataOp data : module.op.getOps<idr::DataOp>())
    if (idr::isMemo(data))
      memos.insert(data.getSymNameAttr());
  module.op.walk([&](idr::ConstantOp constant) {
    constant.getValue().walk([&](idr::ConAttr con) {
      if (memos.contains(con.getCtor().getRootReference()))
        statics.insert(con.getCtor().getLeafReference());
    });
  });
  llvm::DenseMap<StringAttr, bool> answers;
  for (idr::DataOp data : module.op.getOps<idr::DataOp>()) {
    if (!idr::isMemo(data) || !data.getLabels())
      continue;
    for (auto label : data.getLabelsAttr().getAsRange<FlatSymbolRefAttr>()) {
      StringAttr name = label.getAttr();
      if (statics.contains(name))
        continue;
      auto [it, inserted] = answers.try_emplace(name, false);
      if (inserted)
        it->second = reaches(module, name);
      if (it->second)
        idr::lookupCtor(data, name.getValue()).setByName(true);
    }
  }
}

} // namespace idr::defunctionalize
