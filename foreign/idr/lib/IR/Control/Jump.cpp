// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.jump: control leaves for the join region its token designates, its
// arguments that region's parameters. It consumes its token, upstream's
// builtin token, which only a join point's op defines: so a join point is
// named only by a jump, and no check of ours looks for an escape. A jump
// nested in a match reaches its join point through upstream's early exit,
// every op it crosses letting it through.

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

// Its target is the join region its token designates, read off the token's
// owner and number: the token is an entry argument of a region of a join
// point's op, so dominance already puts the jump inside that op. Every op
// between the jump and the owner must let a jump through. The arguments are
// the target's parameters: equal, where the target binds no index
// variable; an instance under the jump's terms otherwise, which the
// function's scope walk checks, since the substitution reads the depth of
// the scope. Each crosses at its parameter's hold where the program's stage
// lets a hold that fits stand (crossedAs).
LogicalResult JumpOp::verify() {
  // A token producer of another dialect may define its token as a result.
  auto token = dyn_cast<BlockArgument>(getTarget());
  Operation *owner = token ? token.getOwner()->getParentOp() : nullptr;
  auto points = dyn_cast_or_null<JoinPointsOpInterface>(owner);
  Region *target = points ? points.getTarget(token) : nullptr;
  if (!target)
    return emitOpError("expects a token that designates a join region");
  for (Operation *op = (*this)->getParentOp(); op != owner; op = op->getParentOp())
    if (!op->hasTrait<OpTrait::PropagateControlFlowBreak>())
      return emitOpError("crosses ") << op->getName() << ", which lets no jump through";
  ValueRange parameters = points.getParameters(*target);
  if (getArgs().size() != parameters.size())
    return emitOpError("passes ") << getArgs().size() << " arguments to a join region of "
                                  << parameters.size() << " parameters";
  if (cast<ErasedBinderOpInterface>(owner).getBoundSorts(*target).empty() &&
      !llvm::equal(getArgs().getTypes(), parameters.getTypes(), [&](Type given, Type asked) {
        return crossedAs(getOperation(), given, asked) == asked;
      }))
    return emitOpError("passes arguments of types ")
           << getArgs().getTypes() << " to parameters of types " << parameters.getTypes();
  return success();
}

// The values a jump passes become its target's parameters.
MutableOperandRange JumpOp::getMutableSuccessorOperands(RegionSuccessor) {
  return getArgsMutable();
}

// The op whose join region the token designates.
SmallVector<Operation *> JumpOp::getPotentialTargets() {
  return {cast<BlockArgument>(getTarget()).getOwner()->getParentOp()};
}
