// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr-rc decides before it rewrites anything: which parameters are
// borrowed (Borrows), where each function's dead boxes are taken apart and
// which constructors get their cells (Reuses), and which owned values hold
// the only reference to every cell they reach (Exclusivity); and the
// vocabulary of placement those analyses and idr-rc's passes share: where a
// value is used, where it dies, and which values hold references.
//
// A value holds references when its type says so (ValueFactsTypeInterface:
// a string, a big, a box, a buffer, a reuse token, or an unboxed sum with a
// slot of one of these). In the owned stage its grade says what it holds:
//   - owned (`!idr.own<T>`): one reference of its own, which exactly one
//     use on every path consumes. Results of calls, constructors,
//     primitives, matches and loops are owned, and so are the parameters
//     that borrow inference leaves owned;
//   - a view (the view grade, `view(T)`; a buffer's view and static data
//     stay plain): none; it lives as long as what it was read from. A
//     borrowed parameter lives as long as the call, a field of a
//     constructor (an idr.field, or a field a match region binds), a view
//     of a buffer (a subview, a cast, a reshape) and an idr.borrow as long
//     as the value it was read from, and static data (a constant, whose
//     cells no count reaches) forever. An element read from a buffer is
//     never left a view: the buffer may be written while the view is read.
// idr.dup gives a view one reference of its own, which one use consumes.
//
// Every analysis here is read-only after its constructor, so the function
// passes idr-rc runs nested may read it from any thread.
#ifndef IDR_ANALYSIS_OWNERSHIP_H
#define IDR_ANALYSIS_OWNERSHIP_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Block.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Value.h"
#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>

namespace idr::ownership {

// The op of `block` that holds `use`, when that op is strictly after
// `after` (anywhere in the block when `after` is null). Null when the use
// is not in the block, or is `after` or earlier. The one walk of a use up
// to the block that holds it.
mlir::Operation *heldIn(mlir::Block &block, mlir::OpOperand &use, mlir::Operation *after);

// The ops of `block` after `after` (from its start when null) that use
// `value`, themselves or in their regions, in order. The second form takes
// the uses as a caller sees them, which may be fewer than the value's own.
llvm::SmallVector<mlir::Operation *> usersIn(mlir::Value value, mlir::Block &block,
                                             mlir::Operation *after);
llvm::SmallVector<mlir::Operation *> usersIn(llvm::ArrayRef<mlir::OpOperand *> uses,
                                             mlir::Block &block, mlir::Operation *after);

// Whether each run of `op` enters exactly one of its regions, once, and
// leaves it back to `op`, as RegionBranchOpInterface says: a match, an
// scf.if with both branches, an scf.index_switch. Counting moves a value
// from outside into each such region, which consumes or drops it there.
// Any other op with regions may run one many times or none (a loop, a
// branch with no else, a structured op on buffers): it holds a value from
// outside for as long as it runs, and its regions only read it.
bool decides(mlir::Operation *op);

// Whether `value` is used after `op`, where the reference it holds must
// still be there: later in the block of `op`, or after an op that holds
// that block, up to the block that defines it; and anywhere inside an op
// that does not decide (a loop) and uses the value inside, which holds it
// for as long as it runs. A use of a view of the value is not a use of it:
// whether the value outlives the view is what the caller asks.
bool usedAfter(mlir::Value value, mlir::Operation *op);

// Where a value whose uses are `uses`, which `block` holds a reference to,
// dies on each path of the block: at its start when nothing there uses it,
// after its last use, or inside each region of that use when it decides.
// Nowhere on a path whose last use consumes it. Calls `at` with each point.
// `graded` is the table through which a call's consumption is read from its
// callee's grade; null before borrow inference has graded the signatures,
// when every call may consume its arguments.
void whereDies(llvm::ArrayRef<mlir::OpOperand *> uses, mlir::Block &block,
               mlir::SymbolTable *graded,
               llvm::function_ref<void(mlir::Block &, mlir::Block::iterator)> at);
void whereDies(mlir::Value value, mlir::Block &block, mlir::SymbolTable *graded,
               llvm::function_ref<void(mlir::Block &, mlir::Block::iterator)> at);

// Whether `use` is at `at` in `block` or after it, itself or inside an op
// there: where a take placed at `at` has already run.
bool fromPoint(mlir::Block &block, mlir::Block::iterator at, mlir::OpOperand &use);

// The fields of a box whose uses are `uses`, built by the constructor
// `tag`, that a take of it gives: the arguments of `fields` (the case
// region that bound them, when one did) and the results of the idr.field
// reads of the box, each with its index.
void eachField(llvm::ArrayRef<mlir::OpOperand *> uses, unsigned tag, mlir::Block *fields,
               llvm::function_ref<void(mlir::Value, unsigned)> f);

// The first read of a box that no match takes apart and whose every use
// reads a field of one constructor, the point from which the box's
// constructor is known in that read's block; null for any other value. The
// second form asks of a value of `type` whose uses are `uses`.
FieldOp onlyReads(mlir::Value box);
FieldOp onlyReads(mlir::Type type, llvm::ArrayRef<mlir::OpOperand *> uses);

// The values whose cell graph exclusivity follows: owned boxes and unboxed
// sums (whose slots may hold boxes), and the tokens of their cells.
bool followed(mlir::Value value);

// Whether a value of `type` holds references, as the type answers.
bool counted(mlir::Type type);

// Whether `value` holds references: its type does, and it is not static.
bool tracked(mlir::Value value);

// Whether a value of `type` is a memo cell, the box of a memo sum: the one
// cell that changes while references to it live, as a force writes its
// state. So its constructor is not known under a match on it, and it is
// never taken apart or built in; and no function takes one over, so the
// dispatch that writes it reads a view of its caller's.
bool isMemoCell(mlir::Type type);

// Whether `value` is an element read from a buffer that holds references.
// It takes a reference of its own where it is read: the buffer may be
// written while a view of the element would still be read, which a field
// of a cell never is. So it is never a view, and the buffer it was read
// from needs nothing for it.
bool isCountedElement(mlir::Value value);

} // namespace idr::ownership

