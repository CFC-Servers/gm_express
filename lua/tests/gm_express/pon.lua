return {
    groupName = "SFS",

    beforeAll = function()
        require( "sfs" )
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
                expect( sfs ).to.exist()
            end
        },

        {
            name = "It encodes a table",
            func = function( state )
                PrintTable(sfs.decode(sfs.encode(state.tbl)))
                expect( sfs.encode, state.tbl ).to.succeed()
            end
        },

        {
            name = "It decodes a SFS string",
            func = function( state )
                local encoded = sfs.encode( state.tbl )
                expect( sfs.decode, encoded ).to.succeed()
            end
        }
    }
}
