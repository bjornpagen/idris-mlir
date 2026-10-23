// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The function's scope walk: one pre-order walk that keeps, on a stack, the
// depth of the scope and the equations every enclosing region assumes, so
// that each type, each region's entry, each cast and each jump is checked
// where it stands, and no op walks to its ancestors. The refinement at a
// point is the most general unifier of every equation on the stack, one
// space of levels for the whole scope: a case's constructor's binders are
// levels after its enclosing scope's.

#include "idr/IR/Families/Scope.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Families/Unify.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Footprint.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/DenseMap.h"

using namespace mlir;

// ErasedBinderOpInterface's default: a region of an op that binds index
// variables but assumes nothing assumes nothing.
std::optional<idr::families::RegionRefinement> idr::noRefinement(Operation *, Region &) {
  return std::nullopt;
}

namespace idr::families {

RegionRefinement caseRefinement(DataType scrutinee, Tag tag) {
  return {scrutinee.getIndices(), scrutinee.ctor(tag).equation,
          scrutinee.getGroup().indices(scrutinee.getMember()).size(), Scoped::RegionBinders,
          scrutinee.getGroup()};
}

namespace {

// One equation of the scope, in its one space of levels.
struct Equation {
  SmallVector<TermNode> lhs;
  SmallVector<TermNode> rhs;
  size_t count;
};

// A region the walk is inside: the scope's depth in it, how many of the
// walk's equations hold in it (the regions' around it, then its own), the
// refinement they make, and whether they clash.
struct Frame {
  Operation *owner;
  uint32_t depthAtOwner;
  uint32_t depth;
  size_t equations;
  LevelMap refinement;
  Unified unified = Unified::Consistent;
};

// `terms` of the enclosing scope or of a region's own binders, moved into
// the scope's one space: binders' levels after the enclosing depth, a null
// group written as the group it names.
SmallVector<TermNode> intoScope(ArrayRef<TermNode> terms, size_t count, uint32_t shift,
                                FamilyAttr group) {
  LevelMap map;
  map.shiftFrom(0, shift);
  SmallVector<TermNode> out;
  TermWriter write(out);
  for (Term term : termsOf(terms, count))
    map.write(write, term);
  for (TermNode &node : out)
    if (node.kind == TermKind::Constructor && !node.payload)
      node.payload = group;
  return out;
}

// The refinement the equations make at depth `depth`: each level they bind
// replaced by its term, resolved through the others.
std::pair<LevelMap, Unified> solve(ArrayRef<Equation> equations, uint32_t depth) {
  Subst subst(depth, 0, Freedom::Unknown, Freedom::Unknown, Opacity::MeetsAnything, Attribute());
  for (const Equation &eq : equations)
    for (auto [lhs, rhs] : llvm::zip_equal(termsOf(eq.lhs, eq.count), termsOf(eq.rhs, eq.count)))
      if (unify(subst, lhs, Side::Application, rhs, Side::Application) == Unified::Clash)
        return {LevelMap(), Unified::Clash};
  LevelMap map;
  TermNode level{TermKind::Level, 0, 0, 0, Attribute()};
  for (uint32_t at = 0; at < depth; ++at) {
    if (!subst.lookup(Side::Application, at))
      continue;
    level.value = at;
    SmallVector<TermNode> written;
    TermWriter write(written);
    subst.write(write, Term(ArrayRef<TermNode>(level)), Side::Application, 0);
    map.replace(at, Term(written));
  }
  return {map, Unified::Consistent};
}

} // namespace

// The regions the walk is inside, and the equations that hold in them,
// outermost first, each held once however deep the regions nest: both
// sized by the function's nesting, in the footprint's storage.
struct Refinements::State {
  footprint::Vector<Frame> stack;
  footprint::Vector<Equation> equations;
};

Refinements::Refinements(Operation *function) : state(new State) {
  state->stack.push_back(Frame{function, 0, 0, 0, LevelMap(), Unified::Consistent});
}

Refinements::~Refinements() = default;

void Refinements::enter(Operation *op, Region &region) {
  auto &stack = state->stack;
  auto &equations = state->equations;
  Frame next{op, stack.back().depth, stack.back().depth, equations.size(), LevelMap(),
             Unified::Consistent};
  if (auto binders = dyn_cast<ErasedBinderOpInterface>(op)) {
    next.depth += static_cast<uint32_t>(binders.getBoundSorts(region).size());
    if (std::optional<RegionRefinement> refinement = binders.getRefinement(region)) {
      uint32_t shift = refinement->scope == Scoped::RegionBinders ? next.depthAtOwner : 0;
      equations.push_back(
          {intoScope(refinement->outer, refinement->count, 0, refinement->group),
           intoScope(refinement->inner, refinement->count, shift, refinement->group),
           refinement->count});
      next.equations = equations.size();
    }
  }
  std::tie(next.refinement, next.unified) =
      solve(ArrayRef<Equation>(equations.data(), next.equations), next.depth);
  stack.push_back(std::move(next));
}

void Refinements::leave() {
  auto &stack = state->stack;
  stack.pop_back();
  state->equations.erase(
      state->equations.begin() + static_cast<std::ptrdiff_t>(stack.back().equations),
      state->equations.end());
}

uint32_t Refinements::depthAtOwner() const { return state->stack.back().depthAtOwner; }
uint32_t Refinements::depth() const { return state->stack.back().depth; }
Unified Refinements::unified() const { return state->stack.back().unified; }
const LevelMap &Refinements::refinement() const { return state->stack.back().refinement; }

std::optional<uint32_t> Refinements::depthAtOwner(Operation *owner) const {
  const auto &stack = state->stack;
  auto at = llvm::find_if(stack, [&](const Frame &f) { return f.owner == owner; });
  if (at == stack.end())
    return std::nullopt;
  return at->depthAtOwner;
}

namespace {

// Whether a region is dead: its one block ends the run with nothing in it.
bool unreachableBody(Region &region) {
  return region.hasOneBlock() && region.front().getOperations().size() == 1 &&
         isa<ub::UnreachableOp>(region.front().front());
}

class Walk {
public:
  explicit Walk(Operation *function) : scopes(function) {}
  LogicalResult enter(Operation *op, Region &region);
  void leave() { scopes.leave(); }
  LogicalResult checkOp(Operation *op);
  // `a` and `b` equal under the refinement here, `a` perhaps a data type
  // refined further.
  bool sameHere(Type a, Type b, Narrowing narrowing);
  // The levels bound outside the regions of `owner`, if it encloses the op
  // the walk is at: its frame is on the stack.
  std::optional<uint32_t> depthAtOwner(Operation *owner) const {
    return scopes.depthAtOwner(owner);
  }

private:
  // One more than the largest level `type` names, and whether it names a
  // member of a group by position, which only a declaration may.
  struct Named {
    uint32_t levels;
    enum class Member : uint8_t { None, ByPosition } member;
  };
  Named levelsOf(Type type);
  LogicalResult checkValue(Operation *op, Value value);
  // The binders `input`'s type gains over `operand`'s as it enters
  // `region`: none, or the region's own levels.
  LogicalResult ownBinders(Operation *op, Region &region, Type operand, Type input);

