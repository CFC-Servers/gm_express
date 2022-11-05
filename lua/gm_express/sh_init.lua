AddCSLuaFile()

require( "pon" )
if SERVER then util.AddNetworkString( "express" ) end

Express = {}
Express.listeners = {}
Express.domain = CreateConVar(
    "express_domain", "gmod.express", FCVAR_ARCHIVE + FCVAR_REPLICATED, "The domain of the Express server"
)

function Express:makeURL()
    return "https://" .. self.domain:GetString() .. "/" .. self.access
end

function Express:Get( id, cb )
    local url = self:makeURL() .. "/" .. id

    local success = function( body, _, _, code )
        if code == 200 then
            local data = util.JSONToTable( body )
            assert( data, "Invalid JSON" )
            assert( data.data, "No data" )

            cb( data.data )
        else
            -- TODO: Handle error
            cb()
        end
    end

    local failure = error

    http.Fetch( url, success, failure )
end

function Express:Put( data, cb )
    local url = self:makeURL()

    local success = function( body, _, _, code )
        if code == 200 then
            local response = util.JSONToTable( body )
            assert( response, "Invalid JSON" )
            assert( response.id, "No ID returned" )

            cb( response.id )
        else
            error( body )
        end
    end

    local failure = error

    http.Post( url, { data = pon.encode( data ) }, success, failure )
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

net.Receive( "express", function()
    local message = net.ReadString()
    local id = net.ReadString()

    Express:Get( id, function( data )
        Express:Call( message, data )
    end )
end )


if SERVER then
    include( "express/sv_init.lua" )
else
    net.Receive( "express_access", function()
        Express.access = net.ReadString()
    end )
end
