// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir-tblgen: mlir-tblgen with two more generators, which write a
// dialect's vocabulary for the Idris side from the dialect's ODS, in two
// modules:
//
// - -gen-idris-syntax, its syntax: the enums its ops, types and attributes
//   take, and its types and attributes, each a constructor of the
//   dialect's sum of types or of attributes, with the printer that writes
//   it in the syntax ODS declares for it. IdrisMLIR.MLIR's types and
//   attributes hold these sums (compiler/src/IdrisMLIR/Syntax/).
// - -gen-idris-dialect, its ops: a builder of each op, over its operands,
//   attributes, regions and results; its discardable attributes; the
//   printer of each op's declarative syntax; and its primitives, the ops
//   Idris names, each a constructor the Idris side builds it from
//   (compiler/src/IdrisMLIR/Dialect/).
//
// Emit writes MLIR only through these modules, so what an op, a type or an
// attribute is, and how each of its parts is spelled, is said once: in ODS.
//
// It is a TableGen backend rather than a program over a dump of the records
// because it then reads ODS through mlir::tblgen (Operator, Attribute,
// AttrOrTypeDef, EnumInfo), the reading the dialects' own C++ is generated
// from, so the two sides cannot take one op differently; and the pinned
// toolchain installs those libraries and mlir-tblgen, not llvm-tblgen.
//
// An op is written in the declarative syntax its ODS gives (its
// assemblyFormat) when the generator can read that syntax whole, so that
// what Emit writes reads as the dumps MLIR prints; and in MLIR's generic
// form otherwise, which IdrisMLIR.MLIR writes and which ODS says alone for
// every op: the name, the operands, the inherent attributes as properties,
// the regions, the discardable attributes and the types. A syntax that is
// C++ (a custom directive, the parsers of idr.match and idr.constant) is
// one nothing generated from ODS can know; each op written generic is
// listed, with the reason, at the end of its printer. A type or an
// attribute has no generic form, so it is written in the syntax ODS
// declares for it, which the generated C++ parser reads; one whose syntax
// ODS does not declare is left out, with the reason, at the end of the
// syntax module. The one syntax of a type the generator knows by itself is
// an identified type's (a TypeDef with MutableType), which no declarative
// syntax can say: its name, then its body, which a type inside its own body
// leaves out, as LLVM writes an identified struct.

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
#include "llvm/ADT/bit.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/FormatVariadic.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/TableGen/Error.h"
#include "llvm/TableGen/Record.h"

#include <map>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

