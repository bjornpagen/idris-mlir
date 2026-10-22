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
//
// A family's identity is its content, so dropping a field declares its
// group anew, and every type, attribute and constant that names the old
// group names the new one, in one replacement once every group is
// declared: a group that holds another is remade through the other's new
// declaration as the replacement reaches it. Otherwise only the field's
// readers and builders change: a read of the field goes, a read past it
// counts the fields left before it, an exchange binds one capture fewer, a
// constructor and a constant hold one field fewer.
//
// It runs on the pass thread, once, when no turn runs: it changes types
// every function may hold.

#include "idr/IR/Families/Families.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Traits.h"
#include "idr/Transforms/OptimizeScheduler.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"

#include <concepts>
#include <deque>
#include <optional>
#include <tuple>
#include <vector>

using namespace mlir;

namespace idr::optimize {

namespace {

// A constructor of a label: its family, as the group and member that
// declare it, and its tag.
using Ctor = std::tuple<FamilyAttr, std::uint32_t, std::uint32_t>;

Ctor ctorOf(DataType data, Tag tag) {
  return {data.getGroup(), data.getMember(), static_cast<std::uint32_t>(tag)};
}

// A label's function: how many captures it takes, its leading parameters
// and its constructors' fields; and its constructors.
struct Label {
  FunctionId fn;
  unsigned captures;
  SmallVector<Ctor, 1> ctors;
};

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

// The changes of grade `value` was made by that its lost use left unused.
void eraseRegrades(Value value) {
  while (value.use_empty()) {
    Operation *def = value.getDefiningOp();
    if (!def || !def->hasTrait<ResultCarriesOperand>())
      return;
    value = def->getOperand(0);
    def->erase();
  }
}

// How many of `bits` lie below `at`.
unsigned below(const llvm::BitVector &bits, unsigned at) {
  unsigned n = 0;
  for (unsigned i = 0; i < at && i < bits.size(); ++i)
    n += bits.test(i) ? 1 : 0;
  return n;
}

} // namespace

void narrowCaptures(Schedule &schedule) {
  ProgramOp program = schedule.program;
  MLIRContext *ctx = program.getContext();
  const solver::Editor &graph = schedule.graph;

  // Every label and its constructors, read off each distinct family the
  // program's types hold, once.
  std::vector<Label> labels;
  std::vector<std::optional<unsigned>> labelOf(graph.size().value());
  llvm::DenseMap<Ctor, unsigned> ownerOf;
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
    return;

  // Every capture, numbered label by label; read ones rise.
  std::vector<unsigned> first{0};
  for (const Label &label : labels)
    first.push_back(first.back() + label.captures);
  auto slot = [&](unsigned l, unsigned p) { return first[l] + p; };
  llvm::BitVector read(first.back());
  std::vector<SmallVector<unsigned, 1>> feeds(first.back());
  SmallVector<unsigned> work;
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
    unsigned at = work.pop_back_val();
    for (unsigned fed : feeds[at])
      mark(fed);
  }

  std::vector<llvm::BitVector> dropped(labels.size());
  bool any = false;
  for (auto [l, label] : llvm::enumerate(labels)) {
    dropped[l].resize(label.captures);
    for (unsigned p = 0; p < label.captures; ++p)
      if (!read.test(slot(static_cast<unsigned>(l), p)))
        dropped[l].set(p);
    any = any || dropped[l].any();
  }
  if (!any)
    return;
  auto droppedOf = [&](Ctor ctor) -> const llvm::BitVector * {
    auto owner = ownerOf.find(ctor);
    if (owner == ownerOf.end() || dropped[owner->second].none())
      return nullptr;
    return &dropped[owner->second];
  };

