--[[
* trove/plugins/ultimates.lua — Ultimate Weapon Progress Tracker
*
* Shows progress toward relic, mythic, and empyrean weapons based on
* dynamis currency. Completion detected via item ownership.
*
* Command: /trove ultimates
]]--

local imgui = require('imgui');

------------------------------------------------------------
-- Shared (injected via init)
------------------------------------------------------------
local renderIcon = nil;
local getItemRes = nil;
local ui = nil;
local renderTooltip = nil;
local renderFileIcon = nil;

------------------------------------------------------------
-- Currency item IDs and denominations
------------------------------------------------------------
local CURRENCY = {
    -- Byne Bills (base unit = 1 One Byne Bill)
    BYNE = {
        name  = 'Byne Bills',
        icon  = 1455, -- One Byne Bill
        color = { 1.00, 0.78, 0.35, 1.00 }, -- amber
        barFill = { 0.70, 0.55, 0.20, 0.65 }, -- darker fill for readability
    },
    -- Whiteshells (base unit = 1 Tukuku Whiteshell)
    SHELL = {
        name  = 'Whiteshells',
        icon  = 1449, -- Tukuku Whiteshell
        color = { 0.55, 0.85, 1.00, 1.00 }, -- light blue
        barFill = { 0.25, 0.50, 0.65, 0.65 },
    },
    -- Bronzepieces (base unit = 1 Ordelle Bronzepiece)
    BRONZE = {
        name  = 'Bronzepieces',
        icon  = 1452, -- Ordelle Bronzepiece
        color = { 0.85, 0.60, 0.40, 1.00 }, -- bronze
        barFill = { 0.55, 0.35, 0.18, 0.65 },
    },
};