  Refinements scopes;
  // The levels each type names, for this walk: types are uniqued, so each
  // is read once however many values have it.
  llvm::DenseMap<Type, Named> seen;
};

Walk::Named Walk::levelsOf(Type type) {
  if (auto it = seen.find(type); it != seen.end())
    return it->second;
  Named named{0, Named::Member::None};
  AttrTypeWalker walker;
  walker.addWalk([](FamilyAttr) { return WalkResult::skip(); });
  walker.addWalk([&](IndexedTypeInterface indexed) {
    named.levels = std::max(named.levels, indexed.getFreeLevels());
    if (indexed.getPositionalMember())
      named.member = Named::Member::ByPosition;
    return indexed.scopeHoldsParts() ? WalkResult::advance() : WalkResult::skip();
  });
  walker.walk<WalkOrder::PreOrder>(type);
  return seen[type] = named;
}

LogicalResult Walk::checkValue(Operation *op, Value value) {
  auto [levels, member] = levelsOf(value.getType());
  if (member == Named::Member::ByPosition)
    return op->emitOpError("has a value of type ")
           << value.getType() << ", which names a member of a family by position outside its "
           << "declaration";
  if (levels > scopes.depth())
    return op->emitOpError("has a value of type ")
           << value.getType() << ", which names level " << levels - 1 << " where "
           << scopes.depth() << " index variables are in scope";
  return success();
}

// A value refined to one constructor as it enters a region (a case's
// scrutinee) gains that constructor's binders where its indices leave one
// open: they are the index variables the region binds, its own levels in
// order, so a field read from it is typed over them. Any other term would
// say the binder is something the constructor never fixed. A value carried
// in with its binders keeps them, as the refinement already checked.
LogicalResult Walk::ownBinders(Operation *op, Region &region, Type operand, Type input) {
  DataType entered = dataTypeOf(input);
  if (!entered || entered.getBinders().empty())
    return success();
  DataType from = dataTypeOf(operand);
  if (from && from.getBinders() == entered.getBinders())
    return success();
  SmallVector<TermNode> own;
  TermWriter write(own);
  for (uint32_t level = scopes.depthAtOwner(); level < scopes.depth(); ++level)
    write.level(level);
  if (entered.getBinders() == ArrayRef<TermNode>(own))
    return success();
  return op->emitOpError("region #")
         << region.getRegionNumber() << " binds " << input << ", whose constructor's binders "
         << "are not the " << scopes.depth() - scopes.depthAtOwner() << " index variables it binds";
}

// The refinement maps index terms, and a layout mark is none: a cast whose
// result is refined further meets its operand through `refines`, which
// reads the indices alone, so an open value and one laid out as its indices
// say are one up to the cast, and an operand at an index the language
// cannot write is admitted to whatever term its result names, a level or,
// in a copy that closed it, a closed one; a value that passes on with no
// op between (a jump's argument, a value forwarded into a region) is
// compared whole, its mark included, since there nothing converts it.
bool Walk::sameHere(Type a, Type b, Narrowing narrowing) {
  const LevelMap &here = scopes.refinement();
  Type ma = mapLevels(a, here);
  Type mb = mapLevels(b, here);
  return ma == mb || (narrowing == Narrowing::Allowed && refines(ma, mb));
}

LogicalResult Walk::enter(Operation *op, Region &region) {
  scopes.enter(op, region);
  // A case whose equation clashes with its scrutinee's index does not
  // exist: only a substitution's dead region may stand, unreachable. The
  // region is on the stack either way, so the walk's leave pops it.
  if (scopes.unified() == Unified::Clash && !unreachableBody(region))
    return op->emitOpError("region #")
           << region.getRegionNumber() << " assumes an equation its scope makes false, "
           << "a case whose constructor its scrutinee's index excludes";
  for (Block &block : region)
    for (BlockArgument arg : block.getArguments())
      if (failed(checkValue(op, arg)))
        return failure();
  // Each value entering the region is the operand it comes from, at the
  // region's refinement; the first a case binds, its scrutinee, refined.
  auto branch = dyn_cast<RegionBranchOpInterface>(op);
  if (!branch || region.empty() || scopes.unified() == Unified::Clash)
    return success();
  OperandRange operands = branch.getEntrySuccessorOperands(RegionSuccessor(&region));
  ValueRange inputs = branch.getSuccessorInputs(RegionSuccessor(&region));
  for (auto [index, pair] : llvm::enumerate(llvm::zip(operands, inputs))) {
    auto [operand, input] = pair;
    if (!sameHere(input.getType(), operand.getType(),
                  index == 0 ? Narrowing::Allowed : Narrowing::Exact))
      return op->emitOpError("region #")
             << region.getRegionNumber() << " binds " << input.getType() << " for "
             << operand.getType() << ", which its refinement does not make it";
    if (index == 0 && failed(ownBinders(op, region, operand.getType(), input.getType())))
      return failure();
  }
  return success();
}

LogicalResult Walk::checkOp(Operation *op) {
  for (Value result : op->getResults())
    if (failed(checkValue(op, result)))
      return failure();
  return success();
}

} // namespace

struct ScopeWalk::State {
  Walk walk;
};

ScopeWalk::ScopeWalk(Operation *function) : state(new State{Walk(function)}) {}
ScopeWalk::~ScopeWalk() = default;
LogicalResult ScopeWalk::enter(Operation *op, Region &region) { return state->walk.enter(op, region); }
void ScopeWalk::leave() { state->walk.leave(); }
LogicalResult ScopeWalk::check(Operation *op) {
  if (failed(state->walk.checkOp(op)))
    return failure();
  if (auto rule = dyn_cast<ScopeRuleOpInterface>(op)) {
    ScopeQuery scope(*this);
    return rule.verifyScopeRule(scope);
  }
  return success();
}

bool ScopeQuery::sameHere(Type a, Type b, Narrowing narrowing) const {
  return walk.state->walk.sameHere(a, b, narrowing);
}

std::optional<uint32_t> ScopeQuery::depthAtOwner(Operation *owner) const {
  return walk.state->walk.depthAtOwner(owner);
}

} // namespace idr::families

