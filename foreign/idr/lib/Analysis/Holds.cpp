// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Whether a value of a type may hold a world or a closure, for every data
// type at once. A data type may hold one when a field of one of its
// constructors is one, seen through its grade, when it is a sum of
// closures, or when a data type a field names may: the least fixpoint over
// the containment among data types, which one pass over its components,
// callees first, reaches. A cycle of data holds nothing beyond what its
// members hold.
//
// The walk stops at an array: what its elements may hold is not followed.
// A verified module has no array on a cycle, so every component is data
// types only or one array, and skipping the arrays leaves each component's
// answer exactly what its data types reach; were an array on one, its data
// types would answer for what they reach through it too: more than they
// hold, never less.
#include "idr/Analysis/Holds.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/TypeGraph.h"

#include "mlir/IR/BuiltinAttributes.h"

using namespace mlir;

namespace {

constexpr uint8_t holdsWorld = 1;
constexpr uint8_t holdsClosure = 2;

// What a field of type `type` is itself, before the data it names.
uint8_t leaf(Type type) {
  type = idr::unrestricted(type);
  if (idr::isWorld(type))
    return holdsWorld;
  if (isa<idr::FnType>(type))
    return holdsClosure;
  return 0;
}

} // namespace

idr::Holds::Holds(Operation *, AnalysisManager &am) {
  const TypeGraph &graph = am.getAnalysis<TypeGraph>();
  // The bits of each node, by position: final for every component already
  // passed, and none for an array.
  SmallVector<uint8_t> found(graph.size(), 0);
  for (const SmallVector<unsigned> &component : graph.components()) {
    uint8_t held = 0;
    for (unsigned at : component) {
      DataType data = graph.declaration(at);
      if (!data)
        continue;
      if (data.isClosures())
        held |= holdsClosure;
      for (const Ctor &ctor : data.getCtors())
        for (Type field : ctor.fields)
          held |= leaf(field);
      for (unsigned next : graph.successors(at))
        if (!graph.isArray(next) && graph.declaration(next))
          held |= found[next];
    }
    for (unsigned at : component) {
      if (DataType data = graph.declaration(at)) {
        found[at] = held;
        bits[data] = held;
      }
    }
  }
}

bool idr::Holds::isInvalidated(const AnalysisManager::PreservedAnalyses &pa) const {
  return !pa.isPreserved<Holds>() || !pa.isPreserved<TypeGraph>();
}

uint8_t idr::Holds::bitsOf(Type type) const {
  if (uint8_t own = leaf(type))
    return own;
  if (DataType data = dataTypeOf(type))
    return bits.lookup(data);
  return 0;
}

bool idr::Holds::mayHoldWorld(Type type) const { return bitsOf(type) & holdsWorld; }

bool idr::Holds::mayHoldClosure(Type type) const { return bitsOf(type) & holdsClosure; }
