// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The verifier of a program, at the stage its idr.program says: the
// program's rules (its data types, its effects and the cells its recycles
// give), which idr.program's region verifier runs once it has checked the
// root and every op of the program is verified, on one thread, when the
// module is read and after every pass on the program; and the rules of one
// function at its program's stage, which idr.func's region verifier runs
// after its body's ops are, in parallel with every other function's. A
// function's rules read the function, the types its values have and its
// program's stage, and nothing else of the module, so no pass rewriting a
// sibling function races them; nothing keeps a table or an answer beyond
// one verify. The knot rule is no verifier's: it refuses the user's program,
// so it is the body of a check pass (knots).
#ifndef IDR_IR_VERIFY_H
#define IDR_IR_VERIFY_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"

#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Operation.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Support/LLVM.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>
#include <variant>

namespace idr {

class TypeGraph;

namespace verify {

// The rules of the program: its target's pointers are the runtime's
// words; each function's declared effects cover what its body may do, its
// own part (bodyEffect) and its calls'; a memo sum is held only in a box;
// past the higher stage containment in place is acyclic and no data type
// has a field of a closure or a suspension; and once the program is
// counted a buffer's global is aligned as a cell's element is, and every
// idr.cell.recycle gives a cell of the size of its token's. A lowered
// program is upstream's functions and globals, which hold no rule of ours.
mlir::LogicalResult program(ProgramOp program);

// No array can hold a reference to itself, by the cycles of `graph`, else
// the refusal `cycle`: the body of idr-knots, which runs once every closure
// is a constructor of a sum.
mlir::LogicalResult knots(ProgramOp program, const TypeGraph &graph);

// The rules of one function at its program's stage, each read through
// stageFacts: what the stage lets its values hold (past higher no closure
// or suspension; an own or excl grade only once the stage gives grades, and
// from then no plain value of ours that holds references); closures' flow
// while they exist; every linear value used at most once on every path; and
// once the program is counted, the counting rule (owned).
mlir::LogicalResult function(FuncOp fn);

// Every value used once by its type (isLinearByType: a world, a
// destination, a cell) or by its grade (an !idr.lin) is used at most once
// on every path of `fn`.
mlir::LogicalResult linearity(FuncOp fn);

// The rules of the frame (Lifetimes.h) on `fn`'s types, at every stage:
// what a value of the frame reaches is of the frame, and none escapes.
mlir::LogicalResult lifetimes(FuncOp fn);

// The owned stage's rule for one function: each reference is consumed
// exactly once on every path, a cell's by the idr.cell.init that fills it,
// and a view is used only while what it was read from holds its reference.
mlir::LogicalResult owned(FuncOp fn);

// Whether at most one region of `branch` runs: each returns straight to
// the op, as a match's or an scf.if's do, and none to another region.
bool alternatives(mlir::RegionBranchOpInterface branch);

// What a value is to the owned walk, decided once from its type and its
// definition (OwnedWalk::roleOf). Four cases, each with its own state in the
// walk: it holds no reference the walk follows (none at all, or static data
// no count reaches); it holds one of its own, as its type says (an owned
// grade, or a cell, which its init consumes); it holds a fresh one its plain
// type cannot say, which an allocation of upstream's buffer ops or
// idr.own.give hands to its one use (the idr.own.adopt that takes it over,
// or the store it is given to); or it is a view, which holds none and lives
// while what it was read from does.
enum class Role { Untracked, Owned, Carried, View };

// The walk of one function in the owned stage: the references each value
// in scope holds, followed along the ops. Where an op forwards values
// (forwardedValues: a region branch's entry, a terminator of its regions),
// an owned value moves on with its reference and a view passes on as a view
// of what its owner became on the same edge. The regions of an op that
// return straight to it are alternatives, which must agree on the values
// from outside where they meet again; any other op's regions may run again
// or after one another, and each leaves the values from outside as it found
// them. It lives for one verify of one function, and so do its answers.
class OwnedWalk {
public:
  explicit OwnedWalk(FuncOp fn);

