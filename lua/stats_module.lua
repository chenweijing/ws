-- 统计每个房间有多少人数

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function (narr, nrec) return {} end
end

local tab_new = require "table.new"
local c = ngx.shared.cache

-- 根据每个房间创建一个sema
local stats = tab_new(10000, 0)
local worker_id = ngx.worker.id()

-- 创建stats
function create_rooms(room_id)
    room_id = string.format("%s_%d", room_id, worker_id)
    local num = stats[room_id]
    if num ~= nil then
        ngx.log(ngx.INFO, room_id, " is exist in stats module, not create new!!!")
    else
        ngx.log(ngx.INFO, "create stats: ", room_id)
        stats[room_id] = 0
    end
end

-- 添加一个成员
function add_one(room_id)
    room_id = string.format("%s_%d", room_id, worker_id)
    local num = stats[room_id]
    if num == nil then
        stats[room_id] = 1
        --ngx.log(ngx.INFO, room_id, " is only one people online.")
    else
        stats[room_id] = num + 1
        -- ngx.log(ngx.INFO, room_id, " is ", num, " people online.")
    end
end

-- 删除一个成员
function delete_one(room_id)
    room_id = string.format("%s_%d", room_id, worker_id)
    local num = stats[room_id]
    if num == nil then
        stats[room_id] = 0
        -- ngx.log(ngx.INFO, room_id, " is only one people online. [del]")
    else
        num = num -1
        if num < 0 then
            num = 0
        end
        stats[room_id] = num
        -- ngx.log(ngx.INFO, room_id, " is ", num, " people online.[del]")
    end
end

function get_num(room_id)
    room_id = string.format("%s_%d", room_id, worker_id)
    local num = stats[room_id]
    if num == nil then
        -- ngx.log(ngx.INFO, "get stats: ", room_id, " num:0")
        return 0
    elseif num < 0 then
        ngx.log(ngx.ERR, "get stats: ", room_id, "num < 0, ", num)
        return 0
    else
        -- ngx.log(ngx.INFO, "get stats: ", room_id, " num:", num)
        return num
    end
end

local rand_num = 1

local _M = new_tab(0, 4)

_M._VERSION = '0.0.1'

function _M.people_in(room_id)
    add_one(room_id)
end

function _M.people_out(room_id)
    delete_one(room_id)
end

function _M.people_online_num(room_id)
    return get_num(room_id)
end

function _M.get_rand()
    rand_num = rand_num + 1
    return rand_num
end

return _M






















