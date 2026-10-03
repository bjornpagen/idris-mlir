// idr.crash: what it reports.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

std::optional<StringRef> CrashOp::getCrashCause() { return getMessage(); }
