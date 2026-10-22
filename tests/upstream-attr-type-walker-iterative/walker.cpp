// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// upstream/81-attr-type-walker-iterative, checked on the pinned MLIR: the
// attribute and type walker and both replacers, over a symbol reference
// nested in builtin arrays DEPTH deep, on a thread whose stack frames per
// level would overflow, do what the recursion did: each walk meets every
// array and the reference once, an interrupt at the reference ends the
// walk, and each replacer rebuilds every array around the reference it
// replaces. The nesting is built in memory, so no parser or printer is
// reached. Prints `ok` when every check holds, and a line for each that
// does not.
#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/MLIRContext.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/thread.h"

#include <cstddef>
#include <cstdlib>

using namespace mlir;

namespace {

// The stack the checks run on: far below what frames per level take at
// the depths the check uses.
constexpr unsigned smallStack = 256 * 1024;

// `inner` nested in `depth` builtin arrays, built from the inside out.
Attribute nested(MLIRContext &context, Attribute inner, unsigned depth) {
  for (unsigned level = 0; level < depth; ++level)
    inner = ArrayAttr::get(&context, inner);
  return inner;
}

// What each check gave against what it should, a line for each that
// differs.
struct Tally {
  unsigned wrong = 0;
  template <class T>
  void expect(const char *check, T got, T want) {
    if (got == want)
      return;
    llvm::outs() << check << ": " << got << ", not " << want << "\n";
    ++wrong;
  }
};

} // namespace

int main(int argc, char **argv) {
  if (argc != 2)
    return 2;
  unsigned depth = static_cast<unsigned>(std::strtoul(argv[1], nullptr, 10));
  MLIRContext context;
  Attribute used = FlatSymbolRefAttr::get(&context, "used");
  Attribute other = FlatSymbolRefAttr::get(&context, "other");
  Attribute input = nested(context, used, depth);
  Attribute replaced = nested(context, other, depth);
  std::size_t arrays = depth;

  Tally tally;
  llvm::thread checks(smallStack, [&] {
    std::size_t seenArrays = 0, seenReferences = 0;
    AttrTypeWalker postOrder;
    postOrder.addWalk([&](ArrayAttr) { ++seenArrays; });
    postOrder.addWalk([&](SymbolRefAttr) { ++seenReferences; });
    postOrder.walk<WalkOrder::PostOrder>(input);
    tally.expect("post-order walk, arrays", seenArrays, arrays);
    tally.expect("post-order walk, references", seenReferences, std::size_t{1});

    seenArrays = seenReferences = 0;
    AttrTypeWalker preOrder;
    preOrder.addWalk([&](ArrayAttr) { ++seenArrays; });
    preOrder.addWalk([&](SymbolRefAttr) { ++seenReferences; });
    preOrder.walk<WalkOrder::PreOrder>(input);
    tally.expect("pre-order walk, arrays", seenArrays, arrays);
    tally.expect("pre-order walk, references", seenReferences, std::size_t{1});

    AttrTypeWalker interrupting;
    interrupting.addWalk([&](SymbolRefAttr) { return WalkResult::interrupt(); });
    tally.expect("walk interrupted at the reference",
                 interrupting.walk<WalkOrder::PostOrder>(input).wasInterrupted(), true);

    AttrTypeReplacer replacer;
    replacer.addReplacement([&](SymbolRefAttr) -> Attribute { return other; });
    tally.expect("AttrTypeReplacer", replacer.replace(input) == replaced, true);

    CyclicAttrTypeReplacer cyclic;
    cyclic.addReplacement([&](SymbolRefAttr) -> Attribute { return other; });
    tally.expect("CyclicAttrTypeReplacer", cyclic.replace(input) == replaced, true);
  });
  checks.join();

  if (tally.wrong != 0)
    return 1;
  llvm::outs() << "ok\n";
  return 0;
}
