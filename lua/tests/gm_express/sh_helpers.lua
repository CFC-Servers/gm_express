return {
    groupName = "Shared Helpers",

    cases = {
        -- variables
        {
            name = "Should create necessary variables",
            func = function()
                expect( express.version ).to.exist()
                expect( express.version ).to.beA( "number" )

                expect( express.revision ).to.exist()
                expect( express.revision ).to.beA( "number" )

                expect( express._putCache ).to.exist()
                expect( express._putCache ).to.beA( "table" )

                expect( express._waitingForAccess ).to.exist()
                expect( express._waitingForAccess ).to.beA( "table" )
            end
        },

        -- express.shSend
        {
            name = "express.shSend calls SendToServer on CLIENT",

            func = function()
                _G.CLIENT = true
                _G.SERVER = false

                local send = stub( net, "Send" )
                local sendToServer = stub( net, "SendToServer" )

                express.shSend()

                expect( send ).notTo.haveBeenCalled()
                expect( sendToServer ).to.haveBeenCalled()
            end,

            cleanup = function()
                _G.CLIENT = false
                _G.SERVER = true
            end
        },
        {
            name = "express.shSend calls Send on SERVER",

            func = function()
                local send = stub( net, "Send" )
                local sendToServer = stub( net, "SendToServer" )

                express.shSend()

                expect( send ).to.haveBeenCalled()
                expect( sendToServer ).notTo.haveBeenCalled()
            end
        },

        -- express.makeBaseURL
        {
            name = "express.makeBaseURL makes the correct URL",
            func = function( state )
                state.original_protocol = express._protocol
                state.original_domain = express.domain
                state.original_version = express.version

                express._protocol = "https"
                express.domain = {
                    GetString = function() return "example.cfcservers.org" end
                }
                express.version = "1"

                local expected = "https://example.cfcservers.org/v1"
                local actual = express:makeBaseURL()

                expect( actual ).to.equal( expected )
            end,

            cleanup = function( state )
                express._protocol = state.original_protocol
                express.domain = state.original_domain
                express.version = state.original_version
            end
        },

        -- express.makeAccessURL
        {
            name = "express.makeAccessURL makes the correct URL",
            func = function( state )
                state.original_protocol = express._protocol
                state.original_domain = express.domain
                state.original_version = express.version
                state.original_access = express.access

                express._protocol = "https"
                express.domain = {
                    GetString = function() return "example.cfcservers.org" end
                }
                express.version = "1"
                express.access = "access-token"

                local action = "action"
                local param = "param"

                local expected = "https://example.cfcservers.org/v1/action/access-token/param"
                local actual = express:makeAccessURL( action, param )

                expect( actual ).to.equal( expected )
            end,

            cleanup = function( state )
                express._protocol = state.original_protocol
                express.domain = state.original_domain
                express.version = state.original_version
                express.access = state.original_access
            end
        },

        -- express.SetAccess
        {
            name = "express.SetAccess sets the access token to the given value",

            func = function( state )
                state.original_access = state.original_access or express.access

                -- Sanity check
                expect( #express._waitingForAccess ).to.equal( 0 )

                local access = "access-token"
                express:SetAccess( access )

                expect( express.access ).to.equal( access )
            end,

            cleanup = function( state )
                express.access = state.original_access
            end
        },
        {
            name = "express.SetAccess runs pending requests",

            func = function( state )
                state.original_access = state.original_access or express.access

                -- Sanity check
                expect( #express._waitingForAccess ).to.equal( 0 )

                local waitingStub = stub()
                express._waitingForAccess = { waitingStub }

                express:SetAccess( "access-token" )
                expect( waitingStub ).to.haveBeenCalled()
                expect( #express._waitingForAccess ).to.equal( 0 )
            end,

            cleanup = function( state )
                express.access = state.original_access
            end
        },

        -- express.CheckRevision
        {
            name = "express.CheckRevision alerts if the request fails",

            func = function()
                local fetchStub = stub( http, "Fetch" ).with( function( _, _, failure )
                    expect( failure, "unsuccessful" ).to.errWith( "Express: unsuccessful on version check! This is bad!" )
                end )

                express.CheckRevision()
                expect( fetchStub ).to.haveBeenCalled()
            end
        },
        {
            name = "express.CheckRevision alerts if the request succeeds with a non 200-level status code",

            func = function()
                local fetchStub = stub( http, "Fetch" ).with( function( _, success )
                    expect( success, "", "nil", "nil", 418 ).to.errWith(
                        "Express: Invalid response code (418) on version check! This is bad!"
                    )
                end )

                express.CheckRevision()
                expect( fetchStub ).to.haveBeenCalled()
            end
        },
        {
            name = "express.CheckRevision alerts if it cannot parse the response",

            func = function()
                local fetchStub = stub( http, "Fetch" ).with( function( _, success )
                    expect( success, "", "nil", "nil", 200 ).to.errWith(
                        "Express: Invalid JSON response on version check! This is bad!"
                    )
                end )

                express.CheckRevision()
                expect( fetchStub ).to.haveBeenCalled()
            end
        },
        {
            name = "express.CheckRevision alerts if it cannot get a revision from the response",

            func = function()
                local response = util.TableToJSON( { notTheRevisionLol = "0" } )

                local fetchStub = stub( http, "Fetch" ).with( function( _, success )
                    expect( success, response, "nil", "nil", 200 ).to.errWith(
                        "Express: Invalid JSON response on version check! This is bad!"
                    )
                end )

                express.CheckRevision()
                expect( fetchStub ).to.haveBeenCalled()
            end
        },
        {
            name = "express.CheckRevision alerts if the remote revision doesn't match the current addon revision",

            func = function( state )
                state.original_revision = state.original_revision or express.revision

                express.revision = 1
                local response = util.TableToJSON( { revision = 0 } )

                local fetchStub = stub( http, "Fetch" ).with( function( _, success )
                    expect( success, response, "nil", "nil", 200 ).to.errWith(
                        "Express: Revision mismatch! Expected 1, got 0 on version check! This is bad!"
                    )
                end )

                express.CheckRevision()
                expect( fetchStub ).to.haveBeenCalled()
            end,

            cleanup = function( state )
                express.revision = state.original_revision
            end
        },
        {
            name = "express.CheckRevision does nothing if the revisions match",

            func = function( state )
                state.original_revision = state.original_revision or express.revision

                express.revision = 1
                local response = util.TableToJSON( { revision = 1 } )

                local fetchStub = stub( http, "Fetch" ).with( function( _, success )
                    expect( success, response, "nil", "nil", 200 ).to.succeed()
                end )

                express.CheckRevision()
                expect( fetchStub ).to.haveBeenCalled()
            end,

            cleanup = function( state )
                express.revision = state.original_revision
            end
        },

        -- express._get
        {
            name = "express._get calls express.Get if the access token is set",
            func = function( state )
                state.original_access = state.original_access or express.access

                -- Sanity check
                expect( #express._waitingForAccess ).to.equal( 0 )

                express.access = "access-token"
                local getStub = stub( express, "Get" )
                express:_get( "id", "callback" )

                expect( getStub ).to.haveBeenCalled()
                expect( #express._waitingForAccess ).to.equal( 0 )
            end,
            cleanup = function( state )
                express.access = state.original_access
            end
        },
        {
            name = "express._get adds the request to the waiting list if the access token is not set",
            func = function( state )
                state.original_access = state.original_access or express.access

                -- Sanity check
                expect( #express._waitingForAccess ).to.equal( 0 )

                express.access = nil
                local getStub = stub( express, "Get" )
                express:_get( "id", "callback" )

                expect( getStub ).notTo.haveBeenCalled()
                expect( #express._waitingForAccess ).to.equal( 1 )
            end,
            cleanup = function( state )
                express.access = state.original_access
                express._waitingForAccess = {}
            end
        },

        -- express._put
        {
            name = "express._put encodes and compresses the given data",
            func = function()
                -- Sanity check
                expect( table.Count( express._putCache ) ).to.equal( 0 )

                local encode = stub( pon, "encode" )
                local compress = stub( util, "Compress" ).returns( "hello" )
                local putStub = stub( express, "Put" )

                express:_put( "data", "callback" )

                expect( encode ).to.haveBeenCalled()
                expect( compress ).to.haveBeenCalled()
                expect( putStub ).to.haveBeenCalled()
            end
        },
        {
            name = "express._put rejects data that is too large",
            func = function( state )
                state.original_maxDataSize = state.original_maxDataSize or express._maxDataSize
                express._maxDataSize = 0

                -- Sanity check
                expect( table.Count( express._putCache ) ).to.equal( 0 )

                local mockData = "hello"
                local expectedBytes = #mockData
                local putStub = stub( express, "Put" )

                stub( pon, "encode" )
                stub( util, "Compress" ).returns( mockData )

                expect( express._put, express, "data", stub() ).to.errWith(
                    "Express: Data too large (" .. expectedBytes .. " bytes)"
                )

                expect( putStub ).notTo.haveBeenCalled()
            end,

            cleanup = function( state )
                express._maxDataSize = state.original_maxDataSize
            end
        },
        {
            name = "express._put returns the ID from the cache if the data is already cached",
            func = function()
                -- Sanity check
                expect( table.Count( express._putCache ) ).to.equal( 0 )

                local mockData = "hello"
                local mockId = "test-id"
                local mockHash = "test-hash"
                local mockCallback = stub()
                local putStub = stub( express, "Put" )

                express._putCache[mockHash] = mockId

                stub( pon, "encode" )
                stub( util, "Compress" ).returns( mockData )
                stub( util, "SHA1" ).returns( mockHash )

                express:_put( mockData, mockCallback )

                expect( putStub ).notTo.haveBeenCalled()
                expect( mockCallback ).to.haveBeenCalled()
            end,

            cleanup = function()
                express._putCache = {}
            end
        },
        {
            name = "express._put on success, calls given callback and stores response ID in cache",
            func = function()
                -- Sanity check
                expect( table.Count( express._putCache ) ).to.equal( 0 )

                local mockData = "hello"
                local mockId = "test-id"
                local mockHash = "test-hash"
                local mockCallback = stub()
                local putStub = stub( express, "Put" ).with( function( _, _, cb )
                    cb( mockId )
                end )

                stub( pon, "encode" )
                stub( util, "Compress" ).returns( mockData )
                stub( util, "SHA1" ).returns( mockHash )

                express:_put( mockData, mockCallback )

                expect( putStub ).to.haveBeenCalled()
                expect( mockCallback ).to.haveBeenCalled()
                expect( express._putCache[mockHash] ).to.equal( mockId )
            end,

            cleanup = function()
                express._putCache = {}
            end
        },

        -- express._send
        {
            name = "express._send calls _put with a callback that nets message info and does not set expected if no onProof was provided",
            func = function()
                stub( net, "Start" )
                stub( net, "WriteString" )
                stub( net, "WriteBool" )

                local setExpected = stub( express, "SetExpected" )
                local shSend = stub( express, "shSend" )
                local putStub = stub( express, "_put" ).with( function( _, _, cb )
                    cb( "test-id", "test-hash" )
                end )

                express:_send( "test-message", "test-data", {} )

                expect( putStub ).to.haveBeenCalled()
                expect( setExpected ).notTo.haveBeenCalled()
                expect( shSend ).to.haveBeenCalled()
            end
        },
        {
            name = "express._send calls _put with a callback that nets message info and sets expected if onProof was provided",
            func = function()
                stub( net, "Start" )
                stub( net, "WriteString" )
                stub( net, "WriteBool" )

                local setExpected = stub( express, "SetExpected" )
                local shSend = stub( express, "shSend" )
                local putStub = stub( express, "_put" ).with( function( _, _, cb )
                    cb( "test-id", "test-hash" )
                end )

                express:_send( "test-message", "test-data", {}, stub() )

                expect( putStub ).to.haveBeenCalled()
                expect( setExpected ).to.haveBeenCalled()
                expect( shSend ).to.haveBeenCalled()
            end
        },

        -- express._getReceiver
        {
            name = "express._getReceiver returns the valid receiver for the given message",
            func = function( state )
                state.original_receivers = state.original_receivers or express._receivers
                express._receivers = {
                    ["test-message"] = "test-receiver"
                }

                local receiver = express:_getReceiver( "test-message" )

                expect( receiver ).to.equal( "test-receiver" )
            end,
            cleanup = function( state )
                express._receivers = state.original_receivers
            end
        },
        {
            name = "express._getReceiver returns the valid receiver for the given message, regardless of casing",
            func = function( state )
                state.original_receivers = state.original_receivers or express._receivers
                express._receivers = {
                    ["test-message"] = "test-receiver"
                }

                local receiver = express:_getReceiver( "TEST-MESSAGE" )

                expect( receiver ).to.equal( "test-receiver" )
            end,
            cleanup = function( state )
                express._receivers = state.original_receivers
            end
        },
        {
            name = "express._getReceiver returns nil if no receiver exists for the given message",
            func = function( state )
                state.original_receivers = state.original_receivers or express._receivers
                express._receivers = {}

                local receiver = express:_getReceiver( "test-message" )

                expect( receiver ).to.beNil()
            end,
            cleanup = function( state )
                express._receivers = state.original_receivers
            end
        },

        -- express._getPreDlReceiver
        {
            name = "express._getPreDlReceiver returns the valid receiver for the given message",
            func = function( state )
                state.original_preDlReceivers = state.original_preDlReceivers or express._preDlReceivers
                express._preDlReceivers = {
                    ["test-message"] = "test-receiver"
                }

                local receiver = express:_getPreDlReceiver( "test-message" )

                expect( receiver ).to.equal( "test-receiver" )
            end,
            cleanup = function( state )
                express._preDlReceivers = state.original_preDlReceivers
            end
        },
        {
            name = "express._getPreDlReceiver returns the valid receiver for the given message, regardless of casing",
            func = function( state )
                state.original_preDlReceivers = state.original_preDlReceivers or express._preDlReceivers
                express._preDlReceivers = {
                    ["test-message"] = "test-receiver"
                }

                local receiver = express:_getPreDlReceiver( "TEST-MESSAGE" )

                expect( receiver ).to.equal( "test-receiver" )
            end,
            cleanup = function( state )
                express._preDlReceivers = state.original_preDlReceivers
            end
        },
        {
            name = "express._getPreDlReceiver returns nil if no receiver exists for the given message",
            func = function( state )
                state.original_preDlReceivers = state.original_preDlReceivers or express._preDlReceivers
                express._preDlReceivers = {}

                local receiver = express:_getPreDlReceiver( "test-message" )

                expect( receiver ).to.beNil()
            end,
            cleanup = function( state )
                express._preDlReceivers = state.original_preDlReceivers
            end
        },

        -- express_domain callback
        {
            name = "express_domain callback calls express.Register and express.CheckRevision",
            func = function()
                local callbacks = cvars.GetConVarCallbacks( "express_domain" )
                expect( callbacks ).to.exist()
                expect( #callbacks ).to.equal( 1 )

                local firstCallback = callbacks[1]
                local callbackFunc = firstCallback[1]

                expect( callbackFunc ).to.beA( "function" )
                expect( firstCallback[2] ).to.equal( "domain_check" )

                local registerStub = stub( express, "Register" )
                local checkRevisionStub = stub( express, "CheckRevision" )

                callbackFunc()

                expect( registerStub ).to.haveBeenCalled()
                expect( checkRevisionStub ).to.haveBeenCalled()
            end
        }

    }
}