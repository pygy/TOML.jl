module TOML

VERSION = "0.2.0"

include("datetime.jl")

DBG = false

macro debug (msg)
    if DBG
        :(println ($msg))
    end
end

type ParserState
    txt::UTF8String
    index::Integer
    line::Integer
    result::Dict{UTF8String,Any}
    cur_tbl::Dict{UTF8String,Any}
    tblarystack::Array
    BOM::Bool

    function ParserState(txt::UTF8String)
        @debug "ParserState(\n$(txt))"
        BOM = length(txt) > 0 && txt[1] == '\ufeff'  ? true : false
        maintbl = (UTF8String => Any)[]
        state = new(
            txt,         # subject
            BOM ? 4 : 1, # index. Strip the BOM if present.
            1,           # line
            maintbl,     # result
            maintbl,     # cur_tbl
            {},          # table array stack
            BOM
        )
        state
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
    func = seek_key(state)
    # trampoline
    while isa(func, Function)
        func = func(state)
    end
    return state.result
end

function seek_key (state::ParserState)
    @debug ("Seek Key\n")

    char = next_non_comment!(state)
    if char == :eof
        return :eof
    end
    if char != '['
        state.index -= 1
        key
    elseif state.txt[state.index] == '['
        state.index += 1
        tablearray
    else
        table
    end
end

const tabl = Regex("[ \t]*([^ \t\r\n][^\]\r\n]*)\]", Base.PCRE.ANCHORED)

function table (state::ParserState)
    m = match(tabl, state.txt, state.index)
    if m == nothing
        error("Badly formed table name.")
    end
    state.index += m.match.endof
    ks = strip(m.captures[1])

    if ks == ""
        error("Section name can't be empty")
    end

    @debug ("Section1: $ks")

    if contains(ks, "[")
        error("Opening brackets '[' are forbidden in table names.")
    end

    keys = map(strip, split(ks, "."))
    H = state.result
    for (i, k) in enumerate(keys)
        if k == ""
            error("Empty key name is not allowed in $k on line $(state.line)")
        end
        if haskey(H,k)
            if isa(H[k],Dict) && (
                i != length(keys) ||
                any(values(H[k])) do v ;; isa(v, Dict) end # a sub-dictionary has already been defined.
            )
                H = H[k]
            else # attempt to overwrite a table
                error("Key \"$k\" already defined in \"$(join(keys, '.'))\" on line $(state.line).")
            end
        else
            H[k] = (UTF8String => Any)[]
            H = H[k]
        end
    end
    endline!(state)
    state.cur_tbl = H
    seek_key
end



const tbar = Regex("[ \t]*([^ \t\r\n][^\]\r\n]*)\]\]", Base.PCRE.ANCHORED)

function tablearray (state::ParserState)
    m = match(tbar, state.txt, state.index)
    if m == nothing
        error("Badly formed table array name.")
    end
    state.index += m.match.endof
    ks = strip(m.captures[1])

    @debug ("Table array: $ks")

    if ks == ""
        error("Table array name can't be empty")
    end

    keys = map(strip, split(ks, "."))
    namepieces = String[]
    H = state.result

    for (i, k) in enumerate(keys)
        if k == ""
            error("Empty key name is not allowed in $k on line $(state.line)")
        end

        if haskey(H, k)
            if i < length(keys)
                @assert(isa(H[k], Union(Array{Dict{UTF8String, Any}, 1}, Dict{UTF8String, Any})),
                        "Attempt to overwrite key $(join(keys[1:i], '.')) on line $(state.line).")
                if isa(H[k], Dict)
                    H = H[k]
                else # H[k] is an array
                    H = last(H[k])
                end
            else
                @assert(isa(H[k], Array{Dict{UTF8String, Any}, 1}),
                        "Attempt to overwrite value with array on line $(state.line).")
                push!(H[k], (UTF8String => Any)[])
                H = last(H[k])
                break
            end
        else
            if i < length(keys)
                H[k] = (UTF8String => Any)[]
                H = H[k]
            else # we're done
                H[k] = [(UTF8String=>Any)[]]
                H = last(H[k])
                break
            end
        end
    end
    endline!(state)
    state.cur_tbl = H
    seek_key
