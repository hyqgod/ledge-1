module("ledge.response", package.seeall)

_VERSION = '0.1'

-- Cache states
local RESPONSE_STATE_UNKNOWN     = -99
local RESPONSE_STATE_PRIVATE     = -12
local RESPONSE_STATE_RELOADED    = -11
local RESPONSE_STATE_REVALIDATED = -10
local RESPONSE_STATE_SUBZERO     = -1
local RESPONSE_STATE_COLD        = 0
local RESPONSE_STATE_WARM        = 1
local RESPONSE_STATE_HOT         = 2

local class = ledge.response
local mt = { __index = class }


function new(self)
    local header = {}

    -- Header metatable for field case insensitivity.
    local header_mt = {
        normalised = {},
    }

    -- If we've seen this key in any case before, return it.
    header_mt.__index = function(t, k)
        k = k:lower():gsub("-", "_")
        if header_mt.normalised[k] then
            return rawget(t, header_mt.normalised[k])
        end
    end

    -- First check the normalised table. If there's no match (first time) add an entry for 
    -- our current case in the normalised table. This is to preserve the human (prettier) case
    -- instead of outputting lowercased / underscored header names.
    --
    -- If there's a match, we're being updated, just with a different case for the key. We use
    -- the normalised table to give us the original key, and perorm a rawset().
    header_mt.__newindex = function(t, k, v)
        k_low = k:lower():gsub("-", "_")
        if not header_mt.normalised[k_low] then
            header_mt.normalised[k_low] = k 
            rawset(t, k, v)
        else
            rawset(t, header_mt.normalised[k_low], v)
        end
    end

    setmetatable(header, header_mt)

    return setmetatable({   status = nil, 
                            body = "", 
                            header = header, 
                            remaining_ttl = 0,
                            state = RESPONSE_STATE_UNKNOWN,
    }, mt)
end


function is_cacheable(self)
    local nocache_headers = {
        ["Pragma"] = { "no-cache" },
        ["Cache-Control"] = {
            "no-cache", 
            "no-store", 
            "private",
        }
    }

    for k,v in pairs(nocache_headers) do
        for i,h in ipairs(v) do
            if self.header[k] and self.header[k] == h then
                return false
            end
        end
    end

    if self:ttl() > 0 then
        return true
    else
        return false
    end
end


function ttl(self)
    -- Header precedence is Cache-Control: s-maxage=NUM, Cache-Control: max-age=NUM,
    -- and finally Expires: HTTP_TIMESTRING.
    if self.header["Cache-Control"] then
        for _,p in ipairs({ "s%-maxage", "max%-age" }) do
            for h in self.header["Cache-Control"]:gmatch(p .. "=\"?(%d+)\"?") do 
                return tonumber(h)
            end
        end
    end

    -- Fall back to Expires.
    if self.header["Expires"] then 
        local time = ngx.parse_http_time(self.header["Expires"])
        if time then return time - ngx.time() end
    end

    return 0
end