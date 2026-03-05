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
local TOGGLE_ICON = "rbxassetid://86955640536661"

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

--===== UFO HUB X • Home • MAX999 + MAX1/2 Switches =====
registerRight("Home", function(scroll)
    local TweenService = game:GetService("TweenService")

    ------------------------------------------------------------------------
    -- THEME
    ------------------------------------------------------------------------
    local THEME = {
        GREEN = Color3.fromRGB(25,255,125),
        RED   = Color3.fromRGB(255,40,40),
        WHITE = Color3.fromRGB(255,255,255),
        BLACK = Color3.fromRGB(0,0,0),
    }

    ------------------------------------------------------------------------
    -- Helper Tween
    ------------------------------------------------------------------------
    local function tween(o,p,d)
        TweenService:Create(o,TweenInfo.new(d or 0.08,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),p):Play()
    end

    ------------------------------------------------------------------------
    -- UIListLayout
    ------------------------------------------------------------------------
    local vlist = scroll:FindFirstChildOfClass("UIListLayout")
    if not vlist then
        vlist = Instance.new("UIListLayout")
        vlist.Parent = scroll
        vlist.Padding = UDim.new(0,12)
        vlist.SortOrder = Enum.SortOrder.LayoutOrder
    end
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

    local base=0
    for _,ch in ipairs(scroll:GetChildren()) do
        if ch:IsA("GuiObject") and ch ~= vlist then
            base = math.max(base,ch.LayoutOrder or 0)
        end
    end

    ------------------------------------------------------------------------
    -- MAX999 Parent Switch
    ------------------------------------------------------------------------
    local MAXState=false
    local MAXRow,MAXArrow
    local MAXChildren={}

    local function makeParentArrowSwitch(name,order,labelText,getState,setState)
        local row=Instance.new("Frame")
        row.Name=name
        row.Parent=scroll
        row.Size=UDim2.new(1,-6,0,50)
        row.BackgroundColor3=THEME.BLACK
        -- กรอบสี่เหลี่ยมตรงๆ
        local s=Instance.new("UIStroke")
        s.Thickness=3
        s.Color=THEME.GREEN
        s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
        s.Parent=row
        row.LayoutOrder=order

        local lab=Instance.new("TextLabel")
        lab.Parent=row
        lab.BackgroundTransparency=1
        lab.Size=UDim2.new(1,-60,1,0)
        lab.Position=UDim2.new(0,16,0,0)
        lab.Font=Enum.Font.GothamBold
        lab.TextSize=16
        lab.TextColor3=THEME.WHITE
        lab.TextXAlignment=Enum.TextXAlignment.Left
        lab.Text="》》》"..labelText.."《《《"

        local arrow=Instance.new("TextLabel")
        arrow.Parent=row
        arrow.BackgroundTransparency=1
        arrow.Size=UDim2.new(0,28,0,28)
        arrow.Position=UDim2.new(1,-28,0.5,0)
        arrow.Font=Enum.Font.GothamBold
        arrow.TextSize=26
        arrow.TextColor3=THEME.WHITE
        arrow.Text="▶"
        arrow.AnchorPoint=Vector2.new(0.5,0.5)

        local function update(on)
            arrow.Text=on and "▼" or "▶"
        end

        local btn=Instance.new("TextButton")
        btn.Parent=row
        btn.BackgroundTransparency=1
        btn.Size=UDim2.fromScale(1,1)
        btn.Text=""
        btn.AutoButtonColor=false
        btn.MouseButton1Click:Connect(function()
            local new=not getState()
            setState(new)
            update(new)
            -- แสดง/ซ่อน MAXChildren
            for _,c in ipairs(MAXChildren) do
                c.Visible=new
            end
        end)

        update(getState())
        return row,arrow
    end

    ------------------------------------------------------------------------
    -- MAX1/2 Switches
    ------------------------------------------------------------------------
    local function makeRowSwitch(name,order,labelText,getState,setState)
        local row=Instance.new("Frame")
        row.Name=name
        row.Parent=scroll
        row.Size=UDim2.new(1,-6,0,40)
        row.BackgroundColor3=THEME.BLACK
        local s=Instance.new("UIStroke")
        s.Thickness=2
        s.Color=THEME.GREEN
        s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
        s.Parent=row
        row.LayoutOrder=order

        local lab=Instance.new("TextLabel")
        lab.Parent=row
        lab.BackgroundTransparency=1
        lab.Size=UDim2.new(1,-60,1,0)
        lab.Position=UDim2.new(0,16,0,0)
        lab.Font=Enum.Font.GothamBold
        lab.TextSize=14
        lab.TextColor3=THEME.WHITE
        lab.TextXAlignment=Enum.TextXAlignment.Left
        lab.Text=labelText

        local sw=Instance.new("Frame")
        sw.Parent=row
        sw.AnchorPoint=Vector2.new(1,0.5)
        sw.Position=UDim2.new(1,-12,0.5,0)
        sw.Size=UDim2.fromOffset(40,20)
        sw.BackgroundColor3=THEME.BLACK
        local swStroke=Instance.new("UIStroke")
        swStroke.Parent=sw
        swStroke.Thickness=1.5

        local knob=Instance.new("Frame")
        knob.Parent=sw
        knob.Size=UDim2.fromOffset(16,16)
        knob.BackgroundColor3=THEME.WHITE
        knob.Position=UDim2.new(0,2,0.5,-8)
        local function update(on)
            swStroke.Color=on and THEME.GREEN or THEME.RED
            tween(knob,{Position=UDim2.new(on and 1 or 0,on and -18 or 2,0.5,-8)},0.08)
        end

        local btn=Instance.new("TextButton")
        btn.Parent=sw
        btn.Size=UDim2.fromScale(1,1)
        btn.BackgroundTransparency=1
        btn.Text=""
        btn.AutoButtonColor=false
        btn.MouseButton1Click:Connect(function()
            local new=not getState()
            setState(new)
            update(new)
        end)

        update(getState())
        return row
    end

    ------------------------------------------------------------------------
    -- สร้าง MAX999
    ------------------------------------------------------------------------
    MAXRow,MAXArrow = makeParentArrowSwitch("MAX999",base+1,"MAX999",
        function() return MAXState end,
        function(v) MAXState=v end
    )

    ------------------------------------------------------------------------
    -- สร้าง MAX1, MAX2 แล้วเก็บใน MAXChildren
    ------------------------------------------------------------------------
    local MAX1 = makeRowSwitch("MAX1",base+2,"MAX1",function() return false end,function(v) end)
    local MAX2 = makeRowSwitch("MAX2",base+3,"MAX2",function() return false end,function(v) end)

    -- ซ่อนตอนเริ่มต้น
    MAX1.Visible=false
    MAX2.Visible=false
    table.insert(MAXChildren,MAX1)
    table.insert(MAXChildren,MAX2)
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
