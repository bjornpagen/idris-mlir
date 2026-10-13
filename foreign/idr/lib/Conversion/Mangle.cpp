// The mangling of program symbols.

#include "idr/Conversion/Mangle.h"

#include "llvm/ADT/StringExtras.h"
#include "llvm/Support/ConvertUTF.h"

namespace idr::conversion {

std::string mangle(llvm::StringRef name) {
  std::string out;
  out.reserve(name.size());
  const auto *at = reinterpret_cast<const llvm::UTF8 *>(name.begin());
  const auto *end = reinterpret_cast<const llvm::UTF8 *>(name.end());
  while (at != end) {
    char c = static_cast<char>(*at);
    if (llvm::isAlnum(c) || c == '_' || c == '.') {
      out += c;
      ++at;
      continue;
    }
    // A byte that starts no UTF-8 sequence is written as itself, a code
    // point below 256: a symbol's text is UTF-8, so this is never met, and
    // were it met the result would still name one symbol.
    const llvm::UTF8 *start = at;
    llvm::UTF32 point = 0;
    if (llvm::convertUTF8Sequence(&at, end, &point, llvm::strictConversion) != llvm::conversionOK) {
      point = *start;
      at = start + 1;
    }
    out += '$';
    out += std::to_string(point);
    out += '$';
  }
  return out;
}

} // namespace idr::conversion
