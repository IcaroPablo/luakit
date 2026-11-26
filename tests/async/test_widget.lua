--- Test widget library.
--
-- @copyright 2017 Aidan Holm <aidanholm@gmail.com>

local assert = require "luassert"

local T = {}

T.test_widget_of_invalid_type_fails = function ()
    assert.has_error(function () widget{type="no_such_widget_type"} end)
    assert.has_error(function () widget{} end)
end

T.test_bin_widget_set_child = function ()
    local bin = widget{type="window"}
    local child1 = widget{type="entry"}
    local child2 = widget{type="label"}

    assert.is_nil(bin.child)
    bin.child = child1
    assert.is_equal(bin.child, child1)
    bin.child = child2
    assert.is_equal(bin.child, child2)
    bin.child = nil
    assert.is_nil(bin.child)
end

T.test_webview_widget_privacy = function ()
    local v = widget{type="webview"}
    assert.is_false(v.private)
    v = widget{type="webview", private=false}
    assert.is_false(v.private)
    v = widget{type="webview", private=true}
    assert.is_true(v.private)
end

T.test_webview_widget_is_muted = function ()
    local v = widget{type="webview"}
    assert.is_false(v.is_muted)
    v.is_muted = true
    assert.is_true(v.is_muted)
    v.is_muted = false
    assert.is_false(v.is_muted)
end

T.test_webview_widget_features = function ()
    local v = widget{type="webview"}
    assert.is_nil(v:get_feature("NoSuchFeature"))
    assert.is_false(v:set_feature("NoSuchFeature", true))

    -- WebKitGTK 2.44 renamed PdfJSViewer to PDFJSViewer
    local pdfjs = v:get_feature("PDFJSViewer") ~= nil and "PDFJSViewer"
        or "PdfJSViewer"
    assert.is_true(v:set_feature(pdfjs, false))
    assert.is_false(v:get_feature(pdfjs))
    assert.is_true(v:set_feature(pdfjs, true))
    assert.is_true(v:get_feature(pdfjs))

    v:set_pdfjs(false)
    assert.is_false(v:get_feature(pdfjs))
    v:set_pdfjs(true)
    assert.is_true(v:get_feature(pdfjs))
end

return T

-- vim: et:sw=4:ts=8:sts=4:tw=80
