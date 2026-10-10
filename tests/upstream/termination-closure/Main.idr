module Main

-- A chain of 240 covering functions with no loop, each matching its first
-- argument and calling one of the next two with its arguments permuted,
-- and 25 total functions that call the first: each total function's check
-- reaches the whole chain. The pinned Idris closes the size-change graphs
-- over every path of the chain, for each of the 25 again; the fork closes
-- over the calls inside components, of which the chain has none, and
-- settles the chain at the first.

%default covering

f0 : Nat -> Nat -> Nat -> Nat
f1 : Nat -> Nat -> Nat -> Nat
f2 : Nat -> Nat -> Nat -> Nat
f3 : Nat -> Nat -> Nat -> Nat
f4 : Nat -> Nat -> Nat -> Nat
f5 : Nat -> Nat -> Nat -> Nat
f6 : Nat -> Nat -> Nat -> Nat
f7 : Nat -> Nat -> Nat -> Nat
f8 : Nat -> Nat -> Nat -> Nat
f9 : Nat -> Nat -> Nat -> Nat
f10 : Nat -> Nat -> Nat -> Nat
f11 : Nat -> Nat -> Nat -> Nat
f12 : Nat -> Nat -> Nat -> Nat
f13 : Nat -> Nat -> Nat -> Nat
f14 : Nat -> Nat -> Nat -> Nat
f15 : Nat -> Nat -> Nat -> Nat
f16 : Nat -> Nat -> Nat -> Nat
f17 : Nat -> Nat -> Nat -> Nat
f18 : Nat -> Nat -> Nat -> Nat
f19 : Nat -> Nat -> Nat -> Nat
f20 : Nat -> Nat -> Nat -> Nat
f21 : Nat -> Nat -> Nat -> Nat
f22 : Nat -> Nat -> Nat -> Nat
f23 : Nat -> Nat -> Nat -> Nat
f24 : Nat -> Nat -> Nat -> Nat
f25 : Nat -> Nat -> Nat -> Nat
f26 : Nat -> Nat -> Nat -> Nat
f27 : Nat -> Nat -> Nat -> Nat
f28 : Nat -> Nat -> Nat -> Nat
f29 : Nat -> Nat -> Nat -> Nat
f30 : Nat -> Nat -> Nat -> Nat
f31 : Nat -> Nat -> Nat -> Nat
f32 : Nat -> Nat -> Nat -> Nat
f33 : Nat -> Nat -> Nat -> Nat
f34 : Nat -> Nat -> Nat -> Nat
f35 : Nat -> Nat -> Nat -> Nat
f36 : Nat -> Nat -> Nat -> Nat
f37 : Nat -> Nat -> Nat -> Nat
f38 : Nat -> Nat -> Nat -> Nat
f39 : Nat -> Nat -> Nat -> Nat
f40 : Nat -> Nat -> Nat -> Nat
f41 : Nat -> Nat -> Nat -> Nat
f42 : Nat -> Nat -> Nat -> Nat
f43 : Nat -> Nat -> Nat -> Nat
f44 : Nat -> Nat -> Nat -> Nat
f45 : Nat -> Nat -> Nat -> Nat
f46 : Nat -> Nat -> Nat -> Nat
f47 : Nat -> Nat -> Nat -> Nat
f48 : Nat -> Nat -> Nat -> Nat
f49 : Nat -> Nat -> Nat -> Nat
f50 : Nat -> Nat -> Nat -> Nat
f51 : Nat -> Nat -> Nat -> Nat
f52 : Nat -> Nat -> Nat -> Nat
f53 : Nat -> Nat -> Nat -> Nat
f54 : Nat -> Nat -> Nat -> Nat
f55 : Nat -> Nat -> Nat -> Nat
f56 : Nat -> Nat -> Nat -> Nat
f57 : Nat -> Nat -> Nat -> Nat
f58 : Nat -> Nat -> Nat -> Nat
f59 : Nat -> Nat -> Nat -> Nat
f60 : Nat -> Nat -> Nat -> Nat
f61 : Nat -> Nat -> Nat -> Nat
f62 : Nat -> Nat -> Nat -> Nat
f63 : Nat -> Nat -> Nat -> Nat
f64 : Nat -> Nat -> Nat -> Nat
f65 : Nat -> Nat -> Nat -> Nat
f66 : Nat -> Nat -> Nat -> Nat
f67 : Nat -> Nat -> Nat -> Nat
f68 : Nat -> Nat -> Nat -> Nat
f69 : Nat -> Nat -> Nat -> Nat
f70 : Nat -> Nat -> Nat -> Nat
f71 : Nat -> Nat -> Nat -> Nat
f72 : Nat -> Nat -> Nat -> Nat
f73 : Nat -> Nat -> Nat -> Nat
f74 : Nat -> Nat -> Nat -> Nat
f75 : Nat -> Nat -> Nat -> Nat
f76 : Nat -> Nat -> Nat -> Nat
f77 : Nat -> Nat -> Nat -> Nat
f78 : Nat -> Nat -> Nat -> Nat
f79 : Nat -> Nat -> Nat -> Nat
f80 : Nat -> Nat -> Nat -> Nat
f81 : Nat -> Nat -> Nat -> Nat
f82 : Nat -> Nat -> Nat -> Nat
f83 : Nat -> Nat -> Nat -> Nat
f84 : Nat -> Nat -> Nat -> Nat
f85 : Nat -> Nat -> Nat -> Nat
f86 : Nat -> Nat -> Nat -> Nat
f87 : Nat -> Nat -> Nat -> Nat
f88 : Nat -> Nat -> Nat -> Nat
f89 : Nat -> Nat -> Nat -> Nat
f90 : Nat -> Nat -> Nat -> Nat
f91 : Nat -> Nat -> Nat -> Nat
f92 : Nat -> Nat -> Nat -> Nat
f93 : Nat -> Nat -> Nat -> Nat
f94 : Nat -> Nat -> Nat -> Nat
f95 : Nat -> Nat -> Nat -> Nat
f96 : Nat -> Nat -> Nat -> Nat
f97 : Nat -> Nat -> Nat -> Nat
f98 : Nat -> Nat -> Nat -> Nat
f99 : Nat -> Nat -> Nat -> Nat
f100 : Nat -> Nat -> Nat -> Nat
f101 : Nat -> Nat -> Nat -> Nat
f102 : Nat -> Nat -> Nat -> Nat
f103 : Nat -> Nat -> Nat -> Nat
f104 : Nat -> Nat -> Nat -> Nat
f105 : Nat -> Nat -> Nat -> Nat
f106 : Nat -> Nat -> Nat -> Nat
f107 : Nat -> Nat -> Nat -> Nat
f108 : Nat -> Nat -> Nat -> Nat
f109 : Nat -> Nat -> Nat -> Nat
f110 : Nat -> Nat -> Nat -> Nat
f111 : Nat -> Nat -> Nat -> Nat
f112 : Nat -> Nat -> Nat -> Nat
f113 : Nat -> Nat -> Nat -> Nat
f114 : Nat -> Nat -> Nat -> Nat
f115 : Nat -> Nat -> Nat -> Nat
f116 : Nat -> Nat -> Nat -> Nat
f117 : Nat -> Nat -> Nat -> Nat
f118 : Nat -> Nat -> Nat -> Nat
f119 : Nat -> Nat -> Nat -> Nat
f120 : Nat -> Nat -> Nat -> Nat
f121 : Nat -> Nat -> Nat -> Nat
f122 : Nat -> Nat -> Nat -> Nat
f123 : Nat -> Nat -> Nat -> Nat
f124 : Nat -> Nat -> Nat -> Nat
f125 : Nat -> Nat -> Nat -> Nat
f126 : Nat -> Nat -> Nat -> Nat
f127 : Nat -> Nat -> Nat -> Nat
f128 : Nat -> Nat -> Nat -> Nat
f129 : Nat -> Nat -> Nat -> Nat
f130 : Nat -> Nat -> Nat -> Nat
f131 : Nat -> Nat -> Nat -> Nat
f132 : Nat -> Nat -> Nat -> Nat
f133 : Nat -> Nat -> Nat -> Nat
f134 : Nat -> Nat -> Nat -> Nat
f135 : Nat -> Nat -> Nat -> Nat
f136 : Nat -> Nat -> Nat -> Nat
f137 : Nat -> Nat -> Nat -> Nat
f138 : Nat -> Nat -> Nat -> Nat
f139 : Nat -> Nat -> Nat -> Nat
f140 : Nat -> Nat -> Nat -> Nat
f141 : Nat -> Nat -> Nat -> Nat
f142 : Nat -> Nat -> Nat -> Nat
f143 : Nat -> Nat -> Nat -> Nat
f144 : Nat -> Nat -> Nat -> Nat
f145 : Nat -> Nat -> Nat -> Nat
f146 : Nat -> Nat -> Nat -> Nat
f147 : Nat -> Nat -> Nat -> Nat
f148 : Nat -> Nat -> Nat -> Nat
f149 : Nat -> Nat -> Nat -> Nat
f150 : Nat -> Nat -> Nat -> Nat
f151 : Nat -> Nat -> Nat -> Nat
f152 : Nat -> Nat -> Nat -> Nat
f153 : Nat -> Nat -> Nat -> Nat
f154 : Nat -> Nat -> Nat -> Nat
f155 : Nat -> Nat -> Nat -> Nat
f156 : Nat -> Nat -> Nat -> Nat
f157 : Nat -> Nat -> Nat -> Nat
f158 : Nat -> Nat -> Nat -> Nat
f159 : Nat -> Nat -> Nat -> Nat
f160 : Nat -> Nat -> Nat -> Nat
f161 : Nat -> Nat -> Nat -> Nat
f162 : Nat -> Nat -> Nat -> Nat
f163 : Nat -> Nat -> Nat -> Nat
f164 : Nat -> Nat -> Nat -> Nat
f165 : Nat -> Nat -> Nat -> Nat
f166 : Nat -> Nat -> Nat -> Nat
f167 : Nat -> Nat -> Nat -> Nat
f168 : Nat -> Nat -> Nat -> Nat
f169 : Nat -> Nat -> Nat -> Nat
f170 : Nat -> Nat -> Nat -> Nat
f171 : Nat -> Nat -> Nat -> Nat
f172 : Nat -> Nat -> Nat -> Nat
f173 : Nat -> Nat -> Nat -> Nat
f174 : Nat -> Nat -> Nat -> Nat
f175 : Nat -> Nat -> Nat -> Nat
f176 : Nat -> Nat -> Nat -> Nat
f177 : Nat -> Nat -> Nat -> Nat
f178 : Nat -> Nat -> Nat -> Nat
f179 : Nat -> Nat -> Nat -> Nat
f180 : Nat -> Nat -> Nat -> Nat
f181 : Nat -> Nat -> Nat -> Nat
f182 : Nat -> Nat -> Nat -> Nat
f183 : Nat -> Nat -> Nat -> Nat
f184 : Nat -> Nat -> Nat -> Nat
f185 : Nat -> Nat -> Nat -> Nat
f186 : Nat -> Nat -> Nat -> Nat
f187 : Nat -> Nat -> Nat -> Nat
f188 : Nat -> Nat -> Nat -> Nat
f189 : Nat -> Nat -> Nat -> Nat
f190 : Nat -> Nat -> Nat -> Nat
f191 : Nat -> Nat -> Nat -> Nat
f192 : Nat -> Nat -> Nat -> Nat
f193 : Nat -> Nat -> Nat -> Nat
f194 : Nat -> Nat -> Nat -> Nat
f195 : Nat -> Nat -> Nat -> Nat
f196 : Nat -> Nat -> Nat -> Nat
f197 : Nat -> Nat -> Nat -> Nat
f198 : Nat -> Nat -> Nat -> Nat
f199 : Nat -> Nat -> Nat -> Nat
f200 : Nat -> Nat -> Nat -> Nat
f201 : Nat -> Nat -> Nat -> Nat
f202 : Nat -> Nat -> Nat -> Nat
f203 : Nat -> Nat -> Nat -> Nat
f204 : Nat -> Nat -> Nat -> Nat
f205 : Nat -> Nat -> Nat -> Nat
f206 : Nat -> Nat -> Nat -> Nat
f207 : Nat -> Nat -> Nat -> Nat
f208 : Nat -> Nat -> Nat -> Nat
f209 : Nat -> Nat -> Nat -> Nat
f210 : Nat -> Nat -> Nat -> Nat
f211 : Nat -> Nat -> Nat -> Nat
f212 : Nat -> Nat -> Nat -> Nat
f213 : Nat -> Nat -> Nat -> Nat
f214 : Nat -> Nat -> Nat -> Nat
f215 : Nat -> Nat -> Nat -> Nat
f216 : Nat -> Nat -> Nat -> Nat
f217 : Nat -> Nat -> Nat -> Nat
f218 : Nat -> Nat -> Nat -> Nat
f219 : Nat -> Nat -> Nat -> Nat
f220 : Nat -> Nat -> Nat -> Nat
f221 : Nat -> Nat -> Nat -> Nat
f222 : Nat -> Nat -> Nat -> Nat
f223 : Nat -> Nat -> Nat -> Nat
f224 : Nat -> Nat -> Nat -> Nat
f225 : Nat -> Nat -> Nat -> Nat
f226 : Nat -> Nat -> Nat -> Nat
f227 : Nat -> Nat -> Nat -> Nat
f228 : Nat -> Nat -> Nat -> Nat
f229 : Nat -> Nat -> Nat -> Nat
f230 : Nat -> Nat -> Nat -> Nat
f231 : Nat -> Nat -> Nat -> Nat
f232 : Nat -> Nat -> Nat -> Nat
f233 : Nat -> Nat -> Nat -> Nat
f234 : Nat -> Nat -> Nat -> Nat
f235 : Nat -> Nat -> Nat -> Nat
f236 : Nat -> Nat -> Nat -> Nat
f237 : Nat -> Nat -> Nat -> Nat
f238 : Nat -> Nat -> Nat -> Nat
f239 : Nat -> Nat -> Nat -> Nat

