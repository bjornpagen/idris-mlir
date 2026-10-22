// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Unread captures, dropped once every function is final: a field of a
// label's constructor that nothing reads but its label's unread parameter
// goes, from its family, from the label's parameters, and from every
// constructor and constant that holds it.
//
// After defunctionalization every call of a label's function is in the
// program, a dispatch's case or a force's, so a capture is a parameter like
// any other: read unless every use gives it, through changes of grade, to
// a label's capture that is unread in turn, a least fixpoint over the
// labels' captures whose bits only rise, so it ends by construction. Only a
// capture used many times can be unread: Idris checked that one of
// quantity one is used. A label stands in one family per key whose set
// holds it, with a constructor in each, and its capture goes from every
// one or stays. It stays where a read of its field (a field read out of a
// value refined to the constructor, a capture an exchange moves out of its
// cell) gives the value anywhere but to the label's call at that capture,
// and where a constant holds the constructor as a run of cells, whose
// spine a dropped field would move.

#include "Captures.h"

#include "idr/IR/Families/Families.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Traits.h"
#include "idr/Transforms/OptimizeScheduler.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"

#include <concepts>

using namespace mlir;

namespace idr::optimize {

namespace captures {

namespace {

// Each use `value` reaches through changes of grade, which give it on
// unchanged.
template <std::invocable<OpOperand &> F>
void forEachEnd(Value value, F &&each) {
  SmallVector<Value> work{value};
  while (!work.empty()) {
    Value at = work.pop_back_val();
    for (OpOperand &use : at.getUses()) {
      Operation *user = use.getOwner();
      if (user->hasTrait<ResultCarriesOperand>() && use.getOperandNumber() == 0) {
        work.push_back(user->getResult(0));
        continue;
      }
      each(use);
    }
  }
}

} // namespace

const llvm::BitVector *Unread::droppedOf(Ctor ctor) const {
  auto owner = ownerOf.find(ctor);
  if (owner == ownerOf.end() || dropped[owner->second].none())
    return nullptr;
  return &dropped[owner->second];
}

std::optional<Unread> unread(Schedule &schedule) {
  ProgramOp program = schedule.program;
  const solver::Editor &graph = schedule.graph;
  Unread out;

  // Every label and its constructors, read off each distinct family the
  // program's types hold, once.
  footprint::Vector<Label> &labels = out.labels;
  footprint::Vector<std::optional<unsigned>> &labelOf = out.labelOf;
  llvm::DenseMap<Ctor, unsigned> &ownerOf = out.ownerOf;
  labelOf.resize(graph.size().value());
  auto note = [&](const families::LabelDecl &decl, Ctor ctor) {
    FunctionId fn = graph.id(decl.fn);
    std::optional<unsigned> &at = labelOf[fn.index()];
    if (!at) {
      at = static_cast<unsigned>(labels.size());
      labels.push_back(Label{fn, static_cast<unsigned>(decl.fields.size()), {}});
    }
    labels[*at].ctors.push_back(ctor);
    ownerOf.try_emplace(ctor, *at);
  };
  llvm::DenseSet<FamilyAttr> seen;
  AttrTypeWalker declared;
  declared.addWalk([&](DataType data) {
    FamilyAttr group = data.getGroup();
    if (!seen.insert(group).second)
      return;
    for (auto [m, member] : llvm::enumerate(group.getMembers())) {
      auto at = static_cast<std::uint32_t>(m);
      idr::match(
          member,
          [&](const families::ClosuresMember &closures) {
            for (auto [t, decl] : llvm::enumerate(closures.labels))
              note(decl, Ctor{group, at, static_cast<std::uint32_t>(t)});
          },
          [&](const families::MemoMember &memo) {
            for (auto [t, decl] : llvm::enumerate(memo.labels))
              note(decl.label, Ctor{group, at, static_cast<std::uint32_t>(t)});
          },
          [](const auto &) {});
    }
  });
  program.walk([&](Operation *op) {
    if (auto fn = dyn_cast<FuncOp>(op))
      declared.walk(fn.getFunctionType());
    for (Type type : op->getResultTypes())
      declared.walk(type);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Type type : block.getArgumentTypes())
          declared.walk(type);
  });
  if (labels.empty())
    return std::nullopt;

