// Which labels of the memo sums are `by_name`. A trusted library's effect
// happens where its value is demanded, so a cell whose label reaches an
// effect the program's outside can observe runs it at every force instead
// of keeping its value. A static constant's label keeps its value all the
// same: a top-level constant names one value of the program, evaluated
// once, so an effect in it is observed that once.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"

using namespace mlir;

namespace idr::defunctionalize {

namespace {

// Whether `op` is an effect the program's outside can observe: the trait
// its op class carries says it, once, beside the op.
bool observable(Operation *op) { return op->hasTrait<ObservableIO>(); }

// Whether `label` reaches an observable effect through direct calls. A
// function without a body may do anything.
bool reaches(SymbolTable &symbols, StringAttr label) {
  llvm::DenseSet<StringAttr> visited;
  SmallVector<StringAttr> work{label};
  while (!work.empty()) {
    StringAttr name = work.pop_back_val();
    if (!visited.insert(name).second)
      continue;
    auto fn = symbols.lookup<FuncOp>(name);
    if (!fn || fn.isExternal())
      return true;
    WalkResult found = fn.walk([&](Operation *op) {
      if (observable(op))
        return WalkResult::interrupt();
      if (auto call = dyn_cast<CallOp>(op))
        work.push_back(call.getCalleeAttr().getAttr());
      return WalkResult::advance();
    });
    if (found.wasInterrupted())
      return true;
  }
  return false;
}

} // namespace

void markByName(ModuleOp module, SymbolTable &symbols) {
  llvm::DenseSet<StringAttr> memos, statics;
  for (DataOp data : module.getOps<DataOp>())
    if (isMemo(data))
      memos.insert(data.getSymNameAttr());
  if (memos.empty())
    return;
  module.walk([&](ConstantOp constant) {
    constant.getValue().walk([&](ConAttr con) {
      if (memos.contains(con.getCtor().getRootReference()))
        statics.insert(con.getCtor().getLeafReference());
    });
  });
  llvm::DenseMap<StringAttr, bool> answers;
  SmallVector<CtorOp> byName;
  for (DataOp data : module.getOps<DataOp>()) {
    if (!isMemo(data) || !data.getLabels())
      continue;
    for (auto label : data.getLabelsAttr().getAsRange<FlatSymbolRefAttr>()) {
      StringAttr name = label.getAttr();
      if (statics.contains(name))
        continue;
      auto [it, inserted] = answers.try_emplace(name, false);
      if (inserted)
        it->second = reaches(symbols, name);
      if (it->second)
        if (CtorOp ctor = lookupCtor(data, name.getValue()))
          byName.push_back(ctor);
    }
  }
  for (CtorOp ctor : byName)
    ctor.setByName(true);
}

} // namespace idr::defunctionalize