f0 x y z = case x of
  Z => f1 y z x
  S _ => f2 z x y
f1 x y z = case x of
  Z => f2 y z x
  S _ => f3 z x y
f2 x y z = case x of
  Z => f3 y z x
  S _ => f4 z x y
f3 x y z = case x of
  Z => f4 y z x
  S _ => f5 z x y
f4 x y z = case x of
  Z => f5 y z x
  S _ => f6 z x y
f5 x y z = case x of
  Z => f6 y z x
  S _ => f7 z x y
f6 x y z = case x of
  Z => f7 y z x
  S _ => f8 z x y
f7 x y z = case x of
  Z => f8 y z x
  S _ => f9 z x y
f8 x y z = case x of
  Z => f9 y z x
  S _ => f10 z x y
f9 x y z = case x of
  Z => f10 y z x
  S _ => f11 z x y
f10 x y z = case x of
  Z => f11 y z x
  S _ => f12 z x y
f11 x y z = case x of
  Z => f12 y z x
  S _ => f13 z x y
f12 x y z = case x of
  Z => f13 y z x
  S _ => f14 z x y
f13 x y z = case x of
  Z => f14 y z x
  S _ => f15 z x y
f14 x y z = case x of
  Z => f15 y z x
  S _ => f16 z x y
f15 x y z = case x of
  Z => f16 y z x
  S _ => f17 z x y
