import os

proc getAssetsPath*() : string {.inline.} =
    result = os.getAppDir() & "/assets"
    when defined(macosx):
        result = os.getAppDir().parentDir &  "/Resources/assets"
    when defined(linux):
        result = os.getAppDir().parentDir &  "/share/assets"    
    result.normalizePath

##! Ternary Operator Simulation
type
  BranchPair[T] = object
    then, otherwise: T

# This cannot be a template yet, buggy compiler...
proc `!`*[T](a, b: T): BranchPair[T] {.inline.} = BranchPair[T](then: a, otherwise: b)

template `?`*[T](cond: bool; p: BranchPair[T]): T =
  (if cond: p.then else: p.otherwise)

##! countTo iterator
iterator countTo*(n: int): int =
  var i = 0
  while i <= n:
    yield i
    inc i  