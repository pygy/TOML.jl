DBG = false

macro debug(msg)
    if DBG
        :(println($msg))
    end
end

function idem(needle::AbstractString, haystack::AbstractString, idx)
    for c1 in needle
        if done(haystack, idx)
            return false
        end
        c2, idx = next(haystack, idx)
        if c2 != c1
            return false
        end
    end
    return true
end

getchar(state::ParserState) = state.subject[state.index]

function nextchar!(state::ParserState)
    if done(state.subject, state.index)
        return :eof
    end
    (char, state.index) = next(state.subject, state.index)
    @debug ("nextchar: $char")
    char
end

function next_non_space!(state::ParserState)
    while true
        c = nextchar!(state)
        if c != ' ' && c != '\t'
            return c
        end
    end
end

function endlineP(c, state::ParserState) # Where 'P' really is a '?'.
    if c == '\r' && state.subject[state.index] == '\n'
        nextchar!(state)
    end
    if c == '\r' || c == '\n'
        state.line += 1
        return true
    else
        return false
    end
end

function endline!(state::ParserState)
    c = next_non_space!(state);
    if endlineP(c, state)
        return
    elseif c == :eof
        return
    elseif c == '#'
        while (c = nextchar!(state); !endlineP(c, state) && c != :eof)
        end
        return
    else
        _error("Illegal character \'$c\'", state)
    end
end

function next_non_comment!(state::ParserState)
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
            elseif !endlineP(c,state) && c != ' ' && c != '\t'
                return c
            end
        end
    end
end

immutable TOMLError
    msg
end

Base.show(io::IO, e::TOMLError) = print(io, repr(e))
Base.repr(e::TOMLError) = "TOMLError: $(e.msg)"

_error(msg, state) = throw(TOMLError("$msg on line $(state.line)."))