f16 x y z = case x of
  Z => f17 y z x
  S _ => f18 z x y
f17 x y z = case x of
  Z => f18 y z x
  S _ => f19 z x y
f18 x y z = case x of
  Z => f19 y z x
  S _ => f20 z x y
f19 x y z = case x of
  Z => f20 y z x
  S _ => f21 z x y
f20 x y z = case x of
  Z => f21 y z x
  S _ => f22 z x y
f21 x y z = case x of
  Z => f22 y z x
  S _ => f23 z x y
f22 x y z = case x of
  Z => f23 y z x
  S _ => f24 z x y
f23 x y z = case x of
  Z => f24 y z x
  S _ => f25 z x y
f24 x y z = case x of
  Z => f25 y z x
  S _ => f26 z x y
f25 x y z = case x of
  Z => f26 y z x
  S _ => f27 z x y
f26 x y z = case x of
  Z => f27 y z x
  S _ => f28 z x y
f27 x y z = case x of
  Z => f28 y z x
  S _ => f29 z x y
f28 x y z = case x of
  Z => f29 y z x
  S _ => f30 z x y
f29 x y z = case x of
  Z => f30 y z x
  S _ => f31 z x y
f30 x y z = case x of
  Z => f31 y z x
  S _ => f32 z x y
f31 x y z = case x of
  Z => f32 y z x
  S _ => f33 z x y
