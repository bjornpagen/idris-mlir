// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the units of idr-in-place share (lib/Transforms/InPlace/): the rule's
// terms read off one body (Chains.cpp), the program-wide solves over them
// (Rule.cpp), the pass that refuses (InPlace.cpp) and the writer of the
// verdict (Writer.cpp).
//
// A requirement asks a value's own cells to be unshared (Asks::Self, as
// far into its fields as the grade's fieldReach says), or everything it
// reaches (Asks::Deep). It is met where the
// value is made anew each time it is evaluated (a construction of values
// that meet it in turn), moved out of a value that meets it, given back by a
// callee whose every return meets it (given what the callee's parameters
// must meet, its summary), or is a parameter of its function, whose callers
// then owe it: and the value must be used once on every path through the
// use that requires it, a read by a callee that keeps nothing of it before
// that use aside. Where a requirement reaches what can meet none (a value
// read again, a copy, a value no flow explains), it reaches a cause.
#ifndef IDR_TRANSFORMS_INPLACE_RULE_H
#define IDR_TRANSFORMS_INPLACE_RULE_H

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Id.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Value.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallBitVector.h"
#include "llvm/ADT/SmallVector.h"

#include <compare>
#include <cstdint>
#include <optional>
#include <vector>

namespace idr::inplace {

using ownership::Asks;
using solver::FunctionId;

// Why a value cannot meet a requirement, and the op that shows it.
enum class Why : std::uint8_t {
  // Used again where the use that requires it may still hold it.
  UsedAgain,
  // A reference to it is taken while another stays: a copy, static data,
  // a field shared into it.
  Shared,
  // No declared flow says what it holds.
  Unexplained,
  // A callee gives it back from a return that meets nothing.
  ReturnShared,
  // The program's entry is passed it from outside.
  FromOutside,
};

struct Cause {
  mlir::Operation *at;
  Why why;
};

// Where a requirement ends in one body: a parameter that must meet it, or a
// cause, by its number among the body's causes.
struct Target {
  enum class Kind : std::uint8_t { Parameter, Cause } kind;
  std::uint32_t index;
  Asks asks;
  friend auto operator<=>(const Target &, const Target &) = default;
};

// What result `index` of a function asks of its parameters when it must
// meet a requirement: none when some return can never meet it.
using Need = std::optional<llvm::SmallVector<std::pair<std::uint32_t, Asks>, 2>>;

// Every function's summaries, two per result (Self, Deep), each its Need.
class Summaries {
public:
  explicit Summaries(const solver::ProgramGraph &graph)
      : needs(graph.table<llvm::SmallVector<Need, 2>>()) {}

  const Need &of(FunctionId fn, unsigned result, Asks asks) const {
    return needs[fn][slot(result, asks)];
  }
  Need &of(FunctionId fn, unsigned result, Asks asks) { return needs[fn][slot(result, asks)]; }
  void reserve(FunctionId fn, unsigned results) {
    needs[fn].assign(results * 2, Need(std::in_place));
  }

private:
  static unsigned slot(unsigned result, Asks asks) {
    return result * 2 + static_cast<unsigned>(asks);
  }
  IndexVector<FunctionId, llvm::SmallVector<Need, 2>> needs;
};

// What a callee keeps of each parameter: whether some move of it, here or in
// a callee, outlives the call. A read by a callee that keeps nothing ends
// with the call.
class Keeps {
public:
  explicit Keeps(const solver::ProgramGraph &graph)
      : kept(graph.table<llvm::SmallBitVector>()) {}
  bool test(FunctionId fn, unsigned param) const { return kept[fn].test(param); }
  IndexVector<FunctionId, llvm::SmallBitVector> kept;
};

// A case region that takes apart a cell of an in-place family bound at
// quantity 1, and the construction of the same family and constructor that
// rebuilds it there, by their positions in the body's walk (the match among
// the body's ops, the case among its regions, the construction among the
// body's ops) so a copy of the body names them the same.
struct RebuildSite {
  DataMatchOp match;
  unsigned caseIndex;
  DataConOp construction;
  mlir::BlockArgument taken;
};

// The rebuild sites of `fn`: in each case region of a cell of an in-place
// family whose value is bound at quantity 1, the first construction of the
// family's same constructor in the region's pre-order not paired yet, outer
// cells first, none inside a region that may run again.
llvm::SmallVector<RebuildSite> rebuildSites(FuncOp fn);

// The rebuild of the cell case `caseIndex` of `match` binds as its argument
// `taken`, by `construction`: a take of the cell at the case's entry, whose
// fields the case's reads of the cell become, and an idr.token.rebuild that
// consumes the take's token in place of the construction.
void rebuild(DataMatchOp match, unsigned caseIndex, unsigned taken, DataConOp construction);

// The reading of one body by the rule: which value meets a requirement
// given what, each walk iterative. Its maps are the body's numbering and go
// with it.
class Chains {
public:
  Chains(FuncOp fn, const solver::ProgramGraph &graph, const Summaries &summaries,
         const Keeps &keeps);

