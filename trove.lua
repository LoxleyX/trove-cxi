--[[
* trove - Crystal Warrior storage + progression tool for CatsEyeXI
*
* Browse your Ephemeral Box, review Currency / Points / Squire storage,
* and withdraw items - all via the custom 0x1A4 packet.
*
* Usage:
*     /trove              - Toggle window (also bound to Ctrl+Z)
*     /trove show         - Show window
*     /trove hide         - Hide window
*     /box is kept as an alias for every command below.
*
* Anything else is passed through to the in-game !box command:
*     /trove store          - !box store
*     /trove cluster        - !box cluster
*     /trove ammo           - !box ammo
*     /trove fire crystal   - !box fire crystal
*     /trove 3 fire crystal - !box 3 fire crystal
]]--

addon.name      = 'trove';
addon.author    = 'Loxley';
addon.version   = '1.0.0';
addon.desc      = 'Browse Ephemeral Box, Currency, Points, and Squire in-game';

require('common');
local ffi   = require('ffi');
local d3d   = require('d3d8');
local imgui = require('imgui');

local C       = ffi.C;
local d3d8dev = d3d.get_device();

ffi.cdef[[
    HRESULT __stdcall D3DXCreateTextureFromFileA(IDirect3DDevice8* pDevice, const char* pSrcFile, IDirect3DTexture8** ppTexture);
]];

------------------------------------------------------------
-- Packet protocol (0x1A4)
------------------------------------------------------------
local PACKET_ID = 0x1A4;

local C2S = {
    WITHDRAW        = 2,
    WITHDRAW_PROMPT = 3,
    GET_SUMMARY     = 4,
    GET_CATEGORY    = 5,
    SEARCH          = 6,
    GET_CURRENCY    = 7,
    GET_POINTS      = 8,
    GET_SQUIRE      = 9,
};

local S2C = {
    CLEAR          = 0,
    ITEM           = 1,
    END_LIST       = 2,
    ACK            = 3,
    LOCKED         = 4,
    SUMMARY        = 5,
    CURRENCY_ENTRY = 6,
    POINTS_ENTRY   = 7,
    SQUIRE_ENTRY   = 8,
};

-- LOCKED reason codes (server → client)
local LOCK_REASON_NOT_CW   = 1;
local LOCK_REASON_NOT_UNLOCKED = 2;

-- Keybind. Ashita uses caret-prefix modifiers: ^ = ctrl, ! = alt, + = shift.
local KEYBIND = '^z';

------------------------------------------------------------
-- AH Category display names
------------------------------------------------------------
local AH_NAMES = {
    [1]  = 'H2H',           [2]  = 'Dagger',        [3]  = 'Sword',
    [4]  = 'Greatsword',    [5]  = 'Axe',           [6]  = 'Greataxe',
    [7]  = 'Scythe',        [8]  = 'Polearm',       [9]  = 'Katana',
    [10] = 'Greatkatana',   [11] = 'Club',          [12] = 'Staff',
    [13] = 'Bow',           [14] = 'Instruments',   [15] = 'Ammunition',
    [16] = 'Shield',        [17] = 'Head',          [18] = 'Body',
    [19] = 'Hands',         [20] = 'Legs',          [21] = 'Feet',
    [22] = 'Neck',          [23] = 'Waist',         [24] = 'Earrings',
    [25] = 'Rings',         [26] = 'Back',
    [28] = 'White Magic',   [29] = 'Black Magic',   [30] = 'Summoning',
    [31] = 'Ninjutsu',      [32] = 'Songs',         [33] = 'Medicines',
    [34] = 'Furnishings',   [35] = 'Crystals',      [36] = 'Cards',
    [37] = 'Cursed Items',  [38] = 'Smithing',      [39] = 'Goldsmithing',
    [40] = 'Clothcraft',    [41] = 'Leathercraft',  [42] = 'Bonecraft',
    [43] = 'Woodworking',   [44] = 'Alchemy',       [45] = 'Geomancy',
    [46] = 'Misc',          [47] = 'Fishing Gear',  [48] = 'Pet Items',
    [49] = 'Ninja Tools',   [50] = 'Beast-made',    [51] = 'Fish',
    [52] = 'Meat & Eggs',   [53] = 'Seafood',       [54] = 'Vegetables',
    [55] = 'Soups',         [56] = 'Breads & Rice', [57] = 'Sweets',
    [58] = 'Drinks',        [59] = 'Ingredients',   [60] = 'Dice',
    [61] = 'Automaton',     [62] = 'Grips',         [63] = 'Alchemy 2',
    [64] = 'Misc 2',        [65] = 'Misc 3',
    [100] = 'Incursion',    [101] = 'Spawners',     [102] = 'Abyssea',
    [103] = 'Limbus',       [104] = 'Ventures',
    [255] = 'Other',
};

local CUSTOM_ORDER = {
    [100] = 1, [101] = 2, [102] = 3, [103] = 4, [104] = 5,
};

------------------------------------------------------------
-- Colors
------------------------------------------------------------
local COLORS = {
    header       = { 0.80, 0.60, 1.00, 1.00 },
    accent       = { 0.65, 0.45, 0.90, 1.00 },
    dimmed       = { 0.50, 0.50, 0.55, 1.00 },
    qty          = { 0.90, 0.75, 1.00, 1.00 },
    qtyLow       = { 1.00, 0.70, 0.40, 1.00 },
    category     = { 0.55, 0.80, 0.55, 1.00 },
    searchHint   = { 0.40, 0.40, 0.45, 1.00 },
    headerBg     = { 0.18, 0.12, 0.25, 1.00 },
    catBtnBg     = { 0.14, 0.10, 0.20, 1.00 },
    empty        = { 0.60, 0.55, 0.70, 0.80 },
    selected     = { 0.25, 0.18, 0.38, 0.90 },
    btnWithdraw  = { 0.35, 0.25, 0.55, 1.00 },
    btnHover     = { 0.45, 0.35, 0.65, 1.00 },
    btnActive    = { 0.55, 0.40, 0.75, 1.00 },
    btnDimmed    = { 0.20, 0.18, 0.25, 0.50 },
    btnFeature   = { 0.30, 0.30, 0.50, 1.00 },
    btnFeatureH  = { 0.40, 0.40, 0.60, 1.00 },
    btnFeatureA  = { 0.50, 0.50, 0.70, 1.00 },
    btnStore     = { 0.25, 0.45, 0.30, 1.00 },
    btnStoreH    = { 0.30, 0.55, 0.35, 1.00 },
    btnStoreA    = { 0.35, 0.65, 0.40, 1.00 },
    btnBack      = { 0.25, 0.22, 0.32, 1.00 },
    btnBackH     = { 0.35, 0.30, 0.45, 1.00 },
    btnBackA     = { 0.45, 0.38, 0.55, 1.00 },
    panelBg      = { 0.10, 0.08, 0.15, 0.95 },
    desc         = { 0.70, 0.70, 0.75, 1.00 },
    white        = { 1.00, 1.00, 1.00, 1.00 },
    yellow       = { 1.00, 0.92, 0.60, 1.00 },
    blue         = { 0.55, 0.75, 1.00, 1.00 },
    green        = { 0.55, 0.90, 0.55, 1.00 },
    rare         = { 1.00, 0.85, 0.30, 1.00 },
    ex           = { 0.40, 0.90, 0.40, 1.00 },
    rareBg       = { 0.40, 0.35, 0.10, 0.80 },
    exBg         = { 0.10, 0.35, 0.15, 0.80 },
    slotText     = { 0.80, 0.80, 0.85, 1.00 },
    jobText      = { 0.85, 0.80, 0.95, 1.00 },
    statusErr    = { 1.00, 0.55, 0.55, 1.00 },
    statusOk     = { 0.55, 0.90, 0.55, 1.00 },
    breadcrumb   = { 0.70, 0.65, 0.85, 1.00 },
    currencyName = { 0.95, 0.90, 0.70, 1.00 },
    currencyTotal= { 1.00, 0.95, 0.75, 1.00 },
    currencyBrk  = { 0.65, 0.65, 0.70, 1.00 },
    pointsGroup  = { 0.55, 0.75, 1.00, 1.00 },
    pointsLabel  = { 0.90, 0.90, 0.95, 1.00 },
    pointsValue  = { 1.00, 0.95, 0.75, 1.00 },
};

------------------------------------------------------------
-- Item flag constants
------------------------------------------------------------
local FLAG_RARE = 0x8000;
local FLAG_EX   = 0x4000;

------------------------------------------------------------
-- Lookup tables
------------------------------------------------------------
local JOB_ABBR = {
    'WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD',
    'RNG','SAM','NIN','DRG','SMN','BLU','COR','PUP','DNC','SCH',
    'GEO','RUN',
};

local SLOT_NAMES = {
    [0x0001] = 'Main',  [0x0002] = 'Sub',    [0x0004] = 'Range',
    [0x0008] = 'Ammo',  [0x0010] = 'Head',   [0x0020] = 'Body',
    [0x0040] = 'Hands', [0x0080] = 'Legs',   [0x0100] = 'Feet',
    [0x0200] = 'Neck',  [0x0400] = 'Waist',  [0x0800] = 'L.Ear',
    [0x1000] = 'R.Ear', [0x2000] = 'L.Ring', [0x4000] = 'R.Ring',
    [0x8000] = 'Back',
};

local WEAPON_SKILLS = {
    [1] = 'Hand-to-Hand', [2] = 'Dagger',     [3] = 'Sword',
    [4] = 'Great Sword',  [5] = 'Axe',        [6] = 'Great Axe',
    [7] = 'Scythe',       [8] = 'Polearm',    [9] = 'Katana',
    [10] = 'Great Katana', [11] = 'Club',      [12] = 'Staff',
    [25] = 'Archery',     [26] = 'Marksmanship', [27] = 'Throwing',
};

