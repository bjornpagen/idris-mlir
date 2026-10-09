module Idris.Env

--- All environment variables accessed by the compiler are enumerated in this module.

import public Data.List
import public Data.Maybe

import System

%default total

||| Environment variable used by Idris2 compiler
public export
record EnvDesc where
  constructor MkEnvDesc
  name : String
  help : String

||| All environment variables used by Idris2 compiler
public export
envs : List EnvDesc
envs = [
    MkEnvDesc "IDRIS2_PREFIX"        "Idris2 installation prefix.",
    MkEnvDesc "IDRIS2_PATH"          "Directories where Idris2 looks for import files.",
    MkEnvDesc "IDRIS2_PACKAGE_PATH"  "Directories where Idris2 looks for Idris 2 packages.",
    MkEnvDesc "IDRIS2_DATA"          "Directories where Idris2 looks for data files.",
    MkEnvDesc "IDRIS2_LIBS"          "Directories where Idris2 looks for libraries (for code generation).",
    MkEnvDesc "PATH"                 "PATH variable is used to search for executables.",
    MkEnvDesc "NO_COLOR"             "Instruct Idris not to print color to stdout. Passing the --color/--colour option will supersede this env var."]

--- `public export` only for `auto` to work in `idrisGetEnv`
public export
envNames : List String
envNames = map (.name) envs

||| Query documented environment variable
public export
idrisGetEnv : HasIO io => (name : String) ->
  {auto 0 known : IsJust (find (name ==) Env.envNames)}
  -> io (Maybe String)
idrisGetEnv name = getEnv name
