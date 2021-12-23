local ffi = require('ffi')
local qoi = require('luaqoi')

local function test()
    local data = ffi.new('qoi_rgba_t[4]')
    for i=0,3
    do
        data[i].rgba.a = 255
        data[i].rgba.r = i == 0 and 255 or 0
        data[i].rgba.g = i == 1 and 255 or 0
        data[i].rgba.b = i == 2 and 255 or 0
    end

    local desc = {
        width = 2,
        height = 2,
        channels = 4,
        colorspace = 0
    }

    qoi.write("test.qoi", data, desc)

    local pixels, desc2 = qoi.read("roundtrip-start.qoi")
    qoi.write("roundtrip-out.qoi", pixels, desc2)
end

test()