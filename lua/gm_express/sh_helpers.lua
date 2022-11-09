AddCSLuaFile()
express._putCache = {}
express._waitingForAccess = {}

function express.shSend( target )
    if CLIENT then
        net.SendToServer()
    else
        net.Send( target )
    end
end

function express:makeBaseURL()
    return self._protocol .. "://" .. self.domain:GetString()
end

function express:makeAccessURL( ... )
    local url = self:makeBaseURL()
    local args = {self.access,  ... }

    -- if #args == 0 then return url end
    return url .. "/" .. table.concat( args, "/" )
end

function express:SetAccess( access )
    self.access = access

    local waiting = self._waitingForAccess
    for _, callback in ipairs( waiting ) do
        callback()
    end

    self._waitingForAccess = {}
end

function express:_get( id, cb )
    if self.access then
        return self:Get( id, cb )
    end

    table.insert( self._waitingForAccess, function()
        self:Get( id, cb )
    end )
end

function express:_put( data, cb )
    data = util.Base64Encode( pon.encode( data ) )
    local hash = util.SHA256( data )

    local cachedId = self._putCache[hash]
    if cachedId then
        cb( cachedId, hash )
        return
    end

    local function wrapCb( id )
        self._putCache[hash] = id
        cb( id, hash )
    end

    return self:Put( data, wrapCb )
end

function express:_send( message, data, plys, onProof )
    self:_put( data, function( id, hash )
        net.Start( "express" )
        net.WriteString( message )
        net.WriteString( id )
        net.WriteBool( onProof ~= nil )

        if onProof then
            self:SetExpected( hash, onProof, plys )
        end

        express.shSend( plys )
    end )
end