local QTY_BUTTONS = {
    { label = 'x1',  qty = 1  },
    { label = 'x3',  qty = 3  },
    { label = 'x6',  qty = 6  },
    { label = 'x12', qty = 12 },
    { label = 'x99', qty = 99 },
    { label = '...',  qty = 0  },
};

------------------------------------------------------------
-- Item helpers
------------------------------------------------------------
local function getSlotName(slots)
    if slots == nil or slots == 0 then return nil; end
    for mask, name in pairs(SLOT_NAMES) do
        if bit.band(slots, mask) ~= 0 then return name; end
    end
    return nil;
end

local function getJobList(jobs)
    if jobs == nil or jobs == 0 then return nil; end
    -- Ashita's resource Jobs field follows the DAT convention: bit N = job N,
    -- i.e. bit 1 = WAR, bit 2 = MNK, ..., bit 22 = RUN (bit 0 is NONE). This
    -- differs from the server's packed form and from how `1 << (job-1)` is
    -- used server-side. All-jobs here is bits 1..22 = 0x7FFFFE.
    if bit.band(jobs, 0x7FFFFE) == 0x7FFFFE then return 'All Jobs'; end
    local list = {};
    for i = 1, 22 do
        if bit.band(jobs, bit.lshift(1, i)) ~= 0 then
            table.insert(list, JOB_ABBR[i]);
        end
    end
    return table.concat(list, '/');
end

local function getItemRes(itemId)
    if itemId == nil or itemId == 0 then return nil; end
    return AshitaCore:GetResourceManager():GetItemById(itemId);
end

ffi.cdef[[
    int MultiByteToWideChar(uint32_t CodePage, uint32_t dwFlags, const char* lpMultiByteStr, int cbMultiByte, wchar_t* lpWideCharStr, int cchWideChar);
    int WideCharToMultiByte(uint32_t CodePage, uint32_t dwFlags, const wchar_t* lpWideCharStr, int cchWideChar, char* lpMultiByteStr, int cbMultiByte, const char* lpDefaultChar, int* lpUsedDefaultChar);
]]

local function shiftjis_to_utf8(input)
    if input == nil then return nil; end
    local buf  = ffi.new('char[4096]');
    ffi.copy(buf, input);
    local wbuf = ffi.new('wchar_t[4096]');
    ffi.C.MultiByteToWideChar(932, 0, buf, -1, wbuf, 4096);
    ffi.C.WideCharToMultiByte(65001, 0, wbuf, -1, buf, 4096, nil, nil);
    return ffi.string(buf);
end

local function getItemString(res, field, index)
    if res == nil then return nil; end
    local val = res[field][index or 1];
    if val == nil then return nil; end
    return shiftjis_to_utf8(val);
end

------------------------------------------------------------
-- Texture cache (game item icons + file-based images)
------------------------------------------------------------
local textureCache = {};
local fileTextures = {};  -- filename -> texture

local function loadItemTexture(itemId)
    if textureCache[itemId] ~= nil then return textureCache[itemId]; end
    if itemId == nil or itemId == 0 then textureCache[itemId] = false; return false; end

    local item = getItemRes(itemId);
    if item == nil or item.ImageSize == 0 then textureCache[itemId] = false; return false; end

    local ptr = ffi.new('IDirect3DTexture8*[1]');
    if (C.D3DXCreateTextureFromFileInMemoryEx(
        d3d8dev, item.Bitmap, item.ImageSize,
        0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
        C.D3DFMT_A8R8G8B8, C.D3DPOOL_MANAGED,
        C.D3DX_DEFAULT, C.D3DX_DEFAULT,
        0xFF000000, nil, nil, ptr) ~= C.S_OK) then
        textureCache[itemId] = false; return false;
    end

    local tex = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
    textureCache[itemId] = tex;
    return tex;
end

local function loadFileTexture(filename)
    if fileTextures[filename] ~= nil then return fileTextures[filename]; end
    local path = string.format('%s/images/%s', addon.path, filename);
    local ptr = ffi.new('IDirect3DTexture8*[1]');
    if C.D3DXCreateTextureFromFileA(d3d8dev, path, ptr) ~= C.S_OK then
        fileTextures[filename] = false;
        return false;
    end
    local tex = ffi.new('IDirect3DTexture8*', ptr[0]);
    d3d.gc_safe_release(tex);
    fileTextures[filename] = tex;
    return tex;
end

------------------------------------------------------------
-- Packet I/O
------------------------------------------------------------
local function makePacket()
    local p = {};
    for i = 1, 64 do p[i] = 0; end
    return p;
end

local function writeU16(packet, offset, value)
    packet[offset + 1] = bit.band(value, 0xFF);
    packet[offset + 2] = bit.band(bit.rshift(value, 8), 0xFF);
end

local function writeU32(packet, offset, value)
    packet[offset + 1] = bit.band(value, 0xFF);
    packet[offset + 2] = bit.band(bit.rshift(value, 8),  0xFF);
    packet[offset + 3] = bit.band(bit.rshift(value, 16), 0xFF);
    packet[offset + 4] = bit.band(bit.rshift(value, 24), 0xFF);
end

