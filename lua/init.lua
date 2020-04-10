-- Copyright (C) 2019-2020 chenwj
-- Intro: websockt for chat, message from redis sub
-- Date: 2019/08/15

require "resty.core"
-- redis message
local redis         = require "redis"
local cjson_safe    = require "cjson.safe"
local config        = require "config"
local log           = require "log"

local is_closed     = false
local co            = nil

-- semaphores
local sema_module       = require "sema_module"
local stats_module      = require "stats_module"

-- for p2p
local peers_module      = require "peers_module"
local peers_sema_module = require "peers_sema_module"

local worker_id         = ngx.worker.id()
local cache             = ngx.shared.cache

local p2pcache          = ngx.shared.p2pcache

local keep_alive_cid    = "it_keep_alive_cid"
local room_message      = require "room_message"
local action            = "action"


local g_threads           = {}        -- 添加redis断开事件监听    
local g_chnl_lasttime     = {}        -- 添加应答信号机制，检测是否断开, 记录最后访问时间

local room_chnl_name            = config.get_room_msg_chnl()
local p2p_chnl_name             = config.get_p2p_msg_chnl()
local room_inout_chnl_name      = config.get_room_add_or_remove_chnnl()
local room_create_chnl_name     = config.get_room_create_chnnl()

local machine_id                = string.format("machine-%f-%d",ngx.now(), math.random())

local redis_msg_timeout         = 5
local g_heartbeat_count         = 0

-- 新的群推送方式
local function process_room_msg(data)
    local msg = cjson_safe.decode(data)

    local room_id = msg["cid"]

    if room_id == nil then
        log.err(action, "redis_room_msg", "err", "room_id is nil.", "worker_id", worker_id)
        return 
    end

    -- 心跳信号
    if room_id == keep_alive_cid then
        --心跳日志
        if worker_id == 0 and msg["machine_id"] == machine_id then
            g_heartbeat_count = g_heartbeat_count + 1
            if g_heartbeat_count == 20 then
                g_heartbeat_count = 0
                --log.info("worker_id", worker_id, action, "redis_room_msg", "heartbeat", "keepalive ok", "machine_id", machine_id)
            end
        end

        g_chnl_lasttime[room_chnl_name] = ngx.now()
        return
    end

    -- 解析消息
    local msg_typ = msg["type"] -- disband or default
    local txt = msg["d"]

    -- 编码消息
    local inner_msg = {}
    inner_msg["typ"]     = msg_typ
    inner_msg["room_id"] = room_id
    inner_msg["message"] = txt
    inner_msg["t1"]      = ngx.now()
    
    -- TODO: 添加消息r值记录
    --[[
    local msg_log = msg["log"] 
    if msg_log ~= nil then
        local r = msg_log["r"]
        inner_msg["r"] = r
        log.info(action, "msg_send", "msg_id", r, "room_id", room_id, "worker_id", worker_id)
    else
        log.info(action, "msg_send", "room_id", "txt", ngx.decode_base64(txt), "room_id", room_id, "worker_id", worker_id)
    end
    ]]

    local set_txt = cjson_safe.encode(inner_msg)

    -- 发送群消息
    local sessions = room_message.get_sessions_from_room(room_id)

    for k, session in pairs(sessions) do
        -- 放入到内存队列中去
        local length, err = p2pcache:rpush(session, set_txt)
        if err ~= nil then
            log.err(action, "memory_msg", "err", err, "worker_id", worker_id)
        else
            peers_sema_module.post(session)
        end
    end

    return false
end

-- 推送点对点消息
--[[
typ:"p2pmsg" "outroom" "inroom", "newroom"
message: "txt or room id"
]]

