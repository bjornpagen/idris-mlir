// idr.ownership:classes: the class of each value of a function, as
// counting places it: untracked, static, borrowed or owned. Nothing here is
// exported: counting's steps share it.
export module idr.ownership:classes;

import idr.mlir;
import idr.dialect;

import :borrowed;
import :counting;
import :readfrom;
import :regions;
import :isstatic;
import :usedafter;

using namespace mlir;

namespace idr::ownership {

enum class Class { Untracked, Static, Borrowed, Owned };

// The class of each value of a function, computed once.
class Classes {
public:
  Classes(func::FuncOp fn, Counting &counting) : fn(fn), counting(counting) {}

  Class classOf(Value value) {
    if (!counting.counted(value.getType()))
      return Class::Untracked;
    if (isStatic(value))
      return Class::Static;
    auto known = classes.find(value);
    if (known != classes.end())
      return known->second;
    Class result = Class::Owned;
    if (Value from = readFrom(value)) {
      if (llvm::all_of(value.getUsers(), [&](Operation *user) { return aliveAt(from, user); }))
        result = Class::Borrowed;
    } else if (auto arg = dyn_cast<BlockArgument>(value);
               arg && arg.getOwner()->getParentOp() == fn.getOperation()) {
      if (isBorrowed(fn, arg.getArgNumber()))
        result = Class::Borrowed;
    }
    classes[value] = result;
    return result;
  }

  // Forgets the class of `value`, whose definition changed.
  void erase(Value value) { classes.erase(value); }

private:
  // Whether `value` still holds a reference, or lives as long as the call,
  // where `op` uses what was read from it: an owned value is used again
  // after `op`, and a borrowed one is read from a value that is alive
  // there, or is a parameter. A match uses its scrutinee as it starts, so
  // a use of the value in one of its regions keeps it alive there too.
  bool aliveAt(Value value, Operation *op) {
    switch (classOf(value)) {
    case Class::Untracked:
    case Class::Static:
      return true;
    case Class::Owned:
      // Used again after `op`, or inside a region of it: a match uses its
      // scrutinee as it starts, so a use in one of its regions keeps it
      // alive there too. usedIn is what counting asks of a region.
      return usedAfter(value, op) ||
             llvm::any_of(op->getRegions(), [&](Region &region) { return usedIn(value, region); });
    case Class::Borrowed:
      break;
    }
    Value from = readFrom(value);
    return !from || aliveAt(from, op);
  }

  func::FuncOp fn;
  Counting &counting;
  llvm::DenseMap<Value, Class> classes;
};

} // namespace idr::ownership
