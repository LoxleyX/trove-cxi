--[[
* trove/plugins/vault.lua — Vault Browser
*
* Displays Mog Vault Deposit Boxes and Wardrobe contents.
* Uses the generic tab protocol (TAB_SOURCE = 1).
*
* Command: /trove vault
]]--

local imgui = require('imgui');

------------------------------------------------------------
-- Shared (injected via init)
------------------------------------------------------------
local renderIcon = nil;
local getItemRes = nil;
local ui = nil;
local renderTooltip = nil;

------------------------------------------------------------
-- State
------------------------------------------------------------
local isOpen          = { false };
local selectedCat     = nil;    -- nil = summary, string = category name
local summary         = {};
local summaryLoaded   = false;
local items           = {};
local itemsLoaded     = false;
local searchBuf       = { '' };

------------------------------------------------------------
-- Protocol (matches trove.lua constants)
------------------------------------------------------------
local PACKET_ID        = 0x1A4;
local C2S_TAB_SUMMARY  = 13;
local C2S_TAB_CATEGORY = 14;
local S2C_TAB_SUMMARY  = 12;
local S2C_TAB_ENTRY    = 8;
local S2C_END_LIST     = 2;
local TAB_SOURCE_VAULT = 1;

local function makePacket()
    local p = {};
    for i = 1, 64 do p[i] = 0; end
    return p;
end

local function sendVaultSummary()
    local p = makePacket();
    p[5] = C2S_TAB_SUMMARY;
    p[7] = TAB_SOURCE_VAULT;
    AshitaCore:GetPacketManager():AddOutgoingPacket(PACKET_ID, p);
end

