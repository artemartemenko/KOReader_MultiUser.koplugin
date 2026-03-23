--[[
MultiUser plugin for KOReader
File: koreader/plugins/MultiUser.koplugin/main.lua
--]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Widget          = require("ui/widget/widget")
local InputContainer  = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer  = require("ui/widget/container/framecontainer")
local OverlapGroup    = require("ui/widget/overlapgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local TextWidget      = require("ui/widget/textwidget")
local Font            = require("ui/font")
local GestureRange    = require("ui/gesturerange")
local Geom            = require("ui/geometry")
local Size            = require("ui/size")
local Blitbuffer      = require("ffi/blitbuffer")
local Screen          = require("device").screen
local DataStorage     = require("datastorage")
local UIManager       = require("ui/uimanager")
local lfs             = require("libs/libkoreader-lfs")
local logger          = require("logger")
local util            = require("util")
local ffiUtil         = require("ffi/util")
local _               = require("gettext")
local T               = ffiUtil.template

local FORBIDDEN_CHARS = '[/\\:*?"<>|%z]'

local PathChooser = require("ui/widget/pathchooser")

local UnlockAvatarPathChooser = PathChooser:extend{}

function UnlockAvatarPathChooser:onMenuSelect(item)
    local path = item.path
    if path:sub(-2, -1) == "/." then
        return PathChooser.onMenuSelect(self, item)
    end
    path = ffiUtil.realpath(path)
    if not path then
        self:changeToPath("/")
        return true
    end
    local attr = lfs.attributes(path)
    if not attr then
        self:changeToPath("/")
        return true
    end
    if attr.mode == "file" and self.select_file then
        return self:onMenuHold(item)
    end
    return PathChooser.onMenuSelect(self, item)
end

local function fullScreenThemedBackdrop(screen_size)
    return FrameContainer:new{
        width = screen_size.w,
        height = screen_size.h,
        dimen = screen_size,
        radius = 0,
        bordersize = 0,
        padding = 0,
        margin = 0,
        allow_mirroring = false,
        background = Blitbuffer.COLOR_WHITE,
        Widget:new{ dimen = Geom:new{ w = 1, h = 1 } },
    }
end

local function profilePickerRowLengths(n)
    if n <= 0 then
        return {}
    elseif n <= 3 then
        return { n }
    elseif n == 4 then
        return { 2, 2 }
    else
        local r1 = math.floor(n / 2)
        return { r1, n - r1 }
    end
end

local RoundedImageWidget = Widget:extend{}

function RoundedImageWidget:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function RoundedImageWidget:getSize()
    return self.dimen
end

function RoundedImageWidget:paintTo(bb, x, y)
    local ImageWidget = require("ui/widget/imagewidget")
    if not self._img_widget then
        self._img_widget = ImageWidget:new{
            file = self.file,
            width = self.width,
            height = self.height,
            scale_factor = 0,
            alpha = true,
        }
    end
    self._img_widget:paintTo(bb, x, y)

    local r = self.radius
    local bg = self.bg_color or Blitbuffer.COLOR_WHITE
    local w, h = self.width, self.height

    if r and r > 0 then
        for dy = 0, r - 1 do
            for dx = 0, r - 1 do
                local dist = math.sqrt((r - 1 - dx)^2 + (r - 1 - dy)^2)
                if dist > r - 0.5 then
                    bb:setPixel(x + dx,         y + dy,         bg)
                    bb:setPixel(x + w - 1 - dx, y + dy,         bg)
                    bb:setPixel(x + dx,         y + h - 1 - dy, bg)
                    bb:setPixel(x + w - 1 - dx, y + h - 1 - dy, bg)
                end
            end
        end
    end

    local bw = self.border_width or 0
    if bw > 0 then
        local bc = self.border_color or Blitbuffer.COLOR_BLACK
        bb:paintBorder(x, y, w, h, bw, bc, r)
    end
end

local ProfilePickTile = InputContainer:extend{}

function ProfilePickTile:init()
    local border_w = self.highlight_current and Size.border.default or Size.border.thin
    local inner_w = math.max(1, self.cell_w - 2 * border_w)
    local inner_h = math.max(1, self.rect_h - 2 * border_w)
    local avatar = self.avatar_file
    local has_avatar = false
    if type(avatar) == "string" and avatar ~= "" and lfs.attributes(avatar, "mode") == "file" then
        local DocumentRegistry = require("document/documentregistry")
        if DocumentRegistry:isImageFile(avatar) then
            has_avatar = true
        end
    end

    local rect
    if has_avatar then
        rect = RoundedImageWidget:new{
            file = avatar,
            width = self.cell_w,
            height = self.rect_h,
            radius = Size.radius.button,
            bg_color = Blitbuffer.COLOR_WHITE,
            border_width = border_w + 1,
            border_color = Blitbuffer.COLOR_BLACK,
        }
    else
        rect = FrameContainer:new{
            margin = 0,
            padding = 0,
            bordersize = border_w,
            background = self.rect_bg,
            invert = false,
            radius = Size.radius.button,
            CenterContainer:new{
                dimen = Geom:new{ w = inner_w, h = inner_h },
                WidgetContainer:new{ dimen = Geom:new{ w = 1, h = 1 } },
            },
        }
    end

    local label = TextWidget:new{
        text = self.label_text,
        face = Font:getFace("smallinfofont", 20),
        bold = self.bold_label,
        max_width = self.cell_w,
    }
    local label_h = label:getSize().h
    local vg = VerticalGroup:new{
        align = "center",
        rect,
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        CenterContainer:new{
            dimen = Geom:new{ w = self.cell_w, h = label_h },
            label,
        },
    }
    self[1] = vg
    self.ges_events = {
        TapProfilePick = {
            GestureRange:new{
                ges = "tap",
                range = function()
                    return self.dimen
                end,
            },
        },
    }
end

function ProfilePickTile:onTapProfilePick()
    if self.tap_callback then
        self.tap_callback()
    end
    return true
end

local function loadLuaTable(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    local fn = load("return " .. content)
    if not fn then return nil end
    local ok, result = pcall(fn)
    return ok and result or nil
end

local function isStringArray(t)
    if type(t) ~= "table" then
        return false
    end
    local n = #t
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
            return false
        end
    end
    for i = 1, n do
        if type(t[i]) ~= "string" then
            return false
        end
    end
    return true
end

local function saveLuaTable(path, tbl)
    local f = io.open(path, "w")
    if not f then return false end
    f:write("{\n")
    for k, v in pairs(tbl) do
        if type(v) == "string" then
            f:write(string.format('    [%q] = %q,\n', k, v))
        elseif type(v) == "boolean" then
            f:write(string.format('    [%q] = %s,\n', k, tostring(v)))
        elseif type(v) == "number" then
            f:write(string.format('    [%q] = %s,\n', k, tostring(v)))
        elseif type(v) == "table" and isStringArray(v) then
            f:write(string.format("    [%q] = {\n", k))
            for i = 1, #v do
                f:write(string.format("        %q,\n", v[i]))
            end
            f:write("    },\n")
        end
    end
    f:write("}\n")
    f:close()
    return true
end

local function mkdir_p(path)
    if lfs.attributes(path, "mode") == "directory" then return true end
    local parts = {}
    for part in path:gmatch("[^/]+") do table.insert(parts, part) end
    local current = path:sub(1,1) == "/" and "/" or ""
    for _, part in ipairs(parts) do
        current = current .. part .. "/"
        if lfs.attributes(current, "mode") ~= "directory" then
            lfs.mkdir(current)
        end
    end
    return lfs.attributes(path, "mode") == "directory"
end

local function rmdir_r(path)
    if lfs.attributes(path, "mode") ~= "directory" then
        os.remove(path); return
    end
    for entry in lfs.dir(path) do
        if entry ~= "." and entry ~= ".." then rmdir_r(path.."/"..entry) end
    end
    lfs.rmdir(path)
end

local MultiUser = WidgetContainer:extend{
    name = "multiuser",
}

local MULTIUSER_SWITCH_MENU_ID = "multiuser_switch_user"
local PROFILE_MENU_ID_PREFIX = "multiuser_sw_"

function MultiUser:purgeStaleProfileSwitchMenuItems(menu_items)
    if type(menu_items) ~= "table" then
        return
    end
    local to_remove = {}
    for k, _ in pairs(menu_items) do
        if type(k) == "string"
            and (k == "multiuser_quick_switch"
                or k == MULTIUSER_SWITCH_MENU_ID
                or k:sub(1, #PROFILE_MENU_ID_PREFIX) == PROFILE_MENU_ID_PREFIX) then
            table.insert(to_remove, k)
        end
    end
    for _, k in ipairs(to_remove) do
        menu_items[k] = nil
    end
end

function MultiUser:syncSwitchUserMenuItemOrder()
    local function sync_order(order_tbl)
        if type(order_tbl) ~= "table" or type(order_tbl.main) ~= "table" then
            return
        end
        local m = order_tbl.main
        for idx = #m, 1, -1 do
            local id = m[idx]
            if id == MULTIUSER_SWITCH_MENU_ID
                or id == "multiuser_quick_switch"
                or (type(id) == "string" and id:sub(1, #PROFILE_MENU_ID_PREFIX) == PROFILE_MENU_ID_PREFIX) then
                table.remove(m, idx)
            end
        end
        local insert_at
        for i, id in ipairs(m) do
            if id == "exit_menu" then
                insert_at = i
                break
            end
        end
        if not insert_at then
            for i, id in ipairs(m) do
                if id == "history" then
                    insert_at = i + 1
                    break
                end
            end
        end
        if insert_at then
            table.insert(m, insert_at, MULTIUSER_SWITCH_MENU_ID)
        end
    end
    local ok_r, reader_order = pcall(require, "ui/elements/reader_menu_order")
    if ok_r and reader_order then
        sync_order(reader_order)
    end
    local ok_f, fm_order = pcall(require, "ui/elements/filemanager_menu_order")
    if ok_f and fm_order then
        sync_order(fm_order)
    end
end

function MultiUser:getOtherProfileWhenExactlyTwo()
    local profiles = self:getProfileNames()
    if #profiles ~= 2 then
        return nil
    end
    local current = self:getCurrentUser()
    for _, pname in ipairs(profiles) do
        if pname ~= current then
            return pname
        end
    end
    return nil
end

function MultiUser:showUserPickerDialogFromMenu()
    local profiles = self:getProfileNames()
    local n = #profiles
    if n <= 1 then
        UIManager:show(require("ui/widget/infomessage"):new{
            text = _("Only one user profile."),
            timeout = 2,
        })
        return
    end
    if n == 2 then
        local other = self:getOtherProfileWhenExactlyTwo()
        if other then
            self:switchToProfile(other)
        end
        return
    end
    if self._user_picker then
        return
    end
    UIManager:nextTick(function()
        if self._user_picker then
            return
        end
        self:showUserPickerDialog()
    end)
end

function MultiUser:init()
    local ok, err = pcall(function()
        self.ui.menu:registerToMainMenu(self)
    end)
    if not ok then logger.err("MultiUser: init failed:", tostring(err)) end
    UIManager:scheduleIn(0, function()
        self:applyCurrentProfileFrontlight()
    end)
end

function MultiUser:getUsersFile()
    if MULTIUSER_USERS_FILE then return MULTIUSER_USERS_FILE end
    return DataStorage:getDataDir() .. "/users.lua"
end

function MultiUser:getBaseDir()
    if MULTIUSER_BASE_DIR then return MULTIUSER_BASE_DIR end
    return DataStorage:getDataDir()
end

function MultiUser:getCurrentUser()
    return MULTIUSER_CURRENT or "default"
end

function MultiUser:saveCurrentProfileFrontlight()
    local Device = require("device")
    if not Device:hasFrontlight() then
        return
    end
    local powerd = Device:getPowerDevice()
    if not powerd or not powerd.fl_min or not powerd.fl_max then
        return
    end
    local fl_min, fl_max = powerd.fl_min, powerd.fl_max
    if fl_max <= fl_min then
        return
    end
    local intensity = powerd.fl_intensity
    if type(intensity) ~= "number" then
        return
    end
    local pct = (intensity - fl_min) / (fl_max - fl_min) * 100
    pct = math.max(0, math.min(100, pct))
    local on = powerd:isFrontlightOn()
    local pname = self:getCurrentUser()
    local users_data = self:loadUsers()
    users_data["mu_fl_" .. pname .. "_intensity_pct"] = pct
    users_data["mu_fl_" .. pname .. "_on"] = on
    if Device:hasNaturalLight() then
        local w = powerd:frontlightWarmth()
        if type(w) ~= "number" then
            w = 0
        end
        users_data["mu_fl_" .. pname .. "_warmth"] = math.max(0, math.min(100, w))
    else
        users_data["mu_fl_" .. pname .. "_warmth"] = nil
    end
    self:saveUsers(users_data)
end

function MultiUser:applyCurrentProfileFrontlight()
    local Device = require("device")
    if not Device:hasFrontlight() then
        return
    end
    local powerd = Device:getPowerDevice()
    if not powerd or not powerd.fl_min or not powerd.fl_max then
        return
    end
    local fl_min, fl_max = powerd.fl_min, powerd.fl_max
    if fl_max <= fl_min then
        return
    end
    local pname = self:getCurrentUser()
    local users_data = self:loadUsers()
    local pctp = users_data["mu_fl_" .. pname .. "_intensity_pct"]
    local on_saved = users_data["mu_fl_" .. pname .. "_on"]
    if type(pctp) ~= "number" and type(on_saved) ~= "boolean" then
        return
    end
    local Math = require("optmath")
    local pct = type(pctp) == "number" and math.max(0, math.min(100, pctp)) or 50
    local intensity = Math.round(fl_min + pct / 100 * (fl_max - fl_min))
    intensity = powerd:normalizeIntensity(intensity)

    self._mu_fl_applying = true
    local ok, err = pcall(function()
        if Device:hasNaturalLight() then
            local w = users_data["mu_fl_" .. pname .. "_warmth"]
            if type(w) == "number" then
                powerd:setWarmth(math.max(0, math.min(100, w)), true)
            end
        end
        powerd:setIntensity(intensity)
        if type(on_saved) == "boolean" then
            if on_saved then
                powerd:turnOnFrontlight()
            else
                powerd:turnOffFrontlight()
            end
        end
    end)
    self._mu_fl_applying = false
    if not ok then
        logger.err("MultiUser: applyCurrentProfileFrontlight failed:", err)
    end
end

function MultiUser:onFrontlightStateChanged()
    if self._mu_fl_applying then
        return
    end
    self:saveCurrentProfileFrontlight()
end

function MultiUser:onSuspend()
    self:saveUnlockSetting("last_lock_time", os.time())
end

function MultiUser:onResume()
    UIManager:scheduleIn(0, function()
        self:applyCurrentProfileFrontlight()
    end)
end

function MultiUser:getDisplayName(name)
    if name == "default" then
        local users_data = self:loadUsers()
        return users_data.default_alias or "default"
    end
    return name
end

function MultiUser:loadUsers()
    return loadLuaTable(self:getUsersFile()) or { current = "default" }
end

function MultiUser:saveUsers(data)
    return saveLuaTable(self:getUsersFile(), data)
end

function MultiUser:getProfileNames()
    local users_dir = self:getBaseDir() .. "/users"
    local on_disk = {}
    local custom_names = {}
    if lfs.attributes(users_dir, "mode") == "directory" then
        for entry in lfs.dir(users_dir) do
            if entry ~= "." and entry ~= ".." then
                if lfs.attributes(users_dir .. "/" .. entry, "mode") == "directory" and entry ~= "default" then
                    on_disk[entry] = true
                    table.insert(custom_names, entry)
                end
            end
        end
    end

    local users_data = self:loadUsers()
    local po = users_data.profile_order

    if not isStringArray(po) then
        table.sort(custom_names, function(a, b)
            local ma = lfs.attributes(users_dir .. "/" .. a, "modification") or 0
            local mb = lfs.attributes(users_dir .. "/" .. b, "modification") or 0
            if ma ~= mb then
                return ma < mb
            end
            return a:lower() < b:lower()
        end)
        po = custom_names
        users_data.profile_order = po
        self:saveUsers(users_data)
    else
        local seen = {}
        for _, n in ipairs(po) do
            seen[n] = true
        end
        local added = false
        for _, n in ipairs(custom_names) do
            if not seen[n] then
                table.insert(po, n)
                seen[n] = true
                added = true
            end
        end
        if added then
            self:saveUsers(users_data)
        end
    end

    local ordered = { "default" }
    local used = { default = true }
    po = users_data.profile_order
    for _, n in ipairs(po) do
        if on_disk[n] and not used[n] then
            table.insert(ordered, n)
            used[n] = true
        end
    end
    for _, n in ipairs(custom_names) do
        if on_disk[n] and not used[n] then
            table.insert(ordered, n)
            used[n] = true
        end
    end
    return ordered
end

function MultiUser:switchToProfile(name)
    self:saveCurrentProfileFrontlight()
    local users_data = self:loadUsers()
    users_data.current = name
    self:saveUsers(users_data)
    UIManager:flushSettings()
    UIManager:restartKOReader()
end

function MultiUser:createProfile(name)
    local profile_dir = self:getBaseDir() .. "/users/" .. name
    if lfs.attributes(profile_dir, "mode") == "directory" then
        return false, _("A profile with this name already exists.")
    end
    if not mkdir_p(profile_dir) then
        return false, _("Could not create profile directory.")
    end
    for _, sub in ipairs({"settings","docsettings","history","cache","plugins","patches","screenshots"}) do
        mkdir_p(profile_dir.."/"..sub)
    end
    local users_data = self:loadUsers()
    local po = users_data.profile_order
    if not isStringArray(po) then
        po = {}
        users_data.profile_order = po
    end
    local dup
    for _, n in ipairs(po) do
        if n == name then
            dup = true
            break
        end
    end
    if not dup then
        table.insert(po, name)
    end
    self:saveUsers(users_data)
    return true
end

function MultiUser:renameProfile(old_name, new_name)
    if old_name ~= "default" then
        return false, _("Only the default profile can be renamed.")
    end
    if self:getCurrentUser() ~= "default" then
        return false, _("Only the default user can rename the default profile.")
    end
    local users_data = self:loadUsers()
    users_data.default_alias = new_name
    self:saveUsers(users_data)
    return true, true
end
function MultiUser:deleteProfile(name)
    if name == "default" then return false, _("The default profile cannot be deleted.") end
    if name == self:getCurrentUser() then return false, _("Cannot delete the active profile.") end
    local profile_dir = self:getBaseDir().."/users/"..name
    if lfs.attributes(profile_dir, "mode") ~= "directory" then return false, _("Profile not found.") end
    rmdir_r(profile_dir)
    local users_data = self:loadUsers()
    users_data["unlock_avatar_" .. name] = nil
    users_data["mu_fl_" .. name .. "_intensity_pct"] = nil
    users_data["mu_fl_" .. name .. "_warmth"] = nil
    users_data["mu_fl_" .. name .. "_on"] = nil
    local po = users_data.profile_order
    if isStringArray(po) then
        for i = #po, 1, -1 do
            if po[i] == name then
                table.remove(po, i)
            end
        end
    end
    self:saveUsers(users_data)
    return true
end

function MultiUser:addToMainMenu(menu_items)
    self:purgeStaleProfileSwitchMenuItems(menu_items)
    self:syncSwitchUserMenuItemOrder()

    menu_items[MULTIUSER_SWITCH_MENU_ID] = {
        sorting_hint = "main",
        text_func = function()
            local other = self:getOtherProfileWhenExactlyTwo()
            if other then
                return T(_("Switch to %1"), self:getDisplayName(other))
            end
            return _("Switch user…")
        end,
        enabled_func = function()
            return #self:getProfileNames() > 1
        end,
        callback = function()
            self:showUserPickerDialogFromMenu()
        end,
    }

    menu_items.multiuser = {
        sorting_hint = "tools",
        text_func = function()
            return T(_("Users  [%1]"), self:getDisplayName(self:getCurrentUser()))
        end,
        sub_item_table_func = function()
            return self:getSubMenuItems()
        end,
    }
end

function MultiUser:getSubMenuItems()
    local current = self:getCurrentUser()
    local profiles = self:getProfileNames()
    local items = {}

    for _, name in ipairs(profiles) do
        local is_current = (name == current)
        local pname = name
        table.insert(items, {
            text_func = function()
                return (is_current and "✓  " or "    ") .. self:getDisplayName(pname)
            end,
            bold = is_current,
            keep_menu_open = true,
            sub_item_table_func = function()
                return self:getProfileSubMenu(pname, is_current)
            end,
        })
    end

    table.insert(items, {
        text = _("New profile…"),
        keep_menu_open = true,
        separator = true,
        callback = function(tm)
            self:showCreateProfileDialog(function()
                tm.item_table = self:getSubMenuItems()
                tm.page = 1
                tm:updateItems()
            end)
        end,
    })

    table.insert(items, {
        text = _("Settings…"),
        keep_menu_open = true,
        sub_item_table_func = function()
            return self:getSettingsSubMenu()
        end,
    })

    return items
end

function MultiUser:getProfileSubMenu(pname, is_current)
    local items = {}

    if not is_current then
        table.insert(items, {
            text = T(_("Switch to \"%1\""), self:getDisplayName(pname)),
            callback = function()
                self:switchToProfile(pname)
            end,
            separator = true,
        })
    end

    if pname == "default" and self:getCurrentUser() == "default" then
        table.insert(items, {
            text = T(_("Rename \"%1\"…"), self:getDisplayName(pname)),
            keep_menu_open = true,
            callback = function(tm)
                self:showRenameDialog(pname, function(new_name)
                    local ok, no_restart = self:renameProfile(pname, new_name)
                    local IM = require("ui/widget/infomessage")
                    if ok then
                        UIManager:show(IM:new{
                            text = T(_("Renamed to \"%1\"."), new_name),
                            timeout = 2,
                        })
                        if tm then
                            tm.item_table = self:getSubMenuItems()
                            tm.page = 1
                            tm:updateItems()
                        end
                    else
                        UIManager:show(IM:new{ text = no_restart, timeout = 3 })
                    end
                end)
            end,
        })
    end

    table.insert(items, {
        text_func = function()
            return T(_("Avatar for %1…"), self:getDisplayName(pname))
        end,
        keep_menu_open = true,
        callback = function(tm)
            self:showUnlockAvatarDialog(pname, tm)
        end,
    })

    if pname ~= "default" and not is_current then
        table.insert(items, {
            text = T(_("Delete \"%1\"…"), pname),
            keep_menu_open = true,
            callback = function(tm)
                UIManager:show(require("ui/widget/confirmbox"):new{
                    text = T(_("Delete profile \"%1\" and ALL its data?\nThis cannot be undone."), pname),
                    ok_text = _("Delete"),
                    ok_callback = function()
                        local ok, err = self:deleteProfile(pname)
                        if ok then
                            UIManager:show(require("ui/widget/infomessage"):new{
                                text = T(_("Profile \"%1\" deleted."), pname), timeout = 2,
                            })
                            if tm then
                                tm.item_table = self:getSubMenuItems()
                                tm.page = 1
                                tm:updateItems()
                            end
                        else
                            UIManager:show(require("ui/widget/infomessage"):new{ text = err, timeout = 3 })
                        end
                    end,
                })
            end,
        })
    end

    return items
end

function MultiUser:showCreateProfileDialog(on_create)
    local InputDialog = require("ui/widget/inputdialog")
    local dlg
    dlg = InputDialog:new{
        title = _("New profile name"),
        input = "",
        input_hint = _("e.g. Yulia, Kids, Work…"),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dlg) end },
            {
                text = _("Create"),
                is_enter_default = true,
                callback = function()
                    local name = util.trim(dlg:getInputText())
                    UIManager:close(dlg)
                    local IM = require("ui/widget/infomessage")
                    if name == "" then
                        UIManager:show(IM:new{ text = _("Name cannot be empty."), timeout = 2 }); return
                    end
                    if name == "default" then
                        UIManager:show(IM:new{ text = _('"default" is reserved.'), timeout = 2 }); return
                    end
                    if name:match(FORBIDDEN_CHARS) then
                        UIManager:show(IM:new{ text = _("Invalid characters in name."), timeout = 2 }); return
                    end
                    local ok, err = self:createProfile(name)
                    if ok then
                        UIManager:show(IM:new{ text = T(_("Profile \"%1\" created."), name), timeout = 2 })
                        if on_create then on_create(name) end
                    else
                        UIManager:show(IM:new{ text = err, timeout = 3 })
                    end
                end,
            },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function MultiUser:showRenameDialog(pname, on_confirm)
    local InputDialog = require("ui/widget/inputdialog")
    local dlg
    dlg = InputDialog:new{
        title = T(_("Rename \"%1\""), self:getDisplayName(pname)),
        input = self:getDisplayName(pname),
        input_hint = _("New name"),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dlg) end },
            {
                text = _("Rename"),
                is_enter_default = true,
                callback = function()
                    local name = util.trim(dlg:getInputText())
                    UIManager:close(dlg)
                    local IM = require("ui/widget/infomessage")
                    if name == "" then
                        UIManager:show(IM:new{ text = _("Name cannot be empty."), timeout = 2 }); return
                    end
                    if pname ~= "default" and name == "default" then
                        UIManager:show(IM:new{ text = _('"default" is reserved.'), timeout = 2 }); return
                    end
                    if pname ~= "default" and name:match(FORBIDDEN_CHARS) then
                        UIManager:show(IM:new{ text = _("Invalid characters in name."), timeout = 2 }); return
                    end
                    on_confirm(name)
                end,
            },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function MultiUser:openUnlockAvatarPathChooser(pname, touchmenu)
    local DocumentRegistry = require("document/documentregistry")
    local start_path = DataStorage:getDataDir()
    local existing = self:getProfileUnlockAvatarPath(pname)
    if existing then
        local parent = ffiUtil.dirname(existing)
        if parent and parent ~= "" and lfs.attributes(parent, "mode") == "directory" then
            start_path = parent
        end
    end
    UIManager:show(UnlockAvatarPathChooser:new{
        path = start_path,
        title = T(_("Choose image for %1"), self:getDisplayName(pname)),
        select_directory = false,
        select_file = true,
        file_filter = function(filename)
            return DocumentRegistry:isImageFile(filename)
        end,
        onConfirm = function(path)
            self:saveProfileUnlockAvatarPath(pname, path)
            if touchmenu then
                touchmenu:updateItems()
            end
        end,
    })
end

function MultiUser:showUnlockAvatarDialog(pname, touchmenu)
    local ButtonDialog = require("ui/widget/buttondialog")
    local display = self:getDisplayName(pname)
    local dlg
    local buttons = {
        {
            {
                text = _("Browse for image file"),
                callback = function()
                    UIManager:close(dlg)
                    self:openUnlockAvatarPathChooser(pname, touchmenu)
                end,
            },
        },
    }
    if self:getProfileUnlockAvatarPath(pname) then
        table.insert(buttons, {
            {
                text = _("Clear image"),
                callback = function()
                    UIManager:close(dlg)
                    self:saveProfileUnlockAvatarPath(pname, nil)
                    if touchmenu then
                        touchmenu:updateItems()
                    end
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("Close"),
            callback = function()
                UIManager:close(dlg)
            end,
        },
    })
    dlg = ButtonDialog:new{
        title = T(_("Avatar: %1"), display),
        buttons = buttons,
    }
    UIManager:show(dlg)
end

local function scheduleOneFlashAfterPickerClose()
    UIManager:nextTick(function()
        UIManager:setDirty("all", "flashui")
    end)
end

function MultiUser:closeUserPickerLayersAndRefreshReader()
    if self._user_picker then
        UIManager:close(self._user_picker, "flashui")
        self._user_picker = nil
        scheduleOneFlashAfterPickerClose()
    end
end

function MultiUser:onOutOfScreenSaver()
    if not (self:getUnlockSetting("ask_on_unlock") == true) then return end

    if self._user_picker then return end

    local idle_sec = self:getUnlockIdleSeconds()
    local now = os.time()
    local last_lock = self:getUnlockSetting("last_lock_time") or 0

    if idle_sec > 0 and last_lock > 0 and (now - last_lock) < idle_sec then return end

    local profiles = self:getProfileNames()
    if #profiles <= 1 then return end

    UIManager:nextTick(function()
        if self._user_picker then return end
        self:showUserPickerDialog()
    end)
end

function MultiUser:showUserPickerDialog()
    if self:getUnlockUserPickerStyle() == "grid" then
        self:_showUserPickerDialogGrid()
    else
        self:_showUserPickerDialogList()
    end
end

function MultiUser:_showUserPickerDialogList()
    local current = self:getCurrentUser()
    local profiles = self:getProfileNames()
    local ButtonDialog = require("ui/widget/buttondialog")
    local screen_size = Screen:getSize()

    local backdrop_layer = fullScreenThemedBackdrop(screen_size)

    local buttons = {}
    for _, name in ipairs(profiles) do
        local pname = name
        local display = self:getDisplayName(pname)
        local is_current = (pname == current)
        table.insert(buttons, {
            {
                text = (is_current and "✓ " or "") .. display,
                font_bold = is_current,
                vsync = true,
                callback = function()
                    if not is_current then
                        if self._user_picker then
                            UIManager:close(self._user_picker, "flashui")
                            self._user_picker = nil
                        end
                        self:switchToProfile(pname)
                    else
                        self:closeUserPickerLayersAndRefreshReader()
                    end
                end,
            },
        })
    end

    local dialog = ButtonDialog:new{
        title = self:getUnlockUserPickerTitle(),
        dismissable = false,
        buttons = buttons,
        modal = false,
    }
    function dialog:onCloseWidget() end

    local stack = OverlapGroup:new{
        dimen = screen_size,
        allow_mirroring = false,
        [1] = backdrop_layer,
        [2] = dialog,
    }

    local shell = WidgetContainer:new{
        modal = true,
        dimen = screen_size,
        covers_fullscreen = true,
        [1] = stack,
    }

    self._user_picker = shell
    UIManager:show(shell, "flashui")
end

function MultiUser:_showUserPickerDialogGrid()
    local current = self:getCurrentUser()
    local profiles = self:getProfileNames()
    local screen_size = Screen:getSize()
    local n = #profiles

    local backdrop_layer = fullScreenThemedBackdrop(screen_size)

    local rows_spec = profilePickerRowLengths(n)
    local max_in_row = 1
    for _, c in ipairs(rows_spec) do
        max_in_row = math.max(max_in_row, c)
    end

    local gap = Size.padding.default + Screen:scaleBySize(4)
    local panel_short = math.floor(math.min(screen_size.w, screen_size.h) * 0.92)
    local margin_h = Size.padding.large * 2
    local panel_w = (max_in_row > 1) and math.floor(screen_size.w * 0.96 - margin_h) or panel_short
    panel_w = math.max(1, math.min(panel_w, screen_size.w - margin_h))
    local cell_active = math.floor((panel_w - gap * (max_in_row - 1)) / max_in_row)
    cell_active = math.max(cell_active, Screen:scaleBySize(64))
    local active_shrink = (max_in_row >= 3) and 0.92 or 0.8
    cell_active = math.max(math.floor(cell_active * active_shrink + 0.5), 1)
    local inactive_ratio = (n >= 3) and 0.9 or 0.8
    local cell_inactive = math.max(1, math.floor(cell_active * inactive_ratio + 0.5))
    local use_tile_size_contrast = (n < 4)

    local grid = VerticalGroup:new{ align = "center" }
    local idx = 1
    for ri, row_count in ipairs(rows_spec) do
        local row = HorizontalGroup:new{ align = "center" }
        for k = 1, row_count do
            local pname = profiles[idx]
            local display = self:getDisplayName(pname)
            local is_current = (pname == current)
            local cw = (use_tile_size_contrast and not is_current) and cell_inactive or cell_active
            local rh = cw
            local tile = ProfilePickTile:new{
                cell_w = cw,
                rect_h = rh,
                rect_bg = nil,
                highlight_current = is_current,
                avatar_file = self:getProfileUnlockAvatarPath(pname),
                label_text = (is_current and "✓ " or "") .. display,
                bold_label = is_current,
                tap_callback = function()
                    if not is_current then
                        if self._user_picker then
                            UIManager:close(self._user_picker, "flashui")
                            self._user_picker = nil
                        end
                        self:switchToProfile(pname)
                    else
                        self:closeUserPickerLayersAndRefreshReader()
                    end
                end,
            }
            table.insert(row, tile)
            if k < row_count then
                table.insert(row, HorizontalSpan:new{ width = gap })
            end
            idx = idx + 1
        end
        table.insert(grid, row)
        if ri < #rows_spec then
            table.insert(grid, VerticalSpan:new{ width = gap })
        end
    end

    local title = TextWidget:new{
        text = self:getUnlockUserPickerTitle(),
        face = Font:getFace("x_smalltfont", 22),
        bold = true,
        max_width = panel_w,
    }
    local title_h = title:getSize().h
    local inner = VerticalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{ w = panel_w, h = title_h },
            title,
        },
        VerticalSpan:new{ width = Size.padding.large },
        grid,
    }

    local panel = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = 0,
        padding = Size.padding.large,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        inner,
    }

    local dialog_root = CenterContainer:new{
        dimen = screen_size,
        panel,
    }

    local stack = OverlapGroup:new{
        dimen = screen_size,
        allow_mirroring = false,
        [1] = backdrop_layer,
        [2] = dialog_root,
    }

    local shell = WidgetContainer:new{
        modal = true,
        dimen = screen_size,
        covers_fullscreen = true,
        [1] = stack,
    }

    self._user_picker = shell
    UIManager:show(shell, "flashui")
end

function MultiUser:getUnlockSetting(key)
    local users_data = self:loadUsers()
    return users_data[key]
end

function MultiUser:saveUnlockSetting(key, value)
    local users_data = self:loadUsers()
    users_data[key] = value
    self:saveUsers(users_data)
end

function MultiUser:getUnlockUserPickerStyle()
    local s = self:getUnlockSetting("unlock_user_picker_style")
    if s == "grid" then
        return "grid"
    end
    return "list"
end

function MultiUser:getUnlockUserPickerCustomTitleRaw()
    local s = self:getUnlockSetting("unlock_user_picker_title")
    if type(s) ~= "string" then
        return ""
    end
    return util.trim(s)
end

function MultiUser:getUnlockUserPickerTitle()
    local custom = self:getUnlockUserPickerCustomTitleRaw()
    if custom ~= "" then
        return custom
    end
    return _("Who's reading?")
end

function MultiUser:showUnlockUserPickerTitleDialog(touchmenu)
    local InputDialog = require("ui/widget/inputdialog")
    local dlg
    dlg = InputDialog:new{
        title = _("Title"),
        input = self:getUnlockUserPickerCustomTitleRaw(),
        input_hint = _("Who's reading?"),
        description = _("Leave empty to restore the default title."),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dlg) end },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    local t = util.trim(dlg:getInputText())
                    UIManager:close(dlg)
                    if t == "" then
                        self:saveUnlockSetting("unlock_user_picker_title", nil)
                    else
                        if #t > 200 then
                            t = t:sub(1, 200)
                        end
                        self:saveUnlockSetting("unlock_user_picker_title", t)
                    end
                    if touchmenu then
                        touchmenu:updateItems()
                    end
                end,
            },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function MultiUser:getProfileUnlockAvatarPath(pname)
    local v = self:getUnlockSetting("unlock_avatar_" .. pname)
    if type(v) ~= "string" then
        return nil
    end
    v = util.trim(v)
    if v == "" then
        return nil
    end
    return v
