// idr.layout:layouts: the layouts of the values of a module. idr-lower
// builds values in these layouts, idr-eval's child reads its results back
// through them, and the owned stage and idr-stack size cells by them.
export module idr.layout:layouts;

import idr.mlir;
import idr.dialect;

import :cells;
import :labels;
import :sums;

export namespace idr::layout {

class Layouts {
public:
  // The layouts of the values of `m`, for the target its data layout
  // describes (dlti.dl_spec; MLIR's defaults without one). Every cell's
  // header is decided here, once: when a box type or a cell has more than
  // its header can describe, each such one gets an `unsupported (layout)`
  // error and the result is a failure. A target whose pointers are not the
  // runtime's words is an internal error.
  static mlir::FailureOr<Layouts> of(mlir::ModuleOp m);

  // The bytes a component of type `component` takes in a cell, and the
  // alignment it is placed at, as the target lays it out.
  unsigned sizeOf(mlir::Type component) const;
  unsigned alignmentOf(mlir::Type component) const;

  // The runtime components of a value type: none for !idr.erased and
  // !idr.world, the slots of an unboxed sum, one pointer for strings, boxes,
  // closures and reuse tokens, one i64 for bigs, the type itself for
  // scalars.
  llvm::SmallVector<mlir::Type> components(mlir::Type type);
  // For each of those components, whether it is counted: a pointer to a
  // cell, a big's word, or a counted slot of a sum.
  llvm::SmallVector<bool> counted(mlir::Type type);

  // The layout of the unboxed sum named `name`, computed once.
  const SumLayout &sum(mlir::StringAttr name);

  // The element layout of an array of `element`, or why it has none: more
  // counted components than a cell's header counts, or a size its tag
  // cannot hold.
  std::expected<Element, std::string> element(mlir::Type element);

  // The cell of a boxed constructor, and of a closure of `label`.
  const Cell &box(CtorOp ctor) const;
  const Cell &closure(const Label &label) const;

  // The labels closures of this module use (idr.closure ops and
  // #idr.closure constants, nested ones included), numbered in the order a
  // walk of the module meets them: idr-lower and idr-eval compute the same
  // numbers from the same module. A closure of a function the module lacks
  // names no label; the verifier rejects it.
  unsigned labelId(mlir::FlatSymbolRefAttr callee, unsigned captures) const;
  unsigned labelId(const Label &label) const;
  const Label &label(unsigned id) const;
  unsigned numLabels() const;

  mlir::ModuleOp getModule() const;

private:
  explicit Layouts(mlir::ModuleOp m);

  // A cell whose first `leading` fields come first, before the object
  // slots, with the header `info` gives for its number of object slots.
  std::expected<Cell, std::string>
  cellOf(llvm::ArrayRef<mlir::Type> fieldTypes, unsigned leading,
         llvm::function_ref<std::expected<CellInfo, std::string>(unsigned objs)> info);

  mlir::ModuleOp module;
  mlir::DataLayout target;
  // Each layout has its own allocation, so that a reference to one stays
  // valid while others are computed.
  llvm::DenseMap<mlir::StringAttr, std::unique_ptr<SumLayout>> sums;
  llvm::DenseMap<mlir::Operation *, std::unique_ptr<Cell>> boxes;
  llvm::SmallVector<Label> labels;
  llvm::DenseMap<std::pair<mlir::Attribute, unsigned>, unsigned> labelIds;
  llvm::DenseMap<unsigned, std::unique_ptr<Cell>> closures;
};

} // namespace idr::layout
