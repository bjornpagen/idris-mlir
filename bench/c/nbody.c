#include <stdio.h>
static long readInt(void) { long n = 0; int c; while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0'); return n; }
#include <math.h>
/* The same algorithm as bench/nbody/Main.idr, with mutable arrays: the
   usual C baseline. */
typedef struct { double x, y, z, vx, vy, vz, m; } body;
#define PI 3.141592653589793
#define SM (4 * PI * PI)
#define DPY 365.24
static body bs[5] = {
  {0, 0, 0, 0, 0, 0, SM},
  {4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01, 1.66007664274403694e-03 * DPY, 7.69901118419740425e-03 * DPY, -6.90460016972063023e-05 * DPY, 9.54791938424326609e-04 * SM},
  {8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01, -2.76742510726862411e-03 * DPY, 4.99852801234917238e-03 * DPY, 2.30417297573763929e-05 * DPY, 2.85885980666130812e-04 * SM},
  {1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01, 2.96460137564761618e-03 * DPY, 2.37847173959480950e-03 * DPY, -2.96589568540237556e-05 * DPY, 4.36624404335156298e-05 * SM},
  {1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01, 2.68067772490389322e-03 * DPY, 1.62824170038242295e-03 * DPY, -9.51592254519715870e-05 * DPY, 5.15138902046611451e-05 * SM}};
static double energy(void) {
  double e = 0;
  for (int i = 0; i < 5; i++) e += 0.5 * bs[i].m * (bs[i].vx * bs[i].vx + bs[i].vy * bs[i].vy + bs[i].vz * bs[i].vz);
  for (int i = 0; i < 5; i++) for (int j = i + 1; j < 5; j++) { double dx = bs[i].x - bs[j].x, dy = bs[i].y - bs[j].y, dz = bs[i].z - bs[j].z; e -= bs[i].m * bs[j].m / sqrt(dx * dx + dy * dy + dz * dz); }
  return e; }
int main(void) {
  long n = readInt();
  double px = 0, py = 0, pz = 0;
  for (int i = 0; i < 5; i++) { px += bs[i].vx * bs[i].m; py += bs[i].vy * bs[i].m; pz += bs[i].vz * bs[i].m; }
  bs[0].vx = -px / SM; bs[0].vy = -py / SM; bs[0].vz = -pz / SM;
  printf("%.17g\n", energy());
  for (long k = 0; k < n; k++) {
    for (int i = 0; i < 5; i++) for (int j = i + 1; j < 5; j++) {
      double dx = bs[i].x - bs[j].x, dy = bs[i].y - bs[j].y, dz = bs[i].z - bs[j].z;
      double d2 = dx * dx + dy * dy + dz * dz, mag = 0.01 / (d2 * sqrt(d2));
      double mi = bs[i].m * mag, mj = bs[j].m * mag;
      bs[i].vx -= dx * mj; bs[i].vy -= dy * mj; bs[i].vz -= dz * mj;
      bs[j].vx += dx * mi; bs[j].vy += dy * mi; bs[j].vz += dz * mi; }
    for (int i = 0; i < 5; i++) { bs[i].x += 0.01 * bs[i].vx; bs[i].y += 0.01 * bs[i].vy; bs[i].z += 0.01 * bs[i].vz; } }
  printf("%.17g\n", energy()); return 0; }
