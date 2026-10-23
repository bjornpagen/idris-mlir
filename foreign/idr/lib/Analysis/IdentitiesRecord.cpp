// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one read of a function whose results might give back its arguments.
//
// Each value is numbered in walk order and given how it is built: an entry
// argument; the same value as another or a field of a refined value
// (idr::sourceOf); a call's result; a match's result; what an op's
// structure says it is built of, a constructor or a natural's successor or
// predecessor; a constant; an op's own result, opaque, with the operands it
// may hold; what a region branch forwards into, with what may enter it; or
// unseen, any other region's argument or what any other op with regions
// gives. Whether each value holds references is read off its type here,
// once. A call is resolved to its callee's id once, here. Each use that
// can rebuild a part carries what the case regions around it say of their
// scrutinees: a data match's region binds its scrutinee refined, to one
// constructor in a case and to the ones left in its default; a literal
// match's case is its literal. The read writes nothing outside the record
// and reads the body once.
#include "idr/Analysis/Solver/IdentityRecords.h"

#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Match.h"

#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"

#include <iterator>
#include <optional>

using namespace mlir;

namespace idr::identities {

// One value at run time: the same carrier, or two applications of one
// family member whose layout is the same, so the bits of one are the bits
// of the other (Fin n and Fin (S n) after their indices are erased).
Represents representation(Type a, Type b) {
  if (unrestricted(a) == unrestricted(b))
    return Represents::Alike;
  DataType l = dataTypeOf(a), r = dataTypeOf(b);
  if (l && r && l.getGroup() == r.getGroup() && l.getMember() == r.getMember() &&
      l.layout() == r.layout())
    return Represents::Alike;
  return Represents::Differently;
}

// Each carrier admits one literal per value (a big's is keyed by its integer
// at its fewest bits, whatever width it was written at), so two literals
// are one value exactly when they are one attribute.
bool operator==(const KnownLiteral &a, const KnownLiteral &b) { return a.literal == b.literal; }

namespace {

// What a constant of `type` is to a case: a constructor with no fields has
// one value, its tag; any other constant is its literal.
Known knownOf(Attribute constant, Type type) {
  auto con = dyn_cast<ConAttr>(constant);
  DataType data = dataTypeOf(type);
  if (con && data && data.ctor(con.getTag()).fields.empty())
    return KnownTag{con.getTag()};
  return KnownLiteral{constant};
}

// What `region` of `match` says of the scrutinee where it runs, where it
// says one thing, as the match answers for the region: the literal a
// literal match's case equals; the constructor the value a region binds the
// scrutinee as is refined to, where one is left (a literal match's default
// binds it at its own type, which leaves none).
std::optional<Known> knownIn(MatchOpInterface match, Region &region) {
  return idr::match(
      match.getRegionScrutinee(region),
      [](const case_scrutinee::Equals &equal) -> std::optional<Known> {
        return KnownLiteral{equal.literal};
      },
      [](const case_scrutinee::Bound &bound) -> std::optional<Known> {
        DataType refined = dataTypeOf(bound.value.getType());
        std::optional<Tag> tag = refined ? refined.singleTag() : std::nullopt;
        if (!tag)
          return std::nullopt;
        return KnownTag{*tag};
      });
}

template <solver::FunctionNames N>
class Reader {
public:
  Reader(const N &names, FuncOp fn, Record &out, const solver::Numbering<ValueTag> &numbering)
      : names(names), fn(fn), out(out), numbering(numbering) {}

  Build buildOf(Value value);
  void readReturns();

private:
  Range push(ValueRange values) {
    Range range{static_cast<std::uint32_t>(out.operands.size()), 0};
    for (Value value : values)
      out.operands.push_back(numbering.at(value));
    range.count = static_cast<std::uint32_t>(out.operands.size()) - range.first;
    return range;
  }
  Range framesAt(Operation *at);
  Build ofResult(OpResult result);
  Build opaqueOf(Value value, Operation *op);
  std::optional<Range> enteringInto(Value value);
  std::uint32_t sideOf(MatchOpInterface match);

