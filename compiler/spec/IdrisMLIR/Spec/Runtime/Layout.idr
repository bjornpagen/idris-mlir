-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the compiler lays out the way the runtime's C reads it, so neither
||| takes it from the other's `sizeof` on the build machine: an array cell's
||| header, its count and info words and then its length, before its first
||| element. The runtime checks its struct against it when it is built.
module IdrisMLIR.Spec.Runtime.Layout

import IdrisMLIR.Spec.Core.Cpp
import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Core.Text

import Data.List1

%default total

||| An array cell's bytes before its first element: a cell's header of two
||| 32-bit words, then a 64-bit length.
public export
arrayHeaderBytes : Nat
arrayHeaderBytes = 4 + 4 + 8

public export
layoutHeader : Header
layoutHeader = MkHeader (ident "RuntimeLayout")
  [ (Nested (ident "runtime" ::: []),
      [ Scalar (ident "arrayHeaderBytes") Unsigned32 (IntCell (natToInteger arrayHeaderBytes))
          (line "an array cell's bytes before its first element")
      ])
  ]
  (brief (line "what the compiler lays out as the runtime's C reads it"))
