// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// upstream/99-function-interface-edits, checked on the pinned MLIR: the four
// edits of a function's signature reach an operation's own, through a
// FunctionOpInterface handle and from the single-item forms. The operation
// is this program's: a function that keeps a tag per argument and per
// result, facts kept by position as idr.func keeps its own, which its
// overrides of the four edits move with the signature, an inserted position
// tagged -1. It is defined here because no operation of MLIR's own
// libraries overrides an edit, and the test dialect's, which the patch adds
// one to, is not in the pinned tools. Each edit through the handle, and each
// single-item form through the handle and through the operation, leaves
// the signature and the tags where the operation's own edit puts them. At
// the unpatched pin the handle runs the interface's copy and the single
// forms the trait's, so the signature changes and the tags stay. Prints
// `ok` when every edit holds, and what each left otherwise.
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/raw_ostream.h"

#include <cstdint>

using namespace mlir;

namespace edits {

constexpr llvm::StringLiteral functionTypeName = "function_type";
constexpr llvm::StringLiteral argAttrsName = "arg_attrs";
constexpr llvm::StringLiteral resAttrsName = "res_attrs";
constexpr llvm::StringLiteral argTagsName = "arg_tags";
constexpr llvm::StringLiteral resTagsName = "res_tags";

// `tags` with -1 inserted before each old position the sorted `indices`
// names, in their order.
llvm::SmallVector<std::int64_t> inserted(llvm::ArrayRef<std::int64_t> tags,
                                         llvm::ArrayRef<unsigned> indices) {
  llvm::SmallVector<std::int64_t> result;
  const unsigned *next = indices.begin();
  for (unsigned at = 0; at <= tags.size(); ++at) {
    for (; next != indices.end() && *next == at; ++next)
      result.push_back(-1);
    if (at < tags.size())
      result.push_back(tags[at]);
  }
  return result;
}

// `tags` without the positions `gone` sets.
llvm::SmallVector<std::int64_t> erased(llvm::ArrayRef<std::int64_t> tags,
                                       const llvm::BitVector &gone) {
  llvm::SmallVector<std::int64_t> result;
  for (unsigned at = 0; at < tags.size(); ++at)
    if (!gone.test(at))
      result.push_back(tags[at]);
  return result;
}

// A function whose own edits keep a tag per argument and per result in step
// with its signature. It has no body: an edit's effect on the entry block is
// upstream's, the same for every function.
class PositionalFunc
    : public Op<PositionalFunc, OpTrait::ZeroOperands, OpTrait::ZeroResults,
                OpTrait::ZeroSuccessors, OpTrait::OneRegion, SymbolOpInterface::Trait,
                ArgAndResultAttrsOpInterface::Trait, CallableOpInterface::Trait,
                FunctionOpInterface::Trait> {
public:
  using Op::Op;
  // The edits the interface gives every function, which the overrides
  // extend.
  using Upstream = FunctionOpInterface::Trait<PositionalFunc>;

  static StringRef getOperationName() { return "edits.func"; }
  static ArrayRef<StringRef> getAttributeNames() { return {}; }

  llvm::ArrayRef<std::int64_t> argTags() { return tags(argTagsName); }
  llvm::ArrayRef<std::int64_t> resTags() { return tags(resTagsName); }

  // Symbol.
  StringAttr getNameAttr() {
    return (*this)->getAttrOfType<StringAttr>(SymbolTable::getSymbolAttrName());
  }
  SymbolTable::Visibility getVisibility() {
    return SymbolTable::getSymbolVisibility(getOperation());
  }
  void setVisibility(SymbolTable::Visibility visibility) {
    SymbolTable::setSymbolVisibility(getOperation(), visibility);
  }

  // Argument and result attributes.
  ArrayAttr getArgAttrsAttr() { return (*this)->getAttrOfType<ArrayAttr>(argAttrsName); }
  ArrayAttr getResAttrsAttr() { return (*this)->getAttrOfType<ArrayAttr>(resAttrsName); }
  void setArgAttrsAttr(ArrayAttr attrs) { (*this)->setAttr(argAttrsName, attrs); }
  void setResAttrsAttr(ArrayAttr attrs) { (*this)->setAttr(resAttrsName, attrs); }
  Attribute removeArgAttrsAttr() { return (*this)->removeAttr(argAttrsName); }
  Attribute removeResAttrsAttr() { return (*this)->removeAttr(resAttrsName); }

  // Callable.
  Region *getCallableRegion() { return isExternal() ? nullptr : &(*this)->getRegion(0); }
  ArrayRef<Type> getArgumentTypes() { return getFunctionType().getInputs(); }
  ArrayRef<Type> getResultTypes() { return getFunctionType().getResults(); }

  // Function.
  FunctionType getFunctionType() {
    return cast<FunctionType>((*this)->getAttrOfType<TypeAttr>(functionTypeName).getValue());
  }
  void setFunctionTypeAttr(TypeAttr type) { (*this)->setAttr(functionTypeName, type); }

  // The four edits, each moving the tags as it moves the signature.
  LogicalResult insertArguments(ArrayRef<unsigned> argIndices, TypeRange argTypes,
                                ArrayRef<DictionaryAttr> argAttrs, ArrayRef<Location> argLocs) {
    llvm::SmallVector<std::int64_t> moved = inserted(argTags(), argIndices);
    if (failed(Upstream::insertArguments(argIndices, argTypes, argAttrs, argLocs)))
      return failure();
    setTags(argTagsName, moved);
    return success();
  }
  LogicalResult insertResults(ArrayRef<unsigned> resultIndices, TypeRange resultTypes,
                              ArrayRef<DictionaryAttr> resultAttrs) {
    llvm::SmallVector<std::int64_t> moved = inserted(resTags(), resultIndices);
    if (failed(Upstream::insertResults(resultIndices, resultTypes, resultAttrs)))
      return failure();
    setTags(resTagsName, moved);
    return success();
  }
  LogicalResult eraseArguments(const llvm::BitVector &argIndices) {
    llvm::SmallVector<std::int64_t> moved = erased(argTags(), argIndices);
    if (failed(Upstream::eraseArguments(argIndices)))
      return failure();
    setTags(argTagsName, moved);
    return success();
  }
  LogicalResult eraseResults(const llvm::BitVector &resultIndices) {
    llvm::SmallVector<std::int64_t> moved = erased(resTags(), resultIndices);
    if (failed(Upstream::eraseResults(resultIndices)))
      return failure();
    setTags(resTagsName, moved);
    return success();
  }

private:
  llvm::ArrayRef<std::int64_t> tags(llvm::StringRef name) {
    return (*this)->getAttrOfType<DenseI64ArrayAttr>(name).asArrayRef();
  }
  void setTags(llvm::StringRef name, llvm::ArrayRef<std::int64_t> tags) {
    (*this)->setAttr(name, DenseI64ArrayAttr::get(getContext(), tags));
  }
};

class EditsDialect : public Dialect {
public:
  explicit EditsDialect(MLIRContext *context)
      : Dialect(getDialectNamespace(), context, TypeID::get<EditsDialect>()) {
    addOperations<PositionalFunc>();
  }
  static StringRef getDialectNamespace() { return "edits"; }
};

} // namespace edits

