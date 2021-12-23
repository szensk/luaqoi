-- Pure LuaJIT implementation of quite OK image format (QOI)
-- MIT license

local ffi = require('ffi')
local bit = require('bit')
local band, bor, bxor = bit.band, bit.bor, bit.bxor
local lshift, rshift, rol = bit.lshift, bit.rshift, bit.rol

-- Constants
local QOI_SRGB   = 0
local QOI_LINEAR = 1

local QOI_OP_INDEX = 0x00
local QOI_OP_DIFF  = 0x40
local QOI_OP_LUMA  = 0x80
local QOI_OP_RUN   = 0xC0
local QOI_OP_RGB   = 0xFE
local QOI_OP_RGBA  = 0xFF
local QOI_MASK_2   = 0xC0

local QOI_MAGIC = 0x716F6966 -- ASCII: qoif
local QOI_HEADER_SIZE = 14
local QOI_PIXELS_MAX = 400000000

-- Structures
local qoi_desc = ffi.cdef[[
typedef struct {
    unsigned int  width;
    unsigned int  height;
    unsigned char channels;
    unsigned char colorspace;
} qoi_desc;
]]

local qoi_rgba_t = ffi.cdef[[
typedef union {
    struct { unsigned char r, g, b, a; } rgba;
    int v;
} qoi_rgba_t;
]]

local qoi_padding = ffi.new("unsigned char[8]", {0,0,0,0,0,0,0,1})

-- Utility
local function qoi_desc(t) 
    return ffi.new('qoi_desc', t)
end

local function color_hash(c)
    return c.rgba.r*3 + c.rgba.g*5 + c.rgba.b*7 + c.rgba.a*11
end

local function qoi_write_32(bytes, p, v)
    bytes[p] = rshift(band(0xFF000000, v), 24); p=p+1
    bytes[p] = rshift(band(0x00FF0000, v), 16); p=p+1
    bytes[p] = rshift(band(0x0000FF00, v), 08); p=p+1
    bytes[p] =        band(0x000000FF, v)     ; p=p+1
    return p
end

local function qoi_read_32(bytes, p) 
    local a,b,c,d = bytes[p], bytes[p+1], bytes[p+2], bytes[p+3]
    a = lshift(a, 24)
    b = lshift(b, 16)
    c = lshift(c, 08)
    return bor(d, bor(c, bor(a, b))), p + 4
end

