require "resty.core"
local redis = require "redis"
local cjson = require "cjson"
local config = require "config"


local arg = ngx.req.get_uri_args()

-- 删除列表测试
-- 根据每个房间创建一个sema
local tab_new = require "table.new"
local g_rooms = tab_new(10000, 0)


--[[
local function add_session_to_room(room_id, session)
	if room_id == nil then
		return false
	end

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
			ngx.say("session:", session, " is exist.")
			is_exist = true
			break
		end
	end

	if is_exist == false then
		table.insert(this_room, session)
	end

	return true
end

local function remove_session_from_room(room_id, session)
	if room_id == nil then
		return false
	end

	-- 判断房间是否存在
	local this_room = g_rooms[room_id]
	if this_room == nil then
		this_room = {}
		g_rooms[room_id] = this_room
	end

	-- 查找并删除是否存在
	for k, v in pairs(this_room) do
		if v == session then
			ngx.say("delete session:", session)
			table.remove(this_room, k)
			break
		end
	end

	return true
end

local function get_sessions_from_room(room_id)
	local sessions = g_rooms[room_id]
	if sessions == nil then
		sessions = {}
		g_rooms[room_id] = sessions
	end

	return sessions
end

local function print_sessions(sessions)
	for k, v in pairs(sessions) do
		ngx.say("k:", k, " v:", v)
	end
end


local room1 = "room-1"
local room2 = "room-2"
local room3 = "room-3"

local s1 = "session-1"
local s2 = "session-2"
local s3 = "session-3"

remove_session_from_room(room1, s1)
remove_session_from_room(room2, s1)
remove_session_from_room(room3, s1)

add_session_to_room(room1, s1)
add_session_to_room(room1, s2)
add_session_to_room(room1, s3)

ngx.say("--- test room2 add 10000 people -----")
local t1 = ngx.now()
for i=1, 10000 do
	local session = string.format("session-2-%d", i)
	add_session_to_room(room2, session)
end
local t2 = ngx.now()
ngx.say(string.format("执行时间： %3f", t2-t1))

ngx.say("------------ room-1 sessons -------------------")
local sessions =  get_sessions_from_room(room1)
print_sessions(sessions)

ngx.say("------------ delete room-1 session-1 -------------------")
remove_session_from_room(room1, s1)
print_sessions(sessions)

ngx.say("------------ delete room-1 session-2 -------------------")
remove_session_from_room(room1, s2)
print_sessions(sessions)


ngx.say("------------ delete room-1 session-3 -------------------")
remove_session_from_room(room1, s3)
print_sessions(sessions)

ngx.say("------------ add room-1 session-1 -------------------")
add_session_to_room(room1, s1)
local sessions =  get_sessions_from_room(room1)
print_sessions(sessions)


ngx.say("=================== redis send =======================\n\n")
]]

local stats = require "stats_module"

local rand_num = stats.get_rand()
local red  = redis:new({timeout=3000})  
local chnl_name = config.get_room_msg_chnl()

if rand_num % 2 == 0 then
	-- room msg
	local room_msg = {}
	local message_txt = "hello, this is room_message testfds aaaaaaaaaaaaaaaaaaaaa;"
	room_msg["cid"] = "test_room_1"
	room_msg["d"] = ngx.encode_base64(message_txt)
	room_msg["type"] = "default"

	local txt = cjson.encode(room_msg)
	--ngx.log(ngx.INFO, "chnl_name:", chnl_name)
	ngx.say(txt)
	red:publish(chnl_name, txt)
else
	-- uid msg
	local uid_msg = {}
	local uids = {"test_uid_1", "test_uid_2"}
	local message_txt = "p2pmessage belive myself;"

	uid_msg["type"] = arg["1"]
	uid_msg["uids"] = uids
	uid_msg["d"] = ngx.encode_base64(message_txt)

	local txt2 = cjson.encode(uid_msg)

	local p2p_chnl_name = config.get_p2p_msg_chnl()
	red:publish(p2p_chnl_name, txt2)
end


ngx.say("send room:",  arg["room"], " msg:", message_txt)


local test_bale = {}

test_bale["a"] = "hello"
test_bale["b"] = "hello two"
test_bale["c"] = "hello two two"

for k, v in pairs(test_bale) do
    ngx.say("k:", k, " v:", v)
end


ngx.say("--------- ")

test_bale["a"] = "hello"
test_bale["b"] = "hello two"
test_bale["c"] = nil

for k, v in pairs(test_bale) do
    ngx.say("k:", k, " v:", v)
end

ngx.say("--------- ")

test_bale["a"] = "hello new"
test_bale["b"] = "hello two new"
table.remove(test_bale, 3)

for k, v in pairs(test_bale) do
    ngx.say("k:", k, " v:", v)
end

ngx.say("hello ok")

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

local t = mysplit(nil, "#")
ngx.say("nil mysplit:", t)


local t2 = mysplit("", "#")
ngx.say("uu mysplit:", t2)

ngx.say("hostname:", ngx.var.hostname)









