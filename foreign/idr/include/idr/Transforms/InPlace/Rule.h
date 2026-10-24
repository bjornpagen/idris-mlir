// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the units of idr-in-place share (lib/Transforms/InPlace/): a body's
// rebuild sites (Sites.cpp), the rule's terms read off one body
// (Chains.cpp), the program-wide solves over them (Rule.cpp), the pass that
// refuses (InPlace.cpp), the versions the verdict makes of each function
// (Versions.cpp) and their writer (Writer.cpp).
//
// A requirement asks a value's own cells to be unshared (Asks::Self, as far
// into its fields as the grade's fieldReach says), or everything it reaches
// (Asks::Deep). It is met where the value is used once and is made anew each
// time it is evaluated (a construction of values that meet it in turn), moved
// out of a value that meets it, given back by a callee whose every return
// meets it (given what the callee's parameters must meet, its summary), or is
// a parameter of its function, whose callers then owe it. A value used many
// times claims nothing of its sharing before references are counted, so it
// meets none itself; a cast that enters it into a position as its one use,
// every other use of what holds its cell a read that ends before the cast,
// meets it where the cell of the value it was entered from does (a region's
// argument entered from one place holds the cell of the value entered:
// ownership::entryOf, the verifier's rule and idr-unique-results' too). An
// element an op of upstream's reads out of an array meets only what its type
// claims, which no pass of ours raises. Where a requirement reaches what can
// meet none (a value used again where the use that requires it may still
// hold it, one used many times otherwise, a copy, a value no flow explains),
// it reaches a cause. A requirement starts where a cell is rebuilt, asking
// what its family's promise asks, and at the boundary: a parameter of
// quantity 1 whose family's values carry the promise by construction (an own
// cell holds a buffer) is owed it by every caller.
#ifndef IDR_TRANSFORMS_INPLACE_RULE_H
#define IDR_TRANSFORMS_INPLACE_RULE_H

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/Analysis/Ownership/Local.h"
#include "idr/Analysis/Ownership/Walks.h"
#include "idr/Analysis/Solver/Extraction.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Id.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Value.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/SmallVector.h"

#include <array>
#include <compare>
#include <cstdint>
#include <optional>
#include <vector>

namespace idr::inplace {

using ownership::Asks;
using solver::FunctionId;

// Why a value cannot meet a requirement, and the op that shows it.
enum class Why : std::uint8_t {
  // Used again where the use that requires it may still hold it: a value
  // used many times that a cast enters into the position that requires it,
  // another of whose uses is no read that ends before the cast.
  UsedAgain,
  // Used many times, and reached otherwise than by a cast that enters it as
  // its one use, or with nothing here to say what its cell holds (a
  // parameter, a value forwarded into a region from several places or into
  // one that runs again): before references are counted it claims nothing
  // of its sharing.
  UsedMany,
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

// A value of one body, by its place in the solver's walk
// (solver::inWalkOrder): the numbering every unit of the rule reads, whose
// one map from a value to its place lives while a body is read, and the
// order of the values of a Walk, so a place names its value in every copy.
struct BodyValueTag {
  using Minter = solver::Numbering<BodyValueTag>;
};
using BodyValue = Id<BodyValueTag>;
using BodyValues = solver::Numbering<BodyValueTag>;

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

// What a callee keeps of each parameter: whether some passage of it, here
// or in a callee, outlives the call (ownership::passageOf). A read by a
// callee that keeps nothing ends with the call.
class Keeps {
public:
  explicit Keeps(const solver::ProgramGraph &graph) : kept(graph.table<llvm::BitVector>()) {}
  ownership::Lent of(FunctionId fn, unsigned param) const {
    return kept[fn].test(param) ? ownership::Lent::Kept : ownership::Lent::Ends;
  }
  IndexVector<FunctionId, llvm::BitVector> kept;
};

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

// A rebuild site by the places in the walk of its function's original body
// of the argument its case binds the cell to and of its construction's
// result, which name it in every copy: the match and the case are the
// argument's.
struct SiteAt {
  std::uint32_t taken;
  std::uint32_t construction;
};

// A case region that takes apart a cell of an in-place family bound at
// quantity 1, and the construction of the same family and constructor that
// rebuilds it there; what the family's promise asks of the cell taken
// apart; and the site's places.
struct RebuildSite {
  DataMatchOp match;
  unsigned caseIndex;
  DataConOp construction;
  mlir::BlockArgument taken;
  Asks asks;
  SiteAt at;
};

// The rebuild sites of `fn`, whose values `values` numbers: in each case
// region of a cell of an in-place family whose value is bound at quantity
// 1, the first construction of the family's same constructor in the
// region's pre-order not paired yet, outer cells first, none inside a
// region that may run again.
llvm::SmallVector<RebuildSite> rebuildSites(FuncOp fn, const BodyValues &values);

// The rebuild of the cell case `caseIndex` of `match` binds as its argument
// `taken`, by `construction`: a take of the cell at the case's entry that
// opens the arrays the cell holds (idr.count.take_open), whose fields and
// arrays the case's reads and openers of the cell become, and an
// idr.token.rebuild that consumes the take's token in place of the
// construction.
void rebuild(DataMatchOp match, unsigned caseIndex, unsigned taken, DataConOp construction);

// The reading of one body by the rule: which value meets a requirement
// given what, each walk iterative. Its one map is the body's numbering,
// which goes with it; what it keeps of each value is in tables by number.
class Chains {
public:
  Chains(FuncOp fn, const solver::ProgramGraph &graph, const Summaries &summaries,
         const Keeps &keeps);

