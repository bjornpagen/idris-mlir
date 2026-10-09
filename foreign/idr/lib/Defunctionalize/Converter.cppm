// idr.defunctionalize:converter: the rewriting of the module into sums.
module;
// assert is a macro, which no import carries.
#include <cassert>

export module idr.defunctionalize:converter;

import idr.mlir;
import idr.dialect;

import :closures;
import :declared;
import :labels;
import :slots;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::defunctionalize {

// The module rewritten as decided: slots retyped, sums declared, values
// coerced where they move between keys, constants and applies converted,
// and closures and suspensions of converted keys made constructors.
struct Converter : Declared {
  using Declared::Declared;

  // A shared part of a constant, in a slot, is converted once.
  llvm::DenseMap<std::pair<Attribute, Key>, Attribute> convertedParts;

  // Keys every slot and decides which keys become sums.
  void decideKeys() {
    keyFields();
    keyArrays();
    keyFunctions();
    keyValues();
    widen();
    keyForces();
    order();
    connect();
    decide();
  }

  // `label` with `captures` as a value of `key`.
  // The captures are held as the function's parameters, which the closure
  // or the sum's constructor takes them as: a capture a match bound at a
  // plain grade enters its linear type again.
  Value build(OpBuilder &b, Location loc, StringAttr label, const Key &key, ValueRange captures) {
    auto callee = FlatSymbolRefAttr::get(label);
    SmallVector<Value> held;
    for (auto [capture, type] : llvm::zip(captures, captureTypes(label, key.first)))
      held.push_back(idr::heldAs(b, loc, capture, type));
    if (Type sum = sumOf(key))
      return idr::ConOp::create(b, loc, sum,
                                SymbolRefAttr::get(idr::getSumName(sum).getAttr(), {callee}),
                                held);
    assert(!isLazy(key) && "idr-defunctionalize: a cell rewritten into a key left lazy");
    return idr::ClosureOp::create(b, loc, key.first, callee, held);
  }

  // Where the program builds a closure of `label`: a closure a coercion
  // rebuilds is reported there.
  Location closureLoc(StringAttr label, Location fallback) {
    auto it = module.closures.find(label);
    return it == module.closures.end() || it->second.empty() ? fallback
                                                              : it->second.front().getLoc();
  }

  bool needsCoercion(const Key &from, const Key &to) {
    return from != to && (isConverted(from) || isConverted(to));
  }

  // `value` of `from` as a value of `to`: a match that rebuilds each label,
  // or poison for a value the analysis never reaches, which is a value of
  // the program, as any poison is: a value of the empty key, or one moving
  // into a slot no label reaches, a move that never runs. A cell may be
  // running or forced as well, and keeps its state in the other sum.
  Value coerce(OpBuilder &b, Location loc, Value value, const Key &from, const Key &to) {
    if (!needsCoercion(from, to))
      return value;
    // A linear value is used once, rebuilt, and enters the other linear
    // slot.
    if (idr::isLinear(value.getType())) {
      Value used = idr::LinUseOp::create(b, loc, idr::unrestricted(value.getType()), value);
      Value moved = coerce(b, loc, used, from, to);
      return idr::LinEnterOp::create(b, loc, idr::linear(moved.getType()), moved);
    }
    assert(canCoerce(from, to) && "idr-defunctionalize: a move it did not decide");
    if (isEmpty(from) || isEmpty(to))
      return ub::PoisonOp::create(b, loc, typeOf(to));
    bool memo = isLazy(from);
    SmallVector<Attribute> cases;
    for (StringAttr label : from.second.getAsRange<StringAttr>())
      cases.push_back(FlatSymbolRefAttr::get(label));
    if (memo) {
      cases.push_back(FlatSymbolRefAttr::get(ctx, idr::memoRunning));
      cases.push_back(FlatSymbolRefAttr::get(ctx, idr::memoForced));
    }
    OpBuilder::InsertionGuard guard(b);
    auto match = idr::MatchOp::create(b, loc, TypeRange{typeOf(to)}, value, b.getArrayAttr(cases),
                                      unsigned(cases.size()));
    for (auto [label, region] :
         llvm::zip(from.second.getAsRange<StringAttr>(), match.getRegions())) {
      SmallVector<Type> types = boundCaptureTypes(label, from.first, value.getType());
      Block *block = b.createBlock(&region, region.end(), types,
                                   SmallVector<Location>(types.size(), loc));
      Location at = isConverted(to) ? loc : closureLoc(label, loc);
      idr::YieldOp::create(b, loc, build(b, at, label, to, block->getArguments()));
    }
    if (!memo)
      return match.getResult(0);
    auto state = [&](StringRef ctor) {
      return SymbolRefAttr::get(idr::getSumName(typeOf(to)).getAttr(),
                                {FlatSymbolRefAttr::get(ctx, ctor)});
    };
    auto labels = static_cast<unsigned>(from.second.size());
    Region &running = match.getRegions()[labels];
    b.createBlock(&running, running.end());
    Value same = idr::ConOp::create(b, loc, typeOf(to), state(idr::memoRunning), ValueRange());
    idr::YieldOp::create(b, loc, same);
    Type inside = idr::fieldType(match.getScrutinee().getType(), forcedType(from));
    Region &forced = match.getRegions()[labels + 1];
    Block *block = b.createBlock(&forced, forced.end(), TypeRange{inside}, {loc});
    Value held = idr::heldAs(b, loc, block->getArgument(0), forcedType(to));
    Value copy = idr::ConOp::create(b, loc, typeOf(to), state(idr::memoForced), held);
    idr::YieldOp::create(b, loc, copy);
    return match.getResult(0);
  }

  // The types a match on a sum of `type` binds the captures of `label` at:
  // the fields at the sum's grade.
  SmallVector<Type> boundCaptureTypes(StringAttr label, Type type, Type scrutinee) {
    SmallVector<Type> types;
    for (Type capture : captureTypes(label, type))
      types.push_back(idr::fieldType(scrutinee, capture));
    return types;
  }

  // A call returns its callee's result, then moves it into its own slot.
  void coerceCalls(OpBuilder &b) {
    SmallVector<func::CallOp> calls;
    module.op.walk([&](func::CallOp call) { calls.push_back(call); });
    for (func::CallOp call : calls) {
      func::FuncOp fn = module.function(call.getCalleeAttr().getAttr());
      for (OpResult value : call.getResults()) {
        auto it = values.find(value);
        if (it == values.end())
          continue;
        Key to = it->second;
        Key from = fn ? result(fn, value.getResultNumber()) : unknown(to.first);
        value.setType(typeOf(value.getType(), from));
        values[value] = from;
        b.setInsertionPointAfter(call);
        Value moved = coerce(b, call.getLoc(), value, from, to);
        if (moved == value)
          continue;
        value.replaceAllUsesExcept(moved, moved.getDefiningOp());
        values[moved] = to;
      }
    }
  }

  void coerceSinks(OpBuilder &b) {
    for (const Sink &sink : sinks) {
      Value value = sink.user->getOperand(sink.index);
      b.setInsertionPoint(sink.user);
      Value moved = coerce(b, sink.user->getLoc(), value, values.lookup(value), sink.to);
      sink.user->setOperand(sink.index, moved);
    }
  }

  // Constant `attr` in a slot of `slot`, with its closures and suspensions
  // of converted keys as constructors.
  Attribute convert(Attribute attr, const Key &slot) {
    if (!module.holdsClosure(attr))
      return attr;
    auto memo = convertedParts.find({attr, slot});
    if (memo != convertedParts.end())
      return memo->second;
    Attribute result = convertParts(attr, slot);
    convertedParts[{attr, slot}] = result;
    return result;
  }

  Attribute convertParts(Attribute attr, const Key &slot) {
    if (auto closure = dyn_cast<idr::ClosureAttr>(attr)) {
      StringAttr label = closure.getCallee().getAttr();
      SmallVector<Attribute> captures;
      for (auto [i, capture] : llvm::enumerate(closure.getCaptures()))
        captures.push_back(convert(capture, argument(label, static_cast<unsigned>(i))));
      auto array = ArrayAttr::get(ctx, captures);
      if (Type sum = sumOf(slot))
        return idr::ConAttr::get(
            ctx, SymbolRefAttr::get(idr::getSumName(sum).getAttr(), {closure.getCallee()}), array);
      return idr::ClosureAttr::get(ctx, closure.getCallee(), array);
    }
    auto con = dyn_cast<idr::ConAttr>(attr);
    if (!con)
      return attr;
    SymbolRefAttr ctor = con.getCtor();
    auto fieldsOf = [&](ArrayAttr cell, function_ref<unsigned(unsigned)> index) {
      SmallVector<Attribute> parts;
      for (auto [i, value] : llvm::enumerate(cell))
        parts.push_back(convert(value, field(ctor, index(static_cast<unsigned>(i)))));
      return ArrayAttr::get(ctx, parts);
    };
    if (!con.isRun())
      return idr::ConAttr::get(ctx, ctor, fieldsOf(con.getFields(), [](unsigned i) { return i; }));
    // A run is converted cell by cell, its tail in the last cell's spine.
    unsigned spine = con.getSpine();
    SmallVector<ArrayAttr> cells;
    for (ArrayAttr cell : con.getRunCells())
      cells.push_back(fieldsOf(cell, [&](unsigned i) { return cellField(i, spine); }));
    return idr::ConAttr::getRun(ctx, ctor, spine, cells, convert(con.getTail(), field(ctor, spine)));
  }

  // An apply of a converted key becomes a match over its labels, each
  // region calling its label with the captures, then the arguments. A key
  // left a closure is one no label reaches, since the module is rewritten
  // only when every other key converts: that apply never runs, and what it
  // gives is poison.
  void rewrite(idr::ApplyOp apply, OpBuilder &b) {
    // The callee is retyped by now, so not getCallee(), which casts it.
    Value closure = apply->getOperand(0);
    Key callee = values.lookup(closure);
    ArrayRef<Type> inputs = cast<idr::FnType>(callee.first).getInputs();
    b.setInsertionPoint(apply);
    if (!isConverted(callee)) {
      for (OpResult own : apply->getResults()) {
        // The poison holds the result's slot: an apply of it reads its key.
        Value poison = ub::PoisonOp::create(b, apply.getLoc(), own.getType());
        if (auto it = values.find(own); it != values.end())
          values[poison] = it->second;
        own.replaceAllUsesWith(poison);
      }
      apply.erase();
      return;
    }
    SmallVector<Attribute> cases;
    for (StringAttr label : callee.second.getAsRange<StringAttr>())
      cases.push_back(FlatSymbolRefAttr::get(label));
    auto match = idr::MatchOp::create(b, apply.getLoc(), apply.getResultTypes(), closure,
                                      b.getArrayAttr(cases), unsigned(cases.size()));
    for (auto [label, region] :
         llvm::zip(callee.second.getAsRange<StringAttr>(), match.getRegions())) {
      func::FuncOp fn = module.function(label);
      SmallVector<Type> types = boundCaptureTypes(label, callee.first, closure.getType());
      Block *block = b.createBlock(&region, region.end(), types,
                                   SmallVector<Location>(types.size(), apply.getLoc()));
      SmallVector<Value> operands;
      for (auto [capture, type] : llvm::zip(block->getArguments(), captureTypes(label, callee.first)))
        operands.push_back(idr::heldAs(b, apply.getLoc(), capture, type));
      for (auto [i, arg] : llvm::enumerate(apply.getArgs()))
        operands.push_back(isKeyed(inputs[i])
                               ? coerce(b, apply.getLoc(), arg, values.lookup(arg),
                                        argument(fn, static_cast<unsigned>(types.size() + i)))
                               : arg);
      auto call = func::CallOp::create(b, apply.getLoc(), fn, operands);
      SmallVector<Value> yields;
      for (auto [value, own] : llvm::zip(call.getResults(), apply.getResults()))
        yields.push_back(values.count(own)
                             ? coerce(b, apply.getLoc(), value,
                                      result(fn, cast<OpResult>(value).getResultNumber()),
                                      values.lookup(own))
                             : value);
      idr::YieldOp::create(b, apply.getLoc(), yields);
    }
    for (auto [own, value] : llvm::zip(apply.getResults(), match.getResults()))
      if (values.count(own))
        values[value] = values.lookup(own);
    apply.replaceAllUsesWith(match.getResults());
    apply.erase();
  }

  // A closure or a suspension of a converted key is its label's
  // constructor.
  void construct(OpBuilder &b, Operation *op, StringAttr label, ValueRange captures) {
    Key key = values.lookup(op->getResult(0));
    if (!sumOf(key))
      return;
    b.setInsertionPoint(op);
    Value con = build(b, op->getLoc(), label, key, captures);
    op->getResult(0).replaceAllUsesWith(con);
    op->erase();
  }

  // Rewrites the module as decided.
  void rewrite() {
    OpBuilder b(ctx);
    retype();
    declareSums(b);
    coerceCalls(b);
    coerceSinks(b);
    module.op.walk([&](idr::ConstantOp constant) {
      constant.setValueAttr(convert(constant.getValue(), values.lookup(constant.getResult())));
    });
    for (idr::ApplyOp apply : module.applies)
      rewrite(apply, b);
    module.op.walk([&](Operation *op) {
      if (auto closure = dyn_cast<idr::ClosureOp>(op))
        construct(b, op, closure.getCalleeAttr().getAttr(), closure.getCaptures());
      else if (auto suspend = dyn_cast<idr::SuspendOp>(op))
        construct(b, op, suspend.getCalleeAttr().getAttr(), suspend.getCaptures());
    });
  }
};

} // namespace idr::defunctionalize
