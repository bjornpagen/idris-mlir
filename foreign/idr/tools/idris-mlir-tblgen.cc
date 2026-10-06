// idris-mlir-tblgen: mlir-tblgen with one more generator,
// -gen-idris-dialect, which writes a dialect's vocabulary for the Idris side
// from the dialect's ODS: a builder of each op, over its operands,
// attributes, regions and results; the enums its attributes take; the
// dialect's types and attributes whose syntax ODS declares; and its
// discardable attributes. Emit writes MLIR only through these modules
// (compiler/src/IdrisMLIR/Dialect/), so what an op is, and how each of its
// parts is spelled, is said once: in ODS.
//
// It is a TableGen backend rather than a program over a dump of the records
// because it then reads ODS through mlir::tblgen (Operator, Attribute,
// AttrOrTypeDef, EnumInfo), the reading the dialects' own C++ is generated
// from, so the two sides cannot take one op differently; and the pinned
// toolchain installs those libraries and mlir-tblgen, not llvm-tblgen.
//
// Ops are written in MLIR's generic form. An op's custom syntax is C++ (its
// custom directives, the parsers of idr.match and idr.constant), which
// nothing generated from ODS can know, while the generic form is every
// op's and is said by ODS alone: the name, the operands, the inherent
// attributes as properties, the regions, the discardable attributes and the
// types. A type or an attribute has no generic form, so only those whose
// syntax ODS declares are generated; one whose syntax is C++ is left out,
// with the reason, at the end of the module.

#include "mlir/TableGen/AttrOrTypeDef.h"
#include "mlir/TableGen/Attribute.h"
#include "mlir/TableGen/Dialect.h"
#include "mlir/TableGen/EnumInfo.h"
#include "mlir/TableGen/GenInfo.h"
#include "mlir/TableGen/Operator.h"
#include "mlir/TableGen/Type.h"
#include "mlir/Tools/mlir-tblgen/MlirTblgenMain.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/FormatVariadic.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/TableGen/Error.h"
#include "llvm/TableGen/Record.h"

#include <map>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace {

using llvm::StringRef;
using mlir::tblgen::AttrOrTypeDef;
using mlir::tblgen::AttrOrTypeParameter;
using mlir::tblgen::EnumInfo;
using mlir::tblgen::NamedAttribute;
using mlir::tblgen::NamedProperty;
using mlir::tblgen::NamedRegion;
using mlir::tblgen::NamedTypeConstraint;
using mlir::tblgen::Operator;

llvm::cl::opt<std::string> dialectName("idris-dialect",
                                       llvm::cl::desc("The dialect -gen-idris-dialect writes"));
llvm::cl::opt<std::string> moduleName("idris-module",
                                      llvm::cl::desc("The Idris module -gen-idris-dialect writes"));

//===----------------------------------------------------------------------===//
// Idris names and text
//===----------------------------------------------------------------------===//

// Idris's reserved words, which no parameter may be named.
bool isReserved(StringRef word) {
  static constexpr StringRef words[] = {
      "data",      "module",         "where",    "let",       "in",        "do",
      "record",    "auto",           "default",  "implicit",  "failing",   "mutual",
      "namespace", "parameters",     "with",     "proof",     "impossible", "case",
      "of",        "if",             "then",     "else",      "forall",    "rewrite",
      "typebind",  "autobind",       "using",    "interface", "implementation",
      "open",      "import",         "public",   "export",    "private",   "infixl",
      "infixr",    "infix",          "prefix",   "total",     "partial",   "covering"};
  return llvm::is_contained(words, word);
}

// `str.append`, `put_str` as `strAppend`, `putStr`; with `upper`, the first
// letter raised too, as a constructor's must be.
std::string camel(StringRef name, bool upper) {
  std::string out;
  bool raise = upper;
  for (char c : name) {
    if (c == '.' || c == '_') {
      raise = !out.empty() || upper;
      continue;
    }
    if (out.empty())
      out += upper ? llvm::toUpper(c) : llvm::toLower(c);
    else
      out += raise ? llvm::toUpper(c) : c;
    raise = false;
  }
  return out;
}

