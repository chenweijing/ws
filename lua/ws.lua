-- Copyright (C) 2019-2020 chenwj
-- Intro: websockt for chat, message from redis sub
-- Date: 2019/08/14 [issue cpu 2019/11/1 by chenwj]

require "resty.core"

local redis             = require "redis"
local server            = require "resty.websocket.server"
local cjson_safe        = require "cjson.safe"
local http              = require "resty.http"
local sema_module       = require "sema_module"
local stats_module      = require "stats_module"
local peers_module      = require "peers_module"
local peers_sema_module = require "peers_sema_module"
local config            = require "config"
local log               = require "log"
local room_message      = require "room_message"

local kill           = ngx.thread.kill
local worker_id      = ngx.worker.id()
local cache          = ngx.shared.cache
local p2pcache       = ngx.shared.p2pcache
local recv_thread    = nil
local g_session_id   = nil
local g_user_id      = nil
local g_is_closed    = false
local g_thd_handle   = nil 
local g_listen_rooms = {}

local action         = "action"
local login_err      = ""
local logout_err     = "logout ok"
local heart_time     = ngx.now()

-- client remote ip
local client_ip      = ngx.var.remote_addr
local headers        = ngx.req.get_headers()
local real_ip        = headers["X-Forward-For"]

if real_ip ~= nil and real_ip ~= "" then
    client_ip = real_ip
end

-- TODO: 测试数据
local g_max_time = 0.000

local wb, err = server:new {
    timeout = 5000,
    max_payload_len = 65535
}

local arg = ngx.req.get_uri_args()
local token = arg["token"]

-- websocket 连接失败事件处理 
if not wb then
    log.err(action, "wsconn", "web_err", err, "token", token, "client", client_ip)
    return
end

if token == nil then
    log.err("web_err", "token is nil.")
    wb:send_close(4001, "token is nil.")
    return
end

-- 验证是否可以登录
local function login_check(token)
    local url = config.get_login_check_url()
    local req_url = string.format("%s%s",url,token)
    local httpc = http.new()
    local res, err = httpc:request_uri(req_url,
        {
            method = "GET",
            -- args = { feature_base64 = feature },
            -- body = ngx.encode_args({ token = token })
        }
    )

    -- TODO:这里服务器断点，会崩溃
    local ok = true
    local result = nil

    if res == nil  then
      ok = false
    else
        if res.status ~= 200 then
             log.err(action, "web_err", "err", "http server connected failed.", "token", token, "client", client_ip)
             wb:send_close(4006, "http server connected failed.")
             ok = false
         end
    end

    if ok then
        log.debug("http_get", res.body)
        result = cjson_safe.decode(res.body)
    end

    httpc:close()

    return ok, result
end

-- 处理添加/移除群通道名 也就是添加或者移除房间
local function process_room_msg(room_id, typ)
    if typ == "in" or typ == "new" then
        room_message.add_session_to_room(room_id, g_session_id)
        g_listen_rooms[room_id] = true
    end

    if typ == "out"  then
        -- room_message.remove_session_from_room(room_id, g_session_id)
        g_listen_rooms[room_id] = false
    end

    local desc = string.format("%s room ok.", typ)
    log.info("user_id", g_user_id, "session_id", g_session_id, "room_id", room_id, action, "room_manage", "desc", desc)
end

-- 获取点对点信息
local function p2p_msg(user_id, session)
     while true do
        ::redo::
        local ok, err = peers_sema_module.wait(session, 60)

        if g_is_closed == true then
            break
        end

        -- 超时处理
        local disconnect_timeout = ngx.now() - heart_time
        if disconnect_timeout >= 60 then
            g_is_closed = true
            logout_err = "heart package recv timeout, conenction is broken!"
            wb:send_close(4000, "connectted timeout")
            break
        end

        if ok then 
            local n = p2pcache:llen(session)

            if n == nil or n < 1 then
                goto redo
            end

            for i=1, n do
                local txt = p2pcache:lpop(session)
                if txt ~= nil then
                    local msg = cjson_safe.decode(txt)
                    local inner_typ = msg["typ"]
                    local t1 = msg["t1"]
                    local r = msg["r"]

                    local t2 = ngx.now()
                    local t = t2 - t1 

                    if t > g_max_time then
                        g_max_time = t
                    end

                    -- TODO:时间过大警告
                    if t > 5 then -- 大于5秒
                        log.info("token", token, "session", g_session_id, "user_id", g_user_id, 
                            action, "send_msg", "send_time_delay", g_max_time,
                            "err", "send time > 5 sec.", "client", client_ip)
                    end

                    -- TODO: 测试记录msg_id
                    --[[
                    if r ~= nil then
                        log.info(action, "msg_send", "msg_id", r, "token", token, "user_id", g_user_id, "session", g_session_id)
                    end
                    ]]

                    -- 群消息
                    if  inner_typ == "default" then
                        local room_id = msg["room_id"]
                        local base64_txt = msg["message"]

                        if g_listen_rooms[room_id] ~= nil and g_listen_rooms[room_id] == true then
                            local send_txt = ngx.decode_base64(base64_txt)
                            local bytes, err = wb:send_text(send_txt)

                            if not bytes or err then
                                log.err(action, "msg_send", "token", token, "user_id", g_user_id, "sesson_id", g_session_id, "web_err", err, "client", client_ip)
                            end
                        end
                    -- p2p消息转发
                    elseif inner_typ == "p2pmsg" then 
                        local send_txt = ngx.decode_base64(msg["message"])
                        local bytes, err = wb:send_text(send_txt)
                        
                        local process_type = msg["process_type"]
                        if process_type == "pwdChanged" then
                            log.info("user_id", g_user_id, "sesson_id", g_session_id, action, "pwd_change", "err", "ok")
                        end

                        if not bytes or err then
                            log.err(action, "msg_send", "token", token, "user_id", g_user_id, "sesson_id", g_session_id, "web_err", err, "client", client_ip)
                        end
                    -- 添加/创建/去除/聊天室
                    elseif inner_typ == "in" or inner_typ == "out" or inner_typ == "new" then
                        local room_id = msg["room_id"]
                        if room_id ~= nil then
                            process_room_msg(room_id, inner_typ)
                        end
                    --  群解散，依旧推消息
                    elseif inner_typ == "disband" then
                        local room_id = msg["room_id"]

                        room_message.remove_session_from_room(room_id, g_session_id)
                        g_listen_rooms[room_id] = false

                        
                        local base64_txt = msg["message"]
                        local send_txt = ngx.decode_base64(base64_txt)
                        local bytes, err = wb:send_text(send_txt)

                        local desc = string.format("%s room ok.", inner_typ)
                        log.info("user_id", g_user_id, "session_id", g_session_id, "room_id", room_id, action, "room_manage", "desc", desc)
                        
                        if not bytes or err then
                            log.err(action, "msg_send", "token", token, "user_id", g_user_id, "sesson_id", g_session_id, "web_err", err, "client", client_ip)
                        end

                    end
                end

                ngx.sleep(0.001)
            end -- for

            ngx.sleep(0.001)
        end
   end
