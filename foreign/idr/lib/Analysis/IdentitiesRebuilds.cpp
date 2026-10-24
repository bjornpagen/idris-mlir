// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a function gives back under what is assumed of its callees, read off
// the record of its one walk.
//
// A part of an argument is a path from it, each step a field of a
// constructor or the predecessor of a natural. Two values that take the
// same path are the same part however each was read: values never change.
// One loop over the record's values, ascending, finds the part each value
// rebuilds, if any, after every value it is made of:
// - the argument itself, the same value as one that rebuilds a part, a
//   field of one, the predecessor of one;
// - a call's result where its callee gives back a part of one of the
//   call's arguments;
// - a constructor whose every field rebuilds the same field of one part
//   (a field is read only of a value refined to its constructor, so that
//   part is that constructor), or, with no fields, inside a case of that
//   constructor on that part;
// - the successor of a part's predecessor;
// - a match whose every region that yields rebuilds one part;
// - a constant inside a case that says the part is it, at its use: a
//   fieldless constructor in a case or default of that constructor, a
//   literal in a literal match's case of that literal.
//
// What may reach a result is the other reading, a sound bound where the
// first is exact. One loop ascending gives each value the arguments it may
// hold on some path, each whole or by a part, after every value it is made
// of; a value that holds no reference holds none:
// - the argument itself, whole; the same value as another, or the
//   successor of one, what that one holds;
// - a field of a value, or the predecessor of one, a part of everything
//   that value holds, since a field of an argument is a part of it and a
//   field of what holds an argument may be the argument;
// - a constructor, what each of its fields holds; a match, what each region
//   that yields gives;
// - a call's result, what each argument its callee lets reach that result
//   holds, whole only where both reach whole;
// - an op's own result, a part of what its operands hold, or, for an op
//   that only changes a grade, what its operand holds;
// - what a region branch forwards into, what each value entering it holds;
//   one may enter from later in the walk, around a loop, so where one did
//   the loop goes round again, until no value holds more, which it does
//   after finitely many rounds, each argument reaching each value at most
//   whole and then by a part;
// - any other region's argument, or what any other op with regions gives,
//   which nothing here reads, a part of every argument that holds
//   references;
// - a constant, nothing.
// The record is never written; a reading holds what it learns while it
// answers.
#include "idr/Analysis/Solver/IdentityRecords.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Match.h"

#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <concepts>
#include <cstddef>
#include <iterator>
#include <optional>
#include <tuple>
#include <utility>

using namespace mlir;

namespace idr::identities {

namespace {

enum class PartId : std::uint32_t {};

// A case for several builds names them.
template <class B, class... Builds>
concept OneOf = (std::same_as<B, Builds> || ...);

// The constructor a type fixes, where it fixes one: a data type refined to
// one constructor, or with one its indices leave; and the type of its
// field at `index`.
std::optional<Tag> fixedTag(Type type) {
  auto data = dyn_cast_if_present<DataType>(type ? unrestricted(type) : Type());
  if (!data)
    return std::nullopt;
  return data.singleTag();
}
Type fieldType(Type type, Tag tag, std::uint32_t index) {
  return unrestricted(cast<DataType>(unrestricted(type)).ctor(tag).fields[index]);
}

// The parts of every argument met so far, each once.
class Parts {
public:
  explicit Parts(const Record &record) {
    for (auto [at, type] : llvm::enumerate(record.argumentTypes))
      rows.push_back({static_cast<std::uint32_t>(at), std::nullopt, type});
  }

  PartId whole(std::uint32_t argument) const { return PartId(argument); }

