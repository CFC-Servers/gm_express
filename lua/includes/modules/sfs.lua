--[[
Copyright (c) 2024 Srlion

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]

local next = next
local pairs = pairs
local table_concat = table.concat
local math_floor = math.floor
local math_ldexp = math.ldexp
local math_frexp = math.frexp

-- string.char is not jit compiled in luajit 2.0.5
local chars = {}; do
    for i = 0, 255 do
        chars[i] = string.char(i)
    end
end
--

local internal_type = _G.type
local IsColor = IsColor
local function type(v)
    if IsColor and IsColor(v) then
        return "Color"
    end
    return internal_type(v)
end

local function is_array(tbl)
    local tbl_len = #tbl

    -- eh, if it's empty then it doesn't matter if it's an array or not, still gonna take 1 byte if it's actually empty
    if tbl_len == 0 then
        return false
    end

    -- lua arrays are 1 indexed, but luajit arrays can be 0 indexed
    if tbl[0] ~= nil then
        return false
    end

    -- Check if there are no elements after the last index
    if next(tbl, tbl_len) ~= nil then
        return false
    end

    if tbl_len == 1 then
        -- For tables with length 1, check if the first key is 1
        if next(tbl) ~= 1 then
            return false
        end
    elseif tbl_len > 1 then
        -- For tables with length > 1, check if the key before the last is tbl_len
        if next(tbl, tbl_len - 1) ~= tbl_len then
            return false
        end
    end

    return true
end

local TYPES = {}
local new_type; do
    local type_count = -1
    function new_type(name, n)
        n = n or 1
        if type_count + n > 255 then
            return error("types count cannot be more than 256")
        end

        local start_type = type_count + 1
        type_count = type_count + n

        TYPES[name] = {
            start = start_type,
            max = n - 1
        }

        if n == 1 then
            return start_type
        else
            return start_type, type_count - start_type
        end
    end
end

-- Simple types
    local NIL = new_type("nil")
    local FALSE = new_type("false")
    local TRUE  = new_type("true")

    local FLOAT = new_type("float")
    local DOUBLE = new_type("double")

    -- Garry's Mod types
    local ENTITY = new_type("entity")
    local PLAYER = new_type("player")
    local VECTOR = new_type("vector")
    local ANGLE = new_type("angle")
    local MATRIX = new_type("matrix")
    local COLOR = new_type("color")

    -- reserved for future use to not break backwards compatibility incase we need to add more types
    local _ = new_type("reserved_1")
    local _ = new_type("reserved_2")
    local _ = new_type("reserved_3")
    local _ = new_type("reserved_4")
--

--
local POSITIVE_FIXED_START, POSITIVE_FIXED_MAX = new_type("positive_fixed", 102)
local POSITIVE_U8 = new_type("positive_u8")
local POSITIVE_U16 = new_type("positive_u16")
local POSITIVE_U32 = new_type("positive_u32")
local POSITIVE_U53 = new_type("positive_u53")

local NEGATIVE_FIXED_START, NEGATIVE_FIXED_MAX = new_type("negative_fixed", 55)
local NEGATIVE_U8 = new_type("negative_u8")
local NEGATIVE_U16 = new_type("negative_u16")
local NEGATIVE_U32 = new_type("negative_u32")
local NEGATIVE_U53 = new_type("negative_u53")

local STRING_FIXED_START, STRING_FIXED_MAX = new_type("string_fixed", 56)
local STRING_U8 = new_type("string_u8")
local STRING_U16 = new_type("string_u16")
local STRING_U32 = new_type("string_u32")

local ARRAY = new_type("array")

local TABLE = new_type("table")

local ENDING = new_type("ending") -- type used to end arrays and tables, can be used for custom types as well
--

-- For user defined types
local CUSTOM_START, CUSTOM_MAX = new_type("custom", 14)
--

local encoders = {}
local Encoder = {
    encoders = encoders,
    ENDING = ENDING
}
do
    local function write_str(buf, str)
        local buf_len = buf[0] + 1
        buf[0] = buf_len
        buf[buf_len] = str
    end
    Encoder.write_str = write_str

    local function get_encoder(buf, t)
        local encoder = encoders[type(t)]
        if encoder == nil then
            write_str(buf, "unsupported type: ")
            write_str(buf, type(t))
            return nil
        end
        return encoder
    end
    Encoder.get_encoder = get_encoder

    local function write_value(buf, val)
        local encoder = get_encoder(buf, val)
        if encoder == nil then
            return true
        end

        if encoder(buf, val) == true then
            return true
        end

        return false
    end
    Encoder.write_value = write_value

    local function write_byte(buf, chr)
        local buf_len = buf[0] + 1
        buf[0] = buf_len
        -- if chars[chr] == nil then
        --     print(true, chr)
        --     error("stop")
        --     return
        -- end
        buf[buf_len] = chars[chr]
    end
    Encoder.write_byte = write_byte

    local function write_u8(buf, num)
        write_byte(buf, num)
    end
    Encoder.write_u8 = write_u8

    local function write_u16(buf, num)
        write_byte(buf, math_floor(num / 0x100))
        write_byte(buf, num % 0x100)
    end
    Encoder.write_u16 = write_u16

    local function write_u32(buf, num)
        write_byte(buf, math_floor(num / 0x1000000) % 0x100)
        write_byte(buf, math_floor(num / 0x10000) % 0x100)
        write_byte(buf, math_floor(num / 0x100) % 0x100)
        write_byte(buf, num % 0x100)
    end
    Encoder.write_u32 = write_u32

    local function write_u53(buf, num)
        write_byte(buf, math_floor(num / 0x1000000000000) % 0x100)
        write_byte(buf, math_floor(num / 0x10000000000) % 0x100)
        write_byte(buf, math_floor(num / 0x100000000) % 0x100)
        write_byte(buf, math_floor(num / 0x1000000) % 0x100)
        write_byte(buf, math_floor(num / 0x10000) % 0x100)
        write_byte(buf, math_floor(num / 0x100) % 0x100)
        write_byte(buf, num % 0x100)
    end
    Encoder.write_u53 = write_u53

    local function write_varint(buf, tag, num)
        if num <= 255 then -- 0 - 255 (8 bits)
            write_byte(buf, tag)
            write_u8(buf, num)
        elseif num <= 65535 then -- 0 - 65535 (16 bits)
            write_byte(buf, tag + 1)
            write_u16(buf, num)
        elseif num <= 4294967295 then -- 0 - 4294967295 (32 bits)
            write_byte(buf, tag + 2)
            write_u32(buf, num)
        else -- 0 - 9007199254740992 (53 bits)
            write_byte(buf, tag + 3)
            write_u53(buf, num)
        end
    end
    Encoder.write_varint = write_varint

    -- write float expects a float not a double (you need to pass values that are actually floats)
    -- this is here for gmod types that are floats (eg. Vector, Angle)
    local function write_float(buf, num)
        local u32 = 0

        if num == 0 then
            u32 = 0x00000000 -- Positive zero
            if 1 / num < 0 then
                u32 = 0x80000000 -- Negative zero
            end
            write_u32(buf, u32)
            return u32
        elseif num ~= num then  -- NaN check
            u32 = 0x7FFFFFFF
            write_u32(buf, u32)
            return u32
        end

        local sign = num < 0 and 1 or 0
        num = sign == 1 and -num or num

        if num == 1 / 0 then -- math.huge
            -- (sign << 31) + (0xFF << 23)
            u32 = (sign * (2^31)) + (0xFF * (2^23))
            write_u32(buf, u32)
            return u32
        end

        local mantissa, exponent = math_frexp(num)
        mantissa = mantissa * 2
        exponent = exponent - 1

        local ieee_exponent = exponent + 127  -- IEEE 754 bias
        if ieee_exponent <= 0 then
            -- Handle subnormal numbers
            mantissa = math_ldexp(mantissa, ieee_exponent - 1)
            ieee_exponent = 0
        elseif ieee_exponent >= 255 then
            -- Handle overflow
            ieee_exponent = 255
            mantissa = 0
        end

        -- Scale mantissa to 23 bits and round
        local mantissa_bits = math_floor(
            ((mantissa - 1) * (2^23)) + 0.5
        )

        -- Ensure mantissa doesn't exceed 23 bits
        mantissa_bits = mantissa_bits % (2^23)

        -- Combine all parts
        -- (sign << 31) | (ieee_exponent << 23) | mantissa_bits
        u32 = (sign * (2^31)) + (ieee_exponent * (2^23)) + mantissa_bits

        write_u32(buf, u32)
        return u32
    end
    Encoder.write_float = write_float

    local function write_double(buf, num)
        local u32_1 = 0
        local u32_2 = 0

        if num == 0 then
            u32_1 = 0x00000000
            if 1 / num < 0 then
                u32_1 = 0x80000000
            end
            write_u32(buf, u32_1)
            write_u32(buf, u32_2)
            return
        elseif num ~= num then -- NaN check
            u32_1 = 0x7FFFFFFF
            u32_2 = 1
            write_u32(buf, u32_1)
            write_u32(buf, u32_2)
            return
        end

        local sign = num < 0 and 1 or 0
        num = sign == 1 and -num or num

        if num == 1 / 0 then -- Infinity
            -- (sign << 31) | (0x7FF << 20)
            u32_1 = (sign * (2^31)) + (0x7FF * (2^20))
            write_u32(buf, u32_1)
            write_u32(buf, u32_2)
            return
        end

        local mantissa, exponent = math_frexp(num)

        local ieee_exponent = exponent + 1022
        if ieee_exponent > 0 then
            -- Normal numbers
            local mantissa_scaled = (mantissa * 2 - 1) * (2^52)
            local mantissa_upper = math_floor(mantissa_scaled / (2^32)) -- (mantissa_scaled >> 32)
            local mantissa_lower = mantissa_scaled % (2^32) -- (mantissa_scaled & 0xFFFFFFFF)

            -- (sign << 31) | (ieee_exponent << 20) | (mantissa_upper % 2^20)
            u32_1 = (sign * (2^31)) + (ieee_exponent * (2^20)) + (mantissa_upper % (2^20))
            u32_2 = mantissa_lower
        else
            -- Subnormal numbers
            local mantissa_scaled = mantissa * math_ldexp(1, 52 + ieee_exponent)
            local mantissa_upper = math_floor(mantissa_scaled / (2^32)) -- (mantissa_scaled >> 32)
            local mantissa_lower = mantissa_scaled % (2^32) -- (mantissa_scaled & 0xFFFFFFFF)

            -- (sign << 31) | (mantissa_upper & 0xFFFFF)
            u32_1 = (sign * (2^31)) + (mantissa_upper % (2^20))
            u32_2 = mantissa_lower
        end

        write_u32(buf, u32_1)
        write_u32(buf, u32_2)
    end
    Encoder.write_double = write_double

    local function write_array(buf, arr, size)
        for i = 1, size do
            if write_value(buf, arr[i]) then
                return true
            end
        end
    end
    Encoder.write_array = write_array

    local function write_table(buf, tbl)
        for key, val in pairs(tbl) do
            if write_value(buf, key) or write_value(buf, val) then
                return true
            end
        end
    end
    Encoder.write_table = write_table

    function Encoder.read_error(buf)
        return table_concat(buf, nil, buf[0] - 1, buf[0])
    end

    do
        local buffer = {
            [0] = 0 -- length
        }

        function Encoder.encode(val, max_cache_size)
            max_cache_size = max_cache_size or 2000
            buffer[0] = 0

            -- returns true when failed to encode
            -- error is never compiled, so we never error to avoid that
            -- concatenating in luajit 2.0.5 is NYI, we make sure that all encoders' functions get jit compiled
            if write_value(buffer, val) then
                return nil, Encoder.read_error(buffer)
            end

            local result = table_concat(buffer, nil, 1, buffer[0])

            if #buffer > max_cache_size then
                buffer = {
                    [0] = 0 -- buffer length
                }
            end

            return result
        end
    end

    encoders["nil"] = function(buf, v)
        write_byte(buf, NIL)
    end

    encoders.boolean = function(buf, v)
        if v == false then
            write_byte(buf, FALSE)
        else
            write_byte(buf, TRUE)
        end
    end

    encoders.float = function(buf, num)
        write_byte(buf, FLOAT)
        write_float(buf, num)
    end

    encoders.double = function(buf, num)
        write_byte(buf, DOUBLE)
        write_double(buf, num)
    end

    encoders.string = function(buf, str)
        local str_len = #str

        if str_len <= STRING_FIXED_MAX then
            write_byte(buf, STRING_FIXED_START + str_len)
        else
            write_varint(buf, STRING_U8, str_len)
        end

        if str_len > 0 then
            write_str(buf, str)
        end
    end

    encoders.array = function(buf, arr, size)
        if size then
            if size < 0 then
                write_str(buf, "array size cannot be negative: ")
                write_str(buf, size)
                return true
            end
        else
            size = #arr
        end
        write_byte(buf, ARRAY)
        write_array(buf, arr, size)
        write_byte(buf, ENDING)
    end

    encoders.table = function(buf, tbl)
        if is_array(tbl) then
            return encoders.array(buf, tbl)
        end
        write_byte(buf, TABLE)
        write_table(buf, tbl)
        write_byte(buf, ENDING)
    end

    encoders.number = function(buf, num)
        -- a number like 1.7976931348623e308 will fail with % 1 ~= 0, but if you subtract 1 from it, it will still equal itself
        if num % 1 ~= 0 or num - 1 == num then -- DOUBLE
            write_byte(buf, DOUBLE)
            write_double(buf, num)
            return
        end

        -- check if it's a positive number (this is weird but to check for -0)
        if 1 / num > 0 then
            if num <= POSITIVE_FIXED_MAX then
                write_byte(buf, POSITIVE_FIXED_START + num)
            else
                write_varint(buf, POSITIVE_U8, num)
            end
        else
            num = -num
            if num <= NEGATIVE_FIXED_MAX then
                write_byte(buf, NEGATIVE_FIXED_START + num)
            else
                write_varint(buf, NEGATIVE_U8, num)
            end
        end
    end

    -- Garry's Mod types
    local Entity_EntIndex = FindMetaTable and FindMetaTable("Entity").EntIndex
    encoders.Entity = function(buf, ent)
        write_byte(buf, ENTITY)
        write_u16(buf, Entity_EntIndex(ent))
    end

    -- All of these are reported as their own type but are otherwise identical in handling to entities
    encoders.Weapon = encoders.Entity
    encoders.Vehicle = encoders.Entity
    encoders.NextBot = encoders.Entity
    encoders.NPC = encoders.Entity

    -- range between 1 and 128 for players, so we can safely use uint8
    encoders.Player = function(buf, ply)
        write_byte(buf, PLAYER)
        write_u8(buf, Entity_EntIndex(ply))
    end

    local Vector_Unpack = FindMetaTable and FindMetaTable("Vector").Unpack
    encoders.Vector = function(buf, vec)
        write_byte(buf, VECTOR)

        local x, y, z = Vector_Unpack(vec)
        write_float(buf, x)
        write_float(buf, y)
        write_float(buf, z)
    end

    local Angle_Unpack = FindMetaTable and FindMetaTable("Angle").Unpack
    encoders.Angle = function(buf, ang)
        write_byte(buf, ANGLE)

        local p, y, r = Angle_Unpack(ang)
        write_float(buf, p)
        write_float(buf, y)
        write_float(buf, r)
    end

    -- :]
    local MATRIX_ToTable = FindMetaTable and FindMetaTable("VMatrix").ToTable
    encoders.VMatrix = function(buf, mat)
        write_byte(buf, MATRIX)

        local matrix = MATRIX_ToTable(mat)
        for i = 1, 4 do
            for j = 1, 4 do
                write_float(buf, matrix[i][j])
            end
        end
    end

    encoders.Color = function(buf, col)
        write_byte(buf, COLOR)

        write_u8(buf, math_floor(col.r))
        write_u8(buf, math_floor(col.g))
        write_u8(buf, math_floor(col.b))
        write_u8(buf, math_floor(col.a))
    end
