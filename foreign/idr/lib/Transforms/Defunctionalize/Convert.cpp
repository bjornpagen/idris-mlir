// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Every type and attribute the edits build, made by the decision on the
// pass thread before any worker runs, so a worker makes none: a slot's
// type is its key's family at the key's own variables, at the slot's
// grade; a signature is its slots' types, set on its function before any
// edit is read; a constant holding a closure is its label's constructor in
// its slot's family; a match over a family, at the depth it is built at,
// binds each state's binders as the next levels; a coercion rebuilds each
// state in the sink's family at the binders its case gives. A match and a
// coercion are each made once, whichever edit asks first.

#include "idr/Analysis/Labels.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallBitVector.h"

#include <numeric>

using namespace mlir;

namespace idr::defunctionalize {

// A slot's type: its key's family applied to the variables the carrier
// names, at the carrier's grade; any other type remade where its parts
// hold slots. Essential, two carriers: a family that holds no reference (a
// closure sum whose labels capture nothing) takes no hold, though the
// closure it stands for held one.
Type Decision::typeOf(Type type, const Slot &slot) {
  if (!slot)
    return replacer.replace(type);
  DataType at = familyOf(*slot).at;
  Grade grade = gradeOf(type);
  if (!holdsReferences(at))
    grade.hold = std::nullopt;
  return graded(grade, at);
}

Tag Decision::tagOf(const Key &key, FlatSymbolRefAttr label) const {
  return Tag{*labels.positionIn(key.labels, label)};
}

// Every function's type set to its converted signature here, serially,
// before any edit is read: a match's callees and a dispatch function's
// calls read their callees' converted types.
void Decision::convertSignatures() {
  for (FuncOp fn : program.getOps<FuncOp>()) {
    Signature &sig = signatures[fn.getSymNameAttr()];
    SmallVector<Type> inputs, results;
    for (auto [type, slot] : llvm::zip_equal(fn.getArgumentTypes(), sig.arguments))
      inputs.push_back(typeOf(type, slot));
    for (auto [type, slot] : llvm::zip_equal(fn.getResultTypes(), sig.results))
      results.push_back(typeOf(type, slot));
    sig.converted = FunctionType::get(ctx, inputs, results);
    fn.setFunctionType(sig.converted);
  }
}

// A constant held in `slot`, each closure in it its label's constructor in
// its slot's family, each constructor of a data family remade with its
// fields in their slots. A part shared by many constants is converted once
// per slot.
Attribute Decision::constantOf(Attribute value, const Slot &slot) {
  if (!holding.holds(value))
    return value;
  // A part is converted once per slot it is held in, the slot named by its
  // family's type, or by nothing where it holds no closure itself.
  auto keyFor = [&](Attribute part, const Slot &s) {
    return std::pair(part, s ? Attribute(TypeAttr::get(familyOf(*s).type)) : Attribute());
  };
  if (auto found = converted.find(keyFor(value, slot)); found != converted.end())
    return found->second;
  // The parts in post-order with their slots, each built once its fields are.
  struct Visit {
    Attribute part;
    Slot slot;
    bool expanded;
  };
  SmallVector<Visit> work{{value, slot, false}};
  auto fieldSlots = [&](Attribute part) {
    SmallVector<std::pair<Attribute, Slot>> out;
    if (auto closure = dyn_cast<ClosureAttr>(part)) {
      const Signature &sig = signature(closure.getCallee().getAttr());
      for (auto [i, capture] : llvm::enumerate(closure.getCaptures()))
        out.push_back({capture, sig.arguments[i]});
    } else if (auto con = dyn_cast<ConAttr>(part)) {
      DataType data = con.getData();
      con.walkFields([&](Attribute field, unsigned i) {
        out.push_back({field, anchorKey(FlowAnchor::fieldOf(data, con.getTag(), i))});
      });
    }
    return out;
  };
  while (!work.empty()) {
    Visit &visit = work.back();
    auto key = keyFor(visit.part, visit.slot);
    if (converted.contains(key) || !holding.holds(visit.part)) {
      if (!converted.contains(key))
        converted[key] = visit.part;
      work.pop_back();
      continue;
    }
    SmallVector<std::pair<Attribute, Slot>> parts = fieldSlots(visit.part);
    if (!visit.expanded) {
      visit.expanded = true;
      for (auto &[part, s] : parts)
        work.push_back({part, s, false});
      continue;
    }
    SmallVector<Attribute> fields;
    for (auto &[part, s] : parts)
      fields.push_back(converted.at(keyFor(part, s)));
    Attribute result;
    // A constant closure holds no index terms, so its label binds none its
    // family does not determine: a closure at terms folds to no constant.
    if (auto closure = dyn_cast<ClosureAttr>(visit.part)) {
      DataType family = familyOf(*visit.slot).at;
      result = ConAttr::get(ctx, family.refinedTo(tagOf(*visit.slot, closure.getCallee()), {}),
                            ArrayAttr::get(ctx, fields));
    } else {
      auto con = cast<ConAttr>(visit.part);
      result = ConAttr::get(ctx, replacer.replace(con.getType()), ArrayAttr::get(ctx, fields));
    }
    converted[key] = result;
    work.pop_back();
  }
  return converted.at(keyFor(value, slot));
}

// The constructor of `tag` in `family`, at `binders` where a case binds
// them, at `grade`: the type a data.con gives, refined to it, and each
// field as the constructor holds it.
Built Decision::constructorOf(DataType family, Tag tag, Grade grade,
                              ArrayRef<families::TermNode> binders) {
  DataType refined = family.refinedTo(tag, binders);
  return Built{graded(grade, refined), *refined.determinedFields(tag)};
}

IndexArgsAttr givenBinders(DataType family, Tag tag, IndexArgsAttr levels) {
  families::CtorView ctor = family.ctor(tag);
  size_t count = ctor.binders.size();
  // Where the indices determine every binder, the refined value keeps none
  // of its own, and its fields are at the terms they determine.
  if (DataType refined = family.refinedTo(tag, levels.getTerms()); refined.getBinders().empty())
    return IndexArgsAttr::get(family.getContext(), *refined.bindersOf(tag), count);
  size_t positions = family.getGroup().indices(family.getMember()).size();
  SmallVector<families::Term> given = families::termsOf(levels.getTerms(), count);
  SmallVector<families::Term> equation = families::termsOf(ctor.equation, positions);
  SmallVector<families::Term> indices = families::termsOf(family.getIndices(), positions);
  // Each binder takes the family's term at the first index that names it.
  llvm::SmallBitVector named(count);
  for (auto [term, index] : llvm::zip_equal(equation, indices))
    if (term.kind() == families::TermKind::Level && term.head().value < count &&
        !named.test(term.head().value)) {
      named.set(term.head().value);
      given[term.head().value] = index;
    }
  SmallVector<families::TermNode> nodes;
  for (const families::Term &term : given)
    llvm::append_range(nodes, term.nodes());
  return IndexArgsAttr::get(family.getContext(), nodes, count);
}

// A match over `value`'s family, built where `depth` index variables are
// bound: a case per state in tag order, each binding its constructor's
// binders as the levels from `depth` on, the value refined at its grade,
// its fields as a read of that gives them, and the terms its call gives
// its label; and, of a closure family, each label's function as its case
// calls it, at those terms. Every field position a read names has its
// index attribute.
MatchId Decision::matchOver(Type value, unsigned depth) {
  auto [found, fresh] =
      matchIds.try_emplace({value, depth}, static_cast<MatchId>(matches.size()));
  if (!fresh)
    return found->second;
  DataType family = cast<DataType>(unrestricted(value));
  Grade grade = gradeOf(value);
  Match made;
  auto states = static_cast<uint32_t>(family.declaredCount());
  SmallVector<int32_t> tags(states);
  std::iota(tags.begin(), tags.end(), 0);
  made.tags = DenseI32ArrayAttr::get(ctx, tags);
  for (uint32_t at = 0; at < states; ++at) {
    Tag tag{at};
    IndexArgsAttr binders = families::levelArgs(
        ctx, depth, static_cast<uint32_t>(family.binderSorts(tag).size()));
    Type refined = graded(grade, family.refinedTo(tag, binders.getTerms()));
    Case &taken = made.cases.emplace_back(
        Case{binders, givenBinders(family, tag, binders), refined, {}});
    unsigned count = static_cast<unsigned>(family.ctor(tag).fields.size());
    for (unsigned i = 0; i < count; ++i)
      taken.fields.push_back(*fieldReadType(taken.refined, i));
    while (fieldIndices.size() < count)
      fieldIndices.push_back(IntegerAttr::get(IntegerType::get(ctx, 64), fieldIndices.size()));
  }
  // Essential, two families: a closure family's cases call its labels; a
  // memo family's labels run in its dispatch function, and its cases call
  // none.
  if (std::optional<families::ClosuresView> closures = family.closures())
    for (auto [label, taken] : llvm::zip_equal(closures->labels(), made.cases))
      made.callees.push_back(
          Callee{labels.function(label.fn.getAttr()), label.fn,
                 families::substitute(signature(label.fn.getAttr()).converted, taken.given)});
  matches.push_back(std::move(made));
  return found->second;
}

// A move of a value of type `value`, of key `from`, into `to`, built where
// `depth` index variables are bound: the value at the sink's family, at
// its own uses; each state of `from`'s family rebuilt in `to`'s at the
// case's binders, at the sink's grade, which a reindex gives as the sink.
// A label is rebuilt as its own label there; running and forced, the
// states past a memo family's labels, as the same states past the sink's,
// a forced cell with its value and a running one with nothing.
CoercionId Decision::coercionOf(Type value, const Key &from, const Key &to, unsigned depth) {
  auto key = std::tuple(value, static_cast<unsigned>(idOf(to)), depth);
  if (auto found = coercionIds.find(key); found != coercionIds.end())
    return found->second;
  Type sink = typeOf(atUses(to.carrier, usesOf(value)), to);
  Coercion made = NeverRuns{sink};
  // A move from a family with no state never runs: a closure no label
  // reaches. A memo family always has its running and forced states.
  if (familyOf(from).at.declaredCount() != 0) {
    MatchId over = matchOver(value, depth);
    DataType target = familyOf(to).at;
    auto labelled = static_cast<uint32_t>(from.labels.size());
    auto past = static_cast<uint32_t>(to.labels.size());
    Rebuild rebuild{over, sink, {}};
    for (auto [at, taken] : llvm::enumerate(match(over).cases)) {
      auto state = static_cast<uint32_t>(at);
      Tag into = state < labelled ? tagOf(to, cast<FlatSymbolRefAttr>(from.labels[state]))
                                  : Tag{past + (state - labelled)};
      rebuild.into.push_back(constructorOf(target, into, gradeOf(sink), taken.binders.getTerms()));
    }
    made = std::move(rebuild);
  }
  auto id = static_cast<CoercionId>(coercions.size());
  coercions.push_back(std::move(made));
  coercionIds[key] = id;
  return id;
}

} // namespace idr::defunctionalize
