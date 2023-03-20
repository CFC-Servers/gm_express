AddCSLuaFile()
express.version = 1
express.revision = 1
express._putCache = {}
express._maxCacheTime = ( 24 - 1 ) * 60 * 60 -- TODO: Get this from the server, similar to the version check
express._waitingForAccess = {}
express.domain = CreateConVar(
    "express_domain", "gmod.express", FCVAR_ARCHIVE + FCVAR_REPLICATED, "The domain of the Express server"
)

-- Useful for self-hosting if you need to set express_domain to localhost
-- and direct clients to a global IP/domain to hit the same service
express.domain_cl = CreateConVar(
    "express_domain_cl", "", FCVAR_ARCHIVE + FCVAR_REPLICATED, "The client-specific domain of the Express server. If empty, express_domain will be used."
)

express.sendDelay = CreateConVar(
    "express_send_delay", 0.15, FCVAR_ARCHIVE + FCVAR_REPLICATED, "How long to wait (in seconds) before sending the Express Message ID to the recipient (longer delays will result in increased reliability)"
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
    if table.Count( data ) == 0 then
        error( "Express: Tried to send empty data!" )
    end

    data = pon.encode( data )

    if string.len( data ) > self._maxDataSize then
        data = "<enc>" .. util.Compress( data )
        assert( data, "Express: Failed to compress data!" )

        local dataLen = string.len( data )
        if dataLen > self._maxDataSize then
            error( "Express: Data too large (" .. dataLen .. " bytes)" )
        end
    end

    local hash = util.SHA1( data )

    local cached = self._putCache[hash]
    if cached then
        local cachedAt = cached.cachedAt

        if os.time() <= ( cachedAt + self._maxCacheTime ) then
            -- Force the callback to run asynchronously for consistency
            timer.Simple( 0, function()
                cb( cached.id, hash )
            end )

            return
        end
    end

    local function wrapCb( id )
        self._putCache[hash] = { id = id, cachedAt = os.time() }
        cb( id, hash )
    end

    if self.access then
        return self:Put( data, wrapCb )
    end

    table.insert( self._waitingForAccess, function()
        self:Put( data, wrapCb )
    end )
end


-- TODO: Fix GLuaTest so we can actually test this function...
-- Creates a contextual callback for the :_put endpoint, delaying the notification to the recipient(s) --
function express:_putCallback( message, plys, onProof )
    return function( id, hash )
        if onProof then
            self:SetExpected( hash, onProof, plys )
        end

        -- Cloudflare isn't fulfilling their promise that the first lookup in
        -- each region will "search" for the target key in K/V if it has't been cached yet.
        -- This delay makes it more likely that the data will have "settled" into K/V before the first lookup
        -- (Once it's cached as a 404, it'll stay that way for about 60 seconds)
        timer.Simple( self.sendDelay:GetFloat(), function()
            net.Start( "express" )
            net.WriteString( message )
            net.WriteString( id )
            net.WriteBool( onProof ~= nil )

            express.shSend( plys )
        end )
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
    return CLIENT and 240 or 60
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
