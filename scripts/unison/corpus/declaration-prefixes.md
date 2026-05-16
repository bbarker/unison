# Declaration Prefixes Corpus Fixture

``` ucm :hide
> builtins.mergeio lib.builtins
```

``` unison
use lib.builtins

unique type Maybe a = Nothing | Just a
unique[q9d1rl3aatgsa0cndefhert8i6ps1ol7] type Tagged a = Tagged a
unique[q9d1rl3aatgsa0cndefhert8i6ps1ol7]type TightTagged a = TightTagged a
structural ability Store where
  get : Nat
unique[kluar3l6itvegkkqpfs6kfkuvcafpi82] ability Flag where
  ping : Nat
unique[kluar3l6itvegkkqpfs6kfkuvcafpi82]ability TightFlag where
  ping : Nat

main : Nat
main = 42
```

``` ucm
> add
> view Maybe
> view Tagged
> view TightTagged
> view Store
> view Flag
> view TightFlag
```
