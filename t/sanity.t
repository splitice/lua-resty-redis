# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_package_cpath "/usr/local/openresty-debug/lualib/?.so;/usr/local/openresty/lualib/?.so;;";
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_NGINX_REDIS_PORT} ||= 6379;

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: set and get
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"

            local red, err = redis.connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not red then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = redis.flushall(red)
            if not res then
                ngx.say("failed to flushall: ", err)
                return
            end

            red:settimeout(1000) -- 1 sec

            local res, err = redis.set(red,"dog", "an animal")
            if not res then
                ngx.say("failed to set dog: ", err)
                return
            end

            ngx.say("set dog: ", res)

            for i = 1, 2 do
                local res, err = redis.get(red,"dog")
                if err then
                    ngx.say("failed to get dog: ", err)
                    return
                end

                if not res then
                    ngx.say("dog not found.")
                    return
                end

                ngx.say("dog: ", res)
            end

            red:close()
        ';
    }
--- request
GET /t
--- response_body
set dog: OK
dog: an animal
dog: an animal
--- no_error_log
[error]



=== TEST 3: get nil bulk value
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"

            local red, err = redis.connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not red then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = redis.flushall(red)
            if not res then
                ngx.say("failed to flushall: ", err)
                return
            end

            red:settimeout(1000) -- 1 sec

            for i = 1, 2 do
                res, err = redis.get(red,"not_found")
                if err then
                    ngx.say("failed to get: ", err)
                    return
                end

                if res == ngx.null then
                    ngx.say("not_found not found.")
                    return
                end

                ngx.say("get not_found: ", res)
            end

            red:close()
        ';
    }
--- request
GET /t
--- response_body
not_found not found.
--- no_error_log
[error]



=== TEST 4: get nil list
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"

            local red, err = redis.connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not red then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = redis.flushall(red)
            if not res then
                ngx.say("failed to flushall: ", err)
                return
            end

            red:settimeout(1000) -- 1 sec

            for i = 1, 2 do
                res, err = redis.lrange(red, "nokey", 0, 1)
                if err then
                    ngx.say("failed to get: ", err)
                    return
                end

                if res == ngx.null then
                    ngx.say("nokey not found.")
                    return
                end

                ngx.say("get nokey: ", #res, " (", type(res), ")")
            end

            red:close()
        ';
    }
--- request
GET /t
--- response_body
get nokey: 0 (table)
get nokey: 0 (table)
--- no_error_log
[error]



=== TEST 5: incr and decr
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"

            local red, err = redis.connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not red then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = redis.flushall(red)
            if not res then
                ngx.say("failed to flushall: ", err)
                return
            end

            red:settimeout(1000) -- 1 sec

            local res, err = redis.set(red,"connections", 10)
            if not res then
                ngx.say("failed to set connections: ", err)
                return
            end

            ngx.say("set connections: ", res)

            res, err = redis.incr(red,"connections")
            if not res then
                ngx.say("failed to set connections: ", err)
                return
            end

            ngx.say("incr connections: ", res)

            local res, err = redis.get(red,"connections")
            if err then
                ngx.say("failed to get connections: ", err)
                return
            end

            res, err = redis.incr(red, "connections")
            if not res then
                ngx.say("failed to incr connections: ", err)
                return
            end

            ngx.say("incr connections: ", res)

            res, err = redis.decr(red,"connections")
            if not res then
                ngx.say("failed to decr connections: ", err)
                return
            end

            ngx.say("decr connections: ", res)

            res, err = redis.get(red,"connections")
            if not res then
                ngx.say("connections not found.")
                return
            end

            ngx.say("connections: ", res)

            res, err = redis.del(red,"connections")
            if not res then
                ngx.say("failed to del connections: ", err)
                return
            end

            ngx.say("del connections: ", res)

            res, err = redis.incr(red,"connections")
            if not res then
                ngx.say("failed to set connections: ", err)
                return
            end

            ngx.say("incr connections: ", res)

            res, err = redis.get(red,"connections")
            if not res then
                ngx.say("connections not found.")
                return
            end

            ngx.say("connections: ", res)

            red:close()
        ';
    }
