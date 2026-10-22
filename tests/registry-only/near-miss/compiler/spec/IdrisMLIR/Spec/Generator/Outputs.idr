-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module IdrisMLIR.Spec.Generator.Outputs

outputs : List String
outputs = ["IdrBase.td", "Control.h", "Effects.h.inc"]

generatorModule : String -> Bool
generatorModule = isPrefixOf "IdrisMLIR.Spec.Generator."
