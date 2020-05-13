-- New high performance static interface
-- Copyright (C) Mathew Heard (splitice)
-- Copyright (C) Yichun Zhang (agentzh)


local sub = string.sub
local byte = string.byte
--local tab_insert = table.insert
--local tab_remove = table.remove
local tcp = ngx.socket.tcp
local null = ngx.null
local type = type
local pairs = pairs
local unpack = unpack
local setmetatable = setmetatable
local tonumber = tonumber
local tostring = tostring
local rawget = rawget
local select = select
--local error = error


local ok, new_tab = pcall(require, "table.new")
if not ok or type(new_tab) ~= "function" then
    new_tab = function (narr, nrec) return {} end
end

local _M = {}
_M._VERSION = '0.28'


local common_cmds = {
    "get",      "set",          "mget",     "mset",
    "del",      "incr",         "decr",                 -- Strings
    "llen",     "lindex",       "lpop",     "lpush",
    "lrange",   "linsert",                              -- Lists
    "hexists",  "hget",         "hset",     "hmget",
    --[[ "hmset", ]]            "hdel",                 -- Hashes
    "smembers", "sismember",    "sadd",     "srem",
    "sdiff",    "sinter",       "sunion",               -- Sets
    "zrange",   "zrangebyscore", "zrank",   "zadd",
    "zrem",     "zincrby",                              -- Sorted Sets
    "auth",     "eval",         "expire",   "script",
    "sort",     "flushall"                              -- Others
}


function _M.connect(host, port_or_opts, opts)
    local unix

    local sock, err = tcp()
    if not sock then
        return nil, err
    end

    do
        local typ = type(host)
        if typ ~= "string" then
            error("bad argument #1 host: string expected, got " .. typ, 2)
        end

        if sub(host, 1, 5) == "unix:" then
            unix = true
        end

        if unix then
            typ = type(port_or_opts)
            if port_or_opts ~= nil and typ ~= "table" then
                error("bad argument #2 opts: nil or table expected, got " ..
                      typ, 2)
            end

        else
            typ = type(port_or_opts)
            if typ ~= "number" then
                port_or_opts = tonumber(port_or_opts)
                if port_or_opts == nil then
                    error("bad argument #2 port: number expected, got " ..
                          typ, 2)
                end
            end

            if opts ~= nil then
                typ = type(opts)
                if typ ~= "table" then
                    error("bad argument #3 opts: nil or table expected, got " ..
                          typ, 2)
                end
            end
        end
    end

    local ok

    if unix then
        ok, err = sock:connect(host, port_or_opts)
        opts = port_or_opts

    else
        ok, err = sock:connect(host, port_or_opts, opts)
    end

    if not ok then
        return ok, err
    end

    if opts and opts.ssl then
        ok, err = sock:sslhandshake(false, opts.server_name, opts.ssl_verify)
        if not ok then
            return ok, "failed to do ssl handshake: " .. err
        end
    end

    return sock
end


local function _read_reply(sock)
    local line, err = sock:receive()
    if not line then
        if err == "timeout" then
            sock:close()
        end
        return nil, err
    end

    local prefix = byte(line)

    if prefix == 36 then    -- char '$'
        -- print("bulk reply")

        local size = tonumber(sub(line, 2))
        if size < 0 then
            return null
        end

        local data, err = sock:receive(size)
        if not data then
            if err == "timeout" then
                sock:close()
            end
            return nil, err
        end

        local dummy, err = sock:receive(2) -- ignore CRLF
        if not dummy then
            return nil, err
        end

        return data

    elseif prefix == 43 then    -- char '+'
        -- print("status reply")

        return sub(line, 2)

    elseif prefix == 42 then -- char '*'
        local n = tonumber(sub(line, 2))

        -- print("multi-bulk reply: ", n)
        if n < 0 then
            return null
        end

        local vals = new_tab(n, 0)
        local nvals = 0
        for i = 1, n do
            local res, err = _read_reply(sock)
            if res then
                nvals = nvals + 1
                vals[nvals] = res

            elseif res == nil then
                return nil, err

            else
                -- be a valid redis error value
                nvals = nvals + 1
                vals[nvals] = {false, err}
            end
        end

        return vals

    elseif prefix == 58 then    -- char ':'
        -- print("integer reply")
        return tonumber(sub(line, 2))

    elseif prefix == 45 then    -- char '-'
        -- print("error reply: ", n)

        return false, sub(line, 2)

    else
        -- when `line` is an empty string, `prefix` will be equal to nil.
        return nil, "unknown prefix: \"" .. tostring(prefix) .. "\""
    end
