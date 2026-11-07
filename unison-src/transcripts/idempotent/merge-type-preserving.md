# `merge` keeps the dependents' stored form where it can

Like `update`, `merge` typechecks a dependent again only if it uses something whose type changed, or builds or matches on
a value of a type that changed. The others only take their new references.

``` ucm :hide
scratch/main> builtins.merge lib.builtin
```

Bob edits the body of a function, and Alice adds a dependent of it.

``` unison
helper : Nat -> Nat
helper n = n + 1

one : Nat
one = helper 1
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + helper : Nat -> Nat
  + one    : Nat

  Run `update` to apply these changes to your codebase.
```

``` ucm
scratch/main> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.

scratch/main> branch alice

  Done. I've created the alice branch based off of main.

  Tip: To merge your work back into the main branch, first
       `switch /main` then `merge /alice`.

scratch/main> branch bob

  Done. I've created the bob branch based off of main.

  Tip: To merge your work back into the main branch, first
       `switch /main` then `merge /bob`.
```

``` unison
two : Nat
two = helper 2 + one
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + two : Nat

  Run `update` to apply these changes to your codebase.
```

``` ucm
scratch/alice> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.
```

``` unison
helper : Nat -> Nat
helper n = n + 2
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  ~ helper : Nat -> Nat

  ~ (modified)

  Run `update` to apply these changes to your codebase.
```

``` ucm
scratch/bob> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  That's done. Nothing that code uses changed its type, so I'm
  saving the results without typechecking it again...

  Done.

scratch/alice> merge /bob

  Loading namespaces...

  Computing diff...

  Loading definitions...

  Computing merge...

  I merged scratch/bob into scratch/alice.

scratch/alice> view one two

  one : Nat
  one = helper 1

  two : Nat
  two =
    use Nat +
    helper 2 + one
```

Bob widens a type, which Alice's dependent is typechecked against. What's above it keeps its type, so it isn't.

``` unison
pick : Nat -> Nat
pick x = x
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + pick : Nat -> Nat

  Run `update` to apply these changes to your codebase.
```

``` ucm
sig/main> builtins.merge lib.builtin

  Done.

sig/main> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.

sig/main> branch alice

  Done. I've created the alice branch based off of main.

  Tip: To merge your work back into the main branch, first
       `switch /main` then `merge /alice`.

sig/main> branch bob

  Done. I've created the bob branch based off of main.

  Tip: To merge your work back into the main branch, first
       `switch /main` then `merge /bob`.
```

``` unison
picked : Nat
picked = pick 1

above : Nat
above = picked + 1
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + above  : Nat
  + picked : Nat

  Run `update` to apply these changes to your codebase.
```

``` ucm
sig/alice> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.
```

``` unison
pick : a -> a
pick x = x
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  ~ pick : a -> a

  ~ (modified)

  Run `update` to apply these changes to your codebase.
```

``` ucm
sig/bob> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.

sig/alice> merge /bob

  Loading namespaces...

  Computing diff...

  Loading definitions...

  Computing merge...

  I merged sig/bob into sig/alice.

sig/alice> view picked above

  above : Nat
  above =
    use Nat +
    picked + 1

  picked : Nat
  picked = pick 1
```

Bob adds a constructor. Alice's function that only passes a shape along is substituted, and the one that builds a shape
is typechecked again.

``` unison
type Shape = Circle Nat

area : Shape -> Nat
area = cases Circle n -> n
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + type Shape

  + area : Shape -> Nat

  Run `update` to apply these changes to your codebase.
```

``` ucm
shape/main> builtins.merge lib.builtin

  Done.

shape/main> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.

shape/main> branch alice

  Done. I've created the alice branch based off of main.

  Tip: To merge your work back into the main branch, first
       `switch /main` then `merge /alice`.

shape/main> branch bob

  Done. I've created the bob branch based off of main.

  Tip: To merge your work back into the main branch, first
       `switch /main` then `merge /bob`.
```

``` unison
pass : Shape -> Nat
pass shape = area shape

make : Shape
make = Circle 1

type Scene = Scene Shape
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + type Scene

  + make : Shape
  + pass : Shape -> Nat

  Run `update` to apply these changes to your codebase.
```

``` ucm
shape/alice> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.
```

``` unison
type Shape = Circle Nat | Square Nat

area : Shape -> Nat
area = cases
  Circle n -> n
  Square n -> n
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  ~ type Shape

  ~ area : Shape -> Nat

  ~ (modified)

  Run `update` to apply these changes to your codebase.
```

``` ucm
shape/bob> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.

shape/alice> merge /bob

  Loading namespaces...

  Computing diff...

  Loading definitions...

  Computing merge...

  I merged shape/bob into shape/alice.

shape/alice> view pass make Scene

  type Scene = Scene Shape

  make : Shape
  make = Circle 1

  pass : Shape -> Nat
  pass shape = area shape
```

A dependent that no longer typechecks reports the usual failure.

``` unison
broken : Nat -> Nat
broken x = x
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + broken : Nat -> Nat

  Run `update` to apply these changes to your codebase.
```

``` ucm
fail/main> builtins.merge lib.builtin

  Done.

fail/main> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.

fail/main> branch alice

  Done. I've created the alice branch based off of main.

  Tip: To merge your work back into the main branch, first
       `switch /main` then `merge /alice`.

fail/main> branch bob

  Done. I've created the bob branch based off of main.

  Tip: To merge your work back into the main branch, first
       `switch /main` then `merge /bob`.
```

``` unison
user : Nat
user = broken 1 + 1
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + user : Nat

  Run `update` to apply these changes to your codebase.
```

``` ucm
fail/alice> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.
```

``` unison
broken : Text -> Text
broken x = x
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  ~ broken : Text -> Text

  ~ (modified)

  Run `update` to apply these changes to your codebase.
```

``` ucm
fail/bob> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.
```

``` ucm :error
fail/alice> merge /bob

  Loading namespaces...

  Computing diff...

  Loading definitions...

  Computing merge...

  I couldn't automatically merge fail/bob into fail/alice.

  You're now on a temporary branch, merge-bob-into-alice, and
  the definitions to fix are in merge-bob-into-alice-2a8b1c4b.u.

  Edit the file, then run:

      fail/merge-bob-into-alice> load merge-bob-into-alice-2a8b1c4b.u

  If `load` reports errors, fix them and run it again. When the
  file loads with no errors, run:

      fail/merge-bob-into-alice> update

  `update` saves the file's definitions into alice, removes any
  definitions you deleted from the file, and deletes the
  temporary branch. To abandon the merge instead, run `cancel`.

  Note: Definitions listed in the file don't exist in the branch
  until a successful `update`.
```

``` unison :added-by-ucm merge-bob-into-alice-2a8b1c4b.u
user : Nat
user =
  use Nat +
  broken 1 + 1

```
