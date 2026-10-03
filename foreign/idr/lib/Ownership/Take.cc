// Taking a value apart: a box where it dies, a scrutinee where a case
// region begins, and an unboxed sum whose only uses read its fields.

#include "Ownership/Ownership.h"

using namespace mlir;

namespace idr::ownership {

SmallVector<Operation *> usersIn(Value value, Block &block, Operation *after) {
  SmallVector<Operation *> users;
  for (Operation *user : value.getUsers()) {
    Operation *top = block.findAncestorOpInBlock(*user);
    if (top && (!after || after->isBeforeInBlock(top)))
      users.push_back(top);
  }
  llvm::sort(users, [](Operation *a, Operation *b) { return a->isBeforeInBlock(b); });
  users.erase(std::unique(users.begin(), users.end()), users.end());
  return users;
}

void whereDies(Value value, Block &block, SymbolTableCollection &symbols,
               function_ref<void(Block &, Block::iterator)> at) {
  SmallVector<Operation *> users = usersIn(value, block, nullptr);
  if (users.empty()) {
    at(block, block.begin());
    return;
  }
  Operation *last = users.back();
  if (last->hasTrait<OpTrait::IsTerminator>())
    return;
  // Borrow inference may still be to come, so every call may consume its
  // arguments here.
  if (llvm::any_of(last->getOpOperands(), [&](OpOperand &operand) {
        return operand.get() == value && useOf(operand, symbols) == Use::Consume;
      }))
    return;
  // The body of a loop over an array runs once per element, and a value
  // from outside it is alive throughout: the value dies after the loop.
  if (last->getNumRegions() != 0 && !isArrayLoop(last)) {
    for (Region &region : last->getRegions())
      if (!region.empty())
        whereDies(value, region.front(), symbols, at);
    return;
  }
  at(block, std::next(last->getIterator()));
}

namespace {

// Whether `use` is at `at` in `block` or after it, itself or inside an op
// there: where a take placed at `at` has already run.
bool fromPoint(Block &block, Block::iterator at, OpOperand &use) {
  Operation *top = block.findAncestorOpInBlock(*use.getOwner());
  return top && at != block.end() && !top->isBeforeInBlock(&*at);
}

// The fields of `box`, built by `ctor`, that a take of it gives: the
// arguments of `fields` (the case region that bound them, when one did) and
// the results of the idr.field reads of the box, each with its index.
void eachField(Value box, CtorOp ctor, Block *fields, function_ref<void(Value, unsigned)> f) {
  if (fields)
    for (BlockArgument arg : fields->getArguments())
      f(arg, arg.getArgNumber());
  for (Operation *user : llvm::make_early_inc_range(box.getUsers()))
    if (auto read = dyn_cast<FieldOp>(user); read && read.getCtor() == ctor.getSymName())
      f(read.getResult(), static_cast<unsigned>(read.getIndex()));
}

} // namespace

bool keepsCountedField(Value box, CtorOp ctor, Block &block, Block::iterator at, Block *fields) {
  Counting counting(ctor->getParentOfType<ModuleOp>());
  bool kept = false;
  eachField(box, ctor, fields, [&](Value field, unsigned) {
    kept = kept || (counting.counted(field.getType()) &&
                    llvm::any_of(field.getUses(),
                                 [&](OpOperand &use) { return fromPoint(block, at, use); }));
  });
  return kept;
}

TakeOp takeAt(Value box, CtorOp ctor, Block &block, Block::iterator at, Block *fields) {
  OpBuilder b(&block, at);
  Location loc = at == block.end() ? block.getParentOp()->getLoc() : at->getLoc();
  auto name = SymbolRefAttr::get(ctor->getParentOfType<DataOp>().getSymNameAttr(),
                                 {FlatSymbolRefAttr::get(ctor.getSymNameAttr())});
  Counting counting(ctor->getParentOfType<ModuleOp>());
  SmallVector<Type> results;
  // A constructor without fields is its atom, which is nobody's to build in.
  if (!ctor.getFieldTypes().empty())
    results.push_back(owned(TokenType::get(ctor.getContext())));
  for (unsigned index = 0, e = static_cast<unsigned>(ctor.getFieldTypes().size()); index < e;
       ++index) {
    Type field = fieldType(box.getType(), ctor.getFieldType(index));
    results.push_back(counting.counted(field) ? owned(field) : field);
  }
  auto take = TakeOp::create(b, loc, results, box, name);
  eachField(box, ctor, fields, [&](Value field, unsigned index) {
    field.replaceUsesWithIf(take.getFields()[index],
                            [&](OpOperand &use) { return fromPoint(block, at, use); });
  });
  return take;
}

FieldOp onlyReads(Value box) {
  if (!isa<BoxType>(unrestricted(box.getType())) || box.use_empty())
    return nullptr;
  FieldOp first;
  for (Operation *user : box.getUsers()) {
    auto read = dyn_cast<FieldOp>(user);
    if (!read || (first && read.getCtorAttr() != first.getCtorAttr()))
      return nullptr;
    if (!first || (read->getBlock() == first->getBlock() && read->isBeforeInBlock(first)))
      first = read;
  }
  // Every use is in the first read's block, at it or after it: from there
  // on the constructor is known.
  Block *block = first->getBlock();
  for (Operation *user : box.getUsers()) {
    Operation *top = block->findAncestorOpInBlock(*user);
    if (!top || top->isBeforeInBlock(first))
      return nullptr;
  }
  return first;
}

TakeOp takeAtEntry(MatchOp match, unsigned index) {
  Block &block = match.getCaseRegion(index).front();
  Value value = match.getScrutinee();
  auto data = getSumName(value.getType());
  auto ctor = SymbolRefAttr::get(data.getAttr(), {cast<FlatSymbolRefAttr>(match.getCases()[index])});
  Counting counting(match->getParentOfType<ModuleOp>());
  SmallVector<Type> results;
  // A constructor without fields is its atom, which is nobody's to build in.
  if (isa<BoxType>(unrestricted(value.getType())) && block.getNumArguments() != 0)
    results.push_back(owned(TokenType::get(match.getContext())));
  for (Type field : block.getArgumentTypes())
    results.push_back(counting.counted(field) ? owned(field) : field);
  OpBuilder b = OpBuilder::atBlockBegin(&block);
  auto take = TakeOp::create(b, match.getLoc(), results, value, ctor);
  for (auto [field, taken] : llvm::zip_equal(block.getArguments(), take.getFields()))
    field.replaceAllUsesWith(taken);
  return take;
}

TakeOp takeFields(Value value, SymbolRefAttr ctor, ArrayRef<Type> fieldTypes) {
  OpBuilder b(value.getContext());
  if (Operation *def = value.getDefiningOp())
    b.setInsertionPointAfter(def);
  else
    b.setInsertionPointToStart(cast<BlockArgument>(value).getOwner());
  Counting counting(value.getParentRegion()->getParentOfType<ModuleOp>());
  SmallVector<Type> results;
  for (Type field : fieldTypes)
    results.push_back(counting.counted(field) ? owned(field) : field);
  auto take = TakeOp::create(b, value.getLoc(), results, value, ctor);
  for (OpOperand &use : llvm::make_early_inc_range(value.getUses())) {
    auto read = dyn_cast<FieldOp>(use.getOwner());
    if (!read)
      continue;
    read.getResult().replaceAllUsesWith(take.getFields()[read.getIndex()]);
    read.erase();
  }
  return take;
}

} // namespace idr::ownership
