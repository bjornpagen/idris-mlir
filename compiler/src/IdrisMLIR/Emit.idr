-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Full Core to the contract: one `idr.program` of the `idr`, `arith`,
||| `math`, `memref`, `ub` and `tensor` dialects in a module, each op made by
||| its builder, which is generated from the op's ODS (IdrisMLIR.Dialect.*),
||| handed to the driver as MLIR bytecode (IdrisMLIR.MLIR.Bytecode). Text is
||| no handoff: MLIR prints the file.
|||
||| A body is written by one fold over `Term`, a paramorphism: the algebra
||| turns each layer into an emitter, which, given the values of the
||| variables in scope and the type the context expects, appends the layer's
||| operations and returns its value. The alternatives Idris proved
||| impossible are left out, which is why the algebra sees each subterm as it
||| was. A match is `idr.match` or `idr.match_lit`, whose regions use the
||| values of their scope where they are; a lambda and a `Delay` are each a
||| function of its own, which an `idr.closure` or an `idr.suspend` names
||| with its captures; an array is made, folded and scanned by the array
||| ops, each a region from indices to an element; a data type carries its
||| constructors in its type.
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
import IdrisMLIR.MLIR
import IdrisMLIR.MLIR.Bytecode
import IdrisMLIR.Term

import Control.Monad.State
import Data.IORef
import Data.List
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
||| module is never held whole. The module holds the program, named by its
||| root, which it runs, at the higher stage; both are at the root's
||| location, which is main's, so that whatever the pipeline reports about
||| the whole program is at the user's code. Every symbol is written once:
||| two functions on one symbol are an internal error. A failure leaves the
||| file unwritten or partly written; the caller discards it.
export
emit : File -> Source -> IO (Either String ())
emit h src = do
  let Just root = find (\f => f.id == src.root) src.fns
    | Nothing => pure (Left "the root function is missing")
  let Right ix = index src
    | Left e => pure (Left e)
  Right w <- newWriter
    | Left e => pure (Left e)
  written <- newIORef SortedSet.empty
  Right () <- each src.fns (\f => case evalStateT (initial f.id (shown f.key.origin)) (function ix f) of
                Left msg => pure (Left msg)
                Right ss => each ss (\s => case symbolOf s of
                  Nothing => pure (Left "a function without its symbol")
                  Just sym => do
                    seen <- readIORef written
                    if contains sym seen then pure (Left ("two functions are named " ++ sym)) else do
                      writeIORef written (insert sym seen)
                      writeTopLevel w s))
    | Left e => pure (Left e)
  finish w h [ (At root.loc, \body => Builtin.moduleOp body)
             , (At root.loc, Idr.programOp root.id.name root.id.name Stage.Higher) ]
  where
    symbolOf : Statement -> Maybe String
    symbolOf s = case lookup "sym_name" s.op.properties of
      Just (StringAttr sym) => Just sym
      _ => Nothing
