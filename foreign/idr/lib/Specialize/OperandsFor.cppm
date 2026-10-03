// idr.specialize:operandsfor: the operands of a call of a clone, from the
// values of its key's holes.
export module idr.specialize:operandsfor;

import idr.mlir;

import :clones;

using namespace mlir;

export namespace idr::specialize {

// The operands of a call of `clone` given the value of each hole of its
// key, or none when the call has no value for a hole the clone still takes.
std::optional<llvm::SmallVector<mlir::Value>>
operandsFor(const Clone &clone, llvm::ArrayRef<std::optional<mlir::Value>> holes) {
  func::FuncOp fn = clone.fn;
  SmallVector<Value> out;
  for (auto [hole, type] : llvm::zip(clone.holes, fn.getArgumentTypes())) {
    if (hole >= holes.size() || !holes[hole] || holes[hole]->getType() != type)
      return std::nullopt;
    out.push_back(*holes[hole]);
  }
  return out;
}

} // namespace idr::specialize
