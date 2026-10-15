// The reproducer, as a check the compiler runs: every x86-64 instruction set
// simdutf's detection reports is one bit of its own, so a kernel's required
// set names the features it uses. At simdutf v9.3.0 (bb77e7bb) and on its
// master branch both assertions fail: AVX512VPOPCNTDQ is AVX512CD's bit.
//
//   c++ -std=c++17 -fsyntax-only -I third_party/simdutf/include \
//       upstream/48-simdutf-avx512vpopcntdq-bit/distinct-bits.cpp
#include "simdutf.h"

namespace {

using simdutf::internal::instruction_set;

constexpr instruction_set x86[] = {
    instruction_set::AVX2,       instruction_set::SSE42,       instruction_set::PCLMULQDQ,
    instruction_set::BMI1,       instruction_set::BMI2,        instruction_set::AVX512F,
    instruction_set::AVX512DQ,   instruction_set::AVX512IFMA,  instruction_set::AVX512PF,
    instruction_set::AVX512ER,   instruction_set::AVX512CD,    instruction_set::AVX512BW,
    instruction_set::AVX512VL,   instruction_set::AVX512VBMI2, instruction_set::AVX512VPOPCNTDQ,
};

constexpr bool distinctBits() {
  unsigned seen = 0;
  for (instruction_set set : x86) {
    unsigned bit = static_cast<unsigned>(set);
    if (bit == 0 || (bit & (bit - 1)) != 0 || (seen & bit) != 0)
      return false;
    seen |= bit;
  }
  return true;
}

static_assert(instruction_set::AVX512VPOPCNTDQ != instruction_set::AVX512CD,
              "AVX512VPOPCNTDQ has a bit of its own, not AVX512CD's");
static_assert(distinctBits(), "each x86-64 instruction set is one bit of its own");

} // namespace