------------------------------------------------------------
-- Relic weapon definitions (16 weapons, 4 stages each)
-- Each stage: { weaponId, currencyType, currencyAmount (in base units) }
-- currencyAmount is already normalized to base denomination
------------------------------------------------------------
local RELICS = {
    {
        name = 'Spharai', finalId = 18264, job = 'MNK',
        stages = {
            { weaponId = 18261, currency = 'BYNE',   amount = 400 },
            { weaponId = 18262, currency = 'BRONZE', amount = 1400 },
            { weaponId = 18263, currency = 'SHELL',  amount = 6100 },
            { weaponId = 18264, currency = 'BYNE',   amount = 10000 },
        },
    },
    {
        name = 'Mandau', finalId = 18270, job = 'THF',
        stages = {
            { weaponId = 18267, currency = 'BYNE',   amount = 400 },
            { weaponId = 18268, currency = 'BRONZE', amount = 1400 },
            { weaponId = 18269, currency = 'SHELL',  amount = 6100 },
            { weaponId = 18270, currency = 'BYNE',   amount = 10000 },
        },
    },
    {
        name = 'Excalibur', finalId = 18276, job = 'PLD',
        stages = {
            { weaponId = 18271, currency = 'BRONZE', amount = 400 },
            { weaponId = 18272, currency = 'BYNE',   amount = 1400 },
            { weaponId = 18273, currency = 'SHELL',  amount = 6100 },
            { weaponId = 18274, currency = 'BRONZE', amount = 10000 },
        },
    },
    {
        name = 'Ragnarok', finalId = 18282, job = 'DRK',
        stages = {
            { weaponId = 18275, currency = 'BRONZE', amount = 400 },
            { weaponId = 18276, currency = 'SHELL',  amount = 1600 },
            { weaponId = 18277, currency = 'BYNE',   amount = 6100 },
            { weaponId = 18278, currency = 'BRONZE', amount = 10000 },
        },
    },
    {
        name = 'Guttler', finalId = 18288, job = 'BST',
        stages = {
            { weaponId = 18279, currency = 'SHELL',  amount = 300 },
            { weaponId = 18280, currency = 'BRONZE', amount = 1400 },
            { weaponId = 18281, currency = 'BYNE',   amount = 6000 },
            { weaponId = 18282, currency = 'SHELL',  amount = 10000 },
        },
    },
    {
        name = 'Bravura', finalId = 18294, job = 'WAR',
        stages = {
            { weaponId = 18283, currency = 'BYNE',   amount = 300 },
            { weaponId = 18284, currency = 'SHELL',  amount = 1600 },
            { weaponId = 18285, currency = 'BRONZE', amount = 6000 },
            { weaponId = 18286, currency = 'BYNE',   amount = 10000 },
        },
    },
    {
        name = 'Gungnir', finalId = 18300, job = 'DRG',
        stages = {
            { weaponId = 18287, currency = 'SHELL',  amount = 400 },
            { weaponId = 18288, currency = 'BYNE',   amount = 1600 },
            { weaponId = 18289, currency = 'BRONZE', amount = 6100 },
            { weaponId = 18290, currency = 'SHELL',  amount = 10000 },
        },
    },
    {
        name = 'Apocalypse', finalId = 18306, job = 'DRK',
        stages = {
            { weaponId = 18291, currency = 'SHELL',  amount = 500 },
            { weaponId = 18292, currency = 'BRONZE', amount = 1600 },
            { weaponId = 18293, currency = 'BYNE',   amount = 6200 },
            { weaponId = 18294, currency = 'SHELL',  amount = 10000 },
        },
    },
    {
        name = 'Kikoku', finalId = 18312, job = 'NIN',
        stages = {
            { weaponId = 18295, currency = 'BYNE',   amount = 400 },
            { weaponId = 18296, currency = 'SHELL',  amount = 1600 },
            { weaponId = 18297, currency = 'BRONZE', amount = 6100 },
            { weaponId = 18298, currency = 'BYNE',   amount = 10000 },
        },
    },
    {
        name = 'Amanomurakumo', finalId = 18318, job = 'SAM',
        stages = {
            { weaponId = 18299, currency = 'BRONZE', amount = 300 },
            { weaponId = 18300, currency = 'SHELL',  amount = 1500 },
            { weaponId = 18301, currency = 'BYNE',   amount = 6000 },
            { weaponId = 18302, currency = 'BRONZE', amount = 10000 },
        },
    },
    {
        name = 'Mjollnir', finalId = 18324, job = 'WHM',
        stages = {
            { weaponId = 18303, currency = 'BRONZE', amount = 500 },
            { weaponId = 18304, currency = 'BYNE',   amount = 1600 },
            { weaponId = 18305, currency = 'SHELL',  amount = 6200 },
            { weaponId = 18306, currency = 'BRONZE', amount = 10000 },
        },
    },
    {
        name = 'Claustrum', finalId = 18330, job = 'BLM',
        stages = {
            { weaponId = 18307, currency = 'SHELL',  amount = 500 },
            { weaponId = 18308, currency = 'BYNE',   amount = 1600 },
            { weaponId = 18309, currency = 'BRONZE', amount = 6200 },
            { weaponId = 18310, currency = 'SHELL',  amount = 10000 },
        },
    },
    {
        name = 'Annihilator', finalId = 18336, job = 'RNG',
        stages = {
            { weaponId = 18311, currency = 'BYNE',   amount = 500 },
            { weaponId = 18312, currency = 'SHELL',  amount = 1500 },
            { weaponId = 18313, currency = 'BRONZE', amount = 6200 },
            { weaponId = 18314, currency = 'BYNE',   amount = 10000 },
        },
    },
    {
        name = 'Gjallarhorn', finalId = 18342, job = 'BRD',
        stages = {
            { weaponId = 18315, currency = 'SHELL',  amount = 300 },
            { weaponId = 18316, currency = 'BYNE',   amount = 1400 },
            { weaponId = 18317, currency = 'BRONZE', amount = 6000 },
            { weaponId = 18318, currency = 'SHELL',  amount = 10000 },
        },
    },
    {
        name = 'Yoichinoyumi', finalId = 18348, job = 'RNG',
        stages = {
            { weaponId = 18319, currency = 'BRONZE', amount = 400 },
            { weaponId = 18320, currency = 'BRONZE', amount = 1500 },
            { weaponId = 18321, currency = 'SHELL',  amount = 6100 },
            { weaponId = 18322, currency = 'BRONZE', amount = 10000 },
        },
    },
    {
        name = 'Aegis', finalId = 15070, job = 'PLD',
        stages = {
            -- Aegis uses all 3 currencies simultaneously; we sum them
            { weaponId = 15067, currency = 'BYNE',   amount = 100,  extraCurrency = { { 'BRONZE', 100 }, { 'SHELL', 100 } } },
            { weaponId = 15068, currency = 'BYNE',   amount = 400,  extraCurrency = { { 'BRONZE', 400 }, { 'SHELL', 400 } } },
            { weaponId = 15069, currency = 'BYNE',   amount = 2000, extraCurrency = { { 'BRONZE', 2000 }, { 'SHELL', 2000 } } },
            { weaponId = 15070, currency = 'BRONZE', amount = 10000 },
        },
    },
};

