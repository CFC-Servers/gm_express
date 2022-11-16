return {
    groupName = "pON",

    beforeAll = function()
        require( "pon" )
    end,

    beforeEach = function( state )
        state.tbl = {
            1, "a", true, false, nil, {}, { {}, {}, nil },
            Color( 1, 1, 1 ), Angle( 1, 1, 1 ), Vector( 1, 1, 1 ), game.GetWorld()
        }
    end,

    cases = {
        {
            name = "It loads properly",
            func = function()
                expect( pon ).to.exist()
            end
        },

        {
            name = "It encodes a table",
            func = function( state )
                expect( pon.encode, state.tbl ).to.succeed()
            end
        },

        {
            name = "It decodes a pON string",
            func = function( state )
                local encoded = pon.encode( state.tbl )
                expect( pon.decode, encoded ).to.succeed()
            end
        }
    }
}