  PartId step(PartId parent, Step step, Type type) {
    auto key = match(
        step,
        [&](const Field &field) {
          return std::make_tuple(raw(parent), 0u,
                                 std::pair(std::to_underlying(field.tag), field.index));
        },
        [&](Predecessor) { return std::make_tuple(raw(parent), 1u, std::pair(0u, 0u)); });
    auto [it, made] = steps.try_emplace(key, static_cast<std::uint32_t>(rows.size()));
    if (made)
      rows.push_back({rows[raw(parent)].argument, Below{raw(parent), step}, Type()});
    Row &row = rows[it->second];
    if (!row.type && type)
      row.type = unrestricted(type);
    return PartId(it->second);
  }

  // The parent of `part`, if `part` is the step `step` below it.
  std::optional<PartId> below(PartId part, Step step) const {
    const Row &row = rows[raw(part)];
    if (!row.below || row.below->step != step)
      return std::nullopt;
    return PartId(row.below->parent);
  }

  std::uint32_t argumentOf(PartId part) const { return rows[raw(part)].argument; }

  // The steps from the argument down to `part`, outermost first.
  footprint::Vector<Step> stepsOf(PartId part) const {
    footprint::Vector<Step> down;
    for (const Row *row = &rows[raw(part)]; row->below; row = &rows[row->below->parent])
      down.push_back(row->below->step);
    std::reverse(down.begin(), down.end());
    return down;
  }

  Type typeOf(PartId part) const { return rows[raw(part)].type; }

  // Whether a value of `type` may be `part`: the part's type is known (a
  // value made it) and represented alike.
  bool fits(PartId part, Type type) const {
    Type known = rows[raw(part)].type;
    return known && representation(known, type) == Represents::Alike;
  }

private:
  static std::uint32_t raw(PartId part) { return std::to_underlying(part); }

  // A part below another: its parent and the step down from it. An
  // argument's whole is below nothing.
  struct Below {
    std::uint32_t parent;
    Step step;
  };
  struct Row {
    std::uint32_t argument;
    std::optional<Below> below;
    // With no grade; null where only a callee's fact made the part.
    Type type;
  };
  footprint::Vector<Row> rows;
  // Each part below another, by its parent, the step's kind and the step.
  footprint::DenseMap<std::tuple<std::uint32_t, std::uint32_t, std::pair<std::uint32_t, std::uint32_t>>,
                      std::uint32_t>
      steps;
};

class Reading {
public:
  Reading(const Record &record, std::span<const FactsView> callees)
      : record(record), callees(callees), parts(record),
        equal(record.values, std::optional<PartId>()) {
    for (ValueId value : record.values.ids())
      equal[value] = rebuilt(value);
  }

  // The part `value` rebuilds where it is used under `frames`.
  std::optional<PartId> at(ValueId value, std::span<const Frame> frames) const {
    if (equal[value])
      return equal[value];
    return match(
        record.builds[value],
        [&](const build::Constant &constant) {
          return inCase(constant.known, constant.type, frames);
        },
        []<OneOf<build::Opaque, build::Forwarded, build::Unseen, build::Entry, build::Same,
                 build::Read, build::Pred, build::Result, build::Con, build::Successor,
                 build::Join> B>(const B &) -> std::optional<PartId> { return std::nullopt; });
  }

  const Record &record;
  std::span<const FactsView> callees;
  Parts parts;

private:
  // The part a case around a use says is `known`, where a value of `type`
  // that is `known` is it: the scrutinee of the innermost such case.
  std::optional<PartId> inCase(const Known &known, Type type, std::span<const Frame> frames) const {
    for (const Frame &frame : frames)
      if (frame.known == known)
        if (std::optional<PartId> part = equal[frame.scrutinee]; part && parts.fits(*part, type))
          return part;
    return std::nullopt;
  }

  std::optional<PartId> rebuilt(ValueId value);
  std::optional<PartId> ofCon(const build::Con &con);
  std::optional<PartId> ofJoin(const build::Join &join);
  std::optional<PartId> ofResult(const build::Result &result);