int main() {
  using edits::PositionalFunc;
  DialectRegistry registry;
  registry.insert<edits::EditsDialect>();
  MLIRContext context(registry);
  context.loadAllAvailableDialects();
  OpBuilder b(&context);
  Location loc = b.getUnknownLoc();
  OwningOpRef<ModuleOp> module = ModuleOp::create(loc);
  b.setInsertionPointToEnd(module->getBody());
  Type f32 = b.getF32Type(), i32 = b.getI32Type();
  DictionaryAttr none = b.getDictionaryAttr({});

  auto function = [&](StringRef name, ArrayRef<Type> inputs, ArrayRef<Type> results,
                      ArrayRef<std::int64_t> argTags, ArrayRef<std::int64_t> resTags) {
    OperationState state(loc, PositionalFunc::getOperationName());
    state.addAttribute(SymbolTable::getSymbolAttrName(), b.getStringAttr(name));
    state.addAttribute(edits::functionTypeName, TypeAttr::get(b.getFunctionType(inputs, results)));
    state.addAttribute(edits::argTagsName, b.getDenseI64ArrayAttr(argTags));
    state.addAttribute(edits::resTagsName, b.getDenseI64ArrayAttr(resTags));
    state.addRegion();
    return cast<PositionalFunc>(b.create(state));
  };
  auto handle = [](PositionalFunc fn) { return cast<FunctionOpInterface>(fn.getOperation()); };
  auto positions = [](llvm::BitVector set, ArrayRef<unsigned> at) {
    for (unsigned each : at)
      set.set(each);
    return set;
  };

  bool held = true;
  auto expect = [&](StringRef edit, PositionalFunc fn, ArrayRef<Type> inputs,
                    ArrayRef<Type> results, ArrayRef<std::int64_t> argTags,
                    ArrayRef<std::int64_t> resTags) {
    if (fn.getFunctionType() == b.getFunctionType(inputs, results) && fn.argTags() == argTags &&
        fn.resTags() == resTags)
      return;
    held = false;
    llvm::outs() << edit << ": " << fn.getFunctionType() << ", argument tags [";
    llvm::interleaveComma(fn.argTags(), llvm::outs());
    llvm::outs() << "], result tags [";
    llvm::interleaveComma(fn.resTags(), llvm::outs());
    llvm::outs() << "]\n";
  };

  // Each edit through the interface's handle.
  PositionalFunc insertArg = function("insert_arg", {f32, f32}, {}, {0, 1}, {});
  (void)handle(insertArg).insertArguments({1}, {i32}, {}, {loc});
  expect("insertArguments through the handle", insertArg, {f32, i32, f32}, {}, {0, -1, 1}, {});

  PositionalFunc insertResult = function("insert_result", {}, {f32}, {}, {0});
  (void)handle(insertResult).insertResults({1}, {i32}, {});
  expect("insertResults through the handle", insertResult, {}, {f32, i32}, {}, {0, -1});

  PositionalFunc eraseArg = function("erase_arg", {f32, i32, f32}, {}, {0, 1, 2}, {});
  (void)handle(eraseArg).eraseArguments(positions(llvm::BitVector(3), {1}));
  expect("eraseArguments through the handle", eraseArg, {f32, f32}, {}, {0, 2}, {});

  PositionalFunc eraseResult = function("erase_result", {}, {i32, f32}, {}, {0, 1});
  (void)handle(eraseResult).eraseResults(positions(llvm::BitVector(2), {0}));
  expect("eraseResults through the handle", eraseResult, {}, {f32}, {}, {1});

  // The single-item forms, through the handle and through the operation.
  PositionalFunc viaHandle = function("single_via_handle", {f32}, {f32}, {0}, {0});
  PositionalFunc viaOp = function("single_via_op", {f32}, {f32}, {0}, {0});
  (void)handle(viaHandle).insertArgument(0, i32, none, loc);
  (void)viaOp.insertArgument(0, i32, none, loc);
  expect("insertArgument through the handle", viaHandle, {i32, f32}, {f32}, {-1, 0}, {0});
  expect("insertArgument through the operation", viaOp, {i32, f32}, {f32}, {-1, 0}, {0});
  (void)handle(viaHandle).insertResult(1, i32, none);
  (void)viaOp.insertResult(1, i32, none);
  expect("insertResult through the handle", viaHandle, {i32, f32}, {f32, i32}, {-1, 0}, {0, -1});
  expect("insertResult through the operation", viaOp, {i32, f32}, {f32, i32}, {-1, 0}, {0, -1});
  (void)handle(viaHandle).eraseArgument(1);
  (void)viaOp.eraseArgument(1);
  expect("eraseArgument through the handle", viaHandle, {i32}, {f32, i32}, {-1}, {0, -1});
  expect("eraseArgument through the operation", viaOp, {i32}, {f32, i32}, {-1}, {0, -1});
  (void)handle(viaHandle).eraseResult(0);
  (void)viaOp.eraseResult(0);
  expect("eraseResult through the handle", viaHandle, {i32}, {i32}, {-1}, {-1});
  expect("eraseResult through the operation", viaOp, {i32}, {i32}, {-1}, {-1});

  if (held)
    llvm::outs() << "ok\n";
  return held ? 0 : 1;
}
