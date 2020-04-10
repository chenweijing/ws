require "resty.core"
local redis = require "redis"
local cjson = require "cjson.safe"
local config = require "config"

local red  = redis:new({timeout=3000})  
local chnl_name = config.get_room_msg_chnl()

local arg = ngx.req.get_uri_args()

math.randomseed(tostring(os.time()):reverse():sub(1, 7))
local rand_num = math.random(1,10000)
local room_id = string.format("room_%d", rand_num)

local test_d = {}
test_d["p"] = "rcvMsg"
test_d["chatroom"] = string.format("%d",rand_num)
test_d["msg_id"] = "msg_id_123"
test_d["msgs"] = "hello, press test"

local d = cjson.encode(test_d)


-- room msg
local room_msg = {}

room_msg["cid"] = room_id
room_msg["d"] = ngx.encode_base64(d)

local txt = cjson.encode(room_msg)
ngx.log(ngx.INFO, "chnl_name:", chnl_name)
ngx.say(txt)
red:publish(chnl_name, txt)

--[[
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
cid: 'eb8ad482c5',
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

--[[
local uid_txt = '{"cid":"47d4941a5a","type":"in","uids":["c7a45fe1"]}'

local room_add_remove_chnl_name = config.get_room_add_or_remove_chnnl()
red:publish(room_add_remove_chnl_name, uid_txt)

local json_msg = cjson.decode(uid_txt)

local uids = json_msg["uids"]
ngx.say("cid:", json_msg["cid"], " type:", json_msg["type"], " uids:", uids[1])
]]