// The names a generated body uses unqualified, besides its parameters: a
// parameter of one of these names would hide it.
bool isUsedInBodies(StringRef name) {
  static constexpr StringRef names[] = {
      "concat",       "toList",      "length",     "map",           "show",
      "unitIf",       "attrIf",      "segmentSizes", "commaSeparated", "v",
      "unitAttr",     "boolAttr",    "integerAttr", "floatAttr",     "stringAttr",
      "flatSymbolRefAttr", "symbolRefAttr", "typeAttr", "typeArrayAttr", "arrayAttr",
      "integerType",  "f64Type",     "indexType"};
  return llvm::is_contained(names, name);
}

// A parameter named after its ODS name, or after its kind and position
// when ODS gives it none.
std::string parameter(StringRef odsName, const llvm::Twine &unnamed) {
  std::string name = camel(odsName, false);
  if (name.empty())
    name = unnamed.str();
  if (isReserved(name) || isUsedInBodies(name))
    name += '\'';
  return name;
}

// An Idris string literal of `text`, which ODS keeps printable.
std::string literal(StringRef text) {
  std::string out = "\"";
  for (char c : text) {
    if (!llvm::isPrint(c))
      llvm::PrintFatalError("an unprintable character in `" + text + "`");
    if (c == '"' || c == '\\')
      out += '\\';
    out += c;
  }
  return out + "\"";
}

// A summary as one line of documentation.
std::string doc(StringRef text) {
  std::string line;
  for (char c : text.trim())
    line += (c == '\n' || c == '\r') ? ' ' : c;
  return line;
}

// What follows a name in its documentation: `: ` and the summary, if ODS
// gives one.
std::string summary(StringRef text) {
  std::string line = doc(text);
  return line.empty() ? "" : ": " + line;
}

// A section of a module: a heading over its text, if it has any.
void section(llvm::raw_ostream &os, StringRef heading, StringRef text) {
  if (text.empty())
    return;
  os << "------------------------------------------------------------------------------\n"
     << "-- " << heading << "\n"
     << "------------------------------------------------------------------------------\n\n"
     << text;
}

//===----------------------------------------------------------------------===//
// Values in Idris: builtin types and attributes
//===----------------------------------------------------------------------===//

// How the Idris side gives a value of some kind, and writes it: its Idris
// type, and the expression that makes its MLIR text from a value `{0}` of
// that type (IdrisMLIR.MLIR's builtin types and attributes).
struct Kind {
  std::string type;
  std::string text;
};

// The builtin type an ODS type constraint names when it is one exact type,
// as an expression of IdrisMLIR.MLIR.
std::optional<std::string> builtinType(const llvm::Record &type) {
  if (type.isSubClassOf("I"))
    return llvm::formatv("integerType {0}", type.getValueAsInt("bitwidth")).str();
  if (type.isSubClassOf("F") && type.getValueAsInt("bitwidth") == 64)
    return std::string("f64Type");
  if (type.getName() == "Index")
    return std::string("indexType");
  return std::nullopt;
}

// The enums the module defines, by their ODS records: written once each,
// before the ops and attributes that take them, with their values if an
// op takes one and their spellings if an attribute does.
struct Enum {
  const llvm::Record *def;
  bool values = false;
  bool spellings = false;
};
std::map<std::string, Enum> enums;

// The Idris name of an enum, and of its namespace.
std::string enumName(const EnumInfo &info) { return info.getEnumClassName().str(); }

// An enum stored as an integer attribute, which the generic form writes as
// its value: an op attribute of ODS's integer enums.
std::optional<Kind> integerEnum(const mlir::tblgen::Attribute &base) {
  EnumInfo info(&base.getDef());
  if (info.isBitEnum())
    return std::nullopt;
  const llvm::Record *storage = info.getBaseAttrClass();
  if (!storage || mlir::tblgen::Attribute(storage).getStorageType().trim() != "::mlir::IntegerAttr")
    return std::nullopt;
  std::string name = enumName(info);
  Enum &used = enums.try_emplace(name, Enum{&base.getDef()}).first->second;
  used.values = true;
  return Kind{name, llvm::formatv("integerAttr ({0}Value {{0}) (integerType {1})", camel(name, false),
                                  info.getBitwidth())
                        .str()};
}

