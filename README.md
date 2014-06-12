## [TOML.jl][tomljl]

A [TOML v0.2.0][toml] parser for [Julia][julia].

Julia v0.2: [![Build Status](http://iainnz.github.io/packages.julialang.org/badges/TOML_0.2.svg)][buildstatusjulia03] — Julia v0.3: [![Build Status](http://iainnz.github.io/packages.julialang.org/badges/TOML_0.3.svg)][buildstatusjulia03]

[tomljl]: https://github.com/pygy/TOML.jl
[toml]: https://github.com/mojombo/toml
[julia]: https://julialang.org
[buildstatusjulia02]: http://pkg.julialang.org/?pkg=TOML&ver=0.2
[buildstatusjulia03]: http://pkg.julialang.org/?pkg=TOML&ver=0.3

### Usage:

```Julia
julia> require("TOML")

julia> TOML.parse(readall("etc/example.toml"))
[
  "clients"=>[
    "data"=>[["gamma", "delta"], [1, 2]],
    "hosts"=>["alpha", "omega"]
  ],
  "database"=>[
    "enabled"=>true, "ports"=>[8001, 8001, 8002],
    "connection_max"=>5000, "server"=>"192.168.1.1"
  ],
  "title"=>"TOML Example",
  "servers"=>[
    "beta"=>["dc"=>"eqdc10","ip"=>"10.0.0.2"],
    "alpha"=>["dc"=>"eqdc10","ip"=>"10.0.0.1"]
  ],
  "owner"=>[
    "dob"=>TOML.DateTime(1979, 5, 27, 7, 32, 0),
    "organization"=>"GitHub",
    "name"=>"Tom Preston-Werner",
    "bio"=>"GitHub Cofounder & CEO\nLikes tater tots and beer."
  ]
]
```

The input must be convertible to UTF-8. Byte sequences that represent an invalid UTF-8 string will be rejected, per spec.

The TOML types are converted to their natural Julia counterparts (except datetimes, see below). Arrays are typed.

The parser is strict, and will throw a `TOMLError` on malformed input.


### DateTime objects:

To keep the dependencies low (the Calendar package is very slow to
load), and waiting for the implemetation of `Timestamp`s in the `Base` Julia library, TOML `DateTime`s are
currently converted to `TOML.DateTime` objects.

```Julia
immutable DateTime
    year::Int
    month::Int
    date::Int
    hour::Int
    minute::Int
    second::Int
end
```

### Licenses...

...should be written for people, to read, and only incidentally for lawyers, to prosecute.

Thus, Romantic WTF and MIT, respectively.
