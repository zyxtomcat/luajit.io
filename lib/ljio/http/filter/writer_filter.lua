-- Copyright (C) Jinhua Luo

local http_time = require("ljio.core.utils").http_time
local constants = require("ljio.http.constants")
local tinsert = table.insert

local M = {}

local postpone_output = 1460
local eol = "\r\n"
local sep = ": "

function M.header_filter(rsp)
	local lcf = rsp.req.lcf or rsp.req.srvcf
	local buf = rsp.bufpool:get()

	local status = constants.status_tbl[rsp.status]
	buf:append(status)

	local headers = rsp.headers

	if rsp.status ~= 304 and headers["content-type"] == nil then
		buf:append("content-type: ", lcf.default_type, "\r\n")
	end

	buf:append("server: luajit.io\r\n")

	buf:append("date: " .. http_time() .. "\r\n")

	if rsp.req.headers["connection"] == "close" then
		buf:append("connection: close\r\n")
	else
		buf:append("connection: keep-alive\r\n")
	end

	for _, key in ipairs(headers) do
		if headers[key] then
			buf:append(key, sep, headers[key], eol)
		end
	end

	buf:append(eol)

	rsp.buffers = buf
	rsp.headers_sent = true

	return true
end

local function flush_body(rsp)
	if rsp.buffers and rsp.buffers.size > 0 then
		local ret,err = rsp.sock:send(rsp.buffers)

		rsp.buffers = nil

		if err then return nil,err end
		rsp.body_sent = true
	end

	return true
end

function M.body_filter(rsp, ...)
	for i = 1, select("#", ...) do
		local buf = select(i, ...)
		local flush = buf.flush
		local eof = buf.eof

		if buf.is_file then
			local ret,err = flush_body(rsp)
			if err then return ret,err end
			local ret,err = rsp.sock:sendfile(buf.path, buf.offset, buf.size)
			if err then return ret,err end
			rsp.bufpool:put(buf)
		elseif buf.size > 0 then
			if rsp.buffers == nil then
				rsp.buffers = buf
			else
				rsp.buffers:append(unpack(buf))
			end
		end

		if flush or eof or (rsp.buffers and rsp.buffers.size >= postpone_output) then
			local ret,err = flush_body(rsp)
			if err then return ret,err end
		end

		if eof then
			rsp.eof = true
			break
		end
	end

	return true
end

return M
