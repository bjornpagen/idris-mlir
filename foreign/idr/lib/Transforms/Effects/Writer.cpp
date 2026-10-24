// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one writer of rows over the program: each function's own part read
// in parallel, the parts joined over the program graph's components
// callees first, and every function and call that changed written back in
// parallel. The writes through parameters are one marking (the writers'
// shared parts); the atoms one union per component, callees first; the
// amounts one pass callees first, since a put passed along a cycle has no
// bound. Then the widening a nested pass that adds effects runs after.

#include "idr/Transforms/Effects.h"

#include "idr/Analysis/Effects.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <utility>

using namespace mlir;
using namespace idr;
using namespace idr::rows;
using namespace idr::rows::writer;
using solver::FunctionId;

namespace {

// The program writer's reader: a call is recorded, and its callee's row
// joined over the components, never read off the call, which may be
// stale. A function's number among the owners is its id's.
struct Calls {
  const solver::ProgramGraph &graph;
  llvm::SmallVectorImpl<Site> &sites;

  void call(CallOp call, Fold &fold, Runs runs) {
    FunctionId callee = graph.id(call.getCalleeAttr());
    sites.push_back(siteOf(call, callee, callee.index(), graph.op(callee), fold, runs));
  }
  Read other(Operation *, Fold &, Runs) { return Read::ByDeclaration; }
};

} // namespace

//===----------------------------------------------------------------------===//
// The program
//===----------------------------------------------------------------------===//

void rows::detail::addCycles(const solver::ProgramGraph &graph,
                             IndexVector<FunctionId, effects::Row> &own) {
  for (solver::SccId component : graph.sccCount().ids()) {
    if (!graph.onCycle(component))
      continue;
    IdRange<FunctionId> members = graph.members(component);
    if (provedTogether(llvm::map_range(members, [&](FunctionId f) { return graph.op(f); })))
      continue;
    for (FunctionId f : members)
      own[f] = own[f] | effects::Row{effects::Atom::divergence};
  }
}

// A callee in an earlier component holds its final row by the time its
// caller is read, since ids increase callees first; a callee in the
// caller's own component still holds its own part, which the union takes
// as a member's anyway.
IndexVector<FunctionId, effects::Row>
rows::joinComponents(const solver::ProgramGraph &graph, IndexVector<FunctionId, effects::Row> own,
                     solver::Work &work) {
  std::uint64_t read = 0;
  for (solver::SccId component : graph.sccCount().ids()) {
    IdRange<FunctionId> members = graph.members(component);
    effects::Row row;
    for (FunctionId f : members) {
      row = row | own[f];
      for (const solver::Call &call : graph.callees(f))
        row = row | own[call.callee];
      read += 1 + graph.callees(f).size();
    }
    for (FunctionId f : members)
      own[f] = row;
  }
  work.add(read);
  return own;
}

void rows::write(ProgramOp program, const solver::ProgramGraph &graph, solver::Work &work) {
  MLIRContext *context = program.getContext();
  IdRange<FunctionId> functions = graph.functions();

  // Each body by itself, in parallel, each into its own slot.
  IndexVector<FunctionId, Own> own = graph.table(Own{});
  parallelFor(context, 0, functions.size(), [&](std::size_t at) {
    FunctionId f = functions[at];
    Calls reader{graph, own[f].sites};
    own[f].derived = derive(graph.op(f), reader);
  });

  // Writes through parameters, marked from callee to caller; then the
  // write each makes elsewhere joins its caller's own atoms. A function's
  // number is its id's: a gap has no parameter.
  footprint::Vector<std::uint32_t> writable(graph.size().value(), 0);
  footprint::Vector<Owner> owners;
  owners.reserve(functions.size());
  for (FunctionId f : functions) {
    writable[f.index()] = static_cast<std::uint32_t>(own[f].derived.written.size());
    owners.push_back({f.index(), &own[f]});
  }
  WriteNodes nodes(writable);
  BitSet<WriteNode> written = markWrites(nodes, owners);

  // The atoms: each function's own, the writes it makes elsewhere through
  // its callees, its cycle's divergence; joined callees first.
  IndexVector<FunctionId, effects::Row> atoms = graph.table(effects::Row{});
  for (FunctionId f : functions)
    atoms[f] = own[f].derived.atoms | writesElsewhere(own[f].sites, nodes, written);
  detail::addCycles(graph, atoms);
  IndexVector<FunctionId, effects::Row> joined = joinComponents(graph, std::move(atoms), work);

  // The amounts, callees first: a callee in another component is final
  // when its caller is read, and one in the caller's own component lies on
  // a cycle with it, so what it puts has no bound.
  IndexVector<FunctionId, llvm::SmallVector<Amount, 2>> puts =
      graph.table(llvm::SmallVector<Amount, 2>{});
  for (FunctionId f : graph.bottomUp()) {
    puts[f] = own[f].derived.puts;
    for (const Site &site : own[f].sites)
      passOn(puts[f], site, [&](std::uint32_t theirs) {
        return graph.sccOf(site.callee) == graph.sccOf(f) ? Amount::unbounded()
                                                          : puts[site.callee][theirs];
      });
  }

  // Every record's attributes, made here, serially, so no worker makes one.
  IndexVector<FunctionId, DenseI32ArrayAttr> untouched = graph.table(DenseI32ArrayAttr{});
  IndexVector<FunctionId, PutBoundsAttr> bounded = graph.table(PutBoundsAttr{});
  for (FunctionId f : functions) {
    untouched[f] = untouchedOf(context, f.index(), writable[f.index()], nodes, written);
    bounded[f] = boundsOf(context, puts[f]);
  }

  // Each function and its calls, in parallel: a worker writes its own
  // function's ops alone, reading the tables.
  parallelFor(context, 0, functions.size(), [&](std::size_t at) {
    FunctionId f = functions[at];
    FuncOp fn = graph.op(f);
    if (fn.getRow() != joined[f])
      fn.setRow(joined[f]);
    fn.setUntouchedAttr(untouched[f]);
    fn.setBoundedAttr(bounded[f]);
    for (const Site &site : own[f].sites) {
      CallOp call = site.call;
      if (call.getRow() != joined[site.callee])
        call.setRow(joined[site.callee]);
      call.setUntouchedAttr(untouched[site.callee]);
    }
  });
}

//===----------------------------------------------------------------------===//
// Widening
//===----------------------------------------------------------------------===//

void rows::widen(ProgramOp program, effects::Row atoms) {
  llvm::SmallVector<FuncOp> functions(program.getOps<FuncOp>());
  parallelForEach(program.getContext(), functions, [&](FuncOp fn) {
    fn.setRow(fn.getRow() | atoms);
    fn.setUntouchedAttr({});
    fn.walk([&](CallOp call) {
      call.setRow(call.getRow() | atoms);
      call.setUntouchedAttr({});
    });
  });
}
