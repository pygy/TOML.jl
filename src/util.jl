
function idem(needle::String, haystack::String, idx)
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

getchar(state::ParserState) = state.txt[state.index]

function nextchar!(state::ParserState)
    if done(state.txt, state.index)
        return :eof
    end
    (char, state.index) = next(state.txt, state.index)
    @debug ("nextchar: $char")
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
        @debug ("======= End Line")
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
            elseif !endlineP(c,state) && c != ' ' && c != '\t'
                return c
            end
        end
    end
end