// How an op attribute of this constraint is given, once what makes it
// optional is set apart: by the kind of attribute that stores it.
Kind attributeKind(const mlir::tblgen::Attribute &attr) {
  mlir::tblgen::Attribute base = attr.getBaseAttr();
  StringRef storage = base.getStorageType().trim();
  if (base.isEnumAttr())
    if (std::optional<Kind> kind = integerEnum(base))
      return *kind;
  if (storage == "::mlir::BoolAttr")
    return {"Bool", "boolAttr {0}"};
  if (storage == "::mlir::IntegerAttr")
    if (std::optional<mlir::tblgen::Type> type = base.getValueType())
      if (std::optional<std::string> builtin = builtinType(type->getDef()))
        return {"Integer", llvm::formatv("integerAttr {{0} ({0})", *builtin).str()};
  if (storage == "::mlir::FloatAttr")
    if (std::optional<mlir::tblgen::Type> type = base.getValueType())
      if (std::optional<std::string> builtin = builtinType(type->getDef()))
        return {"Double", llvm::formatv("floatAttr {{0} ({0})", *builtin).str()};
  if (storage == "::mlir::StringAttr")
    return {"String", "stringAttr {0}"};
  if (storage == "::mlir::FlatSymbolRefAttr")
    return {"String", "flatSymbolRefAttr {0}"};
  if (storage == "::mlir::SymbolRefAttr")
    return {"List String", "symbolRefAttr {0}"};
  if (storage == "::mlir::TypeAttr")
    return {"MlirType", "typeAttr {0}"};
  if (base.getAttrDefName() == "TypeArrayAttr")
    return {"List MlirType", "typeArrayAttr {0}"};
  if (storage == "::mlir::ArrayAttr")
    return {"List MlirAttr", "arrayAttr {0}"};
  // Any other kind (an interface, a dialect's attribute) is given as the
  // attribute its maker wrote.
  return {"MlirAttr", "{0}"};
}

//===----------------------------------------------------------------------===//
// Ops
//===----------------------------------------------------------------------===//

// One parameter of a builder: how it is bound (explicitly, or as an
// implicit argument with a default when ODS lets it be absent), its type,
// and the name the body uses.
struct Parameter {
  std::string name;
  std::string type;
  std::optional<std::string> fallback; // the default of an implicit argument
};

std::string binder(const Parameter &p) {
  if (p.fallback)
    return llvm::formatv("{{default {0} {1} : {2}}", *p.fallback, p.name, p.type).str();
  return llvm::formatv("({0} : {1})", p.name, p.type).str();
}

// The operand, region or result list of an op, as an expression: single
// ones in a list, variadic ones as given, optional ones as their list.
std::string listOf(const std::vector<std::pair<std::string, char>> &parts) {
  if (parts.size() == 1 && parts.front().second == '*')
    return parts.front().first;
  if (parts.size() == 1 && parts.front().second == '?')
    return "(toList " + parts.front().first + ")";
  if (llvm::all_of(parts, [](const auto &part) { return part.second == '1'; })) {
    std::string out = "[";
    llvm::interleave(
        parts, [&](const auto &part) { out += part.first; }, [&] { out += ", "; });
    return out + "]";
  }
  std::string out = "(concat [";
  llvm::interleave(
      parts,
      [&](const auto &part) {
        if (part.second == '1')
          out += "[" + part.first + "]";
        else if (part.second == '?')
          out += "toList " + part.first;
        else
          out += part.first;
      },
      [&] { out += ", "; });
  return out + "])";
}

// A list of attributes, as an expression: the entries always there in
// lists, each joined to the next by `++`, and those there only when given
// as the expression that has them or not.
std::string dictionaryOf(const std::vector<std::pair<std::string, bool>> &parts) {
  std::vector<std::string> pieces;
  std::string run;
  for (const auto &[text, always] : parts) {
    if (always) {
      run += (run.empty() ? "" : ", ") + text;
      continue;
    }
    if (!run.empty())
      pieces.push_back("[" + run + "]");
    run.clear();
    pieces.push_back(text);
  }
  if (!run.empty())
    pieces.push_back("[" + run + "]");
  if (pieces.empty())
    return "[]";
  if (pieces.size() == 1 && pieces.front().front() == '[')
    return pieces.front();
  return "(" + llvm::join(pieces, " ++ ") + ")";
}

// The function that makes an attribute's text from a value, from the
// expression that makes it from `{0}`.
std::string maker(const std::string &text) {
  StringRef pattern = text;
  if (pattern == "{0}")
    return "id";
  if (pattern.ends_with(" {0}") && !pattern.drop_back(4).contains(' '))
    return pattern.drop_back(4).str();
  return llvm::formatv("(\\v => {0})", llvm::formatv(text.c_str(), "v").str()).str();
}

