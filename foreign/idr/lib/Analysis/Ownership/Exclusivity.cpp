// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Exclusivity: which counted values hold the only reference to every cell
// they reach, so that taking them apart reads no count and building in
// their cells tests nothing. In the owned stage a reference is copied only
// where an op takes one of a value it reads, so exclusivity is provenance:
// a value is exclusive when what moves into it is (a fresh value, a use
// moved whole or out of a part of an exclusive one, the field of an
// exclusive memo label, the result of a callee every return of which is),
// and is shared once a reference is taken of it or of a view of it, here or
// in a callee that takes one of the view it is passed. Static data is shared
// by definition and a scoped value is a view or a lifetime's cell, which no
// count tests: only a counted value whose grade leaves its sharing open
// is followed, and what QTT and freshness settle is already in the grade,
// written there before bufferization by the local rule (idr-unique-results),
// so the marking has no node for a value it proves.
//
// The answer is solved by context (ExclusivityAnalyses.cpp), over each body
// read once (ExclusivityGraph.cpp), and kept here as versions of each
// function: the general one, which the original symbol keeps, and a grade
// copy for each context that proves more. It refuses nothing: the in-place
// promise is decided before the optimizer (idr-in-place), and a value this
// solve leaves shared is tested where a take meets it. The step that reads
// the answer (idr-rc-exclusive) writes it into the types, and nothing else
// reads it.
#include "idr/Analysis/Ownership.h"

#include "idr/Analysis/Ownership/ExclusivityDetail.h"

#include <tuple>

using namespace mlir;

namespace idr {

// The solve's parts are named in full, `detail::exclusivity`: the namespace
// `exclusivity` alone is the public one of the followed values' ids.
Exclusivity::Exclusivity(Operation *program, AnalysisManager &am)
    : versionsOf(std::get<0>(reads(am)).table<footprint::Vector<Version>>()) {
  const solver::ProgramGraph &graph = std::get<0>(reads(am));
  detail::exclusivity::Anchors anchors;
  detail::exclusivity::shareStaticAnchors(cast<ProgramOp>(program), anchors);
  IndexVector<FunctionId, detail::exclusivity::Body> bodies =
      graph.table<detail::exclusivity::Body>();
  for (FunctionId fn : graph.functions()) {
    FailureOr<detail::exclusivity::Body> body =
        detail::exclusivity::readBody(graph.op(fn), graph, anchors);
    // A body that broke the representation's invariant was reported where
    // it broke; the pass that asked fails with it.
    if (failed(body)) {
      read = failure();
      return;
    }
    bodies[fn] = std::move(*body);
  }
  IndexVector<FunctionId, llvm::SmallBitVector> copied =
      detail::exclusivity::copiedViews(bodies, graph);
  detail::exclusivity::Solution solution =
      detail::exclusivity::solve(bodies, copied, anchors, graph);
  versionsOf = std::move(solution.versions);
  numContexts = solution.contexts;
  numCopies = solution.copies;
  numRounds = solution.rounds;
  numWork = solution.work;
}

} // namespace idr