f32 x y z = case x of
  Z => f33 y z x
  S _ => f34 z x y
f33 x y z = case x of
  Z => f34 y z x
  S _ => f35 z x y
f34 x y z = case x of
  Z => f35 y z x
  S _ => f36 z x y
f35 x y z = case x of
  Z => f36 y z x
  S _ => f37 z x y
f36 x y z = case x of
  Z => f37 y z x
  S _ => f38 z x y
f37 x y z = case x of
  Z => f38 y z x
  S _ => f39 z x y
f38 x y z = case x of
  Z => f39 y z x
  S _ => f40 z x y
f39 x y z = case x of
  Z => f40 y z x
  S _ => f41 z x y
f40 x y z = case x of
  Z => f41 y z x
  S _ => f42 z x y
f41 x y z = case x of
  Z => f42 y z x
  S _ => f43 z x y
f42 x y z = case x of
  Z => f43 y z x
  S _ => f44 z x y
f43 x y z = case x of
  Z => f44 y z x
  S _ => f45 z x y
f44 x y z = case x of
  Z => f45 y z x
  S _ => f46 z x y
f45 x y z = case x of
  Z => f46 y z x
  S _ => f47 z x y
f46 x y z = case x of
  Z => f47 y z x
  S _ => f48 z x y
f47 x y z = case x of
  Z => f48 y z x
  S _ => f49 z x y
