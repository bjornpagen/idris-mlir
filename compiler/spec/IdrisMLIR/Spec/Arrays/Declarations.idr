-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the arrays declare: the generating set and its yield, a step's
||| movements on buffers, mutable memory and its accesses, the read that
||| gives a value array back, the extent of an array to be made and the tie
||| of its dimensions; the memory space of mutable memory; the two
||| interfaces the generating set and the update share; and the two hand
||| predicates their operands are checked by.
module IdrisMLIR.Spec.Arrays.Declarations

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Arrays.Generating
import IdrisMLIR.Spec.Arrays.Memory

%default total

export
declarations : Declarations
declarations = MkDeclarations
  { ops = generatingOps ++ memoryOps
  , types = []
  , attributes = [SomeAttr mutableAttr]
  , enums = []
  , tables = []
  , interfaces = generatingInterfacesDeclared
  , traits = []
  , directives = []
  , predicates = [valueBuffer, mutableArray]
  , resources = []
  , helpers = []
  , admitted = []
  , rewrites = []
  , skeleton = []
  , headers = []
  }