namespace {

using llvm::StringRef;
using mlir::tblgen::AttrOrTypeDef;
using mlir::tblgen::AttrOrTypeParameter;
using mlir::tblgen::EnumCase;
using mlir::tblgen::EnumInfo;
using mlir::tblgen::NamedAttribute;
using mlir::tblgen::NamedProperty;
using mlir::tblgen::NamedRegion;
using mlir::tblgen::NamedTypeConstraint;
using mlir::tblgen::Operator;

llvm::cl::opt<std::string> dialectName("idris-dialect",
                                       llvm::cl::desc("The dialect the Idris module is of"));
llvm::cl::opt<std::string> moduleName("idris-module",
                                      llvm::cl::desc("The Idris module the generator writes"));
llvm::cl::opt<std::string>
    syntaxModuleName("idris-syntax-module",
                     llvm::cl::desc("The dialect's syntax module, which -gen-idris-dialect imports"));

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
// parameter of one of these names would hide it. `t` and `a` are the
// printers of the types and attributes a type or an attribute holds, `ty`
// and `at` the types of them.
bool isUsedInBodies(StringRef name) {
  static constexpr StringRef names[] = {
      "concat", "toList",    "length",    "map",       "show",   "unitIf",
      "attrIf", "commaSeparated", "v",    "t",         "a",      "ty",
      "at",     "fastConcat", "maybe",    "null",      "symbol", "symbolRef",
      "utf8",   "array",     "signature", "separated"};
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

// An Idris type as an argument of another: in parentheses unless it is one
// word.
std::string parenthesized(StringRef type) {
  return type.contains(' ') ? ("(" + type + ")").str() : type.str();
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

// How the Idris side gives a value of some kind, and writes it: its Idris
// type, and the expression that writes it from a value `{0}` of that type.
struct Kind {
  std::string type;
  std::string text;
};

// The function that writes a value, from the expression that writes `{0}`.
std::string maker(const std::string &text) {
  StringRef pattern = text;
  if (pattern == "{0}")
    return "id";
  if (pattern.ends_with(" {0}") && !pattern.drop_back(4).contains(' '))
    return pattern.drop_back(4).str();
  return llvm::formatv("(\\v => {0})", llvm::formatv(text.c_str(), "v").str()).str();
}

//===----------------------------------------------------------------------===//
// Enums
//===----------------------------------------------------------------------===//

// The enums the dialect's ops, types and attributes take, by their ODS
// records: written once each, in the syntax module, with their spellings if
// a syntax prints one, and their values, in the ops' module, if an op stores
// one as an integer, with their keywords if an op's syntax writes one.
struct Enum {
  const llvm::Record *def;
  bool values = false;
  bool spellings = false;
  bool keywords = false;
};
using Enums = std::map<std::string, Enum>;

// The Idris name of an enum, and of its namespace.
std::string enumName(const EnumInfo &info) { return info.getEnumClassName().str(); }

Enum &useEnum(Enums &enums, const llvm::Record *def) {
  return enums.try_emplace(enumName(EnumInfo(def)), Enum{def}).first->second;
}

// `text` as MLIR's printer writes a keyword or a string where its parser
// reads either: bare when it is a keyword (a letter or `_`, then letters,
// digits, `_`, `$` and `.`), else a quoted string.
std::string keywordOrString(StringRef text) {
  auto start = [](char c) { return llvm::isAlpha(c) || c == '_'; };
  auto rest = [](char c) { return llvm::isAlnum(c) || c == '_' || c == '$' || c == '.'; };
  if (!text.empty() && start(text.front()) && llvm::all_of(text.drop_front(), rest))
    return text.str();
  std::string quoted = "\"";
  for (char c : text) {
    if (c == '"' || c == '\\')
      quoted += '\\';
    quoted += c;
  }
  return quoted + "\"";
}

// The cases of an enum the Idris side holds: every case of an enum; of a
// bit enum, the bits, a set of which it gives as a list of them (the case of
// no bits is the empty list, and a group is its bits).
std::vector<EnumCase> idrisCases(const EnumInfo &info) {
  std::vector<EnumCase> cases = info.getAllCases();
  if (info.isBitEnum())
    llvm::erase_if(cases, [](const EnumCase &c) {
      return !llvm::has_single_bit(static_cast<uint64_t>(c.getValue()));
    });
  return cases;
}

// A bit enum's case of no bits, which writes the empty list.
std::optional<EnumCase> noBits(const EnumInfo &info) {
  for (const EnumCase &c : info.getAllCases())
    if (c.getValue() == 0)
      return c;
  return std::nullopt;
}

void emitEnum(const Enum &used, llvm::raw_ostream &os) {
  EnumInfo info(used.def);
  std::string name = enumName(info);
  std::vector<EnumCase> cases = idrisCases(info);
  os << "namespace " << name << "\n";
  os << "  ||| " << doc(info.getSummary()) << "\n";
  os << "  public export\n  data " << name << " = ";
  llvm::interleave(
      cases, [&](const EnumCase &c) { os << camel(c.getSymbol(), true); }, [&] { os << " | "; });
  os << "\n\n";
  // Qualified: an enum's case may share its name with the interface (Eq).
  os << "export\nPrelude.EqOrd.Eq " << name << " where\n";
  for (const EnumCase &c : cases) {
    std::string qualified = name + "." + camel(c.getSymbol(), true);
    os << "  " << qualified << " == " << qualified << " = True\n";
  }
  os << "  _ == _ = False\n\n";
  // Each case shows as its ODS string, the one way a value of it reads.
  os << "export\nShow " << name << " where\n";
  for (const EnumCase &c : cases)
    os << "  show " << name << "." << camel(c.getSymbol(), true) << " = " << literal(c.getStr())
       << "\n";
  os << "\n";
  if (!used.spellings)
    return;
  // Private to the module, out of the way of whatever imports it. The
  // syntax spells a case as MLIR's enum parser reads it
  // (parseKeywordOrString): its string, quoted where it is no keyword.
  std::string lower = camel(name, false);
  os << "-- How the syntax below spells each " << name << ".\n"
     << lower << "Spelling : " << name << " -> String\n";
  for (const EnumCase &c : cases)
    os << lower << "Spelling " << name << "." << camel(c.getSymbol(), true) << " = "
       << literal(keywordOrString(c.getStr())) << "\n";
  os << "\n";
  if (!info.isBitEnum())
    return;
  os << "-- How the syntax below spells a set of " << name << ": its bits, apart.\n"
     << lower << "Spellings : List " << name << " -> String\n"
     << lower << "Spellings [] = " << literal(noBits(info)->getStr()) << "\n"
     << lower << "Spellings es = separated "
     << literal(used.def->getValueAsString("separator")) << " (map " << lower
     << "Spelling es)\n\n";
}

// The values of an enum an op stores as an integer, private to the ops'
// module too.
void emitEnumValues(const Enum &used, llvm::raw_ostream &os) {
  if (!used.values)
    return;
  EnumInfo info(used.def);
  std::string name = enumName(info);
  std::string lower = camel(name, false);
  os << "-- The value that stands for a " << name << ", as the ops below write it.\n"
     << lower << "Value : " << name << " -> Integer\n";
  for (const EnumCase &c : info.getAllCases())
    os << lower << "Value " << name << "." << camel(c.getSymbol(), true) << " = "
       << c.getValue() << "\n";
  os << "\n";
}

// The keyword of each value of an enum an op stores as an integer, as the
// op's syntax writes it, private to the ops' module. A value of no case is
// written as the attribute it is, which the parser refuses.
void emitEnumKeywords(const Enum &used, llvm::raw_ostream &os) {
  if (!used.keywords)
    return;
  EnumInfo info(used.def);
  std::string name = enumName(info);
  std::string lower = camel(name, false);
  os << "-- The keyword the printer writes for a " << name << ".\ncovering\n"
     << lower << "Keyword : MlirAttr -> String\n";
  std::set<int64_t> seen;
  for (const EnumCase &c : info.getAllCases()) {
    int64_t value = c.getValue();
    if (!seen.insert(value).second)
      continue;
    std::string number = std::to_string(value);
    os << lower << "Keyword (IntegerAttr " << (value < 0 ? "(" + number + ")" : number)
       << " _) = " << literal(c.getStr()) << "\n";
  }
  os << lower << "Keyword a = attrText a\n\n";
}

//===----------------------------------------------------------------------===//
// Values of ops: builtin types and attributes
//===----------------------------------------------------------------------===//

// The builtin type an ODS type constraint names when it is one exact type,
// as a constructor of IdrisMLIR.MLIR's types.
std::optional<std::string> builtinType(const llvm::Record &type) {
  if (type.isSubClassOf("I"))
    return llvm::formatv("IntegerType {0}", type.getValueAsInt("bitwidth")).str();
  if (type.isSubClassOf("F") && type.getValueAsInt("bitwidth") == 64)
    return std::string("F64Type");
  if (type.getName() == "Index")
    return std::string("IndexType");
  return std::nullopt;
}

// An enum stored as an integer attribute, which the generic form writes as
// its value: an op attribute of ODS's integer enums.
std::optional<Kind> integerEnum(Enums &enums, const mlir::tblgen::Attribute &base) {
  // An EnumAttr is an attribute of its own around the enum, not an integer:
  // only an enum that is itself the attribute is stored as one.
  if (!base.getDef().isSubClassOf("EnumInfo"))
    return std::nullopt;
  EnumInfo info(&base.getDef());
  if (info.isBitEnum())
    return std::nullopt;
  const llvm::Record *storage = info.getBaseAttrClass();
  if (!storage || mlir::tblgen::Attribute(storage).getStorageType().trim() != "::mlir::IntegerAttr")
    return std::nullopt;
  std::string name = enumName(info);
  useEnum(enums, &base.getDef()).values = true;
  return Kind{name, llvm::formatv("IntegerAttr ({0}Value {{0}) (IntegerType {1})",
                                  camel(name, false), info.getBitwidth())
                        .str()};
}

// How an op attribute of this constraint is given, once what makes it
// optional is set apart: by the kind of attribute that stores it.
Kind attributeKind(Enums &enums, const mlir::tblgen::Attribute &attr) {
  mlir::tblgen::Attribute base = attr.getBaseAttr();
  StringRef storage = base.getStorageType().trim();
  if (base.isEnumAttr())
    if (std::optional<Kind> kind = integerEnum(enums, base))
      return *kind;
  if (storage == "::mlir::BoolAttr")
    return {"Bool", "BoolAttr {0}"};
  if (storage == "::mlir::IntegerAttr")
    if (std::optional<mlir::tblgen::Type> type = base.getValueType())
      if (std::optional<std::string> builtin = builtinType(type->getDef()))
        return {"Integer", llvm::formatv("IntegerAttr {{0} ({0})", *builtin).str()};
  if (storage == "::mlir::FloatAttr")
    if (std::optional<mlir::tblgen::Type> type = base.getValueType())
      if (std::optional<std::string> builtin = builtinType(type->getDef()))
        return {"Double", llvm::formatv("FloatAttr {{0} ({0})", *builtin).str()};
  if (storage == "::mlir::StringAttr")
    return {"String", "StringAttr {0}"};
  if (storage == "::mlir::FlatSymbolRefAttr")
    return {"String", "SymbolRefAttr (MkSymbolRef {0} [])"};
  if (storage == "::mlir::SymbolRefAttr")
    return {"SymbolRef", "SymbolRefAttr {0}"};
  if (storage == "::mlir::TypeAttr")
    return {"MlirType", "TypeAttr {0}"};
  if (base.getAttrDefName() == "TypeArrayAttr")
    return {"List MlirType", "ArrayAttr (map TypeAttr {0})"};
  if (storage == "::mlir::ArrayAttr")
    return {"List MlirAttr", "ArrayAttr {0}"};
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

// The number of values of each group, for an op whose variadic operands or
// results are told apart by a segment-size property.
std::string segments(const std::vector<std::pair<std::string, char>> &parts) {
  std::string out = "DenseI32ArrayAttr [";
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

void emitOp(Enums &enums, const Operator &op, llvm::raw_ostream &os) {
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
      // claim (a read that moves its element out): the Idris side cannot
      // make it, and writes the op at its default.
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
    Kind kind = attributeKind(enums, attribute->attr);
    if (attribute->attr.isOptional() || attribute->attr.hasDefaultValue()) {
      implicits.push_back({param, "Maybe " + parenthesized(kind.type), std::string("Nothing")});
      properties.emplace_back(
          llvm::formatv("attrIf {0} {1} {2}", key, maker(kind.text), param).str(), false);
    } else {
      explicits.push_back({param, kind.type, std::nullopt});
      properties.emplace_back(
          llvm::formatv("({0}, {1})", key, llvm::formatv(kind.text.c_str(), param).str()).str(),
          true);
    }
  }
  for (auto [index, region] : llvm::enumerate(op.getRegions())) {
    std::string param = parameter(region.name, "region" + llvm::Twine(index));
    regions.emplace_back(param, region.isVariadic() ? '*' : '1');
    explicits.push_back({param, region.isVariadic() ? "List Region" : "Region", std::nullopt});
  }
  for (auto [index, result] : llvm::enumerate(op.getResults())) {
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
// Primitives
//===----------------------------------------------------------------------===//

// An op Idris names as a primitive (Idr_Primitive): one constructor of
// IdrPrim, or of IdrRegionPrim when it has a body, named after its C++ class
// without `Op`. The Idris side builds the op from that constructor and its
// operands alone, so a primitive has no inherent attribute: no constructor
// could give one its value.
struct Primitive {
  std::string constructor;
  std::string operationName;
  bool performsIO;
  // How many arguments a region primitive's body takes; nothing for any
  // other primitive.
  std::optional<int64_t> bodyArguments;
};

// What of `op` its constructor could not give: an inherent attribute, a
// property without a default, or the segment sizes of its operands or
// results; or nothing. A property with a default is a pass's own claim,
// which the constructor leaves at its default, as emitOp does.
std::optional<std::string> inherent(const Operator &op) {
  for (int index = 0, e = op.getNumArgs(); index < e; ++index) {
    mlir::tblgen::Argument arg = op.getArg(index);
    if (const auto *attribute = llvm::dyn_cast_if_present<NamedAttribute *>(arg)) {
      if (!attribute->attr.isDerivedAttr())
        return llvm::formatv("the attribute `{0}`", attribute->name).str();
    } else if (const auto *property = llvm::dyn_cast_if_present<NamedProperty *>(arg)) {
      if (!property->prop.hasDefaultValue())
        return llvm::formatv("the property `{0}`", property->name).str();
    }
  }
  if (op.getTrait("::mlir::OpTrait::AttrSizedOperandSegments") ||
      op.getTrait("::mlir::OpTrait::AttrSizedResultSegments"))
    return std::string("segment sizes");
  return std::nullopt;
}

// The primitive `op` is, if Idris names it one.
std::optional<Primitive> primitiveOf(const Operator &op) {
  if (!op.getTrait("::idr::Primitive"))
    return std::nullopt;
  std::string operationName = op.getOperationName();
  if (std::optional<std::string> what = inherent(op))
    llvm::PrintFatalError(op.getLoc(), "the primitive " + operationName + " has " + *what +
                                           ", which no constructor of a primitive can give");
  StringRef constructor = op.getCppClassName();
  constructor.consume_back("Op");
  Primitive primitive{constructor.str(), operationName, op.getTrait("::idr::PerformsIO") != nullptr,
                      std::nullopt};
  if (op.getNumRegions() == 0)
    return primitive;
  if (op.getNumRegions() != 1 || op.getRegion(0).isVariadic())
    llvm::PrintFatalError(op.getLoc(), "the region primitive " + operationName +
                                           " has more than its one body");
  // The count is the region constraint's (Idr_BodyRegion), which checks it,
  // as SizedRegion's `blocks` is the count of blocks it checks.
  const llvm::Record &body = op.getRegion(0).constraint.getDef();
  if (!body.getValue("arguments"))
    llvm::PrintFatalError(op.getLoc(), "the body of the region primitive " + operationName +
                                           " does not say how many arguments it takes");
  primitive.bodyArguments = body.getValueAsInt("arguments");
  return primitive;
}

// The primitives of the dialect's ops, in the order ODS declares them: the
// two types of their constructors, and what the Idris side reads of each,
// its op, whether it performs IO, and a region primitive's arity.
void emitPrimitives(std::vector<const llvm::Record *> defs, llvm::raw_ostream &os) {
  llvm::sort(defs, llvm::LessRecordByID());
  std::vector<Primitive> plain, regions;
  for (const llvm::Record *def : defs)
    if (std::optional<Primitive> primitive = primitiveOf(Operator(def)))
      (primitive->bodyArguments ? regions : plain).push_back(*primitive);
  auto constructors = [&](const std::vector<Primitive> &primitives) {
    for (auto [index, primitive] : llvm::enumerate(primitives))
      os << (index == 0 ? "  = " : "  | ") << primitive.constructor << "\n";
    os << "\n";
  };
  if (!plain.empty()) {
    os << "||| The dialect's primitives (ops with Idr_Primitive and no region), one\n"
       << "||| constructor each, named after the op's C++ class without `Op`.\n"
       << "public export\ndata IdrPrim\n";
    constructors(plain);
    os << "||| Whether the primitive performs IO (Idr_PerformsIO). Such a primitive\n"
       << "||| takes the world as its last operand and gives the next as its last\n"
       << "||| result, except one without operands, which makes a world: it takes\n"
       << "||| none and gives one.\n"
       << "export\nprimPerformsIO : IdrPrim -> Bool\n";
    for (const Primitive &primitive : plain)
      os << "primPerformsIO " << primitive.constructor << " = "
         << (primitive.performsIO ? "True" : "False") << "\n";
    os << "\n||| The operation of a primitive on operands, with its result types\n"
       << "||| (a primitive has no inherent attribute).\n"
       << "export\nprimOp : IdrPrim -> List Value -> List MlirType -> Op\n";
    for (const Primitive &primitive : plain)
      os << "primOp " << primitive.constructor << " operands results = MkOp "
         << literal(primitive.operationName) << " operands [] [] [] results\n";
    os << "\n";
  }
  if (!regions.empty()) {
    os << "||| The dialect's region primitives.\npublic export\ndata IdrRegionPrim\n";
    constructors(regions);
    os << "||| The block arguments a region primitive's body takes.\n"
       << "public export\nregionArity : IdrRegionPrim -> Nat\n";
    for (const Primitive &primitive : regions)
      os << "regionArity " << primitive.constructor << " = " << *primitive.bodyArguments << "\n";
    os << "\n||| The operation of a region primitive on operands and its body, with\n"
       << "||| its result types.\n"
       << "export\nregionOp : IdrRegionPrim -> List Value -> Region -> List MlirType -> Op\n";
    for (const Primitive &primitive : regions)
      os << "regionOp " << primitive.constructor << " operands body results = MkOp "
         << literal(primitive.operationName) << " operands [] [body] [] results\n";
    os << "\n";
  }
}

//===----------------------------------------------------------------------===//
// Types and attributes
//===----------------------------------------------------------------------===//

// When a parameter is written: always, or, for an optional one, when the
// Idris value has it (a Just, a list that is not empty). A parameter with a
// default other than nothing is always written: the parser reads the
// default written out as it reads any other value.
enum class Presence { Always, IfJust, IfNonEmpty };

// A parameter of a type or an attribute as a field of its constructor: its
// name, its Idris type, the expression that writes it from `{0}`, and when.
struct Field {
  std::string name;
  std::string type;
  std::string text;
  Presence presence = Presence::Always;
};

// The Idris kind of a parameter's C++ value; nothing for one the Idris side
// has no value of.
std::optional<Kind> valueKind(StringRef cpp) {
  cpp = cpp.trim();
  if (cpp == "::mlir::Type")
    return Kind{"ty", "t {0}"};
  if (cpp == "::mlir::Attribute")
    return Kind{"at", "a {0}"};
  if (cpp == "::mlir::FlatSymbolRefAttr")
    return Kind{"String", "symbol {0}"};
  if (cpp == "::mlir::SymbolRefAttr")
    return Kind{"SymbolRef", "symbolRef {0}"};
  if (cpp == "::mlir::StringAttr" || cpp == "::llvm::StringRef")
    return Kind{"String", "utf8 {0}"};
  if (cpp == "::mlir::ArrayAttr")
    return Kind{"List at", "array a {0}"};
  if (cpp == "::mlir::FunctionType")
    return Kind{"Signature ty", "signature t {0}"};
  if (cpp == "unsigned" || cpp == "uint32_t" || cpp == "uint64_t")
    return Kind{"Nat", "show {0}"};
  if (cpp == "int" || cpp == "int32_t" || cpp == "int64_t")
    return Kind{"Integer", "show {0}"};
  if (cpp.consume_front("::llvm::ArrayRef<") && cpp.consume_back(">"))
    if (std::optional<Kind> element = valueKind(cpp))
      return Kind{"List " + parenthesized(element->type),
                  "commaSeparated (map " + maker(element->text) + " {0})"};
  // A type of a dialect's own class (a box's data type) is a type, which
  // its C++ parser reads as any and checks.
  if (cpp.starts_with("::") && cpp.ends_with("Type"))
    return Kind{"ty", "t {0}"};
  return std::nullopt;
}

// The Idris kind of an enum parameter: the enum, or a list of a bit enum's
// bits; nothing, with the reason in `why`, for a bit enum with no case of
// no bits, which could not write the empty list.
std::optional<Kind> enumKind(Enums &enums, const AttrOrTypeParameter &param,
                             std::string &why) {
  const auto *def = llvm::dyn_cast<llvm::DefInit>(param.getDef());
  if (!def || !def->getDef()->isSubClassOf("EnumParameter"))
    return std::nullopt;
  const llvm::Record *record = def->getDef()->getValueAsDef("enum");
  EnumInfo info(record);
  std::string name = enumName(info);
  std::string lower = camel(name, false);
  if (!info.isBitEnum()) {
    useEnum(enums, record).spellings = true;
    return Kind{name, lower + "Spelling {0}"};
  }
  if (!noBits(info)) {
    why = llvm::formatv("its parameter `{0}` is a bit enum without a case of no bits",
                        param.getName())
              .str();
    return std::nullopt;
  }
  useEnum(enums, record).spellings = true;
  return Kind{"List " + name, lower + "Spellings {0}"};
}

// The field of a parameter, or nothing, with the reason in `why`.
std::optional<Field> fieldOf(Enums &enums, const AttrOrTypeParameter &param, size_t index,
                             std::string &why) {
  std::optional<Kind> kind = enumKind(enums, param, why);
  if (!kind && !why.empty())
    return std::nullopt;
  if (!kind)
    kind = valueKind(param.getCppType());
  if (!kind) {
    why = llvm::formatv("its parameter `{0}` is the C++ `{1}`", param.getName(),
                        param.getCppType())
              .str();
    return std::nullopt;
  }
  Field field{parameter(param.getName(), "parameter" + llvm::Twine(index)), kind->type,
              kind->text};
  // An optional parameter without a default of its own defaults to nothing.
  std::optional<StringRef> fallback = param.getDefaultValue();
  if (fallback && *fallback == (param.getCppStorageType() + "()").str()) {
    if (StringRef(kind->type).starts_with("List ")) {
      field.presence = Presence::IfNonEmpty;
    } else {
      field.type = "Maybe " + parenthesized(kind->type);
      field.presence = Presence::IfJust;
    }
  }
  return field;
}

// One element of a declarative syntax.
struct Element {
  enum Form { Literal, Parameter, Directive, Group } form;
  std::string text = {};              // the literal, the parameter's or the directive's name
  bool anchor = false;                // an element marked `^`
  std::vector<Element> group = {};    // an optional group's elements
  std::vector<std::string> args = {}; // a type directive's: `$name`, `operands`, `results`
};

// A parameter's name after `$`.
std::string parameterName(StringRef &format) {
  StringRef name = format.take_while([](char c) { return llvm::isAlnum(c) || c == '_'; });
  format = format.drop_front(name.size());
  return name.str();
}

// A directive of an op's syntax that writes types, `type(x)` or
// `functional-type(x, y)`, after its name; nothing, with the reason in
// `why`, for one whose arguments are not variables, `operands` or `results`.
std::optional<Element> typeDirective(StringRef name, StringRef &format, std::string &why) {
  Element directive{Element::Directive, name.str()};
  why = ("`" + name + "` of what the generator does not know").str();
  format = format.ltrim();
  if (!format.consume_front("("))
    return std::nullopt;
  for (size_t index = 0, count = name == "type" ? 1u : 2u; index < count; ++index) {
    format = format.ltrim();
    if (index != 0 && !format.consume_front(","))
      return std::nullopt;
    format = format.ltrim();
    if (format.consume_front("$"))
      directive.args.push_back("$" + parameterName(format));
    else if (format.consume_front("operands"))
      directive.args.push_back("operands");
    else if (format.consume_front("results"))
      directive.args.push_back("results");
    else
      return std::nullopt;
  }
  format = format.ltrim();
  if (!format.consume_front(")"))
    return std::nullopt;
  why.clear();
  directive.anchor = format.consume_front("^");
  return directive;
}

// The elements of a declarative syntax up to its end, or in a group up to
// its `)`; nothing, with the reason in `why`, for a directive the generator
// does not write (custom, oilist, ref, prop-dict, struct, params) and for an
// else branch. A type's or an attribute's syntax has only `qualified`, and
// the C++ printer alone spaces it; an op's (`op`) has its own directives,
// and the printer writes its whitespace literals.
std::optional<std::vector<Element>> elements(StringRef &format, bool inGroup, std::string &why,
                                             bool op) {
  std::vector<Element> out;
  while (true) {
    format = format.ltrim();
    if (format.empty()) {
      if (!inGroup)
        return out;
      why = "an optional group that does not end";
      return std::nullopt;
    }
    if (inGroup && format.consume_front(")"))
      return out;
    if (format.consume_front("`")) {
      size_t end = format.find('`');
      if (end == StringRef::npos) {
        why = "a literal that does not end";
        return std::nullopt;
      }
      // In a type's or an attribute's syntax, an empty literal, or one of
      // spaces, only spaces the C++ printer.
      StringRef text = format.take_front(end);
      format = format.drop_front(end + 1);
      if (op || !text.trim().empty())
        out.push_back({Element::Literal, text.str()});
      continue;
    }
    if (format.consume_front("$")) {
      std::string name = parameterName(format);
      bool anchor = format.consume_front("^");
      out.push_back({Element::Parameter, name, anchor});
      continue;
    }
    if (format.consume_front("qualified(")) {
      format = format.ltrim();
      Element inner{Element::Parameter, ""};
      if (format.consume_front("$")) {
        inner.text = parameterName(format);
      } else if (op && format.consume_front("type")) {
        std::optional<Element> directive = typeDirective("type", format, why);
        if (!directive)
          return std::nullopt;
        inner = std::move(*directive);
      } else {
        why = "`qualified` of no parameter";
        return std::nullopt;
      }
      format = format.ltrim();
      if (!format.consume_front(")")) {
        why = "`qualified` of more than a parameter";
        return std::nullopt;
      }
      inner.anchor = format.consume_front("^") || inner.anchor;
      out.push_back(std::move(inner));
      continue;
    }
    if (format.consume_front("(")) {
      std::optional<std::vector<Element>> group = elements(format, true, why, op);
      if (!group)
        return std::nullopt;
      format = format.ltrim();
      if (!format.consume_front("?")) {
        why = "an optional group with an else branch";
        return std::nullopt;
      }
      out.push_back({Element::Group, "", false, std::move(*group)});
      continue;
    }
    StringRef word = format.take_while([](char c) { return llvm::isAlnum(c) || c == '-'; });
    if (op && (word == "attr-dict" || word == "attr-dict-with-keyword" || word == "operands" ||
               word == "results")) {
      format = format.drop_front(word.size());
      out.push_back({Element::Directive, word.str()});
      continue;
    }
    if (op && (word == "type" || word == "functional-type")) {
      format = format.drop_front(word.size());
      std::optional<Element> directive = typeDirective(word, format, why);
      if (!directive)
        return std::nullopt;
      out.push_back(std::move(*directive));
      continue;
    }
    why = word.empty() ? "an element the generator does not know"
                       : ("the directive `" + word + "`").str();
    return std::nullopt;
  }
}

// A literal as the declarative printer spaces it: a comma, an arrow and an
// equals sign apart from what follows, a keyword apart from both sides,
// brackets close up.
std::string spaced(StringRef text) {
  if (text == ",")
    return ", ";
  if (text == "->" || text == "=" || text == ":")
    return " " + text.str() + " ";
  if (!text.empty() && (llvm::isAlpha(text.front()) || text.front() == '_'))
    return " " + text.str() + " ";
  return text.str();
}

// One piece of a printer's text: a literal, or an expression.
struct Piece {
  bool isLiteral;
  std::string text;
};

void append(std::vector<Piece> &pieces, Piece piece) {
  if (piece.isLiteral && !pieces.empty() && pieces.back().isLiteral)
    pieces.back().text += piece.text;
  else
    pieces.push_back(std::move(piece));
}

// The expression of pieces: the one piece, or their concatenation.
std::string expression(const std::vector<Piece> &pieces) {
  std::vector<std::string> texts;
  for (const Piece &piece : pieces)
    texts.push_back(piece.isLiteral ? literal(piece.text) : piece.text);
  if (texts.size() == 1)
    return texts.front();
  return "fastConcat [" + llvm::join(texts, ", ") + "]";
}

// The parameter that anchors a group.
const Element *anchorOf(const Element &group) {
  for (const Element &e : group.group)
    if (e.form == Element::Parameter && e.anchor)
      return &e;
  return nullptr;
}

// The pieces that write `elements`, each parameter by its field; false,
// with the reason in `why`, for a parameter that is not one or a group
// without an anchor. Inside its group the anchor is the value the group
// is written for: the Just's, or the list that is not empty.
bool piecesOf(const std::vector<Element> &elements, const std::map<std::string, Field> &fields,
              std::vector<Piece> &out, std::vector<std::string> &written, std::string &why) {
  for (const Element &e : elements) {
    if (e.form == Element::Literal) {
      append(out, {true, spaced(e.text)});
      continue;
    }
    if (e.form == Element::Parameter) {
      auto field = fields.find(e.text);
      if (field == fields.end()) {
        why = llvm::formatv("its syntax names `{0}`, which is no parameter", e.text).str();
        return false;
      }
      const Field &f = field->second;
      written.push_back(e.text);
      std::string text = llvm::formatv(f.text.c_str(), f.name).str();
      append(out, {false, f.presence == Presence::IfJust
                              ? llvm::formatv("maybe \"\" (\\{0} => {1}) {0}", f.name, text).str()
                              : "(" + text + ")"});
      continue;
    }
    const Element *anchor = anchorOf(e);
    if (!anchor || !fields.count(anchor->text)) {
      why = "an optional group without the parameter that anchors it";
      return false;
    }
    std::map<std::string, Field> inside = fields;
    const Field &f = fields.at(anchor->text);
    inside[anchor->text].presence = Presence::Always;
    std::vector<Piece> inner;
    if (!piecesOf(e.group, inside, inner, written, why))
      return false;
    switch (f.presence) {
    case Presence::IfJust:
      append(out, {false, llvm::formatv("maybe \"\" (\\{0} => {1}) {0}", f.name,
                                        expression(inner))
                              .str()});
      break;
    case Presence::IfNonEmpty:
      append(out, {false, llvm::formatv("(if null {0} then \"\" else {1})", f.name,
                                        expression(inner))
                              .str()});
      break;
    case Presence::Always:
      for (Piece &piece : inner)
        append(out, std::move(piece));
      break;
    }
  }
  return true;
}

// Whether an Idris type names `word`.
bool mentions(StringRef type, StringRef word) {
  llvm::SmallVector<StringRef> words;
  type.split(words, ' ');
  return llvm::any_of(words, [&](StringRef w) { return w.trim("()") == word; });
}

// A type or an attribute as the syntax module writes it: its constructor,
// with its documentation, and the clauses of its mnemonic and its printer.
struct Def {
  std::string constructor; // its declaration in the sum
  std::string mnemonicName;
  std::string mnemonic;    // the clause of the mnemonic, after its function
  std::string text;        // the clause of the printer, after its printers
};

// The constructor of a type or an attribute and its text; or, when it is not
// generated, why.
std::optional<std::string> defOf(Enums &enums, const AttrOrTypeDef &def, bool isType, StringRef sum,
                                 Def &out) {
  std::optional<StringRef> mnemonic = def.getMnemonic();
  if (!mnemonic)
    return std::string("it has no mnemonic");
  if (def.hasCustomAssemblyFormat())
    return std::string("its syntax is C++");
  std::vector<Field> fields;
  std::map<std::string, Field> byName;
  for (const AttrOrTypeParameter &param : def.getParameters()) {
    // The type of an attribute's value is the op's that holds it.
    if (llvm::isa<mlir::tblgen::AttributeSelfTypeParameter>(param))
      continue;
    std::string why;
    std::optional<Field> field = fieldOf(enums, param, fields.size(), why);
    if (!field)
      return why;
    // A type holds types: the sum of types has no attribute to give.
    if (isType && mentions(field->type, "at"))
      return llvm::formatv("its parameter `{0}` is an attribute, which no type holds",
                           param.getName())
          .str();
    fields.push_back(*field);
    byName[param.getName().str()] = *field;
  }
  std::vector<Element> syntax;
  if (std::optional<StringRef> format = def.getAssemblyFormat()) {
    StringRef rest = *format;
    std::string why;
    std::optional<std::vector<Element>> parsed = elements(rest, false, why, false);
    if (!parsed)
      return llvm::formatv("its syntax `{0}` has {1}", *format, why).str();
    syntax = *parsed;
  } else if (!fields.empty()) {
    return std::string("it has parameters and no syntax");
  }
  std::string spelling = ((isType ? "!" : "#") + def.getDialect().getName() + "." + *mnemonic).str();
  std::vector<Piece> pieces{{true, spelling}};
  std::vector<std::string> written;
  std::string why;
  if (!piecesOf(syntax, byName, pieces, written, why))
    return why;
  for (const auto &[name, field] : byName)
    if (!llvm::is_contained(written, name))
      return llvm::formatv("its syntax leaves out `{0}`", name).str();

  std::string constructor = def.getCppClassName().str();
  std::string pattern = constructor;
  std::string wildcard = constructor;
  llvm::raw_string_ostream decl(out.constructor);
  decl << "  ||| `" << spelling << "`" << summary(def.getSummary()) << "\n  " << constructor
       << " : ";
  for (const Field &f : fields) {
    decl << "(" << f.name << " : " << f.type << ") -> ";
    pattern += " " + f.name;
    wildcard += " _";
  }
  decl << sum << (isType ? " ty" : " ty at") << "\n";
  if (!fields.empty()) {
    pattern = "(" + pattern + ")";
    wildcard = "(" + wildcard + ")";
  }
  out.mnemonic = llvm::formatv("{0} = {1}", wildcard, literal(*mnemonic)).str();
  out.text = llvm::formatv("{0} = {1}", pattern, expression(pieces)).str();
  out.mnemonicName = mnemonic->str();
  return std::nullopt;
}

// The last name of a dotted module name.
StringRef lastName(StringRef module) {
  size_t dot = module.rfind('.');
  return dot == StringRef::npos ? module : module.drop_front(dot + 1);
}

// Whether `record` is an identified type: a TypeDef with MutableType, a
// name whose body is set once.
bool isIdentified(const llvm::Record &record) {
  return llvm::any_of(record.getValueAsListOfDefs("traits"),
                      [](const llvm::Record *trait) { return trait->getName() == "MutableType"; });
}

// An identified type, as its C++ printer writes it: `<"name">` inside its
// own body, `<"name", kind [@C(fields) by_name, ...] instance #d.instance<
// origin, [arguments]>>` everywhere else. Its constructor holds the name
// and, where it is written whole, the body: a record of the kind (the enum
// its ODS names as `bodyKinds`), the constructors in tag order and the
// instance. The records and the writer of a constructor are `preamble`,
// which goes before the sum of types that holds them.
void identifiedOf(Enums &enums, const AttrOrTypeDef &def, StringRef sum, Def &out,
                  std::string &preamble) {
  const llvm::Record *kinds = def.getDef()->getValueAsDef("bodyKinds");
  useEnum(enums, kinds).spellings = true;
  std::string kind = enumName(EnumInfo(kinds));
  std::string dialect = def.getDialect().getName().str();
  std::string module = lastName(moduleName).str();
  std::string ctor = module + "Ctor", body = module + "Sum";
  std::string ctorText = camel(dialect, false) + "CtorText";
  std::string mnemonic = def.getMnemonic() ? def.getMnemonic()->str() : std::string();
  std::string spelling = "!" + dialect + "." + mnemonic;
  llvm::raw_string_ostream pre(preamble);
  pre << "||| One constructor of a data type's body, as `" << spelling << "` writes it: its\n"
      << "||| name, its fields' types, and whether every force of it runs it.\n"
      << "public export\nrecord " << ctor << " ty where\n  constructor Mk" << ctor << "\n"
      << "  name : String\n  fields : List ty\n  byName : Bool\n\n"
      << "||| A data type's body, as `" << spelling << "` writes it: what sum it is, its\n"
      << "||| constructors in tag order, and the Idris instance it is of, its origin\n"
      << "||| and arguments.\n"
      << "public export\nrecord " << body << " ty where\n  constructor Mk" << body << "\n"
      << "  kind : " << kind << "\n  ctors : List (" << ctor << " ty)\n"
      << "  instanceOf : Maybe (String, List String)\n\n"
      << "-- How `" << spelling << "` writes a constructor of its body.\n"
      << ctorText << " : (t : ty -> String) -> " << ctor << " ty -> String\n"
      << ctorText << " t c = fastConcat [symbol c.name, \"(\", commaSeparated (map t c.fields), "
      << "\")\", if c.byName then \" by_name\" else \"\"]\n\n";
  std::string constructor = def.getCppClassName().str();
  llvm::raw_string_ostream decl(out.constructor);
  decl << "  ||| `" << spelling << "`" << summary(def.getSummary())
       << "; written without its body inside its own body\n  " << constructor
       << " : (name : String) -> (body : Maybe (" << body << " ty)) -> " << sum << " ty\n";
  out.mnemonicName = mnemonic;
  out.mnemonic = llvm::formatv("({0} _ _) = {1}", constructor, literal(mnemonic)).str();
  out.text = llvm::formatv(
                 "({0} name body) = fastConcat [{1}, utf8 name, maybe \"\" (\\b => fastConcat "
                 "[\", \", {2}Spelling b.kind, \" [\", commaSeparated (map ({3} t) b.ctors), "
                 "\"]\", maybe \"\" (\\i => fastConcat [\" instance #{4}.instance<\", utf8 (fst i), "
                 "\", \", array utf8 (snd i), \">\"]) b.instanceOf]) body, \">\"]",
                 constructor, literal(spelling + "<"), camel(kind, false), ctorText, dialect)
                 .str();
}

//===----------------------------------------------------------------------===//
// Printers of ops
//===----------------------------------------------------------------------===//

// An op's printer writes its head: its full name and its declarative syntax
// up to its regions, which the syntax puts last and the caller writes after
// it, since IdrisMLIR.MLIR, which the ops' module imports, writes the
// statements a region holds. Every type and attribute is written qualified,
// which the generated C++ parser reads wherever the syntax has the stripped
// form: the stripped form is a choice of the C++ printer. An op whose
// operands, results, regions or attributes are not what its ODS lets it
// have is written generic, which carries it to the verifier: the printer
// never drops a value, and never makes one up.

// What a name in an op's syntax stands for: an operand or a result, bound
// by its position to `o<i>` or `r<i>`, a region, or an attribute, found by
// its name among the properties.
struct Variable {
  enum Role { Operand, Attribute, Property, Region, Result } role;
  size_t index = 0;
  char arity = '1';
  std::string writer = {};                // the function that writes an attribute
  const llvm::Record *keywords = nullptr; // the enum whose keyword writes it
  bool unit = false;                      // written by its group's keyword alone
  bool omittable = false;                 // an attribute the op may lack
};

// How an op's syntax writes an attribute, as the op's C++ printer does: a
// symbol's name as a symbol, an integer enum by its keyword, a value of a
// buildable type without the type, which the parser is given and does not
// read; any other as itself. False, with the reason in `why`, for a bit
// enum stored as an integer, which is written as its bits.
bool writerOf(const Enums &enums, const NamedAttribute &attribute, Variable &v, std::string &why) {
  mlir::tblgen::Attribute base = attribute.attr.getBaseAttr();
  if (base.isEnumAttr() && base.getDef().isSubClassOf("EnumInfo")) {
    EnumInfo info(&base.getDef());
    if (info.isBitEnum()) {
      why = llvm::formatv("its attribute `{0}` is a bit enum stored as an integer", attribute.name)
                .str();
      return false;
    }
    // The builder gives the integer only of an enum it found stored as one.
    if (!enums.count(enumName(info))) {
      why = llvm::formatv("its attribute `{0}` is an enum its builder gives as any attribute",
                          attribute.name)
                .str();
      return false;
    }
    v.keywords = &base.getDef();
    v.writer = camel(enumName(info), false) + "Keyword";
    return true;
  }
  std::optional<mlir::tblgen::Type> type = base.getValueType();
  if (base.getAttrDefName() == "SymbolNameAttr")
    v.writer = "symbolName";
  else if (type && type->getBuilderCall())
    v.writer = "bare";
  else
    v.writer = "attrText";
  return true;
}

// The names an op's syntax may use, and the arities of its operands and
// results by position.
struct Names {
  std::map<std::string, Variable> variables;
  std::vector<char> operands, results;
  size_t regions = 0;
};

// The names of `op`; nothing, with the reason in `why`, for an op whose
// operands or results vary in length in more than one group, which only a
// segment-size property tells apart.
std::optional<Names> namesOf(const Enums &enums, const Operator &op, std::string &why) {
  Names names;
  for (int index = 0, e = op.getNumArgs(); index < e; ++index) {
    mlir::tblgen::Argument arg = op.getArg(index);
    if (const auto *operand = llvm::dyn_cast_if_present<NamedTypeConstraint *>(arg)) {
      names.variables[operand->name.str()] = {Variable::Operand, names.operands.size(),
                                              arity(*operand)};
      names.operands.push_back(arity(*operand));
      continue;
    }
    if (const auto *property = llvm::dyn_cast_if_present<NamedProperty *>(arg)) {
      names.variables[property->name.str()] = {Variable::Property};
      continue;
    }
    const auto *attribute = llvm::dyn_cast_if_present<NamedAttribute *>(arg);
    if (!attribute || attribute->attr.isDerivedAttr())
      continue;
    Variable v{Variable::Attribute};
    v.unit = attribute->attr.getBaseAttr().getStorageType().trim() == "::mlir::UnitAttr";
    v.omittable = attribute->attr.isOptional() || attribute->attr.hasDefaultValue();
    if (!v.unit && !writerOf(enums, *attribute, v, why))
      return std::nullopt;
    names.variables[attribute->name.str()] = v;
  }
  for (const NamedRegion &region : op.getRegions()) {
    names.variables[region.name.str()] = {Variable::Region, names.regions,
                                          region.isVariadic() ? '*' : '1'};
    ++names.regions;
  }
  for (const NamedTypeConstraint &result : op.getResults()) {
    names.variables[result.name.str()] = {Variable::Result, names.results.size(), arity(result)};
    names.results.push_back(arity(result));
  }
  auto varying = [](const std::vector<char> &arities) {
    return llvm::count_if(arities, [](char a) { return a != '1'; });
  };
  if (varying(names.operands) > 1 || varying(names.results) > 1 ||
      op.getTrait("::mlir::OpTrait::AttrSizedOperandSegments") ||
      op.getTrait("::mlir::OpTrait::AttrSizedResultSegments")) {
    why = "its operands or results vary in length in more than one group";
    return std::nullopt;
  }
  return names;
}

// What a clause of the printer is written from, gathered as its syntax is
// read: the names; the Idris variable an optional group binds to the
// attribute that anchors it (none for a unit attribute); the lines of the
// clause's `do` that look up the attributes always there; the keys of the
// attributes the syntax writes, and the enums whose keywords it writes;
// whether it writes the discardable attributes, and all the operands or
// all the results; and whether a region came, after which only regions do.
struct Printing {
  Names names;
  std::map<std::string, std::string> bound = {};
  std::vector<std::string> lookups = {}, keys = {};
  std::vector<const llvm::Record *> keywords = {};
  size_t fresh = 0;
  bool attrDict = false, allOperands = false, allResults = false, regions = false;
  std::string why = {};

  bool fail(const std::string &reason) {
    why = reason;
    return false;
  }
};

std::string valueName(const Variable &v) {
  return (v.role == Variable::Result ? "r" : "o") + std::to_string(v.index);
}

// An attribute the syntax writes, by its key.
void written(const std::string &key, const Variable &v, Printing &p) {
  p.keys.push_back(key);
  if (v.keywords)
    p.keywords.push_back(v.keywords);
}

// The types an argument of a type directive names, as an Idris list, and,
// for one value, its type alone.
bool typesOf(const std::string &arg, Printing &p, std::string &list, std::string &one) {
  one.clear();
  if (arg == "operands") {
    p.allOperands = true;
    list = "map (.type) os";
    return true;
  }
  if (arg == "results") {
    p.allResults = true;
    list = "rs";
    return true;
  }
  std::string name = arg.substr(1);
  auto found = p.names.variables.find(name);
  if (found == p.names.variables.end() ||
      (found->second.role != Variable::Operand && found->second.role != Variable::Result))
    return p.fail("its syntax has a type directive of `" + name +
                  "`, which is no operand or result");
  const Variable &v = found->second;
  std::string value = valueName(v);
  bool operand = v.role == Variable::Operand;
  if (v.arity == '1') {
    one = operand ? value + ".type" : value;
    list = "[" + one + "]";
  } else {
    list = operand ? "map (.type) " + value : value;
  }
  return true;
}

// Whether an element is a whitespace literal, which writes itself and takes
// no space beside it.
bool isSpacing(const Element &e) {
  return e.form == Element::Literal && (e.text.empty() || e.text == " " || e.text == "\\n");
}

bool isLiteral(const Element *e, std::initializer_list<StringRef> texts) {
  return e && e->form == Element::Literal && llvm::is_contained(texts, StringRef(e->text));
}

// Whether the printer writes a space before `e`, after `previous`: before
// every element but a comma or a closing bracket, and but what follows an
// opening bracket; an opening bracket after a variable closes up to it
// (`@T::@A(%n)`, `%v[@A, 0]`), and a dictionary writes its own.
bool spaceBefore(const Element *previous, const Element &e) {
  if (isSpacing(e) || (previous && isSpacing(*previous)))
    return false;
  if (e.form == Element::Directive && StringRef(e.text).starts_with("attr-dict"))
    return false;
  if (isLiteral(&e, {",", ")", "]", ">"}) || isLiteral(previous, {"(", "[", "<"}))
    return false;
  return !(isLiteral(&e, {"(", "[", "<"}) && previous && previous->form == Element::Parameter);
}

// Writes `text`, after a space when `space`; a list's only when the list,
// `list`, is not empty, so that an empty one writes nothing.
void put(std::vector<Piece> &out, bool space, const std::string &text,
         const std::string &list = "") {
  if (space && !list.empty()) {
    append(out,
           {false, llvm::formatv("(if null {0} then \"\" else \" \" ++ {1})", list, text).str()});
    return;
  }
  if (space)
    append(out, {true, " "});
  append(out, {false, text});
}

// A variable of an op's syntax, as its role writes it.
bool variable(const Element &e, const Variable &v, bool space, Printing &p,
              std::vector<Piece> &out) {
  std::string value = valueName(v);
  switch (v.role) {
  case Variable::Operand:
    if (v.arity == '1')
      put(out, space, value + ".name");
    else
      put(out, space, "commaSeparated (map (.name) " + value + ")", value);
    return true;
  case Variable::Attribute: {
    auto bound = p.bound.find(e.text);
    if (bound != p.bound.end()) {
      if (!v.unit)
        put(out, space, v.writer + " " + bound->second);
      return true;
    }
    if (v.unit || v.omittable)
      return p.fail("its syntax has the attribute `" + e.text +
                    "`, which the op may lack, outside an optional group");
    std::string name = "a" + std::to_string(p.fresh++);
    p.lookups.push_back(name + " <- lookup " + literal(e.text) + " props");
    written(e.text, v, p);
    put(out, space, v.writer + " " + name);
    return true;
  }
  case Variable::Property:
    return p.fail("its syntax has the property `" + e.text + "`, which is no attribute");
  case Variable::Region:
    if (v.arity != '1')
      return p.fail("its syntax has the variadic region `" + e.text + "`");
    p.regions = true;
    return true;
  case Variable::Result:
    return p.fail("its syntax has the result `" + e.text + "` outside a type directive");
  }
  return true;
}

// A directive of an op's syntax: a dictionary of the discardable
// attributes, or types.
bool directive(const Element &e, bool space, Printing &p, std::vector<Piece> &out) {
  if (e.text == "attr-dict" || e.text == "attr-dict-with-keyword") {
    p.attrDict = true;
    append(out, {false, e.text == "attr-dict" ? "dictionary \"{\" \"}\" attrs"
                                              : "dictionary \"attributes {\" \"}\" attrs"});
    return true;
  }
  if (e.text == "operands" || e.text == "results")
    return p.fail("its syntax has the directive `" + e.text + "` outside a type directive");
  std::vector<std::string> lists;
  std::string one;
  for (const std::string &arg : e.args) {
    std::string list;
    if (!typesOf(arg, p, list, one))
      return false;
    lists.push_back(list);
  }
  // The results in parentheses always, which the parser reads for one
  // result as for several.
  if (e.text == "functional-type")
    put(out, space, "signature typeText (MkSignature (" + lists[0] + ") (" + lists[1] + "))");
  else if (!one.empty())
    put(out, space, "typeText " + one);
  else
    put(out, space, "commaSeparated (map typeText (" + lists[0] + "))", "(" + lists[0] + ")");
  return true;
}

bool printed(const std::vector<Element> &syntax, const Element *previous, bool inGroup,
             Printing &p, std::vector<Piece> &out);

// An optional group, written when its anchor is there: a list that is not
// empty, an attribute the op has. A unit attribute is the group's keyword
// alone, and a property that is no attribute is one the builders never
// set, so its group is never written. A group writes nothing but its
// literals, its anchor and the anchor's types, so that what it holds is
// there exactly when its anchor is.
bool group(const Element &g, const Element *before, Printing &p, std::vector<Piece> &out) {
  auto anchored = llvm::find_if(g.group, [](const Element &e) { return e.anchor; });
  if (anchored == g.group.end())
    return p.fail("its syntax has an optional group without an anchor");
  const Element &anchor = *anchored;
  for (const Element &e : g.group)
    if (&e != &anchor && e.form != Element::Literal &&
        !(e.form == Element::Directive && e.text == "type" &&
          anchor.form == Element::Parameter && e.args.front() == "$" + anchor.text))
      return p.fail("its syntax has an optional group that writes more than its anchor");
  std::string condition, key, binding;
  if (anchor.form == Element::Directive) {
    std::string list, one;
    if (anchor.text != "type" || !typesOf(anchor.args.front(), p, list, one) || !one.empty())
      return p.fail(p.why.empty() ? "its syntax has an optional group on what is always there"
                                  : p.why);
    condition = "not (null (" + list + "))";
  } else {
    auto found = p.names.variables.find(anchor.text);
    if (found == p.names.variables.end())
      return p.fail("its syntax names `" + anchor.text + "`, which the op does not have");
    const Variable &v = found->second;
    if (v.role == Variable::Property)
      return true;
    bool always = v.role == Variable::Operand ? v.arity == '1'
                  : v.role == Variable::Attribute ? !v.unit && !v.omittable
                                                  : true;
    if (always)
      return p.fail("its syntax has an optional group on `" + anchor.text +
                    "`, which is always there");
    if (v.role == Variable::Operand) {
      condition = "not (null " + valueName(v) + ")";
    } else {
      if (v.unit && &anchor == &g.group.front())
        return p.fail("its syntax has the unit attribute `" + anchor.text +
                      "` first in its optional group");
      written(anchor.text, v, p);
      key = anchor.text;
      binding = v.unit ? "" : "a" + std::to_string(p.fresh++);
      p.bound[key] = binding;
    }
  }
  std::vector<Piece> inner;
  if (!printed(g.group, before, true, p, inner))
    return false;
  p.bound.erase(key);
  std::string text = inner.empty() ? literal("") : expression(inner);
  if (!binding.empty())
    append(out, {false, llvm::formatv("maybe \"\" (\\{0} => {1}) (lookup {2} props)", binding,
                                      text, literal(key))
                            .str()});
  else if (!key.empty())
    append(out, {false, llvm::formatv("(if isJust (lookup {0} props) then {1} else \"\")",
                                      literal(key), text)
                            .str()});
  else
    append(out, {false, llvm::formatv("(if {0} then {1} else \"\")", condition, text).str()});
  return true;
}

// The pieces that write `syntax`, after `previous`; false, with the reason
// in `p.why`, for what the printer does not write.
bool printed(const std::vector<Element> &syntax, const Element *previous, bool inGroup,
             Printing &p, std::vector<Piece> &out) {
  for (const Element &e : syntax) {
    const Element *before = previous;
    previous = &e;
    bool space = spaceBefore(before, e);
    const Variable *v = nullptr;
    if (e.form == Element::Parameter) {
      auto found = p.names.variables.find(e.text);
      if (found == p.names.variables.end())
        return p.fail("its syntax names `" + e.text + "`, which the op does not have");
      v = &found->second;
    }
    if (p.regions && !(v && v->role == Variable::Region))
      return p.fail("its syntax has a region before its end");
    switch (e.form) {
    case Element::Literal:
      if (e.text == "\\n")
        append(out, {false, "\"\\n\""});
      else if (!e.text.empty())
        append(out, {true, (space ? " " : "") + e.text});
      break;
    case Element::Parameter:
      if (!variable(e, *v, space, p, out))
        return false;
      break;
    case Element::Directive:
      if (!directive(e, space, p, out))
        return false;
      break;
    case Element::Group:
      if (inGroup)
        return p.fail("its syntax has an optional group in an optional group");
      if (!group(e, before, p, out))
        return false;
      break;
    }
  }
  return true;
}

// The pattern that binds an op's operands (`o`) or results (`r`) by their
// positions, and the lines of the clause's `do` that bind what a pattern
// cannot: the values of the group that varies in length, between the
// singles before it and the singles after it. When a directive writes all
// of them (`whole`), the pattern binds the list, and a line takes it apart.
std::string bindingOf(char prefix, const std::vector<char> &arities, bool whole,
                      std::vector<std::string> &lines) {
  auto value = [&](size_t i) { return std::string(1, prefix) + std::to_string(i); };
  auto bracketed = [&](size_t from, size_t to) {
    std::string out = "[";
    for (size_t i = from; i < to; ++i)
      out += (i == from ? "" : ", ") + value(i);
    return out + "]";
  };
  std::string rest = std::string(1, prefix) + "rest", tail = std::string(1, prefix) + "tail";
  std::vector<std::string> later;
  std::string pattern;
  auto varying = llvm::find_if(arities, [](char a) { return a != '1'; });
  if (varying == arities.end()) {
    pattern = bracketed(0, arities.size());
  } else {
    size_t at = static_cast<size_t>(varying - arities.begin());
    size_t after = arities.size() - at - 1;
    std::string singles;
    for (size_t i = 0; i < at; ++i)
      singles += value(i) + " :: ";
    std::string last = after == 0 ? value(at) : rest;
    pattern = singles.empty() ? last : "(" + singles + last + ")";
    if (after != 0) {
      later.push_back(llvm::formatv("let ({0}, {1}) = splitAt (minus (length {2}) {3}) {2}",
                                    value(at), tail, rest, after)
                          .str());
      later.push_back(bracketed(at + 1, arities.size()) + " <- pure " + tail + " | _ => Nothing");
    }
    if (*varying == '?')
      later.push_back("guard (length " + value(at) + " <= 1)");
  }
  if (whole) {
    std::string all = prefix == 'o' ? "os" : "rs";
    bool named = pattern.front() != '[' && pattern.front() != '(';
    lines.push_back(named ? "let " + pattern + " = " + all
                             : pattern + " <- pure " + all + " | _ => Nothing");
    pattern = all;
  }
  lines.insert(lines.end(), later.begin(), later.end());
  return pattern;
}

// The clause of printOp that writes `op`; or, when the op is written
// generic, why.
std::optional<std::string> printerOf(Enums &enums, const Operator &op, std::string &clause) {
  if (op.getDef().getValueAsBit("hasCustomAssemblyFormat"))
    return std::string("its syntax is C++");
  std::optional<StringRef> format = op.getDef().getValueAsOptionalString("assemblyFormat");
  if (!format)
    return std::string("it has no declarative syntax");
  StringRef rest = *format;
  std::string why;
  std::optional<std::vector<Element>> syntax = elements(rest, false, why, true);
  if (!syntax)
    return "its syntax has " + why;
  std::optional<Names> names = namesOf(enums, op, why);
  if (!names)
    return why;
  Printing p{std::move(*names)};
  std::string name = op.getOperationName();
  std::vector<Piece> pieces{{true, name}};
  if (!printed(*syntax, nullptr, false, p, pieces))
    return p.why;
  for (const auto &[key, v] : p.names.variables)
    if (v.role == Variable::Attribute && !v.unit && !v.omittable &&
        !llvm::is_contained(p.keys, key))
      return llvm::formatv("its format leaves out `{0}`", key).str();
  for (const llvm::Record *def : p.keywords)
    useEnum(enums, def).keywords = true;

  std::vector<std::string> lines;
  std::string operands = bindingOf('o', p.names.operands, p.allOperands, lines);
  std::string results = bindingOf('r', p.names.results, p.allResults, lines);
  std::string regions = "[";
  for (size_t i = 0; i < p.names.regions; ++i)
    regions += i == 0 ? "_" : ", _";
  regions += "]";
  // An attribute the syntax does not write, or one ODS does not declare,
  // would be lost: such an op is written generic.
  if (p.keys.empty()) {
    lines.push_back("guard (null props)");
  } else {
    std::vector<std::string> keys;
    for (const std::string &key : p.keys)
      keys.push_back(literal(key));
    lines.push_back("guard (all (\\p => elem (fst p) [" + llvm::join(keys, ", ") + "]) props)");
  }
  if (!p.attrDict)
    lines.push_back("guard (null attrs)");
  lines.insert(lines.end(), p.lookups.begin(), p.lookups.end());
  llvm::raw_string_ostream os(clause);
  os << "printOp (MkOp " << literal(name) << " " << operands << " props " << regions << " attrs "
     << results << ") = do\n";
  for (const std::string &line : lines)
    os << "  " << line << "\n";
  os << "  pure (" << expression(pieces) << ")\n\n";
  return std::nullopt;
}

//===----------------------------------------------------------------------===//
// Discardable attributes
//===----------------------------------------------------------------------===//

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
      os << " : NamedAttr\n" << name << " = (" << key << ", UnitAttr)\n\n";
    else if (type == "::mlir::StringAttr")
      os << " : String -> NamedAttr\n" << name << " s = (" << key << ", StringAttr s)\n\n";
    else
      os << " : MlirAttr -> NamedAttr\n" << name << " a = (" << key << ", a)\n\n";
  }
}

//===----------------------------------------------------------------------===//
// The modules
//===----------------------------------------------------------------------===//

// What both modules of a dialect are written from, read once: its types and
// attributes, its ops by name with the clauses of their printer (and the
// ops written generic, with the reason), its primitives in the order ODS
// declares them, and, found on the way, the enums all of them take.
struct Vocabulary {
  std::optional<mlir::tblgen::Dialect> dialect;
  std::vector<Def> types, attrs;
  std::vector<std::string> omitted, generic;
  // What the sum of types holds besides types: an identified type's body.
  std::string typesPreamble;
  std::string ops, printer, primitives;
  Enums enums;
};

Vocabulary read(const llvm::RecordKeeper &records, StringRef generator) {
  if (dialectName.empty() || moduleName.empty())
    llvm::PrintFatalError("-" + generator + " needs -idris-dialect and -idris-module");
  Vocabulary v;
  for (const llvm::Record *def : records.getAllDerivedDefinitions("Dialect"))
    if (def->getValueAsString("name") == dialectName)
      v.dialect.emplace(def);
  if (!v.dialect)
    llvm::PrintFatalError("no dialect " + dialectName + " in the records");
  StringRef module = lastName(moduleName);
  for (StringRef kind : {"TypeDef", "AttrDef"})
    for (const llvm::Record *record : records.getAllDerivedDefinitionsIfDefined(kind)) {
      AttrOrTypeDef def(record);
      if (def.getDialect().getName() != dialectName)
        continue;
      bool isType = kind == "TypeDef";
      Def written;
      if (isType && isIdentified(*record)) {
        identifiedOf(v.enums, def, (module + "Type").str(), written, v.typesPreamble);
        v.types.push_back(std::move(written));
        continue;
      }
      if (std::optional<std::string> why =
              defOf(v.enums, def, isType, (module + (isType ? "Type" : "Attr")).str(), written))
        v.omitted.push_back(llvm::formatv("{0} {1}: {2}", isType ? "type" : "attribute",
                                          def.getCppClassName(), *why)
                                .str());
      else
        (isType ? v.types : v.attrs).push_back(std::move(written));
    }
  std::vector<const llvm::Record *> dialectOps;
  std::vector<std::pair<std::string, const llvm::Record *>> byName;
  for (const llvm::Record *def : records.getAllDerivedDefinitions("Op")) {
    Operator op(def);
    if (op.getDialectName() != dialectName)
      continue;
    dialectOps.push_back(def);
    byName.emplace_back(op.getOperationName(), def);
  }
  llvm::sort(byName);
  {
    llvm::raw_string_ostream opsOs(v.ops), primitivesOs(v.primitives);
    for (const auto &[name, def] : byName) {
      Operator op(def);
      emitOp(v.enums, op, opsOs);
      std::string clause;
      if (std::optional<std::string> why = printerOf(v.enums, op, clause))
        v.generic.push_back(llvm::formatv("op {0}: {1}", name, *why).str());
      else
        v.printer += clause;
    }
    emitPrimitives(dialectOps, primitivesOs);
  }
  return v;
}

// A dialect's sum of types or of attributes, its mnemonics and its printer.
void emitSum(const std::vector<Def> &defs, bool isType, llvm::raw_ostream &os) {
  if (defs.empty())
    return;
  std::string what = isType ? "type" : "attribute";
  std::string sum = (lastName(moduleName) + (isType ? "Type" : "Attr")).str();
  std::string lower = camel(dialectName, false) + (isType ? "Type" : "Attr");
  std::string params = isType ? " ty" : " ty at";
  os << "||| The " << dialectName << " dialect's " << what << "s, one constructor each, named\n"
     << "||| after its C++ class; `ty` is the type of the types they hold"
     << (isType ? "" : ", `at` of the\n||| attributes") << ".\n"
     << "public export\ndata " << sum << " : (ty : Type) -> "
     << (isType ? "" : "(at : Type) -> ") << "Type where\n";
  for (const Def &def : defs)
    os << def.constructor;
  os << "\n||| The mnemonics of the " << dialectName << " dialect's " << what << "s.\n"
     << "export\n" << lower << "Mnemonics : List String\n" << lower << "Mnemonics = [";
  llvm::interleave(
      defs, [&](const Def &def) { os << literal(def.mnemonicName); }, [&] { os << ", "; });
  os << "]\n\n||| The mnemonic of each of the " << dialectName << " dialect's " << what << "s.\n"
     << "export\n" << lower << "Mnemonic : " << sum << params << " -> String\n";
  for (const Def &def : defs)
    os << lower << "Mnemonic " << def.mnemonic << "\n";
  os << "\n||| The text of each of the " << dialectName << " dialect's " << what
     << "s, the types it\n||| holds written by `t`" << (isType ? "" : ", the attributes by `a`")
     << ".\n"
     << "export\n" << lower << "Text : (t : ty -> String) -> "
     << (isType ? "" : "(a : at -> String) -> ") << sum << params << " -> String\n";
  for (const Def &def : defs)
    os << lower << "Text t " << (isType ? "" : "a ") << def.text << "\n";
  os << "\n";
}

bool emitIdrisSyntax(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  Vocabulary v = read(records, "gen-idris-syntax");
  std::string enumerations, types, attrs;
  llvm::raw_string_ostream enumsOs(enumerations), typesOs(types), attrsOs(attrs);
  for (const auto &[name, used] : v.enums)
    emitEnum(used, enumsOs);
  typesOs << v.typesPreamble;
  emitSum(v.types, true, typesOs);
  emitSum(v.attrs, false, attrsOs);

  os << "||| The " << dialectName << " dialect's syntax, as the Idris side writes it: the enums\n"
     << "||| its ops, types and attributes take, and its types and attributes, which\n"
     << "||| IdrisMLIR.MLIR's types and attributes hold. Generated by idris-mlir-tblgen\n"
     << "||| -gen-idris-syntax from the dialect's ODS; `make build` writes it\n"
     << "||| (tools/dialects.sh). Do not edit.\n"
     << "module " << moduleName << "\n\nimport IdrisMLIR.MLIR.Text\n\n%default total\n\n";
  section(os, "Enums", enumerations);
  section(os, "Types", types);
  section(os, "Attributes", attrs);
  if (!v.omitted.empty()) {
    os << "-- Not generated:\n";
    for (const std::string &why : v.omitted)
      os << "-- " << why << "\n";
  }
  return false;
}

bool emitIdrisDialect(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  if (syntaxModuleName.empty())
    llvm::PrintFatalError("-gen-idris-dialect needs -idris-syntax-module");
  Vocabulary v = read(records, "gen-idris-dialect");
  std::string values, discardables;
  llvm::raw_string_ostream valuesOs(values), discardablesOs(discardables);
  for (const auto &[name, used] : v.enums)
    emitEnumValues(used, valuesOs);
  emitDiscardable(*v.dialect, discardablesOs);

  std::string printer;
  llvm::raw_string_ostream printerOs(printer);
  printerOs << "-- An attribute an op's syntax writes without its type, which the parser\n"
            << "-- is given and does not read.\ncovering\nbare : MlirAttr -> String\n"
            << "bare (IntegerAttr n _) = show n\nbare (FloatAttr d _) = floatLiteral d\n"
            << "bare a = attrText a\n\n"
            << "-- The name of the symbol an op declares, as a reference to it writes it.\n"
            << "covering\nsymbolName : MlirAttr -> String\n"
            << "symbolName (StringAttr s) = symbol s\nsymbolName a = attrText a\n\n";
  for (const auto &[name, used] : v.enums)
    emitEnumKeywords(used, printerOs);
  printerOs << "||| An op of the " << dialectName << " dialect in the declarative syntax its ODS\n"
            << "||| gives, up to its regions: its full name and its syntax, which puts the\n"
            << "||| regions last, for the caller to write after it. Nothing for an op\n"
            << "||| written in the generic form: one whose syntax this printer does not\n"
            << "||| write (each is named below, with the reason), one of another dialect,\n"
            << "||| and one whose operands, results, regions or attributes are not what its\n"
            << "||| ODS lets it have, which the generic form carries to the verifier.\n"
            << "export covering\nprintOp : Op -> Maybe String\n"
            << v.printer << "printOp _ = Nothing\n\n";
  if (!v.generic.empty()) {
    printerOs << "-- Written in the generic form:\n";
    for (const std::string &why : v.generic)
      printerOs << "-- " << why << "\n";
    printerOs << "\n";
  }

  os << "||| The " << dialectName << " dialect, as the Idris side writes it. Generated by\n"
     << "||| idris-mlir-tblgen -gen-idris-dialect from the dialect's ODS; `make build`\n"
     << "||| writes it (tools/dialects.sh). Do not edit.\n"
     << "module " << moduleName << "\n\nimport IdrisMLIR.MLIR\nimport " << syntaxModuleName
     << "\n\nimport Data.List\nimport Data.Maybe\n\n%default total\n\n";
  section(os, "Enums", values);
  section(os, "Discardable attributes", discardables);
  section(os, "Ops", v.ops);
  section(os, "Printer", printer);
  section(os, "Primitives", v.primitives);
  return false;
}

const mlir::GenRegistration genIdrisSyntax("gen-idris-syntax",
                                           "The Idris side's syntax of a dialect",
                                           emitIdrisSyntax);
const mlir::GenRegistration genIdrisDialect("gen-idris-dialect",
                                            "The Idris side's ops of a dialect",
                                            emitIdrisDialect);

} // namespace

int main(int argc, char **argv) { return mlir::MlirTblgenMain(argc, argv); }
