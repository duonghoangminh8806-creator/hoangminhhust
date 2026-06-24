--[[
    ╔══════════════════════════════════════════════════════════════════╗
    ║              PROJECT PHANTOM v1.0 — BLOX FRUITS                ║
    ║           The Script They'll Study For A Decade                ║
    ║                                                                ║
    ║   Architecture : Modular Engine (15 Subsystems)                ║
    ║   Anti-Detect  : 5-Layer Behavioral Mimicry                    ║
    ║   Combat       : AI-Driven DPS Optimization                    ║
    ║   Farming      : XP/Hour Optimized Auto-Progression            ║
    ║                                                                ║
    ║   Author  : Hoàng Minh                                        ║
    ║   Engine  : PHANTOM Framework                                  ║
    ╚══════════════════════════════════════════════════════════════════╝
--]]

-- ================================================================
-- [0] ANTI-DUPLICATE & NAMESPACE
-- ================================================================
if getgenv().PHANTOM_LOADED then
    warn("[PHANTOM] Already running. Use the UI to control.")
    return
end
getgenv().PHANTOM_LOADED = true

local PHANTOM = {
    Version   = "1.0.0",
    StartTime = os.clock(),
    State = {
        Running    = true,
        CurrentSea = 0,
        FarmState  = "IDLE",
        CurrentQuest = nil,
    },
    Config      = {},
    Connections = {},
    Cap         = {},
}

-- Forward-declare all module tables so cross-references work at call time
local Util     = {};  PHANTOM.Util     = Util
local Security = {};  PHANTOM.Security = Security
local Perf     = {};  PHANTOM.Perf     = Perf
local Combat   = {};  PHANTOM.Combat   = Combat
local Quest    = {};  PHANTOM.Quest    = Quest
local Farm     = {};  PHANTOM.Farm     = Farm
local Fruit    = {};  PHANTOM.Fruit    = Fruit
local Raid     = {};  PHANTOM.Raid     = Raid
local Race     = {};  PHANTOM.Race     = Race
local Stats    = {};  PHANTOM.Stats    = Stats
local Webhook  = {};  PHANTOM.Webhook  = Webhook
local QuestDB  = {};  PHANTOM.QuestDB  = QuestDB

-- ================================================================
-- [1] SERVICES  (lazy-cached, only fetched once per service)
-- ================================================================
local Services = setmetatable({}, {
    __index = function(self, k)
        local ok, svc = pcall(game.GetService, game, k)
        if ok and svc then rawset(self, k, svc) end
        return svc
    end,
})

local Players          = Services.Players
local RS               = Services.ReplicatedStorage
local RunService       = Services.RunService
local TweenService     = Services.TweenService
local HttpService      = Services.HttpService
local Lighting         = Services.Lighting
local VirtualUser      = Services.VirtualUser
local TeleportService  = Services.TeleportService
local CollectionService = Services.CollectionService

local Player    = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui", 10)

-- ================================================================
-- [2] ENVIRONMENT DETECTION & CAPABILITIES
-- ================================================================
local Cap = PHANTOM.Cap

local function probeCap(name, fn)
    local ok, r = pcall(fn)
    Cap[name] = (ok and r == true)
end

probeCap("hookmetamethod",    function() return typeof(hookmetamethod)    == "function" end)
probeCap("hookfunction",      function() return typeof(hookfunction)      == "function" end)
probeCap("getrawmetatable",   function() return typeof(getrawmetatable)   == "function" end)
probeCap("newcclosure",       function() return typeof(newcclosure)       == "function" end)
probeCap("getgc",             function() return typeof(getgc)             == "function" end)
probeCap("getupvalues",       function() return typeof(getupvalues)       == "function" end)
probeCap("setupvalue",        function() return typeof(setupvalue)        == "function" end)
probeCap("sethiddenproperty", function() return typeof(sethiddenproperty) == "function" end)
probeCap("setreadonly",       function() return typeof(setreadonly)       == "function" end)
probeCap("getnamecallmethod", function() return typeof(getnamecallmethod) == "function" end)
probeCap("iscclosure",        function() return typeof(iscclosure)        == "function" end)
probeCap("checkcaller",       function() return typeof(checkcaller)       == "function" end)
probeCap("debuggetinfo",      function() return type(debug)=="table" and typeof(debug.getinfo)=="function" end)
probeCap("request",           function() return typeof(request)=="function" or typeof(http_request)=="function" or type(syn)=="table" end)
probeCap("firesignal",        function() return typeof(firesignal) == "function" end)
probeCap("fireproximityprompt", function() return typeof(fireproximityprompt) == "function" end)

-- VIM (VirtualInputManager)
local VIM
pcall(function() VIM = Services.VirtualInputManager end)
Cap.VIM = (VIM ~= nil)

-- Executor name (for display only — we gate on capabilities, not names)
local ExecutorName = "Unknown"
pcall(function()
    if getexecutorname then ExecutorName = getexecutorname()
    elseif identifyexecutor then ExecutorName = identifyexecutor() end
end)
PHANTOM.ExecutorName = ExecutorName

-- Sea detection via PlaceId
local PlaceId = game.PlaceId
local SEA_IDS = {
    [2753915549] = 1,   -- First Sea
    [4442272183] = 2,   -- Second Sea
    [7449423635] = 3,   -- Third Sea
}
PHANTOM.State.CurrentSea = SEA_IDS[PlaceId] or 1

-- Capability count (for dashboard)
local capCount = 0
for _, v in pairs(Cap) do if v then capCount = capCount + 1 end end

-- ================================================================
-- [3] CONFIGURATION
-- ================================================================
PHANTOM.Config = {
    -- Farm
    AutoFarm        = false,
    SelectedMonster = "Auto",

    -- Combat
    AttackMode   = "FastClick",  -- FastClick | DirectHit | Combined
    AttackSpeed  = 0.01,
    HitboxSize   = 50,

    -- Fruit
    FruitSniper      = false,
    FruitMode        = "Notify",  -- Eat | Store | Notify
    FruitSniperDelay = 0.5,

    -- Stats
    AutoStats = false,
    StatMode  = "Melee",

    -- Raid
    AutoRaid  = false,
    RaidFruit = "",

    -- Race
    AutoRaceUpgrade = false,

    -- Navigation
    TeleportMode = "Instant",  -- Instant | Waypoint

    -- Security
    AntiDetection    = true,
    BehavioralMimicry = true,
    RemoteFirewall   = true,
    AntiAFK          = true,
    FakeMovement     = true,

    -- Performance
    PerfMode          = "UltraLow",
    DisableEffects    = true,
    DisableSounds     = false,
    DecalCulling      = true,
    DecalCullDistance  = 150,
    AutoGC            = true,
    GCInterval        = 60,

    -- Mob Control
    BringMobs    = false,
    BringDistance = 10,

    -- Webhook
    WebhookURL        = "",
    WebhookOnFruit    = true,
    WebhookOnLevelUp  = true,

    -- Misc
    AutoRejoin = true,
}

local Config = PHANTOM.Config   -- alias for convenience

-- ================================================================
-- [4] UTILITIES
-- ================================================================

function Util.Try(fn, ...)
    local a = {...}
    return pcall(function() return fn(unpack(a)) end)
end

function Util.GetCharacter()
    local c = Player.Character
    if not c then return nil, nil, nil end
    return c, c:FindFirstChild("Humanoid"), c:FindFirstChild("HumanoidRootPart")
end

function Util.IsAlive()
    local c, h, r = Util.GetCharacter()
    return c and h and r and h.Health > 0
end

function Util.Distance(a, b)
    if typeof(a) == "CFrame" then a = a.Position end
    if typeof(b) == "CFrame" then b = b.Position end
    return (a - b).Magnitude
end

function Util.GetPosition()
    local _, _, r = Util.GetCharacter()
    return r and r.Position or Vector3.new(0, 0, 0)
end

function Util.Teleport(cf)
    if typeof(cf) == "Vector3" then cf = CFrame.new(cf) end
    if typeof(cf) ~= "CFrame" then return false end
    local _, _, r = Util.GetCharacter()
    if not r then return false end
    return pcall(function() r.CFrame = cf end)
end

function Util.WaypointTeleport(targetCF, step, delay)
    step  = step  or 100
    delay = delay or 0.05
    local _, _, r = Util.GetCharacter()
    if not r then return false end
    local s = r.Position
    local e = targetCF.Position
    local d = (e - s).Magnitude
    if d < step then return Util.Teleport(targetCF) end
    local dir   = (e - s).Unit
    local steps = math.ceil(d / step)
    for i = 1, steps - 1 do
        if not Util.IsAlive() then return false end
        local p = s + dir * (step * i)
        pcall(function() r.CFrame = CFrame.new(p.X, p.Y + 5, p.Z) end)
        task.wait(delay)
    end
    return Util.Teleport(targetCF)
end

