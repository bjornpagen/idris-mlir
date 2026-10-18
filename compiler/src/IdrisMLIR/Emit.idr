-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Full Core to the contract: one `idr.program` of the `idr`, `arith`,
||| `math`, `memref`, `ub` and `tensor` dialects in a module, each op made by
||| its builder, which is generated from the op's ODS (IdrisMLIR.Dialect.*),
||| handed to the driver as MLIR bytecode (IdrisMLIR.MLIR.Bytecode). Text is
||| no handoff: MLIR prints the file.
|||
||| A body is written by one fold over `Term`, a paramorphism: the algebra
||| turns each layer into an emitter, which, given what the variables in
||| scope stand for and what the context wants, appends the layer's
||| operations and returns its value. The algebra sees each subterm as it
||| was too: how often a body uses a variable decides how it holds it, and
||| a suspension of a value is that value held. A match is `idr.match` or
||| `idr.match_lit` of its possible arms, whose regions use the
||| values of their scope where they are; a lambda and a `Delay` are each a
||| function of its own, which an `idr.closure` or an `idr.suspend` names
||| with its captures; an array is made, folded and scanned by the array
||| ops, each a region from indices to an element; a data type is its name,
||| its constructors in the module's table of data types.
|||
||| Types are synthesized as they are written, bidirectionally: every
||| emitter returns its value's type (TTC drops the types of `let`s), and a
||| context that knows the type it expects passes it down, for the term
||| whose type its parts do not give, a closure whose body never returns,
||| and for a value whose type holds an extent dynamic where the context
||| holds it static, which is cast to it.
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
import IdrisMLIR.Term

import Control.Monad.State
import Data.IORef
import Data.List
import Data.List1
import Data.SortedSet
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
||| user's code. Every symbol is written once: two functions on one symbol
||| are an internal error. A failure leaves the file unwritten or partly
||| written; the caller discards it.
export
emit : File -> Source -> IO (Either String ())
emit h src = do
  let ix = index src
  Right w <- newWriter ix.table
    | Left e => pure (Left e)
  written <- newIORef SortedSet.empty
  Right () <- each (src.others ++ [src.root]) (\f => case evalStateT (initial f.id (shown f.key.origin)) (function ix f) of
                Left msg => pure (Left msg)
                Right ss => each ss (\(sym, s) => do
                  seen <- readIORef written
                  if contains sym seen then pure (Left ("two functions are named " ++ sym)) else do
                    writeIORef written (insert sym seen)
                    writeTopLevel w s))
    | Left e => pure (Left e)
  finish w h [ (At src.root.loc, \body => Builtin.moduleOp body)
             , (At src.root.loc, Idr.programOp src.root.id.name src.root.id.name Stage.Higher) ]

||| A refusal of a program, as its module carries it: the rule refused
||| under, where, and what it says.
public export
record ModuleRefusal where
  constructor MkModuleRefusal
  rule : Rule
  site : Loc
  message : String

||| Writes the module of a refused program to `h` as bytecode: a module of
||| no program, its attribute `idr.refusals` the refusals, in the order
||| given, each an `#idr.refusal` of its rule, its site and its message,
||| which the driver reports. A refused module has a refusal.
export
refused : File -> List1 ModuleRefusal -> IO (Either String ())
refused h rs = do
  Right w <- newWriter []
    | Left e => pure (Left e)
  finish w h [ (At noLoc, \body => { attributes := [("idr.refusals", ArrayAttr (map refusal (forget rs)))] }
                                   (Builtin.moduleOp body)) ]
  where
    refusal : ModuleRefusal -> MlirAttr
    refusal r = idr (RefusalAttr r.rule (At r.site) r.message)
