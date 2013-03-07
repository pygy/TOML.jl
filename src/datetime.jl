# waiting for official Timestamp support in Julia. Calendar.jl is too slow to load.
const date_pattern = Regex("(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})Z", Base.PCRE.ANCHORED)

immutable DateTime
    year
    month
    date
    hour
    minute
    second
end

function ymd_hms(args...)
    DateTime(args[1:6]...)
end
