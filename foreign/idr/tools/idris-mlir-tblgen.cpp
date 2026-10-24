// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir-tblgen: the one generator of ours not written in Idris, a
// TableGen backend reading upstream's records, which stay upstream's. The
// dialect's specification (compiler/spec/) states every fact of ours and
// prints which upstream ops it admits, one record per op naming upstream's
// own def (Generated/IdrAdmitted<D>.td), and by which of a dialect's
// bytecode records the frontend writes its types and attributes, one
// record per entry naming upstream's own (Generated/Idr<D>Entries.td);
// this reads, through mlir::tblgen, upstream's records for those alone:
//
// - -gen-idris-syntax, an upstream dialect's syntax for the Idris side: the
//   enums its admitted ops, types and attributes take, and its types and
//   attributes with the printers of the syntax ODS declares for them
//   (compiler/src/IdrisMLIR/Syntax/).
// - -gen-idris-dialect, a builder of each admitted op the frontend writes,
//   a guarded op's with the guards its admitted record gives it, and, for a
//   dialect whose syntax holds its attributes, the smart constructor that
//   spells one (compiler/src/IdrisMLIR/Dialect/).
// - -gen-idris-bytecode, an upstream dialect's bytecode entries the
//   frontend writes, for the Idris writer, from their records in upstream's
//   bytecode DSL (compiler/src/IdrisMLIR/Encoding/).
// - -gen-admitted-classes, the C++ class of every admitted op of one
//   admitted record file by the alias the specification gives it, so no
//   C++ restates an upstream class.
//
// It is a backend rather than a program over a dump of the records because
// it reads ODS through mlir::tblgen (Operator, Attribute, AttrOrTypeDef,
// EnumInfo), the reading upstream's own C++ is generated from, so the two
// sides cannot take one op differently. The declarative format of an
// attribute (arith's flags, ub's poison) is re-read by a subset parser
// below, since upstream's format parser lives in the mlir-tblgen executable,
// not a library.

#include "idr/Support/Match.h"

#include "mlir/TableGen/AttrOrTypeDef.h"
#include "mlir/TableGen/Attribute.h"
#include "mlir/TableGen/Dialect.h"
#include "mlir/TableGen/EnumInfo.h"
#include "mlir/TableGen/GenInfo.h"
#include "mlir/TableGen/Operator.h"
#include "mlir/TableGen/Property.h"
#include "mlir/TableGen/Trait.h"
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

#include <array>
#include <cstdint>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <type_traits>
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

// The first letter of a name in camel case: lowered, as a function's or a
// parameter's is; or raised, as a constructor's must be.
enum class Initial { Lowered, Raised };

