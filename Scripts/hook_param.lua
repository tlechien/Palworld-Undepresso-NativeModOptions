-- Unwraps a RegisterHook callback argument.
--
-- UE4SS passes hook arguments as RemoteUnrealParam/LocalUnrealParam wrappers that must be unwrapped
-- with :get(); other values arrive as-is. Testing the wrapper's :type() rather than the Lua type is
-- required, because the wrappers report as userdata like any other UObject.
local HookParam = {}

function HookParam.read(param)
    if param == nil or type(param) ~= "userdata" then
        return param
    end
    local ok, unrealType = pcall(function() return param:type() end)
    if not ok or (unrealType ~= "RemoteUnrealParam" and unrealType ~= "LocalUnrealParam") then
        return param
    end
    -- Not `readOk and value or nil`: that idiom collapses a legitimate boolean false into nil, so a
    -- switch committed to OFF reads as "could not be read" and is discarded.
    local readOk, value = pcall(function() return param:get() end)
    if not readOk then
        return nil
    end
    return value
end

return HookParam
