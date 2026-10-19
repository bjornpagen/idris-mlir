// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The state of the nodes of one run of idr-optimize behind Nodes'
// pointer, which the nodes' phases (Specialize.cpp) and the requests
// (Requests.cpp) share, and no other unit reads.
#ifndef IDR_TRANSFORMS_SPECIALIZESTATE_H
#define IDR_TRANSFORMS_SPECIALIZESTATE_H

#include "idr/IR/Symbols.h"
#include "idr/Support/Worklist.h"
#include "idr/Transforms/Specialize.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/STLExtras.h"

#include <memory>
#include <mutex>
#include <optional>

namespace idr::specialize {

// What one function has asked for: the spec key of every node it was
// given, by owner, which every spec key of that owner it asks for later is
// judged against, and the nodes the ready set has not taken yet, each once.
// A raise node it was given is taken and never judged against. Every
// request of the function goes through it.
class Requester {
public:
  llvm::ArrayRef<SpecKeyAttr> keysOf(mlir::StringAttr owner) { return given[owner]; }
  // `node`, whose key the request was granted, given to the function; its
  // own key, asked by a node of its own recursion, is given but not taken.
  void give(Node &node, bool self) {
    if (const auto *spec = std::get_if<SpecKeyAttr>(&node.key)) {
      llvm::SmallVector<SpecKeyAttr> &keys = given[spec->getOrigin()];
      if (!llvm::is_contained(keys, *spec))
        keys.push_back(*spec);
    }
    if (!self)
      waiting.push(&node);
  }
  // The next node given and not taken.
  std::optional<Node *> take() { return waiting.pop(); }

private:
  llvm::DenseMap<mlir::StringAttr, llvm::SmallVector<SpecKeyAttr>> given;
  OnceWorklist<Node *> waiting;
};

struct Nodes::State {
  explicit State(const Schedule &schedule) : schedule(schedule) {}

  std::mutex mutex;
  const Schedule &schedule;
  llvm::MapVector<mlir::Attribute, std::unique_ptr<Node>> byKey;
  llvm::DenseMap<mlir::StringAttr, Node *> byName;
  // What each function has asked for, by the function.
  llvm::DenseMap<mlir::Operation *, Requester> requesters;
  ContentNames names;
  detail::Order order;
  detail::Forms forms;
};

} // namespace idr::specialize

#endif // IDR_TRANSFORMS_SPECIALIZESTATE_H
