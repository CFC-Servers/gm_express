return {
    groupName = "Shared Main",
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

                expect( net.Receivers["express"] ).to.exist()
                expect( net.Receivers["express_proof"] ).to.exist()
            end
        },

        -- express.Receive
        {
            name = "express.Receive adds the given callback to the receivers table and normalizes the name",
            func = function( state )
                state.original_receivers = table.Copy( express._receivers )
                express._receivers = {}

                local callback = stub()
                express.Receive( "TEST-MESSAGE", callback )

                expect( express._receivers["test-message"] ).to.equal( callback )
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
                local fetchStub = stub( http, "Fetch" ).with( function( _, _, errorCb )
                    expect( errorCb ).to.equal( error )
                end )

                express:Get( "test-id", stub() )

                expect( fetchStub ).to.haveBeenCalled()
            end
        },
        {
            name = "express.Get errors if the requests succeeds with a non 200-level status code",
            func = function()
                local callback = stub()

                local fetchStub = stub( http, "Fetch" ).with( function( _, success )
                    expect( success, "", "", "", 418 ).to.errWith( "Invalid status code: 418" )
                end )

                express:Get( "test-id", callback )

                expect( fetchStub ).to.haveBeenCalled()
                expect( callback ).notTo.haveBeenCalled()
            end
        },
        {
            name = "express.Get errors if it cannot decompress the retrieved data",
            func = function()
                stub( util, "SHA1" ).returns( "test-hash" )
                stub( util, "Decompress" ).returns( nil )

                local callback = stub()

                local fetchStub = stub( http, "Fetch" ).with( function( _, success )
                    expect( success, "", "", "", 200 ).to.errWith( "Invalid data" )
                end )

                express:Get( "test-id", callback )

                expect( fetchStub ).to.haveBeenCalled()
                expect( callback ).notTo.haveBeenCalled()
            end
        },
        {
            name = "express.Get calls the given callback on successful response",
            func = function()
                stub( util, "SHA1" ).returns( "test-hash" )
                stub( util, "Decompress" ).returns( "test-data" )
                stub( pon, "decode" ).returns( {} )

                local callback = stub()

                local fetchStub = stub( http, "Fetch" ).with( function( _, success )
                    success( "", "", "", 200 )
                end )

                express:Get( "test-id", callback )

                expect( fetchStub ).to.haveBeenCalled()
                expect( callback ).to.haveBeenCalled()
            end
        },

        -- express.GetSize
        {
            name = "express.GetSize errors if the request fails",
            func = function()
                local fetchStub = stub( http, "Fetch" ).with( function( _, _, errorCb )
                    expect( errorCb ).to.equal( error )
                end )

                express:GetSize( "test-id", stub() )

                expect( fetchStub ).to.haveBeenCalled()
            end
        },
        {
            name = "express.GetSize errors if the requests succeeds with a non 200-level status code",
            func = function()
                local callback = stub()

                local fetchStub = stub( http, "Fetch" ).with( function( _, success )
                    expect( success, "", "", "", 418 ).to.errWith( "Invalid status code: 418" )
                end )

                express:GetSize( "test-id", callback )

                expect( fetchStub ).to.haveBeenCalled()
                expect( callback ).notTo.haveBeenCalled()
            end
        },
        {
            name = "express.GetSize errors if it cannot read the retrieved data to JSON",
            func = function()
                stub( util, "JSONToTable" ).returns( nil )

                local callback = stub()

                local fetchStub = stub( http, "Fetch" ).with( function( _, success )
                    expect( success, "", "", "", 200 ).to.errWith( "Invalid JSON" )
                end )

                express:GetSize( "test-id", callback )

                expect( fetchStub ).to.haveBeenCalled()
                expect( callback ).notTo.haveBeenCalled()
            end
        },
        {
            name = "express.GetSize errors if it cannot read the size from the retrieved JSON",
            func = function()
                stub( util, "JSONToTable" ).returns( { notTheSizeLol = 123 } )

                local callback = stub()

                local fetchStub = stub( http, "Fetch" ).with( function( _, success )
                    expect( success, "", "", "", 200 ).to.errWith( "No size data" )
                end )

                express:GetSize( "test-id", callback )

                expect( fetchStub ).to.haveBeenCalled()
                expect( callback ).notTo.haveBeenCalled()
            end
        },
        {
            name = "express.GetSize calls the given callback on successful response",
            func = function()
                stub( util, "JSONToTable" ).returns( { size = 123 } )

                local callback = stub()

                local fetchStub = stub( http, "Fetch" ).with( function( _, success )
                    success( "", "", "", 200 )
                end )

                express:GetSize( "test-id", callback )

                expect( fetchStub ).to.haveBeenCalled()
                expect( callback ).to.haveBeenCalled()
            end
        },

        -- express.Put
        {
            name = "express.Put errors if the request fails",
            func = function()
                local httpStub = stub( _G, "HTTP" ).with( function( reqData )
                    expect( reqData.failed ).to.equal( error )
                end )

                express:Put( "test-data", stub() )

                expect( httpStub ).to.haveBeenCalled()
            end
        },
        {
            name = "express.Put errors if the requests succeeds with a non 200-level status code",
            func = function()
                local callback = stub()

                local httpStub = stub( _G, "HTTP" ).with( function( reqData )
                    expect( reqData.success, 418, "" ).to.errWith( "Invalid response code: 418" )
                end )

                express:Put( "test-data", callback )

                expect( httpStub ).to.haveBeenCalled()
                expect( callback ).notTo.haveBeenCalled()
            end
        },
        {
            name = "express.Put errors if it cannot read the retrieved data to JSON",
            func = function()
                stub( util, "JSONToTable" ).returns( nil )

                local callback = stub()

                local httpStub = stub( _G, "HTTP" ).with( function( reqData )
                    expect( reqData.success, 200, "" ).to.errWith( "Invalid JSON" )
                end )

                express:Put( "test-data", callback )

                expect( httpStub ).to.haveBeenCalled()
                expect( callback ).notTo.haveBeenCalled()
            end
        },
        {
            name = "express.Put errors if it cannot read the ID from the retrieved JSON",
            func = function()
                stub( util, "JSONToTable" ).returns( { notTheIdLol = "test-id" } )

                local callback = stub()

                local httpStub = stub( _G, "HTTP" ).with( function( reqData )
                    expect( reqData.success, 200, "" ).to.errWith( "No ID returned" )
                end )

                express:Put( "test-data", callback )

                expect( httpStub ).to.haveBeenCalled()
                expect( callback ).notTo.haveBeenCalled()
            end
        },
        {
            name = "express.Put calls the given callback on successful response",
            func = function()
                stub( util, "JSONToTable" ).returns( { id = "test-id" } )

                local callback = stub()

                local httpStub = stub( _G, "HTTP" ).with( function( reqData )
                    reqData.success( 200, "" )
                end )

                express:Put( "test-data", callback )

                expect( httpStub ).to.haveBeenCalled()
                expect( callback ).to.haveBeenCalled()
            end
        },

        -- express.Call
        {
            name = "express.Call runs the stored callback for the given message",
            func = function()
                local callback = stub()
                stub( express, "_getReceiver" ).returns( callback )

                express:Call( "test-message" )
                expect( callback ).to.haveBeenCalled()
            end
        },

        -- express.CallPreDownload
        {
            name = "express.CallPreDownload runs the stored pre-download callback for the given message",
            func = function()
                local callback = stub()
                stub( express, "_getPreDlReceiver" ).returns( callback )

                express:CallPreDownload( "test-message" )
                expect( callback ).to.haveBeenCalled()
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

                local getSizeStub = stub( express, "GetSize" )

                express:OnMessage()

                expect( getSizeStub ).to.haveBeenCalled()
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

                expect( getSizeStub ).notTo.haveBeenCalled()
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