  const BodyValues &numbering() const { return values; }

  // Where a requirement `asks` on `value` ends. Each (value, strength) is
  // read once per reading, its ends kept.
  llvm::SmallVector<Target> targets(mlir::Value value, Asks asks);

  // A call result a requirement reached, with its strength: what the
  // callee's version must give back. The call is named by its place among
  // the body's calls (ownership::forEachCall), and `results` is how many
  // it gives, so what is asked of each can be kept beside it.
  struct Demand {
    std::uint32_t place;
    unsigned results;
    unsigned result;
    Asks asks;
  };
  // Every value a requirement reaches, by its place, with its strength, and
  // every call result among them: what the verdict grades.
  struct Reached {
    footprint::Vector<std::pair<std::uint32_t, Asks>> values;
    footprint::Vector<Demand> demands;
  };
  void trace(mlir::Value value, Asks asks, Reached &reached);

  llvm::ArrayRef<Cause> causes() const { return causeList; }

private:
  struct Step {
    mlir::Value value;
    Asks asks;
  };
  // A cause of the body, numbered once.
  Target cause(mlir::Operation *at, Why why);
  // What a requirement on `value` reaches next by the rule of its
  // definition: the targets it ends at here, the steps it takes, the call
  // results it reaches; a value used many times ends it, a cause.
  void define(mlir::Value value, Asks asks, llvm::SmallVectorImpl<Target> &ends,
              llvm::SmallVectorImpl<Step> &next, llvm::SmallVectorImpl<Demand> &demands);
  // The same, past its uses: what its cell's definition reaches.
  void defineCell(mlir::Value value, Asks asks, llvm::SmallVectorImpl<Target> &ends,
                  llvm::SmallVectorImpl<Step> &next, llvm::SmallVectorImpl<Demand> &demands);
  // What a requirement on the result of `enter`, a cast that enters a value
  // used many times into the position that requires it, reaches: the cell
  // of the value it was entered from where every other use of what holds
  // that cell is a read that ends before the cast (ownership::entryOf), the
  // use that may still hold it otherwise.
  void entered(LinCastOp enter, Asks asks, llvm::SmallVectorImpl<Target> &ends,
               llvm::SmallVectorImpl<Step> &next, llvm::SmallVectorImpl<Demand> &demands);

  // Whether a (value, strength) is on the reading's stack, or reached by
  // the trace being read; each is cleared when it is done.
  enum class Mark : std::uint8_t { No, Yes };
  // A run of `knownEnds`.
  struct Run {
    std::uint32_t first;
    std::uint32_t count;
  };
  static unsigned slot(Asks asks) { return static_cast<unsigned>(asks); }

