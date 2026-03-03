-- ==== UFO HUB X • One-shot Boot Guard (PER SESSION; no cooldown reopen) ====
-- วางบนสุดของไฟล์ก่อนโค้ดทั้งหมด
do
    local BOOT = getgenv().UFO_BOOT or { status = "idle" }  -- status: idle|running|done
    -- ถ้ากำลังบูต หรือเคยบูตเสร็จแล้ว → ไม่ให้รันอีก
    if BOOT.status == "running" or BOOT.status == "done" then
        return
    end
    BOOT.status = "running"
    getgenv().UFO_BOOT = BOOT
end
-- ===== UFO HUB X • Local Save (executor filesystem) — per map (PlaceId) =====
do
    local HttpService = game:GetService("HttpService")
    local MarketplaceService = game:GetService("MarketplaceService")

    local FS = {
        isfolder   = (typeof(isfolder)=="function") and isfolder   or function() return false end,
        makefolder = (typeof(makefolder)=="function") and makefolder or function() end,
        isfile     = (typeof(isfile)=="function") and isfile       or function() return false end,
        readfile   = (typeof(readfile)=="function") and readfile   or function() return nil end,
        writefile  = (typeof(writefile)=="function") and writefile or function() end,
    }

    local ROOT = "UFO HUB X"  -- โฟลเดอร์หลักในตัวรัน
    local function safeMakeRoot() pcall(function() if not FS.isfolder(ROOT) then FS.makefolder(ROOT) end end) end
    safeMakeRoot()

    local placeId  = tostring(game.PlaceId)
    local gameId   = tostring(game.GameId)
    local mapName  = "Unknown"
    pcall(function()
        local inf = MarketplaceService:GetProductInfo(game.PlaceId)
        if inf and inf.Name then mapName = inf.Name end
    end)

    local FILE = string.format("%s/%s.json", ROOT, placeId)
    local _cache = nil
    local _dirty = false
    local _debounce = false

    local function _load()
        if _cache then return _cache end
        local ok, txt = pcall(function()
            if FS.isfile(FILE) then return FS.readfile(FILE) end
            return nil
        end)
        local data = nil
        if ok and txt and #txt > 0 then
            local ok2, t = pcall(function() return HttpService:JSONDecode(txt) end)
            data = ok2 and t or nil
        end
        if not data or type(data)~="table" then
            data = { __meta = { placeId = placeId, gameId = gameId, mapName = mapName, savedAt = os.time() } }
        end
        _cache = data
        return _cache
    end

    local function _flushNow()
        if not _cache then return end
        _cache.__meta = _cache.__meta or {}
        _cache.__meta.placeId = placeId
        _cache.__meta.gameId  = gameId
        _cache.__meta.mapName = mapName
        _cache.__meta.savedAt = os.time()
        local ok, json = pcall(function() return HttpService:JSONEncode(_cache) end)
        if ok and json then
            pcall(function()
                safeMakeRoot()
                FS.writefile(FILE, json)
            end)
        end
        _dirty = false
    end

    local function _scheduleFlush()
        if _debounce then return end
        _debounce = true
        task.delay(0.25, function()
            _debounce = false
            if _dirty then _flushNow() end
        end)
    end

    local Save = {}

    -- อ่านค่า: key = "Tab.Key" เช่น "RJ.enabled" / "A1.Reduce" / "AFK.Black"
    function Save.get(key, defaultValue)
        local db = _load()
        local v = db[key]
        if v == nil then return defaultValue end
        return v
    end

    -- เซ็ตค่า + เขียนไฟล์แบบดีบาวซ์
    function Save.set(key, value)
        local db = _load()
        db[key] = value
        _dirty = true
        _scheduleFlush()
    end

    -- ตัวช่วย: apply ค่าเซฟถ้ามี ไม่งั้นใช้ default แล้วเซฟกลับ
    function Save.apply(key, defaultValue, applyFn)
        local v = Save.get(key, defaultValue)
        if applyFn then
            local ok = pcall(applyFn, v)
            if ok and v ~= nil then Save.set(key, v) end
        end
        return v
    end

    -- ให้เรียกใช้ที่อื่นได้
    getgenv().UFOX_SAVE = Save
end
-- ===== [/Local Save] =====
--[[
UFO HUB X • One-shot = Toast(2-step) + Main UI (100%)
- Step1: Toast โหลด + แถบเปอร์เซ็นต์
- Step2: Toast "ดาวน์โหลดเสร็จ" โผล่ "พร้อมกับ" UI หลัก แล้วเลือนหายเอง
]]

------------------------------------------------------------
-- 1) ห่อ "UI หลักของคุณ (เดิม 100%)" ไว้ในฟังก์ชัน _G.UFO_ShowMainUI()
------------------------------------------------------------
_G.UFO_ShowMainUI = function()

--[[
UFO HUB X • Main UI + Safe Toggle (one-shot paste)
- ไม่ลบปุ่ม Toggle อีกต่อไป (ลบเฉพาะ UI หลัก)
- Toggle อยู่ของตัวเอง, มีขอบเขียว, ลากได้, บล็อกกล้องตอนลาก
- ซิงก์สถานะกับ UI หลักอัตโนมัติ และรีบอินด์ทุกครั้งที่ UI ถูกสร้างใหม่
]]

local Players  = game:GetService("Players")
local CoreGui  = game:GetService("CoreGui")
local UIS      = game:GetService("UserInputService")
local CAS      = game:GetService("ContextActionService")
local TS       = game:GetService("TweenService")
local RunS     = game:GetService("RunService")

-- ===== Theme / Size =====
local THEME = {
    GREEN=Color3.fromRGB(0,255,140),
    MINT=Color3.fromRGB(120,255,220),
    BG_WIN=Color3.fromRGB(16,16,16),
    BG_HEAD=Color3.fromRGB(6,6,6),
    BG_PANEL=Color3.fromRGB(22,22,22),
    BG_INNER=Color3.fromRGB(18,18,18),
    TEXT=Color3.fromRGB(235,235,235),
    RED=Color3.fromRGB(200,40,40),
    HILITE=Color3.fromRGB(22,30,24),
}
local SIZE={WIN_W=640,WIN_H=360,RADIUS=12,BORDER=3,HEAD_H=46,GAP_OUT=14,GAP_IN=8,BETWEEN=12,LEFT_RATIO=0.22}
local IMG_UFO="rbxassetid://100650447103028"
local ICON_PLAYER = 116976545042904
local ICON_HOME   = 134323882016779
local ICON_QUEST   = 72473476254744
local ICON_SHOP     = 139824330037901
local ICON_UPDATE   = 134419329246667
local ICON_SERVER   = 77839913086023
local ICON_SETTINGS = 72289858646360
local TOGGLE_ICON = "rbxassetid://117052960049460"

local function corner(p,r) local u=Instance.new("UICorner",p) u.CornerRadius=UDim.new(0,r or 10) return u end
local function stroke(p,th,col,tr) local s=Instance.new("UIStroke",p) s.Thickness=th or 1 s.Color=col or THEME.MINT s.Transparency=tr or 0.35 s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border s.LineJoinMode=Enum.LineJoinMode.Round return s end

-- ===== Utilities: find main UI + sync =====
local function findMain()
    local root = CoreGui:FindFirstChild("UFO_HUB_X_UI")
    if not root then
        local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
        if pg then root = pg:FindFirstChild("UFO_HUB_X_UI") end
    end
    local win = root and (root:FindFirstChild("Win") or root:FindFirstChildWhichIsA("Frame")) or nil
    return root, win
end

local function setOpen(open)
    local gui, win = findMain()
    if gui then gui.Enabled = open end
    if win then win.Visible = open end
    getgenv().UFO_ISOPEN = not not open
end

-- ====== SAFE TOGGLE (สร้าง/รีใช้, ไม่โดนลบ) ======
local ToggleGui = CoreGui:FindFirstChild("UFO_HUB_X_Toggle") :: ScreenGui
if not ToggleGui then
    ToggleGui = Instance.new("ScreenGui")
    ToggleGui.Name = "UFO_HUB_X_Toggle"
    ToggleGui.IgnoreGuiInset = true
    ToggleGui.DisplayOrder = 100001
    ToggleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ToggleGui.ResetOnSpawn = false
    ToggleGui.Parent = CoreGui

    local Btn = Instance.new("ImageButton", ToggleGui)
    Btn.Name = "Button"
    Btn.Size = UDim2.fromOffset(64,64)
    Btn.Position = UDim2.fromOffset(90,220)
    Btn.Image = TOGGLE_ICON
    Btn.BackgroundColor3 = Color3.fromRGB(0,0,0)
    Btn.BorderSizePixel = 0
    corner(Btn,8); stroke(Btn,2,THEME.GREEN,0)

    -- drag + block camera
    local function block(on)
        local name="UFO_BlockLook_Toggle"
        if on then
            CAS:BindActionAtPriority(name,function() return Enum.ContextActionResult.Sink end,false,9000,
                Enum.UserInputType.MouseMovement,Enum.UserInputType.Touch,Enum.UserInputType.MouseButton1)
        else pcall(function() CAS:UnbindAction(name) end) end
    end
    local dragging=false; local start; local startPos
    Btn.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            dragging=true; start=i.Position; startPos=Vector2.new(Btn.Position.X.Offset, Btn.Position.Y.Offset); block(true)
            i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dragging=false; block(false) end end)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            local d=i.Position-start; Btn.Position=UDim2.fromOffset(startPos.X+d.X,startPos.Y+d.Y)
        end
    end)
end

-- (Re)bind toggle actions (กันผูกซ้ำ)
do
    local Btn = ToggleGui:FindFirstChild("Button")
    if getgenv().UFO_ToggleClick then pcall(function() getgenv().UFO_ToggleClick:Disconnect() end) end
    if getgenv().UFO_ToggleKey   then pcall(function() getgenv().UFO_ToggleKey:Disconnect() end) end
    getgenv().UFO_ToggleClick = Btn.MouseButton1Click:Connect(function() setOpen(not getgenv().UFO_ISOPEN) end)
    getgenv().UFO_ToggleKey   = UIS.InputBegan:Connect(function(i,gp) if gp then return end if i.KeyCode==Enum.KeyCode.RightShift then setOpen(not getgenv().UFO_ISOPEN) end end)
end

-- ====== ลบ "เฉพาะ" UI หลักเก่าก่อนสร้างใหม่ (ไม่ยุ่ง Toggle) ======
pcall(function() local old = CoreGui:FindFirstChild("UFO_HUB_X_UI"); if old then old:Destroy() end end)

-- ====== MAIN UI (เหมือนเดิม) ======
local GUI=Instance.new("ScreenGui")
GUI.Name="UFO_HUB_X_UI"
GUI.IgnoreGuiInset=true
GUI.ResetOnSpawn=false
GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
GUI.DisplayOrder = 100000
GUI.Parent = CoreGui

local Win=Instance.new("Frame",GUI) Win.Name="Win"
Win.Size=UDim2.fromOffset(SIZE.WIN_W,SIZE.WIN_H)
Win.AnchorPoint=Vector2.new(0.5,0.5); Win.Position=UDim2.new(0.5,0,0.5,0)
Win.BackgroundColor3=THEME.BG_WIN; Win.BorderSizePixel=0
corner(Win,SIZE.RADIUS); stroke(Win,3,THEME.GREEN,0)

do local sc=Instance.new("UIScale",Win)
   local function fit() local v=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
       sc.Scale=math.clamp(math.min(v.X/860,v.Y/540),0.72,1.0) end
   fit(); RunS.RenderStepped:Connect(fit)
end

local Header=Instance.new("Frame",Win)
Header.Size=UDim2.new(1,0,0,SIZE.HEAD_H)
Header.BackgroundColor3=THEME.BG_HEAD; Header.BorderSizePixel=0
corner(Header,SIZE.RADIUS)
local Accent=Instance.new("Frame",Header)
Accent.AnchorPoint=Vector2.new(0.5,1); Accent.Position=UDim2.new(0.5,0,1,0)
Accent.Size=UDim2.new(1,-20,0,1); Accent.BackgroundColor3=THEME.MINT; Accent.BackgroundTransparency=0.35
local Title=Instance.new("TextLabel",Header)
Title.BackgroundTransparency=1; Title.AnchorPoint=Vector2.new(0.5,0)
Title.Position=UDim2.new(0.5,0,0,6); Title.Size=UDim2.new(0.8,0,0,36)
Title.Font=Enum.Font.GothamBold; Title.TextScaled=true; Title.RichText=true
Title.Text='<font color="#FFFFFF">UFO</font> <font color="#00FF8C">HUB X</font>'
Title.TextColor3=THEME.TEXT

local BtnClose=Instance.new("TextButton",Header)
BtnClose.AutoButtonColor=false; BtnClose.Size=UDim2.fromOffset(24,24)
BtnClose.Position=UDim2.new(1,-34,0.5,-12); BtnClose.BackgroundColor3=THEME.RED
BtnClose.Text="X"; BtnClose.Font=Enum.Font.GothamBold; BtnClose.TextSize=13
BtnClose.TextColor3=Color3.new(1,1,1); BtnClose.BorderSizePixel=0
corner(BtnClose,6); stroke(BtnClose,1,Color3.fromRGB(255,0,0),0.1)
BtnClose.MouseButton1Click:Connect(function() setOpen(false) end)

-- UFO icon
local UFO=Instance.new("ImageLabel",Win)
UFO.BackgroundTransparency=1; UFO.Image=IMG_UFO
UFO.Size=UDim2.fromOffset(168,168); UFO.AnchorPoint=Vector2.new(0.5,1)
UFO.Position=UDim2.new(0.5,0,0,84); UFO.ZIndex=4

-- === DRAG MAIN ONLY (ลากได้เฉพาะ UI หลักที่ Header; บล็อกกล้องระหว่างลาก) ===
do
    local dragging = false
    local startInputPos: Vector2
    local startWinOffset: Vector2
    local blockDrag = false

    -- กันเผลอลากตอนกดปุ่ม X
    BtnClose.MouseButton1Down:Connect(function() blockDrag = true end)
    BtnClose.MouseButton1Up:Connect(function() blockDrag = false end)

    local function blockCamera(on: boolean)
        local name = "UFO_BlockLook_MainDrag"
        if on then
            CAS:BindActionAtPriority(name, function()
                return Enum.ContextActionResult.Sink
            end, false, 9000,
            Enum.UserInputType.MouseMovement,
            Enum.UserInputType.Touch,
            Enum.UserInputType.MouseButton1)
        else
            pcall(function() CAS:UnbindAction(name) end)
        end
    end

    Header.InputBegan:Connect(function(input)
        if blockDrag then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            startInputPos  = input.Position
            startWinOffset = Vector2.new(Win.Position.X.Offset, Win.Position.Y.Offset)
            blockCamera(true)
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    blockCamera(false)
                end
            end)
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = input.Position - startInputPos
        Win.Position = UDim2.new(0.5, startWinOffset.X + delta.X, 0.5, startWinOffset.Y + delta.Y)
    end)
end
-- === END DRAG MAIN ONLY ===

-- BODY
local Body=Instance.new("Frame",Win)
Body.BackgroundColor3=THEME.BG_INNER; Body.BorderSizePixel=0
Body.Position=UDim2.new(0,SIZE.GAP_OUT,0,SIZE.HEAD_H+SIZE.GAP_OUT)
Body.Size=UDim2.new(1,-SIZE.GAP_OUT*2,1,-(SIZE.HEAD_H+SIZE.GAP_OUT*2))
corner(Body,12); stroke(Body,0.5,THEME.MINT,0.35)

-- === LEFT (แทนที่บล็อกก่อนหน้าได้เลย) ================================
local LeftShell = Instance.new("Frame", Body)
LeftShell.BackgroundColor3 = THEME.BG_PANEL
LeftShell.BorderSizePixel  = 0
LeftShell.Position         = UDim2.new(0, SIZE.GAP_IN, 0, SIZE.GAP_IN)
LeftShell.Size             = UDim2.new(SIZE.LEFT_RATIO, -(SIZE.BETWEEN/2), 1, -SIZE.GAP_IN*2)
LeftShell.ClipsDescendants = true
corner(LeftShell, 10)
stroke(LeftShell, 1.2, THEME.GREEN, 0)
stroke(LeftShell, 0.45, THEME.MINT, 0.35)

local LeftScroll = Instance.new("ScrollingFrame", LeftShell)
LeftScroll.BackgroundTransparency = 1
LeftScroll.Size                   = UDim2.fromScale(1,1)
LeftScroll.ScrollBarThickness     = 0
LeftScroll.ScrollingDirection     = Enum.ScrollingDirection.Y
LeftScroll.AutomaticCanvasSize    = Enum.AutomaticSize.None
LeftScroll.ElasticBehavior        = Enum.ElasticBehavior.Never
LeftScroll.ScrollingEnabled       = true
LeftScroll.ClipsDescendants       = true

