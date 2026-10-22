// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How a data type is written: `!idr.data<#Vect[v0]>`, `!idr.data<#Tree at
// 1 [v0]>`, refined `!idr.data<#List @Cons>`, `!idr.data<#T {@A, @B}>`,
// `!idr.data<#Ex @MkEx<v3>>`: the group by its alias, the member after `at`
// when it is not the first, the indices when there are any, the
// refinement. A label is read into its tag here, at the boundary, and what
// is read is made in normal form, so a type has one spelling.

#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;
using namespace idr::families;

void DataType::print(AsmPrinter &printer) const {
  FamilyAttr group = getGroup();
  auto member = static_cast<uint32_t>(getMember());
  printer << '<';
  printer.printAttribute(group);
  if (member != 0)
    printer << " at " << member;
  size_t count = group.indices(member).size();
  if (count > 0) {
    printer << '[';
    printTerms(printer, getIndices(), count, group);
    printer << ']';
  }
  SmallVector<Tag> tags;
  if (getRefinement())
    tags.assign(possibleTags().begin(), possibleTags().end());
  if (getRefinement() && tags.empty()) {
    printer << " {}";
  } else if (tags.size() == 1) {
    printer << ' ';
    printer.printSymbolName(ctor(tags.front()).label);
    if (!getBinders().empty()) {
      printer << '<';
      printTerms(printer, getBinders(), ctor(tags.front()).binders.size(), group);
      printer << '>';
    }
  } else if (!tags.empty()) {
    printer << " {";
    llvm::interleaveComma(tags, printer,
                          [&](Tag tag) { printer.printSymbolName(ctor(tag).label); });
    printer << '}';
  }
  printer << '>';
}

Type DataType::parse(AsmParser &parser) {
  SMLoc loc = parser.getCurrentLocation();
  FamilyAttr group;
  uint32_t member = 0;
  if (parser.parseLess() || parser.parseAttribute(group))
    return {};
  if (succeeded(parser.parseOptionalKeyword("at")) && parser.parseInteger(member))
    return {};
  if (member >= group.getMembers().size()) {
    parser.emitError(loc, "expects a member of the family");
    return {};
  }
  SmallVector<TermNode> indices;
  size_t count = group.indices(member).size();
  if (count > 0 && (parser.parseLSquare() || parseTerms(parser, count, indices, nullptr) ||
                    parser.parseRSquare()))
    return {};
  auto labelTag = [&](Tag &tag) -> ParseResult {
    StringAttr label;
    SMLoc at = parser.getCurrentLocation();
    if (parser.parseSymbolName(label))
      return failure();
    std::optional<Tag> found = group.tagOf(member, label.getValue());
    if (!found)
      return parser.emitError(at, "expects a constructor of the family, got @") << label.getValue();
    tag = *found;
    return success();
  };
  // No refinement, a set of constructors (`{}` for none), or one
  // constructor with the terms of its undetermined binders.
  std::optional<SmallVector<Tag>> tags;
  SmallVector<TermNode> binders;
  if (succeeded(parser.parseOptionalLBrace())) {
    tags.emplace();
    if (failed(parser.parseOptionalRBrace()) &&
        (parser.parseCommaSeparatedList([&]() { return labelTag(tags->emplace_back()); }) ||
         parser.parseRBrace()))
      return {};
  } else {
    StringAttr label;
    SMLoc at = parser.getCurrentLocation();
    if (succeeded(parser.parseOptionalSymbolName(label))) {
      std::optional<Tag> found = group.tagOf(member, label.getValue());
      if (!found) {
        parser.emitError(at, "expects a constructor of the family, got @") << label.getValue();
        return {};
      }
      tags.emplace(1, *found);
      if (succeeded(parser.parseOptionalLess()) &&
          (parseTerms(parser, group.ctor(member, *found).binders.size(), binders, nullptr) ||
           parser.parseGreater()))
        return {};
    }
  }
  if (parser.parseGreater())
    return {};
  // The tags as read, in any order and repeated: the builder checks them
  // and makes their normal form.
  DenseI32ArrayAttr refinement;
  if (tags)
    refinement = DenseI32ArrayAttr::get(
        parser.getContext(), llvm::to_vector(llvm::map_range(*tags, [](Tag tag) {
          return static_cast<int32_t>(tag);
        })));
  return getNormalized([&] { return parser.emitError(loc); }, group, member, indices, refinement,
                       binders);
}
