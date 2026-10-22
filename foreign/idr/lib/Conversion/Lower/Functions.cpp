// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The program's functions as LLVM's: idr.func becomes llvm.func, idr.call
// llvm.call and idr.return llvm.return, built directly, so what a
// function's row and record say reaches LLVM on the op LLVM reads, never
// through an intermediate function op with no slot for it.
//
// Phase 0 renames and builds every function serially: a function's type
// and name are what its callers' lowering reads. Phase 2's patterns then
// convert each body on its own.

#include "Lower.h"

#include "idr/Analysis/Effects.h"
#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Lifetimes.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Mangle.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/LLVMIR/LLVMAttrs.h"
#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/Builders.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// Each function's name, mangled under the program's prefix.
using Renames = DenseMap<StringAttr, StringAttr>;

// The facts of a pointer to a cell: never null (poison of one is the
// static cell `nothing`), aligned to a cell's start, its header readable.
SmallVector<NamedAttribute> cellFacts(Builder &b, unsigned headerBytes) {
  return {b.getNamedAttr(LLVM::LLVMDialect::getNonNullAttrName(), b.getUnitAttr()),
          b.getNamedAttr(LLVM::LLVMDialect::getAlignAttrName(),
                         b.getI64IntegerAttr(cellAlignment())),
          b.getNamedAttr(LLVM::LLVMDialect::getDereferenceableAttrName(),
                         b.getI64IntegerAttr(headerBytes))};
}

// The facts of the first component of a value of `type`, laid out as
// `components`, which the types say and the LLVM types no longer do: a
// cell's pointer; the pointer to memory its holder alone reaches (an
// exclusive counted cell, a quantity-1 buffer's cell), which nothing else
// the call reaches aliases; an in-place sum's tag, below its number of
// constructors. No other component has any.
SmallVector<NamedAttribute> componentFacts(Type type, ArrayRef<Type> components,
                                           const Layouts &layouts, Builder &b,
                                           unsigned headerBytes) {
  SmallVector<NamedAttribute> facts;
  if (isCellPointer(type))
    facts = cellFacts(b, headerBytes);
  if (admitsWrite(type) && isa<LLVM::LLVMPointerType>(components.front()))
    facts.push_back(b.getNamedAttr(LLVM::LLVMDialect::getNoAliasAttrName(), b.getUnitAttr()));
  if (!facts.empty())
    return facts;
  auto data = dyn_cast<DataType>(unrestricted(type));
  if (!data || data.layout() != Layout::InPlace)
    return {};
  std::optional<IntegerType> tag = layouts.sum(data).tag;
  if (!tag)
    return {};
  unsigned width = tag->getWidth();
  uint64_t count = data.declaredCount();
  // A tag type its constructors fill has no range to state.
  if (count >= (uint64_t{1} << width))
    return {};
  return {b.getNamedAttr(
      LLVM::LLVMDialect::getRangeAttrName(),
      LLVM::ConstantRangeAttr::get(b.getContext(), width, 0, static_cast<int64_t>(count)))};
}

// Whether `fn` writes through a parameter its record names: one that
// admits a write part and is not listed untouched.
ParameterWrites writesOf(FuncOp fn) {
  ParameterParts parts(fn.getArgumentTypes());
  size_t untouched = 0;
  if (DenseI32ArrayAttr listed = fn.getUntouchedAttr())
    untouched = listed.size();
  return parts.writable() > untouched ? ParameterWrites::Some : ParameterWrites::None;
}

} // namespace

// A view is no value, so once each call gives a view where its callee asks
// one, the call's lowering reads what passes from its own operands' kinds
// alone.
void viewsWhereAsked(ProgramOp program) {
  SymbolTable symbols(program);
  MLIRContext *ctx = program.getContext();
  Type view = LifetimeType::get(ctx, LifetimeKind::view());
  program.walk([&](CallOp call) {
    auto callee = symbols.lookup<FuncOp>(call.getCalleeAttr().getAttr());
    OpBuilder b(call);
    for (auto [operand, param] : llvm::zip_equal(call->getOpOperands(), callee.getArgumentTypes())) {
      auto given = dyn_cast<LifetimeType>(operand.get().getType());
      auto asked = dyn_cast<LifetimeType>(param);
      if (!given || !asked || !asked.getKind().isView() || given.getKind().isView())
        continue;
      operand.set(LifetimeForgetOp::create(b, call.getLoc(), view, operand.get()));
    }
  });
}