local function writeString(packet, offset, str, maxLen)
    local len = math.min(#str, maxLen);
    for i = 1, len do
        packet[offset + i] = str:byte(i);
    end
end

local function sendAction(action)
    local p = makePacket();
    p[5] = action;
    AshitaCore:GetPacketManager():AddOutgoingPacket(PACKET_ID, p);
end

local function sendGetSummary()    sendAction(C2S.GET_SUMMARY);    end
local function sendGetCurrency()   sendAction(C2S.GET_CURRENCY);   end
local function sendGetPoints()     sendAction(C2S.GET_POINTS);     end
local function sendGetSquire()     sendAction(C2S.GET_SQUIRE);     end

local function sendGetCategory(ahCat)
    local p = makePacket();
    p[5]  = C2S.GET_CATEGORY;
    p[11] = ahCat;
    AshitaCore:GetPacketManager():AddOutgoingPacket(PACKET_ID, p);
end

local function sendSearch(search)
    local p = makePacket();
    p[5] = C2S.SEARCH;
    writeString(p, 0x10, search, 31);
    AshitaCore:GetPacketManager():AddOutgoingPacket(PACKET_ID, p);
end

local function sendWithdraw(itemId, qty)
    local p = makePacket();
    p[5] = C2S.WITHDRAW;
    writeU16(p, 0x08, itemId);
    writeU32(p, 0x0C, qty);
    AshitaCore:GetPacketManager():AddOutgoingPacket(PACKET_ID, p);
end

------------------------------------------------------------
-- Packet parse helpers (S2C)
------------------------------------------------------------
local function readU16(data, offset)
    local lo = struct.unpack('B', data, offset + 1);
    local hi = struct.unpack('B', data, offset + 2);
    return lo + bit.lshift(hi, 8);
end

local function readU32(data, offset)
    local b0 = struct.unpack('B', data, offset + 1);
    local b1 = struct.unpack('B', data, offset + 2);
    local b2 = struct.unpack('B', data, offset + 3);
    local b3 = struct.unpack('B', data, offset + 4);
    return b0 + bit.lshift(b1, 8) + bit.lshift(b2, 16) + bit.lshift(b3, 24);
end

local function readI32(data, offset)
    local v = readU32(data, offset);
    if v >= 0x80000000 then v = v - 0x100000000; end
    return v;
end

local function readString(data, offset, maxLen)
    local bytes = {};
    for i = 1, maxLen do
        local b = struct.unpack('B', data, offset + i);
        if b == 0 then break; end
        table.insert(bytes, string.char(b));
    end
    return table.concat(bytes);
end

local function addCommas(n)
    if n == nil or n == 0 then return tostring(n or 0); end
    return tostring(n):reverse():gsub('(%d%d%d)', '%1,'):gsub(',(%-?)$', '%1'):reverse();
end

------------------------------------------------------------
-- State
------------------------------------------------------------

-- Tabs
local TAB_EBOX     = 1;
local TAB_CURRENCY = 2;
local TAB_POINTS   = 3;
local TAB_SQUIRE   = 4;

local state = {
    -- Player capability
    isCrystalWarrior = true,  -- assume until proven otherwise
    cwChecked        = false,

    -- E.Box state
    summary         = {},
    summaryTotal    = 0,
    summaryQty      = 0,
    items           = {},
    viewTotal       = 0,
    viewQty         = 0,
    currentCategory = nil,
    searchActive    = false,
    isLocked        = false,
    lockMsg         = '',

    -- Currency state
    currency         = {},
    currencyLoaded   = false,

    -- Points state
    points        = {},
    pointsLoaded  = false,

    -- Squire state
    squire        = {},
    squireLoaded  = false,

    -- Active tab
    activeTab      = TAB_EBOX,
    pendingRequest = nil,  -- which request we're waiting for: 'ebox_summary' | 'ebox_category' | 'ebox_search' | 'currency' | 'points'

    -- Prevents spam-clicking withdraw buttons before the server ACKs.
    -- The server has its own race-safe re-read inside the 500ms timer, but
    -- this also improves UX by showing the buttons as disabled.
    withdrawInFlight = false,
    withdrawUntil    = 0,

    -- Status
    statusMsg     = '',
    statusIsErr   = false,
    statusUntil   = 0,

    -- Cache bookkeeping. 0 means "never fetched".
    -- Switching tabs / reopening the window within the TTL skips the request.
    fetchedAt = {
        summary  = 0,
        currency = 0,
        points   = 0,
        squire   = 0,
    },

    -- Per-category item cache for E.Box drill-down. Keeps the items table
    -- plus totals so we can restore a category view without a roundtrip.
    --   [ahCat] = { fetchedAt, items, viewTotal, viewQty }
    categoryCache = {},
};

------------------------------------------------------------
-- Cache TTLs (seconds)
------------------------------------------------------------
-- Tuned to the change frequency of each data source:
--   E.Box: mutates on any withdraw/store. Short TTL, but we also invalidate
--   explicitly after addon-driven actions so the TTL is mostly a safety net.
--   Currency can change from any reward drop, so keep it tight.
--   Points and Squire change rarely; longer TTL keeps tab-hopping free.
local TTL = {
    summary  = 60,
    category = 60,
    currency = 60,
    points   = 120,
    squire   = 300,
};

------------------------------------------------------------
-- Cache helpers
------------------------------------------------------------
local function cacheFresh(fetchedAt, ttl)
    return fetchedAt > 0 and (os.clock() - fetchedAt) < ttl;
end

local function invalidateSummary()     state.fetchedAt.summary  = 0; end
local function invalidateCurrency()    state.fetchedAt.currency = 0; end
local function invalidatePoints()      state.fetchedAt.points   = 0; end
local function invalidateSquire()      state.fetchedAt.squire   = 0; end
local function invalidateCategories()  state.categoryCache      = {}; end

-- Anything that mutates the ebox (addon withdraw, /box passthrough, !box chat)
-- dirties the summary and every category view.
local function invalidateEbox()
    invalidateSummary();
    invalidateCategories();
end

local ui = {
    isOpen       = { false },
    searchBuf    = { '' },
    searchSize   = 32,
    selectedItem = nil,
    keybindDone  = false,
};

local searchDebounce = {
    lastBuf = '', changedAt = 0, delay = 0.3, pending = false,
};

local function setStatus(msg, isErr)
    state.statusMsg   = msg or '';
    state.statusIsErr = isErr or false;
    state.statusUntil = os.clock() + 4;
end

------------------------------------------------------------
-- View transitions (E.Box)
------------------------------------------------------------
local function goToSummary()
    state.currentCategory = nil;
    state.searchActive    = false;
    state.items           = {};
    ui.selectedItem       = nil;
    ui.searchBuf[1]       = '';
    searchDebounce.lastBuf = '';
    searchDebounce.pending = false;

    -- Only refetch the summary if the cached copy has aged past TTL. The
    -- existing state.summary / state.summaryTotal / state.summaryQty remain
    -- valid when the cache is fresh, so the render uses them directly.
    if cacheFresh(state.fetchedAt.summary, TTL.summary) then
        state.pendingRequest = nil;
        return;
    end

    state.pendingRequest = 'ebox_summary';
    sendGetSummary();
end

local function goToCategory(ahCat)
    state.currentCategory = ahCat;
    state.searchActive    = false;
    ui.selectedItem       = nil;

    local cached = state.categoryCache[ahCat];
    if cached and cacheFresh(cached.fetchedAt, TTL.category) then
        -- Serve cached items; no packet needed.
        state.items          = cached.items;
        state.viewTotal      = cached.viewTotal;
        state.viewQty        = cached.viewQty;
        state.pendingRequest = nil;
        return;
    end

    state.items          = {};
    state.pendingRequest = 'ebox_category';
    sendGetCategory(ahCat);
end

local function refreshCurrentView()
    if state.activeTab == TAB_EBOX then
        if state.searchActive and ui.searchBuf[1] ~= '' then
            state.pendingRequest = 'ebox_search';
            sendSearch(ui.searchBuf[1]);
        elseif state.currentCategory ~= nil then
            state.pendingRequest = 'ebox_category';
            sendGetCategory(state.currentCategory);
        else
            state.pendingRequest = 'ebox_summary';
            sendGetSummary();
        end
    elseif state.activeTab == TAB_CURRENCY then
        state.pendingRequest = 'currency';
        sendGetCurrency();
    elseif state.activeTab == TAB_POINTS then
        state.pendingRequest = 'points';
        sendGetPoints();
    elseif state.activeTab == TAB_SQUIRE then
        state.pendingRequest = 'squire';
        sendGetSquire();
    end
end

local function applySearch(str)
    if str == '' then
        if state.searchActive then
            state.searchActive = false;
            state.items = {};
            if state.currentCategory ~= nil then
                state.pendingRequest = 'ebox_category';
                sendGetCategory(state.currentCategory);
            else
                state.pendingRequest = 'ebox_summary';
                sendGetSummary();
            end
        end
    else
        state.searchActive = true;
        state.items = {};
        ui.selectedItem = nil;
        state.pendingRequest = 'ebox_search';
        sendSearch(str);
    end
end

------------------------------------------------------------
-- Tab activation
------------------------------------------------------------
-- Cache-respecting variant of refreshCurrentView used by tab switches and
-- window-open toggles. Only issues a packet if the relevant cache is stale.
-- Falls through to refreshCurrentView semantics (force fetch) when cache
-- is missing or expired.
local function ensureCurrentView()
    if state.activeTab == TAB_EBOX then
        if state.searchActive and ui.searchBuf[1] ~= '' then
            -- Search results aren't cached — always re-issue.
            state.pendingRequest = 'ebox_search';
            sendSearch(ui.searchBuf[1]);
        elseif state.currentCategory ~= nil then
            local cached = state.categoryCache[state.currentCategory];
            if cached and cacheFresh(cached.fetchedAt, TTL.category) then
                state.items          = cached.items;
                state.viewTotal      = cached.viewTotal;
                state.viewQty        = cached.viewQty;
                state.pendingRequest = nil;
                return;
            end
            state.items          = {};
            state.pendingRequest = 'ebox_category';
            sendGetCategory(state.currentCategory);
        else
            if cacheFresh(state.fetchedAt.summary, TTL.summary) then
                state.pendingRequest = nil;
                return;
            end
            state.pendingRequest = 'ebox_summary';
            sendGetSummary();
        end
    elseif state.activeTab == TAB_CURRENCY then
        if cacheFresh(state.fetchedAt.currency, TTL.currency) then
            state.pendingRequest = nil;
            return;
        end
        state.pendingRequest = 'currency';
        state.currency       = {};
        sendGetCurrency();
    elseif state.activeTab == TAB_POINTS then
        if cacheFresh(state.fetchedAt.points, TTL.points) then
            state.pendingRequest = nil;
            return;
        end
        state.pendingRequest = 'points';
        state.points         = {};
        sendGetPoints();
    elseif state.activeTab == TAB_SQUIRE then
        if cacheFresh(state.fetchedAt.squire, TTL.squire) then
            state.pendingRequest = nil;
            return;
        end
        state.pendingRequest = 'squire';
        state.squire         = {};
        sendGetSquire();
    end
end

local function onTabActivated(tab)
    state.activeTab = tab;
    if tab == TAB_EBOX and not state.isCrystalWarrior then return; end
    ensureCurrentView();
end

------------------------------------------------------------
-- Packet handler (S2C)
------------------------------------------------------------
ashita.events.register('packet_in', 'trove_packet_in', function(e)
    if e.id ~= PACKET_ID then return; end
    e.blocked = true;

    local action = struct.unpack('B', e.data_modified, 0x04 + 1);

    if action == S2C.CLEAR then
        if state.pendingRequest == 'currency' then
            state.currency = {};
        elseif state.pendingRequest == 'points' then
            state.points = {};
        elseif state.pendingRequest == 'squire' then
            state.squire = {};
        else
            state.items = {};
            state.viewTotal = 0;
            state.viewQty   = 0;
        end
        return;
    end

    if action == S2C.ITEM then
        local itemId = readU16(e.data_modified, 0x08);
        local ahCat  = struct.unpack('B', e.data_modified, 0x0A + 1);
        local qty    = readU32(e.data_modified, 0x0C);
        local name   = readString(e.data_modified, 0x10, 31);

        state.items[itemId] = { id = itemId, name = name, qty = qty, ahCat = ahCat };
        return;
    end

    if action == S2C.END_LIST then
        local now = os.clock();
        if state.pendingRequest == 'currency' then
            state.currencyLoaded      = true;
            state.fetchedAt.currency  = now;
        elseif state.pendingRequest == 'points' then
            state.pointsLoaded        = true;
            state.fetchedAt.points    = now;
        elseif state.pendingRequest == 'squire' then
            state.squireLoaded        = true;
            state.fetchedAt.squire    = now;
        else
            state.viewTotal = readU16(e.data_modified, 0x08);
            state.viewQty   = readU32(e.data_modified, 0x0C);

            -- Cache the newly-streamed items for this category so future
            -- drill-downs within the TTL don't need to hit the server.
            -- Search results are intentionally not cached.
            if state.pendingRequest == 'ebox_category' and state.currentCategory ~= nil then
                state.categoryCache[state.currentCategory] = {
                    fetchedAt = now,
                    items     = state.items,
                    viewTotal = state.viewTotal,
                    viewQty   = state.viewQty,
                };
            end
        end
        state.pendingRequest = nil;
        return;
    end

    if action == S2C.SUMMARY then
        local entryCount = struct.unpack('B', e.data_modified, 0x05 + 1);
        local entries = {};
        local totalItems = 0;
        local totalQty   = 0;

        for i = 0, entryCount - 1 do
            local off   = 0x08 + i * 7;
            local ahCat = struct.unpack('B', e.data_modified, off + 1);
            local count = readU16(e.data_modified, off + 1);
            local qty   = readU32(e.data_modified, off + 3);
            table.insert(entries, { ahCat = ahCat, count = count, totalQty = qty });
            totalItems = totalItems + count;
            totalQty   = totalQty + qty;
        end

        table.sort(entries, function(a, b)
            local ac, bc = CUSTOM_ORDER[a.ahCat], CUSTOM_ORDER[b.ahCat];
            if ac and bc then return ac < bc;
            elseif ac then return false;
            elseif bc then return true;
            else
                local na = AH_NAMES[a.ahCat] or 'zzz';
                local nb = AH_NAMES[b.ahCat] or 'zzz';
                return na < nb;
            end
        end);

        state.summary          = entries;
        state.summaryTotal     = totalItems;
        state.summaryQty       = totalQty;
        state.isLocked         = false;
        state.pendingRequest   = nil;
        state.fetchedAt.summary = os.clock();
        -- Confirmed CW since we got a summary back
        state.isCrystalWarrior = true;
        state.cwChecked        = true;
        return;
    end

    if action == S2C.CURRENCY_ENTRY then
        local iconId    = readU16(e.data_modified, 0x06);
        local section   = readString(e.data_modified, 0x08, 15);
        local name      = readString(e.data_modified, 0x18, 23);
        local total     = readI32(e.data_modified, 0x30);
        local breakdown = readString(e.data_modified, 0x34, 71);

        table.insert(state.currency, {
            iconId    = iconId,
            section   = section,
            name      = name,
            total     = total,
            breakdown = breakdown,
        });
        return;
    end

    if action == S2C.POINTS_ENTRY then
        local group = readString(e.data_modified, 0x08, 19);
        local label = readString(e.data_modified, 0x1C, 23);
        local value = readI32(e.data_modified, 0x34);

        table.insert(state.points, { group = group, label = label, value = value });
        return;
    end

    if action == S2C.SQUIRE_ENTRY then
        local iconId   = readU16(e.data_modified, 0x06);
        local category = readString(e.data_modified, 0x08, 19);
        local subtype  = readString(e.data_modified, 0x1C, 23);
        local name     = readString(e.data_modified, 0x34, 23);
        local tier     = readString(e.data_modified, 0x4C, 7);

        table.insert(state.squire, {
            iconId   = iconId,
            category = category,
            subtype  = subtype,
            name     = name,
            tier     = tier,
        });
        return;
    end

    if action == S2C.ACK then
        local requestAction = struct.unpack('B', e.data_modified, 0x05 + 1);
        local success       = struct.unpack('B', e.data_modified, 0x06 + 1);
        local message       = readString(e.data_modified, 0x10, 31);

        -- Clear in-flight flag as soon as any WITHDRAW ACK arrives
        if requestAction == C2S.WITHDRAW then
            state.withdrawInFlight = false;
        end

        if success == 0 and message ~= '' then
            setStatus(message, true);
        end

        if success == 1 and requestAction == C2S.WITHDRAW then
            -- Withdraw changed ebox state on the server. Invalidate the ebox
            -- caches so the scheduled refresh actually hits the server and
            -- reconciles the new quantities.
            invalidateEbox();
            ashita.tasks.once(0.8, function()
                refreshCurrentView();
                if state.currentCategory ~= nil or state.searchActive then
                    sendGetSummary();
                end
            end);
        end
        return;
    end

    if action == S2C.LOCKED then
        local reason = struct.unpack('B', e.data_modified, 0x05 + 1);
        local msg    = readString(e.data_modified, 0x10, 31);

        if reason == LOCK_REASON_NOT_CW then
            -- Not a Crystal Warrior -> hide E.Box tab entirely
            state.isCrystalWarrior = false;
            state.cwChecked        = true;
            -- If user was on E.Box tab, switch away
            if state.activeTab == TAB_EBOX then
                state.activeTab = TAB_CURRENCY;
                onTabActivated(TAB_CURRENCY);
            end
        else
            state.isLocked = true;
            state.lockMsg  = msg;
            state.cwChecked = true;
        end
        state.pendingRequest = nil;
        return;
    end
end);

------------------------------------------------------------
-- Groupings for display
------------------------------------------------------------
local function getFilteredGroups()
    local groups = {};
    local totalItems = 0;
    local totalQty   = 0;

    for _, item in pairs(state.items) do
        if item.qty > 0 then
            local cat = AH_NAMES[item.ahCat] or 'Other';
            if groups[cat] == nil then groups[cat] = {}; end
            table.insert(groups[cat], item);
            totalItems = totalItems + 1;
            totalQty   = totalQty + item.qty;
        end
    end

    local groupAhCat = {};
    for _, item in pairs(state.items) do
        if item.qty > 0 then
            local catName = AH_NAMES[item.ahCat] or 'Other';
            groupAhCat[catName] = item.ahCat;
        end
    end

    local ordered = {};
    for catName, items in pairs(groups) do
        table.sort(items, function(a, b) return a.name < b.name end);
        table.insert(ordered, { category = catName, items = items, ahCat = groupAhCat[catName] or 0 });
    end
    table.sort(ordered, function(a, b)
        local ac, bc = CUSTOM_ORDER[a.ahCat], CUSTOM_ORDER[b.ahCat];
        if ac and bc then return ac < bc;
        elseif ac then return false;
        elseif bc then return true;
        else return a.category < b.category; end
    end);

    return ordered, totalItems, totalQty;
end

local function getFlatItems()
    local list = {};
    for _, item in pairs(state.items) do
        if item.qty > 0 then table.insert(list, item); end
    end
    table.sort(list, function(a, b) return a.name < b.name end);
    return list;
end

------------------------------------------------------------
-- Render helpers (icons, badges, tooltips, item rows)
------------------------------------------------------------
local function renderIcon(itemId, size)
    local tex = loadItemTexture(itemId);
    if tex and tex ~= false then
        imgui.Image(tonumber(ffi.cast('uint32_t', tex)), { size, size });
        return true;
    end
    return false;
end

local function renderBadges(flags)
    if flags == nil or flags == 0 then return; end
    local isRare = bit.band(flags, FLAG_RARE) ~= 0;
    local isEx   = bit.band(flags, FLAG_EX) ~= 0;
    if not isRare and not isEx then return; end

    if isRare then
        imgui.PushStyleColor(ImGuiCol_Button, COLORS.rareBg);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.rareBg);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.rareBg);
        imgui.PushStyleColor(ImGuiCol_Text, COLORS.rare);
        imgui.SmallButton('Rare');
        imgui.PopStyleColor(4);
    end
    if isEx then
        if isRare then imgui.SameLine(0, 4); end
        imgui.PushStyleColor(ImGuiCol_Button, COLORS.exBg);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.exBg);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.exBg);
        imgui.PushStyleColor(ImGuiCol_Text, COLORS.ex);
        imgui.SmallButton('Ex');
        imgui.PopStyleColor(4);
    end