// The number of values of each group, for an op whose variadic operands or
// results are told apart by a segment-size property.
std::string segments(const std::vector<std::pair<std::string, char>> &parts) {
  std::string out = "segmentSizes [";
  llvm::interleave(
      parts,
      [&](const auto &part) {
        if (part.second == '1')
          out += "1";
        else
          out += "length " + (part.second == '?' ? "(toList " + part.first + ")" : part.first);
      },
      [&] { out += ", "; });
  return out + "]";
}

char arity(const NamedTypeConstraint &value) {
  if (value.isVariadicOfVariadic())
    return '*';
  if (value.isOptional())
    return '?';
  return value.isVariadic() ? '*' : '1';
}

std::string valuesType(StringRef single, char arity) {
  if (arity == '1')
    return single.str();
  return (arity == '?' ? "Maybe " : "List ") + single.str();
}

void emitOp(const Operator &op, llvm::raw_ostream &os) {
  if (op.getNumSuccessors() != 0)
    llvm::PrintFatalError(op.getLoc(), "the Idris side writes no op with successors");
  // getOperationName returns a std::string by value: keep it alive while the
  // mnemonic and the literal below read it (a StringRef bound to the
  // temporary would dangle).
  std::string operationName = op.getOperationName();
  StringRef mnemonic = StringRef(operationName).drop_front(op.getDialectName().size() + 1);
  std::string name = camel(mnemonic, false) + "Op";

  std::vector<Parameter> implicits, explicits;
  std::vector<std::pair<std::string, char>> operands, results, regions;
  std::vector<std::pair<std::string, bool>> properties;
  for (int index = 0, e = op.getNumArgs(); index < e; ++index) {
    mlir::tblgen::Argument arg = op.getArg(index);
    if (const auto *operand = llvm::dyn_cast_if_present<NamedTypeConstraint *>(arg)) {
      if (operand->isVariadicOfVariadic())
        llvm::PrintFatalError(op.getLoc(), "the Idris side writes no variadic of variadics");
      std::string param = parameter(operand->name, "operand" + llvm::Twine(index));
      operands.emplace_back(param, arity(*operand));
      explicits.push_back({param, valuesType("Value", arity(*operand)), std::nullopt});
      continue;
    }
    const auto *attribute = llvm::dyn_cast_if_present<NamedAttribute *>(arg);
    if (!attribute) {
      // A property that is no attribute and has a default is a pass's own
      // claim (an access's in_bounds): the Idris side cannot make it, and
      // writes the op at its default.
      const auto *property = llvm::dyn_cast_if_present<NamedProperty *>(arg);
      if (property && property->prop.hasDefaultValue())
        continue;
      llvm::PrintFatalError(op.getLoc(), "the Idris side writes no property that is not an attribute");
    }
    if (attribute->attr.isDerivedAttr())
      continue;
    std::string param = parameter(attribute->name, "attribute" + llvm::Twine(index));
    std::string key = literal(attribute->name);
    if (attribute->attr.getBaseAttr().getStorageType().trim() == "::mlir::UnitAttr") {
      implicits.push_back({param, "Bool", std::string("False")});
      properties.emplace_back(llvm::formatv("unitIf {0} {1}", key, param).str(), false);
      continue;
    }
    Kind kind = attributeKind(attribute->attr);
    if (attribute->attr.isOptional() || attribute->attr.hasDefaultValue()) {
      bool simple = !StringRef(kind.type).contains(' ');
      implicits.push_back({param, simple ? "Maybe " + kind.type : "Maybe (" + kind.type + ")",
                           std::string("Nothing")});
      properties.emplace_back(
          llvm::formatv("attrIf {0} {1} {2}", key, maker(kind.text), param).str(), false);
    } else {
      explicits.push_back({param, kind.type, std::nullopt});
      properties.emplace_back(
          llvm::formatv("({0}, {1})", key, llvm::formatv(kind.text.c_str(), param).str()).str(),
          true);
    }
  }
  for (const auto &[index, region] : llvm::enumerate(op.getRegions())) {
    std::string param = parameter(region.name, "region" + llvm::Twine(index));
    regions.emplace_back(param, region.isVariadic() ? '*' : '1');
    explicits.push_back({param, region.isVariadic() ? "List Region" : "Region", std::nullopt});
  }
  for (const auto &[index, result] : llvm::enumerate(op.getResults())) {
    std::string param = parameter(result.name, "result" + llvm::Twine(index));
    results.emplace_back(param, arity(result));
    explicits.push_back({param, valuesType("MlirType", arity(result)), std::nullopt});
  }
  if (op.getTrait("::mlir::OpTrait::AttrSizedOperandSegments"))
    properties.emplace_back(
        llvm::formatv("(\"operandSegmentSizes\", {0})", segments(operands)).str(), true);
  if (op.getTrait("::mlir::OpTrait::AttrSizedResultSegments"))
    properties.emplace_back(
        llvm::formatv("(\"resultSegmentSizes\", {0})", segments(results)).str(), true);

  os << "||| `" << op.getOperationName() << "`" << summary(op.getSummary());
  os << "\nexport\n" << name << " : ";
  for (const Parameter &p : implicits)
    os << binder(p) << " -> ";
  for (const Parameter &p : explicits)
    os << binder(p) << " -> ";
  os << "Op\n" << name;
  for (const Parameter &p : explicits)
    os << ' ' << p.name;
  os << " =\n  MkOp " << literal(operationName) << ' ' << listOf(operands) << ' '
     << dictionaryOf(properties) << ' ' << listOf(regions) << " [] " << listOf(results)
     << "\n\n";
}

