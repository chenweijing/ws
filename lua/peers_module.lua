-- Copyright (C) 2019-2020 chenwj
-- Intro: 对用户的管理
-- Date: 2019/08/21

local sess = require "session_module"

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function (narr, nrec) return {} end
end

local tab_new = require "table.new"
local users = tab_new(1000000, 0)

local worker_id = ngx.worker.id()

local function mysplit(inputstr, sep)
    if inputstr == nil or inputstr == "" then
        local t1 = {}
        return t1
    end

    if sep == nil then
        sep = "%s"
    end

    local t = {}; i=1
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        t[i]=str
        i = i+1
    end
    return t
end

local _M = new_tab(0, 4)
_M._VERSION = '0.0.1'

-- 添加一个peer到users中去, 一个userid有多个peer
function _M.new_peer(user_id)
    local session = sess.new_session_id()

    user_id = string.format("%s_%d",user_id, worker_id)
    local peers = users[user_id]

    if peers == nil or peers == "" then
    	users[user_id] = session
    else
    	local new_peers = string.format("%s#%s", peers, session)
    	users[user_id] = new_peers
    end

    return session
end

-- 查询此user_id有几个连接
function _M.has_conns(user_id)
	user_id = string.format("%s_%d",user_id, worker_id)
	local peers = users[user_id]

	if peers == nil or peers == "" then
		return 0
	else
		local res = mysplit(peers, "#")
		local n = table.getn(res)
		return n
	end
end

function _M.get_peer_sessions(user_id)
	if user_id == nil then
		return nil
	end
	
	user_id = string.format("%s_%d",user_id, worker_id)
	local peers = users[user_id]

	if peers == nil or peers == "" then
		return nil
	else
		local res = mysplit(peers, "#")
		return res
	end
end

-- 从uers中删除一个peer
function _M.remove_peer(user_id, session_id)
	user_id = string.format("%s_%d",user_id, worker_id)
	if user_id == nil or session_id == nil then
		return
	end

	local result = nil
	local peers = users[user_id]

	if peers == nil or peers == "" then
        users[user_id] = nil
		return
	end

	local res = mysplit(peers, "#")
	for i=1,table.getn(res) do
		if res[i] ~= session_id and res[i] ~= nil then
			if result == nil or result == "" then
				result = string.format("%s", res[i])
			else
				result = string.format("%s#%s", result, res[i])
			end
		end
	end

	users[user_id] = result
end

return _M
