// What the owned stage settled about the fields of the ops that count
// references.

#include "idr/IR/IdrDialect.h"
#include "idr/Conversion/Fields.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// The value a field was given on as: through the changes of grade that
// have no runtime form (idr.share, idr.lin.enter, idr.lin.use) to the
// value that holds the reference.
Value moved(Value value) {
  while (Operation *def = value.getDefiningOp()) {
    if (!isa<ShareOp, LinEnterOp, LinUseOp>(def))
      break;
    value = def->getOperand(0);
  }
  return value;
}

} // namespace

Fields::Fields(ModuleOp module) {
  module.walk([&](ReuseOp reuse) {
    auto take = reuse.getToken().getDefiningOp<TakeOp>();
    if (!take || take.getCtor() != reuse.getCtor())
      return;
    SmallVector<bool> &mask = keptFields[reuse];
    for (auto [field, taken] : llvm::zip_equal(reuse.getFields(), take.getFields()))
      mask.push_back(moved(field) == taken);
  });
}

ArrayRef<bool> Fields::kept(ReuseOp reuse) const {
  auto it = keptFields.find(reuse);
  return it == keptFields.end() ? ArrayRef<bool>() : ArrayRef<bool>(it->second);
}

} // namespace idr::conversion
