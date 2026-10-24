// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The verifier of a program, at the stage its idr.program says: the
// program's rules (its target, its buffers' globals and the cells its
// recycles give), which idr.program's region verifier runs once it has
// checked the root and every op of the program is verified, on one thread,
// when the module is read and after every pass on the program; and the
// rules of one function at its program's stage, which idr.func's region
// verifier runs after its body's ops are, in parallel with every other
// function's. A function's rules read the function, the types its values
// have and its program's stage, and nothing else of the module, so no pass
// rewriting a sibling function races them; nothing keeps a table or an
// answer beyond one verify. The knot rule is no verifier's: it refuses the
// user's program, so it is a check pass's (idr-knots).
#ifndef IDR_IR_VERIFY_H
#define IDR_IR_VERIFY_H

#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Operation.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Support/LLVM.h"
#include "llvm/ADT/STLExtras.h"

#include <concepts>
#include <memory>

namespace idr {

namespace verify {

// The rules of the program: its target's pointers are the runtime's
// words; and once the program is counted, a buffer's static data is aligned
// as a cell's elements are, to at most a word, and every idr.cell.recycle
// gives a cell of its token's layout. A lowered program is upstream's
// functions and globals, which hold no rule of ours.
mlir::LogicalResult program(ProgramOp program);

// The rules of one function at its program's stage: what the stage lets its
// values hold, past the higher stage no value whose type reaches a closure
// or a suspension; closures' flow while they exist; the one linearity rule;
// and the lifetimes' rules (LifetimeRules), each a rule of its one walk but
// the linearity rule, which counts each value's uses.
mlir::LogicalResult function(FuncOp fn);

// Where upstream's ops stand in a program whose functions are ours, a rule
// of each function's one walk (families::walkFunction) and of the
// program's own ops: an upstream op the specification admits stands only
// at the stages its record gives it, read off the op's class through the
// generated table (AdmittedStages.h.inc); and through the frontend's stage
// (admitted::listedThrough) every upstream op is admitted, since the
// frontend writes upstream's ops only by the builders of admitted ones.
// Past it, bufferization hands the arrays to upstream's models, whose own
// ops no list names and no stage bounds. An op of ours is held to its
// family's stages, never an admitted record's. Every op after the
// frontend's is a pass's, and the frontend writes only admitted ops legal
// at its stage, so an op this rule fails at is an internal error, never a
// refusal of the program.
class Admission {
public:
  explicit Admission(Stage stage) : stage(stage) {}

  // Before the ops of a region: nothing.
  mlir::LogicalResult enter(mlir::Operation *, mlir::Region &) { return mlir::success(); }
  // At `op`, before its regions.
  mlir::LogicalResult check(mlir::Operation *op) const;
  // After the ops of a region: nothing.
  void leave() {}

private:
  Stage stage;
};

// The one linearity rule of `fn`, after every pass. A value its grade uses
// once is used at most once on every path, field by field: a field read
// takes that field alone, an op that ends the value's owner (EndsOwner)
// takes its cell alone and no field, and any other use takes the whole
// value, so reading two fields is no second use, nor is reading fields and
// then ending the owner, while reading one twice is. The IR's linearity
// is affine, as Idris's quantity 1 lets a value go unused on a path that
// ends the run. A value its type uses once (a cell, a destination, a
// package) is used exactly once on every path that goes on, at every
// stage. Once its program is counted, a value that holds a reference of its
// own (counted) moves it on exactly once on every path that goes on, by the
// rule counting places by (referenceAt, Counting.h), a part read from an
// owner with none of its own (ownership::ownerOfPart) is given up with its
// owner and moved on by no use, and a reuse token is never used many
// times. Uses are counted on the worst path: the most over a match's
// alternatives, the sum over regions that run one after another, twice for
// a region that runs again; a path that ends the run gives nothing up.
mlir::LogicalResult linearity(FuncOp fn);

// The lifetimes' rules of one function, a rule of its one walk
// (families::walkFunction), each local, none following a def-use chain but
// a loan's: no
// lifetime is a terminator's operand or a result of an op that gives none;
// every value an op makes that is scoped has its lifetime stated, open
// where the op stands, and outlived by each scoped value the op holds (a
// value an op passes through lives where its operand does or in a lifetime
// that one encloses; a constructor's scoped fields all outlive it); a
// value that flows from one lifetime into another lives in one that
// outlives it (by dominance: the binders open where the walk stands, and
// between parameters the bounds the signature states), at a call into the
// lifetimes its callee's signature names and at the return into those its
// own names; inside a stack lifetime nothing is put into an older cursor;
// every slot lies in its lifetime's own run; no cell of a lifetime holds a
// counted field; every use of a lifetime keeps the frame-limited rule,
// its cells bounded until its end or each reachable from what is still to
// be used; and every loan to upstream's ops (idr.carrier) keeps to its
// lifetime: its aliases, followed through upstream's alias interfaces since
// a bare alias names no lifetime, never leave the region that defines it,
// are never returned, stored as a write's value or adopted by an op of
// ours, and once references are counted the value lent is given up only
// outside that region. The walk enters and leaves each region, so what
// encloses an op is kept on a stack as the walk goes, never found by
// walking up.
class LifetimeRules {
public:
  explicit LifetimeRules(FuncOp fn);
  ~LifetimeRules();
  LifetimeRules(const LifetimeRules &) = delete;
  LifetimeRules &operator=(const LifetimeRules &) = delete;