  FuncOp fn;
  const solver::ProgramGraph &graph;
  const Summaries &summaries;
  const Keeps &keeps;
  footprint::Vector<Cause> causeList;
  BodyValues values;
  // The operands forwarded into each value, as rows by number.
  footprint::Vector<std::uint32_t> forwardStart;
  footprint::Vector<mlir::OpOperand *> forwards;
  // Each call's place among the body's calls, by its first result.
  IndexVector<BodyValue, std::optional<std::uint32_t>> callAt;
  // The ends of each (value, strength) read whole, no cycle cut short.
  IndexVector<BodyValue, std::array<std::optional<Run>, 2>> known;
  footprint::Vector<Target> knownEnds;
  IndexVector<BodyValue, std::array<Mark, 2>> open;
  IndexVector<BodyValue, std::array<Mark, 2>> seen;
};

// Whether a requirement of `asks` on a value reaches the field `anchor`
// names, which holds a value of `fieldValue`: a field that holds
// references, which a read from a value meeting the requirement still
// claims something of (a deep claim every field, a self claim each field
// its own cells reach).
inline bool reachesField(Asks asks, const FlowAnchor &anchor, mlir::Type fieldValue) {
  return holdsReferences(fieldValue) && ownership::asksOfPart(asks, ownership::reachAt(anchor));
}

// Every function's summaries, its components callees first, each solved to
// its least fixpoint: a requirement on a result asks only more of the
// parameters, or becomes impossible, as the component's summaries grow.
// Each body read in a round is a transfer, added to `work`.
// What every callee keeps of each of its parameters: a backward marking of
// the program's parameters from the passages that outlive a call.
Keeps keepsOf(const solver::ProgramGraph &graph);

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
// rebuild sites and the parameters owed at the boundary, back along every
// call whose argument's requirement reaches a parameter of its caller; a
// requirement that reaches a cause instead is a refusal.
Verdict decide(const solver::ProgramGraph &graph, const Summaries &summaries,
               const Keeps &keeps);

// A version of a function: what each result gives back (none where nothing
// is asked), what each parameter is owed, and, by their positions in the
// one walk of the body, the claim each value is graded with, what each call
// asks of its callee's results and the version of the callee it goes to.
struct Version {
  llvm::SmallVector<std::optional<Asks>, 1> results;
  llvm::SmallVector<std::optional<Asks>, 4> params;
  footprint::Vector<std::optional<Asks>> grades;
  footprint::Vector<llvm::SmallVector<std::optional<Asks>, 1>> demands;
  footprint::Vector<std::uint32_t> targets;
};

// The one walk of a body, by place: its values in the solver's walk, whose
// places BodyValues gives, and its calls. A copy is a clone of its
// original, so the walk numbers both alike.
struct Walk {
  explicit Walk(FuncOp fn) {
    solver::inWalkOrder(fn, [&](mlir::Value value) { values.push_back(value); });
    ownership::forEachCall(fn, [&](FunctionCallOpInterface call) { calls.push_back(call); });
  }
  llvm::SmallVector<mlir::Value> values;
  llvm::SmallVector<FunctionCallOpInterface> calls;
};

// What a verdict makes of each function: its versions, the original first
// and then each grade copy a call asks for, none for a function it leaves
// as it is; and its rebuild sites by position.
struct Versions {
  explicit Versions(const solver::ProgramGraph &graph)
      : of(graph.table<footprint::Vector<Version>>()),
        sites(graph.table<llvm::SmallVector<SiteAt, 1>>()) {}

  IndexVector<FunctionId, footprint::Vector<Version>> of;
  IndexVector<FunctionId, llvm::SmallVector<SiteAt, 1>> sites;
};

// The versions a verdict with no refusal makes (Versions.cpp): what each
// body's own starts reach (its rebuild sites, the arguments its callees are
// owed) graded in its original; then each call that asks a claim of a
// callee's results sent to the version that gives it, the original where
// the callee's obligations cover what that needs, else a copy keyed by its
// results, whose own returns are traced in turn. It ends: an owner's keys
// are finite, and each is made once.
Versions versionsOf(const solver::ProgramGraph &graph, const Summaries &summaries,
                    const Keeps &keeps, const Verdict &verdict);

// The versions written into the program (Writer.cpp): its copies, its
// grades, its calls, its rebuilds, the local rule carrying each claim on,
// its positions met, and every row again, whose transfers are added to
// `work`. Fails where a grade copy's name is another function's, reported
// at the function.
mlir::LogicalResult writeVerdict(ProgramOp program, solver::ProgramGraph &graph,
                                 const Versions &versions, mlir::SymbolTable &symbols,
                                 solver::Work &work);

} // namespace idr::inplace

#endif // IDR_TRANSFORMS_INPLACE_RULE_H
