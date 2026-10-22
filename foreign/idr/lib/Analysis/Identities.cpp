// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The functions of a component and what they give back: each read once, the
// greatest fixpoint over the reads, and every fact per result field path
// once it holds. IdentitiesRecord.cpp reads a function; IdentitiesRebuilds.cpp
// says what its returns rebuild under the assumptions left.
#include "Solver/IdentityRecords.h"

#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <deque>

using namespace mlir;

namespace idr::identities {

Component::Component(std::unique_ptr<Records> records) : records(std::move(records)) {}
Component::Component(Component &&) noexcept = default;
Component::~Component() = default;

template <solver::FunctionNames N>
Component Component::read(const N &names, ArrayRef<solver::Member> component) {
  auto out = std::make_unique<Records>();
  for (const solver::Member &member : component)
    out->members.push_back(readRecord(names, member));

  // The members by id, and the callees outside, each once in id order:
  // sorted lists searched, never a map of the program's functions.
  std::vector<std::pair<std::uint32_t, std::uint32_t>> byId;
  for (auto [at, member] : llvm::enumerate(component))
    byId.emplace_back(member.id.index(), static_cast<std::uint32_t>(at));
  llvm::sort(byId);
  auto memberOf = [&](solver::FunctionId f) -> std::optional<std::uint32_t> {
    auto it = llvm::lower_bound(byId, std::pair(f.index(), 0u));
    if (it == byId.end() || it->first != f.index())
      return std::nullopt;
    return it->second;
  };
  for (const Record &record : out->members)
    for (const CallSite &call : record.calls)
      if (!memberOf(call.callee))
        out->outside.push_back(call.callee);
  llvm::sort(out->outside);
  out->outside.erase(std::unique(out->outside.begin(), out->outside.end()), out->outside.end());

  for (const Record &record : out->members) {
    std::vector<Records::Callee> &callees = out->callees.emplace_back();
    for (const CallSite &call : record.calls) {
      if (std::optional<std::uint32_t> member = memberOf(call.callee)) {
        callees.push_back(Records::InComponent{*member});
        continue;
      }
      auto it = llvm::lower_bound(out->outside, call.callee);
      callees.push_back(Records::Elsewhere{static_cast<std::uint32_t>(it - out->outside.begin())});
    }
  }
  return Component(std::move(out));
}

template Component Component::read<solver::ProgramGraph>(const solver::ProgramGraph &,
                                                         ArrayRef<solver::Member>);
template Component Component::read<solver::Editor>(const solver::Editor &,
                                                   ArrayRef<solver::Member>);

std::span<const solver::FunctionId> Component::outsideCallees() const { return records->outside; }

std::vector<Facts> Component::solve(std::span<const std::span<const GivesBack>> outside) && {
  const std::vector<Record> &members = records->members;
  auto count = static_cast<unsigned>(members.size());

  // Every member starts assumed to give back each argument of a result's
  // type, as a whole, at that result.
  std::vector<Facts> assumed(count);
  for (auto [at, record] : llvm::enumerate(members))
    for (auto [result, resultType] : llvm::enumerate(record.resultTypes))
      for (auto [argument, argumentType] : llvm::enumerate(record.argumentTypes))
        if (representation(argumentType, resultType) == Represents::Alike)
          assumed[at].push_back({{static_cast<std::uint32_t>(result), {}},
                                 {static_cast<std::uint32_t>(argument), {}}});

  // The members that call each member: who must be checked again when its
  // assumptions drop.
  std::vector<std::vector<std::uint32_t>> callers(count);
  for (auto [at, callees] : llvm::enumerate(records->callees))
    for (const Records::Callee &callee : callees)
      if (const auto *in = std::get_if<Records::InComponent>(&callee))
        callers[in->member].push_back(static_cast<std::uint32_t>(at));
  for (std::vector<std::uint32_t> &list : callers) {
    llvm::sort(list);
    list.erase(std::unique(list.begin(), list.end()), list.end());
  }

  // What each call site of `member` is assumed or known to give back, read
  // afresh for each check, since assumptions drop between checks.
  auto calleeFacts = [&](std::uint32_t member) {
    std::vector<std::span<const GivesBack>> facts;
    for (const Records::Callee &callee : records->callees[member])
      facts.push_back(std::visit(
          llvm::makeVisitor(
              [&](Records::InComponent in) { return std::span<const GivesBack>(assumed[in.member]); },
              [&](Records::Elsewhere away) { return outside[away.outside]; }),
          callee));
    return facts;
  };

  // A check can only drop assumptions, and a member is checked again only
  // after an assumption of a member it calls dropped: finitely many drops,
  // so the queue empties, at the greatest fixpoint.
  std::deque<std::uint32_t> queue;
  llvm::BitVector queued(count, true);
  for (std::uint32_t member = 0; member < count; ++member)
    queue.push_back(member);
  while (!queue.empty()) {
    std::uint32_t member = queue.front();
    queue.pop_front();
    queued.reset(member);
    std::vector<std::span<const GivesBack>> facts = calleeFacts(member);
    Facts kept = wholeFactsAmong(members[member], facts, assumed[member]);
    if (kept.size() == assumed[member].size())
      continue;
    assumed[member] = std::move(kept);
    for (std::uint32_t caller : callers[member])
      if (!queued.test(caller)) {
        queued.set(caller);
        queue.push_back(caller);
      }
  }

  std::vector<Facts> out;
  out.reserve(count);
  for (std::uint32_t member = 0; member < count; ++member)
    out.push_back(everyFact(members[member], calleeFacts(member)));
  return out;
}

} // namespace idr::identities
