``` ucm :hide
scratch/main> builtins.merge
```

``` unison
foo = 123

bar = 456

mytest = [Ok "ok"]
```

``` ucm
scratch/main> add
scratch/main> edit foo bar
scratch/main> edit mytest
```

``` ucm :error
scratch/main> edit missing
```

``` ucm :hide
scratch/main> project.delete scratch
```

# `edit2`

The `edit2` command adds to the current fold, and takes care not to add definitions that are already in the file.

``` ucm :hide
scratch/main> builtins.mergeio lib.builtin
```

This stanza does nothing for some reason (transcript runner bug?), so we repeat it twice.

``` unison
foo = 17
bar = 18
baz = 19
```

``` unison
foo = 17
bar = 18
baz = 19
```

``` ucm
scratch/main> add
```

``` unison
foo = 17
bar = 18
```

``` ucm
scratch/main> edit2 bar baz
```

``` ucm :hide
scratch/main> project.delete scratch
```