end

local function renderItemDetail(res, storedQty)
    if res == nil then return; end

    local isEquip  = (res.Level > 0 or res.Jobs > 0 or res.Slots > 0);
    local isWeapon = (res.Damage > 0 and res.Delay > 0 and res.Skill > 0);

    if storedQty ~= nil then
        imgui.TextColored(COLORS.dimmed, 'Stored:');
        imgui.SameLine();
        local qc = (storedQty <= 5) and COLORS.qtyLow or COLORS.qty;
        imgui.TextColored(qc, tostring(storedQty));
    end

    renderBadges(res.Flags);

    if res.StackSize > 1 then
        imgui.TextColored(COLORS.dimmed, string.format('Stack: %d', res.StackSize));
    end

    if isEquip then
        if isWeapon then
            local skill = WEAPON_SKILLS[res.Skill] or 'Unknown';
            imgui.TextColored(COLORS.slotText, string.format('(%s)', skill));
        elseif res.Slots > 0 then
            local slot = getSlotName(res.Slots);
            if slot then imgui.TextColored(COLORS.slotText, string.format('[%s]', slot)); end
        end

        if isWeapon then
            imgui.TextColored(COLORS.yellow, string.format('DMG:%d  Delay:%d', res.Damage, res.Delay));
        end
    end

    local desc = getItemString(res, 'Description', 1);
    if desc ~= nil and #desc > 0 then
        -- Weapons have "DMG:N Delay:N" at the start of the description, which
        -- we already render in yellow above. Strip it so it's not duplicated.
        -- Hand-to-Hand weapons use "DMG:+N" / "Delay:+N" (signed), so allow
        -- a leading + or -. The trailing class stays whitespace-only so any
        -- other stats that share the line (e.g. "... HP+35 STR+4") survive.
        if isWeapon then
            desc = desc:gsub("^%s*DMG:%s*[%+%-]?%d+%s*Delay:%s*[%+%-]?%d+%s*[\r\n]*", "")
        end
        if #desc > 0 then
            imgui.Spacing();
            imgui.PushTextWrapPos(imgui.GetContentRegionAvail() + imgui.GetCursorPosX());
            imgui.TextColored(COLORS.desc, desc);
            imgui.PopTextWrapPos();
        end
    end

    -- Level / jobs line sits beneath the description on equipment so the
    -- requirement info reads as a footer rather than a header.
    if isEquip and (res.Level > 0 or res.Jobs > 0) then
        local jobStr = getJobList(res.Jobs) or '';
        local lvlStr = '';
        if res.Level > 0 then
            lvlStr = string.format('Lv%d ', res.Level);
            if res.ItemLevel > 0 and res.ItemLevel ~= res.Level then
                lvlStr = string.format('Lv%d (iLv%d) ', res.Level, res.ItemLevel);
            end
        end
        imgui.Spacing();
        imgui.TextColored(COLORS.jobText, lvlStr .. jobStr);
    end
