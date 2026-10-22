// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-frames' families: one group per component, its frame stack indexed by
// the row a frame awaits, each base frame holding a destination per result
// of its row.

#include "idr/Transforms/Tail.h"

#include "idr/IR/Families/Declaration.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Terms.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"

using namespace mlir;

namespace idr::tail {

FramesFamily declareFrames(MLIRContext *ctx, StringAttr label, Location loc,
                           llvm::ArrayRef<llvm::SmallVector<Type, 1>> rows,
                           llvm::ArrayRef<FrameKind> kinds) {
  using families::CtorDecl;
  using families::TermNode;
  using families::TermWriter;
  unsigned count = static_cast<unsigned>(rows.size());
  // Labels are for readers, unique in their member and their group.
  auto named = [&](llvm::StringRef stem, unsigned at) {
    return StringAttr::get(ctx, stem + llvm::Twine(at));
  };

  // `nat j`, the index of every frame awaiting row j, written once each.
  footprint::Vector<llvm::SmallVector<TermNode, 1>> index(count);
  for (unsigned row = 0; row < count; ++row)
    TermWriter(index[row]).natural(row);

  // The frame stack, its group's one member: a base frame per row holding
  // a destination per result of the row, each at the result's whole type,
  // which a frame keeps as it was declared; then a frame per kind, its
  // field below it the stack awaiting the row it continues.
  footprint::Vector<llvm::SmallVector<Type, 1>> baseFields(count);
  for (unsigned row = 0; row < count; ++row)
    for (Type result : rows[row])
      baseFields[row].push_back(DestType::get(ctx, result));
  footprint::Vector<llvm::SmallVector<Type>> kindFields(kinds.size());
  for (auto [at, kind] : llvm::enumerate(kinds)) {
    kindFields[at].append(kind.held.begin(), kind.held.end());
    kindFields[at].push_back(SelfType::get(ctx, 0, index[kind.continues]));
  }
  footprint::Vector<CtorDecl> ctors;
  for (unsigned row = 0; row < count; ++row)
    ctors.push_back(CtorDecl{named("base", row), {}, index[row], baseFields[row]});
  for (auto [at, kind] : llvm::enumerate(kinds))
    ctors.push_back(CtorDecl{named("frame", static_cast<unsigned>(at)), {}, index[kind.awaits],
                             kindFields[at]});
  llvm::SmallVector<families::Member> members{families::FramesMember{label, ctors}};

  FramesFamily family{FamilyAttr::get(ctx, members), {}, count};
  for (unsigned row = 0; row < count; ++row)
    family.stacks.push_back(DataType::get(ctx, family.group, 0, index[row]));
  return family;
}

} // namespace idr::tail
