// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The captures of each memoizing label, which exclusivity's solve reads
// (ExclusivityDetail.h): the forces that move each label's captures out,
// and the fields whose captures are shared whatever an init moves in.
#include "idr/Analysis/Ownership/ExclusivityDetail.h"

#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"

using namespace mlir;

namespace idr::detail::exclusivity {

Captures::Captures(ProgramOp program) {
  auto label = [](DataType memo, Tag tag) {
    const auto *role = std::get_if<role::Label>(&memo.getCtor(tag).role);
    return role && !role->byName;
  };
  program.walk([&](Operation *op) {
    if (auto force = dyn_cast<MemoRunOp>(op))
      forces[{force.getDataType(), force.getTag()}].push_back(force);
    if (auto init = dyn_cast<CellInitOp>(op); init && init.getDataType().isMemo())
      makers[{init.getDataType(), init.getTag()}].push_back(init);
    // Static data holding a cell of a label: its captures are static.
    if (auto constant = dyn_cast<ConstantOp>(op))
      constant.getValue().walk([&](ConAttr con) {
        DataType data = con.getData();
        if (data.isMemo() && label(data, con.getTag())) {
          makers[{data, con.getTag()}].push_back(constant);
          for (unsigned i = 0, e = static_cast<unsigned>(con.getCtor().fields.size()); i != e; ++i)
            sharedFields.insert({{data, con.getTag()}, i});
        }
      });
    // A capture read as a view that is used: a reference of its own may be
    // taken there.
    auto read = [&](Value value) {
      Source source = sourceOf(value);
      const auto *field = std::get_if<Field>(&source);
      if (!field || value.use_empty())
        return;
      DataType data = dataTypeOf(field->scrutinee.getType());
      if (data && data.isMemo() && label(data, field->tag))
        sharedFields.insert({{data, field->tag}, field->index});
    };
    for (Value result : op->getResults())
      read(result);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (BlockArgument arg : block.getArguments())
          read(arg);
  });
}

ArrayRef<MemoRunOp> Captures::forcesOf(DataType memo, Tag tag) const {
  auto it = forces.find({memo, tag});
  return it == forces.end() ? ArrayRef<MemoRunOp>() : ArrayRef<MemoRunOp>(it->second);
}

bool Captures::keepMadeIn(const llvm::DenseSet<Block *> &live) {
  SmallVector<Label> unmade;
  for (auto &[label, ops] : makers)
    if (llvm::none_of(ops, [&](Operation *op) { return live.contains(op->getBlock()); }))
      unmade.push_back(label);
  for (const Label &label : unmade)
    makers.erase(label);
  return !unmade.empty();
}

bool Captures::shared(DataType memo, Tag tag, unsigned index) const {
  return sharedFields.contains({{memo, tag}, index});
}

} // namespace idr::detail::exclusivity
