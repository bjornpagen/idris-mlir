// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// rt::start: the program's entry and the runner. A program's main calls
// idris_rt_start, which checks the machine, keeps the program's arguments
// and runs the program on its stack, sized by the compiler from every frame
// it can stack, so reaching its guard is the runtime's internal error and
// never the program's. idris-mlir's tools run on the same runner, on a
// stack of their own measured size. What it needs of the system is in the
// platform layer (rt::platform).
#pragma once

#include "End/End.h"
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace rt::start {

// The startup check, which a program and a tool both pass before anything
// else of the runtime runs: a system whose page is not the one the runtime
// is built for, or a processor that lacks one of `features` (the
// IDRIS_RT_CPU_FEATURES bits of what the code about to run was compiled to
// use), cannot run it, and the process ends as such before it runs. It and
// what it calls stay compiled for the target's baseline. Inlined into each
// entry, which is marked the same way, so each compares the page its own
// unit was built for.
[[gnu::always_inline]] IDRIS_RT_BASELINE inline void checkMachine(uint64_t features) noexcept {
  size_t system = rt::platform::systemPageSize();
  if (system != rt::platform::pageSize())
    rt::end::end(rt::end::WrongPage{rt::platform::pageSize(), system});
  if (uint64_t missing = features & ~rt::platform::cpuFeatures(); missing != 0)
    rt::end::end(rt::end::MissingFeatures{missing});
}

// The arguments main received, kept by idris_rt_start before the program
// runs (Arguments.cpp).
void keepArguments(int32_t count, char **text) noexcept;

// The number of the program's arguments, which idris_rt_start kept.
int64_t argumentCount();

// A new string of argument i, whose bytes are decoded as any bytes from
// outside the program are; the empty string when there is no argument i.
const idris_rt_str *argument(int64_t i);

// The runner, which programs and tools share: the heap set up once, under
// the host's limit on committed memory (`limit`, SIZE_MAX for none); GMP
// pointed at it; then fn(arg) on a new thread whose stack is the plan's,
// committed whole as it starts, since it is small and the program's own
// need: [guard | stack | guard | signal stack], in the heap's first region.
// A fault on the stack's guard is the runtime's internal error, said on the
// signal stack; one on the signal stack's guard is a fault no handler can
// take, which the system ends the process by. Refused when the system
// refuses that memory.
idris_rt_ran run(void (*fn)(void *), void *arg, const idris_rt_stack_plan &plan,
                 size_t limit) noexcept;

// GMP's memory functions, over the runtime's allocator (Alloc/Gmp.cpp),
// which the runner sets once, before any thread that may use GMP starts.
void pointGmp() noexcept;

} // namespace rt::start