namespace {

// Every use of a function's name, whatever op holds it, names it mangled.
// Types are left as they are: a family's labels name functions only for
// readers of the program, and no type survives the lowering.
Renames rename(ProgramOp program) {
  MLIRContext *ctx = program.getContext();
  Renames mangled;
  for (auto fn : program->getRegion(0).getOps<FuncOp>())
    mangled[fn.getSymNameAttr()] = StringAttr::get(ctx, mangleProgramSymbol(fn.getSymName()));
  AttrTypeReplacer replacer;
  replacer.addReplacement([&](FlatSymbolRefAttr ref) -> std::optional<Attribute> {
    StringAttr to = mangled.lookup(ref.getAttr());
    return to ? std::optional<Attribute>(FlatSymbolRefAttr::get(to)) : std::nullopt;
  });
  replacer.addReplacement(
      [](Type type) { return std::make_optional(std::make_pair(type, WalkResult::skip())); });
  replacer.recursivelyReplaceElementsIn(program, /*replaceAttrs=*/true, /*replaceLocs=*/false,
                                        /*replaceTypes=*/false);
  return mangled;
}

// The entry block's arguments of a function moved into its llvm.func,
// converted to their components: the one place a function's parameters
// take their lowered types.
struct LowerEntryBlock : OpConversionPattern<LLVM::LLVMFuncOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(LLVM::LLVMFuncOp fn, OpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Block &entry = fn.getBody().front();
    TypeConverter::SignatureConversion conversion(entry.getNumArguments());
    if (failed(getTypeConverter()->convertSignatureArgs(entry.getArgumentTypes(), conversion)))
      return rewriter.notifyMatchFailure(fn, "a parameter's type does not convert");
    rewriter.applySignatureConversion(&entry, conversion, getTypeConverter());
    return success();
  }
};

// A call of the program, under tailcc, as every function of the program is,
// a call in tail position musttail: LLVM makes it a jump or fails to
// compile, never silently a call. Each cursor it passes goes in as the
// cursor its slot holds and comes back as one more result, which the slot
// then holds, or, from a tail call, which is its caller's return. A call
// whose result fills a field of cells built before it is a loop by now.
struct LowerCall : IdrPattern<CallOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CallOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    MLIRContext *ctx = getContext();
    Type ptr = ptrType(ctx);
    SmallVector<Value> args, slots;
    for (auto [operand, converted] : llvm::zip_equal(op.getArgs(), adaptor.getArgs())) {
      if (!lifetimes::isCursor(operand.getType())) {
        llvm::append_range(args, converted);
        continue;
      }
      Value slot = converted.front();
      slots.push_back(slot);
      args.push_back(LLVM::LoadOp::create(rewriter, loc, ptr, slot));
    }
    SmallVector<SmallVector<Type>> resultTypes(op->getNumResults());
    SmallVector<Type> flat;
    for (auto [type, converted] : llvm::zip_equal(op->getResultTypes(), resultTypes)) {
      if (failed(getTypeConverter()->convertType(type, converted)))
        return rewriter.notifyMatchFailure(op, "a result's type does not convert");
      llvm::append_range(flat, converted);
    }
    flat.append(slots.size(), ptr);
    Type result = flat.empty()        ? LLVM::LLVMVoidType::get(ctx)
                  : flat.size() == 1 ? flat.front()
                                     : LLVM::LLVMStructType::getLiteral(ctx, flat);
    SmallVector<Type> params = llvm::map_to_vector(args, [](Value arg) { return arg.getType(); });
    auto call = LLVM::CallOp::create(rewriter, loc, LLVM::LLVMFunctionType::get(result, params),
                                     op.getCalleeAttr(), args);
    call.setCConv(LLVM::cconv::CConv::Tail);
    TailKind tail = op.getTailKind();
    if (tail == TailKind::tail)
      call.setTailCallKind(LLVM::tailcallkind::TailCallKind::MustTail);
    // The call's components, one by one out of the struct LLVM returns.
    SmallVector<Value> given;
    if (flat.size() == 1)
      given.push_back(call.getResult());
    else
      for (unsigned index = 0; index < flat.size(); ++index)
        given.push_back(LLVM::ExtractValueOp::create(rewriter, loc, call.getResult(),
                                                     ArrayRef<int64_t>{index}));
    ArrayRef<Value> rest = given;
    SmallVector<SmallVector<Value>> results;
    for (ArrayRef<Type> converted : resultTypes) {
      results.push_back(SmallVector<Value>(rest.take_front(converted.size())));
      rest = rest.drop_front(converted.size());
    }
    // A tail call's cursors come back as its caller's own results, which
    // the call gives as its caller's return: nothing follows it to keep them.
    if (tail != TailKind::tail)
      for (auto [slot, cursor] : llvm::zip_equal(slots, rest))
        LLVM::StoreOp::create(rewriter, loc, cursor, slot);
    rewriter.replaceOpWithMultiple(op, std::move(results));
    return success();
  }
};