end

local function renderTooltip(item)
    imgui.SetNextWindowSize({ 400, -1 }, ImGuiCond_Always);
    imgui.BeginTooltip();
    imgui.PushTextWrapPos(380);

    local tex = loadItemTexture(item.id);
    if tex and tex ~= false then
        imgui.Image(tonumber(ffi.cast('uint32_t', tex)), { 32, 32 });
        imgui.SameLine();
    end

    imgui.TextColored(COLORS.header, item.name);
    imgui.Separator();

    local res = getItemRes(item.id);
    renderItemDetail(res, item.qty);

    imgui.PopTextWrapPos();
    imgui.EndTooltip();
end

local function renderItemRow(item, index)
    local isSelected = (ui.selectedItem ~= nil and ui.selectedItem.id == item.id);
    local isAlt      = (index % 2 == 0);
    local rowId      = string.format('##row_%d_%d', item.id, index);

    local bgColor = isSelected and COLORS.selected
        or (isAlt and { 0.12, 0.10, 0.16, 0.35 } or { 0.12, 0.10, 0.16, 0.20 });

    imgui.PushStyleColor(ImGuiCol_ChildBg, bgColor);
    imgui.BeginChild(rowId, { -1, 28 }, false);

    if isSelected then
        local dl = imgui.GetWindowDrawList();
        local wx, wy = imgui.GetWindowPos();
        dl:AddRectFilled({ wx, wy }, { wx + 2, wy + 28 }, imgui.GetColorU32(COLORS.accent));
    end

    imgui.SetCursorPos({ 6, 2 });
    if not renderIcon(item.id, 24) then imgui.Dummy({ 24, 24 }); end
    imgui.SameLine(34);

    imgui.SetCursorPosY(0);
    if imgui.Selectable(string.format('##sel_%d_%d', item.id, index), isSelected,
        ImGuiSelectableFlags_SpanAllColumns, { 0, 28 }) then
        ui.selectedItem = isSelected and nil or item;
    end

    if imgui.IsItemHovered() then renderTooltip(item); end

    local dl  = imgui.GetWindowDrawList();
    local wx, wy = imgui.GetWindowPos();
    local ww = imgui.GetWindowWidth();

    -- Compute right-edge layout first so the name can be clipped to fit.
    -- Badges are filled rects + centered text (same look as the tooltip
    -- badges) so the "Ex" / "Rare" labels don't visually hug the quantity.
    local res    = getItemRes(item.id);
    local isRare = res ~= nil and bit.band(res.Flags, FLAG_RARE) ~= 0;
    local isEx   = res ~= nil and bit.band(res.Flags, FLAG_EX)   ~= 0;

    local qtyStr   = string.format('x%d', item.qty);
    local qtyW     = imgui.CalcTextSize(qtyStr);
    local qtyColor = (item.qty <= 5) and COLORS.qtyLow or COLORS.qty;
    local qtyX     = wx + ww - qtyW - 8;

    local GAP         = 6;
    local BADGE_H     = 16;
    local BADGE_PAD_X = 4;  -- horizontal padding inside each badge
    local EX_TEXT_W   = imgui.CalcTextSize('Ex');
    local R_TEXT_W    = imgui.CalcTextSize('R');
    local EX_W        = EX_TEXT_W + BADGE_PAD_X * 2;
    local R_W         = R_TEXT_W  + BADGE_PAD_X * 2;
    local badgeTop    = wy + 6;

    local exX    = isEx   and (qtyX - GAP - EX_W) or qtyX;
    local rareX  = isRare and (exX  - (isEx and GAP or 0) - R_W) or exX;

    -- Truncate the name if it would run into the tag column.
    local nameX    = wx + 34;
    local nameMaxW = (isRare and rareX or (isEx and exX or qtyX)) - GAP - nameX;
    local displayName = item.name or '';
    if imgui.CalcTextSize(displayName) > nameMaxW then
        while #displayName > 1 and imgui.CalcTextSize(displayName .. '...') > nameMaxW do
            displayName = displayName:sub(1, -2);
        end
        displayName = displayName .. '...';
    end

    dl:AddText({ nameX, wy + 7 }, imgui.GetColorU32(COLORS.white), displayName);

    if isRare then
        dl:AddRectFilled({ rareX, badgeTop }, { rareX + R_W, badgeTop + BADGE_H },
            imgui.GetColorU32(COLORS.rareBg));
        dl:AddText({ rareX + BADGE_PAD_X, wy + 7 },
            imgui.GetColorU32(COLORS.rare), 'R');
    end
    if isEx then
        dl:AddRectFilled({ exX, badgeTop }, { exX + EX_W, badgeTop + BADGE_H },
            imgui.GetColorU32(COLORS.exBg));
        dl:AddText({ exX + BADGE_PAD_X, wy + 7 },
            imgui.GetColorU32(COLORS.ex), 'Ex');
    end
    dl:AddText({ qtyX, wy + 7 }, imgui.GetColorU32(qtyColor), qtyStr);

    imgui.EndChild();
    imgui.PopStyleColor(1);
end

local function renderCategoryHeader(cat, catIndex)
    local catId = string.format('##cathdr_%s_%d', cat.category, catIndex);

    imgui.PushStyleColor(ImGuiCol_ChildBg, COLORS.headerBg);
    imgui.BeginChild(catId, { -1, 22 }, false);

    local dl = imgui.GetWindowDrawList();
    local wx, wy = imgui.GetWindowPos();
    dl:AddRectFilled({ wx, wy }, { wx + 3, wy + 22 }, imgui.GetColorU32(COLORS.accent));

    imgui.SetCursorPosX(10);
    imgui.SetCursorPosY(3);
    imgui.TextColored(COLORS.category, cat.category);

    local countStr = string.format('(%d)', #cat.items);
    local ww = imgui.GetWindowWidth();
    imgui.SameLine(ww - imgui.CalcTextSize(countStr) - 12);
    imgui.SetCursorPosY(3);
    imgui.TextColored(COLORS.dimmed, countStr);

    imgui.EndChild();
    imgui.PopStyleColor(1);
end

local function renderCategoryButton(entry, col)
    local name = AH_NAMES[entry.ahCat] or string.format('Cat %d', entry.ahCat);
    local btnId = string.format('##catbtn_%d', entry.ahCat);
    local rowWidth = imgui.GetContentRegionAvail();
    local btnW = (rowWidth - 6) / 2;

    if col == 2 then imgui.SameLine(0, 4); end

    imgui.PushStyleColor(ImGuiCol_ChildBg, COLORS.catBtnBg);
    imgui.BeginChild(btnId, { btnW, 34 }, false);

    local dl = imgui.GetWindowDrawList();
    local wx, wy = imgui.GetWindowPos();
    dl:AddRectFilled({ wx, wy }, { wx + 3, wy + 34 }, imgui.GetColorU32(COLORS.accent));

    imgui.SetCursorPosY(0);
    if imgui.Selectable(string.format('##catsel_%d', entry.ahCat), false,
        ImGuiSelectableFlags_SpanAllColumns, { 0, 34 }) then
        goToCategory(entry.ahCat);
    end

    dl:AddText({ wx + 10, wy + 5 }, imgui.GetColorU32(COLORS.category), name);
    dl:AddText({ wx + 10, wy + 19 }, imgui.GetColorU32(COLORS.dimmed),
        string.format('%d items  |  %s qty', entry.count, addCommas(entry.totalQty)));

    imgui.EndChild();
    imgui.PopStyleColor(1);
end

local function renderSelectionPanel()
    local item = ui.selectedItem;
    if item == nil then return 0; end

    local live = state.items[item.id];
    if live == nil then ui.selectedItem = nil; return 0; end
    item = live;
    ui.selectedItem = live;

    local res = getItemRes(item.id);
    local isEquip = (res ~= nil and (res.Level > 0 or res.Jobs > 0 or res.Slots > 0));
    -- Panel height must clear the 28px icon (at y=6, bottom=34) plus the 22px qty button row.
    local panelH = isEquip and 86 or 70;

    imgui.PushStyleColor(ImGuiCol_ChildBg, COLORS.panelBg);
    imgui.PushStyleColor(ImGuiCol_Border, { 0.65, 0.45, 0.90, 0.60 });
    imgui.BeginChild('##sel_panel', { -1, panelH }, true);

    imgui.SetCursorPos({ 6, 6 });
    renderIcon(item.id, 28);
    imgui.SameLine(40);
    imgui.SetCursorPosY(4);
    imgui.TextColored(COLORS.header, item.name);
    imgui.SameLine();

    local qtyColor = (item.qty <= 5) and COLORS.qtyLow or COLORS.qty;
    imgui.TextColored(qtyColor, string.format('x%d', item.qty));

    if res ~= nil then
        imgui.SameLine(0, 8);
        renderBadges(res.Flags);
    end

    if isEquip and res ~= nil then
        imgui.SetCursorPosX(40);
        local parts = {};
        if res.Damage > 0 and res.Delay > 0 and res.Skill > 0 then
            local skill = WEAPON_SKILLS[res.Skill] or '';
            table.insert(parts, string.format('%s DMG:%d Dly:%d', skill, res.Damage, res.Delay));
        elseif res.Slots > 0 then
            local slot = getSlotName(res.Slots);
            if slot then table.insert(parts, string.format('[%s]', slot)); end
        end
        if res.Level > 0 then table.insert(parts, string.format('Lv%d', res.Level)); end
        local jobStr = getJobList(res.Jobs);
        if jobStr then table.insert(parts, jobStr); end
        imgui.TextColored(COLORS.slotText, table.concat(parts, '  '));
    end

    local btnY = panelH - 28;
    imgui.SetCursorPos({ 6, btnY });

    imgui.PushStyleColor(ImGuiCol_Button, COLORS.btnWithdraw);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.btnHover);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.btnActive);

    -- Safety timeout: clear the in-flight flag if the ACK never comes
    -- (e.g. zone change, packet loss).
    if state.withdrawInFlight and os.clock() > state.withdrawUntil then
        state.withdrawInFlight = false;
    end

    for i, btn in ipairs(QTY_BUTTONS) do
        if i > 1 then imgui.SameLine(0, 4); end

        local canAfford = (btn.qty == 0 or btn.qty <= item.qty);
        local blocked   = (state.withdrawInFlight and btn.qty ~= 0);
        local disabled  = (not canAfford) or blocked;

        if disabled then
            imgui.PushStyleColor(ImGuiCol_Button, COLORS.btnDimmed);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.btnDimmed);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.btnDimmed);
            imgui.PushStyleColor(ImGuiCol_Text, { 0.40, 0.38, 0.45, 0.60 });
        end

        imgui.PushID(string.format('qty_%d_%d', item.id, i));
        if imgui.Button(btn.label, { 38, 22 }) and not disabled then
            if btn.qty == 0 then
                AshitaCore:GetChatManager():QueueCommand(1, string.format('!box %s', item.name));
            else
                sendWithdraw(item.id, btn.qty);
                state.withdrawInFlight = true;
                state.withdrawUntil    = os.clock() + 3.0; -- safety timeout
            end
        end
        imgui.PopID();

        if disabled then imgui.PopStyleColor(4); end

        if imgui.IsItemHovered() then
            imgui.BeginTooltip();
            if btn.qty == 0 then
                imgui.Text('Open in-game withdraw menu');
            else
                imgui.Text(string.format('Withdraw %d', btn.qty));
            end
            imgui.EndTooltip();
        end
    end

    imgui.PopStyleColor(3);
    imgui.EndChild();
    imgui.PopStyleColor(2);

    return panelH + 4;
