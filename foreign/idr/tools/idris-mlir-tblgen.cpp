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
//   results, which for a partial op gives the op with the guards it takes,
//   stated over the builder's own arguments; its discardable attributes; and
//   its primitives, the ops Idris names, each a constructor the Idris side
//   builds it from (compiler/src/IdrisMLIR/Dialect/).
// - -gen-idris-bytecode, a dialect's bytecode entries for the Idris side,
//   from the records in upstream's DSL (mlir/IR/BytecodeBase.td) that
//   mlir-tblgen -gen-bytecode reads for the C++ reader: each record's code,
//   and the parts of each record whose members it knows, so that the writer
//   and the reader lay an entry out by one record; and the field codes and
//   the records of the module's table of data types
//   (compiler/src/IdrisMLIR/Encoding/).
// - -gen-idr-table-codes, the same field codes as the C++ reader's enum.
// - -gen-runtime-abi-decls and -gen-runtime-abi-defs, the runtime's C
//   functions idr-lower calls, an op's (Idr_Runtime) and the lowering's own
//   (Idr_RuntimeFunction): their C prototypes, which the runtime's header
//   includes, so that a definition that does not match its record fails to
//   compile; and the table the lowering and the folders read.
// - -gen-guards, the guards of each op with Idr_GuardedOp, as the C++
//   specialization ::idr::Guarded<Op> its folder and its speculation read.
// - -gen-big-to-word, the word op each big op names (Idr_WordOp).
// - -gen-rule-list, the rules a refusal of a program names, each with its
//   category, one per line, for the tests to read; -gen-rule-categories,
//   the same categories as the C++ side's `categoryOf`.
// - -gen-pass-roles and -gen-pass-stages, the role and the stages of each
//   pass (IdrPass), one pass per line, for the tests to read.
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
// syntax can say: its name alone. Its body is the module's, written once in
// the module's table of data types, whose records the syntax module holds
// and the bytecode writer writes.

#include "idr/Support/Worklist.h"

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
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/FormatVariadic.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/TableGen/Error.h"
#include "llvm/TableGen/Record.h"

