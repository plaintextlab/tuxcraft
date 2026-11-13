-- tuxcraft: put every local file mpv plays on the recent-files list (Super+Z, tux-recent).
local utils = require "mp.utils"

mp.register_event("file-loaded", function()
    local path = mp.get_property("path")
    if not path or path:find("^%a[%w+.-]*://") then return end   -- streams and URLs: no
    if path:sub(1, 1) ~= "/" then
        path = utils.join_path(mp.get_property("working-directory") or "", path)
    end
    mp.command_native_async({ name = "subprocess", args = { "tux-recent", "add", path },
                              playback_only = false }, function() end)
end)