local padL = Instance.new("UIPadding", LeftScroll)
padL.PaddingTop    = UDim.new(0, 8)
padL.PaddingLeft   = UDim.new(0, 8)
padL.PaddingRight  = UDim.new(0, 8)
padL.PaddingBottom = UDim.new(0, 8)

local LeftList = Instance.new("UIListLayout", LeftScroll)
LeftList.Padding   = UDim.new(0, 8)
LeftList.SortOrder = Enum.SortOrder.LayoutOrder

-- ===== คุม Canvas + กันเด้งกลับตอนคลิกแท็บ =====
local function refreshLeftCanvas()
    local contentH = LeftList.AbsoluteContentSize.Y + padL.PaddingTop.Offset + padL.PaddingBottom.Offset
    LeftScroll.CanvasSize = UDim2.new(0, 0, 0, contentH)
end

local function clampTo(yTarget)
    local contentH = LeftList.AbsoluteContentSize.Y + padL.PaddingTop.Offset + padL.PaddingBottom.Offset
    local viewH    = LeftScroll.AbsoluteSize.Y
    local maxY     = math.max(0, contentH - viewH)
    LeftScroll.CanvasPosition = Vector2.new(0, math.clamp(yTarget or 0, 0, maxY))
end

-- ✨ จำตำแหน่งล่าสุดไว้ใช้ “ทุกครั้ง” ที่มีการจัดเลย์เอาต์ใหม่
local lastY = 0

LeftList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    refreshLeftCanvas()
    clampTo(lastY) -- ใช้ค่าเดิมที่จำไว้ ไม่อ่านจาก CanvasPosition ที่อาจโดนรีเซ็ต
end)

task.defer(refreshLeftCanvas)

-- name/icon = ชื่อ/ไอคอนฝั่งขวา, setFns = ฟังก์ชันเซ็ต active, btn = ปุ่มที่ถูกกด
local function onTabClick(name, icon, setFns, btn)
    -- บันทึกตำแหน่งปัจจุบัน “ไว้ก่อน” ที่เลย์เอาต์จะขยับ
    lastY = LeftScroll.CanvasPosition.Y

    setFns()
    showRight(name, icon)

    task.defer(function()
        refreshLeftCanvas()
        clampTo(lastY) -- คืนตำแหน่งเดิมเสมอ

        -- ถ้าปุ่มอยู่นอกจอ ค่อยเลื่อนเข้าเฟรมอย่างพอดี (จะปรับ lastY ด้วย)
        if btn and btn.Parent then
            local viewH   = LeftScroll.AbsoluteSize.Y
            local btnTop  = btn.AbsolutePosition.Y - LeftScroll.AbsolutePosition.Y
            local btnBot  = btnTop + btn.AbsoluteSize.Y
            local pad     = 8
            local y = LeftScroll.CanvasPosition.Y
            if btnTop < 0 then
                y = y + (btnTop - pad)
            elseif btnBot > viewH then
                y = y + (btnBot - viewH) + pad
            end
            lastY = y
            clampTo(lastY)
        end
    end)
end

-- === ผูกคลิกแท็บทั้ง 7 (เหมือนเดิม) ================================
task.defer(function()
    repeat task.wait() until
        btnPlayer and btnHome and btnQuest and btnShop and btnUpdate and btnServer and btnSettings

    btnPlayer.MouseButton1Click:Connect(function()
        onTabClick("Player", ICON_PLAYER, function()
            setPlayerActive(true); setHomeActive(false); setQuestActive(false)
            setShopActive(false); setUpdateActive(false); setServerActive(false); setSettingsActive(false)
        end, btnPlayer)
    end)

    btnHome.MouseButton1Click:Connect(function()
        onTabClick("Home", ICON_HOME, function()
            setPlayerActive(false); setHomeActive(true); setQuestActive(false)
            setShopActive(false); setUpdateActive(false); setServerActive(false); setSettingsActive(false)
        end, btnHome)
    end)

    btnQuest.MouseButton1Click:Connect(function()
        onTabClick("Quest", ICON_QUEST, function()
            setPlayerActive(false); setHomeActive(false); setQuestActive(true)
            setShopActive(false); setUpdateActive(false); setServerActive(false); setSettingsActive(false)
        end, btnQuest)
    end)

    btnShop.MouseButton1Click:Connect(function()
        onTabClick("Shop", ICON_SHOP, function()
            setPlayerActive(false); setHomeActive(false); setQuestActive(false)
            setShopActive(true); setUpdateActive(false); setServerActive(false); setSettingsActive(false)
        end, btnShop)
    end)

    btnUpdate.MouseButton1Click:Connect(function()
        onTabClick("Update", ICON_UPDATE, function()
            setPlayerActive(false); setHomeActive(false); setQuestActive(false)
            setShopActive(false); setUpdateActive(true); setServerActive(false); setSettingsActive(false)
        end, btnUpdate)
    end)

    btnServer.MouseButton1Click:Connect(function()
        onTabClick("Server", ICON_SERVER, function()
            setPlayerActive(false); setHomeActive(false); setQuestActive(false)
            setShopActive(false); setUpdateActive(false); setServerActive(true); setSettingsActive(false)
        end, btnServer)
    end)

    btnSettings.MouseButton1Click:Connect(function()
        onTabClick("Settings", ICON_SETTINGS, function()
            setPlayerActive(false); setHomeActive(false); setQuestActive(false)
            setShopActive(false); setUpdateActive(false); setServerActive(false); setSettingsActive(true)
        end, btnSettings)
    end)
end)
-- ===================================================================

----------------------------------------------------------------
-- LEFT (ปุ่มแท็บ) + RIGHT (คอนเทนต์) — เวอร์ชันครบ + แก้บัคสกอร์ลแยกแท็บ
----------------------------------------------------------------

-- ========== LEFT ==========
local LeftShell=Instance.new("Frame",Body)
LeftShell.BackgroundColor3=THEME.BG_PANEL; LeftShell.BorderSizePixel=0
LeftShell.Position=UDim2.new(0,SIZE.GAP_IN,0,SIZE.GAP_IN)
LeftShell.Size=UDim2.new(SIZE.LEFT_RATIO,-(SIZE.BETWEEN/2),1,-SIZE.GAP_IN*2)
LeftShell.ClipsDescendants=true
corner(LeftShell,10); stroke(LeftShell,1.2,THEME.GREEN,0); stroke(LeftShell,0.45,THEME.MINT,0.35)

local LeftScroll=Instance.new("ScrollingFrame",LeftShell)
LeftScroll.BackgroundTransparency=1
LeftScroll.Size=UDim2.fromScale(1,1)
LeftScroll.ScrollBarThickness=0
LeftScroll.ScrollingDirection=Enum.ScrollingDirection.Y
LeftScroll.AutomaticCanvasSize=Enum.AutomaticSize.None
LeftScroll.ElasticBehavior=Enum.ElasticBehavior.Never
LeftScroll.ScrollingEnabled=true
LeftScroll.ClipsDescendants=true

local padL=Instance.new("UIPadding",LeftScroll)
padL.PaddingTop=UDim.new(0,8); padL.PaddingLeft=UDim.new(0,8); padL.PaddingRight=UDim.new(0,8); padL.PaddingBottom=UDim.new(0,8)
local LeftList=Instance.new("UIListLayout",LeftScroll); LeftList.Padding=UDim.new(0,8); LeftList.SortOrder=Enum.SortOrder.LayoutOrder

local function refreshLeftCanvas()
    local contentH = LeftList.AbsoluteContentSize.Y + padL.PaddingTop.Offset + padL.PaddingBottom.Offset
    LeftScroll.CanvasSize = UDim2.new(0,0,0,contentH)
end
local lastLeftY = 0
LeftList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    refreshLeftCanvas()
    local viewH = LeftScroll.AbsoluteSize.Y
    local maxY  = math.max(0, LeftScroll.CanvasSize.Y.Offset - viewH)
    LeftScroll.CanvasPosition = Vector2.new(0, math.clamp(lastLeftY,0,maxY))
end)
task.defer(refreshLeftCanvas)

-- สร้างปุ่มแท็บ
local function makeTabButton(parent, label, iconId)
    local holder = Instance.new("Frame", parent) holder.BackgroundTransparency=1 holder.Size = UDim2.new(1,0,0,38)
    local b = Instance.new("TextButton", holder) b.AutoButtonColor=false b.Text="" b.Size=UDim2.new(1,0,1,0) b.BackgroundColor3=THEME.BG_INNER corner(b,8)
    local st = stroke(b,1,THEME.MINT,0.35)
    local ic = Instance.new("ImageLabel", b) ic.BackgroundTransparency=1 ic.Image="rbxassetid://"..tostring(iconId) ic.Size=UDim2.fromOffset(22,22) ic.Position=UDim2.new(0,10,0.5,-11)
    local tx = Instance.new("TextLabel", b) tx.BackgroundTransparency=1 tx.TextColor3=THEME.TEXT tx.Font=Enum.Font.GothamMedium tx.TextSize=15 tx.TextXAlignment=Enum.TextXAlignment.Left tx.Position=UDim2.new(0,38,0,0) tx.Size=UDim2.new(1,-46,1,0) tx.Text = label
    local flash=Instance.new("Frame",b) flash.BackgroundColor3=THEME.GREEN flash.BackgroundTransparency=1 flash.BorderSizePixel=0 flash.AnchorPoint=Vector2.new(0.5,0.5) flash.Position=UDim2.new(0.5,0,0.5,0) flash.Size=UDim2.new(0,0,0,0) corner(flash,12)
    b.MouseButton1Down:Connect(function() TS:Create(b, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(1,0,1,-2)}):Play() end)
    b.MouseButton1Up:Connect(function() TS:Create(b, TweenInfo.new(0.10, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(1,0,1,0)}):Play() end)
    local function setActive(on)
        if on then
            b.BackgroundColor3=THEME.HILITE; st.Color=THEME.GREEN; st.Transparency=0; st.Thickness=2
            flash.BackgroundTransparency=0.35; flash.Size=UDim2.new(0,0,0,0)
            TS:Create(flash, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size=UDim2.new(1,0,1,0), BackgroundTransparency=1}):Play()
        else
            b.BackgroundColor3=THEME.BG_INNER; st.Color=THEME.MINT; st.Transparency=0.35; st.Thickness=1
        end
    end
    return b, setActive
end

local btnPlayer,  setPlayerActive   = makeTabButton(LeftScroll, "Player",  ICON_PLAYER)
local btnHome,    setHomeActive     = makeTabButton(LeftScroll, "Home",    ICON_HOME)
local btnQuest,   setQuestActive    = makeTabButton(LeftScroll, "Quest",   ICON_QUEST)
local btnShop,    setShopActive     = makeTabButton(LeftScroll, "Shop",    ICON_SHOP)
local btnUpdate,  setUpdateActive   = makeTabButton(LeftScroll, "Update",  ICON_UPDATE)
local btnServer,  setServerActive   = makeTabButton(LeftScroll, "Server",  ICON_SERVER)
local btnSettings,setSettingsActive = makeTabButton(LeftScroll, "Settings",ICON_SETTINGS)

-- ========== RIGHT ==========
local RightShell=Instance.new("Frame",Body)
RightShell.BackgroundColor3=THEME.BG_PANEL; RightShell.BorderSizePixel=0
RightShell.Position=UDim2.new(SIZE.LEFT_RATIO,SIZE.BETWEEN,0,SIZE.GAP_IN)
RightShell.Size=UDim2.new(1-SIZE.LEFT_RATIO,-SIZE.GAP_IN-SIZE.BETWEEN,1,-SIZE.GAP_IN*2)
corner(RightShell,10); stroke(RightShell,1.2,THEME.GREEN,0); stroke(RightShell,0.45,THEME.MINT,0.35)

local RightScroll=Instance.new("ScrollingFrame",RightShell)
RightScroll.BackgroundTransparency=1; RightScroll.Size=UDim2.fromScale(1,1)
RightScroll.ScrollBarThickness=0; RightScroll.ScrollingDirection=Enum.ScrollingDirection.Y
RightScroll.AutomaticCanvasSize=Enum.AutomaticSize.None   -- คุมเองเพื่อกันเด้ง/จำ Y ได้
RightScroll.ElasticBehavior=Enum.ElasticBehavior.Never

local padR=Instance.new("UIPadding",RightScroll)
padR.PaddingTop=UDim.new(0,12); padR.PaddingLeft=UDim.new(0,12); padR.PaddingRight=UDim.new(0,12); padR.PaddingBottom=UDim.new(0,12)
local RightList=Instance.new("UIListLayout",RightScroll); RightList.Padding=UDim.new(0,10); RightList.SortOrder = Enum.SortOrder.LayoutOrder

local function refreshRightCanvas()
    local contentH = RightList.AbsoluteContentSize.Y + padR.PaddingTop.Offset + padR.PaddingBottom.Offset
    RightScroll.CanvasSize = UDim2.new(0,0,0,contentH)
end
RightList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    local yBefore = RightScroll.CanvasPosition.Y
    refreshRightCanvas()
    local viewH = RightScroll.AbsoluteSize.Y
    local maxY  = math.max(0, RightScroll.CanvasSize.Y.Offset - viewH)
    RightScroll.CanvasPosition = Vector2.new(0, math.clamp(yBefore,0,maxY))
end)
-- ================= RIGHT: Modular per-tab (drop-in) =================
-- ใส่หลังจากสร้าง RightShell เสร็จ (และก่อนผูกปุ่มกด)

-- 1) เก็บ/ใช้ state กลาง
if not getgenv().UFO_RIGHT then getgenv().UFO_RIGHT = {} end
local RSTATE = getgenv().UFO_RIGHT
RSTATE.frames   = RSTATE.frames   or {}
RSTATE.builders = RSTATE.builders or {}
RSTATE.scrollY  = RSTATE.scrollY  or {}
RSTATE.current  = RSTATE.current

-- 2) ถ้ามี RightScroll เก่าอยู่ ให้ลบทิ้ง
pcall(function()
    local old = RightShell:FindFirstChildWhichIsA("ScrollingFrame")
    if old then old:Destroy() end
end)

-- 3) สร้าง ScrollingFrame ต่อแท็บ
local function makeTabFrame(tabName)
    local root = Instance.new("Frame")
    root.Name = "RightTab_"..tabName
    root.BackgroundTransparency = 1
    root.Size = UDim2.fromScale(1,1)
    root.Visible = false
    root.Parent = RightShell

    local sf = Instance.new("ScrollingFrame", root)
    sf.Name = "Scroll"
    sf.BackgroundTransparency = 1
    sf.Size = UDim2.fromScale(1,1)
    sf.ScrollBarThickness = 0      -- ← ซ่อนสกรอลล์บาร์ (เดิม 4)
    sf.ScrollingDirection = Enum.ScrollingDirection.Y
    sf.AutomaticCanvasSize = Enum.AutomaticSize.None
    sf.ElasticBehavior = Enum.ElasticBehavior.Never
    sf.CanvasSize = UDim2.new(0,0,0,600)  -- เลื่อนได้ตั้งแต่เริ่ม

    local pad = Instance.new("UIPadding", sf)
    pad.PaddingTop    = UDim.new(0,12)
    pad.PaddingLeft   = UDim.new(0,12)
    pad.PaddingRight  = UDim.new(0,12)
    pad.PaddingBottom = UDim.new(0,12)

    local list = Instance.new("UIListLayout", sf)
    list.Padding = UDim.new(0,10)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.VerticalAlignment = Enum.VerticalAlignment.Top

    local function refreshCanvas()
        local h = list.AbsoluteContentSize.Y + pad.PaddingTop.Offset + pad.PaddingBottom.Offset
        sf.CanvasSize = UDim2.new(0,0,0, math.max(h,600))
    end

    list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        local yBefore = sf.CanvasPosition.Y
        refreshCanvas()
        local viewH = sf.AbsoluteSize.Y
        local maxY  = math.max(0, sf.CanvasSize.Y.Offset - viewH)
        sf.CanvasPosition = Vector2.new(0, math.clamp(yBefore, 0, maxY))
    end)

    task.defer(refreshCanvas)

    RSTATE.frames[tabName] = {root=root, scroll=sf, list=list, built=false}
    return RSTATE.frames[tabName]
end

-- 4) ลงทะเบียนฟังก์ชันสร้างคอนเทนต์ต่อแท็บ (รองรับหลายตัว)
local function registerRight(tabName, builderFn)
    RSTATE.builders[tabName] = RSTATE.builders[tabName] or {}
    table.insert(RSTATE.builders[tabName], builderFn)
end

-- 5) หัวเรื่อง
local function addHeader(parentScroll, titleText, iconId)
    local row = Instance.new("Frame")
    row.BackgroundTransparency = 1
    row.Size = UDim2.new(1,0,0,28)
    row.Parent = parentScroll

    local icon = Instance.new("ImageLabel", row)
    icon.BackgroundTransparency = 1
    icon.Image = "rbxassetid://"..tostring(iconId or "")
    icon.Size = UDim2.fromOffset(20,20)
    icon.Position = UDim2.new(0,0,0.5,-10)

    local head = Instance.new("TextLabel", row)
    head.BackgroundTransparency = 1
    head.Font = Enum.Font.GothamBold
    head.TextSize = 18
    head.TextXAlignment = Enum.TextXAlignment.Left
    head.TextColor3 = THEME.TEXT
    head.Position = UDim2.new(0,26,0,0)
    head.Size = UDim2.new(1,-26,1,0)
    head.Text = titleText