f48 x y z = case x of
  Z => f49 y z x
  S _ => f50 z x y
f49 x y z = case x of
  Z => f50 y z x
  S _ => f51 z x y
f50 x y z = case x of
  Z => f51 y z x
  S _ => f52 z x y
f51 x y z = case x of
  Z => f52 y z x
  S _ => f53 z x y
f52 x y z = case x of
  Z => f53 y z x
  S _ => f54 z x y
f53 x y z = case x of
  Z => f54 y z x
  S _ => f55 z x y
f54 x y z = case x of
  Z => f55 y z x
  S _ => f56 z x y
f55 x y z = case x of
  Z => f56 y z x
  S _ => f57 z x y
f56 x y z = case x of
  Z => f57 y z x
  S _ => f58 z x y
f57 x y z = case x of
  Z => f58 y z x
  S _ => f59 z x y
f58 x y z = case x of
  Z => f59 y z x
  S _ => f60 z x y
f59 x y z = case x of
  Z => f60 y z x
  S _ => f61 z x y
f60 x y z = case x of
  Z => f61 y z x
  S _ => f62 z x y
f61 x y z = case x of
  Z => f62 y z x
  S _ => f63 z x y
f62 x y z = case x of
  Z => f63 y z x
  S _ => f64 z x y
f63 x y z = case x of
  Z => f64 y z x
  S _ => f65 z x y
f64 x y z = case x of
  Z => f65 y z x
  S _ => f66 z x y
f65 x y z = case x of
  Z => f66 y z x
  S _ => f67 z x y
f66 x y z = case x of
  Z => f67 y z x
  S _ => f68 z x y
f67 x y z = case x of
  Z => f68 y z x
  S _ => f69 z x y
f68 x y z = case x of
  Z => f69 y z x
  S _ => f70 z x y
f69 x y z = case x of
  Z => f70 y z x
  S _ => f71 z x y
f70 x y z = case x of
  Z => f71 y z x
  S _ => f72 z x y
f71 x y z = case x of
  Z => f72 y z x
  S _ => f73 z x y
f72 x y z = case x of
  Z => f73 y z x
  S _ => f74 z x y
f73 x y z = case x of
  Z => f74 y z x
  S _ => f75 z x y
f74 x y z = case x of
  Z => f75 y z x
  S _ => f76 z x y
f75 x y z = case x of
  Z => f76 y z x
  S _ => f77 z x y
f76 x y z = case x of
  Z => f77 y z x
  S _ => f78 z x y
f77 x y z = case x of
  Z => f78 y z x
  S _ => f79 z x y
f78 x y z = case x of
  Z => f79 y z x
  S _ => f80 z x y
f79 x y z = case x of
  Z => f80 y z x
  S _ => f81 z x y
f80 x y z = case x of
  Z => f81 y z x
  S _ => f82 z x y
f81 x y z = case x of
  Z => f82 y z x
  S _ => f83 z x y
f82 x y z = case x of
  Z => f83 y z x
  S _ => f84 z x y
f83 x y z = case x of
  Z => f84 y z x
  S _ => f85 z x y
f84 x y z = case x of
  Z => f85 y z x
  S _ => f86 z x y
f85 x y z = case x of
  Z => f86 y z x
  S _ => f87 z x y
f86 x y z = case x of
  Z => f87 y z x
  S _ => f88 z x y
f87 x y z = case x of
  Z => f88 y z x
  S _ => f89 z x y
f88 x y z = case x of
  Z => f89 y z x
  S _ => f90 z x y
f89 x y z = case x of
  Z => f90 y z x
  S _ => f91 z x y
f90 x y z = case x of
  Z => f91 y z x
  S _ => f92 z x y
f91 x y z = case x of
  Z => f92 y z x
  S _ => f93 z x y
f92 x y z = case x of
  Z => f93 y z x
  S _ => f94 z x y
f93 x y z = case x of
  Z => f94 y z x
  S _ => f95 z x y
f94 x y z = case x of
  Z => f95 y z x
  S _ => f96 z x y
f95 x y z = case x of
  Z => f96 y z x
  S _ => f97 z x y
f96 x y z = case x of
  Z => f97 y z x
  S _ => f98 z x y
f97 x y z = case x of
  Z => f98 y z x
  S _ => f99 z x y
f98 x y z = case x of
  Z => f99 y z x
  S _ => f100 z x y
f99 x y z = case x of
  Z => f100 y z x
  S _ => f101 z x y
