--- Test that the ad blocker blocks a page's requests by its rules.
--
-- @copyright 2026 Ícaro Andrade

local T = {}
local test = require "tests.lib"
local assert = require "luassert"

-- Written before adblock loads, which reads every list in its folder
local rules = [[
! luakit adblock test list
-ad-banner.
tracker.js
/promo*box/
/banner/*/img^
|adtest://start.example^
/end/*.gif|
/pixel^$third-party
-Capital-Ad.
|adtest://plainstart.example/
/anchored.png|
/list?r[]=*adbox
/paren(1)*.png
||ads.example^
||tracker.example/pixel
||cdn.example^$third-party
||[::]^$third-party
@@||ads.example/allowed^
@@-ad-banner.png?allowed
]]

-- Each URI the page loads an image from, and whether it should be blocked
local cases = {
    { "adtest://site.example/x-ad-banner.png", true },
    { "adtest://site.example/x-ad-bannerz.png", false },
    -- tracker.js has no token that every URI it matches has whole
    { "adtest://site.example/mytracker.js", true },
    { "adtest://site.example/promotionalbox/1.png", true },
    { "adtest://site.example/banner/a/b/img/1.png", true },
    { "adtest://start.example/1.png", true },
    { "adtest://site.example/start.example/1.png", false },
    { "adtest://site.example/end/a.gif", true },
    { "adtest://site.example/end/a.gif?x", false },
    { "adtest://other.example/pixel/1.png", true },
    { "adtest://site.example/pixel/1.png", false },
    { "adtest://site.example/x-ad-banner.png?allowed", false },
    -- rules match without regard to case
    { "adtest://site.example/x-capital-ad.png", true },
    -- | anchors hold in rules that are otherwise plain text
    { "adtest://plainstart.example/1.png", true },
    { "adtest://site.example/x?u=adtest://plainstart.example/", false },
    { "adtest://site.example/anchored.png", true },
    { "adtest://site.example/anchored.png?x", false },
    -- ()[] in rules are literal characters
    { "adtest://site.example/list?r[]=x-adbox.png", true },
    { "adtest://site.example/list?r=x-adbox.png", false },
    { "adtest://site.example/paren(1)x.png", true },
    { "adtest://site.example/paren1x.png", false },
    { "adtest://site.example/x.png", false },
}

local page = "adtest://site.example/page.html"
local page_html = [[
<html><body><script>
var results = {};
function load(uris) {
    uris.forEach(function (uri) {
        var img = new Image();
        img.onload = function () { results[uri] = "loaded"; };
        img.onerror = function () { results[uri] = "blocked"; };
        img.src = uri;
    });
}
</script></body></html>
]]

local dir = luakit.data_dir .. "/adblock/"
os.execute(string.format("mkdir -p %q", dir))
local f = assert(io.open(dir .. "test.txt", "w"))
f:write(rules)
f:close()

f = assert(io.open("tests/html/image_css/image.png", "rb"))
local image = f:read("*a")
f:close()

luakit.register_scheme("adtest")
widget.add_signal("create", function (w)
    if w.type == "webview" then
        w:add_signal("scheme-request::adtest", function (_, uri, request)
            if uri == page then
                request:finish(page_html, "text/html")
            else
                request:finish(image, "image/png")
            end
        end)
    end
end)

uris = { page }
require "config.rc"

local adblock = require "adblock"
local window = require "window"
local w = assert(select(2, next(window.bywidget)))

local function eval_js(js)
    w.view:eval_js(js, { callback = test.continue })
    return test.wait(2000)
end

T.test_adblock_blocks_requests_by_rule = function ()
    test.wait_for_idle()
    for _ = 1, 100 do
        if not w.view.is_loading and eval_js("location.href") == page then break end
        test.delay(50)
    end
    assert.is_equal(page, eval_js("location.href"), "the test page didn't load")

    local list = {}
    for _, case in ipairs(cases) do table.insert(list, string.format("%q", case[1])) end
    eval_js("load([" .. table.concat(list, ",") .. "]); true")
    for _ = 1, 100 do
        if eval_js("Object.keys(results).length") == #cases then break end
        test.delay(50)
    end

    for _, case in ipairs(cases) do
        local uri, blocked = case[1], case[2]
        local result = eval_js(string.format("results[%q] || 'unfinished'", uri))
        assert.is_equal(blocked and "blocked" or "loaded", result, uri)
    end
end

-- Domain anchor (||) rules only match http and https URIs, which the test
-- page can't load. So this runs the web module here, with stand-ins for its
-- IPC channel and for a page, and hands it requests itself. It returns false
-- for a request it blocks.
local function web_module_filter()
    local handlers, page_created = {}, nil
    local channel = {
        add_signal = function (_, name, fn) handlers[name] = fn end,
        emit_signal = function () end,
    }
    local env = setmetatable({
        ipc_channel = function () return channel end,
        luakit = {
            web_process_id = 0,
            add_signal = function (name, fn) if name == "page-created" then page_created = fn end end,
        },
    }, { __index = _G })
    local chunk = assert(loadfile("lib/adblock_wm.lua"))
    setfenv(chunk, env)
    chunk()

    handlers.update_rules(channel, nil, adblock.rules)
    for name in pairs(adblock.rules) do handlers.list_set_enabled(channel, nil, name, true) end
    local send_request
    page_created({ add_signal = function (_, _, fn) send_request = fn end })
    return function (page_uri, uri) return send_request({ uri = page_uri }, uri) end
end

T.test_adblock_domain_rules = function ()
    -- A domain whose only rule is a bare ||domain^ gets true, not a table
    local domains = adblock.rules["test.txt"].blacklist.domains
    assert.is_true(domains["ads.example"])
    assert.is_table(domains["cdn.example"])

    local filter = web_module_filter()
    local site = "https://site.example/"
    assert.is_false(filter(site, "https://ads.example/x.js"))
    assert.is_false(filter(site, "https://sub.ads.example/x.js"))
    assert.is_false(filter(site, "http://www.ads.example/x.js"))
    assert.is_nil(filter(site, "https://notads.example/x.js"))
    assert.is_nil(filter(site, "https://ads.example.evil/x.js"))
    assert.is_nil(filter(site, "https://ads.example/allowed/x.js"))
    assert.is_false(filter(site, "https://tracker.example/pixel.gif"))
    assert.is_nil(filter(site, "https://tracker.example/other.gif"))
    assert.is_false(filter(site, "https://cdn.example/lib.js"))
    assert.is_nil(filter("https://cdn.example/", "https://cdn.example/lib.js"))
    -- Brackets in a domain are literal too, as in an IPv6 address
    assert.is_false(filter(site, "http://[::]/x.js"))
    assert.is_nil(filter("http://[::]/", "http://[::]/x.js"))
end

return T

-- vim: et:sw=4:ts=8:sts=4:tw=80