#include <functional>
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
      "os",     "rs",        "rest"};
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
  idr::OnceWorklist<StringRef> work;
  for (const auto &[name, used] : enums)
    work.push(name);
  while (std::optional<StringRef> name = work.pop()) {
    Enum &taken = enums.find(name->str())->second;
    taken.caseFields = caseFieldsOf(EnumInfo(taken.def), owners);
    for (const CaseField &f : taken.caseFields)
      work.push(enums.try_emplace(enumName(EnumInfo(f.values)), Enum{f.values}).first->first);
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
// How the C ABI holds a value of each type
//===----------------------------------------------------------------------===//

// How a runtime function takes an operand of its op, or a parameter, and
// how it gives a result: two sets, so that neither position holds a case
// only the other has. The world is an operand's kind, the one kind with no C
// value, which no parameter declares; not returning is a result's kind.
// Pointer and Bool are the kinds of the functions the lowering calls by
// itself (IdrRuntime.td), which spell their own C types.
enum class OperandKind { World, Int32, Int64, Double, Signed, Unsigned, Str, Big, Buffer, Pointer, Bool };
enum class ResultKind { Void, NoReturn, Int32, Int64, Double, Wrapped, Order, Str, Big, Pointer, Bool };

// A kind as the generated table spells it, the C type an op's function
// declares a value of it as (a declarator with `{0}` where the name goes;
// the world's is empty, since no parameter declares it), and its line of
// documentation.
template <typename KindT>
struct KindRow {
  KindT kind;
  StringRef spelling;
  StringRef pattern;
  StringRef doc;
};

constexpr KindRow<OperandKind> operandRows[] = {
    {OperandKind::World, "World", "", "The world: no C value, so no parameter"},
    {OperandKind::Int32, "Int32", "int32_t {0}",
     "A 32-bit integer (int32_t, uint32_t, int): a character, a byte, a cell's info"},
    {OperandKind::Int64, "Int64", "int64_t {0}",
     "A 64-bit integer (int64_t, uint64_t, size_t): an Int, a count, a size, a handle, a clock"},
    {OperandKind::Double, "Double", "double {0}", "double"},
    {OperandKind::Signed, "Signed", "int64_t {0}",
     "int64_t: an integer of the op's width, sign-extended"},
    {OperandKind::Unsigned, "Unsigned", "uint64_t {0}",
     "uint64_t: an integer of the op's width, zero-extended"},
    {OperandKind::Str, "Str", "const idris_rt_str *{0}", "const idris_rt_str *"},
    {OperandKind::Big, "Big", "idris_rt_big {0}", "idris_rt_big"},
    {OperandKind::Buffer, "Buffer", "idris_rt_array *{0}", "idris_rt_array *: a buffer's cell"},
    {OperandKind::Pointer, "Pointer", "void *{0}",
     "A pointer the lowering made, as its function's C type spells it: a cell, its header, a "
     "string being built, a memref, bytes, a function"},
    {OperandKind::Bool, "Bool", "bool {0}", "bool, which the C ABI extends with zeros"},
};

constexpr KindRow<ResultKind> resultRows[] = {
    {ResultKind::Void, "Void", "void {0}", "No result"},
    {ResultKind::NoReturn, "NoReturn", "IDRIS_RT_NORETURN void {0}",
     "No result: the function does not return"},
    {ResultKind::Int32, "Int32", "int32_t {0}", "A 32-bit integer (int32_t, int)"},
    {ResultKind::Int64, "Int64", "int64_t {0}",
     "A 64-bit integer (int64_t): an Int, a count, a handle, a clock"},
    {ResultKind::Double, "Double", "double {0}", "double"},
    {ResultKind::Wrapped, "Wrapped", "int64_t {0}",
     "int64_t: a result modulo 2^64, which the op wraps to its width"},
    {ResultKind::Order, "Order", "int32_t {0}",
     "int32_t: negative, zero or positive, which the op compares with 0 by its predicate"},
    {ResultKind::Str, "Str", "const idris_rt_str *{0}", "const idris_rt_str *"},
    {ResultKind::Big, "Big", "idris_rt_big {0}", "idris_rt_big"},
    {ResultKind::Pointer, "Pointer", "void *{0}",
     "A pointer, as its function's C type spells it: a new cell, an array, a string being built"},
    {ResultKind::Bool, "Bool", "bool {0}", "bool, which the C ABI extends with zeros"},
};

// Each table lists its enum's cases once, in the enum's order, up to its
// last case, so that a kind's row is at the kind's value.
template <typename KindT, size_t N>
constexpr bool inKindOrder(const KindRow<KindT> (&rows)[N], KindT last) {
  for (size_t index = 0; index < N; ++index)
    if (rows[index].kind != static_cast<KindT>(index))
      return false;
  return N == static_cast<size_t>(last) + 1;
}
static_assert(inKindOrder(operandRows, OperandKind::Bool));
static_assert(inKindOrder(resultRows, ResultKind::Bool));

const KindRow<OperandKind> &rowOf(OperandKind kind) {
  return operandRows[static_cast<size_t>(kind)];
}
const KindRow<ResultKind> &rowOf(ResultKind kind) { return resultRows[static_cast<size_t>(kind)]; }

// The kind a record spells in `field` (an Idr_CType's `abiKind`), one of
// `rows`; any other spelling is a fault of the record.
template <typename KindT, size_t N>
KindT kindSpelled(const KindRow<KindT> (&rows)[N], const llvm::Record &record, StringRef field,
                  StringRef what) {
  StringRef spelling = record.getValueAsString(field);
  for (const KindRow<KindT> &row : rows)
    if (row.spelling == spelling)
      return row.kind;
  llvm::PrintFatalError(&record, "`" + spelling + "` is no " + what);
}

// The words a dialect's type constraint may say the C ABI holds a value of
// it as (Idr_AbiWord's `abiWord`): those no builtin type is by its width.
constexpr OperandKind constraintWords[] = {OperandKind::World,  OperandKind::Str,
                                           OperandKind::Big,    OperandKind::Buffer,
                                           OperandKind::Signed, OperandKind::Unsigned};

// Whether ODS says how the C ABI holds a value of the constraint `type`: a
// dialect's constraint the runtime takes mixes Idr_AbiWord in, where it is
// defined; a builtin type is its own word, by its width.
bool hasAbiWord(const llvm::Record &type) { return type.isSubClassOf("Idr_AbiWord"); }

// The word of a constraint with Idr_AbiWord; any other spelling is a fault
// of the constraint.
OperandKind abiWordOf(const llvm::Record &type) {
  StringRef spelling = type.getValueAsString("abiWord");
  for (OperandKind kind : constraintWords)
    if (rowOf(kind).spelling == spelling)
      return kind;
  llvm::PrintFatalError(&type, "its ABI word `" + spelling +
                                   "` is none of World, Str, Big, Buffer, Signed and Unsigned");
}

// Whether a value of `type` is the world, which is no C value.
bool isWorld(const llvm::Record &type) {
  return hasAbiWord(type) && abiWordOf(type) == OperandKind::World;
}

// Whether `type` is the builtin integer of `width` bits, or the double.
bool isInteger(const llvm::Record &type, int64_t width) {
  return type.isSubClassOf("I") && type.getValueAsInt("bitwidth") == width;
}
bool isDouble(const llvm::Record &type) {
  return type.isSubClassOf("F") && type.getValueAsInt("bitwidth") == 64;
}

// The types a constraint of several types allows; none for any other.
std::vector<const llvm::Record *> allowedTypes(const llvm::Record &type) {
  if (!type.getValue("allowedTypes"))
    return {};
  return type.getValueAsListOfDefs("allowedTypes");
}

// Whether the types a constraint allows are integers of several widths.
bool isAnyWidthInteger(const std::vector<const llvm::Record *> &types) {
  return types.size() > 1 &&
         llvm::all_of(types, [](const llvm::Record *t) { return t->isSubClassOf("I"); });
}

// Whether `type` allows only machine words, integers and floats, whose size
// in bytes is their type's.
bool isWord(const llvm::Record &type) {
  std::vector<const llvm::Record *> types = allowedTypes(type);
  return !types.empty() && llvm::all_of(types, [](const llvm::Record *t) {
    return t->isSubClassOf("I") || t->isSubClassOf("F");
  });
}

// The kinds a value of the ODS type constraint `type` may be passed as: its
// ABI word; a builtin integer of 32 or 64 bits or a double, by its width;
// or the kinds of the types it allows, which the caller refuses when they
// are more than one: one C function takes one kind. An integer of any width
// is passed as its constraint's word says, sign- or zero-extended, so one
// without a word is no operand a C function takes.
std::vector<OperandKind> operandKinds(const llvm::Record &type, const Operator &op,
                                      const llvm::Twine &what) {
  if (hasAbiWord(type))
    return {abiWordOf(type)};
  if (isInteger(type, 32))
    return {OperandKind::Int32};
  if (isInteger(type, 64))
    return {OperandKind::Int64};
  if (isDouble(type))
    return {OperandKind::Double};
  std::vector<const llvm::Record *> members = allowedTypes(type);
  if (isAnyWidthInteger(members))
    llvm::PrintFatalError(op.getLoc(), op.getOperationName() + "'s " + what +
                                           " is an integer of any width, and its constraint `" +
                                           type.getName() +
                                           "` names no extension (Idr_AbiWord's Signed or "
                                           "Unsigned)");
  if (members.empty())
    llvm::PrintFatalError(op.getLoc(), op.getOperationName() + "'s " + what + " is `" +
                                           type.getName() + "`, which no C function takes");
  std::vector<OperandKind> kinds;
  for (const llvm::Record *member : members)
    for (OperandKind kind : operandKinds(*member, op, what))
      if (!llvm::is_contained(kinds, kind))
        kinds.push_back(kind);
  return kinds;
}

// How a C function gives an op's one value, of the constraint `type`: an
// integer of any width as its 64 bits, which the op wraps to its width
// (Wrapped); an i1 as a three-way order, which the op's `predicate`
// compares with 0 (Order); a string, a big, an integer of 32 or 64 bits or
// a double as itself.
ResultKind resultKindOf(const llvm::Record &type, const Operator &op, const llvm::Twine &what,
                        bool hasPredicate) {
  std::string operation = op.getOperationName();
  if (hasAbiWord(type)) {
    OperandKind word = abiWordOf(type);
    if (word == OperandKind::Str)
      return ResultKind::Str;
    if (word == OperandKind::Big)
      return ResultKind::Big;
    llvm::PrintFatalError(op.getLoc(), operation + "'s " + what + " is a " +
                                           rowOf(word).spelling +
                                           ", which no C function gives");
  }
  if (isInteger(type, 32))
    return ResultKind::Int32;
  if (isInteger(type, 64))
    return ResultKind::Int64;
  if (isDouble(type))
    return ResultKind::Double;
  if (isInteger(type, 1)) {
    if (!hasPredicate)
      llvm::PrintFatalError(op.getLoc(), operation + " gives an i1 and has no `predicate` to "
                                                     "compare its C function's order by");
    return ResultKind::Order;
  }
  std::vector<const llvm::Record *> members = allowedTypes(type);
  if (isAnyWidthInteger(members))
    return ResultKind::Wrapped;
  if (members.empty())
    llvm::PrintFatalError(op.getLoc(), operation + "'s " + what + " is `" + type.getName() +
                                           "`, which no C function gives");
  std::vector<ResultKind> kinds;
  for (const llvm::Record *member : members) {
    ResultKind kind = resultKindOf(*member, op, what, hasPredicate);
    if (!llvm::is_contained(kinds, kind))
      kinds.push_back(kind);
  }
  if (kinds.size() != 1)
    llvm::PrintFatalError(op.getLoc(), operation + "'s " + what +
                                           " admits more than one kind, and one C function "
                                           "gives one");
  return kinds.front();
}

// How an op's C function gives its results, decided once, the boundary on
// ODS: the world is no C value, and of the other results an op has none,
// which is Void, or NoReturn for an op with Idr_NoReturn, or one. Two
// values, a value of an op that does not return and an i1 without a
// predicate are faults of the op.
ResultKind resultKind(const Operator &op) {
  std::string operation = op.getOperationName();
  std::vector<int> values;
  for (int index = 0, e = op.getNumResults(); index < e; ++index)
    if (!isWorld(op.getResult(index).constraint.getDef()))
      values.push_back(index);
  bool noreturn = op.getTrait("::idr::NoReturn") != nullptr;
  if (values.empty())
    return noreturn ? ResultKind::NoReturn : ResultKind::Void;
  if (values.size() > 1)
    llvm::PrintFatalError(op.getLoc(),
                          operation + " gives more than one value, and a C function gives one");
  if (noreturn)
    llvm::PrintFatalError(op.getLoc(), operation + " does not return, and gives a value");
  bool hasPredicate = llvm::any_of(
      op.getAttributes(), [](const NamedAttribute &attr) { return attr.name == "predicate"; });
  int value = values.front();
  return resultKindOf(op.getResult(value).constraint.getDef(), op,
                      "result `" + op.getResultName(value) + "`", hasPredicate);
}

//===----------------------------------------------------------------------===//
// Guards
//===----------------------------------------------------------------------===//

// A partial op is a guard and a total op, and its ODS says each guard
// (Idr_Guarded): the kind of check (a case of the enum CheckKind, as its
// record), the names of the op's values the guard op takes, in its order,
// the operand it guards first, and the cause its crash reports. The guard op
// of a kind is the one whose `checkKind` is that case's record, and what it
// takes beside the operand it guards is an operand of the partial op, as it
// is, or, for an i64 operand of the guard op, a count of bytes the partial
// op gives from one of its values: an i64 operand itself, the size of a
// word the op loads (its result) or stores (its operand), or the count the
// value's ABI word names (Idr_AbiWord's `abiCount`), a string's bytes or an
// array's length. The Idris side states each partial op's guards over its
// builder's own arguments; the C++ side reads them as ::idr::Guarded<Op>.

// The enum of the kinds of check, CheckKind in the dialect's namespace,
// whose cases the Idris side's Check lists.
const llvm::Record *checkKinds(const llvm::RecordKeeper &records, StringRef cppNamespace) {
  for (const llvm::Record *def : records.getAllDerivedDefinitionsIfDefined("EnumInfo")) {
    EnumInfo info(def);
    if (info.getEnumClassName() == "CheckKind" && info.getCppNamespace() == cppNamespace)
      return def;
  }
  llvm::PrintFatalError("a partial op names a guard, and " + cppNamespace +
                        " has no enum CheckKind");
}

// The kinds of check of a dialect, and the guard op of each, by the case's
// record, which a mark holds too: every case has one.
struct GuardOps {
  EnumInfo kinds;
  std::map<const llvm::Record *, const llvm::Record *> byKind;
};

GuardOps guardOpsOf(const llvm::RecordKeeper &records, StringRef cppNamespace) {
  GuardOps guards{EnumInfo(checkKinds(records, cppNamespace)), {}};
  for (const llvm::Record *def : records.getAllDerivedDefinitions("Op")) {
    const llvm::RecordVal *kind = def->getValue("checkKind");
    if (!kind || !llvm::isa<llvm::DefInit>(kind->getValue()))
      continue;
    const llvm::Record *checked = def->getValueAsDef("checkKind");
    if (!guards.byKind.emplace(checked, def).second)
      llvm::PrintFatalError(def, "two guard ops check " + checked->getName());
  }
  for (const EnumCase &c : guards.kinds.getAllCases())
    if (!guards.byKind.count(&c.getDef()))
      llvm::PrintFatalError(&guards.kinds.getDef(), "no guard op checks " + c.getSymbol());
  return guards;
}

// Whether a guard op's operand beside the one it guards is a count of
// bytes, an i64, which the partial op gives from one of its values, rather
// than an operand of the partial op as it is.
bool isCount(const NamedTypeConstraint &operand) {
  return isInteger(operand.constraint.getDef(), 64);
}

// What a guard op takes beside the operand it guards, as the partial op
// gives it, by its operand group or its result: an operand as it is; or a
// count of bytes, which is an i64 operand itself, the size of the word the
// op loads (its result) or stores (its operand), a string's bytes or an
// array's length.
struct AsIs {
  int group;
};
struct CountOf {
  int group;
};
struct WordLoaded {
  int result;
};
struct WordStored {
  int group;
};
struct BytesOf {
  int group;
};
struct LengthOf {
  int group;
};
using GuardArgument = std::variant<AsIs, CountOf, WordLoaded, WordStored, BytesOf, LengthOf>;

// One guard of a partial op, read once from its mark: the guard op, the
// Idris constructor of the case of CheckKind it checks, the operand group it
// guards (each value of a group that varies in length alike), what else the
// guard op takes, in its order, and the cause its crash reports.
struct Guard {
  const llvm::Record *guardOp;
  std::string check;
  int guarded;
  std::vector<GuardArgument> arguments;
  std::string cause;
};

// How a guard has a count of bytes from a value of the constraint `type`:
// as its ABI word's count says (Idr_AbiWord's `abiCount`, one of the
// Idr_AbiCount records), or none for a type without a word.
enum class ByteCount { None, Bytes, Length };

ByteCount byteCountOf(const llvm::Record &type) {
  if (!hasAbiWord(type))
    return ByteCount::None;
  const llvm::Record *count = type.getValueAsDef("abiCount");
  static const std::pair<StringRef, ByteCount> counts[] = {{"Idr_NoCount", ByteCount::None},
                                                           {"Idr_BytesOf", ByteCount::Bytes},
                                                           {"Idr_LengthOf", ByteCount::Length}};
  for (const auto &[name, byteCount] : counts)
    if (count->getName() == name)
      return byteCount;
  llvm::PrintFatalError(&type, "its count `" + count->getName() +
                                   "` is none of Idr_NoCount, Idr_BytesOf and Idr_LengthOf");
}

Guard guardOf(const Operator &op, const llvm::Record &mark, const GuardOps &guards) {
  std::string operationName = op.getOperationName();
  const llvm::Record *kind = mark.getValueAsDef("kind");
  auto found = guards.byKind.find(kind);
  // The mark's field takes any enum's case, and only CheckKind's have a
  // guard op.
  if (found == guards.byKind.end())
    llvm::PrintFatalError(&mark, operationName + " names the guard " + kind->getName() +
                                     ", which no guard op checks");
  Operator guard(found->second);
  std::vector<StringRef> names = mark.getValueAsListOfStrings("operands");
  if (names.size() != static_cast<size_t>(guard.getNumOperands()))
    llvm::PrintFatalError(&mark, llvm::formatv("{0}'s guard {1} names {2} values, and {3} takes "
                                               "{4}: the operand it guards, then each other",
                                               operationName, kind->getName(), names.size(),
                                               guard.getOperationName(), guard.getNumOperands())
                                     .str());
  auto group = [&](StringRef name) {
    std::optional<int> index = operandNamed(op, name);
    if (!index)
      llvm::PrintFatalError(&mark, operationName + " has no operand `" + name + "`");
    return *index;
  };
  auto single = [&](StringRef name) {
    int read = group(name);
    if (arity(op.getOperand(read)) != '1')
      llvm::PrintFatalError(&mark, operationName + "'s guard reads `" + name +
                                       "`, which is no single operand");
    return read;
  };
  auto count = [&](StringRef name) -> GuardArgument {
    if (std::optional<int> result = resultNamed(op, name)) {
      const NamedTypeConstraint &loaded = op.getResult(*result);
      if (arity(loaded) != '1' || !isWord(loaded.constraint.getDef()))
        llvm::PrintFatalError(&mark, operationName + "'s result `" + name + "` is no word");
      return WordLoaded{*result};
    }
    int read = single(name);
    const llvm::Record &type = op.getOperand(read).constraint.getDef();
    if (isWord(type))
      return WordStored{read};
    if (isInteger(type, 64))
      return CountOf{read};
    switch (byteCountOf(type)) {
    case ByteCount::Bytes:
      return BytesOf{read};
    case ByteCount::Length:
      return LengthOf{read};
    case ByteCount::None:
      break;
    }
    llvm::PrintFatalError(&mark, operationName + "'s `" + name + "` counts no bytes");
  };
  Guard parsed{found->second, caseName(guards.kinds, EnumCase(kind)), group(names.front()), {},
               mark.getValueAsString("cause").str()};
  for (int index = 1, e = guard.getNumOperands(); index < e; ++index) {
    StringRef name = names[static_cast<size_t>(index)];
    if (isCount(guard.getOperand(index)))
      parsed.arguments.push_back(count(name));
    else
      parsed.arguments.push_back(AsIs{single(name)});
  }
  return parsed;
}

// The guards of an op, one per mark in the order its ODS lists them: none
// for a total op.
std::vector<Guard> readGuards(const Operator &op, const GuardOps &guards) {
  std::vector<Guard> read;
  for (const llvm::Record *mark : traitsOfClass(op, "Idr_Guarded"))
    read.push_back(guardOf(op, *mark, guards));
  return read;
}

// The types the guards are stated in, before the ops whose builders give
// them, and the record of an op with its guards, which every partial op's
// builder and every primitive's op gives.
std::string guardTypes(const GuardOps &guards) {
  std::string out;
  llvm::raw_string_ostream os(out);
  os << "||| How a guard has a count of bytes it checks: an operand of the op, the\n"
     << "||| size of a word of the type given, the bytes of a string, or the length\n"
     << "||| of an array.\n"
     << "public export\ndata Count = CountOf Value | WordOf MlirType | BytesOf Value | "
        "LengthOf Value\n\n"
     << "||| What a guard checks of the operand it guards (CheckKind), with what else\n"
     << "||| its guard op takes: an operand of the op as it is, and each count.\n"
     << "public export\ndata Check = ";
  llvm::interleave(
      guards.kinds.getAllCases(),
      [&](const EnumCase &c) {
        os << caseName(guards.kinds, c);
        Operator guard(guards.byKind.at(&c.getDef()));
        for (int index = 1, e = guard.getNumOperands(); index < e; ++index)
          os << (isCount(guard.getOperand(index)) ? " Count" : " Value");
      },
      [&] { os << " | "; });
  os << "\n\n"
     << "||| A guard an op takes, an op `" << dialectName << ".check.*`: the position of\n"
     << "||| the operand it guards, whose value the guard's result stands for in the\n"
     << "||| op, what it checks, and the cause its crash reports.\n"
     << "public export\nrecord Guard where\n  constructor MkGuard\n  operand : Nat\n"
     << "  check : Check\n  cause : String\n\n"
     << "||| An op and the guards it takes, which are placed before it: what a\n"
     << "||| partial op's builder gives, so that no partial op is placed without its\n"
     << "||| guards.\n"
     << "public export\nrecord Guarded where\n  constructor MkGuarded\n  op : Op\n"
     << "  guards : List Guard\n\n";
  return out;
}

// What a builder or a clause binds of an op's values, which its guards'
// text reads: each operand group's name (a single operand's Value) and each
// result's (its MlirType), where it binds one, and where each group starts
// among the op's operands and how many values it has, as Nat expressions.
// A builder binds every one; a primitive's clause over a list of operands
// cannot bind those after a group that varies in length, nor a result it
// does not match.
struct Bound {
  std::vector<std::optional<std::string>> operands;
  std::vector<std::optional<std::string>> results;
  std::vector<std::string> starts;
  std::vector<std::string> lengths;
};

// The Idris expression of the guards of `op` over what `bound` binds, as
// an argument: a List Guard, one guard for a single operand and one for
// each value of a group that varies in length, each at its place from the
// group's start.
std::string guardsText(const Operator &op, const std::vector<Guard> &guards, const Bound &bound) {
  std::string operationName = op.getOperationName();
  auto named = [&](const std::optional<std::string> &name, StringRef what) {
    if (!name)
      llvm::PrintFatalError(op.getLoc(), operationName + "'s guard reads " + what +
                                             ", which a primitive's clause cannot name");
    return *name;
  };
  auto value = [&](int group) {
    return named(bound.operands[static_cast<size_t>(group)],
                 "`" + op.getOperand(group).name.str() + "`");
  };
  std::vector<std::pair<std::string, bool>> lists;
  for (const Guard &g : guards) {
    std::string check = g.check;
    for (const GuardArgument &argument : g.arguments)
      check += " " + std::visit(llvm::makeVisitor(
                                    [&](const AsIs &a) { return value(a.group); },
                                    [&](const CountOf &a) { return "(CountOf " + value(a.group) + ")"; },
                                    [&](const WordLoaded &a) {
                                      return "(WordOf " +
                                             named(bound.results[static_cast<size_t>(a.result)],
                                                   "its result") +
                                             ")";
                                    },
                                    [&](const WordStored &a) {
                                      return "(WordOf " + value(a.group) + ".type)";
                                    },
                                    [&](const BytesOf &a) { return "(BytesOf " + value(a.group) + ")"; },
                                    [&](const LengthOf &a) {
                                      return "(LengthOf " + value(a.group) + ")";
                                    }),
                                argument);
    if (!g.arguments.empty())
      check = "(" + check + ")";
    std::string cause = literal(g.cause);
    size_t guarded = static_cast<size_t>(g.guarded);
    if (arity(op.getOperand(g.guarded)) == '1') {
      lists.emplace_back(
          llvm::formatv("MkGuard {0} {1} {2}", bound.starts[guarded], check, cause).str(), true);
      continue;
    }
    // Each value of the group is guarded alike.
    lists.emplace_back(llvm::formatv("(map (\\v => MkGuard v {0} {1}) (iterateN {2} S {3}))",
                                     check, cause, bound.lengths[guarded], bound.starts[guarded])
                           .str(),
                       false);
  }
  return joined(lists);
}

// What a builder binds: every operand group and result, as its parameters.
Bound builderBound(const std::vector<std::pair<std::string, char>> &operands,
                   const std::vector<std::pair<std::string, char>> &results) {
  Bound bound;
  int singles = 0;
  std::vector<std::string> varying;
  for (const auto &[name, groupArity] : operands) {
    std::vector<std::string> terms = varying;
    if (singles != 0 || terms.empty())
      terms.push_back(std::to_string(singles));
    bound.starts.push_back(terms.size() == 1 ? terms.front() : "(" + llvm::join(terms, " + ") + ")");
    bound.operands.push_back(name);
    if (groupArity == '1') {
      ++singles;
      bound.lengths.push_back("1");
      continue;
    }
    std::string length =
        groupArity == '?' ? "(length (toList " + name + "))" : "(length " + name + ")";
    bound.lengths.push_back(length);
    varying.push_back(length);
  }
  for (const auto &result : results)
    bound.results.push_back(result.first);
  return bound;
}

//===----------------------------------------------------------------------===//
// Builders
//===----------------------------------------------------------------------===//

// The builder of an op: an Op, or, for a partial op, the op and its guards,
// stated over the builder's own arguments.
void emitOp(Enums &enums, const Operator &op, const std::vector<Guard> &guards,
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
  os << "||| `" << op.getOperationName() << "`" << summary(op.getSummary());
  os << "\nexport\n" << name << " : ";
  for (const Parameter &p : implicits)
    os << binder(p) << " -> ";
  for (const Parameter &p : explicits)
    os << binder(p) << " -> ";
  // A total op is its op; a partial op is its op and its guards: two kinds
  // of op, which the frontend places differently.
  os << (guards.empty() ? "Op" : "Guarded") << "\n" << name;
  for (const Parameter &p : explicits)
    os << ' ' << p.name;
  if (guards.empty())
    os << " =\n  " << made << "\n\n";
  else
    os << " =\n  MkGuarded (" << made << ")\n    "
       << guardsText(op, guards, builderBound(operands, results)) << "\n\n";
}

//===----------------------------------------------------------------------===//
// Primitives
//===----------------------------------------------------------------------===//

// An op Idris names as a primitive (Idr_Primitive): one constructor of the
// sum of its kind, named after its C++ class without `Op`. The Idris side
// builds the op from that constructor and its operands alone, so a
// primitive has no inherent attribute: no constructor could give one its
// value. A primitive with a body is a region primitive; any other is an IO
// primitive (Idr_PerformsIO), which takes the world and gives the next
// with what its IOResult says, or a pure one, whose operands are as many as
// its op's ODS declares.
enum class IOResult { WorldOnly, ValueThenWorld };

// A primitive's constructor and its op.
struct PrimitiveOp {
  std::string constructor;
  const llvm::Record *def;
};
struct PurePrimitive {
  PrimitiveOp op;
  int arity;
};
struct IOPrimitive {
  PrimitiveOp op;
  IOResult result;
};
struct RegionPrimitive {
  PrimitiveOp op;
  int64_t bodyArguments;
};
using Primitive = std::variant<PurePrimitive, IOPrimitive, RegionPrimitive>;

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

// What an IO primitive gives besides the world: none of its results, or
// one, its first, with the world after it.
IOResult ioResultOf(const Operator &op) {
  std::vector<int> values;
  for (int index = 0, e = op.getNumResults(); index < e; ++index)
    if (!isWorld(op.getResult(index).constraint.getDef()))
      values.push_back(index);
  if (values.empty())
    return IOResult::WorldOnly;
  if (values.size() > 1 || values.front() != 0)
    llvm::PrintFatalError(op.getLoc(), "the IO primitive " + op.getOperationName() +
                                           " gives more than one value besides the world, or "
                                           "its value after the world");
  return IOResult::ValueThenWorld;
}

// The primitive `op` is, which Idris names one.
Primitive primitiveOf(const Operator &op) {
  std::string operationName = op.getOperationName();
  if (std::optional<std::string> what = inherent(op))
    llvm::PrintFatalError(op.getLoc(), "the primitive " + operationName + " has " + *what +
                                           ", which no constructor of a primitive can give");
  StringRef constructor = op.getCppClassName();
  constructor.consume_back("Op");
  PrimitiveOp named{constructorName(constructor.str(), "the primitive " + operationName),
                    &op.getDef()};
  if (op.getNumRegions() != 0) {
    if (op.getNumRegions() != 1 || op.getRegion(0).isVariadic())
      llvm::PrintFatalError(op.getLoc(), "the region primitive " + operationName +
                                             " has more than its one body");
    // The count is the region constraint's (Idr_BodyRegion), which checks
    // it, as SizedRegion's `blocks` is the count of blocks it checks.
    const llvm::Record &body = op.getRegion(0).constraint.getDef();
    if (!body.getValue("arguments"))
      llvm::PrintFatalError(op.getLoc(), "the body of the region primitive " + operationName +
                                             " does not say how many arguments it takes");
    return RegionPrimitive{named, body.getValueAsInt("arguments")};
  }
  if (op.getTrait("::idr::PerformsIO"))
    return IOPrimitive{named, ioResultOf(op)};
  // A pure primitive's constructor fixes how many operands it takes
  // (primArity), so each group of them is one value.
  for (int index = 0, e = op.getNumOperands(); index < e; ++index)
    if (arity(op.getOperand(index)) != '1')
      llvm::PrintFatalError(op.getLoc(), "the pure primitive " + operationName +
                                             " has a group of operands that varies in length, "
                                             "and its constructor takes a fixed number");
  return PurePrimitive{named, op.getNumOperands()};
}

// The clause of `function` for a primitive: its op on the operands `os` and
// the result types `rs`, with the guards it takes, none for a total one.
// A partial primitive's clause names what its guards read by patterns: of
// `os`, a Vect of a pure primitive's arity, which matches whole, or a list
// of an IO primitive's operands, whose single operands before its one group
// that varies in length it names; and of `rs`, the list of results, where a
// guard reads a result's type. A list of another length matches the clause
// after it, which writes the op without guards: MLIR refuses an op of the
// wrong arity where it reads the module, so no op runs unguarded.
void emitClause(StringRef function, const PrimitiveOp &p, const std::vector<Guard> &guards,
                bool vect, llvm::raw_ostream &os) {
  Operator op(p.def);
  std::string head = (function + " " + p.constructor).str();
  std::string made = "MkOp " + literal(op.getOperationName()) + (vect ? " (toList os)" : " os") +
                     " [] [] [] rs";
  if (guards.empty()) {
    os << head << " os rs = MkGuarded (" << made << ") []\n";
    return;
  }
  int groups = op.getNumOperands();
  std::vector<std::string> names;
  std::optional<int> varying;
  for (int index = 0; index < groups; ++index) {
    names.push_back(parameter(op.getOperand(index).name, "operand" + llvm::Twine(index)));
    if (arity(op.getOperand(index)) == '1')
      continue;
    if (varying)
      llvm::PrintFatalError(op.getLoc(), op.getOperationName() +
                                             " has a guard and more than one group of operands "
                                             "that varies in length");
    varying = index;
  }
  Bound bound{std::vector<std::optional<std::string>>(static_cast<size_t>(groups)),
              std::vector<std::optional<std::string>>(static_cast<size_t>(op.getNumResults())),
              {},
              {}};
  std::string operandsPattern;
  bool refutable = false;
  if (!varying) {
    for (size_t index = 0; index < names.size(); ++index) {
      bound.operands[index] = names[index];
      bound.starts.push_back(std::to_string(index));
      bound.lengths.push_back("1");
    }
    operandsPattern = "os@[" + llvm::join(names, ", ") + "]";
    refutable = !vect;
  } else {
    // The singles before the group are its start; those after it, the end
    // of `rest`, which a pattern does not name.
    int start = *varying, after = groups - start - 1;
    std::string tail = start == 0 ? "os" : "rest";
    std::string length = after == 0
                             ? "(length " + tail + ")"
                             : llvm::formatv("(minus (length {0}) {1})", tail, after).str();
    for (int index = 0; index < groups; ++index) {
      if (index < start) {
        bound.operands[static_cast<size_t>(index)] = names[static_cast<size_t>(index)];
        bound.starts.push_back(std::to_string(index));
      } else if (index == start) {
        bound.starts.push_back(std::to_string(index));
      } else {
        bound.starts.push_back(llvm::formatv("({0} + {1})", index - 1, length).str());
      }
      bound.lengths.push_back(index == start ? length : "1");
    }
    std::vector<std::string> before(names.begin(), names.begin() + start);
    operandsPattern = start == 0 ? "os" : "os@(" + llvm::join(before, " :: ") + " :: rest)";
    refutable = start != 0;
  }
  std::string resultsPattern = "rs";
  bool readsResult = llvm::any_of(guards, [](const Guard &g) {
    return llvm::any_of(g.arguments, [](const GuardArgument &a) {
      return std::holds_alternative<WordLoaded>(a);
    });
  });
  if (readsResult) {
    std::vector<std::string> resultNames;
    for (int index = 0, e = op.getNumResults(); index < e; ++index) {
      resultNames.push_back(parameter(op.getResultName(index), "result" + llvm::Twine(index)));
      bound.results[static_cast<size_t>(index)] = resultNames.back();
    }
    resultsPattern = "rs@[" + llvm::join(resultNames, ", ") + "]";
    refutable = true;
  }
  os << head << " " << operandsPattern << " " << resultsPattern << " =\n  MkGuarded (" << made
     << ")\n    " << guardsText(op, guards, bound) << "\n";
  if (refutable)
    os << head << " os rs = MkGuarded (" << made << ") []\n";
}

// The primitives of the dialect's ops, in the order ODS declares them: the
// sums of their constructors, what the Idris side reads of each (a pure
// primitive's arity, what an IO primitive gives, a region primitive's
// body's arity), and the op of each with the guards it takes.
void emitPrimitives(std::vector<const llvm::Record *> defs,
                    const std::map<const llvm::Record *, std::vector<Guard>> &guards,
                    llvm::raw_ostream &os) {
  llvm::sort(defs, llvm::LessRecordByID());
  std::vector<PurePrimitive> pure;
  std::vector<IOPrimitive> io;
  std::vector<RegionPrimitive> regions;
  for (const llvm::Record *def : defs) {
    Operator op(def);
    if (!op.getTrait("::idr::Primitive"))
      continue;
    std::visit(llvm::makeVisitor([&](const PurePrimitive &p) { pure.push_back(p); },
                                 [&](const IOPrimitive &p) { io.push_back(p); },
                                 [&](const RegionPrimitive &p) { regions.push_back(p); }),
               primitiveOf(op));
  }
  auto constructors = [&](const auto &primitives) {
    for (auto [index, primitive] : llvm::enumerate(primitives))
      os << (index == 0 ? "  = " : "  | ") << primitive.op.constructor << "\n";
    os << "\n";
  };
  // The op's name of each primitive of a sum, so that the Idris side spells
  // no op's name itself.
  auto opNames = [&](StringRef function, StringRef sum, const auto &primitives) {
    os << "\n||| The name of the op of each " << sum << ".\n"
       << "public export\n" << function << " : " << sum << " -> String\n";
    for (const auto &primitive : primitives)
      os << function << " " << primitive.op.constructor << " = "
         << literal(Operator(primitive.op.def).getOperationName()) << "\n";
  };
  if (!pure.empty()) {
    os << "||| The dialect's pure primitives (ops with Idr_Primitive, no region and no\n"
       << "||| Idr_PerformsIO), one constructor each, named after the op's C++ class\n"
       << "||| without `Op`.\n"
       << "public export\ndata PurePrim\n";
    constructors(pure);
    os << "||| How many operands a pure primitive takes: its op's, one value each.\n"
       << "public export\nprimArity : PurePrim -> Nat\n";
    for (const PurePrimitive &primitive : pure)
      os << "primArity " << primitive.op.constructor << " = " << primitive.arity << "\n";
    opNames("pureName", "PurePrim", pure);
    os << "\n||| The op of a pure primitive on its operands, with its result types (a\n"
       << "||| primitive has no inherent attribute), and the guards it takes.\n"
       << "export\npureOp : (p : PurePrim) -> Vect (primArity p) Value -> List MlirType -> "
          "Guarded\n";
    for (const PurePrimitive &primitive : pure)
      emitClause("pureOp", primitive.op, guards.at(primitive.op.def), true, os);
    os << "\n";
  }
  if (!io.empty()) {
    os << "||| What an IO primitive gives besides the next world: nothing, or a value\n"
       << "||| first and the world after it.\n"
       << "public export\ndata IOResult = WorldOnly | ValueThenWorld\n\n"
       << "||| The dialect's IO primitives (ops with Idr_Primitive and Idr_PerformsIO),\n"
       << "||| one constructor each, named after the op's C++ class without `Op`. Such a\n"
       << "||| primitive takes the world as its last operand and gives the next as its\n"
       << "||| last result, except one without operands, which makes a world: it takes\n"
       << "||| none and gives one.\n"
       << "public export\ndata IOPrim\n";
    constructors(io);
    os << "||| What each IO primitive gives besides the world.\n"
       << "public export\nioResult : IOPrim -> IOResult\n";
    for (const IOPrimitive &primitive : io)
      os << "ioResult " << primitive.op.constructor << " = "
         << (primitive.result == IOResult::WorldOnly ? "WorldOnly" : "ValueThenWorld") << "\n";
    opNames("ioName", "IOPrim", io);
    os << "\n||| The op of an IO primitive on its operands, the world last, with its\n"
       << "||| result types and the guards it takes. A list of operands of a length the\n"
       << "||| op does not take gives the op without guards, which MLIR refuses where\n"
       << "||| it reads the module.\n"
       << "export\nioOp : IOPrim -> List Value -> List MlirType -> Guarded\n";
    for (const IOPrimitive &primitive : io)
      emitClause("ioOp", primitive.op, guards.at(primitive.op.def), false, os);
    os << "\n";
  }
  if (!regions.empty()) {
    os << "||| The dialect's region primitives.\npublic export\ndata IdrRegionPrim\n";
    constructors(regions);
    os << "||| The block arguments a region primitive's body takes.\n"
       << "public export\nregionArity : IdrRegionPrim -> Nat\n";
    for (const RegionPrimitive &primitive : regions)
      os << "regionArity " << primitive.op.constructor << " = " << primitive.bodyArguments
         << "\n";
    os << "\n||| The operation of a region primitive on operands and its body, with\n"
       << "||| its result types.\n"
       << "export\nregionOp : IdrRegionPrim -> List Value -> Region -> List MlirType -> Op\n";
    for (const RegionPrimitive &primitive : regions)
      os << "regionOp " << primitive.op.constructor << " operands body results = MkOp "
         << literal(Operator(primitive.op.def).getOperationName())
         << " operands [] [body] [] results\n";
    os << "\n";
  }
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
  // A location, which the Idris side holds as its Location and writes as
  // MLIR writes a location attribute, `loc(...)`, which the parameter's
  // default parser reads.
  if (cpp == "::mlir::LocationAttr")
    return Kind{"Location", "location {0}"};
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

// The Idris kind of a parameter the dialect defines once for every
// attribute that holds one, keyed on that definition: a constructor's tag
// (Idr_TagParameter), which the Idris side holds as the number it writes,
// and a list written in brackets (Idr_SquareListParameter).
std::optional<Kind> definedKind(const AttrOrTypeParameter &param) {
  const auto *def = llvm::dyn_cast<llvm::DefInit>(param.getDef());
  if (def && def->getDef()->getName() == "Idr_TagParameter")
    return Kind{"Nat", "show {0}"};
  // A list its parameter writes in brackets (Idr_SquareListParameter).
  if (def && def->getDef()->isSubClassOf("Idr_SquareListParameter"))
    if (std::optional<Kind> list = valueKind(param.getCppType()))
      return Kind{list->type, "fastConcat [\"[\", " + list->text + ", \"]\"]"};
  return std::nullopt;
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
            std::optional<Kind> kind = definedKind(param);
            if (!kind)
              kind = valueKind(param.getCppType());
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

// The elements of a type's or an attribute's declarative syntax up to its
// end, or in a group up to its `)`; left out, with the reason, for a
// directive the generator does not write (custom, struct, params) and for
// an else branch. Such a syntax has only `qualified`, and the C++ printer
// alone spaces it.
//
// Each element read consumes text, or the reading ends, so the loop ends
// with the text.
Written<std::vector<Element>> elements(StringRef &format, bool inGroup) {
  std::vector<Element> out;
  for (format = format.ltrim(); !format.empty(); format = format.ltrim()) {
    if (inGroup && format.consume_front(")"))
      return out;
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
      Written<std::vector<Element>> group = elements(format, true);
      if (const auto *omitted = std::get_if<Omitted>(&group))
        return *omitted;
      format = format.ltrim();
      if (!format.consume_front("?"))
        return Omitted{"an optional group with an else branch"};
      out.push_back({Element::Group, "", false, std::get<std::vector<Element>>(std::move(group))});
      continue;
    }
    StringRef word = format.take_while([](char c) { return llvm::isAlnum(c) || c == '-'; });
    return Omitted{word.empty() ? "an element the generator does not know"
                                : ("the directive `" + word + "`").str()};
  }
  if (!inGroup)
    return out;
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

// The pieces that write `elements`, each parameter by its field; left out,
// with the reason, for a parameter that is not one or a group without an
// anchor. Inside its group the anchor is the value the group is written
// for: the Just's, or the list that is not empty.
Written<Pieces> piecesOf(const std::vector<Element> &elements,
                         const std::map<std::string, Field> &fields) {
  Pieces out;
  for (const Element &e : elements) {
    if (e.form == Element::Literal) {
      append(out.pieces, {true, spaced(e.text)});
      continue;
    }
    if (e.form == Element::Parameter) {
      auto field = fields.find(e.text);
      if (field == fields.end())
        return Omitted{llvm::formatv("its syntax names `{0}`, which is no parameter", e.text).str()};
      const Field &f = field->second;
      out.written.push_back(e.text);
      std::string text = llvm::formatv(f.text.c_str(), f.name).str();
      append(out.pieces, {false, f.presence == Presence::IfJust
                                     ? llvm::formatv("maybe \"\" (\\{0} => {1}) {0}", f.name, text).str()
                                     : "(" + text + ")"});
      continue;
    }
    const Element *anchor = anchorOf(e);
    if (!anchor || !fields.count(anchor->text))
      return Omitted{"an optional group without the parameter that anchors it"};
    std::map<std::string, Field> inside = fields;
    const Field &f = fields.at(anchor->text);
    inside[anchor->text].presence = Presence::Always;
    Written<Pieces> read = piecesOf(e.group, inside);
    const Pieces *inner = std::get_if<Pieces>(&read);
    if (!inner)
      return std::get<Omitted>(read);
    llvm::append_range(out.written, inner->written);
    switch (f.presence) {
    case Presence::IfJust:
      append(out.pieces, {false, llvm::formatv("maybe \"\" (\\{0} => {1}) {0}", f.name,
                                               expression(inner->pieces))
                                     .str()});
      break;
    case Presence::IfNonEmpty:
      append(out.pieces, {false, llvm::formatv("(if null {0} then \"\" else {1})", f.name,
                                               expression(inner->pieces))
                                     .str()});
      break;
    case Presence::Always:
      for (const Piece &piece : inner->pieces)
        append(out.pieces, piece);
      break;
    }
  }
  return out;
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
    StringRef rest = *format;
    Written<std::vector<Element>> parsed = elements(rest, false);
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

// Whether `record` is an identified type: a TypeDef with MutableType, a
// name whose body is set once.
bool isIdentified(const llvm::Record &record) {
  return llvm::any_of(record.getValueAsListOfDefs("traits"),
                      [](const llvm::Record *trait) { return trait->getName() == "MutableType"; });
}

// An identified type, as the Idris side writes it: by its name alone,
// `<"name">`, which only a content key reads. Its body is written once, in
// the module's table of data types, and `preamble`, before the sum of types,
// holds the table's records: a body's kind (the enum its ODS names as
// `bodyKinds`), its constructors in tag order and its instance, and each
// constructor's name, fields and role (the enum its ODS names as
// `ctorRoles`). The frontend's table never holds a label, the one role with
// a payload (its function, and whether every force of it runs it), so a
// constructor of the table holds none. No type holds a body.
void identifiedOf(Enums &enums, const AttrOrTypeDef &def, StringRef sum, Def &out,
                  std::string &preamble) {
  const llvm::Record *kinds = def.getDef()->getValueAsDef("bodyKinds");
  useEnum(enums, kinds);
  std::string kind = enumName(EnumInfo(kinds));
  const llvm::Record *roles = def.getDef()->getValueAsDef("ctorRoles");
  useEnum(enums, roles);
  std::string role = enumName(EnumInfo(roles));
  std::string dialect = def.getDialect().getName().str();
  std::string module = lastName(moduleName).str();
  std::string ctor = module + "Ctor", body = module + "Sum";
  std::string mnemonic = def.getMnemonic() ? def.getMnemonic()->str() : std::string();
  std::string spelling = "!" + dialect + "." + mnemonic;
  llvm::raw_string_ostream pre(preamble);
  pre << "||| One constructor of a data type's body, as the module's table of data\n"
      << "||| types holds it: its name, its fields' types, and the part it plays in\n"
      << "||| its sum, never a label's, which the frontend's table does not hold.\n"
      << "public export\nrecord " << ctor << " ty where\n  constructor Mk" << ctor << "\n"
      << "  name : String\n  fields : List ty\n  role : " << role << "\n\n"
      << "||| A data type's body, as the module's table of data types holds it: what\n"
      << "||| sum it is, its constructors in tag order, and the Idris instance it is\n"
      << "||| of, its origin and arguments.\n"
      << "public export\nrecord " << body << " ty where\n  constructor Mk" << body << "\n"
      << "  kind : " << kind << "\n  ctors : List (" << ctor << " ty)\n"
      << "  instanceOf : Maybe (String, List String)\n\n";
  std::string constructor =
      constructorName(def.getCppClassName().str(), "the type " + def.getCppClassName());
  llvm::raw_string_ostream decl(out.constructor);
  decl << "  ||| `" << spelling << "`" << summary(def.getSummary())
       << "; written by its name, its body in the module's table of data types\n  "
       << constructor << " : (name : String) -> " << sum << " ty\n";
  out.mnemonicName = mnemonic;
  out.mnemonic = llvm::formatv("({0} _) = {1}", constructor, literal(mnemonic)).str();
  out.text = llvm::formatv("({0} name) = fastConcat [{1}, utf8 name, \">\"]", constructor,
                           literal(spelling + "<"))
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
// attributes, its ops' builders, primitives and the types its guards are
// stated in, and, found on the way, the enums all of them take.
struct Vocabulary {
  std::optional<mlir::tblgen::Dialect> dialect;
  std::vector<Def> types, attrs;
  std::vector<std::string> omitted;
  // What goes before the sum of types: the records of the table that holds
  // an identified type's body.
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
      std::string what = (isType ? "type " : "attribute ") + def.getCppClassName().str();
      // A def that says the Idris side has none of it (`bit idris = 0`, as
      // the specializer's keys, which no op holds) is the passes' alone.
      if (record->getValue("idris") && !record->getValueAsBit("idris")) {
        v.omitted.push_back(what + ": the passes' alone (idris = 0)");
        continue;
      }
      if (isType && isIdentified(*record)) {
        Def written;
        identifiedOf(v.enums, def, (module + "Type").str(), written, v.typesPreamble);
        v.types.push_back(std::move(written));
        continue;
      }
      std::visit(llvm::makeVisitor(
                     [&](Def written) { (isType ? v.types : v.attrs).push_back(std::move(written)); },
                     [&](const Omitted &omitted) { v.omitted.push_back(what + ": " + omitted.why); }),
                 defOf(v.enums, def, isType, (module + (isType ? "Type" : "Attr")).str()));
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
  // Each op's guards, read once from its marks, which its builder and, for
  // a primitive, its clause state; the guard ops the marks name are the
  // dialect's, which a dialect with a partial op or a primitive has, and
  // the types the guards are stated in are written before the builders.
  std::map<const llvm::Record *, std::vector<Guard>> guards;
  for (const llvm::Record *def : dialectOps)
    guards[def];
  bool guarded = llvm::any_of(dialectOps, [](const llvm::Record *def) {
    Operator op(def);
    return op.getTrait("::idr::Primitive") || !traitsOfClass(op, "Idr_Guarded").empty();
  });
  if (guarded) {
    GuardOps guardOps = guardOpsOf(records, v.dialect->getCppNamespace());
    for (const llvm::Record *def : dialectOps)
      guards[def] = readGuards(Operator(def), guardOps);
    v.guards = guardTypes(guardOps);
  }
  {
    llvm::raw_string_ostream opsOs(v.ops), primitivesOs(v.primitives);
    for (const auto &[name, def] : byName)
      emitOp(v.enums, Operator(def), guards.at(def), opsOs);
    emitPrimitives(dialectOps, guards, primitivesOs);
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
  typesOs << v.typesPreamble;
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
  std::string discardables;
  llvm::raw_string_ostream discardablesOs(discardables);
  emitDiscardable(*v.dialect, discardablesOs);

  writeLicense(os);
  os << "||| The " << dialectName << " dialect, as the Idris side writes it. Generated by\n"
     << "||| idris-mlir-tblgen -gen-idris-dialect from the dialect's ODS; `make build`\n"
     << "||| writes it (tools/dialects.sh). Do not edit.\n"
     << "module " << moduleName << "\n\nimport IdrisMLIR.MLIR\nimport " << syntaxModuleName
     << "\n\nimport Data.List\nimport Data.Vect\n\n%default total\n\n";
  section(os, "Discardable attributes", discardables);
  section(os, "Guards", v.guards);
  section(os, "Ops", v.ops);
  section(os, "Primitives", v.primitives);
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
// optional one that or none (Idr_OptionalAttr). A type is the parts the
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

// A member of a record: an atom; an array of its one element, written as
// its count and then each element; or a composite of its members, written
// one after the other.
struct Member {
  enum Form { Atomic, Array, Composite } form;
  Atom atom = {};
  std::vector<Member> members = {};
  std::vector<std::string> names = {}; // a composite's members' DSL names
};

// The member `def` declares, or why it cannot be read. An enum is a member
// that names its enum (Idr_Enum's `enumName`): the syntax module's, whose
// value of a case is what the reader reads. A record of the module's table
// of data types (Idr_TableRecord) is the parts its own encoder gives.
Written<Member> memberOf(const llvm::Record *def, StringRef name) {
  if (def->getValue("enumName")) {
    std::string e = def->getValueAsString("enumName").str();
    return Member{Member::Atomic, {e, "VarInt (" + camel(e, false) + "Value {0})", true}};
  }
  if (def->isSubClassOf("ArrayWithKnownSize"))
    return Omitted{
        llvm::formatv("its member `{0}` is an array whose count another member gives", name).str()};
  if (def->isSubClassOf("Array")) {
    Written<Member> element = memberOf(def->getValueAsDef("elemT"), name);
    if (const auto *omitted = std::get_if<Omitted>(&element))
      return *omitted;
    return Member{Member::Array, {}, {std::get<Member>(std::move(element))}};
  }
  if (def->isSubClassOf("Idr_TableRecord"))
    return Member{Member::Atomic, {"List Part", "{0}", false}};
  if (def->isSubClassOf("CompositeBytecode")) {
    const llvm::DagInit *dag = def->getValueAsDag("members");
    Member composite{Member::Composite};
    for (unsigned i = 0, e = dag->getNumArgs(); i < e; ++i) {
      StringRef inner = dag->getArgNameStr(i);
      Written<Member> member = memberOf(llvm::cast<llvm::DefInit>(dag->getArg(i))->getDef(), inner);
      if (const auto *omitted = std::get_if<Omitted>(&member))
        return *omitted;
      composite.members.push_back(std::get<Member>(std::move(member)));
      composite.names.push_back(inner.str());
    }
    return composite;
  }
  StringRef parser = def->getValueAsString("cParser");
  if (std::optional<Atom> atom = atomOf(parser))
    return Member{Member::Atomic, *atom};
  return Omitted{llvm::formatv("its member `{0}` is read by `{1}`", name, parser).str()};
}

// The Idris type of a member: one word or a tuple, which an argument writes
// as it is, or a type applied, which it parenthesizes.
struct IdrisType {
  std::string text;
  bool closed;
};

IdrisType typeOf(const Member &m) {
  switch (m.form) {
  case Member::Atomic:
    return {m.atom.type, !StringRef(m.atom.type).contains(' ')};
  case Member::Array: {
    IdrisType element = typeOf(m.members.front());
    return {"List " + (element.closed ? element.text : "(" + element.text + ")"), false};
  }
  case Member::Composite: {
    if (m.members.size() == 1)
      return typeOf(m.members.front());
    std::vector<std::string> types;
    for (const Member &member : m.members)
      types.push_back(typeOf(member).text);
    return {"(" + llvm::join(types, ", ") + ")", true};
  }
  }
  llvm_unreachable("a member is an atom, an array or a composite");
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

// Binds a member's value, under names fresh in `scope`: appends the pattern
// that binds it to `patterns`, and the pieces that write it to `pieces`. An
// array's elements are written by a function of one element, as the map
// of a constructor where one part writes an element.
void bindMember(const Member &m, StringRef name, std::set<std::string> &scope,
                std::vector<std::string> &patterns, std::vector<PartsPiece> &pieces) {
  switch (m.form) {
  case Member::Atomic: {
    std::string value = fresh(name, scope);
    patterns.push_back(value);
    pieces.push_back({m.atom.one, llvm::formatv(m.atom.parts.c_str(), value).str()});
    return;
  }
  case Member::Array: {
    std::string values = fresh(name, scope);
    patterns.push_back(values);
    pieces.push_back({true, "VarInt (length " + values + ")"});
    std::set<std::string> inner = scope;
    std::vector<std::string> elementPatterns;
    std::vector<PartsPiece> element;
    bindMember(m.members.front(), "x", inner, elementPatterns, element);
    std::string pattern = elementPatterns.front();
    if (element.size() == 1 && !element.front().one && element.front().text == pattern) {
      pieces.push_back({false, "concat " + values});
      return;
    }
    if (element.size() == 1 && element.front().one) {
      StringRef text = element.front().text;
      bool eta = text.ends_with(" " + pattern) &&
                 !text.drop_back(pattern.size() + 1).contains(' ');
      pieces.push_back({false, eta ? ("map " + text.drop_back(pattern.size() + 1) + " " + values).str()
                                   : "map (\\" + pattern + " => " + text.str() + ") " + values});
      return;
    }
    pieces.push_back({false, "concatMap (\\" + pattern + " => " + partsExpression(element) +
                                 ") " + values});
    return;
  }
  case Member::Composite: {
    if (m.members.size() == 1) {
      bindMember(m.members.front(), m.names.front(), scope, patterns, pieces);
      return;
    }
    std::vector<std::string> inner;
    for (auto [member, memberName] : llvm::zip(m.members, m.names))
      bindMember(member, memberName, scope, inner, pieces);
    patterns.push_back("(" + llvm::join(inner, ", ") + ")");
    return;
  }
  }
}

// A record's members, each as the reader reads it, and their DSL names.
struct Members {
  std::vector<Member> members;
  std::vector<std::string> names;
};

Written<Members> membersOf(const llvm::Record *def) {
  const llvm::DagInit *dag = def->getValueAsDag("members");
  Members read;
  for (unsigned i = 0, e = dag->getNumArgs(); i < e; ++i) {
    Written<Member> member =
        memberOf(llvm::cast<llvm::DefInit>(dag->getArg(i))->getDef(), dag->getArgNameStr(i));
    if (const auto *omitted = std::get_if<Omitted>(&member))
      return *omitted;
    read.members.push_back(std::get<Member>(std::move(member)));
    read.names.push_back(dag->getArgNameStr(i).str());
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
  for (auto [member, name] : llvm::zip(read.members, read.names)) {
    bindMember(member, name, scope, patterns, leading);
    described.push_back("`" + name + "`");
  }
  std::string encoder = "encode" + record;
  os << "||| The parts of `" << record << "`: " << llvm::join(described, ", ")
     << ".\nexport\n" << encoder << " : ";
  for (const Member &member : read.members)
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

// The field codes of the module's table of data types (IdrFieldCodes,
// IdrBytecode.td), by which a field of the table says how it is written,
// each its place in the list; none in the records of a dialect without the
// table.
std::vector<const llvm::Record *> fieldCodes(const llvm::RecordKeeper &records) {
  if (const llvm::Record *codes = records.getDef("IdrFieldCodes"))
    return codes->getValueAsListOfDefs("codes");
  return {};
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
  // The module's table of data types, which no entry of upstream's DSL
  // lays out: the codes of its fields, and its records, each no entry and
  // so of no code of its own.
  std::string tableText;
  llvm::raw_string_ostream tableOs(tableText);
  for (auto [code, def] : llvm::enumerate(fieldCodes(records)))
    emitCode(def, code, "the field codes of the table of data types", tableOs);
  std::vector<const llvm::Record *> tableRecords =
      records.getAllDerivedDefinitionsIfDefined("Idr_TableRecord");
  llvm::sort(tableRecords, llvm::LessRecordByID());
  for (const llvm::Record *def : tableRecords)
    std::visit(llvm::makeVisitor(
                   [&](const Members &read) { emitEncoder(def, read, {}, {}, tableOs); },
                   [&](const Omitted &o) {
                     omitted.push_back(
                         llvm::formatv("table record {0}: {1}", def->getName(), o.why).str());
                   }),
               membersOf(def));

  writeLicense(os);
  os << "||| The " << dialectName << " dialect's bytecode entries, as the Idris side writes\n"
     << "||| them: the code of each of its records, and the parts of each record whose\n"
     << "||| members' kinds are known, from its members in order, a type as the parts\n"
     << "||| the writer gives for it; and the field codes and the records of the\n"
     << "||| module's table of data types, where the dialect has one. Generated by\n"
     << "||| idris-mlir-tblgen -gen-idris-bytecode from the dialect's bytecode records,\n"
     << "||| from which mlir-tblgen -gen-bytecode writes the C++ reader; `make build`\n"
     << "||| writes it (tools/dialects.sh). Do not edit.\n"
     << "module " << moduleName << "\n\nimport IdrisMLIR.MLIR.Parts\nimport " << syntaxModuleName
     << "\n\n%default total\n\n";
  section(os, "Types", typesText);
  section(os, "Attributes", attrsText);
  section(os, "The table of data types", tableText);
  if (!omitted.empty()) {
    os << "-- Not generated:\n";
    for (const std::string &line : omitted)
      os << "-- " << line << "\n";
  }
  return false;
}

//===----------------------------------------------------------------------===//
// The runtime's C functions
//===----------------------------------------------------------------------===//

// Every C function of the runtime idr-lower calls is declared in ODS: an
// op's by its mark (Idr_Runtime), and each the lowering calls by itself
// (the cell, array, count, string-building, crash and start entries) by a
// record of IdrRuntime.td (Idr_RuntimeFunction). An op's function takes the
// op's operands in order and gives its result, each as the C ABI holds a
// value of its type: the world is no C value at all, a buffer its cell. An
// integer operand of any width is extended to 64 bits as its constraint's
// word says (Signed, Unsigned). An integer result of any width is the C
// function's 64 bits, which the op wraps to its width; a comparison's (an i1
// with a `predicate`) is the C function's three-way order, which the op
// compares with 0. The op's Idr_NoReturn says the function does not return.
// A record of IdrRuntime.td spells each C type and its kind itself.

// A parameter of a C function: its kind, its name, and its C type, a
// declarator with `{0}` where the name goes.
struct CParameter {
  OperandKind kind;
  std::string name;
  std::string pattern;
};

// A C function of the runtime: its symbol, its parameters, its result's
// kind and C type, and what idris_rt_ops.h says of it.
struct RuntimeFunction {
  std::string symbol;
  std::vector<CParameter> params;
  ResultKind result;
  std::string resultPattern;
  std::string comment;
};

// The function an op names, in the table under the op's C++ class.
struct OpFunction {
  RuntimeFunction function;
  std::string opClass;
};

// A function the lowering calls by itself, in the table as
// `helper::<name>`: its symbol without `idris_rt_`, camel-cased.
struct Helper {
  RuntimeFunction function;
  std::string name;
};

// The C function `op` names in its mark. An op gives the function nothing
// but its operands: an attribute but the `predicate` its order is compared
// by, or a property, is a fault of the op. An op has one function, so each
// operand admits one kind: a type, the op, fixes the function.
OpFunction opFunctionOf(const Operator &op, const llvm::Record &mark) {
  std::string operation = op.getOperationName();
  auto fail = [&](const llvm::Twine &why) { llvm::PrintFatalError(op.getLoc(), operation + why); };
  for (int index = 0, e = op.getNumArgs(); index < e; ++index) {
    mlir::tblgen::Argument arg = op.getArg(index);
    if (llvm::isa<NamedTypeConstraint *>(arg))
      continue;
    if (const auto *property = llvm::dyn_cast_if_present<NamedProperty *>(arg))
      fail(" has the property `" + property->name + "`, which its C function cannot take");
    const auto *attribute = llvm::cast<NamedAttribute *>(arg);
    if (attribute->attr.isDerivedAttr() || attribute->name == "predicate")
      continue;
    fail(" has the attribute `" + attribute->name + "`, which its C function cannot take");
  }
  std::vector<CParameter> params;
  for (int index = 0, e = op.getNumOperands(); index < e; ++index) {
    const NamedTypeConstraint &operand = op.getOperand(index);
    std::string name =
        operand.name.empty() ? "operand" + std::to_string(index) : operand.name.str();
    if (arity(operand) != '1')
      fail("'s operand `" + name + "` varies in length, and a C function's parameters do not");
    std::vector<OperandKind> kinds =
        operandKinds(operand.constraint.getDef(), op, "operand `" + name + "`");
    if (kinds.size() != 1)
      fail("'s operand `" + name + "` admits more than one kind, and one C function takes one");
    params.push_back({kinds.front(), name, rowOf(kinds.front()).pattern.str()});
  }
  ResultKind result = resultKind(op);
  std::string about = doc(op.getSummary());
  return {{mark.getValueAsString("symbol").str(), std::move(params), result,
           rowOf(result).pattern.str(), operation + (about.empty() ? "" : ": " + about)},
          op.getQualCppClassName()};
}

// A function the lowering calls by itself, from its record: each parameter
// and the result spelled by its C type (Idr_CType), whose kind is a case of
// its position's enum.
Helper helperOf(const llvm::Record &def) {
  StringRef symbol = def.getValueAsString("symbol");
  StringRef name = symbol;
  if (!name.consume_front("idris_rt_"))
    llvm::PrintFatalError(&def, symbol + " is no name of the runtime's, which begin `idris_rt_`");
  std::vector<CParameter> params;
  const llvm::DagInit *dag = def.getValueAsDag("params");
  for (unsigned i = 0, e = dag->getNumArgs(); i < e; ++i) {
    const auto *type = llvm::dyn_cast<llvm::DefInit>(dag->getArg(i));
    if (!type || !type->getDef()->isSubClassOf("Idr_CType"))
      llvm::PrintFatalError(&def, "its parameter `" + dag->getArgNameStr(i) + "` is no Idr_CType");
    params.push_back({kindSpelled(operandRows, *type->getDef(), "abiKind", "kind of a parameter"),
                      dag->getArgNameStr(i).str(),
                      type->getDef()->getValueAsString("cType").str()});
  }
  const llvm::Record &result = *def.getValueAsDef("result");
  return {{symbol.str(), std::move(params),
           kindSpelled(resultRows, result, "abiKind", "kind of a result"),
           result.getValueAsString("cType").str(), doc(def.getValueAsString("summary"))},
          camel(name, false)};
}

// Every C function idr-lower calls, read from IdrRuntime.td, which includes
// the ops: each op's and each of the lowering's own, ops by their class and
// the others by their name. A symbol two of them declare is a fault.
struct RuntimeAbi {
  std::vector<OpFunction> ops;
  std::vector<Helper> helpers;
};

RuntimeAbi runtimeAbi(const llvm::RecordKeeper &records) {
  RuntimeAbi abi;
  std::map<std::string, std::string> declaredBy;
  auto declare = [&](const RuntimeFunction &f, const std::string &by) {
    auto [known, inserted] = declaredBy.emplace(f.symbol, by);
    if (!inserted)
      llvm::PrintFatalError("both " + known->second + " and " + by + " declare " + f.symbol);
  };
  for (const llvm::Record *def : records.getAllDerivedDefinitions("Op")) {
    Operator op(def);
    if (const llvm::Record *mark = markOf(op, "Idr_Runtime")) {
      abi.ops.push_back(opFunctionOf(op, *mark));
      declare(abi.ops.back().function, op.getOperationName());
    }
  }
  for (const llvm::Record *def : records.getAllDerivedDefinitions("Idr_RuntimeFunction")) {
    abi.helpers.push_back(helperOf(*def));
    declare(abi.helpers.back().function, def->getName().str());
  }
  llvm::sort(abi.ops,
             [](const OpFunction &a, const OpFunction &b) { return a.opClass < b.opClass; });
  llvm::sort(abi.helpers, [](const Helper &a, const Helper &b) { return a.name < b.name; });
  return abi;
}

// The C declaration of a function: its result's C type around the symbol
// and the parameters, by one rule.
std::string cDeclaration(const RuntimeFunction &f) {
  std::vector<std::string> params;
  for (const CParameter &p : f.params)
    // The world, the one kind with no C value, has no parameter.
    if (p.kind != OperandKind::World)
      params.push_back(llvm::formatv(p.pattern.c_str(), p.name).str());
  // C reads an empty list as parameters not said, so none is `void`.
  std::string declarator =
      f.symbol + "(" + (params.empty() ? std::string("void") : llvm::join(params, ", ")) + ")";
  return llvm::formatv(f.resultPattern.c_str(), declarator).str() + ";";
}

bool emitRuntimeAbiDecls(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  RuntimeAbi abi = runtimeAbi(records);
  std::vector<const RuntimeFunction *> functions;
  for (const OpFunction &f : abi.ops)
    functions.push_back(&f.function);
  for (const Helper &h : abi.helpers)
    functions.push_back(&h.function);
  llvm::sort(functions, [](const RuntimeFunction *a, const RuntimeFunction *b) {
    return a->symbol < b->symbol;
  });
  os << "/* The runtime's functions idr-lower calls, the ops' (Idr_Runtime) and its\n"
     << " * own (IdrRuntime.td), as C declares them: generated by idris-mlir-tblgen\n"
     << " * -gen-runtime-abi-decls from the ODS, so that a definition that does not\n"
     << " * match its record fails to compile. idris_rt.h includes it, inside its C\n"
     << " * linkage and after the types it names; each function's meaning is its\n"
     << " * definition's in runtime/, documented beside it. Do not edit. */\n"
     << "#ifndef IDRIS_RT_OPS_H\n#define IDRIS_RT_OPS_H\n\n";
  for (const RuntimeFunction *f : functions)
    os << "/* " << f->comment << " */\n" << cDeclaration(*f) << "\n";
  os << "\n#endif /* IDRIS_RT_OPS_H */\n";
  return false;
}

// The kinds of a function's parameters, as the table's initializer.
std::string kindList(const RuntimeFunction &f) {
  std::vector<std::string> kinds;
  for (const CParameter &p : f.params)
    kinds.push_back("OperandKind::" + rowOf(p.kind).spelling.str());
  return llvm::join(kinds, ", ");
}

// A function's entry of the table, after its parameters' kinds: a C++
// array of none is no array, so a function without parameters has an empty
// span.
std::string entryOf(const RuntimeFunction &f, StringRef operands) {
  return llvm::formatv("{{\"{0}\", {1}, ResultKind::{2}}", f.symbol,
                       f.params.empty() ? StringRef("{}") : operands,
                       rowOf(f.result).spelling)
      .str();
}

bool emitRuntimeAbiDefs(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  RuntimeAbi abi = runtimeAbi(records);
  os << "// The runtime's functions idr-lower calls, as the lowering and the folders\n"
     << "// read them: generated by idris-mlir-tblgen -gen-runtime-abi-defs from the\n"
     << "// ODS. Each function is its symbol, how it takes each of its op's operands\n"
     << "// or each parameter, and how it gives its result; an op's is its Abi<Op>,\n"
     << "// with the C function itself, typed as idris_rt_ops.h declares it, and each\n"
     << "// function the lowering calls by itself is a constant of `helper`. Do not\n"
     << "// edit.\n\n"
     << "#ifndef IDR_IR_IDRRUNTIMEABI_INC\n#define IDR_IR_IDRRUNTIMEABI_INC\n\n"
     << "#include \"idr/IR/IdrDialect.h\"\n\n#include \"idris_rt.h\"\n\n"
     << "#include <span>\n#include <string_view>\n\n"
     << "namespace idr::runtime {\n\n";
  auto enumeration = [&](StringRef name, StringRef what, const auto &rows) {
    os << "// " << what << "\nenum class " << name << " : unsigned char {\n";
    for (const auto &row : rows)
      os << "  // " << row.doc << ".\n  " << row.spelling << ",\n";
    os << "};\n\n";
  };
  enumeration("OperandKind", "How a runtime function takes an operand of its op, or a parameter.",
              operandRows);
  enumeration("ResultKind", "How a runtime function gives its result.", resultRows);
  os << "// One C function of the runtime: its symbol, how it takes each operand of\n"
     << "// its op or each parameter, in order, and how it gives its result.\n"
     << "struct Function {\n  std::string_view symbol;\n  std::span<const OperandKind> operands;\n"
     << "  ResultKind result;\n};\n\n"
     << "// The C function an op calls, `entry`, and the function itself, typed as\n"
     << "// idris_rt_ops.h declares it. Not defined for an op that calls none.\n"
     << "template <typename OpT>\nstruct Abi;\n\n";
  for (const OpFunction &f : abi.ops) {
    os << "template <>\nstruct Abi<" << f.opClass << "> {\n";
    if (!f.function.params.empty())
      os << "  static constexpr OperandKind operands[] = {" << kindList(f.function) << "};\n";
    os << "  static constexpr Function entry" << entryOf(f.function, "operands") << ";\n"
       << "  static constexpr auto *function = &" << f.function.symbol << ";\n};\n\n";
  }
  os << "// The functions the lowering calls by itself (IdrRuntime.td).\nnamespace helper {\n\n";
  for (const Helper &h : abi.helpers) {
    std::string operands = h.name + "Operands";
    os << "// " << h.function.comment << ".\n";
    if (!h.function.params.empty())
      os << "inline constexpr OperandKind " << operands << "[] = {" << kindList(h.function)
         << "};\n";
    os << "inline constexpr Function " << h.name << entryOf(h.function, operands) << ";\n\n";
  }
  os << "} // namespace helper\n\n"
     << "} // namespace idr::runtime\n\n#endif // IDR_IR_IDRRUNTIMEABI_INC\n";
  return false;
}

//===----------------------------------------------------------------------===//
// The guards of the C++ side
//===----------------------------------------------------------------------===//

// The guards of each op that lists Idr_GuardedOp, as ::idr::Guarded<Op>:
// one Guard per mark, in ODS order, of the guard op and the op's operand
// indices it reads, the guarded one first, which the trait ::idr::GuardedOp
// expands at compile time for the op's folder and its speculation. The
// indices are the op's operands', so such an op has one value per operand
// group, and its guards read only its own operands as they are (an i64
// count included): a count of bytes had from a value, which the Idris side
// computes, is no operand index, and an op with one does not list the trait.
bool emitGuards(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  std::vector<std::pair<std::string, const llvm::Record *>> guarded;
  for (const llvm::Record *def : records.getAllDerivedDefinitions("Op")) {
    Operator op(def);
    if (op.getTrait("::idr::GuardedOp"))
      guarded.emplace_back(op.getQualCppClassName(), def);
  }
  llvm::sort(guarded, [](const auto &a, const auto &b) { return a.first < b.first; });
  os << "// The guards of each op that lists Idr_GuardedOp: one Guard per mark\n"
     << "// (Idr_Guarded), in ODS order, of the guard op and the op's operand indices\n"
     << "// it reads, the guarded one first. Generated by idris-mlir-tblgen\n"
     << "// -gen-guards from the ODS; IdrDialect.h includes it after the op classes,\n"
     << "// and the trait GuardedOp reads it. Do not edit.\n\n"
     << "#ifndef IDR_IR_IDRGUARDS_INC\n#define IDR_IR_IDRGUARDS_INC\n\n#include <tuple>\n\n"
     << "namespace idr {\n\n";
  std::optional<GuardOps> guardOps;
  for (const auto &[opClass, def] : guarded) {
    Operator op(def);
    std::string operationName = op.getOperationName();
    for (int index = 0, e = op.getNumOperands(); index < e; ++index)
      if (arity(op.getOperand(index)) != '1')
        llvm::PrintFatalError(op.getLoc(), operationName +
                                               " lists Idr_GuardedOp and has a group of operands "
                                               "that varies in length: a guard names operands "
                                               "by index");
    if (!guardOps)
      guardOps.emplace(guardOpsOf(records, op.getDialect().getCppNamespace()));
    std::vector<std::string> entries;
    for (const Guard &g : readGuards(op, *guardOps)) {
      std::vector<std::string> indices{std::to_string(g.guarded)};
      for (const GuardArgument &argument : g.arguments)
        indices.push_back(std::to_string(std::visit(
            llvm::makeVisitor([](const AsIs &a) { return a.group; },
                              [](const CountOf &a) { return a.group; },
                              [&](const auto &) -> int {
                                llvm::PrintFatalError(
                                    op.getLoc(), operationName +
                                                     " lists Idr_GuardedOp and has a guard on a "
                                                     "count of bytes had from a value, which is "
                                                     "no operand");
                              }),
            argument)));
      entries.push_back("Guard<" + Operator(g.guardOp).getQualCppClassName() + ", " +
                        llvm::join(indices, ", ") + ">");
    }
    os << "template <>\nstruct Guarded<" << opClass << "> {\n  using Guards = std::tuple<"
       << llvm::join(entries, ", ") << ">;\n};\n\n";
  }
  os << "} // namespace idr\n\n#endif // IDR_IR_IDRGUARDS_INC\n";
  return false;
}

//===----------------------------------------------------------------------===//
// The field codes of the table of data types, for the C++ reader
//===----------------------------------------------------------------------===//

// The codes by which a field of the module's table of data types says how
// it is written, each its place in IdrFieldCodes (IdrBytecode.td), as the
// enum lib/IR/Bytecode.cpp reads them by: the frontend's writer writes the
// same codes, from the same list.
bool emitIdrTableCodes(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  std::vector<const llvm::Record *> codes = fieldCodes(records);
  if (codes.empty())
    llvm::PrintFatalError("-gen-idr-table-codes reads IdrFieldCodes, which IdrBytecode.td "
                          "defines");
  std::vector<std::string> cases;
  for (auto [code, def] : llvm::enumerate(codes))
    cases.push_back(llvm::formatv("{0} = {1}", def->getValueAsString("name"), code).str());
  os << "// How a field of the module's table of data types is written, its code\n"
     << "// first: each code its place in IdrFieldCodes (IdrBytecode.td), from which\n"
     << "// the frontend's writer writes them too. Generated by idris-mlir-tblgen\n"
     << "// -gen-idr-table-codes. Do not edit.\n\n"
     << "#ifndef IDR_IR_IDRTABLE_H_INC\n#define IDR_IR_IDRTABLE_H_INC\n\n#include <cstdint>\n\n"
     << "namespace idr {\n\nenum class FieldCode : uint64_t { " << llvm::join(cases, ", ")
     << " };\n\n} // namespace idr\n\n#endif // IDR_IR_IDRTABLE_H_INC\n";
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

// The enum Rule, and the field in which each of its cases names its
// category, a case of another enum.
struct Rules {
  EnumInfo info;
  CaseField category;
};

Rules rulesOf(const llvm::RecordKeeper &records) {
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
  return {info, fields.front()};
}

// The rules of the enum Rule, one per line: the phrase a refusal names it
// by, `unsupported (<phrase>)`, then a tab and its category's phrase, as the
// tests read them.
bool emitRuleList(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  Rules rules = rulesOf(records);
  for (const EnumCase &c : rules.info.getAllCases())
    os << c.getStr() << "\t" << namedCase(c, rules.category.field).getStr() << "\n";
  return false;
}

// The category of each rule as the C++ side reads it, `categoryOf`: one
// case per case of Rule, from its category field, and no default, so that
// the switch names every rule. A case of Rule without the field is the
// generator's error, which caseFieldsOf reports.
bool emitRuleCategories(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  Rules rules = rulesOf(records);
  EnumInfo categories(rules.category.values);
  std::string rule = (rules.info.getCppNamespace() + "::" + rules.info.getEnumClassName()).str();
  std::string category =
      (categories.getCppNamespace() + "::" + categories.getEnumClassName()).str();
  // The function is the enum's, in its namespace.
  StringRef space = rules.info.getCppNamespace();
  space.consume_front("::");
  os << "// The category of each rule a refusal names: generated by idris-mlir-tblgen\n"
     << "// -gen-rule-categories from each case of the enum Rule, which names its\n"
     << "// category in its field `" << rules.category.field << "`. Do not edit.\n\n"
     << "#ifndef IDR_IR_IDRRULECATEGORIES_INC\n#define IDR_IR_IDRRULECATEGORIES_INC\n\n"
     << "namespace " << space << " {\n\n"
     << "// The kind of program a refusal by `rule` names.\n"
     << "inline constexpr " << category << " categoryOf(" << rule << " rule) {\n"
     << "  switch (rule) {\n";
  for (const EnumCase &c : rules.info.getAllCases())
    os << "  case " << rule << "::" << c.getSymbol() << ":\n    return " << category
       << "::" << namedCase(c, rules.category.field).getSymbol() << ";\n";
  os << "  }\n}\n\n} // namespace " << space << "\n\n#endif // IDR_IR_IDRRULECATEGORIES_INC\n";
  return false;
}

//===----------------------------------------------------------------------===//
// The role and the stages of each pass
//===----------------------------------------------------------------------===//

// Every pass of the records, one per line: what it states, a space and its
// argument, sorted by argument, as the tests read them. A pass is an
// IdrPass, whose role and stages are records Passes.td defines (IdrPassRole,
// IdrStage, each with its `name`): TableGen refuses any other, and a pass
// declared on upstream's Pass alone is a fact only this generator sees.
// Upstream's pass generators write a pass's C++, its base class among it
// (which checks and sets the stage), and its documentation, and none writes
// a field of a pass's record for a reader outside C++, so the role and the
// stages are written here, beside the rule list the tests read the same way.
void emitPassLines(const llvm::RecordKeeper &records, llvm::raw_ostream &os,
                   llvm::function_ref<std::string(const llvm::Record &)> stated) {
  std::vector<std::pair<std::string, std::string>> lines;
  for (const llvm::Record *def : records.getAllDerivedDefinitions("PassBase")) {
    if (!def->isSubClassOf("IdrPass"))
      llvm::PrintFatalError(def, llvm::Twine(def->getName()) +
                                     " is no IdrPass: every pass states its role and its stages");
    lines.emplace_back(def->getValueAsString("argument").str(), stated(*def));
  }
  llvm::sort(lines);
  for (const auto &[argument, line] : lines)
    os << line << " " << argument << "\n";
}

// The role of each pass.
bool emitPassRoles(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  emitPassLines(records, os, [](const llvm::Record &pass) {
    return pass.getValueAsDef("role")->getValueAsString("name").str();
  });
  return false;
}

// The stage each pass requires and the stage it leaves, `<requires> <sets>`,
// for the spec that checks the pipeline's order: each pass's `requires` is
// the stage the pass before it `sets`.
bool emitPassStages(const llvm::RecordKeeper &records, llvm::raw_ostream &os) {
  emitPassLines(records, os, [](const llvm::Record &pass) {
    return (pass.getValueAsDef("requires")->getValueAsString("name") + " " +
            pass.getValueAsDef("sets")->getValueAsString("name"))
        .str();
  });
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
const mlir::GenRegistration
    genIdrTableCodes("gen-idr-table-codes",
                     "The field codes of the table of data types, for the C++ reader",
                     emitIdrTableCodes);
const mlir::GenRegistration
    genRuntimeAbiDecls("gen-runtime-abi-decls",
                       "The C declarations of the runtime functions idr-lower calls",
                       emitRuntimeAbiDecls);
const mlir::GenRegistration genRuntimeAbiDefs("gen-runtime-abi-defs",
                                              "The table of the runtime functions idr-lower calls",
                                              emitRuntimeAbiDefs);
const mlir::GenRegistration genGuards("gen-guards", "The guards of each op with Idr_GuardedOp",
                                      emitGuards);
const mlir::GenRegistration genBigToWord("gen-big-to-word", "The word op each big op names",
                                         emitBigToWord);
const mlir::GenRegistration genRuleList("gen-rule-list",
                                        "The rules a refusal names, with their categories",
                                        emitRuleList);
const mlir::GenRegistration genRuleCategories("gen-rule-categories",
                                              "The category of each rule, for the C++ side",
                                              emitRuleCategories);
const mlir::GenRegistration genPassRoles("gen-pass-roles", "The role of each pass, for the tests",
                                         emitPassRoles);
const mlir::GenRegistration genPassStages("gen-pass-stages",
                                          "The stages of each pass, for the tests",
                                          emitPassStages);

} // namespace

int main(int argc, char **argv) { return mlir::MlirTblgenMain(argc, argv); }