f100 x y z = case x of
  Z => f101 y z x
  S _ => f102 z x y
f101 x y z = case x of
  Z => f102 y z x
  S _ => f103 z x y
f102 x y z = case x of
  Z => f103 y z x
  S _ => f104 z x y
f103 x y z = case x of
  Z => f104 y z x
  S _ => f105 z x y
f104 x y z = case x of
  Z => f105 y z x
  S _ => f106 z x y
f105 x y z = case x of
  Z => f106 y z x
  S _ => f107 z x y
f106 x y z = case x of
  Z => f107 y z x
  S _ => f108 z x y
f107 x y z = case x of
  Z => f108 y z x
  S _ => f109 z x y
f108 x y z = case x of
  Z => f109 y z x
  S _ => f110 z x y
f109 x y z = case x of
  Z => f110 y z x
  S _ => f111 z x y
f110 x y z = case x of
  Z => f111 y z x
  S _ => f112 z x y
f111 x y z = case x of
  Z => f112 y z x
  S _ => f113 z x y
f112 x y z = case x of
  Z => f113 y z x
  S _ => f114 z x y
f113 x y z = case x of
  Z => f114 y z x
  S _ => f115 z x y
f114 x y z = case x of
  Z => f115 y z x
  S _ => f116 z x y
f115 x y z = case x of
  Z => f116 y z x
  S _ => f117 z x y
f116 x y z = case x of
  Z => f117 y z x
  S _ => f118 z x y
f117 x y z = case x of
  Z => f118 y z x
  S _ => f119 z x y
f118 x y z = case x of
  Z => f119 y z x
  S _ => f120 z x y
f119 x y z = case x of
  Z => f120 y z x
  S _ => f121 z x y
f120 x y z = case x of
  Z => f121 y z x
  S _ => f122 z x y
f121 x y z = case x of
  Z => f122 y z x
  S _ => f123 z x y
f122 x y z = case x of
  Z => f123 y z x
  S _ => f124 z x y
f123 x y z = case x of
  Z => f124 y z x
  S _ => f125 z x y
f124 x y z = case x of
  Z => f125 y z x
  S _ => f126 z x y
f125 x y z = case x of
  Z => f126 y z x
  S _ => f127 z x y
f126 x y z = case x of
  Z => f127 y z x
  S _ => f128 z x y
f127 x y z = case x of
  Z => f128 y z x
  S _ => f129 z x y
f128 x y z = case x of
  Z => f129 y z x
  S _ => f130 z x y
f129 x y z = case x of
  Z => f130 y z x
  S _ => f131 z x y
f130 x y z = case x of
  Z => f131 y z x
  S _ => f132 z x y
f131 x y z = case x of
  Z => f132 y z x
  S _ => f133 z x y
f132 x y z = case x of
  Z => f133 y z x
  S _ => f134 z x y
f133 x y z = case x of
  Z => f134 y z x
  S _ => f135 z x y
f134 x y z = case x of
  Z => f135 y z x
  S _ => f136 z x y
f135 x y z = case x of
  Z => f136 y z x
  S _ => f137 z x y
f136 x y z = case x of
  Z => f137 y z x
  S _ => f138 z x y
f137 x y z = case x of
  Z => f138 y z x
  S _ => f139 z x y
f138 x y z = case x of
  Z => f139 y z x
  S _ => f140 z x y
f139 x y z = case x of
  Z => f140 y z x
  S _ => f141 z x y
f140 x y z = case x of
  Z => f141 y z x
  S _ => f142 z x y
f141 x y z = case x of
  Z => f142 y z x
  S _ => f143 z x y
f142 x y z = case x of
  Z => f143 y z x
  S _ => f144 z x y
f143 x y z = case x of
  Z => f144 y z x
  S _ => f145 z x y
f144 x y z = case x of
  Z => f145 y z x
  S _ => f146 z x y
f145 x y z = case x of
  Z => f146 y z x
  S _ => f147 z x y
f146 x y z = case x of
  Z => f147 y z x
  S _ => f148 z x y
f147 x y z = case x of
  Z => f148 y z x
  S _ => f149 z x y
f148 x y z = case x of
  Z => f149 y z x
  S _ => f150 z x y
f149 x y z = case x of
  Z => f150 y z x
  S _ => f151 z x y
f150 x y z = case x of
  Z => f151 y z x
  S _ => f152 z x y
f151 x y z = case x of
  Z => f152 y z x
  S _ => f153 z x y
f152 x y z = case x of
  Z => f153 y z x
  S _ => f154 z x y
f153 x y z = case x of
  Z => f154 y z x
  S _ => f155 z x y
