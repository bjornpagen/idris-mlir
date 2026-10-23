// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-frames' second step: calls become jumps. Every function of the
// component takes the stack awaiting its row and returns nothing; each
// call to frame pushes a frame holding what its rest reads and tail-calls
// its callee's run; a tail call of a function of the component passes the
// stack on; a tail that gives a value gives it, with the component's
// lifetimes, to its row's resume, which pops a frame and runs its rest, or,
// at the base, writes each value through its own destination into the
// slots of the call that started on the empty stack. Each function of the
// program keeps its name and signature as the wrapper that starts it: its
// slots (`dest.answer`), whose destinations the base frame holds, the run
// called inside them, and the results they give back, each at the whole
// type it was written at.
//
// No frame holds a lifetime: the lifetimes come back to the resume from
// the tail that gives the value, as current as that tail has them, and a
// scoped value a frame holds is read back in the resume's own, where its
// pusher's lived at the same place.

#include "idr/Transforms/Tail/Frames.h"

#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"
#include "idr/IR/Traits.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::tail::frames {

namespace {

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

} // namespace

unsigned rowIndex(Rows &rows, const Row &row) {
  for (auto [at, known] : llvm::enumerate(rows))
    if (known == row)
      return static_cast<unsigned>(at);
  rows.push_back(row);
  return static_cast<unsigned>(rows.size() - 1);
}

FuncOp Jumps::target(CallOp call) const {
  if (component.isMade(call))
    return call->getParentOfType<ProgramOp>().lookupSymbol<FuncOp>(call.getCalleeAttr());
  return runs[memberOf[graph.id(call.getCalleeAttr())]];
}

void Jumps::passStack(CallOp call, Value stack) {
  llvm::SmallVector<Value> args(call.getArgs());
  args.push_back(stack);
  rewriter.setInsertionPoint(call);
  auto made = CallOp::create(rewriter, call.getLoc(), target(call), call.getIndexArgsAttr(), args,
                             TailKind::tail);
  if (auto at = llvm::find(component.made, call); at != component.made.end())
    *at = made;
  for (Framed &f : component.framed)
    if (f.rest == call)
      f.rest = made;
  rewriter.eraseOp(call);
}

void Jumps::retype(FuncOp fn, unsigned row) {
  (void)fn.insertArgument(fn.getNumArguments(), family.stacks[row], DictionaryAttr(), fn.getLoc());
  (void)fn.eraseResults(llvm::BitVector(fn.getNumResults(), true));
}

void Jumps::onStack(FuncOp fn, unsigned row) {
  MLIRContext *ctx = fn.getContext();
  // The tails and the spine, read before any change to the body.
  llvm::SmallVector<Operation *> spine;
  llvm::SmallVector<Block *> blocks;
  spineOf(fn, spine, blocks);
  llvm::SmallVector<Block *> ends = tailEnds(fn);
  llvm::SmallVector<Operation *> sources =
      llvm::map_to_vector(ends, [](Block *end) { return tailSource(*end); });
  Value stack = fn.getArguments().back();
  llvm::SmallVector<BlockArgument> lifetimes = lifetimesOf(fn);

  // Each tail: a tail call within the component passes the stack on; a
  // value, a tail call out of it first returning here, goes to the resume
  // with the lifetimes it lives in among the component's.
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
    llvm::SmallVector<Value> given(terminator->getOperands());
    llvm::append_range(given, lifetimes);
    given.push_back(stack);
    rewriter.setInsertionPoint(terminator);
    CallOp::create(rewriter, terminator->getLoc(), resumes[row], IndexArgsAttr::get(ctx, {}, 0),
                   given, TailKind::tail);
    // A call whose value goes to the resume returns here first.
    if (call)
      call.setTailKind(decide(call));
  }

  // Nothing is given at any tail now: every block of the spine forwards
  // nothing, and every region op on it, innermost first, gives nothing,
  // stating lifetimes only for what its regions bind.
  for (Block *block : blocks) {
    Operation *terminator = block->getTerminator();
    rewriter.modifyOpInPlace(terminator, [&] { terminator->setOperands(ValueRange()); });
    eraseDeadRegrades(rewriter, block);
  }
  for (Operation *op : llvm::reverse(spine)) {
    (void)remakeGiving(rewriter, op, TypeRange(), ValueRange());
    rewriter.eraseOp(op);
  }

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
    // then the stack, which is below it; the component's lifetimes between
    // them come back to the resume instead.
    ValueRange restArgs = f.rest.getArgs();
    llvm::SmallVector<Value> fields(restArgs.slice(f.call->getNumResults(), kind.held.size()));
    fields.push_back(restArgs.back());
    rewriter.setInsertionPoint(f.rest);
    Value pushed = DataConOp::create(rewriter, f.call.getLoc(), frame, fields).getResult();
    llvm::SmallVector<Value> args(f.call.getArgs());
    args.push_back(pushed);
    CallOp::create(rewriter, f.call.getLoc(), target(f.call), f.call.getIndexArgsAttr(), args,
                   TailKind::tail);
    rewriter.eraseOp(f.rest);
    if (!f.call->use_empty())
      return f.call.emitOpError(
          "internal error: an invariant of idr-frames' first step is broken: everything after a "
          "call to frame moves into its rest, but this call's results are read elsewhere");
    rewriter.eraseOp(f.call);
  }
  return success();
}