end

const end_key =Regex("([^\n\r=]*)([\n\r=])", Base.PCRE.ANCHORED)

function key (state)
    @debug ("key : ")
    m = match(end_key, state.txt, state.index)
    state.index += m.match.endof

    if m.captures[2] != "="
        error("New lines are forbidden in key names. On line $(state.line).")
    end

    k = strip(m.captures[1])

    if k == ""
        error("Key name can't be empty")
    end

    @debug "  - $k"

    if haskey(state.cur_tbl, k)
        error("Attempt to redefine key \"$k\" on line $(state.line)")
    end

    state.cur_tbl[k] = value(state)
    endline!(state)
    seek_key
end

function value (state)
    @debug ("Value:")
    @debug state.txt[state.index:end]
    c = next_non_space!(state)
    if c == :eof || endlineP(char,state)
        error("Empty value on line $(state.line - 1)")
    end

    if c == '"'
        return string_value(state)
    elseif c == '['
        return array_value(state)
    elseif idem("true", state.txt, state.index - 1)
        state.index += 3
        @debug ("  - TRUE")
        return true
    elseif idem("false", state.txt, state.index - 1)
        state.index += 4
        @debug ("  - FALSE")
        return false
    elseif (d = match(date_pattern, state.txt, state.index - 1); d != nothing)
        state.index += 19
        return ymd_hms(map(parseint, d.captures)...,"UTC")
    elseif c == '-' || '0' <= c <= '9'
        state.index -= 1
        return numeric_value(state)
    else
        error("Invalid value on line $(state.line)")
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

unescape (chr::Char) = get(valid_escape, chr, :invalid)

function string_value (state::ParserState)
    buf = (Char)[]
    string_chunk(state,buf)
    Base.utf8(CharString(buf))
end

const str_pattern = Regex("", Base.PCRE.ANCHORED)
function string_chunk (state::ParserState,buf::Array{Char,1})
    @debug ("+++ Start String Chunk\n")
    while (chr = nextchar!(state)) != '"'
        if chr == :eof
            error("Unexpected end of file in a string.")
        end
        if endlineP(chr, state)
            error("Unexpected end of file/line in a string.")
        end
        if chr == '\\'
            chr = nextchar!(state)
            if chr == 'u'
                num = (nextchar!(state),nextchar!(state),nextchar!(state),nextchar!(state))
                chr = parseint(string(num...), 16)
            else
                chr = unescape(chr)
                if chr == :invalid
                    error("Invalid escape sequence in string.")
                end
            end
        end
        if chr == '\0'
            #WASDIWIDOU?
        end
        push!(buf,chr)
    end
    @debug ("*** End String Chunk")
end

function numeric_value (state::ParserState)
    flt = false
    acc = (Char)[]
    if getchar(state) == '-'
        push!(acc,'-')
        nextchar!(state)
    end
    local c
    while (c=nextchar!(state); c!=:eof && '0'<=c<='9')
        @debug ("NumVAl $c")
        push!(acc,c)
    end

    if c != '.'
        state.index -= c==:eof ? 0 : 1
        return parseint(Int64, string(acc...))
    end

    push!(acc,'.')
    while (c=nextchar!(state);  c!=:eof && '0'<=c<='9')
        push!(acc,c)
    end
    state.index -= c==:eof ? 0 : 1
    if last(acc) == '.'
        error("Badly formed number on line $(state.line).")
    end
    return parsefloat(Float64, string(acc...))
end

arlv = 0

function array_value(state)
    global arlv
    @debug "Array level $(arlv += 1)"
    ary = {}
    local typ = Any
    while next_non_comment!(state) != ']'
        @debug ("array_value", state.index)
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
            error("Bad type in Array on line $(state.line).")
        end
        # handle the coma:
        c = next_non_comment!(state)
        if c == ']'
            break
        elseif c != ','
            error("Syntax error in array. Coma expected on line $(state.line).")
        end
    end
    @debug "// Array level $(arlv -= 1)"
    return ary
end

end ## module TOML
