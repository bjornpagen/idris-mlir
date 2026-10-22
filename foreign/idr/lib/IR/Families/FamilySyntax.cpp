// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How #idr.family is written: a group of one member as the member itself,
// several in brackets. A member's levels are positions, printed `v0`,
// `v1`, so a declaration prints with no context; the names Idris gave them
// are its location's, for readers.
//
//   #idr.family<"Vect" loc("Data/Vect.idr":17:1) [nat] {
//     @Nil where 0 ()
//     @Cons <nat> where v0 + 1 (i64, !idr.self[v0])
//   }>
//   #idr.family<"Stream" memo [] { @next fn @step (i64) by_name } forced (i64)>
//   #idr.family<[... , "Frames" frames { @base where 0 (...) @push where 1 (...) }]>
//
// A constructor of the group being read, named in an equation by its
// label, is resolved once every member is read, since a label may name one
// read after it.

#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Match.h"

#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/STLExtras.h"

#include <deque>

using namespace mlir;
using namespace idr;
using namespace idr::families;

namespace {

void printSorts(AsmPrinter &printer, ArrayRef<Sort> sorts) {
  llvm::interleaveComma(sorts, printer, [&](const Sort &sort) { printSort(printer, sort); });
}

void printFields(AsmPrinter &printer, ArrayRef<Type> fields) {
  printer << '(';
  llvm::interleaveComma(fields, printer, [&](Type field) { printer.printType(field); });
  printer << ')';
}

// `@label <sorts> where terms`: what every constructor and label begins
// with.
void printHead(AsmPrinter &printer, StringAttr label, ArrayRef<Sort> binders,
               ArrayRef<TermNode> equation, size_t indices, Attribute group) {
  printer << "\n    ";
  printer.printSymbolName(label.getValue());
  if (!binders.empty()) {
    printer << " <";
    printSorts(printer, binders);
    printer << '>';
  }
  if (indices > 0) {
    printer << " where ";
    printTerms(printer, equation, indices, group);
  }
  printer << ' ';
}

void printMember(AsmPrinter &printer, const Member &member, Attribute group) {
  match(
      member,
      [&](const DataMember &m) {
        printer.printString(m.label.getValue());
        if (m.promise == Promise::InPlace)
          printer << " in_place";
        if (m.loc) {
          printer << " loc(";
          printer.printAttribute(m.loc);
          printer << ')';
        }
        printer << " [";
        printSorts(printer, m.indices);
        printer << "] {";
        for (const CtorDecl &c : m.ctors) {
          printHead(printer, c.label, c.binders, c.equation, m.indices.size(), group);
          printFields(printer, c.fields);
        }
        printer << "\n  }";
      },
      [&](const ClosuresMember &m) {
        printer.printString(m.label.getValue());
        printer << " closures [";
        printSorts(printer, m.indices);
        printer << "] {";
        for (const LabelDecl &l : m.labels) {
          printHead(printer, l.label, l.binders, l.equation, m.indices.size(), group);
          printer << "fn " << l.fn << ' ';
          printFields(printer, l.fields);
        }
        printer << "\n  }";
      },
      [&](const MemoMember &m) {
        printer.printString(m.label.getValue());
        printer << " memo [";
        printSorts(printer, m.indices);
        printer << "] {";
        for (const MemoLabelDecl &l : m.labels) {
          printHead(printer, l.label.label, l.label.binders, l.label.equation, m.indices.size(),
                    group);
          printer << "fn " << l.label.fn << ' ';
          printFields(printer, l.label.fields);
          if (l.mode == Mode::ByName)
            printer << " by_name";
        }
        printer << "\n  } forced (";
        printer.printType(m.forced);
        printer << ')';
      },
      [&](const FramesMember &m) {
        printer.printString(m.label.getValue());
        printer << " frames {";
        for (const CtorDecl &c : m.ctors) {
          printHead(printer, c.label, c.binders, c.equation, 1, group);
          printFields(printer, c.fields);
        }
        printer << "\n  }";
      });
}

// What a declaration's arrays are read into until the attribute is made,
// each kept in place (a deque) while the members view them.
struct Read {
  std::deque<SmallVector<Sort>> sorts;
  std::deque<SmallVector<TermNode>> terms;
  std::deque<SmallVector<Type>> types;
  std::deque<SmallVector<CtorDecl>> ctors;
  std::deque<SmallVector<LabelDecl>> labels;
  std::deque<SmallVector<MemoLabelDecl>> memoLabels;
  SmallVector<PendingLabel> pending;
};

ParseResult parseSortList(AsmParser &parser, AsmParser::Delimiter delimiter,
                          SmallVector<Sort> &out) {
  return parser.parseCommaSeparatedList(delimiter,
                                        [&]() { return parseSort(parser, out.emplace_back()); });
}

ParseResult parseFields(AsmParser &parser, SmallVector<Type> &out) {
  return parser.parseCommaSeparatedList(AsmParser::Delimiter::Paren,
                                        [&]() { return parser.parseType(out.emplace_back()); });
}

// `@label <sorts> where terms`, the binders and the equation into `read`.
ParseResult parseHead(AsmParser &parser, Read &read, size_t indices, StringAttr &label,
                      ArrayRef<Sort> &binders, ArrayRef<TermNode> &equation) {
  if (parser.parseSymbolName(label))
    return failure();
  SmallVector<Sort> &sorts = read.sorts.emplace_back();
  if (succeeded(parser.parseOptionalLess()) &&
      (parseSortList(parser, AsmParser::Delimiter::None, sorts) || parser.parseGreater()))
    return failure();
  binders = sorts;
  SmallVector<TermNode> &terms = read.terms.emplace_back();
  if (indices > 0 &&
      (parser.parseKeyword("where") || parseTerms(parser, indices, terms, &read.pending)))
    return failure();
  equation = terms;
  return success();
}

ParseResult parseLabelDecl(AsmParser &parser, Read &read, size_t indices, LabelDecl &label) {
  SmallVector<Type> &captures = read.types.emplace_back();
  if (parseHead(parser, read, indices, label.label, label.binders, label.equation) ||
      parser.parseKeyword("fn") || parser.parseAttribute(label.fn) ||
      parseFields(parser, captures))
    return failure();
  label.fields = captures;
  return success();
}

FailureOr<Member> parseMember(AsmParser &parser, Read &read) {
  std::string name;
  if (parser.parseString(&name))
    return failure();
  StringAttr label = parser.getBuilder().getStringAttr(name);
  if (succeeded(parser.parseOptionalKeyword("closures"))) {
    ClosuresMember m{label, {}, {}};
    SmallVector<Sort> &indices = read.sorts.emplace_back();
    SmallVector<LabelDecl> &labels = read.labels.emplace_back();
    if (parseSortList(parser, AsmParser::Delimiter::Square, indices) || parser.parseLBrace())
      return failure();
    m.indices = indices;
    while (failed(parser.parseOptionalRBrace()))
      if (parseLabelDecl(parser, read, indices.size(), labels.emplace_back()))
        return failure();
    m.labels = labels;
    return Member(m);
  }
  if (succeeded(parser.parseOptionalKeyword("memo"))) {
    MemoMember m{label, {}, {}, Type()};
    SmallVector<Sort> &indices = read.sorts.emplace_back();
    SmallVector<MemoLabelDecl> &labels = read.memoLabels.emplace_back();
    if (parseSortList(parser, AsmParser::Delimiter::Square, indices) || parser.parseLBrace())
      return failure();
    m.indices = indices;
    while (failed(parser.parseOptionalRBrace())) {
      MemoLabelDecl &l = labels.emplace_back();
      if (parseLabelDecl(parser, read, indices.size(), l.label))
        return failure();
      l.mode = succeeded(parser.parseOptionalKeyword("by_name")) ? Mode::ByName : Mode::Memoized;
    }
    m.labels = labels;
    if (parser.parseKeyword("forced") || parser.parseLParen() || parser.parseType(m.forced) ||
        parser.parseRParen())
      return failure();
    return Member(m);
  }
  if (succeeded(parser.parseOptionalKeyword("frames"))) {
    FramesMember m{label, {}};
    SmallVector<CtorDecl> &ctors = read.ctors.emplace_back();
    if (parser.parseLBrace())
      return failure();
    while (failed(parser.parseOptionalRBrace())) {
      CtorDecl &c = ctors.emplace_back();
      SmallVector<Type> &fields = read.types.emplace_back();
      if (parseHead(parser, read, 1, c.label, c.binders, c.equation) ||
          parseFields(parser, fields))
        return failure();
      c.fields = fields;
    }
    m.ctors = ctors;
    return Member(m);
  }
  DataMember m{label, LocationAttr(), Promise::None, {}, {}};
  if (succeeded(parser.parseOptionalKeyword("in_place")))
    m.promise = Promise::InPlace;
  if (succeeded(parser.parseOptionalKeyword("loc")) &&
      (parser.parseLParen() || parser.parseAttribute(m.loc) || parser.parseRParen()))
    return failure();
  SmallVector<Sort> &indices = read.sorts.emplace_back();
  SmallVector<CtorDecl> &ctors = read.ctors.emplace_back();
  if (parseSortList(parser, AsmParser::Delimiter::Square, indices) || parser.parseLBrace())
    return failure();
  m.indices = indices;
  while (failed(parser.parseOptionalRBrace())) {
    CtorDecl &c = ctors.emplace_back();
    SmallVector<Type> &fields = read.types.emplace_back();
    if (parseHead(parser, read, indices.size(), c.label, c.binders, c.equation) ||
        parseFields(parser, fields))
      return failure();
    c.fields = fields;
  }
  m.ctors = ctors;
  return Member(m);
}

} // namespace