--- request
GET /t
--- response_body
set connections: OK
incr connections: 11
incr connections: 12
decr connections: 11
connections: 11
del connections: 1
incr connections: 1
connections: 1
--- no_error_log
[error]



=== TEST 6: bad incr command format
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"

            local red, err = redis.connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not red then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = redis.flushall(red)
            if not res then
                ngx.say("failed to flushall: ", err)
                return
            end

            red:settimeout(1000) -- 1 sec

            local res, err = redis.incr(red,"connections", 12)
            if not res then
                ngx.say("failed to set connections: ", res, ": ", err)
                return
            end

            ngx.say("incr connections: ", res)

            red:close()
        ';
    }
--- request
GET /t
--- response_body
failed to set connections: false: ERR wrong number of arguments for 'incr' command
--- no_error_log
[error]



=== TEST 7: lpush and lrange
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"

            local red, err = redis.connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not red then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = redis.flushall(red)
            if not res then
                ngx.say("failed to flushall: ", err)
                return
            end

            red:settimeout(1000) -- 1 sec

            local res, err = redis.lpush(red,"mylist", "world")
            if not res then
                ngx.say("failed to lpush: ", err)
                return
            end
            ngx.say("lpush result: ", res)

            res, err = redis.lpush(red,"mylist", "hello")
            if not res then
                ngx.say("failed to lpush: ", err)
                return
            end
            ngx.say("lpush result: ", res)

            res, err = redis.lrange(red,"mylist", 0, -1)
            if not res then
                ngx.say("failed to lrange: ", err)
                return
            end
            local cjson = require "cjson"
            ngx.say("lrange result: ", cjson.encode(res))

            red:close()
        ';
    }
--- request
GET /t
--- response_body
lpush result: 1
lpush result: 2
lrange result: ["hello","world"]
--- no_error_log
[error]



=== TEST 8: blpop expires its own timeout
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"

            local red, err = redis.connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not red then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = redis.flushall(red)
            if not res then
                ngx.say("failed to flushall: ", err)
                return
            end

            red:settimeout(2000) -- 2 sec

            local res, err = redis.blpop(red,"key", 1)
            if err then
                ngx.say("failed to blpop: ", err)
                return
            end

            if res == ngx.null then
                ngx.say("no element popped.")
                return
            end

            local cjson = require "cjson"
            ngx.say("blpop result: ", cjson.encode(res))

            red:close()
        ';
    }
--- request
GET /t
--- response_body
no element popped.
--- no_error_log
[error]
--- timeout: 3



=== TEST 9: blpop expires cosocket timeout
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"

            local red, err = redis.connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not red then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = redis.flushall(red)
            if not res then
                ngx.say("failed to flushall: ", err)
                return
            end

            red:settimeout(200) -- 200 ms

            local res, err = redis.blpop(red,"key", 1)
            if err then
                ngx.say("failed to blpop: ", err)
                return
            end

            if not res then
                ngx.say("no element popped.")
                return
            end

            local cjson = require "cjson"
            ngx.say("blpop result: ", cjson.encode(res))

            red:close()
        ';
    }
--- request
GET /t
--- response_body
failed to blpop: timeout
--- error_log
lua tcp socket read timed out




=== TEST 11: mget
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"

            local red, err = redis.connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not red then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = redis.flushall(red)
            if not res then
                ngx.say("failed to flushall: ", err)
                return
            end

            red:settimeout(1000) -- 1 sec

            local res, err = redis.set(red,"dog", "an animal")
            if not res then
                ngx.say("failed to set dog: ", err)
                return
            end

            ngx.say("set dog: ", res)

            for i = 1, 2 do
                local res, err = redis.mget(red, "dog", "cat", "dog")
                if err then
                    ngx.say("failed to get dog: ", err)
                    return
                end

                if not res then
                    ngx.say("dog not found.")
                    return
                end

                local cjson = require "cjson"
                ngx.say("res: ", cjson.encode(res))
            end

            red:close()
        ';
    }
--- request
GET /t
--- response_body
set dog: OK
res: ["an animal",null,"an animal"]
res: ["an animal",null,"an animal"]
--- no_error_log
[error]

