// idr.ownership:counts: explicit counting: the grades, idr.dup and
// idr.drop that make every reference consumed exactly once on every path
// (Perceus; Counting Immutable Beans' C). It runs on functional code,
// where a match region's yield is the join point and recursion is still a
// call.
//
// Each value is placed on its own, along the ops of the block that
// defines it:
//   - an owned value (`!idr.own<T>`) holds one reference, which goes to its
//     last use on each path. A use that consumes a reference while the
//     value is still needed afterwards consumes an idr.dup of a view of it
//     instead; a last use that only reads is followed by an idr.drop; a
//     value nothing uses is dropped where it is defined. A match region
//     the value is not used in drops it on entry, unless it is still
//     needed after the match, and a region that ends in a crash is left
//     alone;
//   - a view (a borrowed parameter, a field, a constant) holds none: each
//     use that consumes one consumes an idr.dup of it;
//   - a field is a view when every use of it comes while the value it is
//     read from is still alive: a borrowed parameter, or an owned value
//     that is used again after it. Otherwise it takes a reference of its
//     own, an idr.dup where it is read, which is then placed as an owned
//     value, so that the value it comes from can die before it (Beans:
//     `let y = proj x; inc y`). A field of a static value is static.
// A read of an owned value (a field, a match, a borrowed argument) reads a
// view of it (idr.borrow). Every drop of a region's entry comes after the
// dups of its fields, so the fields survive their scrutinee. Nothing is
// placed after a call whose arguments it consumes, so a self tail call
// stays one.
//
// Counting a function takes three steps, each a type of its own: the
// classes of its values (Classes), the reshaping of its code before any
// count is placed (Reshape), and the placement of the counts (Placement).
export module idr.ownership:counts;

import idr.mlir;

import :classes;
import :counting;
import :placement;
import :reshape;

using namespace mlir;

namespace idr::ownership {

// Explicit counting (Perceus): the incs and decs that make every
// reference consumed exactly once on every path. Returns the numbers of
// incs and decs added, or failure after reporting what it cannot count.
export FailureOr<std::pair<unsigned, unsigned>> insertCounts(func::FuncOp fn, Counting &counting,
                                                             bool sink) {
  Classes classes(fn, counting);
  Reshape reshape(fn, counting, classes);
  if (failed(reshape.check()))
    return failure();
  reshape.rewriteSelects();
  reshape.takeApart();
  unsigned incs = reshape.ownFields();
  if (sink)
    reshape.sinkConsumers();
  auto [placedIncs, decs] = Placement(fn, classes).run();
  return std::make_pair(incs + placedIncs, decs);
}

} // namespace idr::ownership