function Util.NavigateTo(cf)
    if Config.TeleportMode == "Waypoint" then
        return Util.WaypointTeleport(cf)
    end
    return Util.Teleport(cf)
end

function Util.FindMob(name, maxDist)
    maxDist = maxDist or math.huge
    local best, bestDist = nil, maxDist
    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return nil, math.huge end
    for _, m in ipairs(enemies:GetChildren()) do
        local h = m:FindFirstChild("Humanoid")
        local r = m:FindFirstChild("HumanoidRootPart")
        if h and r and h.Health > 0 and (name == nil or m.Name == name) then
            local d = Util.Distance(Util.GetPosition(), r.Position)
            if d < bestDist then best, bestDist = m, d end
        end
    end
    return best, bestDist
end

function Util.FindAllMobs(name)
    local t = {}
    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return t end
    for _, m in ipairs(enemies:GetChildren()) do
        local h = m:FindFirstChild("Humanoid")
        local r = m:FindFirstChild("HumanoidRootPart")
        if h and r and h.Health > 0 and (name == nil or m.Name == name) then
            table.insert(t, m)
        end
    end
    return t
end

function Util.GetLevel()
    local ok, v = pcall(function() return Player.Data.Level.Value end)
    return ok and v or 0
end

function Util.GetBerries()
    local ok, v = pcall(function() return Player.Data.Beli.Value end)
    return ok and v or 0
end

function Util.GetFragments()
    local ok, v = pcall(function() return Player.Data.Fragments.Value end)
    return ok and v or 0
end

function Util.GaussianRandom(mean, sd)
    local u1 = math.random()
    local u2 = math.random()
    return mean + sd * math.sqrt(-2 * math.log(math.max(u1, 1e-10))) * math.cos(2 * math.pi * u2)
end

function Util.HumanDelay(base, var)
    var = var or base * 0.3
    local d = math.clamp(Util.GaussianRandom(base, var), base * 0.2, base * 3)
    task.wait(d)
end

function Util.FormatTime(s)
    return string.format("%02d:%02d:%02d", math.floor(s/3600), math.floor(s%3600/60), math.floor(s%60))
end

function Util.FormatNumber(n)
    local s = tostring(math.floor(n))
    local r, k = s, 1
    while k > 0 do r, k = string.gsub(r, "^(-?%d+)(%d%d%d)", "%1,%2") end
    return r
end

function Util.InvokeRemote(...)
    return pcall(function() return RS.Remotes.CommF_:InvokeServer(...) end)
end

-- ================================================================
-- [5] QUEST DATABASE  —  Sea 1 / 2 / 3
-- ================================================================
--  Format: {lvMin, lvMax, mobName, questName, questLv, npcCFrame, mobCFrame [, extras]}
--  extras = { entrance = "remoteArg", pos = Vector3 }

QuestDB.Sea1 = {
    {1,   9,   "Bandit",              "BanditQuest1",   1, CFrame.new(1060.93,16.45,1547.78),    CFrame.new(1038.55,41.29,1576.50)},
    {10,  14,  "Monkey",              "JungleQuest",    1, CFrame.new(-1601.65,36.85,153.38),     CFrame.new(-1448.14,50.85,63.60)},
    {15,  29,  "Gorilla",             "JungleQuest",    2, CFrame.new(-1601.65,36.85,153.38),     CFrame.new(-1142.64,40.46,-515.39)},
    {30,  39,  "Pirate",              "BuggyQuest1",    1, CFrame.new(-1140.17,4.75,3827.40),     CFrame.new(-1201.08,40.62,3857.59)},
    {40,  59,  "Brute",               "BuggyQuest1",    2, CFrame.new(-1140.17,4.75,3827.40),     CFrame.new(-1387.53,24.59,4100.95)},
    {60,  74,  "Desert Bandit",       "DesertQuest",    1, CFrame.new(896.51,6.43,4390.14),       CFrame.new(984.99,16.10,4417.91)},
    {75,  89,  "Desert Officer",      "DesertQuest",    2, CFrame.new(896.51,6.43,4390.14),       CFrame.new(1547.15,14.45,4381.80)},
    {90,  99,  "Snow Bandit",         "SnowQuest",      1, CFrame.new(1386.80,87.27,-1298.35),    CFrame.new(1356.30,105.76,-1328.24)},
    {100, 119, "Snowman",             "SnowQuest",      2, CFrame.new(1386.80,87.27,-1298.35),    CFrame.new(1218.79,138.01,-1488.02)},
    {120, 149, "Chief Petty Officer", "MarineQuest2",   1, CFrame.new(-5035.49,28.67,4324.18),    CFrame.new(-4931.15,65.79,4121.83)},
    {150, 174, "Sky Bandit",          "SkyQuest",       1, CFrame.new(-4842.13,717.69,-2623.04),  CFrame.new(-4955.64,365.46,-2908.18)},
    {175, 189, "Dark Master",         "SkyQuest",       2, CFrame.new(-4842.13,717.69,-2623.04),  CFrame.new(-5148.16,439.04,-2332.96)},
    {190, 209, "Prisoner",            "PrisonerQuest",  1, CFrame.new(5310.60,0.35,474.94),       CFrame.new(4937.31,0.33,649.57)},
    {210, 249, "Dangerous Prisoner",  "PrisonerQuest",  2, CFrame.new(5310.60,0.35,474.94),       CFrame.new(5099.66,0.35,1055.75)},
    {250, 274, "Toga Warrior",        "ColosseumQuest", 1, CFrame.new(-1577.78,7.41,-2984.48),    CFrame.new(-1872.51,49.08,-2913.81)},
    {275, 299, "Gladiator",           "ColosseumQuest", 2, CFrame.new(-1577.78,7.41,-2984.48),    CFrame.new(-1521.37,81.20,-3066.31)},
    {300, 324, "Military Soldier",    "MagmaQuest",     1, CFrame.new(-5316.11,12.26,8517.00),    CFrame.new(-5369.00,61.24,8556.49)},
    {325, 374, "Military Spy",        "MagmaQuest",     2, CFrame.new(-5316.11,12.26,8517.00),    CFrame.new(-5787.00,75.82,8651.69)},
    {375, 399, "Fishman Warrior",     "FishmanQuest",   1, CFrame.new(61122.65,18.49,1569.39),    CFrame.new(60844.10,98.46,1298.39),
        {entrance="requestEntrance", pos=Vector3.new(61163.85,11.67,1819.78)}},
    {400, 449, "Fishman Commando",    "FishmanQuest",   2, CFrame.new(61122.65,18.49,1569.39),    CFrame.new(61738.39,64.20,1433.83),
        {entrance="requestEntrance", pos=Vector3.new(61163.85,11.67,1819.78)}},
    {450, 474, "God's Guard",         "SkyExp1Quest",   1, CFrame.new(-4721.86,845.30,-1953.84),  CFrame.new(-4628.04,866.92,-1931.23),
        {entrance="requestEntrance", pos=Vector3.new(-4607.82,872.54,-1667.55)}},
    {475, 524, "Shanda",              "SkyExp1Quest",   2, CFrame.new(-7863.15,5545.51,-378.42),  CFrame.new(-7685.14,5601.07,-441.38),
        {entrance="requestEntrance", pos=Vector3.new(-7894.61,5547.14,-380.29)}},
    {525, 549, "Royal Squad",         "SkyExp2Quest",   1, CFrame.new(-7903.38,5635.98,-1410.92), CFrame.new(-7654.25,5637.10,-1407.75)},
    {550, 624, "Royal Soldier",       "SkyExp2Quest",   2, CFrame.new(-7903.38,5635.98,-1410.92), CFrame.new(-7760.41,5679.90,-1884.81)},
    {625, 649, "Galley Pirate",       "FountainQuest",  1, CFrame.new(5258.27,38.52,4050.04),     CFrame.new(5557.16,152.32,3998.77)},
    {650, 699, "Galley Captain",      "FountainQuest",  2, CFrame.new(5258.27,38.52,4050.04),     CFrame.new(5677.67,92.78,4966.63)},
}

