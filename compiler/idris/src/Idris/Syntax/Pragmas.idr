-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Idris.Syntax.Pragmas

import Core.FC

%default total

||| A pragma this parser accepts, one constructor per spelling, so that a
||| rule names the pragma it takes by a value it cannot misspell, and a
||| module's uses of pragmas are kept as facts a reader matches on.
public export
data KwPragma
  = KwAllowOverloads
  | KwAutoLazy
  | KwBuiltin
  | KwCharLit
  | KwDeclsLit
  | KwDefault
  | KwDefaultHint
  | KwDeprecate
  | KwDoubleLit
  | KwExport
  | KwExtern
  | KwForeign
  | KwGlobalHint
  | KwHide
  | KwHint
  | KwInline
  | KwIntegerLit
  | KwLanguage
  | KwLogging
  | KwMacro
  | KwMkWorld
  | KwName
  | KwNameLit
  | KwNfMetavarThreshold
  | KwNoInline
  | KwNoMangle
  | KwPair
  | KwPrefixRecordProjections
  | KwRewrite
  | KwRunElab
  | KwSearch
  | KwSpec
  | KwStart
  | KwStringLit
  | KwSyntactic
  | KwTCInline
  | KwTransform
  | KwTTImpLit
  | KwUnboundImplicits
  | KwUnhide
  | KwUnsafe
  | KwWorld

||| How the source writes a pragma, after its `%`.
export
spelling : KwPragma -> String
spelling KwAllowOverloads = "allow_overloads"
spelling KwAutoLazy = "auto_lazy"
spelling KwBuiltin = "builtin"
spelling KwCharLit = "charLit"
spelling KwDeclsLit = "declsLit"
spelling KwDefault = "default"
spelling KwDefaultHint = "defaulthint"
spelling KwDeprecate = "deprecate"
spelling KwDoubleLit = "doubleLit"
spelling KwExport = "export"
spelling KwExtern = "extern"
spelling KwForeign = "foreign"
spelling KwGlobalHint = "globalhint"
spelling KwHide = "hide"
spelling KwHint = "hint"
spelling KwInline = "inline"
spelling KwIntegerLit = "integerLit"
spelling KwLanguage = "language"
spelling KwLogging = "logging"
spelling KwMacro = "macro"
spelling KwMkWorld = "MkWorld"
spelling KwName = "name"
spelling KwNameLit = "nameLit"
spelling KwNfMetavarThreshold = "nf_metavar_threshold"
spelling KwNoInline = "noinline"
spelling KwNoMangle = "nomangle"
spelling KwPair = "pair"
spelling KwPrefixRecordProjections = "prefix_record_projections"
spelling KwRewrite = "rewrite"
spelling KwRunElab = "runElab"
spelling KwSearch = "search"
spelling KwSpec = "spec"
spelling KwStart = "start"
spelling KwStringLit = "stringLit"
spelling KwSyntactic = "syntactic"
spelling KwTCInline = "tcinline"
spelling KwTransform = "transform"
spelling KwTTImpLit = "TTImpLit"
spelling KwUnboundImplicits = "unbound_implicits"
spelling KwUnhide = "unhide"
spelling KwUnsafe = "unsafe"
spelling KwWorld = "World"

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
allLangExts : List LangExt
allLangExts = [ElabReflection]

export
Show LangExt where
  show ElabReflection = "ElabReflection"

export
Eq LangExt where
  ElabReflection == ElabReflection = True
