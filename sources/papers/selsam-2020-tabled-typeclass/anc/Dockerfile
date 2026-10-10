FROM ubuntu:bionic

RUN mkdir /root/app
WORKDIR /root/app

## Basic setup
RUN ["apt-get", "update"]
RUN ["apt-get", "upgrade", "-y"]
RUN ["apt-get", "install", "-y", "g++", "git", "cmake", "libgmp-dev", "wget", "zlib1g-dev", "libncurses5-dev", "ghc", "cabal-install", "emacs", "python3", "python"]

## (1/6) Agda
RUN ["cabal", "update"]
RUN ["cabal", "install", "alex"]
RUN ["cabal", "install", "happy"]
RUN ["cabal", "install", "Agda"]

## (2/6) Coq
RUN apt-get install -y m4 software-properties-common gcc
RUN add-apt-repository ppa:avsm/ppa
RUN apt-get update
RUN apt-get install -y opam
RUN opam --version
RUN opam init -y --disable-sandboxing
RUN eval $(opam env)
RUN opam pin add coq 8.10.2 -y
RUN eval $(opam env)
RUN /root/.opam/default/.opam-switch/build/coq.8.10.2/bin/coqc -v

## (3/6) Scala
RUN ["apt-get", "install", "-y", "scala"]

## (4/6) Lean3
WORKDIR /root/app
RUN ["git", "clone", "https://github.com/leanprover/lean",  "lean3"]
WORKDIR /root/app/lean3
RUN ["mkdir", "build"]
WORKDIR /root/app/lean3/build
RUN ["cmake", "../src"]
RUN LEAN_PATH=/root/app/lean3/library:/root/app/lean3/leanpkg make -j8

## (5/6) Lean4
WORKDIR /root/app
RUN pwd
RUN ["git", "clone", "https://github.com/leanprover/lean4",  "lean4"]
WORKDIR /root/app/lean4
RUN git checkout -b master_snapshot b5fc9c19fe45b6ea72b365b1247fd557b2630683
RUN ["mkdir", "build"]
WORKDIR /root/app/lean4/build
RUN ["cmake", "../src"]
RUN LEAN_PATH=Init=/root/app/lean4/src/Init make -j8

## (6/6) Lean4 no shortcircuit
WORKDIR /root/app
RUN pwd
RUN ["git", "clone", "https://github.com/dselsam/lean4",  "lean4nosc"]
WORKDIR /root/app/lean4nosc
RUN git checkout -b tc_no_shortcircuit 203486a7c448a43a20808523e0c6b5c5032b78e4
RUN ["mkdir", "build"]
WORKDIR /root/app/lean4nosc/build
RUN ["cmake", "../src"]
RUN LEAN_PATH=Init=/root/app/lean4nosc/src/Init make -j8

## Experiments
WORKDIR /root/app
RUN mkdir /root/app/results
RUN mkdir /root/app/results/diamonds
RUN mkdir /root/app/results/append

COPY diamonds.py diamonds.py
COPY append.py append.py
COPY util.py util.py

RUN python3 diamonds.py --lean3 1 --lean4 1 --coq 1 --agda 1 --scala 1 --n_runs 5
RUN python3 append.py --lean4 1 --lean4nosc 1 --n_runs 5