end


-- socket 接收数据，主要是监听断开事件
local function msg_loop()
    while true do
        local data, typ, err = wb:recv_frame()

        if g_is_closed == true then
            break
        end
        
        logout_err = err

        if wb.fatal then
            break
        end

        if not data then
            local bytes, err = wb:send_ping()
            if not bytes then
                break
            end
        elseif typ == "ping" then
            heart_time = ngx.now()
            local bytes, err = wb:send_pong()
            if not bytes then
                break
            end
        elseif typ == "pong" then
            heart_time = ngx.now()
            local bytes, err = wb:send_ping()

        elseif typ == "text" then
            heart_time = ngx.now()

            if #data < 10 then
                local bytes, err = wb:send_text(data)
            end
        elseif typ == "close" then
            bytes, err = wb:send_close()
            break
        else
            break
        end

        ngx.sleep(0.01)
    end
end

local function http_login_check()
    local ok, result = login_check(token)
    
    -- backend error
    if result == nil then
        login_err = "http service return invalid nil."
        wb:send_close(4008, "http service return invalid nil.")
        return false
    end

    if not ok or  result["error"] ~= "" then
        login_err = result["error"]
        wb:send_close(4008, result["error"])
        return false
    end

    local user_id = result["uid"]
    g_user_id = user_id
    
    local cids = result["cids"] 
    for k, room_id in pairs(cids) do
        g_listen_rooms[room_id] = true
    end

    -- uid不能为空
    if user_id == nil then
        login_err = "user info get error."
        wb:send_close(4008, "user info get error.")
        return false
    end

    -- 同一账号登录不能超过3
    --[[
    local has_conn_num = peers_module.has_conns(user_id)
    if has_conn_num > 3 then
         wb:send_close(4002, "user login count is > 3")
         log.err("token", token, "session", g_session_id, "user_id", g_user_id, action, "login", "err", "user login count is > 3")
        return false
    end
    ]]

    return true
end


local function login()
    -- http远程检测
    local result = http_login_check()
    if result == false then
        return false
    end
   
    local session = peers_module.new_peer(g_user_id)
    g_session_id = session

    for room_id, v in pairs(g_listen_rooms) do
        room_message.add_session_to_room(room_id, g_session_id)
    end

    g_thd_handle = ngx.thread.spawn(p2p_msg, g_user_id, session)

    log.info("token", token, "session", g_session_id, "user_id", g_user_id, action, "login", "client", client_ip)

    return true
end

local function logout()
    -- 关闭协程
    if g_thd_handle ~= nil then
        kill(g_thd_handle)
    end

    -- 全局变量
    g_is_closed = true

    -- 退出房间
    for room_id, v in pairs(g_listen_rooms) do
        if room_id ~= nil and g_session_id ~= nil then
            room_message.remove_session_from_room(room_id, g_session_id)
        end
    end

    -- 清除内存数据
    local n = p2pcache:llen(g_session_id)
    if n ~= nil and n > 1 then
         for i=1, n do
            local txt = p2pcache:lpop(g_session_id)
        end
    end

    peers_module.remove_peer(g_user_id, g_session_id)
    peers_sema_module.delete(g_session_id)

    log.info("token", token, "session", g_session_id, "user_id", g_user_id, action, "logout", "web_err", logout_err, "send_time_delay", g_max_time,"client", client_ip)
end


local lg = login()

if lg then
    msg_loop()
    logout()
else
    g_is_closed = true
    log.err("token", token, action, "login", "err", login_err, "client", client_ip)
end

ngx.exit(0)



