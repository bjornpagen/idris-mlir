// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Which integers are the lengths of which arrays. `related(n, a)` holds
// when, wherever `n` and `a` are both in scope, the array `a` has
// `max(n, 0)` elements: what `idr.array.new [%n]` gives, and what the
// program then carries apart.
//
// A component of a record has the length of the component the constructor
// stored. Two values one constructor built stay related after the record
// is taken apart; an array stored alone stays related to the size it was
// built with. The constructor is what pairs them. A read of another
// constructor's field is not that component, and a record no constructor in
// scope built pairs nothing. A size measured off the array (its dimension
// made i64) is its length, however the array was made: a length never
// changes, and the views of an array share it.
//
// The relation of a pair is decided by where its values come from. An
// array made of a size relates to that size. A pair bound at one join (two
// arguments of one function, of one loop, two results of one region op or
// call) is related when every place binding them gives a related pair; a
// value bound at a join and one fixed around it (a size defined before the
// loop that carries the array) when every place gives a value related to
// the fixed one. A call that gives the array back is that array, so the
// pair is the one the caller passed; a size the same call gives back as an
// argument is that argument too. Pairs reach each other in cycles (a loop
// gives back what it took), so the answer is the greatest fixpoint: every
// pair reached is taken to hold, and each that needs a pair that fails, or
// that comes from anything else, fails, until none changes. What remains
// holds by induction over the run: each binding of a pair that holds is
// made of pairs that held. A poison array is no array any access may read,
// so it relates to every size; a poison record likewise holds no component
// an access may read. A poison size relates to no array, since an access
// that never branches on it would read the array unchecked.
//
// The graph has four kinds of node: a size and an array; a size and an
// array field of a record; the size field and the array field of a record;
// and an interface, a pair bound at a function's parameters or results.
// The constructor of Lengths expands an interface into the pairs its places
// bind; the Local of one function reads it from the table, so no question
// of a function walks another.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/Transforms/InBounds.h"

#include "mlir/Dialect/UB/IR/UBOps.h"

#include "llvm/ADT/STLExtras.h"

#include <algorithm>

using namespace mlir;

