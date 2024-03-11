AddCSLuaFile()

require( "pon" )
if SERVER then
    util.AddNetworkString( "express" )
    util.AddNetworkString( "express_proof" )
    util.AddNetworkString( "express_small" )
    util.AddNetworkString( "express_receivers_made" )
end

express = {}
express._receivers = {}
express._protocol = "http"
express._maxRetries = 35
express._awaitingProof = {}
express._preDlReceivers = {}
express._maxDataSize = 100 * 1024 * 1024
express._jsonHeaders = {
    ["Accept"] = "application/json",
    ["Content-Type"] = "application/json"
}
express._bytesHeaders = {
    ["Accept"] = "application/octet-stream"
}


-- Removes a receiver --
function express.ClearReceiver( message )
    message = string.lower( message )
    express._receivers[message] = nil
end


-- Registers a PreDownload receiver --
function express.ReceivePreDl( message, preDl )
    message = string.lower( message )
    express._preDlReceivers[message] = preDl
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

    local failed = function( reason )
        error( "Express: Failed to upload data: " .. reason )
    end

    self.HTTP( {
        method = "POST",
        url = self:makeAccessURL( "write" ),
        body = data,
        success = success,
        failed = failed,
        headers = {
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
        if SERVER then
            -- Server decides for itself
            return express:_getSize( id, makeRequest )
        else
            -- Clients trust the server
            local size = net.ReadUInt( 27 )
            return makeRequest( size )
        end
    end

    makeRequest()
end

-- Handles a net message with data sent via NetStream
function express.OnSmallMessage( _, ply )
    local message = net.ReadString()

    local hasReceiver = express:_getReceiver( message )

    local id = "netstream:" .. message
    local size = net.ReadUInt( 27 )
    local needsProof = net.ReadBool()

    if hasReceiver then
        local shouldHalt = false

        if express:_getPreDlReceiver( message ) then
            local check = express:CallPreDownload( message, ply, id, size, needsProof )
            if check == false then
                shouldHalt = true
            end
        end

        net.ReadStream( ply, function( body )
            -- FIXME: Still calls the onProof callbacak even if we exit early
            if shouldHalt then return end

            express.HandleReceivedData( body, "", function( data )
                express:Call( message, ply, data )
            end )
        end )
    else
        -- We have to read it even if we don't want it, otherwise it stays in the sender's WriteStreams
        -- FIXME: This still calls the onProof callback if it's provided
        net.ReadStream( ply, function()
            error( "Express: Received a message that has no listener! (" .. message .. ")" )
        end )
    end
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


function express.HTTP( tbl )
    return (express.HTTP_Override or _G.HTTP)( tbl )
end


net.Receive( "express", express.OnMessage )
net.Receive( "express_proof", express.OnProof )
net.Receive( "express_small", express.OnSmallMessage )

include( "sh_helpers.lua" )

if SERVER then
    include( "sv_init.lua" )
    AddCSLuaFile( "cl_init.lua" )
else
    include( "cl_init.lua" )
end

do
    local loaded = false
    local function alertLoad()
        loaded = true
        hook.Run( "ExpressLoaded" )
    end

    hook.Add( "CreateTeams", "ExpressLoaded", alertLoad )

    -- A backup in case our CreateTeams hook is never called
    hook.Add( "Think", "ExpressLoadedBackup", function()
        hook.Remove( "Think", "ExpressLoadedBackup" )
        if loaded then return end

        alertLoad()
    end )
end
