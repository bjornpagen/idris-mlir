module Main

-- Every run-time export of Prelude.Interpolation, each used (covers):
-- interpolate at both implementations the module provides, String (the
-- identity) and Void (used where a Void cannot arrive), called by name and
-- through the interpolated strings it desugars, "a \{x} b" being
-- concat [interpolate "a ", interpolate x, interpolate " b"]; and at a
-- program's own types, one implementation declared and one built with
-- MkInterpolation, nested in one another's strings. The interface's
-- constructor is compile-time only. Each line is printed so that Chez
-- checks what it computes.

import Prelude

data Colour = Red | Green | Blue

Interpolation Colour where
  interpolate Red = "red"
  interpolate Green = "green"
  interpolate Blue = "blue"

record Swatch where
  constructor MkSwatch
  colour : Colour
  name : String

-- A Swatch interpolates through its parts' interpolations.
swatchInterpolation : Interpolation Swatch
swatchInterpolation = MkInterpolation (\s => "\{name s} (\{colour s})")

-- Interpolation Void, reached only in a branch no value takes.
noVoid : Either Void String -> String
noVoid (Left v) = "never \{v}"
noVoid (Right s) = "\{s}!"

voidOrString : Either Void String -> String
voidOrString = either interpolate interpolate

main : IO ()
main = do
  let who = "world"
  putStrLn (interpolate "plain")
  putStrLn (interpolate "")
  putStrLn "hello, \{who}"
  putStrLn "\{who}\{who}"
  putStrLn "nested \{"<\{who}>"} and empty \{""} end"
  putStrLn "escapes \{"tab\there"} \\{not interpolated}"
  putStrLn "\{Red}, \{Green} and \{Blue}"
  putStrLn (interpolate Blue)
  putStrLn (interpolate @{swatchInterpolation} (MkSwatch Green "moss"))
  putStrLn "swatch: \{interpolate @{swatchInterpolation} (MkSwatch Red "brick \{who}")}"
  putStrLn (noVoid (Right "void kept out"))
  putStrLn (voidOrString (Right "either"))
  putStrLn (concat (map (\c => "[\{c}]") [Red, Blue, Green]))
