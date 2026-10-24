-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Idris.Syntax.Pragmas

import Core.FC
import Parser.Lexer.Pragma

%default total

||| A pragma a module writes, and where.
public export
record PragmaUse where
  constructor MkPragmaUse
  kind : KwPragma
  loc : FC

public export
data LangExt
  = ElabReflection

export
Show LangExt where
  show ElabReflection = "ElabReflection"

export
Eq LangExt where
  ElabReflection == ElabReflection = True
