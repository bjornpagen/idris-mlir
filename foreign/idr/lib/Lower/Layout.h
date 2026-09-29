// How idr values are represented at runtime. idr-lower builds values in these
// layouts, and idr-eval's child reads its results back through the same code.
#pragma once

#include "idr/Idr.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/StringMap.h"

#include <memory>

namespace idr::lower {

// The second word of a cell's header: tag | objs << 16 | kind << 24. The
// tag is a box's constructor tag, a closure's label or a string's ASCII
// flag; objs is the number of 8-byte object slots (the counted references,
// which the runtime releases when it frees the cell); bit 31 marks a cell
// in a stack frame.
enum class CellKind : uint32_t { Box = 0, Closure = 1, String = 2, Bignum = 3 };
constexpr uint32_t tagMask = 0xFFFF;
inline uint32_t cellInfo(uint32_t tag, unsigned objs, CellKind kind) {
  return tag | objs << 16 | static_cast<uint32_t>(kind) << 24;
}

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
  unsigned offset() const { return tag ? 1 : 0; }
};

// One component of a value stored in a heap cell or static data.
struct Slot {
  mlir::Type type;
  unsigned offset;
};

// A box or a closure: a cell is the 8-byte header (idris_rt_header: the
// count, then the info word), then its components. The counted components
// come first, 8 bytes each, as the runtime's object slots: right after the
// header in a box, after the code pointer (offset 8) in a closure. The
// others follow at their natural alignment, as a C struct or an LLVM struct
// of the same members in address order lays them out.
struct Cell {
  // For each field (of a constructor) or capture (of a closure, after the
  // code pointer), the slots of its components.
  llvm::SmallVector<llvm::SmallVector<Slot>> fields;
  unsigned size = 8;
  // The number of object slots.
  unsigned objs = 0;
  // Every component, (field, component) in address order.
  llvm::SmallVector<std::pair<unsigned, unsigned>> order;

  // The members of the LLVM struct with this layout: i32, i32, then each
  // component in address order.
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
  // !idr.world, the slots of an unboxed sum, one pointer for strings, boxes,
  // closures and reuse tokens, one i64 for bigs, the type itself for
  // scalars.
  llvm::SmallVector<mlir::Type> components(mlir::Type type);
  // For each of those components, whether it is counted: a pointer to a
  // cell, a big's word, or a counted slot of a sum.
  llvm::SmallVector<bool> counted(mlir::Type type);

  // The layout of the unboxed sum named `name`, computed once.
  const SumLayout &sum(mlir::StringAttr name);

  // The cell of a boxed constructor, and of a closure of `label`.
  const Cell &box(CtorOp ctor);
  const Cell &closure(const Label &label);

  // The labels closures of this module use (idr.closure ops and
  // #idr.closure constants, nested ones included), numbered in the order a
  // walk of the module meets them: idr-lower and idr-eval compute the same
  // numbers from the same module. A closure of a function the module lacks
  // names no label; the verifier rejects it.
  unsigned labelId(mlir::FlatSymbolRefAttr callee, unsigned captures) const;
  unsigned labelId(const Label &label) const { return labelId(label.callee, label.captures); }
  const Label &label(unsigned id) const { return labels[id]; }
  unsigned numLabels() const { return static_cast<unsigned>(labels.size()); }

  mlir::ModuleOp getModule() const { return module; }

private:
  // A cell whose first `leading` fields come first, before the object slots.
  Cell cellOf(llvm::ArrayRef<mlir::Type> fieldTypes, unsigned leading);

  mlir::ModuleOp module;
  // Each layout has its own allocation, so that a reference to one stays
  // valid while others are computed.
  llvm::DenseMap<mlir::StringAttr, std::unique_ptr<SumLayout>> sums;
  llvm::DenseMap<mlir::Operation *, std::unique_ptr<Cell>> boxes;
  llvm::SmallVector<Label> labels;
  llvm::DenseMap<std::pair<mlir::Attribute, unsigned>, unsigned> labelIds;
  llvm::DenseMap<unsigned, std::unique_ptr<Cell>> closures;
};

} // namespace idr::lower