// A return gives its values' components, and after them the cursor each
// cursor parameter's slot holds, which phase 1 read before the return: one
// value, or a literal struct of them all.
struct LowerReturn : IdrPattern<ReturnOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ReturnOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    SmallVector<Value> flat;
    for (ValueRange converted : adaptor.getOperands())
      llvm::append_range(flat, converted);
    if (flat.size() <= 1) {
      rewriter.replaceOpWithNewOp<LLVM::ReturnOp>(op, flat);
      return success();
    }
    SmallVector<Type> types = llvm::map_to_vector(flat, [](Value v) { return v.getType(); });
    auto structType = LLVM::LLVMStructType::getLiteral(getContext(), types);
    Value packed = LLVM::PoisonOp::create(rewriter, loc, structType);
    for (auto [index, value] : llvm::enumerate(flat))
      packed = LLVM::InsertValueOp::create(rewriter, loc, packed, value,
                                           ArrayRef<int64_t>{static_cast<int64_t>(index)});
    rewriter.replaceOpWithNewOp<LLVM::ReturnOp>(op, packed);
    return success();
  }
};

} // namespace

LLVM::LLVMFunctionType functionType(FunctionType type, const TypeConverter &converter) {
  MLIRContext *ctx = type.getContext();
  SmallVector<Type> params, results;
  for (Type input : type.getInputs())
    (void)converter.convertType(input, params);
  for (Type output : type.getResults())
    (void)converter.convertType(output, results);
  // A cursor goes in and comes back out: one more result each.
  for (Type input : type.getInputs())
    if (lifetimes::isCursor(input))
      results.push_back(ptrType(ctx));
  Type result = results.empty()        ? LLVM::LLVMVoidType::get(ctx)
                : results.size() == 1 ? results.front()
                                      : LLVM::LLVMStructType::getLiteral(ctx, results);
  return LLVM::LLVMFunctionType::get(result, params);
}

SmallVector<LLVM::LLVMFuncOp> lowerSignatures(ProgramOp program, const TypeConverter &converter,
                                              const Layouts &layouts) {
  Renames mangled = rename(program);
  unsigned headerBytes = HeaderLayout::of(layouts, program.getContext()).bytes;
  SmallVector<LLVM::LLVMFuncOp> lowered;
  for (auto fn : llvm::make_early_inc_range(program->getRegion(0).getOps<FuncOp>())) {
    FunctionType type = fn.getFunctionType();
    OpBuilder b(fn);
    // Every function of the program is reached from the module alone (the
    // entry calls the root from a body of C's convention), so every one
    // takes tailcc and is private.
    auto made = LLVM::LLVMFuncOp::create(b, fn.getLoc(), mangled.at(fn.getSymNameAttr()).getValue(),
                                         functionType(type, converter), LLVM::Linkage::Private,
                                         /*dsoLocal=*/true, LLVM::cconv::CConv::Tail);
    tellFunction(made, fn.getRow(), writesOf(fn));
    unsigned position = 0;
    for (Type input : type.getInputs()) {
      SmallVector<Type> components;
      (void)converter.convertType(input, components);
      if (!components.empty())
        for (const NamedAttribute &fact :
             componentFacts(input, components, layouts, b, headerBytes))
          made.setArgAttr(position, fact.getName(), fact.getValue());
      position += static_cast<unsigned>(components.size());
    }
    // A result of several components is one struct in LLVM, which takes no
    // such facts; a cell pointer is one component.
    if (type.getNumResults() == 1 && isCellPointer(type.getResult(0)) &&
        llvm::none_of(type.getInputs(), [](Type input) { return lifetimes::isCursor(input); }))
      for (const NamedAttribute &fact : cellFacts(b, headerBytes))
        made.setResultAttr(0, fact.getName(), fact.getValue());
    made.getBody().takeBody(fn.getBody());
    fn.erase();
    lowered.push_back(made);
  }
  // The program's root names its function by the mangled name already.
  return lowered;
}

void populateFunctionPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                              const Layouts &layouts, Runtime &runtime) {
  MLIRContext *ctx = patterns.getContext();
  patterns.add<LowerEntryBlock>(converter, ctx);
  patterns.add<LowerCall, LowerReturn>(converter, ctx, layouts, runtime);
}

} // namespace idr::conversion
