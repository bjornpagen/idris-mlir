// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one call graph of an idr.program, from defunctionalization, where
// every call becomes a direct call, to idr-lower, after which nothing reads
// one (the native stack's bound reads LLVM's own graph of the final
// module). It is an index of the program's idr.call ops: it holds no fact
// the calls do not hold, and nothing reads a call's callee another way.
//
// It wraps the analysis manager's one mlir::CallGraph and never builds a
// second: a function's id is its node's dense index, and the components
// are upstream's, bottom-up, as ranges of one permutation. On top it holds
// what upstream cannot, as tables indexed by those ids: each function's
// row of distinct (callee, tail kind) with how many calls have it, the
// callers, the cycles, and the editor through which the one restructuring
// pass that changes calls edits it.
//
// No row holds a call op: a pass that recreates a call without changing
// its callee or kind (counting rewrites operands) leaves the graph exact,
// and no pointer into freed IR can exist. A client that needs its own
// function's calls walks its own body.
//
// Frozen, it is read through const references only, from any thread. A
// restructuring pass thaws it into an Editor, which takes its rows; each
// function's row is replaced whole by the turn that owns that function;
// freezing writes the rows back and recomputes the callers and the
// components from them, with no walk of the IR. The partition is never
// patched in place.
#ifndef IDR_ANALYSIS_SOLVER_PROGRAMGRAPH_H
#define IDR_ANALYSIS_SOLVER_PROGRAMGRAPH_H

#include "idr/Analysis/Solver/Graph.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Id.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Support/TypeID.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
#include <cstdint>
#include <span>
#include <vector>

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

// One distinct (callee, tail kind) of a function, and how many of its
// calls have it. The kind is the call's own fact, read off the call.
struct Call {
  FunctionId callee;
  TailKind kind;
  std::uint32_t sites;
};

class ProgramGraph {
public:
  // Reads `program`, an idr.program, through its analysis manager's call
  // graph: each function's calls in parallel, each into its own slot.
  ProgramGraph(mlir::Operation *program, mlir::AnalysisManager &am);
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const {
    return !pa.isPreserved<ProgramGraph>();
  }

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
    return IdRange<FunctionId>(detail::Rows{callerStart, callerRows}.row(f.index()));
  }
  // How many idr.call ops name `f`.
  std::uint32_t callSites(FunctionId f) const { return sites[f.index()]; }
  bool callsItself(FunctionId f) const { return selfCalls.test(f.index()); }

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
  // Whether `f` may have more than one frame live at a time: its component
  // has two members or more, or it calls itself.
  bool onCycle(FunctionId f) const {
    return members(sccOf(f)).size() > 1 || callsItself(f);
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
  // Rows sorted and merged, then everything derived from them: callers,
  // sites, self calls, and, unless upstream's components are given, the
  // components of the rows.
  void lay(std::vector<llvm::SmallVector<Call, 4>> perFunction);
  void partition();

  Count<FunctionId> count = detail::GraphIds::functions(0);
  std::vector<std::uint32_t> live;
  IndexVector<FunctionId, idr::FuncOp> ops{detail::GraphIds::functions(0)};
  llvm::DenseMap<mlir::StringAttr, FunctionId> byName;

  std::vector<std::uint32_t> rowStart{0};
  std::vector<Call> rows;
  std::vector<std::uint32_t> callerStart{0}, callerRows;
  std::vector<std::uint32_t> sites;
  llvm::BitVector selfCalls;

  std::vector<std::uint32_t> order;
  std::vector<std::uint32_t> sccStart{0};
  std::vector<std::uint32_t> scc;
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
  // `f`'s row, replaced whole: a (callee, kind) may appear once, with its
  // count of calls.
  void setCallees(FunctionId f, llvm::ArrayRef<Call> row);
  // `f` placed into `caller` (contification): `f`'s row joins `caller`'s,
  // and the calls of `f` from `caller` go.
  void moveInto(FunctionId f, FunctionId caller);
  std::span<const Call> callees(FunctionId f) const { return rows[f.index()]; }
  FunctionId id(mlir::FlatSymbolRefAttr callee) const;
  // The id space so far: the graph's, and every function inserted since.
  Count<FunctionId> size() const {
    return detail::GraphIds::functions(static_cast<std::uint32_t>(rows.size()));
  }

  void freeze() &&;

private:
  friend class ProgramGraph;
  explicit Editor(ProgramGraph &home) : home(&home) {}

  ProgramGraph *home;
  std::vector<llvm::SmallVector<Call, 4>> rows;
  std::vector<idr::FuncOp> ops;
  llvm::DenseMap<mlir::StringAttr, FunctionId> byName;
};

// What resolves a callee to its function: the frozen graph, or the editor
// of the restructuring pass that holds it thawed.
template <class N>
concept FunctionNames = requires(const N &names, mlir::FlatSymbolRefAttr callee) {
  { names.id(callee) } -> std::same_as<FunctionId>;
};

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
