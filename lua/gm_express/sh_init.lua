AddCSLuaFile()

require( "pon" )
if SERVER then
    util.AddNetworkString( "express" )
    util.AddNetworkString( "express_proof" )
end

express = {}
express._receivers = {}
express._preDlReceivers = {}
express._protocol = "http"
express._awaitingProof = {}
express.headers = { ["Content-Type"] = "application/json" }
express.domain = CreateConVar(
    "express_domain", "gmod.express", FCVAR_ARCHIVE + FCVAR_REPLICATED, "The domain of the Express server"
)

function express.Receive( message, cb )
    message = string.lower( message )
    express._receivers[message] = cb
end

function express.ReceivePreDl( message, preDl )
    message = string.lower( message )
    express._preDlReceivers[message] = preDl
end

function express:Get( id, cb )
    local url = self:makeAccessURL( id )

    local success = function( body, _, _, code )
        assert( code >= 200 and code < 300, "Invalid status code: " .. code )

        local dataHolder = util.JSONToTable( body )
        assert( dataHolder, "Invalid JSON" )
        assert( dataHolder.data, "No data" )

        local b64Data = dataHolder.data
        local hash = util.SHA256( b64Data )
        local encodedData = util.Base64Decode( b64Data )
        assert( encodedData, "Invalid data" )

        local decodedData = pon.decode( encodedData )
        cb( decodedData, hash )
    end

    http.Fetch( url, success, error, self.headers )
end

function express:GetSize( id, cb )
    local url = self:makeAccessURL( id, "size" )

    local success = function( body, _, _, code )
        assert( code >= 200 and code < 300, "Invalid status code: " .. code )

        local sizeHolder = util.JSONToTable( body )
        assert( sizeHolder, "Invalid JSON" )

        local size = sizeHolder.size
        assert( size, "No size data" )

        cb( tonumber( size ) )
    end

    http.Fetch( url, success, error, self.headers )
end

function express:Put( data, cb )
    local success = function( code, body )
        assert( code >= 200 and code < 300, "Invalid response code: " .. code )

        local response = util.JSONToTable( body )
        assert( response, "Invalid JSON" )
        assert( response.id, "No ID returned" )

        cb( response.id )
    end

    HTTP( {
        method = "POST",
        url = self:makeAccessURL(),
        headers = self.headers,
        body = util.TableToJSON( { data = data } ),
        success = success,
        failed = error
    } )
end

-- Run the express receiver for the given message
function express:Call( message, ply, data )
    local cb = self._receivers[string.lower( message )]
    if not cb then
        ErorrNoHalt( "No receiver for " .. message )
    end

    if CLIENT then return cb( data ) end
    if SERVER then return cb( ply, data ) end
end

-- Run the express pre-download receiver for the given message
function express:CallPreDownload( message, ply, id, needsProof )
    local cb = self._preDlReceivers[string.lower( message )]
    if not cb then return end

    if CLIENT then return cb( message, id, needsProof ) end
    if SERVER then return cb( message, ply, id, needsProof ) end
end

function express.OnMessage( _, ply )
    local message = net.ReadString()
    local id = net.ReadString()
    local needsProof = net.ReadBool()

    -- TODO: Don't GetSize if there aren't any pre-download receivers
    express:GetSize( id, function( size )
        local check = express:CallPreDownload( message, ply, id, size, needsProof )
        if check == false then return end

        express:_get( id, function( data, hash )
            express:Call( message, ply, data )

            if not needsProof then return end
            net.Start( "express_proof" )
            net.WriteString( hash )
            express.shSend( ply )
        end )
    end )
end

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

