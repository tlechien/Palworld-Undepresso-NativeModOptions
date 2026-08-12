-- Cross-mod communication over UE4SS shared variables.
--
-- This is the only channel available between mods: each runs in its own Lua VM and cannot require()
-- another's files. mod_options_client.lua is vendored into consumer mods and carries its own copy of
-- these two calls rather than requiring this module.
local Shared = { PREFIX = "NativeModOptions.V1." }

function Shared.get(key)
    if ModRef == nil then
        return nil
    end
    local ok, value = pcall(function() return ModRef:GetSharedVariable(key) end)
    return ok and value or nil
end

function Shared.set(key, value)
    if ModRef == nil then
        return false
    end
    return pcall(function() ModRef:SetSharedVariable(key, value) end)
end

return Shared
