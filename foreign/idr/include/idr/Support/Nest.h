// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Down a nesting of our own data, depth first, with an explicit stack that
// grows on the heap: a constant nested off its spine, a type in a type, a
// location in a location. Our C++ never recurses on the input's size, so a
// nesting of any depth costs heap, never native stack, and no input can
// reach the stack's guard.
//
// `enter` sees a node on the way down and says whether to go into it;
// `leave` sees each node gone into, after all of its children, so a fact
// built from the children's facts is built in `leave`. Children are
// entered in the order `children` gives them.
#ifndef IDR_SUPPORT_NEST_H
#define IDR_SUPPORT_NEST_H

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
#include <cstdint>
#include <functional>
#include <type_traits>
#include <utility>

namespace idr {

// Whether to go into a node that has been entered.
enum class Descend : std::uint8_t { Into, Past };

template <class Node, class Children, class Enter, class Leave>
  requires std::copyable<Node> && std::invocable<Children &, const Node &> &&
           std::same_as<std::invoke_result_t<Enter &, const Node &>, Descend> &&
           std::invocable<Leave &, const Node &>
void depthFirst(Node root, Children children, Enter enter, Leave leave) {
  // A node is on the stack once on the way down and, if gone into, once
  // more on the way up, below its children.
  enum class Way : std::uint8_t { Down, Up };
  llvm::SmallVector<std::pair<Node, Way>, 32> stack;
  stack.emplace_back(std::move(root), Way::Down);
  while (!stack.empty()) {
    auto [node, way] = stack.pop_back_val();
    if (way == Way::Up) {
      std::invoke(leave, std::as_const(node));
      continue;
    }
    if (std::invoke(enter, std::as_const(node)) == Descend::Past)
      continue;
    stack.emplace_back(node, Way::Up);
    // Pushed last first, so the first child is entered first.
    auto &&kids = std::invoke(children, std::as_const(node));
    for (auto &&child : llvm::reverse(kids))
      stack.emplace_back(child, Way::Down);
  }
}

} // namespace idr

#endif // IDR_SUPPORT_NEST_H