end

function MultiUser:saveProfileUnlockAvatarPath(pname, path)
    local users_data = self:loadUsers()
    local key = "unlock_avatar_" .. pname
    if path and path ~= "" then
        users_data[key] = path
    else
        users_data[key] = nil
    end
    self:saveUsers(users_data)
end

function MultiUser:usesNewUnlockIdleFormat()
    local u = self:loadUsers()
    return u.unlock_idle_days ~= nil or u.unlock_idle_hours ~= nil or u.unlock_idle_minutes ~= nil
end

function MultiUser:getUnlockIdleDHM()
    if self:usesNewUnlockIdleFormat() then
        return self:getUnlockSetting("unlock_idle_days") or 0,
            self:getUnlockSetting("unlock_idle_hours") or 0,
            self:getUnlockSetting("unlock_idle_minutes") or 0
    end
    local val = self:getUnlockSetting("unlock_timeout") or 0
    if val <= 0 then
        return 0, 0, 0
    end
    local unit = self:getUnlockSetting("unlock_timeout_unit") or "min"
    if unit == "hour" then
        return 0, math.min(val, 24), 0
    elseif unit == "day" then
        return math.min(val, 30), 0, 0
    end
    return 0, 0, math.min(val, 60)
end

function MultiUser:getUnlockIdleSeconds()
    if self:usesNewUnlockIdleFormat() then
        local d, h, m = self:getUnlockIdleDHM()
        return d * 86400 + h * 3600 + m * 60
    end
    local val = self:getUnlockSetting("unlock_timeout") or 0
    if val <= 0 then return 0 end
    local unit = self:getUnlockSetting("unlock_timeout_unit") or "min"
    if unit == "hour" then
        return val * 3600
    elseif unit == "day" then
        return val * 86400
    end
    return val * 60
