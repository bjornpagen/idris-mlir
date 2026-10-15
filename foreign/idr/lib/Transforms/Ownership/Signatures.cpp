// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The grades idr-rc's analyses decide, written into the signatures before
// the bodies are rewritten: the owned grades of borrow inference before
// placement, which reads them, and the excl grades of exclusivity before
// the commit, which meets every position against them. Only signatures,
// entry arguments and call results change here.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/IR/BuiltinTypes.h"

using namespace mlir;

namespace idr::ownership {

// An owned parameter and every result that holds references are owned
// (`!idr.own<T>`); a borrowed parameter is a view of the caller's value,
// at the view grade.
void writeOwnedGrades(ProgramOp program, const Borrows &borrows) {
  for (FuncOp fn : program.getOps<FuncOp>()) {
    SmallVector<Type> params(fn.getArgumentTypes());
    for (auto [index, param] : llvm::enumerate(borrows.params(fn))) {
      switch (param) {
      case Borrows::Param::Untracked:
        continue;
      case Borrows::Param::Owned:
        params[index] = owned(params[index]);
        break;
      case Borrows::Param::Borrowed:
        params[index] = view(params[index]);
        break;
      }
      fn.getArgument(static_cast<unsigned>(index)).setType(params[index]);
    }
    SmallVector<Type> results(fn.getResultTypes());
    for (Type &result : results)
      if (holdsReferences(result))
        result = owned(result);
    fn.setFunctionType(FunctionType::get(program.getContext(), params, results));
  }
}

// A parameter is exclusive when the solve proved its entry argument so: it
// saw every caller and each passes an exclusive value. A result is when
// every return the solve reached makes it so.
void writeExclusiveGrades(ProgramOp program, const Exclusivity &solved,
                          const SymbolTable &symbols) {
  for (FuncOp fn : program.getOps<FuncOp>()) {
    for (BlockArgument arg : fn.getArguments())
      if (solved.proves(arg))
        arg.setType(exclusive(arg.getType()));
    SmallVector<Type> results(fn.getResultTypes());
    std::optional<ArrayRef<Operation *>> returns = solved.returns(fn);
    if (returns && !returns->empty())
      for (auto [index, type] : llvm::enumerate(results)) {
        if (!isOwned(type))
          continue;
        if (llvm::all_of(*returns, [&](Operation *ret) {
              return solved.proves(ret->getOperand(static_cast<unsigned>(index)));
            }))
          type = exclusive(type);
      }
    fn.setFunctionType(FunctionType::get(
        program.getContext(), llvm::to_vector(fn.getBody().getArgumentTypes()), results));
  }
  // A call's results are its callee's, a function of the program.
  program.walk([&](CallOp call) {
    auto callee = symbols.lookup<FuncOp>(call.getCalleeAttr().getAttr());
    for (auto [result, type] : llvm::zip_equal(call.getResults(), callee.getResultTypes()))
      result.setType(type);
  });
}

} // namespace idr::ownership
