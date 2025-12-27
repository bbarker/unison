# compile.js

Tests the `compile.js` command which compiles Unison terms to JavaScript.

``` ucm :hide
scratch/main> builtins.merge
```

## Basic compilation

Define a simple term and add it to the codebase:

``` unison
myValue : Nat
myValue = 42
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + myValue : Nat

  Run `update` to apply these changes to your codebase.
```

``` ucm
scratch/main> add

  Done.
```

Now compile it to JavaScript:

``` ucm
scratch/main> compile.js myValue /tmp/test-output.js

  Compiled myValue to /tmp/test-output.js
```

## Different literal types

Test Int literal:

``` unison
myInt : Int
myInt = -42
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + myInt : Int

  Run `update` to apply these changes to your codebase.
```

``` ucm
scratch/main> add

  Done.

scratch/main> compile.js myInt /tmp/test-int.js

  Compiled myInt to /tmp/test-int.js
```

Test Float literal:

``` unison
myFloat : Float
myFloat = 3.14159
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + myFloat : Float

  Run `update` to apply these changes to your codebase.
```

``` ucm
scratch/main> add

  Done.

scratch/main> compile.js myFloat /tmp/test-float.js

  Compiled myFloat to /tmp/test-float.js
```

Test Text literal:

``` unison
myText : Text
myText = "Hello, world!"
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + myText : Text

  Run `update` to apply these changes to your codebase.
```

``` ucm
scratch/main> add

  Done.

scratch/main> compile.js myText /tmp/test-text.js

  Compiled myText to /tmp/test-text.js
```

## Simple function with parameters

Test a function that takes parameters:

``` unison
add : Nat -> Nat -> Nat
add x y = x Nat.+ y
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + add : Nat -> Nat -> Nat

  Run `update` to apply these changes to your codebase.
```

``` ucm
scratch/main> add

  Done.

scratch/main> compile.js add /tmp/test-add.js

  Compiled add to /tmp/test-add.js
```

## Function calling another function

Test a function that calls another function:

``` unison
double : Nat -> Nat
double x = add x x
```

``` ucm :added-by-ucm
  Loading changes detected in scratch.u.

  + double : Nat -> Nat

  Run `update` to apply these changes to your codebase.
```

``` ucm
scratch/main> add

  Done.

scratch/main> compile.js double /tmp/test-double.js

  Compiled double to /tmp/test-double.js
```

## Pattern matching - Boolean

Test a function with Boolean pattern matching:

``` unison
isZero : Nat -> Boolean
isZero n = n == 0
```

``` ucm
scratch/main> add
scratch/main> compile.js isZero /tmp/test-iszero.js
```

## Pattern matching - if-then-else

Test a function with conditional logic:

``` unison
max : Nat -> Nat -> Nat
max a b = if a > b then a else b
```

``` ucm
scratch/main> add
scratch/main> compile.js max /tmp/test-max.js
```

## Recursion

Test a recursive function:

``` unison
factorial : Nat -> Nat
factorial n = if n == 0 then 1 else n Nat.* factorial (Nat.drop n 1)
```

``` ucm
scratch/main> add
scratch/main> compile.js factorial /tmp/test-factorial.js
```

## Error cases

Attempting to compile a non-existent term should show an error:

``` ucm :error
scratch/main> compile.js nonExistent /tmp/output.js

  ⚠️

  I don't know about that term.
```
