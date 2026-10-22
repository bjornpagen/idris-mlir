// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The fold every derivation of a function's row and record shares: each op
// read by its declaration through the effect system's one query API, each
// effect attributed by where it lands, each put into a put parameter summed
// by how often its region runs; and the verifier's reader of calls, the
// calls' own copies of their callees' rows, whose derivation is compiled
// here once.

#include "idr/Analysis/Effects.h"
#include "idr/IR/Effects/Classify.h"
#include "idr/IR/Effects/Consumption.h"
#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Support/Match.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/ViewLikeInterface.h"

#include <variant>

using namespace mlir;
using namespace idr;

// A region branch says which of its regions may run again; an op with
// regions that is no region branch says nothing of how often they run, so
// they may run any number of times.
rows::Runs rows::detail::regionRuns(Operation *op, unsigned index) {
  auto branch = dyn_cast<RegionBranchOpInterface>(op);
  return branch && !branch.isRepetitiveRegion(index) ? Runs::Once : Runs::Repeatedly;
}

// Idris's proof is the one input of the row that is no op: a function it
// did not prove may run forever by itself.
rows::Fold::Fold(FuncOp fn) : fn(fn), parts(fn.getArgumentTypes()) {
  derived.written.resize(parts.writable());
  derived.puts.assign(parts.puttable(), Amount::finite(0));
  idr::match(
      fn.getTermination(),
      [&](Unproved) { join(effects::Row{effects::Atom::divergence}); }, [](InComponent) {},
      [](Acyclic) {});
}

const Layouts &rows::Fold::layouts() {
  if (!laidOut)
    laidOut.emplace(fn.getOperation());
  return *laidOut;
}

void rows::Fold::declared(Operation *op, Runs runs) {
  join(effects::reportedBy(op));
  // Only a put into a put parameter is the record's, and one in a region
  // that runs again has no bound whatever its size: the bytes are read
  // only for a put once per run into a put parameter.
  if (auto putter = dyn_cast<LifetimePutOpInterface>(op)) {
    Value lifetime = putter.getPutLifetime();
    if (std::holds_alternative<PutPart>(partOf(lifetime)))
      put(lifetime,
          runs == Runs::Repeatedly ? Amount::unbounded()
                                   : Amount::finite(putter.getPutBytes(layouts())),
          runs);
  }
  // The op's own effects alone: the function's walk reads what its regions
  // hold op by op. One that says nothing MLIR can read, and is not bounded
  // by its regions, may do anything.
  effects::Walked walked = effects::eachOwnEffect(op, [&](const effects::Effect &each) {
    effect(each);
    return effects::Walked::All;
  });
  if (walked == effects::Walked::Stopped)
    anything();
}

// An acquisition is the function's own business only through what it
// acquired: the effect itself is what `alloc` reports. Any other effect on
// memory the function acquired is the function's own. A write in place
// through a write-admitting parameter, what the row would hold as `write`,
// is the record's; anything else done there is the row's.
void rows::Fold::effect(const effects::Effect &effect) {
  effects::Row atoms = effects::project(effect);
  if (!effect.value || effect.kind == effects::Kind::Allocate) {
    join(atoms);
    return;
  }
  idr::match(
      landing(effect.value), [](Local) {},
      [&](Through through) {
        if (atoms == effects::Row{effects::Atom::write})
          derived.written.set(through.position);
        else
          join(atoms);
      },
      [&](Elsewhere) { join(atoms); });
}

void rows::Fold::writeThrough(Value value) {
  effect(effects::Effect{
      .kind = effects::Kind::Write, .resource = effects::ResourceId::Contents, .value = value});
}

void rows::Fold::put(Value lifetime, Amount amount, Runs runs) {
  if (amount.none())
    return;
  idr::match(
      partOf(lifetime),
      [&](PutPart part) {
        Amount &total = derived.puts[part.position];
        total = total.plus(runs == Runs::Repeatedly ? Amount::unbounded() : amount);
      },
      [](WritePart) {}, [](NoPart) {});
}

// An op is a handle whose members are not const, so the function is read
// through a copy.
RecordPart rows::Fold::partOf(Value value) const {
  auto parameter = dyn_cast<BlockArgument>(value);
  FuncOp function = fn;
  if (!parameter || parameter.getOwner() != &function.getBody().front())
    return NoPart{};
  return parts[parameter.getArgNumber()];
}

// Through views to the value whose memory they are, then: a parameter's,
// read by its part; or memory the op that made it acquired, the function's
// own; or anything else. A view's source is one hop, and the chain is as
// long as the views are deep.
rows::Lands rows::Fold::landing(Value value) const {
  while (auto view = value.getDefiningOp<ViewLikeOpInterface>()) {
    if (view.getViewDest() != value)
      break;
    value = view.getViewSource();
  }
  return idr::match(
      partOf(value), [](WritePart part) -> Lands { return Through{part.position}; },
      [](PutPart) -> Lands { return Elsewhere{}; },
      [&](NoPart) -> Lands {
        Operation *made = value.getDefiningOp();
        if (made && effects::acquires(made, value))
          return Local{};
        return Elsewhere{};
      });
}

void rows::Fold::anything() {
  join(effects::Row::top());
  derived.written.set();
  for (Amount &amount : derived.puts)
    amount = Amount::unbounded();
}

void rows::CallCopies::call(CallOp call, Fold &fold, Runs) {
  fold.join(call.getRow());
  forEachWritten(call, [&](OpOperand &operand) { fold.writeThrough(operand.get()); });
}

template class rows::Derivation<rows::CallCopies>;