namespace idr {

// Borrow inference: which parameters of the program's functions are
// borrowed, a view of the caller's value, and which are owned. A parameter
// that a reuse site takes apart is owned, so it reads Reuses.
class Borrows {
public:
  enum class Param : uint8_t { Untracked, Borrowed, Owned };

  Borrows(mlir::Operation *program, mlir::AnalysisManager &am);

  // Unless it, the Reuses it read and the SymbolTable are all preserved.
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;

  // Each parameter of `fn`.
  llvm::ArrayRef<Param> params(FuncOp fn) const;
  // Whether each result of `fn` holds references, and so is owned.
  llvm::ArrayRef<bool> countedResults(FuncOp fn) const;
  // How many parameters that hold references are borrowed.
  unsigned borrowed() const { return numBorrowed; }

private:
  llvm::DenseMap<mlir::Operation *, llvm::SmallVector<Param>> paramsOf;
  llvm::DenseMap<mlir::Operation *, llvm::SmallVector<bool>> resultsOf;
  unsigned numBorrowed = 0;
};

// Reset/reuse insertion's decisions: in each function, the dead boxes that
// are taken apart where they die and the constructors after each that are
// built in its cell. Each function's sites depend on its body, the data
// types and the layouts alone.
class Reuses {
public:
  // A take and the constructors that reuse its cell. The take goes right
  // after `after` in `block`, or at the block's start when `after` is null;
  // `fields` is the case region that bound the box's fields, or null. The
  // box is `box`, or, when that is null, the field `field` of the take of
  // the function's site `from`, an earlier one: a take before this one gave
  // the box's reads a field of its own, which is what this one takes apart.
  // The box was built by the constructor `tag` of `data`.
  struct Site {
    mlir::Value box;
    unsigned from = 0, field = 0;
    DataType data;
    unsigned tag = 0;
    mlir::Block *block = nullptr;
    mlir::Operation *after = nullptr;
    mlir::Block *fields = nullptr;
    llvm::SmallVector<ConOp> cons;
  };

  Reuses(mlir::Operation *program, mlir::AnalysisManager &am);

  // Unless it, the SymbolTable and the Layouts are all preserved.
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;

  // The sites of `fn`, in the order they are rewritten.
  llvm::ArrayRef<Site> sites(FuncOp fn) const;

private:
  llvm::DenseMap<mlir::Operation *, llvm::SmallVector<Site>> sitesOf;
};

// Exclusivity, solved once on MLIR's solver and kept as tables: which
// owned values hold the only reference to every cell their cell graph
// reaches that a take could hand out, which blocks run, who calls each
// function and what each returns from. No solver outlives the constructor.
class Exclusivity {
public:
  // What is known of a value's cell graph: nothing yet (the optimistic
  // start), a tree of cells this value alone reaches, or cells another
  // reference may reach.
  enum class Sharing : uint8_t { Unknown, Exclusive, Shared };

  Exclusivity(mlir::Operation *program, mlir::AnalysisManager &am);

  // Unless it and the SymbolTable are preserved.
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;

  // Whether the solve failed; nothing else here is then meaningful.
  bool failed() const { return unsolved; }

  // What the solve found of `value`; Unknown for a value it never reached.
  Sharing of(mlir::Value value) const;
  // Whether the grade excl goes on `value`: it is followed, exclusive, and
  // no share forgot that; a change of quantity follows its operand.
  bool proves(mlir::Value value) const;
  // Whether the solve found that `block` may run.
  bool live(mlir::Block *block) const { return liveBlocks.contains(block); }
  // Every call of `fn`, when the solve sees them all.
  std::optional<llvm::ArrayRef<mlir::Operation *>> callers(FuncOp fn) const;
  // Every return of `fn` the solve reached, when it sees them all from a
  // call of it.
  std::optional<llvm::ArrayRef<mlir::Operation *>> returns(FuncOp fn) const;

private:
  bool unsolved = false;
  llvm::DenseMap<mlir::Value, Sharing> sharing;
  llvm::DenseSet<mlir::Block *> liveBlocks;
  llvm::DenseMap<mlir::Operation *, llvm::SmallVector<mlir::Operation *>> callersOf;
  llvm::DenseMap<mlir::Operation *, llvm::SmallVector<mlir::Operation *>> returnsOf;
};

} // namespace idr

#endif // IDR_ANALYSIS_OWNERSHIP_H