local function qoi_encode(data, desc)
    local i, max_size, p, run = 0, 0, 0, 0 
    local px_len, px_end, px_pos, channels = 0, 0, 0, 0
    local bytes  --unsigned char
    local pixels --const unsigned char
    local index = ffi.new('qoi_rgba_t[?]', 64)
    local px, px_prev = ffi.new('qoi_rgba_t'), ffi.new('qoi_rgba_t')

    if data == nil or desc == nil or
       desc.width == 0 or desc.height == 0 or 
       desc.channels < 3 or desc.channels > 4 or
       desc.colorspace > 1 or desc.height >= QOI_PIXELS_MAX / desc.width
    then 
        return nil, 'Bad header'
    end

    max_size = desc.width * desc.height * (desc.channels + 1) + QOI_HEADER_SIZE + ffi.sizeof(qoi_padding)
    p = 0
    bytes = ffi.new('unsigned char[?]', max_size)
    if bytes == nil 
    then
        return nil, 'Unable to allocate'
    end

    p = qoi_write_32(bytes, p, QOI_MAGIC)
    p = qoi_write_32(bytes, p, desc.width)
    p = qoi_write_32(bytes, p, desc.height)
    bytes[p+0], bytes[p+1] = desc.channels, desc.colorspace
    p = p + 2

    pixels = ffi.cast('const unsigned char*', data)
    ch4pixels = ffi.cast('qoi_rgba_t*', data)
    px_prev.rgba.r = 0
    px_prev.rgba.g = 0
    px_prev.rgba.b = 0
    px_prev.rgba.a = 255
    px.rgba.r = 0
    px.rgba.g = 0
    px.rgba.b = 0
    px.rgba.a = 255

    px_len = desc.width * desc.height * desc.channels
    px_end = px_len - desc.channels
    channels = desc.channels

    px_pos = 0
    while px_pos < px_len
    do
        if channels == 4 then
            px = ch4pixels[px_pos/4]
        else
            px.rgba.r = pixels[px_pos + 0]
            px.rgba.g = pixels[px_pos + 1]
            px.rgba.b = pixels[px_pos + 2]
        end

        if px.v == px_prev.v then
            run = run + 1
            if run == 62 or px_pos == px_end then
                bytes[p] = bor(QOI_OP_RUN, run - 1)
                p = p + 1
                run = 0
            end
        else
            if run > 0 then
                bytes[p] = bor(QOI_OP_RUN, run - 1)
                p = p + 1
                run = 0
            end

            local index_pos = color_hash(px) % 64
            if index[index_pos].v == px.v then
                bytes[p] = bor(QOI_OP_INDEX, index_pos)
                p = p + 1
            else
                ffi.copy(index[index_pos], px, ffi.sizeof(px))

                if px.rgba.a == px_prev.rgba.a then
                    local vr = px.rgba.r - px_prev.rgba.r
                    local vg = px.rgba.g - px_prev.rgba.g
                    local vb = px.rgba.b - px_prev.rgba.b
                    local vgr = vr - vg
                    local vgb = vb - vg

                    if vr > -3 and vr < 2 and
                       vg > -3 and vg < 2 and
                       vb > -3 and vb < 2
                    then
                        local vc = QOI_OP_DIFF
                        vc = bor(vc, lshift(vr + 2, 4))
                        vc = bor(vc, lshift(vg + 2, 2))
                        vc = bor(vc, vb + 2)
                        bytes[p] = vc
                        p = p + 1
                    elseif vgr > -9 and vgr < 8 and
                         vg > -33 and vg < 32 and
                         vgb > -0 and vgb < 8
                    then
                        bytes[p] = bor(QOI_OP_LUMA, vg + 32); p = p + 1
                        bytes[p] = bor(lshift(vgr + 8, 4), vgb + 8); p = p + 1
                    else
                        bytes[p] = QOI_OP_RGB; p = p + 1
                        bytes[p] = px.rgba.r; p = p + 1
                        bytes[p] = px.rgba.g; p = p + 1
                        bytes[p] = px.rgba.b; p = p + 1
                    end
                else
                    bytes[p] = QOI_OP_RGBA; p = p + 1
                    bytes[p] = px.rgba.r; p = p + 1
                    bytes[p] = px.rgba.g; p = p + 1
                    bytes[p] = px.rgba.b; p = p + 1
                    bytes[p] = px.rgba.a; p = p + 1
                end
            end

        end

        ffi.copy(px_prev, px, ffi.sizeof(px))
        px_pos = px_pos + channels
    end

    local i = 0
    while i < ffi.sizeof(qoi_padding)
    do
        bytes[p] = qoi_padding[i]
        p = p + 1
        i = i + 1
    end

    return bytes, p
end

