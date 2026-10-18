// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// by-name: whether a memo label runs again at every force, stated of the
// label's function, which the label names, as the sums the program's
// values hold say it: a label whose run the outside can see is by name,
// and keeps no value. The sum's own name is the pass's business.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/SetVector.h"

#include <variant>

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
      const auto *label = std::get_if<role::Label>(&ctor.role);
      if (!label)
        continue;
      auto fn = symbols.lookup<FunctionOpInterface>(label->fn.getAttr());
      if (label->fn.getValue() == f || (fn && names(fn, f)))
        out.push_back({ctor.name, label->byName});
    }
  return out;
}

LogicalResult byNameIs(const Request<Symbol> &request, bool wanted) {
  StringRef f = request.argument.name;
  SmallVector<std::pair<StringAttr, bool>> labels =
      labelsOf(request.module, symbolsOf(request.module, request.analyses), f);
  if (labels.empty())
    return fail(request.module->getLoc(), request.property)
           << "no memo label of the program names @" << f;
  bool held = true;
  for (auto [name, byName] : labels)
    if (byName != wanted) {
      fail(request.module->getLoc(), request.property)
          << "the label @" << name.getValue() << " of @" << f << (byName ? " is" : " is not")
          << " by_name";
      held = false;
    }
  return success(held);
}

} // namespace

// Every memo label of the program whose function @f names is by name, and
// there is one; or none is.
LogicalResult byName(const Request<Symbol> &request) { return byNameIs(request, true); }
LogicalResult notByName(const Request<Symbol> &request) { return byNameIs(request, false); }

} // namespace idr::expect
