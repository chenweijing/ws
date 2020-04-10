require "resty.core"
local redis = require "redis"
local cjson = require "cjson"
local config = require "config"

local red  = redis:new({timeout=3000})  
local chnl_name = config.get_room_msg_chnl()

local arg = ngx.req.get_uri_args()

-- room msg
local room_msg = {}
room_msg["cid"] = arg["room"]
room_msg["d"] = ngx.encode_base64(arg["room_msg"])

local txt = cjson.encode(room_msg)
ngx.log(ngx.INFO, "chnl_name:", chnl_name)
ngx.say(txt)
red:publish(chnl_name, txt)

ngx.say("send room:",  arg["room"], " msg:", arg["room_msg"])

-- uid msg
local uid_msg = {}
local uids = {arg["uid"], "test_uid_1", "test_uid_2"}

uid_msg["type"] = arg["1"]
uid_msg["uids"] = uids
uid_msg["d"] = ngx.encode_base64(arg["uid_msg"])

local txt2 = cjson.encode(uid_msg)

local p2p_chnl_name = config.get_p2p_msg_chnl()
red:publish(p2p_chnl_name, txt2)

ngx.say(txt2)

--local cid = "1234567887654321"
--local str1 = string.sub

--[[
{
	"p": "rcvMsg",
	"chatroom": "eb8ad482c5",
	"msg_id": "",
	"sender": "3999cce1",
	"name": "\xe7\x94\xa8\xe6\x88\xb71",
	"avatar": "",
	"msg_type": "",
	"msgs": {
		"p": "msg",
		"d": "evan1"
	},
	"ref_g": "",
	"time": "1566544548801",
	"at_uids": null
}
]]
-- http://47.98.202.83:8082/test?room=df4cadd9db&room_msg=hello, test room msg&uid=3999cce1&uid_msg=hello, test p2p msg


local uid_txt = '{"cid":"47d4941a5a","type":"in","uids":["c7a45fe1"]}'

local room_add_remove_chnl_name = config.get_room_add_or_remove_chnnl()
red:publish(room_add_remove_chnl_name, uid_txt)

local json_msg = cjson.decode(uid_txt)

local uids = json_msg["uids"]
ngx.say("cid:", json_msg["cid"], " type:", json_msg["type"], " uids:", uids[1])

local function add(...)
    local s = 0
    for i, v in pairs{...} do
        ngx.say("i:", i, " v:", v)
    end
end

local function test_arg(...)
	local arg = {...}
	local n = table.getn(arg)
	local log = {}
	for i=1, n, 2 do
		log[arg[i]] = arg[i+1]
	end

	local log_str = cjson.encode(log)
	local log_sub = string.sub(log_str, 2, #log_str -1)
	ngx.say(log_sub)
end


local a = "hello a arg"
add("hello", 1, 3,  a)

local logmp = {}
logmp["msg"] = "服务器错误"
logmp["txt"] = "test 01"

local log_str = cjson.encode(logmp)

ngx.log(ngx.INFO, log_str)

ngx.say(log_str)

test_arg("worker_id",1, "p2p_msg", "hello p2p msg")













