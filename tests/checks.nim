## The little bit of scaffolding every suite shares.
##
## Not `std/unittest`: these suites run inside `start`'s message loop on a
## desktop of their own, with no console attached and nothing to read the
## output but a log file, so what matters is that each result is flushed as it
## happens and that the *process exit code* says whether the run passed. A
## suite can print `PASS` and still corrupt the heap on the way out, and only
## the exit code catches that.

import std/exitprocs
import winui3

var
  checks = 0
  failures = 0

proc check*(name: string, ok: bool, detail = "") =
  ## Record one result, and print it immediately.
  ##
  ## Flushed per line because the suite may die at any point: an unflushed
  ## buffer would take the last few results — the interesting ones — with it.
  checks.inc
  if not ok:
    failures.inc
  echo (if ok: "  ok    " else: "  FAIL  ") & name &
       (if detail.len > 0: "  (" & detail & ")" else: "")
  flushFile(stdout)

proc beginSuite*() =
  ## Fail by default, so a suite that never reaches `finishSuite` is a failure
  ## rather than a silent success.
  setProgramResult(1)

proc finishSuite*() =
  ## Print the tally, set the exit code from it, and leave the message loop.
  echo ""
  echo (if failures == 0: "PASS" else: "FAIL") &
       ": " & $(checks - failures) & "/" & $checks & " checks"
  flushFile(stdout)
  setProgramResult(if failures == 0: 0 else: 1)
  exitApp()
