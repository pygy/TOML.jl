## TOML.jl: A [TOML v0.2.0](https://github.com/mojombo/toml) parser for [Julia](https://github.com/JuliaLang/julia).

```Julia
julia> require("TOML")

julia> TOML.parse(readall("etc/example.toml"))
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

The input must be convertible to UTF-8. Arbitrary byte strings are not supported, per spec.

The parser is strict, and will raise an error on unexpected input.
