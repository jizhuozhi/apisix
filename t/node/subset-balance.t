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
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 30511;
        location /hello {
            content_by_lua_block {
                ngx.say("30511")
            }
        }
    }
    server {
        listen 30512;
        location /hello {
            content_by_lua_block {
                ngx.say("30512")
            }
        }
    }
    server {
        listen 30513;
        location /hello {
            content_by_lua_block {
                ngx.say("30513")
            }
        }
    }
    server {
        listen 30514;
        location /hello {
            content_by_lua_block {
                ngx.say("30514")
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

our $yaml_config = <<_EOC_;
apisix:
  node_listen: 1984
  enable_control: true
  control:
    ip: 127.0.0.1
    port: 9090
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  consul:
    servers:
      - "http://127.0.0.1:8500"
_EOC_

run_tests();

__DATA__

=== TEST 1: subset_lb metadata match
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  - uri: "/hello"
    upstream:
      scheme: "http"
      discovery_type: "consul"
      service_name: "svc_subset_match"
      type: "subset"
      subset:
        subset_selectors:
          - keys: ["env"]
#END
--- config
location /v1/agent {
    proxy_pass http://127.0.0.1:8500;
}
#END
--- request eval
[
    "PUT /v1/agent/service/register\n" . "{\"ID\": \"svc_subset_match1\", \"Name\": \"svc_subset_match\", \"Address\": \"127.0.0.1\", \"Port\": 30511, \"Meta\": {\"env\": \"prod\"}}",
    "PUT /v1/agent/service/register\n" . "{\"ID\": \"svc_subset_match2\", \"Name\": \"svc_subset_match\", \"Address\": \"127.0.0.1\", \"Port\": 30512, \"Meta\": {\"env\": \"canary\"}}",

    "GET /hello",

    "PUT /v1/agent/service/deregister/svc_subset_match1",
    "PUT /v1/agent/service/deregister/svc_subset_match2",
]
--- more_headers
env: canary
--- response_body_like eval
[
    qr//,
    qr//,

    qr/30512\n/,

    qr//,
    qr//,
]



=== TEST 2: subset_lb metadata match with header_prefix
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  - uri: "/hello"
    upstream:
      scheme: "http"
      discovery_type: "consul"
      service_name: "svc_subset_match"
      type: "subset"
      subset:
        header_prefix: "x-"
        subset_selectors:
          - keys: ["env"]
#END
--- config
location /v1/agent {
    proxy_pass http://127.0.0.1:8500;
}
#END
--- request eval
[
    "PUT /v1/agent/service/register\n" . "{\"ID\": \"svc_subset_match1\", \"Name\": \"svc_subset_match\", \"Address\": \"127.0.0.1\", \"Port\": 30511, \"Meta\": {\"env\": \"prod\"}}",
    "PUT /v1/agent/service/register\n" . "{\"ID\": \"svc_subset_match2\", \"Name\": \"svc_subset_match\", \"Address\": \"127.0.0.1\", \"Port\": 30512, \"Meta\": {\"env\": \"canary\"}}",

    "GET /hello",

    "PUT /v1/agent/service/deregister/svc_subset_match1",
    "PUT /v1/agent/service/deregister/svc_subset_match2",
]
--- more_headers
x-env: canary
--- response_body_like eval
[
    qr//,
    qr//,

    qr/30512\n/,

    qr//,
    qr//,
]



=== TEST 3: subset_lb metadata match with default (NO_FALLBACK)
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  - uri: "/hello"
    upstream:
      scheme: "http"
      discovery_type: "consul"
      service_name: "svc_subset_match"
      type: "subset"
      subset:
        subset_selectors:
          - keys: ["env"]
#END
--- config
location /v1/agent {
    proxy_pass http://127.0.0.1:8500;
}
#END
--- request eval
[
    "PUT /v1/agent/service/register\n" . "{\"ID\": \"svc_subset_match1\", \"Name\": \"svc_subset_match\", \"Address\": \"127.0.0.1\", \"Port\": 30511, \"Meta\": {\"env\": \"prod\"}}",
    "PUT /v1/agent/service/register\n" . "{\"ID\": \"svc_subset_match2\", \"Name\": \"svc_subset_match\", \"Address\": \"127.0.0.1\", \"Port\": 30512, \"Meta\": {\"env\": \"canary\"}}",

    "GET /hello",

    "PUT /v1/agent/service/deregister/svc_subset_match1",
    "PUT /v1/agent/service/deregister/svc_subset_match2",
]
--- more_headers
env: preview
--- error_code eval
[200, 200, 502, 200, 200]
--- ignore_error_log



=== TEST 4: subset_lb metadata match with NO_FALLBACK
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  - uri: "/hello"
    upstream:
      scheme: "http"
      discovery_type: "consul"
      service_name: "svc_subset_match"
      type: "subset"
      subset:
        fallback_policy: NO_FALLBACK
        subset_selectors:
          - keys: ["env"]
#END
--- config
location /v1/agent {
    proxy_pass http://127.0.0.1:8500;
}
#END
--- request eval
[
    "PUT /v1/agent/service/register\n" . "{\"ID\": \"svc_subset_match1\", \"Name\": \"svc_subset_match\", \"Address\": \"127.0.0.1\", \"Port\": 30511, \"Meta\": {\"env\": \"prod\"}}",
    "PUT /v1/agent/service/register\n" . "{\"ID\": \"svc_subset_match2\", \"Name\": \"svc_subset_match\", \"Address\": \"127.0.0.1\", \"Port\": 30512, \"Meta\": {\"env\": \"canary\"}}",

    "GET /hello",

    "PUT /v1/agent/service/deregister/svc_subset_match1",
    "PUT /v1/agent/service/deregister/svc_subset_match2",
]
--- more_headers
env: preview
--- error_code eval
[200, 200, 502, 200, 200]
--- ignore_error_log



=== TEST 5: subset_lb metadata match with ANY_ENDPOINT
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  - uri: "/hello"
    upstream:
      scheme: "http"
      discovery_type: "consul"
      service_name: "svc_subset_match"
      type: "subset"
      subset:
        fallback_policy: ANY_ENDPOINT
        subset_selectors:
          - keys: ["env"]
#END
--- config
location /v1/agent {
    proxy_pass http://127.0.0.1:8500;
}
#END
--- request eval
[
    "PUT /v1/agent/service/register\n" . "{\"ID\": \"svc_subset_match1\", \"Name\": \"svc_subset_match\", \"Address\": \"127.0.0.1\", \"Port\": 30511, \"Meta\": {\"env\": \"prod\"}}",
    "PUT /v1/agent/service/register\n" . "{\"ID\": \"svc_subset_match2\", \"Name\": \"svc_subset_match\", \"Address\": \"127.0.0.1\", \"Port\": 30512, \"Meta\": {\"env\": \"canary\"}}",

    "GET /hello",

    "PUT /v1/agent/service/deregister/svc_subset_match1",
    "PUT /v1/agent/service/deregister/svc_subset_match2",
]
--- more_headers
env: preview
--- response_body_like eval
[
    qr//,
    qr//,

    qr/(30511|30512)\n/,

    qr//,
    qr//,
]



=== TEST 6: subset_lb metadata match with DEFAULT_SUBSET
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  - uri: "/hello"
    upstream:
      scheme: "http"
      discovery_type: "consul"
      service_name: "svc_subset_match"
      type: "subset"
      subset:
        fallback_policy: DEFAULT_SUBSET
        subset_selectors:
          - keys: ["env"]
        default_subset:
          env: ["prod"]
#END
--- config
location /v1/agent {
    proxy_pass http://127.0.0.1:8500;
}
#END
--- request eval
[
    "PUT /v1/agent/service/register\n" . "{\"ID\": \"svc_subset_match1\", \"Name\": \"svc_subset_match\", \"Address\": \"127.0.0.1\", \"Port\": 30511, \"Meta\": {\"env\": \"prod\"}}",
    "PUT /v1/agent/service/register\n" . "{\"ID\": \"svc_subset_match2\", \"Name\": \"svc_subset_match\", \"Address\": \"127.0.0.1\", \"Port\": 30512, \"Meta\": {\"env\": \"canary\"}}",

    "GET /hello",

    "PUT /v1/agent/service/deregister/svc_subset_match1",
    "PUT /v1/agent/service/deregister/svc_subset_match2",
]
--- more_headers
env: preview
--- response_body_like eval
[
    qr//,
    qr//,

    qr/30511\n/,

    qr//,
    qr//,
]



=== TEST 7: subset_lb metadata match with multi subset_selectors
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  - uri: "/hello"
    upstream:
      scheme: "http"
      discovery_type: "consul"
      service_name: "svc_subset_match"
      type: "subset"
      subset:
        subset_selectors:
          - keys: ["env"]
          - keys: ["cluster"]
#END
--- config
location /v1/agent {
    proxy_pass http://127.0.0.1:8500;
}
#END
--- request eval
[
    "PUT /v1/agent/service/register\n" . "{\"ID\": \"svc_subset_match1\", \"Name\": \"svc_subset_match\", \"Address\": \"127.0.0.1\", \"Port\": 30511, \"Meta\": {\"env\": \"prod\"}}",
    "PUT /v1/agent/service/register\n" . "{\"ID\": \"svc_subset_match2\", \"Name\": \"svc_subset_match\", \"Address\": \"127.0.0.1\", \"Port\": 30512, \"Meta\": {\"env\": \"canary\"}}",
    "PUT /v1/agent/service/register\n" . "{\"ID\": \"svc_subset_match3\", \"Name\": \"svc_subset_match\", \"Address\": \"127.0.0.1\", \"Port\": 30513, \"Meta\": {\"cluster\": \"default\"}}",

    "GET /hello",

    "PUT /v1/agent/service/deregister/svc_subset_match1",
    "PUT /v1/agent/service/deregister/svc_subset_match2",
    "PUT /v1/agent/service/deregister/svc_subset_match3",
]
--- more_headers
env: preview
cluster: default
--- response_body_like eval
[
    qr//,
    qr//,
    qr//,

    qr/30513\n/,

    qr//,
    qr//,
    qr//,
]
