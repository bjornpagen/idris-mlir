// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Frames.cpp - idr-frames --------------------------------------------===//
//
// A recursion on a cycle of calls keeps its depth on a typed frame stack,
// never on the native stack, which then holds only the program's acyclic
// call depth: every call between two functions of one component of the
// call graph that is not in tail position pushes the rest of its code as a
// frame and becomes a tail call. Running an action is the first case (a
// bind whose left action is a bind runs it as a tail call, its nesting on
// the heap as the program built it), and a recursion over data the second
// (`size l + size r` pushes the addition's frame).
//
// The stack is a family the pass declares per component (FramesFamily),
// indexed by the row of results a frame awaits, so a frame awaiting
// another row is never on top where a value of one row is given, and the
// resume of a row has a case for exactly the frames that await it. A frame
// is linear and uncounted: pushed once (data.con), popped once by the
// resume's match (data.match, count.unpack), its held values keeping their
// grades across both, so no quantity is lost at the push or forged at the
// pop.
//
// The construction, per component, in two steps:
//
// 1. Continuations become functions. Each call to frame must end its block
//    in a tail of its function, so every region op around it whose results
//    something after it reads gives its continuation to a function of its
//    own (a lifted continuation), which each region of the op tail-calls;
//    a join point around it becomes functions too, each jump a tail call;
//    and the rest of the call's block becomes a function its call runs
//    into, tail-calling it with what the rest reads. A region of a
//    per-level lifetime (a stack or a chain) is split there: it ends by
//    packing its lifetime before the call, and the rest reopens it from
//    the package. Each step moves code, never copies it, and makes a
//    function of the component, read in turn, so it ends: the code it
//    moves only shrinks.
// 2. Calls become jumps. Every function of the component takes the stack
//    awaiting its row and returns nothing; each call to frame pushes a
//    frame holding what its rest reads and tail-calls its callee's run; a
//    tail call of a function of the component passes the stack on; a tail
//    that gives a value gives it to its row's resume, which pops a frame
//    and runs its rest, or, at the base, writes the value into the answer
//    of the call that started on the empty stack. Each function of the
//    program keeps its name and signature as the wrapper that starts it:
//    an answer cell on its own frame, the base frame holding its
//    destinations, a call of the run, the answer read back.
//
// Every call made is in tail position, so the native stack never grows on
// the cycle, which the native stack's bound checks on the final module. A
// promise: no step is an action a debug counter may skip, and a call this
// construction cannot reach is an internal error.
//
// It runs after counting and idr-trmc, so a reuse token live across a
// framed call is a value its frame holds, and a cell rebuilt in place
// across the cycle is still rebuilt in place; and before idr-tail-loops,
// which makes each run's self tail calls a loop.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Tail.h"
#include "idr/IR/Traits.h"
#include "idr/Support/Match.h"
#include "idr/Support/Remake.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Joins.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallVector.h"