QuestDB.Sea2 = {
    {700,  724,  "Raider",             "Area1Quest",        1, CFrame.new(-427.72,72.99,1835.94),     CFrame.new(68.87,93.63,2429.67)},
    {725,  774,  "Mercenary",          "Area1Quest",        2, CFrame.new(-427.72,72.99,1835.94),     CFrame.new(-864.85,122.47,1453.15)},
    {775,  799,  "Swan Pirate",        "Area2Quest",        1, CFrame.new(635.61,73.09,917.81),       CFrame.new(1065.36,137.64,1324.37)},
    {800,  874,  "Factory Staff",      "Area2Quest",        2, CFrame.new(635.61,73.09,917.81),       CFrame.new(533.22,128.46,355.62)},
    {875,  899,  "Marine Lieutenant",  "MarineQuest3",      1, CFrame.new(-2440.99,73.04,-3217.70),   CFrame.new(-2489.26,84.61,-3151.88)},
    {900,  949,  "Marine Captain",     "MarineQuest3",      2, CFrame.new(-2440.99,73.04,-3217.70),   CFrame.new(-2335.20,79.78,-3245.86)},
    {950,  974,  "Zombie",             "ZombieQuest",       1, CFrame.new(-5494.34,48.50,-794.59),    CFrame.new(-5536.49,101.08,-835.59)},
    {975,  999,  "Vampire",            "ZombieQuest",       2, CFrame.new(-5494.34,48.50,-794.59),    CFrame.new(-5806.10,16.72,-1164.43)},
    {1000, 1049, "Snow Trooper",       "SnowMountainQuest", 1, CFrame.new(607.05,401.44,-5370.55),   CFrame.new(535.21,432.74,-5484.91)},
    {1050, 1099, "Winter Warrior",     "SnowMountainQuest", 2, CFrame.new(607.05,401.44,-5370.55),   CFrame.new(1234.44,456.95,-5174.13)},
    {1100, 1124, "Lab Subordinate",    "IceSideQuest",      1, CFrame.new(-6061.84,15.92,-4902.03),  CFrame.new(-5720.55,63.30,-4784.61)},
    {1125, 1174, "Horned Warrior",     "IceSideQuest",      2, CFrame.new(-6061.84,15.92,-4902.03),  CFrame.new(-6292.75,91.18,-5502.64)},
    {1175, 1199, "Magma Ninja",        "FireSideQuest",     1, CFrame.new(-5429.04,15.97,-5297.96),  CFrame.new(-5461.83,130.36,-5836.47)},
    {1200, 1249, "Lava Pirate",        "FireSideQuest",     2, CFrame.new(-5429.04,15.97,-5297.96),  CFrame.new(-5251.18,55.16,-4774.40)},
    {1250, 1274, "Ship Deckhand",      "ShipQuest1",        1, CFrame.new(1040.29,125.08,32911.03),  CFrame.new(921.12,125.98,33088.32),
        {entrance="requestEntrance", pos=Vector3.new(923.21,126.97,32852.83)}},
    {1275, 1299, "Ship Engineer",      "ShipQuest1",        2, CFrame.new(1040.29,125.08,32911.03),  CFrame.new(886.28,40.47,32800.83),
        {entrance="requestEntrance", pos=Vector3.new(923.21,126.97,32852.83)}},
    {1300, 1324, "Ship Steward",       "ShipQuest2",        1, CFrame.new(971.42,125.08,33245.54),   CFrame.new(943.85,129.58,33444.36),
        {entrance="requestEntrance", pos=Vector3.new(923.21,126.97,32852.83)}},
    {1325, 1349, "Ship Officer",       "ShipQuest2",        2, CFrame.new(971.42,125.08,33245.54),   CFrame.new(955.38,181.08,33331.89),
        {entrance="requestEntrance", pos=Vector3.new(923.21,126.97,32852.83)}},
    {1350, 1374, "Arctic Warrior",     "FrostQuest",        1, CFrame.new(5668.13,28.20,-6484.60),   CFrame.new(5935.45,77.26,-6472.75),
        {entrance="requestEntrance", pos=Vector3.new(-6508.55,89.03,-132.83)}},
    {1375, 1424, "Snow Lurker",        "FrostQuest",        2, CFrame.new(5668.13,28.20,-6484.60),   CFrame.new(5628.48,57.57,-6618.34)},
    {1425, 1449, "Sea Soldier",        "ForgottenQuest",    1, CFrame.new(-3054.58,236.87,-10147.79),CFrame.new(-3185.01,58.78,-9663.60)},
    {1450, 1499, "Water Fighter",      "ForgottenQuest",    2, CFrame.new(-3054.58,236.87,-10147.79),CFrame.new(-3262.93,298.69,-10552.52)},
}

QuestDB.Sea3 = {
    {1500, 1524, "Pirate Millionaire",  "PiratePortQuest",   1, CFrame.new(-450.10,107.68,5950.72),   CFrame.new(-193.99,56.12,5755.78)},
    {1525, 1574, "Pistol Billionaire",  "PiratePortQuest",   2, CFrame.new(-450.10,107.68,5950.72),   CFrame.new(-188.14,84.49,6337.04)},
    {1575, 1599, "Dragon Crew Warrior", "DragonCrewQuest",   1, CFrame.new(6735.11,126.99,-711.09),   CFrame.new(6615.23,50.84,-978.93)},
    {1600, 1624, "Dragon Crew Archer",  "DragonCrewQuest",   2, CFrame.new(6735.11,126.99,-711.09),   CFrame.new(6818.58,483.71,512.72)},
    {1625, 1649, "Hydra Enforcer",      "VenomCrewQuest",    1, CFrame.new(5446.87,601.62,749.45),    CFrame.new(4547.11,1001.60,334.19)},
    {1650, 1699, "Venomous Assailant",  "VenomCrewQuest",    2, CFrame.new(5446.87,601.62,749.45),    CFrame.new(4637.88,1077.85,882.41)},
    {1700, 1724, "Marine Commodore",    "MarineTreeIsland",  1, CFrame.new(2179.98,28.73,-6740.05),   CFrame.new(2198.00,128.71,-7109.50)},
    {1725, 1774, "Marine Rear Admiral", "MarineTreeIsland",  2, CFrame.new(2179.98,28.73,-6740.05),   CFrame.new(3294.31,385.41,-7048.63)},
    {1775, 1799, "Fishman Raider",      "DeepForestIsland3", 1, CFrame.new(-10582.75,331.78,-8757.66),CFrame.new(-10555.00,331.00,-8730.00)},
    {1800, 1849, "Forest Pirate",       "DeepForestIsland3", 2, CFrame.new(-10582.75,331.78,-8757.66),CFrame.new(-10340.00,331.00,-8500.00)},
    {1850, 1899, "Demonic Soul",        "HauntedQuest",      1, CFrame.new(-9516.40,145.00,5765.00),  CFrame.new(-9400.00,145.00,5600.00)},
    {1900, 1949, "Possessed Mummy",     "HauntedQuest",      2, CFrame.new(-9516.40,145.00,5765.00),  CFrame.new(-9200.00,145.00,5400.00)},
    {1950, 1999, "Cookie Crafter",      "TreatsQuest",       1, CFrame.new(-2286.00,26.00,-11140.00), CFrame.new(-2100.00,26.00,-11000.00)},
    {2000, 2049, "Cake Guard",          "TreatsQuest",       2, CFrame.new(-2286.00,26.00,-11140.00), CFrame.new(-2400.00,26.00,-11300.00)},
    {2050, 2099, "Biscuit Soldier",     "TreatsQuest2",      1, CFrame.new(-2600.00,30.00,-11500.00), CFrame.new(-2700.00,30.00,-11600.00)},
    {2100, 2149, "Chocolate Battler",   "TreatsQuest2",      2, CFrame.new(-2600.00,30.00,-11500.00), CFrame.new(-2800.00,30.00,-11700.00)},
    {2150, 2199, "Sweet Thief",         "CandyQuest",        1, CFrame.new(-3000.00,35.00,-12000.00), CFrame.new(-3100.00,35.00,-12100.00)},
    {2200, 2274, "Candy Rebel",         "CandyQuest",        2, CFrame.new(-3000.00,35.00,-12000.00), CFrame.new(-3200.00,35.00,-12200.00)},
    {2275, 2324, "Snow Demon",          "TundraQuest",       1, CFrame.new(5600.00,60.00,-7000.00),   CFrame.new(5700.00,60.00,-7100.00)},
    {2325, 2374, "Frozen Warrior",      "TundraQuest",       2, CFrame.new(5600.00,60.00,-7000.00),   CFrame.new(5800.00,60.00,-7200.00)},
    {2375, 2449, "Arctic Pirate",       "TurtleQuest",       1, CFrame.new(-12500.00,400.00,-7500.00),CFrame.new(-12600.00,400.00,-7600.00)},
    {2450, 2550, "Elemental Master",    "TurtleQuest",       2, CFrame.new(-12500.00,400.00,-7500.00),CFrame.new(-12700.00,400.00,-7700.00)},
}

-- Quest lookup by level
function QuestDB.GetQuestForLevel(level, sea)
    local db = QuestDB["Sea" .. tostring(sea)]
    if not db then return nil end
    for i = #db, 1, -1 do
        local q = db[i]
        if level >= q[1] then
            return {
                lvMin     = q[1],  lvMax     = q[2],
                mobName   = q[3],  questName = q[4],
                questLevel= q[5],  npcCFrame = q[6],
                mobCFrame = q[7],  entrance  = q[8],
            }
        end
    end
    local q = db[1]
    return {
        lvMin=q[1], lvMax=q[2], mobName=q[3], questName=q[4],
        questLevel=q[5], npcCFrame=q[6], mobCFrame=q[7], entrance=q[8],
    }
