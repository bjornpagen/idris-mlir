// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A lifetime is an SSA value of type `!idr.lifetime<kind>`. What the value
// is at run time is its type's kind, read in zero steps by every allocation
// into it, every callee given it, every frame holding it and the lowering;
// where its memory comes from is the op that opens it, one op per source
// (`idr.lifetime`, `.home`, `.block`, `.stack`, `.chain`). The kind is no
// identity: the identity is the value, whose scope MLIR keeps, so nothing
// of a lifetime outlives its region.
//
// A lifetime value is bound only by an opener's, a loan's or an unpack's
// entry argument, by `idr.activation`, by a function parameter, and by the
// two ops that derive one lifetime from another (`idr.lifetime.forget`,
// `idr.lifetime.reserve`), each of the extent of its operand. A value that
// lives in a lifetime is graded `scoped`, and the op that makes it states
// which lifetime (StatesLifetimeOpInterface): one hop, never a walk.
#ifndef IDR_IR_LIFETIMES_H
#define IDR_IR_LIFETIMES_H

#include "idr/IR/Grades.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/Hashing.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
#include <cstdint>
#include <optional>

// What a lowered lifetime is (Lowered), the kinds' cases and their facts
// (LifetimeKindCase), and the openers and the case each binds (Opener),
// printed from Spec.Lifetimes. `Packed`, an ODS enum since the package
// type's parameter is one, comes with the dialect's enums, which Grades.h
// includes once.
#include "idr/IR/Generated/Lifetimes.h.inc"

namespace idr {

// What a lifetime value is at run time: nothing, for a lifetime nothing
// allocates into (view); a pointer in, to a block of static size (room); a
// pointer in and out, an unbounded bump (cursor); or nothing, for the
// per-shard home of site k, which the decide step numbers densely (home).
// The parameter of `!idr.lifetime`; each fact of a case a load from the
// specification's table.
class LifetimeKind {
public:
  static constexpr LifetimeKind view() { return LifetimeKind(LifetimeKindCase::View, 0); }
  static constexpr LifetimeKind room() { return LifetimeKind(LifetimeKindCase::Room, 0); }
  static constexpr LifetimeKind cursor() { return LifetimeKind(LifetimeKindCase::Cursor, 0); }
  static constexpr LifetimeKind home(std::uint32_t site) {
    return LifetimeKind(LifetimeKindCase::Home, site);
  }
  // The one fold over the kind's cases: a home gives its site.
  template <std::invocable OnView, std::invocable OnRoom, std::invocable OnCursor,
            std::invocable<std::uint32_t> OnHome>
  constexpr decltype(auto) fold(OnView &&onView, OnRoom &&onRoom, OnCursor &&onCursor,
                                OnHome &&onHome) const {
    switch (kase) {
    case LifetimeKindCase::View:
      return onView();
    case LifetimeKindCase::Room:
      return onRoom();
    case LifetimeKindCase::Cursor:
      return onCursor();
    case LifetimeKindCase::Home:
      break;
    }
    return onHome(site);
  }

  constexpr LifetimeKindCase kindCase() const { return kase; }
  constexpr bool isView() const { return kase == LifetimeKindCase::View; }
  constexpr bool isRoom() const { return kase == LifetimeKindCase::Room; }
  constexpr bool isCursor() const { return kase == LifetimeKindCase::Cursor; }
  constexpr bool isHome() const { return kase == LifetimeKindCase::Home; }
  // Whether something may allocate into a lifetime of this kind: every kind
  // but a view, which has no memory.
  constexpr bool admitsPuts() const { return kindAdmitsPuts[index()] != 0; }
  // Whether a lifetime of this kind may be passed where a parameter of kind
  // `param` is asked: any kind where a view is asked, since nothing happens
  // to a view at run time; any other kind only to itself (a home to its own
  // site), so the call's type check is the mode check.
  constexpr bool passesAs(LifetimeKind param) const {
    return param.fold([&] { return kindPassesAsView[index()] != 0; },
                      [&] { return kindPassesAsRoom[index()] != 0; },
                      [&] { return kindPassesAsCursor[index()] != 0; },
                      [&](std::uint32_t paramSite) {
                        return kindPassesAsHome[index()] != 0 && site == paramSite;
                      });
  }
  // What a lifetime of this kind lowers to: no value for a view or a home,
  // a pointer in for a room, a pointer in and out for a cursor.
  constexpr Lowered lowered() const { return kindLowered[index()]; }
  // The case's keyword.
  llvm::StringRef spelling() const { return kindSpelling[index()]; }

