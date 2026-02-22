# Benchmark Library Install Smoke

This transcript is intended for the `reference-perf.sh --benchmark-transcript ...` path.
It exercises network + codebase IO and verifies the `@mitchellwrosen/benchmark` package
is installable and queryable in a fresh codebase.

``` ucm
> lib.install @mitchellwrosen/benchmark/releases/latest

  I installed @mitchellwrosen/benchmark/releases/2.1.0 into
  lib.mitchellwrosen_benchmark_2_1_0

> find benchmark

  ☝️

  I couldn't find matches in this namespace, searching in
  'lib'...

  1.  lib.mitchellwrosen_benchmark_2_1_0.benchmark : '{IO,
                                                     Exception} a
                                                     ->{IO,
                                                     Exception} ()
  2.  lib.mitchellwrosen_benchmark_2_1_0.benchmark.doc : Doc
  3.  lib.mitchellwrosen_benchmark_2_1_0.internal.bold.internal : Text
                                                                  -> Text
  4.  lib.mitchellwrosen_benchmark_2_1_0.internal.floatToNat.internal : Float
                                                                        -> Nat
  5.  lib.mitchellwrosen_benchmark_2_1_0.internal.nanos4.internal : Float
                                                                    ->{Exception} Text
  6.  lib.mitchellwrosen_benchmark_2_1_0.internal.nanosBetween.internal : TimeSpec
                                                                          -> TimeSpec
                                                                          -> Float
  7.  lib.mitchellwrosen_benchmark_2_1_0.internal.renderFloat.internal : Nat
                                                                         -> Float
                                                                         ->{Exception} Text
  8.  lib.mitchellwrosen_benchmark_2_1_0.internal.renderNat3.internal : Nat
                                                                        ->{Exception} Text
  9.  lib.mitchellwrosen_benchmark_2_1_0.internal.renderPercentage.internal : Float
                                                                              ->{Exception} Text
  10. lib.mitchellwrosen_benchmark_2_1_0.internal.run.internal : '{g,
                                                                 IO,
                                                                 Exception} a
                                                                 -> Nat
                                                                 ->{g,
                                                                 IO,
                                                                 Exception} ()
  11. lib.mitchellwrosen_benchmark_2_1_0.internal.run.internal.doc : Doc
  12. lib.mitchellwrosen_benchmark_2_1_0.internal.time.internal : '{g,
                                                                  IO,
                                                                  Exception} a
                                                                  -> Nat
                                                                  ->{g,
                                                                  IO,
                                                                  Exception} Float
  13. lib.mitchellwrosen_benchmark_2_1_0.internal.time.internal.doc : Doc
  14. lib.mitchellwrosen_benchmark_2_1_0.internal.timespecToNanos.internal : TimeSpec
                                                                             -> Nat
  15. lib.mitchellwrosen_benchmark_2_1_0.README : Doc
  16. lib.mitchellwrosen_benchmark_2_1_0.ReleaseNotes : Doc
```
