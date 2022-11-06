require( "playerload" )
util.AddNetworkString( "express_access" )

function Express:Broadcast( data )
    self:Send( data, player.GetAll() )
end

hook.Add( "PlayerConnect", "Express_Register", function()
    hook.Remove( "PlayerConnect", "Express_Register" )
    local url = Express:makeBaseURL() .. "/register"

    http.Fetch( url, function( body, _, _, code )
        if code ~= 200 then error( body ) end

        local response = util.JSONToTable( body )
        assert( response, "Invalid JSON" )
        assert( response.server, "No server access token" )
        assert( response.client, "No client access token" )

        Express.access = response.server
        Express._clientAccess = response.client
    end, error, Express.headers )
end )

hook.Add( "PlayerFullLoad", "Express_Access", function( ply )
    print( "Sending client access to " .. ply:Nick() )
    net.Start( "express_access" )
    net.WriteString( Express._clientAccess )
    net.Send( ply )
end )
