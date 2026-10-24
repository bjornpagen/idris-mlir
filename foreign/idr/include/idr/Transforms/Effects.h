// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one writer of rows.
//
// A function's row is the least solution of: its own part (the
// derivation's fold of its body), joined with the row of each function it
// calls. Over the program graph's components, callees first, one pass is
// exact: every member of a component reaches every other through calls,
// so its members share one row, the join of their own parts and of the
// rows of the components they call. A cycle of ours may run forever unless
// Idris proved every function on it (everyProved). A cycle of one, a call
// of the function itself, is in its own part already, the derivation's
// reading of the call, so its check holds it too; a cycle of several is
// the graph's, not any one function's, so the writer adds it and no
// function's check can. The record follows the same way: a write through a
// parameter passed on to a callee's written parameter is a write through
// the caller's; what a callee puts into a lifetime passed on is put into
// the caller's, with no bound where the call lies on a cycle or in a
// region that runs again.
//
// Rows are equal to their derivation right after the writer, and cover it
// after every other pass. The writer runs where effects change: in
// defunctionalization's decision (atoms alone, over the label solve's
// reading of each label's run), after each of the optimizer's components,
// at the end of every program pass that adds effects, and last before the
// lowering. A nested pass that adds effects runs after `widen`, which
// gives every function and call at least the atoms it may add.
#ifndef IDR_TRANSFORMS_EFFECTS_H
#define IDR_TRANSFORMS_EFFECTS_H

#include "idr/Analysis/Effects.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"
#include "idr/Support/Match.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
#include <cstdint>
#include <span>
#include <utility>

namespace idr::rows {

// Every function's row and record, and every call's copy, equal to their
// derivation: what each changed is written, nothing else. Reads each body
// in parallel, joins over `graph`'s components serially, writes each
// function and its calls in parallel. Every attribute a record needs is
// made serially, before the parallel writes. What the join reads is added
// to `work`, which the pass that writes reports as its own.
void write(ProgramOp program, const solver::ProgramGraph &graph, solver::Work &work);

// Every function and call holds at least `atoms` besides its own, and no
// parameter is known untouched: what a nested pass that adds effects runs
// after, so its own functions' checks hold while it runs. The writer
// narrows them again.
void widen(ProgramOp program, effects::Row atoms);

// One component's members, when the optimizer finishes the component:
// every callee outside it is final, and each call of one holds the
// callee's row already (the optimizer writes a caller's calls when its turn
// begins, copyCallee), so the members' rows read only their own bodies.
// `editor`, the optimizer's thawed graph, resolves a callee to its id.
void writeComponent(std::span<const solver::Member> members, const solver::Editor &editor);

// Every function's row from its own part, the cycle's divergence included:
// over `graph`'s components callees first, each component's members given
// one row, the union of their own parts and of the rows of the functions
// they call, every one of which outside the component is final by then.
// Each member and each of its calls read is added to `work`.
IndexVector<solver::FunctionId, effects::Row>
joinComponents(const solver::ProgramGraph &graph, IndexVector<solver::FunctionId, effects::Row> own,
               solver::Work &work);

namespace detail {
// The divergence of each cycle of the graph no single proof of Idris's
// covers, joined into each member's own part. A lone member's call of
// itself put it there already; its edge to itself may also be a run of
// labels, in the label solve's graph, which no call of its body shows.
void addCycles(const solver::ProgramGraph &graph, IndexVector<solver::FunctionId, effects::Row> &own);
} // namespace detail

// Every function's atoms, each body read by its own copy of `reader`: what
// defunctionalization's decision asks before it converts, its reader
// reading each label's run as calls of the labels the label solve gives
// it, and `graph` holding those runs as calls. Before counting no
// parameter admits a part, so the atoms are the whole row. What the join
// reads is added to `work`.
template <CallReader R>
IndexVector<solver::FunctionId, effects::Row> solveAtoms(const solver::ProgramGraph &graph,
                                                       const R &reader,
                                                       mlir::MLIRContext &context,
                                                       solver::Work &work) {
  IndexVector<solver::FunctionId, effects::Row> own = graph.table(effects::Row{});
  IdRange<solver::FunctionId> functions = graph.functions();
  mlir::parallelFor(&context, 0, functions.size(), [&](std::size_t at) {
    solver::FunctionId f = functions[at];
    R mine = reader;
    own[f] = derive(graph.op(f), mine).atoms;
  });
  detail::addCycles(graph, own);
  return joinComponents(graph, std::move(own), work);
}

} // namespace idr::rows

