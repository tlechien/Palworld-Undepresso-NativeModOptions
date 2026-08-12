-- Maps a live row widget to the (modId, key) it belongs to.
--
-- Interaction hooks are registered at the class level, so they fire for every instance of that class
-- system-wide -- vanilla's own rows and other mods' rows included. Every callback must resolve its
-- Context through this table before acting. Identity is the object's address; Lua == does not work
-- for UObjects.
--
-- Addresses are also published as shared variables so a consumer mod can do the same resolution from
-- its own Lua VM without a live widget reference. See the wiki.
local Shared = require("shared")

local PREFIX = Shared.PREFIX

local AddressRegistry = {
    byAddress = {},   -- [address] = { modId, key, ... }
}

local function addressOf(object)
    if object == nil then
        return nil
    end
    local ok, address = pcall(function() return object:GetAddress() end)
    if ok and address ~= nil and address ~= 0 then
        return address
    end
    return nil
end
AddressRegistry.addressOf = addressOf

-- Called once per row widget, at panel build. `extra` is merged into the stored owner table; row_lr
-- uses it to carry the option's ordered choice list, which resolving an index back to a value needs.
function AddressRegistry.track(widget, modId, key, extra)
    local address = addressOf(widget)
    if address == nil then
        return nil
    end
    local owner = { modId = modId, key = key }
    if type(extra) == "table" then
        for name, value in pairs(extra) do
            owner[name] = value
        end
    end
    AddressRegistry.byAddress[address] = owner
    Shared.set(PREFIX .. "RowAddress." .. modId .. "." .. key, tostring(address))
    return address
end

-- Bumped once per panel build, after every row address has been published. A consumer mod's hooks
-- fire far more often than they match; a single counter lets it cache an address->option index and
-- rebuild only when the panel has actually changed, instead of re-reading one variable per option on
-- every fire.
local epoch = 0

function AddressRegistry.publishEpoch()
    epoch = epoch + 1
    Shared.set(PREFIX .. "RowEpoch", tostring(epoch))
end

function AddressRegistry.untrack(widget)
    local address = addressOf(widget)
    if address == nil then
        return
    end
    local owner = AddressRegistry.byAddress[address]
    AddressRegistry.byAddress[address] = nil
    if owner ~= nil then
        Shared.set(PREFIX .. "RowAddress." .. owner.modId .. "." .. owner.key, nil)
    end
end

-- Resolves a hook Context back to its owner, or nil when the widget is not one of this mod's rows.
function AddressRegistry.resolve(context)
    local address = addressOf(context)
    if address == nil then
        return nil
    end
    return AddressRegistry.byAddress[address]
end

return AddressRegistry
