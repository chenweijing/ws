-- Copyright (C) 2019-2020 chenwj
-- Intro: 获取session, session = "session" + worker_id + inc
-- Date: 2019/08/21

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function (narr, nrec) return {} end
end

local worker_id = ngx.worker.id()
local inc = 1

local _M = new_tab(0, 4)

_M._VERSION = '0.0.1'

function _M.new_session_id()
    local session = string.format("session-%d-%d", worker_id, inc)
    inc = inc + 1
    return session
end

return _M