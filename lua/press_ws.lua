-- Copyright (C) 2019-2020 chenwj
-- Intro: websockt for chat, message from redis sub
-- Date: 2019/08/14

require "resty.core"
local redis = require "redis"
local server = require "resty.websocket.server"
local cjson_safe = require "cjson.safe"
local http = require "resty.http"

local sema_module = require "sema_module"
local stats_module = require "stats_module"
local peers_module = require "peers_module"
local peers_sema_module = require "peers_sema_module"
local config = require "config"

local kill = ngx.thread.kill

-- 信号量
local worker_id = ngx.worker.id()
-- 获取消息id
local cache = ngx.shared.cache
local p2pcache = ngx.shared.p2pcache
local recv_thread = nil
local g_session_id = nil
local g_user_id = nil

-- 协程控制
local t = {}


local wb, err = server:new {
    timeout = 5000,
    max_payload_len = 65535
}

if not wb then
    ngx.log(ngx.ERR, "failed to new websocket: ", err)
    return
end

local arg = ngx.req.get_uri_args()

local inc_key = string.format("%s_%d", test_room_id, worker_id)
local last_inc_num = cache:get(inc_key)

local function send_by_key(key)
    local v = cache:get(key)
    if v == nil then
        ngx.log(ngx.ERR, "key ", key, " is nil")
        return "error"
    end

    -- send msg, 变成base64发送数据
    local send_txt = ngx.decode_base64(v)
    local bytes, err = wb:send_text(send_txt)
    if not bytes then
        wb:send_close(444, "bytes is nil")
        ngx.log(ngx.ERR, "failed to send text:", err)
        return "error"
    end

    return "ok"
end

local function send_msg(room_id, last_inc_num, last_inc_now)
    local n = last_inc_now - last_inc_num
    if n > 0 then
        for i=1, n do
            -- msg_id = room_name + work_id + msg_inc_num
            local key = string.format("%s_%d_%d",room_id, worker_id, last_inc_num + i)
            local result = send_by_key(key) 
        end
    end
end

--等待一个消息的到来
local function wait_msg(room_id)
    ngx.log(ngx.INFO, "user:", g_user_id, " wait msg in room :", room_id)
    local inc_key = string.format("%s_%d", room_id, worker_id)
    local last_inc_num = cache:get(inc_key) 

    if last_inc_num == nil then
        last_inc_num = 0
    end

    while true do
        local ok, err = sema_module.wait(room_id, 60)
        local inc_key = string.format("%s_%d", room_id, worker_id)
        local last_inc_now = cache:get(inc_key)
        if last_inc_now == nil then
            last_inc_now = 0
        end

        -- ngx.log(ngx.ERR, "inc_key:", inc_key, " last_inc_now:", last_inc_now)

        if ok then
            send_msg(room_id, last_inc_num, last_inc_now)
            last_inc_num = last_inc_now
            -- ngx.log(ngx.INFO, "--> last_inc_num:", last_inc_num)
        end

        ngx.sleep(0.001)
   end
end

local function find_room(room_id)
    local is_found = false
    for k, v in pairs(t) do
        if  k == room_id then
            is_found = true
            break
        end
    end

    return is_found
end

-- 处理添加/移除群通道名 也就是添加或者移除房间
local function create_or_delete_room(room_id, typ)
    if typ == "in" or typ == "new" then
        ngx.log(ngx.INFO, g_user_id, " , s: ", g_session_id, " Create or in a room:", room_id)
        local is_found  = find_room(room_id)

        if is_found == false then
            -- 监听新消息
            sema_module.create(room_id)
            stats_module.people_in(room_id)
            t[room_id] = ngx.thread.spawn(wait_msg, room_id)
        end
    end

    if typ == "out" then
         ngx.log(ngx.INFO, g_user_id, " , s: ", g_session_id, " out a room: ", room_id)
        local is_found  = find_room(room_id)
        if is_found == true then
             stats_module.people_out(room_id)
             local thread_del = t[room_id]
             kill(thread_del)
             t[room_id] = nil
        end

    end
end

