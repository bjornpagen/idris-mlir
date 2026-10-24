// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one call graph of an idr.program, from defunctionalization, where
// every call becomes a direct call, to idr-lower, after which nothing reads
// one (the native stack's bound reads LLVM's own graph of the final
// module). It is an index of the program's calls, every member of the
// call family: it holds no fact the calls do not hold, and nothing reads a
// call's callee another way.
//
// It wraps the analysis manager's one mlir::CallGraph and never builds a
// second: a function's id is its node's dense index, and the components
// are upstream's, bottom-up, as ranges of one permutation. On top it holds
// what upstream cannot, as tables indexed by those ids: each function's
// row of distinct (callee, standing) with how many calls have it, the
// callers, the cycles, which calls run on a frame and the components that
// run one, and the editor through which the one restructuring pass that
// changes calls edits it.
//
// No row holds a call op: a pass that recreates a call without changing
// its callee or standing (counting rewrites operands) leaves the graph exact,
// and no pointer into freed IR can exist. A client that needs its own
// function's calls walks its own body.
//
// Frozen, it is read through const references only, from any thread. A
// restructuring pass thaws it into an Editor, which takes its rows; each
// function's row is replaced whole by the turn that owns that function;
// freezing writes the rows back and recomputes the callers and the
// components from them, with no walk of the IR. The partition is never
// patched in place.
//
// Its tables, its editor's rows and its table of names are the
// footprint's, so the footprint of the pass that builds or edits it counts
// them. The table of names is the one place a callee's name becomes an id:
// MLIR refers to a symbol by name, which no walk numbers.
#ifndef IDR_ANALYSIS_SOLVER_PROGRAMGRAPH_H
#define IDR_ANALYSIS_SOLVER_PROGRAMGRAPH_H

#include "idr/Analysis/Solver/Components.h"
#include "idr/Analysis/Solver/Graph.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Support/TypeID.h"
#include "llvm/ADT/ArrayRef.h"

#include <cstdint>
#include <optional>
#include <span>

namespace idr::solver {

class ProgramGraph;
class Editor;

namespace detail {
// The one minter of function and component ids: the graph when it is built
// or frozen, and its editor when a pass inserts a function.
class GraphIds;
} // namespace detail

struct FunctionTag {
  using Minter = detail::GraphIds;
};
struct SccTag {
  using Minter = detail::GraphIds;
};
// A function of the program: its call graph node's dense index, fixed for
// the graph's life and never written into the IR.
using FunctionId = Id<FunctionTag>;
// A component of the calls; ids increase callees first.
using SccId = Id<SccTag>;

namespace detail {
class GraphIds {
  friend class solver::ProgramGraph;
  friend class solver::Editor;
  static FunctionId function(std::uint32_t at) { return FunctionId(at); }
  static SccId scc(std::uint32_t at) { return SccId(at); }
  static Count<FunctionId> functions(std::uint32_t n) { return Count<FunctionId>(n); }
  static Count<SccId> sccs(std::uint32_t n) { return Count<SccId>(n); }
};
} // namespace detail

// One distinct (callee, standing) of a function, and how many of its
// calls have it. The standing is the call's member of the call family,
// read off the call.
struct Call {
  FunctionId callee;
  CallStanding standing;
  std::uint32_t sites;
};

class ProgramGraph {
public:
  // Reads `program`, an idr.program, through its analysis manager's call
  // graph: each function's calls in parallel, each into its own slot.
  ProgramGraph(mlir::Operation *program, mlir::AnalysisManager &am);

  // The id space: every table of the graph is this long. Ids with no
  // function (upstream's external nodes, an erased function) are gaps,
  // with empty rows and no component.
  Count<FunctionId> size() const { return count; }
  // The program's functions, in id order.
  IdRange<FunctionId> functions() const { return IdRange<FunctionId>(live); }
  idr::FuncOp op(FunctionId f) const { return ops[f]; }
  // The one place a callee's symbol becomes an id: resolved once per call
  // per build. The verifier proved every callee is a function of the
  // program before any pass ran.
  FunctionId id(mlir::FlatSymbolRefAttr callee) const;
  FunctionId id(idr::FuncOp fn) const;

