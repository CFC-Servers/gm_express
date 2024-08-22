AddCSLuaFile()

--- @class express_PutCache
express.putCache = {
    cache = {},
    dirty = false,
    domain = express:getDomain(),
    _maxCacheTime = 3 * 7 * 24 * 60 * 60 -- 3 weeks
}
--- @class express_PutCache
local putCache = express.putCache

local function getCacheLocation()
    if SERVER then return "express/putcache.dat" end

    -- Clients save their putCache per-server
    local serverID = util.SHA1( game.GetIPAddress() )
    return "express/" .. serverID .. "_putcache.dat"
end

--- Sets a value in the Put Cache
--- @param key string
--- @param size number
--- @return express_PutCacheItem
function putCache:Set( key, size )
    --- @type express_PutCacheItem
    local cacheStruct = {
        size = size,
        waiting = {},
        complete = false,
        cachedAt = os.time()
    }

    self.cache[key] = cacheStruct
    self.dirty = true

    return cacheStruct
end

--- Gets a value from the Put Cache
--- @param key string
--- @return express_PutCacheItem?
function putCache:Get( key )
    local cached = self.cache[key]
    if cached.cachedAt + self._maxCacheTime < os.time() then
        self.cache[key] = nil
        return nil
    end

    return cached
end

--- Clears the Put Cache
--- (Used when changing the express backend)
function putCache:Clear()
    self.cache = {}
    self:Save()
end

--- Saves the Put Cache to disk
function putCache:Save()
    if not self.dirty then return end

    self.cache._domain = self.domain
    local encoded, err1, err2 = sfs.encode( self.cache )
    self.cache._domain = nil

    if not encoded then
        express.log( "Failed to encode put cache: " .. err1 .. " - " .. err2 )
        return
    end

    local location = getCacheLocation()
    file.Write( location, encoded )

    self.dirty = false
end

--- Loads the Put Cache from disk
function putCache:Load()
    local location = getCacheLocation()

    file.AsyncRead( location, "DATA", function( _, _, status, data )
        if status ~= FSASYNC_OK then
            print( "Express: Failed to read put cache: " .. status )
            return
        end

        if not data then return end

        local decoded, err1, err2 = sfs.decode( data )
        if not decoded then
            error( "Express: Failed to decode put cache (malformed?): " .. err1 .. " - " .. err2 )
        end

        local domain = decoded._domain
        if domain ~= self.domain then
            print( "Express: Put cache domain mismatch ('" .. self.domain .. "' expected, got '" .. domain .. "') clearing cache" )
            return
        end

        self.cache = decoded
    end )
end

hook.Add( "ShutDown", "express_putcache", function()
    putCache:Save()
end )

hook.Add( "InitPostEntity", "express_putcache", function()
    putCache:Load()
end )

timer.Create( "express_putcache", 60, 0, function()
    putCache:Save()
end )

timer.Create( "express_clean_putcache", 60 * 60, 0, function()
    local now = os.time()
    local madeChanges = false
    local cache = putCache.cache
    local maxCacheTime = putCache._maxCacheTime

    for k, v in pairs( cache ) do
        if v.cachedAt + maxCacheTime < now then
            cache[k] = nil
            madeChanges = true
        end
    end

    if madeChanges then
        putCache:Save()
    end
end )


--- @class express_PutCacheItem
--- @field id string? The ID of the upload, will be nil until complete is true
--- @field size number The size of the data
--- @field complete boolean Whether or not the upload is complete
--- @field waiting function[] A list of functions to call when the upload is complete
--- @field cachedAt number
