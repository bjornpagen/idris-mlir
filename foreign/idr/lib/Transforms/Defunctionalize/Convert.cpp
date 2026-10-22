// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Every type and attribute the edits build, made by the decision on the
// pass thread before any worker runs, so a worker makes none: a slot's
// type is its key's family at the key's own variables, at the slot's
// grade; a signature is its slots' types, set on its function before any
// edit is read; a constant holding a closure is its label's constructor in
// its slot's family; a match over a family, at the depth it is built at,
// binds each label's binders as the next levels; a coercion rebuilds each
// label's constructor in the sink's family at those binders. A match and a
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

// A match over `value`'s family, whose labels are `set` in tag order,
// built where `depth` index variables are bound: each case binds its
// constructor's binders as the levels from `depth` on, the value refined
// at its grade, and its fields as a read of that gives them; each label's
// function is called at those binders. Every field position a read names
// has its index attribute.
MatchId Decision::matchOver(Type value, unsigned depth, ArrayAttr set) {
  auto [found, fresh] =
      matchIds.try_emplace({value, depth}, static_cast<MatchId>(matches.size()));
  if (!fresh)
    return found->second;
  DataType family = cast<DataType>(unrestricted(value));
  Grade grade = gradeOf(value);
  Match made;
  SmallVector<int32_t> tags(set.size());
  std::iota(tags.begin(), tags.end(), 0);
  made.tags = DenseI32ArrayAttr::get(ctx, tags);
  for (auto [at, label] : llvm::enumerate(set.getAsRange<FlatSymbolRefAttr>())) {
    Tag tag{static_cast<uint32_t>(at)};
    IndexArgsAttr binders = families::levelArgs(
        ctx, depth, static_cast<uint32_t>(family.binderSorts(tag).size()));
    Type refined = graded(grade, family.refinedTo(tag, binders.getTerms()));
    Case &taken = made.cases.emplace_back(Case{binders, refined, {}});
    unsigned count = static_cast<unsigned>(family.ctor(tag).fields.size());
    for (unsigned i = 0; i < count; ++i)
      taken.fields.push_back(*fieldReadType(refined, i));
    while (fieldIndices.size() < count)
      fieldIndices.push_back(IntegerAttr::get(IntegerType::get(ctx, 64), fieldIndices.size()));
    made.callees.push_back(
        Callee{labels.function(label.getAttr()), label,
               families::substitute(signature(label.getAttr()).converted, binders)});
  }
  matches.push_back(std::move(made));
  return found->second;
}

// A move of a value of type `value`, of key `from`, into `to`, built where
// `depth` index variables are bound: the value at the sink's family, at
// its own uses; each of `from`'s constructors rebuilt in `to`'s at the
// case's binders, at the sink's grade, which a reindex gives as the sink.
CoercionId Decision::coercionOf(Type value, const Key &from, const Key &to, unsigned depth) {
  auto key = std::tuple(value, static_cast<unsigned>(idOf(to)), depth);
  if (auto found = coercionIds.find(key); found != coercionIds.end())
    return found->second;
  Type sink = typeOf(atUses(to.carrier, usesOf(value)), to);
  Coercion made = NeverRuns{sink};
  // A move no label reaches never runs.
  if (!from.labels.empty() && !to.labels.empty()) {
    MatchId over = matchOver(value, depth, from.labels);
    DataType target = familyOf(to).at;
    Rebuild rebuild{over, sink, {}};
    for (auto [at, label] : llvm::enumerate(from.labels.getAsRange<FlatSymbolRefAttr>()))
      rebuild.into.push_back(constructorOf(target, tagOf(to, label), gradeOf(sink),
                                           match(over).cases[at].binders.getTerms()));
    made = std::move(rebuild);
  }
  auto id = static_cast<CoercionId>(coercions.size());
  coercions.push_back(std::move(made));
  coercionIds[key] = id;
  return id;
}

} // namespace idr::defunctionalize
