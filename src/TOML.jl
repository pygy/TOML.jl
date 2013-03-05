
module TOML
require("Calendar")
using Base
using Calendar
# version = ""

DBG = false

macro debug (msg)
    if DBG
        :(print ($msg))
    end
end

default_options=Set()

type ParserState
    txt::UTF8String
    index::Integer
    line::Integer
    result::Dict{UTF8String,Any}
    stack::Array{Union(Dict,Array)}
    options
    BOM::Bool

    function ParserState(txt::String, options::Any) 
        utf = ""
        try
            utf = Base.utf8(txt)
        catch
            error("TOML.parse(): Input conversion to UTF-8 failed.")
        end
        ParserState(utf, options)
    end

    function ParserState(txt::UTF8String, options::Any)
        BOM = length(txt) > 0 && txt[1] == '\ufeff'  ? true : false
        ParserState(
            txt,
            BOM ? 4 : 1, #index. Strip the BOM if present.
            1, #line
            (UTF8String => Any)[], #result
            options,
            BOM
        )
    end

    ParserState(txt, index, line, result, options, BOM) = new(txt, index, line, result, (Union(Dict,Array))[result], options, BOM)

    ParserState(file::IOStream, options::Any) = ParserState(readall(file), options)

    ParserState(src::Any) = ParserState(src, default_options)
end

function idem(needle::String, haystack::String, idx)
    for c1 in needle
        if done(haystack, idx)
            return false
        end
        c2, idx = next(haystack, idx)
        if !(c2 == c1 || (c1 == '0' && ('0' <= c2 <= '9')))
            return false
        end
    end
    return true
end

indexify(a) =  ( i = 0; map(e->(i+=1,e),a) )

utf8(chars::Array{Char,1}) = utf8(CharString(chars))

getchar(state::ParserState) = state.txt[state.index]

# function nextchar(state::ParserState) 
#     if !done(state.txt, state.index)
#         next(state.txt, state.index)
#     else
#         (:eof, state.index)
#     end
# end



function nextchar!(state::ParserState) 
    if done(state.txt, state.index)
        return :eof
    end
    (char, state.index) = next(state.txt, state.index)
    @debug ("Char: $char\n")
    char
end

function next_non_space! (state::ParserState)
    while true
        c = nextchar!(state)
        if c != ' ' && c != '\t'
            return c
        end
    end
end

function endlineP (c, state::ParserState)
    if c == '\r' && state.txt[state.index + 1] == '\n'
        nextchar!(state)
    end
    if c == '\r' || c == '\n'
        state.line += 1
        @debug ("======= End Line\n")
        return true
    else
        return false
    end
end

function endline! (state::ParserState)
    c = next_non_space!(state);
    if endlineP(c, state)
        return
    elseif c == :eof
        return
    elseif c == '#'
        while (c = nextchar!(state); !endlineP(c, state) && c != :eof)
            true
        end
        return
    else
        error("Illegal character \'$c\' on line $(state.line).")
    end
end

function next_non_comment! (state::ParserState)
    local in_comment = false
    while true
        c = nextchar!(state)
        if in_comment
            if c == :eof
                return c
            elseif endlineP(c, state)
                in_comment = false
            end
        else
            if c == '#'
                in_comment = true
            elseif  !endlineP(c,state) && c != ' ' && c != '\t'
                return c
            end
        end
    end
end

function parse(txt, options)
    state = ParserState(txt, options)
    func = seek_key(state)
    while isa(func, Function)
        func = func(state)
    end
    return state.result
end

parse(txt) = parse(txt,default_options)

# function rewind (state::ParserState)
#         i = state.index - 1
#         while state.txt.data[i] & 0xc0 == 0xa0
#             i -= 1
#         end
#         state.index = i
# end

function seek_key (state::ParserState)
    @debug ("Seek Key\n")

    char = next_non_comment!(state)
    if char == :eof
        return :eof
    end
    if char == '['
        section
    else
        state.index -= 1;
        key
    end
end

function section (state::ParserState)
    r = r"[ \t]*([^ \t\r\n][^\]\r\n]*)\]"
    k = match(r,state.txt,state.index)
    if k == nothing
        error("Badly formed section.")
    end
    @debug ("Section1: $k\n")
    state.index += length(k.match.data) 
    trim = r"(.*[^ \t])[ \t]*$"
    m = match( trim, k.captures[1] )
    ks = m.captures[1]

    if length(ks) == 0
        error("Section name can't be empty")
    end
    keys = split(ks,".")
    H = state.result
    for (i, k) in indexify(keys)
        if k == ""
            error("Empty key name is not allowed in $ks on line $(state.line)")
        end
        if has(H,k)
            if isa(H[k],Dict) && i != length(keys)
                H = H[k]
            else
                error("Key \"$k\" already defined in \"$(join(keys, '.'))\" on line $(state.line).")
            end
        else
            H[k] = (UTF8String => Any)[]
            H = H[k]
        end
    end
    endline!(state)
    state.stack = (Union(Dict,Array))[H]
    seek_key
end

end_key =Set('\n','\r','=')

function key (state)
    @debug ("key\n")
    i1 = state.index
    c = nextchar!(state)
    while !has(end_key, c)
        c = nextchar!(state)
    end

    if c != '='
        error("New lines are forbidden in key names. On line $(state.line).")
    end

    k = state.txt[i1:state.index-2]
    @debug "$k|\n"
    if k == nothing
        error("Badly formed key.")
    end
    

    trim = r"(.*[^ \t])[ \t]*$"
    k = match( trim, k).captures[1]
    if k == ""
        error("Key name can't be empty")
    end

    @debug ("Key: $k\n")
    if has(last(state.stack), k)
        error("Attempt to redefine key \"$k\" on line $(state.line)")
    end
    last(state.stack)[k] = value(state)
    endline!(state)
    seek_key
