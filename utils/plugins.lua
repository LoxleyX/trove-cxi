--[[
* trove/utils/plugins.lua — Plugin manager
*
* Auto-discovers and loads .lua files from the plugins/ directory.
* Each plugin returns a table with optional hooks:
*
*   return {
*       name        = 'My Plugin',              -- display name (required)
*       description = 'What it does',           -- short description
*       commands    = { cmd = function(state, args) end },  -- /trove cmd
*       menu        = { label = 'Do Thing', action = function(state) end },
*       onLoad      = function() end,           -- called once on load
*       onUnload    = function() end,           -- called on addon unload
*       onPacketIn  = function(e, state) end,   -- called on every incoming packet
*       onRender    = function(state) end,      -- called every frame
*       tab         = {                         -- adds a tab to the main trove window
*           label  = 'Tab Name',
*           render = function(state) end,       -- called inside BeginTabItem/EndTabItem
*       },
*       window      = {                         -- adds a separate floating window
*           isOpen = { false },                 -- imgui bool (table with 1 element)
*           render = function() end,            -- called inside Begin/End
*       },
*   }
*
* Commands are registered as /trove <cmd> and dispatched automatically.
* Menu entries appear in the plugin menu (hamburger icon).
* Tab/window rendering is driven by trove.lua via renderTabs/renderWindows.
]]--

local imgui = require('imgui');

local plugins = {};

local loaded = {};  -- array of { plugin, path }

