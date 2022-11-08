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
express.headers = { ["Content-Type"] = "application/json" }
express.domain = CreateConVar(
    "express_domain", "gmod.express", FCVAR_ARCHIVE + FCVAR_REPLICATED, "The domain of the Express server"
)

function express.Receive( message, cb )
    express._receivers[string.lower( message )] = cb
end

function express:Get( id, cb )
    local url = self:makeAccessURL( id )

    local success = function( body, _, _, code )
        print( "express: got " .. id .. " with code " .. code )
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

function express:Put( data, cb )
    local success = function( code, body )
        print( code, body )
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

-- Run express receiver for the given message
function express:Call( message, ply, data )
    local cb = self._receivers[string.lower( message )]
    if not cb then
        ErorrNoHalt( "No receiver for " .. message )
    end

    if CLIENT then return cb( data ) end
    if SERVER then return cb( ply, data ) end
end

-- Receiver for the "express" net message
function express.OnMessage( _, ply )
    local message = net.ReadString()
    local id = net.ReadString()
    local needsProof = net.ReadBool()

    print( "Received express message: ", message, id, needsProof )

    express:_get( id, function( data, hash )
        express:Call( message, ply, data )

        if needsProof then
            net.Start( "express_proof" )
            print( "Sending proof for " .. id, hash )
            net.WriteString( hash )

            express.shSend( ply )
        end
    end )
end

-- Receiver for the "express_proof" net message
function express.OnProof( _, ply )
    local prefix = ply and ply:SteamID64() .. "-" or ""
    local hash = prefix .. net.ReadString()

    local cb = express._awaitingProof[hash]
    if cb then
        cb( ply )
        express._awaitingProof[hash] = nil
    end
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