end

date_pattern = r"(\d\d\d\d)-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)Z"

function value (state)
    @debug ("Value\n")
    c = next_non_space!(state)
    if c == :eof || endlineP(char,state)
        error("Empty value on line $(state.line - 1)")
    end

    if c == '"'
        return string_value(state)
    elseif c == '['
        return array_value(state)
    elseif has(state.options, :tuple) && c == '('
        return tuple_value(state)
    elseif idem("true", state.txt, state.index - 1)
        state.index += 3
        @debug ("TRUE\n")
        return true
    elseif idem("false", state.txt, state.index - 1)
        state.index += 4
        @debug ("FALSE\n")
        return false
    elseif idem("0000-00-00T00:00:00Z", state.txt, state.index - 1)
        d = match(date_pattern, state.txt, state.index - 1)
        d = Calendar.ymd_hms(map(parse_int, d.captures)...,"UTC")
        state.index += 19
        return Date(d)
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
    'n'  => '\n',
    'r'  => '\r',
    't'  => '\t',
]

unescape (chr::Char) = has(valid_escape, chr) ? valid_escape[chr] : :invalid

function string_value (state::ParserState)
    if has(state.options,:tripleQuotes) && state.txt[state.index] == '"' && state.txt[state.index + 1] == '"'
        return long_string_value(state)
    end
    buf = (Char)[]
    string_chunk(state,buf)
    if has(state.options,:concatStrings)
        while next_non_space!(state) == '+'
            @debug ("More String")
            if next_non_comment!(state) == '"'
                string_chunk(state,buf)
            else
                error("String chunk expected on line $(state.line).")
            end
        end
        state.index -= 1
    end


    Base.utf8(CharString(buf))
end

function string_chunk (state::ParserState,buf::Array{Char,1})
    @debug ("+++ Start String Chunk\n")
    while (chr = nextchar!(state)) != '"'
        if chr == :eof
            error("Unexpected end of file in a string.")
        end
        while endlineP(chr, state)
            if has(state.options, :splitString)
                chr = nextchar!(state)
            else
                error("Unexpected end of file/line in a string.")
            end
        end
        if chr == '\\'
            chr = nextchar!(state)
            if chr == 'x'
                chr = parse_int(string([nextchar!(state),nextchar!(state)]...))
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
    @debug ("*** End String Chunk\n")
end


function long_string_value (state::ParserState)
    state.index += 2 # skip the remaining quotes.
    char = next_non_space!(state)
    if !endlineP(char,state)
        error ("Unexpected character \"$char\"on line $(state.line - 1).\n"
             * "A multi-line string starts on the line following the three quotes.")
    end
    buf = (Char)[]
    while (char = nextchar!(state); 
    !(endlineP(char,state)
    && state.txt[state.index] == '"' 
    && state.txt[state.index + 1] == '"'
    && state.txt[state.index + 2] == '"'))
        push!(buf, char)
        if char == '\r' && state.txt[state.index - 1] == '\n' # handle CRLF.
            push!(buf,'\n') 
        end
    end
    state.index += 3 # skip the three quotes
    Base.utf8(CharString(buf))
end


    #     fl = m.match
    #     state.index += length(fl.data) - 1
    #     return parse_float(Float64, fl)
    # elseif (m = match(r"-?\d+", state.txt, state.index - 1)) != nothing
    #     i = m.match
    #     state.index += length(i.data) - 1
    #     return parse_int(Int64, i)


function numeric_value (state::ParserState)
    flt = false
    acc = (Char)[]
    if getchar(state) == '-'
        push!(acc,'-')
        nextchar!(state)
    end
    local c
    while (c=nextchar!(state); c!=:eof && '0'<=c<='9')
        @debug ("NumVAl $c\n")
        push!(acc,c)
    end
    
    if c != '.'
        state.index -= c==:eof ? 0 : 1
        return parse_int(Int64, string(acc...))
    end
    
    push!(acc,'.')
    while (c=nextchar!(state);  c!=:eof && '0'<=c<='9')
        push!(acc,c)
    end
    state.index -= c==:eof ? 0 : 1
    if last(acc) == '.'
        error("Badly formed number on line $(state.line).")
    end
    return parse_float(Float64, string(acc...))
end

arlv = 0

function array_value(state)
    global arlv
    arlv +=1
    @debug "Array level $arlv\n"
    ary = {}
    local typ = Any
    while next_non_comment!(state) != ']'
        state.index -= 1
        val = value(state)
        if has(state.options, :strictArray) && length(ary) == 0
            typ = typeof(val)
            ary = (typ)[]
        end
        if isa(val, typ)
            @debug "++++++++++ $ary  $val  $typ\n"
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
    @debug "// Array level $arlv\n"
    arlv -=1
    return ary
end

function tuple_value(state)
    ary = {}
    if next_non_comment!(state) == ')'
        return return tuple(ary...)
    end
    state.index -= 1

    while next_non_comment!(state) != ')'
        state.index -= 1
        val = value(state)
        push!(ary, val)
        # handle the coma:
        c = next_non_comment!(state) 
        if c == ')'
            break
        elseif c != ','
            error("Syntax error in tuple. Coma expected on line $(state.line).")
        end
    end
    return tuple(ary...)
end

end ## module TOML