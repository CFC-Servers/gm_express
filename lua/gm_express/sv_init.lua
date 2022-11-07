require( "playerload" )
util.AddNetworkString( "express_access" )

function express.Broadcast( message, data, onProof )
    express:Send( message, data, player.GetAll(), onProof )
end

hook.Add( "PlayerConnect", "Express_Register", function()
    hook.Remove( "PlayerConnect", "Express_Register" )
    local url = express:makeBaseURL() .. "/register"

    http.Fetch( url, function( body, _, _, code )
        if code ~= 200 then error( body ) end

        local response = util.JSONToTable( body )
        assert( response, "Invalid JSON" )
        assert( response.server, "No server access token" )
        assert( response.client, "No client access token" )

        express.access = response.server
        express._clientAccess = response.client
    end, error, express.headers )
end )

hook.Add( "PlayerFullLoad", "Express_Access", function( ply )
    net.Start( "express_access" )
    net.WriteString( express._clientAccess )
    net.Send( ply )
end )