// What the two writers, the program's and a component's, read of each body
// and how its parts join: shared by both, so declared once, here.
namespace idr::rows::writer {

// A lifetime a call passes on to its callee's put parameter `theirs`, and
// what it is of the caller's own record.
struct PassedOn {
  std::uint32_t theirs;
  RecordPart mine;
};

// A call as a writer reads it: its callee; the callee's number among the
// functions the writer marks writes over, counted once by its reader; where
// a write through each of its write-admitting operands lands for the
// caller, in order; and each lifetime it passes on to a put parameter.
struct Site {
  FunctionCallOpInterface call;
  solver::FunctionId callee;
  std::uint32_t ordinal;
  Runs runs;
  llvm::SmallVector<Lands, 2> writes;
  llvm::SmallVector<PassedOn, 1> puts;
};

// What one body does by itself, and its calls, read once.
struct Own {
  Derived derived;
  llvm::SmallVector<Site, 4> sites;
};

// `call` of `fn`, which `callee` names and `ordinal` numbers, its operands
// read by `fold`: the part each parameter admits, by the callee's own
// signature, since its index arguments change no grade and no lifetime's
// kind.
Site siteOf(FunctionCallOpInterface call, solver::FunctionId callee, std::uint32_t ordinal,
            FuncOp fn, const Fold &fold, Runs runs);

class WriteNodes;
struct WriteTag {
  using Minter = WriteNodes;
};
using WriteNode = Id<WriteTag>;

// The write-admitting parameters of a set of functions, one node each:
// function `owner`'s parameter at `position` among its write-admitting
// ones. Owners are numbered by whoever builds the nodes.
class WriteNodes {
public:
  explicit WriteNodes(std::span<const std::uint32_t> writable) {
    first.reserve(writable.size());
    for (std::uint32_t count : writable) {
      first.push_back(total);
      total += count;
    }
  }
  Count<WriteNode> count() const { return Count<WriteNode>(total); }
  WriteNode at(std::uint32_t owner, std::uint32_t position) const {
    return WriteNode(first[owner] + position);
  }

private:
  footprint::Vector<std::uint32_t> first;
  std::uint32_t total = 0;
};

// One function of a set the marking reads: its number among the set, and
// what its body does by itself.
struct Owner {
  std::uint32_t ordinal;
  const Own *own;
};

// Every write-admitting parameter written through: each written by its own
// body, then each passed on to a written parameter of a callee, marked from
// callee to caller.
BitSet<WriteNode> markWrites(const WriteNodes &nodes, llvm::ArrayRef<Owner> owners);

// A write through a callee's written parameter, passed something the
// caller neither acquired nor was given through a write-admitting
// parameter of its own, writes memory a caller of the caller may see.
effects::Row writesElsewhere(llvm::ArrayRef<Site> sites, const WriteNodes &nodes,
                             const BitSet<WriteNode> &written);

// The positions a function never writes through, as its record lists them;
// none, as absence says.
mlir::DenseI32ArrayAttr untouchedOf(mlir::MLIRContext *context, std::uint32_t owner,
                                    std::uint32_t writable, const WriteNodes &nodes,
                                    const BitSet<WriteNode> &written);

// The bounded amounts of a function's put parameters, as its record lists
// them; none, as absence says.
PutBoundsAttr boundsOf(mlir::MLIRContext *context, llvm::ArrayRef<Amount> puts);

// What a site passes on into the caller's put parameters: the callee's
// amount, or no bound where the callee lies on the caller's cycle or the
// call in a region that runs again.
template <std::invocable<std::uint32_t> TheirsOf>
void passOn(llvm::MutableArrayRef<Amount> mine, const Site &site, TheirsOf &&theirsOf) {
  for (const PassedOn &passed : site.puts)
    idr::match(
        passed.mine,
        [&](PutPart part) {
          Amount theirs = theirsOf(passed.theirs);
          if (!theirs.none() && site.runs == Runs::Repeatedly)
            theirs = Amount::unbounded();
          mine[part.position] = mine[part.position].plus(theirs);
        },
        [](WritePart) {}, [](NoPart) {});
}

} // namespace idr::rows::writer

#endif // IDR_TRANSFORMS_EFFECTS_H
