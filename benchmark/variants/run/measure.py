#!/usr/bin/env python3
"""Measure compile-time cost of each benchmark arm.

For every (arm, N) we compile exactly one generated module in isolation and
record:

  * ds_preopt : non-blank lines in the target module's -ddump-ds-preopt
  * simpl     : non-blank lines in the target module's -ddump-simpl
  * wall_ms   : min wall clock over REPEATS runs (via /usr/bin/time)
  * rss_kb    : peak RSS of the ghc process (via /usr/bin/time -f %M)

Only the generated module's dump file is counted; the two support modules are
recompiled into the per-run output directory but their dumps are excluded, so
they contribute a constant (not a growing) offset to the timings.

Line counts of the Core dumps are a proxy for Core size. Absolute calibration
against large-records-benchmarks/report is not meaningful (those numbers were
taken with GHC 8.8.4/8.10.7); what matters is the *shape* of the growth curve
within this single GHC 9.14.1 run.
"""

import csv
import glob
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GEN = os.path.join(ROOT, "gen", "out")
WORK = os.path.join(ROOT, ".work")

ARMS = ["R", "A", "C", "L", "P", "PR"]
REPEATS = 3


def get_pkg_args():
    dist_db = os.path.abspath(os.path.join(ROOT, "..", "..", "dist-newstyle", "packagedb", "ghc-9.14.1"))
    store_dbs = sorted(glob.glob(os.path.expanduser("~/.local/state/cabal/store/ghc-9.14.1*/package.db")))
    pkg_args = []
    for db in store_dbs:
        if os.path.exists(db):
            pkg_args.extend(["-package-db", db])
    if os.path.exists(dist_db):
        pkg_args.extend(["-package-db", dist_db])
    pkg_args.extend(["-package", "polytropos-core", "-package", "polytropos-plugin"])
    return pkg_args


def count_lines(outdir: str, arm: str, n: int, suffix: str) -> int:
    """Count non-blank dump lines for the generated module only."""
    total = 0
    for path in glob.glob(os.path.join(outdir, "**", f"*{suffix}"),
                          recursive=True):
        rel = os.path.relpath(path, outdir)
        if f"{arm}{n:03d}" not in rel:
            continue
        with open(path, "r", errors="replace") as fh:
            total += sum(1 for ln in fh if ln.strip())
    return total


def run_one(arm: str, n: int):
    # NOTE: ghc derives the dump-file path from the *source* path, so the
    # source must be given relative to ROOT (with cwd=ROOT) or the dumps end
    # up outside -outputdir.
    src = os.path.join("gen", "out", arm, f"{arm}{n:03d}.hs")
    outdir = os.path.join(WORK, f"{arm}{n:03d}")
    subprocess.run(["rm", "-rf", outdir], check=True)
    os.makedirs(outdir, exist_ok=True)

    # -package-env - is load-bearing, not decoration. Without it GHC picks up
    # a stray .ghc.environment.* from any ancestor directory, which suppresses
    # the `ghc-internal:` unit-id qualification in Core. Shorter names mean
    # fewer wrapped lines, so the same program measures ~7% smaller purely
    # because of where the checkout happens to sit. The metric is *lines*, so
    # it is sensitive to pretty-printer line width; the measurement has to be
    # hermetic or it is not reproducible across locations.
    cmd = [
        "/usr/bin/time", "-f", "%e %M",
        "ghc", "--make", "-O0", "-w",
        "-package-env", "-",
    ] + get_pkg_args() + [
        "-isrc",
        src,
        "-outputdir", outdir,
        "-ddump-to-file",
        "-ddump-ds-preopt", "-ddump-simpl",
    ]

    best_wall = None
    rss = 0
    for _ in range(REPEATS):
        proc = subprocess.run(cmd, capture_output=True, text=True,
                                cwd=ROOT)
        if proc.returncode != 0:
            return {"arm": arm, "n": n,
                    "error": (proc.stderr or proc.stdout)[-2000:]}
        last = proc.stderr.strip().splitlines()[-1].split()
        wall, mem = float(last[0]) * 1000.0, int(last[1])
        rss = max(rss, mem)
        if best_wall is None or wall < best_wall:
            best_wall = wall

    return {
        "arm": arm,
        "n": n,
        "ds_preopt": count_lines(outdir, arm, n, ".dump-ds-preopt"),
        "simpl": count_lines(outdir, arm, n, ".dump-simpl"),
        "wall_ms": round(best_wall),
        "rss_kb": rss,
    }


def main() -> None:
    os.makedirs(WORK, exist_ok=True)
    arms = sys.argv[1:] if len(sys.argv) > 1 else ARMS
    existing = {}
    csv_path = os.path.join(ROOT, "results.csv")
    if os.path.exists(csv_path):
        with open(csv_path, "r", newline="") as fh:
            for r in csv.DictReader(fh):
                existing[(r["arm"], int(r["n"]))] = r

    for arm in arms:
        sizes = sorted(int(f[len(arm):len(arm)+3]) for f in os.listdir(os.path.join(GEN, arm))
                       if f.endswith(".hs"))
        for n in sizes:
            r = run_one(arm, n)
            if "error" in r:
                print(f"{arm} n={n:3d}  FAILED", flush=True)
                print(r["error"], flush=True)
            else:
                existing[(arm, n)] = r
                print(f"{arm:2s} n={n:3d}  ds-preopt={r['ds_preopt']:7d}  "
                      f"simpl={r['simpl']:7d}  wall={r['wall_ms']:7d}ms  "
                      f"rss={r['rss_kb']:8d}kB", flush=True)

    # Sort all rows by arm order and n
    order = {a: i for i, a in enumerate(ARMS)}
    sorted_keys = sorted(existing.keys(), key=lambda k: (order.get(k[0], 99), k[1]))

    with open(csv_path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=[
            "arm", "n", "ds_preopt", "simpl", "wall_ms", "rss_kb"])
        w.writeheader()
        for k in sorted_keys:
            r = existing[k]
            if "error" not in r:
                w.writerow(r)
    print("\nwrote results.csv")


if __name__ == "__main__":
    main()
