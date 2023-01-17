return {
    groupName = "Shared Main",

    beforeEach = function()
        stub( express, "makeAccessURL" ).returns( "https://gmod.express/v1/action/access-token" )
    end,

    cases = {
        {
            name = "Sets up necessary variables and hooks",
            func = function()
                expect( express ).to.exist()
                expect( express ).to.beA( "table" )

                expect( express._receivers ).to.exist()
                expect( express._receivers ).to.beA( "table" )

                expect( express._protocol ).to.exist()
                expect( string.StartWith( express._protocol, "http" ) ).to.beTrue()

                expect( express._maxDataSize ).to.exist()
                expect( express._maxDataSize ).to.beA( "number" )
                expect( express._maxDataSize ).to.beLessThan( ( 24 * 1024 * 1024 ) + 1 )

                expect( express._jsonHeaders ).to.exist()
                expect( express._jsonHeaders ).to.beA( "table" )
                expect( express._jsonHeaders["Content-Type"] ).to.equal( "application/json" )

                expect( express._bytesHeaders ).to.exist()
                expect( express._bytesHeaders ).to.beA( "table" )
                expect( express._bytesHeaders["Accept"] ).to.equal( "application/octet-stream" )

                expect( express.domain ).to.exist()
                expect( tostring( express.domain ) ).to.equal( tostring( GetConVar( "express_domain" ) ) )

                expect( express.domain_cl ).to.exist()
                expect( tostring( express.domain_cl ) ).to.equal( tostring( GetConVar( "express_domain_cl" ) ) )

                expect( net.Receivers["express"] ).to.exist()
                expect( net.Receivers["express_proof"] ).to.exist()
                expect( net.Receivers["express_receivers_made"] ).to.exist()
            end
        },

        -- express:_setReceiver
        {
            name = "express:_setReceiver adds the given callback to the receivers table and normalizes the name",
            func = function( state )
                state.original_receivers = table.Copy( express._receivers )
                express._receivers = {}

                local callback = stub()
                express:_setReceiver( "TEST-MESSAGE", callback )

                expect( express._receivers["test-message"] ).to.equal( callback )
            end,

            cleanup = function( state )
                express._receivers = state.original_receivers
            end
        },

        -- express.ClearReceiver
        {
            name = "express.ClearReceiver removes the callback for the given message and normalizes the name",
            func = function( state )
                state.original_receivers = table.Copy( express._receivers )
                express._receivers = {}

                express.Receive( "test-message", stub() )

                express.ClearReceiver( "TEST-MESSAGE" )
                expect( express._receivers["test-message"] ).toNot.exist()
            end,

            cleanup = function( state )
                express._receivers = state.original_receivers
            end
        },

        -- express.ReceivePreDl
        {
            name = "express.ReceivePreDl adds the given callback to the receivers table and normalizes the name",
            func = function( state )
                state.original_preDlReceivers = table.Copy( express._preDlReceivers )
                express._preDlReceivers = {}

                local callback = stub()
                express.ReceivePreDl( "TEST-MESSAGE", callback )

                expect( express._preDlReceivers["test-message"] ).to.equal( callback )
            end,

            cleanup = function( state )
                express._preDlReceivers = state.original_preDlReceivers
            end
        },

        -- express.Get
        {
            name = "express.Get errors if the request fails",
            func = function()
                local httpStub = stub( _G, "HTTP" ).with( function( options )
                    expect( options.failed ).to.equal( error )
                end )

                express:Get( "test-id", stub() )

                expect( httpStub ).was.called()
            end
        },
        {
            name = "express.Get errors if the requests succeeds with a non 200-level status code",
            func = function()
                local callback = stub()

                local httpStub = stub( _G, "HTTP" ).with( function( options )
                    expect( options.success, 418, "" ).to.errWith( "Express: Invalid response code (418)" )
                end )

                express:Get( "test-id", callback )

                expect( httpStub ).was.called()
                expect( callback ).wasNot.called()
            end
        },
        {
            name = "express.Get calls the given callback on successful response",
            func = function()
                stub( util, "SHA1" ).returns( "test-hash" )
                stub( util, "Decompress" ).returns( "test-data" )
                stub( pon, "decode" ).returns( {} )

                local callback = stub()

                local httpStub = stub( _G, "HTTP" ).with( function( options )
                    options.success( 200, "" )
                end )

                express:Get( "test-id", callback )

                expect( httpStub ).was.called()
                expect( callback ).was.called()
            end
        },

        -- express.GetSize
        {
            name = "express.GetSize errors if the request fails",
            func = function()
                local httpStub = stub( _G, "HTTP" ).with( function( options )
                    expect( options.failed ).to.equal( error )
                end )

                express:GetSize( "test-id", stub() )

                expect( httpStub ).was.called()
            end
        },
        {
            name = "express.GetSize errors if the requests succeeds with a non 200-level status code",
            func = function()
                local callback = stub()

                local httpStub = stub( _G, "HTTP" ).with( function( options )
                    expect( options.success, 418, "" ).to.errWith( "Express: Invalid response code (418)" )
                end )

                express:GetSize( "test-id", callback )

                expect( httpStub ).was.called()
                expect( callback ).wasNot.called()
            end
        },
        {
            name = "express.GetSize errors if it cannot read the retrieved data to JSON",
            func = function()
                stub( util, "JSONToTable" ).returns( nil )

                local callback = stub()

                local httpStub = stub( _G, "HTTP" ).with( function( options )
                    expect( options.success, 200, "" ).to.errWith( "Invalid JSON" )
                end )

                express:GetSize( "test-id", callback )

                expect( httpStub ).was.called()
                expect( callback ).wasNot.called()
            end
        },
        {
            name = "express.GetSize errors if it cannot read the size from the retrieved JSON",
            func = function()
                stub( util, "JSONToTable" ).returns( { notTheSizeLol = 123 } )

                local callback = stub()

                local httpStub = stub( _G, "HTTP" ).with( function( options )
                    expect( options.success, 200, "" ).to.errWith( "No size data" )
                end )

                express:GetSize( "test-id", callback )

                expect( httpStub ).was.called()
                expect( callback ).wasNot.called()
            end
        },
        {
            name = "express.GetSize calls the given callback on successful response",
            func = function()
                stub( util, "JSONToTable" ).returns( { size = 123 } )

                local callback = stub()

                local httpStub = stub( _G, "HTTP" ).with( function( options )
                    options.success( 200, "" )
                end )

                express:GetSize( "test-id", callback )

                expect( httpStub ).was.called()
                expect( callback ).was.called()
            end
        },

        -- express.Put
        {
            name = "express.Put errors if the request fails",
            func = function()
                local httpStub = stub( _G, "HTTP" ).with( function( options )
                    expect( options.failed ).to.equal( error )
                end )

                express:Put( "test-data", stub() )

                expect( httpStub ).was.called()
            end
        },
        {
            name = "express.Put errors if the requests succeeds with a non 200-level status code",
            func = function()
                local callback = stub()

                local httpStub = stub( _G, "HTTP" ).with( function( options )
                    expect( options.success, 418, "" ).to.errWith( "Express: Invalid response code (418)" )
                end )

                express:Put( "test-data", callback )

                expect( httpStub ).was.called()
                expect( callback ).wasNot.called()
            end
        },
        {
            name = "express.Put errors if it cannot read the retrieved data to JSON",
            func = function()
                stub( util, "JSONToTable" ).returns( nil )

                local callback = stub()

                local httpStub = stub( _G, "HTTP" ).with( function( options )
                    expect( options.success, 200, "" ).to.errWith( "Invalid JSON" )
                end )

                express:Put( "test-data", callback )

                expect( httpStub ).was.called()
                expect( callback ).wasNot.called()
            end
        },
        {
            name = "express.Put errors if it cannot read the ID from the retrieved JSON",
            func = function()
                stub( util, "JSONToTable" ).returns( { notTheIdLol = "test-id" } )

                local callback = stub()

                local httpStub = stub( _G, "HTTP" ).with( function( options )
                    expect( options.success, 200, "" ).to.errWith( "No ID returned" )
                end )

                express:Put( "test-data", callback )

                expect( httpStub ).was.called()
                expect( callback ).wasNot.called()
            end
        },
        {
            name = "express.Put calls the given callback on successful response",
            func = function()
                stub( util, "JSONToTable" ).returns( { id = "test-id" } )

                local callback = stub()

                local httpStub = stub( _G, "HTTP" ).with( function( options )
                    options.success( 200, "" )
                end )

                express:Put( "test-data", callback )

                expect( httpStub ).was.called()
                expect( callback ).was.called()
            end
        },

        -- express.Call
        {
            name = "express.Call runs the stored callback for the given message",
            func = function()
                local callback = stub()
                stub( express, "_getReceiver" ).returns( callback )

                express:Call( "test-message" )
                expect( callback ).was.called()
            end
        },

        -- express.CallPreDownload
        {
            name = "express.CallPreDownload runs the stored pre-download callback for the given message",
            func = function()
                local callback = stub()
                stub( express, "_getPreDlReceiver" ).returns( callback )

                express:CallPreDownload( "test-message" )
                expect( callback ).was.called()
            end
        },

        -- express.OnMessage
        {
            name = "express.OnMessage errors if no callback exists for the given message",
            func = function()
                stub( net, "ReadBool" )
                stub( express, "GetSize" )
                stub( express, "CallPreDownload" )
                stub( express, "_get" )
                stub( express, "_getPreDlReceiver" )
                stub( net, "ReadString" ).returnsSequence( { "test-message" } )

                stub( express, "_getReceiver" ).returns( nil )
                expect( express.OnMessage ).to.errWith( "Express: Received a message that has no listener! (test-message)" )
            end
        },
        {
            name = "express.OnMessage calls GetSize if the message has a pre-download receiver",
            func = function()
                stub( net, "ReadBool" )
                stub( express, "CallPreDownload" )
                stub( express, "_get" )
                stub( express, "_getReceiver" ).returns( stub() )
                stub( express, "_getPreDlReceiver" ).returns( stub() )
                stub( net, "ReadString" ).returnsSequence( { "test-message" } )

                local getSizeStub = stub( express, "_getSize" )

                express:OnMessage()

                expect( getSizeStub ).was.called()
            end
        },
        {
            name = "express.OnMessage does not call GetSize if the message doesn't have a pre-download receiver",
            func = function()
                stub( net, "ReadBool" )
                stub( express, "CallPreDownload" )
                stub( express, "_get" )
                stub( express, "_getReceiver" ).returns( stub() )
                stub( express, "_getPreDlReceiver" )
                stub( net, "ReadString" ).returnsSequence( { "test-message" } )

                local getSizeStub = stub( express, "GetSize" )

                express:OnMessage()

                expect( getSizeStub ).wasNot.called()
            end
        },
        {
            name = "express.OnMessage calls CallPreDownload if the message has a pre-download receiver",
            func = function()
            end
        },
        {
            name = "express.OnMessage does not call _get if CallPreDownload returns false",
            func = function()
            end
        },
        {
            name = "express.OnMessage calls _get and Call",
            func = function()
            end
        },
        {
            name = "express.OnMessage networks the data hash if proof was requested",
            func = function()
            end
        },
        {
            name = "express.OnMessage does not network the data hash if proof was not requested",
            func = function()
            end
        },

        -- express.OnProof
        {
            name = "express.OnProof prefixes the hash with the player's steam ID if a player is given",
            func = function()
            end
        },
        {
            name = "express.OnProof uses only the data hash if no player is given",
            func = function()
            end
        },
        {
            name = "express.OnProof runs the stored proof callback for the given hash",
            func = function()
            end
        }
    }
}
