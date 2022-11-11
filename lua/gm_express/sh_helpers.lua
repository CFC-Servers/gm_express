AddCSLuaFile()
express.version = 1
express.revision = 1
express._putCache = {}
express._waitingForAccess = {}


-- Runs the correct net Send function based on the realm --
function express.shSend( target )
    if CLIENT then
        net.SendToServer()
    else
        net.Send( target )
    end
end


-- Creates the base of the API URL from the protocol, domain, and version --
function express:makeBaseURL()
    local protocol = self._protocol
    local domain = self.domain:GetString()
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


-- Encodes and compresses the given data, then sends it to the API if not already cached --
function express:_put( data, cb )
    data = util.Compress( pon.encode( data ) )
    if #data > self._maxDataSize then
        error( "Express: Data too large (" .. #data .. " bytes)" )
    end

    local hash = util.SHA1( data )

    local cachedId = self._putCache[hash]
    if cachedId then
        cb( cachedId, hash )
        return
    end

    local function wrapCb( id )
        self._putCache[hash] = id
        cb( id, hash )
    end

    return self:Put( data, wrapCb )
end


-- Forwards the given parameters to the putter function, then alerts the recipient --
function express:_send( message, data, plys, onProof )
    self:_put( data, function( id, hash )
        net.Start( "express" )
        net.WriteString( message )
        net.WriteString( id )
        net.WriteBool( onProof ~= nil )

        if onProof then
            self:SetExpected( hash, onProof, plys )
        end

        express.shSend( plys )
    end )
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


-- Attempts to re-register with the new domain, and then verifies its version --
cvars.AddChangeCallback( "express_domain", function()
    if SERVER then express:Register() end
    express:CheckRevision()
end, "domain_check" )


-- Tick is the earliest shared hook where HTTP is available
hook.Add( "Tick", "Express_RevisionCheck", function()
    hook.Remove( "Tick", "Express_RevisionCheck" )
    if SERVER then express:Register() end
    express:CheckRevision()
end )
