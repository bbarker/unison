# Multiline Declaration Corpus Fixture

``` ucm :hide
> builtins.mergeio lib.builtins
```

``` unison
use lib.builtins

structural type Maybe a
  = Nothing
  -- declaration continuation comment
  | Just a

unique ability Store where
  get : Nat
  -- declaration continuation comment
  put : Nat -> Nat
```

``` ucm
> add
> view Maybe
> view Store
```