-- 处理点对点消息通道名
local function process_p2p_msg(data)
    if data == nil then
        log.err(action, "redis_p2p_msg", "err", "data is nil.", "worker_id", worker_id)
        return 
    end

    -- parse redis message
    local msg = cjson_safe.decode(data)

    if msg == nil then
        log.err(action, "redis_p2p_msg", "err", "json msg failed", "worker_id", worker_id)
        return 
    end

    -- 心跳信号
    local room_id = msg["cid"]
    if room_id == keep_alive_cid then
        -- log.debug("worker_id", worker_id, "keep_alive_message", "p2p msg keep_alive now")
        g_chnl_lasttime[p2p_chnl_name] = ngx.now()
        return
    end

    local uids = msg["uids"]
    local txt = msg["d"]


    -- encode my message
    local inner_msg = {}
    inner_msg["typ"]      = "p2pmsg"
    inner_msg["message"]  = txt
    inner_msg["process_type"] = msg["type"]
    inner_msg["t1"]       = ngx.now()
    
    -- TODO: 添加消息r值记录
    --[[
    local msg_log = msg["log"] 
    if msg_log ~= nil then
        local r = msg_log["r"]
        inner_msg["r"] = r
        -- TODO: 测试记录msg_id
        log.info(action, "msg_send", "msg_id", r, "worker_id", worker_id)
    else
        log.info(action, "msg_send", "room_id", "txt", ngx.decode_base64(txt), "worker_id", worker_id)
    end
    ]]


    local set_txt = cjson_safe.encode(inner_msg)

    if uids == nil then 
        log.err(action, "redis_p2p_msg", "err", "p2p uids is nil", "worker_id", worker_id)
        return
    end

    -- 1:n 对每个uid进行发送消息
    for k, user_id in pairs(uids) do
        -- ngx.log(ngx.INFO, "对每个uid进行发送消息 user_id:", user_id)
        if user_id ~= nil then
            local sessions = peers_module.get_peer_sessions(user_id)
            if sessions ~= nil then
                for i, session in pairs(sessions) do
                    -- 放入到内存队列中去
                    local length, err = p2pcache:rpush(session, set_txt)
                    if err ~= nil then
                        log.err(action, "memory_msg", "err", "memroy err", "worker_id", worker_id)
                    else
                        peers_sema_module.post(session)
                    end
                end
            end
        end
    end

    return false
end

-- 处理添加/新建/移除群通道名
--[[
{ "cid":"testcid", "type":"in" ,"uids ":["uid1","uid2"]}
{ "cid":"testcid", "type":"out","uids ":["uid1","uid2"]}

typ:"p2pmsg" "outroom" "inroom", "newroom"
message: "txt or room id"
]]
local function process_manage_room_msg(data)
    if data == nil then
        log.err(action, "redis_room_process_msg", "err", "recive redis data is nil", "worker_id", worker_id)
        return 
    end

    local msg = cjson_safe.decode(data)

    if msg == nil then
        log.err(action, "redis_room_process_msg", "err", "json msg failed", "worker_id", worker_id)
        return 
    end

    local room_id = msg["cid"]

    -- 心跳信号
    if room_id == keep_alive_cid then
        g_chnl_lasttime[room_inout_chnl_name] = ngx.now()
        return
    end


    local typ = msg["type"]
    local uids = msg["uids"]

    if uids == nil or room_id == nil or typ == nil then 
        log.err(action, "redis_room_process_msg", "err", "uids or room_id or typ is nil", "worker_id", worker_id)
        return
    end

    local inner_msg = {}
    inner_msg["typ"] = typ
    inner_msg["message"]  = room_id
    inner_msg["room_id"]  = room_id
    inner_msg["t1"]       = ngx.now()

    local set_txt = cjson_safe.encode(inner_msg)

    -- log.info(action, "room_manage_msg", "err", "redis recv ok", "worker_id", worker_id)
    -- log.info("worker_id", worker_id, "add_remove_send_msg", user_id, "session", session, "typ", typ, "d", d)

    -- 1:n 对每个uid进行发送消息
    for k, user_id in pairs(uids) do
        if user_id ~= nil then
            local sessions = peers_module.get_peer_sessions(user_id)
            if sessions ~= nil then
                for i, session in pairs(sessions) do
                    -- 放入到内存队列中去
                    local length, err = p2pcache:rpush(session, set_txt)
                    if err ~= nil then
                        log.err(action, "redis_room_process_msg", "err", "memroy err", "worker_id", worker_id)
                    else
                        peers_sema_module.post(session)
                    end

                    -- log.info("worker_id", worker_id, "add_remove_send_msg", user_id, "session", session, "typ", typ, "d", d)
                end
            end
        end
    end

    return false
end

local function process_room_create(data)
end


-- 等待其它数据模块发送聊天数据过来
local function recv_msg_from_redis(chnl_name, process_func)
    -- redis 缓存
    local red  = redis:new({timeout=2000}) 
    local func  = red:subscribe(chnl_name)

    if not func then
        log.err(action, "redis_connected_msg", "err", "cconnected redis failed", "worker_id", worker_id)
        g_threads[chnl_name] = nil
        return nil
    end

    -- 连接成功
    g_chnl_lasttime[chnl_name] = ngx.now()

    while true do
        local res, err = func()
        if err then
            log.err(action, "redis_connected_msg", "err", "redis connected timeout restart this thread.", "worker_id", worker_id)
            g_threads[chnl_name] = ngx.thread.spawn(recv_msg_from_redis, chnl_name, process_func)
            break
        else
            if is_closed then
                func(false)
                return
            end

            if  res ~= nil then
                -- 处理消息
                local data = res[3]
                process_func(data)
            end
        end
    end
end 