end

function MultiUser:getUnlockIdleMenuTitle()
    if self:getUnlockIdleSeconds() <= 0 then
        return _("Ask every time")
    end
    if self:usesNewUnlockIdleFormat() then
        local d, h, m = self:getUnlockIdleDHM()
        return T(_("Ask after idle: %1d %2h %3m"), d, h, m)
    end
    local t = self:getUnlockSetting("unlock_timeout") or 0
    local u = self:getUnlockSetting("unlock_timeout_unit") or "min"
    if u == "hour" then
        return T(_("Ask after %1 h idle"), t)
    elseif u == "day" then
        return T(_("Ask after %1 d idle"), t)
    end
    return T(_("Ask after %1 min idle"), t)
end

function MultiUser:saveUnlockIdleInterval(d, h, m, touchmenu)
    local users_data = self:loadUsers()
    users_data.unlock_idle_days = d
    users_data.unlock_idle_hours = h
    users_data.unlock_idle_minutes = m
    users_data.unlock_timeout = nil
    users_data.unlock_timeout_unit = nil
    self:saveUsers(users_data)
    if touchmenu then touchmenu:updateItems() end
end

function MultiUser:getSettingsSubMenu()
    return {
        {
            text = _("Ask for user on unlock"),
            checked_func = function()
                return self:getUnlockSetting("ask_on_unlock") == true
            end,
            callback = function()
                local current = self:getUnlockSetting("ask_on_unlock") == true
                self:saveUnlockSetting("ask_on_unlock", not current)
            end,
        },
        {
            text_func = function()
                return self:getUnlockIdleMenuTitle()
            end,
            enabled_func = function()
                return self:getUnlockSetting("ask_on_unlock") == true
            end,
            keep_menu_open = true,
            callback = function(touchmenu)
                local DateTimeWidget = require("ui/widget/datetimewidget")
                local d, h, m = self:getUnlockIdleDHM()
                UIManager:show(DateTimeWidget:new{
                    day = d,
                    hour = h,
                    min = m,
                    day_min = 0,
                    day_max = 30,
                    hour_min = 0,
                    hour_max = 23,
                    min_min = 0,
                    min_max = 59,
                    title_text = _("Idle before asking again"),
                    info_text = _("Days, hours, minutes (e.g. 1 d, 00 h, 00 min). Or set 0 for ask every time."),
                    ok_text = _("Apply"),
                    cancel_text = _("Close"),
                    callback = function(w)
                        self:saveUnlockIdleInterval(w.day, w.hour, w.min, touchmenu)
                    end,
                })
            end,
        },
        {
            text_func = function()
                local custom = self:getUnlockUserPickerCustomTitleRaw()
                if custom == "" then
                    return _("Title: Who's reading?")
                end
                local preview = custom
                if #preview > 36 then
                    preview = preview:sub(1, 33) .. "…"
                end
                return T(_("Title: %1"), preview)
            end,
            keep_menu_open = true,
            callback = function(touchmenu)
                self:showUnlockUserPickerTitleDialog(touchmenu)
            end,
        },
        {
            text_func = function()
                if self:getUnlockUserPickerStyle() == "grid" then
                    return _("Style: Tiles")
                end
                return _("Style: List")
            end,
            keep_menu_open = true,
            sub_item_table_func = function()
                return {
                    {
                        text = _("List"),
                        checked_func = function()
                            return self:getUnlockUserPickerStyle() == "list"
                        end,
                        callback = function(touchmenu)
                            self:saveUnlockSetting("unlock_user_picker_style", "list")
                            if touchmenu then touchmenu:updateItems() end
                        end,
                    },
                    {
                        text = _("Tiles"),
                        checked_func = function()
                            return self:getUnlockUserPickerStyle() == "grid"
                        end,
                        callback = function(touchmenu)
                            self:saveUnlockSetting("unlock_user_picker_style", "grid")
                            if touchmenu then touchmenu:updateItems() end
                        end,
                    },
                }
            end,
        },
    }
