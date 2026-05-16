# Tab Keyword Whitespace Parse Success Fixture

``` ucm :hide
> builtins.mergeio lib.builtins
```

``` unison
use lib.builtins

use	Nat +
type	Maybe a = Nothing | Just a
ability	Store where
  get : Nat

main = 42
```

``` ucm
> add
> view main
> view Maybe
> view Store
```