------------------------------------------------------------
-- Extra progression cards (fill the 3-column grid)
------------------------------------------------------------
local EXTRA_CARDS = {
    {
        name       = 'Mythic',
        icon       = 18993, -- Yagrush
        currency   = 'Alexandrite',
        target     = 30000,
        color      = { 0.70, 0.90, 0.50, 1.00 }, -- lime green
        barFill    = { 0.35, 0.50, 0.20, 0.65 },
        materials  = {
            { id = 3066, name = "Medusa's Brassard" },
            { id = 3067, name = "Gurfurlur's Morion" },
            { id = 3068, name = "Ja Ja's Plastron" },
        },
    },
    {
        name       = 'Ergon',
        icon       = 21685, -- Epeolatry
        currency   = 'H-P Bayld',
        target     = 10000,
        color      = { 0.80, 0.55, 0.90, 1.00 }, -- purple
        barFill    = { 0.40, 0.25, 0.50, 0.65 },
        materialRows = {
            {
                items = {
                    { id = 3980, name = 'Bztavian Stinger' },
                    { id = 3979, name = 'Rockfin Tooth' },
                    { id = 3977, name = 'Gabbrath Horn' },
                    { id = 4015, name = 'Yggdreant Root' },
                    { id = 4013, name = 'Waktza Crest' },
                    { id = 8754, name = 'Cehuetzi Pelt' },
                },
            },
            {
                items = {
                    { id = 3981, name = 'Bztavian Wing' },
                    { id = 3978, name = 'Rockfin Fin' },
                    { id = 6068, name = 'Gabbrath Meat' },
                    { id = 4014, name = 'Yggdreant Bole' },
                    { id = 4012, name = 'Waktza Rostrum' },
                    { id = 8752, name = 'Cehuetzi Claw' },
                },
            },
        },
        -- Extra column: Domain NM materials (displayed right of rows in L-shape)
        sideColumn = {
            { id = 9506, name = 'Amphisbaena Hide' },
            { id = 9510, name = 'Battosai Fang' },
            { id = 9511, name = 'Tortuga Shell' },
        },
    },
};

------------------------------------------------------------
-- Inventory containers to scan
------------------------------------------------------------
local CONTAINERS = {
    0,  -- Inventory
    1,  -- Safe
    2,  -- Storage
    4,  -- Locker
    5,  -- Satchel
    6,  -- Sack
    7,  -- Case
    8,  -- Wardrobe
    9,  -- Safe 2
    10, 11, 12, 13, 14, 15, 16, -- Wardrobes 2-8
};

------------------------------------------------------------
-- Currency name → internal type mapping
------------------------------------------------------------
local CURRENCY_NAME_MAP = {
    ['Byne Bills']   = 'BYNE',
    ['Whiteshells']  = 'SHELL',
    ['Bronzepieces'] = 'BRONZE',
};

