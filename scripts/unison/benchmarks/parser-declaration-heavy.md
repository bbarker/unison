# Parser Declaration Heavy Fixture

``` ucm :hide
> builtins.mergeio lib.builtins
```

``` unison
use lib.builtins

unique type Maybe a = Nothing | Just a
structural type Pair a b = Pair a b
unique[q9d1rl3aatgsa0cndefhert8i6ps1ol7] type Tagged a = Tagged a
unique[kluar3l6itvegkkqpfs6kfkuvcafpi82] type Wrapped t = Wrapped t
structural ability Store where
  get : Nat
  put : Nat -> Nat
unique[rb45pr524qqstpni5nj20nhpqhahls02] ability Logger where
  info : Text -> ()

f x = x
g x y = (x, y)
h : Nat -> Nat
h n = n + 1
k : Text
k = "x -- y"

data0 : Nat
data0 = 0
data1 : Nat
data1 = 1
data2 : Nat
data2 = 2
data3 : Nat
data3 = 3
data4 : Nat
data4 = 4
```

``` ucm
> add
> view Maybe
> view Tagged
> view Logger
```