end

-- 6) API หลัก
function showRight(titleText, iconId)
    local tab = titleText

    if RSTATE.current and RSTATE.frames[RSTATE.current] then
        RSTATE.scrollY[RSTATE.current] = RSTATE.frames[RSTATE.current].scroll.CanvasPosition.Y
        RSTATE.frames[RSTATE.current].root.Visible = false
    end

    local f = RSTATE.frames[tab] or makeTabFrame(tab)
    f.root.Visible = true

    if not f.built then
        addHeader(f.scroll, titleText, iconId)
        -- เรียกทุก builder ของแท็บนี้ (เรียงตามที่ register เข้ามา)
        local list = RSTATE.builders[tab] or {}
        for _, builder in ipairs(list) do
            pcall(builder, f.scroll)
        end
        f.built = true
    end

    task.defer(function()
        local y = RSTATE.scrollY[tab] or 0
        local viewH = f.scroll.AbsoluteSize.Y
        local maxY  = math.max(0, f.scroll.CanvasSize.Y.Offset - viewH)
        f.scroll.CanvasPosition = Vector2.new(0, math.clamp(y, 0, maxY))
    end)

    RSTATE.current = tab
end
    
-- 7) ตัวอย่างแท็บ (ลบเดโมรายการออกแล้ว)
registerRight("Player", function(scroll)
    -- วาง UI ของ Player ที่นี่ (ตอนนี้ปล่อยว่าง ไม่มี Item#)
end)

registerRight("Home", function(scroll) end)
registerRight("Quest", function(scroll) end)
registerRight("Shop", function(scroll) end)
registerRight("Update", function(scroll) end)
registerRight("Server", function(scroll) end)
registerRight("Settings", function(scroll) end)



--===== UFO HUB X • Player — Warp to Player (Model A V1 + Row1 = A V2 เต็มระบบ + Water Clamp) =====
-- ใช้ในแท็บ Player ฝั่งขวา

registerRight("Player", function(scroll)
    local Players          = game:GetService("Players")
    local TweenService     = game:GetService("TweenService")
    local RunService       = game:GetService("RunService")
    local CoreGui          = game:GetService("CoreGui")
    local UserInputService = game:GetService("UserInputService")
    local Workspace        = game:GetService("Workspace")
    local lp               = Players.LocalPlayer

    ------------------------------------------------------------------------
    -- THEME + HELPERS
    ------------------------------------------------------------------------
    local THEME = {
        GREEN      = Color3.fromRGB(25,255,125),
        GREEN_DARK = Color3.fromRGB(0,120,60),
        RED        = Color3.fromRGB(255,40,40),
        WHITE      = Color3.fromRGB(255,255,255),
        BLACK      = Color3.fromRGB(0,0,0),
        TEXT       = Color3.fromRGB(255,255,255),
        DARK       = Color3.fromRGB(10,10,10),
    }

    local function corner(ui,r)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0,r or 12)
        c.Parent = ui
    end

    local function stroke(ui,th,col)
        local s = Instance.new("UIStroke")
        s.Thickness = th or 2.2
        s.Color = col or THEME.GREEN
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Parent = ui
        return s
    end

    local function tween(o,p,d)
        TweenService:Create(
            o,
            TweenInfo.new(d or 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            p
        ):Play()
    end

    ------------------------------------------------------------------------
    -- WATER DETECT (กันไม่ให้ต่ำกว่าผิวน้ำ)
    ------------------------------------------------------------------------
    local RAY_PARAMS = RaycastParams.new()
    RAY_PARAMS.FilterType = Enum.RaycastFilterType.Blacklist
    RAY_PARAMS.FilterDescendantsInstances = {}

    local function updateRaycastIgnore()
        local ignore = {}
        if lp.Character then
            table.insert(ignore, lp.Character)
        end
        RAY_PARAMS.FilterDescendantsInstances = ignore
    end

    local function isWaterHit(result)
        if not result then return false end
        if result.Material == Enum.Material.Water then
            return true
        end
        local inst = result.Instance
        if not inst then return false end
        local n = string.lower(inst.Name or "")
        if n:find("water") or n:find("sea") or n:find("ocean") then
            return true
        end
        return false
    end

    local function getWaterLevelAt(pos)
        -- ยิง ray ลงด้านล่าง หาน้ำทุกแบบ (Terrain Water + Part ที่ชื่อมี water/sea/ocean)
        local origin = pos + Vector3.new(0, 500, 0)
        local dir    = Vector3.new(0, -1000, 0)
        local result = Workspace:Raycast(origin, dir, RAY_PARAMS)
        if result and isWaterHit(result) then
            return result.Position.Y
        end
        return nil
    end

    ------------------------------------------------------------------------
    -- GLOBAL STATE
    ------------------------------------------------------------------------
    _G.UFOX_WARP = _G.UFOX_WARP or {
        targetUserId = nil,
        mode         = "none", -- "none" | "warp" | "fly"
        flyConn      = nil,
        noClip       = false,
    }
    local WARP = _G.UFOX_WARP

    if WARP.mode ~= "warp" and WARP.mode ~= "fly" then
        WARP.mode = "warp"
    end

    local function getTargetPlayer()
        if not WARP.targetUserId then return nil end
        for _,pl in ipairs(Players:GetPlayers()) do
            if pl.UserId == WARP.targetUserId then
                return pl
            end
        end
        return nil
    end

    ------------------------------------------------------------------------
    -- ACTIONS
    ------------------------------------------------------------------------
    local function setNoClip(enable)
        WARP.noClip = enable
        local ch = lp.Character
        if not ch then return end
        for _,part in ipairs(ch:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = not enable
            end
        end
    end

    local function enforceNoClip()
        if not WARP.noClip then return end
        local ch = lp.Character
        if not ch then return end
        for _,part in ipairs(ch:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end

    local function stopFly()
        if WARP.flyConn then
            pcall(function() WARP.flyConn:Disconnect() end)
            WARP.flyConn = nil
        end
        setNoClip(false)

        local ch  = lp.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function()
                hum.PlatformStand = false
                hum:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
            end)
        end
    end

    local function getHumanoidRoot(player)
        player = player or lp
        if not player then return nil end
        local ch = player.Character
        if not ch then return nil end
        return ch:FindFirstChild("HumanoidRootPart")
    end

    local function doInstantWarp()
        -- ปิดโหมดบินก่อน แล้วเทเลพอร์ตจบ
        stopFly()

        local targetPl = getTargetPlayer()
        local hrpSelf  = getHumanoidRoot(lp)
        local hrpTarget= getHumanoidRoot(targetPl)
        if not hrpSelf or not hrpTarget then return end

        local targetPos = hrpTarget.Position + Vector3.new(0,3,0)
        pcall(function()
            hrpSelf.CFrame = CFrame.new(targetPos, targetPos + hrpTarget.CFrame.LookVector)
            hrpSelf.AssemblyLinearVelocity  = Vector3.new(0,0,0)
            hrpSelf.AssemblyAngularVelocity = Vector3.new(0,0,0)
        end)
    end

    ------------------------------------------------------------------------
    -- FLY TO PLAYER + กันจม / จอดด้วย Instant Warp
    ------------------------------------------------------------------------
    local function doFlyWarp()
        stopFly()

        local targetPl = getTargetPlayer()
        local hrpSelf  = getHumanoidRoot(lp)
        local hrpTarget= getHumanoidRoot(targetPl)
        if not hrpSelf or not hrpTarget then return end

        local SPEED        = 350      -- ความเร็วบิน “กลาง ๆ”
        local lift         = 14       -- ยกตัวจากพื้นก่อนเริ่ม
        local heightOffset = 4        -- ลอยเหนือหัวเป้าหมาย
        local stopDist     = 4        -- เข้าใกล้ระยะนี้แล้วสั่ง Instant Warp ปิดจบ
        local WATER_MARGIN = 3        -- ลอยเหนือระดับน้ำอย่างน้อยกี่ stud

        updateRaycastIgnore()

        -- ยกตัวขึ้นจากพื้นแบบนิ่ง ๆ
        pcall(function()
            hrpSelf.CFrame = hrpSelf.CFrame + Vector3.new(0, lift, 0)
            hrpSelf.AssemblyLinearVelocity  = Vector3.new(0,0,0)
            hrpSelf.AssemblyAngularVelocity = Vector3.new(0,0,0)
        end)

        -- ปิดระบบฟิสิกส์เดิน ให้ตัวละครอยู่นิ่งในอากาศ
        local ch  = lp.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function()
                hum.PlatformStand = true
                hum:ChangeState(Enum.HumanoidStateType.Physics)
            end)
        end

        setNoClip(true)

        -- ใช้ Heartbeat เพื่ออัปเดตทุกเฟรม
        WARP.flyConn = RunService.Heartbeat:Connect(function(dt)
            local selfHRP  = getHumanoidRoot(lp)
            local tgtPl    = getTargetPlayer()
            local tgtHRP   = tgtPl and getHumanoidRoot(tgtPl)
            if not selfHRP or not tgtHRP then
                stopFly()
                return
            end

            if WARP.mode ~= "fly" then
                stopFly()
                return
            end

            -- บังคับ NoClip + ลบความเร็วตกทุกเฟรม
            enforceNoClip()
            pcall(function()
                selfHRP.AssemblyLinearVelocity  = Vector3.new(0,0,0)
                selfHRP.AssemblyAngularVelocity = Vector3.new(0,0,0)
            end)

            -- เป้าหมายจริง 3D ตามตำแหน่งผู้เล่น (อยู่สูงก็ไปถึง)
            local targetPos = tgtHRP.Position + Vector3.new(0, heightOffset, 0)
            local pos       = selfHRP.Position
            local diff      = targetPos - pos
            local dist      = diff.Magnitude

            -- ถ้าเข้าใกล้พอแล้ว ใช้ instant warp ปิดจบเลย
            if dist < stopDist then
                doInstantWarp()
                return
            end

            local step = math.min(dist, SPEED * dt)
            local dir  = diff.Unit
            local nextPos = pos + dir * step

            -- กันไม่ให้ต่ำกว่าผิวน้ำ
            local waterY = getWaterLevelAt(nextPos)
            if waterY then
                local minY = waterY + WATER_MARGIN
                if nextPos.Y < minY then
                    nextPos = Vector3.new(nextPos.X, minY, nextPos.Z)
                end
            end

            pcall(function()
                selfHRP.CFrame = CFrame.new(nextPos, targetPos)
            end)
        end)
    end

    local function startAction()
        local targetPl = getTargetPlayer()
        if not targetPl then return end

        if WARP.mode == "warp" then
            doInstantWarp()
        elseif WARP.mode == "fly" then
            doFlyWarp()
        end
    end

    ------------------------------------------------------------------------
    -- UI BUILD BASE
    ------------------------------------------------------------------------
    for _,n in ipairs({"WARP_Header","WARP_Row1","WARP_Row2","WARP_Row3","WARP_Row4","WARP_PlayerOverlay"}) do
        local o = scroll:FindFirstChild(n) or scroll.Parent:FindFirstChild(n)
        if o then o:Destroy() end
    end

    local vlist = scroll:FindFirstChildOfClass("UIListLayout")
    if not vlist then
        vlist = Instance.new("UIListLayout")
        vlist.Parent = scroll
        vlist.Padding   = UDim.new(0,12)
        vlist.SortOrder = Enum.SortOrder.LayoutOrder
    end
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

    local base = 0
    for _,ch in ipairs(scroll:GetChildren()) do
        if ch:IsA("GuiObject") and ch ~= vlist then
            base = math.max(base, ch.LayoutOrder or 0)
        end
    end

    local header = Instance.new("TextLabel")
    header.Name = "WARP_Header"
    header.Parent = scroll
    header.BackgroundTransparency = 1
    header.Size = UDim2.new(1,0,0,36)
    header.Font = Enum.Font.GothamBold
    header.TextSize = 16
    header.TextColor3 = THEME.TEXT
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Text = "》》》Warp to Player 🌀《《《"
    header.LayoutOrder = base + 1

    local function makeRow(name, order, labelText)
        local row = Instance.new("Frame")
        row.Name = name
        row.Parent = scroll
        row.Size = UDim2.new(1,-6,0,46)
        row.BackgroundColor3 = THEME.BLACK
        corner(row,12)
        stroke(row,2.2,THEME.GREEN)
        row.LayoutOrder = order

        local lab = Instance.new("TextLabel")
        lab.Parent = row
        lab.BackgroundTransparency = 1
        lab.Size = UDim2.new(0,180,1,0)
        lab.Position = UDim2.new(0,16,0,0)
        lab.Font = Enum.Font.GothamBold
        lab.TextSize = 13
        lab.TextColor3 = THEME.WHITE
        lab.TextXAlignment = Enum.TextXAlignment.Left
        lab.Text = labelText

        return row, lab
    end

    ------------------------------------------------------------------------
    -- Row 1 : A V2 เต็มระบบ + Overlay เลือกผู้เล่น
    ------------------------------------------------------------------------
    local panelParent = scroll.Parent
    local row1 = makeRow("WARP_Row1", base + 2, "Select Target Player")

    local selectBtn = Instance.new("TextButton")
    selectBtn.Name = "WARP_Select"
    selectBtn.Parent = row1
    selectBtn.AnchorPoint = Vector2.new(1,0.5)
    selectBtn.Position = UDim2.new(1,-16,0.5,0)
    selectBtn.Size = UDim2.new(0,220,0,28)
    selectBtn.BackgroundColor3 = THEME.BLACK
    selectBtn.AutoButtonColor = false
    selectBtn.Text = "🔎 Search Player Name"
    selectBtn.Font = Enum.Font.GothamBold
    selectBtn.TextSize = 13
    selectBtn.TextColor3 = THEME.WHITE
    selectBtn.TextXAlignment = Enum.TextXAlignment.Center
    selectBtn.TextYAlignment = Enum.TextYAlignment.Center
    corner(selectBtn,8)

    local selectStroke = stroke(selectBtn,1.8,THEME.GREEN_DARK)
    selectStroke.Transparency = 0.4

    local padding = Instance.new("UIPadding")
    padding.Parent = selectBtn
    padding.PaddingLeft  = UDim.new(0,8)
    padding.PaddingRight = UDim.new(0,26)

    local arrow = Instance.new("TextLabel")
    arrow.Parent = selectBtn
    arrow.AnchorPoint = Vector2.new(1,0.5)
    arrow.Position = UDim2.new(1,-6,0.5,0)
    arrow.Size = UDim2.new(0,18,0,18)
    arrow.BackgroundTransparency = 1
    arrow.Font = Enum.Font.GothamBold
    arrow.TextSize = 18
    arrow.TextColor3 = THEME.WHITE
    arrow.Text = "▼"

    local function updateSelectVisual(isOpen)
        if isOpen then
            selectStroke.Color        = THEME.GREEN
            selectStroke.Thickness    = 2.4
            selectStroke.Transparency = 0
        else
            selectStroke.Color        = THEME.GREEN_DARK
            selectStroke.Thickness    = 1.8
            selectStroke.Transparency = 0.4
        end
    end

    local function refreshSelectedLabel()
        local pl = getTargetPlayer()
        if pl then
            local display = (pl.DisplayName ~= "" and pl.DisplayName) or pl.Name
            selectBtn.Text = display
        else
            selectBtn.Text = "🔎 Search Player Name"
        end
    end
    refreshSelectedLabel()

    ------------------------------------------------------------------------
    -- Overlay Panel (Player List แบบ A V2)
    ------------------------------------------------------------------------
    local optionsPanel
    local inputConn
    local opened = false

    local function disconnectInput()
        if inputConn then
            inputConn:Disconnect()
            inputConn = nil
        end
    end

    local function closePanel()
        if optionsPanel then
            optionsPanel:Destroy()
            optionsPanel = nil
        end
        disconnectInput()
        opened = false
        updateSelectVisual(false)
    end

    local function openPanel()
        closePanel()

        local pw, ph = panelParent.AbsoluteSize.X, panelParent.AbsoluteSize.Y
        local leftRatio   = 0.645
        local topRatio    = 0.02
        local bottomRatio = 0.02
        local rightMargin = 8

        local leftX   = math.floor(pw * leftRatio)
        local topY    = math.floor(ph * topRatio)
        local bottomM = math.floor(ph * bottomRatio)

        local w = pw - leftX - rightMargin
        local h = ph - topY - bottomM

        optionsPanel = Instance.new("Frame")
        optionsPanel.Name = "WARP_PlayerOverlay"
        optionsPanel.Parent = panelParent
        optionsPanel.BackgroundColor3 = THEME.BLACK
        optionsPanel.ClipsDescendants = true
        optionsPanel.AnchorPoint = Vector2.new(0,0)
        optionsPanel.Position    = UDim2.new(0,leftX,0,topY)
        optionsPanel.Size        = UDim2.new(0,w,0,h)
        optionsPanel.ZIndex      = 50

        corner(optionsPanel,12)
        stroke(optionsPanel,2.4,THEME.GREEN)

        local body = Instance.new("Frame")
        body.Name = "Body"
        body.Parent = optionsPanel
        body.BackgroundTransparency = 1
        body.BorderSizePixel = 0
        body.Position = UDim2.new(0,4,0,4)
        body.Size     = UDim2.new(1,-8,1,-8)
        body.ZIndex   = optionsPanel.ZIndex + 1

        local searchBox = Instance.new("TextBox")
        searchBox.Name = "SearchBox"
        searchBox.Parent = body
        searchBox.BackgroundColor3 = THEME.BLACK
        searchBox.ClearTextOnFocus = false
        searchBox.Font = Enum.Font.GothamBold
        searchBox.TextSize = 14
        searchBox.TextColor3 = THEME.WHITE
        searchBox.PlaceholderText = "🔎 Search Player Name"
        searchBox.TextXAlignment = Enum.TextXAlignment.Center
        searchBox.Text = ""
        searchBox.ZIndex = body.ZIndex + 1
        searchBox.Size = UDim2.new(1,0,0,32)
        searchBox.Position = UDim2.new(0,0,0,0)
        corner(searchBox,8)

        local sbStroke = stroke(searchBox,1.8,THEME.GREEN)
        sbStroke.ZIndex = searchBox.ZIndex + 1

        local listHolder = Instance.new("ScrollingFrame")
        listHolder.Name = "PlayerList"
        listHolder.Parent = body
        listHolder.BackgroundColor3 = THEME.BLACK
        listHolder.BorderSizePixel = 0
        listHolder.ScrollBarThickness = 0
        listHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
        listHolder.CanvasSize = UDim2.new(0,0,0,0)
        listHolder.ZIndex = body.ZIndex + 1
        listHolder.ScrollingDirection = Enum.ScrollingDirection.Y
        listHolder.ClipsDescendants = true

        local listTopOffset = 32 + 10
        listHolder.Position = UDim2.new(0,0,0,listTopOffset)
        listHolder.Size     = UDim2.new(1,0,1,-(listTopOffset + 4))

        local listLayout = Instance.new("UIListLayout")
        listLayout.Parent = listHolder
        listLayout.Padding = UDim.new(0,8)
        listLayout.SortOrder = Enum.SortOrder.LayoutOrder
        listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

        local listPadding = Instance.new("UIPadding")
        listPadding.Parent = listHolder
        listPadding.PaddingTop    = UDim.new(0,6)
        listPadding.PaddingBottom = UDim.new(0,6)
        listPadding.PaddingLeft   = UDim.new(0,4)
        listPadding.PaddingRight  = UDim.new(0,4)

        local function onLayoutChanged()
            listHolder.CanvasSize = UDim2.new(0,0,0,listLayout.AbsoluteContentSize.Y + 4)
        end
        listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(onLayoutChanged)

        -- ล็อกไม่ให้เลื่อนแกน X
        local locking = false
        listHolder:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
            if locking then return end
            locking = true
            local pos = listHolder.CanvasPosition
            if pos.X ~= 0 then
                listHolder.CanvasPosition = Vector2.new(0,pos.Y)
            end
            locking = false
        end)

        --------------------------------------------------------------------
        -- ปุ่มผู้เล่น = Glow Button A V2
        --------------------------------------------------------------------
        local playerButtons = {}

        local function updateButtonVisual(pl, info)
            local on = (WARP.targetUserId == (pl and pl.UserId or nil))
            if not info then return end
            local st      = info.stroke
            local glowBar = info.glow

            if on then
                st.Color        = THEME.GREEN
                st.Thickness    = 2.4
                st.Transparency = 0
                glowBar.Visible = true
            else
                st.Color        = THEME.GREEN_DARK
                st.Thickness    = 1.6
                st.Transparency = 0.4
                glowBar.Visible = false
            end
        end

        local function addPlayerButton(pl)
            if pl == lp then return end

            local btn = Instance.new("TextButton")
            btn.Name = "Btn_" .. pl.UserId
            btn.Parent = listHolder
            btn.Size = UDim2.new(1,0,0,28)
            btn.BackgroundColor3 = THEME.BLACK
            btn.AutoButtonColor = false
            btn.Font = Enum.Font.GothamBold
            btn.TextSize = 14
            btn.TextColor3 = THEME.WHITE
            local display = (pl.DisplayName ~= "" and pl.DisplayName) or pl.Name
            btn.Text = display
            btn.ZIndex = listHolder.ZIndex + 1
            btn.TextXAlignment = Enum.TextXAlignment.Center
            btn.TextYAlignment = Enum.TextYAlignment.Center
            corner(btn,6)

            local st = stroke(btn,1.6,THEME.GREEN_DARK)
            st.Transparency = 0.4

            local glowBar = Instance.new("Frame")
            glowBar.Name = "GlowBar"
            glowBar.Parent = btn
            glowBar.BackgroundColor3 = THEME.GREEN
            glowBar.BorderSizePixel = 0
            glowBar.Size = UDim2.new(0,3,1,0)
            glowBar.Position = UDim2.new(0,0,0,0)
            glowBar.ZIndex = btn.ZIndex + 1
            glowBar.Visible = false

            playerButtons[pl] = {
                btn   = btn,
                glow  = glowBar,
                stroke= st,
            }

            updateButtonVisual(pl, playerButtons[pl])

            btn.MouseButton1Click:Connect(function()
                WARP.targetUserId = pl.UserId
                refreshSelectedLabel()
                for ppl,info in pairs(playerButtons) do
                    updateButtonVisual(ppl, info)
                end
                closePanel()
            end)
        end

        local function rebuildList()
            for _,info in pairs(playerButtons) do
                if info.btn then info.btn:Destroy() end
            end
            table.clear(playerButtons)

            for _,pl in ipairs(Players:GetPlayers()) do
                if pl ~= lp then
                    addPlayerButton(pl)
                end
            end
            onLayoutChanged()
        end

        rebuildList()
        Players.PlayerAdded:Connect(rebuildList)
        Players.PlayerRemoving:Connect(rebuildList)

        local function trim(s)
            return (s:gsub("^%s*(.-)%s*$","%1"))
        end

        local function applySearch()
            local q = string.lower(trim(searchBox.Text or ""))

            for pl,info in pairs(playerButtons) do
                local btn = info.btn
                local display = btn.Text or ""
                local txt = string.lower(display)
                local match = (q == "" or string.find(txt,q,1,true) ~= nil)
                btn.Visible = match
            end

            listHolder.CanvasPosition = Vector2.new(0,0)
        end

        searchBox:GetPropertyChangedSignal("Text"):Connect(applySearch)

        searchBox.Focused:Connect(function()
            sbStroke.Color = THEME.GREEN
        end)
        searchBox.FocusLost:Connect(function()
            sbStroke.Color = THEME.GREEN
        end)

        inputConn = UserInputService.InputBegan:Connect(function(input,gp)
            if not optionsPanel then return end
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end

            local pos = input.Position
            local px,py = pos.X, pos.Y
            local op = optionsPanel.AbsolutePosition
            local os = optionsPanel.AbsoluteSize

            local inside =
                px >= op.X and px <= op.X + os.X and
                py >= op.Y and py <= op.Y + os.Y

            if not inside then
                closePanel()
            end
        end)

        opened = true
        updateSelectVisual(true)
    end

    selectBtn.MouseButton1Click:Connect(function()
        if opened then
            closePanel()
        else
            openPanel()
        end
    end)

    ------------------------------------------------------------------------
    -- Row2 / Row3 : Switch (A V1)
    ------------------------------------------------------------------------
    local row2Switch, row3Switch

    local function makeSwitchRow(name, order, labelText, getOn, setOn)
        local row = Instance.new("Frame")
        row.Name = name
        row.Parent = scroll
        row.Size = UDim2.new(1,-6,0,46)
        row.BackgroundColor3 = THEME.BLACK
        corner(row,12)
        stroke(row,2.2,THEME.GREEN)
        row.LayoutOrder = order

        local lab = Instance.new("TextLabel")
        lab.Parent = row
        lab.BackgroundTransparency = 1
        lab.Size = UDim2.new(1,-160,1,0)
        lab.Position = UDim2.new(0,16,0,0)
        lab.Font = Enum.Font.GothamBold
        lab.TextSize = 13
        lab.TextColor3 = THEME.WHITE
        lab.TextXAlignment = Enum.TextXAlignment.Left
        lab.Text = labelText

        local sw = Instance.new("Frame")
        sw.Parent = row
        sw.AnchorPoint = Vector2.new(1,0.5)
        sw.Position = UDim2.new(1,-12,0.5,0)
        sw.Size = UDim2.fromOffset(52,26)
        sw.BackgroundColor3 = THEME.BLACK
        corner(sw,13)

        local swStroke = Instance.new("UIStroke")
        swStroke.Parent = sw
        swStroke.Thickness = 1.8

        local knob = Instance.new("Frame")
        knob.Parent = sw
        knob.Size = UDim2.fromOffset(22,22)
        knob.BackgroundColor3 = THEME.WHITE
        knob.Position = UDim2.new(0,2,0.5,-11)
        corner(knob,11)

        local function updateVisual(on)
            swStroke.Color = on and THEME.GREEN or THEME.RED
            tween(knob,{
                Position = UDim2.new(on and 1 or 0, on and -24 or 2, 0.5,-11)
            },0.08)
        end

        local btn = Instance.new("TextButton")
        btn.Parent = sw
        btn.BackgroundTransparency = 1
        btn.Size = UDim2.fromScale(1,1)
        btn.Text = ""
        btn.AutoButtonColor = false

        btn.MouseButton1Click:Connect(function()
            local new = not getOn()
            setOn(new)
            updateVisual(new)
        end)

        updateVisual(getOn())

        return {
            row    = row,
            sw     = sw,
            stroke = swStroke,
            knob   = knob,
            update = updateVisual,
        }
    end

    row2Switch = makeSwitchRow(
        "WARP_Row2",
        base + 3,
        "Instant Warp to Player",
        function() return WARP.mode == "warp" end,
        function(on)
            if on then
                WARP.mode = "warp"
                if row3Switch then
                    row3Switch.update(false)
                end
                stopFly()
            else
                if WARP.mode == "warp" then
                    WARP.mode = "none"
                end
            end
        end
    )

    row3Switch = makeSwitchRow(
        "WARP_Row3",
        base + 4,
        "Fly to Player",
        function() return WARP.mode == "fly" end,
        function(on)
            if on then
                WARP.mode = "fly"
                if row2Switch then
                    row2Switch.update(false)
                end
            else
                if WARP.mode == "fly" then
                    WARP.mode = "none"
                end
                stopFly()
            end
        end
    )

    row2Switch.update(WARP.mode == "warp")
    row3Switch.update(WARP.mode == "fly")

    ------------------------------------------------------------------------
    -- Row4 : Start Button
    ------------------------------------------------------------------------
    local row4 = Instance.new("Frame")
    row4.Name = "WARP_Row4"
    row4.Parent = scroll
    row4.Size = UDim2.new(1,-6,0,46)
    row4.BackgroundColor3 = THEME.DARK
    corner(row4,12)
    stroke(row4,2.2,THEME.GREEN)
    row4.LayoutOrder = base + 5

    local startLabel = Instance.new("TextLabel")
    startLabel.Parent = row4
    startLabel.BackgroundTransparency = 1
    startLabel.Size = UDim2.fromScale(1,1)
    startLabel.Font = Enum.Font.GothamBold
    startLabel.TextSize = 14
    startLabel.TextColor3 = THEME.WHITE
    startLabel.Text = "Start"
    startLabel.TextXAlignment = Enum.TextXAlignment.Center

    local startBtn = Instance.new("TextButton")
    startBtn.Parent = row4
    startBtn.BackgroundTransparency = 1
    startBtn.Size = UDim2.fromScale(1,1)
    startBtn.Text = ""
    startBtn.AutoButtonColor = false

    startBtn.MouseButton1Click:Connect(function()
        tween(row4,{BackgroundColor3 = THEME.GREEN},0.06)
        task.delay(0.08,function()
            tween(row4,{BackgroundColor3 = THEME.DARK},0.08)
        end)
        startAction()
    end)
end)
-- ===== UFO HUB X • Update Tab — Map Update 🗺️ =====
registerRight("Update", function(scroll)
    local Players = game:GetService("Players")
    local MarketplaceService = game:GetService("MarketplaceService")
    local RunService = game:GetService("RunService")

    -- CONFIG
    local MAP_SUFFIX = " — อัพเดต v1.0 ✍️"
    local NOTES_TEXT = "- เพิ่มจุดเกิดใหม่\n-A1\n-A2\n-A3\n-A4\n-A5\n-A6\n-A7\n-A8\n-A9"

    -- THEME
    local THEME = {
        GREEN=Color3.fromRGB(25,255,125), WHITE=Color3.fromRGB(255,255,255),
        BLACK=Color3.fromRGB(0,0,0), GREY=Color3.fromRGB(180,180,185)
    }
    local function corner(ui,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 12); c.Parent=ui end
    local function stroke(ui,th,col,trans) local s=Instance.new("UIStroke"); s.Thickness=th or 2.2; s.Color=col or THEME.GREEN; s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Transparency=trans or 0; s.Parent=ui; return s end

    -- clear old
    for _,n in ipairs({"UP_Header","UP_Wrap"}) do local o=scroll:FindFirstChild(n); if o then o:Destroy() end end

    -- list defaults
    local list = scroll:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout",scroll)
    list.Padding = UDim.new(0,12); list.SortOrder = Enum.SortOrder.LayoutOrder
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

    local base = 3100

    -- title
    local head = Instance.new("TextLabel",scroll)
    head.Name="UP_Header"; head.LayoutOrder=base; head.BackgroundTransparency=1; head.Size=UDim2.new(1,0,0,32)
    head.Font=Enum.Font.GothamBlack; head.TextSize=16; head.TextColor3=THEME.WHITE; head.TextXAlignment=Enum.TextXAlignment.Left
    head.Text="》》》Update Game 🗺️《《《"

    -- wrap
    local wrap = Instance.new("Frame",scroll)
    wrap.Name="UP_Wrap"; wrap.LayoutOrder=base+1; wrap.Size=UDim2.new(1,-6,0,260)
    wrap.BackgroundColor3=THEME.BLACK; corner(wrap,12); stroke(wrap,2.2,THEME.GREEN)

    -- ===== Header (now BLACK)
    local header = Instance.new("Frame",wrap)
    header.BackgroundColor3 = THEME.BLACK   -- ← เปลี่ยนเป็นดำ
    header.Position = UDim2.new(0,12,0,12)
    header.Size = UDim2.new(1,-24,0,60)
    corner(header,10); stroke(header,1.6,THEME.GREEN,0)

    local icon = Instance.new("ImageLabel",header)
    icon.BackgroundTransparency=1
    icon.Size = UDim2.fromOffset(48,48)
    icon.Position = UDim2.new(0,8,0,6)
    icon.ScaleType = Enum.ScaleType.Fit
    icon.Image = ("rbxthumb://type=GameIcon&id=%d&w=150&h=150"):format(game.GameId)

    local mapName = "Current Place"
    pcall(function()
        local inf = MarketplaceService:GetProductInfo(game.PlaceId)
        if inf and inf.Name then mapName = inf.Name end
    end)

    local nameLbl = Instance.new("TextLabel",header)
    nameLbl.BackgroundTransparency=1
    nameLbl.Position = UDim2.new(0,8+48+10,0,0)
    nameLbl.Size = UDim2.new(1,-(8+48+10+12),1,0)
    nameLbl.Font = Enum.Font.GothamBlack
    nameLbl.TextSize = 16
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.TextColor3 = THEME.WHITE       -- ← ตัวอักษรขาวให้ตัดกับพื้นดำ
    nameLbl.Text = mapName .. ((MAP_SUFFIX ~= "" and (" "..MAP_SUFFIX)) or "")

    -- ===== Notes (BLACK + no scrollbar visuals)
    local notesScroll = Instance.new("ScrollingFrame",wrap)
    notesScroll.Name = "UP_Notes"
    notesScroll.Position = UDim2.new(0,12,0,12+60+12)
    notesScroll.Size = UDim2.new(1,-24,1,-(12+60+12+12))
    notesScroll.BackgroundColor3 = THEME.BLACK  -- ← เปลี่ยนเป็นดำ
    notesScroll.BorderSizePixel = 0
    notesScroll.ScrollingDirection = Enum.ScrollingDirection.Y
    notesScroll.AutomaticCanvasSize = Enum.AutomaticSize.None
    notesScroll.CanvasSize = UDim2.new(0,0,0,0)
    notesScroll.Active = true
    -- ซ่อนเส้นสกรอลล์ทั้งหมด
    notesScroll.ScrollBarThickness = 0
    notesScroll.ScrollBarImageTransparency = 1
    corner(notesScroll,10); stroke(notesScroll,1.8,THEME.GREEN,0.15)

    local PAD_L, PAD_R, PAD_T, PAD_B = 14, 10, 10, 10
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft   = UDim.new(0,PAD_L)
    pad.PaddingRight  = UDim.new(0,PAD_R)
    pad.PaddingTop    = UDim.new(0,PAD_T)
    pad.PaddingBottom = UDim.new(0,PAD_B)
    pad.Parent = notesScroll

    local label = Instance.new("TextLabel", notesScroll)
    label.BackgroundTransparency = 1
    label.Position = UDim2.new(0,0,0,0)
    label.Size = UDim2.new(1,-(PAD_L+PAD_R), 0, 0)
    label.Font = Enum.Font.Gotham
    label.TextSize = 16
    label.TextColor3 = THEME.WHITE          -- ← ข้อความขาวบนพื้นดำ
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.TextWrapped = true
    label.RichText = true
    label.Text = NOTES_TEXT

    local function refreshNoteSize()
        local _ = label.TextBounds
        label.Size = UDim2.new(1,-(PAD_L+PAD_R), 0, label.TextBounds.Y)
        notesScroll.CanvasSize = UDim2.new(0,0,0, label.TextBounds.Y + PAD_T + PAD_B)
    end
    refreshNoteSize()
    label:GetPropertyChangedSignal("TextBounds"):Connect(refreshNoteSize)
    RunService.Heartbeat:Connect(refreshNoteSize)
end)
-- ===== [FULL PASTE] UFO HUB X • Update Tab — System #2: Social Links (A V1 + press effect + UFO toast) =====
registerRight("Update", function(scroll)
    -- ===== THEME (A V1) =====
    local THEME = {
        GREEN = Color3.fromRGB(25,255,125),
        WHITE = Color3.fromRGB(255,255,255),
        BLACK = Color3.fromRGB(0,0,0),
        TEXT  = Color3.fromRGB(255,255,255),
    }
    local function corner(ui,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 12); c.Parent=ui end
    local function stroke(ui,th,col) local s=Instance.new("UIStroke"); s.Thickness=th or 2.2; s.Color=col or THEME.GREEN; s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=ui end
    local TS = game:GetService("TweenService")

    -- ===== UFO Quick Toast (EN) — title with white 'UFO' + green 'HUB X' =====
    local function QuickToast(msg)
        local PG = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
        local gui = Instance.new("ScreenGui")
        gui.Name = "UFO_QuickToast"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 999999
        gui.Parent = PG

        local W,H = 320, 70
        local box = Instance.new("Frame")
        box.Name = "Toast"
        box.AnchorPoint = Vector2.new(1,1)
        box.Position = UDim2.new(1, -2, 1, -(2 - 24))
        box.Size = UDim2.fromOffset(W, H)
        box.BackgroundColor3 = Color3.fromRGB(10,10,10)
        box.BorderSizePixel = 0
        box.Parent = gui
        corner(box, 10)
        local st = Instance.new("UIStroke", box)
        st.Thickness = 2
        st.Color = THEME.GREEN
        st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

        local title = Instance.new("TextLabel")
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBold
        title.RichText = true
        title.Text = '<font color="#FFFFFF">UFO</font> <font color="#19FF7D">HUB X</font>'
        title.TextSize = 18
        title.TextColor3 = THEME.WHITE
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Position = UDim2.fromOffset(14, 10)
        title.Size = UDim2.fromOffset(W-24, 20)
        title.Parent = box

        local text = Instance.new("TextLabel")
        text.BackgroundTransparency = 1
        text.Font = Enum.Font.Gotham
        text.Text = msg
        text.TextSize = 13
        text.TextColor3 = Color3.fromRGB(200,200,200)
        text.TextXAlignment = Enum.TextXAlignment.Left
        text.Position = UDim2.fromOffset(14, 34)
        text.Size = UDim2.fromOffset(W-24, 24)
        text.Parent = box

        TS:Create(box, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            {Position = UDim2.new(1, -2, 1, -2)}):Play()

        task.delay(1.25, function()
            local t = TS:Create(box, TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut),
                {Position = UDim2.new(1, -2, 1, -(2 - 24))})
            t:Play(); t.Completed:Wait(); gui:Destroy()
        end)
    end

    -- ===== A V1 RULE: one UIListLayout under `scroll` =====
    local list = scroll:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout", scroll)
    list.Padding = UDim.new(0, 12)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

    -- dynamic base by current children (respects file/run order)
    local base = 10
    for _,ch in ipairs(scroll:GetChildren()) do
        if ch:IsA("GuiObject") and ch ~= list then
            base = math.max(base, (ch.LayoutOrder or 0) + 1)
        end
    end

    -- clear duplicates
    for _,n in ipairs({"SOC2_Header","SOC2_Row_YT","SOC2_Row_FB","SOC2_Row_DC","SOC2_Row_IG"}) do
        local o = scroll:FindFirstChild(n); if o then o:Destroy() end
    end

    -- data
    local DATA = {
        { key="YT", label="YouTube UFO HUB X",  color=Color3.fromRGB(220,30,30),
          link="https://youtube.com/@ufohubxstudio?si=XXFZ0rcJn9zva3x6" },
        { key="FB", label="Facebook UFO HUB X", color=Color3.fromRGB(40,120,255), link="" },
        { key="DC", label="Discord UFO HUB X",  color=Color3.fromRGB(88,101,242),
          link="https://discord.gg/A6Mqpfj3" },
        { key="IG", label="Instagram UFO HUB X",color=Color3.fromRGB(225,48,108), link="" },
    }

    -- header (single)
    local head = Instance.new("TextLabel", scroll)
    head.Name = "SOC2_Header"
    head.BackgroundTransparency = 1
    head.Size = UDim2.new(1, 0, 0, 36)
    head.Font = Enum.Font.GothamBold
    head.TextSize = 16
    head.TextColor3 = THEME.TEXT
    head.TextXAlignment = Enum.TextXAlignment.Left
    head.Text = "》》》Social Update UFO HUB X 📣《《《"
    head.LayoutOrder = base; base += 1

    -- press effect util (darken briefly)
    local function pressEffect(row, baseColor)
        local dark = Color3.fromRGB(
            math.max(math.floor(baseColor.R*255)-18,0),
            math.max(math.floor(baseColor.G*255)-18,0),
            math.max(math.floor(baseColor.B*255)-18,0)
        )
        TS:Create(row, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundColor3 = dark}):Play()
        task.delay(0.08, function()
            TS:Create(row, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {BackgroundColor3 = baseColor}):Play()
        end)
    end

    -- row factory (no row icons; right-side plain ▶ only)
    local function makeRow(item, order)
        local row = Instance.new("Frame", scroll)
        row.Name = "SOC2_Row_"..item.key
        row.Size = UDim2.new(1, -6, 0, 46)
        row.LayoutOrder = order
        row.BackgroundColor3 = item.color
        corner(row, 12); stroke(row, 2.2, THEME.GREEN)

        local lab = Instance.new("TextLabel", row)
        lab.BackgroundTransparency = 1
        lab.Position = UDim2.new(0, 16, 0, 0)
        lab.Size = UDim2.new(1, -56, 1, 0) -- leave space for arrow
        lab.Font = Enum.Font.GothamBold
        lab.TextSize = 13
        lab.TextColor3 = THEME.WHITE
        lab.TextXAlignment = Enum.TextXAlignment.Left
        lab.Text = item.label

        -- plain arrow (no bg / no stroke)
        local arrow = Instance.new("TextLabel", row)
        arrow.BackgroundTransparency = 1
        arrow.AnchorPoint = Vector2.new(1,0.5)
        arrow.Position = UDim2.new(1, -14, 0.5, 0)
        arrow.Size = UDim2.fromOffset(18, 18)
        arrow.Font = Enum.Font.GothamBlack
        arrow.TextSize = 18
        arrow.TextColor3 = THEME.WHITE
        arrow.Text = "▶"

        -- click whole row
        local hit = Instance.new("TextButton", row)
        hit.BackgroundTransparency = 1
        hit.AutoButtonColor = false
        hit.Text = ""
        hit.Size = UDim2.fromScale(1,1)
        hit.MouseButton1Click:Connect(function()
            pressEffect(row, item.color)
            if item.link ~= "" then
                local ok=false
                if typeof(setclipboard)=="function" then ok = pcall(function() setclipboard(item.link) end) end
                QuickToast(item.label .. " — Link Copied ✅")
                if not ok then print("[UFO HUB X] Clipboard Not Available; Link: "..item.link) end
            else
                QuickToast(item.label .. " — No Link")
            end
        end)
    end

    -- build rows under header in dynamic order
    for _,it in ipairs(DATA) do makeRow(it, base); base += 1 end
