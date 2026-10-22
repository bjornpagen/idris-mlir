// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Every type and attribute the edits build, made by the decision on the
// pass thread before any worker runs, so a worker makes none: a slot's
// type is its key's family at the key's own variables, at the slot's
// grade; a signature is its slots' types, set on its function before any
// edit is read; a constant holding a closure is its label's constructor in
// its slot's family; a match over a family, at the depth it is built at,
// binds each state's binders as the next levels; a coercion rebuilds each
// state in the sink's family, where the move lands, at the binders its case
// gives. A match and a coercion are each made once, whichever edit asks
// first.

#include "idr/Analysis/Labels.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Families/Unify.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Nest.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/STLExtras.h"

#include <iterator>
#include <numeric>

using namespace mlir;

namespace idr::defunctionalize {

namespace {

// A slot's family at some terms, at the grade `type` has. Essential, two
// carriers: a family that holds no reference (a closure sum whose labels
// capture nothing) takes no hold, though the closure it stands for held one.
Type heldAt(Type type, DataType at) {
  Grade grade = gradeOf(type);
  if (!holdsReferences(at))
    grade.hold = std::nullopt;
  return graded(grade, at);
}

} // namespace

// A slot's type: its key's family applied to the index terms the carrier
// names, at the carrier's grade; any other type remade where its parts
// hold slots.
Type Decision::typeOf(Type type, const Slot &slot) {
  if (!slot)
    return replacer.replace(type);
  return heldAt(type, familyOf(*slot).at);
}

Tag Decision::tagOf(const Key &key, FlatSymbolRefAttr label) const {
  return Tag{*labels.positionIn(key.labels, label)};
}

// Every function's type set to its converted signature here, serially,
// before any edit is read: a match's callees and a dispatch function's
// calls read their callees' converted types.
void Decision::convertSignatures() {
  for (FuncOp fn : program.getOps<FuncOp>()) {
    Signature &sig = signatures[graph.id(fn)];
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
  // A part in the slot it is held in. It is converted once per slot, the
  // slot named by its family's type, or by nothing where it holds no
  // closure itself.
  struct Part {
    Attribute value;
    Slot slot;
    Attribute in;
  };
  auto partIn = [&](Attribute part, const Slot &s) {
    return Part{part, s, s ? Attribute(TypeAttr::get(familyOf(*s).type)) : Attribute()};
  };
  // A part's fields in their slots, in the order the part holds them: a
  // closure's captures as its function's leading parameters, a constructor's
  // fields cell by cell along its run.
  auto fieldsOf = [&](const Part &part) {
    SmallVector<Part> out;
    if (auto closure = dyn_cast<ClosureAttr>(part.value)) {
      const Signature &sig = signature(graph.id(closure.getCallee()));
      for (auto [i, capture] : llvm::enumerate(closure.getCaptures()))
        out.push_back(partIn(capture, sig.arguments[i]));
    } else if (auto con = dyn_cast<ConAttr>(part.value)) {
      DataType data = con.getData();
      con.walkFields([&](Attribute field, unsigned i) {
        out.push_back(partIn(field, anchorKey(FlowAnchor::fieldOf(data, con.getTag(), i))));
      });
    }
    return out;
  };
  // The parts in post-order. Each part's converted form is pushed once its
  // fields' are, which it takes off the top in the order it holds them; a
  // part converted before, or holding no closure, is pushed as it is and
  // not gone into.
  SmallVector<Attribute> done;
  depthFirst(
      partIn(value, slot), fieldsOf,
      [&](const Part &part) {
        if (auto found = converted.find(std::pair(part.value, part.in)); found != converted.end()) {
          done.push_back(found->second);
          return Descend::Past;
        }
        if (!holding.holds(part.value)) {
          done.push_back(part.value);
          return Descend::Past;
        }
        return Descend::Into;
      },
      [&](const Part &part) {
        Attribute result;
        // A constant closure holds no index terms, so its label binds none
        // its family does not determine: a closure at terms folds to no
        // constant.
        if (auto closure = dyn_cast<ClosureAttr>(part.value)) {
          auto fields = ArrayRef<Attribute>(done).take_back(closure.getCaptures().size());
          DataType family = familyOf(*part.slot).at;
          result = ConAttr::get(ctx, family.refinedTo(tagOf(*part.slot, closure.getCallee()), {}),
                                ArrayAttr::get(ctx, fields));
          done.truncate(done.size() - fields.size());
        } else {
          // A run is rebuilt cell by cell, each cell its own fields, so it
          // stays one run in the converted family.
          auto con = cast<ConAttr>(part.value);
          size_t held = 0;
          for (unsigned cell = 0; cell < con.getRunLength(); ++cell)
            held += con.getCell(cell).size();
          ArrayRef<Attribute> fields = ArrayRef<Attribute>(done).take_back(held);
          SmallVector<ArrayAttr> cells;
          for (unsigned cell = 0; cell < con.getRunLength(); ++cell) {
            size_t width = con.getCell(cell).size();
            cells.push_back(ArrayAttr::get(ctx, fields.take_front(width)));
            fields = fields.drop_front(width);
          }
          result = ConAttr::getRun(ctx, cast<DataType>(replacer.replace(con.getData())),
                                   static_cast<unsigned>(con.getSpine()), cells);
          done.truncate(done.size() - held);
        }
        converted[std::pair(part.value, part.in)] = result;
        done.push_back(result);
      });
  return done.back();
}

// The constructor of `tag` in `family`, at `binders` where a case binds
// them, at `grade`: the type a data.con gives, refined to it, and each
// field as the constructor holds it.
Built Decision::constructorOf(DataType family, Tag tag, Grade grade,
                              ArrayRef<families::TermNode> binders) {
  DataType refined = family.refinedTo(tag, binders);
  return Built{graded(grade, refined), *refined.determinedFields(tag)};
}

// The family's indices are rigid, the state's binders the unknowns, as a
// type's own binders are read: one unification, whose binding of each
// binder is written in the case's scope, an unbound one as the case's level
// from `depth` on. A state the indices exclude is a case never entered, so
// what its call would be given is never read, and its binders are levels.
IndexArgsAttr givenBinders(DataType family, Tag tag, unsigned depth) {
  MLIRContext *ctx = family.getContext();
  families::CtorView ctor = family.ctor(tag);
  auto count = static_cast<std::uint32_t>(ctor.binders.size());
  ArrayRef<families::TermNode> indices = family.getIndices();
  families::Subst subst(families::freeLevelsOf(indices), count, families::Freedom::Rigid,
                        families::Freedom::Unknown, families::Opacity::MeetsAnything,
                        family.getGroup());
  if (families::unifyAll(subst, indices, ctor.equation,
                         family.getGroup().indices(family.getMember()).size()) ==
      families::Unified::Clash)
    return families::levelArgs(ctx, depth, count);
  SmallVector<families::TermNode> nodes;
  families::TermWriter write(nodes);
  families::TermNode binder{TermKind::Level, 0, 0, 0, Attribute()};
  for (std::uint32_t at = 0; at < count; ++at) {
    binder.value = at;
    subst.write(write, families::Term(ArrayRef<families::TermNode>(binder)),
                families::Side::Constructor, depth);
  }
  return IndexArgsAttr::get(ctx, nodes, count);
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
  Match built;
  auto states = static_cast<uint32_t>(family.declaredCount());
  SmallVector<int32_t> tags(states);
  std::iota(tags.begin(), tags.end(), 0);
  built.tags = DenseI32ArrayAttr::get(ctx, tags);
  for (uint32_t at = 0; at < states; ++at) {
    Tag tag{at};
    IndexArgsAttr binders = families::levelArgs(
        ctx, depth, static_cast<uint32_t>(family.binderSorts(tag).size()));
    Type refined = graded(grade, family.refinedTo(tag, binders.getTerms()));
    Case &taken =
        built.cases.emplace_back(Case{binders, givenBinders(family, tag, depth), refined, {}});
    unsigned count = static_cast<unsigned>(family.ctor(tag).fields.size());
    for (unsigned i = 0; i < count; ++i)
      taken.fields.push_back(*fieldReadType(taken.refined, i));
    while (fieldIndices.size() < count)
      fieldIndices.push_back(IntegerAttr::get(IntegerType::get(ctx, 64), std::ssize(fieldIndices)));
  }
  // Essential, two families: a closure family's cases call its labels; a
  // memo family's labels run in its dispatch function, and its cases call
  // none. A case calls its label's own function, never a copy, so its
  // operands are given at that function's parameter types at the case's
  // terms, which the converted signature read with no extents is: extents
  // only make a bare tensor input's axis static where a term is a size, a
  // type only a copy takes, while a closure's carrier and its family's
  // fields keep `?` there as the function does, and a call meets its
  // callee's view by shape compatibility. Its results are the function's
  // either way.
  if (std::optional<families::ClosuresView> closures = family.closures())
    for (auto [label, taken] : llvm::zip_equal(closures->labels(), built.cases)) {
      FunctionType bound = families::substitute(signature(graph.id(label.fn)).converted,
                                                ExtentsAttr(), taken.given);
      built.callees.push_back(Callee{labels.function(label.fn.getAttr()), label.fn, bound});
    }
  matches.push_back(std::move(built));
  return found->second;
}

// A move of a value of type `value`, of key `from`, into `to`, built where
// `depth` index variables are bound: the value at the sink's family, at
// its own uses; each state of `from`'s family rebuilt in `to`'s at the
// case's binders, at the sink's grade, which a reindex gives as the sink.
// A label is rebuilt as its own label there; running and forced, the
// states past a memo family's labels, as the same states past the sink's,
// a forced cell with its value and a running one with nothing.
//
// The sink's family is at the terms the value's family is at, so the sink
// is in the scope the move lands in: a value is its sink there, the two
// carriers one type up to their terms, so the two families name as many,
// each at the other's place. A key's own terms are of the scope it was
// named in, a callee's for its parameter, which no reader translates.
CoercionId Decision::coercionOf(Type value, const Key &from, const Key &to, unsigned depth) {
  auto key = std::tuple(value, static_cast<unsigned>(idOf(to)), depth);
  if (auto found = coercionIds.find(key); found != coercionIds.end())
    return found->second;
  DataType family = familyOf(to).type;
  DataType target = DataType::get(ctx, family.getGroup(), family.getMember(),
                                  cast<DataType>(unrestricted(value)).getIndices());
  Type sink = heldAt(atUses(to.carrier, usesOf(value)), target);
  Coercion answer = NeverRuns{sink};
  // A move from a family with no state never runs: a closure no label
  // reaches. A memo family always has its running and forced states.
  if (familyOf(from).at.declaredCount() != 0) {
    MatchId over = matchOver(value, depth);
    auto labelled = static_cast<uint32_t>(from.labels.size());
    auto past = static_cast<uint32_t>(to.labels.size());
    Rebuild rebuild{over, sink, {}};
    for (auto [at, taken] : llvm::enumerate(match(over).cases)) {
      auto state = static_cast<uint32_t>(at);
      Tag into = state < labelled ? tagOf(to, cast<FlatSymbolRefAttr>(from.labels[state]))
                                  : Tag{past + (state - labelled)};
      rebuild.into.push_back(constructorOf(target, into, gradeOf(sink), taken.binders.getTerms()));
    }
    answer = std::move(rebuild);
  }
  auto id = static_cast<CoercionId>(coercions.size());
  coercions.push_back(std::move(answer));
  coercionIds[key] = id;
  return id;
}

} // namespace idr::defunctionalize
