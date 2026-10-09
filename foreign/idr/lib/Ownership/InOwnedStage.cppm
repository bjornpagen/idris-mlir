// idr.ownership:inownedstage: whether a module is in the owned stage.
export module idr.ownership:inownedstage;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::ownership {

// Whether `module` is in the owned stage: a value in it is owned or
// exclusive, which only idr-rc's grades make. The grades are the stage, so
// no attribute restates it. A module without such a value has no reference
// to count: each value in it that holds references is static data, or a
// view of it. One walk, which a pass asks once and passes on.
export bool inOwnedStage(ModuleOp module) {
  auto owned = [](Value value) { return isOwned(value.getType()); };
  return module
      .walk([&](Operation *op) {
        if (llvm::any_of(op->getResults(), owned))
          return WalkResult::interrupt();
        for (Region &region : op->getRegions())
          for (Block &block : region)
            if (llvm::any_of(block.getArguments(), owned))
              return WalkResult::interrupt();
        return WalkResult::advance();
      })
      .wasInterrupted();
}

} // namespace idr::ownership