end

MultiUser.PLUGIN_ID = "multiuser"

function MultiUser.getPluginInstance()
    local ok, PluginLoader = pcall(require, "pluginloader")
    if ok and PluginLoader and PluginLoader.getPluginInstance then
        return PluginLoader:getPluginInstance(MultiUser.PLUGIN_ID)
    end
    return nil
end

function MultiUser.apiIsAvailable()
    return MultiUser.getPluginInstance() ~= nil
end

function MultiUser.apiGetCurrentUser()
    local inst = MultiUser.getPluginInstance()
    if inst then
        return inst:getCurrentUser()
    end
    return MULTIUSER_CURRENT or "default"
end

function MultiUser.apiGetProfileNames()
    local inst = MultiUser.getPluginInstance()
    if inst then
        return inst:getProfileNames()
    end
    return {}
end

local function apiUsersFilePath()
    if MULTIUSER_USERS_FILE then
        return MULTIUSER_USERS_FILE
    end
    if MULTIUSER_BASE_DIR then
        return MULTIUSER_BASE_DIR .. "/users.lua"
    end
    return require("datastorage"):getDataDir() .. "/users.lua"
end

function MultiUser.apiGetProfileAvatarPath(profile_id)
    local inst = MultiUser.getPluginInstance()
    if inst and inst.getProfileUnlockAvatarPath then
        return inst:getProfileUnlockAvatarPath(profile_id)
    end
    return nil
end

function MultiUser.apiGetDisplayName(profile_id)
    local inst = MultiUser.getPluginInstance()
    if inst then
        return inst:getDisplayName(profile_id)
    end
    if profile_id == "default" then
        local data = loadLuaTable(apiUsersFilePath()) or {}
        return data.default_alias or "default"
    end
    return profile_id
end

function MultiUser.apiIsActiveProfile(profile_id)
    return MultiUser.apiGetCurrentUser() == profile_id
end

function MultiUser.apiSwitchToProfile(profile_id)
    local inst = MultiUser.getPluginInstance()
    if inst then
        inst:switchToProfile(profile_id)
        return true
    end
    logger.warn("MultiUser.apiSwitchToProfile: plugin instance not loaded (enable MultiUser.koplugin)")
    return false
end

function MultiUser.apiOpenUserPicker()
    local inst = MultiUser.getPluginInstance()
    if not inst then
        return false
    end
    if inst.showUserPickerDialogFromMenu then
        inst:showUserPickerDialogFromMenu()
        return true
    end
    return false
end

package.loaded["koreader_multiuser_api"] = MultiUser

return MultiUser