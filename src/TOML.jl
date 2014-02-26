module TOML

VERSION = v"0.1.0"

include("datetime.jl")


type ParserState
    txt::UTF8String
    index::Integer
    line::Integer
    result::Dict{UTF8String,Any}
    cur_tbl::Dict{UTF8String,Any}

    function ParserState(txt::UTF8String)
        BOM = length(txt) > 0 && txt[1] == '\ufeff'  ? true : false
        maintbl = (UTF8String => Any)[]
        new(
            txt,         # subject
            BOM ? 4 : 1, # index. Strip the BOM if present.
            1,           # line
            maintbl,     # result
            maintbl      # cur_tbl
        )
    end

    function ParserState(txt::String)
        # try
            txt = ParserState(Base.utf8(txt))
        # catch
        #     error("TOML.parse(): Input conversion to UTF-8 failed.")
        # end
    end

    ParserState(file::IOStream) = ParserState(readall(file))
end


include("util.jl")


function parse(txt)
    state = ParserState(txt)
    while true
        char = next_non_comment!(state)
        if char == :eof
            break
        elseif char != '['
            state.index -= 1
            key(state)
        elseif state.txt[state.index] == '['
            state.index += 1
            tablearray(state)
        else
            table(state)
        end
    end
    return state.result
end


const table_pattern = Regex("[ \t]*([^ \t\r\n][^\]\r\n]*)\]", Base.PCRE.ANCHORED)

function table (state::ParserState)
    m = match(table_pattern, state.txt, state.index)
    if m == nothing
        _error("Badly formed table name", state)
    end
    state.index += m.match.endof
    ks = strip(m.captures[1])
    if ks == ""
        _error("Section name can't be empty", state)
    end
    if contains(ks, "[")
        _error("Opening brackets '[' are forbidden in table names", state)
    end
    keys = split(ks, ".")
    keys = map!(strip, keys, {})
    tbl = state.result
    for (i, k) in enumerate(keys)
        if k == ""
            _error("Empty key name is not allowed in $k", state)
        end
        if haskey(tbl,k)
            if isa(tbl[k],Dict) && (
                i != length(keys) ||
                any(values(tbl[k])) do v ;; isa(v, Dict) end # a sub-dictionary has already been defined.
            )
                tbl = tbl[k]
            else 
                _error("Key \"$k\" already defined in \"$(join(keys, '.'))\"", state)
            end
        else
            tbl[k] = (UTF8String => Any)[]
            tbl = tbl[k]
        end
    end
    endline!(state)
    state.cur_tbl = tbl
end


const table_array_pattern = Regex("[ \t]*([^ \t\r\n][^\]\r\n]*)\]\]", Base.PCRE.ANCHORED)

function tablearray (state::ParserState)
    m = match(table_array_pattern, state.txt, state.index)
    if m == nothing
        _error("Badly formed table array name", state)
    end
    state.index += m.match.endof
    ks = strip(m.captures[1])
    if ks == ""
        _error("Table array name can't be empty", state)
    end
    keys = map(strip, split(ks, "."))
    namepieces = String[]
    tbl = state.result
    for (i, k) in enumerate(keys)
        if k == ""
            _error("Empty key name is not allowed in $k", state)
        end
        if haskey(tbl, k)
            if i < length(keys)
                if !isa(tbl[k], Union(Array{Dict{UTF8String, Any}, 1}, Dict{UTF8String, Any}))
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
                push!(tbl[k], (UTF8String => Any)[])
                tbl = last(tbl[k])
                break
            end
        else
            if i < length(keys)
                tbl[k] = (UTF8String => Any)[]
                tbl = tbl[k]
            else # we're done
                tbl[k] = [(UTF8String=>Any)[]]
                tbl = last(tbl[k])
                break
            end
        end
    end
    endline!(state)
    state.cur_tbl = tbl
end


const key_pattern =Regex("([^\n\r=]*)([\n\r=])", Base.PCRE.ANCHORED)

function key (state)
    m = match(key_pattern, state.txt, state.index)
    if m == nothing
        _error("Badly formed table key name", state)
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


function value (state)
    c = next_non_space!(state)
    if c == :eof || endlineP(char,state)
        state.line -= 1
        _error("Empty value", state)
    end
    if c == '"'
        return string_value(state)
    elseif c == '['
        return array_value(state)
    elseif idem("true", state.txt, state.index - 1)
        state.index += 3
        return true
    elseif idem("false", state.txt, state.index - 1)
        state.index += 4
        return false
    elseif (d = match(date_pattern, state.txt, state.index - 1); d != nothing)
        state.index += 19
        return ymd_hms(map(parseint, d.captures)...,"UTC")
    elseif c == '-' || '0' <= c <= '9'
        state.index -= 1
        return numeric_value(state)
    else
        _error("Invalid value", state)
    end
end


valid_escape = [
    '0'  => '\0',
    '"'  => '"',
    '\\' => '\\',
    '/' => '/',
    'b'  => '\b',
    'f'  => '\f',
    'n'  => '\n',
    'r'  => '\r',
    't'  => '\t',
]

function string_value (state::ParserState)
    buf = (Char)[]
    while (chr = nextchar!(state)) != '"'
        if chr == :eof
            _error("Unexpected end of file in a string", state)
        end
        if endlineP(chr, state)
            _error("Unexpected end of line in a string", state)
        end
        if chr == '\\'
            chr = nextchar!(state)
            if chr == 'u'
                num = (nextchar!(state),nextchar!(state),nextchar!(state),nextchar!(state))
                try
                    chr = parseint(string(num...), 16)
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
        push!(buf,chr)
    end
    Base.utf8(CharString(buf))
end


function numeric_value (state::ParserState)
    parsenum = parseint
    NumTyp = Int64
    acc = (Char)[]
    if getchar(state) == '-'
        push!(acc,'-')
        nextchar!(state)
    end
    local c
    while (c=nextchar!(state); c!=:eof && '0'<=c<='9')
        push!(acc,c)
    end
    if c == '.'
        push!(acc,'.')
        while (c=nextchar!(state);  c!=:eof && '0'<=c<='9')
            push!(acc,c)
        end
        if last(acc) == '.'
            _error("Badly formed number", state)
        end
        parsenum, NumTyp = parsefloat, Float64
    end
    state.index -= c==:eof ? 0 : 1
    parsenum(NumTyp, string(acc...))
end


function array_value(state)
    ary = {}
    local typ = Any
    while next_non_comment!(state) != ']'
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
            _error("Bad type in Array", state)
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