// The resume's match has a case for the base frame, which writes each of
// the row's values through its own destination, the slots of the wrapper
// that started the run, and one for each kind of frame awaiting the row,
// which runs its rest on the values, what it holds, the component's
// lifetimes and the stack below. A frame's scoped values are read back in
// the resume's lifetimes, each at the place its pusher's lived in.
void fillResume(RewriterBase &rewriter, FuncOp resume, unsigned row, const Row &given,
                const FramesFamily &family, llvm::ArrayRef<FrameKind> kinds,
                llvm::ArrayRef<Rest> rests) {
  Block *entry = &resume.getBody().front();
  Location loc = resume.getLoc();
  ValueRange values = entry->getArguments().take_front(given.types.size());
  llvm::SmallVector<BlockArgument> lifetimes = lifetimesOf(resume);
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
    if (tag == family.base(row)) {
      auto parts = CountUnpackOp::create(rewriter, loc, block->getArgument(0)).getFields();
      for (auto [dest, value] : llvm::zip_equal(parts, values))
        DestWriteOp::create(rewriter, loc, dest, value);
    } else {
      unsigned index = static_cast<unsigned>(tag) - family.rows;
      llvm::SmallVector<Value> outers = llvm::map_to_vector(
          kinds[index].heldIn, [&](unsigned place) -> Value { return lifetimes[place]; });
      auto parts = CountUnpackOp::create(rewriter, loc, block->getArgument(0), outers).getFields();
      const Rest &rest = rests[index];
      llvm::SmallVector<Value> args(values);
      llvm::append_range(args, parts.drop_back());
      llvm::append_range(args, lifetimes);
      args.push_back(parts.back());
      CallOp::create(rewriter, loc, rest.fn, rest.terms, args, TailKind::tail);
    }
    YieldOp::create(rewriter, loc, ValueRange());
  }
  rewriter.setInsertionPointAfter(match);
  ReturnOp::create(rewriter, loc, ValueRange());
}

// The slots, one per result at the result's whole type, each scoped one in
// the lifetime parameter the signature names for it, in result order; the
// base frame holding their destinations; the run called on that stack
// inside them; and the results returned as the slots give them back.
void fillWrapper(RewriterBase &rewriter, FuncOp wrapper, FuncOp run, unsigned row,
                 const FramesFamily &family) {
  MLIRContext *ctx = wrapper.getContext();
  Location loc = wrapper.getLoc();
  Block *entry = new Block();
  wrapper.getBody().push_back(entry);
  for (Type input : wrapper.getArgumentTypes())
    entry->addArgument(input, loc);
  rewriter.setInsertionPointToEnd(entry);
  ArrayRef<Type> results = wrapper.getResultTypes();
  llvm::SmallVector<Value> outers;
  if (LivesInAttr lives = wrapper.getLivesInAttr())
    for (const LivesIn &scoped : lives.getResults())
      outers.push_back(entry->getArgument(scoped.lifetime));
  auto slots = DestAnswerOp::create(rewriter, loc, results, outers);
  llvm::SmallVector<Type> dests =
      llvm::map_to_vector(results, [&](Type result) -> Type { return DestType::get(ctx, result); });
  llvm::SmallVector<Location> locs(dests.size(), loc);
  Block *body = rewriter.createBlock(&slots.getBody(), slots.getBody().end(), dests, locs);
  DataType base = family.stacks[row].refined({family.base(row)});
  Value stack = DataConOp::create(rewriter, loc, base, body->getArguments()).getResult();
  llvm::SmallVector<Value> args(entry->getArguments());
  args.push_back(stack);
  auto binder = cast<ErasedBinderOpInterface>(wrapper.getOperation());
  auto own = static_cast<uint32_t>(binder.getBoundSorts(wrapper.getBody()).size());
  CallOp::create(rewriter, loc, run, families::levelArgs(ctx, 0, own), args, TailKind::nontail);
  YieldOp::create(rewriter, loc, ValueRange());
  rewriter.setInsertionPointAfter(slots);
  ReturnOp::create(rewriter, loc, slots.getResults());
}

// Its signature is its own, so it states where its scoped parameters live
// as it is made, before any call of it is built, and gives nothing back
// until the code it is given says so. It binds no index variable, and each
// of `like`'s extents is a term over `like`'s binders at a position of
// `like`'s signature, so none says anything of it: its axes are `?`, named
// by no term. A maker that gives it `like`'s binders and signature gives it
// `like`'s extents with them.
FuncOp beside(SymbolTable &symbols, FuncOp like, StringAttr name, FunctionType type,
              LivesInAttr lives) {
  auto fn = cast<FuncOp>(like->cloneWithoutRegions());
  fn.setSymNameAttr(name);
  fn.setFunctionTypeAttr(TypeAttr::get(type));
  fn.setArgAttrsAttr(nullptr);
  fn.setResAttrsAttr(nullptr);
  fn.setUntouchedAttr(nullptr);
  fn.setBoundedAttr(nullptr);
  fn.setBindersAttr(IndexBindersAttr());
  fn.setExtentsAttr(nullptr);
  fn.setLivesInAttr(lives);
  fn.setGivenBackAttr(nullptr);
  Block *entry = new Block();
  fn.getBody().push_back(entry);
  for (Type input : type.getInputs())
    entry->addArgument(input, like.getLoc());
  symbols.insert(fn, std::next(like->getIterator()));
  return fn;
}

} // namespace idr::tail::frames
