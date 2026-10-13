// Profiling with Tracy: the one header that includes it. Every build reads
// these macros; only the profile build (IDRIS_MLIR_PROFILE, which defines
// TRACY_ENABLE and TRACY_ON_DEMAND everywhere it compiles) gives them a
// body. In every other build each one expands to nothing and its arguments
// are never evaluated, so an argument may walk the module (IDR_PLOT of an
// op count) and costs nothing outside a profile. In the profile build a
// zone costs a load and a branch until a capture connects.
//
// A zone's name is a string literal: Tracy keeps a pointer to it, and a
// zone of ours never allocates. The zones of passes and analyses, whose
// names are only known at run time, are addInstrumentation's.
#ifndef IDR_SUPPORT_PROFILE_H
#define IDR_SUPPORT_PROFILE_H

#include "tracy/Tracy.hpp"

#include <array>
#include <cstddef>
#include <cstdint>

namespace mlir {
class PassManager;
} // namespace mlir

namespace idr::profile {

// What a zone belongs to, which gives it its colour, so that a timeline
// reads by colour before it reads by name.
enum class Subsystem : std::uint8_t { Driver, Parse, Round, Analysis, Pass, Conversion, LLVM, Link };

// One fixed colour per subsystem, 0xRRGGBB.
constexpr std::uint32_t color(Subsystem subsystem) {
  constexpr std::array<std::uint32_t, 8> colors{
      0x4C72B0, // Driver: blue
      0x55A868, // Parse: green
      0xC44E52, // Round: red
      0x8172B2, // Analysis: purple
      0xCCB974, // Pass: ochre
      0x64B5CD, // Conversion: cyan
      0xDD8452, // LLVM: orange
      0x937860, // Link: brown
  };
  return colors[static_cast<std::size_t>(subsystem)];
}

// Zones for every pass and every analysis the manager runs, named by the
// pass or analysis and coloured Pass or Analysis. Defined in every build;
// it adds nothing without TRACY_ENABLE, so a manager's owner calls it
// unconditionally.
void addInstrumentation(mlir::PassManager &pm);

} // namespace idr::profile

#ifdef TRACY_ENABLE
#define IDR_ZONE(name) ZoneScopedN(name)
#define IDR_ZONE_IN(name, sub) ZoneScopedNC(name, ::idr::profile::color(::idr::profile::Subsystem::sub))
#define IDR_FRAME(name) FrameMarkNamed(name)
#define IDR_PLOT(name, value) TracyPlot(name, static_cast<int64_t>(value))
#define IDR_MESSAGE(literal) TracyMessageL(literal)
#else
#define IDR_ZONE(name)
#define IDR_ZONE_IN(name, sub)
#define IDR_FRAME(name)
#define IDR_PLOT(name, value)
#define IDR_MESSAGE(literal)
#endif

#endif // IDR_SUPPORT_PROFILE_H
