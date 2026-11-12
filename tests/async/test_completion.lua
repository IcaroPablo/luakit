--- Tests for the input completions module.
--
-- @copyright 2017 Aidan Holm <aidanholm@gmail.com>

local T = {}
local assert = require("luassert")

uris = {"about:blank"}

local test = require("tests.lib")
require "config.rc"

local window = require "window"
local settings = require "settings"
local history = require "history"
local w = assert(select(2, next(window.bywidget)))

-- Types through the window's key handling into the input bar, as a keyboard
-- does
local function type_keys(keys)
    for key in keys:gmatch(utf8.charpattern) do w.win:send_key(key, {}) end
end

-- A navigation starting resets the mode, so the tests wait for the start
-- page to load first; its load starts after this file has run
local start_page_loaded = false
w.view:add_signal("load-status", function (_, status)
    if status == "finished" then start_page_loaded = true end
end)

local function wait_for_start_page()
    test.wait_until(function () return start_page_loaded end)
end

local function as_you_type(on)
    settings.set_setting("completion.as_you_type", on)
    settings.set_setting("completion.as_you_type_delay", 20)
end

T.test_leaving_completion_restores_correct_input_text = function ()
    test.wait_for_idle()
    local input = w.ibar.input

    w:enter_cmd(":tab")
    w:set_mode("completion")
    w.menu:move_up()
    assert.equal(":tab", input.text)

    input.text = ":adbl"
    w.menu:move_down()
    w.menu:move_up()
    assert.equal(":adbl", input.text)
end

T.test_leaving_completion_keeps_the_cursor_position = function ()
    wait_for_start_page()
    w:enter_cmd(":tabopen")
    w:set_mode("completion")
    -- Moving the cursor off the end leaves completion
    w.ibar.input.position = 4
    assert.is_true(w:is_mode("command"))
    assert.equal(4, w.ibar.input.position)
    w:set_mode()
end

T.test_completion_works_with_non_ascii_text = function ()
    wait_for_start_page()
    history.add("http://example.com/", "ação")
    w:enter_cmd(":open açã")
    w:set_mode("completion")
    assert.is_true(w:is_mode("completion"))
    assert.equal("http://example.com/", w.menu:get()[2])
    w:set_mode()
end

T.test_completion_waits_for_tab_by_default = function ()
    wait_for_start_page()
    as_you_type(false)
    w:enter_cmd(":ta")
    type_keys("b")
    test.delay(100)
    assert.equal(":tab", w.ibar.input.text)
    assert.is_true(w:is_mode("command"))
    w:set_mode()
end

T.test_completion_opens_as_you_type = function ()
    wait_for_start_page()
    as_you_type(true)
    local input = w.ibar.input

    -- Text the command line is given isn't typed
    w:enter_cmd(":ta")
    test.delay(100)
    assert.is_true(w:is_mode("command"))

    -- Typing opens the menu once it pauses, with nothing selected
    type_keys("b")
    test.wait_until(function () return w:is_mode("completion") end)
    assert.equal(":tab", input.text)
    assert.is_nil(w.menu:get())

    -- Typing on keeps the menu open
    type_keys("o")
    test.delay(100)
    assert.is_true(w:is_mode("completion"))
    assert.equal(":tabo", input.text)
    assert.is_nil(w.menu:get())

    -- <Tab> and <Shift-Tab> move through the items, and back to what was typed
    w.win:send_key("Tab", {})
    local first = w.menu:get()
    assert.is_table(first)
    assert.equal(first.text, input.text)
    w.win:send_key("Tab", { "shift" })
    assert.is_nil(w.menu:get())
    assert.equal(":tabo", input.text)

    -- <Escape> closes the menu, keeping the text
    w.win:send_key("Escape", {})
    assert.is_true(w:is_mode("command"))
    assert.equal(":tabo", input.text)

    w:set_mode()
    as_you_type(false)
end

T.test_tab_selects_completions_typed_before_the_menu_updated = function ()
    wait_for_start_page()
    as_you_type(true)
    settings.set_setting("completion.as_you_type_delay", 5000)
    w:enter_cmd(":ta")
    w:set_mode("completion", { as_you_type = true })
    -- <Tab> before the typing pause brings the menu up to date first
    type_keys("bo")
    w.win:send_key("Tab", {})
    assert.matches("^:tabo", w.ibar.input.text)
    w:set_mode()
    as_you_type(false)
end

return T

-- vim: et:sw=4:ts=8:sts=4:tw=80
