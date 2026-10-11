// idr.canon:meets: whether a consumer moved into a match's regions meets
// there, or one match deeper, a value it folds or canonicalizes against
// (:feeds).
//
// The greedy driver asks again on every attempt: a match is queued whenever
// anything under it changes, and again at each iteration. The walk is the
// same while the yields and the consumer are, so the answer is kept for the
// rewriter that asked and dropped when one of them, or a value the answer
// was read from, changes. An answer that rests on the consumer's folder is
// not kept: the folder reads whatever that op reads.
//
// The driver applies every pattern on one worklist, and the pattern objects
// are the ones it owns. The memory is a member of the pattern that asked
// first. The rewriter's listener is that memory, which is how a later
// pattern on the same worklist finds it. A different rewriter has a
// different listener, and the answers are dropped. Nothing is kept for the
// process.
export module idr.canon:meets;

import idr.mlir;
import idr.dialect;

import :feeds;

using namespace mlir;
using namespace idr;

namespace {

// The first word of a polymorphic object: its virtual table. Compared, not
// dereferenced as another type. The rewriter's listener is the only place a
// pattern can leave this memory, and the driver's own listener, the debug
// logging listener and the expensive-checks listener are other types.
const void *virtualTable(const void *object) {
  const void *table;
  __builtin_memcpy(&table, object, sizeof(table));
  return table;
}

} // namespace

export namespace idr::canon {

// The answers meetsInSomeRegion keeps for one rewriter. A pattern holds it.
// Copying it would leave the listener pointing at the copy.
class MeetsMemory {
public:
  MeetsMemory() { listen.memory = this; }
  MeetsMemory(const MeetsMemory &) = delete;
  MeetsMemory &operator=(const MeetsMemory &) = delete;
  MeetsMemory(MeetsMemory &&) = delete;
  MeetsMemory &operator=(MeetsMemory &&) = delete;

private:
  struct Deps {
    SmallVector<Operation *, 16> ops;
    SmallVector<Value, 8> values;
    bool fold = false;
  };

  struct Entry {
    bool meets = false;
    SmallVector<Operation *, 16> ops;
    SmallVector<Value, 8> values;
  };

  using Key = std::pair<OpResult, Operation *>;

  struct Listen : RewriterBase::Listener {
    MeetsMemory *memory = nullptr;
    OpBuilder::Listener *builder = nullptr;
    RewriterBase::Listener *rewrite = nullptr;

    void retarget(OpBuilder::Listener *next) {
      builder = next;
      rewrite = next ? dyn_cast<RewriterBase::Listener>(next) : nullptr;
    }

    void notifyOperationInserted(Operation *op, OpBuilder::InsertPoint previous) override;
    void notifyBlockInserted(Block *block, Region *previous,
                             Region::iterator previousIt) override;
    void notifyBlockErased(Block *block) override;
    void notifyOperationModified(Operation *op) override;
    void notifyOperationReplaced(Operation *op, ValueRange replacement) override;
    void notifyOperationErased(Operation *op) override;
    void notifyMatchFailure(Location loc,
                            function_ref<void(Diagnostic &)> reasonCallback) override;
  };

  friend MeetsMemory &bindMeets(MeetsMemory &local, PatternRewriter &rewriter);
  friend bool meetsInSomeRegion(MeetsMemory &memory, OpResult result, Operation *consumer);

  // The memory whose listener `listener` is, when it is one of these.
  static MeetsMemory *listening(OpBuilder::Listener *listener);

  static void noteOp(Deps &deps, Operation *op) {
    if (op)
      deps.ops.push_back(op);
  }

  // Users as well as the value: a new or removed use is what hasOneUse and
  // the one-use chain in feeds() read, and a user may drop the value before
  // the notification, so the users at the time of the walk are remembered.
  static void note(Deps &deps, Value value) {
    if (!value)
      return;
    deps.values.push_back(value);
    for (Operation *user : value.getUsers())
      deps.ops.push_back(user);
  }

  // The defining ops throughLinear walks, which feeds() reads past the value
  // the region yields.
  static void noteLinear(Deps &deps, Value value) {
    for (;;) {
      note(deps, value);
      Operation *def = value.getDefiningOp();
      noteOp(deps, def);
      if (auto enter = dyn_cast_or_null<LinEnterOp>(def)) {
        value = enter.getValue();
        continue;
      }
      auto lin = dyn_cast_or_null<LinUseOp>(def);
      auto enter = lin ? lin.getLinear().getDefiningOp<LinEnterOp>() : LinEnterOp();
      if (!enter)
        return;
      noteOp(deps, enter);
      value = enter.getValue();
    }
  }

