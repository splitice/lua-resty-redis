# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;;";
    lua_package_cpath "/usr/local/openresty-debug/lualib/?.so;/usr/local/openresty/lualib/?.so;;";
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_NGINX_REDIS_PORT} ||= 6379;

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: hmset key-pairs
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

            red:settimeout(1000) -- 1 sec

            local res, err = redis.hmset(red, "animals", "dog", "bark", "cat", "meow")
            if not res then
                ngx.say("failed to set animals: ", err)
                return
            end
            ngx.say("hmset animals: ", res)

            local res, err = redis.hmget(red, "animals", "dog", "cat")
            if not res then
                ngx.say("failed to get animals: ", err)
                return
            end

            ngx.say("hmget animals: ", res)

            red:close()
        ';
    }
--- request
GET /t
--- response_body
hmset animals: OK
hmget animals: barkmeow
--- no_error_log
[error]



=== TEST 2: hmset lua tables
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

            red:settimeout(1000) -- 1 sec

            local t = { dog = "bark", cat = "meow", cow = "moo" }
            local res, err = redis.hmset(red, "animals", t)
            if not res then
                ngx.say("failed to set animals: ", err)
                return
            end
            ngx.say("hmset animals: ", res)

            local res, err = redis.hmget(red, "animals", "dog", "cat", "cow")
            if not res then
                ngx.say("failed to get animals: ", err)
                return
            end

            ngx.say("hmget animals: ", res)

            red:close()
        ';
    }
--- request
GET /t
--- response_body
hmset animals: OK
hmget animals: barkmeowmoo
--- no_error_log
[error]



=== TEST 3: hmset a single scalar
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

            red:settimeout(1000) -- 1 sec

            local res, err = redis.hmset(red, "animals", "cat")
            if not res then
                ngx.say("failed to set animals: ", err)
                return
            end
            ngx.say("hmset animals: ", res)

            local res, err = redis.hmget(red, "animals", "cat")
            if not res then
                ngx.say("failed to get animals: ", err)
                return
            end

            ngx.say("hmget animals: ", res)

            red:close()
        ';
    }
--- request
GET /t
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
table expected, got string