end

local function renderQuickActions()
    imgui.PushStyleColor(ImGuiCol_Button, COLORS.btnStore);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.btnStoreH);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.btnStoreA);
    if imgui.Button('Store All', { 0, 24 }) then
        AshitaCore:GetChatManager():QueueCommand(1, '!box store');
    end
    if imgui.IsItemHovered() then
        imgui.BeginTooltip(); imgui.Text('Store all storable items'); imgui.EndTooltip();
    end
    imgui.PopStyleColor(3);

    imgui.SameLine();
    imgui.PushStyleColor(ImGuiCol_Button, COLORS.btnFeature);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.btnFeatureH);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.btnFeatureA);

    if imgui.Button('Clusters', { 0, 24 }) then
        AshitaCore:GetChatManager():QueueCommand(1, '!box cluster');
    end
    if imgui.IsItemHovered() then
        imgui.BeginTooltip(); imgui.Text('Withdraw crystal clusters'); imgui.EndTooltip();
    end

    imgui.SameLine();
    if imgui.Button('Ammo', { 0, 24 }) then
        AshitaCore:GetChatManager():QueueCommand(1, '!box ammo');
    end
    if imgui.IsItemHovered() then
        imgui.BeginTooltip(); imgui.Text('Withdraw ammo bundles'); imgui.EndTooltip();
    end

    imgui.PopStyleColor(3);
end

local function renderBreadcrumb()
    imgui.PushStyleColor(ImGuiCol_Button, COLORS.btnBack);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.btnBackH);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.btnBackA);
    if imgui.Button('< Back', { 0, 24 }) then goToSummary(); end
    imgui.PopStyleColor(3);

    imgui.SameLine();

    local label;
    if state.searchActive then
        label = string.format('Search: "%s"', ui.searchBuf[1]);
    elseif state.currentCategory ~= nil then
        label = AH_NAMES[state.currentCategory] or 'Unknown';
    else
        label = '';
    end
    imgui.TextColored(COLORS.breadcrumb, label);
end

-- Small footer shown at the end of the scroll area with counts for the current view.
local function renderViewFooter()
    if state.searchActive then
        local label;
        if state.viewTotal >= 20 then
            label = string.format('Showing first 20 matches (%s qty). Refine your search to see more.', addCommas(state.viewQty));
        else
            label = string.format('%d results  |  %s qty', state.viewTotal, addCommas(state.viewQty));
        end
        imgui.Spacing();
        imgui.TextColored(COLORS.dimmed, '  ' .. label);
    elseif state.currentCategory ~= nil then
        imgui.Spacing();
        imgui.TextColored(COLORS.dimmed, string.format('  %d items  |  %s qty',
            state.viewTotal, addCommas(state.viewQty)));
    else
        -- Summary view
        if #state.summary > 0 then
            imgui.Spacing();
            imgui.TextColored(COLORS.dimmed, string.format(
                '  %d items  |  %s qty',
                state.summaryTotal, addCommas(state.summaryQty)));
        end
    end
end

local function renderStatus()
    if state.statusMsg == '' then return; end
    if os.clock() > state.statusUntil then state.statusMsg = ''; return; end
    local color = state.statusIsErr and COLORS.statusErr or COLORS.statusOk;
    imgui.TextColored(color, state.statusMsg);
end

------------------------------------------------------------
-- E.Box tab content
------------------------------------------------------------
local function renderEboxTab()
    if state.isLocked then
        imgui.Spacing(); imgui.Spacing();
        local msg = (state.lockMsg ~= '') and state.lockMsg or 'Ephemeral Box is locked.';
        local tw  = imgui.CalcTextSize(msg);
        imgui.SetCursorPosX((imgui.GetWindowWidth() - tw) * 0.5);
        imgui.TextColored(COLORS.statusErr, msg);
        return;
    end

    -- Crystal Warrior insignia in the top-left, inline with the action buttons
    local cwTex = loadFileTexture('cw.png');
    if cwTex and cwTex ~= false then
        imgui.Image(tonumber(ffi.cast('uint32_t', cwTex)), { 20, 20 });
        imgui.SameLine(0, 6);
    end

    renderQuickActions();
    imgui.Spacing();

    imgui.PushItemWidth(-1);
    imgui.InputText('##search', ui.searchBuf, ui.searchSize, ImGuiInputTextFlags_None);
    imgui.PopItemWidth();

    if ui.searchBuf[1] == '' then
        local px, py = imgui.GetItemRectMin();
        imgui.GetWindowDrawList():AddText({ px + 8, py + 4 },
            imgui.GetColorU32(COLORS.searchHint), 'Search items...');
    end

    imgui.Spacing();

    local inSummary = (not state.searchActive and state.currentCategory == nil);

    if not inSummary then
        renderBreadcrumb();
    end
    renderStatus();
    imgui.Separator();
    imgui.Spacing();

    local panelH = 0;
    if ui.selectedItem ~= nil then
        local r = getItemRes(ui.selectedItem.id);
        panelH = (r ~= nil and (r.Level > 0 or r.Jobs > 0 or r.Slots > 0)) and 90 or 74;
    end

    imgui.BeginChild('##ebox_scroll', { -1, -panelH }, false);

    if inSummary then
        if #state.summary == 0 then
            imgui.Spacing(); imgui.Spacing(); imgui.Spacing();
            local msg = 'Your Ephemeral Box is empty.';
            local tw = imgui.CalcTextSize(msg);
            imgui.SetCursorPosX((imgui.GetWindowWidth() - tw) * 0.5);
            imgui.TextColored(COLORS.empty, msg);
        else
            for i, entry in ipairs(state.summary) do
                local col = ((i - 1) % 2) + 1;
                renderCategoryButton(entry, col);
            end
            renderViewFooter();
        end
    elseif state.searchActive then
        local groups, totalItems = getFilteredGroups();
        if totalItems == 0 then
            imgui.Spacing(); imgui.Spacing(); imgui.Spacing();
            local msg = string.format('No items matching "%s"', ui.searchBuf[1]);
            local tw = imgui.CalcTextSize(msg);
            imgui.SetCursorPosX((imgui.GetWindowWidth() - tw) * 0.5);
            imgui.TextColored(COLORS.empty, msg);
        else
            for i, cat in ipairs(groups) do
                renderCategoryHeader(cat, i);
                for j, item in ipairs(cat.items) do
                    renderItemRow(item, i * 100 + j);
                end
                imgui.Spacing();
            end
            renderViewFooter();
        end
    else
        local items = getFlatItems();
        if #items == 0 then
            imgui.Spacing(); imgui.Spacing(); imgui.Spacing();
            local msg = 'No items in this category.';
            local tw = imgui.CalcTextSize(msg);
            imgui.SetCursorPosX((imgui.GetWindowWidth() - tw) * 0.5);
            imgui.TextColored(COLORS.empty, msg);
        else
            for i, item in ipairs(items) do
                renderItemRow(item, i);
            end
            renderViewFooter();
        end
    end

    imgui.EndChild();
    renderSelectionPanel();
end

