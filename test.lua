local ffi = require('ffi')
local qoi = require('luaqoi')

local function generateRandom(n)
    local data = ffi.new('char[?]', n)
    for i=0,n-1 do
        data[i] = math.random(0,255)
    end
    return data
end

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
        colorspace = qoi.SRGB
    }

    local desc3 = {
        width = 2,
        height = 2,
        channels = 3,
        colorspace = qoi.SRGB
    }
    local data3 = generateRandom(desc3.width * desc3.height * desc3.channels)

    qoi.write("test4.qoi", data, desc)

    qoi.write("test3.qoi", data3, desc3)

    local pixels, desc2 = qoi.read("roundtrip-start.qoi")
    qoi.write("roundtrip-out.qoi", pixels, desc2)
end

local function bench()
    math.randomseed(5892173192)

    local testRepeat = 100
    local unpack = unpack or table.unpack
    local desc = {
        width = 1024,
        height = 1024,
        channels = 4,
        colorspace = qoi.SRGB
    }

    local data = ffi.new('qoi_rgba_t[1048576]')
    for i=0,desc.width*desc.height-1 do
        data[i].rgba.a = 255
        data[i].rgba.r = math.random(0,255)
        data[i].rgba.g = math.random(0,255)
        data[i].rgba.b = math.random(0,255)
    end

    local times       = {}
	local throughputs = {}

    for i=1,testRepeat do
        local start = os.clock()
        local encoded, len = qoi.encode(data, desc)
        local time = os.clock() - start
        local throughput = ((desc.width*desc.height*desc.channels)/(1024*1024))/time
		table.insert(times, time)
		table.insert(throughputs, throughput)
    end

    qoi.write("bench.qoi", data, desc)

    print( ("min: %.3fs %.2f MB/s"):format( math.min(unpack(times)), math.min(unpack(throughputs))) )
	print( ("max: %.3fs %.2f MB/s"):format( math.max(unpack(times)), math.max(unpack(throughputs))) )
end

if arg[1] then
    bench()
else
    test()
end