end)
-- ===== [/FULL PASTE] =====
--===== UFO HUB X • SERVER — Model A V1 (2 rows: change + live count) =====
registerRight("Server", function(scroll)
    local Players        = game:GetService("Players")
    local TeleportService= game:GetService("TeleportService")
    local HttpService    = game:GetService("HttpService")
    local TweenService   = game:GetService("TweenService")
    local lp             = Players.LocalPlayer

    -- THEME (A V1)
    local THEME = {
        GREEN = Color3.fromRGB(25,255,125),
        WHITE = Color3.fromRGB(255,255,255),
        BLACK = Color3.fromRGB(0,0,0),
        TEXT  = Color3.fromRGB(255,255,255),
        RED   = Color3.fromRGB(255,40,40),
        GREY  = Color3.fromRGB(70,70,75),
    }
    local function corner(ui,r) local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,r or 12) c.Parent=ui end
    local function stroke(ui,th,col) local s=Instance.new("UIStroke") s.Thickness=th or 2.2 s.Color=col or THEME.GREEN s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border s.Parent=ui end
    local function tween(o,p,d) TweenService:Create(o, TweenInfo.new(d or 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), p):Play() end

    -- A V1: single ListLayout on scroll
    local list = scroll:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout", scroll)
    list.Padding = UDim.new(0,12); list.SortOrder = Enum.SortOrder.LayoutOrder
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

    -- Header (Server + emoji)
    local head = scroll:FindFirstChild("SV_Header") or Instance.new("TextLabel", scroll)
    head.Name="SV_Header"; head.BackgroundTransparency=1; head.Size=UDim2.new(1,0,0,36)
    head.Font=Enum.Font.GothamBold; head.TextSize=16; head.TextColor3=THEME.TEXT
    head.TextXAlignment=Enum.TextXAlignment.Left; head.Text="》》》Server 🌐《《《"; head.LayoutOrder = 10

    -- Clear same-name rows (A V1 rule, no wrappers)
    for _,n in ipairs({"S1_Change","S2_PlayerCount"}) do local o=scroll:FindFirstChild(n) if o then o:Destroy() end end

    -- Row factory (A V1)
    local function makeRow(name, label, order)
        local row = Instance.new("Frame", scroll)
        row.Name=name; row.Size=UDim2.new(1,-6,0,46); row.BackgroundColor3=THEME.BLACK
        row.LayoutOrder=order; corner(row,12); stroke(row,2.2,THEME.GREEN)

        local lab = Instance.new("TextLabel", row)
        lab.BackgroundTransparency=1; lab.Size=UDim2.new(1,-160,1,0); lab.Position=UDim2.new(0,16,0,0)
        lab.Font=Enum.Font.GothamBold; lab.TextSize=13; lab.TextColor3=THEME.WHITE
        lab.TextXAlignment=Enum.TextXAlignment.Left; lab.Text=label

        return row
    end

    ----------------------------------------------------------------
    -- (#1) Change Server — one-tap button (no toggle)
    ----------------------------------------------------------------
    local r1 = makeRow("S1_Change", "Change Server", 11)
    local btnWrap = Instance.new("Frame", r1)
    btnWrap.AnchorPoint=Vector2.new(1,0.5); btnWrap.Position=UDim2.new(1,-12,0.5,0)
    btnWrap.Size=UDim2.fromOffset(110,28); btnWrap.BackgroundColor3=THEME.BLACK; corner(btnWrap,8); stroke(btnWrap,1.8,THEME.GREEN)

    local btn = Instance.new("TextButton", btnWrap)
    btn.BackgroundTransparency=1; btn.Size=UDim2.fromScale(1,1)
    btn.Font=Enum.Font.GothamBold; btn.TextSize=13; btn.TextColor3=THEME.TEXT
    btn.Text="Change Server "

    local busy=false
    local function setBusy(v)
        busy=v
        btn.Text = v and "Changing Server ..." or "Change Server"
        local st = btnWrap:FindFirstChildOfClass("UIStroke")
        if st then st.Color = v and THEME.GREY or THEME.GREEN end
    end

    local function findOtherPublicServer(placeId)
        -- Query public servers; pick a different JobId with free slots
        local cursor = nil
        for _=1,4 do -- up to 4 pages
            local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100%s")
                :format(placeId, cursor and ("&cursor="..HttpService:UrlEncode(cursor)) or "")
            local ok,res = pcall(function() return HttpService:GetAsync(url) end)
            if ok and res then
                local data = HttpService:JSONDecode(res)
                if data and data.data then
                    for _,sv in ipairs(data.data) do
                        local jobId = sv.id
                        local playing = tonumber(sv.playing) or 0
                        local maxp = tonumber(sv.maxPlayers) or Players.MaxPlayers
                        if jobId and jobId ~= game.JobId and playing < maxp then
                            return jobId
                        end
                    end
                end
                cursor = data and data.nextPageCursor or nil
                if not cursor then break end
            else
                break
            end
        end
        return nil
    end

    local function hop()
        if busy then return end
        setBusy(true)
        task.spawn(function()
            local targetJob = nil
            local okFind, errFind = pcall(function()
                targetJob = findOtherPublicServer(game.PlaceId)
            end)
            if targetJob then
                local ok,tpErr = pcall(function()
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, targetJob, lp)
                end)
                if not ok then
                    warn("Failed to Change Server ❌:", tpErr)
                    TeleportService:Teleport(game.PlaceId, lp) -- fallback (may land same server)
                end
            else
                -- fallback: simple teleport to place (Roblox will pick a server)
                TeleportService:Teleport(game.PlaceId, lp)
            end
            -- ถ้าการเทเลพอร์ตไม่สำเร็จทันที ให้ปลด busy ผ่าน timeout
            task.delay(4, function() if busy then setBusy(false) end end)
        end)
    end

    btn.MouseButton1Click:Connect(hop)

    ----------------------------------------------------------------
    -- (#2) Live player count — real-time
    ----------------------------------------------------------------
    local r2 = makeRow("S2_PlayerCount", "Players in This Server", 12)

    local countBox = Instance.new("Frame", r2)
    countBox.AnchorPoint=Vector2.new(1,0.5); countBox.Position=UDim2.new(1,-12,0.5,0)
    countBox.Size=UDim2.fromOffset(110,28); countBox.BackgroundColor3=THEME.BLACK; corner(countBox,8); stroke(countBox,1.8,THEME.GREEN)

    local countLabel = Instance.new("TextLabel", countBox)
    countLabel.BackgroundTransparency=1; countLabel.Size=UDim2.fromScale(1,1)
    countLabel.Font=Enum.Font.GothamBold; countLabel.TextSize=13; countLabel.TextColor3=THEME.TEXT
    countLabel.TextScaled=false; countLabel.Text="-- / --"

    local function updateCount()
        local current = #Players:GetPlayers()
        local maxp = Players.MaxPlayers
        countLabel.Text = string.format("%d / %d", current, maxp)
    end
    updateCount()
    Players.PlayerAdded:Connect(updateCount)
    Players.PlayerRemoving:Connect(updateCount)
end)
-- ===== [FULL PASTE] UFO HUB X • Server — System #2: Server ID 🔑
-- A V1 layout • black buttons • clean TextBox • UFO-style Quick Toast (EN)
registerRight("Server", function(scroll)
    local Players         = game:GetService("Players")
    local TeleportService = game:GetService("TeleportService")
    local TweenService    = game:GetService("TweenService")
    local lp              = Players.LocalPlayer

    -- THEME (A V1)
    local THEME = {
        GREEN = Color3.fromRGB(25,255,125),
        WHITE = Color3.fromRGB(255,255,255),
        BLACK = Color3.fromRGB(0,0,0),
        TEXT  = Color3.fromRGB(255,255,255),
        RED   = Color3.fromRGB(255,40,40),
        GREY  = Color3.fromRGB(60,60,65),
    }
    local function corner(ui,r) local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,r or 12) c.Parent=ui end
    local function stroke(ui,th,col) local s=Instance.new("UIStroke") s.Thickness=th or 2.2 s.Color=col or THEME.GREEN s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border s.Parent=ui end
    local function tween(o,p,d) TweenService:Create(o, TweenInfo.new(d or 0.08, Enum.EasingStyle.Quad,Enum.EasingDirection.Out), p):Play() end

    -- ========= UFO Quick Toast (EN) =========
    local function QuickToast(msg)
        local PG = Players.LocalPlayer:WaitForChild("PlayerGui")
        local old = PG:FindFirstChild("UFO_QuickToast"); if old then old:Destroy() end

        local gui = Instance.new("ScreenGui")
        gui.Name = "UFO_QuickToast"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 999999
        gui.Parent = PG

        local W,H = 320, 70
        local box = Instance.new("Frame")
        box.AnchorPoint = Vector2.new(1,1)
        box.Position = UDim2.new(1, -2, 1, -(2 - 24))
        box.Size = UDim2.fromOffset(W, H)
        box.BackgroundColor3 = Color3.fromRGB(10,10,10)
        box.BorderSizePixel = 0
        box.Parent = gui
        corner(box, 10)
        local st = Instance.new("UIStroke", box)
        st.Thickness = 2
        st.Color = THEME.GREEN
        st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

        local title = Instance.new("TextLabel")
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBold
        title.RichText = true
        title.Text = '<font color="#FFFFFF">UFO</font> <font color="#19FF7D">HUB X</font>'
        title.TextSize = 18
        title.TextColor3 = THEME.WHITE
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Position = UDim2.fromOffset(14, 10)
        title.Size = UDim2.fromOffset(W-24, 20)
        title.Parent = box

        local text = Instance.new("TextLabel")
        text.BackgroundTransparency = 1
        text.Font = Enum.Font.Gotham
        text.Text = msg
        text.TextSize = 13
        text.TextColor3 = Color3.fromRGB(200,200,200)
        text.TextXAlignment = Enum.TextXAlignment.Left
        text.Position = UDim2.fromOffset(14, 34)
        text.Size = UDim2.fromOffset(W-24, 24)
        text.Parent = box

        TweenService:Create(box, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            {Position = UDim2.new(1, -2, 1, -2)}):Play()

        task.delay(1.25, function()
            local t = TweenService:Create(box, TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut),
                {Position = UDim2.new(1, -2, 1, -(2 - 24))})
            t:Play(); t.Completed:Wait(); gui:Destroy()
        end)
    end
    -- ========================================

    local list = scroll:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout", scroll)
    list.Padding = UDim.new(0,12); list.SortOrder = Enum.SortOrder.LayoutOrder
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

    if not scroll:FindFirstChild("SID_Header") then
        local head = Instance.new("TextLabel", scroll)
        head.Name="SID_Header"; head.BackgroundTransparency=1; head.Size=UDim2.new(1,0,0,36)
        head.Font=Enum.Font.GothamBold; head.TextSize=16; head.TextColor3=THEME.TEXT
        head.TextXAlignment=Enum.TextXAlignment.Left; head.Text="》》》Server ID 🔑《《《"
        head.LayoutOrder = 2000
    end

    local function makeRow(name, label, order)
        if scroll:FindFirstChild(name) then return scroll[name] end
        local row = Instance.new("Frame", scroll)
        row.Name=name; row.Size=UDim2.new(1,-6,0,46); row.BackgroundColor3=THEME.BLACK
        row.LayoutOrder=order; corner(row,12); stroke(row,2.2,THEME.GREEN)
        local lab=Instance.new("TextLabel", row)
        lab.BackgroundTransparency=1; lab.Size=UDim2.new(1,-180,1,0); lab.Position=UDim2.new(0,16,0,0)
        lab.Font=Enum.Font.GothamBold; lab.TextSize=13; lab.TextColor3=THEME.WHITE
        lab.TextXAlignment=Enum.TextXAlignment.Left; lab.Text=label
        return row
    end
    local function makeActionButton(parent, text)
        local btn = Instance.new("TextButton", parent)
        btn.AutoButtonColor=false; btn.Text=text; btn.Font=Enum.Font.GothamBold; btn.TextSize=13
        btn.TextColor3=THEME.WHITE; btn.BackgroundColor3=THEME.BLACK
        btn.Size=UDim2.fromOffset(120,28); btn.AnchorPoint=Vector2.new(1,0.5); btn.Position=UDim2.new(1,-12,0.5,0)
        corner(btn,10); stroke(btn,1.6,THEME.GREEN)
        btn.MouseEnter:Connect(function() tween(btn,{BackgroundColor3=THEME.GREY},0.08) end)
        btn.MouseLeave:Connect(function() tween(btn,{BackgroundColor3=THEME.BLACK},0.08) end)
        return btn
    end
    local function makeRightInput(parent, placeholder)
        local boxWrap = Instance.new("Frame", parent)
        boxWrap.AnchorPoint=Vector2.new(1,0.5); boxWrap.Position=UDim2.new(1,-12,0.5,0)
        boxWrap.Size=UDim2.fromOffset(300,28); boxWrap.BackgroundColor3=THEME.BLACK
        corner(boxWrap,10); stroke(boxWrap,1.6,THEME.GREEN)

        local tb = Instance.new("TextBox", boxWrap)
        tb.BackgroundTransparency=1; tb.Size=UDim2.fromScale(1,1); tb.Position=UDim2.new(0,8,0,0)
        tb.Font=Enum.Font.Gotham; tb.TextSize=13; tb.TextColor3=THEME.WHITE
        tb.ClearTextOnFocus=false
        tb.Text = ""
        tb.PlaceholderText = placeholder or "Paste JobId / VIP Link / roblox Link://…"
        tb.PlaceholderColor3 = Color3.fromRGB(180,180,185)
        tb.TextXAlignment = Enum.TextXAlignment.Left
        return tb
    end

    local function trim(s) return (s or ""):gsub("^%s+",""):gsub("%s+$","") end
    local function parseInputToTeleport(infoText)
        local t = trim(infoText)
        local deep_place = t:match("[?&]placeId=(%d+)")
        local deep_job   = t:match("[?&]gameInstanceId=([%w%-]+)")
        local priv_code  = t:match("[?&]privateServerLinkCode=([%w%-%_]+)")
        local priv_place = t:match("[?&]placeId=(%d+)")
        local plain_job  = t:match("(%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x)")
        if not plain_job and deep_job and #deep_job >= 32 then plain_job = deep_job end
        if priv_code then
            return { mode="private", placeId = tonumber(priv_place) or game.PlaceId, code = priv_code }
        elseif deep_job or plain_job then
            local jobId = deep_job or plain_job
            return { mode="public", placeId = tonumber(deep_place) or game.PlaceId, jobId = jobId }
        else
            return nil, "Invalid input. Please paste a JobId or VIP link (privateServerLinkCode)=...), or a roblox:// link."
        end
    end

    local inputRow = makeRow("SID_Input", "Server ID Input ", 2001)
    local inputBox = inputRow:FindFirstChildWhichIsA("Frame") and inputRow:FindFirstChildWhichIsA("Frame"):FindFirstChildOfClass("TextBox")
    if not inputBox then
        inputBox = makeRightInput(inputRow, "e.g. JobId, VIP link, or roblox link://…")
    else
        if inputBox.Text == "TextBox" then inputBox.Text = "" end
    end

    local joinRow = makeRow("SID_Join", "Join by This Server", 2002)
    if not joinRow:FindFirstChildOfClass("TextButton") then
        local joinBtn = makeActionButton(joinRow, "Join")
        joinBtn.MouseButton1Click:Connect(function()
            local raw = inputBox.Text or ""
            local target, err = parseInputToTeleport(raw)
            if not target then QuickToast(err); return end
            if target.mode=="public" and tostring(target.jobId)==tostring(game.JobId) then
                QuickToast("You are already in this server"); return
            end
            local ok, msg = false, nil
            if target.mode=="private" then
                ok, msg = pcall(function() TeleportService:TeleportToPrivateServer(target.placeId, target.code, {lp}) end)
            else
                ok, msg = pcall(function() TeleportService:TeleportToPlaceInstance(target.placeId, target.jobId, lp) end)
            end
            if not ok then
                QuickToast("Failed to Change Server ❌: "..tostring(msg))
            else
                local tip = (target.mode=="private") and ("Private Code: "..string.sub(target.code,1,6).."…")
                                                   or  ("Unique Server ID (JobId): "..string.sub(target.jobId,1,8).."…")
                QuickToast("Changing Server…  "..tip)
            end
        end)
    end

    local copyRow = makeRow("SID_Copy", "Copy Current Server ID", 2003)
    if not copyRow:FindFirstChildOfClass("TextButton") then
        local copyBtn = makeActionButton(copyRow, "Copy ID")
        copyBtn.MouseButton1Click:Connect(function()
            local id = tostring(game.JobId or "")
            local ok = pcall(function() setclipboard(id) end)
            if ok then QuickToast("Server ID Copied ✅") else QuickToast("Current Server ID: "..id) end
            if inputBox and id~="" then inputBox.Text = id end
        end)
    end
