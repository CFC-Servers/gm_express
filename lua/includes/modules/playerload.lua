local load_queue = {}

hook.Add( "PlayerInitialSpawn", "GM_FullLoadQueue", function( ply )
    load_queue[ply] = true
end )

hook.Add( "SetupMove", "GM_FullLoadInit", function( ply, _, cmd )
    if not loadQueue[ply] then return end
    if cmd:IsForced() then return end

    load_queue[ply] = nil
    hook.Run( "PlayerFullLoad", ply )
end )
