-- SFS (Srlion's Fast Serializer)
-- we try to avoid NYI operations in luajit as much as possible
-- unforunately, we can't avoid all of them in luajit 2.0.5 - pairs & table.concat
-- https://github.com/tarantool/tarantool/wiki/LuaJIT-Not-Yet-Implemented
-- we don't use string concating because it's also NYI in luajit 2.0.5
-- we never error so we don't get blacklisted by the jit compiler
-- errors return strings instead of throwing errors

-- this is intentionally made for net messages, so you don't have to use pcall to check if there are any errors
-- you should use this without using util.Compress, as this just adds one byte to each value, you will probably end up with a larger string if you compress it

-- this idea is from messagepack which is really smart
-- small numbers (0 ~ 127) and (-32 ~ -1) are encoded as a single byte
-- tables and arrays are encoded with a prefix byte, which is the number of elements in the table or array, but it can be one byte if it's less than 16
-- strings are encoded with a prefix byte, which is the length of the string, but it can be one byte if it's less than 32

local math = math
local HUGE = math.huge
local floor = math.floor
local internal_type = type
local IsColor = IsColor
local type = function(v)
    if IsColor(v) then
        return "Color"
    end
    return internal_type(v)
end

-- string.char is not jit compiled in luajit 2.0.5
local chars = {}; do
    for i = 0, 255 do
        chars[i] = string.char(i)
    end
end

local MAX_NUMBER = 1.7976931348623e+308
local MIN_NUMBER = -MAX_NUMBER

---
local POSITIVE_INT = 0x00
local POSITIVE_INT_END = 0x7f

local TABLE_FIXED = 0x80
local TABLE_FIXED_END = 0x8f

local ARRAY_FIXED = 0x90
local ARRAY_FIXED_END = 0x9f

local STR_FIXED = 0xa0
local STR_FIXED_END = 0xbf

local NIL = 0xc0
local FALSE = 0xc1
local TRUE = 0xc2

local UINT_8 = 0xc3
local UINT_16 = 0xc4
local UINT_32 = 0xc5
local UINT_52 = 0xc6

local NINT_8 = 0xc7
local NINT_16 = 0xc8
local NINT_32 = 0xc9
local NINT_52 = 0xca

local DOUBLE = 0xcb

local STR_8 = 0xcc
local STR_16 = 0xcd
local STR_32 = 0xce

local ARRAY_8 = 0xcf
local ARRAY_16 = 0xd0
local ARRAY_32 = 0xd1

local TABLE_8 = 0xd2
local TABLE_16 = 0xd3
local TABLE_32 = 0xd4

local VECTOR = 0xd5
local ANGLE = 0xd6

local ENTITY = 0xd7
local PLAYER = 0xd8

local COLOR = 0xd9

-- this was added in version 2.0.0
-- it's used for arrays that start at 0, I'm not sure if lua 5.1 has same behavior as luajit 2.0.5
-- but luajit 2.0.5 supports starting arrays at 0 index, so checking if table is an array or not gets messed up and output is wrong
-- so if you supply local t = {[0] = 0, 1, 2, 3} and do next(t, #t) it will return (nil, nil) instead of (0, 0)
local ARRAY_ZERO_BASED_INDEX = 0xda

local FREE_FOR_CUSTOM = 0xdb
local FREE_FOR_CUSTOM_END = 0xdf

local NEGATIVE_INT = 0xe0
local NEGATIVE_INT_END = 0xff
---

local encoders = {}
local Encoder = {
    encoders = encoders
}
do
    local pairs = pairs
    local next = next
    local ceil = math.ceil
    local log = math.log
    local concat = table.concat
    local write, write_unsigned, write_double

    -- garry's mod related
    local Vector_Unpack, Angle_Unpack
    local Entity_EntIndex, Player_UserID
    if FindMetaTable then
        Vector_Unpack = FindMetaTable("Vector").Unpack
        Angle_Unpack = FindMetaTable("Angle").Unpack

        Entity_EntIndex = FindMetaTable("Entity").EntIndex
        Player_UserID = FindMetaTable("Player").UserID
    end
    --

    local get_encoder = function(buf, t)
        local encoder = encoders[type(t)]
        if encoder == nil then
            write(buf, "Unsupported type: ")
            write(buf, type(t))
            return nil
        end
        return encoder
    end

    local buffer = {
        [0] = 0 -- buffer length
    }

    -- this function is obviously not jit compiled in luajit 2.0.5 but internal functions are
    function Encoder.encode(val, max_cache_size)
        max_cache_size = max_cache_size or 2000
        buffer[0] = 0

        local encoder = get_encoder(buffer, val)
        if encoder == nil then
            return nil, concat(buffer, nil, buffer[0] - 1, buffer[0])
        end

        if encoder(buffer, val, arg) == true then -- if it returns true, it means there was an error
            -- error is never compiled, so we never error to avoid that
            -- concating in luajit 2.0.5 is NYI, we make sure that all encoders' functions get jit compiled
            return nil, concat(buffer, nil, buffer[0] - 1, buffer[0])
        end

        local result = concat(buffer, nil, 1, buffer[0])

        if #buffer > max_cache_size then
            buffer = {
                [0] = 0 -- buffer length
            }
        end

        return result
    end

    function Encoder.encode_array(arr, len, max_cache_size)
        max_cache_size = max_cache_size or 2000
        buffer[0] = 0

        if encoders.array(buffer, arr, len) == true then -- if it returns true, it means there was an error
            -- error is never compiled, so we never error to avoid that
            -- concating in luajit 2.0.5 is NYI, we make sure that all encoders' functions get jit compiled
            return nil, concat(buffer, nil, buffer[0] - 1, buffer[0])
        end

        local result = concat(buffer, nil, 1, buffer[0])

        if #buffer > max_cache_size then
            buffer = {
                [0] = 0 -- buffer length
            }
        end

        return result
    end

    function write(buf, chr)
        local buf_len = buf[0] + 1
        buf[0] = buf_len
        buf[buf_len] = chr
    end
    Encoder.write = write

    encoders["nil"] = function(buf)
        write(buf, chars[NIL])
    end

    function encoders.boolean(buf, bool)
        if bool == true then
            write(buf, chars[TRUE])
        else
            write(buf, chars[FALSE])
        end
    end

    function encoders.array(buf, arr, len, start_index)
        start_index = (start_index == nil or start_index ~= 0 and start_index ~= 1) and 1 or start_index

        if len < 0 then
            write(buf, "Array size cannot be negative: ")
            write(buf, len)
            return true
        elseif len > 0xFFFFFFFF then
            write(buf, "Array size too large to encode: ")
            write(buf, len)
            return true
        end

        if len <= 0xF then
            write(buf, chars[ARRAY_FIXED + len])
        else
            write_unsigned(buf, ARRAY_8, len)
        end

        if start_index == 0 then
            write(buf, chars[ARRAY_ZERO_BASED_INDEX])
        end

        for idx = start_index, len do
            local val = arr[idx]
            local encoder = get_encoder(buf, val)
            if encoder == nil then return true end
            encoder(buf, val)
        end
    end

    -- we can't check if a table is an array or not because lua tables are not arrays, they are tables
    -- use Encoder.encode_array if you want to encode an array
    function encoders.table(buf, tbl)
        -- check if it's an array, it's not accurate for arrays with holes but better than nothing
        do
            -- this is the fastest possible way, a lot better than cbor's/messagepack's/pon's way of checking if it's an array
            local tbl_len = #tbl
            if tbl_len > 0 and next(tbl, tbl_len) == nil then
                if tbl[0] ~= nil then
                    return encoders.array(buf, tbl, tbl_len, 0)
                else
                    return encoders.array(buf, tbl, tbl_len)
                end
            end
        end

        local buf_len = buf[0]
        local table_start = buf_len -- we store the start of the table so when we write the table size, we can change the current buffer index to the start of the table
        -- we have no way to get the table size without iterating through it, so we just add 5 empty strings to the buffer as a placeholder
        -- we add 5 empty strings because we don't know if table size is going to be a fixed number, uint8, uint16 or uint32
        -- uint32 takes 5 bytes, so we add 5 empty strings
        do
            for idx = 1, 5 do
                buf[buf_len + idx] = ""
            end
            buf_len = buf_len + 5
            buf[0] = buf_len
        end

        local table_count = 0
        for key, val in pairs(tbl) do
            table_count = table_count + 1

            local encoder_key = get_encoder(buf, key)
            if encoder_key == nil then return true end
            encoder_key(buf, key)

            local encoder_val = get_encoder(buf, val)
            if encoder_val == nil then return true end
            encoder_val(buf, val)
        end

        local table_end = buf[0] -- we store the end of the table because we need to change current buffer index to the start of the table to write the table size
        buf[0] = table_start -- change current buffer index to the start of the table

        -- write the table size
        if table_count <= 0xF then
            write(buf, chars[TABLE_FIXED + table_count])
        else
            if table_count > 0xFFFFFFFF then
                write(buf, "Table size too large to encode: ")
                write(buf, table_count)
                return true
            end
            write_unsigned(buf, TABLE_8, table_count)
        end

        buf[0] = table_end -- change current buffer index back to the end of the table
    end

    function encoders.string(buf, str)
        local str_len = #str
        if str_len > 0xFFFFFFFF then
            write(buf, "String too large to encode: ")
            write(buf, str_len)
            return true
        end

        if str_len <= 0x1F then
            write(buf, chars[STR_FIXED + str_len])
        else
            write_unsigned(buf, STR_8, str_len)
        end
        write(buf, str)
    end

    function encoders.number(buf, num)
        if (num > MAX_NUMBER and num ~= HUGE) or (num < MIN_NUMBER and num ~= -HUGE) then
            write(buf, "Number too large to encode: ")
            write(buf, num)
            return true
        end

        if num % 1 ~= 0 or num > 0xFFFFFFFFFFFFF or num < -0xFFFFFFFFFFFFF then -- DOUBLE
            write_double(buf, DOUBLE, num)
            return
        end

        if num < 0 then
            num = -num
            if num <= 0x1F then
                write(buf, chars[NEGATIVE_INT + num])
            else
                write_unsigned(buf, NINT_8, num)
            end
        else
            if num <= 0x7F then
                write(buf, chars[POSITIVE_INT + num])
            else
                write_unsigned(buf, UINT_8, num)
            end
        end
    end

    function encoders.Vector(buf, vec)
        write(buf, chars[VECTOR])
        local x, y, z = Vector_Unpack(vec)
        encoders.number(buf, x)
        encoders.number(buf, y)
        encoders.number(buf, z)
    end

    function encoders.Angle(buf, ang)
        write(buf, chars[ANGLE])
        local p, y, r = Angle_Unpack(ang)
        encoders.number(buf, p)
        encoders.number(buf, y)
        encoders.number(buf, r)
    end

    function encoders.Entity(buf, ent)
        write(buf, chars[ENTITY])
        encoders.number(buf, Entity_EntIndex(ent))
    end

    function encoders.Player(buf, ply)
        write(buf, chars[PLAYER])
        encoders.number(buf, Player_UserID(ply))
    end

    function encoders.Color(buf, col)
        write(buf, chars[COLOR])
        encoders.number(buf, col.r)
        encoders.number(buf, col.g)
        encoders.number(buf, col.b)
        encoders.number(buf, col.a)
    end

    function write_unsigned(buf, tag, num)
        if num <= 0xFF then -- uint8
            write(buf, chars[tag + 0x00])
            write(buf, chars[num])
        elseif num <= 0xFFFF then -- uint16
            write(buf, chars[tag + 0x01])
            write(buf, chars[floor(num / 256)])
            write(buf, chars[num % 256])
        elseif num <= 0xFFFFFFFF then -- uint32
            write(buf, chars[tag + 0x02])
            write(buf, chars[floor(num / 0x1000000) % 256])
            write(buf, chars[floor(num / 0x10000) % 256])
            write(buf, chars[floor(num / 256) % 256])
            write(buf, chars[num % 256])
        elseif num <= 0xFFFFFFFFFFFFF then -- uint52
            write(buf, chars[tag + 0x3])
            write(buf, chars[num % 256])
            write(buf, chars[floor(num / 256) % 256])
            write(buf, chars[floor(num / 0x10000) % 256])
            write(buf, chars[floor(num / 0x1000000) % 256])
            write(buf, chars[floor(num / 0x100000000) % 256])
            write(buf, chars[floor(num / 0x10000000000) % 256])
            write(buf, chars[floor(num / 0x1000000000000) % 256])
        end
    end
    Encoder.write_unsigned = write_unsigned

    -- i can't remember where i got this from, but it's not mine (i swear i always credit people)
    local log2 = log(2)
    function write_double(buf, tag, value)
        local abs_value = value < 0 and -value or value
        --IEEE double-precision floating point number
        --Specification: https://en.wikipedia.org/wiki/Double-precision_floating-point_format
        --Separate out the sign, exponent and fraction
        local sign = value < 0 and 1 or 0
        local exponent = ceil(log(abs_value) / log2) - 1
        local fraction = abs_value / (2 ^ exponent) - 1
        --Make sure the exponent stays in range - allowed values are -1023 through 1024
        if exponent < -1023 then
            --We allow this case for subnormal numbers and just clamp the exponent and re-calculate the fraction
            --without the offset of 1
            exponent = -1023
            fraction = abs_value / (2 ^ exponent)
        elseif abs_value ~= HUGE and exponent > 1024 then
            write(buf, "Exponent out of range: ")
            write(buf, value)
            return true
        end

        --Handle special cases
        if value == 0 then
            --Zero
            exponent = -1023
            fraction = 0
        elseif abs_value == HUGE then
            --Infinity
            exponent = 1024
            fraction = 0
        elseif value ~= value then
            --NaN
            exponent = 1024
            fraction = 1
        end

        local exp_out = exponent + 1023
        local fraction_out = fraction * 0x10000000000000

        write(buf, chars[tag])
        write(buf, chars[128 * sign + floor(exp_out / 16)])
        write(buf, chars[(exp_out % 16) * 16 + floor(fraction_out / 0x1000000000000)])
        write(buf, chars[floor(fraction_out / 0x10000000000) % 256])
        write(buf, chars[floor(fraction_out / 0x100000000) % 256])
        write(buf, chars[floor(fraction_out / 0x1000000) % 256])
        write(buf, chars[floor(fraction_out / 0x10000) % 256])
        write(buf, chars[floor(fraction_out / 0x100) % 256])
        write(buf, chars[floor(fraction_out % 256)])
    end
    Encoder.write_double = write_double
end

local decoders = {}
local Decoder = {
    decoders = decoders
}
do
    local sub = string.sub

    local read_type, read_byte, read_word, read_dword
    local decode_array, decode_table, decode_string, decode_double

    -- garry's mod related
    local Vector, Angle, Entity, Player, Color = Vector, Angle, Entity, Player, Color
    --

    local str_byte = string.byte
    local byte = function(ctx, size)
        local index = ctx[1]
        if index + size - 1 > ctx[3] then -- buffer length
            return nil, "Attemped to read beyond buffer size"
        elseif index + size - 1 > ctx[4] then -- max size
            return nil, "Max decode size exceeded"
        end
        ctx[1] = index + size
        return str_byte(ctx[2], index, index + size - 1)
    end
    Decoder.byte = byte

    local get_decoder = function(ctx)
        local t = read_type(ctx)
        local decoder = decoders[t]
        if decoder == nil then
            return nil, "Unsupported type: ", t
        end
        return decoder
    end
    Decoder.get_decoder = get_decoder

    local context = {
        1,  -- index
        "", -- buffer
        0,  -- buffer length
        HUGE, -- max size for decode, useful when decoding from user input that was sent over netmessages
    }

    local decode = function()
        if context[3] < 1 then -- this will make string.byte fail
            return nil, "Buffer is empty"
        end

        local err, err_2
        local decoder
        local val

        decoder, err, err_2 = get_decoder(context)
        if err ~= nil then
            return nil, err, err_2
        end

        val, err, err_2 = decoder(context)
        if err ~= nil then
            return nil, err, err_2
        end

        return val
    end

    function Decoder.decode(str)
        context[1] = 1
        context[2] = str
        context[3] = #str
        context[4] = HUGE

        return decode()
    end

    function Decoder.decode_with_max_size(str, max_size)
        if type(max_size) ~= "number" then
            return nil, "max_size is not a number", max_size
        end

        if max_size < 0 then
            return nil, "max_size can either be a positive number or math.huge for unlimited", max_size
        end

        context[1] = 1
        context[2] = str
        context[3] = #str
        context[4] = max_size

        return decode()
    end

    decoders[NIL] = function(ctx)
        ctx[1] = ctx[1] + 1
        return nil
    end

    decoders[FALSE] = function(ctx)
        ctx[1] = ctx[1] + 1
        return false
    end

    decoders[TRUE] = function(ctx)
        ctx[1] = ctx[1] + 1
        return true
    end

    --
    decoders[ARRAY_FIXED] = function(ctx)
        local bty, err = read_byte(ctx)
        if bty == nil then
            return nil, err
        end
        local len = bty - ARRAY_FIXED
        return decode_array(ctx, len)
    end

    for i = ARRAY_FIXED + 1, ARRAY_FIXED_END do
        decoders[i] = decoders[ARRAY_FIXED]
    end
    --

    decoders[ARRAY_8] = function(ctx)
        ctx[1] = ctx[1] + 1
        local len, err = read_byte(ctx)
        if len == nil then
            return nil, err
        end
        return decode_array(ctx, len)
    end

    decoders[ARRAY_16] = function(ctx)
        ctx[1] = ctx[1] + 1
        local len, err = read_word(ctx)
        if err ~= nil then
            return nil, err
        end
        return decode_array(ctx, len)
    end

    decoders[ARRAY_32] = function(ctx)
        ctx[1] = ctx[1] + 1
        local len, err = read_dword(ctx)
        if err ~= nil then
            return nil, err
        end
        return decode_array(ctx, len)
    end

    --
    decoders[TABLE_FIXED] = function(ctx)
        local bty, err = read_byte(ctx)
        if bty == nil then
            return nil, err
        end
        local len = bty - TABLE_FIXED
        return decode_table(ctx, len)
    end

    for i = TABLE_FIXED + 1, TABLE_FIXED_END do
        decoders[i] = decoders[TABLE_FIXED]
    end
    --

    decoders[TABLE_8] = function(ctx)
        ctx[1] = ctx[1] + 1
        local len, err = read_byte(ctx)
        if err ~= nil then
            return nil, err
        end
        return decode_table(ctx, len)
    end

    decoders[TABLE_16] = function(ctx)
        ctx[1] = ctx[1] + 1
        local len, err = read_word(ctx)
        if err ~= nil then
            return nil, err
        end
        return decode_table(ctx, len)
    end

    decoders[TABLE_32] = function(ctx)
        ctx[1] = ctx[1] + 1
        local len, err = read_dword(ctx)
        if err ~= nil then
            return nil, err
        end
        return decode_table(ctx, len)
    end

    --
    decoders[STR_FIXED] = function(ctx)
        local bty, err = read_byte(ctx)
        if err ~= nil then
            return nil, err
        end
        local len = bty - STR_FIXED
        return decode_string(ctx, len)
    end

    for i = STR_FIXED + 1, STR_FIXED_END do
        decoders[i] = decoders[STR_FIXED]
    end
    --

    decoders[STR_8] = function(ctx)
        ctx[1] = ctx[1] + 1
        local len, err = read_byte(ctx)
        if err ~= nil then
            return nil, err
        end
        return decode_string(ctx, len)
    end

    decoders[STR_16] = function(ctx)
        ctx[1] = ctx[1] + 1
        local len, err = read_word(ctx)
        if err ~= nil then
            return nil, err
        end
        return decode_string(ctx, len)
    end

    decoders[STR_32] = function(ctx)
        ctx[1] = ctx[1] + 1
        local len, err = read_dword(ctx)
        if err ~= nil then
            return nil, err
        end
        return decode_string(ctx, len)
    end

    --
    decoders[POSITIVE_INT] = function(ctx)
        local bty, err = read_byte(ctx)
        if err ~= nil then
            return nil, err
        end
        return bty - POSITIVE_INT
    end

    for i = POSITIVE_INT + 1, POSITIVE_INT_END do
        decoders[i] = decoders[POSITIVE_INT]
    end
    --

    decoders[UINT_8] = function(ctx)
        ctx[1] = ctx[1] + 1
        local u8, err = read_byte(ctx)
        if err ~= nil then
            return nil, err
        end
        return u8
    end

    decoders[UINT_16] = function(ctx)
        ctx[1] = ctx[1] + 1
        local u16, err = read_word(ctx)
        if err ~= nil then
            return nil, err
        end
        return u16
    end

    decoders[UINT_32] = function(ctx)
        ctx[1] = ctx[1] + 1
        local u32, err = read_dword(ctx)
        if err ~= nil then
            return nil, err
        end
        return u32
    end

    decoders[UINT_52] = function(ctx)
        ctx[1] = ctx[1] + 1
        local b1, b2, b3, b4, b5, b6, b7 = byte(ctx, 7)
        if b1 == nil then
            return nil, b2
        end
        return b1 + (b2 * 0x100) + (b3 * 0x10000) + (b4 * 0x1000000) + (b5 * 0x100000000) + (b6 * 0x10000000000) + (b7 * 0x1000000000000)
    end

    --
    decoders[NEGATIVE_INT] = function(ctx)
        local bty, err = read_byte(ctx)
        if bty == nil then
            return nil, err
        end
        return NEGATIVE_INT - bty
    end

    for i = NEGATIVE_INT + 1, NEGATIVE_INT_END do
        decoders[i] = decoders[NEGATIVE_INT]
    end
    --

    decoders[NINT_8] = function(ctx)
        ctx[1] = ctx[1] + 1
        local n8, err = read_byte(ctx)
        if n8 == nil then
            return nil, err
        end
        return -n8
    end

    decoders[NINT_16] = function(ctx)
        ctx[1] = ctx[1] + 1
        local n16, err = read_word(ctx)
        if err ~= nil then
            return nil, err
        end
        return -n16
    end

    decoders[NINT_32] = function(ctx)
        ctx[1] = ctx[1] + 1
        local n32, err = read_dword(ctx)
        if err ~= nil then
            return nil, err
        end
        return -n32
    end

    decoders[NINT_52] = function(ctx)
        ctx[1] = ctx[1] + 1
        local b1, b2, b3, b4, b5, b6, b7 = byte(ctx, 7)
        if b1 == nil then
            return nil, b2
        end
        return -(b1 + (b2 * 0x100) + (b3 * 0x10000) + (b4 * 0x1000000) + (b5 * 0x100000000) + (b6 * 0x10000000000) + (b7 * 0x1000000000000))
    end

    decoders[DOUBLE] = function(ctx)
        ctx[1] = ctx[1] + 1
        return decode_double(ctx)
    end

    decoders[VECTOR] = function(ctx)
        ctx[1] = ctx[1] + 1

        local err, err_2
        local decoder
        local x, y, z

        -- x
        decoder, err, err_2 = get_decoder(ctx)
        if err ~= nil then
            return nil, err, err_2
        end

        x, err = decoder(ctx)
        if err ~= nil then
            return nil, err
        end
        --

        -- y
        decoder, err, err_2 = get_decoder(ctx)
        if err ~= nil then
            return nil, err, err_2
        end

        y, err = decoder(ctx)
        if err ~= nil then
            return nil, err
        end
        --

        -- z
        decoder, err, err_2 = get_decoder(ctx)
        if err ~= nil then
            return nil, err, err_2
        end

        z, err = decoder(ctx)
        if err ~= nil then
            return nil, err
        end
        --

        return Vector(x, y, z)
    end

    decoders[ANGLE] = function(ctx)
        ctx[1] = ctx[1] + 1

        local err, err_2
        local decoder
        local p, y, r

        -- p
        decoder, err, err_2 = get_decoder(ctx)
        if err ~= nil then
            return nil, err, err_2
        end

        p, err = decoder(ctx)
        if err ~= nil then
            return nil, err
        end
        --

        -- y
        decoder, err, err_2 = get_decoder(ctx)
        if err ~= nil then
            return nil, err, err_2
        end

        y, err = decoder(ctx)
        if err ~= nil then
            return nil, err
        end
        --

        -- r
        decoder, err, err_2 = get_decoder(ctx)
        if err ~= nil then
            return nil, err, err_2
        end

        r, err = decoder(ctx)
        if err ~= nil then
            return nil, err
        end
        --

        return Angle(p, y, r)
    end

    decoders[ENTITY] = function(ctx)
        ctx[1] = ctx[1] + 1

        local err, err_2
        local decoder
        local ent_index

        decoder, err, err_2 = get_decoder(ctx)
        if err ~= nil then
            return nil, err, err_2
        end

        ent_index, err = decoder(ctx)
        if err ~= nil then
            return nil, err
        end

        return Entity(ent_index)
    end

    decoders[PLAYER] = function(ctx)
        ctx[1] = ctx[1] + 1

        local err, err_2
        local decoder
        local user_id

        decoder, err, err_2 = get_decoder(ctx)
        if err ~= nil then
            return nil, err, err_2
        end

        user_id, err = decoder(ctx)
        if err ~= nil then
            return nil, err
        end

        return Player(user_id)
    end

    decoders[COLOR] = function(ctx)
        ctx[1] = ctx[1] + 1

        local err, err_2
        local decoder
        local r, g, b, a

        -- r
        decoder, err, err_2 = get_decoder(ctx)
        if err ~= nil then
            return nil, err, err_2
        end

        r, err = decoder(ctx)
        if err ~= nil then
            return nil, err
        end
        --

        -- g
        decoder, err, err_2 = get_decoder(ctx)
        if err ~= nil then
            return nil, err, err_2
        end

        g, err = decoder(ctx)
        if err ~= nil then
            return nil, err
        end
        --

        -- b
        decoder, err, err_2 = get_decoder(ctx)
        if err ~= nil then
            return nil, err, err_2
        end

        b, err = decoder(ctx)
        if err ~= nil then
            return nil, err
        end
        --

        -- a
        decoder, err, err_2 = get_decoder(ctx)
        if err ~= nil then
            return nil, err, err_2
        end

        a, err = decoder(ctx)
        if err ~= nil then
            return nil, err
        end
        --

        return Color(r, g, b, a)
    end

    function decode_array(ctx, len)
        -- zzzzz no table.new or table.setn, we try to allocate small space to avoid table resizing for small tables
        local arr = {nil, nil, nil, nil, nil, nil, nil, nil}

        local start_index = 1
        if read_type(ctx) == ARRAY_ZERO_BASED_INDEX then
            ctx[1] = ctx[1] + 1
            start_index = 0
        end

        for idx = start_index, len do
            local err, err_2
            local decoder
            local val

            decoder, err, err_2 = get_decoder(ctx)
            if err ~= nil then
                return nil, err, err_2
            end

            val, err = decoder(ctx)
            if err ~= nil then
                return nil, err
            end

            arr[idx] = val
        end

        return arr
    end
    Decoder.decode_array = decode_array

    function decode_table(ctx, len)
        local err, err_2
        local decoder
        local key, val

        -- zzzzz no table.new or table.setn, we try to allocate small space to avoid table resizing for small tables
        local tbl = {nil, nil, nil, nil, nil, nil, nil, nil}
        for _ = 1, len do
            -- key
            decoder, err, err_2 = get_decoder(ctx)
            if err ~= nil then
                return nil, err, err_2
            end

            key, err = decoder(ctx)
            if err ~= nil then
                return nil, err
            end
            --

            -- val
            decoder, err, err_2 = get_decoder(ctx)
            if err ~= nil then
                return nil, err, err_2
            end

            val, err = decoder(ctx)
            if err ~= nil then
                return nil, err
            end
            --

            tbl[key] = val
        end

        return tbl
    end
    Decoder.decode_table = decode_table

    function decode_string(ctx, len)
        local index = ctx[1]
        if index + len - 1 > ctx[3] then
            return nil, "Attemped to read beyond buffer size"
        elseif index + len - 1 > ctx[4] then
            return nil, "Max decode size exceeded"
        end

        ctx[1] = index + len

        return sub(ctx[2], index, index + len - 1)
    end
    Decoder.decode_string = decode_string

    function decode_double(ctx)
        local b1, b2, b3, b4, b5, b6, b7, b8 = byte(ctx, 8)
        if b1 == nil then
            return nil, b2
        end

        --Separate out the values
        local sign = b1 >= 128 and 1 or 0
        local exponent = (b1 % 128) * 16 + floor(b2 / 16)
        local fraction = (b2 % 16) * 0x1000000000000 + b3 * 0x10000000000 + b4 * 0x100000000 + b5 * 0x1000000 + b6 * 0x10000 + b7 * 0x100 + b8
        --Handle special cases
        if exponent == 2047 then
            --Infinities
            if fraction == 0 then return ((sign == 0 and 1) or -1) * HUGE end
            --NaN
            if fraction == 0xfffffffffffff then return 0 / 0 end
        end

        --Combine the values and return the result
        if exponent == 0 then
            --Handle subnormal numbers
            return ((sign == 0 and 1) or -1) * (2 ^ (exponent - 1023)) * (fraction / 0x10000000000000)
        else
            --Handle normal numbers
            return ((sign == 0 and 1) or -1) * (2 ^ (exponent - 1023)) * ((fraction / 0x10000000000000) + 1)
        end
    end
    Decoder.decode_double = decode_double

    function read_type(ctx)
        local typ = str_byte(ctx[2], ctx[1])
        return typ
    end
    Decoder.read_type = read_type

    function read_byte(ctx)
        local bty, err = byte(ctx, 1)
        if bty == nil then
            return nil, err
        end
        return bty
    end
    Decoder.read_byte = read_byte

    function read_word(ctx)
        local b1, b2 = byte(ctx, 2)
        if b1 == nil then
            return nil, b2
        end
        return b1 * 0x100 + b2
    end
    Decoder.read_word = read_word

    function read_dword(ctx)
        local b1, b2, b3, b4 = byte(ctx, 4)
        if b1 == nil then
            return nil, b2
        end
        return b1 * 0x1000000 + b2 * 0x10000 + b3 * 0x100 + b4
    end
    Decoder.read_dword = read_dword
end

_G.sfs = {
    Encoder = Encoder, -- to allow usage of internal functions
    Decoder = Decoder, -- to allow usage of internal functions

    encode = Encoder.encode,
    encode_with_buffer = Encoder.encode_with_buffer,
    encode_array = Encoder.encode_array,

    decode = Decoder.decode,
    decode_with_max_size = Decoder.decode_with_max_size,

    set_type_function = function(t_fn) -- this is for me as I have custom type function in sam/scb to allow type function to get jit compiled :c
        type = t_fn
    end,

    add_encoder = function(typ, encoder)
        encoders[typ] = encoder
        if FREE_FOR_CUSTOM == FREE_FOR_CUSTOM_END then
            return nil, "No more free slots for custom encoders"
        end
        FREE_FOR_CUSTOM = FREE_FOR_CUSTOM + 1
        return FREE_FOR_CUSTOM - 1
    end,

    add_decoder = function(typ, decoder)
        decoders[typ] = decoder
    end,

    chars = chars,
    VERSION = "2.0.1"
}