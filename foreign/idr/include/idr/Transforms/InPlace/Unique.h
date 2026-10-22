// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the units of the local rule share (lib/Transforms/InPlace/): each
// body read once and the solve of the local rule over the program
// (Unique.cpp), and the write of what it proves (UniqueResults.cpp), which
// idr-unique-results runs and idr-in-place runs after it grades.
//
// A body is its values, numbered by the solver's walk (Locals), and the
// terms the edges its ops declare give each of them (ownership::forEachTerm),
// so the solve reads numbers and no IR. What the rule may raise is a cell
// of a data family, no memo label's (a force writes its cells while
// references to them live), that its op makes new or that is forwarded
// into, and that flows only through linear positions. A call's result is
// its callee's derived claim; a value an op keeps as itself is its
// operand's where it flows on linearly; a part an op of ours that infers
// its results reads or takes out is what the read table gives it, as the
// op's inference does; every other value is what its type says. The write
// runs each such op's inference again, and lends each holder an op of
// upstream's reads to it (lendReads), as that op takes the bare carrier.
#ifndef IDR_TRANSFORMS_INPLACE_UNIQUE_H
#define IDR_TRANSFORMS_INPLACE_UNIQUE_H

#include "idr/Analysis/Ownership/Local.h"
#include "idr/Analysis/Solver/Extraction.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Id.h"

#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Value.h"

#include <cstdint>
#include <optional>

namespace idr::unique {

using solver::FunctionId;

// The numbering of a body's values: the solver's, in its one walk, whose
// one map from a value lives while a body is read, or written, and goes
// with it.
struct LocalTag {
  using Minter = solver::Numbering<LocalTag>;
};
using Locals = solver::Numbering<LocalTag>;

// A value of one body, by its place in Locals.
using Local = std::uint32_t;
inline constexpr Local noLocal = ~Local{0};

// What a value is to the solve.
enum class Role : std::uint8_t {
  // What its type claims, which nothing here changes.
  Typed,
  // Raised to what the rule proves from its terms, where it is kept.
  Raised,
  // Its operand's claim: a position that keeps its operand's value, and
  // flows on linearly.
  Same,
  // Its callee's derived claim: a call's result.
  Called,
  // What the grade's read table gives it from what it is read or taken out
  // of: a result its op infers so (a field a take or a read gives), which
  // the write infers again.
  Read,
};

struct Node {
  Role role;
  // What its type claims as a source of the rule (ownership::claimOfSource).
  Unique typed;
  ownership::Origin origin;
  // Its terms, [first, last) of the body's; for Same, `first` is its
  // operand; for Called, its call among the body's.
  std::uint32_t first;
  std::uint32_t last;
};

// A call's result: its callee and which of its results.
struct CallResult {
  FunctionId callee;
  std::uint32_t index;
};

// Whether a body's terminator returns, giving its operands back, or ends
// the run, giving nothing.
enum class Returns : std::uint8_t { Yes, No };

struct Body {
  FuncOp fn;
  // One per value, by its Local.
  footprint::Vector<Node> nodes;
  footprint::Vector<ownership::Term<Local>> terms;
  // Who reads each value, as a compressed row: the values whose terms name
  // it, and a Same value of its operand.
  footprint::Vector<std::uint32_t> readerStart;
  footprint::Vector<Local> readers;
  footprint::Vector<CallResult> calls;
  Returns returns = Returns::No;
  // The value each result returns.
  footprint::Vector<Local> returned;
  // Each operand of an op that infers its results from it (a read, a
  // take): a value whose claim that op reads.
  footprint::Vector<Local> inferring;
  // What the last solve of the body proved of each value.
  footprint::Vector<Unique> claims;
};

// The claim each function gives back, per result.
using Results = IndexVector<FunctionId, footprint::Vector<Unique>>;

// Whether a value of `type` is one the rule may raise, as a result or as a
// value: a cell of a data family that is no memo label's, freed by its count
// or its lifetime, claiming less than everything.
bool raisable(mlir::Type type);

// The solve over `graph`'s components, callees first, on the one static
// schedule: every function's body read and solved, and the claim each of
// its results gives back. Its value evaluations are added to `work`.
struct Solution {
  IndexVector<FunctionId, std::optional<Body>> bodies;
  Results results;
};
Solution solve(const solver::ProgramGraph &graph, mlir::MLIRContext &context,
               solver::Work &work);

// The local rule solved over `graph`'s program and written into its types:
// each value it proves raised where its claim is kept, each result its
// function gives so, each op that infers its results inferred again, and
// each use of a raised value that takes less met. A claim already in the
// types is a source of the rule, so what a pass graded before it (a
// parameter graded at the boundary) reaches every value it is taken or
// read into at a linear position. Returns how many results it raised; its
// value evaluations are added to `work`.
unsigned raiseClaims(const solver::ProgramGraph &graph, mlir::MLIRContext &context,
                     solver::Work &work);

} // namespace idr::unique

#endif // IDR_TRANSFORMS_INPLACE_UNIQUE_H
