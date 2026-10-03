// idr.narrow:lanes: the integer lanes of a vectorized loop compute in 32
// bits under a runtime bound on its index space. A loop over an array
// computes its indices as the 64-bit Int the program wrote (idr-lower
// casts linalg.index to the word), and the target's lanes pay for it:
// neither x86-64-v3 nor NEON has a 64-bit vector multiply, and x86-64-v3
// has no int64-to-double conversion, so LLVM emulates the one and
// scalarizes the other, where 32-bit lanes have both. Each vectorized loop
// that computes on lanes of integers wider than 32 bits becomes two
// versions: where every integer it reads from outside (the sizes, the tile
// bound) is at most B, a copy in which every integer op that integer range
// analysis proves fits 32 bits is narrowed by upstream's
// arith-int-range-narrowing; otherwise the loop as it was. A loop that
// runs at most once, as upstream's value bounds see its bounds (the loop
// of a peeled tile loop's last tile), stays as it is: its version would
// never pay for the code it adds.
//
// The bound is an SSA fact, since the analysis reads no branch condition:
// in the copy each such input stands behind arith.minui of itself and B,
// which equals it under the guard and which the analysis bounds to [0, B].
// B is found, not guessed: the copy is built in a scratch module with the
// inputs as arguments and tried at powers of two from 2^31 down (a binary
// search over the exponent: a smaller bound fits whatever a larger one
// does), the analysis run on it each time, and the largest B kept at which
// every elementwise integer op in it wider than 32 bits fits, and is one
// whose 32-bit form computes what it computes (`exact`). Interval
// arithmetic over the body is what the analysis computes, so the body's
// own arithmetic decides the bound. The narrowing then runs on that copy
// under the analysis of the chosen B, and the copy is cloned into the
// version; the function itself is never analysed.
export module idr.narrow:lanes;

import idr.mlir;
import idr.graph;

import :copy;
import :widths;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::narrow {

// The exponents of the bounds tried: below 2^31 every index fits i32, and
// below 2^8 a version runs on too few elements to matter.
constexpr unsigned minExponent = 8;
constexpr unsigned maxExponent = 31;

// What `narrowLanes` did with the vectorized loops that compute on wide
// lanes: the loops versioned with 32-bit lanes, and the ones left wide.
export struct Lanes {
  uint64_t narrowed = 0;
  uint64_t wide = 0;
};

namespace {

// Versions `loop` with 32-bit lanes under a bound on its sizes, or leaves
// it as it is, with a remark; fails, after an error, on an internal error.
LogicalResult versionLanes(IRRewriter &rewriter, scf::ForOp loop, Lanes &done) {
  Location loc = loop.getLoc();
  auto wide = [&](const Twine &why) {
    remark::missed(loc, remark::RemarkOpts::name("Wide").category("idr-narrow-lanes"))
        << ("the lanes stay 64-bit: " + why).str();
    ++done.wide;
    return success();
  };
  auto internal = [&](const Twine &what) -> LogicalResult {
    return emitError(loc) << "internal error: idr-narrow-lanes: " << what;
  };
  if (idr::graph::runsAtMostOnce(loop))
    return wide("the loop runs at most once, which no version pays for");
  SetVector<Value> inputs = inputsOf(loop);
  if (llvm::none_of(inputs, testable))
    return wide("the loop reads no size from outside");
  Copy copy(loc, loop, inputs);
  // Whether the copy's integer ops fit under the bound 2^exponent.
  auto fitsAt = [&](unsigned exponent) -> FailureOr<bool> {
    std::unique_ptr<DataFlowSolver> solver = copy.analyse(exponent);
    if (!solver)
      return failure();
    return copy.fits(*solver);
  };
  FailureOr<bool> least = fitsAt(minExponent);
  if (failed(least))
    return internal("the analysis of a copy failed");
  if (!*least)
    return wide("its integer ops do not all compute the same in 32 bits under any bound on the sizes");
  unsigned low = minExponent, high = maxExponent;
  while (low < high) {
    unsigned mid = (low + high + 1) / 2;
    FailureOr<bool> at = fitsAt(mid);
    if (failed(at))
      return internal("the analysis of a copy failed");
    if (*at)
      low = mid;
    else
      high = mid - 1;
  }
  std::unique_ptr<DataFlowSolver> solver = copy.analyse(low);
  if (!solver)
    return internal("the analysis of a copy failed");
  if (failed(copy.narrow(*solver)))
    return internal("the narrowing of a copy did not converge");

  // if (every tested input <= 2^low) { the copy } else { the loop }.
  rewriter.setInsertionPoint(loop);
  llvm::MapVector<Type, Value> bounds;
  Value guard;
  for (Value input : inputs) {
    if (!testable(input))
      continue;
    Value &bound = bounds[input.getType()];
    if (!bound)
      bound = arith::ConstantOp::create(rewriter, loc,
                                        IntegerAttr::get(input.getType(), int64_t{1} << low));
    Value test = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::ule, input, bound);
    guard = guard ? Value(arith::AndIOp::create(rewriter, loc, guard, test)) : test;
  }
  auto branch = scf::IfOp::create(rewriter, loc, TypeRange{}, guard, /*withElseRegion=*/true);
  rewriter.setInsertionPointToStart(branch.thenBlock());
  copy.cloneInto(rewriter, inputs);
  rewriter.moveOpBefore(loop, branch.elseBlock()->getTerminator());
  remark::passed(loc, remark::RemarkOpts::name("Narrowed").category("idr-narrow-lanes"))
      << ("the integer lanes compute in 32 bits for sizes up to 2^" + Twine(low)).str();
  ++done.narrowed;
  return success();
}

} // namespace

// Makes the integer lanes of every vectorized loop of `module` compute in
// 32 bits under a runtime bound on its index space, where they can. Fails
// on an internal error.
export FailureOr<Lanes> narrowLanes(ModuleOp module) {
  Lanes done;
  // The outermost vectorized loops: a loop inside one is part of it.
  SmallVector<scf::ForOp> loops;
  module.walk<WalkOrder::PreOrder>([&](scf::ForOp loop) {
    if (!isVectorized(loop))
      return WalkResult::advance();
    loops.push_back(loop);
    return WalkResult::skip();
  });
  IRRewriter rewriter(module.getContext());
  for (scf::ForOp loop : loops)
    if (computesWideLanes(loop) && failed(versionLanes(rewriter, loop, done)))
      return failure();
  return done;
}

} // namespace idr::narrow
