// The verifier of a program: the module's rules, which the dialect runs
// from `idr.program` before the ops inside are verified, and the rules of
// one function, which idr.func's region verifier runs after its body's ops
// are, in parallel with every other function's. Nothing here keeps a table
// or an answer beyond one verify, so the verifiers of different functions
// share nothing they write.
#ifndef IDR_IR_VERIFY_H
#define IDR_IR_VERIFY_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Ownership.h"

#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Operation.h"
#include "mlir/Support/LLVM.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>
#include <utility>
#include <variant>

namespace idr {

class TypeGraph;

namespace verify {

// The rules of the module: one root, every sum or box type naming a
// declaration of its kind, containment through unboxed sums acyclic, and
// no array that can hold a reference to itself.
mlir::LogicalResult program(mlir::ModuleOp module);

// No array can hold a reference to itself, by the cycles of `graph`.
mlir::LogicalResult knots(mlir::ModuleOp module, const TypeGraph &graph);

// Whether `op` defines a value of grade own or excl: a result, or an
// argument of a block of one of its regions. A function is in the owned
// stage exactly when it or an op in it does.
bool definesOwned(mlir::Operation *op);

// One pre-order walk of a function's body: the place of every op in it,
// every value of quantity one in walk order, and whether the function is
// in the owned stage. Pre-order numbers the ops of one region in block
// order, so comparing two places orders the ops of a region without
// touching a block's order cache, which other threads' verifiers read.
class Numbering {
public:
  explicit Numbering(FuncOp fn);

  unsigned place(mlir::Operation *op) const { return places.lookup(op); }
  llvm::ArrayRef<mlir::Value> linearValues() const { return linear; }
  bool owned() const { return stage; }

private:
  llvm::DenseMap<mlir::Operation *, unsigned> places;
  llvm::SmallVector<mlir::Value> linear;
  bool stage = false;
};

// Every value of quantity one, a world or an !idr.lin, is used at most
// once on every path of the function `numbering` walked.
mlir::LogicalResult linearity(const Numbering &numbering);

// The owned stage's rule for one function: each reference is consumed
// exactly once on every path, a view is used only while its owner holds
// its reference, and every idr.reuse builds in a cell of its own size.
mlir::LogicalResult owned(FuncOp fn);

// The walk of one function in the owned stage: the references each value
// in scope holds, followed along the ops, through the regions of a match
// as alternatives that must agree where they meet again, and through the
// loops over arrays and the scf loops idr-tail-loops makes. It lives for
// one verify of one function, and so do its answers: each declaration it
// needs is found once, and the cells' layouts are built at most once, at
// the first reuse.
class OwnedWalk {
public:
  explicit OwnedWalk(FuncOp fn);

  mlir::LogicalResult check();

private:
  // The references a value held before a change, so that a match's
  // regions start from the same state.
  struct Change {
    mlir::Value value;
    std::optional<int> old;
  };

  // What the walk asks of the module, once per type (Owned.cpp).
  DataOp declaration(mlir::Type type);
  CtorOp constructor(mlir::SymbolRefAttr ctor);
  bool counts(mlir::Type type);

  // The references in scope (Owned.cpp).
  bool tracked(mlir::Value value);
  bool isView(mlir::Value value);
  bool alive(mlir::Value value);
  void set(mlir::Value value, int references);
  void define(mlir::Value value, int references, mlir::Value owner = mlir::Value(),
              bool borrowed = false);
  void undo(size_t mark);
  llvm::MapVector<mlir::Value, int> changesSince(size_t mark);
  mlir::InFlightDiagnostic fail(mlir::Operation &op, mlir::Value value, const llvm::Twine &what);
  mlir::LogicalResult consume(mlir::Operation &op, mlir::Value value);
  mlir::LogicalResult use(mlir::Operation &op, mlir::Value value);
  mlir::LogicalResult settled(mlir::Block &block, mlir::Operation &at);

  // One op (Owned.cpp).
  mlir::LogicalResult visit(mlir::Operation &op);
  ownership::Use useKind(mlir::OpOperand &operand);
  bool reachesOnlyAtoms(mlir::Value value);
  mlir::LogicalResult fits(ReuseOp reuse);

  // Blocks and the ops with regions (OwnedRegions.cpp).
  mlir::FailureOr<bool> walk(mlir::Block &block);
  mlir::FailureOr<bool> walkRegions(mlir::Operation &op);
  mlir::FailureOr<bool> walkMatch(mlir::Operation &op, mlir::Value scrutinee);
  mlir::FailureOr<bool> walkArrayLoop(mlir::Operation &op,
                                      llvm::ArrayRef<std::pair<mlir::Value, bool>> operands,
                                      mlir::Region &body, mlir::ValueRange results);

  // The scf loops (OwnedLoops.cpp).
  mlir::Value slotOwner(mlir::Operation *loop, unsigned slot);
  void passOn(mlir::Value value, mlir::Value owner);
  mlir::FailureOr<bool> walkLoop(mlir::scf::WhileOp loop);
  std::variant<unsigned, mlir::Value> viewOf(mlir::Value value, mlir::Block &before);
  mlir::FailureOr<bool> walkFor(mlir::scf::ForOp loop);

  FuncOp fn;
  IdrDialect::StackAttrHelper stack;
  llvm::DenseMap<mlir::Type, DataOp> declarations;
  llvm::DenseMap<mlir::Type, bool> counted;
  std::optional<Layouts> layouts;
  llvm::DenseMap<mlir::Value, int> held;
  llvm::DenseMap<mlir::Value, mlir::Value> owners;
  llvm::SmallVector<Change> log;
  // For each loop, the owner of each borrowed slot.
  llvm::DenseMap<mlir::Operation *, llvm::SmallVector<mlir::Value>> loops;
  // The match results that pass a borrowed slot on, with its owner.
  llvm::DenseMap<mlir::Value, mlir::Value> passedOn;
};

} // namespace verify
} // namespace idr

#endif // IDR_IR_VERIFY_H
