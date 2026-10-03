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

  // The tag, if any, then the slots.
  llvm::SmallVector<mlir::Type> types() const {
    llvm::SmallVector<mlir::Type> all;
    if (tag)
      all.push_back(tag);
    all.append(slots.begin(), slots.end());
    return all;
  }
  unsigned offset() const { return tag ? 1 : 0; }
};

} // namespace idr::layout
