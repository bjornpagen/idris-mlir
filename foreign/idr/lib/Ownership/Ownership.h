// Ownership in the idr dialect: which values hold references, what each use
// of one does with it, the passes of idr-rc and the verifier of the owned
// stage.
//
// A value holds references when its type does (a string, a big, a box, a
// closure, a reuse token, or an unboxed sum with a slot of one of these).
// In the owned stage its grade says what it holds:
//   - owned (`!idr.own<T>`): one reference of its own, which exactly one
//     use on every path consumes. Results of calls, constructors, closures,
//     primitives and matches are owned, and so are the parameters that
//     borrow inference leaves owned;
//   - a view (plain T): none; it lives as long as what it was read from. A
//     borrowed parameter lives as long as the call, a field of a
//     constructor (an idr.field, or a field a match region binds) and an
//     idr.borrow as long as the value it was read from, and static data (a
//     constant, whose cells no count reaches) forever.
// idr.dup gives a view one reference of its own, which one use consumes.
#pragma once

#include "idr/Idr.h"

#include "llvm/ADT/DenseMap.h"

namespace idr::lower {
class Layouts;
} // namespace idr::lower

namespace idr::ownership {

// The module attribute that marks the owned stage, and its value.
inline constexpr llvm::StringLiteral stageAttr = "idr.stage";
inline constexpr llvm::StringLiteral ownedStage = "owned";

// Whether `value` is static: a constant, poison, or a field read from one.
bool isStatic(mlir::Value value);

// Whether `view` is an atom: a constant nullary constructor, a static cell
// with no fields that no count reaches and nothing reuses, which is in
// every exclusive tree.
bool isAtom(mlir::Value view);

// Which types hold references. An unboxed sum does when a field of one of
// its constructors does; the answers are computed once per module.
class Counting {
public:
  explicit Counting(mlir::Operation *module) : module(module) {}

  bool counted(mlir::Type type);

  // Whether `value` holds references: its type does, and it is not static.
  bool tracked(mlir::Value value) { return counted(value.getType()) && !isStatic(value); }

private:
  mlir::Operation *module;
  llvm::DenseMap<mlir::Attribute, DataOp> datas;
  llvm::DenseMap<mlir::Attribute, bool> sums;
};

// The value a field was read from: the operand of an idr.field, or the
// scrutinee of the match whose region binds it; null for any other value.
mlir::Value readFrom(mlir::Value value);

// Whether `op`'s region is the body of a loop over an array
// (idr.array.generate, idr.array.fold): it runs once per index it covers,
// so a value from outside it is used again after any op in it.
bool isArrayLoop(mlir::Operation *op);

// Whether `value` is used after `op`: later in its block, or after an op
// that holds that block, up to the block that defines it; always, from
// inside the body of a loop the value comes from outside of.
bool usedAfter(mlir::Value value, mlir::Operation *op);

// Whether the function borrows its parameter `index`: in the owned
// stage, whether the parameter is a view.
bool isBorrowed(mlir::func::FuncOp fn, unsigned index);

// What a use does with a reference: consumes one, or only needs the value to
// be alive. Returns, yields, constructors, closures, takes, reuses, decs,
// arguments of owned parameters and the arguments of an apply consume;
// everything else borrows, the closure an apply calls included.
enum class Use { Consume, Borrow };
Use useOf(mlir::OpOperand &operand, mlir::SymbolTableCollection &symbols);

// The function a call calls, or null.
mlir::func::FuncOp callee(mlir::func::CallOp call, mlir::SymbolTableCollection &symbols);

// Takes the scrutinee of `match` apart where its case region `index`
// begins: an idr.take whose fields replace the region's arguments.
TakeOp takeAtEntry(MatchOp match, unsigned index);

// Takes the unboxed sum `value`, built by `ctor` whose fields have
// `fieldTypes`, apart where it is defined, and gives each of its field
// reads the field taken.
TakeOp takeFields(mlir::Value value, mlir::SymbolRefAttr ctor, mlir::ArrayRef<mlir::Type> fieldTypes);

// The passes of idr-rc, in the order it runs them (Rc.cc).

// Beans' reset/reuse insertion: in a case region of a match on a box that
// is dead there, the box is taken apart where it dies and its cell reused
// by the first constructor of a cell of the same size on each path after
// it. Returns the number of takes and of reuses.
std::pair<unsigned, unsigned> insertResetReuse(mlir::func::FuncOp fn, lower::Layouts &layouts);

// Lean's borrow inference: which parameters of the module's functions can
// be borrowed. Writes the signatures: a borrowed parameter keeps its plain
// type, an owned one and every result that holds references become owned.
// Returns how many parameters are borrowed.
unsigned inferBorrows(mlir::ModuleOp module, Counting &counting);

// The signatures with every parameter and result that holds references
// owned: what counting assumes when borrow inference does not run.
void ownSignatures(mlir::ModuleOp module, Counting &counting);

// Explicit counting (Perceus): the incs and decs that make every
// reference consumed exactly once on every path. Returns the numbers of
// incs and decs added, or failure after reporting what it cannot count.
mlir::FailureOr<std::pair<unsigned, unsigned>> insertCounts(mlir::func::FuncOp fn,
                                                             Counting &counting, bool sink);

// Exclusivity (Exclusive.cc): the owned values that hold the only
// reference to every cell they reach get the excl grade, and an exclusive
// value given to an owned position is shared into it (idr.share). Returns
// how many values are exclusive.
mlir::FailureOr<unsigned> inferExclusive(mlir::ModuleOp module);

// The verifier of the owned stage (Verify.cc): every reference is consumed
// exactly once on every path, no value is used after its last reference is
// gone, and every idr.reuse builds in a cell of its own size.
mlir::LogicalResult verifyOwned(mlir::ModuleOp module);

} // namespace idr::ownership