end

-- Quest lookup by mob name
function QuestDB.GetQuestByMob(name, sea)
    local db = QuestDB["Sea" .. tostring(sea)]
    if not db then return nil end
    for _, q in ipairs(db) do
        if q[3] == name then
            return {
                lvMin=q[1], lvMax=q[2], mobName=q[3], questName=q[4],
                questLevel=q[5], npcCFrame=q[6], mobCFrame=q[7], entrance=q[8],
            }
        end
    end
end

-- Get all mob names for dropdown
function QuestDB.GetMobNames(sea)
    local db = QuestDB["Sea" .. tostring(sea)]
    if not db then return {"Auto"} end
    local names = {"Auto"}
    for _, q in ipairs(db) do table.insert(names, q[3]) end
    return names
end

-- ================================================================
-- [6] SECURITY ENGINE  —  5-Layer Anti-Detection
-- ================================================================

-- ── Layer 1: Metamethod Armor ────────────────────────────────────
function Security.InitMetamethodArmor()
    if not (Cap.hookmetamethod and Cap.newcclosure and Cap.getnamecallmethod) then return end

    local BlockedNames = {
        TeleportDetect=1, YOURMOTHER=1, FE_CHECKER=1, Exploit_Check=1,
        AntiExploit=1, AC_Check=1, Kick=1,
    }
    local BlockedPatterns = {"anticheat","anti_cheat","exploit","detect","checker","ban"}

    local function isBlocked(n)
        if BlockedNames[n] then return true end
        local lo = string.lower(n)
        for _, p in ipairs(BlockedPatterns) do
            if string.find(lo, p) then return true end
        end
        return false
    end

    pcall(function()
        local old
        old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" then
                if isBlocked(self.Name) then
                    return method == "InvokeServer" and nil or nil
                end
            end
            if method == "Kick" and self == Player then return end
            return old(self, ...)
        end))
    end)
end

-- ── Layer 2: Anti-AFK ────────────────────────────────────────────
function Security.InitAntiAFK()
    local c = Player.Idled:Connect(function()
        pcall(function()
            VirtualUser:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
            task.wait(1)
            VirtualUser:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        end)
    end)
    table.insert(PHANTOM.Connections, c)
end

-- ── Layer 3: Behavioral Mimicry ──────────────────────────────────
function Security.InitBehavioralMimicry()
    task.spawn(function()
        while PHANTOM.State.Running do
            if Config.BehavioralMimicry then
                pcall(function()
                    local _, _, r = Util.GetCharacter()
                    if not r then return end
                    local action = math.random(1, 5)
                    if action == 1 then
                        local cam = workspace.CurrentCamera
                        if cam then cam.CFrame = cam.CFrame * CFrame.Angles(0, math.rad(math.random(-3,3)), 0) end
                    elseif action == 2 then
                        r.CFrame = r.CFrame + Vector3.new(math.random(-1,1)*0.01, 0, math.random(-1,1)*0.01)
                    end
                    -- actions 3-5 are intentional no-ops (natural idle pauses)
                end)
            end
            task.wait(Util.GaussianRandom(15, 5))
        end
    end)
end

-- ── Layer 4: Fake Movement ───────────────────────────────────────
function Security.InitFakeMovement()
    task.spawn(function()
        while PHANTOM.State.Running do
            if Config.FakeMovement then
                pcall(function()
                    local _, h = Util.GetCharacter()
                    if h and h.MoveDirection.Magnitude < 0.1 then
                        h:ChangeState(Enum.HumanoidStateType.Jumping)
                        task.wait(0.05)
                        h:ChangeState(Enum.HumanoidStateType.Landed)
                    end
                end)
            end
            task.wait(Util.GaussianRandom(12, 4))
        end
    end)
end

-- ── Layer 5: SimulationRadius Control ────────────────────────────
function Security.InitSimRadius()
    if not Cap.sethiddenproperty then return end
    task.spawn(function()
        while PHANTOM.State.Running do
            pcall(function()
                if Util.IsAlive() then
                    sethiddenproperty(Player, "SimulationRadius", math.huge)
                    sethiddenproperty(Player, "MaximumSimulationRadius", math.huge)
                end
            end)
            task.wait(3)
        end
    end)
end

function Security.Init()
    if Config.AntiDetection then Security.InitMetamethodArmor() end
    if Config.AntiAFK        then Security.InitAntiAFK()        end
    Security.InitBehavioralMimicry()
    Security.InitFakeMovement()
    Security.InitSimRadius()
end

-- ================================================================
-- [7] ADAPTIVE PERFORMANCE ENGINE
-- ================================================================

Perf.FPSHistory = {}
Perf.CurrentFPS = 60

function Perf.ApplyProfile(profile)
    pcall(function()
        if profile == "UltraLow" then
            Lighting.GlobalShadows = false
            Lighting.FogEnd        = 100000
            Lighting.Brightness    = 1
            Lighting.ClockTime     = 12
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        elseif profile == "Balanced" then
            Lighting.GlobalShadows = false
            Lighting.FogEnd        = 9000
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level04
        elseif profile == "Quality" then
            Lighting.GlobalShadows = true
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level07
        end
    end)
    pcall(function()
        local t = workspace:FindFirstChild("Terrain")
        if t then
            t.WaterWaveSize    = 0
            t.WaterWaveSpeed   = 0
            t.WaterReflectance = 0
            t.WaterTransparency= 1
        end
    end)
end

