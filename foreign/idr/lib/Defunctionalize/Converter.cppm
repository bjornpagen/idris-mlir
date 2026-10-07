// idr.defunctionalize:converter: the rewriting of the module into sums.
module;
// assert is a macro, which no import carries.
#include <cassert>

export module idr.defunctionalize:converter;

import idr.mlir;
import idr.dialect;

import :closures;
import :decided;
import :labels;
import :slots;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::defunctionalize {

// The module rewritten as decided: slots retyped, sums declared, values
// coerced where they move between keys, constants and applies converted,
// and closures of converted keys made constructors.
struct Converter : Decided {
  using Decided::Decided;

  Type sumOf(const Key &key) {
    return isConverted(key) ? keys.lookup(key) : Type();
  }

  // The type of a slot of `key`: its sum, or the closure type unchanged.
  Type typeOf(const Key &key) {
    if (Type sum = sumOf(key))
      return sum;
    return key.first;
  }

  // The type of a slot of `key` whose type was `type`: its sum or closure
  // type, linear when `type` is.
  Type typeOf(Type type, const Key &key) {
    if (!key.first)
      return type;
    Type slot = typeOf(key);
    return idr::isLinear(type) ? idr::linear(slot) : slot;
  }

  // The types of the captures of `label` as a closure of `type`, as
  // converted.
  ArrayRef<Type> captureTypes(StringAttr label, idr::FnType type) {
    return module.function(label).getArgumentTypes().drop_back(arity(type));
  }

  // A suspension's value may be a closure. `was` is the function's result
  // type before retype, so the lazy type can follow it to the sum.
  llvm::DenseMap<StringAttr, Type> suspensionResults();
  Type adapt(Type type, const llvm::DenseMap<Type, Type> &next);
  void adaptLazy(const llvm::DenseMap<StringAttr, Type> &was);

  void retype() {
    for (func::FuncOp fn : module.op.getOps<func::FuncOp>()) {
      SmallVector<Type> inputs, outputs;
      for (auto [i, type] : llvm::enumerate(fn.getArgumentTypes()))
        inputs.push_back(typeOf(type, argument(fn, static_cast<unsigned>(i))));
      for (auto [i, type] : llvm::enumerate(fn.getResultTypes()))
        outputs.push_back(typeOf(type, result(fn, static_cast<unsigned>(i))));
      fn.setFunctionType(FunctionType::get(ctx, inputs, outputs));
    }
    for (auto &[value, key] : values)
      value.setType(typeOf(value.getType(), key));
    module.op.walk([&](idr::CtorOp ctor) {
      auto data = ctor->getParentOfType<idr::DataOp>().getSymNameAttr();
      SmallVector<Type> types;
      for (auto [i, type] : llvm::enumerate(ctor.getFieldTypes().getAsValueRange<TypeAttr>()))
        types.push_back(typeOf(type, fields.lookup({data, ctor.getSymNameAttr(), unsigned(i)})));
      ctor.setFieldTypesAttr(Builder(ctx).getTypeArrayAttr(types));
    });
  }

  void declareSums(OpBuilder &b) {
    b.setInsertionPointToStart(module.op.getBody());
    for (auto &[key, sum] : keys) {
      if (!sum)
        continue;
      auto data = idr::DataOp::create(b, module.op.getLoc(), idr::getSumName(sum).getAttr(),
                                      isa<idr::BoxType>(sum) ? b.getUnitAttr() : UnitAttr(),
                                      b.getUnitAttr());
      OpBuilder inner = OpBuilder::atBlockEnd(&data.getBody().emplaceBlock());
      for (auto label : key.second.getAsRange<StringAttr>()) {
        func::FuncOp fn = module.function(label);
        // The captures' types carry their quantities into the fields.
        ArrayRef<Type> types = captureTypes(label, key.first);
        idr::CtorOp::create(inner, fn.getLoc(), label, b.getTypeArrayAttr(types));
      }
    }
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
  // or poison for a value the analysis never reaches.
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
    if (isEmpty(from))
      return ub::PoisonOp::create(b, loc, typeOf(to));
    SmallVector<Attribute> cases;
    for (StringAttr label : from.second.getAsRange<StringAttr>())
      cases.push_back(FlatSymbolRefAttr::get(label));
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
    return match.getResult(0);
  }

  // The types a match on a closure sum of `type` binds the captures of
  // `label` at: the fields at the sum's grade.
  SmallVector<Type> boundCaptureTypes(StringAttr label, idr::FnType type, Type scrutinee) {
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

  // Constant `attr` in a slot of `slot`, with its closures of converted
  // keys as constructors.
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
    if (auto con = dyn_cast<idr::ConAttr>(attr)) {
      SmallVector<Attribute> parts;
      for (auto [i, value] : llvm::enumerate(con.getFields()))
        parts.push_back(convert(value, field(con.getCtor(), static_cast<unsigned>(i))));
      return idr::ConAttr::get(ctx, con.getCtor(), ArrayAttr::get(ctx, parts));
    }
    return attr;
  }

  // An apply of a converted key becomes a match over its labels, each
  // region calling its label with the captures, then the arguments. An
  // apply of a closure gets closures.
  void rewrite(idr::ApplyOp apply, OpBuilder &b) {
    // The callee is retyped by now, so not getCallee(), which casts it.
    Value closure = apply->getOperand(0);
    Key callee = values.lookup(closure);
    ArrayRef<Type> inputs = callee.first.getInputs();
    b.setInsertionPoint(apply);
    if (!isConverted(callee)) {
      for (auto [i, type] : llvm::enumerate(inputs)) {
        if (!isClosureType(type))
          continue;
        OpOperand &arg = apply.getArgsMutable()[static_cast<unsigned>(i)];
        arg.set(coerce(b, apply.getLoc(), arg.get(), values.lookup(arg.get()), unknown(type)));
      }
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
        operands.push_back(isClosureType(inputs[i])
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

  void run() {
    keyFields();
    keyFunctions();
    keyValues();
    order();
    connect();
    decide();

    OpBuilder b(ctx);
    llvm::DenseMap<StringAttr, Type> was = suspensionResults();
    retype();
    adaptLazy(was);
    declareSums(b);
    coerceCalls(b);
    coerceSinks(b);
    module.op.walk([&](idr::ConstantOp constant) {
      constant.setValueAttr(convert(constant.getValue(), values.lookup(constant.getResult())));
    });
    for (idr::ApplyOp apply : module.applies)
      rewrite(apply, b);
    module.op.walk([&](idr::ClosureOp closure) {
      Key key = values.lookup(closure->getResult(0));
      if (!sumOf(key))
        return;
      b.setInsertionPoint(closure);
      Value con = build(b, closure.getLoc(), closure.getCalleeAttr().getAttr(), key,
                        closure.getCaptures());
      closure.replaceAllUsesWith(con);
      closure.erase();
    });
  }
};

} // namespace idr::defunctionalize
