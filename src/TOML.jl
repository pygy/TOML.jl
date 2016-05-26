module TOML

VERSION = v"0.1.2"

using Compat


if Base.VERSION >= v"0.4.0-dev+5050"
    anchored_regex(r) = Regex(r, Base.PCRE.ANCHORED, 0)
else
    anchored_regex(r) = Regex(r, Base.PCRE.ANCHORED)
end


include("datetime.jl")


type ParserState
    subject::UTF8String
    index::Integer
    line::Integer
    result::Dict{UTF8String, Any}
    cur_tbl::Dict{UTF8String, Any}
    tbl_names::Set{UTF8String}

    function ParserState{T<: @compat Union{AbstractString, Array{UInt8, 1}}}(subject::T)
        if isa(subject, @compat Union{ByteString, Array{UInt8, 1}}) && !isvalid(UTF8String, subject)
            throw(TOMLError("$T with invalid UTF-8 byte sequence."))
        end
        try
            subject = convert(UTF8String, subject)
        catch
            throw(TOMLError("Couldn't convert $T to UTF8String " *
                "(no method convert(Type{UTF8String}, $T))."))
        end
        BOM = length(subject) > 0 && subject[1] == '\ufeff'  ? true : false
        maintbl = Dict{UTF8String,Any}()
        new(
            subject,
            BOM ? 4 : 1,      # index. Strip the BOM if present.
            1,                # line
            maintbl,          # result
            maintbl,          # cur_tbl
            Set{UTF8String}() # tbl_names
        )
    end
end


include("util.jl")


function parse(subject:: @compat Union{AbstractString, Array{UInt8, 1}})
    try
        state = ParserState(subject)
        while true
            char = next_non_comment!(state)
            if char == :eof
                break
            elseif char != '['
                state.index -= 1
                key(state)
            elseif getchar(state) == '['
                state.index += 1
                table_array(state)
            else
                table(state)
            end
        end
        state.result
    catch err
        (isa(err, TOMLError) ? throw : rethrow)(err)
    end
end


const table_pattern = anchored_regex("[ \t]*([^ \t\r\n][^\]\r\n]*)\]")

function table(state::ParserState)
    m = match(table_pattern, state.subject, state.index)
    if m == nothing
        _error("Malformed table name", state)
    end
    state.index += m.match.endof
    ks = strip(m.captures[1])
    if contains(ks, "[")
        _error("Opening brackets '[' are forbidden in table names", state)
    end
    keys = split(ks, ".")
    tbl = state.result
    for (i, k) in enumerate(keys)
        if k == ""
            _error("Empty key name is not allowed in $ks", state)
        end
        if haskey(tbl, k)
            if isa(tbl[k], Dict) && (
                i != length(keys) ||
                !(join(keys, ".") in state.tbl_names)
            )
                tbl = tbl[k]
            else
                _error("Key \"$k\" already defined", state)
            end
        else
            tbl[k] = Dict{UTF8String,Any}()
            tbl = tbl[k]
        end
    end
    push!(state.tbl_names, join(keys, "."))
    endline!(state)
    state.cur_tbl = tbl
end


const table_array_pattern = anchored_regex("[ \t]*([^ \t\r\n]?[^\]\r\n]*)\]\]")

function table_array(state::ParserState)
    m = match(table_array_pattern, state.subject, state.index)
    if m == nothing
        _error("Malformed table array name", state)
    end
    state.index += m.match.endof
    ks = strip(m.captures[1])
    keys = split(ks, ".")
    tbl = state.result
    for (i, k) in enumerate(keys)
        if k == ""
            _error("Empty key name is not allowed in $ks", state)
        end
        if haskey(tbl, k)
            if i < length(keys)
                if !isa(tbl[k], @compat Union{Array{Dict{UTF8String, Any}, 1}, Dict{UTF8String, Any}})
                    _error("Attempt to overwrite key $(join(keys[1:i], '.'))", state)
                end
                if isa(tbl[k], Dict)
                    tbl = tbl[k]
                else # tbl[k] is an array
                    tbl = last(tbl[k])
                end
            else
                if !isa(tbl[k], Array{Dict{UTF8String, Any}, 1})
                    _error("Attempt to overwrite value with array", state)
                end
                push!(tbl[k], Dict{UTF8String,Any}())
                tbl = last(tbl[k])
                break
            end
        else
            if i < length(keys)
                tbl[k] = Dict{UTF8String,Any}()
                tbl = tbl[k]
            else # we're done
                tbl[k] = [Dict{UTF8String,Any}()]
                tbl = last(tbl[k])
                break
            end
        end
    end
    endline!(state)
    state.cur_tbl = tbl
