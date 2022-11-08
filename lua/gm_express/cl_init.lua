net.Receive( "express_access", function()
    express:SetAccess( net.ReadString() )
end )

function express.Send( message, data, onProof )
    express:_send( message, data, nil, onProof )
end

function express:SetExpected( hash, cb )
    self._awaitingProof[hash] = cb
end
