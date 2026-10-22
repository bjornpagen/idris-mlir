// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir-tblgen: the one generator of ours not written in Idris, a
// TableGen backend reading upstream's records, which stay upstream's. The
// dialect's specification (compiler/spec/) states every fact of ours and
// prints which upstream ops it admits, one record per op naming upstream's
// own def (Generated/IdrAdmitted<D>.td); this reads, through mlir::tblgen,
// upstream's records for those alone:
//
// - -gen-idris-syntax, an upstream dialect's syntax for the Idris side: the
//   enums its admitted ops, types and attributes take, and its types and
//   attributes with the printers of the syntax ODS declares for them
//   (compiler/src/IdrisMLIR/Syntax/).
// - -gen-idris-dialect, a builder of each admitted op the frontend writes,
//   a guarded op's with the guards its admitted record gives it
//   (compiler/src/IdrisMLIR/Dialect/).
// - -gen-idris-bytecode, an upstream dialect's bytecode entries for the
//   Idris writer, from its records in upstream's bytecode DSL
//   (compiler/src/IdrisMLIR/Encoding/).
// - -gen-admitted-classes, the C++ class of every admitted op by its
//   record's name, so no C++ restates an upstream class.
//
// It is a backend rather than a program over a dump of the records because
// it reads ODS through mlir::tblgen (Operator, Attribute, AttrOrTypeDef,
// EnumInfo), the reading upstream's own C++ is generated from, so the two
// sides cannot take one op differently. The declarative format of an
// attribute (arith's flags, ub's poison) is re-read by a subset parser
// below, since upstream's format parser lives in the mlir-tblgen executable,
// not a library.

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

