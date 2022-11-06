net.Receive( "express_access", function()
    print( "Received Express access token" )
    express.access = net.ReadString()
end )