  IndexVector<ValueId, std::optional<PartId>> equal;
};

std::optional<PartId> Reading::rebuilt(ValueId value) {
  return match(
      record.builds[value],
      [](const OneOf<build::Opaque, build::Forwarded, build::Unseen> auto &)
          -> std::optional<PartId> { return std::nullopt; },
      [](const build::Constant &) -> std::optional<PartId> { return std::nullopt; },
      [&](const build::Entry &entry) -> std::optional<PartId> {
        return parts.whole(entry.argument);
      },
      [&](const build::Same &same) { return equal[same.of]; },
      [&](const build::Read &read) -> std::optional<PartId> {
        if (std::optional<PartId> of = equal[read.of])
          return parts.step(*of, read.field, read.type);
        return std::nullopt;
      },
      [&](const build::Pred &pred) -> std::optional<PartId> {
        if (std::optional<PartId> of = equal[pred.of])
          return parts.step(*of, Predecessor{}, Type());
        return std::nullopt;
      },
      [&](const build::Successor &successor) -> std::optional<PartId> {
        if (std::optional<PartId> of = equal[successor.of])
          return parts.below(*of, Predecessor{});
        return std::nullopt;
      },
      [&](const build::Result &result) { return ofResult(result); },
      [&](const build::Con &con) { return ofCon(con); },
      [&](const build::Join &join) { return ofJoin(join); });
}

// A callee's fact for this result, whole, applied to the call's argument:
// each field of its argument path is of a type that fixes its constructor,
// so each step's constructor is read off the part's type as it descends.
std::optional<PartId> Reading::ofResult(const build::Result &result) {
  const CallSite &call = record.calls[result.call];
  std::span<const ValueId> args = record.run(call.args);
  for (const GivesBack &fact : callees[result.call].givesBack) {
    if (fact.result.index != result.result || !fact.result.fields.empty())
      continue;
    std::optional<PartId> part = equal[args[fact.argument.index]];
    for (std::uint32_t position : fact.argument.fields) {
      if (!part)
        break;
      Type at = parts.typeOf(*part);
      std::optional<Tag> tag = fixedTag(at);
      part = tag ? std::optional(parts.step(*part, Field{*tag, position},
                                            fieldType(at, *tag, position)))
                 : std::nullopt;
    }
    if (part)
      return part;
  }
  return std::nullopt;
}

std::optional<PartId> Reading::ofCon(const build::Con &con) {
  std::span<const Frame> frames = record.framesOf(con.frames);
  std::span<const ValueId> fields = record.run(con.fields);
  if (fields.empty())
    return inCase(KnownTag{con.tag}, con.type, frames);
  std::optional<PartId> first = at(fields.front(), frames);
  if (!first)
    return std::nullopt;
  std::optional<PartId> whole = parts.below(*first, Field{con.tag, 0});
  if (!whole || !parts.fits(*whole, con.type))
    return std::nullopt;
  for (auto [index, field] : llvm::enumerate(fields)) {
    std::optional<PartId> part = at(field, frames);
    if (!part || parts.below(*part, Field{con.tag, static_cast<std::uint32_t>(index)}) != whole)
      return std::nullopt;
  }
  return whole;
}

std::optional<PartId> Reading::ofJoin(const build::Join &join) {
  Range side = record.sides[join.side];
  std::optional<PartId> agreed;
  // An arm that never returns yields nothing to agree on.
  for (const Arm &arm : std::span<const Arm>(record.arms).subspan(side.first, side.count)) {
    bool agrees = match(
        arm, [](NeverReturns) { return true; },
        [&](const Yields &yields) {
          std::optional<PartId> part =
              at(record.run(yields.values)[join.result], record.framesOf(yields.frames));
          if (!part || (agreed && *agreed != *part))
            return false;
          agreed = part;
          return true;
        });
    if (!agrees)
      return std::nullopt;
  }
  return agreed;
}

} // namespace

footprint::Vector<GivesBack> wholeFactsAmong(const Record &record,
                                             std::span<const FactsView> callees,
                                             std::span<const GivesBack> asked) {
  Reading reading(record, callees);
  footprint::Vector<GivesBack> kept;
  for (const GivesBack &fact : asked) {
    PartId whole = reading.parts.whole(fact.argument.index);
    if (llvm::all_of(record.returns, [&](const Return &ret) {
          return reading.at(record.run(ret.values)[fact.result.index],
                            record.framesOf(ret.frames)) == whole;
        }))
      kept.push_back(fact);
  }
  return kept;
}

// The published path of a part, where it is one: every step a field of a
// type that fixes its constructor, read from the argument's type down. A
// part below a predecessor, or a field of a value whose type leaves two
// constructors, is no place in the argument's inline layout.
std::optional<Path> layoutPath(const Record &record, const Parts &parts, PartId part) {
  Path path{parts.argumentOf(part), {}};
  Type at = record.argumentTypes[path.index];
  for (const Step &step : parts.stepsOf(part)) {
    bool placed = match(
        step, [](Predecessor) { return false; },
        [&](const Field &field) {
          if (fixedTag(at) != field.tag)
            return false;
          path.fields.push_back(field.index);
          at = fieldType(at, field.tag, field.index);
          return true;
        });
    if (!placed)
      return std::nullopt;
  }
  return path;
}

footprint::Vector<GivesBack> everyFact(const Record &record, std::span<const FactsView> callees) {
  footprint::Vector<GivesBack> facts;
  if (record.returns.empty())
    return facts;
  Reading reading(record, callees);
  // One component of a result: its path, its type, and what each return
  // builds there, with the case regions around the build.
  struct Occurrence {
    ValueId value;
    Range frames;
  };
  struct Item {
    Path path;
    Type type;
    footprint::Vector<Occurrence> occurrences;
  };
  footprint::Vector<Item> work;
  for (std::uint32_t result = 0; result < record.resultTypes.size(); ++result) {
    Item item{{result, {}}, record.resultTypes[result], {}};
    for (const Return &ret : record.returns)
      item.occurrences.push_back({record.run(ret.values)[result], ret.frames});
    work.push_back(std::move(item));
  }
  // In order of discovery: a component is decided whole before its fields
  // are looked into, and only when it is not given back whole.
  for (std::size_t next = 0; next < work.size(); ++next) {
    Item item = std::move(work[next]);
    std::optional<PartId> agreed;
    bool same = true;
    for (const Occurrence &occurrence : item.occurrences) {
      std::optional<PartId> part = reading.at(occurrence.value, record.framesOf(occurrence.frames));
      if (!part || (agreed && *agreed != *part)) {
        same = false;
        break;
      }
      agreed = part;
    }
    if (same && agreed) {
      if (std::optional<Path> argument = layoutPath(record, reading.parts, *agreed))
        facts.push_back({item.path, *argument});
      continue;
    }
    // Looked into only where the component's type fixes its constructor,
    // which every return then builds.
    std::optional<Tag> tag = fixedTag(item.type);
    if (!tag)
      continue;
    std::uint32_t fields = 0;
    footprint::Vector<const build::Con *> cons;
    bool built = llvm::all_of(item.occurrences, [&](const Occurrence &occurrence) {
      const build::Con *con = match(
          record.builds[occurrence.value], [](const build::Con &made) { return &made; },
          []<OneOf<build::Opaque, build::Forwarded, build::Unseen, build::Entry, build::Same,
                   build::Read, build::Pred, build::Result, build::Successor, build::Join,
                   build::Constant> B>(const B &) -> const build::Con * { return nullptr; });
      fields = con ? con->fields.count : 0;
      cons.push_back(con);
      return con && con->tag == *tag && fields != 0;
    });
    if (!built)
      continue;
    for (std::uint32_t index = 0; index < fields; ++index) {
      Item field{item.path, fieldType(item.type, *tag, index), {}};
      field.path.fields.push_back(index);
      for (const build::Con *con : cons)
        field.occurrences.push_back({record.run(con->fields)[index], con->frames});
      work.push_back(std::move(field));
    }
  }
  return facts;
}

//===----------------------------------------------------------------------===//
// What may reach a result
//===----------------------------------------------------------------------===//

namespace {

// An argument a value may hold, and how far.
struct Held {
  std::uint32_t argument;
  Reach reach;
  friend bool operator==(const Held &, const Held &) = default;
};

// A part covers a whole: it bounds the result's claim no higher.
constexpr Reach covering(Reach a, Reach b) {
  return a == Reach::Part || b == Reach::Part ? Reach::Part : Reach::Whole;
}

// What each value of a record may hold of its function's arguments on
// some path, each argument once, ascending: a run of one table per value,
// written in one loop ascending, so each value reads the runs of what it is
// made of, written already, but what enters a region from later in the
// walk, for which the loop goes round again until no run grows. A value
// that holds what another holds, as it is, shares that one's run, and a
// run that holds what it held in the round before stays where it was.
class Holding {
public:
  Holding(const Record &record, std::span<const FactsView> callees)
      : record(record), callees(callees), runs(record.values, Range{}) {
    // Every run only grows from one round to the next (a value holds the
    // union of what it reads, and an argument's reach only weakens), and a
    // run holds each argument once, at one of two reaches, so the rounds
    // end: each round but the last grows a run, and no run grows past every
    // argument at the weaker reach. A record no value of which is entered
    // from later in the walk takes one.
    Grew grew = round();
    while (entered == Entered::Later && grew == Grew::Yes)
      grew = round();
  }