  constexpr bool operator==(const LifetimeKind &) const = default;
  friend llvm::hash_code hash_value(LifetimeKind kind) {
    return llvm::hash_combine(kind.index(), kind.site);
  }

private:
  constexpr LifetimeKind(LifetimeKindCase kase, std::uint32_t site) : kase(kase), site(site) {}
  constexpr unsigned index() const { return static_cast<unsigned>(kase); }
  LifetimeKindCase kase;
  // A home's site; zero for every other kind, which has none.
  std::uint32_t site;
};

// The `LifetimeKind` directive of `!idr.lifetime`'s syntax: `view`, `room`,
// `cursor`, or `home k`.
mlir::ParseResult parseLifetimeKind(mlir::AsmParser &parser, mlir::FailureOr<LifetimeKind> &kind);
void printLifetimeKind(mlir::AsmPrinter &printer, LifetimeKind kind);

// Where an opener's memory comes from: a constant of its class, which the
// generated code specializes for each opener (`static constexpr Opener
// opener`), read by OpensLifetimeOpInterface's one method.
template <typename Op>
struct LifetimeOpener;

template <typename Op>
Opener openerOfOp(Op) {
  return LifetimeOpener<Op>::opener;
}

// Whether `type` is a lifetime of a kind something may allocate into, a
// cursor, a room, a view, or of the case `kase`: the predicates ODS asks of
// a lifetime operand, and an opener of the lifetime it binds.
bool admitsPuts(mlir::Type type);
bool isCursorLifetime(mlir::Type type);
bool isRoomLifetime(mlir::Type type);
bool isViewLifetime(mlir::Type type);
bool isLifetimeOfCase(mlir::Type type, LifetimeKindCase kase);

} // namespace idr

namespace idr::lifetimes {

// The kind of a lifetime value.
LifetimeKind kindOf(mlir::Value lifetime);

// Whether a lifetime of type `arg` may be passed where a parameter of type
// `param` is asked (LifetimeKind::passesAs): the call's rule for its
// lifetime operands, which idr.call's verifier reads.
bool passesAs(mlir::Type arg, mlir::Type param);

// The tail group's rule for a call in tail position, which idr.call's
// verifier reads with both signatures in hand: a cursor comes back from
// every call that puts into it, so a caller and its tail callee lower to
// equal returns only when they take the same number of cursor parameters.
bool sameCursors(mlir::FunctionType caller, mlir::FunctionType callee);

// The lifetime a scoped value lives in: what the op that made it states
// (StatesLifetimeOpInterface), for a result, or the op whose region binds
// it, for a block argument, a function stating its parameters'. One hop:
// no check follows a def-use chain. Null for a value that is not scoped.
mlir::Value statedLifetime(mlir::Value scoped);

// The lifetime whose extent a lifetime value has: the operand of a cast to
// a view or of a reserved room, which live as long as it; the value itself
// otherwise.
mlir::Value extentOf(mlir::Value lifetime);

// Where `lifetime`'s memory comes from, if an opener binds it.
std::optional<Opener> openerOf(mlir::Value lifetime);

// What a per-level lifetime's package holds, if its lifetime may be per
// level: a stack lifetime's mark, or a chain, by its opener or by the
// package an unpack reopened. A block in the opener's frame is never per
// level, and a lifetime without memory has nothing to pack.
std::optional<Packed> packedOf(mlir::Value lifetime);

// The cursor whose stack a stack lifetime is on: the base its opener, or the
// unpack that reopens it, names; null for any other lifetime.
mlir::Value baseOf(mlir::Value lifetime);

// The lifetime a cell is memory of: the one its source names (a slot of
// the frame stated in it, a cell bumped into it); null for a cell its count
// frees, whose source names none.
mlir::Value cellLifetime(mlir::Value cell);

// An op that states each scoped result's lifetime by its own operand of
// `outers`, in result order, after the results it gives of its own: two
// results of two lifetimes keep each its own span, and which entry is whose
// is read off the results' types. The openers, the loan, the unpack, and
// the control ops share this one definition.
template <typename Op>
concept StatesOuters = requires(Op op) {
  op.getOuters();
  op.getOutersMutable();
};

// How many of `op`'s results after the first `own` and before `end` are
// scoped.
template <StatesOuters Op>
unsigned scopedResults(Op op, unsigned own, unsigned end) {
  return static_cast<unsigned>(llvm::count_if(
      op->getResults().drop_front(own).take_front(end - own),
      [](mlir::Value result) { return freedBy(result.getType(), Release::Scoped); }));
}

// The position of result `made` among the scoped results after the first
// `own`, which its entry of `outers` has; none for a value that is no such
// result.
template <StatesOuters Op>
std::optional<unsigned> outerAt(Op op, mlir::Value made, unsigned own) {
  auto result = llvm::dyn_cast<mlir::OpResult>(made);
  if (!result || result.getOwner() != op.getOperation() || result.getResultNumber() < own)
    return std::nullopt;
  return scopedResults(op, own, result.getResultNumber());
}

template <StatesOuters Op>
mlir::Value statedOuter(Op op, mlir::Value made, unsigned own) {
  std::optional<unsigned> at = outerAt(op, made, own);
  auto outers = op.getOuters();
  if (!at || !freedBy(made.getType(), Release::Scoped) || *at >= outers.size())
    return nullptr;
  return outers[*at];
}

// States `lifetime` for result `made`: its entry restated, or made where the
// result has just become scoped; and, for a null lifetime of a result no
// longer scoped, its entry gone, so an op remade with fewer scoped results
// keeps one entry for each.
template <StatesOuters Op>
void stateOuter(Op op, mlir::Value made, mlir::Value lifetime, unsigned own) {
  std::optional<unsigned> at = outerAt(op, made, own);
  if (!at)
    return;
  llvm::SmallVector<mlir::Value, 4> outers(op.getOuters());
  unsigned scoped = scopedResults(op, own, op->getNumResults());
  bool isScoped = freedBy(made.getType(), Release::Scoped);
  if (lifetime && isScoped && outers.size() == scoped)
    outers[*at] = lifetime;
  else if (lifetime && isScoped && outers.size() + 1 == scoped)
    outers.insert(outers.begin() + *at, lifetime);
  else if (!lifetime && !isScoped && outers.size() == scoped + 1)
    outers.erase(outers.begin() + *at);
  else
    return;
  op.getOutersMutable().assign(outers);
}

// One entry of `outers` per scoped result after the first `own`.
template <StatesOuters Op>
mlir::LogicalResult verifyOuters(Op op, unsigned own) {
  unsigned scoped = scopedResults(op, own, op->getNumResults());
  if (op.getOuters().size() != scoped)
    return op.emitOpError("states ") << op.getOuters().size() << " lifetimes for its " << scoped
                                     << " scoped results, one each in their order";
  return mlir::success();
}

} // namespace idr::lifetimes