end)
--===== UFO HUB X • SETTINGS — Smoother 🚀 (A V1 • fixed 3 rows) + Runner Save (per-map) + AA1 =====
registerRight("Settings", function(scroll)
    local TweenService = game:GetService("TweenService")
    local Lighting     = game:GetService("Lighting")
    local Players      = game:GetService("Players")
    local Http         = game:GetService("HttpService")
    local MPS          = game:GetService("MarketplaceService")
    local lp           = Players.LocalPlayer

    --=================== PER-MAP SAVE (file: UFO HUB X/<PlaceId - Name>.json; fallback RAM) ===================
    local function safePlaceName()
        local ok,info = pcall(function() return MPS:GetProductInfo(game.PlaceId) end)
        local n = (ok and info and info.Name) or ("Place_"..tostring(game.PlaceId))
        return n:gsub("[^%w%-%._ ]","_")
    end
    local SAVE_DIR  = "UFO HUB X"
    local SAVE_FILE = SAVE_DIR .. "/" .. tostring(game.PlaceId) .. " - " .. safePlaceName() .. ".json"
    local hasFS = (typeof(isfolder)=="function" and typeof(makefolder)=="function"
                and typeof(readfile)=="function" and typeof(writefile)=="function")
    if hasFS and not isfolder(SAVE_DIR) then pcall(makefolder, SAVE_DIR) end
    getgenv().UFOX_RAM = getgenv().UFOX_RAM or {}
    local RAM = getgenv().UFOX_RAM

    local function loadSave()
        if hasFS and pcall(function() return readfile(SAVE_FILE) end) then
            local ok, data = pcall(function() return Http:JSONDecode(readfile(SAVE_FILE)) end)
            if ok and type(data)=="table" then return data end
        end
        return RAM[SAVE_FILE] or {}
    end
    local function writeSave(t)
        t = t or {}
        if hasFS then pcall(function() writefile(SAVE_FILE, Http:JSONEncode(t)) end) end
        RAM[SAVE_FILE] = t
    end
    local function getSave(path, default)
        local cur = loadSave()
        for seg in string.gmatch(path, "[^%.]+") do cur = (type(cur)=="table") and cur[seg] or nil end
        return (cur==nil) and default or cur
    end
    local function setSave(path, value)
        local data, p, keys = loadSave(), nil, {}
        for seg in string.gmatch(path, "[^%.]+") do table.insert(keys, seg) end
        p = data
        for i=1,#keys-1 do local k=keys[i]; if type(p[k])~="table" then p[k] = {} end; p = p[k] end
        p[keys[#keys]] = value
        writeSave(data)
    end
    --==========================================================================================================

    -- THEME (A V1)
    local THEME = {
        GREEN = Color3.fromRGB(25,255,125),
        WHITE = Color3.fromRGB(255,255,255),
        BLACK = Color3.fromRGB(0,0,0),
        TEXT  = Color3.fromRGB(255,255,255),
        RED   = Color3.fromRGB(255,40,40),
    }
    local function corner(ui,r) local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,r or 12) c.Parent=ui end
    local function stroke(ui,th,col) local s=Instance.new("UIStroke") s.Thickness=th or 2.2 s.Color=col or THEME.GREEN s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border s.Parent=ui end
    local function tween(o,p) TweenService:Create(o,TweenInfo.new(0.1,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),p):Play() end

    -- Ensure ListLayout
    local list = scroll:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout", scroll)
    list.Padding = UDim.new(0,12); list.SortOrder = Enum.SortOrder.LayoutOrder
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

    -- STATE
    _G.UFOX_SMOOTH = _G.UFOX_SMOOTH or { mode=0, plastic=false, _snap={}, _pp={} }
    local S = _G.UFOX_SMOOTH

    -- ===== restore from SAVE =====
    S.mode    = getSave("Settings.Smoother.Mode",    S.mode)      -- 0/1/2
    S.plastic = getSave("Settings.Smoother.Plastic", S.plastic)   -- boolean

    -- Header
    local head = scroll:FindFirstChild("A1_Header") or Instance.new("TextLabel", scroll)
    head.Name="A1_Header"; head.BackgroundTransparency=1; head.Size=UDim2.new(1,0,0,36)
    head.Font=Enum.Font.GothamBold; head.TextSize=16; head.TextColor3=THEME.TEXT
    head.TextXAlignment=Enum.TextXAlignment.Left; head.Text="》》》Smoothness Settings 🚀《《《"; head.LayoutOrder = 10

    -- Remove any old rows
    for _,n in ipairs({"A1_Reduce","A1_Remove","A1_Plastic"}) do local old=scroll:FindFirstChild(n); if old then old:Destroy() end end

    -- Row factory
    local function makeRow(name, label, order, onToggle)
        local row = Instance.new("Frame", scroll)
        row.Name=name; row.Size=UDim2.new(1,-6,0,46); row.BackgroundColor3=THEME.BLACK
        row.LayoutOrder=order; corner(row,12); stroke(row,2.2,THEME.GREEN)

        local lab=Instance.new("TextLabel", row)
        lab.BackgroundTransparency=1; lab.Size=UDim2.new(1,-160,1,0); lab.Position=UDim2.new(0,16,0,0)
        lab.Font=Enum.Font.GothamBold; lab.TextSize=13; lab.TextColor3=THEME.WHITE
        lab.TextXAlignment=Enum.TextXAlignment.Left; lab.Text=label

        local sw=Instance.new("Frame", row)
        sw.AnchorPoint=Vector2.new(1,0.5); sw.Position=UDim2.new(1,-12,0.5,0)
        sw.Size=UDim2.fromOffset(52,26); sw.BackgroundColor3=THEME.BLACK
        corner(sw,13)
        local swStroke=Instance.new("UIStroke", sw); swStroke.Thickness=1.8; swStroke.Color=THEME.RED

        local knob=Instance.new("Frame", sw)
        knob.Size=UDim2.fromOffset(22,22); knob.BackgroundColor3=THEME.WHITE
        knob.Position=UDim2.new(0,2,0.5,-11); corner(knob,11)

        local state=false
        local function setState(v)
            state=v
            swStroke.Color = v and THEME.GREEN or THEME.RED
            tween(knob, {Position=UDim2.new(v and 1 or 0, v and -24 or 2, 0.5, -11)})
            if onToggle then onToggle(v) end
        end
        local btn=Instance.new("TextButton", sw)
        btn.BackgroundTransparency=1; btn.Size=UDim2.fromScale(1,1); btn.Text=""
        btn.MouseButton1Click:Connect(function() setState(not state) end)

        return setState
    end

    -- ===== FX helpers (same as before) =====
    local FX = {ParticleEmitter=true, Trail=true, Beam=true, Smoke=true, Fire=true, Sparkles=true}
    local PP = {BloomEffect=true, ColorCorrectionEffect=true, DepthOfFieldEffect=true, SunRaysEffect=true, BlurEffect=true}

    local function capture(inst)
        if S._snap[inst] then return end
        local t={}; pcall(function()
            if inst:IsA("ParticleEmitter") then t.Rate=inst.Rate; t.Enabled=inst.Enabled
            elseif inst:IsA("Trail") then t.Enabled=inst.Enabled; t.Brightness=inst.Brightness
            elseif inst:IsA("Beam") then t.Enabled=inst.Enabled; t.Brightness=inst.Brightness
            elseif inst:IsA("Smoke") then t.Enabled=inst.Enabled; t.Opacity=inst.Opacity
            elseif inst:IsA("Fire") then t.Enabled=inst.Enabled; t.Heat=inst.Heat; t.Size=inst.Size
            elseif inst:IsA("Sparkles") then t.Enabled=inst.Enabled end
        end)
        S._snap[inst]=t
    end
    for _,d in ipairs(workspace:GetDescendants()) do if FX[d.ClassName] then capture(d) end end

    local function applyHalf()
        for i,t in pairs(S._snap) do if i.Parent then pcall(function()
            if i:IsA("ParticleEmitter") then i.Rate=(t.Rate or 10)*0.5
            elseif i:IsA("Trail") or i:IsA("Beam") then i.Brightness=(t.Brightness or 1)*0.5
            elseif i:IsA("Smoke") then i.Opacity=(t.Opacity or 1)*0.5
            elseif i:IsA("Fire") then i.Heat=(t.Heat or 5)*0.5; i.Size=(t.Size or 5)*0.7
            elseif i:IsA("Sparkles") then i.Enabled=false end
        end) end end
        for _,obj in ipairs(Lighting:GetChildren()) do
            if PP[obj.ClassName] then
                S._pp[obj]={Enabled=obj.Enabled, Intensity=obj.Intensity, Size=obj.Size}
                obj.Enabled=true; if obj.Intensity then obj.Intensity=(obj.Intensity or 1)*0.5 end
                if obj.ClassName=="BlurEffect" and obj.Size then obj.Size=math.floor((obj.Size or 0)*0.5) end
            end
        end
    end
    local function applyOff()
        for i,_ in pairs(S._snap) do if i.Parent then pcall(function() i.Enabled=false end) end end
        for _,obj in ipairs(Lighting:GetChildren()) do if PP[obj.ClassName] then obj.Enabled=false end end
    end
    local function restoreAll()
        for i,t in pairs(S._snap) do if i.Parent then for k,v in pairs(t) do pcall(function() i[k]=v end) end end end
        for obj,t in pairs(S._pp)   do if obj.Parent then for k,v in pairs(t) do pcall(function() obj[k]=v end) end end end
    end

    local function plasticMode(on)
        for _,p in ipairs(workspace:GetDescendants()) do
            if p:IsA("BasePart") and not p:IsDescendantOf(lp.Character) then
                if on then
                    if not p:GetAttribute("Mat0") then p:SetAttribute("Mat0",p.Material.Name); p:SetAttribute("Refl0",p.Reflectance) end
                    p.Material=Enum.Material.SmoothPlastic; p.Reflectance=0
                else
                    local m=p:GetAttribute("Mat0"); local r=p:GetAttribute("Refl0")
                    if m then pcall(function() p.Material=Enum.Material[m] end) p:SetAttribute("Mat0",nil) end
                    if r~=nil then p.Reflectance=r; p:SetAttribute("Refl0",nil) end
                end
            end
        end
    end

    -- ===== 3 switches (fixed orders 11/12/13) + SAVE =====
    local set50, set100, setPl

    set50  = makeRow("A1_Reduce", "Reduce Effects 50%", 11, function(v)
        if v then
            S.mode=1; applyHalf()
            if set100 then set100(false) end
        else
            if S.mode==1 then S.mode=0; restoreAll() end
        end
        setSave("Settings.Smoother.Mode", S.mode)
    end)

    set100 = makeRow("A1_Remove", "Remove Effects 100%", 12, function(v)
        if v then
            S.mode=2; applyOff()
            if set50 then set50(false) end
        else
            if S.mode==2 then S.mode=0; restoreAll() end
        end
        setSave("Settings.Smoother.Mode", S.mode)
    end)

    setPl   = makeRow("A1_Plastic","Change Map to Plastic)", 13, function(v)
        S.plastic=v; plasticMode(v)
        setSave("Settings.Smoother.Plastic", v)
    end)

    -- ===== Apply restored saved state to UI/World =====
    if S.mode==1 then
        set50(true)
    elseif S.mode==2 then
        set100(true)
    else
        set50(false); set100(false); restoreAll()
    end
    setPl(S.plastic)
end)

-- ########## AA1 — Auto-run Smoother from SaveState (ไม่ต้องกดปุ่ม UI) ##########
task.defer(function()
    local TweenService = game:GetService("TweenService")
    local Lighting     = game:GetService("Lighting")
    local Players      = game:GetService("Players")
    local Http         = game:GetService("HttpService")
    local MPS          = game:GetService("MarketplaceService")
    local lp           = Players.LocalPlayer

    -- ใช้ SAVE เดิมแบบเดียวกับด้านบน
    local function safePlaceName()
        local ok,info = pcall(function() return MPS:GetProductInfo(game.PlaceId) end)
        local n = (ok and info and info.Name) or ("Place_"..tostring(game.PlaceId))
        return n:gsub("[^%w%-%._ ]","_")
    end
    local SAVE_DIR  = "UFO HUB X"
    local SAVE_FILE = SAVE_DIR .. "/" .. tostring(game.PlaceId) .. " - " .. safePlaceName() .. ".json"
    local hasFS = (typeof(isfolder)=="function" and typeof(makefolder)=="function"
                and typeof(readfile)=="function" and typeof(writefile)=="function")
    if hasFS and not isfolder(SAVE_DIR) then pcall(makefolder, SAVE_DIR) end
    getgenv().UFOX_RAM = getgenv().UFOX_RAM or {}
    local RAM = getgenv().UFOX_RAM

    local function loadSave()
        if hasFS and pcall(function() return readfile(SAVE_FILE) end) then
            local ok, data = pcall(function() return Http:JSONDecode(readfile(SAVE_FILE)) end)
            if ok and type(data)=="table" then return data end
        end
        return RAM[SAVE_FILE] or {}
    end
    local function getSave(path, default)
        local cur = loadSave()
        for seg in string.gmatch(path, "[^%.]+") do cur = (type(cur)=="table") and cur[seg] or nil end
        return (cur==nil) and default or cur
    end

    -- ใช้ state เดียวกับ UI
    _G.UFOX_SMOOTH = _G.UFOX_SMOOTH or { mode=0, plastic=false, _snap={}, _pp={} }
    local S = _G.UFOX_SMOOTH

    local FX = {ParticleEmitter=true, Trail=true, Beam=true, Smoke=true, Fire=true, Sparkles=true}
    local PP = {BloomEffect=true, ColorCorrectionEffect=true, DepthOfFieldEffect=true, SunRaysEffect=true, BlurEffect=true}

    local function capture(inst)
        if S._snap[inst] then return end
        local t={}; pcall(function()
            if inst:IsA("ParticleEmitter") then t.Rate=inst.Rate; t.Enabled=inst.Enabled
            elseif inst:IsA("Trail") then t.Enabled=inst.Enabled; t.Brightness=inst.Brightness
            elseif inst:IsA("Beam") then t.Enabled=inst.Enabled; t.Brightness=inst.Brightness
            elseif inst:IsA("Smoke") then t.Enabled=inst.Enabled; t.Opacity=inst.Opacity
            elseif inst:IsA("Fire") then t.Enabled=inst.Enabled; t.Heat=inst.Heat; t.Size=inst.Size
            elseif inst:IsA("Sparkles") then t.Enabled=inst.Enabled end
        end)
        S._snap[inst]=t
    end
    for _,d in ipairs(workspace:GetDescendants()) do
        if FX[d.ClassName] then capture(d) end
    end

    local function applyHalf()
        for i,t in pairs(S._snap) do
            if i.Parent then pcall(function()
                if i:IsA("ParticleEmitter") then i.Rate=(t.Rate or 10)*0.5
                elseif i:IsA("Trail") or i:IsA("Beam") then i.Brightness=(t.Brightness or 1)*0.5
                elseif i:IsA("Smoke") then i.Opacity=(t.Opacity or 1)*0.5
                elseif i:IsA("Fire") then i.Heat=(t.Heat or 5)*0.5; i.Size=(t.Size or 5)*0.7
                elseif i:IsA("Sparkles") then i.Enabled=false end
            end) end
        end
        for _,obj in ipairs(Lighting:GetChildren()) do
            if PP[obj.ClassName] then
                S._pp[obj] = S._pp[obj] or {}
                local snap = S._pp[obj]
                if snap.Enabled == nil then
                    snap.Enabled = obj.Enabled
                    if obj.Intensity ~= nil then snap.Intensity = obj.Intensity end
                    if obj.ClassName=="BlurEffect" and obj.Size then snap.Size = obj.Size end
                end
                obj.Enabled = true
                if obj.Intensity and snap.Intensity ~= nil then
                    obj.Intensity = (snap.Intensity or obj.Intensity or 1)*0.5
                end
                if obj.ClassName=="BlurEffect" and obj.Size and snap.Size ~= nil then
                    obj.Size = math.floor((snap.Size or obj.Size or 0)*0.5)
                end
            end
        end
    end

    local function applyOff()
        for i,_ in pairs(S._snap) do
            if i.Parent then pcall(function() i.Enabled=false end) end
        end
        for _,obj in ipairs(Lighting:GetChildren()) do
            if PP[obj.ClassName] then obj.Enabled=false end
        end
    end

    local function restoreAll()
        for i,t in pairs(S._snap) do
            if i.Parent then
                for k,v in pairs(t) do pcall(function() i[k]=v end) end
            end
        end
        for obj,t in pairs(S._pp) do
            if obj.Parent then
                for k,v in pairs(t) do pcall(function() obj[k]=v end) end
            end
        end
    end

    local function plasticMode(on)
        for _,p in ipairs(workspace:GetDescendants()) do
            if p:IsA("BasePart") and not p:IsDescendantOf(lp.Character) then
                if on then
                    if not p:GetAttribute("Mat0") then
                        p:SetAttribute("Mat0", p.Material.Name)
                        p:SetAttribute("Refl0", p.Reflectance)
                    end
                    p.Material = Enum.Material.SmoothPlastic
                    p.Reflectance = 0
                else
                    local m = p:GetAttribute("Mat0")
                    local r = p:GetAttribute("Refl0")
                    if m then pcall(function() p.Material = Enum.Material[m] end); p:SetAttribute("Mat0", nil) end
                    if r ~= nil then p.Reflectance = r; p:SetAttribute("Refl0", nil) end
                end
            end
        end
    end

    -- อ่าน SaveState แล้ว apply อัตโนมัติ (AA1)
    local mode    = getSave("Settings.Smoother.Mode",    S.mode or 0)
    local plastic = getSave("Settings.Smoother.Plastic", S.plastic or false)
    S.mode    = mode
    S.plastic = plastic

    if mode == 1 then
        applyHalf()
    elseif mode == 2 then
        applyOff()
    else
        restoreAll()
    end
    plasticMode(plastic)
end)
-- ===== UFO HUB X • Settings — AFK 💤 (MODEL A LEGACY, full systems) + Runner Save + AA1 =====
-- 1) Black Screen (Performance AFK)  [toggle]
-- 2) White Screen (Performance AFK)  [toggle]
-- 3) AFK Anti-Kick (20 min)          [toggle default ON]
-- 4) Activity Watcher (5 min → enable #3) [toggle default ON]
-- + AA1: Auto-run จาก SaveState โดยตรง ไม่ต้องแตะ UI

-- ########## SERVICES ##########
local Players       = game:GetService("Players")
local TweenService  = game:GetService("TweenService")
local UIS           = game:GetService("UserInputService")
local RunService    = game:GetService("RunService")
local VirtualUser   = game:GetService("VirtualUser")
local Http          = game:GetService("HttpService")
local MPS           = game:GetService("MarketplaceService")
local lp            = Players.LocalPlayer

-- ########## PER-MAP SAVE (file + RAM fallback) ##########
local function safePlaceName()
    local ok,info = pcall(function() return MPS:GetProductInfo(game.PlaceId) end)
    local n = (ok and info and info.Name) or ("Place_"..tostring(game.PlaceId))
    return n:gsub("[^%w%-%._ ]","_")
end

local SAVE_DIR  = "UFO HUB X"
local SAVE_FILE = SAVE_DIR.."/"..tostring(game.PlaceId).." - "..safePlaceName()..".json"

local hasFS = (typeof(isfolder)=="function" and typeof(makefolder)=="function"
            and typeof(writefile)=="function" and typeof(readfile)=="function")

if hasFS and not isfolder(SAVE_DIR) then pcall(makefolder, SAVE_DIR) end

getgenv().UFOX_RAM = getgenv().UFOX_RAM or {}
local RAM = getgenv().UFOX_RAM

local function loadSave()
    if hasFS and pcall(function() return readfile(SAVE_FILE) end) then
        local ok,dec = pcall(function() return Http:JSONDecode(readfile(SAVE_FILE)) end)
        if ok and type(dec)=="table" then return dec end
    end
    return RAM[SAVE_FILE] or {}
end

local function writeSave(t)
    t = t or {}
    if hasFS then
        pcall(function()
            writefile(SAVE_FILE, Http:JSONEncode(t))
        end)
    end
    RAM[SAVE_FILE] = t
end

local function getSave(path, default)
    local data = loadSave()
    local cur  = data
    for seg in string.gmatch(path,"[^%.]+") do
        cur = (type(cur)=="table") and cur[seg] or nil
    end
    return (cur==nil) and default or cur
end

local function setSave(path, value)
    local data = loadSave()
    local keys = {}
    for seg in string.gmatch(path,"[^%.]+") do table.insert(keys, seg) end
    local p = data
    for i=1,#keys-1 do
        local k = keys[i]
        if type(p[k])~="table" then p[k] = {} end
        p = p[k]
    end
    p[keys[#keys]] = value
    writeSave(data)
end

-- ########## THEME / HELPERS ##########
local THEME = {
    GREEN = Color3.fromRGB(25,255,125),
    RED   = Color3.fromRGB(255,40,40),
    WHITE = Color3.fromRGB(255,255,255),
    BLACK = Color3.fromRGB(0,0,0),
    TEXT  = Color3.fromRGB(255,255,255),
}

local function corner(ui,r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0,r or 12)
    c.Parent = ui
end

local function stroke(ui,th,col)
    local s = Instance.new("UIStroke")
    s.Thickness = th or 2.2
    s.Color = col or THEME.GREEN
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = ui
end

local function tween(o,p)
    TweenService:Create(o, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), p):Play()
end

-- ########## GLOBAL AFK STATE ##########
_G.UFOX_AFK = _G.UFOX_AFK or {
    blackOn    = false,
    whiteOn    = false,
    antiIdleOn = true,   -- default ON
    watcherOn  = true,   -- default ON
    lastInput  = tick(),
    antiIdleLoop = nil,
    idleHooked   = false,
    gui          = nil,
    watcherConn  = nil,
    inputConns   = {},
}

local S = _G.UFOX_AFK

-- ===== restore from SAVE → override defaults =====
S.blackOn    = getSave("Settings.AFK.Black",    S.blackOn)
S.whiteOn    = getSave("Settings.AFK.White",    S.whiteOn)
S.antiIdleOn = getSave("Settings.AFK.AntiKick", S.antiIdleOn)
S.watcherOn  = getSave("Settings.AFK.Watcher",  S.watcherOn)

-- ########## CORE: OVERLAY (Black / White) ##########
local function ensureGui()
    if S.gui and S.gui.Parent then return S.gui end
    local gui = Instance.new("ScreenGui")
    gui.Name="UFOX_AFK_GUI"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn   = false
    gui.DisplayOrder   = 999999
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = lp:WaitForChild("PlayerGui")
    S.gui = gui
    return gui
end

local function clearOverlay(name)
    if S.gui then
        local f = S.gui:FindFirstChild(name)
        if f then f:Destroy() end
    end
end

local function showBlack(v)
    clearOverlay("WhiteOverlay")
    clearOverlay("BlackOverlay")
    if not v then return end
    local gui = ensureGui()
    local black = Instance.new("Frame", gui)
    black.Name = "BlackOverlay"
    black.BackgroundColor3 = Color3.new(0,0,0)
    black.Size = UDim2.fromScale(1,1)
    black.ZIndex = 200
    black.Active = true
end

local function showWhite(v)
    clearOverlay("BlackOverlay")
    clearOverlay("WhiteOverlay")
    if not v then return end
    local gui = ensureGui()
    local white = Instance.new("Frame", gui)
    white.Name = "WhiteOverlay"
    white.BackgroundColor3 = Color3.new(1,1,1)
    white.Size = UDim2.fromScale(1,1)
    white.ZIndex = 200
    white.Active = true
end

local function syncOverlays()
    if S.blackOn then
        S.whiteOn = false
        showWhite(false)
        showBlack(true)
    elseif S.whiteOn then
        S.blackOn = false
        showBlack(false)
        showWhite(true)
    else
        showBlack(false)
        showWhite(false)
    end
end

-- ########## CORE: Anti-Kick / Activity ##########
local function pulseOnce()
    local cam = workspace.CurrentCamera
    local cf  = cam and cam.CFrame or CFrame.new()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0,0), cf)
    end)