function Perf.StartFPSMonitor()
    local last = tick()
    local conn = RunService.RenderStepped:Connect(function()
        local now = tick()
        local fps = 1 / math.max(now - last, 0.001)
        last = now
        table.insert(Perf.FPSHistory, fps)
        if #Perf.FPSHistory > 60 then table.remove(Perf.FPSHistory, 1) end
        local sum = 0
        for _, v in ipairs(Perf.FPSHistory) do sum = sum + v end
        Perf.CurrentFPS = math.floor(sum / #Perf.FPSHistory)
    end)
    table.insert(PHANTOM.Connections, conn)
end

function Perf.StartEffectCleaner()
    task.spawn(function()
        while PHANTOM.State.Running do
            if Config.DisableEffects then
                pcall(function()
                    for _, v in pairs(workspace:GetDescendants()) do
                        if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke") or v:IsA("Fire") or v:IsA("Sparkles") then
                            v.Enabled = false
                            if v:IsA("ParticleEmitter") then v.Rate = 0 end
                        end
                    end
                end)
            end
            if Config.DisableSounds then
                pcall(function()
                    local c = Player.Character
                    for _, v in pairs(workspace:GetDescendants()) do
                        if v:IsA("Sound") and v.Parent ~= c then v.Volume = 0; v.Playing = false end
                    end
                end)
            end
            task.wait(5)
        end
    end)
end

function Perf.StartDecalCuller()
    task.spawn(function()
        while PHANTOM.State.Running do
            if Config.DecalCulling then
                pcall(function()
                    local pos  = Util.GetPosition()
                    local dist = Config.DecalCullDistance
                    for _, v in pairs(workspace:GetDescendants()) do
                        if (v:IsA("Decal") or v:IsA("Texture")) and v.Parent and v.Parent:IsA("BasePart") then
                            v.Transparency = (v.Parent.Position - pos).Magnitude > dist and 1 or 0
                        end
                    end
                end)
            end
            task.wait(3)
        end
    end)
end

function Perf.StartGC()
    task.spawn(function()
        while PHANTOM.State.Running do
            if Config.AutoGC then pcall(collectgarbage, "collect") end
            task.wait(Config.GCInterval)
        end
    end)
end

function Perf.Init()
    Perf.ApplyProfile(Config.PerfMode)
    Perf.StartFPSMonitor()
    Perf.StartEffectCleaner()
    Perf.StartDecalCuller()
    Perf.StartGC()
end

-- ================================================================
-- [8] COMBAT ENGINE
-- ================================================================

Combat._attackMelee   = nil
Combat._uvCache       = nil
Combat._hitRemote     = nil
Combat._attackRemote  = nil
Combat._weaponData    = nil
Combat._combatUtil    = nil
Combat._origHitbox    = {}

function Combat.Init()
    pcall(function()
        local Net = require(RS:WaitForChild("Modules"):WaitForChild("Net"))
        Combat._hitRemote = Net:RemoteEvent("RegisterHit")
    end)
    pcall(function()
        Combat._attackRemote = RS.Modules.Net:FindFirstChild("RE/RegisterAttack")
    end)
    pcall(function()
        Combat._combatUtil = require(RS:WaitForChild("Modules"):WaitForChild("CombatUtil"))
    end)
    pcall(function()
        Combat._weaponData = require(RS:WaitForChild("Modules"):WaitForChild("WeaponData"))
    end)
    Combat.FindAttackMelee()
end

function Combat.FindAttackMelee()
    if Combat._attackMelee then return Combat._attackMelee end
    if not (Cap.getgc and Cap.debuggetinfo) then return nil end
    pcall(function()
        for _, v in next, getgc(true) do
            if typeof(v) == "function" then
                local ok, info = pcall(debug.getinfo, v)
                if ok and info and info.name == "attackMelee" then
                    Combat._attackMelee = v
                    Combat.CacheUpvalues(v)
                    return
                end
            end
        end
    end)
    return Combat._attackMelee
end

function Combat.CacheUpvalues(fn)
    if Combat._uvCache or not Cap.getupvalues then return end
    Combat._uvCache = {}
    local ok, uvs = pcall(getupvalues, fn)
    if not ok or type(uvs) ~= "table" then return end
    for i, v in next, uvs do
        if typeof(v) == "number" and v > 0 and v < 5 then
            table.insert(Combat._uvCache, {idx=i, kind="number"})
        elseif typeof(v) == "boolean" and v == true then
            table.insert(Combat._uvCache, {idx=i, kind="boolean"})
        end
    end
end

function Combat.ApplyFastUV(fn)
    if not Cap.setupvalue or not Combat._uvCache then return end
    for _, uv in ipairs(Combat._uvCache) do
        pcall(setupvalue, fn, uv.idx, uv.kind == "number" and 0 or false)
    end
end

function Combat.FastClick()
    pcall(function()
        local fn = Combat._attackMelee or Combat.FindAttackMelee()
        if typeof(fn) ~= "function" then return end

        local char = Player.Character
        if not char then return end
        local tool = char:FindFirstChildOfClass("Tool")
        if not tool then return end

        local wn = tool:GetAttribute("WeaponName")
        if not wn or not Combat._weaponData or not Combat._weaponData[wn] then return end
        local w = Combat._weaponData[wn]

        if not Combat._origHitbox[wn] then
            Combat._origHitbox[wn] = w.HitboxMagnitude
        end

        Combat.ApplyFastUV(fn)
        w.HitboxMagnitude = Config.HitboxSize

        if VIM then
            pcall(function()
                VIM:SendMouseButtonEvent(0,0,0,true,game,0)
                VIM:SendMouseButtonEvent(0,0,0,false,game,0)
            end)
        end
        pcall(fn)
    end)
end

function Combat.DirectHit(target)
    if not Combat._hitRemote then return end
    local char = Player.Character
    if not char then return end
    local hrp = target:FindFirstChild("HumanoidRootPart")
    local hum = target:FindFirstChild("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then return end

    pcall(function()
        local wn = ""
        if Combat._combatUtil then wn = Combat._combatUtil:GetWeaponName(tool) or "" end
        local uuid = tostring(Player.UserId):sub(2,4) .. tostring(math.random(10000,99999))
        Combat._hitRemote:FireServer(hrp, {{target, hrp}}, nil, nil, uuid)
        if Combat._combatUtil then
            pcall(function() Combat._combatUtil:ApplyDamageHighlight(target, char, wn, hrp, nil) end)
        end
    end)
end

function Combat.AttackAllMobs(mobName)
    if Combat._attackRemote then
        pcall(function() Combat._attackRemote:FireServer() end)
    end
    local mobs = Util.FindAllMobs(mobName)
    table.sort(mobs, function(a,b)
        local ha = a:FindFirstChild("Humanoid")
        local hb = b:FindFirstChild("Humanoid")
        if not ha or not hb then return false end
        return ha.Health < hb.Health
    end)
    for _, mob in ipairs(mobs) do Combat.DirectHit(mob) end
end

function Combat.BringMob(mob, dist)
    dist = dist or 10
    local _, _, hrp = Util.GetCharacter()
    if not hrp then return end
    local mHRP = mob:FindFirstChild("HumanoidRootPart")
    if not mHRP then return end
    pcall(function()
        mHRP.CFrame = hrp.CFrame * CFrame.new(0, 0, -dist)
    end)
end

function Combat.Attack(mobName)
    local mode = Config.AttackMode
    if mode == "FastClick" then
        Combat.FastClick()
    elseif mode == "DirectHit" then
        Combat.AttackAllMobs(mobName)
    elseif mode == "Combined" then
        Combat.FastClick()
        Combat.AttackAllMobs(mobName)
    end
end

function Combat.StartLoop()
    task.spawn(function()
        while PHANTOM.State.Running do
            if PHANTOM.State.FarmState == "COMBAT" then
                local qd = PHANTOM.State.CurrentQuest
                if qd then
                    if Config.BringMobs then
                        for _, mob in ipairs(Util.FindAllMobs(qd.mobName)) do
                            Combat.BringMob(mob, Config.BringDistance)
                        end
                    end
                    Combat.Attack(qd.mobName)
                end
            end
            task.wait(Config.AttackSpeed)
        end
    end)
end

-- ================================================================
-- [9] QUEST ENGINE
-- ================================================================

function Quest.IsQuestActive()
    local ok, r = pcall(function()
        local main = PlayerGui:FindFirstChild("Main")
        if main then
            local q = main:FindFirstChild("Quest")
            return q and q.Visible
        end
        return false
    end)
    return ok and r or false
end

function Quest.AcceptQuest(questName, questLevel)
    return pcall(function()
        RS.Remotes.CommF_:InvokeServer("StartQuest", questName, questLevel)
    end)
end

function Quest.GetOptimalQuest()
    local level = Util.GetLevel()
    local sea   = PHANTOM.State.CurrentSea
    if Config.SelectedMonster ~= "Auto" then
        local q = QuestDB.GetQuestByMob(Config.SelectedMonster, sea)
        if q then return q end
    end
    return QuestDB.GetQuestForLevel(level, sea)
end

function Quest.HandleEntrance(qd)
    if not qd.entrance then return end
    local dist = Util.Distance(Util.GetPosition(), qd.mobCFrame.Position)
    if dist > 3000 then
        pcall(function()
            RS.Remotes.CommF_:InvokeServer(qd.entrance.entrance, qd.entrance.pos)
        end)
        task.wait(1)
    end
end

-- ================================================================
-- [10] AUTO-FARM CONTROLLER  —  The Brain
-- ================================================================

Farm.Stats = {
    StartTime = 0,
    Kills     = 0,
    Quests    = 0,
    StartLv   = 0,
    LevelUps  = 0,
}

function Farm.Start()
    if PHANTOM.State.FarmState ~= "IDLE" then return end
    Farm.Stats.StartTime = os.clock()
    Farm.Stats.StartLv   = Util.GetLevel()
    Farm.Stats.Kills     = 0
    Farm.Stats.Quests    = 0
    Farm.Stats.LevelUps  = 0
    PHANTOM.State.FarmState = "STARTING"

    task.spawn(function()
        while PHANTOM.State.Running and Config.AutoFarm do
            local ok, err = pcall(Farm.Tick)
            if not ok then task.wait(1) end
            task.wait(0.1)
        end
        PHANTOM.State.FarmState = "IDLE"
    end)
end

function Farm.Stop()
    Config.AutoFarm = false
    PHANTOM.State.FarmState = "IDLE"
end

function Farm.Tick()
    -- Dead? Wait for respawn
    if not Util.IsAlive() then
        PHANTOM.State.FarmState = "DEAD"
        local tries = 0
        while not Util.IsAlive() and tries < 30 do task.wait(1); tries = tries + 1 end
        return
    end

    -- Get quest
    local qd = Quest.GetOptimalQuest()
    if not qd then PHANTOM.State.FarmState = "NO_QUEST"; task.wait(2); return end
    PHANTOM.State.CurrentQuest = qd

    -- Track level ups
    local lv = Util.GetLevel()
    if lv > Farm.Stats.StartLv + Farm.Stats.LevelUps then
        Farm.Stats.LevelUps = lv - Farm.Stats.StartLv
        if Config.AutoStats then Stats.DistributePoints() end
        if Config.WebhookURL ~= "" and Config.WebhookOnLevelUp then
            Webhook.Send("levelup", {level = lv})
        end
        qd = Quest.GetOptimalQuest()
        PHANTOM.State.CurrentQuest = qd
        if not qd then return end
    end

    -- Sea transition warning
    local sea = PHANTOM.State.CurrentSea
    if (sea == 1 and lv >= 700) or (sea == 2 and lv >= 1500) then
        PHANTOM.State.FarmState = "SEA_CHANGE_NEEDED"
        -- Can't auto-teleport between places — just flag it
    end

    -- Quest active?
    local hasQuest = Quest.IsQuestActive()

    if not hasQuest then
        -- Travel to NPC → Accept
        PHANTOM.State.FarmState = "TRAVEL_NPC"
        Quest.HandleEntrance(qd)
        if Util.Distance(Util.GetPosition(), qd.npcCFrame.Position) > 30 then
            Util.NavigateTo(qd.npcCFrame)
            task.wait(0.5)
        end
        PHANTOM.State.FarmState = "ACCEPTING"
        Quest.AcceptQuest(qd.questName, qd.questLevel)
        task.wait(0.3)
        return
    end

    -- Find mob
    local mob, mobDist = Util.FindMob(qd.mobName, 500)

    if not mob or mobDist > 200 then
        PHANTOM.State.FarmState = "TRAVEL_MOB"
        Quest.HandleEntrance(qd)
        Util.NavigateTo(qd.mobCFrame)
        task.wait(0.3)
        return
    end

    -- FIGHT!
    PHANTOM.State.FarmState = "COMBAT"

    if Config.BringMobs then
        for _, m in ipairs(Util.FindAllMobs(qd.mobName)) do
            Combat.BringMob(m, Config.BringDistance)
        end
    end

    Combat.Attack(qd.mobName)

    -- Track kills (heuristic: if the mob reference changed, we got a kill)
    task.wait(Config.AttackSpeed)
    local newMob = Util.FindMob(qd.mobName, 500)
    if mob and (not newMob or newMob ~= mob) then
        Farm.Stats.Kills = Farm.Stats.Kills + 1
    end
end

-- ================================================================
-- [11] DEVIL FRUIT SYSTEM
-- ================================================================

function Fruit.Scan()
    local fruits = {}
    pcall(function()
        for _, v in pairs(workspace:GetDescendants()) do
            if v:IsA("Tool") and v.Parent == workspace then
                table.insert(fruits, {
                    name     = v.Name,
                    instance = v,
                    position = v:GetPivot().Position,
                    distance = Util.Distance(Util.GetPosition(), v:GetPivot().Position),
                })
            end
        end
    end)
    table.sort(fruits, function(a,b) return a.distance < b.distance end)
    return fruits
end

function Fruit.Collect(fruit)
    if not fruit or not fruit.instance then return false end
    Util.Teleport(CFrame.new(fruit.position))
    task.wait(0.5)
    pcall(function()
        local _, _, r = Util.GetCharacter()
        if r then r.CFrame = CFrame.new(fruit.position) end
        task.wait(0.3)
        if Cap.fireproximityprompt then
            for _, p in pairs(fruit.instance:GetDescendants()) do
                if p:IsA("ProximityPrompt") then pcall(fireproximityprompt, p) end
            end
        end
    end)
    return true
end

function Fruit.Handle(fruit)
    local mode = Config.FruitMode
    if mode == "Eat" then
        Fruit.Collect(fruit)
        pcall(function() RS.Remotes.CommF_:InvokeServer("Eat") end)
    elseif mode == "Store" then
        Fruit.Collect(fruit)
        pcall(function() RS.Remotes.CommF_:InvokeServer("StoreFruit") end)
    elseif mode == "Notify" then
        if Config.WebhookURL ~= "" then
            Webhook.Send("fruit", {name=fruit.name, position=tostring(fruit.position)})
        end
    end
end

function Fruit.StartSniper()
    task.spawn(function()
        while PHANTOM.State.Running do
            if Config.FruitSniper then
                local found = Fruit.Scan()
                if #found > 0 then Fruit.Handle(found[1]) end
            end
            task.wait(Config.FruitSniperDelay)
        end
    end)
end

-- ================================================================
-- [12] AUTO-RAID
-- ================================================================

function Raid.Start()
    task.spawn(function()
        while PHANTOM.State.Running and Config.AutoRaid do
            pcall(function()
                local raidFolder = workspace:FindFirstChild("Raid")
                if raidFolder then
                    for _, mob in ipairs(raidFolder:GetChildren()) do
                        local h = mob:FindFirstChild("Humanoid")
                        if h and h.Health > 0 then Combat.DirectHit(mob) end
                    end
                elseif Config.RaidFruit ~= "" then
                    pcall(function()
                        RS.Remotes.CommF_:InvokeServer("RaidStart", Config.RaidFruit)
                    end)
                end
            end)
            task.wait(0.5)
        end
    end)
end

-- ================================================================
-- [13] RACE UPGRADE
-- ================================================================

function Race.GetCurrent()
    local ok, v = pcall(function() return Player.Data.Race.Value end)
    return ok and v or "Human"
end

function Race.Reroll()
    pcall(function() RS.Remotes.CommF_:InvokeServer("RaceReroll") end)
end

-- ================================================================
-- [14] AUTO STATS
-- ================================================================

function Stats.DistributePoints()
    pcall(function()
        local stat = Config.StatMode or "Melee"
        local pts  = Player.Data.Points and Player.Data.Points.Value or 0
        for i = 1, math.min(pts, 200) do
            RS.Remotes.CommF_:InvokeServer("AddPoint", stat)
            if i % 20 == 0 then task.wait(0.1) end  -- batch for performance
        end
    end)
end

-- ================================================================
-- [15] WEBHOOK
-- ================================================================

function Webhook.Send(eventType, data)
    if Config.WebhookURL == "" or not Cap.request then return end

    local embed = {}
    if eventType == "fruit" then
        embed = {
            title       = "🍎 Devil Fruit Detected!",
            description = "**" .. (data.name or "?") .. "** has spawned!",
            color       = 16744576,
            fields      = {
                {name="Position", value=data.position or "?", inline=true},
                {name="Server",   value=game.JobId,           inline=true},
            },
        }
    elseif eventType == "levelup" then
        embed = {
            title       = "📈 Level Up!",
            description = "Reached level **" .. tostring(data.level) .. "**",
            color       = 5763719,
            fields      = {
                {name="Player", value=Player.Name,                       inline=true},
                {name="Sea",    value=tostring(PHANTOM.State.CurrentSea), inline=true},
            },
        }
    elseif eventType == "session" then
        embed = {
            title  = "📊 Session Summary",
            color  = 3447003,
            fields = {
                {name="Duration", value=data.duration or "0:00",    inline=true},
                {name="Kills",    value=tostring(data.kills or 0),  inline=true},
                {name="Levels",   value=tostring(data.levels or 0), inline=true},
            },
        }
    end
    embed.footer    = {text = "PHANTOM v" .. PHANTOM.Version}
    embed.timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")

    local body = HttpService:JSONEncode({username = "PHANTOM", embeds = {embed}})
    pcall(function()
        local httpReq = request or http_request or (syn and syn.request)
        if httpReq then
            httpReq({
                Url     = Config.WebhookURL,
                Method  = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body    = body,
            })
        end
    end)
end

-- ================================================================
-- [16] PREMIUM UI HUB
-- ================================================================

function PHANTOM.BuildUI()
    -- Load external UI library
    local Library
    pcall(function()
        Library = loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/longhihilonghihi-hub/" ..
            "Aihoicailoncacchobuoiwisibchcj/refs/heads/main/" ..
            "Ditmemayluccailoncacymafluc"
        ))()
    end)
    if not Library then
        warn("[PHANTOM] UI library failed to load. Running headless mode.")
        return
    end
    PHANTOM._Library = Library

    -- ── Window ───────────────────────────────────────────────────
    local Window = Library:CreateWindow({
        Title = "PHANTOM v" .. PHANTOM.Version,
        Desc  = "Ultimate Blox Fruits Framework",
        Image = "rbxassetid://83109821876237",
    })

    -- ── Tab wrapper (adapts library API to clean interface) ──────
    local function wrapTab(raw)
        local sec, flip = nil, false
        local w = {}
        local function ensure()
            if not sec then sec = raw:AddLeftGroupbox(" ") end
        end
        function w:AddSection(name)
            if flip then sec = raw:AddRightGroupbox(name or " ")
            else         sec = raw:AddLeftGroupbox(name or " ") end
            flip = not flip
            return sec
        end
        function w:AddToggle(id, s) ensure(); s.Description=nil; return sec:AddToggle(id, s) end
        function w:AddButton(s, cb) ensure(); if type(s)=="table" then s.Description=nil end; return sec:AddButton(s, cb) end
        function w:AddDropdown(id, s) ensure(); s.Description=nil; return sec:AddDropdown(id, s) end
        function w:AddSlider(id, s) ensure(); s.Description=nil; return sec:AddSlider(s) end
        function w:AddInput(id, s)  ensure(); return sec:AddInput(id, s) end
        function w:AddLabel(t)      ensure(); return sec:AddLabel(t) end
        return w
    end

    -- ── Create all tabs ──────────────────────────────────────────
    local T = {}
    T.Dash     = wrapTab(Window:AddTab("Dashboard"))
    T.Farm     = wrapTab(Window:AddTab("Auto Farm"))
    T.Combat   = wrapTab(Window:AddTab("Combat"))
    T.Fruit    = wrapTab(Window:AddTab("Devil Fruit"))
    T.Raid     = wrapTab(Window:AddTab("Raid"))
    T.Stats    = wrapTab(Window:AddTab("Stats"))
    T.Race     = wrapTab(Window:AddTab("Race"))
    T.Teleport = wrapTab(Window:AddTab("Teleport"))
    T.Security = wrapTab(Window:AddTab("Security"))
    T.Perf     = wrapTab(Window:AddTab("Performance"))
    T.Webhook  = wrapTab(Window:AddTab("Webhook"))
    T.Settings = wrapTab(Window:AddTab("Settings"))

    -- ╔════════════════════════════════════════════════════════════╗
    -- ║  DASHBOARD                                                ║
    -- ╚════════════════════════════════════════════════════════════╝
    T.Dash:AddSection("System Info")
    T.Dash:AddLabel(
        "🎮 PHANTOM v" .. PHANTOM.Version .. "\n" ..
        "👤 " .. Player.Name .. "\n" ..
        "🖥️ " .. ExecutorName .. "\n" ..
        "🌊 Sea " .. PHANTOM.State.CurrentSea .. "\n" ..
        "📊 Level " .. Util.GetLevel() .. "\n" ..
        "🔧 " .. capCount .. " capabilities detected"
    )

    T.Dash:AddSection("Live Stats")
    local dashLabel = T.Dash:AddLabel("Waiting for farm start...")

    -- Live stat updater
    task.spawn(function()
        while PHANTOM.State.Running do
            pcall(function()
                local elapsed = os.clock() - (Farm.Stats.StartTime > 0 and Farm.Stats.StartTime or os.clock())
                local txt = string.format(
                    "⏱ %s  |  💀 %s kills  |  📈 +%d levels\n⚡ %s  |  🎯 %s  |  🖥 %d FPS",
                    Util.FormatTime(math.max(elapsed, 0)),
                    Util.FormatNumber(Farm.Stats.Kills),
                    Farm.Stats.LevelUps,
                    PHANTOM.State.FarmState,
                    PHANTOM.State.CurrentQuest and PHANTOM.State.CurrentQuest.mobName or "None",
                    Perf.CurrentFPS
                )
                pcall(function()
                    if dashLabel and dashLabel.SetText then dashLabel:SetText(txt) end
                end)
            end)
            task.wait(1)
        end
    end)

    -- ╔════════════════════════════════════════════════════════════╗
    -- ║  AUTO FARM                                                ║
    -- ╚════════════════════════════════════════════════════════════╝
    T.Farm:AddSection("Farm Control")
    T.Farm:AddToggle("AutoFarm", {
        Text = "⚔ Enable Auto Farm", Default = false,
        Callback = function(v)
            Config.AutoFarm = v
            if v then Farm.Start() else Farm.Stop() end
        end,
    })

    T.Farm:AddSection("Monster Selection")
    T.Farm:AddDropdown("MonsterSelect", {
        Text = "Target Monster",
        Values  = QuestDB.GetMobNames(PHANTOM.State.CurrentSea),
        Default = "Auto",
        Callback = function(v) Config.SelectedMonster = v end,
    })

    T.Farm:AddToggle("BringMobs", {
        Text = "Bring Mobs To You", Default = false,
        Callback = function(v) Config.BringMobs = v end,
    })
    T.Farm:AddSlider("BringDist", {
        Text = "Bring Distance", Min = 5, Max = 50, Default = 10, Rounding = 0,
        Callback = function(v) Config.BringDistance = v end,
    })

    -- ╔════════════════════════════════════════════════════════════╗
    -- ║  COMBAT                                                   ║
    -- ╚════════════════════════════════════════════════════════════╝
    T.Combat:AddSection("Attack Configuration")
    T.Combat:AddDropdown("AtkMode", {
        Text = "Attack Mode",
        Values  = {"FastClick", "DirectHit", "Combined"},
        Default = "FastClick",
        Callback = function(v) Config.AttackMode = v end,
    })
    T.Combat:AddSlider("AtkSpeed", {
        Text = "Attack Delay (ms)", Min = 1, Max = 500, Default = 10, Rounding = 0,
        Callback = function(v) Config.AttackSpeed = v / 1000 end,
    })

    T.Combat:AddSection("Hitbox")
    T.Combat:AddSlider("Hitbox", {
        Text = "Hitbox Magnitude", Min = 10, Max = 2000, Default = 50, Rounding = 0,
        Callback = function(v) Config.HitboxSize = v end,
    })

    -- ╔════════════════════════════════════════════════════════════╗
    -- ║  DEVIL FRUIT                                              ║
    -- ╚════════════════════════════════════════════════════════════╝
    T.Fruit:AddSection("Fruit Sniper")
    T.Fruit:AddToggle("FruitSniper", {
        Text = "🍎 Enable Fruit Sniper", Default = false,
        Callback = function(v) Config.FruitSniper = v end,
    })
    T.Fruit:AddDropdown("FruitMode", {
        Text = "On Fruit Found",
        Values  = {"Eat", "Store", "Notify"},
        Default = "Notify",
        Callback = function(v) Config.FruitMode = v end,
    })
    T.Fruit:AddSlider("FruitDelay", {
        Text = "Scan Interval (ms)", Min = 100, Max = 5000, Default = 500, Rounding = 0,
        Callback = function(v) Config.FruitSniperDelay = v / 1000 end,
    })

    T.Fruit:AddSection("Manual Scan")
    T.Fruit:AddButton({Text = "🔍 Scan Now"}, function()
        local found = Fruit.Scan()
        if #found > 0 then
            Library:Notify({Title="Fruit Found!", Description=found[1].name .. " — " .. math.floor(found[1].distance) .. " studs away", Duration=5})
        else
            Library:Notify({Title="No Fruits", Description="No devil fruits detected on this server.", Duration=3})
        end
    end)

    -- ╔════════════════════════════════════════════════════════════╗
    -- ║  RAID                                                     ║
    -- ╚════════════════════════════════════════════════════════════╝
    T.Raid:AddSection("Auto Raid")
    T.Raid:AddToggle("AutoRaid", {
        Text = "🏰 Enable Auto Raid", Default = false,
        Callback = function(v)
            Config.AutoRaid = v
            if v then Raid.Start() end
        end,
    })
    T.Raid:AddInput("RaidFruit", {
        Text = "Raid Fruit Name", Default = "", Placeholder = "e.g. Flame",
        Callback = function(v) Config.RaidFruit = v end,
    })

    -- ╔════════════════════════════════════════════════════════════╗
    -- ║  STATS                                                    ║
    -- ╚════════════════════════════════════════════════════════════╝
    T.Stats:AddSection("Auto Stat Distribution")
    T.Stats:AddToggle("AutoStats", {
        Text = "📈 Auto Distribute Stats", Default = false,
        Callback = function(v) Config.AutoStats = v end,
    })
    T.Stats:AddDropdown("StatMode", {
        Text = "Put Points Into",
        Values  = {"Melee", "Defense", "Sword", "Gun", "Blox Fruit"},
        Default = "Melee",
        Callback = function(v) Config.StatMode = v end,
    })

    T.Stats:AddSection("Quick Actions")
    T.Stats:AddButton({Text = "⚡ Distribute All Points Now"}, function()
        Stats.DistributePoints()
        Library:Notify({Title="Stats", Description="Points distributed!", Duration=3})
    end)

    -- ╔════════════════════════════════════════════════════════════╗
    -- ║  RACE                                                     ║
    -- ╚════════════════════════════════════════════════════════════╝
    T.Race:AddSection("Race Info")
    T.Race:AddLabel("Current Race: " .. Race.GetCurrent())

    T.Race:AddSection("Actions")
    T.Race:AddButton({Text = "🎲 Reroll Race"}, function()
        Race.Reroll()
        Library:Notify({Title="Race", Description="Race reroll attempted!", Duration=3})
    end)

    -- ╔════════════════════════════════════════════════════════════╗
    -- ║  TELEPORT                                                 ║
    -- ╚════════════════════════════════════════════════════════════╝
    T.Teleport:AddSection("Quick Teleport")

    -- Build destination list from current sea's quest DB
    local destNames  = {}
    local destFrames = {}
    local seaDB = QuestDB["Sea" .. tostring(PHANTOM.State.CurrentSea)]
    if seaDB then
        for _, q in ipairs(seaDB) do
            if not destFrames[q[3]] then
                table.insert(destNames, q[3])
                destFrames[q[3]] = q[7]
            end
        end
    end

    local selectedDest = destNames[1] or ""
    T.Teleport:AddDropdown("TpDest", {
        Text = "Destination",
        Values  = destNames,
        Default = destNames[1],
        Callback = function(v) selectedDest = v end,
    })
    T.Teleport:AddButton({Text = "🚀 Teleport!"}, function()
        if destFrames[selectedDest] then
            Util.NavigateTo(destFrames[selectedDest])
            Library:Notify({Title="Teleport", Description="Teleported to " .. selectedDest, Duration=3})
        end
    end)

    T.Teleport:AddSection("Options")
    T.Teleport:AddDropdown("TpMode", {
        Text = "Teleport Style",
        Values  = {"Instant", "Waypoint"},
        Default = "Instant",
        Callback = function(v) Config.TeleportMode = v end,
    })

    -- ╔════════════════════════════════════════════════════════════╗
    -- ║  SECURITY                                                 ║
    -- ╚════════════════════════════════════════════════════════════╝
    T.Security:AddSection("Anti-Detection Layers")
    T.Security:AddToggle("Layer1", {
        Text = "🛡 Metamethod Armor", Default = true,
        Callback = function(v) Config.AntiDetection = v end,
    })
    T.Security:AddToggle("Layer2", {
        Text = "🎭 Behavioral Mimicry", Default = true,
        Callback = function(v) Config.BehavioralMimicry = v end,
    })
    T.Security:AddToggle("Layer3", {
        Text = "🚫 Anti-AFK", Default = true,
        Callback = function(v) Config.AntiAFK = v end,
    })
    T.Security:AddToggle("Layer4", {
        Text = "🏃 Fake Movement", Default = true,
        Callback = function(v) Config.FakeMovement = v end,
    })

    T.Security:AddSection("Executor Capabilities")
    local capLines = {}
    for k, v in pairs(Cap) do
        table.insert(capLines, (v and "✅" or "❌") .. " " .. k)
    end
    table.sort(capLines)
    T.Security:AddLabel(table.concat(capLines, "\n"))

    -- ╔════════════════════════════════════════════════════════════╗
    -- ║  PERFORMANCE                                              ║
    -- ╚════════════════════════════════════════════════════════════╝
    T.Perf:AddSection("Graphics Profile")
    T.Perf:AddDropdown("PerfProfile", {
        Text = "Performance Profile",
        Values  = {"UltraLow", "Balanced", "Quality"},
        Default = "UltraLow",
        Callback = function(v) Config.PerfMode = v; Perf.ApplyProfile(v) end,
    })

    T.Perf:AddSection("Effects")
    T.Perf:AddToggle("FxOff", {
        Text = "Disable Particles/Fire/Smoke", Default = true,
        Callback = function(v) Config.DisableEffects = v end,
    })
    T.Perf:AddToggle("SndOff", {
        Text = "Mute Distant Sounds", Default = false,
        Callback = function(v) Config.DisableSounds = v end,
    })

    T.Perf:AddSection("Rendering")
    T.Perf:AddToggle("DecalCull", {
        Text = "Distance Decal Culling", Default = true,
        Callback = function(v) Config.DecalCulling = v end,
    })
    T.Perf:AddSlider("CullDist", {
        Text = "Cull Distance (studs)", Min = 50, Max = 500, Default = 150, Rounding = 0,
        Callback = function(v) Config.DecalCullDistance = v end,
    })

    T.Perf:AddSection("Memory")
    T.Perf:AddToggle("AutoGC", {
        Text = "Auto Garbage Collection", Default = true,
        Callback = function(v) Config.AutoGC = v end,
    })
    T.Perf:AddSlider("GCInt", {
        Text = "GC Interval (seconds)", Min = 10, Max = 300, Default = 60, Rounding = 0,
        Callback = function(v) Config.GCInterval = v end,
    })

    -- ╔════════════════════════════════════════════════════════════╗
    -- ║  WEBHOOK                                                  ║
    -- ╚════════════════════════════════════════════════════════════╝
    T.Webhook:AddSection("Discord Integration")
    T.Webhook:AddInput("WebhookURL", {
        Text = "Webhook URL", Default = "", Placeholder = "https://discord.com/api/webhooks/...",
        Callback = function(v) Config.WebhookURL = v end,
    })

    T.Webhook:AddToggle("WH_Fruit", {
        Text = "🍎 Notify on Fruit Spawn", Default = true,
        Callback = function(v) Config.WebhookOnFruit = v end,
    })
    T.Webhook:AddToggle("WH_Level", {
        Text = "📈 Notify on Level Up", Default = true,
        Callback = function(v) Config.WebhookOnLevelUp = v end,
    })

    T.Webhook:AddSection("Test")
    T.Webhook:AddButton({Text = "📤 Send Test Webhook"}, function()
        Webhook.Send("session", {
            duration = Util.FormatTime(os.clock() - PHANTOM.StartTime),
            kills    = Farm.Stats.Kills,
            levels   = Farm.Stats.LevelUps,
        })
        Library:Notify({Title="Webhook", Description="Test webhook sent!", Duration=3})
    end)

    -- ╔════════════════════════════════════════════════════════════╗
    -- ║  SETTINGS                                                 ║
    -- ╚════════════════════════════════════════════════════════════╝
    T.Settings:AddSection("General")
    T.Settings:AddToggle("AutoRejoin", {
        Text = "🔄 Auto Rejoin on Kick", Default = true,
        Callback = function(v) Config.AutoRejoin = v end,
    })

    T.Settings:AddSection("Script Control")
    T.Settings:AddButton({Text = "🔴 Destroy PHANTOM"}, function()
        PHANTOM.State.Running = false
        for _, conn in ipairs(PHANTOM.Connections) do pcall(function() conn:Disconnect() end) end
        pcall(function() Library:Unload() end)
        getgenv().PHANTOM_LOADED = false
        warn("[PHANTOM] Destroyed. Goodbye!")
    end)

    T.Settings:AddButton({Text = "📊 Print Session Stats"}, function()
        local e = os.clock() - (Farm.Stats.StartTime > 0 and Farm.Stats.StartTime or os.clock())
        warn("══════ PHANTOM SESSION ══════")
        warn("Duration : " .. Util.FormatTime(e))
        warn("Kills    : " .. Util.FormatNumber(Farm.Stats.Kills))
        warn("Levels   : +" .. Farm.Stats.LevelUps)
        warn("FPS      : " .. Perf.CurrentFPS)
        warn("State    : " .. PHANTOM.State.FarmState)
        warn("═════════════════════════════")
    end)

    -- ── Startup notification ─────────────────────────────────────
    task.wait(1)
    Library:Notify({
        Title       = "PHANTOM v" .. PHANTOM.Version,
        Description = "Loaded successfully!\n" ..
                      Player.Name .. " | Sea " .. PHANTOM.State.CurrentSea .. " | Lv." .. Util.GetLevel() .. "\n" ..
                      ExecutorName .. " | " .. capCount .. " capabilities\n" ..
                      "Toggle GUI with the button at bottom-left.",
        Duration    = 6,
    })
