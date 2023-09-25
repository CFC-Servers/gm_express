local tonumber = tonumber
local bit_bxor = bit.bxor
local string_byte = string.byte
local string_char = string.char
local string_gsub = string.gsub

local function xorStr( str, b )
    local result = ""

    for i = 1, #str do
        local c = string_byte( str, i )
        result = result .. string_char( bit_bxor( c, b ) )
    end

    return result
end

local function hex_to_binary( hex )
    return string_gsub( hex, "..", function( hexval )
        return stringchar( tonumber( hexval, 16 ) )
    end )
end

do
    local string_rep = string.rep
    local util_SHA256 = util.SHA256

    return function( key, text )
        local block_size = 64

        if #key > block_size then
            key = util_SHA256( key )
        end

        local key_xord_with_0x36 = xorStr( key, 0x36 ) .. string_rep( string_char( 0x36 ), block_size - #key )
        local key_xord_with_0x5c = xorStr( key, 0x5C ) .. string_rep( string_char( 0x5C ), block_size - #key )

        return util_SHA256( key_xord_with_0x5c .. hex_to_binary( util_SHA256( key_xord_with_0x36 .. text ) ) )
    end
end