//===----------------------------------------------------------------------===//
// Types and attributes
//===----------------------------------------------------------------------===//

// How the value of a parameter of a type or an attribute is given and
// written in its declarative syntax, by the parameter's C++ type; nothing
// for a C++ type the Idris side has no value of.
std::optional<Kind> parameterKind(const AttrOrTypeParameter &param) {
  if (const auto *def = llvm::dyn_cast<llvm::DefInit>(param.getDef()))
    if (def->getDef()->isSubClassOf("EnumParameter")) {
      EnumInfo info(def->getDef()->getValueAsDef("enum"));
      if (info.isBitEnum())
        return std::nullopt;
      std::string name = enumName(info);
      Enum &used =
          enums.try_emplace(name, Enum{def->getDef()->getValueAsDef("enum")}).first->second;
      used.spellings = true;
      return Kind{name, llvm::formatv("{0}Spelling {{0}", camel(name, false)).str()};
    }
  StringRef type = param.getCppType().trim();
  if (type == "::mlir::Type")
    return Kind{"MlirType", "{0}.text"};
  if (type == "::mlir::Attribute")
    return Kind{"MlirAttr", "{0}.text"};
  if (type == "::mlir::FlatSymbolRefAttr")
    return Kind{"String", "(flatSymbolRefAttr {0}).text"};
  if (type == "::mlir::SymbolRefAttr")
    return Kind{"List String", "(symbolRefAttr {0}).text"};
  if (type == "::mlir::StringAttr" || type == "::llvm::StringRef")
    return Kind{"String", "(stringAttr {0}).text"};
  if (type == "::mlir::ArrayAttr")
    return Kind{"List MlirAttr", "(arrayAttr {0}).text"};
  if (type == "unsigned" || type == "uint32_t" || type == "uint64_t")
    return Kind{"Nat", "show {0}"};
  if (type == "int" || type == "int32_t" || type == "int64_t")
    return Kind{"Integer", "show {0}"};
  if (type == "::llvm::ArrayRef<::mlir::Type>")
    return Kind{"List MlirType", "commaSeparated (map (.text) {0})"};
  return std::nullopt;
}

// One piece of a declarative syntax: a literal, or a parameter by name.
struct Piece {
  bool isLiteral;
  std::string text;
};

// The pieces of a declarative syntax made of literals and parameters, the
// only syntax the generator writes; nothing for any other directive.
std::optional<std::vector<Piece>> pieces(StringRef format) {
  std::vector<Piece> out;
  while (!(format = format.ltrim()).empty()) {
    if (format.consume_front("`")) {
      size_t end = format.find('`');
      if (end == StringRef::npos)
        return std::nullopt;
      out.push_back({true, format.take_front(end).str()});
      format = format.drop_front(end + 1);
    } else if (format.consume_front("$")) {
      StringRef name = format.take_while([](char c) { return llvm::isAlnum(c) || c == '_'; });
      out.push_back({false, name.str()});
      format = format.drop_front(name.size());
    } else {
      return std::nullopt;
    }
  }
  return out;
}

