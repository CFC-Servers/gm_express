express._receiverMadeQueue = {}
express._canSendReceiverMade = false


net.Receive( "express_access", function()
    express:SetAccess( net.ReadString() )
    express:_sendReceiversMadeQueue()
end )

function express:_sendReceiversMadeQueue()
    express._canSendReceiverMade = true

    local messages = table.GetKeys( express._receiverMadeQueue )
    express:_alertReceiversMade( unpack( messages ) )
end

function express:_alertReceiversMade( ... )
    local names = { ... }
    local receiverCount = #names

    net.Start( "express_receivers_made" )
    net.WriteUInt( receiverCount, 8 )

    for i = 1, receiverCount do
        net.WriteString( names[i] )
    end

    net.SendToServer()
end


-- Registers a basic receiver --
function express.Receive( message, cb )
    express:_setReceiver( message, cb )

    if not express._canSendReceiverMade then
        express._receiverMadeQueue[message] = true
        return
    end

    express:_alertReceiversMade( message )
end


-- Calls the main _send function but passes nil for the recipient --
function express.Send( message, data, onProof )
    express:_send( message, data, nil, onProof )
end


function express:SetExpected( hash, cb )
    self._awaitingProof[hash] = cb
end