  std::span<const Call> callees(FunctionId f) const {
    return std::span<const Call>(rows).subspan(rowStart[f.index()],
                                               rowStart[f.index() + 1] - rowStart[f.index()]);
  }
  // The distinct functions with a call of `f`.
  IdRange<FunctionId> callers(FunctionId f) const {
    return IdRange<FunctionId>(::idr::detail::Rows{callerStart, callerRows}.row(f.index()));
  }
  // How many idr.call ops name `f`.
  std::uint32_t callSites(FunctionId f) const { return sites[f.index()]; }
  bool callsItself(FunctionId f) const { return selfCalls.test(f); }

  // Every component, callees first: a component's id is below the id of
  // every component that calls into it.
  Count<SccId> sccCount() const { return detail::GraphIds::sccs(sccOrder()); }
  SccId sccOf(FunctionId f) const { return detail::GraphIds::scc(scc[f.index()]); }
  IdRange<FunctionId> members(SccId c) const {
    return IdRange<FunctionId>(std::span<const std::uint32_t>(order).subspan(
        sccStart[c.index()], sccStart[c.index() + 1] - sccStart[c.index()]));
  }
  // Every function, components callees first, each component's members
  // contiguous.
  IdRange<FunctionId> bottomUp() const { return IdRange<FunctionId>(order); }
  // Whether a member of component `c` may have more than one frame live at
  // a time: the component is a cycle, by isCycle, a lone member's edge to
  // itself its self call. Every reader of the program's cycles asks this.
  bool onCycle(SccId c) const {
    return isCycle(members(c), [&](FunctionId lone) { return callsItself(lone); });
  }
  bool onCycle(FunctionId f) const { return onCycle(sccOf(f)); }
  // Whether a call made in component `from`, of `callee`, standing as
  // `standing`, runs on a frame: it returns to its caller (returnsToCaller),
  // and its callee is a member of `from`, so the caller waits on the cycle
  // while the callee runs, and idr-frames moves what follows the call into
  // a frame of its own. The one place a call is decided to run on a frame:
  // the components that do are laid from it, and every pass that treats
  // such a call apart asks it (idr-frames, which splits its function
  // there; the lifetimes' planner and loans, and borrow inference, which
  // stand no region around it). The caller's component is given rather
  // than read off the call: idr-frames asks it of code it has moved into
  // functions the graph does not hold.
  bool runsOnFrame(SccId from, FunctionId callee, CallStanding standing) const;
  bool runsOnFrame(SccId from, FunctionCallOpInterface call) const {
    return runsOnFrame(from, id(call.getCalleeAttr()), call.getStanding());
  }
  // Whether component `c` runs a call on a frame: a call a member makes
  // runs on one. Asked of every component before any member's body is
  // read, so it is laid once with the components, from the rows they were
  // laid on: as exact as the rows, which nothing writes while the graph is
  // frozen.
  bool runsCallsOnFrames(SccId c) const { return framed.test(c); }
  // Whether a call made in component `from`, of `callee`, stays on the
  // stack of frames `from` runs its calls on: the component runs calls on
  // frames and the callee is a member, whether the call runs on a frame or
  // is its caller's last act, which passes the stack on. Every function on
  // that stack takes the component's lifetimes in one arrangement.
  bool onFrameStack(SccId from, FunctionId callee) const {
    return runsCallsOnFrames(from) && sccOf(callee) == from;
  }

  // A fact per function, sized by the id space.
  template <class T>
  IndexVector<FunctionId, T> table(const T &init = T{}) const {
    return IndexVector<FunctionId, T>(count, init);
  }

