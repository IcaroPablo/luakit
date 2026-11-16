--- Test the window.close_with_last_tab setting.

local assert = require "luassert"
local test = require "tests.lib"

uris = {"about:blank"}
require "config.rc"

local settings = require "settings"
local window = require "window"

local T = {}

local function with_close_with_last_tab(func)
    settings.set_setting("window.close_with_last_tab", true)
    local ok, err = pcall(func)
    settings.set_setting("window.close_with_last_tab", false)
    assert(ok, err)
end

T.test_closing_the_last_tab_closes_the_window = function ()
    test.wait_for_idle()
    with_close_with_last_tab(function ()
        local w = window.new({"about:blank"})
        -- the status bar's tab count updates once luakit is idle
        test.wait_for_idle()
        w:close_tab()
        -- close_win clears the fields of a window that closed
        assert.is_nil(w.tabs)
        -- and luakit stays, for the test's own window
        assert.is_not_nil(next(window.bywidget))
    end)
end

T.test_a_window_that_refuses_to_close_keeps_a_blank_tab = function ()
    test.wait_for_idle()
    local w = assert(select(2, next(window.bywidget)))
    while w.tabs:count() > 1 do w:close_tab() end
    -- the last window asks whether luakit may quit, and this says no
    local function refuse() return "testing" end
    luakit.add_signal("can-close", refuse)
    with_close_with_last_tab(function () w:close_tab() end)
    luakit.remove_signal("can-close", refuse)
    assert.is_not_nil(w.tabs)
    assert.equal(1, w.tabs:count())
end

return T

-- vim: et:sw=4:ts=8:sts=4:tw=80
