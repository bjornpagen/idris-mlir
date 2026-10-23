// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Joins.h - The one construction of join points ----------------------===//
//
// Every join point is made here, whoever finds it: contification, which
// moves a function that always returns to one continuation into its
// caller; the tail passes, which make a self tail call a back jump; the
// arrays' loops, a turn per index of a finite domain; and the e-graph's
// case-of-case, which shares a consumer's cases between the arms of the
// match it consumes. The shape follows from the jumps alone: a group whose
// jump graph has a cycle is one idr.loop, whose regions repeat; any other
// is idr.joins nested from the members jumped to inward, the members of one
// depth sharing one flat idr.join, so no join region names a token its own
// op defines and none repeats.
//
// Tail position is a precondition of a jump, never a fact the jump holds: a
// site is an op whose results its block's terminator passes on unchanged to
// the place the group goes, which the finder established. The construction
// reads nothing else and decides nothing else: it never fails, and a
// precondition broken is a verifier error after the pass, an internal one.
// Whether a loop it makes may run forever is the finder's to say, from what
// Idris proved of the code it moves in (Ending): a loop that may begins each
// join region with idr.may_loop, whose divergence the row derived from the
// ops then holds wherever the loop goes, inlined, contified or copied, and
// which keeps it from being deleted as unused, since eager evaluation runs
// it. A group states no lifetime: a finder that moves scoped values into
// one restates its `outers` after, one lifetime per scoped result and then
// per scoped parameter of each region, in order (lifetimes::restateOuters).
//
//===----------------------------------------------------------------------===//

#ifndef IDR_TRANSFORMS_JOINS_H
#define IDR_TRANSFORMS_JOINS_H

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>

namespace idr::joins {

// One join point to make: the region whose one block becomes the join
// region, moved in whole. Its entry block's arguments become the join
// region's parameters, and its terminator, a function's idr.return or a
// match region's idr.yield, the group's idr.yield; a jump or a terminator
// that never ends stays. It binds `binders`, which its types name from
// level `firstLevel` on, renumbered to the depth of the group's scope.
struct Member {
  mlir::Region *body;
  IndexBindersAttr binders;
  unsigned firstLevel;
};

// A jump the group will hold from member `from` to member `to`, which the
// finder knows before any op is built: the jump graph that decides the
// shape. A jump from the body is no edge.
struct Edge {
  unsigned from;
  unsigned to;
};

// Whether the group's repetition, where its jumps form a cycle, is known to
// end: Idris proved together every function whose code its members are
// (endingOf), the pass that made it bounds its turns, or no member jumps to
// a member, so nothing repeats; or it may run forever, and each join region
// of the loop the group makes begins with idr.may_loop.
enum class Ending : std::uint8_t { Ends, MayNotEnd };

// The ending of a group whose members are the code of `functions`, one at
// least: Idris's one proof that a cycle of ours ends, every function on it
// proved in one and the same component of its own, the proof the writer of
// rows reads of a cycle of calls (rows::provedTogether). A cycle of
// calls that becomes a cycle of jumps keeps the divergence it had.
Ending endingOf(llvm::ArrayRef<FuncOp> functions);

// An op that becomes a jump to member `target`: the last op of its block
// before a terminator that passes on exactly its results. The jump passes
// `args`, values of the site's scope, and `terms` for the target's
// binders, the null attribute where it binds none.
struct Site {
  mlir::Operation *op;
  unsigned target;
  mlir::ValueRange args;
  IndexArgsAttr terms;
};

// The tokens of a group, seen from inside it.
class Targets {
public:
  // The token through which a jump in `in`, a region inside the group,
  // reaches member `member`.
  mlir::Value tokenFor(unsigned member, mlir::Region *in) const;

private:
  friend struct Builder;
  // Per member, its group op and its join region's index there: as many as
  // the group has members, so counted in the footprint.
  footprint::Vector<mlir::Operation *> ops;
  footprint::Vector<unsigned> indices;
};

// A group just built: its outermost op, its tokens, and its innermost body,
// a block that ends in nothing yet. The caller ends it: in a yield of the
// group's results, a jump, or a terminator that never ends.
struct Group {
  mlir::Operation *outermost;
  mlir::Block *body;
  Targets targets;
};

// Builds at the rewriter's insertion point the group of `members` with the
// jump graph `edges`, its results of types `results`; the members' regions
// are moved in, their terminators made the group's. A loop whose repetition
// may not end (`ending`) holds idr.may_loop at each join region's entry.
Group build(mlir::RewriterBase &rewriter, mlir::Location loc, mlir::TypeRange results,
            llvm::ArrayRef<Member> members, llvm::ArrayRef<Edge> edges, Ending ending);

// The index variables the scopes around `region` bind: each op that binds
// them says how many in its region (ErasedBinderOpInterface). A member's
// binders are renumbered to it where the group goes.
unsigned scopeDepth(mlir::Region *region);

// Replaces `site` by a jump through `token`: its block's terminator, which
// passed on the site's results, goes with it.
JumpOp jumpAt(mlir::RewriterBase &rewriter, const Site &site, mlir::Value token);

// The group of `members` around `place`, whose results become the group's:
// the body runs `place` and yields what it gives, and each site, in the
// body or in a member, becomes a jump; `ending` as `build` reads it.
// Returns the outermost op.
mlir::Operation *wrap(mlir::RewriterBase &rewriter, mlir::Operation *place,
                      llvm::ArrayRef<Member> members, llvm::ArrayRef<Site> sites, Ending ending);

// `fn` with self tail calls `calls` as one idr.loop: the function's body
// jumps into its one join region, which holds the old body, each self tail
// call a jump back, passing the call's erased arguments as its terms. The
// loop may run forever where Idris did not prove `fn` ends.
LoopOp loopSelf(mlir::RewriterBase &rewriter, FuncOp fn, llvm::ArrayRef<Site> calls);

} // namespace idr::joins

#endif // IDR_TRANSFORMS_JOINS_H
