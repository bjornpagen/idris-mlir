// reuses-in-place: what reference counting left in a function, stated as
// the property a test wants of it: it builds in reused cells.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

// The function the argument names and its clones together: at least one
// of them builds in the cell of a box that died (idr.reuse), and none
// gives a box a fresh cell.
LogicalResult reusesInPlace(ModuleOp module, AnalysisManager &analyses, StringRef function) {
  constexpr StringRef property = "reuses-in-place";
  SmallVector<FunctionOpInterface> functions =
      named(module, analyses.getAnalysis<SymbolTable>(), function, property);
  if (functions.empty())
    return failure();
  bool held = true, reused = false;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](Operation *op) {
      if (isa<ReuseOp>(op))
        reused = true;
      auto con = dyn_cast<ConOp>(op);
      if (con && isa<BoxType>(unrestricted(con.getType()))) {
        fail(op->getLoc(), property) << "a box of " << con.getCtor() << " gets a fresh cell in "
                                     << where(op);
        held = false;
      }
    });
  if (!reused) {
    fail(functions.front()->getLoc(), property) << "nothing is built in a reused cell in " << function;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