end

-- ================================================================
-- [17] BOOT SEQUENCE
-- ================================================================

function PHANTOM.Boot()
    warn("╔══════════════════════════════════════╗")
    warn("║    PROJECT PHANTOM v" .. PHANTOM.Version .. " BOOTING    ║")
    warn("╚══════════════════════════════════════╝")

    -- Phase 1: Security (highest priority — must be first)
    warn("[PHANTOM] Initializing security engine...")
    Security.Init()

    -- Phase 2: Performance optimization
    warn("[PHANTOM] Applying performance profile...")
    Perf.Init()

    -- Phase 3: Combat system
    warn("[PHANTOM] Loading combat engine...")
    Combat.Init()
    Combat.StartLoop()

    -- Phase 4: Fruit sniper (background)
    warn("[PHANTOM] Starting fruit sniper (background)...")
    Fruit.StartSniper()

    -- Phase 5: Auto-rejoin handler
    if Config.AutoRejoin then
        pcall(function()
            game:GetService("CoreGui").RobloxPromptGui.promptOverlay.ChildAdded:Connect(function(child)
                task.wait(1)
                if child.Name == "ErrorPrompt" and child:FindFirstChild("MessageArea") then
                    pcall(function()
                        TeleportService:Teleport(PlaceId, Player)
                    end)
                end
            end)
        end)
    end

    -- Phase 6: Character respawn handler (re-init combat on respawn)
    Player.CharacterAdded:Connect(function()
        task.wait(2)
        pcall(function()
            Combat._attackMelee = nil
            Combat._uvCache     = nil
            Combat.FindAttackMelee()
        end)
    end)

    -- Phase 7: UI (last — all systems must be ready)
    warn("[PHANTOM] Building UI...")
    PHANTOM.BuildUI()

    -- Done!
    warn("╔══════════════════════════════════════╗")
    warn("║    PHANTOM v" .. PHANTOM.Version .. " — ONLINE         ║")
    warn("║    Sea " .. PHANTOM.State.CurrentSea .. " | Lv." .. Util.GetLevel() .. " | " .. ExecutorName)
    warn("║    " .. capCount .. " capabilities active          ║")
    warn("╚══════════════════════════════════════╝")
end

-- ================================================================
-- 🚀 LAUNCH
-- ================================================================
PHANTOM.Boot()