end


const key_pattern = anchored_regex("([^\n\r=]*)([\n\r=])")

function key(state)
    m = match(key_pattern, state.subject, state.index)
    if m == nothing
        _error("Unexpected end of file", state)
    end
    state.index += m.match.endof
    if m.captures[2] != "="
        _error("New lines are forbidden in key names", state)
    end
    k = strip(m.captures[1])
    if k == ""
        _error("Key name can't be empty", state)
    end
    if haskey(state.cur_tbl, k)
        _error("Attempt to redefine key \"$k\"", state)
    end
    state.cur_tbl[k] = value(state)
    endline!(state)
end


function value(state)
    c = next_non_space!(state)
    if c == :eof || c == '\r' || c == '\n'
        _error("Value expected", state)
    end
    if c == '"'
        return string_value(state)
    elseif c == '['
        return array_value(state)
    elseif idem("true", state.subject, state.index - 1)
        state.index += 3
        return true
    elseif idem("false", state.subject, state.index - 1)
        state.index += 4
        return false
    elseif (d = match(date_pattern, state.subject, state.index - 1); d != nothing)
        state.index += 19
        return ymd_hms(map(s -> Base.parse(Int, s), d.captures)..., "UTC")
    elseif c == '-' || '0' <= c <= '9'
        state.index -= 1
        return numeric_value(state)
    else
        _error("Invalid value", state)
    end
end


valid_escape = @compat Dict{Char,Char}(
    '0'  => '\0',
    '"'  => '"',
    '\\' => '\\',
    '/' => '/',
    'b'  => '\b',
    'f'  => '\f',
    'n'  => '\n',
    'r'  => '\r',
    't'  => '\t',
)

function string_value(state::ParserState)
    buf = (Char)[]
    while (chr = nextchar!(state)) != '"'
        if chr == :eof
            _error("Premature end of file in a string", state)
        end
        if chr == '\r' || chr == '\n'
            _error("Unexpected end of line in a string", state)
        end
        if chr == '\\'
            chr = nextchar!(state)
            if chr == 'u'
                num = (nextchar!(state), nextchar!(state), nextchar!(state), nextchar!(state))
                try
                    chr = Base.parse(Int, string(num...), 16)
                catch
                    _error("Invalid Unicode escape sequence '\\u$(string(num...))'", state)
                end
            else
                unesc = chr
                chr = get(valid_escape, chr, :invalid)
                if chr == :invalid
                    _error("Invalid escape sequence '\\$unesc' in string", state)
                end
            end
        end
        push!(buf, chr)
    end
    Base.utf8(buf)
end


function numeric_value(state::ParserState)
    NumTyp = Int64
    acc = (Char)[]
    firstdigit = 1
    if getchar(state) == '-'
        push!(acc, '-')
        nextchar!(state)
        firstdigit = 2
    end
    local c
    while (c=nextchar!(state); c!=:eof && '0'<=c<='9')
        push!(acc, c)
    end
    if c == '.'
        push!(acc, '.')
        while (c=nextchar!(state);  c!=:eof && '0'<=c<='9')
            push!(acc, c)
        end
        if last(acc) == '.'
            _error("Malformed number", state)
        end
        NumTyp = Float64
    end
    state.index -= c==:eof ? 0 : 1

    num = 0
    try
        numrepr = string(acc...)
        num = Base.parse(NumTyp, numrepr)
    catch err
        _error("Couldn't parse number ($(repr(err)))", state)
    end
    num
end


function array_value(state)
    ary = Any[]
    local typ = Any
    while next_non_comment!(state) != ']' # covers empty arrays and trailing comas
        state.index -= 1
        val = value(state)
        if length(ary) == 0
            typ = typeof(val)
            typ = typ <: Array ? Array : typ
            ary = (typ)[]
        end
        if isa(val, typ)
            push!(ary, val)
        else
            _error("Mixed types in array: expected $typ, found $(typeof(val))", state)
        end
        c = next_non_comment!(state)
        if c == ']'
            break
        elseif c != ','
            _error("Syntax error in array. Coma expected", state)
        end
    end
    ary
end

end ## module TOML
