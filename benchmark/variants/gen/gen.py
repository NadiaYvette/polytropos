#!/usr/bin/env python3
"""Generate benchmark modules for the extensible-variant compile-time question.

Three arms, each parameterised by N:

  R  plain record, N fields, stock Show/Eq, N use sites.
     This is a POSITIVE CONTROL. Records are known to blow up quadratically in
     GHC Core (that is the entire raison d'etre of large-records), so this arm
     proves the measurement can actually detect superlinear growth when it is
     there. Without it, a flat result for A and C would be uninformative.

  A  plain sum, N constructors, stock Show/Eq, N use sites.
     This is the actual question: does GHC handle large sums linearly?

  C  structural variant (Bench.StructVariant), N constructors, N injections
     and N projections. Each use site performs a distinct type-level 'Idx'
     search against the SAME row, so N lookups x O(N) each = O(N^2) in the
     absence of a plugin. This is the faithful analogue of what large-anon's
     RowHasField does, and of what a plugin would make O(1).

All arms use a small fixed payload defined once in Bench.Payload, so growth is
attributable to the number of constructors/fields, not to payload size.
"""

import os
import sys

SIZES = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]

HEADER = """{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
"""


def cname(i: int) -> str:
    return "C%02d" % i


# ---------------------------------------------------------------- arm R

def gen_record(n: int) -> str:
    fields = "\n    , ".join("f%02d :: !Int" % i for i in range(n))
    ctor = " ".join(str(i) for i in range(n))
    uses = ", ".join("f%02d r" % i for i in range(n))
    return HEADER + f"""-- | Generated: plain record with {n} fields (positive control).
module Bench.Gen.R.R{n:03d} (Rec(..), mkRec, useAll) where

data Rec = Rec {{
      {fields}
    }}
  deriving (Show, Eq)

mkRec :: Rec
mkRec = Rec {ctor}

-- | One use site per field: the field selectors are the classic source of
-- quadratic Core in records.
useAll :: [Int]
useAll = [ {uses} ]
  where
    r = mkRec
"""


# ---------------------------------------------------------------- arm A

def gen_sum(n: int) -> str:
    alts = "\n  | ".join("%s !P" % cname(i) for i in range(n))
    build = "\n    , ".join("%s (mkP %d)" % (cname(i), i) for i in range(n))
    cases = "\n      ".join(
        "%s _ -> %d" % (cname(i), i) for i in range(n))
    return HEADER + f"""-- | Generated: plain sum with {n} constructors, stock Show/Eq.
module Bench.Gen.A.A{n:03d} (S(..), mkS, useAll) where

import Bench.Payload

data S
  = {alts}
  deriving (Show, Eq)

mkS :: [S]
mkS = [ {build} ]

-- | One use site per constructor: a full case analysis.
useAll :: [Int]
useAll = [ use q | q <- mkS ]
  where
    use :: S -> Int
    use q = case q of
      {cases}
"""


# ---------------------------------------------------------------- arm C

def gen_variant(n: int) -> str:
    names = ", ".join('"%s"' % cname(i) for i in range(n))
    plds = ", ".join("P" for _ in range(n))

    inj_binds = "\n\n".join(
        'v{i:02d} :: V\nv{i:02d} = mkVariant (natToInt (Proxy @(Idx "{nm}" NS))) (mkP {i})'
        .format(i=i, nm=cname(i)) for i in range(n))
    prj_binds = "\n\n".join(
        'p{i:02d} :: Maybe (Pld "{nm}" NS PS)\n'
        'p{i:02d} = asVariant (natToInt (Proxy @(Idx "{nm}" NS))) v{i:02d}'
        .format(i=i, nm=cname(i)) for i in range(n))
    inj_list = ", ".join("v%02d" % i for i in range(n))
    prj_list = ", ".join("p%02d" % i for i in range(n))

    return HEADER + f"""-- | Generated: structural variant with {n} constructors.
--
-- Each @Idx "Cnn" NS@ is a distinct type-level search against the same row,
-- which is what makes this O(N^2) without a plugin.
module Bench.Gen.C.C{n:03d} (NS, PS, V, injectAll, projectAll) where

import Data.Proxy (Proxy(..))
import Bench.Payload
import Bench.StructVariant

type NS = '[ {names} ]

type PS = '[ {plds} ]

type V = Variant NS PS

{inj_binds}

injectAll :: [V]
injectAll = [ {inj_list} ]

{prj_binds}

projectAll :: [Maybe P]
projectAll = [ {prj_list} ]
"""


def gen_variant_literal(n: int) -> str:
    """Arm C2: identical to arm C, but with the tag supplied as a literal.

    This is what a TcPlugin would produce: the compile-time search is replaced
    by a constant. Comparing C against C2 isolates exactly what the plugin buys.
    """
    names = ", ".join('"%s"' % cname(i) for i in range(n))
    plds = ", ".join("P" for _ in range(n))

    inj_binds = "\n\n".join(
        'v{i:02d} = mkVariant {i} (mkP {i})'.format(i=i) for i in range(n))
    prj_binds = "\n\n".join(
        'p{i:02d} :: Maybe P\np{i:02d} = asVariant {i} v{i:02d}'
        .format(i=i) for i in range(n))
    inj_list = ", ".join("v%02d" % i for i in range(n))
    prj_list = ", ".join("p%02d" % i for i in range(n))

    return HEADER + f"""-- | Generated: structural variant, {n} constructors, LITERAL tags.
--
-- This is arm C with the type-level search replaced by a compile-time
-- constant, i.e. exactly what a TcPlugin would emit.
module Bench.Gen.L.L{n:03d} (NS, PS, V, injectAll, projectAll) where

import Data.Proxy (Proxy(..))
import Bench.Payload
import Bench.StructVariant

type NS = '[ {names} ]

type PS = '[ {plds} ]

type V = Variant NS PS

{inj_binds}

injectAll :: [V]
injectAll = [ {inj_list} ]

{prj_binds}

projectAll :: [Maybe P]
projectAll = [ {prj_list} ]
"""


ARMS = {
    "R": gen_record,
    "A": gen_sum,
    "C": gen_variant,
    "L": gen_variant_literal,
}


def main() -> None:
    outdir = sys.argv[1] if len(sys.argv) > 1 else "out"
    for arm, fn in ARMS.items():
        d = os.path.join(outdir, arm)
        os.makedirs(d, exist_ok=True)
        for n in SIZES:
            path = os.path.join(d, f"{arm}{n:03d}.hs")
            with open(path, "w") as fh:
                fh.write(fn(n))
    print("generated %d arms x %d sizes under %s"
          % (len(ARMS), len(SIZES), outdir))


if __name__ == "__main__":
    main()
