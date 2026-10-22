// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The functions of a component and what they give back: each read once, the
// greatest fixpoint over the reads, and every fact per result field path
// once it holds. IdentitiesRecord.cpp reads a function; IdentitiesRebuilds.cpp
// says what its returns rebuild under the assumptions left.
#include "idr/Analysis/Solver/IdentityRecords.h"
#include "idr/Support/Match.h"

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
  footprint::Vector<std::pair<std::uint32_t, std::uint32_t>> byId;
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
    footprint::Vector<Records::Callee> &callees = out->callees.emplace_back();
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

namespace {

// Whether a member waits in the check queue: a choice, never a flag.
enum class Queued : std::uint8_t { No, Yes };

} // namespace

footprint::Vector<Facts> Component::solve(std::span<const std::span<const GivesBack>> outside,
                                          solver::Work &work) && {
  const footprint::Vector<Record> &members = records->members;
  auto count = static_cast<unsigned>(members.size());
  // Each reading of a member visits its every value: its record's, once
  // when it was read, and a reading's at each check and publication.
  std::uint64_t visited = 0;
  auto visit = [&](std::uint32_t member) { visited += members[member].values.value(); };
  for (std::uint32_t member = 0; member < count; ++member)
    visit(member);

  // Every member starts assumed to give back each argument of a result's
  // type, as a whole, at that result.
  footprint::Vector<Facts> assumed(count);
  for (auto [at, record] : llvm::enumerate(members))
    for (auto [result, resultType] : llvm::enumerate(record.resultTypes))
      for (auto [argument, argumentType] : llvm::enumerate(record.argumentTypes))
        if (representation(argumentType, resultType) == Represents::Alike)
          assumed[at].push_back({{static_cast<std::uint32_t>(result), {}},
                                 {static_cast<std::uint32_t>(argument), {}}});

  // The members that call each member: who must be checked again when its
  // assumptions drop.
  footprint::Vector<footprint::Vector<std::uint32_t>> callers(count);
  for (auto [at, callees] : llvm::enumerate(records->callees))
    for (const Records::Callee &callee : callees)
      match(
          callee,
          [&](Records::InComponent in) {
            callers[in.member].push_back(static_cast<std::uint32_t>(at));
          },
          [](Records::Elsewhere) {});
  for (footprint::Vector<std::uint32_t> &list : callers) {
    llvm::sort(list);
    list.erase(std::unique(list.begin(), list.end()), list.end());
  }

  // What each call site of `member` is assumed or known to give back, read
  // afresh for each check, since assumptions drop between checks.
  auto calleeFacts = [&](std::uint32_t member) {
    footprint::Vector<std::span<const GivesBack>> facts;
    for (const Records::Callee &callee : records->callees[member])
      facts.push_back(match(
          callee,
          [&](Records::InComponent in) { return std::span<const GivesBack>(assumed[in.member]); },
          [&](Records::Elsewhere away) { return outside[away.outside]; }));
    return facts;
  };

  // A check can only drop assumptions, and a member is checked again only
  // after an assumption of a member it calls dropped: finitely many drops,
  // so the queue empties, at the greatest fixpoint.
  std::deque<std::uint32_t, footprint::Allocator<std::uint32_t>> queue;
  footprint::Vector<Queued> queued(count, Queued::Yes);
  for (std::uint32_t member = 0; member < count; ++member)
    queue.push_back(member);
  while (!queue.empty()) {
    std::uint32_t member = queue.front();
    queue.pop_front();
    queued[member] = Queued::No;
    footprint::Vector<std::span<const GivesBack>> facts = calleeFacts(member);
    Facts kept = wholeFactsAmong(members[member], facts, assumed[member]);
    visit(member);
    if (kept.size() == assumed[member].size())
      continue;
    assumed[member] = std::move(kept);
    for (std::uint32_t caller : callers[member])
      if (queued[caller] == Queued::No) {
        queued[caller] = Queued::Yes;
        queue.push_back(caller);
      }
  }

  footprint::Vector<Facts> out;
  out.reserve(count);
  for (std::uint32_t member = 0; member < count; ++member) {
    out.push_back(everyFact(members[member], calleeFacts(member)));
    visit(member);
  }
  work.add(visited);
  return out;
}

} // namespace idr::identities
