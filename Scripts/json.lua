-- json.lua -- minimal JSON encode/decode. Vendored per mod: UE4SS mods cannot require() each
-- other's files, so this is copied rather than shared.
-- schemas and value maps (objects, arrays, strings, numbers, booleans, null).

local json = {}

local escape_map = {
    ["\\"] = "\\\\", ["\""] = "\\\"", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function encode_string(s)
    local out = { "\"" }
    for i = 1, #s do
        local c = s:sub(i, i)
        out[#out + 1] = escape_map[c] or c
    end
    out[#out + 1] = "\""
    return table.concat(out)
end

local function is_array(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    if n == 0 then return true end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true
end

local encode_value

local function encode_array(t)
    local parts = {}
    for i = 1, #t do
        parts[i] = encode_value(t[i])
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function encode_object(t)
    local parts = {}
    for k, v in pairs(t) do
        parts[#parts + 1] = encode_string(tostring(k)) .. ":" .. encode_value(v)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

encode_value = function(v)
    local t = type(v)
    if v == nil then
        return "null"
    elseif t == "boolean" then
        return v and "true" or "false"
    elseif t == "number" then
        return tostring(v)
    elseif t == "string" then
        return encode_string(v)
    elseif t == "table" then
        return is_array(v) and encode_array(v) or encode_object(v)
    end
    return "null"
end

function json.encode(value)
    return encode_value(value)
end

local function skip_ws(s, i)
    local _, j = s:find("^%s*", i)
    return j + 1
end

local decode_value

local function decode_string(s, i)
    local j = i + 1
    local out = {}
    while true do
        local c = s:sub(j, j)
        if c == "" then
            error("json: unterminated string")
        elseif c == "\"" then
            return table.concat(out), j + 1
        elseif c == "\\" then
            local n = s:sub(j + 1, j + 1)
            local map = { n = "\n", r = "\r", t = "\t", ["\""] = "\"", ["\\"] = "\\", ["/"] = "/" }
            out[#out + 1] = map[n] or n
            j = j + 2
        else
            out[#out + 1] = c
            j = j + 1
        end
    end
end

local function decode_number(s, i)
    local j = s:find("[^%-%+%.eE0-9]", i) or (#s + 1)
    return tonumber(s:sub(i, j - 1)), j
end

decode_value = function(s, i)
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == "\"" then
        return decode_string(s, i)
    elseif c == "{" then
        local obj = {}
        local j = skip_ws(s, i + 1)
        if s:sub(j, j) == "}" then return obj, j + 1 end
        while true do
            j = skip_ws(s, j)
            local key
            key, j = decode_string(s, j)
            j = skip_ws(s, j)
            if s:sub(j, j) ~= ":" then error("json: expected ':'") end
            j = j + 1
            local value
            value, j = decode_value(s, j)
            obj[key] = value
            j = skip_ws(s, j)
            local sep = s:sub(j, j)
            if sep == "," then
                j = j + 1
            elseif sep == "}" then
                return obj, j + 1
            else
                error("json: expected ',' or '}'")
            end
        end
    elseif c == "[" then
        local arr = {}
        local j = skip_ws(s, i + 1)
        if s:sub(j, j) == "]" then return arr, j + 1 end
        while true do
            local value
            value, j = decode_value(s, j)
            arr[#arr + 1] = value
            j = skip_ws(s, j)
            local sep = s:sub(j, j)
            if sep == "," then
                j = j + 1
            elseif sep == "]" then
                return arr, j + 1
            else
                error("json: expected ',' or ']'")
            end
        end
    elseif s:sub(i, i + 3) == "true" then
        return true, i + 4
    elseif s:sub(i, i + 4) == "false" then
        return false, i + 5
    elseif s:sub(i, i + 3) == "null" then
        return nil, i + 4
    else
        return decode_number(s, i)
    end
end

function json.decode(s)
    if type(s) ~= "string" or s == "" then
        error("json: empty input")
    end
    return (decode_value(s, 1))
end

return json
