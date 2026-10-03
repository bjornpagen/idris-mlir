// idr.expect:report: how a property reports where it fails.
export module idr.expect:report;

import idr.mlir;

using namespace mlir;

namespace idr::expect {

// The error that a property fails at `loc`, to which the caller adds what
// was found: `expected <property>: <what>`.
InFlightDiagnostic fail(Location loc, StringRef property) {
  return emitError(loc) << "expected " << property << ": ";
}

// The name of the function that holds `op`, for an error's text.
std::string where(Operation *op) {
  auto fn = isa<func::FuncOp>(op) ? cast<func::FuncOp>(op) : op->getParentOfType<func::FuncOp>();
  return fn ? ("@" + fn.getSymName()).str() : std::string("the module");
}

} // namespace idr::expect
