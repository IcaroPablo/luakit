-- Simple URI-based content filter - web module.
--
-- @submodule adblock_wm
-- @copyright 2016 Aidan Holm <aidanholm@gmail.com>
-- @author Aidan Holm <aidanholm@gmail.com>

local ui = ipc_channel("adblock_wm")
local lousy = require "lousy"

local enabled = true
local rules = {}
local enabled_rules = {}
local page_whitelist = {}

ui:add_signal("enable", function(_, _, e) enabled = e end)
ui:add_signal("update_rules", function(_, _, r)
    rules = r
    ui:emit_signal("rules_updated", luakit.web_process_id)
end)
ui:add_signal("update_page_whitelist", function(_, _, wl)
    page_whitelist = wl
    ui:emit_signal("rules_updated", luakit.web_process_id)
end)
ui:add_signal("list_set_enabled", function(_, _, list, enable)
    enabled_rules[list] = enable and rules[list] or nil
end)

local function domain_match(domain, opts)
    local res = false
    local cnt = 0
    local dlist = opts["domain"]
    if dlist then
        for _, s in pairs(dlist) do
            if string.len(s) > 0 then
                if string.sub(s, 1, 1) == "~" then
                    if domain == string.sub(s, 2) then return false end
                else
                    cnt = cnt + 1
                    if not res and domain == s then res = true end
                end
            end
        end
    end
    return cnt == 0 or res
end

local function third_party_match(domain1, domain2, opts)
    local thp = opts["third-party"]
    if thp ~= nil then
        if thp == true then return domain1 ~= domain2 end
        return domain1 == domain2
    end
    return true
end

local function domain_from_uri(uri)
    local domain = (uri and string.match(string.lower(uri), "^%a+://([^/]*)/?"))
    -- Strip leading www. www2. etc
    domain = string.match(domain or "", "^www%d?%.(.+)") or domain
    return domain or ""
end

-- Whether a rule's options let it apply to this request; true is a rule
-- without options
local function opts_match(opts, page_domain, uri_domain)
    return opts == true
        or (third_party_match(page_domain, uri_domain, opts) and domain_match(page_domain, opts))
end

local match_filed = function (filed, plain, uri, page_domain, uri_domain)
    if not filed then return end
    for pattern, opts in pairs(filed) do
        if opts_match(opts, page_domain, uri_domain) then
            if plain then
                if string.find(uri, pattern, 1, true) then return true, pattern end
            elseif string.match(uri, pattern) then
                return true, pattern
            end
        end
    end
end

-- What "^" becomes in a pattern, as in the adblock module. A domain whose
-- only rule is the bare ||domain^ is filed as true instead of a table.
local separator = "[^%w%-%.%%]"
local bare_domain_rule = { [separator] = true }

-- Domain anchor rules are filed by domain with only the part of their pattern
-- after it. The domain goes back in front, at the start of the host or after a
-- dot in it. Those patterns are built the first time a request reaches the
-- domain, and kept: few of the rules' domains are ever reached.
local domain_patterns = setmetatable({}, { __mode = "k" })

local match_domain = function (filed, domain, uri, page_domain, uri_domain)
    if not filed then return end
    -- A bare rule's patterns depend only on its domain
    local key = filed == true and domain or filed
    local patterns = domain_patterns[key]
    if not patterns then
        local escaped = string.gsub(domain, "([%%%.%+%-%?])", "%%%1")
        patterns = {}
        for rest, opts in pairs(filed == true and bare_domain_rule or filed) do
            table.insert(patterns, {
                "^https?://" .. escaped .. rest, "^https?://[^/]*%." .. escaped .. rest, opts })
        end
        domain_patterns[key] = patterns
    end
    for _, p in ipairs(patterns) do
        if opts_match(p[3], page_domain, uri_domain) then
            if string.match(uri, p[1]) or string.match(uri, p[2]) then
                return true, p[1]
            end
        end
    end
end

-- The adblock module files a list's rules by domain and by token; a URI can
-- only match the rules filed under its domains and tokens
local match_list = function (list, uri, uri_domains, uri_tokens, page_domain, uri_domain)
    local domains, plain, patterns = list.domains or {}, list.plain or {}, list.patterns or {}

    for domain in pairs(uri_domains) do
        local found, pattern = match_domain(domains[domain], domain, uri, page_domain, uri_domain)
        if found then return true, pattern end
    end

    for token in pairs(uri_tokens) do
        local found, pattern = match_filed(plain[token], true, uri, page_domain, uri_domain)
        if found then return true, pattern end
        found, pattern = match_filed(patterns[token], false, uri, page_domain, uri_domain)
        if found then return true, pattern end
    end
end

-- Tests URI against user-defined filter functions, then whitelist, then blacklist
local match = function (src, dst)
    -- Always allow data: URIs
    if string.sub(dst, 1, 5) == "data:" then
        msg.debug("allowing data URI")
        return
    end

    -- Matching is not case sensitive
    dst = string.lower(dst)

    local src_domain = domain_from_uri(src)
    local dst_domain = domain_from_uri(dst)

    -- Build a table of all domains this URI falls under
    local dst_domains = {}
    do
        local d = dst_domain
        while d do
            dst_domains[d] = true
            d = string.match(d, "%.(.+)")
        end
    end

    -- Its runs of letters and digits, and "" for the rules without a token
    local dst_tokens = { [""] = true }
    for token in string.gmatch(dst, "[a-z0-9]+") do
        dst_tokens[token] = true
    end

    -- Test against each list's whitelist rules first
    for _, list in pairs(enabled_rules) do
        local found, pattern = match_list(list.whitelist, dst, dst_domains, dst_tokens, src_domain, dst_domain)
        if found then
            msg.debug("allowing request as pattern %q matched to uri %s", pattern, dst)
            return true
        end
    end

    -- Test against each list's blacklist rules
    for _, list in pairs(enabled_rules) do
        local found, pattern = match_list(list.blacklist, dst, dst_domains, dst_tokens, src_domain, dst_domain)
        if found then
            msg.debug("blocking request as pattern %q matched to uri %s", pattern, dst)
            return false
        end
    end
end


-- Direct requests to match function
local filter = function (src, dst)
    -- Don't adblock on local files
    local file_uri = src and string.sub(src, 1, 7) == "file://"

    if enabled and not file_uri then
        return match(src, dst)
    end
end

luakit.add_signal("page-created", function(page)
    page:add_signal("send-request", function(p, uri)
        -- Prevent adblock-blocked: pages from being blocked themselves
        if uri:match("^adblock%-blocked:") then return end

        local allow = filter(p.uri, uri)
        if allow == false and p.uri == uri then
            if not lousy.util.table.hasitem(page_whitelist, lousy.uri.parse(uri).host) then
                return "adblock-blocked:" .. uri
            end
        else
            if allow == false then return false end
        end
    end)
end)

-- vim: et:sw=4:ts=8:sts=4:tw=80