-- 获取点对点信息
local function p2p_msg(user_id)
    -- ngx.log(ngx.INFO, "user_id:", user_id, " in")
    local session = peers_module.new_peer(user_id)
    if session == nil then
        ngx.log(ngx.ERR, "user_id:", user_id, " wait p2p_msg failed!")
        return
    end

    g_user_id = user_id
    g_session_id = session

     while true do
        -- wait by session id
        -- ngx.log(ngx.INFO, "user_id:", user_id, " session:", session, " wait")
        local ok, err = peers_sema_module.wait(session, 60)
        if ok then
            
            local n = p2pcache:llen(session)

            for i=1, n do
                local txt = p2pcache:lpop(session)
                if txt ~= nil then
                    local msg = cjson_safe.decode(txt)
                    local inner_typ = msg["typ"] 

                    -- 消息转发
                    if inner_typ == "p2pmsg" then
                        local send_txt = ngx.decode_base64(msg["message"])
                        local bytes, err = wb:send_text(send_txt)
                        ngx.log(ngx.INFO, "Message send==>>:",worker_id, " user_id:", user_id, " send txt:", send_txt)
                    end

                    -- 添加聊天室监听
                    -- 去除聊天室监听
                    -- 创建聊天室
                    if inner_typ == "in" or inner_typ == "out" or inner_typ == "new" then
                        local room_id = msg["message"]
                        if room_id == nil then
                            ngx.log(ngx.ERR, "user_id:", user_id, " session:", session, " create/add/del room failed")
                        else
                            create_or_delete_room(room_id, inner_typ)
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
        -- ngx.log(ngx.ERR, "waitting ...")
        local data, typ, err = wb:recv_frame()

        if wb.fatal then
            ngx.log(ngx.ERR, "failed to receive frame:", err)
            break
        end

        if not data then
            local bytes, err = wb:send_ping()
            if not bytes then
                ngx.log(ngx.ERR, "failed to send ping:", err)
                break
            end
        elseif typ == "ping" then
            local bytes, err = wb:send_pong()
            if not bytes then
                ngx.log(ngx.ERR, "failed to send pong:", err)
                break
            end
        elseif typ == "pong" then
            -- ngx.log(ngx.ERR, "client ponged")
        elseif typ == "text" then
            -- ngx.log(ngx.INFO, "recv from clinet msg:", data)
        elseif typ == "close" then
            ngx.log(ngx.INFO, "recv from close")
            bytes, err = wb:send_close()
            break
        else
            break
            ngx.sleep(0.01)
        end
        -- ngx.sleep(0.5)
    end
end

local function mysplit(inputstr, sep)
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


--- 登录检测
-- local ok, result = login_check(token)
local uid = arg["uid"]
local num = 0

local room_str = arg["cids"]
local rooms = mysplit(room_str, ";")

local is_ok = false

-- 事件循环
if uid ~= nil then
    local user_id = uid
    g_user_id = uid
    for k, room_id in pairs(rooms) do
        local room_id_str = string.format("room_%s", room_id)
        sema_module.create(room_id_str)
        stats_module.people_in(room_id_str)
        t[room_id_str] = ngx.thread.spawn(wait_msg, room_id_str)
    end

    -- 添加点对点事件
    t[user_id] = ngx.thread.spawn(p2p_msg, user_id)
    ngx.log(ngx.INFO, "test user:", user_id, " login sussessul.")

    -- 循环
    msg_loop()
else
    wb:send_close(4100, "token validation failed!")
    return
end

-- 事件退出
if is_ok then
    -- ws关闭
    for k, v in pairs(t) do
        kill(v)
    end

    for k, room_id in pairs(rooms) do
        local room_id_str = string.format("room_%s", room_id)
        -- ngx.log(ngx.INFO, "i=",k,  " out:", room_id)
        stats_module.people_out(room_id_str)
    end
end

-- 人数减少
if g_session_id ~= nil and g_user_id ~= nil then
    peers_module.remove_peer(g_user_id, g_session_id)
    ngx.log(ngx.INFO, "user:", user,  " is leave.")
end

ngx.exit(0)


