AddCSLuaFile()
express.version = 1
express.revision = 1
express._putCache = {}
express._maxCacheTime = (24 - 1) * 60 * 60
express._waitingForAccess = {}

express.domain = CreateConVar(
    "express_domain", "gmod.express", FCVAR_ARCHIVE + FCVAR_REPLICATED,
    "The domain of the Express server"
)
express.downloadChunkSize = CreateConVar(
    "express_download_chunk_size", tostring( 12 * 1024 * 1024 ), FCVAR_ARCHIVE,
    "The size (in bytes) of each chunk downloaded from the Express server", 1
)
express.maxAttempts = CreateConVar(
    "express_download_max_attempts", tostring( 12 ), FCVAR_ARCHIVE,
    "How many times to retry downloading a file before giving up", 0
)
express.retryDelay = CreateConVar(
    "express_download_retry_delay", tostring( 0.125 ), FCVAR_ARCHIVE,
    "The duration in seconds to wait between each download retry", 0
)
express.timeout = CreateConVar(
    "express_timeout", tostring( CLIENT and 280 or 60 ), FCVAR_ARCHIVE,
    "The timeout in seconds for Express HTTP requests. (Flaky/slow connections should set this higher)", 1
)
express.useRanges = CreateConVar(
    "express_use_ranges", tostring( 1 ), FCVAR_ARCHIVE + FCVAR_REPLICATED,
    "Whether or not to request data in Ranges. (Improves stability for bad internets, might avoid some bugs, could slow things down)", 0, 1
)
express.compressThreshold = CreateConVar(
    "express_compress_threshold", tostring( 20 * 1024 * 1024 ), FCVAR_ARCHIVE + FCVAR_REPLICATED,
    "At what size (in bytes) will Express util.Compress the data - Compressing is slow - so try to only do it when you need it"
)
express.minSize = CreateConVar(
    "express_min_size", tostring( 64 * 3 * 1024 ), FCVAR_ARCHIVE + FCVAR_REPLICATED,
    "The minimum size (in bytes) that will send via express. Anything smaller than this will send with NetStream"
)

-- Useful for self-hosting if you need to set express_domain to localhost
-- and direct clients to a global IP/domain to hit the same service
express.domain_cl = CreateConVar(
    "express_domain_cl", "", FCVAR_ARCHIVE + FCVAR_REPLICATED,
    "The client-specific domain of the Express server. If empty, express_domain will be used."
)


-- Runs the correct net Send function based on the realm --
function express.shSend( target )
    if CLIENT then
        net.SendToServer()
    else
        net.Send( target )
    end
end


-- Returns the correct domain based on the realm and convars --
function express:getDomain()
    local domain = self.domain:GetString()
    if SERVER then return domain end

    local clDomain = self.domain_cl:GetString()
    if clDomain ~= "" then return clDomain end

    return domain
end


-- Creates the base of the API URL from the protocol, domain, and version --
function express:makeBaseURL()
    local protocol = self._protocol
    local domain = self:getDomain()
    return string.format( "%s://%s/v%d", protocol, domain, self.version )
end


-- Creates a full URL with the given access token --
function express:makeAccessURL( action, ... )
    local url = self:makeBaseURL()
    local args = { action, self.access,  ... }

    return url .. "/" .. table.concat( args, "/" )
end

function express.parseContentRange( header )
    local pattern = "bytes (%d+)-(%d+)/(%d+)"
    local rangeStart, rangeEnd, fullSize = header:match( pattern )
    return tonumber( rangeStart ), tonumber( rangeEnd ), tonumber( fullSize )
end


-- Sets the access token and runs requests that were waiting --
function express:SetAccess( access, clientAccess )
    self.access = access
    self._clientAccess = clientAccess

    local waiting = self._waitingForAccess
    for _, callback in ipairs( waiting ) do
        callback()
    end

    self._waitingForAccess = {}
end


-- Checks the version of the API and alerts of a mismatch --
function express.CheckRevision()

    local suffix = " on version check! This is bad!"
    local err = function( msg )
        return "Express: " .. msg .. suffix
    end

    local url = express:makeBaseURL() .. "/revision"
    local success = function( code, body )
        assert( code >= 200 and code < 300, err( "Invalid response code (" .. code .. ")" ) )

        local dataHolder = util.JSONToTable( body )
        assert( dataHolder, err( "Invalid JSON response" ) )

        local revision = dataHolder.revision
        assert( revision, err( "Invalid JSON response" ) )

        local current = express.revision
        if revision ~= current then
            error( err( "Revision mismatch! Expected " .. current .. ", got " .. revision ) )
        end
    end

    express.HTTP( {
        url = url,
        method = "GET",
        success = success,
        failed = function( message )
            error( err( message ) )
        end,
        headers = express.jsonHeaders,
        timeout = express:_getTimeout()
    } )
end

