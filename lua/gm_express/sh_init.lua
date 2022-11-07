AddCSLuaFile()

require( "pon" )
if SERVER then util.AddNetworkString( "express" ) end

express = {}
express._sendCache = {}
express._listeners = {}
express._protocol = "http"
express._awaitingProof = {}
express.headers = { ["Content-Type"] = "application/json" }
express.domain = CreateConVar(
    "express_domain", "gmod.express", FCVAR_ARCHIVE + FCVAR_REPLICATED, "The domain of the Express server"
)

function express:makeBaseURL()
    return self._protocol .. "://" .. self.domain:GetString()
end

function express:makeAccessURL()
    return self:makeBaseURL() .. "/" .. self.access
end

function express:setExpected( hash, cb, plys )
    if CLIENT then
        self._awaitingProof[hash] = cb
    else
        if not istable( plys ) then plys = { plys } end

        for _, ply in ipairs( plys ) do
            local key = ply:SteamID64() .. "-" .. hash
            self._awaitingProof[key] = cb
        end
    end
end

function express:Get( id, cb )
    local url = self:makeAccessURL() .. "/" .. id

    local success = function( body, _, _, code )
        if code >= 200 and code < 300 then
            local data = util.JSONToTable( body )
            assert( data, "Invalid JSON" )
            assert( data.data, "No data" )

            data = data.data
            local hash = util.SHA256( data )

            data = util.Base64Decode( data )
            assert( data, "Invalid data" )

            data = pon.decode( data )

            cb( data, hash )
        else
            -- TODO: Handle error
            cb()
        end
    end

    local failure = error

    http.Fetch( url, success, failure, self.headers )
end

function express:Put( data, cb )
    data = util.Base64Encode( pon.encode( data ) )
    local hash = util.SHA256( data )

    local cached = self._sendCache[hash]
    if cached then
        cb( cached )
        return
    end

    local success = function( code, body )
        if code >= 200 and code < 300 then
            local response = util.JSONToTable( body )
            assert( response, "Invalid JSON" )
            assert( response.id, "No ID returned" )

            self._sendCache[hash] = response.id

            cb( response.id, hash )
        else
            error( body )
        end
    end

    local failure = error

    HTTP( {
        method = "POST",
        url = self:makeAccessURL(),
        headers = self.headers,
        body = util.TableToJSON( { data = data } ),
        success = success,
        failed = failure
    } )
end

function express.Listen( message, cb )
    express._listeners[string.lower( message )] = cb
end

function express.RemoveListener( message )
    express._listeners[string.lower( message )] = nil
end

function express:Call( message, ... )
    local cb = self._listeners[string.lower( message )]
    if cb then
        cb( ... )
    end
end

function express.Send( message, data, plys, onProof )
    express:Put( data, function( id, hash )
        net.Start( "express" )
        net.WriteString( message )
        net.WriteString( id )
        net.WriteBool( onProof ~= nil )

        if onProof then
            express:setExpected( plys, hash, onProof )
        end

        if CLIENT then
            net.SendToServer()
        else
            net.Send( plys )
        end
        print( "Sent " .. message .. " with ID " .. id )
    end )
end

net.Receive( "express", function( _, ply )
    local message = net.ReadString()
    local id = net.ReadString()
    local needsProof = net.ReadBool()

    print( message, id, needsProof )

    express:Get( id, function( data, hash )
        express:Call( message, data, ply )

        if needsProof then
            net.Start( "express_proof" )
            net.WriteString( hash )

            if CLIENT then
                net.SendToServer()
            else
                net.Send( ply )
            end
        end
    end )
end )

net.Receive( "express_proof", function( _, ply )
    local prefix = ply and ply:SteamID64() .. "-" or ""
    local hash = prefix .. net.ReadString()

    local cb = express._awaitingProof[hash]
    if cb then
        cb( ply )
        express._awaitingProof[hash] = nil
    end
end )


if SERVER then
    include( "sv_init.lua" )
    AddCSLuaFile( "cl_init.lua" )
else
    net.Receive( "express_access", function()
        express.access = net.ReadString()
    end )
end
