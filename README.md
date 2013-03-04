# TOML.jl: A [TOML](https://github.com/mojombo/toml) parser for [Julia](julialang.org).

```Julia
julia> require("TOML")

julia> TOML.parse(open("test.toml"))
[
  "clients"=>[
    "data"=>{{"gamma", "delta"}, {1, 2}},
    "hosts"=>{"alpha", "omega"}
  ],
  "database"=>[
    "enabled"=>true, "ports"=>{8001, 8001, 8002},
    "connection_max"=>5000, "server"=>"192.168.1.1"
  ],
  "title"=>"TOML Example",
  "servers"=>[
    "beta"=>["dc"=>"eqdc10","ip"=>"10.0.0.2"],
    "alpha"=>["dc"=>"eqdc10","ip"=>"10.0.0.1"]
  ],
  "owner"=>[
    "dob"=>Date(May 27, 1979 7:32:00 AM GMT),
    "organization"=>"GitHub",
    "name"=>"Tom Preston-Werner",
    "bio"=>"GitHub Cofounder & CEO\nLikes tater tots and beer."
  ]
]
```

The parser is strict, and will raise an error on unexpected input.

## API

```Julia
TOML.parse(src::Union(IOStream,String))
TOML.parse(src::Union(IOStream,String), options::Set)
```

The input must be convertible to UTF-8. Arbitrary byte strings are not supported, per spec.

## Options / extensions.

By default, the parser follows the spec as of [b098bd2b0s](https://github.com/mojombo/toml/tree/b098bd2b06920b69102bd4929cc5d7784893a123). You can override its behavior with the following options:

 * `:tripleQuotes`: Add support for python-style, triple quoted long string.

```CoffeeScript
document = """
FOOO
BAR
""" # returns "FOO\nBAR"
```
 * `:concatStrings`: Allow to split a string on several lines without inserting line breaks.

```CoffeeScript
long = "Let's prented this is " +
          "a long string."# returns "Let's prented this is a long string."
```
 * `:splitString`: Redundant with the above (the spec is still in flux).

```CoffeeScript
long = "Let's prented this is 
a long string."# returns "Let's prented this is a long string."
```
 * `:tuple`: Enable tuple support. Example: `("foo", 2, [])`
 * `:strictArray`: Enforce type homogeneity in arrays.

### Example:

```Julia
julia> TOML.parse("tup=(1,\"e\")",Set(:tuple))
["tup"=>(1,"e")]
```

## TODO:

Add the package to METADATA.jl
