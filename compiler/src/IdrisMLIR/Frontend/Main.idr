||| The `mlir` backend, registered with the stock Idris driver.
module IdrisMLIR.Frontend.Main

import Compiler.Common
import Core.Context
import Core.Directory
import Idris.Driver
import Idris.Syntax

import IdrisMLIR.Emit
import IdrisMLIR.Erase
import IdrisMLIR.IR
import IdrisMLIR.Frontend.Translate

import System.File

orFail : FC -> Either String a -> Core a
orFail fc (Left msg) = throw (GenericMsg fc ("mlir backend: " ++ msg))
orFail _ (Right x) = pure x

write : String -> String -> Core ()
write path text = do
  Right () <- coreLift (writeFile path text)
    | Left err => throw (FileErr path err)
  pure ()

||| Runs after a module checks and before its TTC is written. Writes the
||| module's IR (before erasure) and its MLIR next to the TTC.
compileModule : Ref Ctxt Defs -> Ref Syn SyntaxInfo ->
                String -> Core (Maybe (String, List String))
compileModule c _ source = do
  -- Idris only fails `--check` for errors with a source line (see Translate).
  let fc = MkFC (PhysicalIdrSrc !(ctxtPathToNS source)) (0, 0) (0, 0)
  prog <- translateModule fc
  mlir <- orFail fc (erase prog >>= emit)
  write !(getTTCFileName source "ir") (showProgram prog)
  write !(getTTCFileName source "mlir") mlir
  pure (Just (!(getObjFileName source "mlir"), []))

compileProgram : Ref Ctxt Defs -> Ref Syn SyntaxInfo ->
                 String -> String -> ClosedTerm -> String -> Core (Maybe String)
compileProgram _ _ _ _ _ _ =
  throw (GenericMsg EmptyFC
    "mlir backend: whole-program compilation (-o) needs IO lowering, which is not implemented; use --inc mlir --check")

executeProgram : Ref Ctxt Defs -> Ref Syn SyntaxInfo ->
                 String -> ClosedTerm -> Core ()
executeProgram _ _ _ _ = throw (GenericMsg EmptyFC "mlir backend: execution is not implemented")

backend : Codegen
backend = MkCG compileProgram executeProgram (Just compileModule) (Just "mlir")

main : IO ()
main = mainWithCodegens [("mlir", backend)]
