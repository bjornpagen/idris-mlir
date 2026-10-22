-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the runtime's area of the specification declares: the closed sets
||| an op names (a crash site's cause, a clock's kind), the runtime's helper
||| functions the lowering calls, and the headers the runtime is printed
||| (how a program ends; what a clock reading is; what the compiler lays out
||| as the runtime's C reads it).
module IdrisMLIR.Spec.Runtime.Declarations

import IdrisMLIR.Spec.Core.Declarations
import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Runtime.Clocks
import IdrisMLIR.Spec.Runtime.Endings
import IdrisMLIR.Spec.Runtime.Helpers
import IdrisMLIR.Spec.Runtime.Layout

%default total

public export
declarations : Declarations
declarations =
  { enums := [enumDef causeClosed, enumDef clockKindClosed]
  , helpers := helpers
  , headers := [endingsHeader, clocksHeader, layoutHeader]
  } nothing
