// Whether a field of a constructor value is its one read.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

bool idr::fieldReadOnce(Value value, unsigned index) {
  unsigned reads = 0;
  SmallVector<Value, 4> work{value};
  while (!work.empty()) {
    Value held = work.pop_back_val();
    for (Operation *user : held.getUsers()) {
      if (isa<LinEnterOp, LinUseOp>(user)) {
        work.push_back(user->getResult(0));
        continue;
      }
      auto read = dyn_cast<FieldOp>(user);
      if (!read)
        return false;
      if (read.getIndex() == index)
        ++reads;
    }
  }
  return reads == 1;
}