  // The consumer and the one-use chain reader() and eliminationAt follow
  // (a linear position, a field, a linear position, an apply).
  static void noteChain(Deps &deps, Operation *op) {
    for (unsigned step = 0; op && step < 8; ++step) {
      noteOp(deps, op);
      if (op->getNumResults() != 1)
        return;
      Value result = op->getResult(0);
      note(deps, result);
      if (!result.hasOneUse())
        return;
      Operation *user = *result.user_begin();
      if (user == op)
        return;
      op = user;
    }
  }

  // Whether feeds() can call the consumer's folder for `value`. The folder is
  // not tried for an op with regions, and these consumers decide before it.
  static bool restsOnFold(Value value, Operation *consumer) {
    Value plain = throughLinear(value);
    if (!matchPattern(plain, m_Constant()))
      return false;
    if (consumer->getNumRegions() != 0)
      return false;
    if (isa<PutStrOp, PutListOp, ForceOp, MatchOp, MatchLitOp, FieldOp, TagOp, func::CallOp>(
            consumer))
      return false;
    if (auto con = dyn_cast<ConOp>(consumer); con && isa<BoxType>(unrestricted(con.getType())))
      return false;
    Operation *def = plain.getDefiningOp();
    return !isa_and_nonnull<StrAppendOp, StrConsOp, StrFromCharOp, StrShowOp>(def);
  }

  // Whether some region of the match that defines `result` yields, as that
  // result, a value that feeds the consumer holding `use`, or, while `deeper`
  // is above 0, the result of a match one of whose regions does so in turn:
  // case-of-case moves the consumer on into that match. The bound keeps the
  // question as cheap as the matches are wide, however deep they nest, and
  // a consumer moves only toward a value it meets within that many moves.
  // `read`, when set, collects what the walk read so a later attempt can
  // reuse the answer while those are unchanged.
  static bool yieldsFeeding(OpResult result, OpOperand &use, unsigned deeper, Deps *read) {
    Operation *match = result.getOwner();
    if (read)
      read->ops.push_back(match);
    return llvm::any_of(match->getRegions(), [&](Region &region) {
      Operation *term = region.front().getTerminator();
      if (read)
        read->ops.push_back(term);
      auto yield = dyn_cast<YieldOp>(term);
      if (!yield)
        return false;
      Value value = yield.getOperand(result.getResultNumber());
      if (read) {
        noteLinear(*read, value);
        if (restsOnFold(value, use.getOwner()))
          read->fold = true;
      }
      if (canon::feeds(value, use))
        return true;
      auto inner = dyn_cast<OpResult>(value);
      if (deeper == 0 || !inner || !isa<MatchOp, MatchLitOp>(inner.getOwner()))
        return false;
      return yieldsFeeding(inner, use, deeper - 1, read);
    });
  }

  const Entry *find(OpResult result, Operation *consumer) const {
    auto found = entries.find({result, consumer});
    return found == entries.end() ? nullptr : &found->second;
  }

  void remember(OpResult result, Operation *consumer, bool meets, Deps &read) {
    Key key{result, consumer};
    dropKey(key);
    Entry entry;
    entry.meets = meets;
    entry.ops = std::move(read.ops);
    entry.values = std::move(read.values);
    uniqueInto(entry.ops);
    uniqueInto(entry.values);
    for (Operation *op : entry.ops)
      byOp[op].push_back(key);
    for (Value value : entry.values)
      byValue[value].push_back(key);
    entries.try_emplace(key, std::move(entry));
  }

  void invalidateOp(Operation *op) {
    if (entries.empty())
      return;
    SmallVector<Key, 4> keys;
    collect(byOp, op, keys);
    for (Value operand : op->getOperands())
      collect(byValue, operand, keys);
    for (Value result : op->getResults())
      collect(byValue, result, keys);
    for (Key key : keys)
      dropKey(key);
  }

  // A new or moved block can change which terminator a region walks. The
  // match that owns the region is what the walk recorded.
  void invalidateRegion(Region *region) {
    if (region)
      if (Operation *parent = region->getParentOp())
        invalidateOp(parent);
  }

  void drop() {
    on = false;
    entries.clear();
    byOp.clear();
    byValue.clear();
  }

  void install(PatternRewriter &rewriter) {
    if (rewriter.getListener() == &listen)
      return;
    // A new driver, or this memory is no longer the listener, so updates
    // since it was were missed. The previous one's ops must not answer.
    drop();
    listen.retarget(rewriter.getListener());
    rewriter.setListener(&listen);
    on = true;
  }

