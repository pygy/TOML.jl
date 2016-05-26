module TestTOML

using TOML
using JSON
using Compat

function parsedate(str::AbstractString) #for the tests.
    d = match(TOML.date_pattern, str)
    if d == nothing ;; error("Invalid date string.") end
    TOML.DateTime(map(parseint, d.captures)...)
end

testdir = Base.source_path()[1:end-8]

list = readdir("$testdir/valid")
valid = map(filter(a-> a[end-4:end]==".toml", list)) do s
    s[1:end-5]
end

invalid = readdir("$testdir//invalid")

tml = ""
jsn = ""

if isa(STDIN,Base.TTY)
    eval(Base,:(have_color = $(contains(get(ENV,"TERM",""), "xterm"))))
end

exitstatus = 0

function display_error(er)
    Base.with_output_color(:red, STDOUT) do io
        println(io, "ERROR: ", er)
    end
end

function display_success(msg)
    Base.with_output_color(:green, STDOUT) do io
        println(io, msg)
    end
end

# valid = filter(valid) do n ;; match(r"table-array", n) == nothing end

function test()
    for t in valid
        print("Valid $t: ")
            open(string(testdir, "/valid/", t, ".toml")) do tml
                open(string(testdir, "/valid/", t, ".json")) do jsn
                try
                    tml = TOML.parse(readall(tml))
                    jsn = jsn2data(JSON.parse(readall(jsn)))
                    if jsn == tml
                        display_success("Ok")
                    else
                        display_error("unexpected result.\nTOML:\n$tml\n\nJSON:\n$jsn\n")
                        global exitstatus = 1
                    end
                catch err
                    if !isa(err, TOML.TOMLError)
                        rethrow(err)
                    end
                    display_error("couldn't be parsed.\n" * repr(err))
                    global exitstatus = 1
                end
            end
        end
    end

    for t in invalid
        println("Invalid $t:")
        open(string(testdir, "/invalid/", t)) do tml
            try
                tml = TOML.parse(readall(tml))
                display_error("should have failed but didn't.")
                print(tml)
                global exitstatus = 1
            catch err
                if !isa(err, TOML.TOMLError)
                    rethrow(err)
                end
                display_success("  " * repr(err))
            end
        end
    end
end

jsnval = @compat Dict{ASCIIString,Function}(
    "string" =>identity,
    "float"  =>parsefloat,
    "integer"=>parseint,
    "datetime"   => parsedate,
    "array"  => (a -> map(jsn2data, a)),
    "bool"   => (b -> b == "true")
)

function jsn2data(jsn)
    # println(jsn)
    if "type" in keys(jsn)
        jsnval[jsn["type"]](jsn["value"])
    else
        @compat Dict{Any,Any}([k => jsn2data(v) for (k, v) in jsn])
    end
end


end # module TestTOML

TestTOML.test()

exit(TestTOML.exitstatus)
