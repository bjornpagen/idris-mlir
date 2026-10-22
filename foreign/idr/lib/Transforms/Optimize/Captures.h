// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The labels' captures nothing reads, dropped once every function is
// final: the solve that finds them (Captures.cpp), and the rewrite that
// drops them from the program (CaptureDrops.cpp). Both run on the pass
// thread, once, when no turn runs: the rewrite changes types every
// function may hold.
#ifndef IDR_LIB_TRANSFORMS_OPTIMIZE_CAPTURES_H
#define IDR_LIB_TRANSFORMS_OPTIMIZE_CAPTURES_H

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Transforms/Optimize.h"

#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>
#include <tuple>

namespace idr::optimize::captures {

// A constructor of a label: its family, as the group and member that
// declare it, and its tag.
using Ctor = std::tuple<FamilyAttr, std::uint32_t, std::uint32_t>;

inline Ctor ctorOf(DataType data, Tag tag) {
  return {data.getGroup(), data.getMember(), static_cast<std::uint32_t>(tag)};
}

// A label's function: how many captures it takes, its leading parameters
// and its constructors' fields; and its constructors.
struct Label {
  FunctionId fn;
  unsigned captures;
  llvm::SmallVector<Ctor, 1> ctors;
};

// What the solve found: every label; each function's label, by its id;
// each constructor's label; and the captures each label drops, some label
// dropping one.
struct Unread {
  footprint::Vector<Label> labels;
  footprint::Vector<std::optional<unsigned>> labelOf;
  llvm::DenseMap<Ctor, unsigned> ownerOf;
  footprint::Vector<llvm::BitVector> dropped;

  // The captures the label of `ctor` drops; none where it drops none.
  const llvm::BitVector *droppedOf(Ctor ctor) const;
};

// The captures nothing reads; none where no label drops one.
std::optional<Unread> unread(Schedule &schedule);

// Every call, read, exchange, constructor, parameter, family and constant
// without the captures `unread` drops.
void drop(Schedule &schedule, const Unread &unread);

} // namespace idr::optimize::captures

#endif // IDR_LIB_TRANSFORMS_OPTIMIZE_CAPTURES_H