  bool answer(OpResult result, Operation *consumer) {
    if (on)
      if (const Entry *known = find(result, consumer))
        return known->meets;
    Deps read;
    if (on) {
      noteChain(read, consumer);
      for (Value operand : consumer->getOperands())
        noteOp(read, operand.getDefiningOp());
    }
    bool meets = llvm::any_of(consumer->getOpOperands(), [&](OpOperand &use) {
      return use.get() == result &&
             yieldsFeeding(result, use, /*deeper=*/1, on ? &read : nullptr);
    });
    if (on && !read.fold)
      remember(result, consumer, meets, read);
    return meets;
  }

  template <typename T>
  static void uniqueInto(SmallVectorImpl<T> &items) {
    llvm::SmallPtrSet<T, 16> seen;
    llvm::erase_if(items, [&](T item) { return !seen.insert(item).second; });
  }

  template <typename Map, typename Lookup>
  static void collect(Map &map, Lookup lookup, SmallVectorImpl<Key> &keys) {
    auto found = map.find(lookup);
    if (found != map.end())
      keys.append(found->second.begin(), found->second.end());
  }

  template <typename Map, typename Lookup>
  void unlink(Map &map, Lookup lookup, Key key) {
    auto found = map.find(lookup);
    if (found == map.end())
      return;
    llvm::erase(found->second, key);
    if (found->second.empty())
      map.erase(found);
  }

  void dropKey(Key key) {
    auto found = entries.find(key);
    if (found == entries.end())
      return;
    Entry gone = std::move(found->second);
    entries.erase(found);
    for (Operation *op : gone.ops)
      unlink(byOp, op, key);
    for (Value value : gone.values)
      unlink(byValue, value, key);
  }

  Listen listen;
  bool on = false;
  DenseMap<Key, Entry> entries;
  DenseMap<Operation *, SmallVector<Key, 1>> byOp;
  DenseMap<Value, SmallVector<Key, 1>> byValue;
};

MeetsMemory *MeetsMemory::listening(OpBuilder::Listener *listener) {
  auto *rewrite = dyn_cast_or_null<RewriterBase::Listener>(listener);
  if (!rewrite)
    return nullptr;
  Listen sample;
  if (virtualTable(rewrite) != virtualTable(&sample))
    return nullptr;
  return static_cast<Listen *>(rewrite)->memory;
}

// The memory already listening on `rewriter`, or `local` once it is. A
// pattern that asks later on this worklist shares the first pattern's
// memory: one listener, so each still hears the updates that drop answers.
MeetsMemory &bindMeets(MeetsMemory &local, PatternRewriter &rewriter) {
  if (MeetsMemory *live = MeetsMemory::listening(rewriter.getListener())) {
    if (live != &local)
      local.drop();
    return *live;
  }
  local.install(rewriter);
  return local;
}

// Whether `consumer`, moved into every region of the match that defines
// `result`, meets in some region a value it folds or canonicalizes against,
// there or in a region of a match that region yields the result of: in a
// region of the match, or one match deeper, since a helper's `if` over two
// actions, inlined into a region, leaves the closures the bind folds
// against in the regions of a match the region yields the result of.
bool meetsInSomeRegion(MeetsMemory &memory, OpResult result, Operation *consumer) {
  return memory.answer(result, consumer);
}

void MeetsMemory::Listen::notifyOperationInserted(Operation *op,
                                                 OpBuilder::InsertPoint previous) {
  memory->invalidateOp(op);
  if (builder)
    builder->notifyOperationInserted(op, previous);
}

void MeetsMemory::Listen::notifyBlockInserted(Block *block, Region *previous,
                                             Region::iterator previousIt) {
  memory->invalidateRegion(block->getParent());
  memory->invalidateRegion(previous);
  if (builder)
    builder->notifyBlockInserted(block, previous, previousIt);
}

void MeetsMemory::Listen::notifyBlockErased(Block *block) {
  memory->invalidateRegion(block->getParent());
  if (rewrite)
    rewrite->notifyBlockErased(block);
}

void MeetsMemory::Listen::notifyOperationModified(Operation *op) {
  memory->invalidateOp(op);
  if (rewrite)
    rewrite->notifyOperationModified(op);
}

void MeetsMemory::Listen::notifyOperationReplaced(Operation *op, ValueRange replacement) {
  memory->invalidateOp(op);
  if (rewrite)
    rewrite->notifyOperationReplaced(op, replacement);
}

void MeetsMemory::Listen::notifyOperationErased(Operation *op) {
  memory->invalidateOp(op);
  if (rewrite)
    rewrite->notifyOperationErased(op);
}

void MeetsMemory::Listen::notifyMatchFailure(Location loc,
                                            function_ref<void(Diagnostic &)> reasonCallback) {
  if (rewrite)
    rewrite->notifyMatchFailure(loc, reasonCallback);
}

} // namespace idr::canon
