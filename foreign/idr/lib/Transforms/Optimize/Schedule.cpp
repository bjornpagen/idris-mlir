// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The schedule: one member per function of the program graph, its
// components callees first, and what each component waits on. Built once,
// on the pass thread, before the first wave, from the graph: the program is
// first-order, every force a call of its family's dispatch, so the graph's
// calls are everything a function runs. The graph is thawed for the run,
// and its editor holds rows alone, so what else the schedule reads of it
// (its components, its callers, which functions are on a cycle) is taken
// out first.

#include "idr/Transforms/Optimize.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ErrorHandling.h"

using namespace mlir;

namespace idr::optimize {

Schedule::Schedule(ProgramOp program, solver::ProgramGraph &frozen)
    : program(program), graph(takeOut(frozen)) {}

solver::Editor Schedule::takeOut(solver::ProgramGraph &frozen) {
  std::uint32_t ids = frozen.size().value();
  cyclic.resize(ids);
  labelled.resize(ids);
  components.grow(ids);
  // A member per id, a gap's with no function: ids are dense.
  for (solver::FunctionId fn : frozen.size().ids())
    members.push_back(Member{frozen.op(fn), nullptr, fn, fn});
  for (solver::FunctionId fn : frozen.functions()) {
    Member &member = members[fn.index()];
    llvm::append_range(member.callers, frozen.callers(fn));
    if (frozen.onCycle(fn))
      cyclic.set(fn.index());
  }
  // A component of the graph is one component of the schedule, until a
  // wait closes a cycle through two; its callees in other components are
  // counted each once.
  for (solver::SccId scc : frozen.sccCount().ids()) {
    auto ids = frozen.members(scc);
    unsigned first = (*ids.begin()).index();
    for (solver::FunctionId fn : ids)
      components.join(first, fn.index());
  }
  for (solver::SccId scc : frozen.sccCount().ids()) {
    auto ids = frozen.members(scc);
    unsigned mine = components.findLeader((*ids.begin()).index());
    llvm::SmallDenseSet<unsigned, 8> callees;
    for (solver::FunctionId fn : ids) {
      byComponent[mine].push_back(fn);
      for (const solver::Call &call : frozen.callees(fn))
        if (unsigned theirs = components.findLeader(call.callee.index()); theirs != mine)
          callees.insert(theirs);
    }
    unfinished[mine] = callees.size();
  }
  for (auto &entry : byComponent)
    llvm::sort(entry.second);
  // The functions the families' labels name, read once off every distinct
  // type the program's values have.
  AttrTypeWalker walker;
  walker.addWalk([&](DataType data) {
    if (std::optional<families::ClosuresView> closures = data.closures())
      for (const families::LabelDecl &label : closures->labels())
        labelled.set(frozen.id(label.fn).index());
    if (std::optional<families::MemoView> memo = data.memo())
      for (const families::MemoLabelDecl &label : memo->labels())
        labelled.set(frozen.id(label.label.fn).index());
  });
  program.walk([&](Operation *op) {
    for (Type type : op->getResultTypes())
      walker.walk(type);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Type type : block.getArgumentTypes())
          walker.walk(type);
  });
  return frozen.thaw();
}

const Summary *Schedule::summaryOf(FunctionId fn) const {
  return idr::match(
      members[fn.index()].phase, [](const Final &final) { return &final.summary; },
      [](const auto &) -> const Summary * { return nullptr; });
}

std::optional<Readable> Schedule::final(FunctionId fn) const {
  const Member &member = members[fn.index()];
  return idr::match(
      member.phase,
      [&](const Final &final) -> std::optional<Readable> {
        return Readable{member.fn, final.summary.times};
      },
      [](const auto &) -> std::optional<Readable> { return std::nullopt; });
}

// A final function, or a member of the reader's component its turn took
// up; the grant that names a copy of anything else is never made, so the
// reader asks only for these.
Readable Schedule::readable(FunctionId, FunctionId target) const {
  const Member &member = members[target.index()];
  return idr::match(
      member.phase, [&](const Final &final) { return Readable{member.fn, final.summary.times}; },
      [&](const Done &done) { return Readable{member.fn, done.solved.times}; },
      [&](const Parked &parked) { return Readable{member.fn, parked.solved.times}; },
      [&](Waiting) { return Readable{member.fn, {}}; });
}

//===----------------------------------------------------------------------===//
// Admission
//===----------------------------------------------------------------------===//

// A function whose arena alone exceeds the host's memory ends the
// compiler through its one out-of-memory handler, a crash of the machine,
// never a refusal. Any other enters once it fits beside those in flight,
// or when nothing else runs, so no wait lasts for ever.
void Admission::enter(std::uint64_t bytes) {
  if (bytes > budget)
    llvm::report_bad_alloc_error("idr-optimize: a function's e-graph needs more memory than the "
                                 "host has");
  std::unique_lock lock(mutex);
  freed.wait(lock, [&] { return inFlight == 0 || inFlight + bytes <= budget; });
  inFlight += bytes;
}

void Admission::leave(std::uint64_t bytes) {
  {
    std::lock_guard lock(mutex);
    inFlight -= bytes;
  }
  freed.notify_all();
}

} // namespace idr::optimize