  // The rows taken out for one restructuring pass; the graph holds none
  // until the editor is frozen back into it.
  Editor thaw() &;

private:
  friend class Editor;
  ProgramGraph() = default;
  std::uint32_t sccOrder() const { return static_cast<std::uint32_t>(sccStart.size() - 1); }
  // Rows sorted and merged, then everything derived from them alone:
  // callers, sites, self calls.
  void lay(footprint::Vector<footprint::Vector<Call>> perFunction);
  // The components of the rows, where upstream's are not given.
  void partition();
  // What the rows and the components decide together, laid after both
  // wherever the components came from: the components with a call that
  // runs on a frame.
  void frame();

  Count<FunctionId> count = detail::GraphIds::functions(0);
  footprint::Vector<std::uint32_t> live;
  IndexVector<FunctionId, idr::FuncOp> ops{detail::GraphIds::functions(0)};
  footprint::DenseMap<mlir::StringAttr, FunctionId> byName;

  footprint::Vector<std::uint32_t> rowStart{0};
  footprint::Vector<Call> rows;
  footprint::Vector<std::uint32_t> callerStart{0}, callerRows;
  footprint::Vector<std::uint32_t> sites;
  BitSet<FunctionId> selfCalls{detail::GraphIds::functions(0)};

  footprint::Vector<std::uint32_t> order;
  footprint::Vector<std::uint32_t> sccStart{0};
  footprint::Vector<std::uint32_t> scc;
  BitSet<SccId> framed{detail::GraphIds::sccs(0)};
};

// The editable form, held by the one restructuring pass that thawed it.
// Inserting and erasing are the pass's serial steps (between its waves);
// a row is replaced whole by the turn that owns its function, so turns on
// distinct functions write disjoint rows. Freezing consumes the editor.
class Editor {
public:
  Editor(Editor &&) = default;
  Editor(const Editor &) = delete;
  Editor &operator=(const Editor &) = delete;

  // A function the pass made: its id is the next one, never a reused one.
  FunctionId insert(idr::FuncOp fn);
  // A function the pass erased: its row goes, and so do the edges into it.
  void erase(FunctionId f);
  // `f`'s row, replaced whole: a (callee, standing) may appear once, with its
  // count of calls.
  void setCallees(FunctionId f, llvm::ArrayRef<Call> row);
  std::span<const Call> callees(FunctionId f) const { return rows[f.index()]; }
  // The function `callee` names, which the verifier proved one.
  FunctionId id(mlir::FlatSymbolRefAttr callee) const;
  // The function `callee` names, or none: a copy the pass has made and not
  // yet inserted is no function of the graph until it is.
  std::optional<FunctionId> find(mlir::FlatSymbolRefAttr callee) const;
  // The id space so far: the graph's, and every function inserted since.
  Count<FunctionId> size() const {
    return detail::GraphIds::functions(static_cast<std::uint32_t>(rows.size()));
  }

  void freeze() &&;

private:
  friend class ProgramGraph;
  explicit Editor(ProgramGraph &home) : home(&home) {}

  ProgramGraph *home;
  footprint::Vector<footprint::Vector<Call>> rows;
  footprint::Vector<idr::FuncOp> ops;
  footprint::DenseMap<mlir::StringAttr, FunctionId> byName;
};

// `fn`'s row as its calls now are, what a restructuring pass gives
// Editor::setCallees for each function it makes or changes: each distinct
// (callee, standing) once with how many of its calls have it, in the one
// order every row has, whoever writes it. A call of a copy the editor does
// not hold yet is in no row until the copy is inserted and its caller's row
// written again.
footprint::Vector<Call> rowOf(idr::FuncOp fn, const Editor &editor);

// A member of a component as a per-component solve reads it: the optimizer's
// components grow by its made nodes and merge by its waits, so a solve is
// handed its members rather than reading the frozen partition.
struct Member {
  FunctionId id;
  idr::FuncOp fn;
};

} // namespace idr::solver

MLIR_DECLARE_EXPLICIT_TYPE_ID(idr::solver::ProgramGraph)

#endif // IDR_ANALYSIS_SOLVER_PROGRAMGRAPH_H
