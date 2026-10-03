// idr.lower:fields: what the owned stage settled about the fields of the
// ops that count references, read before phase 2 forgets it.
export module idr.lower:fields;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::lower {

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

// What the owned stage settled about the fields of the ops that count
// references, read after phase 1 and before the conversion starts, which
// replaces each op as it meets it.
export class Fields {
public:
  // A field a reuse gives back as its token's take gave it is in the cell
  // already, with the reference the cell held all along: the take moved it
  // out without a count and the reuse moves it in without one, so the owned
  // stage counts nothing for it, and nothing need be stored for it here
  // (Lean's ExpandResetReuse; Perceus's reuse specialization). The fact is
  // the identity of two values of the owned stage, which the conversion
  // loses as it goes: it replaces each op as it meets it, so by the time a
  // reuse is converted the take that made its token is a test and some
  // loads. So it is read from every reuse before the conversion starts.
  explicit Fields(ModuleOp module) {
    module.walk([&](ReuseOp reuse) {
      auto take = reuse.getToken().getDefiningOp<TakeOp>();
      if (!take || take.getCtor() != reuse.getCtor())
        return;
      SmallVector<bool> &mask = keptFields[reuse];
      for (auto [field, taken] : llvm::zip_equal(reuse.getFields(), take.getFields()))
        mask.push_back(moved(field) == taken);
    });
  }

  // For a reuse of the constructor its token's take took apart: for each
  // field, whether the cell holds it already, because the reuse gives it
  // back as the take gave it. Empty for a reuse of another constructor,
  // whose cell holds none of its fields, and a new header.
  ArrayRef<bool> kept(ReuseOp reuse) const {
    auto it = keptFields.find(reuse);
    return it == keptFields.end() ? ArrayRef<bool>() : ArrayRef<bool>(it->second);
  }

private:
  DenseMap<Operation *, SmallVector<bool>> keptFields;
};

} // namespace idr::lower