namespace idr {
#define GEN_PASS_DEF_IDRFRAMES
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::tail {
namespace {

using solver::FunctionId;
using solver::ProgramGraph;
using solver::SccId;

//===----------------------------------------------------------------------===//
// Moving code into a function
//===----------------------------------------------------------------------===//

// `a`'s terms then `b`'s: a jump's terms for its join region's own binders
// after the levels of the scope the region's function is made in.
IndexArgsAttr concatArgs(MLIRContext *ctx, IndexArgsAttr a, IndexArgsAttr b) {
  llvm::SmallVector<families::TermNode> nodes(a.getTerms());
  llvm::append_range(nodes, b.getTerms());
  return IndexArgsAttr::get(ctx, nodes, a.getCount() + b.getCount());
}

// The index binders in scope at `region`: each op around it that binds
// index variables, outermost first. A function made of code there binds
// them all, in order, so every type of the code names its own levels.
llvm::SmallVector<families::Sort> scopeSorts(Region *region) {
  llvm::SmallVector<Region *> path;
  for (; region; region = region->getParentRegion())
    path.push_back(region);
  llvm::SmallVector<families::Sort> sorts;
  for (Region *at : llvm::reverse(path))
    if (auto binder = dyn_cast<ErasedBinderOpInterface>(at->getParentOp()))
      llvm::append_range(sorts, binder.getBoundSorts(*at));
  return sorts;
}

// Whether `value` is made by one of the ops of its block from `first` on,
// or bound inside one of them.
bool madeFrom(Value value, Operation *first) {
  Block *block = first->getBlock();
  Operation *anchor = value.getDefiningOp();
  if (!anchor) {
    Block *owner = cast<BlockArgument>(value).getOwner();
    if (owner == block)
      return false;
    anchor = owner->getParentOp();
  }
  Operation *top = block->findAncestorOpInBlock(*anchor);
  return top && !top->isBeforeInBlock(first);
}

// What the ops of `first`'s block from `first` on read that they do not
// make, in the order first read: what a function made of them takes.
llvm::SetVector<Value> liveIns(Operation *first) {
  llvm::SetVector<Value> in;
  for (Operation *op = first; op; op = op->getNextNode())
    op->walk([&](Operation *inner) {
      for (Value operand : inner->getOperands())
        if (!madeFrom(operand, first))
          in.insert(operand);
    });
  return in;
}

// The component's state while the pass rebuilds it: its functions, the
// program's first, each with the row it gives; the calls the pass made of
// functions it made; and each call to frame with the tail call of its
// rest that follows it.
struct Framed {
  CallOp call;
  CallOp rest;
};

class Component {
public:
  Component(RewriterBase &rewriter, SymbolTable &symbols, const ProgramGraph &graph, SccId scc)
      : rewriter(rewriter), symbols(symbols), graph(graph), scc(scc) {}

  // Whether `call` runs a function of the program's in this component:
  // the graph names every function the program had, and the pass's own
  // calls, which name the functions it made, are asked first.
  bool isMade(CallOp call) const { return llvm::is_contained(made, call); }
  bool isMember(CallOp call) const {
    return !isMade(call) && graph.sccOf(graph.id(call.getCalleeAttr())) == scc;
  }
  // A call to frame: of a function of the component, and no tail call.
  bool frames(CallOp call) const {
    return call.getTailKind() == TailKind::nontail && isMember(call);
  }

  LogicalResult restructure(FuncOp fn, unsigned row);

  // A function of the component, with its row.
  struct Function {
    FuncOp fn;
    unsigned row;
  };
  llvm::SmallVector<Function> functions;
  llvm::SmallVector<CallOp> made;
  llvm::SmallVector<Framed> framed;
  // How many of `functions`, the first, are the program's.
  unsigned members = 0;

private:
  FuncOp makeFunction(FuncOp owner, llvm::StringRef kind, FunctionType type,
                      llvm::ArrayRef<families::Sort> binders);
  CallOp outline(FuncOp owner, unsigned row, Operation *first, ValueRange params,
                 llvm::StringRef kind);
  void sinkInto(Operation *rejoin, CallOp call);
  void normalize(Block *root);
  LogicalResult dissolve(FuncOp owner, unsigned row, Operation *join);
  LogicalResult split(FuncOp owner, unsigned row, CallOp site, Operation *opener);

  RewriterBase &rewriter;
  SymbolTable &symbols;
  const ProgramGraph &graph;
  SccId scc;
};

// A function the pass makes beside `owner`: owner's facts (its row, what
// Idris proved of its loops), a signature of its own, the index binders of
// the scope its code comes from, and an entry block taking its parameters.
// Its row and per-parameter record are the writer's to make exact.
FuncOp Component::makeFunction(FuncOp owner, llvm::StringRef kind, FunctionType type,
                               llvm::ArrayRef<families::Sort> binders) {
  MLIRContext *ctx = owner.getContext();
  auto fn = cast<FuncOp>(owner->cloneWithoutRegions());
  fn.setSymNameAttr(StringAttr::get(ctx, owner.getSymName() + "." + kind));
  fn.setFunctionTypeAttr(TypeAttr::get(type));
  fn.setArgAttrsAttr(nullptr);
  fn.setResAttrsAttr(nullptr);
  fn.setUntouchedAttr(nullptr);
  fn.setBoundedAttr(nullptr);
  fn.setBindersAttr(binders.empty() ? IndexBindersAttr() : IndexBindersAttr::get(ctx, binders));
  Block *entry = new Block();
  fn.getBody().push_back(entry);
  for (Type input : type.getInputs())
    entry->addArgument(input, owner.getLoc());
  symbols.insert(fn, std::next(owner->getIterator()));
  return fn;
}

// The ops of `first`'s block from `first` on moved into a function of
// their own, which takes `params` (values `first`'s code receives) and
// then what the code reads, and gives what the block's terminator gives;
// in their place a tail call of it, whose results the terminator gives.
CallOp Component::outline(FuncOp owner, unsigned row, Operation *first, ValueRange params,
                          llvm::StringRef kind) {
  MLIRContext *ctx = owner.getContext();
  Block *block = first->getBlock();
  Operation *terminator = block->getTerminator();
  llvm::SetVector<Value> in = liveIns(first);
  llvm::SmallVector<Value> passed(params);
  for (Value value : in)
    if (!llvm::is_contained(params, value))
      passed.push_back(value);
  llvm::SmallVector<Type> inputs = llvm::map_to_vector(passed, [](Value v) { return v.getType(); });
  auto type = FunctionType::get(ctx, inputs, terminator->getOperandTypes());
  llvm::SmallVector<families::Sort> binders = scopeSorts(block->getParent());
  FuncOp fn = makeFunction(owner, kind, type, binders);
  Block *entry = &fn.getBody().front();

  // The code moves, so the ops the pass recorded stay the ops they are.
  entry->getOperations().splice(entry->end(), block->getOperations(), first->getIterator(),
                                terminator->getIterator());
  rewriter.setInsertionPointToEnd(entry);
  ReturnOp::create(rewriter, terminator->getLoc(), terminator->getOperands());
  for (auto [value, arg] : llvm::zip_equal(passed, entry->getArguments()))
    rewriter.replaceUsesWithIf(value, arg, [&](OpOperand &use) {
      return fn->isProperAncestor(use.getOwner());
    });

  rewriter.setInsertionPoint(terminator);
  auto call = CallOp::create(rewriter, terminator->getLoc(), fn,
                             families::levelArgs(ctx, 0, static_cast<uint32_t>(binders.size())),
                             fn.getResultTypes(), passed, TailKind::tail);
  rewriter.modifyOpInPlace(terminator, [&] { terminator->setOperands(call.getResults()); });
  made.push_back(call);
  functions.push_back({fn, row});
  return call;
}

// `call`, right after `rejoin` and taking its results, moved into each of
// its regions that rejoins it: each tail-calls the continuation with what
// it gives, and the op gives the continuation's results, so it is in tail
// position once its block gives them.
void Component::sinkInto(Operation *rejoin, CallOp call) {
  llvm::SmallVector<Operation *> ends;
  for (Region &region : rejoin->getRegions()) {
    if (region.empty())
      continue;
    Operation *end = region.front().getTerminator();
    if (isa<RegionBranchTerminatorOpInterface>(end) &&
        end->getNumOperands() == rejoin->getNumResults())
      ends.push_back(end);
  }
  for (Operation *end : ends) {
    rewriter.setInsertionPoint(end);
    IRMapping map;
    for (auto [result, given] : llvm::zip_equal(rejoin->getResults(), end->getOperands()))
      map.map(result, given);
    auto copy = cast<CallOp>(rewriter.clone(*call, map));
    rewriter.modifyOpInPlace(end, [&] { end->setOperands(copy.getResults()); });
    made.push_back(copy);
  }
  Operation *remade = remakeOp(rewriter, rejoin, rejoin->getOperands(), call.getResultTypes());
  rewriter.replaceAllUsesWith(call.getResults(), remade->getResults());
  llvm::erase(made, call);
  rewriter.eraseOp(call);
  rewriter.eraseOp(rejoin);
}

// The changes of grade after each region op of the tail spine from `root`
// moved into the op's regions, before each region's end: every region op
// a tail runs through then gives what its function gives, type for type,
// so a continuation made of the code after one gives it too.
void Component::normalize(Block *root) {
  llvm::SmallVector<Block *, 8> spine{root};
  while (!spine.empty()) {
    Block *block = spine.pop_back_val();
    Operation *source = tailSource(*block);
    if (!source || !source->hasTrait<OpTrait::PropagateControlFlowBreak>())
      continue;
    llvm::SmallVector<Operation *> ends;
    for (Region &region : source->getRegions()) {
      if (region.empty())
        continue;
      Operation *end = region.front().getTerminator();
      if (isa<RegionBranchTerminatorOpInterface>(end) &&
          end->getNumOperands() == source->getNumResults())
        ends.push_back(end);
    }
    llvm::SmallVector<Type> types(source->getResultTypes());
    llvm::SmallVector<Operation *> regrades;
    for (Operation *op = source->getNextNode(); !op->hasTrait<OpTrait::IsTerminator>();
         op = op->getNextNode())
      regrades.push_back(op);
    for (Operation *regrade : regrades) {
      unsigned at = cast<OpResult>(regrade->getOperand(0)).getResultNumber();
      for (Operation *end : ends) {
        rewriter.setInsertionPoint(end);
        Operation *copy = rewriter.clone(*regrade);
        copy->setOperand(0, end->getOperand(at));
        rewriter.modifyOpInPlace(end, [&] { end->setOperand(at, copy->getResult(0)); });
      }
      types[at] = regrade->getResult(0).getType();
      rewriter.replaceAllUsesWith(regrade->getResult(0), source->getResult(at));
      rewriter.eraseOp(regrade);
    }
    if (!regrades.empty()) {
      Operation *remade = remakeOp(rewriter, source, source->getOperands(), types);
      rewriter.replaceAllUsesWith(source->getResults(), remade->getResults());
      rewriter.eraseOp(source);
      source = remade;
    }
    for (Operation *end : ends)
      spine.push_back(end->getBlock());
  }
}

// A join point op around a call to frame, its continuation already lifted
// so it is in tail position: each join region becomes a function of its
// parameters and what it reads, each jump to it a tail call, and the body
// takes the op's place.
LogicalResult Component::dissolve(FuncOp owner, unsigned row, Operation *join) {
  MLIRContext *ctx = owner.getContext();
  auto points = cast<JoinPointsOpInterface>(join);
  for (Region &region : join->getRegions())
    normalize(&region.front());
  unsigned depth = static_cast<unsigned>(scopeSorts(join->getParentRegion()).size());

  // What each join region reads from above the op, closed over the jumps:
  // a region that jumps to another passes it what it reads, so reads it
  // too. A union over finitely many values that only grows, so it ends.
  llvm::SmallVector<JumpOp> jumps;
  join->walk([&](JumpOp jump) {
    if (points.getTarget(cast<BlockArgument>(jump.getTarget())))
      jumps.push_back(jump);
  });
  unsigned count = join->getNumRegions() - 1;
  llvm::SmallVector<llvm::SetVector<Value>> reads(count);
  for (unsigned i = 0; i < count; ++i) {
    Region &region = join->getRegion(i + 1);
    region.walk([&](Operation *op) {
      for (Value operand : op->getOperands())
        if (!region.isAncestor(operand.getParentRegion()) && !isa<TokenType>(operand.getType()))
          reads[i].insert(operand);
    });
  }
  for (bool grew = true; grew;) {
    grew = false;
    for (JumpOp jump : jumps) {
      // The region of the op the jump lies in; the body passes nothing,
      // its code staying where everything above the op is in scope.
      Region *home = jump->getParentRegion();
      while (home->getParentOp() != join)
        home = home->getParentOp()->getParentRegion();
      unsigned from = home->getRegionNumber();
      if (from == 0)
        continue;
      unsigned to = points.getTarget(cast<BlockArgument>(jump.getTarget()))->getRegionNumber() - 1;
      for (Value value : reads[to])
        grew |= reads[from - 1].insert(value);
    }
  }

  // The functions, one per join region, before any jump changes, so a
  // jump may name any of them.
  struct Lifted {
    Region *region;
    FuncOp fn;
    llvm::SmallVector<Value> reads;
  };
  llvm::SmallVector<Lifted> lifted;
  for (unsigned i = 0; i < count; ++i) {
    Region &region = join->getRegion(i + 1);
    llvm::SmallVector<Type> inputs(points.getParameters(region).getTypes());
    for (Value value : reads[i])
      inputs.push_back(value.getType());
    llvm::SmallVector<families::Sort> binders = scopeSorts(&region);
    FuncOp fn = makeFunction(owner, "join", FunctionType::get(ctx, inputs, join->getResultTypes()),
                             binders);
    lifted.push_back({&region, fn, llvm::to_vector(reads[i])});
    functions.push_back({fn, row});
  }

  // Each jump to one of them a tail call, its terms the region's binders
  // after the scope's own.
  for (JumpOp jump : jumps) {
    Region *target = points.getTarget(cast<BlockArgument>(jump.getTarget()));
    const Lifted &to = lifted[target->getRegionNumber() - 1];
    llvm::SmallVector<Value> args(jump.getArgs());
    llvm::append_range(args, to.reads);
    IndexArgsAttr terms = concatArgs(ctx, families::levelArgs(ctx, 0, depth), jump.getTermsAttr());
    rewriter.setInsertionPoint(jump);
    auto call = CallOp::create(rewriter, jump.getLoc(), to.fn, terms, join->getResultTypes(),
                               args, TailKind::tail);
    YieldOp::create(rewriter, jump.getLoc(), call.getResults());
    made.push_back(call);
    rewriter.eraseOp(jump);
  }

  // Each join region's code into its function; the body in the op's place.
  for (const Lifted &to : lifted) {
    Block &block = to.region->front();
    Block *entry = &to.fn.getBody().front();
    Operation *end = block.getTerminator();
    entry->getOperations().splice(entry->end(), block.getOperations(), block.begin(),
                                  end->getIterator());
    rewriter.setInsertionPointToEnd(entry);
    ReturnOp::create(rewriter, end->getLoc(), end->getOperands());
    rewriter.eraseOp(end);
    Block::BlockArgListType params = points.getParameters(*to.region);
    for (auto [param, arg] : llvm::zip(params, entry->getArguments()))
      rewriter.replaceAllUsesWith(param, arg);
    for (auto [value, arg] :
         llvm::zip_equal(to.reads, entry->getArguments().drop_front(params.size())))
      rewriter.replaceUsesWithIf(value, arg, [&](OpOperand &use) {
        return to.fn->isProperAncestor(use.getOwner());
      });
  }
  Block &body = join->getRegion(0).front();
  Operation *bodyEnd = body.getTerminator();
  llvm::SmallVector<Value> given(bodyEnd->getOperands());
  rewriter.eraseOp(bodyEnd);
  body.eraseArguments(0, body.getNumArguments());
  rewriter.inlineBlockBefore(&body, join);
  rewriter.replaceOp(join, given);
  return success();
}

// A call to frame directly in the region of a per-level lifetime (a stack
// or a chain): the region ends before the call by packing its lifetime
// and the values living in it, the call runs after it, and its rest
// reopens the lifetime from the package and runs the rest of the region,
// then what followed the opener.
LogicalResult Component::split(FuncOp owner, unsigned row, CallOp site, Operation *opener) {
  MLIRContext *ctx = owner.getContext();
  Block *inside = site->getBlock();
  Value lifetime = inside->getArgument(0);
  std::optional<Packed> packed = lifetimes::packedOf(lifetime);
  if (!packed)
    return site.emitOpError("internal error: idr-frames: a call on its function's cycle in "
                            "the region of a lifetime that cannot be per level");
  // What the rest of the region reads that the region made before the
  // call: what lives in the lifetime goes into the package, the rest out
  // of the region beside it; the call's operands go out too.
  Operation *afterSite = site->getNextNode();
  llvm::SetVector<Value> restReads = liveIns(afterSite);
  llvm::SmallVector<Value> scoped, plain, outside;
  for (Value value : restReads) {
    // The call's results are the rest's first parameters; the lifetime is
    // reopened fresh.
    if (value == lifetime || llvm::is_contained(site->getResults(), value))
      continue;
    bool fromRegion = value.getParentRegion() == inside->getParent();
    if (!fromRegion)
      outside.push_back(value);
    else if (lifetimes::statedLifetime(value) == lifetime)
      scoped.push_back(value);
    else
      plain.push_back(value);
  }
  for (Value arg : site.getArgs())
    if (arg.getParentRegion() == inside->getParent() &&
        lifetimes::statedLifetime(arg) == lifetime)
      return site.emitOpError("internal error: idr-frames: an operand of a call on its "
                              "function's cycle lives in the lifetime split around it");

  // The rest of the region and what followed the opener, into the rest's
  // function: an unpack reopening the lifetime, the region's code in it,
  // then the opener's continuation.
  Block *outer = opener->getBlock();
  Operation *outerEnd = outer->getTerminator();
  llvm::SmallVector<Type> held = llvm::map_to_vector(scoped, [](Value v) { return v.getType(); });
  auto package = LifetimePackageType::get(ctx, *packed, held);

  llvm::SmallVector<Value> regionArgs;
  for (Value arg : site.getArgs())
    if (arg.getParentRegion() == inside->getParent())
      regionArgs.push_back(arg);
  llvm::SmallVector<Value> carried(plain);
  for (Value arg : regionArgs)
    if (!llvm::is_contained(carried, arg))
      carried.push_back(arg);

  // The region now ends at the pack, giving the package and what the call
  // and the rest need of it.
  rewriter.setInsertionPoint(site);
  auto pack = LifetimePackOp::create(rewriter, site.getLoc(), package, lifetime, scoped);
  llvm::SmallVector<Value> yielded{pack.getResult()};
  llvm::append_range(yielded, carried);
  llvm::SmallVector<Operation *> rest;
  for (Operation *op = afterSite; op; op = op->getNextNode())
    rest.push_back(op);
  Operation *regionEnd = inside->getTerminator();
  llvm::SmallVector<Value> regionGives(regionEnd->getOperands());
  Location loc = site.getLoc();

  // The rest's function: (call results, package, carried, outside, what
  // the opener's continuation reads) -> what the outer block gives.
  llvm::SmallVector<Value> passedOuter;
  for (Value value : liveIns(opener->getNextNode()))
    if (!llvm::is_contained(opener->getResults(), value))
      passedOuter.push_back(value);
  // The lifetime the opener's results live in, which the unpack states
  // for its own.
  Value outerLifetime;
  for (Value result : opener->getResults())
    if (Value stated = lifetimes::statedLifetime(result); stated && !outerLifetime)
      outerLifetime = stated;
  if (outerLifetime && !llvm::is_contained(outside, outerLifetime) &&
      !llvm::is_contained(passedOuter, outerLifetime))
    outside.push_back(outerLifetime);
  llvm::SmallVector<Type> inputs(site.getResultTypes());
  inputs.push_back(package);
  for (Value value : carried)
    inputs.push_back(value.getType());
  for (Value value : outside)
    inputs.push_back(value.getType());
  for (Value value : passedOuter)
    inputs.push_back(value.getType());
  llvm::SmallVector<families::Sort> binders = scopeSorts(outer->getParent());
  FuncOp fn = makeFunction(owner, "resumed",
                           FunctionType::get(ctx, inputs, outerEnd->getOperandTypes()), binders);
  Block *entry = &fn.getBody().front();
  unsigned at = 0;
  auto argsOf = [&](size_t n) {
    auto range = entry->getArguments().slice(at, n);
    at += static_cast<unsigned>(n);
    return range;
  };
  auto results = argsOf(site->getNumResults());
  BlockArgument pkgArg = argsOf(1).front();
  auto carriedArgs = argsOf(carried.size());
  auto outsideArgs = argsOf(outside.size());
  auto outerArgs = argsOf(passedOuter.size());

  // The unpack, the region's rest inside it.
  rewriter.setInsertionPointToEnd(entry);
  auto unpack = LifetimeUnpackOp::create(rewriter, loc, opener->getResultTypes(), pkgArg,
                                         outerLifetime);
  Block *reopened = rewriter.createBlock(&unpack.getBody());
  BlockArgument fresh = reopened->addArgument(lifetime.getType(), loc);
  llvm::SmallVector<BlockArgument> restated;
  for (Value value : scoped)
    restated.push_back(reopened->addArgument(value.getType(), loc));
  for (Operation *op : rest)
    if (op != regionEnd)
      op->moveBefore(reopened, reopened->end());
  rewriter.setInsertionPointToEnd(reopened);
  YieldOp::create(rewriter, regionEnd->getLoc(), regionGives);
  rewriter.eraseOp(regionEnd);

  // The opener's continuation after the unpack.
  rewriter.setInsertionPointAfter(unpack);
  llvm::SmallVector<Operation *> following;
  for (Operation *op = opener->getNextNode(); op != outerEnd; op = op->getNextNode())
    following.push_back(op);
  for (Operation *op : following)
    op->moveBefore(entry, entry->end());
  rewriter.setInsertionPointToEnd(entry);
  ReturnOp::create(rewriter, outerEnd->getLoc(), outerEnd->getOperands());

  // Every value the moved code reads, read from the function's own.
  auto within = [&](OpOperand &use) { return fn->isProperAncestor(use.getOwner()); };
  for (auto [value, arg] : llvm::zip_equal(site.getResults(), results))
    rewriter.replaceUsesWithIf(value, arg, within);
  rewriter.replaceUsesWithIf(lifetime, fresh, within);
  for (auto [value, arg] : llvm::zip_equal(scoped, restated))
    rewriter.replaceUsesWithIf(value, arg, within);
  for (auto [value, arg] : llvm::zip_equal(carried, carriedArgs))
    rewriter.replaceUsesWithIf(value, arg, within);
  for (auto [value, arg] : llvm::zip_equal(outside, outsideArgs))
    rewriter.replaceUsesWithIf(value, arg, within);
  for (auto [value, arg] : llvm::zip_equal(passedOuter, outerArgs))
    rewriter.replaceUsesWithIf(value, arg, within);
  for (auto [value, arg] : llvm::zip_equal(opener->getResults(), unpack.getResults()))
    rewriter.replaceUsesWithIf(value, arg, within);
  if (outerLifetime)
    rewriter.replaceUsesWithIf(
        outerLifetime,
        outsideArgs[static_cast<unsigned>(llvm::find(outside, outerLifetime) - outside.begin())],
        within);

  // In the function the call stays in: the region ends at the pack, the
  // opener gives what it yields, then the call and the tail call of its
  // rest.
  rewriter.setInsertionPointToEnd(inside);
  YieldOp::create(rewriter, loc, yielded);
  llvm::SmallVector<Type> openerResults =
      llvm::map_to_vector(yielded, [](Value v) { return v.getType(); });
  Operation *remade = remakeOp(rewriter, opener, opener->getOperands(), openerResults);
  rewriter.moveOpAfter(site, remade);
  Value pkgOut = remade->getResult(0);
  for (auto [value, out] : llvm::zip_equal(carried, remade->getResults().drop_front()))
    rewriter.replaceUsesWithIf(value, out, [&](OpOperand &use) {
      return use.getOwner() == site.getOperation();
    });
  llvm::SmallVector<Value> passed(site.getResults());
  passed.push_back(pkgOut);
  llvm::append_range(passed, remade->getResults().drop_front());
  llvm::append_range(passed, outside);
  llvm::append_range(passed, passedOuter);
  rewriter.setInsertionPoint(outerEnd);
  auto call = CallOp::create(rewriter, loc, fn,
                             families::levelArgs(ctx, 0, static_cast<uint32_t>(binders.size())),
                             fn.getResultTypes(), passed, TailKind::tail);
  rewriter.modifyOpInPlace(outerEnd, [&] { outerEnd->setOperands(call.getResults()); });
  rewriter.eraseOp(opener);
  made.push_back(call);
  functions.push_back({fn, row});
  framed.push_back({site, call});
  return success();
}

LogicalResult Component::restructure(FuncOp fn, unsigned row) {
  for (;;) {
    // A join point op around a call to frame, outermost first.
    Operation *join = nullptr;
    fn.walk<WalkOrder::PreOrder>([&](Operation *op) {
      if (!op->hasTrait<OpTrait::TokenProducerTrait>())
        return WalkResult::advance();
      bool holds = op->walk([&](CallOp call) {
                         return frames(call) ? WalkResult::interrupt() : WalkResult::advance();
                       })
                       .wasInterrupted();
      if (!holds)
        return WalkResult::skip();
      join = op;
      return WalkResult::interrupt();
    });
    if (!join)
      break;
    normalize(&fn.getBody().front());
    if (!inTailPosition(join)) {
      CallOp continuation = outline(fn, row, join->getNextNode(), join->getResults(), "k");
      sinkInto(join, continuation);
      // The op was made again: it is found afresh.
      continue;
    }
    if (failed(dissolve(fn, row, join)))
      return failure();
  }
  normalize(&fn.getBody().front());

  // Each call to frame, in program order; one an earlier one's change moved
  // into a function of its own is that function's.
  llvm::SmallVector<CallOp> sites;
  fn.walk<WalkOrder::PreOrder>([&](CallOp call) {
    if (frames(call))
      sites.push_back(call);
  });
  for (CallOp site : sites) {
    if (site->getParentOfType<FuncOp>() != fn)
      continue;
    // The region ops around the call, outermost first: each a break may
    // cross whose results something after it reads gives its continuation
    // to a function, until the call's block ends a tail. Each such change
    // remakes the ops around, so they are read again after it.
    for (;;) {
      llvm::SmallVector<Operation *> around;
      for (Operation *op = site->getParentOp(); op != fn.getOperation(); op = op->getParentOp())
        around.push_back(op);
      Operation *lift = nullptr;
      for (Operation *op : llvm::reverse(around)) {
        if (op->hasTrait<OpTrait::PropagateControlFlowBreak>()) {
          if (inTailPosition(op))
            continue;
          lift = op;
          break;
        }
        // Only a lifetime's region directly around the call may split.
        if (op != site->getParentOp())
          return site.emitOpError("internal error: idr-frames: a call on its function's cycle "
                                  "inside an op whose region frames cannot split: ")
                 << op->getName();
      }
      if (!lift)
        break;
      CallOp continuation = outline(fn, row, lift->getNextNode(), lift->getResults(), "k");
      sinkInto(lift, continuation);
      normalize(&fn.getBody().front());
    }
    // The rest of the call's block runs after it: in a lifetime's region,
    // which ends before the call, reopened by the rest.
    Operation *parent = site->getParentOp();
    if (parent != fn.getOperation() && !parent->hasTrait<OpTrait::PropagateControlFlowBreak>()) {
      if (failed(split(fn, row, site, parent)))
        return failure();
      continue;
    }
    CallOp rest = outline(fn, row, site->getNextNode(), site->getResults(), "rest");
    framed.push_back({site, rest});
  }
  return success();
}

//===----------------------------------------------------------------------===//
// Calls into jumps
//===----------------------------------------------------------------------===//

// The rows of a component: its functions' distinct result types.
unsigned rowIndex(llvm::SmallVectorImpl<llvm::SmallVector<Type, 1>> &rows, TypeRange results) {
  for (auto [at, row] : llvm::enumerate(rows))
    if (llvm::equal(row, results))
      return static_cast<unsigned>(at);
  rows.emplace_back(results.begin(), results.end());
  return static_cast<unsigned>(rows.size() - 1);
}

// The region ops of `fn`'s tail spine, outermost first, and the blocks it
// runs through.
void spineOf(FuncOp fn, llvm::SmallVectorImpl<Operation *> &ops,
             llvm::SmallVectorImpl<Block *> &blocks) {
  llvm::SmallVector<Block *, 8> work{&fn.getBody().front()};
  while (!work.empty()) {
    Block *block = work.pop_back_val();
    blocks.push_back(block);
    Operation *source = tailSource(*block);
    if (!source || !source->hasTrait<OpTrait::PropagateControlFlowBreak>())
      continue;
    ops.push_back(source);
    for (Region &region : source->getRegions()) {
      if (region.empty())
        continue;
      Operation *end = region.front().getTerminator();
      if (isa<RegionBranchTerminatorOpInterface>(end) &&
          end->getNumOperands() == source->getNumResults())
        work.push_back(&region.front());
    }
  }
}

// The changes of grade at the end of `block` that nothing reads any more.
void eraseDeadRegrades(RewriterBase &rewriter, Block *block) {
  for (Operation &op : llvm::make_early_inc_range(llvm::reverse(*block)))
    if (op.hasTrait<ResultCarriesOperand>() && op.use_empty())
      rewriter.eraseOp(&op);
}

// Every function of the component on the stack: it takes the stack
// awaiting its row and returns nothing; each tail gives its value to its
// row's resume, or passes the stack on to the function it runs.
class Jumps {
public:
  Jumps(RewriterBase &rewriter, Component &component, const FramesFamily &family,
        llvm::ArrayRef<FuncOp> resumes, llvm::ArrayRef<FuncOp> runs,
        const IndexVector<FunctionId, unsigned> &memberOf, const ProgramGraph &graph)
      : rewriter(rewriter), component(component), family(family), resumes(resumes), runs(runs),
        memberOf(memberOf), graph(graph) {}

  void onStack(FuncOp fn, unsigned row);
  LogicalResult frameCalls(llvm::ArrayRef<FrameKind> kinds);

private:
  // The function a tail call of a function of the component goes to on
  // the stack: a function the pass made, as it is; the program's, its run.
  FuncOp target(CallOp call) const;
  // `call` made again with the stack after its arguments, giving nothing.
  void passStack(CallOp call, Value stack);

  RewriterBase &rewriter;
  Component &component;
  const FramesFamily &family;
  llvm::ArrayRef<FuncOp> resumes;
  llvm::ArrayRef<FuncOp> runs;
  const IndexVector<FunctionId, unsigned> &memberOf;
  const ProgramGraph &graph;
};

FuncOp Jumps::target(CallOp call) const {
  if (component.isMade(call))
    return call->getParentOfType<ProgramOp>().lookupSymbol<FuncOp>(call.getCalleeAttr());
  return runs[memberOf[graph.id(call.getCalleeAttr())]];
}

void Jumps::passStack(CallOp call, Value stack) {
  llvm::SmallVector<Value> args(call.getArgs());
  args.push_back(stack);
  rewriter.setInsertionPoint(call);
  auto made = CallOp::create(rewriter, call.getLoc(), target(call), call.getIndexArgsAttr(),
                             TypeRange(), args, TailKind::tail);
  if (auto *at = llvm::find(component.made, call); at != component.made.end())
    *at = made;
  for (Framed &f : component.framed)
    if (f.rest == call)
      f.rest = made;
  rewriter.eraseOp(call);
}

void Jumps::onStack(FuncOp fn, unsigned row) {
  MLIRContext *ctx = fn.getContext();
  // The tails and the spine, read before any change.
  llvm::SmallVector<Operation *> spine;
  llvm::SmallVector<Block *> blocks;
  spineOf(fn, spine, blocks);
  llvm::SmallVector<Block *> ends = tailEnds(fn);
  llvm::SmallVector<Operation *> sources =
      llvm::map_to_vector(ends, [](Block *end) { return tailSource(*end); });

  (void)fn.insertArgument(fn.getNumArguments(), family.stacks[row], DictionaryAttr(), fn.getLoc());
  Value stack = fn.getArguments().back();

  // Each tail: a tail call within the component passes the stack on; a
  // value, a tail call out of it first returning here, goes to the resume.
  llvm::SmallVector<CallOp> passing;
  for (auto [end, source] : llvm::zip_equal(ends, sources)) {
    Operation *terminator = end->getTerminator();
    if (!isa<ReturnOp>(terminator) && !isa<RegionBranchTerminatorOpInterface>(terminator))
      continue;
    auto call = dyn_cast_or_null<CallOp>(source);
    if (call && call.getTailKind() == TailKind::tail &&
        (component.isMade(call) || component.isMember(call))) {
      passing.push_back(call);
      continue;
    }
    if (call && call.getTailKind() == TailKind::tail)
      call.setTailKind(TailKind::nontail);
    llvm::SmallVector<Value> given(terminator->getOperands());
    given.push_back(stack);
    rewriter.setInsertionPoint(terminator);
    CallOp::create(rewriter, terminator->getLoc(), resumes[row], IndexArgsAttr::get(ctx, {}, 0),
                   TypeRange(), given, TailKind::tail);
  }

  // Nothing is given at any tail now: every block of the spine forwards
  // nothing, and every region op on it, innermost first, gives nothing.
  for (Block *block : blocks) {
    Operation *terminator = block->getTerminator();
    rewriter.modifyOpInPlace(terminator, [&] { terminator->setOperands(ValueRange()); });
    eraseDeadRegrades(rewriter, block);
  }
  for (Operation *op : llvm::reverse(spine)) {
    (void)remakeOp(rewriter, op, op->getOperands(), TypeRange());
    rewriter.eraseOp(op);
  }
  llvm::BitVector all(fn.getNumResults(), true);
  (void)fn.eraseResults(all);

  for (CallOp call : passing)
    passStack(call, stack);
}

// Each call to frame pushes its frame, the values its rest reads and the
// stack below, and tail-calls its callee's run on it.
LogicalResult Jumps::frameCalls(llvm::ArrayRef<FrameKind> kinds) {
  for (auto [index, f] : llvm::enumerate(component.framed)) {
    const FrameKind &kind = kinds[index];
    DataType frame =
        family.stacks[kind.awaits].refined({family.kind(static_cast<unsigned>(index))});
    // The rest's arguments after the call's results: what the frame holds,
    // then the stack, which is below it.
    llvm::SmallVector<Value> fields(f.rest.getArgs().drop_front(f.call->getNumResults()));
    rewriter.setInsertionPoint(f.rest);
    Value pushed = DataConOp::create(rewriter, f.call.getLoc(), frame, fields).getResult();
    llvm::SmallVector<Value> args(f.call.getArgs());
    args.push_back(pushed);
    CallOp::create(rewriter, f.call.getLoc(), target(f.call), f.call.getIndexArgsAttr(),
                   TypeRange(), args, TailKind::tail);
    rewriter.eraseOp(f.rest);
    if (!f.call->use_empty())
      return f.call.emitOpError("internal error: idr-frames: a framed call's results are read "
                                "elsewhere than by its rest");
    rewriter.eraseOp(f.call);
  }
  return success();
}

// What a kind's case runs: the continuation the frame's rest was, at the
// terms its call passed.
struct Rest {
  FuncOp fn;
  IndexArgsAttr terms;
};

// The resume of row `row`: the value and the stack awaiting it; its match
// has a case for the base frame, which writes the value into the answer,
// and one for each kind of frame awaiting the row, which runs its rest on
// the value, what it holds and the stack below.
void fillResume(RewriterBase &rewriter, FuncOp resume, unsigned row, const FramesFamily &family,
                llvm::ArrayRef<FrameKind> kinds, llvm::ArrayRef<Rest> rests) {
  Block *entry = &resume.getBody().front();
  Location loc = resume.getLoc();
  ValueRange values = entry->getArguments().drop_back();
  Value stack = entry->getArguments().back();
  llvm::SmallVector<Tag> tags{family.base(row)};
  for (auto [index, kind] : llvm::enumerate(kinds))
    if (kind.awaits == row)
      tags.push_back(family.kind(static_cast<unsigned>(index)));
  rewriter.setInsertionPointToEnd(entry);
  auto match = DataMatchOp::create(rewriter, loc, TypeRange(), stack, ValueRange(), tags);
  for (auto [at, tag] : llvm::enumerate(tags)) {
    Region &region = match.getCaseRegion(static_cast<unsigned>(at));
    DataType refined = family.stacks[row].refined({tag});
    Block *block = rewriter.createBlock(&region, region.end(), {refined}, {loc});
    auto parts = CountUnpackOp::create(rewriter, loc, block->getArgument(0)).getFields();
    if (tag == family.base(row)) {
      for (auto [dest, value] : llvm::zip_equal(parts, values))
        DestWriteOp::create(rewriter, loc, dest, value);
    } else {
      const Rest &rest = rests[static_cast<unsigned>(tag) - family.rows];
      llvm::SmallVector<Value> args(values);
      llvm::append_range(args, parts);
      CallOp::create(rewriter, loc, rest.fn, rest.terms, TypeRange(), args, TailKind::tail);
    }
    YieldOp::create(rewriter, loc, ValueRange());
  }
  rewriter.setInsertionPointAfter(match);
  ReturnOp::create(rewriter, loc, ValueRange());
}

// The function of the program, as it is called from outside the
// component: an answer cell on its own frame, the base frame holding the
// destinations of its fields, its run on that stack, the answer read back.
void fillWrapper(RewriterBase &rewriter, FuncOp wrapper, FuncOp run, unsigned row,
                 const FramesFamily &family) {
  MLIRContext *ctx = wrapper.getContext();
  Location loc = wrapper.getLoc();
  Block *entry = new Block();
  wrapper.getBody().push_back(entry);
  for (Type input : wrapper.getArgumentTypes())
    entry->addArgument(input, loc);
  rewriter.setInsertionPointToEnd(entry);
  unsigned count = static_cast<unsigned>(wrapper.getNumResults());
  Value box;
  llvm::SmallVector<Value> dests;
  if (count > 0) {
    Value activation = ActivationOp::create(rewriter, loc).getResult();
    Value cell =
        CellStackOp::create(rewriter, loc, CellType::get(ctx, family.answers[row]), activation)
            .getResult();
    llvm::SmallVector<int32_t> holes;
    for (unsigned field = 0; field < count; ++field)
      holes.push_back(static_cast<int32_t>(field));
    auto init = CellInitOp::create(rewriter, loc, cell, ValueRange(), holes);
    box = init.getResult();
    for (unsigned field = 0; field < count; ++field)
      dests.push_back(init.getDest(field));
  }
  DataType base = family.stacks[row].refined({family.base(row)});
  Value stack = DataConOp::create(rewriter, loc, base, dests).getResult();
  llvm::SmallVector<Value> args(entry->getArguments());
  args.push_back(stack);
  auto binder = cast<ErasedBinderOpInterface>(wrapper.getOperation());
  auto own = static_cast<uint32_t>(binder.getBoundSorts(wrapper.getBody()).size());
  CallOp::create(rewriter, loc, run, families::levelArgs(ctx, 0, own), TypeRange(), args,
                 TailKind::nontail);
  llvm::SmallVector<Value> answer;
  for (unsigned field = 0; field < count; ++field)
    answer.push_back(DataFieldOp::create(rewriter, loc, box, field).getResult());
  ReturnOp::create(rewriter, loc, answer);
}

// A function beside `like` with its facts, named `name`, of type `type`,
// binding no index variable; an empty entry block taking its parameters.
FuncOp beside(SymbolTable &symbols, FuncOp like, StringAttr name, FunctionType type) {
  auto fn = cast<FuncOp>(like->cloneWithoutRegions());
  fn.setSymNameAttr(name);
  fn.setFunctionTypeAttr(TypeAttr::get(type));
  fn.setArgAttrsAttr(nullptr);
  fn.setResAttrsAttr(nullptr);
  fn.setUntouchedAttr(nullptr);
  fn.setBoundedAttr(nullptr);
  fn.setBindersAttr(IndexBindersAttr());
  Block *entry = new Block();
  fn.getBody().push_back(entry);
  for (Type input : type.getInputs())
    entry->addArgument(input, like.getLoc());
  symbols.insert(fn, std::next(like->getIterator()));
  return fn;
}

struct Frames : impl::IdrFramesBase<Frames> {
  void runOnProgram(ProgramOp program) {
    MLIRContext *ctx = program.getContext();
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    ProgramGraph &graph = getAnalysis<ProgramGraph>();
    IRRewriter rewriter(ctx);

    // The components with a call to frame, read before any change.
    llvm::SmallVector<SccId> framing;
    for (SccId scc : graph.sccCount().ids()) {
      bool any = false;
      for (FunctionId f : graph.members(scc))
        any = any || llvm::any_of(graph.callees(f), [&](const solver::Call &call) {
                return call.kind == TailKind::nontail && graph.sccOf(call.callee) == scc;
              });
      if (any)
        framing.push_back(scc);
    }
    if (framing.empty())
      return markAllAnalysesPreserved();

    // The functions the pass makes and those whose calls change, for the
    // program graph's editor at the end.
    llvm::SmallVector<FuncOp> made, touched;
    IndexVector<FunctionId, unsigned> memberOf = graph.table<unsigned>(0);
    for (SccId scc : framing) {
      Component component(rewriter, symbols, graph, scc);
      llvm::SmallVector<llvm::SmallVector<Type, 1>> rows;
      for (FunctionId f : graph.members(scc)) {
        FuncOp fn = graph.op(f);
        memberOf[f] = static_cast<unsigned>(component.functions.size());
        component.functions.push_back({fn, rowIndex(rows, fn.getResultTypes())});
      }
      component.members = static_cast<unsigned>(component.functions.size());
      numFunctions += component.members;

      // 1. Continuations become functions, each read in turn.
      for (size_t at = 0; at < component.functions.size(); ++at)
        if (failed(component.restructure(component.functions[at].fn, component.functions[at].row)))
          return signalPassFailure();
      for (CallOp call : component.made)
        call.setTailKind(decide(call));

      // The kinds of frame, and the family.
      llvm::SmallVector<FrameKind> kinds;
      llvm::SmallVector<Rest> rests;
      for (const Framed &f : component.framed) {
        auto owner = f.call->getParentOfType<FuncOp>();
        unsigned continues = 0;
        for (const Component::Function &g : component.functions)
          if (g.fn == owner)
            continues = g.row;
        FuncOp callee = symbols.lookup<FuncOp>(f.call.getCalleeAttr().getAttr());
        FrameKind kind{rowIndex(rows, callee.getResultTypes()), continues, {}};
        for (Value held : f.rest.getArgs().drop_front(f.call->getNumResults()))
          kind.held.push_back(held.getType());
        kinds.push_back(std::move(kind));
        rests.push_back({symbols.lookup<FuncOp>(f.rest.getCalleeAttr().getAttr()),
                         f.rest.getIndexArgsAttr()});
      }
      numFrames += kinds.size();
      FuncOp first = component.functions.front().fn;
      FramesFamily family = declareFrames(
          ctx, StringAttr::get(ctx, first.getSymName() + ".frames"), first.getLoc(), rows, kinds);

      // 2. Calls become jumps. Each function of the program's body moves
      // into its run, and the function, keeping its name, its signature and
      // its place in the program graph, becomes the wrapper that starts it.
      llvm::SmallVector<FuncOp> wrappers, runs;
      for (unsigned m = 0; m < component.members; ++m) {
        FuncOp wrapper = component.functions[m].fn;
        FuncOp run = beside(symbols, wrapper, StringAttr::get(ctx, wrapper.getSymName() + ".run"),
                            wrapper.getFunctionType());
        run.setBindersAttr(wrapper.getBindersAttr());
        run.setArgAttrsAttr(wrapper.getArgAttrsAttr());
        run.setResAttrsAttr(wrapper.getResAttrsAttr());
        run.getBody().takeBody(wrapper.getBody());
        component.functions[m].fn = run;
        wrappers.push_back(wrapper);
      }
      for (const Component::Function &f : component.functions)
        runs.push_back(f.fn);
      llvm::SmallVector<FuncOp> resumes;
      for (unsigned row = 0; row < family.rows; ++row) {
        llvm::SmallVector<Type> inputs(rows[row]);
        inputs.push_back(family.stacks[row]);
        StringAttr name = StringAttr::get(ctx, first.getSymName() + ".resume");
        resumes.push_back(beside(symbols, first, name, FunctionType::get(ctx, inputs, {})));
      }

      Jumps jumps(rewriter, component, family, resumes, runs, memberOf, graph);
      for (const Component::Function &f : component.functions)
        jumps.onStack(f.fn, f.row);
      if (failed(jumps.frameCalls(kinds)))
        return signalPassFailure();
      for (unsigned row = 0; row < family.rows; ++row)
        fillResume(rewriter, resumes[row], row, family, kinds, rests);
      for (unsigned m = 0; m < component.members; ++m)
        fillWrapper(rewriter, wrappers[m], runs[m], component.functions[m].row, family);

      llvm::append_range(made, runs);
      llvm::append_range(made, resumes);
      llvm::append_range(touched, runs);
      llvm::append_range(touched, resumes);
      llvm::append_range(touched, wrappers);
    }

    // The program graph learns the functions made and the calls changed;
    // then every row is made equal to its derivation again.
    {
      solver::Editor editor = graph.thaw();
      for (FuncOp fn : made)
        (void)editor.insert(fn);
      for (FuncOp fn : touched)
        editor.setCallees(editor.id(FlatSymbolRefAttr::get(fn.getSymNameAttr())),
                          callRow(fn, editor));
      std::move(editor).freeze();
    }
    rows::write(program, graph);
    markAnalysesPreserved<SymbolTable, ProgramGraph>();
  }
};

} // namespace
} // namespace idr::tail
