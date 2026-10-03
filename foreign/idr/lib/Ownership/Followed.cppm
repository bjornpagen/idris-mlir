// idr.ownership:followed: the values whose cell graph exclusivity follows.
// Nothing here is exported: exclusivity's steps share it.
export module idr.ownership:followed;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::ownership {

// The values whose cell graph the analysis follows: owned boxes and
// unboxed sums (whose slots may hold boxes), and the tokens of their cells.
bool followed(Value value) {
  Type type = value.getType();
  return isOwned(type) && isa<BoxType, DataType, TokenType>(unrestricted(type));
}

} // namespace idr::ownership
