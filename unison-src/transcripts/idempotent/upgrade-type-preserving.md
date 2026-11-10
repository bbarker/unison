# `upgrade` keeps the dependents' stored form where it can

Like `update`, `upgrade` typechecks a dependent again only if it uses something whose type changed, or builds or matches
on a value of a type that changed. The others only take their new references.

``` ucm :hide
scratch/main> builtins.merge lib.builtin
```

A body change reaches a chain of dependents, a cycle and a test without changing a type.

``` unison
old.helper : Nat -> Nat
old.helper n = n + 1

new.helper : Nat -> Nat
new.helper n = n + 2

one : Nat
one = old.helper 1

two : Nat
two = one + 1

ping : Nat -> Nat
ping n = if n == 0 then 0 else pong (Nat.drop n 1)

pong : Nat -> Nat
pong n = old.helper (ping n)

test> checkTwo = [Test.Result.Ok (Nat.toText two)]
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + checkTwo   : [Result]
  + new.helper : Nat -> Nat
  + old.helper : Nat -> Nat
  + one        : Nat
  + ping       : Nat -> Nat
  + pong       : Nat -> Nat
  + two        : Nat

  Run `update` to apply these changes to your codebase.

    19 | test> checkTwo = [Test.Result.Ok (Nat.toText two)]
    
    ✅ Passed 3
```

``` ucm
scratch/main> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.

scratch/main> move old lib.old

  Done.

scratch/main> move new lib.new

  Done.

scratch/main> upgrade old new

  I upgraded old to new.

scratch/main> view one pong

  one : Nat
  one = helper 1

  pong : Nat -> Nat
  pong n = helper (ping n)
```

A dependent of a term whose type changed is typechecked again, and what's above it isn't unless its type changes too.

``` unison
old.pick : Nat -> Nat
old.pick x = x

new.pick : a -> a
new.pick x = x

picked : Nat
picked = old.pick 1

above : Nat
above = picked + 1
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + above    : Nat
  + new.pick : a -> a
  + old.pick : Nat -> Nat
  + picked   : Nat

  Run `update` to apply these changes to your codebase.
```

``` ucm
sig/main> builtins.merge lib.builtin

  Done.

sig/main> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.

sig/main> move old lib.old

  Done.

sig/main> move new lib.new

  Done.

sig/main> upgrade old new

  I upgraded old to new.

sig/main> view picked above

  above : Nat
  above =
    use Nat +
    picked + 1

  picked : Nat
  picked = pick 1
```

A data type gains a constructor. A function that only passes shapes along is substituted, one that builds a shape is
typechecked again, and a type that mentions it is printed and parsed.

``` unison
type old.Shape = Circle Nat
type new.Shape = Circle Nat | Square Nat

old.area : old.Shape -> Nat
old.area = cases old.Shape.Circle n -> n

new.area : new.Shape -> Nat
new.area = cases
  new.Shape.Circle n -> n
  new.Shape.Square n -> n

pass : old.Shape -> Nat
pass shape = old.area shape

make : old.Shape
make = old.Shape.Circle 1

type Scene = Scene old.Shape
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + type new.Shape
  + type old.Shape
  + type Scene

  + make     : old.Shape
  + new.area : new.Shape -> Nat
  + old.area : old.Shape -> Nat
  + pass     : old.Shape -> Nat

  Run `update` to apply these changes to your codebase.
```

``` ucm
shape/main> builtins.merge lib.builtin

  Done.

shape/main> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.

shape/main> move old lib.old

  Done.

shape/main> move new lib.new

  Done.

shape/main> upgrade old new

  I upgraded old to new.

shape/main> view pass make Scene

  type Scene = Scene Shape

  make : Shape
  make = Circle 1

  pass : Shape -> Nat
  pass shape = area shape
```

A term link follows the printer, so the term with it is typechecked again.

``` unison
old.linked : Nat
old.linked = 1

new.linked : Nat
new.linked = 2
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + new.linked : Nat
  + old.linked : Nat

  Run `update` to apply these changes to your codebase.
```

``` ucm
link/main> builtins.merge lib.builtin

  Done.

link/main> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.
```

``` unison
theLink = termLink old.linked
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + theLink : Term

  Run `update` to apply these changes to your codebase.
```

``` ucm
link/main> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.

link/main> move old lib.old

  Done.

link/main> move new lib.new

  Done.

link/main> upgrade old new

  I upgraded old to new.

link/main> view theLink

  theLink : Term
  theLink = termLink linked
```

A dependent that no longer typechecks reports the usual failure.

``` unison
old.broken : Nat -> Nat
old.broken x = x

new.broken : Text -> Text
new.broken x = x

fine : Nat
fine = 1

user : Nat
user = old.broken 1 + fine
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + fine       : Nat
  + new.broken : Text -> Text
  + old.broken : Nat -> Nat
  + user       : Nat

  Run `update` to apply these changes to your codebase.
```

``` ucm
broken/main> builtins.merge lib.builtin

  Done.

broken/main> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.

broken/main> move old lib.old

  Done.

broken/main> move new lib.new

  Done.
```

``` ucm :error
broken/main> upgrade old new

  I couldn't automatically upgrade old to new.

  You're now on a temporary branch, upgrade-old-to-new, and the
  definitions to fix are in upgrade-old-to-new-fe0b209d.u.

  Edit the file, then run:

      broken/upgrade-old-to-new> load upgrade-old-to-new-fe0b209d.u

  If `load` reports errors, fix them and run it again. When the
  file loads with no errors, run:

      broken/upgrade-old-to-new> update

  `update` saves the file's definitions into main, removes any
  definitions you deleted from the file, and deletes the
  temporary branch. To abandon the upgrade instead, run
  `cancel`.

  Note: Definitions listed in the file don't exist in the branch
  until a successful `update`.
```

``` unison :added-by-ucm upgrade-old-to-new-fe0b209d.u
-- The definitions below no longer typecheck after upgrading.
-- Please fix the errors, then run `update`.

user : Nat
user =
  use Nat +
  broken 1 + fine

```
