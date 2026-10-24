-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Idris.Pretty.Render

import Libraries.Text.PrettyPrint.Prettyprinter
import public Libraries.Text.PrettyPrint.Prettyprinter.Render.String

%default total

||| A document as text: unannotated, at an unbounded width, so what is
||| printed is the same on any terminal.
export
render : Doc ann -> String
render doc = renderString (layoutPretty (MkLayoutOptions Unbounded) doc)