#include <cstdint>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <variant>
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
// and `at` the types of them; `os`, `rs` and `rest` what a primitive's
// clause binds of its operands and results.
bool isUsedInBodies(StringRef name) {
  static constexpr StringRef names[] = {
      "concat", "toList",    "length",    "map",       "show",   "unitIf",
      "attrIf", "commaSeparated", "v",    "t",         "a",      "ty",
      "at",     "fastConcat", "maybe",    "null",      "symbol", "symbolRef",
      "utf8",   "array",     "signature", "separated", "minus",  "iterateN",
      "os",     "rs",        "rest",      "positions"};
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
// trait it is. The lists open at the walk's point are a stack of what each
// has left, the innermost last: a trait list's own traits come before the
// rest of the list that holds it, and however deep ODS nests its lists the
// native stack stays flat.
std::vector<const llvm::Record *> traitsOfClass(const Operator &op, StringRef name) {
  std::vector<const llvm::Record *> found;
  llvm::SmallVector<llvm::ArrayRef<const llvm::Init *>> open{
      op.getDef().getValueAsListInit("traits")->getElements()};
  while (!open.empty()) {
    if (open.back().empty()) {
      open.pop_back();
      continue;
    }
    const llvm::Record *def = llvm::cast<llvm::DefInit>(open.back().front())->getDef();
    open.back() = open.back().drop_front();
    if (def->isSubClassOf(name) && !llvm::is_contained(found, def))
      found.push_back(def);
    if (def->isSubClassOf("TraitList"))
      open.push_back(def->getValueAsListInit("traits")->getElements());
  }
  return found;
}

// The one mark of class `name` on `op`, or none; two are a fault of ODS.
const llvm::Record *markOf(const Operator &op, StringRef name) {
  std::vector<const llvm::Record *> marks = traitsOfClass(op, name);
  if (marks.size() > 1)
    llvm::PrintFatalError(op.getLoc(), op.getOperationName() + " has more than one " + name);
  return marks.empty() ? nullptr : marks.front();
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
// records: written once each, in the syntax module, with their values and,
// if a syntax prints one, their spellings; and the fields in which their
// cases name another enum's.
struct Enum {
  const llvm::Record *def;
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
// records those fields: each enum is taken once, and the enums are the
// records', so the walk ends. A name is the map's own key, which stays
// where it is as the map grows.
void addCaseFields(Enums &enums, const EnumsOfCases &owners) {
  std::vector<std::string> work;
  std::set<std::string> taken;
  for (const auto &[name, used] : enums) {
    work.push_back(name);
    taken.insert(name);
  }
  while (!work.empty()) {
    std::string name = std::move(work.back());
    work.pop_back();
    Enum &each = enums.find(name)->second;
    each.caseFields = caseFieldsOf(EnumInfo(each.def), owners);
    for (const CaseField &f : each.caseFields) {
      std::string next = enumName(EnumInfo(f.values));
      enums.try_emplace(next, Enum{f.values});
      if (taken.insert(next).second)
        work.push_back(next);
    }
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
  // The value of each case, beside the enum, for whatever writes a case as
  // its value: an op's integer attribute, a bytecode entry. The Idris side
  // holds it as a Nat, as a bytecode entry writes it (a VarInt); a negative
  // value would be another value there, so it is refused here.
  std::string lower = camel(name, false);
  os << "||| The value of each " << name << ".\nexport\n"
     << lower << "Value : " << name << " -> Nat\n";
  for (const EnumCase &c : cases) {
    if (c.getValue() < 0)
      llvm::PrintFatalError(&c.getDef(), "the case " + c.getSymbol() + " of " + name +
                                             " has a negative value");
    os << lower << "Value " << qualifiedCase(info, c) << " = " << c.getValue() << "\n";
  }
  os << "\n";
  if (!used.spellings)
    return;
  // Private to the module, out of the way of whatever imports it. The
  // syntax spells a case as MLIR's enum parser reads it
  // (parseKeywordOrString): its string, quoted where it is no keyword.
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
// `width` bits, which the generic form writes as its value: the syntax
// module's value of the case.
Kind enumValue(Enums &enums, const llvm::Record *def, int64_t width) {
  EnumInfo info(def);
  std::string name = enumName(info);
  useEnum(enums, def);
  return Kind{name, llvm::formatv("IntegerAttr (natToInteger ({0}Value {{0})) (IntegerType {1})",
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

// Lists joined, as an expression: each run of single values one list,
// joined to the next by `++`, whose operands' types (a List, never a Vect)
// fix which `++` it is. A `concat` of the lists would leave its container
// open, which a list literal then fills ambiguously beside Data.Vect's.
std::string joined(const std::vector<std::pair<std::string, bool>> &pieces) {
  std::vector<std::string> lists, run;
  auto close = [&] {
    if (!run.empty())
      lists.push_back("[" + llvm::join(run, ", ") + "]");
    run.clear();
  };
  for (const auto &[text, single] : pieces) {
    if (single) {
      run.push_back(text);
      continue;
    }
    close();
    lists.push_back(text);
  }
  close();
  if (lists.empty())
    return "[]";
  return lists.size() == 1 ? lists.front() : "(" + llvm::join(lists, " ++ ") + ")";
}

// The operand, region or result list of an op, as an expression: single
// ones in a list, variadic ones as given, optional ones as their list.
std::string listOf(const std::vector<std::pair<std::string, char>> &parts) {
  std::vector<std::pair<std::string, bool>> pieces;
  for (const auto &[name, partArity] : parts)
    pieces.emplace_back(partArity == '?' ? "(toList " + name + ")" : name, partArity == '1');
  return joined(pieces);
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

//===----------------------------------------------------------------------===//
// Builders
//===----------------------------------------------------------------------===//

// The guards the specification gives an admitted op, as the list its
// builder returns with it: each guard op given the operands at the positions
// of the groups the guard names, a group's first operand at the number of
// operands the groups before it hold. A group that holds any number, or
// none, guarded first, is guarded operand by operand, each against the same
// other operands. The specification cannot know upstream's operand groups,
// so a position past them is refused here, where the record is read.
std::string guardsOf(const Operator &op, const llvm::Record &admitted,
                     const std::vector<std::pair<std::string, char>> &operands) {
  auto offsetOf = [&](std::size_t group) {
    std::vector<std::string> lengths;
    for (const auto &[name, partArity] : llvm::ArrayRef(operands).take_front(group))
      lengths.push_back(partArity == '1'   ? std::string("1")
                        : partArity == '?' ? "length (toList " + name + ")"
                                           : "length " + name);
    return lengths.empty() ? std::string("0") : "(" + llvm::join(lengths, " + ") + ")";
  };
  std::vector<std::string> lists;
  for (const llvm::Record *guard : admitted.getValueAsListOfDefs("guards")) {
    std::vector<std::int64_t> given = guard->getValueAsListOfInts("operandGroups");
    if (given.empty() || llvm::any_of(given, [&](std::int64_t group) {
          return group < 0 || static_cast<std::uint64_t>(group) >= operands.size();
        }))
      llvm::PrintFatalError(op.getLoc(), op.getOperationName() +
                                             " has a guard whose operand groups are not among "
                                             "its record's");
    std::string check = literal(guard->getValueAsString("guardOp"));
    std::string cause = std::to_string(guard->getValueAsInt("causeNumber"));
    std::vector<std::string> others;
    for (std::int64_t group : llvm::ArrayRef(given).drop_front())
      others.push_back(offsetOf(group));
    const auto &[guarded, guardedArity] = operands[given.front()];
    std::string at = offsetOf(given.front());
    if (guardedArity == '1') {
      others.insert(others.begin(), at);
      lists.push_back("[MkGuard " + check + " [" + llvm::join(others, ", ") + "] " + cause + "]");
      continue;
    }
    lists.push_back("map (\\p'' => MkGuard " + check + " (p'' :: [" + llvm::join(others, ", ") +
                    "]) " + cause + ") (positions " + at + " " +
                    (guardedArity == '?' ? "(toList " + guarded + ")" : guarded) + ")");
  }
  return lists.empty() ? std::string() : llvm::join(lists, " ++ ");
}

// The builder of an upstream op the frontend writes: one argument per
// inherent attribute, operand group, region and result group, and the op;
// with its guards, where the specification gives it any, so a partial op
// is never written without them.
void emitOp(Enums &enums, const Operator &op, const llvm::Record &admitted,
            llvm::raw_ostream &os) {
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

  std::string made = "MkOp " + literal(operationName) + ' ' + listOf(operands) + ' ' +
                     dictionaryOf(properties) + ' ' + listOf(regions) + " [] " + listOf(results);
  std::string guards = guardsOf(op, admitted, operands);
  os << "||| `" << op.getOperationName() << "`" << summary(op.getSummary());
  os << "\nexport\n" << name << " : ";
  for (const Parameter &p : implicits)
    os << binder(p) << " -> ";
  for (const Parameter &p : explicits)
    os << binder(p) << " -> ";
  os << (guards.empty() ? "Op" : "Guarded") << "\n" << name;
  for (const Parameter &p : explicits)
    os << ' ' << p.name;
  if (guards.empty())
    os << " =\n  " << made << "\n\n";
  else
    os << " =\n  MkGuarded (" << made << ") (" << guards << ")\n\n";
}

//===----------------------------------------------------------------------===//
// Types and attributes
//===----------------------------------------------------------------------===//

// What the generator writes of a part of ODS: the part, or why it leaves
// it out, which the module lists at its end.
struct Omitted {
  std::string why;
};
template <class T>
using Written = std::variant<T, Omitted>;

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

// The Idris kind of a C++ value that is no array; nothing for one the Idris
// side has no value of.
std::optional<Kind> plainKind(StringRef cpp) {
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
  // A location, which the Idris side holds as its Location and writes as
  // MLIR writes a location attribute, `loc(...)`, which the parameter's
  // default parser reads.
  if (cpp == "::mlir::LocationAttr")
    return Kind{"Location", "location {0}"};
  if (cpp == "unsigned" || cpp == "uint32_t" || cpp == "uint64_t")
    return Kind{"Nat", "show {0}"};
  if (cpp == "int" || cpp == "int32_t" || cpp == "int64_t" || cpp == "::llvm::APInt")
    return Kind{"Integer", "show {0}"};
  // A type of a dialect's own class (a box's data type) is a type, which
  // its C++ parser reads as any and checks.
  if (cpp.starts_with("::") && cpp.ends_with("Type"))
    return Kind{"ty", "t {0}"};
  return std::nullopt;
}

// The Idris kind of a parameter's C++ value; nothing for one the Idris side
// has no value of. An array is a list of its element's kind, however deep
// arrays nest: their layers are counted off on the way in and wrapped round
// the element's kind on the way out, so no nesting deepens the stack.
std::optional<Kind> valueKind(StringRef cpp) {
  unsigned layers = 0;
  for (cpp = cpp.trim(); cpp.consume_front("::llvm::ArrayRef<") && cpp.consume_back(">");
       cpp = cpp.trim())
    ++layers;
  std::optional<Kind> kind = plainKind(cpp);
  for (; kind && layers > 0; --layers)
    kind = Kind{"List " + parenthesized(kind->type),
                "commaSeparated (map " + maker(kind->text) + " {0})"};
  return kind;
}

// A parameter that is no enum's, whose kind is found otherwise.
struct NotEnum {};

// The Idris kind of an enum parameter: the enum, or a list of a bit enum's
// bits; left out, with the reason, for a bit enum with no case of no bits,
// which could not write the empty list.
std::variant<Kind, NotEnum, Omitted> enumKind(Enums &enums, const AttrOrTypeParameter &param) {
  const auto *def = llvm::dyn_cast<llvm::DefInit>(param.getDef());
  if (!def || !def->getDef()->isSubClassOf("EnumParameter"))
    return NotEnum{};
  const llvm::Record *record = def->getDef()->getValueAsDef("enum");
  EnumInfo info(record);
  std::string name = enumName(info);
  std::string lower = camel(name, false);
  if (!info.isBitEnum()) {
    useEnum(enums, record).spellings = true;
    return Kind{name, lower + "Spelling {0}"};
  }
  if (!noBits(info))
    return Omitted{llvm::formatv("its parameter `{0}` is a bit enum without a case of no bits",
                                 param.getName())
                       .str()};
  useEnum(enums, record).spellings = true;
  return Kind{"List " + name, lower + "Spellings {0}"};
}

// The field of a parameter of the kind `kind`, an optional one without a
// default of its own defaulting to nothing.
Field fieldWith(const AttrOrTypeParameter &param, size_t index, const Kind &kind) {
  Field field{parameter(param.getName(), "parameter" + llvm::Twine(index)), kind.type, kind.text};
  std::optional<StringRef> fallback = param.getDefaultValue();
  if (fallback && *fallback == (param.getCppStorageType() + "()").str()) {
    if (StringRef(kind.type).starts_with("List ")) {
      field.presence = Presence::IfNonEmpty;
    } else {
      field.type = "Maybe " + parenthesized(kind.type);
      field.presence = Presence::IfJust;
    }
  }
  return field;
}

// The field of a parameter, or why it is left out.
Written<Field> fieldOf(Enums &enums, const AttrOrTypeParameter &param, size_t index) {
  return std::visit(
      llvm::makeVisitor(
          [&](const Kind &kind) -> Written<Field> { return fieldWith(param, index, kind); },
          [&](NotEnum) -> Written<Field> {
            std::optional<Kind> kind = valueKind(param.getCppType());
            if (!kind)
              return Omitted{llvm::formatv("its parameter `{0}` is the C++ `{1}`",
                                           param.getName(), param.getCppType())
                                 .str()};
            return fieldWith(param, index, *kind);
          },
          [](const Omitted &omitted) -> Written<Field> { return omitted; }),
      enumKind(enums, param));
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

// The elements of a type's or an attribute's declarative syntax, each
// optional group's within it; left out, with the reason, for a directive
// the generator does not write (custom, struct, params) and for an else
// branch. Such a syntax has only `qualified`, and the C++ printer alone
// spaces it.
//
// The groups open at the reading point are a stack, the syntax itself at
// the bottom and the innermost group last: a `(` opens one, and its `)` and
// `?` close it into the one around it, so however deep groups nest the
// native stack stays flat. Each element read consumes text, or the reading
// ends, so the loop ends with the text.
Written<std::vector<Element>> elements(StringRef format) {
  llvm::SmallVector<std::vector<Element>, 2> open(1);
  for (format = format.ltrim(); !format.empty(); format = format.ltrim()) {
    std::vector<Element> &out = open.back();
    if (open.size() > 1 && format.consume_front(")")) {
      std::vector<Element> group = std::move(out);
      open.pop_back();
      format = format.ltrim();
      if (!format.consume_front("?"))
        return Omitted{"an optional group with an else branch"};
      open.back().push_back({Element::Group, "", false, std::move(group)});
      continue;
    }
    if (format.consume_front("`")) {
      size_t end = format.find('`');
      if (end == StringRef::npos)
        return Omitted{"a literal that does not end"};
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
      if (!format.consume_front("$"))
        return Omitted{"`qualified` of no parameter"};
      Element inner{Element::Parameter, parameterName(format)};
      format = format.ltrim();
      if (!format.consume_front(")"))
        return Omitted{"`qualified` of more than a parameter"};
      inner.anchor = format.consume_front("^");
      out.push_back(std::move(inner));
      continue;
    }
    if (format.consume_front("(")) {
      open.emplace_back();
      continue;
    }
    StringRef word = format.take_while([](char c) { return llvm::isAlnum(c) || c == '-'; });
    return Omitted{word.empty() ? "an element the generator does not know"
                                : ("the directive `" + word + "`").str()};
  }
  if (open.size() == 1)
    return std::move(open.front());
  return Omitted{"an optional group that does not end"};
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

// The text of a syntax: the pieces that write it, and the parameters it
// writes.
struct Pieces {
  std::vector<Piece> pieces;
  std::vector<std::string> written;
};

// A group of a syntax being written: its elements yet to write, the fields
// as it sees them (its anchor always there inside it), the pieces it has so
// far, and its anchor, a field of the group around it, whose presence there
// decides how the group is written into it.
struct Writing {
  llvm::ArrayRef<Element> rest;
  std::map<std::string, Field> fields;
  Pieces out;
  std::string anchor;
};

// The pieces that write `elements`, each parameter by its field; left out,
// with the reason, for a parameter that is not one or a group without an
// anchor. Inside its group the anchor is the value the group is written
// for: the Just's, or the list that is not empty.
//
// The groups being written are a stack, the syntax itself at the bottom and
// the innermost group last; a group whose elements run out is written into
// the one around it, so however deep groups nest the native stack stays
// flat.
Written<Pieces> piecesOf(const std::vector<Element> &elements,
                         const std::map<std::string, Field> &fields) {
  llvm::SmallVector<Writing, 2> open;
  open.push_back({elements, fields, {}, {}});
  while (true) {
    Writing &top = open.back();
    if (top.rest.empty()) {
      if (open.size() == 1)
        return std::move(top.out);
      Writing done = std::move(top);
      open.pop_back();
      Pieces &out = open.back().out;
      const Field &f = open.back().fields.at(done.anchor);
      llvm::append_range(out.written, done.out.written);
      switch (f.presence) {
      case Presence::IfJust:
        append(out.pieces, {false, llvm::formatv("maybe \"\" (\\{0} => {1}) {0}", f.name,
                                                 expression(done.out.pieces))
                                       .str()});
        break;
      case Presence::IfNonEmpty:
        append(out.pieces, {false, llvm::formatv("(if null {0} then \"\" else {1})", f.name,
                                                 expression(done.out.pieces))
                                       .str()});
        break;
      case Presence::Always:
        for (const Piece &piece : done.out.pieces)
          append(out.pieces, piece);
        break;
      }
      continue;
    }
    const Element &e = top.rest.front();
    top.rest = top.rest.drop_front();
    if (e.form == Element::Literal) {
      append(top.out.pieces, {true, spaced(e.text)});
      continue;
    }
    if (e.form == Element::Parameter) {
      auto field = top.fields.find(e.text);
      if (field == top.fields.end())
        return Omitted{llvm::formatv("its syntax names `{0}`, which is no parameter", e.text).str()};
      const Field &f = field->second;
      top.out.written.push_back(e.text);
      std::string text = llvm::formatv(f.text.c_str(), f.name).str();
      append(top.out.pieces, {false, f.presence == Presence::IfJust
                                         ? llvm::formatv("maybe \"\" (\\{0} => {1}) {0}", f.name, text).str()
                                         : "(" + text + ")"});
      continue;
    }
    const Element *anchor = anchorOf(e);
    if (!anchor || !top.fields.count(anchor->text))
      return Omitted{"an optional group without the parameter that anchors it"};
    std::map<std::string, Field> inside = top.fields;
    inside[anchor->text].presence = Presence::Always;
    open.push_back({e.group, std::move(inside), {}, anchor->text});
  }
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
Written<Def> defOf(Enums &enums, const AttrOrTypeDef &def, bool isType, StringRef sum) {
  std::optional<StringRef> mnemonic = def.getMnemonic();
  if (!mnemonic)
    return Omitted{"it has no mnemonic"};
  if (def.hasCustomAssemblyFormat())
    return Omitted{"its syntax is C++"};
  std::vector<Field> fields;
  std::map<std::string, Field> byName;
  for (const AttrOrTypeParameter &param : def.getParameters()) {
    // The type of an attribute's value is the op's that holds it.
    if (llvm::isa<mlir::tblgen::AttributeSelfTypeParameter>(param))
      continue;
    Written<Field> read = fieldOf(enums, param, fields.size());
    const Field *field = std::get_if<Field>(&read);
    if (!field)
      return std::get<Omitted>(read);
    // A type holds types: the sum of types has no attribute to give.
    if (isType && mentions(field->type, "at"))
      return Omitted{llvm::formatv("its parameter `{0}` is an attribute, which no type holds",
                                   param.getName())
                         .str()};
    fields.push_back(*field);
    byName[param.getName().str()] = *field;
  }
  std::vector<Element> syntax;
  if (std::optional<StringRef> format = def.getAssemblyFormat()) {
    Written<std::vector<Element>> parsed = elements(*format);
    if (const auto *omitted = std::get_if<Omitted>(&parsed))
      return Omitted{llvm::formatv("its syntax `{0}` has {1}", *format, omitted->why).str()};
    syntax = std::get<std::vector<Element>>(std::move(parsed));
  } else if (!fields.empty()) {
    return Omitted{"it has parameters and no syntax"};
  }
  std::string spelling = ((isType ? "!" : "#") + def.getDialect().getName() + "." + *mnemonic).str();
  Written<Pieces> read = piecesOf(syntax, byName);
  const Pieces *text = std::get_if<Pieces>(&read);
  if (!text)
    return std::get<Omitted>(read);
  std::vector<Piece> pieces{{true, spelling}};
  for (const Piece &piece : text->pieces)
    append(pieces, piece);
  for (const auto &[name, field] : byName)
    if (!llvm::is_contained(text->written, name))
      return Omitted{llvm::formatv("its syntax leaves out `{0}`", name).str()};

  std::string constructor = constructorName(def.getCppClassName().str(),
                                            "the " + llvm::Twine(isType ? "type " : "attribute ") +
                                                def.getCppClassName());
  std::string pattern = constructor;
  std::string wildcard = constructor;
  Def out;
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
  return out;
}

// The last name of a dotted module name.
StringRef lastName(StringRef module) {
  size_t dot = module.rfind('.');
  return dot == StringRef::npos ? module : module.drop_front(dot + 1);
}

//===----------------------------------------------------------------------===//
// The Idris modules
//===----------------------------------------------------------------------===//

// What both modules of an upstream dialect are written from, read once:
// its types and attributes, the builders of the ops the specification
// admits and the frontend writes, and, found on the way, the enums all of
// them take.
struct Vocabulary {
  std::optional<mlir::tblgen::Dialect> dialect;
  std::vector<Def> types, attrs;
  std::vector<std::string> omitted;
  std::string ops;
  Enums enums;
};

// The upstream ops the specification admits, each by upstream's own record
// (Generated/IdrAdmitted<D>.td's IdrAdmitted records), in their order: the
// set is the specification's, the ops' facts upstream's, so nothing of
// upstream is restated and a wrong name is TableGen's own error.
std::vector<const llvm::Record *> admittedOps(const llvm::RecordKeeper &records) {
  std::vector<const llvm::Record *> ops;
  for (const llvm::Record *admitted : records.getAllDerivedDefinitionsIfDefined("IdrAdmitted"))
    ops.push_back(admitted);
  return ops;
}

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
      std::string what = (isType ? "type " : "attribute ") + def.getCppClassName().str();
      std::visit(llvm::makeVisitor(
                     [&](Def written) { (isType ? v.types : v.attrs).push_back(std::move(written)); },
                     [&](const Omitted &omitted) { v.omitted.push_back(what + ": " + omitted.why); }),
                 defOf(v.enums, def, isType, (module + (isType ? "Type" : "Attr")).str()));
    }
  llvm::raw_string_ostream opsOs(v.ops);
  for (const llvm::Record *admitted : admittedOps(records)) {
    Operator op(admitted->getValueAsDef("op"));
    if (op.getDialectName() != dialectName || admitted->getValueAsInt("frontendWrites") == 0)
      continue;
    emitOp(v.enums, op, *admitted, opsOs);
  }
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

// The license of a module the generator writes into the tree: the
// generator is ours and so is the ODS it reads, so the module is ours too,
// under the line every file of ours opens with. It comes first, before the
// module's documentation.
void writeLicense(llvm::raw_ostream &os) {
  os << "-- SPDX-License-Identifier: 0BSD\n-- Copyright (c) 2026 Bjorn Pagen\n";
}

bool emitIdrisSyntax(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  Vocabulary v = read(records, "gen-idris-syntax");
  std::string enumerations, types, attrs;
  llvm::raw_string_ostream enumsOs(enumerations), typesOs(types), attrsOs(attrs);
  for (const auto &[name, used] : v.enums)
    emitEnum(used, enumsOs);
  for (const auto &[name, used] : v.enums)
    emitCaseFields(used, enumsOs);
  emitSum(v.types, true, typesOs);
  emitSum(v.attrs, false, attrsOs);

  writeLicense(os);
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
    for (const std::string &line : v.omitted)
      os << "-- " << line << "\n";
  }
  return false;
}

bool emitIdrisDialect(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  if (syntaxModuleName.empty())
    llvm::PrintFatalError("-gen-idris-dialect needs -idris-syntax-module");
  Vocabulary v = read(records, "gen-idris-dialect");
  writeLicense(os);
  os << "||| The " << dialectName << " dialect's ops the frontend writes, as the Idris side\n"
     << "||| builds them: one builder per op the specification admits. Generated by\n"
     << "||| idris-mlir-tblgen -gen-idris-dialect from upstream's ODS. Do not edit.\n"
     << "module " << moduleName << "\n\nimport IdrisMLIR.MLIR\nimport IdrisMLIR.Dialect.Idr\nimport "
     << syntaxModuleName << "\n\nimport Data.List\n\n%default total\n\n";
  section(os, "Ops", v.ops);
  return false;
}

//===----------------------------------------------------------------------===//
// Bytecode entries
//===----------------------------------------------------------------------===//

// A dialect's bytecode records are upstream's DSL (mlir/IR/BytecodeBase.td),
// from which mlir-tblgen -gen-bytecode writes the C++ reader. Nothing
// upstream writes Idris, so the Idris writer's encoders are generated here
// from the same records, and an entry has one layout. A record's code is its
// place in its dialect's `elems`, by which the reader dispatches. Its
// encoder takes its members in order and gives its parts, its code first,
// each member as the reader reads it: a member's kind is its parser
// template, which WithType and WithGetter keep (so `WithType<"::mlir::
// FunctionType", Type>` is a type, and a List<k> a k), and an array and a
// composite are told by their DSL classes, as -gen-bytecode tells them. A
// record with a member of any other kind has no encoder, and the module
// says why.

// How an encoder takes a member read by one of the reader's own methods, or
// an enum, and writes it: its Idris type, and the expression of its parts
// from a value `{0}` of it, one Part or, with `one` false, a List Part.
struct Atom {
  std::string type;
  std::string parts;
  bool one;
};

// The atoms, by the parser template each is read by. A dialect's attribute
// or type as a member (a builtin StringAttr in a NamedAttribute) is read as
// any attribute or type is. An attribute is its entry's number, and an
// optional one that or none. A type is the parts the
// writer gives for it: the number of its entry, or a field of what holds
// it.
std::optional<Atom> atomOf(StringRef parser) {
  static const std::pair<StringRef, Atom> atoms[] = {
      {"succeeded($_reader.readVarInt($_var))", {"Nat", "VarInt {0}", true}},
      {"succeeded($_reader.readSignedVarInt($_var))", {"Integer", "SignedVarInt {0}", true}},
      {"succeeded($_reader.readBool($_var))", {"Bool", "Flag {0}", true}},
      {"succeeded($_reader.readString($_var))", {"String", "Str {0}", true}},
      {"succeeded($_reader.readAttribute($_var))", {"AttrRef", "AttrAt {0}", true}},
      {"succeeded($_reader.readAttribute<$_resultType>($_var))", {"AttrRef", "AttrAt {0}", true}},
      {"succeeded($_reader.readOptionalAttribute($_var))", {"Maybe AttrRef", "OptionalAttrAt {0}", true}},
      {"succeeded($_reader.readType($_var))", {"List Part", "{0}", false}},
      {"succeeded($_reader.readType<$_resultType>($_var))", {"List Part", "{0}", false}}};
  for (const auto &[template_, atom] : atoms)
    if (template_ == parser)
      return atom;
  return std::nullopt;
}

// A member of a record, its nodes in preorder: each an atom; an array of
// its one element, the node after it, written as its count and then each
// element; or a composite of the `arity` members after it, written one
// after the other. Each node holds the name it is bound by: a record's
// member and a composite's by their DSL names, an array's element by `x`;
// a composite binds nothing of its own. Flat, every walk over a member is
// a loop, however deep upstream nests its arrays and composites.
struct MemberNode {
  enum Form { Atomic, Array, Composite } form;
  Atom atom = {};
  unsigned arity = 0;
  std::string name = {};
};
using Member = std::vector<MemberNode>;

// The member `def` declares, bound by `name`, or why it cannot be read. An
// enum is a member that names its enum (an `enumName` field): the syntax
// module's, whose value of a case is what the reader reads. The records
// left to read are a stack, the next last, each with the name its node is
// bound by and the name a refusal gives it (an array's element is reported
// by the array's); a composite's members are pushed last first, so they are
// read, and the first refusal met, in their order.
Written<Member> memberOf(const llvm::Record *def, StringRef name) {
  struct Pending {
    const llvm::Record *def;
    std::string bound;
    StringRef reported;
  };
  Member member;
  llvm::SmallVector<Pending> pending{{def, name.str(), name}};
  while (!pending.empty()) {
    Pending next = pending.pop_back_val();
    if (next.def->getValue("enumName")) {
      std::string e = next.def->getValueAsString("enumName").str();
      member.push_back({MemberNode::Atomic,
                        {e, "VarInt (" + camel(e, false) + "Value {0})", true},
                        0,
                        std::move(next.bound)});
      continue;
    }
    if (next.def->isSubClassOf("ArrayWithKnownSize"))
      return Omitted{llvm::formatv("its member `{0}` is an array whose count another member gives",
                                   next.reported)
                         .str()};
    if (next.def->isSubClassOf("Array")) {
      member.push_back({MemberNode::Array, {}, 1, std::move(next.bound)});
      pending.push_back({next.def->getValueAsDef("elemT"), "x", next.reported});
      continue;
    }
    if (next.def->isSubClassOf("CompositeBytecode")) {
      const llvm::DagInit *dag = next.def->getValueAsDag("members");
      member.push_back({MemberNode::Composite, {}, dag->getNumArgs(), std::move(next.bound)});
      for (unsigned i = dag->getNumArgs(); i-- > 0;) {
        StringRef inner = dag->getArgNameStr(i);
        pending.push_back({llvm::cast<llvm::DefInit>(dag->getArg(i))->getDef(), inner.str(), inner});
      }
      continue;
    }
    StringRef parser = next.def->getValueAsString("cParser");
    std::optional<Atom> atom = atomOf(parser);
    if (!atom)
      return Omitted{
          llvm::formatv("its member `{0}` is read by `{1}`", next.reported, parser).str()};
    member.push_back({MemberNode::Atomic, *atom, 0, std::move(next.bound)});
  }
  return member;
}

// The Idris type of a member: one word or a tuple, which an argument writes
// as it is, or a type applied, which it parenthesizes.
struct IdrisType {
  std::string text;
  bool closed;
};

// Each node's type is made from its members', which follow it: read
// backwards, a node finds them on the stack, its first member's on top. A
// composite of one member reads as that member.
IdrisType typeOf(const Member &member) {
  llvm::SmallVector<IdrisType> types;
  for (const MemberNode &node : llvm::reverse(member)) {
    switch (node.form) {
    case MemberNode::Atomic:
      types.push_back({node.atom.type, !StringRef(node.atom.type).contains(' ')});
      break;
    case MemberNode::Array: {
      IdrisType element = types.pop_back_val();
      types.push_back(
          {"List " + (element.closed ? element.text : "(" + element.text + ")"), false});
      break;
    }
    case MemberNode::Composite: {
      if (node.arity == 1)
        break;
      std::vector<std::string> texts;
      for (unsigned i = 0; i < node.arity; ++i)
        texts.push_back(types.pop_back_val().text);
      types.push_back({"(" + llvm::join(texts, ", ") + ")", true});
      break;
    }
    }
  }
  return types.back();
}

// The names an encoder's body uses unqualified, besides what it binds.
bool isUsedInEncoders(StringRef name) {
  static constexpr StringRef names[] = {"length", "map", "concat", "concatMap"};
  return llvm::is_contained(names, name);
}

// A name for a member's value after its DSL name, hiding nothing the body
// uses and no name bound around it.
std::string fresh(StringRef dslName, std::set<std::string> &scope) {
  std::string name = camel(dslName, false);
  while (isReserved(name) || isUsedInEncoders(name) || scope.count(name))
    name += '\'';
  scope.insert(name);
  return name;
}

// One piece of an encoder's parts: one Part, or a List Part.
struct PartsPiece {
  bool one;
  std::string text;
};

// The expression of pieces: each run of single parts a list, the lists
// joined by `++`.
std::string partsExpression(const std::vector<PartsPiece> &pieces) {
  std::vector<std::string> lists, run;
  auto close = [&] {
    if (!run.empty())
      lists.push_back("[" + llvm::join(run, ", ") + "]");
    run.clear();
  };
  for (const PartsPiece &piece : pieces) {
    if (piece.one) {
      run.push_back(piece.text);
      continue;
    }
    close();
    lists.push_back(piece.text);
  }
  close();
  return lists.empty() ? "[]" : llvm::join(lists, " ++ ");
}

// The names a member's nodes bind, fresh in `scope` in preorder: an atom's
// value and an array's are named where they are met; an array's element is
// named in a copy of the scope, which the walk drops back to where the
// element ends, so an element's names hide nothing after it; a composite
// names nothing of its own. Where each node's subtree ends is read first,
// backwards, each node finding its members' sizes on the stack.
std::vector<std::string> namesOf(const Member &member, std::set<std::string> &scope) {
  std::vector<std::size_t> end(member.size());
  llvm::SmallVector<std::size_t> sizes;
  for (std::size_t i = member.size(); i-- > 0;) {
    std::size_t size = 1;
    for (unsigned k = 0; k < member[i].arity; ++k)
      size += sizes.pop_back_val();
    sizes.push_back(size);
    end[i] = i + size;
  }
  // The elements the walk is in, innermost last: where each ends, and the
  // scope as it was before it.
  struct InElement {
    std::size_t end;
    std::set<std::string> outer;
  };
  llvm::SmallVector<InElement> in;
  auto leave = [&](std::size_t at) {
    while (!in.empty() && in.back().end == at) {
      scope = std::move(in.back().outer);
      in.pop_back();
    }
  };
  std::vector<std::string> names(member.size());
  for (std::size_t i = 0; i < member.size(); ++i) {
    leave(i);
    const MemberNode &node = member[i];
    if (node.form == MemberNode::Composite)
      continue;
    names[i] = fresh(node.name, scope);
    if (node.form == MemberNode::Array)
      in.push_back({end[i], scope});
  }
  leave(member.size());
  return names;
}

// A node bound: the pattern that binds its value, and the pieces that write
// it.
struct Bound {
  std::string pattern;
  std::vector<PartsPiece> pieces;
};

// Binds a member's value, under names fresh in `scope`: appends the pattern
// that binds it to `patterns`, and the pieces that write it to `pieces`. An
// array's elements are written by a function of one element, as the map
// of a constructor where one part writes an element. Each node is bound
// from its members' bindings, which follow it: read backwards, a node finds
// them on the stack, its first member's on top. A composite of one member
// is bound as that member.
void bindMember(const Member &member, std::set<std::string> &scope,
                std::vector<std::string> &patterns, std::vector<PartsPiece> &pieces) {
  std::vector<std::string> names = namesOf(member, scope);
  llvm::SmallVector<Bound> bound;
  for (std::size_t i = member.size(); i-- > 0;) {
    const MemberNode &node = member[i];
    switch (node.form) {
    case MemberNode::Atomic:
      bound.push_back(
          Bound{names[i], {{node.atom.one, llvm::formatv(node.atom.parts.c_str(), names[i]).str()}}});
      break;
    case MemberNode::Array: {
      Bound element = bound.pop_back_val();
      const std::string &values = names[i];
      const std::string &pattern = element.pattern;
      Bound array{values, {{true, "VarInt (length " + values + ")"}}};
      if (element.pieces.size() == 1 && !element.pieces.front().one &&
          element.pieces.front().text == pattern) {
        array.pieces.push_back({false, "concat " + values});
      } else if (element.pieces.size() == 1 && element.pieces.front().one) {
        StringRef text = element.pieces.front().text;
        bool eta = text.ends_with(" " + pattern) &&
                   !text.drop_back(pattern.size() + 1).contains(' ');
        array.pieces.push_back(
            {false, eta ? ("map " + text.drop_back(pattern.size() + 1) + " " + values).str()
                        : "map (\\" + pattern + " => " + text.str() + ") " + values});
      } else {
        array.pieces.push_back({false, "concatMap (\\" + pattern + " => " +
                                           partsExpression(element.pieces) + ") " + values});
      }
      bound.push_back(std::move(array));
      break;
    }
    case MemberNode::Composite: {
      if (node.arity == 1)
        break;
      std::vector<std::string> inner;
      Bound composite;
      for (unsigned k = 0; k < node.arity; ++k) {
        Bound each = bound.pop_back_val();
        inner.push_back(std::move(each.pattern));
        llvm::append_range(composite.pieces, each.pieces);
      }
      composite.pattern = "(" + llvm::join(inner, ", ") + ")";
      bound.push_back(std::move(composite));
      break;
    }
    }
  }
  patterns.push_back(std::move(bound.back().pattern));
  llvm::append_range(pieces, bound.back().pieces);
}

// A record's members, each as the reader reads it, bound by its DSL name.
using Members = std::vector<Member>;

Written<Members> membersOf(const llvm::Record *def) {
  const llvm::DagInit *dag = def->getValueAsDag("members");
  Members read;
  for (unsigned i = 0, e = dag->getNumArgs(); i < e; ++i) {
    Written<Member> member =
        memberOf(llvm::cast<llvm::DefInit>(dag->getArg(i))->getDef(), dag->getArgNameStr(i));
    if (const auto *omitted = std::get_if<Omitted>(&member))
      return *omitted;
    read.push_back(std::get<Member>(std::move(member)));
  }
  return read;
}

// A record's code: its place among `among`.
void emitCode(const llvm::Record *def, size_t code, StringRef among, llvm::raw_ostream &os) {
  std::string codeName = camel(def->getName(), false) + "Code";
  os << "||| The code of `" << def->getName() << "`, its place among " << among
     << ".\nexport\n" << codeName << " : Nat\n" << codeName << " = " << code << "\n\n";
}

// A record's encoder: its parts, `leading` (an entry's code) and then its
// members in order, which `described` and the members' names say.
void emitEncoder(const llvm::Record *def, const Members &read, std::vector<PartsPiece> leading,
                 std::vector<std::string> described, llvm::raw_ostream &os) {
  std::string record = def->getName().str();
  std::set<std::string> scope;
  std::vector<std::string> patterns;
  for (const Member &member : read) {
    bindMember(member, scope, patterns, leading);
    described.push_back("`" + member.front().name + "`");
  }
  std::string encoder = "encode" + record;
  os << "||| The parts of `" << record << "`: " << llvm::join(described, ", ")
     << ".\nexport\n" << encoder << " : ";
  for (const Member &member : read)
    os << typeOf(member).text << " -> ";
  os << "List Part\n" << encoder;
  for (const std::string &pattern : patterns)
    os << " " << pattern;
  os << " = " << partsExpression(leading) << "\n\n";
}

// One entry's code and encoder, or its code and why it has no encoder.
void emitRecord(const llvm::Record *def, size_t code, StringRef what, llvm::raw_ostream &os,
                std::vector<std::string> &omitted) {
  emitCode(def, code, ("the dialect's " + what + "s").str(), os);
  std::string codeName = camel(def->getName(), false) + "Code";
  std::visit(llvm::makeVisitor(
                 [&](const Members &read) {
                   emitEncoder(def, read, {{true, "VarInt " + codeName}}, {"its code"}, os);
                 },
                 [&](const Omitted &o) {
                   omitted.push_back(llvm::formatv("{0} {1}: {2}", what, def->getName(), o.why).str());
                 }),
             membersOf(def));
}

// The records of the dialect's types or attributes, in `elems` order: the
// list of the DialectTypes or DialectAttributes of -idris-dialect. The DSL
// names a dialect as its C++ class does (`Idr`, `Builtin`), ODS by its
// namespace (`idr`, `builtin`), so the two are compared without case.
std::vector<const llvm::Record *> elemsOf(const llvm::RecordKeeper &records, StringRef kind,
                                          bool &found) {
  std::vector<const llvm::Record *> elems;
  for (const llvm::Record *def : records.getAllDerivedDefinitionsIfDefined(kind))
    if (def->getValueAsString("dialect").equals_insensitive(dialectName)) {
      elems = def->getValueAsListOfDefs("elems");
      found = true;
    }
  return elems;
}

bool emitIdrisBytecode(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  if (dialectName.empty() || moduleName.empty() || syntaxModuleName.empty())
    llvm::PrintFatalError(
        "-gen-idris-bytecode needs -idris-dialect, -idris-module and -idris-syntax-module");
  bool found = false;
  std::vector<const llvm::Record *> types = elemsOf(records, "DialectTypes", found);
  std::vector<const llvm::Record *> attrs = elemsOf(records, "DialectAttributes", found);
  if (!found)
    llvm::PrintFatalError("no bytecode records of the dialect " + dialectName);
  std::string typesText, attrsText;
  llvm::raw_string_ostream typesOs(typesText), attrsOs(attrsText);
  std::vector<std::string> omitted;
  for (auto [code, def] : llvm::enumerate(types))
    emitRecord(def, code, "type", typesOs, omitted);
  for (auto [code, def] : llvm::enumerate(attrs))
    emitRecord(def, code, "attribute", attrsOs, omitted);
  writeLicense(os);
  os << "||| The " << dialectName << " dialect's bytecode entries, as the Idris side writes\n"
     << "||| them: the code of each of its records, and the parts of each record whose\n"
     << "||| members' kinds are known, from its members in order, a type as the parts\n"
     << "||| the writer gives for it. Generated by\n"
     << "||| idris-mlir-tblgen -gen-idris-bytecode from the dialect's bytecode records,\n"
     << "||| from which mlir-tblgen -gen-bytecode writes the C++ reader; `make build`\n"
     << "||| writes it (tools/dialects.sh). Do not edit.\n"
     << "module " << moduleName << "\n\nimport IdrisMLIR.MLIR.Parts\nimport " << syntaxModuleName
     << "\n\n%default total\n\n";
  section(os, "Types", typesText);
  section(os, "Attributes", attrsText);
  if (!omitted.empty()) {
    os << "-- Not generated:\n";
    for (const std::string &line : omitted)
      os << "-- " << line << "\n";
  }
  return false;
}

//===----------------------------------------------------------------------===//
// The admitted upstream ops' classes
//===----------------------------------------------------------------------===//

// The C++ class of every upstream op the specification admits, by the name
// of its record: `::idr::admitted::Arith_AddIOp` is `::mlir::arith::AddIOp`.
// Stage legality, the e-graph's kinds and every per-op table name an
// upstream op through this, so its class is read from its def and the
// specification never restates one.
bool emitAdmittedClasses(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  os << "// The classes of the upstream ops the dialect admits, by their records'\n"
     << "// names: generated by idris-mlir-tblgen -gen-admitted-classes from\n"
     << "// upstream's ODS and the specification's admitted records. Do not edit.\n\n"
     << "namespace idr::admitted {\n";
  for (const llvm::Record *admitted : admittedOps(records)) {
    const llvm::Record *def = admitted->getValueAsDef("op");
    os << "using " << def->getName() << " = " << Operator(def).getQualCppClassName() << ";\n";
  }
  os << "} // namespace idr::admitted\n";
  return false;
}

const mlir::GenRegistration genIdrisSyntax("gen-idris-syntax",
                                           "The Idris side's syntax of a dialect",
                                           emitIdrisSyntax);
const mlir::GenRegistration genIdrisDialect("gen-idris-dialect",
                                            "The Idris side's ops of a dialect",
                                            emitIdrisDialect);
const mlir::GenRegistration genIdrisBytecode("gen-idris-bytecode",
                                             "The Idris side's bytecode entries of a dialect",
                                             emitIdrisBytecode);
const mlir::GenRegistration genAdmittedClasses("gen-admitted-classes",
                                              "The C++ classes of the admitted upstream ops",
                                              emitAdmittedClasses);

} // namespace

int main(int argc, char **argv) { return mlir::MlirTblgenMain(argc, argv); }