  // The calls of each label give its dropped captures no more, and the
  // changes of grade that made them go.
  SmallVector<CallOp> calls;
  program.walk([&](CallOp call) {
    if (std::optional<unsigned> l = labelOf[graph.id(call.getCalleeAttr()).index()];
        l && dropped[*l].any())
      calls.push_back(call);
  });
  for (CallOp call : calls) {
    const llvm::BitVector &bits = dropped[*labelOf[graph.id(call.getCalleeAttr()).index()]];
    unsigned begin = call.getArgs().getBeginOperandIndex();
    SmallVector<unsigned> positions(bits.set_bits());
    for (unsigned p : llvm::reverse(positions)) {
      Value given = call->getOperand(begin + p);
      call->eraseOperand(begin + p);
      eraseRegrades(given);
    }
  }
  // The reads: a dropped field's goes, one past a dropped field counts the
  // fields left before it; an exchange binds its dropped captures no more.
  SmallVector<DataFieldOp> fields;
  program.walk([&](DataFieldOp field) { fields.push_back(field); });
  for (DataFieldOp field : fields) {
    DataType data = dataTypeOf(field.getValue().getType());
    std::optional<Tag> tag = data ? data.singleTag() : std::nullopt;
    const llvm::BitVector *bits = tag ? droppedOf(ctorOf(data, *tag)) : nullptr;
    if (!bits)
      continue;
    auto index = static_cast<unsigned>(field.getIndex());
    if (bits->test(index)) {
      field.erase();
      continue;
    }
    field.setIndex(index - below(*bits, index));
  }
  SmallVector<MemoRunOp> runs;
  program.walk([&](MemoRunOp run) { runs.push_back(run); });
  for (MemoRunOp run : runs)
    if (const llvm::BitVector *bits = droppedOf(ctorOf(run.getDataType(), Tag{run.getTag()})))
      run.getRegion().front().eraseArguments(*bits);
  // The constructors hold the dropped fields no more.
  SmallVector<DataConOp> cons;
  program.walk([&](DataConOp con) { cons.push_back(con); });
  for (DataConOp con : cons) {
    DataType data = dataTypeOf(con.getResult().getType());
    const llvm::BitVector *bits = data ? droppedOf(ctorOf(data, con.getTag())) : nullptr;
    if (!bits)
      continue;
    SmallVector<unsigned> positions(bits->set_bits());
    for (unsigned p : llvm::reverse(positions))
      con->eraseOperand(p);
  }
  // Each label's function takes its dropped captures no more.
  for (auto [l, label] : llvm::enumerate(labels)) {
    if (dropped[l].none())
      continue;
    FuncOp fn = schedule.function(label.fn);
    llvm::BitVector arguments(fn.getNumArguments());
    for (unsigned p : dropped[l].set_bits())
      arguments.set(p);
    renumberGivenBack(fn, arguments, llvm::BitVector());
    (void)fn.eraseArguments(arguments);
  }

  // Each group a narrowed constructor is declared in, declared anew; then
  // every type, attribute and constant of the program through the new
  // declarations.
  std::deque<SmallVector<Type>> fieldStore;
  std::deque<SmallVector<families::LabelDecl>> labelStore;
  std::deque<SmallVector<families::MemoLabelDecl>> memoStore;
  auto narrowed = [&](const families::LabelDecl &decl, Ctor ctor) {
    const llvm::BitVector *bits = droppedOf(ctor);
    if (!bits)
      return decl;
    SmallVector<Type> &kept = fieldStore.emplace_back();
    for (auto [i, field] : llvm::enumerate(decl.fields))
      if (!bits->test(static_cast<unsigned>(i)))
        kept.push_back(field);
    families::LabelDecl out = decl;
    out.fields = kept;
    return out;
  };
  llvm::DenseMap<FamilyAttr, FamilyAttr> anew;
  for (auto [l, label] : llvm::enumerate(labels)) {
    if (dropped[l].none())
      continue;
    for (const Ctor &ctor : label.ctors) {
      FamilyAttr group = std::get<0>(ctor);
      if (anew.contains(group))
        continue;
      SmallVector<families::Member> members;
      for (auto [m, member] : llvm::enumerate(group.getMembers())) {
        auto at = static_cast<std::uint32_t>(m);
        members.push_back(idr::match(
            member,
            [&](const families::ClosuresMember &closures) -> families::Member {
              SmallVector<families::LabelDecl> &decls = labelStore.emplace_back();
              for (auto [t, decl] : llvm::enumerate(closures.labels))
                decls.push_back(narrowed(decl, Ctor{group, at, static_cast<std::uint32_t>(t)}));
              return families::ClosuresMember{closures.label, closures.indices, decls};
            },
            [&](const families::MemoMember &memo) -> families::Member {
              SmallVector<families::MemoLabelDecl> &decls = memoStore.emplace_back();
              for (auto [t, decl] : llvm::enumerate(memo.labels))
                decls.push_back(families::MemoLabelDecl{
                    decl.mode, narrowed(decl.label, Ctor{group, at, static_cast<std::uint32_t>(t)})});
              return families::MemoMember{memo.label, memo.indices, decls, memo.forced};
            },
            [](const auto &other) -> families::Member { return other; }));
      }
      anew[group] = FamilyAttr::get(ctx, members);
    }
  }
  AttrTypeReplacer replacer;
  replacer.addReplacement([&](FamilyAttr group) -> std::optional<Attribute> {
    if (FamilyAttr now = anew.lookup(group))
      return now;
    return std::nullopt;
  });
  replacer.addReplacement([&](ConAttr con) -> std::optional<Attribute> {
    const llvm::BitVector *bits = droppedOf(ctorOf(con.getData(), con.getTag()));
    if (!bits)
      return std::nullopt;
    SmallVector<Attribute> kept;
    for (auto [i, field] : llvm::enumerate(con.getFields()))
      if (!bits->test(static_cast<unsigned>(i)))
        kept.push_back(field);
    return ConAttr::get(ctx, con.getData(), ArrayAttr::get(ctx, kept));
  });
  replacer.recursivelyReplaceElementsIn(program, /*replaceAttrs=*/true, /*replaceLocs=*/false,
                                        /*replaceTypes=*/true);
}

} // namespace idr::optimize