namespace idr {

using families::Narrowing;
using families::ScopeQuery;
using families::TermNode;

// A cast's two types are one under the refinements around it, its result
// perhaps refined further.
// The grades on either side are the reindex's own verifier's (a reindex
// that builds gives a fresh one), so the scope compares the carriers.
LogicalResult DataReindexOp::verifyScopeRule(ScopeQuery &scope) {
  if (!scope.sameHere(unrestricted(getValue().getType()), unrestricted(getType()),
                      Narrowing::Allowed))
    return emitOpError("casts ") << getValue().getType() << " to " << getType()
                                 << ", which the refinements around it do not make equal";
  return success();
}

// A jump's arguments are its target's parameters with the target's index
// variables replaced by the jump's terms: the target's op encloses the
// jump, so its depth is on the walk's stack. Each crosses at its
// parameter's hold where the program's stage lets a hold that fits stand
// (crossedAs).
LogicalResult JumpOp::verifyScopeRule(ScopeQuery &scope) {
  auto token = cast<BlockArgument>(getTarget());
  Operation *owner = token.getOwner()->getParentOp();
  auto points = cast<JoinPointsOpInterface>(owner);
  Region *target = points.getTarget(token);
  std::optional<uint32_t> depth = scope.depthAtOwner(owner);
  if (!depth)
    return emitOpError("jumps to a join point that does not enclose it");
  IndexArgsAttr terms = getTermsAttr();
  families::LevelMap map;
  for (auto [level, term] : llvm::enumerate(families::termsOf(terms.getTerms(), terms.getCount())))
    map.replace(*depth + static_cast<uint32_t>(level), term);
  for (auto [arg, parameter] : llvm::zip(getArgs(), points.getParameters(*target))) {
    Type asked = families::mapLevels(parameter.getType(), map);
    if (!scope.sameHere(crossedAs(getOperation(), arg.getType(), asked), asked, Narrowing::Exact))
      return emitOpError("passes ") << arg.getType() << " to a parameter of type " << parameter.getType()
                                    << " at its terms";
  }
  return success();
}

// The index terms each indexed type names directly: a data type its
// indices, then the binders its refinement keeps; a natural its index; a
// member named by position its indices.
llvm::SmallVector<ArrayRef<TermNode>, 2> DataType::getIndexTermRuns() const {
  return {getIndices(), getBinders()};
}

llvm::SmallVector<ArrayRef<TermNode>, 2> NatType::getIndexTermRuns() const { return {getIndex()}; }

llvm::SmallVector<ArrayRef<TermNode>, 2> SelfType::getIndexTermRuns() const { return {getIndices()}; }

// A data type's free levels were counted when it was made.
std::uint32_t DataType::getFreeLevels() const { return freeLevels(); }

// A data type's family fact holds what its parts name, so a scope's walk
// need not enter it.
bool DataType::scopeHoldsParts() const { return false; }

// The member of the group being declared, named by its position.
std::optional<std::uint32_t> SelfType::getPositionalMember() const { return getMember(); }

} // namespace idr
