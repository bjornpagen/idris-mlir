module IdrisMLIR.Frontend.Inspect

import Compiler.Common
import Core.Context
import Core.Directory
import Idris.Syntax
import Libraries.Data.NameMap

import Data.List
import Data.String
import System.File

%default covering

-- A diagnostic summary of checked TT, not a typed IR. Reads definitions
-- through Defs; never through getIncCompileData/CExp.
signatureQuantities : Term vars -> List String
signatureQuantities (Bind _ _ (Pi _ quantity _ _) body) =
  show quantity :: signatureQuantities body
signatureQuantities _ = []

typeAvailable : Term vars -> Bool
typeAvailable (Erased _ _) = False
typeAvailable _ = True

definitionKind : Def -> String
definitionKind (PMDef _ _ _ _ _) = "function"
definitionKind (DCon _ _ _) = "constructor"
definitionKind (TCon _ _ _ _ _ _ _) = "type-constructor"
definitionKind (ForeignDef _ _) = "foreign"
definitionKind (Builtin _) = "builtin"
definitionKind _ = "other"

describe : {auto c : Ref Ctxt Defs} -> Name -> Core String
describe name = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact name (gamma defs)
    | Nothing => throw (InternalError "Cannot inspect missing definition")
  let count = case definition def of
        PMDef _ _ _ _ patterns => length patterns
        _ => 0
  pure $ concat $ the (List String)
    [ "definition\t", show (fullname def)
    , "\tkind=", definitionKind (definition def)
    , "\ttype=", if typeAvailable (type def) then "present" else "unavailable"
    , "\tquantities=", joinBy "," (signatureQuantities (type def))
    , "\tclauses=", show count
    ]

inspectModule : Ref Ctxt Defs -> Ref Syn SyntaxInfo ->
                String -> Core (Maybe (String, List String))
inspectModule c s sourceFile = do
  defs <- get Ctxt
  rows <- traverse describe (keys (toIR defs))
  path <- getTTCFileName sourceFile "ttsummary"
  objectName <- getObjFileName sourceFile "ttsummary"
  let summary = unlines ("idris-mlir-tt-summary\t1" :: sort rows)
  Right () <- coreLift $ writeFile path summary
    | Left err => throw (FileErr path err)
  pure (Just (objectName, []))

compileUnsupported : Ref Ctxt Defs -> Ref Syn SyntaxInfo ->
                     String -> String -> ClosedTerm -> String ->
                     Core (Maybe String)
compileUnsupported _ _ _ _ _ _ =
  throw (GenericMsg EmptyFC
    "core-inspect only writes .ttsummary files; MLIR output is not implemented. Use --inc core-inspect --check")

executeUnsupported : Ref Ctxt Defs -> Ref Syn SyntaxInfo ->
                     String -> ClosedTerm -> Core ()
executeUnsupported _ _ _ _ =
  throw (GenericMsg EmptyFC "core-inspect does not execute programs")

export
inspector : Codegen
inspector = MkCG compileUnsupported executeUnsupported
                (Just inspectModule) (Just "ttsummary")
