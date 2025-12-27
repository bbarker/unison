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

## Error cases

Attempting to compile a non-existent term should show an error:

``` ucm :error
scratch/main> compile.js nonExistent /tmp/output.js

  ⚠️

  I don't know about that term.
```
