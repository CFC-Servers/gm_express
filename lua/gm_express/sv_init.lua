hook.Add( "InitPostEntity", "Express_Register", function()
    http.Fetch( Express:makeURL() .. "/register", function( body, _, _, code )
        if code ~= 200 then error( body ) end

        local response = util.JSONToTable( body )
        assert( response, "Invalid JSON" )
        assert( response.server, "No server access token" )
        assert( response.client, "No client access token" )

        Express.access = response.server
        Express._clientAccess = response.client
    end )
end )

hook.Add( "PlayerFullLoad", "Express_Access", function( ply )
    net.Start( "express_access" )
    net.WriteString( Express._clientAccess )
    net.Send( ply )
end )