  // Where a requirement `asks` on `value`, required by `use` (none for the
  // value a rebuild takes apart, all of whose uses must read parts), ends.
  // Each (value, strength) is read once per reading, its ends kept.
  llvm::SmallVector<Target> targets(mlir::Value value, Asks asks, mlir::OpOperand *use);

  // A call result a requirement reached, with its strength: what the
  // callee's version must give back.
  struct Demand {
    CallOp call;
    unsigned result;
    Asks asks;
  };
  // Every value a requirement reaches, with its strength, and every call
  // result among them: what the verdict grades.
  struct Reached {
    footprint::Vector<std::pair<mlir::Value, Asks>> values;
    footprint::Vector<Demand> demands;
  };
  void trace(mlir::Value value, Asks asks, Reached &reached);

  llvm::ArrayRef<Cause> causes() const { return causeList; }

private:
  struct Step {
    mlir::Value value;
    Asks asks;
    mlir::OpOperand *use;
  };
  // A cause of the body, numbered once.
  Target cause(mlir::Operation *at, Why why);
  // Whether `value` is used once on every path through `use`: every other
  // use reads a part of it, runs in a region that excludes `use`'s, or is
  // a read by a callee that keeps nothing of it, made before `use`; the
  // cause otherwise.
  std::optional<Target> usedOnce(mlir::Value value, mlir::OpOperand *use);
  // Whether `use` reaches only reads by callees that keep nothing of the
  // value, each made before `requirer`, through positions that hand the
  // value on as itself.
  bool borrowedBefore(mlir::OpOperand &use, mlir::Operation *requirer) const;
  // What a requirement on `value` reaches next by the rule of its
  // definition: the targets it ends at here, the steps it takes, the call
  // results it reaches.
  void define(mlir::Value value, Asks asks, llvm::SmallVectorImpl<Target> &ends,
              llvm::SmallVectorImpl<Step> &next, llvm::SmallVectorImpl<Demand> &demands);

  FuncOp fn;
  const solver::ProgramGraph &graph;
  const Summaries &summaries;
  const Keeps &keeps;
  footprint::Vector<Cause> causeList;
  llvm::DenseMap<mlir::Value, llvm::SmallVector<mlir::OpOperand *, 2>> forwardedInto;
  // The ends of each (value, strength) read whole, no cycle cut short.
  llvm::DenseMap<std::pair<mlir::Value, unsigned>, llvm::SmallVector<Target>> known;
};

// Whether a requirement of `asks` on a value reaches the field `anchor`
// names, which holds a value of `fieldValue`: a field that holds
// references, which a read from a value meeting the requirement still
// claims something of (a deep claim every field, a self claim each field
// its own cells reach).
inline bool reachesField(Asks asks, const FlowAnchor &anchor, mlir::Type fieldValue) {
  return holdsReferences(fieldValue) && ownership::asksOfPart(asks, ownership::reachAt(anchor));
}

// What every callee keeps of each of its parameters: a backward marking of
// the program's parameters from the moves that outlive a call.
Keeps keepsOf(const solver::ProgramGraph &graph);

// Every function's summaries, its components callees first, each solved to
// its least fixpoint: a requirement on a result asks only more of the
// parameters, or becomes impossible, as the component's summaries grow.
// Each body read in a round is a transfer, added to `work`.
Summaries summariesOf(const solver::ProgramGraph &graph, const Keeps &keeps, solver::Work &work);

// A call, or the value a rebuild takes apart, whose requirement reached a
// cause: the refusal, named at `at` in the user's terms.
struct Refusal {
  FuncOp caller;
  mlir::Operation *at;
  // The callee the call owes, none where the function rebuilds a value of
  // its own body.
  std::optional<FuncOp> callee;
  DataType family;
  Cause cause;
};

// The rule's verdict on a program: what each parameter's callers owe it,
// the rebuild sites, and the refusals, once per cause.
struct Verdict {
  explicit Verdict(const solver::ProgramGraph &graph)
      : obligations(graph.table<llvm::SmallVector<std::optional<Asks>, 4>>()),
        sites(graph.table<llvm::SmallVector<RebuildSite, 1>>()) {}

  IndexVector<FunctionId, llvm::SmallVector<std::optional<Asks>, 4>> obligations;
  IndexVector<FunctionId, llvm::SmallVector<RebuildSite, 1>> sites;
  std::vector<Refusal> refusals;
};

// The obligation closure, one marking of the program's parameters from the
// rebuild sites, back along every call whose argument's requirement reaches
// a parameter of its caller; a requirement that reaches a cause instead is
// a refusal.
Verdict decide(const solver::ProgramGraph &graph, const Summaries &summaries,
               const Keeps &keeps);

// A verdict with no refusal written into the program (Writer.cpp): its
// grades, its versions, its rebuilds, and every row again, whose transfers
// are added to `work`. Fails where a grade copy's name is another
// function's, reported at the function.
mlir::LogicalResult writeVerdict(ProgramOp program, solver::ProgramGraph &graph,
                                 const Summaries &summaries, const Keeps &keeps,
                                 const Verdict &verdict, mlir::SymbolTable &symbols,
                                 solver::Work &work);

} // namespace idr::inplace

#endif // IDR_TRANSFORMS_INPLACE_RULE_H
