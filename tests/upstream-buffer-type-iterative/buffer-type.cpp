// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// upstream/91-buffer-type-iterative, checked on the pinned MLIR:
// bufferization::getBufferType computes, on a thread whose stack a native
// frame per value of a chain would overflow, the buffer type of an scf.for
// that carries an allocated tensor through PAIRS pairs of tensor.cast, each
// to tensor<?xf32> and back to tensor<4xf32>, and gives what the recursion
// gave. The loop's result asks for its iter_arg's; the iter_arg for its
// init_arg's and then for the yielded value's, back along every cast to the
// iter_arg, which, met there a second time, is given the init_arg's; each
// cast keeps its source's layout. So the result, the iter_arg and the
// yielded value all have the allocation's buffer type, memref<4xf32>. The
// chain is flat: it is the computation that recursed on its length. Prints
// `ok` when the three hold, and what each was given otherwise.
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Arith/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Bufferization/IR/BufferizableOpInterface.h"
#include "mlir/Dialect/Bufferization/IR/Bufferization.h"
#include "mlir/Dialect/Bufferization/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/SCF/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/Tensor/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/thread.h"

#include <cstdlib>

using namespace mlir;
using namespace mlir::bufferization;

namespace {

// The stack the computation runs on: far below what a frame per value takes
// at the lengths the check uses.
constexpr unsigned smallStack = 256 * 1024;

// One value whose buffer type is asked for: what it is, and what it was
// given.
struct Asked {
  llvm::StringRef what;
  Value value;
  FailureOr<BufferLikeType> given = failure();
};

} // namespace

int main(int argc, char **argv) {
  if (argc != 2)
    return 2;
  unsigned pairs = static_cast<unsigned>(std::strtoul(argv[1], nullptr, 10));
  if (pairs == 0)
    return 2;
  DialectRegistry registry;
  registry.insert<arith::ArithDialect, BufferizationDialect, scf::SCFDialect,
                  tensor::TensorDialect>();
  arith::registerBufferizableOpInterfaceExternalModels(registry);
  bufferization::registerBufferizableOpInterfaceExternalModels(registry);
  scf::registerBufferizableOpInterfaceExternalModels(registry);
  tensor::registerBufferizableOpInterfaceExternalModels(registry);
  MLIRContext context(registry);
  context.loadAllAvailableDialects();

  OpBuilder b(&context);
  Location loc = b.getUnknownLoc();
  OwningOpRef<ModuleOp> module = ModuleOp::create(loc);
  b.setInsertionPointToEnd(module->getBody());
  Type f32 = b.getF32Type();
  auto fixed = RankedTensorType::get({4}, f32);
  auto unsized = RankedTensorType::get({ShapedType::kDynamic}, f32);
  Value allocation = AllocTensorOp::create(b, loc, fixed, ValueRange()).getResult();
  Value lower = arith::ConstantIndexOp::create(b, loc, 0);
  Value upper = arith::ConstantIndexOp::create(b, loc, 4);
  Value step = arith::ConstantIndexOp::create(b, loc, 1);
  Value yielded;
  auto loop = scf::ForOp::create(
      b, loc, lower, upper, step, ValueRange{allocation},
      [&](OpBuilder &body, Location at, Value, ValueRange carried) {
        Value value = carried.front();
        for (unsigned pair = 0; pair < pairs; ++pair) {
          value = tensor::CastOp::create(body, at, unsized, value);
          value = tensor::CastOp::create(body, at, fixed, value);
        }
        yielded = value;
        scf::YieldOp::create(body, at, value);
      });

  Asked asked[] = {{"the loop's result", loop.getResult(0)},
                   {"its iter_arg", loop.getRegionIterArgs().front()},
                   {"the yielded value", yielded}};
  BufferizationOptions options;
  BufferizationState state;
  llvm::thread compute(smallStack, [&] {
    for (Asked &each : asked)
      each.given = getBufferType(each.value, options, state);
  });
  compute.join();

  Type allocated = MemRefType::get({4}, f32);
  bool held = true;
  for (const Asked &each : asked)
    held = held && succeeded(each.given) && Type(*each.given) == allocated;
  if (held) {
    llvm::outs() << "ok\n";
    return 0;
  }
  for (const Asked &each : asked) {
    llvm::outs() << each.what << ": ";
    if (succeeded(each.given))
      llvm::outs() << Type(*each.given);
    else
      llvm::outs() << "no buffer type";
    llvm::outs() << ", where the allocation's is " << allocated << "\n";
  }
  return 1;
}
