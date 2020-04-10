-- Copyright (C) 2019-2020 chenwj
-- Intro: 点对点传输信号
-- Date: 2019/08/22

local semaphore = require "ngx.semaphore"

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function (narr, nrec) return {} end
end

local tab_new = require "table.new"
local peers_semas = tab_new(1000000, 0)

-- 创建sema
local function create_sema(session_id)
    if session_id == nil then
        return nil
    end

    local sema = peers_semas[session_id]
    if sema ~= nil then
        -- ngx.log(ngx.INFO, session_id, " is exist, not create new!!!")
        return sema
    else
        -- ngx.log(ngx.INFO, "create session_id semaphore: ", session_id)
        peers_semas[session_id] = semaphore.new(0)

        return peers_semas[session_id]
    end
end

-- 获取sema
local function get_sema(session_id)
    if session_id == nil then
        return nil
    end

    local sema = peers_semas[session_id]
    -- ngx.log(ngx.INFO, "get_sema, session_id:", session_id)
    if sema == nil then
        -- ngx.log(ngx.ERR, "get sema err: ", session_id, " create it!")
        peers_semas[session_id] = semaphore.new(0)
        return peers_semas[session_id]
    end
    return sema
end

-- 删除sema
function delete_sema(session_id)
    peers_semas[session_id] =  nil
end


local _M = new_tab(0, 4)

_M._VERSION = '0.0.1'

function _M.create(session_id)
    create_sema(session_id)
end

function _M.wait(session_id, sec)
    local sema = create_sema(session_id)
    if not sema then
        ngx.log(ngx.ERR, "get sema err, session_id:", session_id)
        return nil, "not found room"
    end
    
    -- ngx.log(ngx.INFO, "sema : ", session_id, " now has ", sema:count(), " resource.")
    return sema:wait(sec) 
end

function _M.post(session_id)
    local sema = get_sema(session_id)
    if sema ~= nil then
        return sema:post(1) 
    else
        ngx.log(ngx.ERR, "post ", session_id, " not found sema.")
        return "error", "not found sema"
    end
end

function _M.delete(session_id)
    peers_semas[session_id] =  nil
end

return _M