// A literal as the declarative printer spaces it: a comma, an arrow and an
// equals sign apart from what follows, a keyword apart from both sides,
// brackets close up.
std::string spaced(StringRef text) {
  if (text == "," )
    return ", ";
  if (text == "->" || text == "=" || text == ":")
    return " " + text.str() + " ";
  if (!text.empty() && (llvm::isAlpha(text.front()) || text.front() == '_'))
    return " " + text.str() + " ";
  return text.str();
}

// Why a type or an attribute is not generated; or, written out, nothing.
std::optional<std::string> emitDef(const AttrOrTypeDef &def, bool isType, llvm::raw_ostream &os) {
  std::optional<StringRef> mnemonic = def.getMnemonic();
  if (!mnemonic)
    return std::string("it has no mnemonic");
  std::vector<Parameter> params;
  std::map<std::string, std::string> texts;
  for (const AttrOrTypeParameter &param : def.getParameters()) {
    // The type of an attribute's value is the op's that holds it.
    if (llvm::isa<mlir::tblgen::AttributeSelfTypeParameter>(param))
      continue;
    std::optional<Kind> kind = parameterKind(param);
    if (!kind)
      return llvm::formatv("its parameter `{0}` is the C++ `{1}`", param.getName(),
                           param.getCppType())
          .str();
    std::string name = parameter(param.getName(), "parameter" + llvm::Twine(params.size()));
    params.push_back({name, kind->type, std::nullopt});
    texts[param.getName().str()] = llvm::formatv(kind->text.c_str(), name).str();
  }
  std::vector<Piece> syntax;
  if (def.hasCustomAssemblyFormat())
    return std::string("its syntax is C++");
  if (std::optional<StringRef> format = def.getAssemblyFormat()) {
    std::optional<std::vector<Piece>> parsed = pieces(*format);
    if (!parsed)
      return llvm::formatv("its syntax `{0}` has a directive", *format).str();
    syntax = *parsed;
  } else if (!params.empty()) {
    return std::string("it has parameters and no syntax");
  }
  std::string spelling =
      ((isType ? "!" : "#") + def.getDialect().getName() + "." + *mnemonic).str();
  std::string name = camel(*mnemonic, false) + (isType ? "Type" : "Attr");
  // The text: the literals between parameters joined into one string each.
  std::vector<std::string> parts;
  std::string pending = spelling;
  for (const Piece &piece : syntax) {
    if (piece.isLiteral) {
      pending += spaced(piece.text);
      continue;
    }
    auto text = texts.find(piece.text);
    if (text == texts.end())
      return llvm::formatv("its syntax names `{0}`, which is no parameter", piece.text).str();
    if (!pending.empty())
      parts.push_back(literal(pending));
    pending.clear();
    parts.push_back(text->second);
  }
  if (!pending.empty())
    parts.push_back(literal(pending));
  std::string body = llvm::join(parts, " ++ ");

  os << "||| `" << spelling << "`" << summary(def.getSummary());
  os << "\nexport\n" << name << " : ";
  for (const Parameter &p : params)
    os << binder(p) << " -> ";
  os << (isType ? "MlirType" : "MlirAttr") << "\n" << name;
  for (const Parameter &p : params)
    os << ' ' << p.name;
  os << " = " << (isType ? "MkMlirType" : "MkMlirAttr") << ' '
     << (parts.size() == 1 ? body : "(" + body + ")") << "\n\n";
  return std::nullopt;
}

//===----------------------------------------------------------------------===//
// Enums and discardable attributes
//===----------------------------------------------------------------------===//

void emitEnum(const Enum &used, llvm::raw_ostream &os) {
  EnumInfo info(used.def);
  std::string name = enumName(info);
  std::vector<mlir::tblgen::EnumCase> cases = info.getAllCases();
  os << "namespace " << name << "\n";
  os << "  ||| " << doc(info.getSummary()) << "\n";
  os << "  public export\n  data " << name << " = ";
  llvm::interleave(
      cases, [&](const mlir::tblgen::EnumCase &c) { os << camel(c.getSymbol(), true); },
      [&] { os << " | "; });
  os << "\n\n";
  // Private to the module, out of the way of whatever imports it.
  std::string lower = camel(name, false);
  if (used.values) {
    os << "-- The value that stands for a " << name << ", as the ops below write it.\n"
       << lower << "Value : " << name << " -> Integer\n";
    for (const mlir::tblgen::EnumCase &c : cases)
      os << lower << "Value " << name << "." << camel(c.getSymbol(), true) << " = "
         << c.getValue() << "\n";
    os << "\n";
  }
  if (used.spellings) {
    os << "-- The spelling of a " << name << ", as the attributes below write it.\n"
       << lower << "Spelling : " << name << " -> String\n";
    for (const mlir::tblgen::EnumCase &c : cases)
      os << lower << "Spelling " << name << "." << camel(c.getSymbol(), true) << " = "
         << literal(c.getStr()) << "\n";
    os << "\n";
  }
}