------------------------------------------------------------
-- Currency tab content
------------------------------------------------------------
local function renderCurrencyTab()
    -- Group by section
    local sections = {};
    local sectionOrder = {};
    for _, entry in ipairs(state.currency) do
        local s = entry.section;
        if sections[s] == nil then
            sections[s] = {};
            table.insert(sectionOrder, s);
        end
        table.insert(sections[s], entry);
    end

    -- Refresh button
    imgui.PushStyleColor(ImGuiCol_Button, COLORS.btnFeature);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.btnFeatureH);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.btnFeatureA);
    if imgui.Button('Refresh', { 70, 22 }) then
        state.currency = {};
        state.pendingRequest = 'currency';
        sendGetCurrency();
    end
    imgui.PopStyleColor(3);
    imgui.Separator();
    imgui.Spacing();

    imgui.BeginChild('##currency_scroll', { -1, -1 }, false);

    if #state.currency == 0 then
        if state.pendingRequest == 'currency' then
            imgui.TextColored(COLORS.dimmed, 'Loading...');
        else
            imgui.TextColored(COLORS.empty, 'No currency to display.');
        end
    else
        for _, sectionName in ipairs(sectionOrder) do
            -- Section header
            imgui.PushStyleColor(ImGuiCol_ChildBg, COLORS.headerBg);
            local hdrId = string.format('##cursec_%s', sectionName);
            imgui.BeginChild(hdrId, { -1, 20 }, false);
            local dl = imgui.GetWindowDrawList();
            local wx, wy = imgui.GetWindowPos();
            dl:AddRectFilled({ wx, wy }, { wx + 3, wy + 20 }, imgui.GetColorU32(COLORS.accent));
            imgui.SetCursorPosX(10);
            imgui.SetCursorPosY(2);
            imgui.TextColored(COLORS.category, sectionName);
            imgui.EndChild();
            imgui.PopStyleColor(1);

            -- Entries
            for i, entry in ipairs(sections[sectionName]) do
                local rowId = string.format('##currow_%s_%d', sectionName, i);
                local isAlt = (i % 2 == 0);
                local bg = isAlt and { 0.12, 0.10, 0.16, 0.35 } or { 0.12, 0.10, 0.16, 0.20 };

                imgui.PushStyleColor(ImGuiCol_ChildBg, bg);
                imgui.BeginChild(rowId, { -1, 36 }, false);

                -- Icon
                imgui.SetCursorPos({ 6, 6 });
                if entry.iconId ~= nil and entry.iconId > 0 then
                    if not renderIcon(entry.iconId, 24) then imgui.Dummy({ 24, 24 }); end
                else
                    imgui.Dummy({ 24, 24 });
                end

                -- Name + total on first line, breakdown on second
                local dl2 = imgui.GetWindowDrawList();
                local wx2, wy2 = imgui.GetWindowPos();
                local ww2 = imgui.GetWindowWidth();

                dl2:AddText({ wx2 + 36, wy2 + 4  }, imgui.GetColorU32(COLORS.currencyName),  entry.name);
                dl2:AddText({ wx2 + 36, wy2 + 20 }, imgui.GetColorU32(COLORS.currencyBrk),   entry.breakdown);

                local totalStr = addCommas(entry.total);
                local tw2 = imgui.CalcTextSize(totalStr);
                dl2:AddText({ wx2 + ww2 - tw2 - 8, wy2 + 8 },
                    imgui.GetColorU32(COLORS.currencyTotal), totalStr);

                imgui.EndChild();
                imgui.PopStyleColor(1);
            end

            imgui.Spacing();
        end
    end

    imgui.EndChild();
end

------------------------------------------------------------
-- Points tab content
------------------------------------------------------------
local function renderPointsTab()
    -- Group by group name
    local groups = {};
    local groupOrder = {};
    for _, entry in ipairs(state.points) do
        local g = entry.group;
        if groups[g] == nil then
            groups[g] = {};
            table.insert(groupOrder, g);
        end
        table.insert(groups[g], entry);
    end

    imgui.PushStyleColor(ImGuiCol_Button, COLORS.btnFeature);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.btnFeatureH);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.btnFeatureA);
    if imgui.Button('Refresh', { 70, 22 }) then
        state.points = {};
        state.pendingRequest = 'points';
        sendGetPoints();
    end
    imgui.PopStyleColor(3);
    imgui.Separator();
    imgui.Spacing();

    imgui.BeginChild('##points_scroll', { -1, -1 }, false);

    if #state.points == 0 then
        if state.pendingRequest == 'points' then
            imgui.TextColored(COLORS.dimmed, 'Loading...');
        else
            imgui.TextColored(COLORS.empty, 'No points to display.');
        end
    else
        for _, groupName in ipairs(groupOrder) do
            imgui.PushStyleColor(ImGuiCol_ChildBg, COLORS.headerBg);
            local hdrId = string.format('##ptgrp_%s', groupName);
            imgui.BeginChild(hdrId, { -1, 20 }, false);
            local dl = imgui.GetWindowDrawList();
            local wx, wy = imgui.GetWindowPos();
            dl:AddRectFilled({ wx, wy }, { wx + 3, wy + 20 }, imgui.GetColorU32(COLORS.accent));
            imgui.SetCursorPosX(10);
            imgui.SetCursorPosY(2);
            imgui.TextColored(COLORS.pointsGroup, groupName);
            imgui.EndChild();
            imgui.PopStyleColor(1);

            for i, entry in ipairs(groups[groupName]) do
                local rowId = string.format('##ptrow_%s_%d', groupName, i);
                local isAlt = (i % 2 == 0);
                local bg = isAlt and { 0.12, 0.10, 0.16, 0.35 } or { 0.12, 0.10, 0.16, 0.20 };

                imgui.PushStyleColor(ImGuiCol_ChildBg, bg);
                imgui.BeginChild(rowId, { -1, 22 }, false);

                local dl2 = imgui.GetWindowDrawList();
                local wx2, wy2 = imgui.GetWindowPos();
                local ww2 = imgui.GetWindowWidth();

                dl2:AddText({ wx2 + 10, wy2 + 4 }, imgui.GetColorU32(COLORS.pointsLabel), entry.label);

                local vstr = addCommas(entry.value);
                local tw2 = imgui.CalcTextSize(vstr);
                dl2:AddText({ wx2 + ww2 - tw2 - 10, wy2 + 4 },
                    imgui.GetColorU32(COLORS.pointsValue), vstr);

                imgui.EndChild();
                imgui.PopStyleColor(1);
            end

            imgui.Spacing();
        end
    end

    imgui.EndChild();
end

------------------------------------------------------------
-- Squire tab content
------------------------------------------------------------
-- Order categories the same way the squire system defines them, with custom
-- categories after the standard ones.
local SQUIRE_CATEGORY_ORDER = {
    'Relic +1',
    'AF +1',
    'Novice Trial',
    'Grand Trial',
    'Domain Invasion',
    'Endgame',
    'Crystal Warrior',
    'Yagudo Arena',
    'Incursion',
    'CW Misc.',
};

local function squireCategoryRank(name)
    for i, n in ipairs(SQUIRE_CATEGORY_ORDER) do
        if n == name then return i; end
    end
    return 99; -- unknown categories sort last
end

