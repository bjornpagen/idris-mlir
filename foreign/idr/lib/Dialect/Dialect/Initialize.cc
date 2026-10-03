// The idr dialect's generated definition: its types, attributes and enums
// as TableGen defines them, the spellings of its types (the generated
// parser and printer are local to the unit that holds the definitions), and
// what the dialect registers when it is initialized: its types, attributes
// and ops, the inliner's rules, and the aliases of its large constants.
// One unit, because registering a type needs its storage complete.

#include "idr/Idr.h"

#include "mlir/IR/DialectImplementation.h"
#include "mlir/Transforms/InliningUtils.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;
using namespace idr;

#include "idr/IdrDialect.cc.inc"
#include "idr/IdrEnums.cc.inc"

#define GET_ATTRDEF_CLASSES
#include "idr/IdrAttrs.cc.inc"

#define GET_TYPEDEF_CLASSES
#include "idr/IdrTypes.cc.inc"

// The spellings: !idr.lin<T> is (1, ·) of T, !idr.own<T> is (ω, own) of
// T, !idr.erased is (0, ·) of no carrier, !idr.world is (1, ·) of the
// world; any other grade is written out as !idr.q. The world's carrier is
// never written by itself.
Type IdrDialect::parseType(DialectAsmParser &parser) const {
  llvm::SMLoc loc = parser.getCurrentLocation();
  MLIRContext *ctx = parser.getContext();
  if (succeeded(parser.parseOptionalKeyword("lin"))) {
    Type value;
    if (parser.parseLess() || parser.parseType(value) || parser.parseGreater())
      return {};
    return QType::getChecked([&] { return parser.emitError(loc); }, ctx,
                             Grade{Quantity::One, Permission::None}, value);
  }
  if (succeeded(parser.parseOptionalKeyword("own"))) {
    Type value;
    if (parser.parseLess() || parser.parseType(value) || parser.parseGreater())
      return {};
    return QType::getChecked([&] { return parser.emitError(loc); }, ctx,
                             Grade{Quantity::Many, Permission::Own}, value);
  }
  if (succeeded(parser.parseOptionalKeyword("excl"))) {
    Type value;
    if (parser.parseLess() || parser.parseType(value) || parser.parseGreater())
      return {};
    return QType::getChecked([&] { return parser.emitError(loc); }, ctx,
                             Grade{Quantity::Many, Permission::Excl}, value);
  }
  if (succeeded(parser.parseOptionalKeyword("erased")))
    return erased(ctx);
  if (succeeded(parser.parseOptionalKeyword("world")))
    return world(ctx);
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
  if (auto q = dyn_cast<QType>(type)) {
    if (isWorld(q)) {
      printer << "world";
    } else if (isErased(q) && q.getGrade().permission == Permission::None) {
      printer << "erased";
    } else if (isLinear(q) && q.getGrade().permission == Permission::None) {
      printer << "lin<" << q.getValue() << '>';
    } else if (q.getGrade() == Grade{Quantity::Many, Permission::Own}) {
      printer << "own<" << q.getValue() << '>';
    } else if (q.getGrade() == Grade{Quantity::Many, Permission::Excl}) {
      printer << "excl<" << q.getValue() << '>';
    } else {
      printer << "q";
      q.print(printer);
    }
    return;
  }
  if (failed(generatedTypePrinter(type, printer)))
    llvm_unreachable("a type of the idr dialect");
}

namespace {

// The generated lists of the dialect's types, attributes and ops, taken
// here as types: a generated file is included before the import below, and
// an include after an import can clash with the imported module's copy of
// the headers it reaches.
template <typename... Ts> struct List {};

using TypeList = List<
#define GET_TYPEDEF_LIST
#include "idr/IdrTypes.cc.inc"
    >;
using AttrList = List<
#define GET_ATTRDEF_LIST
#include "idr/IdrAttrs.cc.inc"
    >;
using OpList = List<
#define GET_OP_LIST
#include "idr/IdrOps.cc.inc"
    >;

} // namespace

import idr.ops;
import idr.sharing;

void IdrDialect::initialize() {
  [this]<typename... Ts>(List<Ts...>) { addTypes<Ts...>(); }(TypeList{});
  [this]<typename... Ts>(List<Ts...>) { addAttributes<Ts...>(); }(AttrList{});
  [this]<typename... Ts>(List<Ts...>) { addOperations<Ts...>(); }(OpList{});
  ops::addInlinerInterface(*this);
  sharing::addSharingInterfaces(*this);
}
