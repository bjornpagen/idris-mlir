// Whether a type is the world, graded or not.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

// The world and the erased value are known by their carriers, graded or
// not: a carrier that a grade was stripped from (unrestricted) is still
// the value it is.
bool idr::isWorld(Type type) { return isa<WorldType>(unrestricted(type)); }