// `str.append`, `put_str` as `strAppend`, `putStr`, or with the initial
// raised `StrAppend`, `PutStr`.
std::string camel(StringRef name, Initial initial) {
  std::string out;
  bool raise = initial == Initial::Raised;
  for (char c : name) {
    if (c == '.' || c == '_') {
      raise = !out.empty() || initial == Initial::Raised;
      continue;
    }
    if (out.empty())
      out += initial == Initial::Raised ? llvm::toUpper(c) : llvm::toLower(c);
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
// clause binds of its operands and results; `checkingEach` what a guarded
// builder checks a group of any number by.
bool isUsedInBodies(StringRef name) {
  static constexpr StringRef names[] = {
      "concat", "toList",    "length",    "map",       "show",   "unitIf",
      "attrIf", "commaSeparated", "v",    "t",         "a",      "ty",
      "at",     "fastConcat", "maybe",    "null",      "symbol", "symbolRef",
      "utf8",   "array",     "signature", "separated", "minus",  "iterateN",
      "os",     "rs",        "rest",      "checkingEach"};
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
  std::string name = camel(odsName, Initial::Lowered);
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

// The last name of a dotted module name.
StringRef lastName(StringRef module) {
  size_t dot = module.rfind('.');
  return dot == StringRef::npos ? module : module.drop_front(dot + 1);
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

// Whether an Idris value is one item or a list of them. A kind's Idris type
// is its item's type, or a list of it; among a generated list's pieces, a
// run of items is written as one list literal, and a list as it is.
enum class ItemOrList { Item, List };

// Which of a dialect's sums a def belongs to: its types, or its attributes,
// which hold types and attributes both.
enum class DefKind { Type, Attribute };

// How the Idris side gives a value of some kind, and writes it: whether it
// is one item or a list of them, the Idris type of an item, the expression
// that writes it from a value `{0}` of the kind, and the sum whose defs can
// hold such a value: the types', and so either, or the attributes' alone,
// for a value that holds an attribute (`at`), which no type holds. The
// kind's own Idris type is made from the first two, so whether it is a list
// is never read back from its text.
struct Kind {
  ItemOrList form;
  std::string item;
  std::string text;
  DefKind sum;

  std::string type() const {
    return form == ItemOrList::List ? "List " + parenthesized(item) : item;
  }
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

// A field in which every case of an enum names a case of another enum (a
// rule's category): the Idris side reads it as a function from the one enum
// to the other, named after the enum and the field.
struct CaseField {
  std::string field;
  const llvm::Record *values; // the enum whose cases the field names
};

// Whether the syntax module writes each case's value: where an op's
// builder writes a case as its value, an integer attribute, which is the
// one reader of a case's value.
enum class Values { Unread, ReadByBuilders };

// Whether the syntax module writes each case's spelling: where a type's or
// an attribute's syntax spells a case, which is the one reader of it.
enum class Spellings { Unread, ReadBySyntax };

// The enums the dialect's ops, types and attributes take, by their ODS
// records: written once each, in the syntax module, with their values
// where a builder reads them, their spellings where a syntax prints one,
// and the fields in which their cases name another enum's.
struct Enum {
  const llvm::Record *def;
  Values values = Values::Unread;
  Spellings spellings = Spellings::Unread;
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
  return constructorName(camel(c.getSymbol(), Initial::Raised),
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
  // Two different cases are unequal; an enum of one case has no such pair,
  // and a clause for it would be unreachable.
  if (cases.size() > 1)
    os << "  _ == _ = False\n";
  os << "\n";
  // Each case shows as its ODS string, the one way a value of it reads.
  os << "export\nShow " << name << " where\n";
  for (const EnumCase &c : cases)
    os << "  show " << qualifiedCase(info, c) << " = " << literal(c.getStr()) << "\n";
  os << "\n";
  std::string lower = camel(name, Initial::Lowered);
  // The value of each case, beside the enum, for the builders that write a
  // case as its value, an op's integer attribute. The Idris side holds it
  // as a Nat, which the builder makes the attribute's integer; a negative
  // value would be another value there, so it is refused here.
  if (used.values == Values::ReadByBuilders) {
    os << "||| The value of each " << name << ".\nexport\n"
       << lower << "Value : " << name << " -> Nat\n";
    for (const EnumCase &c : cases) {
      if (c.getValue() < 0)
        llvm::PrintFatalError(&c.getDef(), "the case " + c.getSymbol() + " of " + name +
                                               " has a negative value");
      os << lower << "Value " << qualifiedCase(info, c) << " = " << c.getValue() << "\n";
    }
    os << "\n";
  }
  if (used.spellings == Spellings::Unread)
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
    std::string function = camel(name, Initial::Lowered) + camel(f.field, Initial::Raised);
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

// How a row of upstream's records is matched against an attribute's
// record: as the one def it names, or as any def of the class it names.
enum class Match { TheDef, OfClass };

// What an op attribute holds besides itself that its Idris value writes:
// nothing; or the value type ODS gives it, which must be one exact type:
// for an integer, an integer type or index, as an integer attribute holds
// its type; for a float, a builtin float type.
enum class Valued { Alone, ByIntegerType, ByFloatType };

// An upstream attribute the Idris side gives as a value of its own: the
// record ODS declares it by, how an attribute's base record is matched
// against it, its kind's form and item type, and the expression that writes
// `{0}`, in which `{1}` is the value type of a row valued by it.
// Each record is named here once and resolved once per run, so an op
// attribute's kind is read off the record it is built on, never off the C++
// class that stores it. A def's row comes before the row of a class that
// holds it.
struct AttrRow {
  StringRef record;
  Match match;
  Valued valued;
  ItemOrList form;
  StringRef item;
  StringRef text;
};

constexpr AttrRow attrRows[] = {
    {"BoolAttr", Match::TheDef, Valued::Alone, ItemOrList::Item, "Bool", "BoolAttr {0}"},
    {"SignlessIntegerAttrBase", Match::OfClass, Valued::ByIntegerType, ItemOrList::Item,
     "Integer", "IntegerAttr {0} ({1})"},
    {"IndexAttr", Match::TheDef, Valued::ByIntegerType, ItemOrList::Item, "Integer",
     "IntegerAttr {0} ({1})"},
    {"FloatAttrBase", Match::OfClass, Valued::ByFloatType, ItemOrList::Item, "Double",
     "FloatAttr {0} ({1})"},
    {"StringBasedAttr", Match::OfClass, Valued::Alone, ItemOrList::Item, "String",
     "StringAttr {0}"},
    {"FlatSymbolRefAttr", Match::TheDef, Valued::Alone, ItemOrList::Item, "String",
     "SymbolRefAttr (MkSymbolRef {0} [])"},
    {"SymbolRefAttr", Match::TheDef, Valued::Alone, ItemOrList::Item, "SymbolRef",
     "SymbolRefAttr {0}"},
    {"TypeAttrBase", Match::OfClass, Valued::Alone, ItemOrList::Item, "MlirType",
     "TypeAttr {0}"},
    {"TypeArrayAttr", Match::TheDef, Valued::Alone, ItemOrList::List, "MlirType",
     "ArrayAttr (map TypeAttr {0})"},
    {"ArrayAttrBase", Match::OfClass, Valued::Alone, ItemOrList::List, "MlirAttr",
     "ArrayAttr {0}"},
    {"DenseI32ArrayAttr", Match::TheDef, Valued::Alone, ItemOrList::List, "Nat",
     "DenseI32ArrayAttr {0}"},
    {"DenseI64ArrayAttr", Match::TheDef, Valued::Alone, ItemOrList::List, "Integer",
     "DenseI64ArrayAttr {0}"},
};

// The upstream records the generator reads an op's ODS by, each named once
// and resolved once per run: every row's, in the rows' order; the unit
// attribute, which an op takes as present or absent; the index type; and
// the two traits by which an op's variadic groups carry their sizes.
struct Upstream {
  std::array<const llvm::Record *, std::size(attrRows)> rows;
  const llvm::Record *unitAttr;
  const llvm::Record *index;
  const llvm::Record *operandSegments;
  const llvm::Record *resultSegments;
};

const llvm::Record *upstreamDef(const llvm::RecordKeeper &records, StringRef name) {
  const llvm::Record *def = records.getDef(name);
  if (!def)
    llvm::PrintFatalError("upstream's ODS has no def " + name);
  return def;
}

Upstream upstream(const llvm::RecordKeeper &records) {
  Upstream u{{},
             upstreamDef(records, "UnitAttr"),
             upstreamDef(records, "Index"),
             upstreamDef(records, "AttrSizedOperandSegments"),
             upstreamDef(records, "AttrSizedResultSegments")};
  for (auto [row, record] : llvm::zip_equal(attrRows, u.rows)) {
    if (row.match == Match::TheDef) {
      record = upstreamDef(records, row.record);
      continue;
    }
    record = records.getClass(row.record);
    if (!record)
      llvm::PrintFatalError("upstream's ODS has no class " + row.record);
  }
  return u;
}

// Whether `op` lists the trait `trait`, through the trait lists that hold
// it.
bool lists(const Operator &op, const llvm::Record *trait) {
  return llvm::any_of(op.getTraits(),
                      [&](const mlir::tblgen::Trait &each) { return &each.getDef() == trait; });
}

// The type an ODS type constraint names when it is one exact type, as the
// attribute its row makes holds it: an integer attribute's type, an integer
// type or index, as IdrisMLIR.MLIR's integer-or-index; a float attribute's,
// as a constructor of IdrisMLIR.MLIR's types.
std::optional<std::string> heldType(const Upstream &u, Valued valued, const llvm::Record &type) {
  switch (valued) {
  case Valued::ByIntegerType:
    if (type.isSubClassOf("I"))
      return llvm::formatv("OfWidth {0}", type.getValueAsInt("bitwidth")).str();
    if (&type == u.index)
      return std::string("OfIndex");
    return std::nullopt;
  case Valued::ByFloatType:
    if (type.isSubClassOf("F") && type.getValueAsInt("bitwidth") == 64)
      return std::string("F64Type");
    return std::nullopt;
  // An attribute valued alone holds no type.
  case Valued::Alone:
    return std::nullopt;
  }
  llvm_unreachable("a closed set of ways an attribute is valued");
}

// How the ops' module writes a value of an enum stored as an integer of
// `width` bits, which the generic form writes as its value: the syntax
// module's value of the case.
Kind enumValue(Enums &enums, const llvm::Record *def, int64_t width) {
  EnumInfo info(def);
  std::string name = enumName(info);
  useEnum(enums, def).values = Values::ReadByBuilders;
  return Kind{ItemOrList::Item, name,
              llvm::formatv("IntegerAttr (natToInteger ({0}Value {{0})) (OfWidth {1})",
                            camel(name, Initial::Lowered), width)
                  .str(),
              DefKind::Type};
}

// How an op attribute of this constraint is given, once what makes it
// optional is set apart: by the record of the attribute it is built on. An
// integer enum that is itself the attribute is its case's value (an
// EnumAttr is an attribute of its own around the enum, a dialect's); a bit
// enum is the integer attribute ODS stores it in; any attribute no row
// names (an interface, a dialect's attribute, an integer or a float of no
// one builtin type) is given as the attribute its maker wrote. Each is a
// value of IdrisMLIR.MLIR's own, never a sum's `at`, so either sum holds it.
Kind attributeKind(Enums &enums, const Upstream &u, const mlir::tblgen::Attribute &attr) {
  const llvm::Record *def = &attr.getBaseAttr().getDef();
  if (def->isSubClassOf("EnumAttrInfo")) {
    EnumInfo info(def);
    if (!info.isBitEnum())
      return enumValue(enums, def, info.getBitwidth());
    def = info.getBaseAttrClass();
  }
  for (auto [row, record] : llvm::zip_equal(attrRows, u.rows)) {
    if (row.match == Match::TheDef ? def != record : !def->isSubClassOf(record))
      continue;
    if (row.valued == Valued::Alone)
      return {row.form, row.item.str(), row.text.str(), DefKind::Type};
    std::optional<mlir::tblgen::Type> type = mlir::tblgen::Attribute(def).getValueType();
    std::optional<std::string> held =
        type ? heldType(u, row.valued, type->getDef()) : std::optional<std::string>();
    if (held)
      return {row.form, row.item.str(), llvm::formatv(row.text.data(), "{0}", *held).str(),
              DefKind::Type};
    break;
  }
  return {ItemOrList::Item, "MlirAttr", "{0}", DefKind::Type};
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
std::string joined(const std::vector<std::pair<std::string, ItemOrList>> &pieces) {
  std::vector<std::string> lists, run;
  auto close = [&] {
    if (!run.empty())
      lists.push_back("[" + llvm::join(run, ", ") + "]");
    run.clear();
  };
  for (const auto &[text, form] : pieces) {
    if (form == ItemOrList::Item) {
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
  std::vector<std::pair<std::string, ItemOrList>> pieces;
  for (const auto &[name, partArity] : parts)
    pieces.emplace_back(partArity == '?' ? "(toList " + name + ")" : name,
                        partArity == '1' ? ItemOrList::Item : ItemOrList::List);
  return joined(pieces);
}

// Whether an op's attribute is always there, its entry written as itself;
// or there only when given, written as the expression that has it or not.
enum class EntryPresence { Always, WhenGiven };

// A list of attributes, as an expression: the entries always there in
// lists, each joined to the next by `++`, and those there only when given
// as the expression that has them or not.
std::string dictionaryOf(const std::vector<std::pair<std::string, EntryPresence>> &parts) {
  std::vector<std::string> pieces;
  std::string run;
  for (const auto &[text, presence] : parts) {
    if (presence == EntryPresence::Always) {
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

// The name of the dialect the Idris module is of, as the specification's
// closed set of dialects names it: the module's last name, which the
// specification gives as the dialect's constructor (`Dialect.Arith`).
std::string dialectConstructor() { return ("Dialect." + lastName(moduleName)).str(); }

// The body of an admitted op's builder, `made` the op: its guards, each
// written before the op as the check of the operand group the guard is
// given first, against the groups it is given after, its continuation
// binding that group's parameter again to what the check gives, so every
// later guard and the op itself take the checked value; then the op. A
// group of one operand is checked by `Checking`; one that holds any number,
// or none, by `checkingEach`, operand by operand against the same others,
// its parameter then the list of what the checks give, which the op's
// operand list and a later guard read as a group's operands either way.
// The specification cannot know upstream's operand groups, so a position
// past them is refused here, where the record is read.
std::string guardedBody(const Operator &op,
                        llvm::ArrayRef<const llvm::Record *> guards,
                        const std::vector<std::pair<std::string, char>> &operands,
                        const std::string &made) {
  if (guards.empty())
    return "  " + made + "\n";
  std::string body;
  std::size_t depth = 0;
  for (const llvm::Record *guard : guards) {
    std::vector<std::int64_t> given = guard->getValueAsListOfInts("operandGroups");
    if (given.empty() || llvm::any_of(given, [&](std::int64_t group) {
          return group < 0 || static_cast<std::uint64_t>(group) >= operands.size();
        }))
      llvm::PrintFatalError(op.getLoc(), op.getOperationName() +
                                             " has a guard whose operand groups are not among "
                                             "its record's");
    std::string check = "(MkOpName Dialect." + guard->getValueAsString("guardDialect").str() +
                        ' ' + literal(guard->getValueAsString("guardName")) + ")";
    // The cause typed, as the case at its position in the closed set of
    // causes the specification names, which the module's type check holds
    // to be one of the set's.
    std::string cause = "(caseAt " + guard->getValueAsString("causeModule").str() + "." +
                        guard->getValueAsString("causeSetName").str() + " " +
                        std::to_string(guard->getValueAsInt("causeNumber")) + ")";
    std::vector<std::pair<std::string, char>> others;
    for (std::int64_t group : llvm::ArrayRef(given).drop_front())
      others.push_back(operands[static_cast<std::size_t>(group)]);
    const auto &[checked, checkedArity] = operands[static_cast<std::size_t>(given.front())];
    std::string opening = checkedArity == '1'   ? "Checking " + check + ' ' + cause + ' ' + checked
                          : checkedArity == '?' ? "checkingEach " + check + ' ' + cause +
                                                      " (toList " + checked + ")"
                                                : "checkingEach " + check + ' ' + cause + ' ' +
                                                      checked;
    body += std::string(2 + 2 * depth, ' ') + opening + ' ' + listOf(others) + " (\\" + checked +
            " =>\n";
    ++depth;
  }
  return body + std::string(2 + 2 * depth, ' ') + "Unguarded (" + made + ")" +
         std::string(depth, ')') + "\n";
}

// The builder of an upstream op the frontend writes: one argument per
// inherent attribute, operand group, region and result group, and the op;
// with its guards, where the specification gives it any, so a partial op
// is never written without them.
void emitOp(Enums &enums, const Upstream &u, const Operator &op, const llvm::Record &admitted,
            llvm::raw_ostream &os) {
  if (op.getNumSuccessors() != 0)
    llvm::PrintFatalError(op.getLoc(), "the Idris side writes no op with successors");
  // getOperationName returns a std::string by value: keep it alive while the
  // mnemonic and the literal below read it (a StringRef bound to the
  // temporary would dangle).
  std::string operationName = op.getOperationName();
  StringRef mnemonic = StringRef(operationName).drop_front(op.getDialectName().size() + 1);
  std::string name = camel(mnemonic, Initial::Lowered) + "Op";

  std::vector<Parameter> implicits, explicits;
  std::vector<std::pair<std::string, char>> operands, results, regions;
  std::vector<std::pair<std::string, EntryPresence>> properties;
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
    if (&attribute->attr.getBaseAttr().getDef() == u.unitAttr) {
      implicits.push_back({param, "Bool", std::string("False")});
      properties.emplace_back(llvm::formatv("unitIf {0} {1}", key, param).str(),
                              EntryPresence::WhenGiven);
      continue;
    }
    Kind kind = attributeKind(enums, u, attribute->attr);
    if (attribute->attr.isOptional() || attribute->attr.hasDefaultValue()) {
      implicits.push_back({param, "Maybe " + parenthesized(kind.type()), std::string("Nothing")});
      properties.emplace_back(
          llvm::formatv("attrIf {0} {1} {2}", key, maker(kind.text), param).str(),
          EntryPresence::WhenGiven);
    } else {
      explicits.push_back({param, kind.type(), std::nullopt});
      properties.emplace_back(
          llvm::formatv("({0}, {1})", key, llvm::formatv(kind.text.c_str(), param).str()).str(),
          EntryPresence::Always);
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
  if (lists(op, u.operandSegments))
    properties.emplace_back(
        llvm::formatv("(\"operandSegmentSizes\", {0})", segments(operands)).str(),
        EntryPresence::Always);
  if (lists(op, u.resultSegments))
    properties.emplace_back(
        llvm::formatv("(\"resultSegmentSizes\", {0})", segments(results)).str(),
        EntryPresence::Always);

  std::string made = "MkOp (MkOpName " + dialectConstructor() + ' ' + literal(mnemonic) + ") " +
                     listOf(operands) + ' ' + dictionaryOf(properties) + ' ' + listOf(regions) +
                     " [] " + listOf(results);
  std::vector<const llvm::Record *> guards = admitted.getValueAsListOfDefs("guards");
  os << "||| `" << op.getOperationName() << "`" << summary(op.getSummary());
  os << "\nexport\n" << name << " : ";
  for (const Parameter &p : implicits)
    os << binder(p) << " -> ";
  for (const Parameter &p : explicits)
    os << binder(p) << " -> ";
  os << (guards.empty() ? "Op" : "Guarded") << "\n" << name;
  for (const Parameter &p : explicits)
    os << ' ' << p.name;
  os << " =\n" << guardedBody(op, guards, operands, made) << "\n";
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

// The next step of a reading that may leave its part out: `step` on what
// was written so far, or the reason it was left out, passed on unread.
template <class T, class Step>
std::invoke_result_t<Step, T> andThen(Written<T> read, Step step) {
  using Next = std::invoke_result_t<Step, T>;
  return idr::match(std::move(read), step, [](Omitted omitted) -> Next { return omitted; });
}

// When a parameter is written: always, or, for an optional one, when the
// Idris value has it (a Just, a list that is not empty). A parameter with a
// default other than nothing is always written: the parser reads the
// default written out as it reads any other value.
enum class Presence { Always, IfJust, IfNonEmpty };

// A parameter of a type or an attribute as a field of its constructor: its
// name, its Idris type, the expression that writes it from `{0}`, the sum
// whose defs can hold it, its kind's, and when it is written.
struct Field {
  std::string name;
  std::string type;
  std::string text;
  DefKind sum;
  Presence presence = Presence::Always;
};

// The Idris kind of each C++ value a parameter that is no array may be, by
// the C++ type ODS spells it with: a parameter given as a string is that
// spelling and nothing more, so it is the one fact to read, and each is
// spelled here once. A location the Idris side holds as its Location and
// writes as MLIR writes a location attribute, `loc(...)`, which the
// parameter's default parser reads. An attribute, and an array of them, is
// held only by the sum of attributes, whose `at` it is given as.
struct PlainRow {
  StringRef cpp;
  ItemOrList form;
  StringRef item;
  StringRef text;
  DefKind sum;
};

constexpr PlainRow plainRows[] = {
    {"::mlir::Type", ItemOrList::Item, "ty", "t {0}", DefKind::Type},
    {"::mlir::Attribute", ItemOrList::Item, "at", "a {0}", DefKind::Attribute},
    {"::mlir::FlatSymbolRefAttr", ItemOrList::Item, "String", "symbol {0}", DefKind::Type},
    {"::mlir::SymbolRefAttr", ItemOrList::Item, "SymbolRef", "symbolRef {0}", DefKind::Type},
    {"::mlir::StringAttr", ItemOrList::Item, "String", "utf8 {0}", DefKind::Type},
    {"::llvm::StringRef", ItemOrList::Item, "String", "utf8 {0}", DefKind::Type},
    {"::mlir::ArrayAttr", ItemOrList::List, "at", "array a {0}", DefKind::Attribute},
    {"::mlir::FunctionType", ItemOrList::Item, "Signature ty", "signature t {0}", DefKind::Type},
    {"::mlir::LocationAttr", ItemOrList::Item, "Location", "location {0}", DefKind::Type},
    {"unsigned", ItemOrList::Item, "Nat", "show {0}", DefKind::Type},
    {"uint32_t", ItemOrList::Item, "Nat", "show {0}", DefKind::Type},
    {"uint64_t", ItemOrList::Item, "Nat", "show {0}", DefKind::Type},
    {"int", ItemOrList::Item, "Integer", "show {0}", DefKind::Type},
    {"int32_t", ItemOrList::Item, "Integer", "show {0}", DefKind::Type},
    {"int64_t", ItemOrList::Item, "Integer", "show {0}", DefKind::Type},
    {"::llvm::APInt", ItemOrList::Item, "Integer", "show {0}", DefKind::Type},
};

// The Idris kind of a C++ value that is no array; nothing for one the Idris
// side has no value of, which the module then lists as not generated.
std::optional<Kind> plainKind(StringRef cpp) {
  const PlainRow *row =
      llvm::find_if(plainRows, [&](const PlainRow &each) { return each.cpp == cpp; });
  if (row == std::end(plainRows))
    return std::nullopt;
  return Kind{row->form, row->item.str(), row->text.str(), row->sum};
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
    kind = Kind{ItemOrList::List, kind->type(),
                "commaSeparated (map " + maker(kind->text) + " {0})", kind->sum};
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
  std::string lower = camel(name, Initial::Lowered);
  if (!info.isBitEnum()) {
    useEnum(enums, record).spellings = Spellings::ReadBySyntax;
    return Kind{ItemOrList::Item, name, lower + "Spelling {0}", DefKind::Type};
  }
  if (!noBits(info))
    return Omitted{llvm::formatv("its parameter `{0}` is a bit enum without a case of no bits",
                                 param.getName())
                       .str()};
  useEnum(enums, record).spellings = Spellings::ReadBySyntax;
  return Kind{ItemOrList::List, name, lower + "Spellings {0}", DefKind::Type};
}

// The field of a parameter of the kind `kind`, an optional one without a
// default of its own defaulting to nothing: a list is absent when it is
// empty, and one item when it is not given, as a Maybe.
Field fieldWith(const AttrOrTypeParameter &param, size_t index, const Kind &kind) {
  Field field{parameter(param.getName(), "parameter" + llvm::Twine(index)), kind.type(),
              kind.text, kind.sum};
  std::optional<StringRef> fallback = param.getDefaultValue();
  if (fallback && *fallback == (param.getCppStorageType() + "()").str()) {
    switch (kind.form) {
    case ItemOrList::List:
      field.presence = Presence::IfNonEmpty;
      break;
    case ItemOrList::Item:
      field.type = "Maybe " + parenthesized(field.type);
      field.presence = Presence::IfJust;
      break;
    }
  }
  return field;
}

// The field of a parameter, or why it is left out.
Written<Field> fieldOf(Enums &enums, const AttrOrTypeParameter &param, size_t index) {
  return idr::match(
      enumKind(enums, param),
      [&](const Kind &kind) -> Written<Field> { return fieldWith(param, index, kind); },
      [&](NotEnum) -> Written<Field> {
        std::optional<Kind> kind = valueKind(param.getCppType());
        if (!kind)
          return Omitted{llvm::formatv("its parameter `{0}` is the C++ `{1}`", param.getName(),
                                       param.getCppType())
                             .str()};
        return fieldWith(param, index, *kind);
      },
      [](const Omitted &omitted) -> Written<Field> { return omitted; });
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

// What a piece of a printer's text is: literal text, which the printer
// quotes and a run of which is one piece; or an expression of the text.
enum class PieceForm { Literal, Expression };

// One piece of a printer's text.
struct Piece {
  PieceForm form;
  std::string text;
};

void append(std::vector<Piece> &pieces, Piece piece) {
  if (piece.form == PieceForm::Literal && !pieces.empty() &&
      pieces.back().form == PieceForm::Literal)
    pieces.back().text += piece.text;
  else
    pieces.push_back(std::move(piece));
}

// The expression of pieces: the one piece, or their concatenation.
std::string expression(const std::vector<Piece> &pieces) {
  std::vector<std::string> texts;
  for (const Piece &piece : pieces)
    texts.push_back(piece.form == PieceForm::Literal ? literal(piece.text) : piece.text);
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
// flat. Each round writes an element or closes a group, and a syntax holds
// finitely many, so the rounds end with the syntax itself written whole.
Written<Pieces> piecesOf(const std::vector<Element> &elements,
                         const std::map<std::string, Field> &fields) {
  llvm::SmallVector<Writing, 2> open;
  open.push_back({elements, fields, {}, {}});
  while (open.size() > 1 || !open.front().rest.empty()) {
    Writing &top = open.back();
    if (top.rest.empty()) {
      Writing done = std::move(top);
      open.pop_back();
      Pieces &out = open.back().out;
      const Field &f = open.back().fields.at(done.anchor);
      llvm::append_range(out.written, done.out.written);
      switch (f.presence) {
      case Presence::IfJust:
        append(out.pieces,
               {PieceForm::Expression, llvm::formatv("maybe \"\" (\\{0} => {1}) {0}", f.name,
                                                     expression(done.out.pieces))
                                           .str()});
        break;
      case Presence::IfNonEmpty:
        append(out.pieces,
               {PieceForm::Expression, llvm::formatv("(if null {0} then \"\" else {1})", f.name,
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
      append(top.out.pieces, {PieceForm::Literal, spaced(e.text)});
      continue;
    }
    if (e.form == Element::Parameter) {
      auto field = top.fields.find(e.text);
      if (field == top.fields.end())
        return Omitted{llvm::formatv("its syntax names `{0}`, which is no parameter", e.text).str()};
      const Field &f = field->second;
      top.out.written.push_back(e.text);
      std::string text = llvm::formatv(f.text.c_str(), f.name).str();
      append(top.out.pieces, {PieceForm::Expression, f.presence == Presence::IfJust
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
  return std::move(open.front().out);
}

// A type or an attribute as the syntax module writes it: its constructor,
// with its documentation, and the clauses of its mnemonic and its printer.
struct Def {
  std::string constructor; // its declaration in the sum
  std::string mnemonicName;
  std::string mnemonic;    // the clause of the mnemonic, after its function
  std::string text;        // the clause of the printer, after its printers
};

// The fields of a type's or an attribute's parameters, in their order and
// by the parameter's name.
struct Fields {
  std::vector<Field> inOrder;
  std::map<std::string, Field> byName;
};

// The fields of a def's parameters; or why one is left out, and with it the
// def.
Written<Fields> fieldsOf(Enums &enums, const AttrOrTypeDef &def, DefKind kind) {
  Written<Fields> read = Fields{};
  for (const AttrOrTypeParameter &param : def.getParameters()) {
    // The type of an attribute's value is the op's that holds it.
    if (llvm::isa<mlir::tblgen::AttributeSelfTypeParameter>(param))
      continue;
    read = andThen(std::move(read), [&](Fields fields) {
      return andThen(fieldOf(enums, param, fields.inOrder.size()),
                     [&](Field field) -> Written<Fields> {
                       // A type holds types: the sum of types has no attribute to give.
                       if (kind == DefKind::Type && field.sum == DefKind::Attribute)
                         return Omitted{llvm::formatv(
                                            "its parameter `{0}` is an attribute, which no type holds",
                                            param.getName())
                                            .str()};
                       fields.byName[param.getName().str()] = field;
                       fields.inOrder.push_back(std::move(field));
                       return std::move(fields);
                     });
    });
  }
  return read;
}

// The elements of a def's declarative syntax, none for a def with neither
// parameters nor syntax; or why it is left out.
Written<std::vector<Element>> syntaxOf(const AttrOrTypeDef &def, const Fields &fields) {
  std::optional<StringRef> format = def.getAssemblyFormat();
  if (!format) {
    if (!fields.inOrder.empty())
      return Omitted{"it has parameters and no syntax"};
    return std::vector<Element>{};
  }
  return idr::match(
      elements(*format),
      [](std::vector<Element> syntax) -> Written<std::vector<Element>> { return syntax; },
      [&](const Omitted &omitted) -> Written<std::vector<Element>> {
        return Omitted{llvm::formatv("its syntax `{0}` has {1}", *format, omitted.why).str()};
      });
}

// The constructor of a type or an attribute and its text, from its fields
// and the pieces that write its syntax; or, when its syntax leaves out a
// parameter, why it is not generated.
Written<Def> defWith(const AttrOrTypeDef &def, DefKind kind, StringRef sum, StringRef mnemonic,
                     const std::vector<Field> &fields, const std::map<std::string, Field> &byName,
                     const Pieces &text) {
  std::string spelling = ((kind == DefKind::Type ? "!" : "#") + def.getDialect().getName() + "." + mnemonic).str();
  std::vector<Piece> pieces{{PieceForm::Literal, spelling}};
  for (const Piece &piece : text.pieces)
    append(pieces, piece);
  for (const auto &[name, field] : byName)
    if (!llvm::is_contained(text.written, name))
      return Omitted{llvm::formatv("its syntax leaves out `{0}`", name).str()};
  std::string constructor = constructorName(def.getCppClassName().str(),
                                            "the " + llvm::Twine(kind == DefKind::Type ? "type " : "attribute ") +
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
  decl << sum << (kind == DefKind::Type ? " ty" : " ty at") << "\n";
  if (!fields.empty()) {
    pattern = "(" + pattern + ")";
    wildcard = "(" + wildcard + ")";
  }
  out.mnemonic = llvm::formatv("{0} = {1}", wildcard, literal(mnemonic)).str();
  out.text = llvm::formatv("{0} = {1}", pattern, expression(pieces)).str();
  out.mnemonicName = mnemonic.str();
  return out;
}

// The constructor of a type or an attribute and its text; or, when it is not
// generated, why.
Written<Def> defOf(Enums &enums, const AttrOrTypeDef &def, DefKind kind, StringRef sum) {
  std::optional<StringRef> mnemonic = def.getMnemonic();
  if (!mnemonic)
    return Omitted{"it has no mnemonic"};
  if (def.hasCustomAssemblyFormat())
    return Omitted{"its syntax is C++"};
  return andThen(fieldsOf(enums, def, kind), [&](Fields read) {
    return andThen(syntaxOf(def, read), [&](std::vector<Element> syntax) {
      return andThen(piecesOf(syntax, read.byName), [&](Pieces text) -> Written<Def> {
        return defWith(def, kind, sum, *mnemonic, read.inOrder, read.byName, text);
      });
    });
  });
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
  // The modules the builders' guards import, each once: those they name
  // their causes from, then those `caseAt`, by which they write a cause,
  // needs, as each guard's record gives them.
  std::vector<std::string> guardImports;
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
  // The dialect is found by the name the command line gives, once; each
  // def and op after is the dialect's when its own dialect is that record.
  for (const llvm::Record *def : records.getAllDerivedDefinitions("Dialect"))
    if (def->getValueAsString("name") == dialectName)
      v.dialect.emplace(def);
  if (!v.dialect)
    llvm::PrintFatalError("no dialect " + dialectName + " in the records");
  StringRef module = lastName(moduleName);
  // Each sum by the ODS class its defs derive from, which TableGen finds
  // them by.
  static constexpr std::pair<StringRef, DefKind> sums[] = {{"TypeDef", DefKind::Type},
                                                           {"AttrDef", DefKind::Attribute}};
  for (const auto &[odsClass, kind] : sums)
    for (const llvm::Record *record : records.getAllDerivedDefinitionsIfDefined(odsClass)) {
      AttrOrTypeDef def(record);
      if (def.getDialect() != *v.dialect)
        continue;
      std::string what =
          (kind == DefKind::Type ? "type " : "attribute ") + def.getCppClassName().str();
      idr::match(
          defOf(v.enums, def, kind, (module + (kind == DefKind::Type ? "Type" : "Attr")).str()),
          [&](Def written) {
            (kind == DefKind::Type ? v.types : v.attrs).push_back(std::move(written));
          },
          [&](const Omitted &omitted) { v.omitted.push_back(what + ": " + omitted.why); });
    }
  llvm::raw_string_ostream opsOs(v.ops);
  Upstream u = upstream(records);
  for (const llvm::Record *admitted : admittedOps(records)) {
    Operator op(admitted->getValueAsDef("op"));
    if (op.getDialect() != *v.dialect || admitted->getValueAsInt("frontendWrites") == 0)
      continue;
    for (const llvm::Record *guard : admitted->getValueAsListOfDefs("guards")) {
      std::vector<StringRef> imports = guard->getValueAsListOfStrings("caseImports");
      imports.insert(imports.begin(), guard->getValueAsString("causeModule"));
      for (StringRef imported : imports)
        if (!llvm::is_contained(v.guardImports, imported))
          v.guardImports.push_back(imported.str());
    }
    emitOp(v.enums, u, op, *admitted, opsOs);
  }
  addCaseFields(v.enums, enumsOfCases(records));
  return v;
}

// A dialect's sum of types or of attributes, its mnemonics and its printer.
void emitSum(const std::vector<Def> &defs, DefKind kind, llvm::raw_ostream &os) {
  bool isType = kind == DefKind::Type;
  if (defs.empty())
    return;
  std::string what = isType ? "type" : "attribute";
  std::string sum = (lastName(moduleName) + (isType ? "Type" : "Attr")).str();
  std::string lower = camel(dialectName, Initial::Lowered) + (isType ? "Type" : "Attr");
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
  emitSum(v.types, DefKind::Type, typesOs);
  emitSum(v.attrs, DefKind::Attribute, attrsOs);

  writeLicense(os);
  os << "||| The " << dialectName << " dialect's syntax, as the Idris side writes it: the enums\n"
     << "||| its ops, types and attributes take, and its types and attributes, which\n"
     << "||| IdrisMLIR.MLIR's types and attributes hold. Generated by idris-mlir-tblgen\n"
     << "||| -gen-idris-syntax from the dialect's ODS; `make test-mlir-tools` generates\n"
     << "||| it again and fails on any difference. Do not edit.\n"
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

// The smart constructor of a dialect's attributes, where its syntax holds
// them in a sum: an attribute spelled as the syntax writes it, under the
// dialect, so no writer spells one by hand and none is spelled under
// another dialect. The sum is taken over what crosses as text: the one
// type an attribute that crosses as text holds, an integer type or index,
// and no attribute (`Void`), since none of the handoff's attributes is
// spelled inside another's text; so a spelled attribute cannot hold a type
// or an attribute its text could not write.
std::string spelledAttributes(const Vocabulary &v) {
  if (v.attrs.empty())
    return "";
  std::string lower = camel(dialectName, Initial::Lowered);
  std::string sum = (lastName(moduleName) + "Attr").str();
  return llvm::formatv("||| An attribute of the {0} dialect, spelled as its syntax writes it.\n"
                       "export\n"
                       "{1} : {2} IntegerOrIndex Void -> MlirAttr\n"
                       "{1} x = Spelled {3} (MkSpelling ({1}AttrText integerOrIndexText absurd x))\n\n",
                       dialectName.getValue(), lower, sum, dialectConstructor())
      .str();
}

bool emitIdrisDialect(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  if (syntaxModuleName.empty())
    llvm::PrintFatalError("-gen-idris-dialect needs -idris-syntax-module");
  Vocabulary v = read(records, "gen-idris-dialect");
  writeLicense(os);
  os << "||| The " << dialectName << " dialect's ops the frontend writes, as the Idris side\n"
     << "||| builds them: one builder per op the specification admits, and the\n"
     << "||| smart constructor of its attributes where its syntax holds them.\n"
     << "||| Generated by idris-mlir-tblgen -gen-idris-dialect from upstream's ODS;\n"
     << "||| `make test-mlir-tools` generates it again and fails on any difference.\n"
     << "||| Do not edit.\n"
     << "module " << moduleName
     << "\n\nimport IdrisMLIR.MLIR\nimport IdrisMLIR.Spec.Core.Dialect\nimport "
     << syntaxModuleName << "\n";
  // A guarded builder writes its cause as a case of the specification's
  // closed set of causes, by `caseAt`.
  for (const std::string &module : v.guardImports)
    os << "import " << module << "\n";
  os << "\nimport Data.List\n\n%default total\n\n";
  section(os, "Attributes", spelledAttributes(v));
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

// How an encoder takes a member read by one of the reader's own methods and
// writes it: its Idris type, and the expression of its parts from a value
// `{0}` of it, one Part (an item) or a List Part.
struct Atom {
  std::string type;
  std::string parts;
  ItemOrList form;
};

// The atoms, by the parser template each is read by. A dialect's attribute
// or type as a member (a builtin StringAttr in a NamedAttribute) is read as
// any attribute or type is. An attribute is its entry's number, and an
// optional one that or none. A type is the parts the
// writer gives for it: the number of its entry, or a field of what holds
// it.
std::optional<Atom> atomOf(StringRef parser) {
  static const std::pair<StringRef, Atom> atoms[] = {
      {"succeeded($_reader.readVarInt($_var))", {"Nat", "VarInt {0}", ItemOrList::Item}},
      {"succeeded($_reader.readSignedVarInt($_var))", {"Integer", "SignedVarInt {0}", ItemOrList::Item}},
      {"succeeded($_reader.readBool($_var))", {"Bool", "Flag {0}", ItemOrList::Item}},
      {"succeeded($_reader.readString($_var))", {"String", "Str {0}", ItemOrList::Item}},
      {"succeeded($_reader.readAttribute($_var))", {"AttrRef", "AttrAt {0}", ItemOrList::Item}},
      {"succeeded($_reader.readAttribute<$_resultType>($_var))", {"AttrRef", "AttrAt {0}", ItemOrList::Item}},
      {"succeeded($_reader.readOptionalAttribute($_var))", {"Maybe AttrRef", "OptionalAttrAt {0}", ItemOrList::Item}},
      {"succeeded($_reader.readType($_var))", {"List Part", "{0}", ItemOrList::List}},
      {"succeeded($_reader.readType<$_resultType>($_var))", {"List Part", "{0}", ItemOrList::List}}};
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

// The member `def` declares, bound by `name`, or why it cannot be read. The
// records left to read are a stack, the next last, each with the name its
// node is bound by and the name a refusal gives it (an array's element is
// reported by the array's); a composite's members are pushed last first, so
// they are read, and the first refusal met, in their order.
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

// How an argument writes an Idris type: as it is, for one word or a tuple;
// or in parentheses, for a type applied.
enum class TypeForm { Closed, Applied };

// The Idris type of a member, and how an argument writes it.
struct IdrisType {
  std::string text;
  TypeForm form;
};

// Each node's type is made from its members', which follow it: read
// backwards, a node finds them on the stack, its first member's on top. A
// composite of one member reads as that member.
IdrisType typeOf(const Member &member) {
  llvm::SmallVector<IdrisType> types;
  for (const MemberNode &node : llvm::reverse(member)) {
    switch (node.form) {
    case MemberNode::Atomic:
      types.push_back({node.atom.type, StringRef(node.atom.type).contains(' ') ? TypeForm::Applied
                                                                               : TypeForm::Closed});
      break;
    case MemberNode::Array: {
      IdrisType element = types.pop_back_val();
      types.push_back(
          {"List " + (element.form == TypeForm::Closed ? element.text : "(" + element.text + ")"),
           TypeForm::Applied});
      break;
    }
    case MemberNode::Composite: {
      if (node.arity == 1)
        break;
      std::vector<std::string> texts;
      for (unsigned i = 0; i < node.arity; ++i)
        texts.push_back(types.pop_back_val().text);
      types.push_back({"(" + llvm::join(texts, ", ") + ")", TypeForm::Closed});
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
  std::string name = camel(dslName, Initial::Lowered);
  while (isReserved(name) || isUsedInEncoders(name) || scope.count(name))
    name += '\'';
  scope.insert(name);
  return name;
}

// One piece of an encoder's parts: one Part (an item), or a List Part.
struct PartsPiece {
  ItemOrList form;
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
    if (piece.form == ItemOrList::Item) {
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
          Bound{names[i], {{node.atom.form, llvm::formatv(node.atom.parts.c_str(), names[i]).str()}}});
      break;
    case MemberNode::Array: {
      Bound element = bound.pop_back_val();
      const std::string &values = names[i];
      const std::string &pattern = element.pattern;
      Bound array{values, {{ItemOrList::Item, "VarInt (length " + values + ")"}}};
      if (element.pieces.size() == 1 && element.pieces.front().form == ItemOrList::List &&
          element.pieces.front().text == pattern) {
        array.pieces.push_back({ItemOrList::List, "concat " + values});
      } else if (element.pieces.size() == 1 && element.pieces.front().form == ItemOrList::Item) {
        StringRef text = element.pieces.front().text;
        bool eta = text.ends_with(" " + pattern) &&
                   !text.drop_back(pattern.size() + 1).contains(' ');
        array.pieces.push_back(
            {ItemOrList::List, eta ? ("map " + text.drop_back(pattern.size() + 1) + " " + values).str()
                        : "map (\\" + pattern + " => " + text.str() + ") " + values});
      } else {
        array.pieces.push_back({ItemOrList::List, "concatMap (\\" + pattern + " => " +
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
  Written<Members> read = Members{};
  for (unsigned i = 0, e = dag->getNumArgs(); i < e; ++i)
    read = andThen(std::move(read), [&](Members members) {
      return andThen(
          memberOf(llvm::cast<llvm::DefInit>(dag->getArg(i))->getDef(), dag->getArgNameStr(i)),
          [&](Member member) -> Written<Members> {
            members.push_back(std::move(member));
            return std::move(members);
          });
    });
  return read;
}

// A record's code: its place among `among`.
void emitCode(const llvm::Record *def, size_t code, StringRef among, llvm::raw_ostream &os) {
  std::string codeName = camel(def->getName(), Initial::Lowered) + "Code";
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
  std::string codeName = camel(def->getName(), Initial::Lowered) + "Code";
  idr::match(
      membersOf(def),
      [&](const Members &read) {
        emitEncoder(def, read, {{ItemOrList::Item, "VarInt " + codeName}}, {"its code"}, os);
      },
      [&](const Omitted &o) {
        omitted.push_back(llvm::formatv("{0} {1}: {2}", what, def->getName(), o.why).str());
      });
}

// A dialect's bytecode records of its types or of its attributes, in
// `elems` order.
using Elems = std::vector<const llvm::Record *>;

// The dialect's bytecode records the specification admits, each by
// upstream's own record (Generated/Idr<D>Entries.td's
// IdrAdmittedEntry records): the frontend writes the dialect's types and
// attributes by these alone, so the set is the specification's, the
// records upstream's, and a wrong name is TableGen's own error.
Elems admittedEntries(const llvm::RecordKeeper &records) {
  Elems entries;
  for (const llvm::Record *admitted : records.getAllDerivedDefinitionsIfDefined("IdrAdmittedEntry"))
    entries.push_back(admitted->getValueAsDef("entry"));
  return entries;
}

// The records of the dialect's types or attributes: the list of the
// DialectTypes or DialectAttributes of -idris-dialect, or nothing when the
// dialect's bytecode declares none. The DSL names a dialect as its C++
// class does (`Idr`, `Builtin`), ODS by its namespace (`idr`, `builtin`),
// so the two are compared without case.
std::optional<Elems> elemsOf(const llvm::RecordKeeper &records, StringRef kind) {
  std::optional<Elems> elems;
  for (const llvm::Record *def : records.getAllDerivedDefinitionsIfDefined(kind))
    if (def->getValueAsString("dialect").equals_insensitive(dialectName))
      elems = def->getValueAsListOfDefs("elems");
  return elems;
}

bool emitIdrisBytecode(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  if (dialectName.empty() || moduleName.empty())
    llvm::PrintFatalError("-gen-idris-bytecode needs -idris-dialect and -idris-module");
  // A dialect's bytecode may declare its types alone or its attributes
  // alone, the other then having no entries; declaring neither, it has no
  // bytecode records at all.
  std::optional<Elems> types = elemsOf(records, "DialectTypes");
  std::optional<Elems> attrs = elemsOf(records, "DialectAttributes");
  if (!types && !attrs)
    llvm::PrintFatalError("no bytecode records of the dialect " + dialectName);
  Elems typeElems = types.value_or(Elems{}), attrElems = attrs.value_or(Elems{});
  // An entry is printed where the specification admits it, at its code, its
  // place among all of the dialect's; an admitted record that is none of
  // them would be printed nowhere, so it is refused.
  Elems admitted = admittedEntries(records);
  for (const llvm::Record *entry : admitted)
    if (!llvm::is_contained(typeElems, entry) && !llvm::is_contained(attrElems, entry))
      llvm::PrintFatalError(entry, "the admitted record " + entry->getName() +
                                       " is no bytecode entry of the dialect " + dialectName);
  std::string typesText, attrsText;
  llvm::raw_string_ostream typesOs(typesText), attrsOs(attrsText);
  std::vector<std::string> omitted;
  for (auto [code, def] : llvm::enumerate(typeElems))
    if (llvm::is_contained(admitted, def))
      emitRecord(def, code, "type", typesOs, omitted);
  for (auto [code, def] : llvm::enumerate(attrElems))
    if (llvm::is_contained(admitted, def))
      emitRecord(def, code, "attribute", attrsOs, omitted);
  writeLicense(os);
  os << "||| The " << dialectName << " dialect's bytecode entries the frontend writes, as\n"
     << "||| the Idris side writes them: the code of each record the specification\n"
     << "||| admits, its place among all of the dialect's, and the parts of each whose\n"
     << "||| members' kinds are known, from its members in order, a type as the parts\n"
     << "||| the writer gives for it. Generated by\n"
     << "||| idris-mlir-tblgen -gen-idris-bytecode from the dialect's entries file and\n"
     << "||| the bytecode records it includes, from which mlir-tblgen -gen-bytecode\n"
     << "||| writes the C++ reader;\n"
     << "||| `make test-mlir-tools` generates it again and fails on any difference.\n"
     << "||| Do not edit.\n"
     << "module " << moduleName << "\n\nimport IdrisMLIR.MLIR.Parts\n\n%default total\n\n";
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

// The C++ class of every upstream op one admitted record file admits, by
// the alias the specification gives it: `::idr::admitted::SCF_YieldOp` is
// `::mlir::scf::YieldOp`. A record's name is unique only within its
// dialect's ODS, so each file is read by a run of its own and the alias,
// unique across every dialect, names the class. Stage legality, the
// e-graph's kinds and every per-op table name an upstream op through this,
// so its class is read from its def and the specification never restates
// one.
bool emitAdmittedClasses(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  os << "// The classes of the upstream ops the dialect admits, by their aliases:\n"
     << "// generated by idris-mlir-tblgen -gen-admitted-classes from upstream's\n"
     << "// ODS and the specification's admitted records. Do not edit.\n\n"
     << "namespace idr::admitted {\n";
  for (const llvm::Record *admitted : admittedOps(records)) {
    const llvm::Record *def = admitted->getValueAsDef("op");
    os << "using " << admitted->getValueAsString("alias") << " = "
       << Operator(def).getQualCppClassName() << ";\n";
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
