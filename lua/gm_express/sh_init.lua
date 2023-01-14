AddCSLuaFile()

require( "pon" )
if SERVER then
    util.AddNetworkString( "express" )
    util.AddNetworkString( "express_proof" )
end

express = {}
express._receivers = {}
express._protocol = "http"
express._awaitingProof = {}
express._preDlReceivers = {}
express._maxDataSize = 24 * 1024 * 1024
express._jsonHeaders = { ["Content-Type"] = "application/json" }
express._bytesHeaders = { ["Accept"] = "application/octet-stream" }
express.domain = CreateConVar(
    "express_domain", "gmod.express", FCVAR_ARCHIVE + FCVAR_REPLICATED, "The domain of the Express server"
)

-- Useful for self-hosting if you need to set express_domain to localhost
-- and direct clients to a global IP/domain to hit the same service
express.domain_cl = CreateConVar(
    "express_domain_cl", "", FCVAR_ARCHIVE + FCVAR_REPLICATED, "The client-specific domain of the Express server. If empty, express_domain will be used."
)


-- Registers a basic receiver --
function express.Receive( message, cb )
    message = string.lower( message )
    express._receivers[message] = cb
end


-- Registers a PreDownload receiver --
function express.ReceivePreDl( message, preDl )
    message = string.lower( message )
    express._preDlReceivers[message] = preDl
end


-- Retrieves and parses the data for given ID --
function express:Get( id, cb )
    local url = self:makeAccessURL( "read", id )

    local success = function( code, body )
        express._checkResponseCode( code )

        local hash = util.SHA1( body )
        local encodedData = util.Decompress( body, self._maxDataSize )

        if #encodedData == 0 then
            print( "Express: Failed to decompress data for ID " .. id )
            cb( "", hash )
        else
            local decodedData = pon.decode( encodedData )
            cb( decodedData, hash )
        end
    end

    HTTP( {
        method = "GET",
        url = url,
        success = success,
        failed = error,
        headers = self._bytesHeaders,
        timeout = self:_getTimeout()
    } )
end


-- Asks the API for this ID's data's size --
function express:GetSize( id, cb )
    local url = self:makeAccessURL( "size", id )

    local success = function( code, body )
        express._checkResponseCode( code )

        local sizeHolder = util.JSONToTable( body )
        assert( sizeHolder, "Invalid JSON" )

        local size = sizeHolder.size
        assert( size, "No size data" )

        cb( tonumber( size ) )
    end

    HTTP( {
        method = "GET",
        url = url,
        success = success,
        failed = error,
        headers = self._jsonHeaders,
        timeout = self:_getTimeout()
    } )
end


-- Given prepared data, sends it to the API --
function express:Put( data, cb )
    local success = function( code, body )
        express._checkResponseCode( code )

        local response = util.JSONToTable( body )
        assert( response, "Invalid JSON" )
        assert( response.id, "No ID returned" )

        cb( response.id )
    end

    HTTP( {
        method = "POST",
        url = self:makeAccessURL( "write" ),
        body = data,
        success = success,
        failed = error,
        headers = {
            ["Content-Length"] = #data,
            ["Accept"] = "application/json"
        },
        type = "application/octet-stream",
        timeout = CLIENT and 240 or 60
    } )
end


-- Runs the express receiver for the given message --
function express:Call( message, ply, data )
    local cb = self:_getReceiver( message )
    if not cb then return end

    if CLIENT then return cb( data ) end
    if SERVER then return cb( ply, data ) end
end


-- Runs the express pre-download receiver for the given message --
function express:CallPreDownload( message, ply, id, size, needsProof )
    local cb = self:_getPreDlReceiver( message )
    if not cb then return end

    if CLIENT then return cb( message, id, size, needsProof ) end
    if SERVER then return cb( message, ply, id, size, needsProof ) end
end


-- Handles a net message containing an ID to download from the API --
function express.OnMessage( _, ply )
    local message = net.ReadString()
    if not express:_getReceiver( message ) then
        error( "Express: Received a message that has no listener! (" .. message .. ")" )
    end

    local id = net.ReadString()
    local needsProof = net.ReadBool()

    local function makeRequest( size )
        if size then
            local check = express:CallPreDownload( message, ply, id, size, needsProof )
            if check == false then return end
        end

        express:_get( id, function( data, hash )
            express:Call( message, ply, data )

            if not needsProof then return end
            net.Start( "express_proof" )
            net.WriteString( hash )
            express.shSend( ply )
        end )
    end

    if express:_getPreDlReceiver( message ) then
        return express:GetSize( id, makeRequest )
    end

    makeRequest()
end


-- Handles a net message containing a proof of data download --
function express.OnProof( _, ply )
    -- Server prefixes the hash with the player's Steam ID
    local prefix = ply and ply:SteamID64() .. "-" or ""
    local hash = prefix .. net.ReadString()

    local cb = express._awaitingProof[hash]
    if not cb then return end

    cb( ply )
    express._awaitingProof[hash] = nil
end


net.Receive( "express", express.OnMessage )
net.Receive( "express_proof", express.OnProof )

include( "sh_helpers.lua" )

if SERVER then
    include( "sv_init.lua" )
    AddCSLuaFile( "cl_init.lua" )
else
    include( "cl_init.lua" )
end
