-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Idris.CommandLine

import Core.Options

import Control.WellFounded
import Data.Maybe
import Data.Nat
import Data.String
import Libraries.Utils.String
import Data.Either

%default total

public export
data PkgCommand
      = Build
      | Install
      | Typecheck
      | Clean

export
Show PkgCommand where
  show Build = "--build"
  show Install = "--install"
  show Typecheck = "--typecheck"
  show Clean = "--clean"

||| The options a package's `opts` field may give, which is where the
||| checker reads options: the frontend parses its own command line.
public export
data CLOpt
  =
   ||| Don't implicitly import Prelude
  NoPrelude |
   ||| Set source directory
  SourceDir String |
   ||| Set build directory
  BuildDir String |
   ||| Set output directory
  OutputDir String |
   ||| Set the log level globally
  Logging LogLevel |
   ||| Add a package as a dependency
  PkgPath String |
  IgnoreMissingIPKG |
  Timing (Maybe Nat) |
   ||| Treat warnings as errors
  WarningsAsErrors |
   ||| Do not print shadowing warnings
  IgnoreShadowingWarnings |
   ||| Turn on %default total globally
  Total

||| An option's argument, if it takes one, with what the option means given
||| the argument's value: every option takes at most one. Each case names
||| the type of the value its action is given, so no type is computed from a
||| description of the arguments.
data OptArg
  = NoArg (List CLOpt)
   | Required String (String -> List CLOpt)
   | AutoNat String (Maybe Nat -> List CLOpt)
   | RequiredLogLevel String (LogLevel -> List CLOpt)

||| How an error shows an option's argument.
showArg : OptArg -> String
showArg (NoArg _) = ""
showArg (Required a _) = "<" ++ a ++ ">"
showArg (RequiredLogLevel a _) = "<" ++ a ++ ">"
showArg (AutoNat a _) = "<" ++ a ++ ">"

record OptDesc where
  constructor MkOpt
  flags : List String
  arg : OptArg

options : List OptDesc
options = [MkOpt ["--no-prelude"] (NoArg [NoPrelude]),
           MkOpt ["--package", "-p"] (Required "package" (\f => [PkgPath f])),
           MkOpt ["--source-dir"] (Required "dir" (\d => [SourceDir d])),
           MkOpt ["--build-dir"] (Required "dir" (\d => [BuildDir d])),
           MkOpt ["--output-dir"] (Required "dir" (\d => [OutputDir d])),
           MkOpt ["--total"] (NoArg [Total]),
           MkOpt ["-Werror"] (NoArg [WarningsAsErrors]),
           MkOpt ["-Wno-shadowing"] (NoArg [IgnoreShadowingWarnings]),
           MkOpt ["--ignore-missing-ipkg"] (NoArg [IgnoreMissingIPKG]),
           MkOpt ["--timing"] (AutoNat "level" (\ n => [Timing n])),
           MkOpt ["--log"] (RequiredLogLevel "log level" (\l => [Logging l]))
           ]

checkNat : Integer -> Maybe Nat
checkNat n = toMaybe (n >= 0) (integerToNat n)

-- What an option leaves of the arguments after its flag: never more than
-- there were.
record Rest (args : List String) where
  constructor MkRest
  rest : List String
  0 noLonger : Nat.LTE (length rest) (length args)

processArgs : String -> OptArg -> (xs : List String) ->
              Either String (List CLOpt, Rest xs)
processArgs flag (NoArg f) xs = Right (f, MkRest xs reflexive)
-- Missing required arguments
processArgs flag opt [] =
  Left $ "Missing required argument " ++ showArg opt ++ " for flag " ++ flag
-- Happy cases
processArgs flag (RequiredLogLevel a f) (x :: xs) =
  do arg <- maybeToEither ("Expected LogLevel argument " ++ show x ++ " for flag " ++ flag)
                          (parseLogLevel x)
     Right (f arg, MkRest xs (lteSuccRight reflexive))
processArgs flag (AutoNat a f) ("auto" :: xs) = Right (f Nothing, MkRest xs (lteSuccRight reflexive))
processArgs flag (AutoNat a f) (x :: xs) =
  do arg <- maybeToEither ("Expected Nat or \"auto\" argument " ++ show x ++ " for flag " ++ flag)
                          (parseSigned x >>= checkNat)
     Right (f (Just arg), MkRest xs (lteSuccRight reflexive))
processArgs flag (Required a f) (x :: xs) = Right (f x, MkRest xs (lteSuccRight reflexive))

-- The argument matched is given apart from those after it: there is always
-- one, since the loop over the arguments stops when none are left.
matchFlag : (d : OptDesc) -> (x : String) -> (xs : List String) ->
            Either String (Maybe (List CLOpt, Rest xs))
matchFlag d x xs
    = if x `elem` flags d
         then do args <- processArgs x (arg d) xs
                 Right (Just args)
         else Right Nothing

findMatch : List OptDesc -> (x : String) -> (xs : List String) ->
            Either String (List CLOpt, Rest xs)
-- A package's options are flags and their arguments, and name no file.
findMatch [] f args = Left "Unknown flag \{f}"
findMatch (d :: ds) x xs
    = case !(matchFlag d x xs) of
           Nothing => findMatch ds x xs
           Just res => Right res

-- Each option takes at least its flag from the arguments, so fewer are left
-- after it, which `acc` bounds.
parseOpts : List OptDesc -> (args : List String) ->
            (0 acc : Accessible Nat.LT (length args)) -> Either String (List CLOpt)
parseOpts opts [] _ = Right []
parseOpts opts (x :: xs) (Access rec)
   = do (cl, MkRest rest le) <- findMatch opts x xs
        cls <- parseOpts opts rest (rec (length rest) (LTESucc le))
        pure (cl ++ cls)

export
getOpts : List String -> Either String (List CLOpt)
getOpts opts = parseOpts options opts (wellFounded (length opts))