end

local function startAntiIdle()
    if S.antiIdleLoop then return end
    S.antiIdleLoop = task.spawn(function()
        while S.antiIdleOn do
            pulseOnce()
            for i=1,540 do  -- ~9 นาที (ตรงกับค่าเดิม)
                if not S.antiIdleOn then break end
                task.wait(1)
            end
        end
        S.antiIdleLoop = nil
    end)
end

-- hook Roblox Idle แค่ครั้งเดียว (เหมือนเดิม แต่ global)
if not S.idleHooked then
    S.idleHooked = true
    lp.Idled:Connect(function()
        if S.antiIdleOn then
            pulseOnce()
        end
    end)
end

-- input watcher (mouse/keyboard/touch) → update lastInput
local function ensureInputHooks()
    if S.inputConns and #S.inputConns > 0 then return end
    local function markInput() S.lastInput = tick() end
    table.insert(S.inputConns, UIS.InputBegan:Connect(markInput))
    table.insert(S.inputConns, UIS.InputChanged:Connect(function(io)
        if io.UserInputType ~= Enum.UserInputType.MouseWheel then
            markInput()
        end
    end))
end

local INACTIVE = 5*60 -- 5 นาที
local function startWatcher()
    if S.watcherConn then return end
    S.watcherConn = RunService.Heartbeat:Connect(function()
        if not S.watcherOn then return end
        if tick() - S.lastInput >= INACTIVE then
            -- เปิด Anti-Kick อัตโนมัติ (เหมือนเดิม)
            S.antiIdleOn = true
            setSave("Settings.AFK.AntiKick", true)
            if not S.antiIdleLoop then startAntiIdle() end
            pulseOnce()
            S.lastInput = tick()
        end
    end)