f154 x y z = case x of
  Z => f155 y z x
  S _ => f156 z x y
f155 x y z = case x of
  Z => f156 y z x
  S _ => f157 z x y
f156 x y z = case x of
  Z => f157 y z x
  S _ => f158 z x y
f157 x y z = case x of
  Z => f158 y z x
  S _ => f159 z x y
f158 x y z = case x of
  Z => f159 y z x
  S _ => f160 z x y
f159 x y z = case x of
  Z => f160 y z x
  S _ => f161 z x y
f160 x y z = case x of
  Z => f161 y z x
  S _ => f162 z x y
f161 x y z = case x of
  Z => f162 y z x
  S _ => f163 z x y
f162 x y z = case x of
  Z => f163 y z x
  S _ => f164 z x y
f163 x y z = case x of
  Z => f164 y z x
  S _ => f165 z x y
f164 x y z = case x of
  Z => f165 y z x
  S _ => f166 z x y
f165 x y z = case x of
  Z => f166 y z x
  S _ => f167 z x y
f166 x y z = case x of
  Z => f167 y z x
  S _ => f168 z x y
f167 x y z = case x of
  Z => f168 y z x
  S _ => f169 z x y
f168 x y z = case x of
  Z => f169 y z x
  S _ => f170 z x y
f169 x y z = case x of
  Z => f170 y z x
  S _ => f171 z x y
f170 x y z = case x of
  Z => f171 y z x
  S _ => f172 z x y
f171 x y z = case x of
  Z => f172 y z x
  S _ => f173 z x y
f172 x y z = case x of
  Z => f173 y z x
  S _ => f174 z x y
f173 x y z = case x of
  Z => f174 y z x
  S _ => f175 z x y
f174 x y z = case x of
  Z => f175 y z x
  S _ => f176 z x y
f175 x y z = case x of
  Z => f176 y z x
  S _ => f177 z x y
f176 x y z = case x of
  Z => f177 y z x
  S _ => f178 z x y
f177 x y z = case x of
  Z => f178 y z x
  S _ => f179 z x y
f178 x y z = case x of
  Z => f179 y z x
  S _ => f180 z x y
f179 x y z = case x of
  Z => f180 y z x
  S _ => f181 z x y
f180 x y z = case x of
  Z => f181 y z x
  S _ => f182 z x y
f181 x y z = case x of
  Z => f182 y z x
  S _ => f183 z x y
f182 x y z = case x of
  Z => f183 y z x
  S _ => f184 z x y
f183 x y z = case x of
  Z => f184 y z x
  S _ => f185 z x y
f184 x y z = case x of
  Z => f185 y z x
  S _ => f186 z x y
f185 x y z = case x of
  Z => f186 y z x
  S _ => f187 z x y
f186 x y z = case x of
  Z => f187 y z x
  S _ => f188 z x y
f187 x y z = case x of
  Z => f188 y z x
  S _ => f189 z x y
f188 x y z = case x of
  Z => f189 y z x
  S _ => f190 z x y
f189 x y z = case x of
  Z => f190 y z x
  S _ => f191 z x y
f190 x y z = case x of
  Z => f191 y z x
  S _ => f192 z x y
f191 x y z = case x of
  Z => f192 y z x
  S _ => f193 z x y
f192 x y z = case x of
  Z => f193 y z x
  S _ => f194 z x y
f193 x y z = case x of
  Z => f194 y z x
  S _ => f195 z x y
f194 x y z = case x of
  Z => f195 y z x
  S _ => f196 z x y
f195 x y z = case x of
  Z => f196 y z x
  S _ => f197 z x y
f196 x y z = case x of
  Z => f197 y z x
  S _ => f198 z x y
f197 x y z = case x of
  Z => f198 y z x
  S _ => f199 z x y
f198 x y z = case x of
  Z => f199 y z x
  S _ => f200 z x y
f199 x y z = case x of
  Z => f200 y z x
  S _ => f201 z x y
f200 x y z = case x of
  Z => f201 y z x
  S _ => f202 z x y
f201 x y z = case x of
  Z => f202 y z x
  S _ => f203 z x y
f202 x y z = case x of
  Z => f203 y z x
  S _ => f204 z x y
f203 x y z = case x of
  Z => f204 y z x
  S _ => f205 z x y
f204 x y z = case x of
  Z => f205 y z x
  S _ => f206 z x y
f205 x y z = case x of
  Z => f206 y z x
  S _ => f207 z x y
f206 x y z = case x of
  Z => f207 y z x
  S _ => f208 z x y
