<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Audits

`bugs.md` is the register of the compiler bugs known on main, each under
the lane that owns its fix (tools/lanes/README.md), with its test or
reproducer, its cause when known, and what is owed; an entry goes when its
fix lands. Planned work is not here: it is a proposal (proposals/README.md),
and a finding that is not a bug becomes an item of the proposal that owns
it. The audits that were taken and finished are in git: the test-suite
audit, the leak audit, the label solve, the rederivation sweep and the
rest, last at 77eaa5b1.
