// Ownership in the idr dialect: which values hold references, what each use
// of one does with it, the passes of idr-rc and the verifier of the owned
// stage.
//
// A value holds references when its type does (a string, a big, a box, a
// closure, a reuse token, or an unboxed sum with a slot of one of these),
// unless it is static: a constant, whose cells are persistent data that no
// count reaches, or poison, which nothing reads. A value that holds
// references is
//   - owned: it holds one reference of its own, which exactly one use on
//     every path consumes. Results of calls, constructors, closures,
//     primitives and matches are owned, and so are parameters;
//   - borrowed: it holds none, and lives as long as what it was read from.
//     A parameter marked `idr.borrowed` lives as long as the call, and a
//     field of a constructor (an idr.field, or a field a match region
//     binds) as long as the value it was read from.
// idr.inc gives a value one more reference, which one more use consumes.
#pragma once

#include "idr/Idr.h"

#include "llvm/ADT/DenseMap.h"

namespace idr::lower {
class Layouts;
} // namespace idr::lower

namespace idr::ownership {

// The attribute of a parameter that the function borrows.
inline constexpr llvm::StringLiteral borrowedAttr = "idr.borrowed";
// The module attribute that marks the owned stage, and its value.
inline constexpr llvm::StringLiteral stageAttr = "idr.stage";
inline constexpr llvm::StringLiteral ownedStage = "owned";

// Whether `value` is static: a constant, poison, or a field read from one.
bool isStatic(mlir::Value value);

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

// Whether `value` is used after `op`: later in its block, or after an op
// that holds that block, up to the block that defines it.
bool usedAfter(mlir::Value value, mlir::Operation *op);

// Whether the function borrows its parameter `index`.
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
// be borrowed. Marks each with `idr.borrowed` and returns how many.
unsigned inferBorrows(mlir::ModuleOp module, Counting &counting);

// Explicit counting (Perceus): the incs and decs that make every
// reference consumed exactly once on every path. Returns the numbers of
// incs and decs added, or failure after reporting what it cannot count.
mlir::FailureOr<std::pair<unsigned, unsigned>> insertCounts(mlir::func::FuncOp fn,
                                                            Counting &counting);

// The verifier of the owned stage (Verify.cc): every reference is consumed
// exactly once on every path, no value is used after its last reference is
// gone, and every idr.reuse builds in a cell of its own size.
mlir::LogicalResult verifyOwned(mlir::ModuleOp module);

} // namespace idr::ownership
