// How idr values are represented at runtime. idr-lower builds values in these
// layouts, and idr-eval's child reads its results back through the same code.
#pragma once

#include "idr/Idr.h"

#include "idris_rt.h"

#include "mlir/Interfaces/DataLayoutInterfaces.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/StringMap.h"

#include <expected>
#include <memory>
#include <string>

namespace idr::lower {

// The info word of a cell's header, which the runtime reads to free the cell
// (idris_rt_info: the tag, the number of object slots, the kind). A CellInfo
// exists only for a tag and an object count that fit their fields, so a word
// whose fields overflow into each other cannot be written; the factories say
// why when they do not fit.
class CellInfo {
public:
  static std::expected<CellInfo, std::string> box(uint64_t tag, uint64_t objs) noexcept;
  // A closure's code pointer says what it is, so its tag is 0.
  static std::expected<CellInfo, std::string> closure(uint64_t objs) noexcept;
  // An array's: the tag is the element's size in bytes, its objs the object
  // slots each element starts with.
  static std::expected<CellInfo, std::string> array(uint64_t stride, uint64_t objs) noexcept;
  static constexpr CellInfo string(bool ascii) noexcept {
    return CellInfo(idris_rt_info(ascii ? 1u : 0u, 0, IDRIS_RT_KIND_STRING));
  }
  static constexpr CellInfo bignum() noexcept {
    return CellInfo(idris_rt_info(0, 0, IDRIS_RT_KIND_BIGNUM));
  }

  constexpr uint32_t word() const noexcept { return bits; }
  // The same cell in a stack frame.
  constexpr CellInfo onStack() const noexcept { return CellInfo(bits | IDRIS_RT_STACK_CELL); }

private:
  constexpr explicit CellInfo(uint32_t word) noexcept : bits(word) {}
  uint32_t bits;
};

// The tag of a box, the low bits of its info word (idris_rt_info_tag).
constexpr uint32_t tagMask = IDRIS_RT_TAG_LIMIT - 1;

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

// A box or a closure: a cell is the header (idris_rt_header: the count,
// then the info word, IDRIS_RT_WORD_BYTES together), then its components.
// The counted components come first, one pointer-sized word each, as the
// runtime's object slots: right after the header in a box, after the code
// pointer in a closure. The others follow, each at the size and alignment
// the target's data layout gives its type. A cell starts and ends on a
// word boundary.
struct Cell {
  // For each field (of a constructor) or capture (of a closure, the code
  // pointer first), the slots of its components.
  llvm::SmallVector<llvm::SmallVector<Slot>> fields;
  unsigned size = IDRIS_RT_WORD_BYTES;
  // The number of object slots.
  unsigned objs = 0;
  // Every component, (field, component) in address order.
  llvm::SmallVector<std::pair<unsigned, unsigned>> order;
  // The header's info word, which counts the object slots.
  CellInfo info;
};

// An element of an array (idris_rt_array): its components in their slots,
// at offsets from the element's start, laid out as a cell's fields are
// (object slots first); the element's size, which is the array's stride;
// and the info word of the array's cell.
struct Element {
  llvm::SmallVector<Slot> slots;
  unsigned stride;
  CellInfo info;
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
  // The layouts of the values of `m`, for the target its data layout
  // describes (dlti.dl_spec; MLIR's defaults without one). Every cell's
  // header is decided here, once: when a box type or a cell has more than
  // its header can describe, each such one gets an `unsupported (layout)`
  // error and the result is a failure. A target whose pointers are not the
  // runtime's words gets `unsupported (target)`.
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
  const Cell &box(CtorOp ctor) const { return *boxes.find(ctor)->second; }
  const Cell &closure(const Label &label) const { return *closures.find(labelId(label))->second; }

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

} // namespace idr::lower