------------------------------------------------------------
-- Discovery: scan plugins/ directory
------------------------------------------------------------
local function discoverPlugins()
    local dir = string.format('%saddons\\trove\\plugins\\', AshitaCore:GetInstallPath());
    local handle = io.popen('dir /b "' .. dir .. '*.lua" 2>nul');
    if handle == nil then return {}; end

    local files = {};
    for line in handle:lines() do
        if line:match('%.lua$') then
            files[#files + 1] = line;
        end
    end
    handle:close();
    return files;
end

------------------------------------------------------------
-- Load all plugins
------------------------------------------------------------
plugins.load = function()
    local files = discoverPlugins();
    for _, filename in ipairs(files) do
        local name = filename:gsub('%.lua$', '');
        local ok, result = pcall(function()
            return require('plugins/' .. name);
        end);

        if ok and type(result) == 'table' and result.name then
            loaded[#loaded + 1] = { plugin = result, file = filename };
            if result.onLoad then
                local lok, lerr = pcall(result.onLoad);
                if not lok then
                    print(string.format('[trove] Plugin %s onLoad error: %s', result.name, tostring(lerr)));
                end
            end
            print(string.format('[trove] Plugin loaded: %s', result.name));
        elseif ok then
            print(string.format('[trove] Plugin %s: invalid (must return table with .name)', filename));
        else
            print(string.format('[trove] Plugin %s failed to load: %s', filename, tostring(result)));
        end
    end
end

------------------------------------------------------------
-- Initialize all plugins with shared functions
-- Passes: renderIcon, getItemRes, ui (theme helper module)
------------------------------------------------------------
plugins.initAll = function(renderIcon, getItemRes)
    local ui = require('utils/ui');
    for _, entry in ipairs(loaded) do
        if entry.plugin.init then
            local ok, err = pcall(entry.plugin.init, renderIcon, getItemRes, ui);
            if not ok then
                print(string.format('[trove] Plugin %s init error: %s', entry.plugin.name, tostring(err)));
            end
        end
    end
end

------------------------------------------------------------
-- Unload all plugins
------------------------------------------------------------
plugins.unload = function()
    for _, entry in ipairs(loaded) do
        if entry.plugin.onUnload then
            pcall(entry.plugin.onUnload);
        end
    end
    loaded = {};
end

------------------------------------------------------------
-- Try to handle a command. Returns true if a plugin handled it.
------------------------------------------------------------
plugins.handleCommand = function(cmd, state, args)
    for _, entry in ipairs(loaded) do
        if entry.plugin.commands and entry.plugin.commands[cmd] then
            local ok, err = pcall(entry.plugin.commands[cmd], state, args);
            if not ok then
                print(string.format('[trove] Plugin %s command error: %s', entry.plugin.name, tostring(err)));
            end
            return true;
        end
    end
    return false;
end

------------------------------------------------------------
-- Dispatch packet_in to all plugins
------------------------------------------------------------
plugins.onPacketIn = function(e, state)
    for _, entry in ipairs(loaded) do
        if entry.plugin.onPacketIn then
            pcall(entry.plugin.onPacketIn, e, state);
        end
    end
end

------------------------------------------------------------
-- Dispatch render to all plugins
------------------------------------------------------------
plugins.onRender = function(state)
    for _, entry in ipairs(loaded) do
        if entry.plugin.onRender then
            pcall(entry.plugin.onRender, state);
        end
    end
end

------------------------------------------------------------
-- Get menu entries for UI (includes both menu actions and
-- window toggles from plugins with windows)
------------------------------------------------------------
plugins.getMenuEntries = function()
    local entries = {};
    for _, entry in ipairs(loaded) do
        if entry.plugin.menu then
            entries[#entries + 1] = {
                label     = entry.plugin.menu.label or entry.plugin.name,
                action    = entry.plugin.menu.action,
                separator = entry.plugin.menu.separator or false,
                plugin    = entry.plugin,
            };
        end
    end
    return entries;
end

------------------------------------------------------------
-- Render plugin tabs inside the main tab bar.
-- Called from trove.lua after built-in tabs.
------------------------------------------------------------
plugins.renderTabs = function(state)
    for _, entry in ipairs(loaded) do
        if entry.plugin.tab then
            local tab = entry.plugin.tab;
            if imgui.BeginTabItem(tab.label) then
                local ok, err = pcall(tab.render, state);
                if not ok then
                    imgui.TextColored({ 1, 0.3, 0.3, 1 }, 'Plugin error: ' .. tostring(err));
                end
                imgui.EndTabItem();
            end
        end
    end
end

------------------------------------------------------------
-- Render plugin floating windows.
-- Called from trove.lua in the render loop.
------------------------------------------------------------
plugins.renderWindows = function()
    for _, entry in ipairs(loaded) do
        if entry.plugin.window then
            local win = entry.plugin.window;
            if win.isOpen[1] then
                local ok, err = pcall(win.render);
                if not ok then
                    print(string.format('[trove] Plugin %s window error: %s', entry.plugin.name, tostring(err)));
                end
            end
        end
    end
end

------------------------------------------------------------
-- Get plugins that have windows (for menu toggles)
------------------------------------------------------------
plugins.getWindowPlugins = function()
    local result = {};
    for _, entry in ipairs(loaded) do
        if entry.plugin.window then
            result[#result + 1] = entry.plugin;
        end
    end
    return result;
end

------------------------------------------------------------
-- Check if any plugin has an active alert (for burger btn)
------------------------------------------------------------
plugins.hasAlert = function()
    for _, entry in ipairs(loaded) do
        if entry.plugin.hasAlert and entry.plugin.hasAlert() then
            return true;
        end
    end
    return false;
end

------------------------------------------------------------
-- Get list of loaded plugins (for display)
------------------------------------------------------------
plugins.list = function()
    local result = {};
    for _, entry in ipairs(loaded) do
        result[#result + 1] = {
            name        = entry.plugin.name,
            description = entry.plugin.description or '',
            file        = entry.file,
            hasMenu     = entry.plugin.menu ~= nil,
            hasTab      = entry.plugin.tab ~= nil,
            hasWindow   = entry.plugin.window ~= nil,
            commands    = {},
        };
        if entry.plugin.commands then
            for cmd in pairs(entry.plugin.commands) do
                result[#result].commands[#result[#result].commands + 1] = cmd;
            end
        end
    end
    return result;
end

return plugins;
