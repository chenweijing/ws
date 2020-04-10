local semaphore = require "ngx.semaphore"
local log = require "log"

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function (narr, nrec) return {} end
end

local c = ngx.shared.cache
local worker_id = ngx.worker.id()

-- 根据每个房间创建一个sema
local tab_new = require "table.new"
local semas = tab_new(1000000, 0)

-- 创建sema
local function create_sema(room_id)
    if room_id == nil then
        return nil
    end

    room_id = string.format("%s_%d", room_id, worker_id)
    local sema = semas[room_id]
    if sema ~= nil then
        -- ngx.log(ngx.INFO, room_id, " is exist, not create new!!!")
        return sema
    else
        -- ngx.log(ngx.INFO, "create semaphore: ", room_id)
        semas[room_id] = semaphore.new(0)

        return semas[room_id]
    end
end

-- 获取sema
local function get_sema(room_id)
    if room_id == nil then
        return nil
    end

    room_id = string.format("%s_%d", room_id, worker_id)

    local sema = semas[room_id]
    -- ngx.log(ngx.INFO, "get_sema, room_id:", room_id)
    if sema == nil then
        -- ngx.log(ngx.ERR, "get sema err: ", room_id, " create it!")
        semas[room_id] = semaphore.new(0)
        return semas[room_id]
    end
    return sema
end

-- 删除sema
function delete_sema(room_id)
    if room_id ~= nil then
        room_id = string.format("%_%d", room_id, worker_id)
        sema[room_id] = nil
    end
end


local _M = new_tab(0, 4)

_M._VERSION = '0.0.1'

function _M.create(room_id)
    create_sema(room_id)
end

function _M.wait(room_id, sec)
    local sema = create_sema(room_id)
    if not sema then
        -- ngx.log(ngx.ERR, "get sema err, room_id:", room_id)
        return nil, "not found room"
    end
    
    -- ngx.log(ngx.INFO, "sema : ", room_id, " now has ", sema:count(), " resource.")
    return sema:wait(sec) 
end

function _M.post(room_id, n)
    if n == nil then
        -- ngx.log(ngx.ERR, "post ", room_id, " n is nil")
        return "error", "n is nil"
    end

    if n <= 0 then
        -- ngx.log(ngx.INFO, "no people online, don`t post semaphore.")
        return "ok", nil
    end

    local sema = get_sema(room_id)
    if sema ~= nil then
        -- local c = sema:count()
        -- local n = math.abs(c)
        -- ngx.log(ngx.INFO, "sema : ", room_id, " now has ", sema:count(), " resource, pos n=", n)
        return sema:post(n) 
    else
        ngx.log(ngx.ERR, "post ", room_id, " not found sema.")
        return "error", "not found sema"
    end
end

return _M






















