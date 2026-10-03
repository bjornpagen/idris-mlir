// The spelling !idr.lin<T>: T at (1, .).

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

Type idr::linear(Type value) { return graded({Quantity::One, Permission::None}, value); }