------------------------------------------------------------
-- State
------------------------------------------------------------
local isOpen       = { false };
local scanned      = false;
local currencyHave = { BYNE = 0, SHELL = 0, BRONZE = 0 };
local ownedItems   = {}; -- [itemId] = true
local troveState   = nil; -- reference to main trove state (for currency data)

------------------------------------------------------------
-- Read currency totals from the Currency tab data (server-provided)
------------------------------------------------------------
local function readCurrencyFromState()
    currencyHave = { BYNE = 0, SHELL = 0, BRONZE = 0 };

    if not troveState or not troveState.currency then return; end

    for _, entry in ipairs(troveState.currency) do
        local cType = CURRENCY_NAME_MAP[entry.name];
        if cType then
            currencyHave[cType] = entry.total or 0;
        end
    end
end

------------------------------------------------------------
-- Scan inventory containers for relic weapon ownership
------------------------------------------------------------
local function scanWeapons()
    ownedItems = {};

    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    if not inventory then
        scanned = true;
        return;
    end

    -- Build lookup of all relic weapon IDs + extra material IDs
    local weaponLookup = {};
    for _, relic in ipairs(RELICS) do
        for _, stage in ipairs(relic.stages) do
            weaponLookup[stage.weaponId] = true;
        end
        weaponLookup[relic.finalId] = true;
    end
    for _, card in ipairs(EXTRA_CARDS) do
        if card.materials then
            for _, mat in ipairs(card.materials) do
                weaponLookup[mat.id] = true;
            end
        end
        if card.materialRows then
            for _, row in ipairs(card.materialRows) do
                for _, mat in ipairs(row.items) do
                    weaponLookup[mat.id] = true;
                end
            end
        end
        if card.sideColumn then
            for _, mat in ipairs(card.sideColumn) do
                weaponLookup[mat.id] = true;
            end
        end
    end

    for _, containerId in ipairs(CONTAINERS) do
        local max = inventory:GetContainerCountMax(containerId);
        if max and max > 0 then
            for j = 0, max do
                local ok, item = pcall(function() return inventory:GetContainerItem(containerId, j); end);
                if ok and item and item.Id ~= 0 and item.Id ~= 65535 then
                    if weaponLookup[item.Id] then
                        ownedItems[item.Id] = true;
                    end
                end
            end
        end
    end

    scanned = true;
end

------------------------------------------------------------
-- Full rescan: currency from server data + weapons from memory
------------------------------------------------------------
local function rescan()
    readCurrencyFromState();
    scanWeapons();
end

------------------------------------------------------------
-- Get completion stage for a relic (0 = none, 1-4 = stages)
------------------------------------------------------------
local function getCompletionStage(relic)
    -- Check final weapon first (the Lv75 relic itself)
    if ownedItems[relic.finalId] then
        return #relic.stages;
    end
    -- Check from highest stage down
    for s = #relic.stages, 1, -1 do
        if ownedItems[relic.stages[s].weaponId] then
            return s;
        end
    end
    return 0;
end

------------------------------------------------------------
-- Calculate total currency needed per type for a relic
------------------------------------------------------------
local function getTotalNeeded(relic)
    local needed = { BYNE = 0, SHELL = 0, BRONZE = 0 };
    for _, stage in ipairs(relic.stages) do
        needed[stage.currency] = needed[stage.currency] + stage.amount;
        if stage.extraCurrency then
            for _, extra in ipairs(stage.extraCurrency) do
                needed[extra[1]] = needed[extra[1]] + extra[2];
            end
        end
    end
    return needed;
end

