// The processor features an AArch64 program may be compiled to use and
// idris_rt_start tests (cpu_features.h): those of apple-m1 and the Apple
// CPUs after it that function multiversioning names and compiler-rt looks
// for on every AArch64 system, Apple's included. Each has two names: the one
// __builtin_cpu_supports tests (function multiversioning's) and LLVM's,
// which differ for some (fp16 is LLVM's fullfp16).
// apple-m1 has bits 0 to 21; apple-m2 and apple-m3 add bf16, i8mm and bti,
// apple-m4 the four of SME. A CPU named with --cpu may enable more, which
// are not tested (apple-m4's wfxt, apple-m5's cssc and mte: Apple's
// compiler-rt does not look for them).
// PIN(runtime-quarantine) — see PINS.md

#pragma once

#define IDRIS_RT_CPU_FEATURES(X)                                                                 \
  X(0, "simd", "neon")                                                                           \
  X(1, "aes", "aes")                                                                             \
  X(2, "sha2", "sha2")                                                                           \
  X(3, "sha3", "sha3")                                                                           \
  X(4, "crc", "crc")                                                                             \
  X(5, "lse", "lse")                                                                             \
  X(6, "rdm", "rdm")                                                                             \
  X(7, "fp16", "fullfp16")                                                                       \
  X(8, "fp16fml", "fp16fml")                                                                     \
  X(9, "dotprod", "dotprod")                                                                     \
  X(10, "fcma", "complxnum")                                                                     \
  X(11, "jscvt", "jsconv")                                                                       \
  X(12, "rcpc", "rcpc")                                                                          \
  X(13, "rcpc2", "rcpc-immo")                                                                    \
  X(14, "flagm", "flagm")                                                                        \
  X(15, "flagm2", "altnzcv")                                                                     \
  X(16, "frintts", "fptoint")                                                                    \
  X(17, "dit", "dit")                                                                            \
  X(18, "dpb", "ccpp")                                                                           \
  X(19, "dpb2", "ccdp")                                                                          \
  X(20, "sb", "sb")                                                                              \
  X(21, "ssbs", "ssbs")                                                                          \
  X(22, "bf16", "bf16")                                                                          \
  X(23, "i8mm", "i8mm")                                                                          \
  X(24, "bti", "bti")                                                                            \
  X(25, "sme", "sme")                                                                            \
  X(26, "sme2", "sme2")                                                                          \
  X(27, "sme-f64f64", "sme-f64f64")                                                              \
  X(28, "sme-i16i64", "sme-i16i64")