function express.HandleReceivedData( body, id, cb )
    if string.StartsWith( body, "<enc>" ) then
        print( "Express: Decompressing data for ID '" .. id .. "'." )
        body = util.Decompress( string.sub( body, 6 ) )
        if ( not body ) or #body == 0 then
            error( "Express: Failed to decompress data for ID '" .. id .. "'." )
        end
    end

    if string.StartsWith( body, "<raw>" ) then
        print( "Express: Returning raw data for ID '" .. id .. "'." )
        body = string.sub( body, 6 )
        local hash = util.SHA1( body )
        return cb( body, hash )
    else
        local hash = util.SHA1( body )
        local decodedData = pon.decode( body )
        return cb( decodedData, hash )
    end
end

function express:Get( id, cb )
    local url = self:makeAccessURL( "read", id )

    local attempts = 0
    local rangeStart = 0
    local rangeEnd = self.downloadChunkSize:GetInt()

    local fullBody = ""
    local headers = table.Copy( self._bytesHeaders )

    local makeRequest
    local function success( code, body, responseHeaders )
        -- print( "Express: GET " .. url .. " : " .. tostring( code ), headers.Range, "Attempts: " .. attempts )

        if code == 404 then
            if attempts >= self.maxAttempts:GetInt() then
                error( "Express: Failed to download file ' " .. url .. " ' after " .. attempts .. " attempts." )
            else
                print( "Express:Get() got 404, retrying: " .. id )
                attempts = attempts + 1
                timer.Simple( self.retryDelay:GetFloat() + (attempts / 4), makeRequest )
            end

            return
        end

        express._checkResponseCode( code )

        if attempts > 0 then
            print( "Express:Get() succeeded after " .. attempts .. " attempts" )
        end

        -- We had a successful download, so reset the attempts
        attempts = 0
        fullBody = fullBody .. body

        -- If Range headers are supported on the server
        if code == 206 then
            local _, _, fullSize = self.parseContentRange( responseHeaders["Content-Range"] )
            if #fullBody == fullSize then
                return express.HandleReceivedData( fullBody, id, cb )
            end

            rangeStart = rangeEnd + 1
            rangeEnd = rangeStart + self.downloadChunkSize:GetInt()
            return makeRequest()
        end

        -- If we didn't receive a 206, then we should have received a 200 with the full file
        -- This will happen if the express server doesn't support Range headers
        return express.HandleReceivedData( fullBody, id, cb )
    end

    local function failure( reason )
        -- Unsuccessful HTTP requests might succeed on a retry
        if reason == "unsuccessful" then
            print( "Express: Failed to download file '" .. url .. "': HTTP request failed. Retrying." )
            attempts = attempts + 1
            makeRequest()
        else
            error( "Express: Failed to download file '" .. url .. "': " .. reason .. "\n" )
        end
    end

    makeRequest = function()
        if express.useRanges:GetBool() then
            -- We have to add 0-1 or the http call will fail :(
            headers.Range = string.format( "bytes=%d-%d, 0-1", rangeStart, rangeEnd )
        end
        -- print( "Express: Downloading chunk " .. rangeStart .. " to " .. rangeEnd .. " of " .. id )

        express.HTTP( {
            method = "GET",
            url = url,
            headers = headers,
            success = success,
            failed = failure,
            timeout = self:_getTimeout()
        } )
    end

    makeRequest()
end

-- Runs the main :Get function, or queues the request if no access token is set --
function express:_get( id, cb )
    if self.access then
        return self:Get( id, cb )
    end

    table.insert( self._waitingForAccess, function()
        self:Get( id, cb )
    end )
end

-- Processes/Formats the data that will be sent
-- preCompressCallback is called before compression (the most expensive part) in case we want to do something different
function express.processSendData( data, preCompressCallback )
    if istable( data ) then
        print( "Express: Sending table data." )
        if table.Count( data ) == 0 then
            error( "Express: Tried to send empty data!" )
        end

        data = pon.encode( data )
    elseif isstring( data ) then
        print( "Express: Sending raw data." )
        if #data == 0 then
            error( "Express: Tried to send empty data!" )
        end

        data = "<raw>" .. data
    else
        error( "Express: Invalid data type '" .. type( data ) .. "'! (expected string or table)" )
    end

    local hash = util.SHA1( data )
    local size = string.len( data )
    local struct = {
        data = data,
        hash = hash,
        size = size
    }

    local shouldContinue = preCompressCallback( struct )
    if shouldContinue == false then return end

    if size > express.compressThreshold:GetFloat() then
        local compressed = util.Compress( data )
        assert( compressed, "Express: Failed to compress data!" )

        size = string.len( data )

        struct.size = size
        struct.data = "<enc>" .. compressed
    end

    if size > express._maxDataSize then
        error( "Express: Data too large (" .. size .. " bytes)" )
    end

    return struct
end


--- Sends the given data with Express
--- Encodes and compresses the given data, then sends it to the API if not already cached
function express:_put( struct, cb )
    local size = struct.size
    local hash = struct.hash

    local now = os.time()
    local cached = self._putCache[hash]

    if cached then
        if cached.complete then
            local cachedAt = cached.cachedAt

            if now <= ( cachedAt + self._maxCacheTime ) then
                local cachedSize = cached.cachedSize
                local niceSize = string.NiceSize( cachedSize )
                print( "Express: Using cached ID '" .. cached.id .. "' for hash '" .. hash .. "' (Saved you " .. niceSize .. "!)" )

                -- Force the callback to run asynchronously for consistency
                timer.Simple( 0, function()
                    cb( cached.id, hash, cachedSize )
                end )

                return
            end
        else
            table.insert( cached.waiting, cb )
            return
        end
    end

    local waiting = {}
    local cacheItem = {
        size = size,
        waiting = waiting,
        complete = false
    }
    self._putCache[hash] = cacheItem

    local function onComplete( id )
        cacheItem.id = id
        cacheItem.complete = true

        local count = #waiting
        for _ = 1, count do
            table.remove( waiting )( id, hash, size )
        end

        cb( id, hash, size )
    end

    if self.access then
        return self:Put( struct.data, onComplete )
    end

    table.insert( self._waitingForAccess, function()
        self:Put( struct.data, onComplete )
    end )
end


-- Creates a contextual callback for the :_put endpoint, delaying the notification to the recipient(s) --
function express:_putCallback( message, plys, onProof )
    return function( id, hash, size )
        assert( id )
        assert( hash )
        assert( size )

        if onProof then
            self:SetExpected( hash, onProof, plys )
        end

        net.Start( "express" )
        print( "Express: Sending message '" .. message .. "' to: ", plys )
        net.WriteString( message )
        net.WriteString( id )
        net.WriteBool( onProof ~= nil )

        if SERVER then
            net.WriteUInt( size, 27 )
        end

        express.shSend( plys )
    end
end


function express:_putSmall( struct, message, plys, onProof )
    net.Start( "express_small" )
    print( "Express: Sending NetStream message '" .. message .. "' to: ", plys )
    net.WriteString( message )
    net.WriteUInt( struct.size, 27 )
    net.WriteBool( onProof ~= nil )
    net.WriteStream( struct.data, onProof, true )
    express.shSend( plys )
end


-- Calls the _put function with a contextual callback --
function express:_send( message, data, plys, onProof )
    if not isstring( message ) then
        error( "Express: Invalid message type '" .. type( message ) .. "'!", 2 )
    end

    if not (istable( data ) or isstring( data )) then
        error( "Express: Invalid data type '" .. type( data ) .. "'!", 2)
    end

    if SERVER then
        if not (istable( plys ) or type( plys ) == "Player") then
            error( "Express: Invalid player(s) type '" .. type( plys ) .. "'! (expected Player or table of Players)", 2 )
        end
    end

    if onProof and not isfunction( onProof ) then
        error( "Express: Invalid proof callback type '" .. type( onProof ) .. "'!", 2 )
    end

    -- Pre-compress callback is where we check if we should fallback to NetStream
    local processed = express.processSendData( data, function( struct )
        print( "Got processed data pre-compress callback" )

        local size = struct.size

        if size < express.minSize:GetFloat() then
            print( "Express: Message ('" .. message .. "') is too small to send with express. Falling back to NetStream:", string.NiceSize( size ) )
            self:_putSmall( struct, message, plys, onProof )
            return false
        end
    end )

    if not processed then return end

    self:_put( processed, self:_putCallback( message, plys, onProof ) )
end


-- Assigns a callback to the given message --
function express:_setReceiver( message, cb )
    message = string.lower( message )
    self._receivers[message] = cb
end


-- Returns the receiver set for the given message --
function express:_getReceiver( message )
    message = string.lower( message )
    return self._receivers[message]
end


-- Returns the pre-download receiver set for the given message --
function express:_getPreDlReceiver( message )
    message = string.lower( message )
    return self._preDlReceivers[message]
end


-- Returns a realm-specific timeout value for HTTP requests --
function express:_getTimeout()
    return self.timeout:GetFloat()
end


-- Ensures that the given HTTP response code indicates a succcessful request --
function express._checkResponseCode( code )
    local isOk = isnumber( code ) and code >= 200 and code < 300
    if isOk then return end

    error( "Express: Invalid response code (" .. tostring( code ) .. ")" )
end


-- Attempts to re-register with the new domain, and then verifies its version --
cvars.AddChangeCallback( "express_domain", function()
    express._putCache = {}

    if SERVER then express:Register() end

    express:CheckRevision()
end, "domain_check" )

-- Both client and server should check the version on startup so that errors are caught early --
cvars.AddChangeCallback( "express_domain_cl", function( _, _, new )
    if CLIENT then express._putCache = {} end
    if new == "" then return end

    express:CheckRevision()
end, "domain_check" )


hook.Add( "ExpressLoaded", "Express_HTTPInit", function()
    hook.Add( "Tick", "Express_RevisionCheck", function()
        hook.Remove( "Tick", "Express_RevisionCheck" )
        if SERVER then express:Register() end
        express:CheckRevision()
    end )
end )
