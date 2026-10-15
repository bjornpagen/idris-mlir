// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir-tblgen: mlir-tblgen with the generators of what the dialect's
// ODS says to the rest of the tree, so that each fact about an op is said
// once, beside the op, and every other reader of it is generated:
//
// - -gen-idris-syntax, a dialect's syntax for the Idris side: the enums its
//   ops, types and attributes take, and its types and attributes, each a
//   constructor of the dialect's sum of types or of attributes, with the
//   printer that writes it in the syntax ODS declares for it. IdrisMLIR.MLIR's
//   types and attributes hold these sums (compiler/src/IdrisMLIR/Syntax/).
// - -gen-idris-dialect, a dialect's ops for the Idris side: a builder of each
//   op, over its operands, inherent attributes and properties, regions and
//   results; its discardable attributes; its primitives, the ops Idris
//   names, each a constructor the Idris side builds it from; and the guards
//   its partial ops take (compiler/src/IdrisMLIR/Dialect/).
// - -gen-runtime-abi-decls and -gen-runtime-abi-defs, the runtime's C
//   functions the ops call (Idr_Runtime): their C prototypes, which the
//   runtime's header includes, so that a definition that does not match its
//   op fails to compile; and the table the lowering and the folders read.
// - -gen-big-to-word, the word op each big op names (Idr_WordOp).
// - -gen-rule-list, the rules a refusal of a program names, each with its
//   category, one per line, for the tests to read.
//
// Emit writes MLIR only through the Idris modules, so what an op, a type or
// an attribute is, and how each of its parts is spelled, is said once: in
// ODS. Emit hands ops over in MLIR's generic form, which ODS says alone for
// every op (the name, the operands, the inherent attributes and properties,
// the regions, the discardable attributes and the types), so an op needs no
// printer on the Idris side.
//
// It is a TableGen backend rather than a program over a dump of the records
// because it then reads ODS through mlir::tblgen (Operator, Attribute,
// AttrOrTypeDef, EnumInfo), the reading the dialects' own C++ is generated
// from, so the two sides cannot take one op differently; and the pinned
// toolchain installs those libraries and mlir-tblgen, not llvm-tblgen.
//
// A type or an attribute has no generic form, so it is written in the
// syntax ODS declares for it, which the generated C++ parser reads; one
// whose syntax ODS does not declare is left out, with the reason, at the end
// of the syntax module. The syntax of a type the generator knows by itself
// is an identified type's (a TypeDef with MutableType), which no declarative
// syntax can say: its name, then its body, which a type inside its own body
// leaves out, as LLVM writes an identified struct.

#include "mlir/TableGen/AttrOrTypeDef.h"
#include "mlir/TableGen/Attribute.h"
#include "mlir/TableGen/Dialect.h"
#include "mlir/TableGen/EnumInfo.h"
#include "mlir/TableGen/GenInfo.h"
#include "mlir/TableGen/Operator.h"
#include "mlir/TableGen/Property.h"
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

#include <functional>
#include <map>
#include <optional>
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

