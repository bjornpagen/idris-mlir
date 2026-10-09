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

namespace {

// The dialect's spellings of a value at a grade, read and written from this
// one table: a whole type, or a grade over any value. Any other grade is
// the generated `!idr.q<quantity, permission, value>`, as is every grade
// when written out; the world's carrier alone is `!idr.world_carrier`. The
// wholes come first: the world is (one, plain) too.
struct Whole {
  StringRef keyword;
  Type (*make)(MLIRContext *);
};
constexpr Whole wholes[] = {{"erased", idr::erased}, {"world", idr::world}};

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
    if (type == whole.make(getContext())) {
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
