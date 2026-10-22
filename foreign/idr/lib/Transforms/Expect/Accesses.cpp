// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// writes-forwarded and overwrites-dropped: of two accesses of one element
// of mutable memory, the one the other makes redundant is gone, stated as
// what is not left. A read right after a write of its element is the value
// written; a write right after a write of its element overwrites what
// nothing read, so the first goes. "Right after" is stated in a small
// scope of its own, apart from how the passes find such a pair: the first
// op before that does more than compute, as the effect system's one query
// says, is a write of the same array value at the same index values. A read
// borrows and a write moves its value in, so both are of a program whose
// references are not yet counted; and neither holds of a value Idris proved
// used once, whose one use the pair is.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/STLExtras.h"

#include "idr/IR/Generated/StageFacts.h.inc"

using namespace mlir;

namespace idr::expect {

namespace {

// The write right before `op` in its block of the element `array` at
// `indices` names: the first op before `op` that does more than compute,
// where it writes that array value at those index values; none otherwise.
std::optional<ArraySetOp> writeRightBefore(Operation *op, Value array, ValueRange indices) {
  Operation *before = op->getPrevNode();
  while (before && effects::whole(before).onlyComputes())
    before = before->getPrevNode();
  auto write = dyn_cast_or_null<ArraySetOp>(before);
  if (!write || write.getArray() != array || !llvm::equal(write.getIndices(), indices))
    return std::nullopt;
  return write;
}

// Both properties are of a program whose references are not yet counted:
// stated of another, a counted one or the lowered module, each fails at
// the program, saying so, and is never held by having nothing to check.
LogicalResult uncounted(const Request<Roots> &request) {
  auto program = dyn_cast<ProgramOp>(programOf(request.module));
  if (program && countingAt[program.getStage()] == StageCounting::Uncounted)
    return success();
  return fail(program ? program.getLoc() : request.module->getLoc(), request.property)
         << "is stated of a program whose references are not yet counted, which the module "
            "does not hold";
}

} // namespace

// In the function the argument names and its clones, or anywhere, no read
// of mutable memory reads the element the write right before it wrote,
// where the value written may stand for the read's and Idris did not prove
// it used once.
LogicalResult writesForwarded(const Request<Roots> &request) {
  if (failed(uncounted(request)))
    return failure();
  bool held = true;
  for (Operation *root : request.argument.roots(request.module))
    root->walk([&](ArrayGetOp read) {
      std::optional<ArraySetOp> write = writeRightBefore(read, read.getArray(), read.getIndices());
      if (!write)
        return;
      Type written = write->getValue().getType();
      if (isLinear(written) || !forgets(written, read.getValue().getType()))
        return;
      fail(read.getLoc(), request.property)
          << "a read in " << where(read) << " reads the element the write right before it wrote";
      held = false;
    });
  return success(held);
}

// In the function the argument names and its clones, or anywhere, no write
// of mutable memory is followed by a write of its element, where Idris did
// not prove its value used once; each is reported where it stands.
LogicalResult overwritesDropped(const Request<Roots> &request) {
  if (failed(uncounted(request)))
    return failure();
  bool held = true;
  for (Operation *root : request.argument.roots(request.module))
    root->walk([&](ArraySetOp write) {
      std::optional<ArraySetOp> earlier =
          writeRightBefore(write, write.getArray(), write.getIndices());
      if (!earlier || isLinear(earlier->getValue().getType()))
        return;
      fail(earlier->getLoc(), request.property)
          << "a write in " << where(*earlier) << " is overwritten by the next, unread";
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
