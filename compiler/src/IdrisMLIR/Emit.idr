-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Full Core to the contract: one module of the `idr`, `arith`, `math`,
||| `memref` and `ub` dialects, each op made by its builder, which is
||| generated from the op's ODS (IdrisMLIR.Dialect.*). An op is written in
||| its dialect's declarative format where the format is one the generated
||| printer writes, and in MLIR's generic form otherwise (IdrisMLIR.MLIR).
|||
||| A body is written by one fold over `Term`, a paramorphism: the algebra
||| turns each layer into an emitter, which, given the values of the
||| variables in scope and the type the context expects, appends the layer's
||| operations and returns its value. The alternatives Idris proved
||| impossible are left out, which is why the algebra sees each subterm as it
||| was. Control flow is regions: a match is `idr.match` or `idr.match_lit`,
||| a lambda `idr.lambda` and a `Delay` `idr.delay`, whose bodies use the
||| values of their scope where they are.
|||
||| Types are synthesized as they are written, bidirectionally: every
||| emitter returns its value's type (TTC drops the types of `let`s), and a
||| context that knows the type it expects passes it down, for
||| the one term whose type its parts do not give, a closure whose body never
||| returns.
module IdrisMLIR.Emit

import IdrisMLIR.Dialect.Arith as Arith
import IdrisMLIR.Dialect.Builtin as Builtin
import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Dialect.Math as Math
import IdrisMLIR.Dialect.MemRef as MemRef
import IdrisMLIR.Dialect.UB as UB
import IdrisMLIR.Emit.Declarations
import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Ids
import IdrisMLIR.MLIR
import IdrisMLIR.Term

import Control.Monad.State
import Data.List
import Data.String
import System.File

%default total

||| An op in its dialect's declarative format, through the dialect's
||| generated printer, which leaves its regions to the region printer and
||| gives nothing for an op it writes generic: one with a custom format, or
||| of a dialect the module does not write.
covering
format : Format
format o = case fst (break (== '.') o.name) of
  "idr" => Idr.printOp o
  "arith" => Arith.printOp o
  "math" => Math.printOp o
  "memref" => MemRef.printOp o
  "ub" => UB.printOp o
  "builtin" => Builtin.printOp o
  _ => Nothing

||| Writes `text` to the handle.
written : File -> String -> IO (Either String ())
written h text = either (\e => Left ("writing the module: " ++ show e)) Right <$> fPutStr h text

||| Writes the top-level op `act` makes, once it is made whole.
covering
top : File -> E Statement -> IO (Either String ())
top h act = case evalStateT (MkES 0 [<]) act of
  Left msg => pure (Left msg)
  Right s => written h (topLevel format s)

||| Writes each of `xs`, stopping at the first failure.
each : List a -> (a -> IO (Either String ())) -> IO (Either String ())
each [] f = pure (Right ())
each (x :: xs) f = do
  Right () <- f x
    | Left e => pure (Left e)
  each xs f

||| Writes the contract text of a program, the `idr` module idris-mlir
||| reads, to `h`, one top-level op at a time, so that the text of the
||| whole module never exists at once. The module is at the root's
||| location, which is main's, so that whatever the pipeline reports about
||| the whole program is at the user's code. A failure may leave part of
||| the module written; the caller discards it.
export covering
emit : File -> Source -> IO (Either String ())
emit h src = do
  let Just root = find (\f => f.id == src.root) src.fns
    | Nothing => pure (Left "the root function is missing")
  let ix = index src
  let (opening, closing) = moduleText format (At root.loc)
                             ({ attributes := [Idr.programDiscardable] }
                                (Builtin.moduleOp (MkRegion [] [])))
  Right () <- written h opening
    | Left e => pure (Left e)
  Right () <- each src.datas (\d => top h (dataDecl ix d))
    | Left e => pure (Left e)
  Right () <- each src.fns (\f => top h (function ix src.root f))
    | Left e => pure (Left e)
  written h closing