local function renderSquireTab()
    -- Group entries by category -> subtype
    local byCat  = {};       -- categoryName -> { subtypes = { subName -> items }, order = {} }
    local catOrder = {};     -- preserves first-seen order for unknown cats

    for _, entry in ipairs(state.squire) do
        if byCat[entry.category] == nil then
            byCat[entry.category] = { subtypes = {}, subOrder = {} };
            table.insert(catOrder, entry.category);
        end
        local cat = byCat[entry.category];
        if cat.subtypes[entry.subtype] == nil then
            cat.subtypes[entry.subtype] = {};
            table.insert(cat.subOrder, entry.subtype);
        end
        table.insert(cat.subtypes[entry.subtype], entry);
    end

    -- Sort categories using the predefined order
    table.sort(catOrder, function(a, b) return squireCategoryRank(a) < squireCategoryRank(b); end);

    -- Refresh button
    imgui.PushStyleColor(ImGuiCol_Button, COLORS.btnFeature);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.btnFeatureH);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.btnFeatureA);
    if imgui.Button('Refresh', { 70, 22 }) then
        state.squire = {};
        state.pendingRequest = 'squire';
        sendGetSquire();
    end
    imgui.PopStyleColor(3);

    imgui.SameLine();
    imgui.TextColored(COLORS.dimmed, string.format('%d items stored', #state.squire));
    imgui.Separator();
    imgui.Spacing();

    imgui.BeginChild('##squire_scroll', { -1, -1 }, false);

    if #state.squire == 0 then
        if state.pendingRequest == 'squire' then
            imgui.TextColored(COLORS.dimmed, 'Loading...');
        else
            imgui.TextColored(COLORS.empty, 'Nothing stored with the Squire.');
        end
    else
        for _, catName in ipairs(catOrder) do
            local cat = byCat[catName];

            -- Sort subtypes alphabetically within each category
            table.sort(cat.subOrder);

            -- Category header
            imgui.PushStyleColor(ImGuiCol_ChildBg, COLORS.headerBg);
            local hdrId = string.format('##sqcat_%s', catName);
            imgui.BeginChild(hdrId, { -1, 22 }, false);
            local dl = imgui.GetWindowDrawList();
            local wx, wy = imgui.GetWindowPos();
            dl:AddRectFilled({ wx, wy }, { wx + 3, wy + 22 }, imgui.GetColorU32(COLORS.accent));
            imgui.SetCursorPosX(10);
            imgui.SetCursorPosY(3);
            imgui.TextColored(COLORS.category, catName);

            -- Total items count on right
            local total = 0;
            for _, subName in ipairs(cat.subOrder) do
                total = total + #cat.subtypes[subName];
            end
            local countStr = string.format('(%d)', total);
            local ww = imgui.GetWindowWidth();
            imgui.SameLine(ww - imgui.CalcTextSize(countStr) - 12);
            imgui.SetCursorPosY(3);
            imgui.TextColored(COLORS.dimmed, countStr);
            imgui.EndChild();
            imgui.PopStyleColor(1);

            -- Subtype sections + items
            local rowIdx = 0;
            for _, subName in ipairs(cat.subOrder) do
                local items = cat.subtypes[subName];
                table.sort(items, function(a, b) return a.name < b.name; end);

                -- Subtype label (indented, dim)
                imgui.Indent(6);
                imgui.TextColored(COLORS.dimmed, string.format('%s (%d)', subName, #items));
                imgui.Unindent(6);

                for _, entry in ipairs(items) do
                    rowIdx = rowIdx + 1;
                    local rowId = string.format('##sqrow_%s_%d', catName, rowIdx);
                    local isAlt = (rowIdx % 2 == 0);
                    local bg = isAlt and { 0.12, 0.10, 0.16, 0.35 } or { 0.12, 0.10, 0.16, 0.20 };

                    imgui.PushStyleColor(ImGuiCol_ChildBg, bg);
                    imgui.BeginChild(rowId, { -1, 28 }, false);

                    -- Icon
                    imgui.SetCursorPos({ 16, 2 });
                    if entry.iconId ~= nil and entry.iconId > 0 then
                        if not renderIcon(entry.iconId, 24) then imgui.Dummy({ 24, 24 }); end
                    else
                        imgui.Dummy({ 24, 24 });
                    end
                    imgui.SameLine(44);

                    -- Selectable overlay for tooltip support
                    imgui.SetCursorPosY(0);
                    if imgui.Selectable(string.format('##sqsel_%d', rowIdx), false,
                        ImGuiSelectableFlags_SpanAllColumns, { 0, 28 }) then
                        -- no-op: squire tab is informational
                    end
                    if imgui.IsItemHovered() and entry.iconId ~= nil and entry.iconId > 0 then
                        renderTooltip({ id = entry.iconId, name = entry.name, qty = 1 });
                    end

                    -- Draw text
                    local dl2 = imgui.GetWindowDrawList();
                    local wx2, wy2 = imgui.GetWindowPos();
                    local ww2 = imgui.GetWindowWidth();
                    dl2:AddText({ wx2 + 44, wy2 + 7 }, imgui.GetColorU32(COLORS.white), entry.name);

                    -- Tier on the right (if any)
                    if entry.tier ~= nil and entry.tier ~= '' then
                        local tierStr = entry.tier;
                        local tw = imgui.CalcTextSize(tierStr);
                        dl2:AddText({ wx2 + ww2 - tw - 12, wy2 + 7 },
                            imgui.GetColorU32(COLORS.yellow), tierStr);
                    end

                    imgui.EndChild();
                    imgui.PopStyleColor(1);
                end
            end

            imgui.Spacing();
        end
    end

    imgui.EndChild();
end

------------------------------------------------------------
-- Render: Main window (tab bar)
------------------------------------------------------------
local function renderTab(tabId, label, iconTex)
    -- BeginTabItem doesn't natively support icons - we hack by drawing icon via the draw list
    -- using a spacer label. To keep it simple, we render the icon separately if provided.
    local open = imgui.BeginTabItem(label);
    if open and state.activeTab ~= tabId then
        onTabActivated(tabId);
    end
    return open;
end

local function renderWindow()
    if not ui.isOpen[1] then return; end

    imgui.SetNextWindowSize({ 380, 560 }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSizeConstraints({ 320, 280 }, { 500, 900 });

    imgui.PushStyleColor(ImGuiCol_TitleBg,         { 0.12, 0.08, 0.18, 0.95 });
    imgui.PushStyleColor(ImGuiCol_TitleBgActive,    { 0.18, 0.12, 0.25, 0.95 });
    imgui.PushStyleColor(ImGuiCol_WindowBg,         { 0.06, 0.05, 0.09, 0.92 });
    imgui.PushStyleColor(ImGuiCol_Border,           { 0.30, 0.20, 0.45, 0.60 });
    imgui.PushStyleColor(ImGuiCol_FrameBg,          { 0.14, 0.10, 0.20, 0.80 });
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered,   { 0.20, 0.15, 0.30, 0.80 });
    imgui.PushStyleColor(ImGuiCol_ScrollbarBg,      { 0.06, 0.05, 0.09, 0.50 });
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrab,    { 0.30, 0.20, 0.45, 0.60 });
    imgui.PushStyleColor(ImGuiCol_Tab,              { 0.18, 0.12, 0.25, 0.95 });
    imgui.PushStyleColor(ImGuiCol_TabHovered,       { 0.30, 0.20, 0.45, 0.95 });
    imgui.PushStyleColor(ImGuiCol_TabActive,        { 0.35, 0.25, 0.55, 0.95 });
    -- Selectable / row hover colours (default would be bright red/orange)
    imgui.PushStyleColor(ImGuiCol_Header,           { 0.30, 0.22, 0.42, 0.60 });
    imgui.PushStyleColor(ImGuiCol_HeaderHovered,    { 0.40, 0.28, 0.55, 0.55 });
    imgui.PushStyleColor(ImGuiCol_HeaderActive,     { 0.50, 0.35, 0.70, 0.75 });

    if imgui.Begin('Trove', ui.isOpen, ImGuiWindowFlags_None) then

        if imgui.BeginTabBar('##trove_tabs', ImGuiTabBarFlags_None) then
            -- E.Box tab (only for Crystal Warriors)
            if state.isCrystalWarrior then
                if imgui.BeginTabItem('E.Box') then
                    if state.activeTab ~= TAB_EBOX then onTabActivated(TAB_EBOX); end
                    renderEboxTab();
                    imgui.EndTabItem();
                end
            end

            if imgui.BeginTabItem('Currency') then
                if state.activeTab ~= TAB_CURRENCY then onTabActivated(TAB_CURRENCY); end
                renderCurrencyTab();
                imgui.EndTabItem();
            end

            if imgui.BeginTabItem('Points') then
                if state.activeTab ~= TAB_POINTS then onTabActivated(TAB_POINTS); end
                renderPointsTab();
                imgui.EndTabItem();
            end

            if imgui.BeginTabItem('Squire') then
                if state.activeTab ~= TAB_SQUIRE then onTabActivated(TAB_SQUIRE); end
                renderSquireTab();
                imgui.EndTabItem();
            end

            imgui.EndTabBar();
        end
    end
    imgui.End();
    imgui.PopStyleColor(14);
end

------------------------------------------------------------
-- Search debounce
------------------------------------------------------------
local function processSearchDebounce()
    if state.activeTab ~= TAB_EBOX then return; end
    if ui.searchBuf[1] ~= searchDebounce.lastBuf then
        searchDebounce.lastBuf   = ui.searchBuf[1];
        searchDebounce.changedAt = os.clock();
        searchDebounce.pending   = true;
    end
    if searchDebounce.pending and (os.clock() - searchDebounce.changedAt) >= searchDebounce.delay then
        searchDebounce.pending = false;
        applySearch(ui.searchBuf[1]);
    end
end

------------------------------------------------------------
-- Commands
------------------------------------------------------------
local function scheduleRefresh()
    -- Any ebox-touching command may have changed the stored quantities;
    -- drop the ebox caches so the queued refresh actually hits the server.
    invalidateEbox();
    ashita.tasks.once(1.0, function()
        if ui.isOpen[1] then
            refreshCurrentView();
            if state.activeTab == TAB_EBOX and (state.currentCategory ~= nil or state.searchActive) then
                sendGetSummary();
            end
        end
    end);
end

-- Drop every cached panel and re-issue the active tab's request. Used by
-- `/trove refresh` for the "I want live data right now" case.
local function refreshAll()
    invalidateSummary();
    invalidateCategories();
    invalidateCurrency();
    invalidatePoints();
    invalidateSquire();
    refreshCurrentView();
end

ashita.events.register('command', 'trove_command', function(e)
    local args = e.command:args();
    if #args == 0 then return; end
    local cmd = args[1]:lower();

    -- Auto-refresh when the player runs the server's !box chat command directly
    if cmd == '!box' then
        scheduleRefresh();
        return;
    end

    -- Accept both /trove (primary) and /box (alias, kept for muscle memory)
    if cmd ~= '/trove' and cmd ~= '/box' then return; end
    e.blocked = true;

    if #args == 1 then
        ui.isOpen[1] = not ui.isOpen[1];
        if ui.isOpen[1] then ensureCurrentView(); end
        return;
    end

    local sub = args[2]:lower();
    if sub == 'show' then
        ui.isOpen[1] = true;
        ensureCurrentView();
        return;
    elseif sub == 'hide' then
        ui.isOpen[1] = false;
        return;
    elseif sub == 'refresh' then
        refreshAll();
        return;
    end

    -- Passthrough to !box
    local parts = {};
    for i = 2, #args do table.insert(parts, args[i]); end
    AshitaCore:GetChatManager():QueueCommand(1, string.format('!box %s', table.concat(parts, ' ')));
    scheduleRefresh();
end);

------------------------------------------------------------
-- Events
------------------------------------------------------------
ashita.events.register('d3d_present', 'trove_render', function()
    -- Install keybind on first frame (ensures Ashita chat manager is ready)
    if not ui.keybindDone then
        ui.keybindDone = true;
        AshitaCore:GetChatManager():QueueCommand(1, string.format('/bind %s /trove', KEYBIND));
    end

    if ui.isOpen[1] then processSearchDebounce(); end
    renderWindow();
end);

ashita.events.register('unload', 'trove_unload', function()
    AshitaCore:GetChatManager():QueueCommand(1, string.format('/unbind %s', KEYBIND));
    textureCache = {};
    fileTextures = {};
    print('[trove] Unloaded.');
end);

print(string.format('[trove] Loaded. /trove (or /box) to toggle, also bound to %s.', KEYBIND));
