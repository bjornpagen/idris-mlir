// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The values a test writes a property's result to be, read as Item says:
// a list split only outside brackets and quotes, each item unwrapped of the
// parentheses that keep its commas from splitting the list of properties,
// then read as `_`, an integer, a float, or an attribute as MLIR writes it.

#include "idr/Transforms/Expect.h"

#include "mlir/AsmParser/AsmParser.h"

using namespace mlir;

namespace idr::expect {

namespace {

// The items of `text` split at `separator` where it stands outside brackets
// and quotes, so a value written as MLIR writes it keeps its own. The `>`
// of an arrow closes nothing.
SmallVector<StringRef> itemsOf(StringRef text, char separator) {
  SmallVector<StringRef> out;
  int depth = 0;
  bool quoted = false;
  size_t start = 0;
  for (size_t i = 0; i < text.size(); ++i) {
    char c = text[i];
    if (quoted) {
      if (c == '\\')
        ++i;
      else if (c == '"')
        quoted = false;
      continue;
    }
    if (c == '"')
      quoted = true;
    else if (c == '(' || c == '[' || c == '{' || c == '<')
      ++depth;
    else if (c == ')' || c == ']' || c == '}' || (c == '>' && !(i > 0 && text[i - 1] == '-')))
      --depth;
    else if (c == separator && depth == 0) {
      out.push_back(text.slice(start, i));
      start = i + 1;
    }
  }
  out.push_back(text.substr(start));
  return out;
}

// An item without the parentheses that keep the commas in it from
// splitting the list of properties: an opening one whose match is the
// item's last character.
StringRef unwrapped(StringRef item) {
  item = item.trim();
  if (item.size() < 2 || item.front() != '(' || item.back() != ')')
    return item;
  int depth = 0;
  for (size_t i = 0; i + 1 < item.size(); ++i) {
    if (item[i] == '(')
      ++depth;
    else if (item[i] == ')' && --depth == 0)
      return item;
  }
  return item.drop_front().drop_back().trim();
}

// One value, as Item reads it: `_`, an integer, a float, then an attribute.
// No item is empty, and the empty text is no attribute either; it is
// refused before the attribute parser reports it as one of its own.
FailureOr<Item> itemOf(const Written &written, StringRef item) {
  StringRef text = unwrapped(item);
  if (text == "_")
    return Item(Computed{});
  int64_t integer;
  if (!text.getAsInteger(10, integer))
    return Item(integer);
  double real;
  if (!text.getAsDouble(real))
    return Item(real);
  if (text.empty())
    return written.malformed();
  if (Attribute attr = parseAttribute(text, written.module->getContext()))
    return Item(attr);
  return written.malformed();
}

} // namespace

FailureOr<SmallVector<Item>> valuesOf(const Written &written, StringRef text, char separator) {
  SmallVector<Item> out;
  for (StringRef item : itemsOf(text, separator)) {
    FailureOr<Item> value = itemOf(written, item);
    if (failed(value))
      return failure();
    out.push_back(*value);
  }
  return out;
}

} // namespace idr::expect