------------------------------------------------------------
-- Render: progress bar
------------------------------------------------------------
local function renderProgressBar(cDef, have, need, width)
    local pct = need > 0 and math.min(have / need, 1.0) or 0;
    local barH = 16;
    local iconSize = 14;

    local dl = imgui.GetWindowDrawList();
    local cx, cy = imgui.GetCursorScreenPos();

    -- Icon left of bar
    imgui.SetCursorPosX(imgui.GetCursorPosX());
    renderIcon(cDef.icon, iconSize);
    imgui.SameLine(0, 4);
    local bx, by = imgui.GetCursorScreenPos();

    local barW = width - iconSize - 8;

    -- Background
    dl:AddRectFilled({ bx, by }, { bx + barW, by + barH },
        imgui.GetColorU32({ 0.06, 0.06, 0.09, 0.90 }), 3);

    -- Fill (darker tint for text readability)
    if pct > 0 then
        dl:AddRectFilled({ bx, by }, { bx + barW * pct, by + barH },
            imgui.GetColorU32(cDef.barFill), 3);
    end

    -- Border
    dl:AddRect({ bx, by }, { bx + barW, by + barH },
        imgui.GetColorU32({ 1, 1, 1, 0.06 }), 3);

    -- Fraction text centered in bar (shadow + foreground for readability)
    local fracStr = string.format('%s / %s', tostring(math.min(have, need)), tostring(need));
    local fracW = imgui.CalcTextSize(fracStr);
    local tx = bx + (barW - fracW) / 2;

    dl:AddText({ tx + 1, by + 2 }, imgui.GetColorU32({ 0, 0, 0, 0.80 }), fracStr);
    dl:AddText({ tx, by + 1 }, imgui.GetColorU32({ 1.0, 1.0, 1.0, 0.95 }), fracStr);

    imgui.Dummy({ width, barH + 2 });
end

