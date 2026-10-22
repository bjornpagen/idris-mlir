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
// - a fieldless constant inside a case of its constructor, at its use.
// The record is never written; a reading holds what it learns while it
// answers.
#include "Solver/IdentityRecords.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <algorithm>
#include <tuple>
#include <utility>

using namespace mlir;

namespace idr::identities {

namespace {

enum class PartId : std::uint32_t {};

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
    auto key = std::make_tuple(raw(parent), static_cast<std::uint32_t>(step.index()),
                               std::visit(llvm::makeVisitor(
                                              [](const Field &field) {
                                                return std::pair(std::to_underlying(field.tag),
                                                                 field.index);
                                              },
                                              [](Predecessor) { return std::pair(0u, 0u); }),
                                          step));
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
  llvm::SmallVector<Step, 4> stepsOf(PartId part) const {
    llvm::SmallVector<Step, 4> down;
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
  std::vector<Row> rows;
  llvm::DenseMap<std::tuple<std::uint32_t, std::uint32_t, std::pair<std::uint32_t, std::uint32_t>>,
                 std::uint32_t>
      steps;
};

class Reading {
public:
  Reading(const Record &record, std::span<const std::span<const GivesBack>> callees)
      : record(record), callees(callees), parts(record),
        equal(record.values, std::optional<PartId>()) {
    for (ValueId value : record.values.ids())
      equal[value] = rebuilt(value);
  }

  // The part `value` rebuilds where it is used under `frames`.
  std::optional<PartId> at(ValueId value, std::span<const Frame> frames) const {
    if (equal[value])
      return equal[value];
    const auto *constant = std::get_if<build::Constant>(&record.builds[value]);
    if (!constant || !constant->fieldless)
      return std::nullopt;
    return inCase(*constant->fieldless, constant->type, frames);
  }

  const Record &record;
  std::span<const std::span<const GivesBack>> callees;
  Parts parts;

private:
  // The part a case of constructor `tag` around a use enters at, where a
  // value of `type` with that constructor is it.
  std::optional<PartId> inCase(Tag tag, Type type, std::span<const Frame> frames) const {
    for (const Frame &frame : frames)
      if (frame.tag == tag)
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
  return std::visit(
      llvm::makeVisitor(
          [](const build::Opaque &) -> std::optional<PartId> { return std::nullopt; },
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
          [&](const build::Join &join) { return ofJoin(join); }),
      record.builds[value]);
}

// A callee's fact for this result, whole, applied to the call's argument:
// each field of its argument path is of a type that fixes its constructor,
// so each step's constructor is read off the part's type as it descends.
std::optional<PartId> Reading::ofResult(const build::Result &result) {
  const CallSite &call = record.calls[result.call];
  std::span<const ValueId> args = record.run(call.args);
  for (const GivesBack &fact : callees[result.call]) {
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
    return inCase(con.tag, con.type, frames);
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
  for (const Arm &arm : std::span<const Arm>(record.arms).subspan(side.first, side.count)) {
    const auto *yields = std::get_if<Yields>(&arm);
    if (!yields)
      continue;
    std::optional<PartId> part =
        at(record.run(yields->values)[join.result], record.framesOf(yields->frames));
    if (!part || (agreed && *agreed != *part))
      return std::nullopt;
    agreed = part;
  }
  return agreed;
}

} // namespace

Facts wholeFactsAmong(const Record &record, std::span<const std::span<const GivesBack>> callees,
                      std::span<const GivesBack> asked) {
  Reading reading(record, callees);
  Facts kept;
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

// The given_back path of a part, where it is one: every step a field of a
// type that fixes its constructor, read from the argument's type down. A
// part below a predecessor, or a field of a value whose type leaves two
// constructors, is no place in the argument's inline layout.
std::optional<Path> layoutPath(const Record &record, const Parts &parts, PartId part) {
  Path path{parts.argumentOf(part), {}};
  Type at = record.argumentTypes[path.index];
  for (const Step &step : parts.stepsOf(part)) {
    const auto *field = std::get_if<Field>(&step);
    if (!field || fixedTag(at) != field->tag)
      return std::nullopt;
    path.fields.push_back(field->index);
    at = fieldType(at, field->tag, field->index);
  }
  return path;
}

Facts everyFact(const Record &record, std::span<const std::span<const GivesBack>> callees) {
  Facts facts;
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
    std::vector<Occurrence> occurrences;
  };
  std::vector<Item> work;
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
    bool built = llvm::all_of(item.occurrences, [&](const Occurrence &occurrence) {
      const auto *con = std::get_if<build::Con>(&record.builds[occurrence.value]);
      fields = con ? con->fields.count : 0;
      return con && con->tag == *tag && fields != 0;
    });
    if (!built)
      continue;
    for (std::uint32_t index = 0; index < fields; ++index) {
      Item field{item.path, fieldType(item.type, *tag, index), {}};
      field.path.fields.push_back(index);
      for (const Occurrence &occurrence : item.occurrences) {
        const auto &con = std::get<build::Con>(record.builds[occurrence.value]);
        field.occurrences.push_back({record.run(con.fields)[index], con.frames});
      }
      work.push_back(std::move(field));
    }
  }
  return facts;
}

} // namespace idr::identities
