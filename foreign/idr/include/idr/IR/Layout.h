// How idr values are represented at runtime, as the runtime (idris_rt.h)
// reads them: the cells of boxes, memo sums and arrays and the slots of
// unboxed sums, decided once per module for its target (Layouts); and the
// boxes that make every cell's object slots fit its header (fit), which
// idr-defunctionalize decides once the module's types are final.

#ifndef IDR_IR_LAYOUT_H
#define IDR_IR_LAYOUT_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringMap.h"

#include "idris_rt.h"

#include <expected>
#include <memory>
#include <string>
#include <utility>

namespace idr::layout {

// The most object slots a header counts: its objs field is 8 bits wide.
// Every test of whether a cell's header can count what the cell holds
// compares against this one bound.
inline constexpr unsigned mostObjects = IDRIS_RT_OBJS_LIMIT - 1;

// The tag of a box, the low bits of its info word (idris_rt_info_tag).
inline constexpr uint32_t tagMask = IDRIS_RT_TAG_LIMIT - 1;

// The info word of a cell's header, which the runtime reads to free the cell
// (idris_rt_info: the tag, the number of object slots, the kind). A CellInfo
// exists only for a tag and an object count that fit their fields, so a word
// whose fields overflow into each other cannot be written; the factories say
// why when they do not fit.
class CellInfo {
public:
  static std::expected<CellInfo, std::string> box(uint64_t tag, uint64_t objs) noexcept;
  // A memo cell in the state of the constructor `tag`: laid out and freed
  // as a box, and of its own kind, which says that a force may write it.
  static std::expected<CellInfo, std::string> thunk(uint64_t tag, uint64_t objs) noexcept;
  // An array's: the tag is the element's size in bytes, its objs the object
  // slots each element starts with.
  static std::expected<CellInfo, std::string> array(uint64_t stride, uint64_t objs) noexcept;
  static CellInfo string(bool ascii) noexcept;
  static CellInfo bignum() noexcept;

  uint32_t word() const noexcept;
  // The same cell in a stack frame.
  CellInfo onStack() const noexcept;

private:
  explicit CellInfo(uint32_t word) noexcept;
  // A box's word or a memo cell's, which differ only in the kind.
  static std::expected<CellInfo, std::string> constructor(uint64_t tag, uint64_t objs,
                                                          uint32_t kind) noexcept;
  uint32_t bits;
};

// One component of a value stored in a heap cell or static data.
struct Slot {
  mlir::Type type;
  unsigned offset;
};

// A box, or a memo cell in one of its states: a cell is the header
// (idris_rt_header: the count, then the info word, IDRIS_RT_WORD_BYTES
// together), then its components. The counted components come first, one
// pointer-sized word each, right after the header, as the runtime's object
// slots. The others follow, each at the size and alignment the target's
// data layout gives its type. A cell starts and ends on a word boundary,
// and holds no code address.
struct Cell {
  // For each field of the constructor, the slots of its components.
  llvm::SmallVector<llvm::SmallVector<Slot>> fields;
  // The bytes allocated for the cell: a memo cell's are its largest
  // state's, whichever state it is built in.
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

// An unboxed sum spread over scalar slots. A slot that holds a counted
// component in one constructor (a pointer to a cell, or a big) holds one in
// every constructor that uses it, and null in those that do not, so that the
// references of a sum are exactly its counted slots.
struct SumLayout {
  mlir::Type tag; // null when the type has at most one constructor
  llvm::SmallVector<mlir::Type> slots;
  llvm::SmallVector<bool> counted; // for each slot
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

// The runtime components of the value types of a module, and which of them a
// cell's header counts. They are the same on every target: what a component
// takes in bytes is Layouts', and what is counted is not a matter of bytes.
// The sums are computed as they are asked for, on one thread.
class Components {
public:
  // The components of the values of `m`, by its declarations as they are
  // now: a declaration that changes after this is not seen.
  explicit Components(mlir::ModuleOp m);

  // The declaration named `name`, or null.
  DataOp declaration(mlir::StringAttr name) const;

  // The runtime components of a value type: none for !idr.world, the slots
  // of an unboxed sum, one pointer for strings, boxes (memo cells included)
  // and reuse tokens, one i64 for bigs, the type itself for scalars. A
  // !idr.fn that idr-defunctionalize leaves is a value the program never
  // reaches, and it is still lowered, as one pointer.
  llvm::SmallVector<mlir::Type> components(mlir::Type type);
  // For each of those components, whether it is counted: a pointer to a
  // cell, a big's word, or a counted slot of a sum.
  llvm::SmallVector<bool> counted(mlir::Type type);

  // The number of counted components of a value of `type`, and of values
  // of `types` side by side: the object slots they take in a cell.
  unsigned objects(mlir::Type type);
  unsigned objects(llvm::ArrayRef<mlir::Type> types);

  // The layout of the unboxed sum named `name`, computed once.
  const SumLayout &sum(mlir::StringAttr name);

  mlir::ModuleOp getModule() const;

protected:
  using SumOf = llvm::function_ref<const SumLayout &(mlir::StringAttr)>;
  // The answers of components and counted, each sum read from `sumOf`.
  llvm::SmallVector<mlir::Type> componentsWith(mlir::Type type, SumOf sumOf) const;
  llvm::SmallVector<bool> countedWith(mlir::Type type, SumOf sumOf) const;
  // The layout of the sum named `name` if it has been computed, or null.
  const SumLayout *computed(mlir::StringAttr name) const;

