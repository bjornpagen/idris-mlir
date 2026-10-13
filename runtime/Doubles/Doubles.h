// rt::doubles: doubles as text, read from text, and as integers.
// PIN(runtime-quarantine) — see PINS.md
#pragma once

#include <stddef.h>
#include <stdint.h>

namespace rt::doubles {

// The fields of a double's bits, as IEEE 754 lays them out.
inline constexpr uint64_t mantissaBits = 52;
inline constexpr uint64_t mantissaMask = (uint64_t{1} << mantissaBits) - 1;
inline constexpr uint64_t exponentBits = 11;
inline constexpr uint64_t exponentMask = (uint64_t{1} << exponentBits) - 1;
inline constexpr int64_t exponentBias = (int64_t{1} << (exponentBits - 1)) - 1;

inline uint64_t bitsOf(double x) { return __builtin_bit_cast(uint64_t, x); }

// Room for the longest text formatDouble writes, 24 bytes: a sign, 17
// digits, a point and an exponent such as `e-308`.
inline constexpr size_t doubleTextMax = 32;

// The text of a double; returns its length (Printing.cpp).
size_t formatDouble(double x, volatile char *out);

} // namespace rt::doubles
