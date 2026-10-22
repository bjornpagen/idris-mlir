// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-frames' family: one group per component, its frame stack indexed by
// the row a frame awaits, and the answers its base frames write.

#include "idr/Transforms/Tail.h"

#include "idr/IR/Families/Declaration.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Terms.h"
#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::tail {

FramesFamily declareFrames(MLIRContext *ctx, StringAttr label, Location loc,
                           llvm::ArrayRef<llvm::SmallVector<Type, 1>> rows,
                           llvm::ArrayRef<FrameKind> kinds) {
  using families::CtorDecl;
  using families::TermNode;
  using families::TermWriter;
  unsigned count = static_cast<unsigned>(rows.size());

  // `nat j`, the index of every frame awaiting row j, written once each.
  llvm::SmallVector<llvm::SmallVector<TermNode, 1>> index(count);
  for (unsigned row = 0; row < count; ++row)
    TermWriter(index[row]).natural(row);

  // The answers are members 1 to R of the group, the frame stack member 0;
  // a frame's field below it is the stack awaiting the row it continues.
  // Labels are for readers, unique in their member and their group.
  auto named = [&](llvm::StringRef stem, unsigned at) {
    return StringAttr::get(ctx, stem + llvm::Twine(at));
  };
  llvm::SmallVector<llvm::SmallVector<Type>> baseFields(count);
  for (unsigned row = 0; row < count; ++row)
    for (auto [field, type] : llvm::enumerate(rows[row]))
      baseFields[row].push_back(DestType::get(ctx, unrestricted(type)));
  llvm::SmallVector<llvm::SmallVector<Type>> kindFields(kinds.size());
  for (auto [at, kind] : llvm::enumerate(kinds)) {
    kindFields[at].append(kind.held.begin(), kind.held.end());
    kindFields[at].push_back(SelfType::get(ctx, 0, index[kind.continues]));
  }

  llvm::SmallVector<CtorDecl> ctors;
  for (unsigned row = 0; row < count; ++row)
    ctors.push_back(CtorDecl{named("base", row), {}, index[row], baseFields[row]});
  for (auto [at, kind] : llvm::enumerate(kinds))
    ctors.push_back(CtorDecl{named("frame", static_cast<unsigned>(at)), {}, index[kind.awaits],
                             kindFields[at]});

  llvm::SmallVector<families::Member> members;
  members.push_back(families::FramesMember{label, ctors});
  llvm::SmallVector<CtorDecl> answerCtors;
  for (unsigned row = 0; row < count; ++row)
    answerCtors.push_back(CtorDecl{named("answer", row), {}, {}, rows[row]});
  for (unsigned row = 0; row < count; ++row)
    members.push_back(families::DataMember{named("answers", row), loc, families::Promise::None,
                                           {}, llvm::ArrayRef(answerCtors).slice(row, 1)});

  FramesFamily family{FamilyAttr::get(ctx, members), {}, {}, count};
  for (unsigned row = 0; row < count; ++row) {
    family.stacks.push_back(DataType::get(family.group, 0, index[row]));
    family.answers.push_back(DataType::get(family.group, 1 + row, {}));
  }
  return family;
}

} // namespace idr::tail
