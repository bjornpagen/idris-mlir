// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The cut of the partition's parts into bins. The parts are ordered by the
// top-level namespace their names keep, then by the hash of their names;
// a bin closes before a part of another group or one that would take it
// past twice the target, and after a part whose hash, read against its
// size, says so once the bin holds a quarter of the target. So a cut
// depends only on its neighbours, and an edit moves only the cuts beside
// it. Each bin is named by the hash of its names.

#include "idr/Target/Target.h"

#include "idr/Conversion/Mangle.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/xxhash.h"

#include <bit>
#include <cstdint>
#include <numeric>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using namespace llvm;
using idr::target::Bin;
using idr::target::Partition;
using idr::target::binInstructions;

namespace {

// A part closes its bin when its hash, read as a fraction of 2^64, is below
// its share of the target: hash / (2^64 / target) < size says exactly that
// when the target is a power of two.
static_assert(std::has_single_bit(binInstructions));
constexpr std::uint64_t hashPerInstruction = ~std::uint64_t{0} / binInstructions + 1;

// The top-level namespace a name keeps: what precedes its first dot after
// the program's prefix, which every program symbol has, and one group, the
// empty one, for every name without a dot.
StringRef namespaceOf(StringRef name) {
  StringRef plain = GlobalValue::dropLLVMManglingEscape(name);
  plain.consume_front(idr::conversion::programPrefix);
  return plain.contains('.') ? plain.take_front(plain.find('.')) : StringRef();
}

// The hash of a set of names, sorted, one per line: XXH3's 64 bits, which
// decide a part's cut and, spelled in hex, name a bin.
std::uint64_t hashOf(std::vector<StringRef> &names) {
  sort(names);
  return xxh3_64bits(arrayRefFromStringRef(join(names, "\n")));
}

// A bin's name: its hash in 16 lower-case hex digits, so that name order is
// hash order.
std::string nameOf(std::uint64_t hash) {
  std::string name;
  raw_string_ostream(name) << format_hex_no_prefix(hash, 16, /*Upper=*/false);
  return name;
}

// What the cut reads of a part: its names in order, its hash, and its
// group, the namespace of its first name.
struct Keyed {
  std::vector<StringRef> names;
  std::uint64_t hash;
  StringRef group() const { return namespaceOf(names.front()); }
};

} // namespace

Expected<std::vector<Partition::Cut>> Partition::cut(ArrayRef<Part> parts) {
  std::vector<Keyed> keyed;
  keyed.reserve(parts.size());
  for (const Part &part : parts) {
    std::vector<StringRef> names = part.names;
    std::uint64_t hash = hashOf(names);
    keyed.push_back(Keyed{std::move(names), hash});
  }
  auto order = [&](unsigned index) {
    const Keyed &key = keyed[index];
    return std::tuple(key.group(), key.hash, key.names.front(), parts[index].position);
  };
  std::vector<unsigned> ordered(parts.size());
  std::iota(ordered.begin(), ordered.end(), 0u);
  sort(ordered, [&](unsigned a, unsigned b) { return order(a) < order(b); });

  // Before a part, the open bin closes when the part would take it past
  // twice the target or is of another group; after it, when the bin holds a
  // quarter of the target and the part's hash says so.
  std::vector<SmallVector<unsigned>> chosen;
  SmallVector<unsigned> open;
  std::uint64_t held = 0;
  auto close = [&] {
    chosen.push_back(std::exchange(open, {}));
    held = 0;
  };
  for (unsigned index : ordered) {
    std::uint64_t size = parts[index].size;
    if (!open.empty() && (keyed[open.front()].group() != keyed[index].group() ||
                          held + size > 2 * binInstructions))
      close();
    open.push_back(index);
    held += size;
    if (held >= binInstructions / 4 && keyed[index].hash / hashPerInstruction < size)
      close();
  }
  if (!open.empty())
    close();

  // Bins named by the hash of their names, kept in name order.
  std::vector<Cut> cuts;
  for (SmallVector<unsigned> &members : chosen) {
    Bin bin;
    std::vector<StringRef> names;
    for (unsigned index : members) {
      bin.instructions += parts[index].size;
      append_range(names, keyed[index].names);
    }
    bin.name = nameOf(hashOf(names));
    cuts.push_back(Cut{std::move(bin), std::move(members)});
  }
  sort(cuts, [](const Cut &a, const Cut &b) { return a.bin.name < b.bin.name; });
  for (unsigned index = 0; index + 1 < cuts.size(); ++index)
    if (cuts[index].bin.name == cuts[index + 1].bin.name)
      return createStringError("two bins are named " + cuts[index].bin.name);
  return cuts;
}