  mlir::ModuleOp module;

private:
  // Resolved once, so that measuring a module is linear in what it
  // measures: a lookup in the module scans its body.
  llvm::DenseMap<mlir::StringAttr, DataOp> decls;
  // Each layout has its own allocation, so that a reference to one stays
  // valid while others are computed.
  llvm::DenseMap<mlir::StringAttr, std::unique_ptr<SumLayout>> sums;
};

// Whether `data` may become a box without changing what an op already in
// the module means. With one constructor, every idr.field of a value names
// the constructor it has, so the read stays within its own live cell
// wherever it runs. A closure sum is made by idr-defunctionalize, which
// reads it only through idr.match. A sum of several constructors may
// already be read where its constructor is unknown (a read of an unboxed
// sum may run anywhere), which a box would turn into a load past the end
// of a smaller cell.
bool boxable(DataOp data);

// The cells whose header counts the object slots of what they hold spread
// over their own: each constructor of a box (a memo sum's states among
// them), and each element of an array of an unboxed sum.
class Holders {
public:
  // The holders of `m`: its array element types are found once, here.
  explicit Holders(mlir::ModuleOp m);

  // Calls `each` with every holder whose cell counts more object slots
  // than a header can, as `parts` measures the declarations now: the
  // constructor or the element's declaration, what it holds, and how many
  // object slots that takes.
  void overflows(Components &parts,
                 llvm::function_ref<void(mlir::Operation *at, llvm::ArrayRef<mlir::Type> held,
                                         unsigned objects)>
                     each);

private:
  mlir::ModuleOp module;
  // The declarations whose values are array elements.
  llvm::SetVector<DataOp> elements;
};

// Makes boxes of records and closure sums until no cell that holds one
// counts more object slots than its header can, the widest first (ties by
// name), and retypes their values in the module; returns how many it made.
// A cell that still overflows does so by fields no box can shrink, which
// Layouts reports.
unsigned fit(mlir::ModuleOp module);

// idr's comparison of two values held as words, as a signed comparison of
// the words: a big's small words and the runtime's three-way result both
// order that way.
mlir::arith::CmpIPredicate signedPredicate(CmpPredicate predicate);

} // namespace idr::layout

namespace idr {

// The layouts of the values of a module, on the components of its value
// types, placed as its target lays them out: what idr-lower builds values
// in, and what the owned stage and idr-stack size cells by. Every sum and
// every boxed constructor's cell is computed by the constructor, and
// nothing changes after it, so passes running in parallel read it without
// a lock. It holds while no idr.data changes.
class Layouts : public layout::Components {
public:
  // The layouts of `module`, for the target its data layout describes
  // (dlti.dl_spec; MLIR's defaults without one). Every cell's header is
  // decided here, once: a cell that holds more than its header can describe
  // gets an `unsupported (layout)` error at its constructor, and valid()
  // fails. After idr-defunctionalize, every record or closure sum that
  // would make a cell holding it overflow is a box (fit), so such a cell
  // is a constructor's own fields, or the fields of a sum of several
  // constructors that it holds. A target whose pointers are not the
  // runtime's words is the compiler's error.
  explicit Layouts(mlir::Operation *module);

  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const {
    return !pa.isPreserved<Layouts>();
  }

  // Whether every cell could be built: what each pass that asks for the
  // layouts tests first, the reasons having been reported.
  mlir::LogicalResult valid() const;

  // As Components answers them, from the sums computed at construction.
  llvm::SmallVector<mlir::Type> components(mlir::Type type) const;
  llvm::SmallVector<bool> counted(mlir::Type type) const;
  unsigned objects(mlir::Type type) const;
  unsigned objects(llvm::ArrayRef<mlir::Type> types) const;
  const layout::SumLayout &sum(mlir::StringAttr name) const;

  // The bytes a component of type `component` takes in a cell, and the
  // alignment it is placed at, as the target lays it out.
  unsigned sizeOf(mlir::Type component) const;
  unsigned alignmentOf(mlir::Type component) const;

  // The element layout of an array of `element`, or why it has none: more
  // counted components than a cell's header counts, or a size its tag
  // cannot hold.
  std::expected<layout::Element, std::string> element(mlir::Type element) const;

  // The cell of a boxed constructor. A memo sum's constructor gives the
  // cell in that state, at the size of the sum's largest state, which every
  // cell of the sum is allocated at.
  const layout::Cell &box(CtorOp ctor) const;

  // Whether `type` is a box of a memo sum, whose cell a force may write.
  bool isMemo(mlir::Type type) const;

private:
  // A cell of `fieldTypes`, object slots first, with the header `info`
  // gives for its number of object slots.
  std::expected<layout::Cell, std::string>
  cellOf(llvm::ArrayRef<mlir::Type> fieldTypes,
         llvm::function_ref<std::expected<layout::CellInfo, std::string>(unsigned objs)> info)
      const;

  bool fits = true;
  // The size and alignment of every component type the declarations hold,
  // measured once with the module's data layout, whose own answers are
  // remembered as they are asked and so cannot be shared between threads.
  llvm::DenseMap<mlir::Type, std::pair<unsigned, unsigned>> measures;
  llvm::DenseMap<mlir::Operation *, layout::Cell> boxes;
};

} // namespace idr

#endif // IDR_IR_LAYOUT_H