end

local decoders = {}
local Decoder = {
    decoders = decoders
}
do
    local string_byte = string.byte
    local string_sub = string.sub

    -- Context Structure
    local context = {
        1,      -- index
        "",     -- bytes
        0,      -- bytes length
        1 / 0   -- max size for decode (math.huge)
    }

    local function peak_type(ctx)
        local typ = string_byte(ctx[2], ctx[1])
        return typ
    end
    Decoder.peak_type = peak_type

    local function get_decoder(ctx)
        local tpy = peak_type(ctx)
        local decoder = decoders[tpy]
        if decoder == nil then
            return nil, "unsupported type: ", tpy
        end
        return decoder
    end
    Decoder.get_decoder = get_decoder

    local function read_value(ctx)
        local decoder, val, err, err2

        decoder, err, err2 = get_decoder(ctx)
        if err then
            if err2 then
                return nil, err .. err2
            end
            return nil, err
        end

        val, err = decoder(ctx)
        if err then
            return nil, err
        end

        return val
    end
    Decoder.read_value = read_value

    local function read_byte(ctx, size)
        local idx = ctx[1]
        if idx + size - 1 > ctx[3] then -- ctx[3] bytes length
            return nil, "bytes underflow"
        elseif idx + size - 1 > ctx[4] then -- ctx[4] max size
            return nil, "bytes overflow"
        end
        ctx[1] = idx + size
        return string_byte(ctx[2], idx, idx + size - 1)
    end
    Decoder.read_byte = read_byte

    local function read_str(ctx, size)
        local idx = ctx[1]
        if idx + size - 1 > ctx[3] then -- ctx[3] bytes length
            return nil, "bytes underflow"
        elseif idx + size - 1 > ctx[4] then -- ctx[4] max size
            return nil, "bytes overflow"
        end
        ctx[1] = idx + size
        return string_sub(ctx[2], idx, idx + size - 1)
    end
    Decoder.read_str = read_str

    local function read_u8(ctx)
        local byt, err = read_byte(ctx, 1)
        if err then
            return nil, err
        end
        return byt
    end
    Decoder.read_u8 = read_u8

    local function read_u16(ctx)
        local b1, b2 = read_byte(ctx, 2) -- read_byte returns multiple values, but error can be the second value
        if b1 == nil then
            return nil, b2
        end
        return b1 * 0x100 + b2
    end
    Decoder.read_u16 = read_u16

    local function read_u32(ctx)
        local b1, b2, b3, b4 = read_byte(ctx, 4)
        if b1 == nil then
            return nil, b2
        end
        return b1 * 0x1000000 + b2 * 0x10000 + b3 * 0x100 + b4
    end
    Decoder.read_u32 = read_u32

    local function read_u53(ctx)
        local b1, b2, b3, b4, b5, b6, b7 = read_byte(ctx, 7)
        if b1 == nil then
            return nil, b2
        end
        return b1 * 0x1000000000000
            + b2 * 0x10000000000
            + b3 * 0x100000000
            + b4 * 0x1000000
            + b5 * 0x10000
            + b6 * 0x100
            + b7
    end
    Decoder.read_u53 = read_u53

    local function read_float(ctx)
        local u32, err = read_u32(ctx)
        if err then
            return nil, err
        end

        -- ((u32 >> 31) & 1) == 1 and -1 or 1
        local sign = math_floor(u32 / (2^31)) % 2 == 1 and -1 or 1
        -- (u32 >> 23) & 0xFF
        local exponent_field = math_floor(u32 / (2^23)) % (2^8)
        -- u32 & 0x7FFFFF
        local mantissa = u32 % (2^23)

        if exponent_field == 0xFF then
            if mantissa == 0 then
                return sign * (1 / 0)  -- math.huge
            end
            return 0 / 0  -- NaN
        end

        if exponent_field == 0 and mantissa == 0 then
            return sign * 0  -- Zero
        end

        -- mantissa >> 23
        local mantissa_scaled = mantissa / (2^23)

        if exponent_field ~= 0 then
            -- Normal numbers
            mantissa_scaled = mantissa_scaled + 1
            local actual_exponent = exponent_field - 127
            return sign * math_ldexp(mantissa_scaled, actual_exponent)
        else
            -- Subnormal numbers
            return sign * math_ldexp(mantissa_scaled, -126)
        end
    end
    Decoder.read_float = read_float

    local function read_double(ctx)
        local u32_1, u32_2, err

        u32_1, err = read_u32(ctx)
        if err then return nil, err end

        u32_2, err = read_u32(ctx)
        if err then return nil, err end

        -- ((u32_1 >> 31) & 1) == 1 and -1 or 1
        local sign = math_floor(u32_1 / (2^31)) % 2 == 1 and -1 or 1
        -- (u32_1 >> 20) & 0x7FF
        local exponent_field = math_floor(u32_1 / (2^20)) % (2^11)
        -- u32_1 & 0xFFFFF
        local mantissa_upper = u32_1 % (2^20)

        if exponent_field == 0x7FF then
            if mantissa_upper == 0 and u32_2 == 0 then
                return sign * (1 / 0)  -- math.huge
            end
            return 0 / 0  -- NaN
        end

        if exponent_field == 0 and mantissa_upper == 0 and u32_2 == 0 then
            return sign * 0  -- Zero
        end

        -- mantissa_upper << 32 + u32_2
        local mantissa_scaled = mantissa_upper * (2^32) + u32_2

        if exponent_field ~= 0 then
            -- Normal numbers
            mantissa_scaled = (mantissa_scaled / (2 ^ 52)) + 1
            local actual_exponent = exponent_field - 1023
            return sign * math_ldexp(mantissa_scaled, actual_exponent)
        else
            -- Subnormal numbers
            mantissa_scaled = mantissa_scaled / (2 ^ 52)
            return sign * math_ldexp(mantissa_scaled, -1022)
        end
    end
    Decoder.read_double = read_double

    local function read_array(ctx, till)
        local arr = {nil, nil, nil, nil, nil, nil, nil, nil, nil, nil} -- initialize with size of 10
        local size = 0
        while peak_type(ctx) ~= till do
            local val, err = read_value(ctx)
            if err then
                return nil, err
            end
            size = size + 1
            arr[size] = val
        end
        ctx[1] = ctx[1] + 1 -- skip the ending type
        return arr, nil, size
    end
    Decoder.read_array = read_array

    local function read_table(ctx, till)
        local tbl = {nil, nil, nil, nil, nil, nil, nil, nil, nil, nil} -- initialize with size of 10
        while peak_type(ctx) ~= till do
            local key, val, err
            key, err = read_value(ctx)
            if err then
                return nil, err
            end
            val, err = read_value(ctx)
            if err then
                return nil, err
            end
            tbl[key] = val
        end
        ctx[1] = ctx[1] + 1 -- skip the ending type
        return tbl
    end
    Decoder.read_table = read_table

    function Decoder.setup_context(bytes, max_size)
        if type(bytes) ~= "string" then
            return nil, "bytes must be a string"
        end

        if max_size == nil then
            max_size = 1 / 0 -- math.huge
        elseif type(max_size) ~= "number" then
            return nil, "max_size must be a number"
        elseif max_size < 1 then
            return nil, "max_size must be greater than 0"
        end

        context[1] = 1
        context[2] = bytes
        context[3] = #bytes
        context[4] = max_size

        if context[3] < 1 then
            return nil, "no bytes to decode"
        end

        return context
    end

    function Decoder.decode(bytes, max_size)
        do
            local _, err = Decoder.setup_context(bytes, max_size)
            if err then
                return nil, err
            end
        end

        local val, err = read_value(context)
        if err then
            return nil, err
        end

        return val
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

    decoders[FLOAT] = function(ctx)
        ctx[1] = ctx[1] + 1
        return read_float(ctx)
    end

    decoders[DOUBLE] = function(ctx)
        ctx[1] = ctx[1] + 1
        return read_double(ctx)
    end

    -- Garry's Mod types
    local Entity = Entity
    decoders[ENTITY] = function(ctx)
        ctx[1] = ctx[1] + 1
        local ent_idx, err = read_u16(ctx)
        if err then
            return nil, err
        end
        return Entity(ent_idx)
    end

    decoders[PLAYER] = function(ctx)
        ctx[1] = ctx[1] + 1
        local ply_uid, err = read_u8(ctx)
        if err then
            return nil, err
        end
        return Entity(ply_uid)
    end

    local Vector = Vector
    decoders[VECTOR] = function(ctx)
        ctx[1] = ctx[1] + 1

        local x, y, z, err

        x, err = read_float(ctx)
        if err then return nil, err end

        y, err = read_float(ctx)
        if err then return nil, err end

        z, err = read_float(ctx)
        if err then return nil, err end

        return Vector(x, y, z)
    end

    local Angle = Angle
    decoders[ANGLE] = function(ctx)
        ctx[1] = ctx[1] + 1

        local p, y, r, err

        p, err = read_float(ctx)
        if err then return nil, err end

        y, err = read_float(ctx)
        if err then return nil, err end

        r, err = read_float(ctx)
        if err then return nil, err end

        return Angle(p, y, r)
    end

    local Matrix = Matrix
    decoders[MATRIX] = function(ctx)
        ctx[1] = ctx[1] + 1

        local matrix, err = {}, nil
        for i = 1, 4 do
            matrix[i] = {}
            for j = 1, 4 do
                matrix[i][j], err = read_float(ctx)
                if err then
                    return nil, err
                end
            end
        end

        return Matrix(matrix)
    end

    local Color = Color
    decoders[COLOR] = function(ctx)
        ctx[1] = ctx[1] + 1

        local r, g, b, a, err

        r, err = read_u8(ctx)
        if err then return nil, err end

        g, err = read_u8(ctx)
        if err then return nil, err end

        b, err = read_u8(ctx)
        if err then return nil, err end

        a, err = read_u8(ctx)
        if err then return nil, err end

        return Color(r, g, b, a)
    end

    --
    decoders[POSITIVE_U8] = function(ctx)
        ctx[1] = ctx[1] + 1

        local num, err = read_u8(ctx)
        if err then return nil, err end
        return num
    end

    decoders[POSITIVE_U16] = function(ctx)
        ctx[1] = ctx[1] + 1

        local num, err = read_u16(ctx)
        if err then return nil, err end
        return num
    end

    decoders[POSITIVE_U32] = function(ctx)
        ctx[1] = ctx[1] + 1

        local num, err = read_u32(ctx)
        if err then return nil, err end
        return num
    end

    decoders[POSITIVE_U53] = function(ctx)
        ctx[1] = ctx[1] + 1

        local num, err = read_u53(ctx)
        if err then return nil, err end
        return num
    end
    --

    --
    decoders[NEGATIVE_U8] = function(ctx)
        ctx[1] = ctx[1] + 1

        local num, err = read_u8(ctx)
        if err then return nil, err end
        return -num
    end

    decoders[NEGATIVE_U16] = function(ctx)
        ctx[1] = ctx[1] + 1

        local num, err = read_u16(ctx)
        if err then return nil, err end
        return -num
    end

    decoders[NEGATIVE_U32] = function(ctx)
        ctx[1] = ctx[1] + 1

        local num, err = read_u32(ctx)
        if err then return nil, err end
        return -num
    end

    decoders[NEGATIVE_U53] = function(ctx)
        ctx[1] = ctx[1] + 1

        local num, err = read_u53(ctx)
        if err then return nil, err end
        return -num
    end
    --

    --
    decoders[STRING_U8] = function(ctx)
        ctx[1] = ctx[1] + 1

        local str_len, str, err

        str_len, err = read_u8(ctx)
        if err then return nil, err end

        str, err = read_str(ctx, str_len)
        if err then return nil, err end

        return str
    end

    decoders[STRING_U16] = function(ctx)
        ctx[1] = ctx[1] + 1

        local str_len, str, err

        str_len, err = read_u16(ctx)
        if err then return nil, err end

        str, err = read_str(ctx, str_len)
        if err then return nil, err end

        return str
    end

    decoders[STRING_U32] = function(ctx)
        ctx[1] = ctx[1] + 1

        local str_len, str, err

        str_len, err = read_u32(ctx)
        if err then return nil, err end

        str, err = read_str(ctx, str_len)
        if err then return nil, err end

        return str
    end
    --

    --
    decoders[ARRAY] = function(ctx)
        ctx[1] = ctx[1] + 1
        local arr, err = read_array(ctx, ENDING)
        if err then return nil, err end
        return arr
    end

    decoders[TABLE] = function(ctx)
        ctx[1] = ctx[1] + 1
        local tbl, err = read_table(ctx, ENDING)
        if err then return nil, err end
        return tbl
    end

    --
    decoders[STRING_FIXED_START] = function(ctx)
        local byt, str, err

        byt, err = read_byte(ctx, 1)
        if err then return nil, err end

        local str_len = byt - STRING_FIXED_START

        str, err = read_str(ctx, str_len)
        if err then return nil, err end

        return str
    end

    for i = 1, STRING_FIXED_MAX do
        decoders[STRING_FIXED_START + i] = decoders[STRING_FIXED_START]
    end
    --
    --
    decoders[POSITIVE_FIXED_START] = function(ctx)
        local byt, num, err

        byt, err = read_byte(ctx, 1)
        if err then return nil, err end

        num = byt - POSITIVE_FIXED_START
        return num
    end

    for i = 1, POSITIVE_FIXED_MAX do
        decoders[POSITIVE_FIXED_START + i] = decoders[POSITIVE_FIXED_START]
    end
    --

    --
    decoders[NEGATIVE_FIXED_START] = function(ctx)
        local byt, num, err

        byt, err = read_byte(ctx, 1)
        if err then return nil, err end

        num = byt - NEGATIVE_FIXED_START
        return -num
    end

    for i = 1, NEGATIVE_FIXED_MAX do
        decoders[NEGATIVE_FIXED_START + i] = decoders[NEGATIVE_FIXED_START]
    end
    --