namespace idr {

// An op whose one region runs once and gives back what it yields, after
// the `Own` results it gives of its own (a loan's owner): the openers, the
// loan and the unpack. Each scoped result lives in the lifetime its own
// entry of `outers` states (StatesOuters): an entry for no scoped result
// would change nothing an op does, and a scoped result with no lifetime
// stated would be a value no check can place. An opener's region binds the
// kind the opener opens, and nothing else, which no region constraint of
// ODS can say.
template <typename ConcreteType, template <typename> class Trait, unsigned Own>
class RunsOnceAfter : public mlir::OpTrait::TraitBase<ConcreteType, Trait> {
public:
  static mlir::LogicalResult verifyRegionTrait(mlir::Operation *op) {
    auto self = llvm::cast<ConcreteType>(op);
    if (failed(lifetimes::verifyOuters(self, Own)))
      return mlir::failure();
    if constexpr (requires { LifetimeOpener<ConcreteType>::opener; }) {
      mlir::Block &entry = self.getBody().front();
      constexpr LifetimeKindCase opens =
          openerBinds[static_cast<unsigned>(LifetimeOpener<ConcreteType>::opener)];
      if (entry.getNumArguments() != 1 || !isLifetimeOfCase(entry.getArgument(0).getType(), opens))
        return op->emitOpError("binds no lifetime of the kind it opens, and nothing else");
    }
    return mlir::success();
  }
};

template <typename ConcreteType>
class RunsOnce : public RunsOnceAfter<ConcreteType, RunsOnce, 0> {};

template <typename ConcreteType>
class RunsOnceGivingBack : public RunsOnceAfter<ConcreteType, RunsOnceGivingBack, 1> {};

// An op whose result is a lifetime value: `idr.activation`, and the two ops
// that derive one lifetime from another (`idr.lifetime.forget`,
// `idr.lifetime.reserve`), each of its operand's extent. No other op gives
// one, which the function verifier reads off this trait.
template <typename ConcreteType>
class GivesLifetime : public mlir::OpTrait::TraitBase<ConcreteType, GivesLifetime> {};

} // namespace idr

#endif // IDR_IR_LIFETIMES_H
