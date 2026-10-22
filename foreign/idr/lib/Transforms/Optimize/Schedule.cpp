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

using namespace mlir;

namespace idr::optimize {

Schedule::Schedule(ProgramOp program, solver::ProgramGraph &frozen)
    : program(program), graph(takeOut(frozen)) {}

solver::Editor Schedule::takeOut(solver::ProgramGraph &frozen) {
  std::uint32_t ids = frozen.size().value();
  cyclic.resize(ids);
  labelled.resize(ids);
  components.grow(ids);
  unfinished.assign(ids, 0);
  byComponent.resize(ids);
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
    auto component = frozen.members(scc);
    unsigned first = (*component.begin()).index();
    for (solver::FunctionId fn : component)
      components.join(first, fn.index());
  }
  for (solver::SccId scc : frozen.sccCount().ids()) {
    auto component = frozen.members(scc);
    unsigned mine = components.findLeader((*component.begin()).index());
    llvm::SmallDenseSet<unsigned, 8> outside;
    for (solver::FunctionId fn : component) {
      byComponent[mine].push_back(fn);
      for (const solver::Call &call : frozen.callees(fn))
        if (unsigned theirs = components.findLeader(call.callee.index()); theirs != mine)
          outside.insert(theirs);
    }
    unfinished[mine] = static_cast<unsigned>(outside.size());
  }
  for (footprint::Vector<FunctionId> &group : byComponent)
    llvm::sort(group);
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

} // namespace idr::optimize
