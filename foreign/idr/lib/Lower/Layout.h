// How idr values are represented at runtime. idr-lower builds values in these
// layouts, and idr-eval's child reads its results back through the same code.
#pragma once

#include "idr/Idr.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/StringMap.h"

namespace idr::lower {

// An unboxed sum spread over scalar slots.
struct SumLayout {
  mlir::Type tag;                       // null when the type has at most one constructor
  llvm::SmallVector<mlir::Type> slots;
  // For each constructor name: for each field, the slots of its components.
  llvm::StringMap<llvm::SmallVector<llvm::SmallVector<unsigned>>> fields;

  llvm::SmallVector<mlir::Type> types() const;
  unsigned offset() const { return tag ? 1 : 0; }
};

// One component of a value stored in a heap cell or static data.
struct Slot {
  mlir::Type type;
  unsigned offset;
};

// A box or a closure: a cell is the 8-byte header (idris_rt_header: the
// count, then the constructor tag or the closure's label), then its
// components at their natural alignment, as a C struct or an LLVM struct of
// the same members lays them out. A closure's first component after the
// header is its code pointer.
struct Cell {
  // For each field (of a constructor) or capture (of a closure), the slots
  // of its components.
  llvm::SmallVector<llvm::SmallVector<Slot>> fields;
  unsigned size = 8;

  // The members of the LLVM struct with this layout: i32, i32, then each
  // component.
  llvm::SmallVector<mlir::Type> members(mlir::MLIRContext *ctx) const;
};

// A closure label: a function with the number of leading
// parameters that are captures. Closures of one label share their code.
struct Label {
  mlir::FlatSymbolRefAttr callee;
  unsigned captures;
  // The callee's type before idr-lower converts it.
  mlir::FunctionType type;

  llvm::ArrayRef<mlir::Type> captureTypes() const { return type.getInputs().take_front(captures); }
  llvm::ArrayRef<mlir::Type> argumentTypes() const { return type.getInputs().drop_front(captures); }
};

class Layouts {
public:
  explicit Layouts(mlir::ModuleOp m);

  // The runtime components of a value type: none for !idr.erased and
  // !idr.world, the slots of an unboxed sum, one pointer for strings, boxes
  // and closures, one i64 for bigs, the type itself for scalars.
  llvm::SmallVector<mlir::Type> components(mlir::Type type);

  // The layout of the unboxed sum named `name`, computed once.
  const SumLayout &sum(mlir::StringAttr name);

  // The cell of a boxed constructor, and of a closure of `label`.
  const Cell &box(CtorOp ctor);
  const Cell &closure(const Label &label);

  // The labels closures of this module use (idr.closure ops and
  // #idr.closure constants, nested ones included), numbered in the order a
  // walk of the module meets them: idr-lower and idr-eval compute the same
  // numbers from the same module.
  unsigned labelId(mlir::FlatSymbolRefAttr callee, unsigned captures) const;
  unsigned labelId(const Label &label) const { return labelId(label.callee, label.captures); }
  const Label &label(unsigned id) const { return labels[id]; }
  unsigned numLabels() const { return static_cast<unsigned>(labels.size()); }

  mlir::ModuleOp getModule() const { return module; }

private:
  Cell cellOf(llvm::ArrayRef<mlir::Type> fieldTypes, unsigned start);

  mlir::ModuleOp module;
  llvm::DenseMap<mlir::StringAttr, SumLayout> sums;
  llvm::DenseMap<mlir::Operation *, Cell> boxes;
  llvm::SmallVector<Label> labels;
  llvm::DenseMap<std::pair<mlir::Attribute, unsigned>, unsigned> labelIds;
  llvm::DenseMap<unsigned, Cell> closures;
};

} // namespace idr::lower
