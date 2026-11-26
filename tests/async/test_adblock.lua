--- Test that the ad blocker blocks a page's requests by its rules.
--
-- @copyright 2026 Ícaro Andrade

local T = {}
local test = require "tests.lib"
local assert = require "luassert"

-- Written before adblock loads, which reads every list in its folder
local rules = [[
! luakit adblock test list
/to-be-removed/
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
local function write_rules(text)
    local f = assert(io.open(dir .. "test.txt", "w"))
    f:write(text)
    f:close()
end
write_rules(rules)

local f = assert(io.open("tests/html/image_css/image.png", "rb"))
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

local function wait_for_page()
    test.wait_for_idle()
    for _ = 1, 100 do
        if not w.view.is_loading and eval_js("location.href") == page then return end
        test.delay(50)
    end
    assert.is_equal(page, eval_js("location.href"), "the test page didn't load")
end

-- Loads an image from uri, and returns "loaded" or "blocked"
local function load_image(uri)
    eval_js(string.format("load([%q]); true", uri))
    for _ = 1, 40 do
        local result = eval_js(string.format("results[%q] || ''", uri))
        if result ~= "" then return result end
        test.delay(25)
    end
end

T.test_adblock_blocks_requests_by_rule = function ()
    wait_for_page()

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

T.test_adblock_reload_reaches_open_pages = function ()
    wait_for_page()
    assert.is_equal("blocked", load_image("adtest://site.example/to-be-removed/0.png"))
    assert.is_equal("loaded", load_image("adtest://site.example/reloaded-rule/0.png"))

    write_rules((rules:gsub("/to%-be%-removed/\n", "")) .. "/reloaded-rule/\n")
    adblock.load(true)

    -- The new rules reach the page's web process over luakit's IPC, which
    -- eval_js doesn't wait for
    local added, removed
    for n = 1, 40 do
        added = load_image("adtest://site.example/reloaded-rule/" .. n .. ".png")
        removed = load_image("adtest://site.example/to-be-removed/" .. n .. ".png")
        if added == "blocked" and removed == "loaded" then break end
        test.delay(50)
    end
    assert.is_equal("blocked", added, "a rule added by a reload doesn't reach an open page")
    assert.is_equal("loaded", removed, "a rule removed by a reload still blocks on an open page")
end

return T

-- vim: et:sw=4:ts=8:sts=4:tw=80
