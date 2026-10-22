// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// tests-nothing: a function tests no sharing at run time, and no reuse
// token for null. The one test of sharing reads a count and writes none,
// as its declaration says to the effect system; a token holds its cell,
// never null, exactly when its grade claims it unique, so a token of any
// other grade is tested for null wherever it is spent. A take of a value
// its type proves nothing of gives such a token, so it is found by its
// token.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Interfaces/CallInterfaces.h"

using namespace mlir;

namespace idr::expect {

// Something must be taken apart in @f, a token made there, so the property
// cannot hold of a function that takes nothing apart.
LogicalResult testsNothing(const Request<Functions> &request) {
  ArrayRef<FunctionOpInterface> functions = request.argument.functions;
  bool held = true, taken = false;
  auto token = [&](Value value, Operation *at) {
    if (!isa<ReuseTokenType>(unrestricted(value.getType())))
      return;
    taken = true;
    if (claims(value.getType(), Unique::Deep))
      return;
    fail(value.getLoc(), request.property) << "a reuse token of " << value.getType() << " in "
                                           << where(at) << " may be null, and is tested";
    held = false;
  };
  for (FunctionOpInterface fn : functions)
    fn.getFunctionBody().walk([&](Operation *op) {
      for (Region &region : op->getRegions())
        for (Block &block : region)
          for (BlockArgument arg : block.getArguments())
            token(arg, op);
      for (Value result : op->getResults())
        token(result, op);
      if (isa<CallOpInterface>(op))
        return;
      effects::EffectSet own = effects::own(op);
      if (!own.on(effects::Kind::Read, effects::ResourceId::Count) ||
          own.on(effects::Kind::Write, effects::ResourceId::Count))
        return;
      fail(op->getLoc(), request.property)
          << op->getName() << " tests the sharing of a value in " << where(op);
      held = false;
    });
  if (!taken) {
    fail(functions.front()->getLoc(), request.property)
        << "nothing is taken apart in @" << request.argument.name;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
