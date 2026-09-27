(* The same algorithm as bench/nbody/Main.idr: immutable records. *)
type body = {px : real, py : real, pz : real, vx : real, vy : real, vz : real, mass : real}
val pi = 3.141592653589793
val solarMass = 4.0 * pi * pi
val daysPerYear = 365.24
fun body (x, y, z, vx, vy, vz, m) : body =
  {px = x, py = y, pz = z, vx = vx * daysPerYear, vy = vy * daysPerYear, vz = vz * daysPerYear,
   mass = m * solarMass}
val initial =
  ({px = 0.0, py = 0.0, pz = 0.0, vx = 0.0, vy = 0.0, vz = 0.0, mass = solarMass},
   body (4.84143144246472090e0, ~1.16032004402742839e0, ~1.03622044471123109e~01,
         1.66007664274403694e~03, 7.69901118419740425e~03, ~6.90460016972063023e~05,
         9.54791938424326609e~04),
   body (8.34336671824457987e0, 4.12479856412430479e0, ~4.03523417114321381e~01,
         ~2.76742510726862411e~03, 4.99852801234917238e~03, 2.30417297573763929e~05,
         2.85885980666130812e~04),
   body (1.28943695621391310e1, ~1.51111514016986312e1, ~2.23307578892655734e~01,
         2.96460137564761618e~03, 2.37847173959480950e~03, ~2.96589568540237556e~05,
         4.36624404335156298e~05),
   body (1.53796971148509165e1, ~2.59193146099879641e1, 1.79258772950371181e~01,
         2.68067772490389322e~03, 1.62824170038242295e~03, ~9.51592254519715870e~05,
         5.15138902046611451e~05))
fun momentum (b : body, (x, y, z)) = (x + #vx b * #mass b, y + #vy b * #mass b, z + #vz b * #mass b)
fun offset (sun : body, a, b, c, d) =
  let val (x, y, z) = momentum (a, momentum (b, momentum (c, momentum (d, momentum (sun, (0.0, 0.0, 0.0))))))
  in ({px = #px sun, py = #py sun, pz = #pz sun, vx = ~x / solarMass, vy = ~y / solarMass,
       vz = ~z / solarMass, mass = #mass sun}, a, b, c, d) end
fun interact (dt, a : body, b : body) =
  let val dx = #px a - #px b val dy = #py a - #py b val dz = #pz a - #pz b
      val d2 = dx * dx + dy * dy + dz * dz
      val mag = dt / (d2 * Math.sqrt d2)
      val ma = #mass a * mag val mb = #mass b * mag
  in ({px = #px a, py = #py a, pz = #pz a, vx = #vx a - dx * mb, vy = #vy a - dy * mb,
       vz = #vz a - dz * mb, mass = #mass a},
      {px = #px b, py = #py b, pz = #pz b, vx = #vx b + dx * ma, vy = #vy b + dy * ma,
       vz = #vz b + dz * ma, mass = #mass b}) end
fun move (dt, b : body) : body =
  {px = #px b + dt * #vx b, py = #py b + dt * #vy b, pz = #pz b + dt * #vz b,
   vx = #vx b, vy = #vy b, vz = #vz b, mass = #mass b}
fun advance (dt, (a, b, c, d, e)) =
  let val (a1, b1) = interact (dt, a, b)
      val (a2, c1) = interact (dt, a1, c)
      val (a3, d1) = interact (dt, a2, d)
      val (a4, e1) = interact (dt, a3, e)
      val (b2, c2) = interact (dt, b1, c1)
      val (b3, d2) = interact (dt, b2, d1)
      val (b4, e2) = interact (dt, b3, e1)
      val (c3, d3) = interact (dt, c2, d2)
      val (c4, e3) = interact (dt, c3, e2)
      val (d4, e4) = interact (dt, d3, e3)
  in (move (dt, a4), move (dt, b4), move (dt, c4), move (dt, d4), move (dt, e4)) end
fun kinetic (b : body) = 0.5 * #mass b * (#vx b * #vx b + #vy b * #vy b + #vz b * #vz b)
fun potential (a : body, b : body) =
  let val dx = #px a - #px b val dy = #py a - #py b val dz = #pz a - #pz b
  in #mass a * #mass b / Math.sqrt (dx * dx + dy * dy + dz * dz) end
fun energy (a, b, c, d, e) =
  kinetic a + kinetic b + kinetic c + kinetic d + kinetic e
  - potential (a, b) - potential (a, c) - potential (a, d) - potential (a, e)
  - potential (b, c) - potential (b, d) - potential (b, e)
  - potential (c, d) - potential (c, e) - potential (d, e)
fun run (0, s) = s
  | run (n, s) = run (n - 1, advance (0.01, s))
val () =
  let val n = readInt ()
      val s = offset initial
      fun show x = print (Real.fmt (StringCvt.GEN (SOME 17)) x ^ "\n")
  in show (energy s); show (energy (run (n, s))) end