end

-- ########## AA1: AUTO-RUN จาก SaveState (ไม่ต้องแตะ UI) ##########
task.defer(function()
    -- sync หน้าจอ AFK (black/white) ตามค่าที่เซฟไว้
    syncOverlays()

    -- ถ้า Anti-Kick ON → start loop ให้เลย
    if S.antiIdleOn then
        startAntiIdle()
    end

    -- watcher & input hooks (ดูการขยับทุก 5 นาทีเหมือนเดิม)
    ensureInputHooks()
    startWatcher()
end)

-- ########## UI ฝั่งขวา (MODEL A LEGACY • เหมือนเดิม) ##########
registerRight("Settings", function(scroll)
    -- ลบ section เก่า (ถ้ามี)
    local old = scroll:FindFirstChild("Section_AFK_Preview"); if old then old:Destroy() end
    local old2 = scroll:FindFirstChild("Section_AFK_Full");  if old2 then old2:Destroy() end

    -- layout เดิม
    local vlist = scroll:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout", scroll)
    vlist.Padding = UDim.new(0,12)
    vlist.SortOrder = Enum.SortOrder.LayoutOrder
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

    local nextOrder = 10
    for _,ch in ipairs(scroll:GetChildren()) do
        if ch:IsA("GuiObject") and ch ~= vlist then
            nextOrder = math.max(nextOrder, (ch.LayoutOrder or 0)+1)
        end
    end

    -- Header
    local header = Instance.new("TextLabel", scroll)
    header.Name = "Section_AFK_Full"
    header.BackgroundTransparency = 1
    header.Size = UDim2.new(1,0,0,36)
    header.Font = Enum.Font.GothamBold
    header.TextSize = 16
    header.TextColor3 = THEME.TEXT
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Text = "》》》AFK 💤《《《"
    header.LayoutOrder = nextOrder

    -- Row helper (เหมือนโค้ดเดิม)
    local function makeRow(textLabel, defaultOn, onToggle)
        local row = Instance.new("Frame", scroll)
        row.Size = UDim2.new(1,-6,0,46)
        row.BackgroundColor3 = THEME.BLACK
        corner(row,12)
        stroke(row,2.2,THEME.GREEN)
        row.LayoutOrder = header.LayoutOrder + 1

        local lab = Instance.new("TextLabel", row)
        lab.BackgroundTransparency = 1
        lab.Size = UDim2.new(1,-160,1,0)
        lab.Position = UDim2.new(0,16,0,0)
        lab.Font = Enum.Font.GothamBold
        lab.TextSize = 13
        lab.TextColor3 = THEME.WHITE
        lab.TextXAlignment = Enum.TextXAlignment.Left
        lab.Text = textLabel

        local sw = Instance.new("Frame", row)
        sw.AnchorPoint = Vector2.new(1,0.5)
        sw.Position = UDim2.new(1,-12,0.5,0)
        sw.Size = UDim2.fromOffset(52,26)
        sw.BackgroundColor3 = THEME.BLACK
        corner(sw,13)

        local swStroke = Instance.new("UIStroke", sw)
        swStroke.Thickness = 1.8
        swStroke.Color = defaultOn and THEME.GREEN or THEME.RED

        local knob = Instance.new("Frame", sw)
        knob.Size = UDim2.fromOffset(22,22)
        knob.Position = UDim2.new(defaultOn and 1 or 0, defaultOn and -24 or 2, 0.5, -11)
        knob.BackgroundColor3 = THEME.WHITE
        corner(knob,11)

        local state = defaultOn
        local function setState(v)
            state = v
            swStroke.Color = v and THEME.GREEN or THEME.RED
            tween(knob, {Position = UDim2.new(v and 1 or 0, v and -24 or 2, 0.5, -11)})
            if onToggle then onToggle(v) end
        end

        local btn = Instance.new("TextButton", sw)
        btn.BackgroundTransparency = 1
        btn.Size = UDim2.fromScale(1,1)
        btn.Text = ""
        btn.AutoButtonColor = false
        btn.MouseButton1Click:Connect(function()
            setState(not state)
        end)

        return setState
    end

    -- ===== Rows + bindings (ใช้ STATE เดิม + SAVE + CORE) =====
    local setBlack = makeRow("Black Screen (Performance AFK)", S.blackOn, function(v)
        S.blackOn = v
        if v then S.whiteOn = false end
        syncOverlays()
        setSave("Settings.AFK.Black", v)
        if v == true then
            setSave("Settings.AFK.White", false)
        end
    end)

    local setWhite = makeRow("White Screen (Performance AFK)", S.whiteOn, function(v)
        S.whiteOn = v
        if v then S.blackOn = false end
        syncOverlays()
        setSave("Settings.AFK.White", v)
        if v == true then
            setSave("Settings.AFK.Black", false)
        end
    end)

    local setAnti  = makeRow("AFK Anti-Kick (20 min)", S.antiIdleOn, function(v)
        S.antiIdleOn = v
        setSave("Settings.AFK.AntiKick", v)
        if v then
            startAntiIdle()
        end
    end)

    local setWatch = makeRow("Activity Watcher (5 min → enable #3)", S.watcherOn, function(v)
        S.watcherOn = v
        setSave("Settings.AFK.Watcher", v)
        -- watcher loop จะเช็ค S.watcherOn อยู่แล้ว
    end)

    -- ===== Init เมื่อเปิดแท็บ Settings (ให้ตรงกับสถานะจริง) =====
    syncOverlays()
    if S.antiIdleOn then
        startAntiIdle()
    end
    ensureInputHooks()
    startWatcher()
end)
---- ========== ผูกปุ่มแท็บ + เปิดแท็บแรก ==========
local tabs = {
    {btn = btnPlayer,   set = setPlayerActive,   name = "Player",   icon = ICON_PLAYER},
    {btn = btnHome,     set = setHomeActive,     name = "Home",     icon = ICON_HOME},
    {btn = btnQuest,    set = setQuestActive,    name = "Quest",    icon = ICON_QUEST},
    {btn = btnShop,     set = setShopActive,     name = "Shop",     icon = ICON_SHOP},
    {btn = btnUpdate,   set = setUpdateActive,   name = "Update",   icon = ICON_UPDATE},
    {btn = btnServer,   set = setServerActive,   name = "Server",   icon = ICON_SERVER},
    {btn = btnSettings, set = setSettingsActive, name = "Settings", icon = ICON_SETTINGS},
}