--  群发定时器函数
local function start_room_msg_chnl()
    local chnl_name = config.get_room_msg_chnl()
    local process_func = process_room_msg

    g_threads[chnl_name] = ngx.thread.spawn(recv_msg_from_redis, chnl_name, process_func)
    -- recv_msg_from_redis(chnl_name, process_func)
end

--  p2p定时启动函数
local function start_p2p_msg_chnl()
    local chnl_name = config.get_p2p_msg_chnl()
    local process_func = process_p2p_msg

    g_threads[chnl_name] = ngx.thread.spawn(recv_msg_from_redis, chnl_name, process_func)
    -- recv_msg_from_redis(chnl_name, process_func)
end

--  群增加移除
local function start_room_add_or_remove_chnl()
    local chnl_name = config.get_room_add_or_remove_chnnl()
    local process_func = process_manage_room_msg

    g_threads[chnl_name] = ngx.thread.spawn(recv_msg_from_redis, chnl_name, process_func)
    -- recv_msg_from_redis(chnl_name, process_func)
end

--  创建群函数
local function start_create_room_chnl()
    local chnl_name = config.get_room_create_chnnl()
    local process_func = process_manage_room_msg

    g_threads[chnl_name] = ngx.thread.spawn(recv_msg_from_redis, chnl_name, process_func)
    -- recv_msg_from_redis(chnl_name, process_func)
end

local function  restart_thread(chnl_name, process_func)
    -- kill 
    if g_threads[chnl_name] ~= nil then
        ngx.thread.kill(g_threads[chnl_name])
    end

    -- restart 
    local log_str = string.format("%s restart redis connected", chnl_name)
    log.err(action, "redis_connected_msg", "err", log_str, "worker_id", worker_id)
    g_threads[chnl_name] = ngx.thread.spawn(recv_msg_from_redis, chnl_name, process_func)
end

-- 保活消息内部发送
local function keep_alive_message_send()
    if ngx.worker.id() ~= 0 then 
        return
    end

    local chnl_name1 = config.get_room_msg_chnl()
    local chnl_name2 = config.get_p2p_msg_chnl()
    local chnl_name3 = config.get_room_add_or_remove_chnnl()
    local chnl_name4 = config.get_room_create_chnnl()

    local process_func = process_manage_room_msg

    local msg = {}
    msg["cid"]          = keep_alive_cid
    msg["msg"]          = "keep_alive_msg_content"
    msg["machine_id"]   = machine_id
    local txt = cjson_safe.encode(msg)

    while true do
        local red  = redis:new({timeout=3000})  

        red:publish(chnl_name1, txt)
        red:publish(chnl_name2, txt)
        red:publish(chnl_name3, txt)
        red:publish(chnl_name4, txt)

        local t1 = g_chnl_lasttime[room_chnl_name]
        if t1 == nil then
            t1 = 0.000
        end

        local t = ngx.now() - t1
        if t > redis_msg_timeout then
            restart_thread(room_chnl_name, process_room_msg)
        end

        local t1 = g_chnl_lasttime[p2p_chnl_name]
        if t1 == nil then
            t1 = 0.000
        end
        local t = ngx.now() - t1
        if t > redis_msg_timeout then
            restart_thread(p2p_chnl_name, process_p2p_msg)
        end

        local t1 = g_chnl_lasttime[p2p_chnl_name]
        if t1 == nil then
            t1 = 0.000
        end

        local t = ngx.now() - t1
        if t > redis_msg_timeout then
            restart_thread(room_inout_chnl_name, process_manage_room_msg)
            restart_thread(room_create_chnl_name, process_manage_room_msg)
        end

        ngx.sleep(1)
    end
end

----------------------------- START RECV CHANNL -----------------------------------------------
if worker_id == nil then
    ngx.log(ngx.INFO,"worker_id is ", worker_id, " return here.")
    return
end

ngx.log(ngx.INFO,"start by worker_id: ", worker_id, " ...")

-- 启动处理群发消息函数
local ok, err = ngx.timer.at(0, start_room_msg_chnl)
if not ok then
    log.err("timer_err", err)
end

-- 启动p2p函数
local ok, err = ngx.timer.at(1, start_p2p_msg_chnl)
if not ok then
    log.err("timer_err", err)
end

-- 启动群增加移除处理函数
local ok, err = ngx.timer.at(1, start_room_add_or_remove_chnl)
if not ok then
    log.err("timer_err", err)
end

-- 创建群函数
local ok, err = ngx.timer.at(1, start_create_room_chnl)
if not ok then
    log.err("timer_err", err)
end

-- 保活
if worker_id == 0 then
    local ok, err = ngx.timer.at(3, keep_alive_message_send)
    if not ok then
        log.err("timer_err", err)
    end
end

