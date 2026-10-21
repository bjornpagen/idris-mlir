// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Where the ops of one function sit, and where its values are used and
// die (Ownership.h): one numbering of the function's ops, each with the
// span of what it holds, so that order is a comparison and ancestry is
// containment. The numbering leaves a gap after every op; an op a
// rewrite inserted is numbered in the gap it landed in when first
// asked, and only when no gap is left is the function numbered again.
#include "idr/Analysis/Ownership.h"

#include "idr/IR/Ownership.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/iterator.h"

#include <algorithm>

using namespace mlir;

namespace idr::ownership {

namespace {

// The room the numbering leaves after one op (its span's start, and its
// end) for what a rewrite inserts there before the function is numbered
// again: each insertion in one gap halves what is left of it.
constexpr uint64_t kGap = 1 << 16;

} // namespace

Positions::Positions(FuncOp fn) : fn(fn) { renumber(); }

void Positions::renumber() {
  spans.clear();
  blockSpans.clear();
  opsInBlock.clear();
  spans[fn.getOperation()] = {0, UINT64_MAX};
  uint64_t next = kGap;
  number(fn.getBody(), next);
}

void Positions::number(Region &region, uint64_t &next) {
  for (Block &block : region) {
    // Collected beside the map, and moved in once the block is done:
    // numbering what an op holds inserts the blocks in there into the
    // same map, which a reference into it would not survive.
    SmallVector<Operation *> held;
    uint64_t blockPos = next;
    next += kGap;
    for (Operation &op : block) {
      held.push_back(&op);
      uint64_t pos = next;
      next += kGap;
      for (Region &inner : op.getRegions())
        number(inner, next);
      spans[&op] = {pos, next};
      next += kGap;
    }
    blockSpans[&block] = {blockPos, next};
    opsInBlock[&block] = std::move(held);
  }
}

Positions::Span Positions::span(Operation *op) {
  auto it = spans.find(op);
  if (it != spans.end())
    return it->second;
  // The highest op over `op` with no span: what a rewrite inserted, whole.
  Operation *top = op;
  for (Operation *parent = top->getParentOp(); parent && !spans.contains(parent);
       parent = top->getParentOp())
    top = parent;
  assign(top);
  return spans.at(op);
}

// Numbers `top` and what it holds in the gap it landed in: after the
// numbered op before it in its block (or the op that holds the block),
// before the numbered one after it (or that op's end). When the gap
// cannot hold them, the function is numbered again.
void Positions::assign(Operation *top) {
  Block *block = top->getBlock();
  // The gap is the block's own extent, narrowed by the numbered ops
  // around `top`: not the holding op's span, which every block it
  // holds would then number its first written op from, into each
  // other. A block the numbering does not know (one a rewrite made
  // in a region already numbered) is beyond a gap: number again.
  if (block && !blockSpans.contains(block)) {
    renumber();
    return;
  }
  Operation *parent = block ? block->getParentOp() : nullptr;
  Span outer = block ? blockSpans.at(block)
                     : (parent ? spans.at(parent) : Span{0, UINT64_MAX});
  uint64_t lo = outer.pos, hi = outer.end;
  if (block) {
    for (auto it = top->getIterator(); it != block->begin();) {
      --it;
      if (auto found = spans.find(&*it); found != spans.end()) {
        lo = found->second.end;
        break;
      }
    }
    for (auto it = std::next(top->getIterator()); it != block->end(); ++it)
      if (auto found = spans.find(&*it); found != spans.end()) {
        hi = found->second.pos;
        break;
      }
  }
  uint64_t count = 0;
  top->walk([&](Operation *) { ++count; });
  uint64_t step = (hi - lo) / (2 * (count + 1));
  if (step == 0) {
    renumber();
    return;
  }
  uint64_t next = lo;
  // The same walk as number(), at this gap's step; the blocks it meets
  // are the rewrite's own but for `top`'s, which takes it in order.
  std::function<void(Region &)> fill = [&](Region &region) {
    for (Block &inner : region) {
      // Beside the map until the block is done, as number() collects.
      SmallVector<Operation *> held;
      bool known = blockSpans.contains(&inner);
      uint64_t blockPos = next;
      if (!known)
        next += step;
      for (Operation &op : inner) {
        if (spans.contains(&op))
          continue;
        held.push_back(&op);
        next += step;
        uint64_t pos = next;
        for (Region &nested : op.getRegions())
          fill(nested);
        next += step;
        spans[&op] = {pos, next};
      }
      if (!known)
        blockSpans[&inner] = {blockPos, next};
      SmallVector<Operation *> &kept = opsInBlock[&inner];
      kept.append(held.begin(), held.end());
    }
  };
  // `top` alone first, in its block's order, then what it holds.
  next += step;
  uint64_t pos = next;
  for (Region &inner : top->getRegions())
    fill(inner);
  next += step;
  spans[top] = {pos, next};

  if (block) {
    SmallVector<Operation *> &held = opsInBlock[block];
    auto at = llvm::lower_bound(
        held, pos, [&](Operation *heldOp, uint64_t at) { return spans.at(heldOp).pos < at; });
    held.insert(at, top);
  }
}

void Positions::forget(Operation *op) {
  if (!spans.contains(op))
    return;
  if (Block *block = op->getBlock()) {
    SmallVector<Operation *> &held = opsInBlock[block];
    held.erase(std::remove(held.begin(), held.end(), op), held.end());
  }
  op->walk([&](Operation *inner) {
    spans.erase(inner);
    for (Region &region : inner->getRegions())
      for (Block &block : region) {
        opsInBlock.erase(&block);
        blockSpans.erase(&block);
      }
  });
}

Operation *Positions::topIn(Block &block, Operation *op) {
  uint64_t at = span(op).pos;
  auto found = opsInBlock.find(&block);
  if (found == opsInBlock.end()) {
    if (Operation *parent = block.getParentOp())
      (void)span(parent);
    found = opsInBlock.find(&block);
    if (found == opsInBlock.end()) {
      // A block a rewrite made where the numbering already stood:
      // number the function again rather than answer for a block the
      // numbering does not hold. A block of another function stays
      // unknown after it, and is no holder here.
      renumber();
      at = span(op).pos;
      found = opsInBlock.find(&block);
      if (found == opsInBlock.end())
        return nullptr;
    }
  }
  ArrayRef<Operation *> held = found->second;
  // The last op of the block at or before `op`: the one that holds it,
  // when its span ends after `op` begins.
  size_t lo = 0, hi = held.size();
  while (lo < hi) {
    size_t mid = (lo + hi) / 2;
    if (span(held[mid]).pos <= at)
      lo = mid + 1;
    else
      hi = mid;
  }
  if (lo == 0)
    return nullptr;
  Operation *top = held[lo - 1];
  return at < span(top).end ? top : nullptr;
}

bool Positions::before(Operation *a, Operation *b) { return span(a).pos < span(b).pos; }

Operation *Positions::heldIn(Block &block, OpOperand &use, Block::iterator from) {
  if (from == block.end())
    return nullptr;
  Operation *top = topIn(block, use.getOwner());
  return top && span(top).pos >= span(&*from).pos ? top : nullptr;
}

template <typename Uses>
SmallVector<Operation *> Positions::holders(Uses &&uses, Block &block, Block::iterator from) {
  SmallVector<Operation *> users;
  for (OpOperand &use : uses)
    if (Operation *top = heldIn(block, use, from))
      users.push_back(top);
  llvm::sort(users, [&](Operation *a, Operation *b) { return span(a).pos < span(b).pos; });
  users.erase(std::unique(users.begin(), users.end()), users.end());
  return users;
}

SmallVector<Operation *> Positions::usersIn(Value value, Block &block, Block::iterator from) {
  return holders(value.getUses(), block, from);
}

SmallVector<Operation *> Positions::usersIn(ArrayRef<OpOperand *> uses, Block &block,
                                            Block::iterator from) {
  return holders(llvm::make_pointee_range(uses), block, from);
}

bool Positions::decides(Operation *op) { return op->hasTrait<Decides>(); }

SmallVector<uint64_t> Positions::usePositions(Value value) {
  // Number every user first: numbering one may number the function
  // again, which would stale a position already read.
  for (Operation *user : value.getUsers())
    (void)span(user);
  SmallVector<uint64_t> at;
  for (Operation *user : value.getUsers())
    at.push_back(spans.at(user).pos);
  llvm::sort(at);
  return at;
}

bool Positions::usedAfter(Value value, Operation *op) {
  (void)span(op);
  SmallVector<uint64_t> at = usePositions(value);
  Block *home = value.getParentBlock();
  // Whether a use is inside `op`, in one of its regions.
  auto usedWithin = [&](Operation *within) {
    Span span = this->span(within);
    auto first = std::upper_bound(at.begin(), at.end(), span.pos);
    return first != at.end() && *first < span.end;
  };
  for (Operation *level = op; level; level = level->getParentOp()) {
    Block *block = level->getBlock();
    if (!block)
      return false;
    // A use in this block at or after where `level` ends: its holder in
    // the block is a later op. The block's own extent bounds it.
    uint64_t levelEnd = span(level).end;
    if (!blockSpans.contains(block)) {
      renumber();
      return usedAfter(value, op);
    }
    uint64_t blockEnd = blockSpans.at(block).end;
    auto first = std::lower_bound(at.begin(), at.end(), levelEnd);
    if (first != at.end() && *first < blockEnd)
      return true;
    Operation *parent = block->getParentOp();
    if (block == home || isa<FuncOp>(parent))
      return false;
    if (!decides(parent) && usedWithin(parent))
      return true;
  }
  return false;
}

bool Positions::usedIn(Value value, Region &region) {
  if (region.empty())
    return false;
  if (Operation *parent = region.getParentOp())
    (void)span(parent);
  uint64_t lo = UINT64_MAX, hi = 0;
  for (Block &block : region) {
    auto found = blockSpans.find(&block);
    if (found == blockSpans.end()) {
      renumber();
      return usedIn(value, region);
    }
    lo = std::min(lo, found->second.pos);
    hi = std::max(hi, found->second.end);
  }
  if (lo == UINT64_MAX)
    return false;
  SmallVector<uint64_t> at = usePositions(value);
  auto first = std::lower_bound(at.begin(), at.end(), lo);
  return first != at.end() && *first < hi;
}

void Positions::whereDies(ArrayRef<OpOperand *> uses, Block &block,
                          function_ref<bool(OpOperand &)> takesOver,
                          function_ref<void(Block &, Block::iterator)> at) {
  SmallVector<Operation *> users = usersIn(uses, block, block.begin());
  if (users.empty()) {
    at(block, block.begin());
    return;
  }
  Operation *last = users.back();
  if (last->hasTrait<OpTrait::IsTerminator>() ||
      llvm::any_of(uses, [&](OpOperand *use) { return use->getOwner() == last && takesOver(*use); }))
    return;
  // An op that decides moves the value into each of its regions, where
  // it dies on each path; any other holds it for as long as it runs,
  // and it dies after the op.
  if (decides(last)) {
    for (Region &region : last->getRegions())
      if (!region.empty())
        whereDies(uses, region.front(), takesOver, at);
    return;
  }
  at(block, std::next(last->getIterator()));
}

void Positions::whereDies(Value value, Block &block, function_ref<bool(OpOperand &)> takesOver,
                          function_ref<void(Block &, Block::iterator)> at) {
  SmallVector<OpOperand *> uses = llvm::to_vector(llvm::make_pointer_range(value.getUses()));
  whereDies(uses, block, takesOver, at);
}

FieldOp Positions::onlyReads(Value box) {
  if (!isa<BoxType>(unrestricted(box.getType())) || box.use_empty())
    return nullptr;
  SmallVector<OpOperand *> uses = llvm::to_vector(llvm::make_pointer_range(box.getUses()));
  return onlyReads(box.getType(), uses);
}

// A nested pattern reads the fields of a box an outer one matched.
FieldOp Positions::onlyReads(Type type, ArrayRef<OpOperand *> uses) {
  if (!isa<BoxType>(unrestricted(type)) || uses.empty())
    return nullptr;
  FieldOp first;
  for (OpOperand *use : uses) {
    auto read = dyn_cast<FieldOp>(use->getOwner());
    if (!read || (first && read.getTag() != first.getTag()))
      return nullptr;
    if (!first || (read->getBlock() == first->getBlock() && before(read, first)))
      first = read;
  }
  // Every use is in the first read's block, at it or after it: from
  // there on the constructor is known. The uses in the block are
  // usersIn's; one before the first read makes the list from the
  // block's start longer than the one from the first read, and a use
  // outside the block is in neither.
  Block *block = first->getBlock();
  if (usersIn(uses, *block, first->getIterator()).size() !=
      usersIn(uses, *block, block->begin()).size())
    return nullptr;
  if (llvm::any_of(uses, [&](OpOperand *use) { return !topIn(*block, use->getOwner()); }))
    return nullptr;
  return first;
}

} // namespace idr::ownership
