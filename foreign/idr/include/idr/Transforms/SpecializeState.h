// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The state of the nodes of one run of idr-optimize behind Nodes' pointer,
// which the nodes' phases (Specialize.cpp) and the requests (Requests.cpp)
// share, and no other unit reads.
#ifndef IDR_TRANSFORMS_SPECIALIZESTATE_H
#define IDR_TRANSFORMS_SPECIALIZESTATE_H

#include "idr/Transforms/Specialize.h"

#include "llvm/ADT/DenseMap.h"

#include <memory>
#include <mutex>
#include <vector>

namespace idr::specialize {

struct Nodes::State {
  explicit State(const optimize::Schedule &schedule) : schedule(schedule) {}

  // Held while a node is inserted or its phase moves, and nowhere else: a
  // request is judged on its requester's own state, which its turn owns.
  std::mutex mutex;
  const optimize::Schedule &schedule;
  // Every node, in the order made, and by its key's identity in the arena.
  std::vector<std::unique_ptr<Node>> nodes;
  llvm::DenseMap<const void *, Node *> byKey;
  // Each name a key took, to its node: a second key on one name is the
  // compiler's error, and a name the program held when the run began is a
  // copy an earlier run made of the same key.
  llvm::DenseMap<mlir::StringAttr, Node *> byName;
  // The node each placed function is, by its id.
  llvm::DenseMap<FunctionId, Node *> byFunction;
};

} // namespace idr::specialize

#endif // IDR_TRANSFORMS_SPECIALIZESTATE_H
