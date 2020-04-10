-- Copyright (C) 2019-2020 chenwj
-- Intro: 日志记录，以后可能还得推送到其它服务器上去
-- Date: 2019/08/28

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function (narr, nrec) return {} end
end

local cjson_safe = require "cjson.safe"

-- 日志级别：
-- 1 debug 详细的调试日志
-- 2 info  重要信息日志
-- 3 err   错误日志
local level = 2

local _M = new_tab(0, 4)

_M._VERSION = '0.0.1'

function _M.debug(...)
	if level > 1 then
		return 
	end

	local arg = {...}
	local n = table.getn(arg)

	if n < 2 then
		return
	end

	local log = {}
	for i=1, n, 2 do
		log[arg[i]] = arg[i+1]
	end

	log["time"] = ngx.time()
	local log_str = cjson_safe.encode(log)
	-- local log_sub = string.sub(log_str, 2, #log_str -1)

	if log_str ~= nil then
		ngx.log(ngx.DEBUG, log_str)
	end
end

function _M.info(...)
	local arg = {...}
	local n = table.getn(arg)

	if n < 2 then
		return
	end

	local log = {}
	for i=1, n, 2 do
		log[arg[i]] = arg[i+1]
	end

	log["time"] = ngx.time()
	local log_str = cjson_safe.encode(log)
	-- local log_sub = string.sub(log_str, 2, #log_str -1)

	if log_str ~= nil then
		ngx.log(ngx.INFO, log_str)
	end
end

function _M.err(...)
	local arg = {...}
	local n = table.getn(arg)

	if n < 2 then
		return
	end

	local log = {}
	for i=1, n, 2 do
		log[arg[i]] = arg[i+1]
	end

	log["time"] = ngx.time()
	local log_str = cjson_safe.encode(log)
	-- local log_sub = string.sub(log_str, 2, #log_str -1)
	
	if log_str ~= nil then
		ngx.log(ngx.ERR, log_str)
	end
end

return _M