// A constructor the generator writes, named after ODS (an enum's case, an
// op's or a type's C++ class), which must not be one of the Prelude's: in a
// namespace of its own it is still found where the Prelude's is meant (`[]`
// reads as any `Nil`), so the clash is fixed where ODS gives the name.
std::string constructorName(const std::string &name, const llvm::Twine &what) {
  static constexpr StringRef prelude[] = {"Nil",  "Just", "Nothing", "True",   "False", "LT",
                                          "EQ",   "GT",   "MkPair",  "Unit",   "MkUnit", "Left",
                                          "Right", "Z",   "S",       "Refl",   "Yes",   "No",
                                          "Lin",  "MkDPair", "Delay", "Force"};
  if (llvm::is_contained(prelude, StringRef(name)))
    llvm::PrintFatalError(what + " would be the Idris constructor `" + name +
                          "`, which is the Prelude's: rename it in ODS");
  return name;
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
// Marks
//===----------------------------------------------------------------------===//

// The records of the traits `op` lists that are of the TableGen class
// `name`, in the order ODS lists them, through the trait lists that hold
// them: a mark of the dialect's is a record of its class, whatever kind of
// trait it is.
std::vector<const llvm::Record *> traitsOfClass(const Operator &op, StringRef name) {
  std::vector<const llvm::Record *> found;
  std::function<void(const llvm::ListInit *)> walk = [&](const llvm::ListInit *traits) {
    for (const llvm::Init *init : traits->getElements()) {
      const llvm::Record *def = llvm::cast<llvm::DefInit>(init)->getDef();
      if (def->isSubClassOf(name) && !llvm::is_contained(found, def))
        found.push_back(def);
      if (def->isSubClassOf("TraitList"))
        walk(def->getValueAsListInit("traits"));
    }
  };
  walk(op.getDef().getValueAsListInit("traits"));
  return found;
}

// The one mark of class `name` on `op`, or none; two are a fault of ODS.
const llvm::Record *markOf(const Operator &op, StringRef name) {
  std::vector<const llvm::Record *> marks = traitsOfClass(op, name);
  if (marks.size() > 1)
    llvm::PrintFatalError(op.getLoc(), op.getOperationName() + " has more than one " + name);
  return marks.empty() ? nullptr : marks.front();
}

// The names a mark lists in one string, separated by commas.
std::vector<std::string> namesIn(StringRef list) {
  llvm::SmallVector<StringRef> parts;
  list.split(parts, ',', -1, false);
  std::vector<std::string> names;
  for (StringRef part : parts)
    names.push_back(part.trim().str());
  return names;
}

// The index of the operand group `name` of `op`, or none.
std::optional<int> operandNamed(const Operator &op, StringRef name) {
  for (int index = 0, e = op.getNumOperands(); index < e; ++index)
    if (op.getOperand(index).name == name)
      return index;
  return std::nullopt;
}

// The index of the result `name` of `op`, or none.
std::optional<int> resultNamed(const Operator &op, StringRef name) {
  for (int index = 0, e = op.getNumResults(); index < e; ++index)
    if (op.getResultName(index) == name)
      return index;
  return std::nullopt;
}

//===----------------------------------------------------------------------===//
// Enums
//===----------------------------------------------------------------------===//

// A field in which every case of an enum names a case of another enum (a
// rule's category): the Idris side reads it as a function from the one enum
// to the other, named after the enum and the field.
struct CaseField {
  std::string field;
  const llvm::Record *values; // the enum whose cases the field names
};

// The enums the dialect's ops, types and attributes take, by their ODS
// records: written once each, in the syntax module, with their spellings if
// a syntax prints one, and their values, in the ops' module, if an op stores
// one as an integer; and the fields in which their cases name another
// enum's.
struct Enum {
  const llvm::Record *def;
  bool values = false;
  bool spellings = false;
  std::vector<CaseField> caseFields = {};
};
using Enums = std::map<std::string, Enum>;

// The Idris name of an enum, and of its namespace.
std::string enumName(const EnumInfo &info) { return info.getEnumClassName().str(); }

Enum &useEnum(Enums &enums, const llvm::Record *def) {
  return enums.try_emplace(enumName(EnumInfo(def)), Enum{def}).first->second;
}

// The enums that list each case, for a case a field of another enum's case
// names.
using EnumsOfCases = std::map<const llvm::Record *, std::vector<const llvm::Record *>>;

EnumsOfCases enumsOfCases(const llvm::RecordKeeper &records) {
  EnumsOfCases out;
  for (const llvm::Record *def : records.getAllDerivedDefinitionsIfDefined("EnumInfo"))
    for (const llvm::Record *c : def->getValueAsListOfDefs("enumerants"))
      out[c].push_back(def);
  return out;
}

// The fields in which the cases of `info` name cases of another enum. Every
// case has each, so each function the Idris side reads them as is total.
std::vector<CaseField> caseFieldsOf(const EnumInfo &info, const EnumsOfCases &owners) {
  std::vector<CaseField> fields;
  std::vector<EnumCase> cases = info.getAllCases();
  for (const EnumCase &c : cases)
    for (const llvm::RecordVal &value : c.getDef().getValues()) {
      const auto *init = llvm::dyn_cast<llvm::DefInit>(value.getValue());
      if (!init || !init->getDef()->isSubClassOf("EnumCase"))
        continue;
      auto owner = owners.find(init->getDef());
      if (owner == owners.end() || owner->second.size() != 1)
        llvm::PrintFatalError(&c.getDef(), "the field `" + value.getName() + "` of the case " +
                                               c.getSymbol() + " names a case of no one enum");
      auto known =
          llvm::find_if(fields, [&](const CaseField &f) { return f.field == value.getName(); });
      if (known == fields.end())
        fields.push_back({value.getName().str(), owner->second.front()});
      else if (known->values != owner->second.front())
        llvm::PrintFatalError(&c.getDef(), "the field `" + value.getName() +
                                               "` names cases of two enums");
    }
  for (const CaseField &f : fields)
    for (const EnumCase &c : cases) {
      const llvm::RecordVal *value = c.getDef().getValue(f.field);
      if (!value || !llvm::isa<llvm::DefInit>(value->getValue()))
        llvm::PrintFatalError(&c.getDef(), "the case " + c.getSymbol() + " of " +
                                               info.getEnumClassName() + " has no `" + f.field +
                                               "`, which its other cases have");
    }
  return fields;
}

// The case of `values` a case names in `field`.
EnumCase namedCase(const EnumCase &c, StringRef field) {
  return EnumCase(c.getDef().getValueAsDef(field));
}

// Completes `enums` with the enums the cases of each name in a field, and
// records those fields: a worklist over the enums, each taken once.
void addCaseFields(Enums &enums, const EnumsOfCases &owners) {
  std::vector<std::string> pending;
  for (const auto &[name, used] : enums)
    pending.push_back(name);
  while (!pending.empty()) {
    std::string name = pending.back();
    pending.pop_back();
    std::vector<CaseField> fields = caseFieldsOf(EnumInfo(enums.at(name).def), owners);
    for (const CaseField &f : fields) {
      std::string target = enumName(EnumInfo(f.values));
      if (enums.try_emplace(target, Enum{f.values}).second)
        pending.push_back(target);
    }
    enums.at(name).caseFields = std::move(fields);
  }
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

// A case of an enum as the Idris side names it, and qualified: a case may
// share its name with an interface (Eq) or a case of another enum.
std::string caseName(const EnumInfo &info, const EnumCase &c) {
  return constructorName(camel(c.getSymbol(), true),
                         "the case " + c.getSymbol() + " of " + info.getEnumClassName());
}

std::string qualifiedCase(const EnumInfo &info, const EnumCase &c) {
  return enumName(info) + "." + caseName(info, c);
}

void emitEnum(const Enum &used, llvm::raw_ostream &os) {
  EnumInfo info(used.def);
  std::string name = enumName(info);
  std::vector<EnumCase> cases = idrisCases(info);
  os << "namespace " << name << "\n";
  os << "  ||| " << doc(info.getSummary()) << "\n";
  os << "  public export\n  data " << name << " = ";
  llvm::interleave(
      cases, [&](const EnumCase &c) { os << caseName(info, c); }, [&] { os << " | "; });
  os << "\n\n";
  os << "export\nPrelude.EqOrd.Eq " << name << " where\n";
  for (const EnumCase &c : cases) {
    std::string qualified = qualifiedCase(info, c);
    os << "  " << qualified << " == " << qualified << " = True\n";
  }
  os << "  _ == _ = False\n\n";
  // Each case shows as its ODS string, the one way a value of it reads.
  os << "export\nShow " << name << " where\n";
  for (const EnumCase &c : cases)
    os << "  show " << qualifiedCase(info, c) << " = " << literal(c.getStr()) << "\n";
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
    os << lower << "Spelling " << qualifiedCase(info, c) << " = "
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

// The functions of the fields in which an enum's cases name another enum's,
// after every enum, which each may name.
void emitCaseFields(const Enum &used, llvm::raw_ostream &os) {
  EnumInfo info(used.def);
  std::string name = enumName(info);
  for (const CaseField &f : used.caseFields) {
    EnumInfo values(f.values);
    std::string function = camel(name, false) + camel(f.field, true);
    os << "||| The " << f.field << " of each " << name << ".\n"
       << "export\n" << function << " : " << name << " -> " << enumName(values) << "\n";
    for (const EnumCase &c : info.getAllCases())
      os << function << " " << qualifiedCase(info, c) << " = "
         << qualifiedCase(values, namedCase(c, f.field)) << "\n";
    os << "\n";
  }
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
    os << lower << "Value " << qualifiedCase(info, c) << " = " << c.getValue() << "\n";
  os << "\n";
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

// How the ops' module writes a value of an enum stored as an integer of
// `width` bits, which the generic form writes as its value.
Kind enumValue(Enums &enums, const llvm::Record *def, int64_t width) {
  EnumInfo info(def);
  std::string name = enumName(info);
  useEnum(enums, def).values = true;
  return Kind{name, llvm::formatv("IntegerAttr ({0}Value {{0}) (IntegerType {1})",
                                  camel(name, false), width)
                        .str()};
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
  return enumValue(enums, &base.getDef(), info.getBitwidth());
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
  if (storage == "::mlir::DenseI32ArrayAttr")
    return {"List Nat", "DenseI32ArrayAttr {0}"};
  if (storage == "::mlir::DenseI64ArrayAttr")
    return {"List Integer", "DenseI64ArrayAttr {0}"};
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
      // claim: the Idris side writes the op at its default. One without a
      // default it could not write at all: the handoff carries an op's
      // inherent attributes, and a property that is no attribute is not
      // among them.
      const auto *property = llvm::cast<NamedProperty *>(arg);
      if (property->prop.hasDefaultValue())
        continue;
      llvm::PrintFatalError(op.getLoc(), operationName + " has the property `" + property->name +
                                             "`, which is no attribute and has no default: the "
                                             "Idris side cannot write it");
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
  Primitive primitive{constructorName(constructor.str(), "the primitive " + operationName),
                      operationName, op.getTrait("::idr::PerformsIO") != nullptr, std::nullopt};
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
// How the C ABI holds a value of each type
//===----------------------------------------------------------------------===//

// How a C function takes an operand of its op, or gives its op's result,
// spelled as the table's C++ names it, as C declares it, and as the name of
// a variant of the function takes it.
enum class Word {
  World, Int32, Int64, Double, Signed, Unsigned, Wrapped, Order, Str, Big, Buffer, Void
};

struct WordInfo {
  Word word;
  StringRef kind;    // the table's case
  StringRef cType;   // the C type, before a parameter's name
  StringRef suffix;  // of the C function of an operand of several kinds
  StringRef variant; // of the table's typed pointer to that function
  StringRef doc;
};

const WordInfo &infoOf(Word word) {
  static const WordInfo infos[] = {
      {Word::World, "World", "", "", "", "The world: no C value"},
      {Word::Int32, "Int32", "int32_t ", "", "", "int32_t: a character, a byte"},
      {Word::Int64, "Int64", "int64_t ", "", "", "int64_t: an Int, a count, a handle, a clock"},
      {Word::Double, "Double", "double ", "_f64", "double", "double"},
      {Word::Signed, "Signed", "int64_t ", "_s", "signed",
       "int64_t: an integer of the op's width, sign-extended"},
      {Word::Unsigned, "Unsigned", "uint64_t ", "_u", "unsigned",
       "uint64_t: an integer of the op's width, zero-extended"},
      {Word::Wrapped, "Wrapped", "int64_t ", "", "",
       "int64_t: a result modulo 2^64, which the op wraps to its width"},
      {Word::Order, "Order", "int32_t ", "", "",
       "int32_t: negative, zero or positive, which the op compares with 0 by its predicate"},
      {Word::Str, "Str", "const idris_rt_str *", "", "", "const idris_rt_str *"},
      {Word::Big, "Big", "idris_rt_big ", "", "", "idris_rt_big"},
      {Word::Buffer, "Buffer", "", "", "",
       "idris_rt_array *, char *, int64_t: the cell, its first byte, its size"},
      {Word::Void, "Void", "void ", "", "", "No result"},
  };
  return infos[static_cast<size_t>(word)];
}

// The dialect's types the C ABI holds as one value each, by their ODS
// records.
std::optional<Word> dialectWord(StringRef type) {
  static const std::pair<StringRef, Word> words[] = {
      {"Idr_WorldType", Word::World},     {"Idr_StrType", Word::Str},
      {"Idr_StrValue", Word::Str},        {"Idr_StrRead", Word::Str},
      {"Idr_BigType", Word::Big},         {"Idr_NatType", Word::Big},
      {"Idr_BigValue", Word::Big},        {"Idr_NatValue", Word::Big},
      {"Idr_BigOrNatValue", Word::Big},   {"Idr_BigRead", Word::Big},
      {"Idr_NatRead", Word::Big},         {"Idr_BigOrNatRead", Word::Big},
      {"Idr_Rank1ArrayValue", Word::Buffer}};
  for (const auto &[name, word] : words)
    if (name == type)
      return word;
  return std::nullopt;
}

//===----------------------------------------------------------------------===//
// Guards
//===----------------------------------------------------------------------===//

// A partial op is a guard and a total op, and its ODS says each guard
// (Idr_Guarded): the kind of check (a case of the enum CheckKind), the
// names of the op's values the guard op takes, in its order, the operand it
// guards first, and the cause its crash reports. The guard op of a kind is
// the one whose `checkKind` is that case, and what it takes beside the
// operand it guards is what the Idris side gives its check: an operand of
// the partial op, as it is, for an operand that is no count; and for a
// count of bytes (an i64), how the count is had from the value the mark
// names: that value itself, an i64 operand; the size of a word the op loads
// or stores; the bytes of a string; or the length of an array. The Idris
// side reads them as `guardsOf`, which gives each guard of an op with the
// positions of the operands it reads.

// The enum of the kinds of check, CheckKind in the dialect's namespace,
// which the C++ of the guards names too.
const llvm::Record *checkKinds(const llvm::RecordKeeper &records, StringRef cppNamespace) {
  for (const llvm::Record *def : records.getAllDerivedDefinitionsIfDefined("EnumInfo")) {
    EnumInfo info(def);
    if (info.getEnumClassName() == "CheckKind" && info.getCppNamespace() == cppNamespace)
      return def;
  }
  llvm::PrintFatalError("a partial op names a guard, and " + cppNamespace +
                        " has no enum CheckKind");
}

// The guard op of each kind of check, by the kind's symbol.
std::map<std::string, const llvm::Record *> guardOps(const llvm::RecordKeeper &records,
                                                     const EnumInfo &kinds) {
  std::map<std::string, const llvm::Record *> ops;
  for (const llvm::Record *def : records.getAllDerivedDefinitions("Op")) {
    const llvm::RecordVal *kind = def->getValue("checkKind");
    if (!kind || !llvm::isa<llvm::DefInit>(kind->getValue()))
      continue;
    std::string symbol = EnumCase(def->getValueAsDef("checkKind")).getSymbol().str();
    if (!ops.emplace(symbol, def).second)
      llvm::PrintFatalError(def, "two guard ops check " + symbol);
  }
  for (const EnumCase &c : kinds.getAllCases())
    if (!ops.count(c.getSymbol().str()))
      llvm::PrintFatalError(&kinds.getDef(), "no guard op checks " + c.getSymbol());
  return ops;
}

// Whether a guard op's operand, beside the one it guards, is a count of
// bytes, which the Idris side has from a value of the partial op, rather
// than an operand of the partial op itself.
bool isCount(const NamedTypeConstraint &operand) {
  return operand.constraint.getDef().getName() == "I64";
}

// The Idris type each operand of a guard op beside the one it guards is
// given as: a count, or an operand's position.
std::vector<std::string> checkArgs(const Operator &guard) {
  std::vector<std::string> args;
  for (int index = 1, e = guard.getNumOperands(); index < e; ++index)
    args.push_back(isCount(guard.getOperand(index)) ? "Count" : "Nat");
  return args;
}

// The position of operand group `group` of `op` among the operands of one
// of its ops, as an Idris Nat over `os`, the operands: the groups are told
// apart by their arities alone, so at most one of them varies in length.
std::string positionOf(const Operator &op, int group) {
  int groups = op.getNumOperands(), varying = -1;
  for (int index = 0; index < groups; ++index)
    if (arity(op.getOperand(index)) != '1') {
      if (varying != -1)
        llvm::PrintFatalError(op.getLoc(), op.getOperationName() +
                                               " has a guard and more than one group of operands "
                                               "that varies in length");
      varying = index;
    }
  if (varying == -1 || group <= varying)
    return std::to_string(group);
  return llvm::formatv("(minus (length os) {0})", groups - group).str();
}

// One guard's clause of guardsOf, as the list it gives: one guard, or one
// for each value of a group of operands that varies in length.
std::string guardOf(const Operator &op, const llvm::Record &mark, const EnumInfo &kinds,
                    const std::map<std::string, const llvm::Record *> &guards) {
  std::string operationName = op.getOperationName();
  StringRef kind = mark.getValueAsString("kind");
  std::vector<EnumCase> cases = kinds.getAllCases();
  auto known = llvm::find_if(cases, [&](const EnumCase &c) { return c.getSymbol() == kind; });
  if (known == cases.end())
    llvm::PrintFatalError(&mark, operationName + " names the guard " + kind +
                                     ", which is no case of CheckKind");
  Operator guard(guards.at(kind.str()));
  std::vector<std::string> names = namesIn(mark.getValueAsString("operand"));
  if (names.size() != static_cast<size_t>(guard.getNumOperands()))
    llvm::PrintFatalError(&mark, llvm::formatv("{0}'s guard {1} names {2} values, and {3} takes "
                                               "{4}: the operand it guards, then each other",
                                               operationName, kind, names.size(),
                                               guard.getOperationName(), guard.getNumOperands())
                                     .str());
  auto group = [&](StringRef name) {
    std::optional<int> index = operandNamed(op, name);
    if (!index)
      llvm::PrintFatalError(&mark, operationName + " has no operand `" + name + "`");
    return *index;
  };
  // A count is a count operand itself, a word the op loads (its result) or
  // stores (its operand), whose size it is, a string, whose bytes it is, or
  // an array, whose length it is.
  auto count = [&](StringRef name) -> std::string {
    std::optional<int> result = resultNamed(op, name);
    const llvm::Record &type = result ? op.getResult(*result).constraint.getDef()
                                      : op.getOperand(group(name)).constraint.getDef();
    if (type.getValue("allowedTypes") &&
        llvm::all_of(type.getValueAsListOfDefs("allowedTypes"), [](const llvm::Record *t) {
          return t->isSubClassOf("I") || t->isSubClassOf("F");
        }))
      return "WordSize";
    if (result)
      llvm::PrintFatalError(&mark, operationName + "'s result `" + name + "` is no word");
    std::string position = positionOf(op, group(name));
    if (type.getName() == "I64")
      return "(CountAt " + position + ")";
    std::optional<Word> word = dialectWord(type.getName());
    if (word == Word::Str)
      return "(BytesOf " + position + ")";
    if (word == Word::Buffer)
      return "(LengthOf " + position + ")";
    llvm::PrintFatalError(&mark, operationName + "'s `" + name + "` counts no bytes");
  };
  std::string check = caseName(kinds, *known);
  for (int index = 1, e = guard.getNumOperands(); index < e; ++index) {
    StringRef name = names[static_cast<size_t>(index)];
    if (isCount(guard.getOperand(index))) {
      check += " " + count(name);
      continue;
    }
    int read = group(name);
    if (arity(op.getOperand(read)) != '1')
      llvm::PrintFatalError(&mark, operationName + "'s guard reads `" + name +
                                       "`, which is no single operand");
    check += " " + positionOf(op, read);
  }
  if (check.find(' ') != std::string::npos)
    check = "(" + check + ")";
  std::string cause = literal(mark.getValueAsString("cause"));
  int guarded = group(names.front());
  std::string position = positionOf(op, guarded);
  if (arity(op.getOperand(guarded)) == '1')
    return llvm::formatv("[MkGuard {0} {1} {2}]", position, check, cause).str();
  // Each value of the group is guarded alike.
  int groups = op.getNumOperands();
  return llvm::formatv("map (\\i => MkGuard i {0} {1}) (positions {2} (minus (length os) {3}))",
                       check, cause, position, groups - 1)
      .str();
}

// The guards of the dialect's partial ops, by the ops' names, and the types
// they are given in: none when no op of the dialect is partial.
std::string guardsOf(const llvm::RecordKeeper &records, const mlir::tblgen::Dialect &dialect,
                     const std::vector<std::pair<std::string, const llvm::Record *>> &ops) {
  std::string clauses;
  const llvm::Record *kinds = nullptr;
  std::map<std::string, const llvm::Record *> guards;
  for (const auto &[name, def] : ops) {
    Operator op(def);
    std::vector<const llvm::Record *> marks = traitsOfClass(op, "Idr_Guarded");
    if (marks.empty())
      continue;
    if (!kinds) {
      kinds = checkKinds(records, dialect.getCppNamespace());
      guards = guardOps(records, EnumInfo(kinds));
    }
    std::vector<std::string> lists;
    for (const llvm::Record *mark : marks)
      lists.push_back(guardOf(op, *mark, EnumInfo(kinds), guards));
    std::string body =
        lists.size() == 1 ? lists.front() : "concat [" + llvm::join(lists, ", ") + "]";
    bool readsOperands = StringRef(body).contains(" os)");
    clauses += llvm::formatv("guardsOf (MkOp {0} {1} _ _ _ _) = {2}\n", literal(name),
                             readsOperands ? "os" : "_", body)
                   .str();
  }
  if (!kinds)
    return "";
  EnumInfo info(kinds);
  std::string out;
  llvm::raw_string_ostream os(out);
  os << "||| How a guard has a count of bytes it checks: the operand at a position,\n"
     << "||| the size of the word the op loads or stores, the bytes of the string at\n"
     << "||| a position, or the length of the array at a position.\n"
     << "public export\ndata Count = CountAt Nat | WordSize | BytesOf Nat | LengthOf Nat\n\n"
     << "||| What a guard checks of the operand it guards (CheckKind), with what else\n"
     << "||| its guard op takes: each operand of the op it takes as it is, by its\n"
     << "||| position among the op's, and each count.\n"
     << "public export\ndata Check = ";
  llvm::interleave(
      info.getAllCases(),
      [&](const EnumCase &c) {
        os << caseName(info, c);
        for (const std::string &arg : checkArgs(Operator(guards.at(c.getSymbol().str()))))
          os << " " << arg;
      },
      [&] { os << " | "; });
  os << "\n\n"
     << "||| A guard a partial op takes, an op `" << dialect.getName()
     << ".check.*`: the position\n"
     << "||| of the operand it guards, whose value the guard's result stands for in\n"
     << "||| the op, what it checks, and the cause its crash reports.\n"
     << "public export\nrecord Guard where\n  constructor MkGuard\n  operand : Nat\n"
     << "  check : Check\n  cause : String\n\n"
     << "-- The `count` positions from `start`.\n"
     << "positions : Nat -> Nat -> List Nat\npositions start Z = []\n"
     << "positions start (S count) = start :: positions (S start) count\n\n"
     << "||| The guards an op takes before it, in the order its ODS lists them;\n"
     << "||| none for a total op or an op of another dialect.\n"
     << "export\nguardsOf : Op -> List Guard\n"
     << clauses << "guardsOf _ = []\n\n";
  return out;
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
  if (cpp == "int" || cpp == "int32_t" || cpp == "int64_t" || cpp == "::llvm::APInt")
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

// One element of a declarative syntax of a type or an attribute.
struct Element {
  enum Form { Literal, Parameter, Group } form;
  std::string text = {};           // the literal, or the parameter's name
  bool anchor = false;             // an element marked `^`
  std::vector<Element> group = {}; // an optional group's elements
};

// A parameter's name after `$`.
std::string parameterName(StringRef &format) {
  StringRef name = format.take_while([](char c) { return llvm::isAlnum(c) || c == '_'; });
  format = format.drop_front(name.size());
  return name.str();
}

// The elements of a type's or an attribute's declarative syntax up to its
// end, or in a group up to its `)`; nothing, with the reason in `why`, for
// a directive the generator does not write (custom, struct, params) and for
// an else branch. Such a syntax has only `qualified`, and the C++ printer
// alone spaces it.
std::optional<std::vector<Element>> elements(StringRef &format, bool inGroup, std::string &why) {
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
      // An empty literal, or one of spaces, only spaces the C++ printer.
      StringRef text = format.take_front(end);
      format = format.drop_front(end + 1);
      if (!text.trim().empty())
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
      if (!format.consume_front("$")) {
        why = "`qualified` of no parameter";
        return std::nullopt;
      }
      Element inner{Element::Parameter, parameterName(format)};
      format = format.ltrim();
      if (!format.consume_front(")")) {
        why = "`qualified` of more than a parameter";
        return std::nullopt;
      }
      inner.anchor = format.consume_front("^");
      out.push_back(std::move(inner));
      continue;
    }
    if (format.consume_front("(")) {
      std::optional<std::vector<Element>> group = elements(format, true, why);
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
    std::optional<std::vector<Element>> parsed = elements(rest, false, why);
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

  std::string constructor = constructorName(def.getCppClassName().str(),
                                            "the " + llvm::Twine(isType ? "type " : "attribute ") +
                                                def.getCppClassName());
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
// own body, `<"name", kind [@C(fields) role by_name, ...] instance
// #d.instance<origin, [arguments]>>` everywhere else. Its constructor holds
// the name and, where it is written whole, the body: a record of the kind
// (the enum its ODS names as `bodyKinds`), the constructors in tag order and
// the instance. A constructor's role (the enum its ODS names as
// `ctorRoles`) is written after its fields, by its keyword unless it is
// plain, and a label's then names the label's function. The records and the
// writer of a constructor are `preamble`, which goes before the sum of types
// that holds them.
void identifiedOf(Enums &enums, const AttrOrTypeDef &def, StringRef sum, Def &out,
                  std::string &preamble) {
  const llvm::Record *kinds = def.getDef()->getValueAsDef("bodyKinds");
  useEnum(enums, kinds).spellings = true;
  std::string kind = enumName(EnumInfo(kinds));
  const llvm::Record *roles = def.getDef()->getValueAsDef("ctorRoles");
  useEnum(enums, roles).spellings = true;
  EnumInfo roleInfo(roles);
  std::string role = enumName(roleInfo);
  std::vector<EnumCase> roleCases = roleInfo.getAllCases();
  auto plain = llvm::find_if(roleCases, [](const EnumCase &c) { return c.getSymbol() == "Plain"; });
  if (plain == roleCases.end())
    llvm::PrintFatalError(roles, role + " has no case Plain, the role written as nothing");
  std::string dialect = def.getDialect().getName().str();
  std::string module = lastName(moduleName).str();
  std::string ctor = module + "Ctor", body = module + "Sum";
  std::string ctorText = camel(dialect, false) + "CtorText";
  std::string mnemonic = def.getMnemonic() ? def.getMnemonic()->str() : std::string();
  std::string spelling = "!" + dialect + "." + mnemonic;
  llvm::raw_string_ostream pre(preamble);
  pre << "||| One constructor of a data type's body, as `" << spelling << "` writes it: its\n"
      << "||| name, its fields' types, whether every force of it runs it, the part it\n"
      << "||| plays in its sum, and the function it names, which only a label names.\n"
      << "public export\nrecord " << ctor << " ty where\n  constructor Mk" << ctor << "\n"
      << "  name : String\n  fields : List ty\n  byName : Bool\n  role : " << role << "\n"
      << "  fn : Maybe String\n\n"
      << "||| A data type's body, as `" << spelling << "` writes it: what sum it is, its\n"
      << "||| constructors in tag order, and the Idris instance it is of, its origin\n"
      << "||| and arguments.\n"
      << "public export\nrecord " << body << " ty where\n  constructor Mk" << body << "\n"
      << "  kind : " << kind << "\n  ctors : List (" << ctor << " ty)\n"
      << "  instanceOf : Maybe (String, List String)\n\n"
      << "-- How `" << spelling << "` writes a constructor of its body.\n"
      << ctorText << " : (t : ty -> String) -> " << ctor << " ty -> String\n"
      << ctorText << " t c = fastConcat [symbol c.name, \"(\", commaSeparated (map t c.fields), "
      << "\")\", if c.role == " << qualifiedCase(roleInfo, *plain) << " then \"\" else \" \" ++ "
      << camel(role, false) << "Spelling c.role, maybe \"\" (\\f => \" \" ++ symbol f) c.fn, "
      << "if c.byName then \" by_name\" else \"\"]\n\n";
  std::string constructor =
      constructorName(def.getCppClassName().str(), "the type " + def.getCppClassName());
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
// The Idris modules
//===----------------------------------------------------------------------===//

// What both modules of a dialect are written from, read once: its types and
// attributes, its ops' builders, primitives and guards, and, found on the
// way, the enums all of them take.
struct Vocabulary {
  std::optional<mlir::tblgen::Dialect> dialect;
  std::vector<Def> types, attrs;
  std::vector<std::string> omitted;
  // What the sum of types holds besides types: an identified type's body.
  std::string typesPreamble;
  std::string ops, primitives, guards;
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
    for (const auto &[name, def] : byName)
      emitOp(v.enums, Operator(def), opsOs);
    emitPrimitives(dialectOps, primitivesOs);
  }
  v.guards = guardsOf(records, *v.dialect, byName);
  addCaseFields(v.enums, enumsOfCases(records));
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
  for (const auto &[name, used] : v.enums)
    emitCaseFields(used, enumsOs);
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

  os << "||| The " << dialectName << " dialect, as the Idris side writes it. Generated by\n"
     << "||| idris-mlir-tblgen -gen-idris-dialect from the dialect's ODS; `make build`\n"
     << "||| writes it (tools/dialects.sh). Do not edit.\n"
     << "module " << moduleName << "\n\nimport IdrisMLIR.MLIR\nimport " << syntaxModuleName
     << "\n\n%default total\n\n";
  section(os, "Enums", values);
  section(os, "Discardable attributes", discardables);
  section(os, "Ops", v.ops);
  section(os, "Primitives", v.primitives);
  section(os, "Guards", v.guards);
  return false;
}

//===----------------------------------------------------------------------===//
// The runtime's C functions
//===----------------------------------------------------------------------===//

// An op that calls the runtime (Idr_Runtime) names its C function. The
// function takes the op's operands in order and gives its result, each as
// the C ABI holds a value of its type: the world is no C value at all, a
// buffer its cell, its first byte and its size. An operand that is an
// integer of any width is extended to 64 bits as the op's signedness
// (`is_signed`) says, and an operand of several kinds has a C function per
// kind, named after the op's with a suffix for each (_s, _u, _f64). An
// integer result of any width is the C function's 64 bits, which the op
// wraps to its width; a comparison's (an i1 with a `predicate`) is the C
// function's three-way order, which the op compares with 0. The op's
// Idr_NoReturn says the function does not return.

// The kinds a value of an ODS type constraint may be passed as (`result`:
// given back as), more than one for an operand of several kinds.
std::vector<Word> wordsOf(const llvm::Record &type, bool result, const Operator &op,
                          const std::string &what) {
  if (std::optional<Word> word = dialectWord(type.getName()))
    return {*word};
  if (type.isSubClassOf("I")) {
    int64_t width = type.getValueAsInt("bitwidth");
    if (width == 32)
      return {Word::Int32};
    if (width == 64)
      return {Word::Int64};
    if (width == 1 && result)
      return {Word::Order};
  }
  if (type.isSubClassOf("F") && type.getValueAsInt("bitwidth") == 64)
    return {Word::Double};
  if (type.getValue("allowedTypes")) {
    std::vector<const llvm::Record *> members = type.getValueAsListOfDefs("allowedTypes");
    if (members.size() > 1 &&
        llvm::all_of(members, [](const llvm::Record *t) { return t->isSubClassOf("I"); })) {
      if (result)
        return {Word::Wrapped};
      return {Word::Signed, Word::Unsigned};
    }
    std::vector<Word> words;
    for (const llvm::Record *member : members)
      for (Word word : wordsOf(*member, result, op, what))
        if (!llvm::is_contained(words, word))
          words.push_back(word);
    return words;
  }
  llvm::PrintFatalError(op.getLoc(), op.getOperationName() + "'s " + what + " is `" +
                                         type.getName() + "`, which no C function takes");
}

// One C function an op calls, and the op's class.
struct RuntimeFunction {
  std::string symbol;
  std::string opClass;
  std::string operation;
  std::string summary;
  std::vector<std::pair<Word, std::string>> params; // one per operand of the op, and its name
  Word result;
  bool noreturn;
  std::vector<Word> variant; // the kinds of the operands of several kinds
};

// The C functions `op` calls: none, one, or one per kind of its operands.
std::vector<RuntimeFunction> runtimeFunctionsOf(const Operator &op) {
  const llvm::Record *mark = markOf(op, "Idr_Runtime");
  if (!mark)
    return {};
  std::string operation = op.getOperationName();
  auto fail = [&](const llvm::Twine &why) { llvm::PrintFatalError(op.getLoc(), operation + why); };
  bool isSigned = false, hasPredicate = false;
  for (int index = 0, e = op.getNumArgs(); index < e; ++index) {
    mlir::tblgen::Argument arg = op.getArg(index);
    if (llvm::isa<NamedTypeConstraint *>(arg))
      continue;
    if (const auto *property = llvm::dyn_cast_if_present<NamedProperty *>(arg))
      fail(" has the property `" + property->name + "`, which its C function cannot take");
    const auto *attribute = llvm::cast<NamedAttribute *>(arg);
    if (attribute->attr.isDerivedAttr())
      continue;
    if (attribute->name == "is_signed")
      isSigned = true;
    else if (attribute->name == "predicate")
      hasPredicate = true;
    else
      fail(" has the attribute `" + attribute->name + "`, which its C function cannot take");
  }
  std::vector<std::pair<std::string, std::vector<Word>>> operands;
  for (int index = 0, e = op.getNumOperands(); index < e; ++index) {
    const NamedTypeConstraint &operand = op.getOperand(index);
    std::string name =
        operand.name.empty() ? "operand" + std::to_string(index) : operand.name.str();
    if (arity(operand) != '1')
      fail("'s operand `" + name + "` varies in length, and a C function's parameters do not");
    std::vector<Word> words = wordsOf(operand.constraint.getDef(), false, op, "operand " + name);
    if ((llvm::is_contained(words, Word::Signed) || llvm::is_contained(words, Word::Unsigned)) &&
        !isSigned)
      fail(" takes an integer of any width and has no `is_signed` to extend it by");
    if (words.size() > 1 && llvm::any_of(words, [](Word w) { return infoOf(w).suffix.empty(); }))
      fail("'s operand `" + name + "` has several kinds, one of which names no C function");
    operands.emplace_back(name, std::move(words));
  }
  std::vector<Word> results;
  for (int index = 0, e = op.getNumResults(); index < e; ++index) {
    std::vector<Word> words = wordsOf(op.getResult(index).constraint.getDef(), true, op,
                                      ("result " + op.getResultName(index)).str());
    if (words.size() != 1)
      fail(" gives a result of several kinds, and a C function gives one");
    if (words.front() != Word::World)
      results.push_back(words.front());
  }
  if (results.size() > 1)
    fail(" gives more than one value, and a C function gives one");
  Word result = results.empty() ? Word::Void : results.front();
  if (result == Word::Order && !hasPredicate)
    fail(" gives an i1 and has no `predicate` to compare its C function's order by");
  bool noreturn = op.getTrait("::idr::NoReturn") != nullptr;
  if (noreturn && result != Word::Void)
    fail(" does not return, and gives a value");

  // The product of the operands' kinds, each with its suffix.
  std::vector<RuntimeFunction> functions{
      {mark->getValueAsString("symbol").str(), op.getQualCppClassName(), operation,
       doc(op.getSummary()), {}, result, noreturn, {}}};
  for (const auto &[name, words] : operands) {
    std::vector<RuntimeFunction> next;
    for (const RuntimeFunction &f : functions)
      for (Word word : words) {
        RuntimeFunction g = f;
        g.params.emplace_back(word, name);
        if (words.size() > 1) {
          g.symbol += infoOf(word).suffix.str();
          g.variant.push_back(word);
        }
        next.push_back(std::move(g));
      }
    functions = std::move(next);
  }
  return functions;
}

// Every C function the ops of the records call, by symbol.
std::vector<RuntimeFunction> runtimeFunctions(const llvm::RecordKeeper &records) {
  std::vector<RuntimeFunction> functions;
  for (const llvm::Record *def : records.getAllDerivedDefinitions("Op"))
    for (RuntimeFunction &f : runtimeFunctionsOf(Operator(def)))
      functions.push_back(std::move(f));
  llvm::sort(functions, [](const RuntimeFunction &a, const RuntimeFunction &b) {
    return a.symbol < b.symbol;
  });
  for (size_t index = 1; index < functions.size(); ++index)
    if (functions[index].symbol == functions[index - 1].symbol)
      llvm::PrintFatalError("both " + functions[index - 1].operation + " and " +
                            functions[index].operation + " call " + functions[index].symbol);
  return functions;
}

// The C declaration of a function.
std::string cDeclaration(const RuntimeFunction &f) {
  std::vector<std::string> params;
  for (const auto &[word, name] : f.params) {
    if (word == Word::World)
      continue;
    if (word == Word::Buffer) {
      params.push_back(llvm::formatv("idris_rt_array *{0}_cell, char *{0}_bytes, int64_t {0}_size",
                                     name)
                           .str());
      continue;
    }
    params.push_back(infoOf(word).cType.str() + name);
  }
  return llvm::formatv("{0}{1}{2}({3});", f.noreturn ? "IDRIS_RT_NORETURN " : "",
                       infoOf(f.result).cType, f.symbol,
                       params.empty() ? std::string("void") : llvm::join(params, ", "))
      .str();
}

bool emitRuntimeAbiDecls(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  os << "/* The runtime's functions the ops call (Idr_Runtime), as C declares them:\n"
     << " * generated by idris-mlir-tblgen -gen-runtime-abi-decls from the ODS, each\n"
     << " * function's parameters and result its op's operands and result, so that a\n"
     << " * definition that does not match its op fails to compile. idris_rt.h includes\n"
     << " * it, inside its C linkage and after the types it names; each function's\n"
     << " * meaning is documented there. Do not edit. */\n"
     << "#ifndef IDRIS_RT_OPS_H\n#define IDRIS_RT_OPS_H\n\n";
  for (const RuntimeFunction &f : runtimeFunctions(records))
    os << "/* " << f.operation << (f.summary.empty() ? "" : ": " + f.summary) << " */\n"
       << cDeclaration(f) << "\n";
  os << "\n#endif /* IDRIS_RT_OPS_H */\n";
  return false;
}

bool emitRuntimeAbiDefs(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  std::vector<RuntimeFunction> functions = runtimeFunctions(records);
  os << "// The runtime's functions the ops call (Idr_Runtime), as the lowering and the\n"
     << "// folders read them: generated by idris-mlir-tblgen -gen-runtime-abi-defs from\n"
     << "// the ODS. For each op, its functions, each its symbol, how it takes each of\n"
     << "// the op's operands, how it gives the op's result and whether it returns, and\n"
     << "// each C function itself, typed as idris_rt_ops.h declares it; and every\n"
     << "// function by its symbol. Do not edit.\n\n"
     << "#ifndef IDR_IR_IDRRUNTIMEABI_INC\n#define IDR_IR_IDRRUNTIMEABI_INC\n\n"
     << "#include \"idr/IR/IdrDialect.h\"\n\n#include \"idris_rt.h\"\n\n"
     << "#include <algorithm>\n#include <iterator>\n#include <span>\n#include <string_view>\n\n"
     << "namespace idr::runtime {\n\n"
     << "// How a runtime function takes an operand of its op, or gives the op's\n"
     << "// result.\nenum class Kind : unsigned char {\n";
  for (size_t index = 0; index <= static_cast<size_t>(Word::Void); ++index) {
    const WordInfo &info = infoOf(static_cast<Word>(index));
    os << "  // " << info.doc << ".\n  " << info.kind << ",\n";
  }
  os << "};\n\n"
     << "// One C function of the runtime: its symbol, how it takes each operand of\n"
     << "// its op, in order, how it gives the op's result, and whether it returns.\n"
     << "struct Function {\n  std::string_view symbol;\n  std::span<const Kind> operands;\n"
     << "  Kind result;\n  bool noreturn;\n};\n\n"
     << "// The C functions an op calls: one, or one per kind of the operand that has\n"
     << "// several (`function`, or `signedFunction`, `unsignedFunction`,\n"
     << "// `doubleFunction`), each also as a typed pointer. Not defined for an op\n"
     << "// that calls none.\ntemplate <typename OpT>\nstruct Abi;\n\n";
  std::map<std::string, std::vector<const RuntimeFunction *>> byOp;
  for (const RuntimeFunction &f : functions)
    byOp[f.opClass].push_back(&f);
  // Each function's place in its op's list, for the table by symbol.
  std::map<std::string, std::string> entries;
  for (const auto &[opClass, ofOp] : byOp) {
    os << "template <>\nstruct Abi<" << opClass << "> {\n";
    for (auto [index, f] : llvm::enumerate(ofOp)) {
      os << "  static constexpr Kind operands" << index << "[] = {";
      llvm::interleave(
          f->params, [&](const auto &param) { os << "Kind::" << infoOf(param.first).kind; },
          [&] { os << ", "; });
      os << "};\n";
    }
    os << "  static constexpr Function functions[] = {\n";
    for (auto [index, f] : llvm::enumerate(ofOp)) {
      os << "      {\"" << f->symbol << "\", "
         << (f->params.empty() ? std::string("{}") : "operands" + std::to_string(index))
         << ", Kind::" << infoOf(f->result).kind << ", " << (f->noreturn ? "true" : "false")
         << "},\n";
      entries[f->symbol] = llvm::formatv("Abi<{0}>::functions[{1}]", opClass, index).str();
    }
    os << "  };\n";
    for (const RuntimeFunction *f : ofOp) {
      std::string words;
      for (Word word : f->variant)
        words += (words.empty() ? "" : "_") + infoOf(word).variant.str();
      std::string member = words.empty() ? "function" : camel(words, false) + "Function";
      os << "  static constexpr auto *" << member << " = &" << f->symbol << ";\n";
    }
    os << "};\n\n";
  }
  os << "// Every function of the table, by symbol.\n"
     << "inline constexpr Function functions[] = {\n";
  for (const auto &[symbol, entry] : entries)
    os << "    " << entry << ",\n";
  os << "};\n\n"
     << "// The function named `symbol`, or null.\n"
     << "constexpr const Function *lookup(std::string_view symbol) {\n"
     << "  const Function *found = std::lower_bound(\n"
     << "      std::begin(functions), std::end(functions), symbol,\n"
     << "      [](const Function &f, std::string_view s) { return f.symbol < s; });\n"
     << "  return found != std::end(functions) && found->symbol == symbol ? found : nullptr;\n"
     << "}\n\n"
     << "} // namespace idr::runtime\n\n#endif // IDR_IR_IDRRUNTIMEABI_INC\n";
  return false;
}

//===----------------------------------------------------------------------===//
// Big ops and their word ops
//===----------------------------------------------------------------------===//

// A big op whose value, where every big it takes and gives fits a word, is
// a word op's names it (Idr_WordOp, its record's own class): the word op's
// C++ class, applied to the words of the op's operands and, for a unary op,
// to a constant as its second operand; or none, where the word is the value
// itself.
bool emitBigToWord(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  std::vector<std::pair<std::string, const llvm::Record *>> marked;
  for (const llvm::Record *def : records.getAllDerivedDefinitions("Op"))
    if (def->isSubClassOf("Idr_WordOp"))
      marked.emplace_back(Operator(def).getQualCppClassName(), def);
  llvm::sort(marked, [](const auto &a, const auto &b) { return a.first < b.first; });
  os << "// The word op each big op names (Idr_WordOp): generated by\n"
     << "// idris-mlir-tblgen -gen-big-to-word from the ODS. With GET_BIG_TO_WORD_LIST\n"
     << "// defined, the big ops alone, separated by commas, for a template or an isa\n"
     << "// over all of them; else the table. Do not edit.\n\n"
     << "#ifdef GET_BIG_TO_WORD_LIST\n#undef GET_BIG_TO_WORD_LIST\n\n";
  llvm::interleave(
      marked, [&](const auto &entry) { os << entry.first; }, [&] { os << ",\n"; });
  os << "\n\n#else\n#ifndef IDR_IR_IDRBIGTOWORD_INC\n#define IDR_IR_IDRBIGTOWORD_INC\n\n"
     << "#include <cstdint>\n\nnamespace idr {\n\n"
     << "// The word op of a big op: `Op`, applied to the words of the big op's\n"
     << "// operands and, where `constant` is given, to that constant as its second\n"
     << "// operand; `Op` is void where the word is the value itself. Not defined for\n"
     << "// an op that names none.\ntemplate <typename BigOpT>\nstruct BigToWord;\n\n";
  for (const auto &[opClass, def] : marked) {
    StringRef word = def->getValueAsString("wordOp");
    StringRef constant = def->getValueAsString("wordConstant");
    int64_t value = 0;
    if (!constant.empty() && constant.getAsInteger(10, value))
      llvm::PrintFatalError(def, opClass + "'s word constant `" + constant + "` is no integer");
    if (word.empty() && !constant.empty())
      llvm::PrintFatalError(def, opClass + " names a constant and no word op to apply it to");
    os << "template <>\nstruct BigToWord<" << opClass << "> {\n"
       << "  using Op = " << (word.empty() ? StringRef("void") : word) << ";\n";
    if (!constant.empty())
      os << "  static constexpr int64_t constant = " << value << ";\n";
    os << "};\n\n";
  }
  os << "} // namespace idr\n\n#endif // IDR_IR_IDRBIGTOWORD_INC\n#endif\n";
  return false;
}

//===----------------------------------------------------------------------===//
// The rules a refusal names
//===----------------------------------------------------------------------===//

// The rules of the enum Rule, one per line: the phrase a refusal names it
// by, `unsupported (<phrase>)`, then a tab and its category's phrase, as the
// tests read them.
bool emitRuleList(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  const llvm::Record *rules = nullptr;
  for (const llvm::Record *def : records.getAllDerivedDefinitionsIfDefined("EnumInfo"))
    if (EnumInfo(def).getEnumClassName() == "Rule") {
      if (rules)
        llvm::PrintFatalError("two enums named Rule");
      rules = def;
    }
  if (!rules)
    llvm::PrintFatalError("no enum Rule in the records");
  EnumInfo info(rules);
  std::vector<CaseField> fields = caseFieldsOf(info, enumsOfCases(records));
  if (fields.size() != 1)
    llvm::PrintFatalError(rules, "a rule's case names its category, and no other enum's case");
  for (const EnumCase &c : info.getAllCases())
    os << c.getStr() << "\t" << namedCase(c, fields.front().field).getStr() << "\n";
  return false;
}

const mlir::GenRegistration genIdrisSyntax("gen-idris-syntax",
                                           "The Idris side's syntax of a dialect",
                                           emitIdrisSyntax);
const mlir::GenRegistration genIdrisDialect("gen-idris-dialect",
                                            "The Idris side's ops of a dialect",
                                            emitIdrisDialect);
const mlir::GenRegistration
    genRuntimeAbiDecls("gen-runtime-abi-decls",
                       "The C declarations of the runtime functions the ops call",
                       emitRuntimeAbiDecls);
const mlir::GenRegistration genRuntimeAbiDefs("gen-runtime-abi-defs",
                                              "The table of the runtime functions the ops call",
                                              emitRuntimeAbiDefs);
const mlir::GenRegistration genBigToWord("gen-big-to-word", "The word op each big op names",
                                         emitBigToWord);
const mlir::GenRegistration genRuleList("gen-rule-list",
                                        "The rules a refusal names, with their categories",
                                        emitRuleList);

} // namespace

int main(int argc, char **argv) { return mlir::MlirTblgenMain(argc, argv); }
