// idr.lower:crashMessage: the message of a crash, as the runtime prints it.
export module idr.lower:crashMessage;

import idr.mlir;

using namespace mlir;

namespace idr::lower {

namespace {

std::string describe(Location loc) {
  if (auto file = dyn_cast<FileLineColLoc>(loc))
    return (file.getFilename().getValue() + ":" + Twine(file.getLine()) + ":" +
            Twine(file.getColumn()))
        .str();
  if (auto fused = dyn_cast<FusedLoc>(loc))
    for (Location inner : fused.getLocations())
      if (auto text = describe(inner); !text.empty())
        return text;
  if (auto named = dyn_cast<NameLoc>(loc))
    return describe(named.getChildLoc());
  if (auto site = dyn_cast<CallSiteLoc>(loc))
    return describe(site.getCallee());
  return "";
}

} // namespace

// The message of a crash: its cause and the Idris location.
export std::string crashMessage(Location loc, StringRef cause) {
  std::string where = describe(loc);
  return ("idris-mlir: " + cause + (where.empty() ? "" : " at " + where) + "\n").str();
}

} // namespace idr::lower
