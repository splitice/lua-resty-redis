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

=== TEST 1: single channel
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local cjson = require "cjson"
            local redis = require "resty.redis"

            redis.add_commands("foo", "bar")

            local red, err = redis.connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not red then
                ngx.say("failed to connect: ", err)
                return
            end

            red:settimeout(1000) -- 1 sec

            local res, err = redis.foo(red, "a")
            if not res then
                ngx.say("failed to foo: ", err)
            end

            res, err = redis.bar(red)
            if not res then
                ngx.say("failed to bar: ", err)
            end
        ';
    }
--- request
GET /t
--- response_body eval
qr/\Afailed to foo: ERR unknown command [`']foo[`'](?:, with args beginning with: `a`,\s*)?
failed to bar: ERR unknown command [`']bar[`'](?:, with args beginning with:\s*)?
\z/
--- no_error_log
[error]