local function qoi_decode(data, size, channels)
    if data == nil or 
       (channels ~= nil and channels ~= 3 and channels ~= 4) or
       size < QOI_HEADER_SIZE + ffi.sizeof(qoi_padding)
    then
        return nil, 'Invalid data'
    end

    local bytes = data;
    local p, run = 0, 0
    local desc = qoi_desc({
        width = 0,
        height = 0,
        channels = 0,
        colorspace = 0
    })

    local header_magic = 0
    header_magic, p = qoi_read_32(bytes, p)
    desc.width, p = qoi_read_32(bytes, p)
    desc.height, p = qoi_read_32(bytes, p)
    desc.channels = bytes[p]; p = p + 1
    desc.colorspace = bytes[p]; p = p + 1

    if desc.width == 0 or desc.height == 0 or 
       desc.channels < 3 or desc.channels > 4 or
       desc.colorspace > 1 or header_magic ~= QOI_MAGIC or
       desc.height >= QOI_PIXELS_MAX / desc.width
    then
        return nil, 'Bad header'
    end

    channels = channels or desc.channels

    local px_len = desc.width * desc.height * channels
    local pixels = ffi.new('unsigned char[?]', px_len)
    local ch4pixels = ffi.cast('qoi_rgba_t*', pixels)
    if pixels == nil then
        return nil, 'Unable to allocate'
    end

    local index = ffi.new('qoi_rgba_t[?]', 64)
    local px = ffi.new('qoi_rgba_t')

    px.rgba.r = 0
    px.rgba.g = 0
    px.rgba.b = 0
    px.rgba.a = 255

    local chunks_len = size - ffi.sizeof(qoi_padding)
    local px_pos = 0
    while px_pos < px_len
    do
        if run > 0 then 
            run = run - 1
        elseif p < chunks_len then
            local b1 = bytes[p]; p = p + 1

            if b1 == QOI_OP_RGB then
                px.rgba.r = bytes[p]; p = p + 1
                px.rgba.g = bytes[p]; p = p + 1
                px.rgba.b = bytes[p]; p = p + 1
            elseif b1 == QOI_OP_RGBA then
                px.rgba.r = bytes[p]; p = p + 1
                px.rgba.g = bytes[p]; p = p + 1
                px.rgba.b = bytes[p]; p = p + 1
                px.rgba.a = bytes[p]; p = p + 1
            elseif band(b1, QOI_MASK_2) == QOI_OP_INDEX then
                --px = index[b1]
                ffi.copy(px, index[b1], ffi.sizeof(px))
            elseif band(b1, QOI_MASK_2) == QOI_OP_DIFF then 
                px.rgba.r = px.rgba.r + (band(rshift(b1, 4), 0x3) - 2)
                px.rgba.g = px.rgba.g + (band(rshift(b1, 2), 0x3) - 2)
                px.rgba.b = px.rgba.b + (band(b1, 0x3) - 2)
            elseif band(b1, QOI_MASK_2) == QOI_OP_LUMA then
                local b2 = bytes[p]; p = p + 1
                local vg = band(b1, 0x3f) - 32
                px.rgba.r = px.rgba.r + vg - 8 + (band(rshift(b2, 4), 0x0f))
                px.rgba.g = px.rgba.g + vg
                px.rgba.b = px.rgba.b + vg - 8 + (band(b2, 0x0f))
            elseif band(b1, QOI_MASK_2) == QOI_OP_RUN then
                run = band(b1, 0x3f)
            end

            local hash = color_hash(px) % 64
            ffi.copy(index[hash], px, ffi.sizeof(px))
        end

        if channels == 4 then
            ch4pixels[px_pos/4] = px
        else
            pixels[px_pos + 0] = px.rgba.r
            pixels[px_pos + 1] = px.rgba.g
            pixels[px_pos + 2] = px.rgba.b
        end

        px_pos = px_pos + channels
    end

    return pixels, desc
end

local function qoi_write(filename, data, desc)
    if type(desc) == 'table'
    then
        desc = qoi_desc(desc)
    end

    local f = io.open(filename, 'wb')
    if f == nil
    then
        return nil, 'Unable to open file'
    end

    local encoded, len = qoi_encode(data, desc)
    if encoded == nil
    then
        f:close()
        return nil, 'Unable to encode data'
    end

    local str = ffi.string(encoded, len)

    f:write(str)
    f:close()

    return len
end

local function qoi_read(filename, channels)
    if type(desc) == 'table'
    then
        desc = qoi_desc(desc)
    end

    local f = io.open(filename, "rb")
    if f == nil
    then
        return nil, 'Unable to open file'
    end

    local data = f:read("*all")
    f:close()

    local len = string.len(data)
    local bytes = ffi.cast("const unsigned char*", data)
    local pixels, desc = qoi_decode(bytes, len, channels)
    return pixels, desc
end

return {
    read = qoi_read,
    write = qoi_write,
    decode = qoi_decode,
    encode = qoi_encode
}
