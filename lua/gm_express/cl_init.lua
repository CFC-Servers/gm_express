net.Receive( "express_access", function()
    print( "Received Express access token" )
    Express.access = net.ReadString()
end )
