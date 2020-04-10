local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function (narr, nrec) return {} end
end

-------------------- FOR MY CONNFIG HERE ---------------------------
-- 群发消息通道名
local room_msg_chnl  = "room_msg_chnl"

-- 点对点消息通道名
local p2p_msg_chnl = "p2pMsg"

-- 添加/移除群通道名
local room_add_or_remove_chnnl = "room_add_or_remove_chnnl"

-- 创建群通道名
local room_create_chnnl = "room_create_chnnl"

-- ws登录访问的http请求地址
local login_check_info = {
    address = "47.75.29.144",
    port = 32000
}

-- redis配置
local redis = {
	address = "127.0.0.1",
	port = 6379,
	password = "newlife&99"
}
-------------------- FOR MY CONNFIG HERE END---------------------------

local _M = new_tab(0, 4)
_M._VERSION = '0.0.1'

-- 获取群发消息通道名
function _M.get_room_msg_chnl()
	return room_msg_chnl
end

-- 获取点对点消息通道名
function _M.get_p2p_msg_chnl()
	return p2p_msg_chnl
end

-- 添加/移除群通道名
function _M.get_room_add_or_remove_chnnl()
	return room_add_or_remove_chnnl
end

-- 创建群通道名
function _M.get_room_create_chnnl()
	return room_create_chnnl
end

function _M.get_redis_info()
	return redis
end

-- 登录验证http请求地址
function _M.get_login_check_url()
    local login_check_url = string.format("http://%s:%d/auth?token=", login_check_info.address, login_check_info.port)
	return login_check_url
end

return _M