void FamilyAttr::print(AsmPrinter &printer) const {
  ArrayRef<Member> members = getMembers();
  printer << '<';
  if (members.size() == 1) {
    printMember(printer, members.front(), *this);
  } else {
    printer << '[';
    llvm::interleaveComma(members, printer,
                          [&](const Member &member) { printMember(printer, member, *this); });
    printer << ']';
  }
  printer << '>';
}

Attribute FamilyAttr::parse(AsmParser &parser, Type) {
  SMLoc loc = parser.getCurrentLocation();
  Read read;
  SmallVector<Member> members;
  if (parser.parseLess())
    return {};
  auto one = [&]() -> ParseResult {
    FailureOr<Member> member = parseMember(parser, read);
    if (failed(member))
      return failure();
    members.push_back(*member);
    return success();
  };
  if (succeeded(parser.parseOptionalLSquare())) {
    if (parser.parseCommaSeparatedList(one) || parser.parseRSquare())
      return {};
    if (members.size() < 2) {
      parser.emitError(loc, "expects a group of one member written without brackets");
      return {};
    }
  } else if (one()) {
    return {};
  }
  if (parser.parseGreater())
    return {};
  // The labels of the group's own constructors are known once every member
  // is read: a first group, its own constructors' terms still untagged,
  // gives them, and the group is made checked once they are tagged.
  if (!read.pending.empty()) {
    auto labels = get(parser.getContext(), ArrayRef<Member>(members));
    for (PendingLabel &label : read.pending)
      if (resolveLabel(parser, (*label.nodes)[label.node], labels, label.label, label.at))
        return {};
  }
  return getChecked([&] { return parser.emitError(loc); }, parser.getContext(),
                    ArrayRef<Member>(members));
}

// A group's alias in the IR: its first member's label, the letters and
// digits of it, which MLIR suffixes where two groups would share one.
std::string FamilyAttr::aliasName() const {
  std::string alias;
  for (char c : label(0).getValue())
    if (llvm::isAlnum(c) || c == '_')
      alias.push_back(c);
  if (alias.empty() || llvm::isDigit(alias.front()))
    alias.insert(alias.begin(), 'F');
  return alias;
}
