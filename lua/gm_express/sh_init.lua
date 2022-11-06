AddCSLuaFile()

require( "pon" )
if SERVER then util.AddNetworkString( "express" ) end

Express = {}
Express._listeners = {}
Express._protocol = "http"
Express.headers = { ["Content-Type"] = "application/json" }
Express.domain = CreateConVar(
    "express_domain", "gmod.express", FCVAR_ARCHIVE + FCVAR_REPLICATED, "The domain of the Express server"
)

function Express:makeBaseURL()
    return self._protocol .. "://" .. self.domain:GetString()
end

function Express:makeAccessURL()
    return self:makeBaseURL() .. "/" .. self.access
end

function Express:Get( id, cb )
    local url = self:makeAccessURL() .. "/" .. id

    local success = function( body, _, _, code )
        if code >= 200 and code < 300 then
            local data = util.JSONToTable( body )
            assert( data, "Invalid JSON" )
            assert( data.data, "No data" )

            data = data.data
            data = util.Base64Decode( data )
            assert( data, "Invalid data" )

            data = pon.decode( data )

            cb( data )
        else
            -- TODO: Handle error
            cb()
        end
    end

    local failure = error

    http.Fetch( url, success, failure, self.headers )
end

function Express:Put( data, cb )
    local url = self:makeAccessURL()

    local success = function( code, body )
        if code >= 200 and code < 300 then
            local response = util.JSONToTable( body )
            assert( response, "Invalid JSON" )
            assert( response.id, "No ID returned" )

            cb( response.id )
        else
            error( body )
        end
    end

    local failure = error

    data = util.Base64Encode( pon.encode( data ) )

    HTTP( {
        method = "POST",
        url = url,
        headers = self.headers,
        body = util.TableToJSON( { data = data } ),
        success = success,
        failed = failure
    } )
end

function Express:Listen( message, cb )
    self._listeners[string.lower( message )] = cb
end

function Express:Call( message, ... )
    local cb = self._listeners[string.lower( message )]
    if cb then
        cb( ... )
    end
end

function Express:Send( message, data, plys )
    print( "Sending " .. message )
    self:Put( data, function( id )
        net.Start( "express" )
        net.WriteString( message )
        net.WriteString( id )

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

    print( message, id )

    Express:Get( id, function( data )
        Express:Call( message, data, ply )
    end )
end )


if SERVER then
    include( "sv_init.lua" )
    AddCSLuaFile( "cl_init.lua" )
else
    net.Receive( "express_access", function()
        Express.access = net.ReadString()
    end )
end
