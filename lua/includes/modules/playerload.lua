local function getHookName( ply )
    local steamID = ply:SteamID64()
    return "GM_FullLoad_" .. steamID
end

hook.Add( "PlayerInitialSpawn", "GM_FullLoadSetup", function( spawnedPly )
    local hookName = getHookName( spawnedPly )

    hook.Add( "SetupMove", hookName, function( ply, _, cmd )
        if ply ~= spawnedPly then return end
        if cmd:IsForced() then return end

        hook.Remove( "SetupMove", hookName )
        hook.Run( "PlayerFullLoad", ply )
    end )
end )

hook.Add( "PlayerDisconnected", "GM_FullLoadCleanup", function( ply )
    local hookName = getHookName( ply )
    hook.Remove( "SetupMove", hookName )
end )