end

local function can_encode(val)
    local t = type(val)
    if t == "table" then
        for k, v in pairs(val) do
            if not can_encode(k) or not can_encode(v) then
                return false
            end
        end
        return true
    end
    return encoders[t] ~= nil
end

local encode_to_hex, decode_from_hex; do
    local byte = string.byte
    local char = string.char
    local string_format = string.format
    local string_gsub = string.gsub
    local tonumber = tonumber

    local function hex(c)
        local b = byte(c)
        return (string_format("%02X", b))
    end

    local function string_to_hex(str)
        return (string_gsub(str, ".", hex))
    end

    function encode_to_hex(val)
        local encoded, err = Encoder.encode(val)
        if err then
            return nil, err
        end
        local hexed = string_to_hex(encoded)
        return hexed
    end

    local function from_hex(c)
        return char(tonumber(c, 16))
    end

    local function hex_to_string(str)
        return (string_gsub(str, "..", from_hex))
    end

    function decode_from_hex(str)
        local ok, unhexed = pcall(hex_to_string, str)
        if not ok then
            return nil, unhexed
        end
        local decoded, err = Decoder.decode(unhexed)
        if err then
            return nil, err
        end
        return decoded
    end
end

_G.sfs = {
    TYPES = TYPES,

    Encoder = Encoder, -- to allow usage of internal functions
    Decoder = Decoder, -- to allow usage of internal functions

    encode = Encoder.encode,
    decode = Decoder.decode,

    encode_to_hex = encode_to_hex,
    decode_from_hex = decode_from_hex,

    new_buffer = function()
        return {
            [0] = 0
        }
    end,
    end_buffer = function(buf)
        return table_concat(buf, nil, 1, buf[0])
    end,
    reset_buffer = function(buf)
        buf[0] = 0
    end,

    set_type_function = function(t_fn) -- this is for me as I have custom type function in sam/scb to allow type function to get jit compiled :c
        type = t_fn
    end,

    add_custom_type = function(typ, encoder, decoder)
        if CUSTOM_START == CUSTOM_MAX then
            return error("cannot add more custom types")
        end

        if encoders[typ] or decoders[typ] then
            -- this just prints incase you mistakenly add a type that already exists
            ErrorNoHaltWithStack("type already exists: `" .. typ .. "`")
        end

        encoders[typ] = encoder
        decoders[CUSTOM_START] = decoder

        CUSTOM_START = CUSTOM_START + 1
        return CUSTOM_START - 1
    end,

    set_custom_type_with_id = function(id, typ, encoder, decoder)
        if encoders[typ] or decoders[typ] then
            -- this just prints incase you mistakenly add a type that already exists
            ErrorNoHaltWithStack("type already exists: `" .. typ .. "`")
        end

        encoders[typ] = encoder
        decoders[id] = decoder
    end,

    can_encode = can_encode,

    chars = chars,
    VERSION = "4.0.0"
}

