#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

use t::APISIX 'no_plan';

repeat_each(1);
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->yaml_config) {
        my $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

        $block->set_value("yaml_config", $yaml_config);
    }

    if ($block->apisix_yaml) {
        my $upstream = <<_EOC_;
upstreams:
    - service_name: mock
      discovery_type: mock
      type: roundrobin
      id: 1
#END
_EOC_

        $block->set_value("apisix_yaml", $block->apisix_yaml . $upstream);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: create new server picker when nodes change
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream_id: 1
--- config
    location /t {
        content_by_lua_block {
            local discovery = require("apisix.discovery.init").discovery
            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.1", port = 1980, weight = 1},
                        {host = "0.0.0.0", port = 1980, weight = 1},
                    }
                end
            }
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.say(res.status)

            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.2", port = 1980, weight = 1},
                        {host = "127.0.0.3", port = 1980, weight = 1},
                    }
                end
            }
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
        }
    }
--- grep_error_log eval
qr/create_obj_fun\(\): upstream nodes:/
--- grep_error_log_out
create_obj_fun(): upstream nodes:
create_obj_fun(): upstream nodes:



=== TEST 2: don't create new server picker if nodes don't change
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream_id: 1
--- config
    location /t {
        content_by_lua_block {
            local discovery = require("apisix.discovery.init").discovery
            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.1", port = 1980, weight = 1},
                        {host = "0.0.0.0", port = 1980, weight = 1},
                    }
                end
            }
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.say(res.status)

            discovery.mock = {
                nodes = function()
                    return {
                        {host = "0.0.0.0", port = 1980, weight = 1},
                        {host = "127.0.0.1", port = 1980, weight = 1},
                    }
                end
            }
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
        }
    }
--- grep_error_log eval
qr/create_obj_fun\(\): upstream nodes:/
--- grep_error_log_out
create_obj_fun(): upstream nodes:



=== TEST 3: create new server picker when nodes change, up_conf doesn't come from upstream
--- apisix_yaml
routes:
  - uris:
        - /hello
    service_id: 1
services:
  - id: 1
    upstream:
        service_name: mock
        discovery_type: mock
        type: roundrobin
--- config
    location /t {
        content_by_lua_block {
            local discovery = require("apisix.discovery.init").discovery
            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.1", port = 1980, weight = 1},
                        {host = "0.0.0.0", port = 1980, weight = 1},
                    }
                end
            }
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.say(res.status)

            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.2", port = 1980, weight = 1},
                        {host = "0.0.0.0", port = 1980, weight = 1},
                    }
                end
            }
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
        }
    }
--- grep_error_log eval
qr/create_obj_fun\(\): upstream nodes:/
--- grep_error_log_out
create_obj_fun(): upstream nodes:
create_obj_fun(): upstream nodes:



=== TEST 4: don't create new server picker if nodes don't change (port missing)
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream_id: 1
--- config
    location /t {
        content_by_lua_block {
            local discovery = require("apisix.discovery.init").discovery
            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.1", weight = 1},
                        {host = "0.0.0.0", weight = 1},
                    }
                end
            }
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.say(res.status)
            discovery.mock = {
                nodes = function()
                    return {
                        {host = "0.0.0.0", weight = 1},
                        {host = "127.0.0.1", weight = 1},
                    }
                end
            }
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
        }
    }
--- grep_error_log eval
qr/create_obj_fun\(\): upstream nodes:/
--- grep_error_log_out
create_obj_fun(): upstream nodes:
--- error_log
connect() failed



=== TEST 5: create new server picker when priority change
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream_id: 1
--- config
    location /t {
        content_by_lua_block {
            local discovery = require("apisix.discovery.init").discovery
            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.1", port = 1980, weight = 1},
                        {host = "0.0.0.0", port = 1980, weight = 1},
                    }
                end
            }
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.say(res.status)

            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.1", port = 1980, weight = 1},
                        {host = "0.0.0.0", port = 1980, weight = 1, priority = 1},
                    }
                end
            }
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
        }
    }
--- grep_error_log eval
qr/create_obj_fun\(\): upstream nodes:/
--- grep_error_log_out
create_obj_fun(): upstream nodes:
create_obj_fun(): upstream nodes:



=== TEST 6: default priority of discovered node is 0
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream_id: 1
--- config
    location /t {
        content_by_lua_block {
            local discovery = require("apisix.discovery.init").discovery
            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.1", port = 1979, weight = 1, priority = 1},
                        {host = "0.0.0.0", port = 1980, weight = 1},
                        {host = "127.0.0.2", port = 1979, weight = 1, priority = -1},
                    }
                end
            }
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.say(res.status)
        }
    }
--- error_log
connect() failed
--- grep_error_log eval
qr/proxy request to \S+/
--- grep_error_log_out
proxy request to 127.0.0.1:1979
proxy request to 0.0.0.0:1980



=== TEST 7: create new server picker when metadata change
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream_id: 1
--- config
    location /t {
        content_by_lua_block {
            local discovery = require("apisix.discovery.init").discovery
            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.1", port = 1980, weight = 1, metadata = {a = 1}},
                        {host = "0.0.0.0", port = 1980, weight = 1, metadata = {}},
                    }
                end
            }
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.say(res.status)

            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.1", port = 1980, weight = 1, metadata = {a = 1}},
                        {host = "0.0.0.0", port = 1980, weight = 1, metadata = {b = 1}},
                    }
                end
            }
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
        }
    }
--- grep_error_log eval
qr/create_obj_fun\(\): upstream nodes:/
--- grep_error_log_out
create_obj_fun(): upstream nodes:
create_obj_fun(): upstream nodes:



=== TEST 8: don't create new server picker when metadata doesn't change
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream_id: 1
--- config
    location /t {
        content_by_lua_block {
            local discovery = require("apisix.discovery.init").discovery
            local meta1 = {a = 1}
            local meta2 = {b = 2}
            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.1", port = 1980, weight = 1, metadata = meta1},
                        {host = "0.0.0.0", port = 1980, weight = 1, metadata = meta2},
                    }
                end
            }
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.say(res.status)

            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.1", port = 1980, weight = 1, metadata = meta1},
                        {host = "0.0.0.0", port = 1980, weight = 1, metadata = meta2},
                    }
                end
            }
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
        }
    }
--- grep_error_log eval
qr/create_obj_fun\(\): upstream nodes:/
--- grep_error_log_out
create_obj_fun(): upstream nodes:



=== TEST 9: bad nodes return by the discovery
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream_id: 1
--- config
    location /t {
        content_by_lua_block {
            local discovery = require("apisix.discovery.init").discovery
            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.1", port = 1980, weight = "0"},
                    }
                end
            }
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.say(res.status)
        }
    }
--- response_body
503
--- error_log
invalid nodes format: failed to validate item 1: property "weight" validation failed: wrong type: expected integer, got string



=== TEST 10: compare nodes by value only once when nodes's address be changed but values are same
--- log_level: debug
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream_id: 1
--- config
    location /t {
        content_by_lua_block {
            local old_nodes = {{host = "127.0.0.1", port = 1980, weight = 1}, {host = "127.0.0.2", port = 1980, weight = 1}}
            local discovery = require("apisix.discovery.init").discovery
            discovery.mock = {
                nodes = function()
                    return old_nodes
                end
            }
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            for i = 1, 10 do
                local res = httpc:request_uri(uri, {method = "GET", keepalive = false})
                if res.status ~= 200 then
                    ngx.say("request failed: ", res.status)
                    return
                end
            end

            local new_nodes = {{host = "127.0.0.2", port = 1980, weight = 1}, {host = "127.0.0.1", port = 1980, weight = 1}}
            discovery.mock = {
                nodes = function()
                    return new_nodes
                end
            }
            for i = 1, 10 do
                local res = httpc:request_uri(uri, {method = "GET", keepalive = false})
                if res.status ~= 200 then
                    ngx.say("request failed: ", res.status)
                    return
                end
            end
            ngx.say("pass")
        }
    }
--- response_body
pass
--- grep_error_log eval
qr/compare upstream nodes by value|fill node info for upstream/
--- grep_error_log_out
fill node info for upstream
compare upstream nodes by value
fill node info for upstream
