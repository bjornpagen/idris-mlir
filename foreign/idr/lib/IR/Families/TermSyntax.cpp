// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How an index term is written. A constructor term is written with its
// family and its label, read into its tag here, at the boundary. A sort is
// written beside the scopes that bind it (Scopes.cpp).

#include "idr/IR/Families/Terms.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ErrorHandling.h"

using namespace mlir;

namespace idr::families {

// A constructor names its family whatever its position: `#G @Cons(v0, v1)`,
// `self at 1 @Here`. So a term reads with no sort at hand, and a term of a
// group still being read keeps its label until the group's labels are all
// known.
//
// One pass over the nodes in preorder, with a count of the arguments each
// open constructor still owes: a term as deep as a long list is printed
// with no recursion on its depth.
void printTerm(AsmPrinter &printer, Term term, Attribute ownGroup) {
  ArrayRef<TermNode> nodes = term.nodes();
  SmallVector<uint32_t> owed;
  for (size_t at = 0; at < nodes.size(); ++at) {
    const TermNode &node = nodes[at];
    switch (node.kind) {
    case TermKind::Natural:
      printer << node.value;
      break;
    case TermKind::Level:
      printer << 'v' << node.value;
      break;
    case TermKind::Successor:
      // Its one child is the level it adds to, printed with it.
      printer << 'v' << nodes[++at].value << " + " << node.value;
      break;
    case TermKind::Sum: {
      // Its parts are its own nodes, each how often its level occurs, then
      // the level; then the count, where there is one.
      for (uint32_t part = 0; part < node.arity; ++part) {
        uint64_t times = nodes[at + 1 + 2 * part].value;
        if (part > 0)
          printer << " + ";
        printer << 'v' << nodes[at + 2 + 2 * part].value;
        if (times > 1)
          printer << " * " << times;
      }
      if (node.value > 0)
        printer << " + " << node.value;
      at += 2 * static_cast<size_t>(node.arity);
      break;
    }
    case TermKind::Multiple:
      llvm_unreachable("a part of a sum is printed with its sum");
    case TermKind::Literal:
      printer << "lit ";
      if (auto type = dyn_cast<TypeAttr>(node.payload)) {
        printer << "type ";
        printer.printType(type.getValue());
      } else {
        printer.printAttribute(node.payload);
      }
      break;
    case TermKind::Opaque:
      printer << '_';
      break;
    case TermKind::Constructor: {
      if (node.payload)
        printer.printAttribute(node.payload);
      else
        printer << "self";
      if (node.member != 0)
        printer << " at " << node.member;
      printer << ' ';
      auto group = cast<FamilyAttr>(node.payload ? node.payload : ownGroup);
      Tag tag{static_cast<uint32_t>(node.value)};
      printer.printSymbolName(group.ctor(node.member, tag).label);
      if (node.arity > 0) {
        printer << '(';
        owed.push_back(node.arity);
        continue;
      }
      break;
    }
    }
    // A whole term ended: its constructor's next argument follows it, or
    // the constructor closes, a whole term in its turn.
    while (!owed.empty()) {
      if (--owed.back() > 0) {
        printer << ", ";
        break;
      }
      printer << ')';
      owed.pop_back();
    }
  }
}

void printTerms(AsmPrinter &printer, ArrayRef<TermNode> nodes, size_t count, Attribute ownGroup) {
  llvm::interleaveComma(termsOf(nodes, count), printer,
                        [&](Term term) { printTerm(printer, term, ownGroup); });
}

ParseResult resolveLabel(AsmParser &parser, TermNode &node, FamilyAttr group, StringRef label,
                         SMLoc at) {
  if (node.member >= group.getMembers().size())
    return parser.emitError(at, "expects a member of the family, got member ") << node.member;
  std::optional<Tag> tag = group.tagOf(node.member, label);
  if (!tag)
    return parser.emitError(at, "expects a constructor of the family, got @") << label;
  CtorView ctor = group.ctor(node.member, *tag);
  if (node.arity != ctor.binders.size() + ctor.fields.size())
    return parser.emitError(at, "expects @")
           << label << " applied to its " << ctor.binders.size() + ctor.fields.size()
           << " binders and fields";
  node.value = static_cast<uint32_t>(*tag);
  return success();
}

namespace {

// A constructor whose arguments are being read: its node, its family (null
// for the group being declared, whose labels resolve once it is read), its
// label until then, and how many arguments it has read.
struct OpenConstructor {
  size_t node;
  Attribute group;
  StringAttr label;
  SMLoc at;
  SMLoc labelAt;
  uint32_t arity = 0;
};

// What reading a term's head leaves: a whole term, or a constructor whose
// arguments follow it.
enum class Head : uint8_t { Whole, Opened };

// A constructor whose arguments are all read: its label becomes its tag,
// or waits for its group to be read.
ParseResult closeConstructor(AsmParser &parser, SmallVectorImpl<TermNode> &out,
                             const OpenConstructor &con, SmallVectorImpl<PendingLabel> *pending) {
  out[con.node].arity = con.arity;
  if (!con.group) {
    if (!pending)
      return parser.emitError(con.at, "expects no constructor of a group being declared here");
    pending->push_back({&out, con.node, con.label.str(), con.labelAt});
    return success();
  }
  return resolveLabel(parser, out[con.node], cast<FamilyAttr>(con.group), con.label.getValue(),
                      con.labelAt);
}

// Reads one head into `out`: a whole term, but for a constructor followed
// by its arguments, which goes on `open` for the caller to read them.
FailureOr<Head> parseTermHead(AsmParser &parser, SmallVectorImpl<TermNode> &out,
                              SmallVectorImpl<PendingLabel> *pending,
                              SmallVectorImpl<OpenConstructor> &open) {
  TermWriter write(out);
  SMLoc at = parser.getCurrentLocation();
  if (succeeded(parser.parseOptionalKeyword("_"))) {
    write.opaque();
    return Head::Whole;
  }
  if (succeeded(parser.parseOptionalKeyword("lit"))) {
    if (succeeded(parser.parseOptionalKeyword("type"))) {
      Type type;
      if (parser.parseType(type))
        return failure();
      write.literal(TypeAttr::get(type));
      return Head::Whole;
    }
    Attribute constant;
    if (parser.parseAttribute(constant))
      return failure();
    write.literal(constant);
    return Head::Whole;
  }
  uint64_t number;
  OptionalParseResult natural = parser.parseOptionalInteger(number);
  if (natural.has_value()) {
    if (failed(*natural))
      return failure();
    write.natural(number);
    return Head::Whole;
  }
  // A constructor: its family, then its label in it.
  Attribute group;
  if (failed(parser.parseOptionalKeyword("self"))) {
    OptionalParseResult attr = parser.parseOptionalAttribute(group);
    if (!attr.has_value()) {
      // A level is `v<k>`, a bare keyword, perhaps `* m` times; then
      // perhaps `+` and another, or `+ n`, which ends the sum. What is read
      // is added up, so any order and any repetition is made one normal
      // form.
      NatSum sum;
      do {
        StringRef keyword;
        uint32_t level;
        if (parser.parseKeyword(&keyword) || !keyword.consume_front("v") ||
            keyword.getAsInteger(10, level))
          return parser.emitError(at, "expects an index term");
        uint64_t times = 1;
        if (succeeded(parser.parseOptionalStar()) && parser.parseInteger(times))
          return failure();
        sum.addLevel(level, times);
        if (failed(parser.parseOptionalPlus()))
          break;
        uint64_t count;
        OptionalParseResult counted = parser.parseOptionalInteger(count);
        if (counted.has_value()) {
          if (failed(*counted))
            return failure();
          sum.addCount(count);
          break;
        }
      } while (true);
      write.sum(sum);
      return Head::Whole;
    }
    if (failed(*attr))
      return failure();
    if (!isa<FamilyAttr>(group))
      return parser.emitError(at, "expects a family, got ") << group;
  }
  uint32_t member = 0;
  if (succeeded(parser.parseOptionalKeyword("at")) && parser.parseInteger(member))
    return failure();
  OpenConstructor con{out.size(), group, StringAttr(), at, parser.getCurrentLocation()};
  if (parser.parseSymbolName(con.label))
    return failure();
  write.constructor(group, member, 0, 0);
  if (succeeded(parser.parseOptionalLParen())) {
    open.push_back(con);
    return Head::Opened;
  }
  if (failed(closeConstructor(parser, out, con, pending)))
    return failure();
  return Head::Whole;
}

} // namespace

// The constructors whose arguments are being read are a stack, innermost
// last: a term as deep as a long list is read with no recursion on its
// depth. Each round reads a head from the input, so the rounds end with
// the input at the latest, and the term ends when no constructor is open.
ParseResult parseTerm(AsmParser &parser, SmallVectorImpl<TermNode> &out,
                      SmallVectorImpl<PendingLabel> *pending) {
  SmallVector<OpenConstructor> open;
  do {
    FailureOr<Head> head = parseTermHead(parser, out, pending, open);
    if (failed(head))
      return failure();
    if (*head == Head::Opened)
      continue;
    // A whole term was read: the innermost open constructor's next
    // argument, after which a comma reads another, or the constructor
    // closes, a whole term in its turn.
    while (!open.empty()) {
      OpenConstructor &con = open.back();
      ++con.arity;
      if (succeeded(parser.parseOptionalComma()))
        break;
      if (parser.parseRParen() || failed(closeConstructor(parser, out, con, pending)))
        return failure();
      open.pop_back();
    }
  } while (!open.empty());
  return success();
}

ParseResult parseTerms(AsmParser &parser, size_t count, SmallVectorImpl<TermNode> &out,
                       SmallVectorImpl<PendingLabel> *pending) {
  for (size_t index = 0; index < count; ++index) {
    if (index > 0 && parser.parseComma())
      return failure();
    if (parseTerm(parser, out, pending))
      return failure();
  }
  return success();
}

} // namespace idr::families
