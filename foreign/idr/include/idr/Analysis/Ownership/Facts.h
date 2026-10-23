// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The facts of a value's type and of the IR that the ownership markings
// read (exclusivity, borrows, the in-place check, the local rule), each
// answered by the declaration that holds it: the grade's axes, and how far
// a claim on a value's own cells reaches into each of its fields, by the
// grade (Grades.h); a family's promise and constructors by the data type
// (Families/); how a value moves by the flow interface and upstream's
// region interfaces. Nothing here decides: each line reads one fact its
// owner keeps, so no marking holds a second copy of a type's facts.
#ifndef IDR_ANALYSIS_OWNERSHIP_FACTS_H
#define IDR_ANALYSIS_OWNERSHIP_FACTS_H

#include "idr/IR/Families/Declaration.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Match.h"

#include "mlir/IR/Block.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Region.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/LoopLikeInterface.h"
#include "llvm/ADT/STLExtras.h"

#include <cstdint>
#include <optional>

namespace idr::ownership {

// What a requirement on a value asks of its cells, on the grade's sharing
// axis: its own cells unshared (`unique self`, which reaches into a field
// as far as fieldReach says), or nothing it reaches shared (`unique deep`).
// Deep asks all that Self does, so the two are ordered as their claims.
enum class Asks : std::uint8_t { Self, Deep };

constexpr Unique claimFor(Asks asks) { return asks == Asks::Self ? Unique::Self : Unique::Deep; }

// What a claim asks as a requirement: the inverse of claimFor, and nothing
// for a claim of nothing.
constexpr std::optional<Asks> asksFor(Unique claim) {
  if (claim == Unique::None)
    return std::nullopt;
  return claim == Unique::Self ? Asks::Self : Asks::Deep;
}

// What a field reached as `reach`, read at `uses`, gives of a value
// claiming `claim`: the grade's own table (Hold::read), never a
// restatement of it. A read at one use gives what the claim reaches; a read
// at many gives nothing, since what is used many times may be copied.
constexpr Unique readClaim(FieldReach reach, Uses uses, Unique claim) {
  return Hold::counted(claim).read(reach, uses).claim();
}

// The alternatives of the flow sums that one case takes together, each set
// named by its list, so an alternative a sum gains is taken by no case
// until one names it.
// A source at a whole value, no part of one.
template <class T>
concept WholeSource =
    OneOf<T, FlowSource::Taken, FlowSource::Whole, FlowSource::Parameter, FlowSource::Result>;
// A source that is no use the op takes over whole.
template <class T>
concept NotTaken =
    OneOf<T, FlowSource::Whole, FlowSource::Part, FlowSource::Parameter, FlowSource::Result>;
// A place at a whole value, no part of one.
template <class T>
concept WholePlace = OneOf<T, FlowSource::Whole, FlowSource::Parameter, FlowSource::Result>;
// A move that is no flow from a source into a place.
template <class T>
concept NoFlow = OneOf<T, FlowEdges::Unify, FlowEdges::Source, FlowEdges::Fresh,
                       FlowEdges::Release, FlowEdges::Overwrite, FlowEdges::Fill,
                       FlowEdges::Constant, FlowEdges::Dispatch>;
// A move that neither takes a use over nor gives one up.
template <class T>
concept KeepsUses = OneOf<T, FlowEdges::Unify, FlowEdges::Source, FlowEdges::Fresh,
                          FlowEdges::Overwrite, FlowEdges::Fill, FlowEdges::Constant,
                          FlowEdges::Dispatch>;

// How far a claim on a value's own cells reaches into the part `anchor`
// names: a field's declaration says (fieldReach); the elements, the forced
// state, the memo state, a capture and a hole are no own cells of the value.
inline FieldReach reachAt(const FlowAnchor &anchor) {
  return match(
      anchor.place,
      [](const FlowAnchor::Field &field) {
        return fieldReach(field.group.ctor(field.member, field.ctor).fields[field.index]);
      },
      [](const OneOf<FlowAnchor::Elements, FlowAnchor::Forced, FlowAnchor::MemoState,
                     FlowAnchor::Capture, FlowAnchor::Hole> auto &) { return FieldReach::Other; });
}

// What a requirement `asks` on a value asks of the holder it is moved out
// of, through a part reached as `reach`: the least claim on the holder
// whose read of that part gives what is asked, the part moved at one use
// (the rule counts a value's uses itself). A self requirement stays self
// where the holder's claim on its own cells covers the part, so a record
// that holds a rebuilt list owes `unique self`; through any other part only
// a deep claim covers it.
constexpr Asks holderAsks(Asks asks, FieldReach reach) {
  return asks == Asks::Self && readClaim(reach, Uses::Once, Unique::Self) == Unique::Self
             ? Asks::Self
             : Asks::Deep;
}

// Whether a requirement `asks` on a value built of a part reached as
// `reach` reaches the part: a read of the part, at one use, from a value
// meeting it still claims something.
constexpr bool asksOfPart(Asks asks, FieldReach reach) {
  return readClaim(reach, Uses::Once, claimFor(asks)) != Unique::None;
}

// What a value of `type` claims of its sharing: its hold's, none for a type
// that holds no reference or for static data.
inline Unique claimOf(mlir::Type type) {
  std::optional<Hold> hold = holdOf(type);
  return hold ? hold->claim() : Unique::None;
}

// Whether a value of `type` holds a reference whose sharing is still open
// below `asked`: it holds references, its count frees it (static data is
// shared by definition, and a scoped value is a view or a lifetime's cell,
// which no count tests), and its grade claims less. A value whose type
// answers has no node in any marking.
inline bool leavesOpen(mlir::Type type, Unique asked) {
  std::optional<Hold> hold = holdOf(type);
  return holdsReferences(type) && hold && hold->release() == Release::Counted &&
         !hold->claims(asked);
}

// Whether a value of `type` is counted at all, whatever it claims.
inline bool counted(mlir::Type type) {
  std::optional<Hold> hold = holdOf(type);
  return holdsReferences(type) && hold && hold->release() == Release::Counted;
}

// `type` with its claim raised to `unique`: a verified refinement on the
// grade's sharing axis, its uses and release kept.
inline mlir::Type claiming(mlir::Type type, Unique unique) {
  return atHold(type, holdOf(type)->refined(unique));
}

// The data type a value of `type` is an application of, seen through its
// grade; null for any other type.
inline DataType familyOf(mlir::Type type) {
  return llvm::dyn_cast<DataType>(unrestricted(type));
}

// What `data`'s in-place promise asks of a value it rebuilds, read off the
// family's declaration (promisedClaim): its own cells unshared, whatever
// they hold. That reaches the storage of every buffer one of them holds
// and never the buffer's elements, so bufferization writes the buffer in
// place while what it holds may be shared; nothing where the family
// promises nothing, or for a value of no family.
inline std::optional<Asks> promisedAsks(DataType data) {
  return data ? asksFor(data.promisedClaim()) : std::nullopt;
}

// Whether two family applications are of one family, whatever their index
// terms and refinements: a rebuild may change an index (a cons onto a vector
// of length n is one of length n + 1), never the family.
inline bool sameFamily(DataType a, DataType b) {
  return a && b && a.getGroup() == b.getGroup() && a.getMember() == b.getMember();
}

// Whether a value of a memo family: its cells change while references to
// them live, so what a field holds is the label's, not the cell value's.
inline bool isMemo(DataType data) {
  using namespace idr::families;
  return data && data.kind() == MemberKind::Memo;
}

// The constructor a value of `type` is refined to, when one: what a case
// region binds, and what a construction builds.
inline std::optional<Tag> refinedTag(mlir::Type type) {
  DataType data = familyOf(type);
  return data ? data.singleTag() : std::nullopt;
}

// Whether a value of `type`, refined to one constructor, is a cell: its
// layout is one pointer to a cell, which a take hands out and a rebuild
// fills again.
inline bool isCell(mlir::Type type) {
  DataType data = familyOf(type);
  return data && data.isCellPointer();
}

// Whether a value of `type` bounds everything it reaches: no cycle of
// containment and no dynamically sized cell, the layout fact a data type
// computes when it is made. A borrowed argument whose type bounds what it
// reaches holds a fixed number of bytes past its last use, which the
// frame-limited rule allows.
inline bool boundsWhatItReaches(mlir::Type type) {
  DataType data = familyOf(type);
  return data && data.boundsReach();
}

// The value a position hands on as itself, when `value` is the result of
// one: an op that keeps its operand's value at another grade (the
// SameValue trait, the linear cast among them). The flow of a region branch
// is read separately (forwardedValues).
inline std::optional<mlir::Value> sameValueSource(mlir::Value value) {
  mlir::Operation *op = value.getDefiningOp();
  if (op && op->hasTrait<SameValue>())
    return op->getOperand(0);
  return std::nullopt;
}

// The field of a data type `anchor` names, when it names one.
inline std::optional<FlowAnchor::Field> fieldOf(const FlowAnchor &anchor) {
  using Found = std::optional<FlowAnchor::Field>;
  return match(
      anchor.place, [](const FlowAnchor::Field &field) -> Found { return field; },
      [](const FlowAnchor::Elements &) -> Found { return std::nullopt; },
      [](const FlowAnchor::Forced &) -> Found { return std::nullopt; },
      [](const FlowAnchor::MemoState &) -> Found { return std::nullopt; },
      [](const FlowAnchor::Capture &) -> Found { return std::nullopt; },
      [](const FlowAnchor::Hole &) -> Found { return std::nullopt; });
}

// How a part is reached: out of a use the op takes over, or read from a
// value the op leaves its reference.
enum class Reach : std::uint8_t { Taken, Read };
inline Reach reachOf(const FlowSource::Part &part) {
  return match(
      part.of, [](const FlowSource::Taken &) { return Reach::Taken; },
      [](const FlowSource::Whole &) { return Reach::Read; });
}

// What the place a part is read from holds once the op has read it, as the
// op's edges say: nothing, the reference it held moved out with the part,
// where the op takes over the whole the part is of, or keeps the whole and
// declares that place overwritten (an array's take, a memo cell's
// exchange: the place holds nothing until a later write fills it); or the
// reference it held, which the part only views. An overwrite of another
// place says nothing of this one.
enum class PlaceAfter : std::uint8_t { Emptied, Kept };

// The place `part` is read from among `edges`, the edges of the op that
// reads it.
inline PlaceAfter placeAfter(const FlowEdges &edges, const FlowSource::Part &part) {
  if (reachOf(part) == Reach::Taken)
    return PlaceAfter::Emptied;
  mlir::Value whole = part.value();
  bool overwritten = llvm::any_of(edges.edges(), [&](const FlowEdges::Edge &edge) {
    return match(
        edge.move,
        [&](const FlowEdges::Overwrite &over) {
          return over.place.of == whole && over.place.anchor == part.anchor;
        },
        [](const OneOf<FlowEdges::Flow, FlowEdges::Unify, FlowEdges::Source, FlowEdges::Fresh,
                       FlowEdges::Release, FlowEdges::Fill, FlowEdges::Constant,
                       FlowEdges::Dispatch> auto &) { return false; });
  });
  return overwritten ? PlaceAfter::Emptied : PlaceAfter::Kept;
}

// Whether `op` is one of upstream's, which reads and makes only the bare
// carriers its own constraints name, never a grade of ours: an op of
// another dialect that is neither a region branch nor a terminator of one.
// What those forward is a position, met as a call's argument is
// (forwardedValues), and scf's take any type.
inline bool carriersOnly(mlir::Operation *op) {
  return !llvm::isa_and_present<IdrDialect>(op->getDialect()) &&
         !llvm::isa<mlir::RegionBranchOpInterface, mlir::RegionBranchTerminatorOpInterface>(op);
}

// Whether `op` may run one of its regions any number of times (a loop, a
// recursive join group): a value from outside used in one is used once per
// run.
inline bool repeats(mlir::Operation *op) { return llvm::isa<mlir::LoopLikeOpInterface>(op); }

// Whether `use`, an op, may run after `call` on some path: later in a block
// that holds the call, anywhere in a region that runs again around it, or
// in a region of a branch that is not an alternative to the call's.
inline bool runsAfter(mlir::Operation *use, mlir::Operation *call) {
  for (mlir::Operation *at = call; at && !llvm::isa<FuncOp>(at); at = at->getParentOp()) {
    if (mlir::Operation *holder = at->getBlock()->findAncestorOpInBlock(*use)) {
      if (holder != at)
        return at->isBeforeInBlock(holder);
      return !mlir::insideMutuallyExclusiveRegions(use, call);
    }
    mlir::Operation *parent = at->getParentOp();
    if (parent && repeats(parent) && parent->isAncestor(use))
      return true;
  }
  return false;
}

// Whether `use` reads a part of its value and takes none of it over: a
// field read, a view of a part, which the op declares as a move out of a
// part of the value it leaves its reference.
inline bool readsPart(mlir::OpOperand &use) {
  auto declared = llvm::dyn_cast<FlowOpInterface>(use.getOwner());
  if (!declared)
    return false;
  FlowEdges edges;
  declared.getFlowEdges(edges);
  return llvm::any_of(edges.edges(), [&](const FlowEdges::Edge &edge) {
    return match(
        edge.move,
        [&](const FlowEdges::Flow &flow) {
          return match(
              flow.from.at,
              [&](const FlowSource::Part &part) {
                return reachOf(part) == Reach::Read && flow.from.value() == use.get();
              },
              [](const WholeSource auto &) { return false; });
        },
        [](const NoFlow auto &) { return false; });
  });
}

// Whether `value` is an element read out of the elements of an array, as
// the op that reads it declares: a view by its stretch's row where nothing
// there writes, else a reference of its own, never a part of the array's.
inline bool readOutOfElements(mlir::Value value) {
  auto declared = llvm::dyn_cast_or_null<FlowOpInterface>(value.getDefiningOp());
  if (!declared)
    return false;
  FlowEdges edges;
  declared.getFlowEdges(edges);
  return llvm::any_of(edges.edges(), [&](const FlowEdges::Edge &edge) {
    return match(
        edge.move,
        [&](const FlowEdges::Flow &flow) {
          if (flow.to.value() != value)
            return false;
          return match(
              flow.from.at,
              [](const FlowSource::Part &part) {
                return match(
                    part.anchor.place, [](const FlowAnchor::Elements &) { return true; },
                    [](const OneOf<FlowAnchor::Field, FlowAnchor::Forced, FlowAnchor::MemoState,
                                   FlowAnchor::Capture, FlowAnchor::Hole> auto &) {
                      return false;
                    });
              },
              [](const WholeSource auto &) { return false; });
        },
        [](const NoFlow auto &) { return false; });
  });
}

// Whether `value` is an element an op of upstream's reads out of an array
// (a tensor.extract, a memref.load): its type is the array's element type,
// which that op's own verifier holds it to, so it keeps its type's grade.
// No pass of ours rewrites it, and no rule follows it into the array, which
// keeps its own reference beside it. A poison is no such value: its op
// reads nothing, so its type is ours to choose.
inline bool upstreamElement(mlir::Value value) {
  mlir::Operation *op = value.getDefiningOp();
  return op && carriersOnly(op) && readOutOfElements(value);
}

} // namespace idr::ownership

#endif // IDR_ANALYSIS_OWNERSHIP_FACTS_H
