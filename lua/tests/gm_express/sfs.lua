return {
    groupName = "SFS",

    beforeAll = function( state )
        state.sfs = require( "sfs" )
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
            func = function( state )
                expect( state.sfs ).to.exist()
            end
        },

        {
            name = "It encodes a table",
            func = function( state )
                expect( state.sfs.encode, state.tbl ).to.succeed()
            end
        },

        {
            name = "It decodes an SFS string",
            func = function( state )
                local encoded = state.sfs.encode( state.tbl )
                expect( state.sfs.decode, encoded ).to.succeed()
            end
        }
    }
}