  std::span<const Held> of(ValueId value) const { return at(runs[value]); }

private:
  // Whether a round grew any run; whether any value is entered from later
  // in the walk, which the first round finds.
  enum class Grew : std::uint8_t { No, Yes };
  enum class Entered : std::uint8_t { InOrder, Later };

  // One round: each value's run read again, in the walk's order.
  Grew round() {
    Grew grew = Grew::No;
    for (ValueId value : record.values.ids()) {
      previous = runs[value];
      Range now = heldBy(value);
      if (!llvm::equal(at(now), at(previous)))
        grew = Grew::Yes;
      runs[value] = now;
    }
    return grew;
  }

  std::span<const Held> at(Range range) const {
    return std::span<const Held>(table).subspan(range.first, range.count);
  }

  // Each of `run`'s, at `as` where one is given, onto the scratch.
  void gather(Range run, std::optional<Reach> as) {
    for (const Held &held : at(run))
      scratch.push_back({held.argument, as ? *as : held.reach});
  }

  // The scratch as a run, each argument once at the reach covering its
  // others: `same`, where that run holds it already, or the value's run of
  // the round before where that one does, else a new run.
  Range written(Range same) {
    llvm::sort(scratch, [](const Held &a, const Held &b) { return a.argument < b.argument; });
    auto kept = scratch.begin();
    for (const Held &held : scratch) {
      if (kept != scratch.begin() && std::prev(kept)->argument == held.argument) {
        std::prev(kept)->reach = covering(std::prev(kept)->reach, held.reach);
        continue;
      }
      *kept++ = held;
    }
    scratch.erase(kept, scratch.end());
    Range run = same;
    if (llvm::equal(scratch, at(same))) {
      // Held already.
    } else if (llvm::equal(scratch, at(previous))) {
      run = previous;
    } else {
      run = Range{static_cast<std::uint32_t>(table.size()),
                  static_cast<std::uint32_t>(scratch.size())};
      table.insert(table.end(), scratch.begin(), scratch.end());
    }
    scratch.clear();
    return run;
  }