f207 x y z = case x of
  Z => f208 y z x
  S _ => f209 z x y
f208 x y z = case x of
  Z => f209 y z x
  S _ => f210 z x y
f209 x y z = case x of
  Z => f210 y z x
  S _ => f211 z x y
f210 x y z = case x of
  Z => f211 y z x
  S _ => f212 z x y
f211 x y z = case x of
  Z => f212 y z x
  S _ => f213 z x y
f212 x y z = case x of
  Z => f213 y z x
  S _ => f214 z x y
f213 x y z = case x of
  Z => f214 y z x
  S _ => f215 z x y
f214 x y z = case x of
  Z => f215 y z x
  S _ => f216 z x y
f215 x y z = case x of
  Z => f216 y z x
  S _ => f217 z x y
f216 x y z = case x of
  Z => f217 y z x
  S _ => f218 z x y
f217 x y z = case x of
  Z => f218 y z x
  S _ => f219 z x y
f218 x y z = case x of
  Z => f219 y z x
  S _ => f220 z x y
f219 x y z = case x of
  Z => f220 y z x
  S _ => f221 z x y
f220 x y z = case x of
  Z => f221 y z x
  S _ => f222 z x y
f221 x y z = case x of
  Z => f222 y z x
  S _ => f223 z x y
f222 x y z = case x of
  Z => f223 y z x
  S _ => f224 z x y
f223 x y z = case x of
  Z => f224 y z x
  S _ => f225 z x y
f224 x y z = case x of
  Z => f225 y z x
  S _ => f226 z x y
f225 x y z = case x of
  Z => f226 y z x
  S _ => f227 z x y
f226 x y z = case x of
  Z => f227 y z x
  S _ => f228 z x y
f227 x y z = case x of
  Z => f228 y z x
  S _ => f229 z x y
f228 x y z = case x of
  Z => f229 y z x
  S _ => f230 z x y
f229 x y z = case x of
  Z => f230 y z x
  S _ => f231 z x y
f230 x y z = case x of
  Z => f231 y z x
  S _ => f232 z x y
f231 x y z = case x of
  Z => f232 y z x
  S _ => f233 z x y
f232 x y z = case x of
  Z => f233 y z x
  S _ => f234 z x y
f233 x y z = case x of
  Z => f234 y z x
  S _ => f235 z x y
f234 x y z = case x of
  Z => f235 y z x
  S _ => f236 z x y
f235 x y z = case x of
  Z => f236 y z x
  S _ => f237 z x y
f236 x y z = case x of
  Z => f237 y z x
  S _ => f238 z x y
f237 x y z = case x of
  Z => f238 y z x
  S _ => f239 z x y
f238 x y z = f239 y z x
f239 x y z = x + y + z

total
top0 : Nat -> Nat
top0 n = f0 n 0 n

total
top1 : Nat -> Nat
top1 n = f0 n 1 n

total
top2 : Nat -> Nat
top2 n = f0 n 2 n

total
top3 : Nat -> Nat
top3 n = f0 n 3 n

total
top4 : Nat -> Nat
top4 n = f0 n 4 n

total
top5 : Nat -> Nat
top5 n = f0 n 5 n

total
top6 : Nat -> Nat
top6 n = f0 n 6 n

total
top7 : Nat -> Nat
top7 n = f0 n 7 n

total
top8 : Nat -> Nat
top8 n = f0 n 8 n

total
top9 : Nat -> Nat
top9 n = f0 n 9 n

total
top10 : Nat -> Nat
top10 n = f0 n 10 n

total
top11 : Nat -> Nat
top11 n = f0 n 11 n

total
top12 : Nat -> Nat
top12 n = f0 n 12 n

total
top13 : Nat -> Nat
top13 n = f0 n 13 n

total
top14 : Nat -> Nat
top14 n = f0 n 14 n

total
top15 : Nat -> Nat
top15 n = f0 n 15 n

total
top16 : Nat -> Nat
top16 n = f0 n 16 n

total
top17 : Nat -> Nat
top17 n = f0 n 17 n

total
top18 : Nat -> Nat
top18 n = f0 n 18 n

total
top19 : Nat -> Nat
top19 n = f0 n 19 n

total
top20 : Nat -> Nat
top20 n = f0 n 20 n

total
top21 : Nat -> Nat
top21 n = f0 n 21 n

total
top22 : Nat -> Nat
top22 n = f0 n 22 n

total
top23 : Nat -> Nat
top23 n = f0 n 23 n

total
top24 : Nat -> Nat
top24 n = f0 n 24 n

main : IO ()
main = printLn (top0 3)
