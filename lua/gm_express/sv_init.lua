require( "playerload" )
util.AddNetworkString( "express_access" )

function express.Broadcast( message, data, onProof )
    express:Send( message, data, player.GetAll(), onProof )
end

function express.Register()
    -- All stored items expire after a day
    -- That includes tokens, so we need
    -- to re-register if we make it this far
    if not timer.Exists( "Express_Register" ) then
        local oneDay = 60 * 60 * 24
        timer.Create( "Express_Register", oneDay, 0, express.Register )
    end

    express._putCache = {}
    local url = express:makeBaseURL() .. "/register"

    http.Fetch( url, function( body, _, _, code )
        assert( code >= 200 and code < 300, "Invalid status code: " .. code )

        local response = util.JSONToTable( body )
        assert( response, "Invalid JSON" )
        assert( response.server, "No server access token" )
        assert( response.client, "No client access token" )

        express:SetAccess( response.server )
        express._clientAccess = response.client

        if player.GetCount() == 0 then return end

        net.Start( "express_access" )
        net.WriteString( express._clientAccess )
        net.Broadcast()
    end, error, express.headers )
end

function express.Send( ... )
    express:_send( ... )
end

function express:SetExpected( hash, cb, plys )
    if not istable( plys ) then plys = { plys } end

    for _, ply in ipairs( plys ) do
        local key = ply:SteamID64() .. "-" .. hash
        self._awaitingProof[key] = cb
    end
end

hook.Add( "PlayerConnect", "Express_Register", function()
    hook.Remove( "PlayerConnect", "Express_Register" )
    express:Register()
end )

hook.Add( "PlayerFullLoad", "Express_Access", function( ply )
    net.Start( "express_access" )
    net.WriteString( express._clientAccess )
    net.Send( ply )
end )
