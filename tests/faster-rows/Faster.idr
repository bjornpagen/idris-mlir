-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The registry's Faster rows, none: the module the test-only frontend of
||| tests/faster-rows is built with in place of the shipped one. A Faster
||| row is another lowering of a definition whose body is its one meaning,
||| so a frontend built with none compiles every program from the bodies,
||| and gives each program the result the shipped frontend gives it. Its
||| type is the shipped module's, so a frontend whose rows live elsewhere,
||| or whose Faster rows have another type, does not build with it.
module IdrisMLIR.Registry.Faster

import IdrisMLIR.Registry.Entry

%default total

export
faster : List (Entry Faster)
faster = []