  // Before the ops of `region`, a region of `op`.
  mlir::LogicalResult enter(mlir::Operation *op, mlir::Region &region);
  // At `op`, before its regions.
  mlir::LogicalResult check(mlir::Operation *op);
  // After the ops of the region last entered.
  void leave();

  // What the rule keeps as the walk goes: opaque here, declared for the
  // rule's own units in idr/IR/Lifetimes/Rules.h.
  struct State;

private:
  std::unique_ptr<State> state;
};

// The two proofs a lifetime that is put into again and again rests on,
// which the verifier checks and the decide step meets before it writes a
// lifetime, so both read one rule.

// Whether `made`, a value made in a lifetime parameter something is put
// into, is taken on every path into what its function gives back there:
// it has a user in its own block, which every path through it reaches, that
// is its function's return at a result living in the lifetime (`returned`
// of the result's position), a terminator carrying it into a value living
// there, or an op with no region and no call that makes a value living
// there (`lives`) of it. Each value so made is asked the same, so the
// values made in the lifetime form chains that end at the return, one hop
// each, and none is left behind in the caller's memory on any path.
template <std::predicate<mlir::Value> Lives, std::predicate<unsigned> Returned>
bool takenIntoResult(mlir::Value made, Lives &&lives, Returned &&returned) {
  mlir::Block *home = llvm::isa<mlir::OpResult>(made)
                          ? made.getDefiningOp()->getBlock()
                          : llvm::cast<mlir::BlockArgument>(made).getOwner();
  for (mlir::OpOperand &use : made.getUses()) {
    mlir::Operation *user = use.getOwner();
    if (user->getBlock() != home)
      continue;
    if (llvm::isa<ReturnOp>(user)) {
      if (returned(use.getOperandNumber()))
        return true;
      continue;
    }
    if (user->hasTrait<mlir::OpTrait::IsTerminator>()) {
      bool carried = false;
      forwardedValues(user, [&](mlir::OpOperand &forwarded, mlir::Value input) {
        carried = carried || (&forwarded == &use && lives(input));
      });
      if (carried)
        return true;
      continue;
    }
    if (user->getNumRegions() == 0 && !llvm::isa<mlir::CallOpInterface>(user) &&
        llvm::any_of(user->getResults(), [&](mlir::Value result) { return lives(result); }))
      return true;
  }
  return false;
}

// Whether `root`, made by an op at the top of a lifetime's block, is used
// again, on every path, after each op from it up to `last` (of that block)
// that may acquire memory: then at every allocation there, everything the
// root reaches is still to be used, so nothing it holds is dead in the
// lifetime while memory is taken. A use is of the root, or of a value that
// is the root (a region's argument a match binds of it, a cast of it); a use
// inside a region covers only what comes before it in that region's block,
// since another path may not run it.
bool usedAfterEveryAllocation(mlir::Value root, mlir::Operation *last);

} // namespace verify
} // namespace idr

#endif // IDR_IR_VERIFY_H
