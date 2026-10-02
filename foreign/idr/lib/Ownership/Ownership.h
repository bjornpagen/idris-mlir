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

// Whether `view` is static data that reaches no cell but atoms: a constant
// nullary constructor (an atom, a static cell with no fields), or a constant
// unboxed sum, which has no cell, whose fields reach none either (a pair of
// empty lists). No take hands out a cell of it, since an atom has no fields
// to take and a sum no cell; no count reaches it, nothing frees or writes
// it. So whoever else holds it changes nothing a consumer of exclusivity
// does: it is in every exclusive tree. A static box with fields is not: a
// take of it would hand out its cell as a token to build in.
bool reachesOnlyAtoms(mlir::Value view);

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

// The ops of `block` after `after` (from its start when null) that use
// `value`, themselves or in their regions, in order.
llvm::SmallVector<mlir::Operation *> usersIn(mlir::Value value, mlir::Block &block,
                                             mlir::Operation *after);

// Where `value`, which `block` holds a reference to, dies on each path of
// the block: at its start when nothing there uses it, after its last use,
// or inside each region of that use when it has regions (not the body of a
// loop over an array, which the value outlives). Nowhere on a path whose
// last use consumes it: the value moves on, its cell with it, and a take
// after that use would keep a second reference alive across it, so that
// whoever receives the value finds its cell shared and copies it. Calls
// `at` with each point.
void whereDies(mlir::Value value, mlir::Block &block, mlir::SymbolTableCollection &symbols,
               llvm::function_ref<void(mlir::Block &, mlir::Block::iterator)> at);

// Takes the box `box`, built by `ctor`, apart at `at` in `block`: an
// idr.take whose fields replace the reads of the box's fields after that
// point, the arguments of `fields` (the case region that bound them, when
// one did) and idr.field, so that a field read after the box dies keeps the
// box's reference instead of taking one of its own where the box reads it,
// only for the box to drop it again. Reads before the take are borrowed
// from the box, which is still alive there.
TakeOp takeAt(mlir::Value box, CtorOp ctor, mlir::Block &block, mlir::Block::iterator at,
              mlir::Block *fields);

// Whether `box`, built by `ctor`, keeps a field that holds references past
// `at` in `block`, where it dies: a field of it (as takeAt finds them) used
// at that point or after. Only then does a take there save anything over a
// drop, as Perceus specializes a drop only where the children are used: a
// field that lives on moves out of an unshared cell instead of taking a
// reference of its own while the box drops the cell's. A field that dies
// with the box is dropped either way, and one that holds no reference has
// nothing to move.
bool keepsCountedField(mlir::Value box, CtorOp ctor, mlir::Block &block, mlir::Block::iterator at,
                       mlir::Block *fields);

// The first read of a box that no match takes apart and whose every use
// reads a field of one constructor (a nested pattern reads the fields of a
// box an outer one matched), the point from which the box's constructor
// is known in that read's block; null for any other value.
FieldOp onlyReads(mlir::Value box);

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