local function activateTab(t)
    -- จดตำแหน่งสกอร์ลซ้ายไว้ก่อน (กันเด้ง)
    lastLeftY = LeftScroll.CanvasPosition.Y
    for _,x in ipairs(tabs) do x.set(x == t) end
    showRight(t.name, t.icon)
    task.defer(function()
        refreshLeftCanvas()
        local viewH = LeftScroll.AbsoluteSize.Y
        local maxY  = math.max(0, LeftScroll.CanvasSize.Y.Offset - viewH)
        LeftScroll.CanvasPosition = Vector2.new(0, math.clamp(lastLeftY,0,maxY))
        -- ถ้าปุ่มอยู่นอกเฟรม ค่อยเลื่อนให้อยู่พอดี
        local btn = t.btn
        if btn and btn.Parent then
            local top = btn.AbsolutePosition.Y - LeftScroll.AbsolutePosition.Y
            local bot = top + btn.AbsoluteSize.Y
            local pad = 8
            if top < 0 then
                LeftScroll.CanvasPosition = LeftScroll.CanvasPosition + Vector2.new(0, top - pad)
            elseif bot > viewH then
                LeftScroll.CanvasPosition = LeftScroll.CanvasPosition + Vector2.new(0, (bot - viewH) + pad)
            end
            lastLeftY = LeftScroll.CanvasPosition.Y
        end
    end)
end

for _,t in ipairs(tabs) do
    t.btn.MouseButton1Click:Connect(function() activateTab(t) end)
end

-- เปิดด้วยแท็บแรก
activateTab(tabs[1])

-- ===== Start visible & sync toggle to this UI =====
setOpen(true)

-- ===== Rebind close buttons inside this UI (กันกรณีชื่อ X หลายตัว) =====
for _,o in ipairs(GUI:GetDescendants()) do
    if o:IsA("TextButton") and (o.Text or ""):upper()=="X" then
        o.MouseButton1Click:Connect(function() setOpen(false) end)
    end
end

-- ===== Auto-rebind ถ้า UI หลักถูกสร้างใหม่ภายหลัง =====
local function hookContainer(container)
    if not container then return end
    container.ChildAdded:Connect(function(child)
        if child.Name=="UFO_HUB_X_UI" then
            task.wait() -- ให้ลูกพร้อม
            for _,o in ipairs(child:GetDescendants()) do
                if o:IsA("TextButton") and (o.Text or ""):upper()=="X" then
                    o.MouseButton1Click:Connect(function() setOpen(false) end)
                end
            end
        end
    end)
end
hookContainer(CoreGui)
local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
hookContainer(pg)

end -- <<== จบ _G.UFO_ShowMainUI() (โค้ด UI หลักของคุณแบบ 100%)

------------------------------------------------------------
-- 2) Toast chain (2-step) • โผล่ Step2 พร้อมกับ UI หลัก แล้วเลือนหาย
------------------------------------------------------------
do
    -- ล้าง Toast เก่า (ถ้ามี)
    pcall(function()
        local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
        for _,n in ipairs({"UFO_Toast_Test","UFO_Toast_Test_2"}) do
            local g = pg:FindFirstChild(n); if g then g:Destroy() end
        end
    end)

    -- CONFIG
    local EDGE_RIGHT_PAD, EDGE_BOTTOM_PAD = 2, 2
    local TOAST_W, TOAST_H = 320, 86
    local RADIUS, STROKE_TH = 10, 2
    local GREEN = Color3.fromRGB(0,255,140)
    local BLACK = Color3.fromRGB(10,10,10)
    local LOGO_STEP1 = "rbxassetid://89004973470552"
    local LOGO_STEP2 = "rbxassetid://83753985156201"
    local TITLE_TOP, MSG_TOP = 12, 34
    local BAR_LEFT, BAR_RIGHT_PAD, BAR_H = 68, 12, 10
    local LOAD_TIME = 2.0

    local TS = game:GetService("TweenService")
    local RunS = game:GetService("RunService")
    local PG = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

    local function tween(inst, ti, ease, dir, props)
        return TS:Create(inst, TweenInfo.new(ti, ease or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
    end
    local function makeToastGui(name)
        local gui = Instance.new("ScreenGui")
        gui.Name = name
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 999999
        gui.Parent = PG
        return gui
    end
    local function buildBox(parent)
        local box = Instance.new("Frame")
        box.Name = "Toast"
        box.AnchorPoint = Vector2.new(1,1)
        box.Position = UDim2.new(1, -EDGE_RIGHT_PAD, 1, -(EDGE_BOTTOM_PAD - 24))
        box.Size = UDim2.fromOffset(TOAST_W, TOAST_H)
        box.BackgroundColor3 = BLACK
        box.BorderSizePixel = 0
        box.Parent = parent
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, RADIUS)
        local stroke = Instance.new("UIStroke", box)
        stroke.Thickness = STROKE_TH
        stroke.Color = GREEN
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.LineJoinMode = Enum.LineJoinMode.Round
        return box
    end
    local function buildTitle(box)
        local title = Instance.new("TextLabel")
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBold
        title.RichText = true
        title.Text = '<font color="#FFFFFF">UFO</font> <font color="#00FF8C">HUB X</font>'
        title.TextSize = 18
        title.TextColor3 = Color3.fromRGB(235,235,235)
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Position = UDim2.fromOffset(68, TITLE_TOP)
        title.Size = UDim2.fromOffset(TOAST_W - 78, 20)
        title.Parent = box
        return title
    end
    local function buildMsg(box, text)
        local msg = Instance.new("TextLabel")
        msg.BackgroundTransparency = 1
        msg.Font = Enum.Font.Gotham
        msg.Text = text
        msg.TextSize = 13
        msg.TextColor3 = Color3.fromRGB(200,200,200)
        msg.TextXAlignment = Enum.TextXAlignment.Left
        msg.Position = UDim2.fromOffset(68, MSG_TOP)
        msg.Size = UDim2.fromOffset(TOAST_W - 78, 18)
        msg.Parent = box
        return msg
    end
    local function buildLogo(box, imageId)
        local logo = Instance.new("ImageLabel")
        logo.BackgroundTransparency = 1
        logo.Image = imageId
        logo.Size = UDim2.fromOffset(54, 54)
        logo.AnchorPoint = Vector2.new(0, 0.5)
        logo.Position = UDim2.new(0, 8, 0.5, -2)
        logo.Parent = box
        return logo
    end

    -- Step 1 (progress)
    local gui1 = makeToastGui("UFO_Toast_Test")
    local box1 = buildBox(gui1)
    buildLogo(box1, LOGO_STEP1)
    buildTitle(box1)
    local msg1 = buildMsg(box1, "Initializing... please wait")

    local barWidth = TOAST_W - BAR_LEFT - BAR_RIGHT_PAD
    local track = Instance.new("Frame"); track.BackgroundColor3 = Color3.fromRGB(25,25,25); track.BorderSizePixel = 0
    track.Position = UDim2.fromOffset(BAR_LEFT, TOAST_H - (BAR_H + 12))
    track.Size = UDim2.fromOffset(barWidth, BAR_H); track.Parent = box1
    Instance.new("UICorner", track).CornerRadius = UDim.new(0, BAR_H // 2)

    local fill = Instance.new("Frame"); fill.BackgroundColor3 = GREEN; fill.BorderSizePixel = 0
    fill.Size = UDim2.fromOffset(0, BAR_H); fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, BAR_H // 2)

    local pct = Instance.new("TextLabel")
    pct.BackgroundTransparency = 1; pct.Font = Enum.Font.GothamBold; pct.TextSize = 12
    pct.TextColor3 = Color3.new(1,1,1); pct.TextStrokeTransparency = 0.15; pct.TextStrokeColor3 = Color3.new(0,0,0)
    pct.TextXAlignment = Enum.TextXAlignment.Center; pct.TextYAlignment = Enum.TextYAlignment.Center
    pct.AnchorPoint = Vector2.new(0.5,0.5); pct.Position = UDim2.fromScale(0.5,0.5); pct.Size = UDim2.fromScale(1,1)
    pct.Text = "0%"; pct.ZIndex = 20; pct.Parent = track

    tween(box1, 0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out,
        {Position = UDim2.new(1, -EDGE_RIGHT_PAD, 1, -EDGE_BOTTOM_PAD)}):Play()

    task.spawn(function()
        local t0 = time()
        local progress = 0
        while progress < 100 do
            progress = math.clamp(math.floor(((time() - t0)/LOAD_TIME)*100 + 0.5), 0, 100)
            fill.Size = UDim2.fromOffset(math.floor(barWidth*(progress/100)), BAR_H)
            pct.Text = progress .. "%"
            RunS.Heartbeat:Wait()
        end
        msg1.Text = "Loaded successfully."
        task.wait(0.25)
        local out1 = tween(box1, 0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut,
            {Position = UDim2.new(1, -EDGE_RIGHT_PAD, 1, -(EDGE_BOTTOM_PAD - 24))})
        out1:Play(); out1.Completed:Wait(); gui1:Destroy()

        -- Step 2 (no progress) + เปิด UI หลักพร้อมกัน
        local gui2 = makeToastGui("UFO_Toast_Test_2")
        local box2 = buildBox(gui2)
        buildLogo(box2, LOGO_STEP2)
        buildTitle(box2)
        buildMsg(box2, "Download UI completed. ✅")
        tween(box2, 0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out,
            {Position = UDim2.new(1, -EDGE_RIGHT_PAD, 1, -EDGE_BOTTOM_PAD)}):Play()

        -- เปิด UI หลัก "พร้อมกัน" กับ Toast ขั้นที่ 2
        if _G.UFO_ShowMainUI then pcall(_G.UFO_ShowMainUI) end

        -- ให้ผู้ใช้เห็นข้อความครบ แล้วค่อยเลือนลง (ปรับเวลาได้ตามใจ)
        task.wait(1.2)
        local out2 = tween(box2, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut,
            {Position = UDim2.new(1, -EDGE_RIGHT_PAD, 1, -(EDGE_BOTTOM_PAD - 24))})
        out2:Play(); out2.Completed:Wait(); gui2:Destroy()
    end)
end
-- ==== mark boot done (lock forever until reset) ====
do
    local B = getgenv().UFO_BOOT or {}
    B.status = "done"
    getgenv().UFO_BOOT = B
end