end


local function _gen_req(args)
    local nargs = #args

    local req = new_tab(nargs * 5 + 1, 0)
    req[1] = "*" .. nargs .. "\r\n"
    local nbits = 2

    for i = 1, nargs do
        local arg = args[i]
        if type(arg) ~= "string" then
            arg = tostring(arg)
        end

        req[nbits] = "$"
        req[nbits + 1] = #arg
        req[nbits + 2] = "\r\n"
        req[nbits + 3] = arg
        req[nbits + 4] = "\r\n"

        nbits = nbits + 5
    end

    -- it is much faster to do string concatenation on the C land
    -- in real world (large number of strings in the Lua VM)
    return req
end


--local function _check_msg(res)
--    return type(res) == "table" and res[1] == "message"
--end


local function _do_cmd(sock, ...)
    local args = {...}

    local req = _gen_req(args)

    -- print("request: ", table.concat(req))

    local bytes, err = sock:send(req)
    if not bytes then
        return nil, err
    end

    return _read_reply(sock)
end

function _M.read_reply(sock)
    return _read_reply(sock)
end


for i = 1, #common_cmds do
    local cmd = common_cmds[i]

    _M[cmd] =
        function (sock, ...)
            return _do_cmd(sock, cmd, ...)
        end
end

function _M.hmset(sock, hashname, ...)
    if select('#', ...) == 1 then
        local t = select(1, ...)

        local n = 0
        for k, v in pairs(t) do
            n = n + 2
        end

        local array = new_tab(n, 0)

        local i = 0
        for k, v in pairs(t) do
            array[i + 1] = k
            array[i + 2] = v
            i = i + 2
        end
        -- print("key", hashname)
        return _do_cmd(sock, "hmset", hashname, unpack(array))
    end

    -- backwards compatibility
    return _do_cmd(sock, "hmset", hashname, ...)
end

local _P = {}
local mt = { __index = _P }

function _M.init_pipeline(sock, n)
    return setmetatable({ _reqs = new_tab(n or 4, 0), _sock = sock }, mt)
end


function _P.commit_pipeline(self)
    local reqs = rawget(self, "_reqs")
    if not reqs then
        return nil, "no pipeline"
    end

    local sock = rawget(self, "_sock")
    if not sock then
        return nil, "no sock"
    end

    self._reqs = nil

    local bytes, err = sock:send(reqs)
    if not bytes then
        return nil, err
    end

    local nvals = 0
    local nreqs = #reqs
    local vals = new_tab(nreqs, 0)
    for i = 1, nreqs do
        local res, err = _read_reply(sock)
        if res then
            nvals = nvals + 1
            vals[nvals] = res

        elseif res == nil then
            if err == "timeout" then
                sock:close()
            end
            return nil, err

        else
            -- be a valid redis error value
            nvals = nvals + 1
            vals[nvals] = {false, err}
        end
    end

    return vals
end


local function _do_pipeline_cmd(self, ...)
    local args = {...}

    local req = _gen_req(args)


    local reqs = rawget(self, "_reqs")
    reqs[#reqs + 1] = req
    return
end


function _M.array_to_hash(t)
    local n = #t
    -- print("n = ", n)
    local h = new_tab(0, n / 2)
    for i = 1, n, 2 do
        h[t[i]] = t[i + 1]
    end
    return h
end


-- this method is deperate since we already do lazy method generation.
function _M.add_commands(...)
    local cmds = {...}
    for i = 1, #cmds do
        local cmd = cmds[i]
        _M[cmd] =
            function (sock, ...)
                return _do_cmd(sock, cmd, ...)
            end
    end
end


setmetatable(_M, {__index = function(self, cmd)
    local method =
        function (sock, ...)
            return _do_cmd(sock, cmd, ...)
        end

    -- cache the lazily generated method in our
    -- module table
    _M[cmd] = method
    return method
end})

setmetatable(_P, {__index = function(self, cmd)
    local method =
        function (self, ...)
            return _do_pipeline_cmd(self, cmd, ...)
        end

    -- cache the lazily generated method in our
    -- module table
    _P[cmd] = method
    return method
end})


return _M
