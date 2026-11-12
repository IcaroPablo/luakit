--- Tests for the input completions module.
--
-- @copyright 2017 Aidan Holm <aidanholm@gmail.com>

local T = {}
local assert = require("luassert")

uris = {"about:blank"}

local test = require("tests.lib")
require "config.rc"

local window = require "window"
local history = require "history"
local w = assert(select(2, next(window.bywidget)))

-- A navigation starting resets the mode, so the tests wait for the start
-- page to load first; its load starts after this file has run
local start_page_loaded = false
w.view:add_signal("load-status", function (_, status)
    if status == "finished" then start_page_loaded = true end
end)

local function wait_for_start_page()
    test.wait_until(function () return start_page_loaded end)
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

return T

-- vim: et:sw=4:ts=8:sts=4:tw=80
