// idr.specialize:bindingtime: the binding time of one parameter, and the
// name idr-binding-times reports it by.
export module idr.specialize:bindingtime;

import idr.mlir;

using namespace mlir;

export namespace idr::specialize {

enum class BindingTime : uint8_t {
  // The function is on no cycle: a call specializes on anything static.
  Free,
  Fixed,
  Decreasing,
  Bounded,
  Other,
};

llvm::StringRef nameOf(BindingTime time) {
  switch (time) {
  case BindingTime::Free:
    return "free";
  case BindingTime::Fixed:
    return "fixed";
  case BindingTime::Decreasing:
    return "decreasing";
  case BindingTime::Bounded:
    return "bounded";
  case BindingTime::Other:
    return "other";
  }
  return "other";
}

} // namespace idr::specialize