local function sendVaultCategory(categoryName)
    local p = makePacket();
    p[5] = C2S_TAB_CATEGORY;
    p[7] = TAB_SOURCE_VAULT;
    local bytes = { string.byte(categoryName, 1, 20) };
    for i = 1, math.min(#bytes, 20) do p[8 + i] = bytes[i]; end
    AshitaCore:GetPacketManager():AddOutgoingPacket(PACKET_ID, p);
end

------------------------------------------------------------
-- Packet reading helpers
------------------------------------------------------------
local function readU16(data, offset)
    local lo = struct.unpack('B', data, offset + 1);
    local hi = struct.unpack('B', data, offset + 2);
    return lo + hi * 256;
end

local function readString(data, offset, maxLen)
    local s = '';
    for i = 0, maxLen - 1 do
        local b = struct.unpack('B', data, offset + i + 1);
        if b == 0 then break; end
        s = s .. string.char(b);
    end
    return s;
end

------------------------------------------------------------
-- Render: Summary view
------------------------------------------------------------
local function renderSummary()
    if summaryLoaded ~= true then
        ui.dim('Loading...');
        return;
    end

    if #summary == 0 then
        ui.dim('No vault containers unlocked.');
        return;
    end

    -- Refresh button
    if ui.button('Refresh', 60, 22) then
        summaryLoaded = false;
        sendVaultSummary();
    end
    imgui.Separator();
    imgui.Spacing();

    imgui.BeginChild('##vault_summary', { -1, -1 }, false);
    for i, entry in ipairs(summary) do
        local subtitle = string.format('%d item%s stored', entry.count, entry.count ~= 1 and 's' or '');
        if ui.categoryButton(entry.category, subtitle, i) then
            selectedCat = entry.category;
            items = {};
            itemsLoaded = false;
            searchBuf = { '' };
            sendVaultCategory(entry.category);
        end
        imgui.Spacing();
    end
    imgui.EndChild();
end

------------------------------------------------------------
-- Render: Item list view
------------------------------------------------------------
local function renderItems()
    if ui.button('< Back', 55, 22) then
        selectedCat = nil;
        items = {};
        itemsLoaded = false;
        searchBuf = { '' };
        return;
    end
    imgui.SameLine();
    ui.colored(selectedCat, 'header');
    imgui.SameLine();
    ui.dim(string.format('(%d)', #items));
    imgui.Separator();
    imgui.Spacing();

    if not itemsLoaded then
        ui.dim('Loading...');
        return;
    end

    if #items == 0 then
        ui.dim('Empty.');
        return;
    end

    -- Search filter
    imgui.PushItemWidth(-1);
    imgui.InputText('##vault_search', searchBuf, 256);
    imgui.PopItemWidth();
    imgui.Spacing();

    local filter = searchBuf[1]:lower();

    imgui.BeginChild('##vault_items', { -1, -1 }, false);
    local idx = 0;
    for _, item in ipairs(items) do
        local res = getItemRes(item.iconId);
        local name = (res and res.Name and res.Name[1]) or item.name or '???';
        if filter == '' or name:lower():find(filter, 1, true) then
            idx = idx + 1;
            ui.itemRow(renderIcon, getItemRes, {
                id   = item.iconId,
                name = name,
                qty  = tonumber(item.tier) or 1,
            }, idx, renderTooltip);
        end
    end
    imgui.EndChild();
end

------------------------------------------------------------
-- Main render
------------------------------------------------------------
local function renderWindow()
    if not isOpen[1] then return; end

    -- Auto-request summary on first open
    if not summaryLoaded then
        sendVaultSummary();
        summaryLoaded = 'pending';
    end

    imgui.SetNextWindowSize({ 280, 400 }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSizeConstraints({ 250, 300 }, { 400, 700 });

    local winColors = ui.pushWindowStyle();

    if imgui.Begin('Vault###trove_vault', isOpen, ImGuiWindowFlags_None) then
        if selectedCat then
            renderItems();
        else
            renderSummary();
        end
    end
    imgui.End();
    ui.popWindowStyle(winColors);
end

------------------------------------------------------------
-- Plugin export
------------------------------------------------------------
return {
    name        = 'Vault',
    description = 'Browse Mog Vault deposit boxes and wardrobes',

    init = function(sharedRenderIcon, sharedGetItemRes, sharedUi, sharedRenderTooltip)
        renderIcon = sharedRenderIcon;
        getItemRes = sharedGetItemRes;
        ui = sharedUi;
        renderTooltip = sharedRenderTooltip;
    end,

    commands = {
        vault = function(state, args)
            isOpen[1] = not isOpen[1];
            if isOpen[1] and not summaryLoaded then
                sendVaultSummary();
            end
        end,
    },

    window = {
        isOpen  = isOpen,
        render  = renderWindow,
        label   = 'Vault',
        icon    = 26352, -- Moogle Sacoche
    },

    onPacketIn = function(e, state)
        if e.id ~= 0x1A4 then return; end

        local action = struct.unpack('B', e.data_modified, 0x04 + 1);

        -- Tab summary response
        if action == S2C_TAB_SUMMARY then
            local source = struct.unpack('B', e.data_modified, 0x06 + 1);
            if source ~= TAB_SOURCE_VAULT then return; end

            local entryCount = struct.unpack('B', e.data_modified, 0x05 + 1);
            summary = {};
            local offset = 0x08;
            for i = 1, entryCount do
                local category = readString(e.data_modified, offset, 20);
                local count    = readU16(e.data_modified, offset + 20);
                table.insert(summary, { category = category, count = count });
                offset = offset + 22;
            end
            summaryLoaded = true;
            return;
        end

        -- Tab entry (source = vault)
        if action == S2C_TAB_ENTRY then
            local source = struct.unpack('B', e.data_modified, 0x05 + 1);
            if source ~= TAB_SOURCE_VAULT then return; end

            local iconId   = readU16(e.data_modified, 0x06);
            local name     = readString(e.data_modified, 0x34, 23);
            local tier     = readString(e.data_modified, 0x4C, 7);

            table.insert(items, {
                iconId = iconId,
                name   = name,
                tier   = tier,
            });
            return;
        end

        -- End list (source = vault)
        if action == S2C_END_LIST then
            local source = struct.unpack('B', e.data_modified, 0x05 + 1);
            if source ~= TAB_SOURCE_VAULT then return; end
            itemsLoaded = true;
            return;
        end
    end,
};
