// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect's generated definition: its types, attributes and enums
// as TableGen defines them, the spellings of its types (the generated
// parser and printer are local to the unit that holds the definitions), its
// constants as folding materializes them, upstream's patterns it adds to
// every op's, and what it registers when it is initialized. One unit,
// because registering a type needs its storage complete.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Func.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlow.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/MemRef/Transforms/Transforms.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;
using namespace idr;

#include "idr/IR/IdrDialect.cpp.inc"
#include "idr/IR/IdrEnums.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "idr/IR/IdrAttrs.cpp.inc"

#define GET_TYPEDEF_CLASSES
#include "idr/IR/IdrTypes.cpp.inc"

namespace {

// The world, written whole: a !idr.q of the world's carrier, which is only
// ever at (one, plain).
bool isGradedWorld(Type type) { return isa<QType>(type) && isWorld(type); }

// The dialect's spellings of a value at a grade, read and written from this
// one table: a whole type, or a grade over any value. Any other grade is
// the generated `!idr.q<quantity, permission, value>`, as is every grade
// when written out; the world's carrier alone is `!idr.world_carrier`. The
// wholes come first: the world is (one, plain) too.
struct Whole {
  StringRef keyword;
  Type (*make)(MLIRContext *);
  bool (*is)(Type);
};
constexpr Whole wholes[] = {{"world", idr::world, isGradedWorld}};

struct Over {
  StringRef keyword;
  Grade grade;
};
constexpr Over overs[] = {{"lin", {Quantity::One, Permission::Plain}},
                          {"own", {Quantity::Many, Permission::Own}},
                          {"excl", {Quantity::Many, Permission::Excl}}};

} // namespace

Type IdrDialect::parseType(DialectAsmParser &parser) const {
  llvm::SMLoc loc = parser.getCurrentLocation();
  MLIRContext *ctx = parser.getContext();
  for (const Whole &whole : wholes)
    if (succeeded(parser.parseOptionalKeyword(whole.keyword)))
      return whole.make(ctx);
  for (const Over &over : overs)
    if (succeeded(parser.parseOptionalKeyword(over.keyword))) {
      Type value;
      if (parser.parseLess() || parser.parseType(value) || parser.parseGreater())
        return {};
      return QType::getChecked([&] { return parser.emitError(loc); }, ctx, over.grade, value);
    }
  // The generated parser reads the mnemonic itself.
  StringRef mnemonic;
  Type type;
  OptionalParseResult result = generatedTypeParser(parser, &mnemonic, type);
  if (result.has_value())
    return type;
  parser.emitError(loc) << "unknown type `" << mnemonic << "` in dialect `idr`";
  return {};
}

void IdrDialect::printType(Type type, DialectAsmPrinter &printer) const {
  for (const Whole &whole : wholes)
    if (whole.is(type)) {
      printer << whole.keyword;
      return;
    }
  if (auto q = dyn_cast<QType>(type))
    for (const Over &over : overs)
      if (q.getGrade() == over.grade) {
        printer << over.keyword << '<' << q.getValue() << '>';
        return;
      }
  if (failed(generatedTypePrinter(type, printer)))
    llvm_unreachable("a type of the idr dialect");
}

// idr.constant for the dialect's values and strings, and
// arith.constant for scalars.
Operation *IdrDialect::materializeConstant(OpBuilder &builder, Attribute value,
                                           Type type, Location loc) {
  if (ConstantOp::isBuildableWith(value, type))
    return ConstantOp::create(builder, loc, type, value);
  if (arith::ConstantOp::isBuildableWith(value, type))
    return arith::ConstantOp::create(builder, loc, type, cast<TypedAttr>(value));
  return nullptr;
}

// The dimension of an array, `memref.dim` of an `idr.array.new`, is the
// size the array was made with: upstream's resolution of a dimension
// through ReifyRankedShapedTypeOpInterface, which idr.array.new
// implements, as a canonicalization.
void IdrDialect::getCanonicalizationPatterns(RewritePatternSet &results) const {
  memref::populateResolveRankedShapedTypeResultDimsPatterns(results);
}

void IdrDialect::initialize() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "idr/IR/IdrTypes.cpp.inc"
      >();
  addAttributes<
#define GET_ATTRDEF_LIST
#include "idr/IR/IdrAttrs.cpp.inc"
      >();
  addOperations<
#define GET_OP_LIST
#include "idr/IR/IdrOps.cpp.inc"
      >();
  addInlinerInterface(*this);
  detail::addAsmInterface(*this);
}
