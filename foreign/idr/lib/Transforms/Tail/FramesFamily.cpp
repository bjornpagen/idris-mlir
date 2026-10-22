// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-frames' families: one group per component, its frame stack indexed by
// the row a frame awaits, and beside it the group of the answers its base
// frames' destinations write.

#include "idr/Transforms/Tail.h"

#include "idr/IR/Families/Declaration.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Terms.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::tail {

namespace {

// A row's value as an answer's field declares it: its carrier, used once
// where the value is, as a declaration states a quantity.
Type declaredField(Type value) {
  Type carrier = unrestricted(value);
  return usesOf(value) == Uses::Once ? graded(Grade{Uses::Once, std::nullopt}, carrier) : carrier;
}

} // namespace

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

  // The answers, one member per row, each one constructor of the row's
  // values. No member holds itself or a frame, so each is laid out in
  // place, its components the row's: a slot holds it with no cell, and a
  // row of any width, none included, is one value.
  llvm::SmallVector<llvm::SmallVector<Type>> answerFields(count);
  for (unsigned row = 0; row < count; ++row)
    answerFields[row] = llvm::map_to_vector(rows[row], declaredField);
  llvm::SmallVector<CtorDecl> answerCtors;
  for (unsigned row = 0; row < count; ++row)
    answerCtors.push_back(CtorDecl{named("answer", row), {}, {}, answerFields[row]});
  llvm::SmallVector<families::Member> answerMembers;
  for (unsigned row = 0; row < count; ++row)
    answerMembers.push_back(families::DataMember{named("answers", row), loc,
                                                 families::Promise::None, {},
                                                 llvm::ArrayRef(answerCtors).slice(row, 1)});
  FamilyAttr answersGroup = FamilyAttr::get(ctx, answerMembers);
  llvm::SmallVector<DataType> answers;
  for (unsigned row = 0; row < count; ++row)
    answers.push_back(DataType::get(ctx, answersGroup, row, {}));

  // `nat j`, the index of every frame awaiting row j, written once each.
  llvm::SmallVector<llvm::SmallVector<TermNode, 1>> index(count);
  for (unsigned row = 0; row < count; ++row)
    TermWriter(index[row]).natural(row);

  // The frame stack, its group's one member: a base frame per row holding
  // the destination of its answer's slot, then a frame per kind, its field
  // below it the stack awaiting the row it continues.
  llvm::SmallVector<llvm::SmallVector<Type, 1>> baseFields(count);
  for (unsigned row = 0; row < count; ++row)
    baseFields[row].push_back(DestType::get(ctx, answers[row]));
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
  llvm::SmallVector<families::Member> members{families::FramesMember{label, ctors}};

  FramesFamily family{FamilyAttr::get(ctx, members), {}, std::move(answers), count};
  for (unsigned row = 0; row < count; ++row)
    family.stacks.push_back(DataType::get(ctx, family.group, 0, index[row]));
  return family;
}

} // namespace idr::tail
