-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Source locations, kept independent of Idris's `FC` so that the middle end
||| does not import the Idris compiler.
module IdrisMLIR.Loc

import IdrisMLIR.Ids
import IdrisMLIR.Registry.Libraries

%default total

||| A span of source, 0-based as in Idris: where it starts and where it ends.
public export
record Span where
  constructor MkSpan
  startLine, startCol, endLine, endCol : Int

||| Where code is: a span of a module the session read, as Idris names the
||| module, and the module's source file when it is installed; a span of a
||| module the session never read, by the name the location gives it
||| (reflection can make up a location in any module), with no source; a
||| span of a package's file, which is in no module; or nowhere, code the
||| compiler generated.
public export
data Located = InModule Shown (Maybe String) Span | InUnreadModule Shown Span | InPackage String Span | Unlocated

||| A location: where the code comes from, as the registry classified its
||| module (`origin`, what code tests), and where it is.
public export
record Loc where
  constructor MkLoc
  origin : Origin
  located : Located

||| The location of generated code.
export
noLoc : Loc
noLoc = MkLoc Generated Unlocated

||| The source file of a location, when it has one.
export
locFile : Loc -> Maybe String
locFile l = case l.located of
  InModule _ file _ => file
  InUnreadModule _ _ => Nothing
  InPackage file _ => Just file
  Unlocated => Nothing

||| The module of a location, as Idris names it, when it is in one: printed,
||| and given back to Idris for its error locations, but never compared.
export
locModule : Loc -> Maybe Shown
locModule l = case l.located of
  InModule m _ _ => Just m
  InUnreadModule m _ => Just m
  InPackage _ _ => Nothing
  Unlocated => Nothing

||| The span of a location, when it has one.
export
locSpan : Loc -> Maybe Span
locSpan l = case l.located of
  InModule _ _ s => Just s
  InUnreadModule _ s => Just s
  InPackage _ s => Just s
  Unlocated => Nothing

||| `file:line:column`, 1-based, for messages; a library module whose
||| source is not installed, and a module the session never read, is named
||| by its module, and generated code by no place.
export
Show Loc where
  show l = case l.located of
    InModule _ (Just file) s => file ++ at s
    InModule m Nothing s => show m ++ at s
    InUnreadModule m s => show m ++ at s
    InPackage file s => file ++ at s
    Unlocated => "generated code"
    where
      at : Span -> String
      at s = ":" ++ show (s.startLine + 1) ++ ":" ++ show (s.startCol + 1)

||| Is a location in a library whose diagnostics are reported at the user's
||| code that reached it?
export
inLibrary : Loc -> Bool
inLibrary l = covers ReportAtCaller l.origin