  // Every capture, numbered label by label; read ones rise.
  footprint::Vector<unsigned> first{0};
  for (const Label &label : labels)
    first.push_back(first.back() + label.captures);
  auto slot = [&](unsigned l, unsigned p) { return first[l] + p; };
  llvm::BitVector read(first.back());
  footprint::Vector<SmallVector<unsigned, 1>> feeds(first.back());
  footprint::Vector<unsigned> work;
  auto mark = [&](unsigned at) {
    if (read.test(at))
      return;
    read.set(at);
    work.push_back(at);
  };

  // A read of a label's field that gives the value anywhere but to the
  // label's call at that capture, and a constant run of its constructor,
  // keep the capture.
  auto readOf = [&](Value value, Ctor ctor, unsigned field) {
    auto owner = ownerOf.find(ctor);
    if (owner == ownerOf.end() || field >= labels[owner->second].captures)
      return;
    unsigned l = owner->second;
    bool alone = true;
    forEachEnd(value, [&](OpOperand &use) {
      auto call = dyn_cast<CallOp>(use.getOwner());
      alone = alone && call && graph.id(call.getCalleeAttr()) == labels[l].fn &&
              use.getOperandNumber() - call.getArgs().getBeginOperandIndex() == field;
    });
    if (!alone)
      mark(slot(l, field));
  };
  program.walk([&](DataFieldOp field) {
    DataType data = dataTypeOf(field.getValue().getType());
    if (std::optional<Tag> tag = data ? data.singleTag() : std::nullopt)
      readOf(field.getResult(), ctorOf(data, *tag), static_cast<unsigned>(field.getIndex()));
  });
  program.walk([&](MemoRunOp run) {
    Ctor ctor = ctorOf(run.getDataType(), Tag{run.getTag()});
    for (BlockArgument capture : run.getRegion().front().getArguments())
      readOf(capture, ctor, capture.getArgNumber());
  });
  AttrTypeWalker constants;
  constants.addWalk([&](ConAttr con) {
    if (con.getRunLength() < 2)
      return;
    if (auto owner = ownerOf.find(ctorOf(con.getData(), con.getTag())); owner != ownerOf.end())
      for (unsigned p = 0; p < labels[owner->second].captures; ++p)
        mark(slot(owner->second, p));
  });
  program.walk([&](Operation *op) {
    constants.walk(op->getRawDictionaryAttrs());
    if (Attribute properties = op->getPropertiesAsAttribute())
      constants.walk(properties);
  });

  // A capture's uses: given to a label's capture, which being read makes
  // it read; anything else reads it.
  for (auto [l, label] : llvm::enumerate(labels)) {
    FuncOp fn = schedule.function(label.fn);
    for (unsigned p = 0; p < label.captures; ++p) {
      BlockArgument param = fn.getArgument(p);
      bool seed = fn.isRoot() || isLinear(param.getType());
      forEachEnd(param, [&](OpOperand &use) {
        auto call = dyn_cast<CallOp>(use.getOwner());
        std::optional<unsigned> other =
            call ? labelOf[graph.id(call.getCalleeAttr()).index()] : std::nullopt;
        unsigned q = call ? use.getOperandNumber() - call.getArgs().getBeginOperandIndex() : 0;
        if (other && q < labels[*other].captures) {
          feeds[slot(*other, q)].push_back(slot(static_cast<unsigned>(l), p));
          return;
        }
        seed = true;
      });
      if (seed)
        mark(slot(static_cast<unsigned>(l), p));
    }
  }
  while (!work.empty()) {
    unsigned at = work.back();
    work.pop_back();
    for (unsigned fed : feeds[at])
      mark(fed);
  }

  footprint::Vector<llvm::BitVector> &dropped = out.dropped;
  dropped.resize(labels.size());
  bool any = false;
  for (auto [l, label] : llvm::enumerate(labels)) {
    dropped[l].resize(label.captures);
    for (unsigned p = 0; p < label.captures; ++p)
      if (!read.test(slot(static_cast<unsigned>(l), p)))
        dropped[l].set(p);
    any = any || dropped[l].any();
  }
  if (!any)
    return std::nullopt;
  return out;
}

} // namespace captures

void narrowCaptures(Schedule &schedule) {
  if (std::optional<captures::Unread> found = captures::unread(schedule))
    captures::drop(schedule, *found);
}

} // namespace idr::optimize
