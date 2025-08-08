-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local require = require
local core = require("apisix.core")
local ipairs = ipairs
local pairs = pairs
local discovery_utils = require("apisix.utils.discovery")

local _M = {}
local pickers = {}

local function get_picker(type)
    local picker = pickers[type]
    if not picker then
        picker = require("apisix.balancer." .. type)
        pickers[type] = picker
    end
    return picker
end

local function insert_node_to_trie(root, keys, k, v, metadata)
    local cur = root
    for _, key in ipairs(keys) do
        local value = metadata and metadata[key]
        if not value then
            return
        end
        cur.children = cur.children or {}
        cur.children[value] = cur.children[value] or {}
        cur = cur.children[value]
    end
    cur.nodes = cur.nodes or {}
    cur.nodes[k] = v
end

local function build_picker_for_leaves(root, upstream, sub_picker)
    if not root then
        return
    end

    if root.nodes then
        root.picker = sub_picker.new(root.nodes, upstream)
        return
    end

    if root.children then
        for _, child in pairs(root.children) do
            build_picker_for_leaves(child, upstream, sub_picker)
        end
    end
end

local function build_subset_trees(all_nodes, upstream, metadata_map, sub_picker)
    local trees = {}

    for _, selector in ipairs(upstream.subset.subset_selectors or {}) do
        local root = {}
        for k, v in pairs(all_nodes) do
            local metadata = metadata_map[k]
            insert_node_to_trie(root, selector.keys, k, v, metadata)
        end

        build_picker_for_leaves(root, upstream, sub_picker)

        table.insert(trees, {
            keys = selector.keys,
            root = root,
        })
    end

    return trees
end

local function get_leaf_picker(ctx, header_prefix, tree)
    local keys = tree.keys
    local curr = tree.root
    for _, k in ipairs(keys) do
        local v = ctx.var["http_" .. header_prefix .. k]
        if not curr or not curr.children then
            return nil
        end
        curr = curr.children[v]
    end
    return curr and curr.picker or nil
end

local function get_subset_picker(ctx, header_prefix, trees, fallback_picker)
    for i, tree in ipairs(trees) do
        local subset_picker = get_leaf_picker(ctx, header_prefix, tree)
        if subset_picker then
            return subset_picker
        end
    end
    return fallback_picker
end

function _M.new(up_nodes, upstream)
    local subset = upstream.subset or {}
    local sub_picker = get_picker(subset.type or "roundrobin")

    local nodes = {}
    local metadata_map = {}
    for _, node in ipairs(upstream.nodes) do
        local key = node.host .. ":" .. node.port
        if up_nodes[key] then
            table.insert(nodes, node)
            metadata_map[key] = node.metadata
        end
    end

    local trees = build_subset_trees(up_nodes, upstream, metadata_map, sub_picker)

    local fallback_picker
    local fallback_policy = subset.fallback_policy

    if fallback_policy == "ANY_ENDPOINT" then
        fallback_picker = sub_picker.new(up_nodes, upstream)
    elseif fallback_policy == "DEFAULT_SUBSET" then
        local matched_nodes = discovery_utils.nodes_metadata_match(nodes, subset.default_subset)
        if matched_nodes and #matched_nodes > 0 then
            local matched_up_nodes = {}
            for _, node in ipairs(matched_nodes) do
                local key = node.host .. ":" .. node.port
                matched_up_nodes[key] = up_nodes[key]
            end
            fallback_picker = sub_picker.new(matched_up_nodes, upstream)
        end
    end

    local header_prefix = subset.header_prefix or ""

    return {
        upstream = upstream,

        get = function(ctx)
            local picker = get_subset_picker(ctx, header_prefix, trees, fallback_picker)
            if not picker then
                return nil, "no available subset"
            end
            ctx.subset_picker = picker
            return picker.get(ctx)
        end,

        after_balance = function(ctx, before_retry)
            local picker = ctx.subset_picker
            if not picker then
                core.log.warn("no subset_picker found in ctx during after_balance")
                return
            end
            if picker.after_balance then
                return picker.after_balance(ctx, before_retry)
            end
        end,

        before_retry_next_priority = function(ctx)
            local picker = ctx.subset_picker
            ctx.subset_picker = nil
            if picker and picker.before_retry_next_priority then
                return picker.before_retry_next_priority(ctx)
            end
        end,
    }
end

return _M
