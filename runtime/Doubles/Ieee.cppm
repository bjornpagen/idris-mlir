// rt.doubles:ieee: the fields of a double's bits, as IEEE 754 lays them out.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <stdint.h>

export module rt.doubles:ieee;

namespace rt::doubles {

inline constexpr uint64_t mantissaBits = 52;
inline constexpr uint64_t mantissaMask = (uint64_t{1} << mantissaBits) - 1;
inline constexpr uint64_t exponentBits = 11;
inline constexpr uint64_t exponentMask = (uint64_t{1} << exponentBits) - 1;
inline constexpr int64_t exponentBias = (int64_t{1} << (exponentBits - 1)) - 1;

uint64_t bitsOf(double x) { return __builtin_bit_cast(uint64_t, x); }

} // namespace rt::doubles
