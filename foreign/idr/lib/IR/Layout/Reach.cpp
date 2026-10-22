// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The bytes everything a value of a bounded type reaches takes, computed
// once with the layouts: a frame that holds such a value past its last use
// holds at most that much of it. A type bounds what it reaches only where
// it holds itself nowhere and every field's type bounds what it reaches
// (the reach its storage computed when it was made), so the bounded types
// and their fields' types are a finite acyclic graph, walked fields first
// on a stack of its own, never the C++ one.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Support/Match.h"

#include "llvm/ADT/STLExtras.h"

#include <algorithm>

using namespace mlir;

namespace idr {

namespace {

// Where the walk stands at an entry: not yet met, its fields pushed, done.
enum class Visit : uint8_t { Open, Expanded, Done };

// The bytes a value of `type` takes in its own cell: a cell's size for
// constructor `tag`, nothing for a value in place, which is its fields.
uint64_t ownBytes(const std::variant<layout::SumLayout, layout::CellLayout> &shape, Tag tag) {
  return match(
      shape, [](const layout::SumLayout &) -> uint64_t { return 0; },
      [&](const layout::CellLayout &cells) -> uint64_t { return cells.cell(tag).size; });
}

} // namespace

std::optional<uint64_t> Layouts::reachedBytes(Type type) const {
  if (layout::reachOf(type) == Reach::Unbounded)
    return std::nullopt;
  auto data = dyn_cast<DataType>(unrestricted(type));
  // A value that holds no reference reaches nothing; a number's value is its
  // word, and no entry is made for it.
  if (!data || !numbered.contains(data.unrefined()))
    return uint64_t{0};
  return entryOf(data, "reached bytes").reached;
}

void Layouts::computeReach() {
  footprint::Vector<Visit> visits(laidOut.size(), Visit::Open);
  // The entry a bounded field's data type has, if it is laid out.
  auto entryAt = [&](Type field) -> std::optional<uint32_t> {
    auto data = dyn_cast<DataType>(unrestricted(field));
    if (!data || !data.boundsReach())
      return std::nullopt;
    auto it = numbered.find(data.unrefined());
    return it == numbered.end() ? std::nullopt : std::optional<uint32_t>(it->second);
  };
  footprint::Vector<uint32_t> stack;
  for (uint32_t start = 0; start < laidOut.size(); ++start) {
    stack.push_back(start);
    while (!stack.empty()) {
      uint32_t at = stack.back();
      DataType type = laidOut[at].type;
      if (visits[at] == Visit::Done || !type.boundsReach()) {
        visits[at] = Visit::Done;
        stack.pop_back();
        continue;
      }
      if (visits[at] == Visit::Open) {
        visits[at] = Visit::Expanded;
        for (Tag tag : type.possibleTags())
          for (Type field : laidOut[at].fields[static_cast<uint32_t>(tag)])
            if (std::optional<uint32_t> next = entryAt(field); next && visits[*next] == Visit::Open)
              stack.push_back(*next);
        continue;
      }
      // Every field's entry is done: the largest constructor, its cell and
      // what each field reaches.
      std::optional<uint64_t> most = uint64_t{0};
      for (Tag tag : type.possibleTags()) {
        std::optional<uint64_t> bytes = ownBytes(laidOut[at].shape, tag);
        for (Type field : laidOut[at].fields[static_cast<uint32_t>(tag)]) {
          std::optional<uint32_t> held = entryAt(field);
          std::optional<uint64_t> part = held ? laidOut[*held].reached : reachedBytes(field);
          bytes = bytes && part ? std::optional<uint64_t>(*bytes + *part) : std::nullopt;
        }
        most = most && bytes ? std::optional<uint64_t>(std::max(*most, *bytes)) : std::nullopt;
      }
      laidOut[at].reached = most;
      visits[at] = Visit::Done;
      stack.pop_back();
    }
  }
}

} // namespace idr