namespace idr::inbounds {

namespace {

// Past this many nodes reached from one question, the rest fail: an answer
// is then only weaker. Past this many records followed in one chain, or
// calls followed back to the array they were given, the same.
constexpr size_t pairLimit = 4096;
constexpr unsigned walkLimit = 64;

} // namespace

bool Lengths::Local::related(Value size, Value array) {
  // A call that returns the array it was given is that array. Follow it
  // before the pair is asked, a bounded number of times: each step is an
  // operand of the call, and past the bound the pair stays unrelated.
  array = arrayRoot(array);
  for (unsigned hop = 0; hop < walkLimit; ++hop) {
    std::optional<GivenBack> back = givenBack(array);
    if (!back || back->value == array)
      break;
    if (std::optional<GivenBack> sizeBack = givenBack(size); sizeBack && sizeBack->call == back->call)
      size = sizeBack->value;
    array = arrayRoot(back->value);
  }
  Question start;
  start.a = size;
  start.b = array;
  return holds(start);
}

bool Lengths::Local::holds(const Question &question) {
  SmallVector<unsigned> fresh;
  unsigned id = nodeOf(question, fresh);
  if (!fresh.empty())
    solve(fresh);
  return nodes[id].state == State::Held;
}

unsigned Lengths::Local::nodeOf(const Question &question, SmallVectorImpl<unsigned> &fresh) {
  auto id = static_cast<unsigned>(nodes.size());
  bool inserted = false;
  if (question.kind == Kind::Interface) {
    auto [it, made] = interfaceNodes.try_emplace(question.key.tuple(), id);
    id = it->second;
    inserted = made;
  } else {
    auto [it, made] = valueNodes.try_emplace(ValueKey{static_cast<unsigned>(question.kind), question.a,
                                                      question.b, question.ctor, question.i,
                                                      question.j},
                                             id);
    id = it->second;
    inserted = made;
  }
  if (inserted) {
    nodes.push_back(Node{question});
    fresh.push_back(id);
  }
  return id;
}

// Reaches every node the question `fresh` holds needs that no earlier
// question reached, then takes the greatest fixpoint over them. A node
// reached earlier is settled: everything it needs was reached and settled
// with it.
void Lengths::Local::solve(SmallVectorImpl<unsigned> &fresh) {
  SmallVector<unsigned> broken;
  for (size_t next = 0; next < fresh.size(); ++next) {
    unsigned id = fresh[next];
    std::optional<SmallVector<Question>> needs =
        fresh.size() > pairLimit ? std::nullopt : needsOf(nodes[id].question);
    if (!needs) {
      nodes[id].state = State::Broken;
      broken.push_back(id);
      continue;
    }
    for (const Question &need : *needs) {
      unsigned other = nodeOf(need, fresh);
      nodes[id].needs.push_back(other);
      nodes[other].neededBy.push_back(id);
    }
  }
  for (unsigned id : fresh)
    if (nodes[id].state == State::Open &&
        llvm::any_of(nodes[id].needs, [&](unsigned n) { return nodes[n].state == State::Broken; })) {
      nodes[id].state = State::Broken;
      broken.push_back(id);
    }
  while (!broken.empty()) {
    unsigned id = broken.pop_back_val();
    for (unsigned user : nodes[id].neededBy)
      if (nodes[user].state == State::Open) {
        nodes[user].state = State::Broken;
        broken.push_back(user);
      }
  }
  for (unsigned id : fresh)
    if (nodes[id].state == State::Open)
      nodes[id].state = State::Held;
}

std::optional<SmallVector<Lengths::Local::Question>>
Lengths::Local::needsOf(const Question &question) {
  switch (question.kind) {
  case Kind::Pair:
    return pairNeeds(question.a, question.b);
  case Kind::Component:
    return componentNeeds(question);
  case Kind::Fields:
    return fieldNeeds(question);
  case Kind::Interface:
    return interfaceNeeds(question.key);
  }
  return std::nullopt;
}

std::optional<SmallVector<Lengths::Local::Question>> Lengths::Local::pairNeeds(Value size,
                                                                               Value array) {
  auto pair = [](Value n, Value a) {
    Question q;
    q.a = n;
    q.b = arrayRoot(a);
    return q;
  };
  SmallVector<Question> needs;
  if (array.getDefiningOp<ub::PoisonOp>())
    return needs;
  if (std::optional<Value> of = measured(size); of && arrayRoot(*of) == arrayRoot(array))
    return needs;
  // An array read out of a record is the component its constructor stored.
  if (std::optional<Component> part = componentOf(arrayRoot(array))) {
    Question q;
    q.kind = Kind::Component;
    q.a = size;
    q.b = part->record;
    q.ctor = part->ctor;
    q.i = static_cast<unsigned>(part->index);
    needs.push_back(q);
    return needs;
  }
  std::optional<Join> sizeJoin = joinOf(size, *this);
  std::optional<Join> arrayJoin = joinOf(array, *this);
  if (sizeJoin && arrayJoin && sizeJoin->key == arrayJoin->key) {
    if (!sizeJoin->local) {
      Question q;
      q.kind = Kind::Interface;
      q.key = {sizeJoin->function, sizeJoin->side, InterfaceKey::Shape::Pair, sizeJoin->position,
               arrayJoin->position};
      needs.push_back(q);
      return needs;
    }
    for (auto [n, a] : llvm::zip_equal(sizeJoin->incoming, arrayJoin->incoming))
      needs.push_back(pair(n, a));
    return needs;
  }
  if (arrayJoin && arrayJoin->local && dominance().properlyDominates(size, arrayJoin->owner)) {
    for (Value a : arrayJoin->incoming)
      needs.push_back(pair(size, a));
    return needs;
  }
  if (sizeJoin && sizeJoin->local && dominance().properlyDominates(array, sizeJoin->owner)) {
    for (Value n : sizeJoin->incoming)
      needs.push_back(pair(n, array));
    return needs;
  }
  Value made;
  // A guarded array has one dimension, so one size.
  if (auto fresh = array.getDefiningOp<ArrayNewOp>(); fresh && fresh.getSizes().size() == 1)
    made = fresh.getSizes().front();
  else if (auto generated = array.getDefiningOp<ArrayGenerateOp>())
    made = generated.getSize();
  if (!made || !clampsEqual(size, made))
    return std::nullopt;
  return needs;
}

// The size `a` and the array field `i` of constructor `ctor` of the record
// `b`. Empty when the record is the program's poison, which no run reads.
// None when some construction does not show the component.
std::optional<SmallVector<Lengths::Local::Question>>
Lengths::Local::componentNeeds(const Question &question) {
  Value size = question.a;
  Value record = arrayRoot(question.b);
  SmallVector<Question> needs;
  if (record.getDefiningOp<ub::PoisonOp>())
    return needs;
  auto component = [&](Value n, Value in) {
    Question q = question;
    q.a = n;
    q.b = in;
    ++q.depth;
    return q;
  };
  // Both reads are of this same record: its two stored components are
  // paired, not the reads themselves.
  if (std::optional<Component> sizePart = componentOf(arrayRoot(size));
      sizePart && sizePart->ctor == question.ctor && arrayRoot(sizePart->record) == record) {
    Question q;
    q.kind = Kind::Fields;
    q.a = record;
    q.ctor = question.ctor;
    q.i = static_cast<unsigned>(sizePart->index);
    q.j = question.i;
    q.depth = question.depth;
    needs.push_back(q);
    return needs;
  }
  if (auto con = record.getDefiningOp<ConOp>()) {
    if (con.getCtor().getLeafReference() != question.ctor || question.i >= con.getFields().size())
      return std::nullopt;
    Question q;
    q.a = size;
    q.b = arrayRoot(con.getFields()[question.i]);
    needs.push_back(q);
    return needs;
  }
  std::optional<Join> recordJoin = joinOf(record, *this);
  if (!recordJoin || question.depth >= walkLimit)
    return std::nullopt;
  std::optional<Join> sizeJoin = joinOf(size, *this);
  if (sizeJoin && sizeJoin->key == recordJoin->key &&
      sizeJoin->incoming.size() == recordJoin->incoming.size()) {
    if (!recordJoin->local) {
      Question q;
      q.kind = Kind::Interface;
      q.key = {recordJoin->function, recordJoin->side, InterfaceKey::Shape::Component,
               sizeJoin->position, recordJoin->position, question.ctor, question.i};
      needs.push_back(q);
      return needs;
    }
    for (auto [n, in] : llvm::zip_equal(sizeJoin->incoming, recordJoin->incoming))
      needs.push_back(component(n, in));
    return needs;
  }
  if (recordJoin->local && dominance().properlyDominates(size, recordJoin->owner)) {
    for (Value in : recordJoin->incoming)
      needs.push_back(component(size, in));
    return needs;
  }
  return std::nullopt;
}

// The size field `i` and the array field `j` of constructor `ctor` of the
// record `a`, the two components it stored.
std::optional<SmallVector<Lengths::Local::Question>>
Lengths::Local::fieldNeeds(const Question &question) {
  Value record = arrayRoot(question.a);
  SmallVector<Question> needs;
  // The program's poison is a record no run reads a component of.
  if (record.getDefiningOp<ub::PoisonOp>())
    return needs;
  if (auto con = record.getDefiningOp<ConOp>()) {
    OperandRange fields = con.getFields();
    if (con.getCtor().getLeafReference() != question.ctor || question.i >= fields.size() ||
        question.j >= fields.size())
      return std::nullopt;
    Question q;
    q.a = arrayRoot(fields[question.i]);
    q.b = arrayRoot(fields[question.j]);
    needs.push_back(q);
    return needs;
  }
  std::optional<Join> join = joinOf(record, *this);
  if (!join || question.depth >= walkLimit)
    return std::nullopt;
  if (!join->local) {
    Question q;
    q.kind = Kind::Interface;
    q.key = {join->function, join->side, InterfaceKey::Shape::Fields, join->position,
             join->position, question.ctor, question.i, question.j};
    needs.push_back(q);
    return needs;
  }
  for (Value in : join->incoming) {
    Question q = question;
    q.a = in;
    ++q.depth;
    needs.push_back(q);
  }
  return needs;
}

// A function's Local reads an interface from the table. The constructor's
// follows it into every place that binds it: each call of the function for
// its parameters, each of its returns for its results.
std::optional<SmallVector<Lengths::Local::Question>>
Lengths::Local::interfaceNeeds(const InterfaceKey &key) {
  SmallVector<Question> needs;
  if (!expands())
    return lengths().interface(key) ? std::optional(needs) : std::nullopt;
  auto function = cast<FuncOp>(key.function);
  SmallVector<OperandRange> places;
  if (key.side == InterfaceKey::Side::Parameters) {
    const SmallVector<CallOp> *sites = lengths().callsOf(function);
    if (!sites)
      return std::nullopt;
    for (CallOp call : *sites)
      places.push_back(call.getArgOperands());
  } else {
    if (function.isExternal())
      return std::nullopt;
    for (ReturnOp ret : lengths().returnsOf(function))
      places.push_back(ret.getOperands());
  }
  unsigned used = std::max(key.first, key.second);
  for (OperandRange values : places) {
    if (used >= values.size())
      return std::nullopt;
    Question q;
    q.a = values[key.first];
    switch (key.shape) {
    case InterfaceKey::Shape::Pair:
      q.b = arrayRoot(values[key.second]);
      break;
    case InterfaceKey::Shape::Component:
      q.kind = Kind::Component;
      q.b = values[key.second];
      q.ctor = key.ctor;
      q.i = key.field;
      break;
    case InterfaceKey::Shape::Fields:
      q.kind = Kind::Fields;
      q.ctor = key.ctor;
      q.i = key.field;
      q.j = key.other;
      break;
    }
    needs.push_back(q);
  }
  return needs;
}

} // namespace idr::inbounds
