// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The captures the solve found unread (Captures.cpp) dropped from the
// program.
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

#include "Captures.h"

#include "idr/IR/Families/Families.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Traits.h"
#include "idr/Transforms/OptimizeScheduler.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "llvm/ADT/STLExtras.h"

#include <deque>

using namespace mlir;

namespace idr::optimize::captures {

namespace {

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

void drop(Schedule &schedule, const Unread &unread) {
  ProgramOp program = schedule.program;
  MLIRContext *ctx = program.getContext();
  const solver::Editor &graph = schedule.graph;

  // The calls of each label give its dropped captures no more, and the
  // changes of grade that made them go.
  SmallVector<CallOp> calls;
  program.walk([&](CallOp call) {
    if (std::optional<unsigned> l = unread.labelOf[graph.id(call.getCalleeAttr()).index()];
        l && unread.dropped[*l].any())
      calls.push_back(call);
  });
  for (CallOp call : calls) {
    const llvm::BitVector &bits =
        unread.dropped[*unread.labelOf[graph.id(call.getCalleeAttr()).index()]];
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
    const llvm::BitVector *bits = tag ? unread.droppedOf(ctorOf(data, *tag)) : nullptr;
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
    if (const llvm::BitVector *bits = unread.droppedOf(ctorOf(run.getDataType(), Tag{run.getTag()})))
      run.getRegion().front().eraseArguments(*bits);
  // The constructors hold the dropped fields no more.
  SmallVector<DataConOp> cons;
  program.walk([&](DataConOp con) { cons.push_back(con); });
  for (DataConOp con : cons) {
    DataType data = dataTypeOf(con.getResult().getType());
    const llvm::BitVector *bits = data ? unread.droppedOf(ctorOf(data, con.getTag())) : nullptr;
    if (!bits)
      continue;
    SmallVector<unsigned> positions(bits->set_bits());
    for (unsigned p : llvm::reverse(positions))
      con->eraseOperand(p);
  }
  // Each label's function takes its dropped captures no more.
  for (auto [l, label] : llvm::enumerate(unread.labels)) {
    if (unread.dropped[l].none())
      continue;
    FuncOp fn = schedule.function(label.fn);
    llvm::BitVector arguments(fn.getNumArguments());
    for (unsigned p : unread.dropped[l].set_bits())
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
    const llvm::BitVector *bits = unread.droppedOf(ctor);
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
  for (auto [l, label] : llvm::enumerate(unread.labels)) {
    if (unread.dropped[l].none())
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
    const llvm::BitVector *bits = unread.droppedOf(ctorOf(con.getData(), con.getTag()));
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

} // namespace idr::optimize::captures
