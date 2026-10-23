module Main

-- A Double's function of the C library and a Double's text mean what the
-- program computes on its target: the last digit of `exp`, `log`, `pow`,
-- `sin` and the rest is each library's, and the runtime's text of a
-- Double agrees with the stock host's only because the runtime was written
-- to match it. The type checker's evaluator computed both by the host that
-- runs the compiler. It now leaves them applied, as it leaves any
-- primitive it cannot fold. Each type below reaches them on both its
-- sides, whose arguments are written two ways, so the sides are one term
-- only once the arguments are evaluated, each to the primitive applied to
-- one constant, left applied: the types check that such a side converts
-- with the other. A type reaches the text through `cast`, since `show` of
-- a Double reaches it through a private function of the Prelude, which no
-- type here unfolds. The run prints e and 0.1 as the program computes
-- them.

import Prelude

%default total

0 exponential : exp 1.0 = exp (0.5 + 0.5)
exponential = Refl

0 text : cast {to = String} 0.1 = cast {to = String} (1.0 / 10.0)
text = Refl

main : IO ()
main = do
  printLn (exp 1.0)
  putStrLn (show 0.1)
