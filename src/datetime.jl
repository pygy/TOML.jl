# waiting for official Timestamp support in Julia. Calendar.jl is too slow to load.
const date_pattern = anchored_regex("(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})Z")

immutable DateTime
    year::Int
    month::Int
    date::Int
    hour::Int
    minute::Int
    second::Int
end

function ymd_hms(args...)
    DateTime(args[1:6]...)
end
