# Scientific Notation Uppercase Parse Success Fixture

``` ucm :hide
> builtins.mergeio lib.builtins
```

``` unison
use lib.builtins

expUpper = 1E+3
expUpperNeg = -1.2E-3
compactPlus = 1+1
plusSpaceAfter = 1+ 1
signedStandalone = +1
signedList = [+1,+1]
```

``` ucm
> add
> view expUpper
> view expUpperNeg
> view compactPlus
> view plusSpaceAfter
> view signedStandalone
> view signedList
```
