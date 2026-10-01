// Arrays: one cell holding a length and its elements (idris_rt_array). The
// compiler reads and writes the elements itself, with the layout it chose;
// the runtime allocates the cell and frees it (rc.cc).
// PIN(runtime-quarantine) — see PINS.md

#include "internal.h"

namespace {

[[noreturn]] void tooLarge() {
  static constexpr char message[] = "idris runtime: array too large\n";
  idris_rt_crash(message, sizeof message - 1);
}

} // namespace

extern "C" idris_rt_array *idris_rt_array_new(int64_t length, uint32_t info) {
  uint64_t count = length < 0 ? 0 : static_cast<uint64_t>(length);
  uint64_t stride = idris_rt_info_tag(info);
  // The cell's size must fit a size_t with the header and length before it.
  if (stride != 0 && count > (SIZE_MAX - sizeof(idris_rt_array)) / stride)
    tooLarge();
  auto *array = static_cast<idris_rt_array *>(
      rt::newCell(sizeof(idris_rt_array) + static_cast<size_t>(count * stride), info));
  array->length = count;
  return array;
}
