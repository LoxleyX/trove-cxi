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
addon.version   = '1.4.1';
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

local trove_plugins  = require('utils/plugins');
local trove_ui       = require('utils/ui');

------------------------------------------------------------
-- Theme (change to load a custom theme from themes/)
------------------------------------------------------------
local THEME = 'default';
trove_ui.applyTheme(THEME);

------------------------------------------------------------
-- Packet protocol (0x1A4)
------------------------------------------------------------
local PACKET_ID = 0x1A4;

local C2S = {
    WITHDRAW          = 2,
    WITHDRAW_PROMPT   = 3,
    GET_SUMMARY       = 4,
    GET_CATEGORY      = 5,
    SEARCH            = 6,
    GET_CURRENCY      = 7,
    GET_POINTS        = 8,
    GET_SQUIRE        = 9,
    GET_RECIPE        = 10,
    GET_TAB_SUMMARY   = 13,
    GET_TAB_CATEGORY  = 14,
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
    TAB_ENTRY      = 8,
    RECIPE         = 11,
    TAB_SUMMARY    = 12,
};

-- Tab source IDs (matches C++ TAB_SOURCE_* constants)
local TAB_SOURCE = {
    SQUIRE = 0,
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
-- Colors (proxy to active theme — changes when theme switches)
-- Maps old key names to theme keys where they differ.
------------------------------------------------------------
local COLOR_ALIASES = {
    btnWithdraw = 'btnPrimary',
    btnHover    = 'btnPrimaryHover',
    btnActive   = 'btnPrimaryActive',
    btnFeatureH = 'btnFeatureHover',
    btnFeatureA = 'btnFeatureActive',
    btnStoreH   = 'btnPositiveHover',
    btnStoreA   = 'btnPositiveActive',
    btnStore    = 'btnPositive',
    btnBackH    = 'btnBackHover',
    btnBackA    = 'btnBackActive',
};

local COLORS = setmetatable({}, {
    __index = function(_, key)
        local themeKey = COLOR_ALIASES[key] or key;
        return trove_ui.color(themeKey);
    end,
});

-- Cached alternating row backgrounds (rebuilt on theme change to avoid per-row allocations)
local rowBgCache = { version = -1, alt = nil, normal = nil };
local function getRowBg(isAlt)
    local v = trove_ui.getThemeVersion();
    if rowBgCache.version ~= v then
        local base = COLORS.childBg;
        rowBgCache.alt    = { base[1], base[2], base[3], 0.35 };
        rowBgCache.normal = { base[1], base[2], base[3], 0.20 };
        rowBgCache.version = v;
    end
    return isAlt and rowBgCache.alt or rowBgCache.normal;
end

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

-- FFXI item descriptions use a custom font that maps certain invalid-
-- ShiftJIS byte pairs to element icons. MultiByteToWideChar doesn't know
-- about them and emits "?". We translate each `0xEF <idx>` pair to a
-- sentinel `0x01 <idx>` so the description still encodes the element
-- position; the renderer later turns those into colored "●" glyphs.
-- `0x01` (ASCII SOH) is a control character that won't appear in normal
-- item text and survives the ShiftJIS → UTF-8 round-trip unchanged.
local ELEMENT_COLORS = {
    [0x1F] = { 1.00, 0.45, 0.25, 1.00 },  -- Fire: orange-red
    [0x20] = { 0.55, 0.85, 1.00, 1.00 },  -- Ice: light cyan
    [0x21] = { 0.55, 1.00, 0.55, 1.00 },  -- Wind: green
    [0x22] = { 0.90, 0.75, 0.45, 1.00 },  -- Earth: tan
    [0x23] = { 1.00, 0.90, 0.30, 1.00 },  -- Thunder: yellow
    [0x24] = { 0.45, 0.60, 1.00, 1.00 },  -- Water: blue
    [0x25] = { 1.00, 1.00, 0.85, 1.00 },  -- Light: pale
    [0x26] = { 0.75, 0.45, 1.00, 1.00 },  -- Dark: purple
};

local ELEMENT_MARK = 0x01;  -- sentinel byte before a colored-element index

local function replaceElementGlyphs(s)
    if s:find('\xEF', 1, true) == nil then return s; end
    local out, i, n = {}, 1, #s;
    while i <= n do
        local b = s:byte(i);
        if b == 0xEF and i < n and ELEMENT_COLORS[s:byte(i + 1)] ~= nil then
            out[#out + 1] = string.char(ELEMENT_MARK, s:byte(i + 1));
            i = i + 2;
        else
            out[#out + 1] = s:sub(i, i);
            i = i + 1;
        end
    end
    return table.concat(out);
end

-- Reusable FFI buffers for ShiftJIS → UTF-8 conversion. Previously these
-- were allocated inside shiftjis_to_utf8 (12 KB per call, every tooltip
-- frame at 60 fps → heavy GC pressure and eventual OOM after hours).
local sjis_buf  = ffi.new('char[4096]');
local sjis_wbuf = ffi.new('wchar_t[4096]');

local function shiftjis_to_utf8(input)
    if input == nil then return nil; end
    input = replaceElementGlyphs(input);
    ffi.copy(sjis_buf, input);
    ffi.C.MultiByteToWideChar(932, 0, sjis_buf, -1, sjis_wbuf, 4096);
    ffi.C.WideCharToMultiByte(65001, 0, sjis_wbuf, -1, sjis_buf, 4096, nil, nil);
    return ffi.string(sjis_buf);
end

local function getItemString(res, field, index)
    if res == nil then return nil; end
    local val = res[field][index or 1];
    if val == nil then return nil; end
    return shiftjis_to_utf8(val);
end

-- Render an item description that may contain ELEMENT_MARK sentinels for
-- per-element coloured dots. Text flows inline with `SameLine(0, 0)` and
-- wraps at segment boundaries when the accumulated line would exceed the
-- current content width. `\n` in the description forces a new line.
--
-- Element dots are drawn on the window's drawlist as filled circles
-- instead of using a Unicode glyph — the default imgui font doesn't
-- include U+25CF (BLACK CIRCLE) and falls back to "?" for it.
local DOT_WIDTH  = 10;  -- total horizontal slot reserved for a dot
local DOT_RADIUS = 3;

local function renderColoredDescription(desc, defaultColor)
    if desc == nil or #desc == 0 then return; end

    local wrapWidth = imgui.GetContentRegionAvail();
    local lineW    = 0;
    local rendered = false;

    local function preRender(w)
        if rendered and (lineW + w > wrapWidth) then
            -- The previous widget already advanced to the next row; skip
            -- SameLine so this segment starts fresh on that row.
            lineW = 0;
        elseif rendered then
            imgui.SameLine(0, 0);
        end
    end

    local function emitText(text, color, escape)
        local w = imgui.CalcTextSize(text);
        preRender(w);
        if escape then text = text:gsub('%%', '%%%%'); end
        imgui.TextColored(color, text);
        lineW = lineW + w;
        rendered = true;
    end

    local function emitDot(color)
        preRender(DOT_WIDTH);
        local dl = imgui.GetWindowDrawList();
        local sx, sy = imgui.GetCursorScreenPos();
        local lineH = imgui.GetTextLineHeight();
        dl:AddCircleFilled(
            { sx + DOT_WIDTH / 2, sy + lineH / 2 },
            DOT_RADIUS,
            imgui.GetColorU32(color));
        imgui.Dummy({ DOT_WIDTH, lineH });
        lineW = lineW + DOT_WIDTH;
        rendered = true;
    end

    local i, n = 1, #desc;
    while i <= n do
        local b = desc:byte(i);
        if b == 0x0A then
            if not rendered then imgui.Text(''); end
            lineW, rendered = 0, false;
            i = i + 1;
        elseif b == ELEMENT_MARK and i < n then
            local color = ELEMENT_COLORS[desc:byte(i + 1)];
            if color ~= nil then
                emitDot(color);
                i = i + 2;
            else
                i = i + 1;
            end
        else
            local start = i;
            while i <= n do
                local bb = desc:byte(i);
                if bb == 0x0A or bb == ELEMENT_MARK then break; end
                i = i + 1;
            end
            if i > start then
                emitText(desc:sub(start, i - 1), defaultColor, true);
            end
        end
    end
end

------------------------------------------------------------
-- Texture cache (game item icons + file-based images)
------------------------------------------------------------
local textureCache   = {};
local fileTextures   = {};  -- filename -> texture
local textureHandles = {};  -- itemId|filename -> tonumber(uint32) for imgui.Image

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
    textureHandles[itemId] = tonumber(ffi.cast('uint32_t', tex));
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
    -- CRITICAL: store the gc_safe_release return value, not the raw pointer.
    -- Previously the wrapper was created then discarded — when GC collected
    -- it, Release() was called on the D3D texture while the addon still held
    -- a dangling raw pointer. Next render → use-after-free → crash.
    local tex = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
    fileTextures[filename] = tex;
    textureHandles[filename] = tonumber(ffi.cast('uint32_t', tex));
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

local function sendGetSummary()        sendAction(C2S.GET_SUMMARY);         end
local function sendGetCurrency()       sendAction(C2S.GET_CURRENCY);        end
local function sendGetPoints()         sendAction(C2S.GET_POINTS);          end
local function sendGetSquire()         sendAction(C2S.GET_SQUIRE);          end
local function sendGetTabSummary(source)
    local p = makePacket();
    p[5] = C2S.GET_TAB_SUMMARY;
    p[7] = source;
    AshitaCore:GetPacketManager():AddOutgoingPacket(PACKET_ID, p);
end

local function sendGetTabCategory(source, categoryName)
    local p = makePacket();
    p[5] = C2S.GET_TAB_CATEGORY;
    p[7] = source;
    local bytes = { string.byte(categoryName, 1, 20) };
    for i = 1, math.min(#bytes, 20) do p[8 + i] = bytes[i]; end
    AshitaCore:GetPacketManager():AddOutgoingPacket(PACKET_ID, p);
end

local function sendGetRecipe(itemId)
    local p = makePacket();
    p[5] = C2S.GET_RECIPE;
    writeU16(p, 0x08, itemId);
    AshitaCore:GetPacketManager():AddOutgoingPacket(PACKET_ID, p);
end

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
local TAB_CRAFTING = 5;

-- Tab visibility (read/written by settings plugin)
local tabVisibility = {
    ebox     = true,
    currency = true,
    points   = true,
    squire   = true,
    crafting = true,
};

local state = {
    -- Tab visibility (plugins can read/write this)
    tabVisibility = tabVisibility,

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
    squire              = {},
    squireLoaded        = false,
    squireSummary       = {},
    squireSummaryLoaded = false,
    squireCategory      = nil,

    -- Crafting state
    craftRecipes        = {},     -- array of parsed recipe tables from server
    craftLoaded         = false,  -- true after END_LIST received
    craftItemId         = 0,      -- item we requested recipes for
    craftItemName       = '',
    craftHistory        = {},     -- stack of { id, name } for back navigation / breadcrumbs
    batchWithdrawCount  = 0,      -- pending WITHDRAW ACKs for batch prepare
    craftFlashId        = 0,      -- item ID to flash (non-craftable click feedback)
    craftFlashUntil     = 0,      -- os.clock() when flash expires

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
    isOpen          = { false },
    searchBuf       = { '' },
    searchSize      = 32,
    selectedItem    = nil,
    keybindDone     = false,
    craftSearchBuf  = { '' },
    craftSearchSize = 32,
};

local searchDebounce = {
    lastBuf = '', changedAt = 0, delay = 0.3, pending = false,
};

local craftDebounce = {
    lastBuf = '', changedAt = 0, delay = 0.3, pending = false, results = {},
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
        if state.squireCategory then
            state.pendingRequest = 'squire';
            sendGetTabCategory(TAB_SOURCE.SQUIRE, state.squireCategory);
        else
            state.pendingRequest = 'squire_summary';
            sendGetTabSummary(TAB_SOURCE.SQUIRE);
        end
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
        if state.squireCategory then
            state.pendingRequest = 'squire';
            state.squire         = {};
            sendGetTabCategory(TAB_SOURCE.SQUIRE, state.squireCategory);
        else
            if cacheFresh(state.fetchedAt.squire, TTL.squire) then
                state.pendingRequest = nil;
                return;
            end
            state.pendingRequest = 'squire_summary';
            sendGetTabSummary(TAB_SOURCE.SQUIRE);
        end
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
-- Auto-refresh crafting recipe when inventory changes so ingredient
-- counts stay live. Debounced to avoid spamming during bulk operations.
local craftRefreshDebounce = { pending = false, at = 0, delay = 2.0, synthCooldownUntil = 0 };

-- Catch the synth result packet (0x06F COMBINE_ANS) and display the
-- outcome in the Trove status bar. The FFXI client drops this packet when
-- its internal "synthesizing" flag isn't set (which AddOutgoingPacket
-- bypasses), so we handle it ourselves. Don't block — let the client
-- process it too in case `/lastsynth` or native UI set the flag.
local SYNTH_RESULT_MSG = {
    [0x00] = 'Synthesis succeeded!',
    [0x01] = 'Synthesis failed. Crystal lost.',
    [0x02] = 'Synthesis interrupted! Materials lost.',
    [0x03] = 'Bad recipe combination.',
    [0x04] = 'Synthesis canceled.',
    [0x06] = 'Skill too low for this recipe.',
    [0x07] = 'Cannot hold another rare item.',
    [0x0C] = 'Desynthesis succeeded!',
    [0x0D] = 'Must wait longer.',
    [0x0E] = 'Synthesis interrupted! Materials lost.',
};

ashita.events.register('packet_in', 'trove_synth_result', function(e)
    if e.id ~= 0x06F then return; end

    local result = struct.unpack('B', e.data_modified, 0x04 + 1);
    local qty    = struct.unpack('B', e.data_modified, 0x06 + 1);
    local itemId = readU16(e.data_modified, 0x08);

    local msg = SYNTH_RESULT_MSG[result];
    if msg == nil then msg = string.format('Synth result: %d', result); end

    local isSuccess = (result == 0x00 or result == 0x0C);
    if isSuccess and itemId > 0 then
        local res = getItemRes(itemId);
        local name = res and shiftjis_to_utf8(res.Name[1]) or tostring(itemId);
        msg = msg .. string.format(' %s x%d', name, qty);
    end

    state.synthResultMsg     = msg;
    state.synthResultIsErr   = not isSuccess;
    state.synthResultUntil   = os.clock() + 4;

    -- Suppress the inventory-watch auto-refresh for a few seconds so this
    -- status message isn't immediately wiped by a recipe reload triggered
    -- by the inventory changes from the synth consuming materials.
    craftRefreshDebounce.pending            = false;
    craftRefreshDebounce.synthCooldownUntil = os.clock() + 4;

    -- Schedule a recipe refresh after the message clears so ingredient
    -- counts update (the inventory-watch packets arrived during the
    -- cooldown and were suppressed, so we need an explicit refresh).
    ashita.tasks.once(4.5, function()
        if state.craftItemId > 0 and state.craftLoaded then
            state.craftRecipes   = {};
            state.craftLoaded    = false;
            state.pendingRequest = 'crafting';
            sendGetRecipe(state.craftItemId);
        end
    end);

    -- Clear the craft cooldown early on result so the player can
    -- immediately click Craft again (server enforces the real 15s).
    state.synthCooldownUntil = os.clock() + 1;
end);


ashita.events.register('packet_in', 'trove_inv_watch', function(e)
    -- 0x01F = item assign, 0x020 = item update/quantity change
    if e.id ~= 0x01F and e.id ~= 0x020 then return; end
    if state.activeTab == TAB_CRAFTING and state.craftItemId > 0 and state.craftLoaded then
        -- Don't queue a refresh while the synth result message is still showing.
        if os.clock() < craftRefreshDebounce.synthCooldownUntil then return; end
        craftRefreshDebounce.pending = true;
        craftRefreshDebounce.at      = os.clock();
    end
end);

ashita.events.register('packet_in', 'trove_plugin_packets', function(e)
    if trove_plugins and trove_plugins.onPacketIn then
        local ok, err = pcall(trove_plugins.onPacketIn, e, state);
        if not ok then
            print(string.format('[trove] Plugin packet error: %s', tostring(err)));
        end
    end
end);

ashita.events.register('packet_in', 'trove_packet_in', function(e)
    if e.id ~= PACKET_ID then return; end
    e.blocked = true;

    -- pcall the handler body so a Lua error inside can't escalate to a
    -- C++ "unknown exception" that tears down the whole addon system.
    local ok, err = pcall(function()

    local action = struct.unpack('B', e.data_modified, 0x04 + 1);

    if action == S2C.CLEAR then
        if state.pendingRequest == 'currency' then
            state.currency = {};
        elseif state.pendingRequest == 'points' then
            state.points = {};
        elseif state.pendingRequest == 'squire' then
            state.squire = {};
        elseif state.pendingRequest == 'crafting' then
            state.craftRecipes = {};
            state.craftLoaded  = false;
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
        local source = struct.unpack('B', e.data_modified, 0x05 + 1);

        -- Tab protocol responses (source > 0 handled by plugins)
        if source == TAB_SOURCE.SQUIRE then
            state.squireLoaded        = true;
            state.fetchedAt.squire    = now;
            state.pendingRequest      = nil;
            return;
        elseif source > 0 then
            -- Other tab sources handled by plugins
            state.pendingRequest = nil;
            return;
        end

        if state.pendingRequest == 'currency' then
            state.currencyLoaded      = true;
            state.fetchedAt.currency  = now;
        elseif state.pendingRequest == 'points' then
            state.pointsLoaded        = true;
            state.fetchedAt.points    = now;
        elseif state.pendingRequest == 'crafting' then
            state.craftLoaded         = true;
            -- No recipes found: flash the item and pop back if we navigated from an ingredient
            if #state.craftRecipes == 0 and #state.craftHistory > 0 then
                state.craftFlashId    = state.craftItemId;
                state.craftFlashUntil = os.clock() + 0.4;
                local prev = table.remove(state.craftHistory);
                requestRecipe(prev.id, false);
            end
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

    if action == S2C.TAB_SUMMARY then
        local entryCount = struct.unpack('B', e.data_modified, 0x05 + 1);
        local source     = struct.unpack('B', e.data_modified, 0x06 + 1);
        local entries = {};
        local offset = 0x08;
        for i = 1, entryCount do
            local category = readString(e.data_modified, offset, 20);
            local count    = readU16(e.data_modified, offset + 20);
            table.insert(entries, { category = category, count = count });
            offset = offset + 22;
        end
        -- Route to the correct state based on source
        if source == TAB_SOURCE.SQUIRE then
            state.squireSummary = entries;
            state.squireSummaryLoaded = true;
        end
        state.pendingRequest = nil;
        return;
    end

    if action == S2C.TAB_ENTRY then
        local source = struct.unpack('B', e.data_modified, 0x05 + 1);
        if source == TAB_SOURCE.SQUIRE then
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
        end
        return;
    end

    if action == S2C.RECIPE then
        local ingCount   = struct.unpack('B', e.data_modified, 0x05 + 1);
        local desynth    = struct.unpack('B', e.data_modified, 0x06 + 1);
        local craftable  = readU16(e.data_modified, 0x08);
        local crystalId  = readU16(e.data_modified, 0x0A);
        local crystalInv = readU16(e.data_modified, 0x0C);
        local crystalEbx = readU32(e.data_modified, 0x0E);

        -- Results (NQ + HQ1-3)
        local results = {};
        for r = 0, 3 do
            local off = 0x12 + r * 3;
            local id  = readU16(e.data_modified, off);
            local qty = struct.unpack('B', e.data_modified, off + 2 + 1);
            if id > 0 then
                results[r] = { id = id, qty = qty };
            end
        end

        -- Skills
        local SKILL_NAMES = { 'Wood', 'Smith', 'Gold', 'Cloth', 'Leather', 'Bone', 'Alchemy', 'Cook' };
        local skills = {};
        for s = 0, 7 do
            local v = struct.unpack('B', e.data_modified, 0x1E + s + 1);
            if v > 0 then
                skills[SKILL_NAMES[s + 1]] = v;
            end
        end

        -- Ingredients
        local ingredients = {};
        for g = 0, ingCount - 1 do
            local off   = 0x26 + g * 9;
            local id    = readU16(e.data_modified, off);
            local need  = struct.unpack('B', e.data_modified, off + 2 + 1);
            local inv   = readU16(e.data_modified, off + 3);
            local ebox  = readU32(e.data_modified, off + 5);
            if id > 0 then
                ingredients[#ingredients + 1] = { id = id, need = need, inv = inv, ebox = ebox };
            end
        end

        table.insert(state.craftRecipes, {
            desynth     = (desynth ~= 0),
            craftable   = craftable,
            crystal     = { id = crystalId, inv = crystalInv, ebox = crystalEbx },
            results     = results,
            skills      = skills,
            ingredients = ingredients,
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

        if requestAction == C2S.WITHDRAW then
            -- Batch mode: count down on any ACK (success or failure).
            if state.batchWithdrawCount > 0 then
                state.batchWithdrawCount = state.batchWithdrawCount - 1;
                if success == 1 then invalidateEbox(); end
                if state.batchWithdrawCount == 0 and state.craftItemId > 0 then
                    ashita.tasks.once(0.8, function()
                        state.craftRecipes  = {};
                        state.craftLoaded   = false;
                        state.pendingRequest = 'crafting';
                        sendGetRecipe(state.craftItemId);
                    end);
                end
            elseif success == 1 then
                invalidateEbox();
                -- Normal single-withdraw refresh (E.Box tab).
                ashita.tasks.once(0.8, function()
                    refreshCurrentView();
                    if state.currentCategory ~= nil or state.searchActive then
                        sendGetSummary();
                    end
                end);
            end
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

    end); -- pcall
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
    local handle = textureHandles[itemId];
    if tex and tex ~= false and handle ~= nil then
        imgui.Image(handle, { size, size });
        return true;
    end
    return false;
end

-- Inject shared functions into plugins after they load
local function initPlugins()
    trove_plugins.initAll(renderIcon, getItemRes, renderTooltip);
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
            -- renderColoredDescription wraps at segment boundaries itself
            -- (it measures each piece against GetContentRegionAvail), and
            -- already escapes "%" so printf format specifiers don't crash
            -- imgui. The segment pipeline also turns the ELEMENT_MARK
            -- sentinels into coloured "●" glyphs inline with the text.
            renderColoredDescription(desc, COLORS.desc);
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
    local handle = textureHandles[item.id];
    if tex and tex ~= false and handle ~= nil then
        imgui.Image(handle, { 32, 32 });
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

    local bgColor = isSelected and COLORS.selected or getRowBg(isAlt);

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
    imgui.PushStyleColor(ImGuiCol_Border, COLORS.accent);
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
    local cwHandle = textureHandles['cw.png'];
    if cwTex and cwTex ~= false and cwHandle ~= nil then
        imgui.Image(cwHandle, { 20, 20 });
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

    imgui.PushStyleColor(ImGuiCol_ChildBg, COLORS.windowBg);
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
    imgui.PopStyleColor(1); -- ebox_scroll bg
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

    imgui.PushStyleColor(ImGuiCol_ChildBg, COLORS.windowBg);
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
                local bg = getRowBg(isAlt);

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
    imgui.PopStyleColor(1); -- currency_scroll bg
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

    imgui.PushStyleColor(ImGuiCol_ChildBg, COLORS.windowBg);
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
                local bg = getRowBg(isAlt);

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
    imgui.PopStyleColor(1); -- points_scroll bg
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
    -- Category list view (summary)
    if not state.squireCategory then
        if not state.squireSummaryLoaded then
            if state.pendingRequest == 'squire_summary' then
                imgui.TextColored(COLORS.dimmed, 'Loading...');
            else
                state.pendingRequest = 'squire_summary';
                sendGetTabSummary(TAB_SOURCE.SQUIRE);
            end
            return;
        end

        if #state.squireSummary == 0 then
            imgui.TextColored(COLORS.empty, 'Nothing stored with the Squire.');
            return;
        end

        -- Refresh button
        imgui.PushStyleColor(ImGuiCol_Button, COLORS.btnFeature);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.btnFeatureH);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.btnFeatureA);
        if imgui.Button('Refresh', { 70, 22 }) then
            state.squireSummaryLoaded = false;
            state.pendingRequest = 'squire_summary';
            sendGetTabSummary(TAB_SOURCE.SQUIRE);
        end
        imgui.PopStyleColor(3);
        imgui.Separator();
        imgui.Spacing();

        imgui.PushStyleColor(ImGuiCol_ChildBg, COLORS.windowBg);
        imgui.BeginChild('##squire_summary', { -1, -1 }, false);
        for i, entry in ipairs(state.squireSummary) do
            local subtitle = string.format('%d item%s stored', entry.count, entry.count ~= 1 and 's' or '');
            if trove_ui.categoryButton(entry.category, subtitle, i) then
                state.squireCategory = entry.category;
                state.squire = {};
                state.squireLoaded = false;
                state.pendingRequest = 'squire';
                sendGetTabCategory(TAB_SOURCE.SQUIRE, entry.category);
            end
            imgui.Spacing();
        end
        imgui.EndChild();
        imgui.PopStyleColor(1);
        return;
    end

    -- Item list view (within a category)
    -- Back button
    imgui.PushStyleColor(ImGuiCol_Button, COLORS.btnFeature);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.btnFeatureH);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.btnFeatureA);
    if imgui.Button('Back', { 50, 22 }) then
        state.squireCategory = nil;
        state.squire = {};
        state.squireLoaded = false;
        return;
    end
    imgui.PopStyleColor(3);
    imgui.SameLine();
    imgui.TextColored(COLORS.dimmed, string.format('%s (%d items)', state.squireCategory, #state.squire));
    imgui.Separator();
    imgui.Spacing();

    -- Group entries by subtype
    local byCat  = {};
    local catOrder = {};

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

    table.sort(catOrder, function(a, b) return squireCategoryRank(a) < squireCategoryRank(b); end);

    imgui.PushStyleColor(ImGuiCol_ChildBg, COLORS.windowBg);
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
                    local bg = getRowBg(isAlt);

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
    imgui.PopStyleColor(1); -- squire_scroll bg
end

------------------------------------------------------------
-- Render: Crafting tab
------------------------------------------------------------
-- Client-side item name index for instant search. Built lazily on first use.
local craftIndex     = nil; -- array of { id, name (lowercase sortname) }
local craftIndexSize = 0;

local function buildCraftIndex()
    if craftIndex ~= nil then return; end
    craftIndex = {};
    local rm = AshitaCore:GetResourceManager();
    for id = 1, 65535 do
        local res = rm:GetItemById(id);
        if res ~= nil then
            local n = res.Name[1];
            if n ~= nil and #n > 0 then
                craftIndex[#craftIndex + 1] = { id = id, name = n:lower() };
            end
        end
    end
    craftIndexSize = #craftIndex;
end

local function searchCraftItems(query)
    buildCraftIndex();
    local q = query:lower();
    if #q == 0 then return {}; end
    local results = {};
    for i = 1, craftIndexSize do
        if craftIndex[i].name:find(q, 1, true) ~= nil then
            results[#results + 1] = craftIndex[i];
            if #results >= 20 then break; end
        end
    end
    return results;
end

local function requestRecipe(itemId, pushHistory)
    if pushHistory ~= false and state.craftItemId > 0 then
        table.insert(state.craftHistory, { id = state.craftItemId, name = state.craftItemName });
    end
    local res = getItemRes(itemId);
    state.craftItemId   = itemId;
    state.craftItemName = (res ~= nil and res.Name[1] ~= nil) and shiftjis_to_utf8(res.Name[1]) or tostring(itemId);
    state.craftRecipes  = {};
    state.craftLoaded   = false;
    state.pendingRequest = 'crafting';
    sendGetRecipe(itemId);
end

-- Build and send a 0x096 synth packet from a recipe. Returns nil on success
-- or an error string if ingredients aren't all in main inventory.
local function trySynth(recipe)
    local inv = AshitaCore:GetMemoryManager():GetInventory();
    local maxSlots = inv:GetContainerCountMax(0);

    -- Map inventory: itemId → sorted list of { slot, avail }
    local invMap = {};
    for slot = 1, maxSlots do
        local ci = inv:GetContainerItem(0, slot);
        if ci ~= nil and ci.Id > 0 and ci.Count > 0 then
            if not invMap[ci.Id] then invMap[ci.Id] = {}; end
            invMap[ci.Id][#invMap[ci.Id] + 1] = { slot = slot, avail = ci.Count };
        end
    end

    -- Find crystal slot
    local cSlots = invMap[recipe.crystal.id];
    if not cSlots or #cSlots == 0 then return 'Crystal not in inventory'; end
    local crystalSlot = cSlots[1].slot;

    -- Find ingredient slots (respecting stacks for duplicate ingredients)
    local itemNos  = {};
    local tableNos = {};
    local slotUsed = {}; -- slot → count consumed so far

    for _, ing in ipairs(recipe.ingredients) do
        local slots = invMap[ing.id];
        if not slots then return 'Missing: ' .. tostring(ing.id); end
        for _ = 1, ing.need do
            local found = false;
            for _, s in ipairs(slots) do
                local used = slotUsed[s.slot] or 0;
                if used < s.avail then
                    itemNos[#itemNos + 1]   = ing.id;
                    tableNos[#tableNos + 1] = s.slot;
                    slotUsed[s.slot] = used + 1;
                    found = true;
                    break;
                end
            end
            if not found then return 'Not enough in inventory'; end
        end
    end

    -- Build packet 0x096. Server expects PacketSize 0x12 (36 bytes exactly).
    -- Ashita derives the size field from table length, so table must be 36.
    local p = {};
    for i = 1, 36 do p[i] = 0; end

    -- p[5] = HashNo (0), p[6] = padding (0)
    writeU16(p, 0x06, recipe.crystal.id);  -- Crystal
    p[0x08 + 1] = crystalSlot;             -- CrystalIdx
    p[0x09 + 1] = #itemNos;               -- Items count
    for i = 1, #itemNos do
        writeU16(p, 0x0A + (i - 1) * 2, itemNos[i]);
    end
    for i = 1, #tableNos do
        p[0x1A + i] = tableNos[i];
    end

    AshitaCore:GetPacketManager():AddOutgoingPacket(0x96, p);
    return nil;
end

-- Ingredient availability color.
local function ingredientColor(inv, ebox, need)
    if inv >= need then return COLORS.green or { 0.40, 1.00, 0.40, 1.00 }; end
    if (inv + ebox) >= need then return COLORS.blue or { 0.50, 0.70, 1.00, 1.00 }; end
    return COLORS.rare or { 1.00, 0.40, 0.40, 1.00 };
end

local SKILL_COLORS = {
    Wood     = { 0.45, 0.80, 0.45, 1.00 },
    Smith    = { 0.70, 0.70, 0.80, 1.00 },
    Gold     = { 1.00, 0.90, 0.40, 1.00 },
    Cloth    = { 1.00, 0.65, 0.85, 1.00 },
    Leather  = { 0.85, 0.65, 0.40, 1.00 },
    Bone     = { 0.80, 0.75, 0.70, 1.00 },
    Alchemy  = { 0.75, 0.55, 1.00, 1.00 },
    Cook     = { 1.00, 0.75, 0.40, 1.00 },
};

-- Calculate what needs pulling from ebox for N crafts.
-- mode: 'missing' = only the shortfall, 'all' = full sets.
-- Returns: { pullList = { {id, qty}, ... }, feasible = bool }
local function calcPrepare(recipe, count, mode)
    local pulls = {};
    local feasible = true;

    -- Crystal
    local crNeed = (mode == 'all') and count or math.max(0, count - recipe.crystal.inv);
    crNeed = math.min(crNeed, recipe.crystal.ebox);
    if (mode == 'all' and recipe.crystal.ebox < count)
       or (mode == 'missing' and recipe.crystal.inv < count and recipe.crystal.ebox < (count - recipe.crystal.inv)) then
        feasible = false;
    end
    if crNeed > 0 then
        pulls[#pulls + 1] = { id = recipe.crystal.id, qty = crNeed };
    end

    -- Ingredients
    for _, ing in ipairs(recipe.ingredients) do
        local totalNeed = ing.need * count;
        local delta;
        if mode == 'all' then
            delta = totalNeed;
        else
            delta = math.max(0, totalNeed - ing.inv);
        end
        delta = math.min(delta, ing.ebox);

        if (mode == 'all' and ing.ebox < totalNeed)
           or (mode == 'missing' and ing.inv < totalNeed and ing.ebox < (totalNeed - ing.inv)) then
            feasible = false;
        end
        if delta > 0 then
            pulls[#pulls + 1] = { id = ing.id, qty = delta };
        end
    end

    return { pullList = pulls, feasible = feasible };
end

local function executePrepare(pullList)
    if #pullList == 0 then return; end
    state.batchWithdrawCount = #pullList;
    for _, pull in ipairs(pullList) do
        sendWithdraw(pull.id, pull.qty);
    end
end

local PREPARE_COUNTS = { 1, 3, 6, 12 };

local function renderRecipe(recipe, index)
    -- Skills line
    local skillParts = {};
    for name, level in pairs(recipe.skills) do
        table.insert(skillParts, string.format('%s %d', name, level));
    end
    if #skillParts > 0 then
        imgui.TextColored(COLORS.dimmed, table.concat(skillParts, ' / '));
    end
    if recipe.desynth then
        imgui.SameLine(0, 8);
        imgui.TextColored(COLORS.rare or { 1, 0.4, 0.4, 1 }, '(Desynth)');
    end

    -- Craftable badge (right-aligned)
    local craftLabel = string.format('Can craft: %d', recipe.craftable);
    imgui.SameLine(imgui.GetWindowWidth() - imgui.CalcTextSize(craftLabel) - 16);
    local craftColor = recipe.craftable > 0 and { 0.40, 1.00, 0.40, 1.00 } or { 1.00, 0.40, 0.40, 1.00 };
    imgui.TextColored(craftColor, craftLabel);

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Crystal
    local cr = recipe.crystal;
    local crColor = ingredientColor(cr.inv, cr.ebox, 1);
    if not renderIcon(cr.id, 20) then imgui.Dummy({ 20, 20 }); end
    imgui.SameLine(0, 4);
    local crRes = getItemRes(cr.id);
    local crName = crRes and shiftjis_to_utf8(crRes.Name[1]) or tostring(cr.id);
    imgui.TextColored(crColor, crName);
    imgui.SameLine(0, 8);
    imgui.TextColored(COLORS.dimmed, string.format('(%d/%d)', cr.inv + cr.ebox, 1));
    if imgui.IsItemHovered() then
        imgui.BeginTooltip();
        imgui.TextColored(COLORS.header, crName);
        imgui.TextColored(COLORS.dimmed, string.format('Inventory: %d  |  E.Box: %d', cr.inv, cr.ebox));
        imgui.EndTooltip();
    end

    imgui.Spacing();

    -- Ingredients (clickable: navigates to recipe if craftable, flashes if not)
    for ingIdx, ing in ipairs(recipe.ingredients) do
        local color = ingredientColor(ing.inv, ing.ebox, ing.need);
        -- Flash feedback for non-craftable clicks
        local isFlashing = state.craftFlashId == ing.id and os.clock() < state.craftFlashUntil;
        if isFlashing then color = { 1.0, 1.0, 1.0, 1.0 }; end

        if not renderIcon(ing.id, 20) then imgui.Dummy({ 20, 20 }); end
        imgui.SameLine(0, 4);
        local ingRes = getItemRes(ing.id);
        local ingName = ingRes and shiftjis_to_utf8(ingRes.Name[1]) or tostring(ing.id);
        local label = ing.need > 1 and string.format('%s x%d', ingName, ing.need) or ingName;
        imgui.PushStyleColor(ImGuiCol_Text, color);
        local selId = string.format('%s##ing_%d_%d', label, index, ingIdx);
        if imgui.Selectable(selId, false, ImGuiSelectableFlags_None, { 0, 0 }) then
            requestRecipe(ing.id);
        end
        imgui.PopStyleColor();
        imgui.SameLine(0, 8);
        imgui.TextColored(COLORS.dimmed, string.format('(%d/%d)', ing.inv + ing.ebox, ing.need));
        if imgui.IsItemHovered() then
            imgui.BeginTooltip();
            renderIcon(ing.id, 32);
            imgui.SameLine(0, 6);
            imgui.BeginGroup();
            imgui.TextColored(COLORS.header, ingName);
            imgui.TextColored(COLORS.dimmed, string.format('Need: %d', ing.need));
            imgui.TextColored(COLORS.dimmed, string.format('Inventory: %d  |  E.Box: %d', ing.inv, ing.ebox));
            imgui.EndGroup();
            imgui.EndTooltip();
        end
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Results: NQ then HQ1-3 (vertically stacked)
    local nq = recipe.results[0];
    if nq ~= nil then
        if not renderIcon(nq.id, 20) then imgui.Dummy({ 20, 20 }); end
        imgui.SameLine(0, 4);
        local nqRes = getItemRes(nq.id);
        local nqName = nqRes and shiftjis_to_utf8(nqRes.Name[1]) or tostring(nq.id);
        local nqLabel = nq.qty > 1 and string.format('%s x%d', nqName, nq.qty) or nqName;
        imgui.TextColored({ 0.40, 1.00, 0.40, 1.00 }, nqLabel);
        if imgui.IsItemHovered() then renderTooltip({ id = nq.id, name = nqName, qty = 0 }); end

        local HQ_TIER_COLORS = {
            [1] = { 0.80, 0.80, 0.80, 1.00 },
            [2] = { 0.50, 0.70, 1.00, 1.00 },
            [3] = { 1.00, 0.90, 0.30, 1.00 },
        };
        for tier = 1, 3 do
            local hq = recipe.results[tier];
            if hq ~= nil and (hq.id ~= nq.id or hq.qty ~= nq.qty) then
                if not renderIcon(hq.id, 20) then imgui.Dummy({ 20, 20 }); end
                imgui.SameLine(0, 4);
                local hqRes = getItemRes(hq.id);
                local hqName = hqRes and shiftjis_to_utf8(hqRes.Name[1]) or tostring(hq.id);
                local hqLabel = hq.qty > 1 and string.format('%s x%d', hqName, hq.qty) or hqName;
                imgui.TextColored(HQ_TIER_COLORS[tier], string.format('HQ%d: %s', tier, hqLabel));
                if imgui.IsItemHovered() then renderTooltip({ id = hq.id, name = hqName, qty = 0 }); end
            end
        end
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Prepare buttons (withdraw materials from E.Box)
    local inFlight = state.batchWithdrawCount > 0;

    -- Row 1: "Prepare Missing" — pull only the shortfall from ebox
    -- Button palettes: amber for "missing only", teal for "all materials".
    local BTN_MISSING       = { 0.55, 0.40, 0.15, 0.80 };
    local BTN_MISSING_HOVER = { 0.65, 0.50, 0.20, 0.90 };
    local BTN_MISSING_ACT   = { 0.60, 0.45, 0.18, 1.00 };
    local BTN_ALL           = { 0.15, 0.40, 0.50, 0.80 };
    local BTN_ALL_HOVER     = { 0.20, 0.50, 0.60, 0.90 };
    local BTN_ALL_ACT       = { 0.18, 0.45, 0.55, 1.00 };
    local BTN_DISABLED      = { 0.20, 0.18, 0.25, 0.40 };
    local BTN_DISABLED_TEXT = { 0.40, 0.40, 0.40, 0.50 };

    imgui.TextColored({ 0.90, 0.75, 0.40, 1.00 }, 'Withdraw missing:');
    imgui.SameLine(0, 6);
    for _, n in ipairs(PREPARE_COUNTS) do
        local prep = calcPrepare(recipe, n, 'missing');
        local enabled = prep.feasible and #prep.pullList > 0 and not inFlight;
        if not enabled then
            imgui.PushStyleColor(ImGuiCol_Button, BTN_DISABLED);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, BTN_DISABLED);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, BTN_DISABLED);
            imgui.PushStyleColor(ImGuiCol_Text, BTN_DISABLED_TEXT);
        else
            imgui.PushStyleColor(ImGuiCol_Button, BTN_MISSING);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, BTN_MISSING_HOVER);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, BTN_MISSING_ACT);
            imgui.PushStyleColor(ImGuiCol_Text, { 1, 1, 1, 1 });
        end
        local btnId = string.format('x%d##miss_%d_%d', n, index, n);
        if imgui.Button(btnId, { 0, 22 }) and enabled then
            executePrepare(prep.pullList);
        end
        imgui.PopStyleColor(4);
        imgui.SameLine(0, 4);
    end
    imgui.NewLine();

    -- Row 2: "Withdraw All" — pull full sets from ebox (teal)
    imgui.TextColored({ 0.45, 0.80, 0.85, 1.00 }, 'Withdraw all:');
    imgui.SameLine(0, 24);
    for _, n in ipairs(PREPARE_COUNTS) do
        local prep = calcPrepare(recipe, n, 'all');
        local enabled = prep.feasible and #prep.pullList > 0 and not inFlight;
        if not enabled then
            imgui.PushStyleColor(ImGuiCol_Button, BTN_DISABLED);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, BTN_DISABLED);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, BTN_DISABLED);
            imgui.PushStyleColor(ImGuiCol_Text, BTN_DISABLED_TEXT);
        else
            imgui.PushStyleColor(ImGuiCol_Button, BTN_ALL);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, BTN_ALL_HOVER);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, BTN_ALL_ACT);
            imgui.PushStyleColor(ImGuiCol_Text, { 1, 1, 1, 1 });
        end
        local btnId = string.format('x%d##all_%d_%d', n, index, n);
        if imgui.Button(btnId, { 0, 22 }) and enabled then
            executePrepare(prep.pullList);
        end
        imgui.PopStyleColor(4);
        imgui.SameLine(0, 4);
    end
    imgui.NewLine();

    -- Craft button: sends the same 0x096 synth packet as the native menu.
    -- Server validates everything (crystal, ingredients, skill, cooldown).
    imgui.Spacing();
    local synthCooldown = os.clock() < (state.synthCooldownUntil or 0);
    local canCraft = not recipe.desynth and recipe.craftable > 0 and not inFlight and not synthCooldown;
    local BTN_CRAFT       = { 0.25, 0.55, 0.25, 0.80 };
    local BTN_CRAFT_HOVER = { 0.30, 0.65, 0.30, 0.90 };
    local BTN_CRAFT_ACT   = { 0.28, 0.60, 0.28, 1.00 };
    if not canCraft then
        imgui.PushStyleColor(ImGuiCol_Button, BTN_DISABLED);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, BTN_DISABLED);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, BTN_DISABLED);
        imgui.PushStyleColor(ImGuiCol_Text, BTN_DISABLED_TEXT);
    else
        imgui.PushStyleColor(ImGuiCol_Button, BTN_CRAFT);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, BTN_CRAFT_HOVER);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, BTN_CRAFT_ACT);
        imgui.PushStyleColor(ImGuiCol_Text, { 1, 1, 1, 1 });
    end
    local craftBtnId = string.format('Craft##craft_%d', index);
    if imgui.Button(craftBtnId, { -1, 26 }) and canCraft then
        local err = trySynth(recipe);
        if err then
            setStatus(err, true);
        else
            state.synthCooldownUntil = os.clock() + 15;
        end
    end
    imgui.PopStyleColor(4);
end

local function renderCraftingTab()
    -- Search box
    imgui.TextColored(COLORS.dimmed, 'Search for any item to view its crafting recipe:');
    imgui.SetNextItemWidth(-1);
    imgui.InputText('##craft_search', ui.craftSearchBuf, ui.craftSearchSize, ImGuiInputTextFlags_None);

    -- Debounced client-side search
    local buf = ui.craftSearchBuf[1];
    if buf ~= craftDebounce.lastBuf then
        craftDebounce.lastBuf   = buf;
        craftDebounce.changedAt = os.clock();
        craftDebounce.pending   = true;
    end
    if craftDebounce.pending and os.clock() - craftDebounce.changedAt >= craftDebounce.delay then
        craftDebounce.pending = false;
        craftDebounce.results = searchCraftItems(buf);
    end

    imgui.Spacing();

    -- If we have a loaded recipe, show it
    if state.craftLoaded and state.craftItemId > 0 then
        -- Back button
        if #state.craftHistory > 0 then
            imgui.PushStyleColor(ImGuiCol_Button, COLORS.btnBack or { 0.3, 0.25, 0.4, 0.8 });
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.btnBackH or { 0.4, 0.35, 0.5, 0.9 });
            imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.btnBackA or { 0.35, 0.3, 0.45, 1.0 });
            if imgui.Button('<', { 24, 24 }) then
                local prev = table.remove(state.craftHistory);
                requestRecipe(prev.id, false);
            end
            imgui.PopStyleColor(3);
            imgui.SameLine(0, 4);
        end

        -- Close button (return to search results)
        imgui.PushStyleColor(ImGuiCol_Button, COLORS.btnBack or { 0.3, 0.25, 0.4, 0.8 });
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.btnBackH or { 0.4, 0.35, 0.5, 0.9 });
        imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.btnBackA or { 0.35, 0.3, 0.45, 1.0 });
        if imgui.Button('x', { 24, 24 }) then
            state.craftItemId  = 0;
            state.craftRecipes = {};
            state.craftLoaded  = false;
            state.craftHistory = {};
        end
        imgui.PopStyleColor(3);
        imgui.SameLine(0, 6);

        -- Breadcrumbs: History1 > History2 > Current
        for bi, crumb in ipairs(state.craftHistory) do
            imgui.PushStyleColor(ImGuiCol_Button,        { 0, 0, 0, 0 });
            imgui.PushStyleColor(ImGuiCol_ButtonHovered,  { 0.30, 0.22, 0.42, 0.60 });
            imgui.PushStyleColor(ImGuiCol_ButtonActive,   { 0.40, 0.30, 0.55, 0.80 });
            imgui.PushStyleColor(ImGuiCol_Text, COLORS.dimmed);
            local crumbId = string.format('%s##crumb_%d', crumb.name, bi);
            if imgui.SmallButton(crumbId) then
                local targetId = crumb.id;
                for _ = bi, #state.craftHistory do
                    table.remove(state.craftHistory);
                end
                requestRecipe(targetId, false);
            end
            imgui.PopStyleColor(4);
            imgui.SameLine(0, 2);
            imgui.TextColored(COLORS.dimmed, '>');
            imgui.SameLine(0, 2);
        end

        -- Current item name (or synth result message)
        local synthMsg = state.synthResultMsg or '';
        if #synthMsg > 0 and os.clock() < (state.synthResultUntil or 0) then
            local isErr = state.synthResultIsErr;
            local color = isErr and (COLORS.statusErr or { 1, 0.4, 0.4, 1 }) or (COLORS.statusOk or { 0.4, 1, 0.4, 1 });
            imgui.TextColored(color, synthMsg);
        else
            imgui.TextColored(COLORS.header, state.craftItemName);
        end

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        imgui.PushStyleColor(ImGuiCol_ChildBg, COLORS.windowBg);
        imgui.BeginChild('##craft_scroll', { -1, -1 }, false);

        if #state.craftRecipes == 0 then
            imgui.Spacing(); imgui.Spacing();
            imgui.TextColored(COLORS.dimmed, 'No crafting recipes found for this item.');
        else
            for i, recipe in ipairs(state.craftRecipes) do
                if i > 1 then imgui.Spacing(); imgui.Separator(); imgui.Spacing(); end
                renderRecipe(recipe, i);
            end
        end

        imgui.EndChild();
        imgui.PopStyleColor(1); -- craft_scroll bg
        return;
    end

    -- Pending recipe request
    if state.pendingRequest == 'crafting' then
        imgui.TextColored(COLORS.dimmed, 'Loading recipe...');
        return;
    end

    -- Search results list
    imgui.PushStyleColor(ImGuiCol_ChildBg, COLORS.windowBg);
    imgui.BeginChild('##craft_results', { -1, -1 }, false);

    local results = craftDebounce.results;
    if #results == 0 and #buf > 0 then
        imgui.Spacing();
        imgui.TextColored(COLORS.dimmed, string.format('No items matching "%s"', buf));
    else
        for i, entry in ipairs(results) do
            local rowId = string.format('##craft_row_%d', entry.id);
            local isAlt = (i % 2 == 0);
            local bg = getRowBg(isAlt);

            imgui.PushStyleColor(ImGuiCol_ChildBg, bg);
            imgui.BeginChild(rowId, { -1, 26 }, false);

            imgui.SetCursorPos({ 4, 1 });
            if not renderIcon(entry.id, 24) then imgui.Dummy({ 24, 24 }); end
            imgui.SameLine(32);

            imgui.SetCursorPosY(0);
            if imgui.Selectable(string.format('##csel_%d', entry.id), false,
                ImGuiSelectableFlags_SpanAllColumns, { 0, 26 }) then
                requestRecipe(entry.id);
            end

            local dl = imgui.GetWindowDrawList();
            local wx, wy = imgui.GetWindowPos();
            local res = getItemRes(entry.id);
            local displayName = res and shiftjis_to_utf8(res.Name[1]) or entry.name;
            -- Wrap gsub in extra parens to discard the 2nd return value (sub
            -- count); passing both to AddText causes a sol arg-count mismatch.
            dl:AddText({ wx + 32, wy + 6 }, imgui.GetColorU32(COLORS.white), ((displayName or ''):gsub('%%', '%%%%')));

            if imgui.IsItemHovered() then renderTooltip({ id = entry.id, name = displayName or '', qty = 0 }); end

            imgui.EndChild();
            imgui.PopStyleColor(1);
        end
    end

    imgui.EndChild();
    imgui.PopStyleColor(1); -- craft_results bg
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

    imgui.PushStyleColor(ImGuiCol_TitleBg,         COLORS.windowTitleBg);
    imgui.PushStyleColor(ImGuiCol_TitleBgActive,    COLORS.windowTitleBgAct);
    imgui.PushStyleColor(ImGuiCol_WindowBg,         COLORS.windowBg);
    imgui.PushStyleColor(ImGuiCol_Border,           COLORS.windowBorder);
    imgui.PushStyleColor(ImGuiCol_FrameBg,          COLORS.frameBg);
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered,   COLORS.frameBgHovered);
    imgui.PushStyleColor(ImGuiCol_ScrollbarBg,      COLORS.scrollbarBg);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrab,    COLORS.scrollbarGrab);
    imgui.PushStyleColor(ImGuiCol_Tab,              COLORS.tab);
    imgui.PushStyleColor(ImGuiCol_TabHovered,       COLORS.tabHovered);
    imgui.PushStyleColor(ImGuiCol_TabActive,        COLORS.tabActive);
    -- Selectable / row hover colours
    imgui.PushStyleColor(ImGuiCol_Header,           COLORS.selectHeader);
    imgui.PushStyleColor(ImGuiCol_HeaderHovered,    COLORS.selectHovered);
    imgui.PushStyleColor(ImGuiCol_HeaderActive,     COLORS.selectActive);

    if imgui.Begin('Trove', ui.isOpen, ImGuiWindowFlags_None) then

        if imgui.BeginTabBar('##trove_tabs', ImGuiTabBarFlags_None) then
            -- E.Box tab (only for Crystal Warriors + visible)
            if state.isCrystalWarrior and tabVisibility.ebox then
                if imgui.BeginTabItem('Box') then
                    if state.activeTab ~= TAB_EBOX then onTabActivated(TAB_EBOX); end
                    renderEboxTab();
                    imgui.EndTabItem();
                end
            end

            if tabVisibility.currency then
                if imgui.BeginTabItem('Currency') then
                    if state.activeTab ~= TAB_CURRENCY then onTabActivated(TAB_CURRENCY); end
                    renderCurrencyTab();
                    imgui.EndTabItem();
                end
            end

            if tabVisibility.points then
                if imgui.BeginTabItem('Points') then
                    if state.activeTab ~= TAB_POINTS then onTabActivated(TAB_POINTS); end
                    renderPointsTab();
                    imgui.EndTabItem();
                end
            end

            if tabVisibility.squire then
                if imgui.BeginTabItem('Squire') then
                    if state.activeTab ~= TAB_SQUIRE then onTabActivated(TAB_SQUIRE); end
                    renderSquireTab();
                    imgui.EndTabItem();
                end
            end

            if tabVisibility.crafting then
                if imgui.BeginTabItem('Crafting') then
                    if state.activeTab ~= TAB_CRAFTING then state.activeTab = TAB_CRAFTING; end
                    renderCraftingTab();
                    imgui.EndTabItem();
                end
            end

            -- Plugin tabs (rendered after built-in tabs)
            trove_plugins.renderTabs(state);

            imgui.EndTabBar();
        end

        -- Burger menu button (absolute positioned top-right, above tab content)
        local btnLabel = trove_plugins.hasAlert() and '(!)'or '=';
        imgui.SetCursorPos({ imgui.GetWindowWidth() - 28, 34 });
        if imgui.SmallButton(btnLabel) then
            imgui.OpenPopup('##trove_panels');
        end
        if imgui.BeginPopup('##trove_panels') then
            -- Render window toggles from plugins
            local winPlugins = trove_plugins.getWindowPlugins();
            for _, plugin in ipairs(winPlugins) do
                local win = plugin.window;
                -- Skip CW-only windows if not a Crystal Warrior
                if win.cwOnly and not state.isCrystalWarrior then
                    -- skip
                else
                    if win.separator then imgui.Separator(); end
                    if win.icon then renderIcon(win.icon, 16); imgui.SameLine(0, 6); end
                    local label = win.label or plugin.name;
                    if plugin.hasAlert and plugin.hasAlert() then label = label .. ' (!)'; end
                    if imgui.Selectable(label, win.isOpen[1]) then
                        win.isOpen[1] = not win.isOpen[1];
                    end
                end
            end

            -- Render plugin menu actions (commands that aren't window toggles)
            local menuEntries = trove_plugins.getMenuEntries();
            if #menuEntries > 0 then
                imgui.Separator();
            end
            for _, entry in ipairs(menuEntries) do
                if entry.separator then
                    imgui.Separator();
                end
                if imgui.Selectable(entry.label) then
                    entry.action(state);
                end
            end

            imgui.EndPopup();
        end
    end
    imgui.End();
    imgui.PopStyleColor(14);

    -- Render plugin floating windows
    trove_plugins.renderWindows();
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

------------------------------------------------------------
-- Export (loaded at top of file, see utils/export.lua)
------------------------------------------------------------

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
    elseif sub == 'dump' and args[3] ~= nil then
        -- Dump raw bytes of an item's description so we can map the custom
        -- glyph sequences FFXI uses for elemental icons, etc. Usage:
        --     /trove dump <itemid>
        local id = tonumber(args[3]);
        if id == nil then
            print('[trove] usage: /trove dump <itemid>');
            return;
        end
        local res = getItemRes(id);
        if res == nil or res.Description == nil or res.Description[1] == nil then
            print(string.format('[trove] no description for item %d', id));
            return;
        end
        local raw = res.Description[1];
        print(string.format('[trove] item %d description (%d bytes):', id, #raw));
        -- Emit as space-separated hex, wrapping every 16 bytes.
        local line = {};
        for i = 1, #raw do
            line[#line + 1] = string.format('%02X', raw:byte(i));
            if #line == 16 then
                print('  ' .. table.concat(line, ' '));
                line = {};
            end
        end
        if #line > 0 then print('  ' .. table.concat(line, ' ')); end
        return;
    end

    -- Try plugin commands first
    if (trove_plugins.handleCommand(sub, state, args)) then return; end

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
        trove_plugins.load();
        initPlugins();
    end

    if ui.isOpen[1] then processSearchDebounce(); end

    -- Tick the craft-recipe auto-refresh debounce (inventory changed while
    -- viewing a recipe → re-request so ingredient counts stay live).
    if craftRefreshDebounce.pending
       and os.clock() - craftRefreshDebounce.at >= craftRefreshDebounce.delay then
        craftRefreshDebounce.pending = false;
        if state.activeTab == TAB_CRAFTING and state.craftItemId > 0 and state.craftLoaded then
            state.craftRecipes   = {};
            state.craftLoaded    = false;
            state.pendingRequest = 'crafting';
            sendGetRecipe(state.craftItemId);
        end
    end

    trove_plugins.onRender(state);
    renderWindow();
end);

ashita.events.register('unload', 'trove_unload', function()
    trove_plugins.unload();
    AshitaCore:GetChatManager():QueueCommand(1, string.format('/unbind %s', KEYBIND));
    textureCache   = {};
    fileTextures   = {};
    textureHandles = {};
    print('[trove] Unloaded.');
end);

print(string.format('[trove] Loaded. /trove (or /box) to toggle, also bound to %s.', KEYBIND));
