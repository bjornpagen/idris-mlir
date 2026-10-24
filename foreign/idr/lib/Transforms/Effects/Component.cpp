// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The writer of one of the optimizer's components, when the optimizer
// finishes it: every callee outside the component is final and each call
// of one holds its callee's row already, so the members' rows read only
// their own bodies, joined into one row for every member, with the
// writes through parameters marked within the component (the writers'
// shared parts).

#include "idr/Transforms/Effects.h"

#include "idr/Analysis/Effects.h"
#include "idr/Analysis/Solver/Components.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>
#include <span>
#include <utility>

using namespace mlir;
using namespace idr;
using namespace idr::rows;
using namespace idr::rows::writer;
using solver::FunctionId;

namespace {

// The optimizer's reader for one component: a call of a member is
// recorded, joined over the component; a call of a final callee holds the
// callee's row already, which it gives. What a final callee puts into a
// lifetime is not on its call, so a put parameter passed on to one has no
// bound: lifetimes are decided after the optimizer, so none is passed yet.
struct ComponentCalls {
  const solver::Editor &editor;
  llvm::ArrayRef<std::pair<FunctionId, unsigned>> byId;
  std::span<const solver::Member> members;
  llvm::SmallVectorImpl<Site> &sites;

  // The member a callee is, by its number among the members, if it is one:
  // a call of a final callee is no site.
  std::optional<unsigned> memberOf(FunctionId callee) const {
    auto at = llvm::lower_bound(byId, callee, [](const std::pair<FunctionId, unsigned> &entry,
                                                 FunctionId id) { return entry.first < id; });
    if (at == byId.end() || at->first != callee)
      return std::nullopt;
    return at->second;
  }

  void call(CallOp call, Fold &fold, Runs runs) {
    FunctionId callee = editor.id(call.getCalleeAttr());
    if (std::optional<unsigned> member = memberOf(callee)) {
      sites.push_back(siteOf(call, callee, *member, members[*member].fn, fold, runs));
      return;
    }
    CallCopies copies;
    copies.call(call, fold, runs);
    for (Value operand : call.getArgs())
      if (admitsPuts(operand.getType()))
        fold.put(operand, Amount::unbounded(), runs);
  }
  Read other(Operation *, Fold &, Runs) { return Read::ByDeclaration; }
};

} // namespace

void rows::writeComponent(std::span<const solver::Member> members, const solver::Editor &editor) {
  // An op is a handle whose members are not const, so each member's
  // function is read and written through a copy.
  FuncOp first = members.front().fn;
  MLIRContext *context = first.getContext();
  footprint::Vector<std::pair<FunctionId, unsigned>> byId;
  byId.reserve(members.size());
  for (auto [index, member] : llvm::enumerate(members))
    byId.push_back({member.id, static_cast<unsigned>(index)});
  llvm::sort(byId, [](const auto &a, const auto &b) { return a.first < b.first; });

  // Each member by itself, each site numbered by its callee's place among
  // the members.
  footprint::Vector<Own> own(members.size());
  for (auto [index, member] : llvm::enumerate(members)) {
    ComponentCalls reader{editor, byId, members, own[index].sites};
    own[index].derived = derive(member.fn, reader);
  }

  // Writes through parameters, within the component: a final callee's are
  // on its calls, read by the fold already.
  footprint::Vector<std::uint32_t> writable;
  footprint::Vector<Owner> owners;
  writable.reserve(own.size());
  owners.reserve(own.size());
  for (auto [index, mine] : llvm::enumerate(own)) {
    writable.push_back(static_cast<std::uint32_t>(mine.derived.written.size()));
    owners.push_back({static_cast<std::uint32_t>(index), &mine});
  }
  WriteNodes nodes(writable);
  BitSet<WriteNode> written = markWrites(nodes, owners);

  // One row for every member: what each does and what each writes
  // elsewhere through another, and the cycle's divergence. The optimizer's
  // components grow and merge apart from the frozen graph's, so no SccId
  // names this one; whether it is a cycle is isCycle over its members as
  // read here, from the bodies as they now stand. A site is a call of a
  // member, so a lone member's sites are its calls of itself.
  effects::Row row;
  for (const Own &mine : own)
    row = row | mine.derived.atoms | writesElsewhere(mine.sites, nodes, written);
  if (isCycle(own, [](const Own &lone) { return !lone.sites.empty(); }) &&
      !provedTogether(llvm::map_range(members, [](const solver::Member &m) { return m.fn; })))
    row = row | effects::Row{effects::Atom::divergence};

  // The members' amounts: a put passed on to a member lies on the cycle.
  footprint::Vector<DenseI32ArrayAttr> untouched;
  footprint::Vector<PutBoundsAttr> bounded;
  untouched.reserve(own.size());
  bounded.reserve(own.size());
  for (auto [index, mine] : llvm::enumerate(own)) {
    llvm::SmallVector<Amount, 2> puts = mine.derived.puts;
    for (const Site &site : mine.sites)
      passOn(puts, site, [](std::uint32_t) { return Amount::unbounded(); });
    auto owner = static_cast<std::uint32_t>(index);
    untouched.push_back(untouchedOf(context, owner, writable[owner], nodes, written));
    bounded.push_back(boundsOf(context, puts));
  }

  for (auto [index, member] : llvm::enumerate(members)) {
    FuncOp fn = member.fn;
    fn.setRow(row);
    fn.setUntouchedAttr(untouched[index]);
    fn.setBoundedAttr(bounded[index]);
    for (const Site &site : own[index].sites) {
      CallOp call = site.call;
      call.setRow(row);
      call.setUntouchedAttr(untouched[site.ordinal]);
    }
  }
}
