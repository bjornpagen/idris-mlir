-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the effect system declares of the dialect: the states of the tree,
||| whose classes the C++ names; the interface by which the one query API
||| reads an op's own effects as one set; and the header of constants the
||| hand C++ includes: the tree, the atoms and what each projects from, the
||| typed rules, runtime memory and what LLVM is told.
module IdrisMLIR.Spec.Effects.Declarations

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Effects.LLVM

%default total

||| An op's own effects as one set, read with one dispatch: its class's
||| constant where its class decides them, its rules applied to its types
||| where they decide, with no list of effects built either way. Every op
||| that runs where it stands has it.
export
declaredEffectsInterface : InterfaceDef
declaredEffectsInterface = MkInterfaceDef
  { name = ident "DeclaredEffectsOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject (code "::idr::effects::EffectSet") (ident "getDeclaredEffects") []
          (DelegatesByClass (ident "declaredEffects")) (line "the op's own effects, without its regions'") ]
  , verifier = Unverified
  , doc = brief (line "an op's own effects, as one set")
  }

||| The constants the effect system's hand C++ reads, every closed set
||| before the tables over it.
export
effectTree : Header
effectTree = MkHeader (ident "EffectTree")
  [ ( ident "idr" ::: []
    , map EnumOf
        [ enumDef reachClosed, enumDef kindClosed, enumDef resourceClosed, enumDef atomClosed
        , enumDef conditionClosed, enumDef landingClosed, enumDef ruleClosed, enumDef runtimeMemoryClosed
        , enumDef accessClosed, enumDef locationClosed, enumDef attributeClosed ]
      ++ map TableOf
        [ resourceTable, atomTable, projectionTable, valueMemoryTable, callKindsTable
        , ruleTable, runtimeMemoryTable, locationTable, llvmTable ] ) ]
  (brief (line "the effect tree, the atoms of a row, the typed rules and what LLVM is told"))

export
declarations : Declarations
declarations = { resources := Declaration.resources
               , interfaces := [declaredEffectsInterface]
               , headers := [effectTree] } nothing
