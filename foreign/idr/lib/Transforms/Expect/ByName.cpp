// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// by-name: whether a memo label runs again at every force, stated of the
// label's function, which the label names, as the sums the program's
// values hold say it: a label whose run the outside can see is by name,
// and keeps no value. The sum's own name is the pass's business.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace idr::expect {

namespace {

// The memo labels of the sums the program's values hold whose function @f
// names, each with whether it is by name.
SmallVector<std::pair<StringAttr, bool>> labelsOf(ModuleOp module, SymbolTable &symbols,
                                                  StringRef f) {
  llvm::SetVector<DataType> sums;
  auto note = [&](Type type) {
    type.walk([&](DataType data) {
      if (data.isMemo())
        sums.insert(data);
    });
  };
  programOf(module)->walk([&](Operation *op) {
    for (Type type : op->getResultTypes())
      note(type);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Type type : block.getArgumentTypes())
          note(type);
  });
  SmallVector<std::pair<StringAttr, bool>> out;
  for (DataType sum : sums)
    for (const Ctor &ctor : sum.getCtors()) {
      if (ctor.role != CtorRole::Label || !ctor.fn)
        continue;
      auto fn = symbols.lookup<FunctionOpInterface>(ctor.fn.getAttr());
      if (ctor.fn.getValue() == f || (fn && names(fn, f)))
        out.push_back({ctor.name, ctor.byName});
    }
  return out;
}

LogicalResult byNameIs(ModuleOp module, AnalysisManager &analyses, StringRef function, bool wanted,
                       StringRef property) {
  StringRef f = function.ltrim('@');
  if (f.empty())
    return fail(module.getLoc(), property) << "name the label's function, as " << property << "=@f";
  SmallVector<std::pair<StringAttr, bool>> labels = labelsOf(module, symbolsOf(module, analyses), f);
  if (labels.empty())
    return fail(module.getLoc(), property) << "no memo label of the program names " << function;
  bool held = true;
  for (auto [name, byName] : labels)
    if (byName != wanted) {
      fail(module.getLoc(), property) << "the label @" << name.getValue() << " of " << function
                                      << (byName ? " is" : " is not") << " by_name";
      held = false;
    }
  return success(held);
}

} // namespace

// Every memo label of the program whose function @f names is by name, and
// there is one; or none is.
LogicalResult byName(ModuleOp module, AnalysisManager &analyses, StringRef function) {
  return byNameIs(module, analyses, function, true, "by-name");
}
LogicalResult notByName(ModuleOp module, AnalysisManager &analyses, StringRef function) {
  return byNameIs(module, analyses, function, false, "not-by-name");
}

} // namespace idr::expect
