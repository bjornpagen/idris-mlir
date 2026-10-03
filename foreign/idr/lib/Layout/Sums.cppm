// idr.layout:sums: an unboxed sum, spread over scalar slots.
export module idr.layout:sums;

import idr.mlir;

export namespace idr::layout {

// An unboxed sum spread over scalar slots. A slot that holds a counted
// component in one constructor (a pointer to a cell, or a big) holds one in
// every constructor that uses it, and null in those that do not, so that the
// references of a sum are exactly its counted slots.
struct SumLayout {
  mlir::Type tag;                       // null when the type has at most one constructor
  llvm::SmallVector<mlir::Type> slots;
  llvm::SmallVector<bool> counted;      // for each slot
  // For each constructor name: for each field, the slots of its components.
  llvm::StringMap<llvm::SmallVector<llvm::SmallVector<unsigned>>> fields;

  llvm::SmallVector<mlir::Type> types() const;
  unsigned offset() const;
};

} // namespace idr::layout
