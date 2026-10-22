-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Full Core to the module: one `idr.program` of the `idr`, `arith`,
||| `math`, `memref`, `linalg`, `ub`, `tensor`, `bufferization` and `scf`
||| dialects in a module, each op made by its builder, which is printed
||| from the dialect's specification or from upstream's records
||| (IdrisMLIR.Dialect.*), handed to the driver as MLIR bytecode
||| (IdrisMLIR.MLIR.Bytecode). Text is no handoff: MLIR prints the file.
|||
||| A body is written by one fold over `Term`, a paramorphism: the algebra
||| turns each layer into an emitter, which, given its scope and what the
||| context wants, appends the layer's operations and returns its value.
||| Quantities are the binders' as Idris checked them: nothing here counts
||| a use. A match is `idr.data.match`, a region per case, each case
||| binding the scrutinee refined to its constructor and its constructor's
||| erased binders, its fields reads of the refined value; a match on
||| literals is `idr.lit.match`, its default binding the scrutinee refined
||| to the complement of its keys; a lambda and a `Delay` are each a
||| function of its own, which an `idr.fn.closure` or an `idr.lazy.suspend` names
||| with its captures and its scope's levels; an array is made, folded and
||| scanned by the array ops, each a region from indices to an element; a
||| data type is its family's group and member applied to index terms.
||| Idris's world is no value of the module: IO is ordered by the effects
||| its ops declare.
|||
||| Types are synthesized as they are written, bidirectionally: every
||| emitter returns its value's type, and a context that knows the type it
||| expects passes it down, for the term whose type its parts do not give,
||| a closure whose body never returns, a value whose type holds an extent
||| dynamic where the context holds it static, which is cast to it, and a
||| value at index terms the scope's refinements make equal to the
||| context's, which is reindexed to it.
module IdrisMLIR.Emit

import IdrisMLIR.Dialect.Builtin as Builtin
import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Emit.Declarations
import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.MLIR.Bytecode
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Pipeline.Stage
import IdrisMLIR.Term

import Control.Monad.State
import Data.List
import Data.List1
import System.File

%default total

||| Each of `xs` done, stopping at the first failure.
each : List a -> (a -> IO (Either String ())) -> IO (Either String ())
each [] f = pure (Right ())
each (x :: xs) f = do
  Right () <- f x
    | Left e => pure (Left e)
  each xs f

||| Writes the module of a program, the `idr` module idris-mlir reads, to
||| `h` as bytecode, one function and those it owns at a time, so that the
||| module is never held whole: the program's other functions, then its
||| root. The module holds the program, named by its root, which it runs,
||| at the higher stage; both are at the root's location, which is main's,
||| so that whatever the pipeline reports about the whole program is at the
||| user's code. That no two functions share a symbol is the program's
||| symbol table's, which MLIR verifies when it reads the module; the
||| frontend finds two instances on one key where the key is made. A
||| failure leaves the file unwritten or partly written; the caller
||| discards it.
export covering
emit : File -> Source -> IO (Either String ())
emit h src = do
  let ix = index src
  Right w <- newWriter
    | Left e => pure (Left e)
  Right () <- each (src.others ++ [src.root]) (\f => case evalStateT (initial f) (function ix f) of
                Left msg => pure (Left msg)
                Right ss => each ss (\(_, s) => writeTopLevel w s))
    | Left e => pure (Left e)
  finish w h [ (At src.root.loc, \body => Builtin.moduleOp body)
             , (At src.root.loc, Idr.programOp (StringAttr src.root.symbol) (SymbolRefAttr (MkSymbolRef src.root.symbol [])) Higher) ]

||| A refusal of a program, as its module carries it: the rule refused
||| under, where, and what it says.
public export
record ModuleRefusal where
  constructor MkModuleRefusal
  rule : SomeRule
  site : Loc
  message : String

||| A refusal as its op: its rule, and its message a string.
refusal : ModuleRefusal -> Op
refusal r = Idr.refusalOp r.rule (StringAttr r.message)

||| Writes the module of a refused program to `h` as bytecode: a module of
||| no program and one `idr.refusal` per refusal, in the order given, its
||| site the op's location, its rule a property of the op and its message
||| a string, which the driver reports. A refused module has a refusal.
export covering
refused : File -> List1 ModuleRefusal -> IO (Either String ())
refused h rs = do
  Right w <- newWriter
    | Left e => pure (Left e)
  Right () <- each (forget rs) (\r => writeTopLevel w (MkStatement Nothing (refusal r) (At r.site)))
    | Left e => pure (Left e)
  finish w h [ (At noLoc, \body => Builtin.moduleOp body) ]