void emitDiscardable(const mlir::tblgen::Dialect &dialect, llvm::raw_ostream &os) {
  const llvm::DagInit *attrs = dialect.getDiscardableAttributes();
  if (!attrs)
    return;
  for (unsigned i = 0, e = attrs->getNumArgs(); i < e; ++i) {
    StringRef odsName = attrs->getArgNameStr(i);
    std::string type = attrs->getArg(i)->getAsUnquotedString();
    std::string name = camel(odsName, false) + "Discardable";
    std::string key = literal((dialect.getName() + "." + odsName).str());
    os << "||| The discardable attribute `" << dialect.getName() << "." << odsName << "`.\n";
    os << "export\n" << name;
    if (type == "::mlir::UnitAttr")
      os << " : NamedAttr\n" << name << " = (" << key << ", unitAttr)\n\n";
    else if (type == "::mlir::StringAttr")
      os << " : String -> NamedAttr\n" << name << " s = (" << key << ", stringAttr s)\n\n";
    else
      os << " : MlirAttr -> NamedAttr\n" << name << " a = (" << key << ", a)\n\n";
  }
}

bool emitIdrisDialect(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  if (dialectName.empty() || moduleName.empty())
    llvm::PrintFatalError("-gen-idris-dialect needs -idris-dialect and -idris-module");
  std::optional<mlir::tblgen::Dialect> dialect;
  for (const llvm::Record *def : records.getAllDerivedDefinitions("Dialect"))
    if (def->getValueAsString("name") == dialectName)
      dialect.emplace(def);
  if (!dialect)
    llvm::PrintFatalError("no dialect " + dialectName + " in the records");

  // The dialect's types and attributes, and its ops by name; the enums they
  // take are found on the way, so the module is written once all are.
  std::string definitions, ops, enumerations;
  llvm::raw_string_ostream definitionsOs(definitions), opsOs(ops), enumsOs(enumerations);
  std::vector<std::string> omitted;
  for (StringRef kind : {"TypeDef", "AttrDef"})
    for (const llvm::Record *def : records.getAllDerivedDefinitionsIfDefined(kind)) {
      AttrOrTypeDef typeOrAttr(def);
      if (typeOrAttr.getDialect().getName() != dialectName)
        continue;
      if (std::optional<std::string> why = emitDef(typeOrAttr, kind == "TypeDef", definitionsOs))
        omitted.push_back(llvm::formatv("{0} {1}: {2}", kind == "TypeDef" ? "type" : "attribute",
                                        typeOrAttr.getCppClassName(), *why)
                              .str());
    }
  emitDiscardable(*dialect, definitionsOs);
  std::vector<std::pair<std::string, const llvm::Record *>> byName;
  for (const llvm::Record *def : records.getAllDerivedDefinitions("Op")) {
    Operator op(def);
    if (op.getDialectName() == dialectName)
      byName.emplace_back(op.getOperationName(), def);
  }
  llvm::sort(byName);
  for (const auto &[name, def] : byName)
    emitOp(Operator(def), opsOs);
  for (const auto &[name, used] : enums)
    emitEnum(used, enumsOs);

  os << "||| The " << dialectName << " dialect, as the Idris side writes it. Generated by\n"
     << "||| idris-mlir-tblgen -gen-idris-dialect from the dialect's ODS; `make build`\n"
     << "||| writes it (tools/dialects.sh). Do not edit.\n"
     << "module " << moduleName << "\n\nimport IdrisMLIR.MLIR\n\n%default total\n\n";
  section(os, "Enums", enumerations);
  section(os, "Types and attributes", definitions);
  section(os, "Ops", ops);
  if (!omitted.empty()) {
    os << "-- Not generated:\n";
    for (const std::string &why : omitted)
      os << "-- " << why << "\n";
  }
  return false;
}

const mlir::GenRegistration genIdrisDialect("gen-idris-dialect",
                                            "The Idris side's vocabulary of a dialect",
                                            emitIdrisDialect);

} // namespace

int main(int argc, char **argv) { return mlir::MlirTblgenMain(argc, argv); }