  mlir::LogicalResult check();

private:
  // The references an Owned or Carried value holds here.
  struct References {
    int count;
  };
  // The values that hold the references a view was read from: it is alive
  // while each of them is. None: it is alive throughout, a borrowed
  // parameter, which its caller keeps alive, or read from one.
  struct Viewing {
    llvm::SmallVector<mlir::Value, 1> owners;
  };
  // A value's state, by its role; an Untracked value has none.
  using Slot = std::variant<References, Viewing>;

  // The references a value held before a change, so that each region of
  // an op starts from the same state.
  struct Change {
    mlir::Value value;
    std::optional<References> old;
  };

  // What an op with regions forwards, and to where: for each value a
  // forwarded operand becomes (a result, or an argument of a region's
  // entry block), the operands forwarded into it; for each forwarded
  // operand, the values it becomes, one per successor.
  struct Forwarding {
    llvm::MapVector<mlir::Value, llvm::SmallVector<mlir::OpOperand *, 2>> into;
    llvm::DenseMap<mlir::OpOperand *, llvm::SmallVector<mlir::Value, 2>> to;

    void add(mlir::Operation *from);
    bool forwards(mlir::OpOperand &operand) const { return to.contains(&operand); }
  };

  // What a value is to the walk, and the state in scope (Owned.cpp).
  Role roleOf(mlir::Value value);
  int references(mlir::Value value) const;
  const Viewing *viewing(mlir::Value value) const;
  bool alive(mlir::Value value);
  void set(mlir::Value value, int count);
  void viewOf(mlir::Value value, llvm::ArrayRef<mlir::Value> from);
  void undo(size_t mark);
  llvm::MapVector<mlir::Value, int> changesSince(size_t mark);
  mlir::InFlightDiagnostic fail(mlir::Operation &op, mlir::Value value, const llvm::Twine &what);
  mlir::LogicalResult consume(mlir::Operation &op, mlir::Value value);
  mlir::LogicalResult use(mlir::Operation &op, mlir::Value value);
  mlir::LogicalResult settled(mlir::Block &block, mlir::Operation &at);

  // One op without regions (OwnedOps.cpp).
  mlir::LogicalResult visit(mlir::Operation &op);
  mlir::LogicalResult regrade(mlir::Operation &op);
  mlir::LogicalResult loaded(mlir::Operation &op);
  mlir::LogicalResult exclusive(mlir::Operation &op);
  mlir::LogicalResult operands(mlir::Operation &op,
                               const llvm::DenseSet<mlir::OpOperand *> &forwarded);
  bool takesCarried(mlir::OpOperand &operand);
  llvm::SmallVector<mlir::Value> readBy(mlir::Operation &op,
                                        const llvm::DenseSet<mlir::OpOperand *> &forwarded);
  mlir::LogicalResult make(mlir::Operation &op, mlir::Value value,
                           llvm::ArrayRef<mlir::Value> from);

  // Blocks and the ops with regions (OwnedRegions.cpp): whether the walk
  // reaches the end of what it walked, or every path in it ends first (in
  // ub.unreachable after a crash), after which nothing is accounted for.
  enum class Reach { End, Ends };
  mlir::FailureOr<Reach> walk(mlir::Block &block);
  mlir::FailureOr<Reach> walkRegions(mlir::Operation &op);
  mlir::LogicalResult enter(mlir::Operation &op, const Forwarding &forwarding,
                            mlir::Value input, llvm::ArrayRef<mlir::Value> reads,
                            llvm::function_ref<bool(mlir::Operation *)> given);
  mlir::FailureOr<llvm::SmallVector<mlir::Value>>
  ownersAcross(mlir::Operation &op, const Forwarding &forwarding, mlir::OpOperand &operand,
               mlir::Value input);
  bool payload(const Forwarding &forwarding, mlir::Value input);
  mlir::LogicalResult backEdges(mlir::Operation &op, const Forwarding &forwarding,
                                const llvm::SmallPtrSetImpl<mlir::Operation *> &reached);

  FuncOp fn;
  // Each value's role, once asked.
  llvm::DenseMap<mlir::Value, Role> roles;
  // The state of each value in scope that has one: the references of an
  // Owned or Carried value, the owners of a View.
  llvm::DenseMap<mlir::Value, Slot> slots;
  llvm::SmallVector<Change> log;
};

} // namespace verify
} // namespace idr

#endif // IDR_IR_VERIFY_H