------------------------------------------------------------
-- Render: single relic weapon card
------------------------------------------------------------
local function renderRelicCard(relic, index, cardW)
    local completion = getCompletionStage(relic);
    local isComplete = (completion >= #relic.stages);
    local needed = getTotalNeeded(relic);

    -- Calculate overall percentage
    local totalNeed = 0;
    local totalHave = 0;
    for cType, amt in pairs(needed) do
        if amt > 0 then
            totalNeed = totalNeed + amt;
            totalHave = totalHave + math.min(currencyHave[cType], amt);
        end
    end
    local overallPct = totalNeed > 0 and (totalHave / totalNeed) or 0;
    if isComplete then overallPct = 1.0; end

    -- Count how many currency types needed (for dynamic height)
    local numBars = 0;
    if not isComplete then
        for _, cType in ipairs({ 'BYNE', 'SHELL', 'BRONZE' }) do
            if needed[cType] and needed[cType] > 0 then numBars = numBars + 1; end
        end
    end
    local cardH = 38 + 3 * 20; -- fixed height (3 bar slots)
    local base = ui.color('childBg');
    local bgColor;
    if isComplete then
        bgColor = { 0.28, 0.22, 0.08, 0.85 }; -- gold for complete
    elseif completion > 0 then
        bgColor = { 0.10, 0.22, 0.12, 0.85 }; -- green tint for partial
    else
        bgColor = { base[1] + 0.03, base[2] + 0.03, base[3] + 0.05, 0.70 };
    end

    imgui.PushStyleColor(ImGuiCol_ChildBg, bgColor);
    imgui.BeginChild(string.format('##relic_%d', index), { cardW or -1, cardH }, false, ImGuiWindowFlags_NoScrollbar);

    local dl = imgui.GetWindowDrawList();
    local wx, wy = imgui.GetWindowPos();
    local ww = imgui.GetWindowWidth();

    -- Accent bar (color by completion)
    local accentColor = isComplete and { 1.00, 0.85, 0.30, 1.00 }
        or completion > 0 and { 0.40, 0.90, 0.40, 1.00 }
        or ui.color('accent');
    dl:AddRectFilled({ wx, wy }, { wx + 3, wy + cardH }, imgui.GetColorU32(accentColor));

    -- Weapon icon
    imgui.SetCursorPos({ 8, 6 });
    renderIcon(relic.finalId, 24);

    -- Name + job + completion
    local nameX = 38;
    dl:AddText({ wx + nameX, wy + 6 }, imgui.GetColorU32(ui.color('white')), relic.name);

    -- Overall percentage on right
    local pctStr = string.format('%d%%', math.floor(overallPct * 100));
    local pctW = imgui.CalcTextSize(pctStr);
    local pctColor = isComplete and { 1.00, 0.85, 0.30, 1.00 }
        or overallPct >= 0.75 and { 0.40, 0.90, 0.40, 1.00 }
        or overallPct >= 0.25 and { 1.00, 0.85, 0.35, 1.00 }
        or { 0.70, 0.70, 0.70, 1.00 };
    dl:AddText({ wx + ww - pctW - 10, wy + 6 }, imgui.GetColorU32(pctColor), pctStr);

    -- Stage dots (4 circles)
    for s = 1, #relic.stages do
        local dotX = wx + nameX + (s - 1) * 14;
        local dotY = wy + 24;
        if s <= completion then
            local dotCol = isComplete and { 1.00, 0.85, 0.30, 1.00 } or { 0.40, 0.90, 0.40, 1.00 };
            dl:AddCircleFilled({ dotX + 4, dotY + 4 }, 4, imgui.GetColorU32(dotCol));
        else
            dl:AddCircle({ dotX + 4, dotY + 4 }, 4,
                imgui.GetColorU32({ 0.40, 0.40, 0.45, 1.00 }), 12);
        end
    end

    -- Progress bars per currency type
    local barY = 36;
    local barW = ww - nameX - 12;
    imgui.SetCursorPos({ nameX, barY });

    if not isComplete then
        -- Sort currency bars by required amount (smallest first)
        local sortedBars = {};
        for _, cType in ipairs({ 'BYNE', 'SHELL', 'BRONZE' }) do
            local amt = needed[cType];
            if amt and amt > 0 then
                sortedBars[#sortedBars + 1] = { type = cType, amount = amt };
            end
        end
        table.sort(sortedBars, function(a, b) return a.amount < b.amount; end);

        for _, bar in ipairs(sortedBars) do
            imgui.SetCursorPosX(nameX);
            renderProgressBar(CURRENCY[bar.type], currencyHave[bar.type], bar.amount, barW);
        end
    end

    imgui.EndChild();
    imgui.PopStyleColor(1);

    -- Tooltip showing the Lv75 weapon (reuses shared item tooltip)
    if imgui.IsItemHovered() and renderTooltip then
        renderTooltip({ id = relic.finalId, name = relic.name, qty = 0 });
    end
end

------------------------------------------------------------
-- Render: extra progression card (Mythic / Empyrean)
------------------------------------------------------------
-- Currency icon IDs for progress bars (distinct from card icon)
local CURRENCY_BAR_ICONS = {
    ['Alexandrite'] = 2488,
    ['H-P Bayld']   = 8798,
};

local function renderExtraCard(card, index, cardW)
    -- Get currency from state
    local have = 0;
    if troveState and troveState.currency then
        for _, entry in ipairs(troveState.currency) do
            if entry.name == card.currency then
                have = entry.total or 0;
                break;
            end
        end
    end

    local pct = card.target > 0 and math.min(have / card.target, 1.0) or 0;

    -- Collect all material IDs for ownership check
    local allMats = true;
    local matOwned = {};
    local matRows = card.materialRows or { { items = card.materials or {} } };
    for _, row in ipairs(matRows) do
        for _, mat in ipairs(row.items) do
            matOwned[mat.id] = ownedItems[mat.id] or false;
            if not matOwned[mat.id] then allMats = false; end
        end
    end
    if card.sideColumn then
        for _, mat in ipairs(card.sideColumn) do
            matOwned[mat.id] = ownedItems[mat.id] or false;
            if not matOwned[mat.id] then allMats = false; end
        end
    end

    local numRows = #matRows;
    local cardH = 38 + 3 * 20; -- match relic card height
    if numRows > 1 then
        cardH = 30 + 20 + numRows * 20; -- bar + rows
    end

    local base = ui.color('childBg');
    local bgColor;
    if pct >= 1.0 and allMats then
        bgColor = { 0.28, 0.22, 0.08, 0.85 }; -- gold
    elseif pct > 0 then
        bgColor = { 0.10, 0.22, 0.12, 0.85 };
    else
        bgColor = { base[1] + 0.03, base[2] + 0.03, base[3] + 0.05, 0.70 };
    end

    imgui.PushStyleColor(ImGuiCol_ChildBg, bgColor);
    imgui.BeginChild(string.format('##extra_%d', index), { cardW or -1, cardH }, false, ImGuiWindowFlags_NoScrollbar);

    local dl = imgui.GetWindowDrawList();
    local wx, wy = imgui.GetWindowPos();
    local ww = imgui.GetWindowWidth();

    -- Accent bar
    dl:AddRectFilled({ wx, wy }, { wx + 3, wy + cardH }, imgui.GetColorU32(card.color));

    -- Icon
    imgui.SetCursorPos({ 8, 6 });
    renderIcon(card.icon, 24);

    -- Name + percentage
    local nameX = 38;
    dl:AddText({ wx + nameX, wy + 6 }, imgui.GetColorU32(ui.color('white')), card.name);
    local pctStr = string.format('%d%%', math.floor(pct * 100));
    local pctW = imgui.CalcTextSize(pctStr);
    local pctColor = pct >= 1.0 and { 1.00, 0.85, 0.30, 1.00 }
        or pct >= 0.75 and { 0.40, 0.90, 0.40, 1.00 }
        or pct >= 0.25 and { 1.00, 0.85, 0.35, 1.00 }
        or { 0.70, 0.70, 0.70, 1.00 };
    dl:AddText({ wx + ww - pctW - 10, wy + 6 }, imgui.GetColorU32(pctColor), pctStr);

    -- Currency progress bar (uses currency-specific icon, not card icon)
    local barW = ww - nameX - 12;
    imgui.SetCursorPos({ nameX, 26 });
    local barIcon = CURRENCY_BAR_ICONS[card.currency] or card.icon;
    local cDef = { icon = barIcon, name = card.currency, barFill = card.barFill };
    renderProgressBar(cDef, have, card.target, barW);

    -- Material rows
    local matY = 48;
    for ri, row in ipairs(matRows) do
        imgui.SetCursorPos({ nameX, matY });
        for mi, mat in ipairs(row.items) do
            if mi > 1 then imgui.SameLine(0, 2); end
            local owned = matOwned[mat.id];
            if not owned then
                imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.30);
            end
            renderIcon(mat.id, 18);
            if not owned then
                imgui.PopStyleVar();
            end
            if imgui.IsItemHovered() and renderTooltip then
                renderTooltip({ id = mat.id, name = mat.name, qty = 0 });
            end
        end
        matY = matY + 20;
    end

    -- Side column (L-shape, right of material rows)
    if card.sideColumn then
        local sideX = ww - (#card.sideColumn * 20) - 6;
        local sideY = 48;
        for si, mat in ipairs(card.sideColumn) do
            imgui.SetCursorPos({ sideX + (si - 1) * 20, sideY });
            local owned = matOwned[mat.id];
            if not owned then
                imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.30);
            end
            renderIcon(mat.id, 18);
            if not owned then
                imgui.PopStyleVar();
            end
            if imgui.IsItemHovered() and renderTooltip then
                renderTooltip({ id = mat.id, name = mat.name, qty = 0 });
            end
        end
    end

    imgui.EndChild();
    imgui.PopStyleColor(1);
end

------------------------------------------------------------
-- Render: main window
------------------------------------------------------------
local function renderWindow()
    if not isOpen[1] then return; end

    if not scanned then
        scanWeapons();
        scanned = true;
    end
    readCurrencyFromState();

    imgui.SetNextWindowSize({ 680, 480 }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSizeConstraints({ 600, 350 }, { 900, 800 });

    local winColors = ui.pushWindowStyle();

    if imgui.Begin('Ultimates###trove_relics', isOpen, ImGuiWindowFlags_None) then

        -- Header: currency totals with icons
        local currencyLoaded = troveState and troveState.currency and #troveState.currency > 0;
        for _, cType in ipairs({ 'BYNE', 'SHELL', 'BRONZE' }) do
            local cDef = CURRENCY[cType];
            renderIcon(cDef.icon, 16);
            imgui.SameLine(0, 4);
            if currencyLoaded then
                imgui.TextColored(cDef.color, tostring(currencyHave[cType]));
            else
                imgui.TextColored({ 0.50, 0.50, 0.55, 1.00 }, '?');
            end
            if imgui.IsItemHovered() and not currencyLoaded then
                imgui.SetTooltip('Open Currency tab once to load data');
            end
            imgui.SameLine(0, 14);
        end

        -- DVP converted to currency equivalent (500 DVP = 100 currency)
        local dvp = nil;
        if troveState and troveState.points and #troveState.points > 0 then
            for _, entry in ipairs(troveState.points) do
                if entry.label == 'Dynamis' and entry.group == 'Ventures' then
                    dvp = entry.value or 0;
                    break;
                end
            end
        end
        if renderFileIcon then
            renderFileIcon('cw.png', 16);
            imgui.SameLine(0, 4);
        end
        if dvp then
            local dvpCurrency = math.floor(dvp / 5);
            imgui.TextColored({ 0.65, 0.85, 1.00, 1.00 }, tostring(dvpCurrency));
            if imgui.IsItemHovered() then
                imgui.SetTooltip(string.format('%d Dynamis Venture Points\n500 DVP = 100 currency', dvp));
            end
        else
            imgui.TextColored({ 0.50, 0.50, 0.55, 1.00 }, '?');
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Open Currency and Points tabs once to load data');
            end
        end

        imgui.Spacing();

        if ui.button('Rescan', 0, 20) then
            scanned = false;
            rescan();
        end

        imgui.Separator();
        imgui.Spacing();

        -- Weapon list (3 columns)
        imgui.BeginChild('##relic_list', { -1, -1 }, false);
        local gap = 4;
        local colW = math.floor((imgui.GetContentRegionAvail() - gap * 2) / 3);
        local totalItems = #RELICS + #EXTRA_CARDS;
        for i = 1, totalItems do
            local col = ((i - 1) % 3);
            if col > 0 then imgui.SameLine(0, gap); end
            if i <= #RELICS then
                renderRelicCard(RELICS[i], i, colW);
            else
                renderExtraCard(EXTRA_CARDS[i - #RELICS], i, colW);
            end
            if col == 2 then imgui.Spacing(); end
        end
        imgui.EndChild();
    end
    imgui.End();
    ui.popWindowStyle(winColors);
end

------------------------------------------------------------
-- Plugin export
------------------------------------------------------------
return {
    name        = 'Ultimates',
    description = 'Track dynamis currency progress toward relic weapons',

    init = function(sharedRenderIcon, sharedGetItemRes, sharedUi, sharedRenderTooltip, sharedRenderFileIcon)
        renderIcon = sharedRenderIcon;
        getItemRes = sharedGetItemRes;
        ui = sharedUi;
        renderTooltip = sharedRenderTooltip;
        renderFileIcon = sharedRenderFileIcon;
    end,

    -- Grab trove state on first render (for currency data)
    onRender = function(state)
        if not troveState and state then
            troveState = state;
        end
    end,

    commands = {
        ultimates = function(state, args)
            if state then troveState = state; end
            isOpen[1] = not isOpen[1];
            if isOpen[1] then
                scanned = false;
            end
        end,
    },

    window = {
        isOpen = isOpen,
        render = renderWindow,
        label  = 'Ultimates',
        icon   = 18270, -- Mandau
    },
};
