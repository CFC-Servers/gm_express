express = {}
function express.Receive()
    error( "express.Receive called before Express has loaded! Try using the ExpressLoaded hook to know when it's safe" )
end

AddCSLuaFile( "includes/modules/sfs.lua" )
include( "gm_express/sh_init.lua" )