  const N &names;
  FuncOp fn;
  Record &out;
  const solver::Numbering<ValueTag> &numbering;
  // The match whose results are being read, and its side: a match's
  // results are visited one after another.
  Operation *lastMatch = nullptr;
  std::uint32_t lastSide = 0;
  // The opaque op whose results are being read, and its operands' run,
  // pushed once for all of them.
  Operation *lastOpaque = nullptr;
  Range lastFrom;
};

// The case regions around `at`, inner first, each with what it says of its
// scrutinee.
template <solver::FunctionNames N>
Range Reader<N>::framesAt(Operation *at) {
  Range range{static_cast<std::uint32_t>(out.frames.size()), 0};
  for (Region *region = at->getParentRegion(); region && region->getParentOp() != fn.getOperation();
       region = region->getParentRegion()) {
    auto match = dyn_cast<MatchOpInterface>(region->getParentOp());
    if (!match || region->empty())
      continue;
    if (std::optional<Known> known = knownIn(match, *region))
      out.frames.push_back({numbering.at(match.getScrutinee()), *known});
  }
  range.count = static_cast<std::uint32_t>(out.frames.size()) - range.first;
  return range;
}

// A match's regions, read once at its first result: each that yields to
// the match is an arm with its values; one that ends otherwise (a crash,
// a jump out of it) never gives the match its results; an empty default
// region never runs. A yield returns to its parent, the match, as
// upstream's ReturnLike says; a jump is a region branch's terminator too,
// but leaves for an enclosing join point, with that point's parameters.
template <solver::FunctionNames N>
std::uint32_t Reader<N>::sideOf(MatchOpInterface match) {
  if (match.getOperation() == lastMatch)
    return lastSide;
  Range arms{static_cast<std::uint32_t>(out.arms.size()), 0};
  for (Region &region : match->getRegions()) {
    if (region.empty())
      continue;
    Operation *end = region.front().getTerminator();
    if (end->hasTrait<OpTrait::ReturnLike>())
      out.arms.push_back(Yields{push(end->getOperands()), framesAt(end)});
    else
      out.arms.push_back(NeverReturns{});
  }
  arms.count = static_cast<std::uint32_t>(out.arms.size()) - arms.first;
  lastMatch = match.getOperation();
  lastSide = static_cast<std::uint32_t>(out.sides.size());
  out.sides.push_back(arms);
  return lastSide;
}

// The function a call names, where its callee is a name and not a value
// (an application runs whatever its closure holds).
FlatSymbolRefAttr calleeNamed(CallOpInterface call) {
  return dyn_cast_if_present<FlatSymbolRefAttr>(
      dyn_cast_if_present<SymbolRefAttr>(call.getCallableForCallee()));
}

// What a result is built of, where idr::sourceOf found it made here: the
// closed set of constructs this question reads, each through MLIR's
// dispatch for it: a call by name (upstream's call interface, whose every
// argument a callee may give back, a word among them), a match, an op's
// structure, a constant. Each alternative of a structure is one of the
// record's builds, as the op answered it, so no op is named and nothing it
// said is derived again.
template <solver::FunctionNames N>
Build Reader<N>::ofResult(OpResult result) {
  Operation *op = result.getOwner();
  if (auto call = dyn_cast<CallOpInterface>(op))
    if (FlatSymbolRefAttr callee = calleeNamed(call)) {
      auto at = static_cast<std::uint32_t>(out.calls.size());
      if (result.getResultNumber() == 0)
        out.calls.push_back({names.id(callee), push(call.getArgOperands())});
      else
        at -= 1;
      return build::Result{at, result.getResultNumber(), result.getType()};
    }
  if (auto match = dyn_cast<MatchOpInterface>(op))
    return build::Join{sideOf(match), result.getResultNumber()};
  if (std::optional<Range> entering = enteringInto(result))
    return build::Forwarded{*entering};
  if (auto structured = dyn_cast<StructureOpInterface>(op))
    return match(
        structured.getStructure(),
        [&](const structural::Built &built) -> Build {
          return build::Con{built.tag, result.getType(), push(built.fields), framesAt(op)};
        },
        [&](const structural::Successor &successor) -> Build {
          return build::Successor{numbering.at(successor.of)};
        },
        [&](const structural::Predecessor &predecessor) -> Build {
          return build::Pred{numbering.at(predecessor.of)};
        },
        [&](const structural::Unbuilt &) -> Build { return opaqueOf(result, op); });
  Attribute constant;
  if (matchPattern(result, m_Constant(&constant)))
    return build::Constant{knownOf(constant, result.getType()), result.getType()};
  return opaqueOf(result, op);
}

// What enters `value` where it is a successor input of a region branch (a
// region's argument, or the branch's result), on every edge into it, as
// upstream's interface lists them: the branch's entry operands and each
// terminator's that branches to it. None where no region branch forwards
// into it.
template <solver::FunctionNames N>
std::optional<Range> Reader<N>::enteringInto(Value value) {
  auto result = dyn_cast<OpResult>(value);
  Region *region = result ? nullptr : cast<BlockArgument>(value).getParentRegion();
  Operation *owner = result ? result.getOwner() : region->getParentOp();
  auto branch = dyn_cast<RegionBranchOpInterface>(owner);
  if (!branch)
    return std::nullopt;
  RegionSuccessor successor = result ? RegionSuccessor(owner) : RegionSuccessor(region);
  ValueRange inputs = branch.getSuccessorInputs(successor);
  auto found = llvm::find(inputs, value);
  if (found == inputs.end())
    return std::nullopt;
  SmallVector<Value> entering;
  branch.getPredecessorValues(successor, static_cast<int>(std::distance(inputs.begin(), found)),
                              entering);
  return push(entering);
}

// What `op` makes as `value` where this question cannot see through it: no
// part of anything, and holding at most what its operands hold, each run
// pushed once per op, whole where the op only changes a grade; nothing
// where the value holds no reference, so a word's op pushes nothing. An op
// with regions gives what its regions yield, which is not read here, so its
// results are unseen.
template <solver::FunctionNames N>
Build Reader<N>::opaqueOf(Value value, Operation *op) {
  if (op->getNumRegions() != 0)
    return build::Unseen{};
  if (out.refs[numbering.at(value)] == Refs::Words)
    return build::Opaque{};
  if (op != lastOpaque) {
    lastOpaque = op;
    lastFrom = push(op->getOperands());
  }
  return build::Opaque{lastFrom, op->hasTrait<ResultCarriesOperand>() ? Reach::Whole : Reach::Part};
}

template <solver::FunctionNames N>
Build Reader<N>::buildOf(Value value) {
  if (auto arg = dyn_cast<BlockArgument>(value); arg && arg.getOwner() == &fn.getBody().front())
    return build::Entry{arg.getArgNumber()};
  return match(
      sourceOf(value),
      [&](const idr::Same &same) -> Build { return build::Same{numbering.at(same.value)}; },
      // A read whose op does more than compute (a memo cell's state, which
      // forcing writes) is no part of anything, and holds what the cell
      // does.
      [&](const idr::Field &field) -> Build {
        if (Operation *op = value.getDefiningOp(); op && !effects::whole(op).onlyComputes())
          return opaqueOf(value, op);
        return build::Read{numbering.at(field.scrutinee), Field{field.tag, field.index},
                           value.getType()};
      },
      // A region's argument is given by what enters the region, which may
      // come after it in the walk, around a loop.
      [&](const idr::Made &) -> Build {
        if (auto result = dyn_cast<OpResult>(value))
          return ofResult(result);
        if (std::optional<Range> entering = enteringInto(value))
          return build::Forwarded{*entering};
        return build::Unseen{};
      });
}

// The function's return: the terminator of its body's one block, where it
// returns to the function's caller (upstream's ReturnLike), which stands
// under no case region and so has no frames. A body that ends the run
// instead (a crash) has none, and gives back anything.
template <solver::FunctionNames N>
void Reader<N>::readReturns() {
  Operation *end = fn.getBody().front().getTerminator();
  if (end->hasTrait<OpTrait::ReturnLike>())
    out.returns.push_back({push(end->getOperands()), Range{}});
}

} // namespace

template <solver::FunctionNames N>
Record readRecord(const N &names, const solver::Member &member) {
  FuncOp fn = member.fn;
  solver::Numbering<ValueTag> numbering(fn);
  Record out{member.id,
             numbering.size(),
             IndexVector<ValueId, Build>(numbering.size(), build::Unseen{}),
             IndexVector<ValueId, Refs>(numbering.size(), Refs::Words),
             {}, {}, {}, {}, {}, {}, {}, {}, {}};
  for (auto [at, type] : llvm::enumerate(fn.getArgumentTypes())) {
    out.argumentTypes.push_back(unrestricted(type));
    if (holdsReferences(unrestricted(type)))
      out.referenceArguments.push_back(static_cast<std::uint32_t>(at));
  }
  for (Type type : fn.getResultTypes())
    out.resultTypes.push_back(unrestricted(type));
  Reader<N> reader(names, fn, out, numbering);
  solver::inWalkOrder(fn, [&](Value value) {
    ValueId id = numbering.at(value);
    out.refs[id] = holdsReferences(unrestricted(value.getType())) ? Refs::References : Refs::Words;
    out.builds[id] = reader.buildOf(value);
  });
  reader.readReturns();
  return out;
}

template Record readRecord<solver::ProgramGraph>(const solver::ProgramGraph &,
                                                 const solver::Member &);
template Record readRecord<solver::Editor>(const solver::Editor &, const solver::Member &);

} // namespace idr::identities