  // A part of everything `run` holds.
  Range weakened(Range run) {
    gather(run, Reach::Part);
    return written(run);
  }

  // A part of every argument that holds references, written once.
  Range everything() {
    if (!unseen) {
      for (std::uint32_t argument : record.referenceArguments)
        scratch.push_back({argument, Reach::Part});
      unseen = written(Range{});
    }
    return *unseen;
  }

  Range heldBy(ValueId value);

  const Record &record;
  std::span<const FactsView> callees;
  IndexVector<ValueId, Range> runs;
  footprint::Vector<Held> table;
  footprint::Vector<Held> scratch;
  std::optional<Range> unseen;
  // The run of the value being read, as the round before left it.
  Range previous;
  Entered entered = Entered::InOrder;
};

Range Holding::heldBy(ValueId value) {
  if (record.refs[value] == Refs::Words)
    return Range{};
  return match(
      record.builds[value],
      [&](const build::Entry &entry) {
        scratch.push_back({entry.argument, Reach::Whole});
        return written(Range{});
      },
      [&](const build::Same &same) { return runs[same.of]; },
      [&](const build::Successor &successor) { return runs[successor.of]; },
      [&](const build::Read &read) { return weakened(runs[read.of]); },
      [&](const build::Pred &pred) { return weakened(runs[pred.of]); },
      [&](const build::Opaque &opaque) {
        std::optional<Reach> as;
        if (opaque.reach == Reach::Part)
          as = Reach::Part;
        for (ValueId from : record.run(opaque.from))
          gather(runs[from], as);
        return written(Range{});
      },
      [&](const build::Forwarded &forwarded) {
        for (ValueId from : record.run(forwarded.from)) {
          if (from.index() >= value.index())
            entered = Entered::Later;
          gather(runs[from], std::nullopt);
        }
        return written(Range{});
      },
      [&](const build::Unseen &) { return everything(); },
      [&](const build::Con &con) {
        Range first{};
        for (ValueId field : record.run(con.fields)) {
          if (first.count == 0)
            first = runs[field];
          gather(runs[field], std::nullopt);
        }
        return written(first);
      },
      [&](const build::Join &join) {
        Range side = record.sides[join.side];
        Range first{};
        for (const Arm &arm : std::span<const Arm>(record.arms).subspan(side.first, side.count))
          match(
              arm, [](NeverReturns) {},
              [&](const Yields &yields) {
                Range given = runs[record.run(yields.values)[join.result]];
                if (first.count == 0)
                  first = given;
                gather(given, std::nullopt);
              });
        return written(first);
      },
      [&](const build::Result &result) {
        std::span<const ValueId> args = record.run(record.calls[result.call].args);
        for (const MayReach &fact : callees[result.call].mayReach) {
          if (fact.result != result.result)
            continue;
          for (const Held &held : at(runs[args[fact.argument]]))
            scratch.push_back({held.argument, covering(fact.reach, held.reach)});
        }
        return written(Range{});
      },
      [](const build::Constant &) { return Range{}; });
}

} // namespace

footprint::Vector<MayReach> reachesOf(const Record &record, std::span<const FactsView> callees) {
  footprint::Vector<MayReach> reaches;
  if (record.returns.empty())
    return reaches;
  Holding holding(record, callees);
  for (std::uint32_t result = 0; result < record.resultTypes.size(); ++result) {
    std::size_t first = reaches.size();
    for (const Return &ret : record.returns)
      for (const Held &held : holding.of(record.run(ret.values)[result]))
        reaches.push_back({result, held.argument, held.reach});
    // Each return's run holds an argument once; several returns may each
    // hold one, at the reach that covers both.
    auto from = reaches.begin() + static_cast<std::ptrdiff_t>(first);
    std::sort(from, reaches.end(),
              [](const MayReach &a, const MayReach &b) { return a.argument < b.argument; });
    auto kept = from;
    for (auto at = from; at != reaches.end(); ++at) {
      if (kept != from && std::prev(kept)->argument == at->argument) {
        std::prev(kept)->reach = covering(std::prev(kept)->reach, at->reach);
        continue;
      }
      *kept++ = *at;
    }
    reaches.erase(kept, reaches.end());
  }
  return reaches;
}

} // namespace idr::identities
