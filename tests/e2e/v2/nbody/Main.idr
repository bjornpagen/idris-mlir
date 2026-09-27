module Main

-- rule: FE-TR-6, SEM-DBL-2, ELIM-G-19
-- The n-body benchmark of the Computer Language Benchmarks Game: five
-- bodies, immutable records, one function per pair interaction. Record
-- updates put implementations under a `let` (FE-TR-6, zeta).

import Arith

%default partial

record Body where
  constructor MkBody
  px : Double
  py : Double
  pz : Double
  vx : Double
  vy : Double
  vz : Double
  mass : Double

record System where
  constructor MkSystem
  b0 : Body
  b1 : Body
  b2 : Body
  b3 : Body
  b4 : Body

pi : Double
pi = 3.141592653589793

solarMass : Double
solarMass = 4.0 * pi * pi

daysPerYear : Double
daysPerYear = 365.24

body : Double -> Double -> Double -> Double -> Double -> Double -> Double -> Body
body x y z vx vy vz m =
  MkBody x y z (vx * daysPerYear) (vy * daysPerYear) (vz * daysPerYear) (m * solarMass)

initial : System
initial = MkSystem
  (MkBody 0.0 0.0 0.0 0.0 0.0 0.0 solarMass)
  (body 4.84143144246472090e+00 (-1.16032004402742839e+00) (-1.03622044471123109e-01)
        1.66007664274403694e-03 7.69901118419740425e-03 (-6.90460016972063023e-05)
        9.54791938424326609e-04)
  (body 8.34336671824457987e+00 4.12479856412430479e+00 (-4.03523417114321381e-01)
        (-2.76742510726862411e-03) 4.99852801234917238e-03 2.30417297573763929e-05
        2.85885980666130812e-04)
  (body 1.28943695621391310e+01 (-1.51111514016986312e+01) (-2.23307578892655734e-01)
        2.96460137564761618e-03 2.37847173959480950e-03 (-2.96589568540237556e-05)
        4.36624404335156298e-05)
  (body 1.53796971148509165e+01 (-2.59193146099879641e+01) 1.79258772950371181e-01
        2.68067772490389322e-03 1.62824170038242295e-03 (-9.51592254519715870e-05)
        5.15138902046611451e-05)

momentum : Body -> (Double, Double, Double) -> (Double, Double, Double)
momentum b (x, y, z) = (x + vx b * mass b, y + vy b * mass b, z + vz b * mass b)

offset : System -> System
offset s@(MkSystem sun a b c d) =
  let (x, (y, z)) = momentum a (momentum b (momentum c (momentum d (momentum sun (0.0, 0.0, 0.0)))))
  in MkSystem ({ vx := negate x / solarMass, vy := negate y / solarMass, vz := negate z / solarMass } sun) a b c d

interact : Double -> Body -> Body -> (Body, Body)
interact dt a b =
  let dx = px a - px b
      dy = py a - py b
      dz = pz a - pz b
      d2 = dx * dx + dy * dy + dz * dz
      mag = dt / (d2 * sqrt d2)
      ma = mass a * mag
      mb = mass b * mag
  in ( { vx := vx a - dx * mb, vy := vy a - dy * mb, vz := vz a - dz * mb } a
     , { vx := vx b + dx * ma, vy := vy b + dy * ma, vz := vz b + dz * ma } b )

move : Double -> Body -> Body
move dt b = { px := px b + dt * vx b, py := py b + dt * vy b, pz := pz b + dt * vz b } b

advance : Double -> System -> System
advance dt (MkSystem a b c d e) =
  let (a1, b1) = interact dt a b
      (a2, c1) = interact dt a1 c
      (a3, d1) = interact dt a2 d
      (a4, e1) = interact dt a3 e
      (b2, c2) = interact dt b1 c1
      (b3, d2) = interact dt b2 d1
      (b4, e2) = interact dt b3 e1
      (c3, d3) = interact dt c2 d2
      (c4, e3) = interact dt c3 e2
      (d4, e4) = interact dt d3 e3
  in MkSystem (move dt a4) (move dt b4) (move dt c4) (move dt d4) (move dt e4)

kinetic : Body -> Double
kinetic b = 0.5 * mass b * (vx b * vx b + vy b * vy b + vz b * vz b)

potential : Body -> Body -> Double
potential a b =
  let dx = px a - px b
      dy = py a - py b
      dz = pz a - pz b
  in mass a * mass b / sqrt (dx * dx + dy * dy + dz * dz)

energy : System -> Double
energy (MkSystem a b c d e) =
  kinetic a + kinetic b + kinetic c + kinetic d + kinetic e
  - potential a b - potential a c - potential a d - potential a e
  - potential b c - potential b d - potential b e
  - potential c d - potential c e - potential d e

run : Int -> System -> System
run 0 s = s
run n s = run (n - 1) (advance 0.01 s)

main : IO ()
main = do
  n <- readInt
  let s = offset initial
  printDouble (energy s)
  printDouble (energy (run n s))
