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
local g_rooms = tab_new(100000, 0)

local _M = new_tab(0, 4)
_M._VERSION = '0.0.1'

function _M.add_session_to_room(room_id, session)
    if room_id == nil then
        return false
    end

    room_id = string.format("%s-%d", room_id, worker_id)

    -- 判断房间是否存在
    local this_room = g_rooms[room_id]
    if this_room == nil then
        this_room = {}
        g_rooms[room_id] = this_room
    end

    -- 查找session是否存在
    local is_exist = false
    for k, v in pairs(this_room) do
        if v == session then
            is_exist = true
            break
        end
    end

    if is_exist == false then
        table.insert(this_room, session)
    end

    return true
end

function _M.remove_session_from_room(room_id, session)
    if room_id == nil then
        return false
    end

    room_id = string.format("%s-%d", room_id, worker_id)

    -- 判断房间是否存在
    local this_room = g_rooms[room_id]
    if this_room == nil then
        this_room = {}
        g_rooms[room_id] = this_room
    end

    -- 查找并删除是否存在
    for k, v in pairs(this_room) do
        if v == session then
            table.remove(this_room, k)
            break
        end
    end

    return true
end

function _M.get_sessions_from_room(room_id)
    room_id = string.format("%s-%d", room_id, worker_id)

    local sessions = g_rooms[room_id]
    if sessions == nil then
        sessions = {}
        g_rooms[room_id] = sessions
    end

    return sessions
end

function _M.print_sessions(sessions)
    for k, v in pairs(sessions) do
        ngx.log(ngx.INFO, "key:", k, " session:", v)
    end
end

return _M






















