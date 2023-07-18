require( "playerload" )
util.AddNetworkString( "express_access" )


-- Registers a basic receiver --
function express.Receive( message, cb )
    express:_setReceiver( message, cb )
end


-- Broadcasts the given data to all connected players --
function express.Broadcast( message, data, onProof )
    express.Send( message, data, player.GetAll(), onProof )
end


-- Registers with the current API, storing and distributing access tokens --
function express.Register()
    -- All stored items expire after a day
    -- That includes tokens, so we need
    -- to re-register if we make it this far
    local oneDay = 60 * 60 * 24
    timer.Create( "Express_Register", oneDay, 0, express.Register )

    local url = express:makeBaseURL() .. "/register"

    local failed = function( reason )
        error( "Express: Failed to register with the API. This is bad! (reason " .. reason .. ")" )
    end

    local success = function( code, body )
        express._checkResponseCode( code )

        local response = util.JSONToTable( body )
        assert( response, "Invalid JSON" )
        assert( response.server, "Could not get Server Access Token from API" )
        assert( response.client, "Could not get Client Access Token from API" )

        express:SetAccess( response.server )
        express._clientAccess = response.client

        if player.GetCount() == 0 then return end

        net.Start( "express_access" )
        net.WriteString( express._clientAccess )
        net.Broadcast()
    end

    express.HTTP( {
        url = url,
        method = "GET",
        success = success,
        failed = failed,
        headers = express.jsonHeaders,
        timeout = express:_getTimeout()
    } )
end


-- Passthrough for the shared _send function --
function express.Send( ... )
    express:_send( ... )
end


-- Sets a callback for each of the recipients that will run when they provide proof --
function express:SetExpected( hash, cb, plys )
    if not istable( plys ) then plys = { plys } end

    for _, ply in ipairs( plys ) do
        local key = ply:SteamID64() .. "-" .. hash
        self._awaitingProof[key] = cb
    end
end


-- Runs a hook when a player makes a new express Receiver --
function express._onReceiverMade( _, ply )
    local messageCount = net.ReadUInt( 8 )

    for _ = 1, messageCount do
        local name = string.lower( net.ReadString() )
        hook.Run( "ExpressPlayerReceiver", ply, name )
    end
end

net.Receive( "express_receivers_made", express._onReceiverMade )


-- Send the player their access token as soon as it's safe to do so --
function express._onPlayerLoaded( ply )
    net.Start( "express_access" )
    net.WriteString( express._clientAccess )
    net.Send( ply )
end

hook.Add( "PlayerFullLoad", "Express_PlayerReady", express._onPlayerLoaded )
