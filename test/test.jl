require("TOML")
require("JSON")

list = readdir(".")

tests = map(filter(a-> a[end-4:end]==".toml", list)) do s
    s[1:end-5]
end

for t in tests
    print("$t: "); tml = TOML.parse(open(string(t,".toml")))
    jsn = JSON.parse(readall(open(string(t,".json"))))
    if jsn == tml
        print ("Ok\n")
    else
        print("FAIL\nTOML:\n$tml\n\nJSON:\n$jsn\n\n")
    end
end

for t in tests
    print("$t: "); 
    success = true
    try 
        tml = TOML.parse(open(string(t,".toml")))
        print(tml)
    catch
        success = false
    end
    if success
        print ("Ok\n")
    else
        print("FAIL\n")
    end
end