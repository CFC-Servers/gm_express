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
    "express_download_chunk_size", tostring( 8 * 1024 * 1024 ), FCVAR_ARCHIVE,
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
express.usePutCache = CreateConVar(
    "express_use_put_cache", tostring( 1 ), FCVAR_ARCHIVE,
    "Whether to cache POST requests to the Express server (minimizes re-sending the same data)", 0, 1
)
express.timeout = CreateConVar(
    "express_timeout", tostring( CLIENT and 280 or 60 ), FCVAR_ARCHIVE,
    "The timeout in seconds for Express HTTP requests. (Flaky/slow connections should set this higher)", 1
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
function express:SetAccess( access )
    self.access = access

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
    local success = function( body, _, _, code )
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

    http.Fetch( url, success, function( message )
        error( err( message ) )
    end, express.jsonHeaders )
end

function express:Get( id, cb )
    local url = self:makeAccessURL( "read", id )

    local attempts = 0
    local rangeStart = 0
    local rangeEnd = self.downloadChunkSize:GetInt()

    local fullBody = ""
    local headers = table.Copy( self._bytesHeaders )

    local function finishDownload()
        if string.StartWith( fullBody, "<enc>" ) then
            print( "Express: Decompressing data for ID '" .. id .. "'." )
            fullBody = util.Decompress( string.sub( fullBody, 6 ) )
            if ( not fullBody ) or #fullBody == 0 then
                error( "Express: Failed to decompress data for ID '" .. id .. "'." )
            end
        end

        print( "Express: Downloaded " .. #fullBody .. " bytes for ID '" .. id )

        if string.StartWith( fullBody, "<raw>" ) then
            print( "Express: Returning raw data for ID '" .. id .. "'." )
            fullBody = string.sub( fullBody, 6 )
            local hash = util.SHA1( fullBody )
            return cb( fullBody, hash )
        else
            local hash = util.SHA1( fullBody )
            local decodedData = pon.decode( fullBody )
            return cb( decodedData, hash )
        end
    end

    local makeRequest
    local function success( code, body, responseHeaders )
        print( "Express: GET " .. url .. " : " .. tostring( code ), headers.Range, "Attempts: " .. attempts )

        if code == 404 then
            if attempts >= self.maxAttempts:GetInt() then
                error( "Express: Failed to download file ' " .. url .. " ' after " .. attempts .. " attempts." )
            else
                print( "Express:Get() got 404, retrying: " .. id )
                attempts = attempts + 1
                timer.Simple( self.retryDelay:GetFloat() + ( attempts / 4 ), makeRequest )
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
                return finishDownload()
            end

            rangeStart = rangeEnd + 1
            rangeEnd = rangeStart + self.downloadChunkSize:GetInt()
            return makeRequest()
        end

        -- If we didn't receive a 206, then we should have received a 200 with the full file
        -- This will happen if the express server doesn't support Range headers
        return finishDownload()
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
        -- We have to add 0-1 or the http call will fail :(
        headers.Range = string.format( "bytes=%d-%d, 0-1", rangeStart, rangeEnd )
        -- print( "Express: Downloading chunk " .. rangeStart .. " to " .. rangeEnd .. " of " .. id )

        HTTP( {
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


-- Runs the main :GetSize function, or queues the request if no access token is set --
-- FIXME: If this gets delayed because it doesn't have an access token, the PreDl Receiver will not be able to stop the download --
function express:_getSize( id, cb )
    if self.access then
        return self:GetSize( id, cb )
    end

    table.insert( self._waitingForAccess, function()
        self:GetSize( id, cb )
    end )
end


---Encodes and compresses the given data, then sends it to the API if not already cached
function express:_put( data, cb )
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
        error( "Express: Invalid data type '" .. type( data ) .. "'!" )
    end

    local hash = util.SHA1( data )

    if string.len( data ) > self._maxDataSize then
        data = "<enc>" .. util.Compress( data )
        assert( data, "Express: Failed to compress data!" )

        local dataLen = string.len( data )
        if dataLen > self._maxDataSize then
            error( "Express: Data too large (" .. dataLen .. " bytes)" )
        end
    end

    local now = os.time()
    if express.usePutCache:GetBool() then
        local cached = self._putCache[hash]
        if cached then
            local cachedAt = cached.cachedAt

            if now <= ( cachedAt + self._maxCacheTime ) then
                print( "Express: Using cached ID '" .. cached.id .. "' for hash '" .. hash .. "'" )

                -- Force the callback to run asynchronously for consistency
                timer.Simple( 0, function()
                    cb( cached.id, hash )
                end )

                return
            end
        end
    end

    local function wrapCb( id )
        self._putCache[hash] = { id = id, cachedAt = now }
        cb( id, hash )
    end

    if self.access then
        return self:Put( data, wrapCb )
    end

    table.insert( self._waitingForAccess, function()
        self:Put( data, wrapCb )
    end )
end


-- Creates a contextual callback for the :_put endpoint, delaying the notification to the recipient(s) --
function express:_putCallback( message, plys, onProof )
    return function( id, hash )
        if onProof then
            self:SetExpected( hash, onProof, plys )
        end

        net.Start( "express" )
        net.WriteString( message )
        net.WriteString( id )
        net.WriteBool( onProof ~= nil )

        express.shSend( plys )
    end
end


-- Calls the _put function with a contextual callback --
function express:_send( message, data, plys, onProof )
    self:_put( data, self:_putCallback( message, plys, onProof ) )
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
