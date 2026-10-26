local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Player = Players.LocalPlayer

local VERIFY_URL = "https://izoki.bytecraft.workers.dev/verify?key="
-- Verification always includes the executor HWID when one is available.
local GUI_NAME = "KhfreshKeySystem"

--// FREE SCHEDULE (UTC) — os.date("!*t").wday: 1=Sun … 7=Sat
--// Only Monday (2) and Tuesday (3) are no-key. 6=Fri and 7=Sat are NOT free.
local FREE_WEEKDAYS_UTC = {
    [2] = "MONDAY",
    [3] = "TUESDAY",
}

local function getUTCDateInfo()
    local ok, value = pcall(function()
        return os.date("!*t")
    end)

    if ok and type(value) == "table" and tonumber(value.wday) then
        return value
    end

    return nil
end

local function getUTCDayName()
    local utc = getUTCDateInfo()
    if not utc then
        return "UNKNOWN"
    end

    local names = {
        [1] = "SUNDAY",
        [2] = "MONDAY",
        [3] = "TUESDAY",
        [4] = "WEDNESDAY",
        [5] = "THURSDAY",
        [6] = "FRIDAY",
        [7] = "SATURDAY",
    }

    return names[tonumber(utc.wday)] or "UNKNOWN"
end

local function isFreeDayUTC()
    local utc = getUTCDateInfo()
    if not utc then
        -- Fail closed: when UTC cannot be read, require the normal key flow.
        return false
    end

    return FREE_WEEKDAYS_UTC[tonumber(utc.wday)] ~= nil
end

local FREE_DAY_UTC = isFreeDayUTC()
local CURRENT_UTC_DAY = getUTCDayName()

pcall(function()
    local old = CoreGui:FindFirstChild(GUI_NAME)
    if old then old:Destroy() end
end)

--// ============================================================
--// Helpers
--// ============================================================

local function tween(obj, info, props)
    local ok, tw = pcall(function()
        return TweenService:Create(obj, info, props)
    end)
    if ok and tw then
        tw:Play()
        return tw
    end
end

local function requestGet(url)
    local synApi = syn and syn.request
    if type(synApi) == "function" then
        return synApi({Url = url, Method = "GET"})
    end

    local globalRequest = rawget(_G, "request")
    if type(globalRequest) == "function" then
        return globalRequest({Url = url, Method = "GET"})
    end

    local httpRequest = rawget(_G, "http_request")
    if type(httpRequest) == "function" then
        return httpRequest({Url = url, Method = "GET"})
    end

    local httpGlobal = rawget(_G, "http")
    if type(httpGlobal) == "table" and type(httpGlobal.request) == "function" then
        return httpGlobal.request({Url = url, Method = "GET"})
    end

    return {
        StatusCode = 200,
        Body = game:HttpGet(url)
    }
end

local function getStableHWID()
    if type(gethwid) == "function" then
        local ok, value = pcall(gethwid)
        if ok and value and tostring(value) ~= "" then
            return tostring(value)
        end
    end

    local okService, analytics = pcall(function()
        return game:GetService("RbxAnalyticsService")
    end)

    if okService and analytics then
        local okClient, clientId = pcall(function()
            return analytics:GetClientId()
        end)
        if okClient and clientId and tostring(clientId) ~= "" then
            return tostring(clientId)
        end
    end

    return ""
end

local function getClipboard()
    local getter = rawget(_G, "getclipboard")
    if type(getter) == "function" then
        local ok, value = pcall(getter)
        if ok and value ~= nil then return tostring(value) end
    end

    local getter2 = rawget(_G, "readclipboard")
    if type(getter2) == "function" then
        local ok, value = pcall(getter2)
        if ok and value ~= nil then return tostring(value) end
    end

    return nil
end

local function setClipboard(value)
    value = tostring(value or "")

    local candidates = {
        rawget(_G, "setclipboard"),
        rawget(_G, "toclipboard"),
        rawget(_G, "writeclipboard"),
        rawget(_G, "set_clipboard"),
    }

    -- Some executors expose clipboard helpers as direct globals rather than _G fields.
    pcall(function()
        candidates[#candidates + 1] = setclipboard
        candidates[#candidates + 1] = toclipboard
        candidates[#candidates + 1] = writeclipboard
        candidates[#candidates + 1] = set_clipboard
    end)

    for _, setter in ipairs(candidates) do
        if type(setter) == "function" then
            local ok = pcall(setter, value)
            if ok then return true end
        end
    end

    local synApi = syn
    if type(synApi) == "table" then
        local writer = synApi.write_clipboard or synApi.setclipboard
        if type(writer) == "function" then
            local ok = pcall(writer, value)
            if ok then return true end
        end
    end

    return false
end

local function normalizeKey(value)
    return tostring(value or ""):gsub("%s+", "")
end

local function responseStatus(response)
    return tonumber(response and (response.StatusCode or response.Status or response.status_code)) or 0
end

local function responseBody(response)
    return tostring(response and (response.Body or response.body) or "")
end

--// ============================================================
--// GUI ROOT
--// ============================================================

local Gui = Instance.new("ScreenGui")
Gui.Name = GUI_NAME
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = true
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = CoreGui

local Overlay = Instance.new("Frame")
Overlay.Size = UDim2.fromScale(1, 1)
Overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
Overlay.BackgroundTransparency = 0.55
Overlay.BorderSizePixel = 0
Overlay.Active = true
Overlay.ZIndex = 1
Overlay.Parent = Gui

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(560, 430)
Main.Position = UDim2.new(0.5, -280, 0.5, -215)
Main.BackgroundColor3 = Color3.fromRGB(11, 11, 14)
Main.BorderSizePixel = 0
Main.Active = true
Main.ZIndex = 2
Main.Parent = Gui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 20)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(58, 58, 68)
MainStroke.Thickness = 1.25
MainStroke.Transparency = 0.1
MainStroke.Parent = Main

local Shadow = Instance.new("ImageLabel")
Shadow.Size = UDim2.new(1, 80, 1, 80)
Shadow.Position = UDim2.new(0.5, 0, 0.5, 8)
Shadow.AnchorPoint = Vector2.new(0.5, 0.5)
Shadow.BackgroundTransparency = 1
Shadow.Image = "rbxassetid://6014261993"
Shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
Shadow.ImageTransparency = 0.38
Shadow.ZIndex = 1
Shadow.Parent = Main

local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 70)
TopBar.BackgroundTransparency = 1
TopBar.Active = true
TopBar.ZIndex = 5
TopBar.Parent = Main

local Divider = Instance.new("Frame")
Divider.Size = UDim2.new(1, -36, 0, 1)
Divider.Position = UDim2.fromOffset(18, 69)
Divider.BackgroundColor3 = Color3.fromRGB(43, 43, 51)
Divider.BorderSizePixel = 0
Divider.ZIndex = 5
Divider.Parent = Main

local LogoBG = Instance.new("Frame")
LogoBG.Size = UDim2.fromOffset(42, 42)
LogoBG.Position = UDim2.fromOffset(18, 14)
LogoBG.BackgroundColor3 = Color3.fromRGB(31, 31, 37)
LogoBG.BorderSizePixel = 0
LogoBG.ZIndex = 6
LogoBG.Parent = Main

local LogoBGCorner = Instance.new("UICorner")
LogoBGCorner.CornerRadius = UDim.new(0, 13)
LogoBGCorner.Parent = LogoBG

local Logo = Instance.new("TextLabel")
Logo.Size = UDim2.fromScale(1, 1)
Logo.BackgroundTransparency = 1
Logo.Font = Enum.Font.GothamBlack
Logo.Text = "K"
Logo.TextSize = 25
Logo.TextColor3 = Color3.fromRGB(255, 255, 255)
Logo.ZIndex = 7
Logo.Parent = LogoBG

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -160, 0, 25)
Title.Position = UDim2.fromOffset(72, 13)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.Text = "KHFRESH HUB"
Title.TextSize = 18
Title.TextColor3 = Color3.fromRGB(250, 250, 252)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.ZIndex = 6
Title.Parent = Main

local Subtitle = Instance.new("TextLabel")
Subtitle.Size = UDim2.new(1, -160, 0, 18)
Subtitle.Position = UDim2.fromOffset(72, 38)
Subtitle.BackgroundTransparency = 1
Subtitle.Font = Enum.Font.Gotham
Subtitle.Text = "IZOKI AUTH  •  KEY VERIFICATION"
Subtitle.TextSize = 10
Subtitle.TextColor3 = Color3.fromRGB(124, 124, 136)
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.ZIndex = 6
Subtitle.Parent = Main

local Close = Instance.new("TextButton")
Close.Size = UDim2.fromOffset(32, 32)
Close.Position = UDim2.new(1, -48, 0, 17)
Close.BackgroundColor3 = Color3.fromRGB(24, 24, 29)
Close.BorderSizePixel = 0
Close.AutoButtonColor = false
Close.Font = Enum.Font.GothamBold
Close.Text = "×"
Close.TextSize = 22
Close.TextColor3 = Color3.fromRGB(160, 160, 170)
Close.ZIndex = 7
Close.Parent = Main

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 10)
CloseCorner.Parent = Close

local function makeLabel(parent, text, pos, size, font, textSize, color)
    local obj = Instance.new("TextLabel")
    obj.BackgroundTransparency = 1
    obj.Position = pos
    obj.Size = size
    obj.Font = font
    obj.Text = text
    obj.TextSize = textSize
    obj.TextColor3 = color
    obj.TextXAlignment = Enum.TextXAlignment.Left
    obj.ZIndex = 7
    obj.Parent = parent
    return obj
end

local KeyTitle = makeLabel(
    Main,
    "ACCESS KEY",
    UDim2.fromOffset(20, 86),
    UDim2.new(1, -40, 0, 20),
    Enum.Font.GothamBold,
    11,
    Color3.fromRGB(220, 220, 226)
)

local KeyHint = makeLabel(
    Main,
    "Paste your 136-character key below.",
    UDim2.fromOffset(20, 109),
    UDim2.new(1, -40, 0, 18),
    Enum.Font.Gotham,
    10,
    Color3.fromRGB(105, 105, 116)
)

local KeyBox = Instance.new("TextBox")
KeyBox.Size = UDim2.new(1, -40, 0, 48)
KeyBox.Position = UDim2.fromOffset(20, 133)
KeyBox.BackgroundColor3 = Color3.fromRGB(18, 18, 23)
KeyBox.BorderSizePixel = 0
KeyBox.ClearTextOnFocus = false
KeyBox.Font = Enum.Font.Code
KeyBox.PlaceholderText = "Paste key here..."
KeyBox.PlaceholderColor3 = Color3.fromRGB(82, 82, 95)
KeyBox.Text = ""
KeyBox.TextColor3 = Color3.fromRGB(240, 240, 246)
KeyBox.TextSize = 12
KeyBox.TextXAlignment = Enum.TextXAlignment.Left
KeyBox.ZIndex = 8
KeyBox.Parent = Main

local KeyPadding = Instance.new("UIPadding")
KeyPadding.PaddingLeft = UDim.new(0, 14)
KeyPadding.PaddingRight = UDim.new(0, 14)
KeyPadding.Parent = KeyBox

local KeyCorner = Instance.new("UICorner")
KeyCorner.CornerRadius = UDim.new(0, 11)
KeyCorner.Parent = KeyBox

local KeyStroke = Instance.new("UIStroke")
KeyStroke.Color = Color3.fromRGB(50, 50, 60)
KeyStroke.Thickness = 1
KeyStroke.Transparency = 0.15
KeyStroke.Parent = KeyBox

local GetKey = Instance.new("TextButton")
GetKey.Size = UDim2.new(0.5, -25, 0, 40)
GetKey.Position = UDim2.fromOffset(20, 196)
GetKey.BackgroundColor3 = Color3.fromRGB(27, 27, 33)
GetKey.BorderSizePixel = 0
GetKey.AutoButtonColor = false
GetKey.Font = Enum.Font.GothamBold
GetKey.Text = "GET KEY"
GetKey.TextSize = 10
GetKey.TextColor3 = Color3.fromRGB(232, 232, 238)
GetKey.ZIndex = 8
GetKey.Parent = Main

local GetKeyCorner = Instance.new("UICorner")
GetKeyCorner.CornerRadius = UDim.new(0, 10)
GetKeyCorner.Parent = GetKey

local GetKeyStroke = Instance.new("UIStroke")
GetKeyStroke.Color = Color3.fromRGB(52, 52, 62)
GetKeyStroke.Thickness = 1
GetKeyStroke.Parent = GetKey

local InfoTitle = makeLabel(
    Main,
    "SECURE LOADER",
    UDim2.fromOffset(20, 252),
    UDim2.new(1, -40, 0, 20),
    Enum.Font.GothamBold,
    11,
    Color3.fromRGB(220, 220, 226)
)

local InfoHint = makeLabel(
    Main,
    "GET KEY copies the current IZOKI website. VERIFY KEY checks your key and runs the embedded script.",
    UDim2.fromOffset(20, 273),
    UDim2.new(1, -40, 0, 30),
    Enum.Font.Gotham,
    10,
    Color3.fromRGB(105, 105, 116)
)
InfoHint.TextWrapped = true
InfoHint.TextYAlignment = Enum.TextYAlignment.Top

local Verify = Instance.new("TextButton")
Verify.Size = UDim2.new(0.5, -25, 0, 40)
Verify.Position = UDim2.new(0.5, 5, 0, 196)
Verify.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
Verify.BorderSizePixel = 0
Verify.AutoButtonColor = false
Verify.Font = Enum.Font.GothamBold
Verify.Text = "VERIFY KEY"
Verify.TextSize = 11
Verify.TextColor3 = Color3.fromRGB(0, 0, 0)
Verify.ZIndex = 8
Verify.Parent = Main

local VerifyCorner = Instance.new("UICorner")
VerifyCorner.CornerRadius = UDim.new(0, 11)
VerifyCorner.Parent = Verify

local VerifyStroke = Instance.new("UIStroke")
VerifyStroke.Color = Color3.fromRGB(225, 225, 230)
VerifyStroke.Thickness = 1
VerifyStroke.Transparency = 0.1
VerifyStroke.Parent = Verify



local Status = makeLabel(
    Main,
    "● Waiting for key",
    UDim2.fromOffset(20, 320),
    UDim2.new(1, -40, 0, 20),
    Enum.Font.GothamMedium,
    10,
    Color3.fromRGB(118, 118, 130)
)

local Footer = makeLabel(
    Main,
    "IZOKI AUTH  •  izoki.bytecraft.workers.dev",
    UDim2.fromOffset(20, 0),
    UDim2.new(1, -40, 0, 18),
    Enum.Font.Gotham,
    9,
    Color3.fromRGB(68, 68, 78)
)
Footer.Position = UDim2.new(0, 20, 1, -20)
Footer.TextXAlignment = Enum.TextXAlignment.Right


--// ============================================================
--// Button feedback
--// ============================================================

local function hoverButton(button, normal, over)
    button.MouseEnter:Connect(function()
        tween(button, TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundColor3 = over
        })
    end)
    button.MouseLeave:Connect(function()
        tween(button, TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundColor3 = normal
        })
    end)
end

hoverButton(GetKey, Color3.fromRGB(27, 27, 33), Color3.fromRGB(41, 41, 49))
hoverButton(Verify, Color3.fromRGB(255, 255, 255), Color3.fromRGB(222, 222, 222))
hoverButton(Close, Color3.fromRGB(24, 24, 29), Color3.fromRGB(48, 48, 56))

--// ============================================================
--// Get Key
--// ============================================================

local GET_KEY_URL = "https://izoki.bytecraft.workers.dev/"
local KEY_FILE_NAME = "KhfreshKeySystem/izoki_key.txt"

local function canUseFileApi()
    return type(isfile) == "function"
        and type(readfile) == "function"
        and type(writefile) == "function"
end

local function ensureFolder()
    local makefolderFn = rawget(_G, "makefolder")
    if type(makefolderFn) ~= "function" then
        makefolderFn = makefolder
    end
    if type(makefolderFn) ~= "function" then return end
    pcall(function()
        if type(isfolder) == "function" then
            if not isfolder("KhfreshKeySystem") then
                makefolderFn("KhfreshKeySystem")
            end
        else
            makefolderFn("KhfreshKeySystem")
        end
    end)
end

local function saveKey(key)
    if not canUseFileApi() then
        return false
    end
    key = normalizeKey(key)
    if key == "" then return false end
    ensureFolder()
    local ok = pcall(function()
        writefile(KEY_FILE_NAME, key)
    end)
    if not ok then return false end

    local verifyOk, saved = pcall(function()
        return readfile(KEY_FILE_NAME)
    end)
    return verifyOk and normalizeKey(saved) == key
end

local function loadSavedKey()
    if not canUseFileApi() then
        return nil
    end
    local exists = false
    pcall(function()
        exists = isfile(KEY_FILE_NAME)
    end)
    if not exists then return nil end

    local ok, value = pcall(function()
        return readfile(KEY_FILE_NAME)
    end)
    if not ok or value == nil then return nil end

    local key = normalizeKey(value)
    if key == "" then return nil end
    return key
end

local function deleteSavedKey()
    local deleter = rawget(_G, "delfile")
    if type(deleter) ~= "function" then return end
    pcall(function()
        if type(isfile) ~= "function" or isfile(KEY_FILE_NAME) then
            deleter(KEY_FILE_NAME)
        end
    end)
end

local function hideKeySystem()
    pcall(function()
        local closeTween = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        tween(Main, closeTween, {Size = UDim2.fromOffset(0, 0)})
        tween(Overlay, closeTween, {BackgroundTransparency = 1})
    end)
    task.wait(0.23)
    pcall(function()
        if Gui and Gui.Parent then Gui:Destroy() end
    end)
end

GetKey.MouseButton1Click:Connect(function()
    local ok = setClipboard(GET_KEY_URL)
    if ok then
        Status.Text = "● Link copied successfully"
        Status.TextColor3 = Color3.fromRGB(112, 220, 148)
        GetKey.Text = "COPIED"
        task.delay(1.1, function()
            if GetKey and GetKey.Parent then
                GetKey.Text = "GET KEY"
            end
        end)
    else
        Status.Text = "● Clipboard unavailable"
        Status.TextColor3 = Color3.fromRGB(255, 171, 90)
        warn("[KHFRESH] Copy failed. Copy manually: " .. GET_KEY_URL)
    end
end)


Close.MouseButton1Click:Connect(function()
    hideKeySystem()
end)

--// ============================================================
--// Drag using the top bar only
--// ============================================================

local dragging = false
local dragStart = nil
local startPos = nil

TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    local delta = input.Position - dragStart
    Main.Position = UDim2.new(
        startPos.X.Scale,
        startPos.X.Offset + delta.X,
        startPos.Y.Scale,
        startPos.Y.Offset + delta.Y
    )
end)

--// ============================================================
--// Key verification + code execution
--// ============================================================

local verifying = false
local verified = false

--// ============================================================
--// EMBEDDED PAYLOAD
--// Paste the hub source at the very end of this file; it is executed after verification.
--// Do not paste the payload into the UI.
--// ============================================================
local executeEmbeddedScript

local function setBusy(state)
    verifying = state
    Verify.Active = not state
    GetKey.Active = not state
end

local function shakeKeyBox()
    local base = UDim2.fromOffset(20, 133)
    local sequence = {
        UDim2.fromOffset(26, 133),
        UDim2.fromOffset(14, 133),
        UDim2.fromOffset(24, 133),
        base
    }
    for _, pos in ipairs(sequence) do
        tween(KeyBox, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = pos
        })
        task.wait(0.06)
    end
end

local function verifyKey()
    if verifying then return end

    local key = normalizeKey(KeyBox.Text)
    if key == "" then
        Status.Text = "● Enter a key first"
        Status.TextColor3 = Color3.fromRGB(255, 171, 90)
        shakeKeyBox()
        return
    end

    local hwid = getStableHWID()
    if hwid == "" then
        Status.Text = "● Could not read executor HWID"
        Status.TextColor3 = Color3.fromRGB(255, 90, 90)
        return
    end

    setBusy(true)
    Verify.Text = "VERIFYING..."
    Status.Text = "● Checking key with IZOKI..."
    Status.TextColor3 = Color3.fromRGB(175, 175, 188)

    local verifyUrl = VERIFY_URL
        .. HttpService:UrlEncode(key)
        .. "&hwid="
        .. HttpService:UrlEncode(hwid)

    local requestOk, response = pcall(function()
        return requestGet(verifyUrl)
    end)

    if not requestOk or not response then
        setBusy(false)
        Verify.Text = "VERIFY KEY"
        Status.Text = "● Request failed"
        Status.TextColor3 = Color3.fromRGB(255, 90, 90)
        return
    end

    local statusCode = responseStatus(response)
    local body = responseBody(response)
    local valid = false
    local serverMessage = nil
    local serverCode = nil

    if type(statusCode) == "number" and statusCode >= 200 and statusCode < 500 then
        local decodeOk, data = pcall(function()
            return HttpService:JSONDecode(body)
        end)

        if decodeOk and type(data) == "table" then
            valid = data.valid == true or data.success == true
            serverMessage = data.message
            serverCode = data.code
        end

        if not valid then
            valid = body:find('"valid"%s*:%s*true') ~= nil
                or body:find('"success"%s*:%s*true') ~= nil
        end
    end

    if not valid then
        setBusy(false)
        Verify.Text = "VERIFY KEY"

        if serverCode == "HWID_MISMATCH" then
            Status.Text = "● Key is bound to another device"
        elseif serverCode == "KEY_EXPIRED" then
            Status.Text = "● Key expired"
        elseif serverCode == "KEY_REVOKED" then
            Status.Text = "● Key revoked"
        elseif serverCode == "HWID_REQUIRED" then
            Status.Text = "● HWID is required"
        elseif serverCode == "INVALID_KEY" or serverCode == "INVALID_KEY_FORMAT" or serverCode == "KEY_NOT_FOUND" then
            Status.Text = "● Key not found, expired, or deleted"
        elseif statusCode == 429 then
            Status.Text = "● Too many verify requests; wait and retry"
        elseif statusCode >= 500 then
            Status.Text = "● IZOKI server error; try again later"
        else
            Status.Text = "● " .. tostring(serverMessage or "Invalid or expired key")
        end

        Status.TextColor3 = Color3.fromRGB(255, 90, 90)
        shakeKeyBox()
        return
    end

    verified = true
    local saved = saveKey(key)
    if not saved then
        warn("[KHFRESH] Key verified, but persistent file storage is unavailable in this executor.")
    end
    Status.Text = "● Key verified successfully"
    Status.TextColor3 = Color3.fromRGB(112, 220, 148)
    Verify.Text = "ACCESS GRANTED"

    -- Hide the key UI as soon as the server approves the key.
    hideKeySystem()
    setBusy(false)

    task.spawn(function()
        executeEmbeddedScript()
    end)
end

Verify.MouseButton1Click:Connect(function()
    if verifying then return end
    verifyKey()
end)

--// ============================================================
--// Opening animation
--// ============================================================

Main.Size = UDim2.fromOffset(0, 0)
Main.Position = UDim2.new(0.5, 0, 0.5, 0)
Overlay.BackgroundTransparency = 1

tween(Overlay, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
    BackgroundTransparency = 0.55
})

tween(Main, TweenInfo.new(0.42, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
    Size = UDim2.fromOffset(560, 430),
    Position = UDim2.new(0.5, -280, 0.5, -215)
})

--// ============================================================================
--// AUTO LOGIN FROM SAVED KEY
--// ============================================================================
--// If a previously verified key exists, verify it silently and launch the
--// embedded source without making the user press VERIFY KEY again.

local function autoLoginSavedKey()
    local savedKey = loadSavedKey()
    if not savedKey then
        return
    end

    task.spawn(function()
        task.wait(0.18)

        local hwid = getStableHWID()
        if hwid == "" then
            Status.Text = "● Saved key found; HWID unavailable"
            Status.TextColor3 = Color3.fromRGB(255, 171, 90)
            return
        end

        setBusy(true)
        Verify.Text = "AUTO VERIFY..."
        Status.Text = "● Verifying saved key..."
        Status.TextColor3 = Color3.fromRGB(175, 175, 188)

        local verifyUrl = VERIFY_URL
            .. HttpService:UrlEncode(savedKey)
            .. "&hwid="
            .. HttpService:UrlEncode(hwid)

        local requestOk, response = pcall(function()
            return requestGet(verifyUrl)
        end)

        local statusCode = responseStatus(response)
        local body = responseBody(response)
        local valid = false
        local serverCode = nil
        local serverMessage = nil

        if requestOk and response and type(statusCode) == "number" and statusCode >= 200 and statusCode < 500 then
            local decodeOk, data = pcall(function()
                return HttpService:JSONDecode(body)
            end)
            if decodeOk and type(data) == "table" then
                valid = data.valid == true or data.success == true
                serverCode = data.code
                serverMessage = data.message
            end
            if not valid then
                valid = body:find('"valid"%s*:%s*true') ~= nil
                    or body:find('"success"%s*:%s*true') ~= nil
            end
        end

        if not valid then
            setBusy(false)
            deleteSavedKey()
            Verify.Text = "VERIFY KEY"
            if serverCode == "HWID_MISMATCH" then
                Status.Text = "● Saved key belongs to another device"
            elseif serverCode == "KEY_EXPIRED" then
                Status.Text = "● Saved key expired"
            elseif serverCode == "KEY_REVOKED" then
                Status.Text = "● Saved key revoked"
            elseif serverCode == "INVALID_KEY" or serverCode == "INVALID_KEY_FORMAT" or serverCode == "KEY_NOT_FOUND" then
                Status.Text = "● Saved key expired, deleted, or no longer exists"
            elseif statusCode == 429 then
                Status.Text = "● Too many verify requests; wait and retry"
            elseif statusCode >= 500 then
                Status.Text = "● IZOKI server error; try again later"
            else
                Status.Text = "● " .. tostring(serverMessage or "Saved key is invalid")
            end
            Status.TextColor3 = Color3.fromRGB(255, 90, 90)
            return
        end

        verified = true
        Status.Text = "● Saved key verified"
        Status.TextColor3 = Color3.fromRGB(112, 220, 148)
        Verify.Text = "ACCESS GRANTED"

        hideKeySystem()
        setBusy(false)

        task.spawn(function()
            executeEmbeddedScript()
        end)
    end)
end

--// ============================================================================
--// PASTE YOUR HUB SCRIPT BELOW THIS LINE
--// ============================================================================
--// KHONG CAN NGOAC LONG STRING; CHI PASTE NGUYEN VAN SOURCE.
--// Chi can paste NGUYEN VAN full hub source ngay ben duoi dong:
--//     --// >>> PASTE HUB SOURCE BELOW <<<
--//
--// Phan code duoc paste nam TRUC TIEP trong executeEmbeddedScript(),
--// nen no chi chay sau khi IZOKI verify thanh cong.
--// ============================================================================



local __KH_HUB_SRC = [===============[
print([[
 KHFRESH HUB — STATIC UI REWRITE
 UI backend: self-written static library + full Lucide icons
]])

local runtimeEnv = (getgenv and getgenv()) or _G
runtimeEnv.KhfreshStage = function(_) end
runtimeEnv.KhfreshReport = function(t, m) pcall(function() warn("[Khfresh Hub]", t, m) end) end
runtimeEnv.KhfreshNeedChild = function(parent, childName, timeout)
    if not parent then return nil end
    local child = parent:FindFirstChild(childName)
    if not child and timeout and timeout > 0 then
        pcall(function() child = parent:WaitForChild(childName, timeout) end)
    end
    return child
end

local KHFRESH_LOGO_ASSET = ""
local function setKhfreshLoadProgress(_, _) end
local function closeKhfreshLoadingScreen() end

local __SIRIUS_UI_SOURCE = [====[

-- KhfreshLib Sirius shell v41
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local getHiddenUI = (typeof(gethui) == "function" and gethui) or nil
local hookMetamethod = (typeof(hookmetamethod) == "function" and hookmetamethod) or nil
local getnamecallmethod = (typeof(getnamecallmethod) == "function" and getnamecallmethod) or nil
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local env = (getgenv and getgenv()) or _G

local LUCIDE = {
["a-arrow-down"] = "rbxassetid://92867583610071",
	["a-arrow-up"] = "rbxassetid://132318504999733",
	["a-large-small"] = "rbxassetid://111491496660216",
	["accessibility"] = "rbxassetid://114029945302017",
	["activity"] = "rbxassetid://94212016861936",
	["air-vent"] = "rbxassetid://81517226012329",
	["airplay"] = "rbxassetid://115020759309179",
	["alarm-clock-check"] = "rbxassetid://76437352099157",
	["alarm-clock-minus"] = "rbxassetid://77364179863205",
	["alarm-clock-off"] = "rbxassetid://97904885874823",
	["alarm-clock-plus"] = "rbxassetid://80468822979214",
	["alarm-clock"] = "rbxassetid://126259032907535",
	["alarm-smoke"] = "rbxassetid://96965448419685",
	["album"] = "rbxassetid://127358331163602",
	["align-center-horizontal"] = "rbxassetid://81570549209434",
	["align-center-vertical"] = "rbxassetid://118470463752466",
	["align-end-horizontal"] = "rbxassetid://139502909745427",
	["align-end-vertical"] = "rbxassetid://96528869059554",
	["align-horizontal-distribute-center"] = "rbxassetid://97220086126656",
	["align-horizontal-distribute-end"] = "rbxassetid://106128590702022",
	["align-horizontal-distribute-start"] = "rbxassetid://76074660002997",
	["align-horizontal-justify-center"] = "rbxassetid://75732302772427",
	["align-horizontal-justify-end"] = "rbxassetid://129167626402283",
	["align-horizontal-justify-start"] = "rbxassetid://130161830325281",
	["align-horizontal-space-around"] = "rbxassetid://91646106782950",
	["align-horizontal-space-between"] = "rbxassetid://103886093046990",
	["align-start-horizontal"] = "rbxassetid://125674804697729",
	["align-start-vertical"] = "rbxassetid://105020230154823",
	["align-vertical-distribute-center"] = "rbxassetid://93791183635525",
	["align-vertical-distribute-end"] = "rbxassetid://139354223511433",
	["align-vertical-distribute-start"] = "rbxassetid://74961997822126",
	["align-vertical-justify-center"] = "rbxassetid://134754696166569",
	["align-vertical-justify-end"] = "rbxassetid://92569381441969",
	["align-vertical-justify-start"] = "rbxassetid://99692844572718",
	["align-vertical-space-around"] = "rbxassetid://96206012459190",
	["align-vertical-space-between"] = "rbxassetid://124998077349706",
	["ambulance"] = "rbxassetid://78599995190651",
	["ampersand"] = "rbxassetid://75272915739209",
	["ampersands"] = "rbxassetid://126947193455996",
	["amphora"] = "rbxassetid://137370389604364",
	["anchor"] = "rbxassetid://92181172123618",
	["angry"] = "rbxassetid://74237056000103",
	["annoyed"] = "rbxassetid://80064369052011",
	["antenna"] = "rbxassetid://99628923540956",
	["anvil"] = "rbxassetid://100203029845919",
	["aperture"] = "rbxassetid://83396154449972",
	["app-window-mac"] = "rbxassetid://79587216113811",
	["app-window"] = "rbxassetid://93142176757189",
	["apple"] = "rbxassetid://104349242902442",
	["archive-restore"] = "rbxassetid://78956681942188",
	["archive-x"] = "rbxassetid://75830115088395",
	["archive"] = "rbxassetid://122180020814574",
	["armchair"] = "rbxassetid://105384358373973",
	["arrow-big-down-dash"] = "rbxassetid://137987229582002",
	["arrow-big-down"] = "rbxassetid://81081164158885",
	["arrow-big-left-dash"] = "rbxassetid://97827621354677",
	["arrow-big-left"] = "rbxassetid://85973092492641",
	["arrow-big-right-dash"] = "rbxassetid://117825834972403",
	["arrow-big-right"] = "rbxassetid://82960676755590",
	["arrow-big-up-dash"] = "rbxassetid://99260194327483",
	["arrow-big-up"] = "rbxassetid://93136954756149",
	["arrow-down-0-1"] = "rbxassetid://120961896217875",
	["arrow-down-1-0"] = "rbxassetid://93474255891850",
	["arrow-down-a-z"] = "rbxassetid://99554596207900",
	["arrow-down-from-line"] = "rbxassetid://132045845807798",
	["arrow-down-left"] = "rbxassetid://102899325237364",
	["arrow-down-narrow-wide"] = "rbxassetid://129105261655061",
	["arrow-down-right"] = "rbxassetid://123109928624974",
	["arrow-down-to-dot"] = "rbxassetid://101675355931221",
	["arrow-down-to-line"] = "rbxassetid://87050478931254",
	["arrow-down-up"] = "rbxassetid://85780258549577",
	["arrow-down-wide-narrow"] = "rbxassetid://88461733425991",
	["arrow-down-z-a"] = "rbxassetid://76115279362232",
	["arrow-down"] = "rbxassetid://98764963621439",
	["arrow-left-from-line"] = "rbxassetid://87857914437603",
	["arrow-left-right"] = "rbxassetid://131324733048447",
	["arrow-left-to-line"] = "rbxassetid://118645136026970",
	["arrow-left"] = "rbxassetid://102531941843733",
	["arrow-right-from-line"] = "rbxassetid://74073639809355",
	["arrow-right-left"] = "rbxassetid://77015754304300",
	["arrow-right-to-line"] = "rbxassetid://78632510329852",
	["arrow-right"] = "rbxassetid://113692007244654",
	["arrow-up-0-1"] = "rbxassetid://105257823943016",
	["arrow-up-1-0"] = "rbxassetid://134175521693798",
	["arrow-up-a-z"] = "rbxassetid://77763416595160",
	["arrow-up-down"] = "rbxassetid://81019887641527",
	["arrow-up-from-dot"] = "rbxassetid://124408496673275",
	["arrow-up-from-line"] = "rbxassetid://95777664626453",
	["arrow-up-left"] = "rbxassetid://123490598231261",
	["arrow-up-narrow-wide"] = "rbxassetid://73006024672636",
	["arrow-up-right"] = "rbxassetid://129280608535523",
	["arrow-up-to-line"] = "rbxassetid://108818207813537",
	["arrow-up-wide-narrow"] = "rbxassetid://87437426951568",
	["arrow-up-z-a"] = "rbxassetid://107546173611884",
	["arrow-up"] = "rbxassetid://89282378235317",
	["arrows-up-from-line"] = "rbxassetid://133710016938621",
	["asterisk"] = "rbxassetid://88552752106723",
	["at-sign"] = "rbxassetid://79059152889146",
	["atom"] = "rbxassetid://73167696981648",
	["audio-lines"] = "rbxassetid://70930641819242",
	["audio-waveform"] = "rbxassetid://86462036665209",
	["award"] = "rbxassetid://132740088158419",
	["axe"] = "rbxassetid://132405197863294",
	["axis-3d"] = "rbxassetid://122438676546804",
	["baby"] = "rbxassetid://93472926933440",
	["backpack"] = "rbxassetid://140420225386018",
	["badge-alert"] = "rbxassetid://101829200081951",
	["badge-cent"] = "rbxassetid://133345018873154",
	["badge-check"] = "rbxassetid://76078495178149",
	["badge-dollar-sign"] = "rbxassetid://127139803581141",
	["badge-euro"] = "rbxassetid://120016477674659",
	["badge-indian-rupee"] = "rbxassetid://75659682309981",
	["badge-info"] = "rbxassetid://131995373201472",
	["badge-japanese-yen"] = "rbxassetid://99081574588615",
	["badge-minus"] = "rbxassetid://140321561183881",
	["badge-percent"] = "rbxassetid://121359224294885",
	["badge-plus"] = "rbxassetid://100325578561866",
	["badge-pound-sterling"] = "rbxassetid://119688217279444",
	["badge-question-mark"] = "rbxassetid://121464963737502",
	["badge-russian-ruble"] = "rbxassetid://108839463659864",
	["badge-swiss-franc"] = "rbxassetid://91447608372740",
	["badge-turkish-lira"] = "rbxassetid://137839965873529",
	["badge-x"] = "rbxassetid://122931434733842",
	["badge"] = "rbxassetid://116620312917084",
	["baggage-claim"] = "rbxassetid://86922213051957",
	["ban"] = "rbxassetid://90767043015246",
	["banana"] = "rbxassetid://140713420056179",
	["bandage"] = "rbxassetid://129660129590770",
	["banknote-arrow-down"] = "rbxassetid://139366449345199",
	["banknote-arrow-up"] = "rbxassetid://133758343082529",
	["banknote-x"] = "rbxassetid://95348701438065",
	["banknote"] = "rbxassetid://104840231536668",
	["barcode"] = "rbxassetid://118473018143689",
	["barrel"] = "rbxassetid://130647115622774",
	["baseline"] = "rbxassetid://124677132511270",
	["bath"] = "rbxassetid://76031400297942",
	["battery-charging"] = "rbxassetid://80139357470047",
	["battery-full"] = "rbxassetid://70906718268972",
	["battery-low"] = "rbxassetid://139659256984314",
	["battery-medium"] = "rbxassetid://105934079398915",
	["battery-plus"] = "rbxassetid://91931341486966",
	["battery-warning"] = "rbxassetid://115230083817257",
	["battery"] = "rbxassetid://70765800346189",
	["beaker"] = "rbxassetid://80902539995520",
	["bean-off"] = "rbxassetid://98164436608714",
	["bean"] = "rbxassetid://89491967076869",
	["bed-double"] = "rbxassetid://73820193212911",
	["bed-single"] = "rbxassetid://113423940880634",
	["bed"] = "rbxassetid://97726529032925",
	["beef"] = "rbxassetid://105850162318915",
	["beer-off"] = "rbxassetid://120333134736361",
	["beer"] = "rbxassetid://116404978807744",
	["bell-dot"] = "rbxassetid://93161277118810",
	["bell-electric"] = "rbxassetid://100277767266983",
	["bell-minus"] = "rbxassetid://126334890449727",
	["bell-off"] = "rbxassetid://78560046118930",
	["bell-plus"] = "rbxassetid://77014333795836",
	["bell-ring"] = "rbxassetid://94612128913941",
	["bell"] = "rbxassetid://97392696311902",
	["between-horizontal-end"] = "rbxassetid://81602774794322",
	["between-horizontal-start"] = "rbxassetid://76112384929846",
	["between-vertical-end"] = "rbxassetid://72817612571631",
	["between-vertical-start"] = "rbxassetid://85278312190301",
	["biceps-flexed"] = "rbxassetid://82004462003936",
	["bike"] = "rbxassetid://102930322246035",
	["binary"] = "rbxassetid://91751953950088",
	["binoculars"] = "rbxassetid://101460003267896",
	["biohazard"] = "rbxassetid://95956532900432",
	["bird"] = "rbxassetid://132284145117371",
	["birdhouse"] = "rbxassetid://83999157401433",
	["bitcoin"] = "rbxassetid://95459240442938",
	["blend"] = "rbxassetid://111679612185257",
	["blinds"] = "rbxassetid://71164165283925",
	["blocks"] = "rbxassetid://72212693357737",
	["bluetooth-connected"] = "rbxassetid://96315134002985",
	["bluetooth-off"] = "rbxassetid://80600044218117",
	["bluetooth-searching"] = "rbxassetid://100673019606426",
	["bluetooth"] = "rbxassetid://90506573139443",
	["bold"] = "rbxassetid://116141470019166",
	["bolt"] = "rbxassetid://102881251417484",
	["bomb"] = "rbxassetid://139223800924636",
	["bone"] = "rbxassetid://111242153474115",
	["book-a"] = "rbxassetid://104067275658465",
	["book-alert"] = "rbxassetid://124159928044853",
	["book-audio"] = "rbxassetid://109208148317037",
	["book-check"] = "rbxassetid://115999656081696",
	["book-copy"] = "rbxassetid://108543407492005",
	["book-dashed"] = "rbxassetid://127430784795958",
	["book-down"] = "rbxassetid://101011730128222",
	["book-headphones"] = "rbxassetid://108670200799574",
	["book-heart"] = "rbxassetid://112788845135284",
	["book-image"] = "rbxassetid://80808285757226",
	["book-key"] = "rbxassetid://116024426170705",
	["book-lock"] = "rbxassetid://118765061220571",
	["book-marked"] = "rbxassetid://73211024251780",
	["book-minus"] = "rbxassetid://112724962046282",
	["book-open-check"] = "rbxassetid://130848362492667",
	["book-open-text"] = "rbxassetid://100629528672195",
	["book-open"] = "rbxassetid://129845326810392",
	["book-plus"] = "rbxassetid://140267785051233",
	["book-text"] = "rbxassetid://94011772484232",
	["book-type"] = "rbxassetid://97817304725443",
	["book-up-2"] = "rbxassetid://130161620853665",
	["book-up"] = "rbxassetid://98640174079190",
	["book-user"] = "rbxassetid://128489189240523",
	["book-x"] = "rbxassetid://118754548186537",
	["book"] = "rbxassetid://125383279695672",
	["bookmark-check"] = "rbxassetid://93940443347986",
	["bookmark-minus"] = "rbxassetid://96807096039910",
	["bookmark-plus"] = "rbxassetid://121469724491615",
	["bookmark-x"] = "rbxassetid://112272342584706",
	["bookmark"] = "rbxassetid://121093149326239",
	["boom-box"] = "rbxassetid://99901322535868",
	["bot-message-square"] = "rbxassetid://96145330292478",
	["bot-off"] = "rbxassetid://140417690560013",
	["bot"] = "rbxassetid://80451686744860",
	["bottle-wine"] = "rbxassetid://131675403196921",
	["bow-arrow"] = "rbxassetid://124089655150375",
	["box"] = "rbxassetid://101768155599700",
	["boxes"] = "rbxassetid://136372617578355",
	["braces"] = "rbxassetid://117761094704041",
	["brackets"] = "rbxassetid://74368995728099",
	["brain-circuit"] = "rbxassetid://70547962410202",
	["brain-cog"] = "rbxassetid://132039205501538",
	["brain"] = "rbxassetid://92424107303177",
	["brick-wall-fire"] = "rbxassetid://92980588705520",
	["brick-wall-shield"] = "rbxassetid://75954432775071",
	["brick-wall"] = "rbxassetid://112878522258821",
	["briefcase-business"] = "rbxassetid://129135125207283",
	["briefcase-conveyor-belt"] = "rbxassetid://108665725653714",
	["briefcase-medical"] = "rbxassetid://119917756334087",
	["briefcase"] = "rbxassetid://96754188164225",
	["bring-to-front"] = "rbxassetid://132975903553748",
	["brush-cleaning"] = "rbxassetid://71728977448805",
	["brush"] = "rbxassetid://127035535799640",
	["bubbles"] = "rbxassetid://106183424168227",
	["bug-off"] = "rbxassetid://88020025049245",
	["bug-play"] = "rbxassetid://80107955888092",
	["bug"] = "rbxassetid://83626408925438",
	["building-2"] = "rbxassetid://77873775611951",
	["building"] = "rbxassetid://110616258983082",
	["bus-front"] = "rbxassetid://89863432456045",
	["bus"] = "rbxassetid://133798469717463",
	["cable-car"] = "rbxassetid://128643682205596",
	["cable"] = "rbxassetid://128449944504901",
	["cake-slice"] = "rbxassetid://136769828413242",
	["cake"] = "rbxassetid://103131590503275",
	["calculator"] = "rbxassetid://74915716529646",
	["calendar-1"] = "rbxassetid://98458364171044",
	["calendar-arrow-down"] = "rbxassetid://108415736543437",
	["calendar-arrow-up"] = "rbxassetid://70574654109118",
	["calendar-check-2"] = "rbxassetid://120231170248276",
	["calendar-check"] = "rbxassetid://71551019465748",
	["calendar-clock"] = "rbxassetid://119132152594595",
	["calendar-cog"] = "rbxassetid://122402172360287",
	["calendar-days"] = "rbxassetid://99072017568595",
	["calendar-fold"] = "rbxassetid://117368871270394",
	["calendar-heart"] = "rbxassetid://88839008103676",
	["calendar-minus-2"] = "rbxassetid://98846170279891",
	["calendar-minus"] = "rbxassetid://137354318924383",
	["calendar-off"] = "rbxassetid://109726151749217",
	["calendar-plus-2"] = "rbxassetid://112264562093883",
	["calendar-plus"] = "rbxassetid://125266115249843",
	["calendar-range"] = "rbxassetid://103641849247576",
	["calendar-search"] = "rbxassetid://92010083223634",
	["calendar-sync"] = "rbxassetid://78082218499697",
	["calendar-x-2"] = "rbxassetid://107518051061147",
	["calendar-x"] = "rbxassetid://106703374806500",
	["calendar"] = "rbxassetid://114792700814035",
	["camera-off"] = "rbxassetid://81057636835256",
	["camera"] = "rbxassetid://79950339943067",
	["candy-cane"] = "rbxassetid://71689468772492",
	["candy-off"] = "rbxassetid://110232752314832",
	["candy"] = "rbxassetid://107812129154678",
	["cannabis"] = "rbxassetid://98792006538601",
	["captions-off"] = "rbxassetid://105223545364193",
	["captions"] = "rbxassetid://104960225031445",
	["car-front"] = "rbxassetid://87380942739063",
	["car-taxi-front"] = "rbxassetid://122455403384057",
	["car"] = "rbxassetid://121065933462582",
	["caravan"] = "rbxassetid://120070979471783",
	["card-sim"] = "rbxassetid://134490550095771",
	["carrot"] = "rbxassetid://119118221444304",
	["case-lower"] = "rbxassetid://129303130603241",
	["case-sensitive"] = "rbxassetid://125410273293056",
	["case-upper"] = "rbxassetid://111633433531325",
	["cassette-tape"] = "rbxassetid://137065788934157",
	["cast"] = "rbxassetid://98202245922071",
	["castle"] = "rbxassetid://119275077187784",
	["cat"] = "rbxassetid://124252153404931",
	["cctv"] = "rbxassetid://99979894766624",
	["chart-area"] = "rbxassetid://123446436762366",
	["chart-bar-big"] = "rbxassetid://72336824986044",
	["chart-bar-decreasing"] = "rbxassetid://107217459044963",
	["chart-bar-increasing"] = "rbxassetid://88268905998571",
	["chart-bar-stacked"] = "rbxassetid://98478751113024",
	["chart-bar"] = "rbxassetid://105389816384108",
	["chart-candlestick"] = "rbxassetid://125676898615697",
	["chart-column-big"] = "rbxassetid://98598733210787",
	["chart-column-decreasing"] = "rbxassetid://73586137373563",
	["chart-column-increasing"] = "rbxassetid://120421615068601",
	["chart-column-stacked"] = "rbxassetid://86031449675105",
	["chart-column"] = "rbxassetid://97915995538580",
	["chart-gantt"] = "rbxassetid://88811660555940",
	["chart-line"] = "rbxassetid://101833156055618",
	["chart-network"] = "rbxassetid://104027882693561",
	["chart-no-axes-column-decreasing"] = "rbxassetid://123371717192542",
	["chart-no-axes-column-increasing"] = "rbxassetid://140383830943049",
	["chart-no-axes-column"] = "rbxassetid://94078751170351",
	["chart-no-axes-combined"] = "rbxassetid://121424233161912",
	["chart-no-axes-gantt"] = "rbxassetid://131936541106368",
	["chart-pie"] = "rbxassetid://113412261630136",
	["chart-scatter"] = "rbxassetid://108217585014571",
	["chart-spline"] = "rbxassetid://90307460742494",
	["check-check"] = "rbxassetid://95183312173858",
	["check-line"] = "rbxassetid://115122343485290",
	["check"] = "rbxassetid://93898873302694",
	["chef-hat"] = "rbxassetid://121744015002573",
	["cherry"] = "rbxassetid://139519182403183",
	["chess-bishop"] = "rbxassetid://121701705580238",
	["chess-king"] = "rbxassetid://90885687223462",
	["chess-knight"] = "rbxassetid://96467707042169",
	["chess-pawn"] = "rbxassetid://111318574652751",
	["chess-queen"] = "rbxassetid://98304702099749",
	["chess-rook"] = "rbxassetid://76223925830262",
	["chevron-down"] = "rbxassetid://134243273101015",
	["chevron-first"] = "rbxassetid://105243363790238",
	["chevron-last"] = "rbxassetid://89268452603731",
	["chevron-left"] = "rbxassetid://73780377692148",
	["chevron-right"] = "rbxassetid://92473583511724",
	["chevron-up"] = "rbxassetid://122444883127455",
	["chevrons-down-up"] = "rbxassetid://139404716013205",
	["chevrons-down"] = "rbxassetid://100524612205956",
	["chevrons-left-right-ellipsis"] = "rbxassetid://125035817741526",
	["chevrons-left-right"] = "rbxassetid://87910685945204",
	["chevrons-left"] = "rbxassetid://82617201744347",
	["chevrons-right-left"] = "rbxassetid://87149546686569",
	["chevrons-right"] = "rbxassetid://139121276490483",
	["chevrons-up-down"] = "rbxassetid://131833120209646",
	["chevrons-up"] = "rbxassetid://100467452364672",
	["chromium"] = "rbxassetid://128165143739006",
	["church"] = "rbxassetid://113714744350666",
	["cigarette-off"] = "rbxassetid://77797883078452",
	["circle-alert"] = "rbxassetid://83898160590116",
	["circle-arrow-down"] = "rbxassetid://95901860261344",
	["circle-arrow-left"] = "rbxassetid://102148876968988",
	["circle-arrow-out-down-left"] = "rbxassetid://140598097856694",
	["circle-arrow-out-down-right"] = "rbxassetid://119952801379305",
	["circle-arrow-out-up-left"] = "rbxassetid://132858212688303",
	["circle-arrow-out-up-right"] = "rbxassetid://81783743753173",
	["circle-arrow-right"] = "rbxassetid://70786767999559",
	["circle-arrow-up"] = "rbxassetid://84395128546494",
	["circle-check-big"] = "rbxassetid://93202927221730",
	["circle-check"] = "rbxassetid://85262178816537",
	["circle-chevron-down"] = "rbxassetid://137069490345718",
	["circle-chevron-left"] = "rbxassetid://130250009740827",
	["circle-chevron-right"] = "rbxassetid://125943696958495",
	["circle-chevron-up"] = "rbxassetid://111223574026321",
	["circle-dashed"] = "rbxassetid://126799443883746",
	["circle-divide"] = "rbxassetid://106398997754208",
	["circle-dollar-sign"] = "rbxassetid://91106238890387",
	["circle-dot-dashed"] = "rbxassetid://111451232827180",
	["circle-dot"] = "rbxassetid://82947033619201",
	["circle-ellipsis"] = "rbxassetid://91687150884779",
	["circle-equal"] = "rbxassetid://95133963751438",
	["circle-fading-arrow-up"] = "rbxassetid://104648212910336",
	["circle-fading-plus"] = "rbxassetid://91847890443490",
	["circle-gauge"] = "rbxassetid://108157549473765",
	["circle-minus"] = "rbxassetid://133556159576809",
	["circle-off"] = "rbxassetid://97923456918886",
	["circle-parking-off"] = "rbxassetid://128369410981252",
	["circle-parking"] = "rbxassetid://124034962915196",
	["circle-pause"] = "rbxassetid://139337739700879",
	["circle-percent"] = "rbxassetid://133311912860256",
	["circle-play"] = "rbxassetid://120408917249739",
	["circle-plus"] = "rbxassetid://113157136350384",
	["circle-pound-sterling"] = "rbxassetid://105476153083828",
	["circle-power"] = "rbxassetid://140676030155098",
	["circle-question-mark"] = "rbxassetid://97516698664325",
	["circle-slash-2"] = "rbxassetid://136766902186549",
	["circle-slash"] = "rbxassetid://125206439913049",
	["circle-small"] = "rbxassetid://73685402843600",
	["circle-star"] = "rbxassetid://120318414957104",
	["circle-stop"] = "rbxassetid://87400503942659",
	["circle-user-round"] = "rbxassetid://95489465399880",
	["circle-user"] = "rbxassetid://136220511671311",
	["circle-x"] = "rbxassetid://76821953846248",
	["circle"] = "rbxassetid://130359823580534",
	["circuit-board"] = "rbxassetid://107695264369312",
	["citrus"] = "rbxassetid://139018222976433",
	["clapperboard"] = "rbxassetid://132660667070200",
	["clipboard-check"] = "rbxassetid://92649798577170",
	["clipboard-clock"] = "rbxassetid://123957515687745",
	["clipboard-copy"] = "rbxassetid://125851897718493",
	["clipboard-list"] = "rbxassetid://96460215958908",
	["clipboard-minus"] = "rbxassetid://107968008485671",
	["clipboard-paste"] = "rbxassetid://74382068849983",
	["clipboard-pen-line"] = "rbxassetid://77711589791615",
	["clipboard-pen"] = "rbxassetid://75290966822953",
	["clipboard-plus"] = "rbxassetid://134285318675662",
	["clipboard-type"] = "rbxassetid://89949374318028",
	["clipboard-x"] = "rbxassetid://102222456890103",
	["clipboard"] = "rbxassetid://89601995828423",
	["clock-1"] = "rbxassetid://129363225422045",
	["clock-10"] = "rbxassetid://104332695855541",
	["clock-11"] = "rbxassetid://119023205186105",
	["clock-12"] = "rbxassetid://117789618723068",
	["clock-2"] = "rbxassetid://134710777209413",
	["clock-3"] = "rbxassetid://136385631189327",
	["clock-4"] = "rbxassetid://121808839832144",
	["clock-5"] = "rbxassetid://85082019959457",
	["clock-6"] = "rbxassetid://71009733505593",
	["clock-7"] = "rbxassetid://103111188546225",
	["clock-8"] = "rbxassetid://110059272125337",
	["clock-9"] = "rbxassetid://77610027126437",
	["clock-alert"] = "rbxassetid://97157344465162",
	["clock-arrow-down"] = "rbxassetid://92349314416042",
	["clock-arrow-up"] = "rbxassetid://111484286332629",
	["clock-check"] = "rbxassetid://85231630218857",
	["clock-fading"] = "rbxassetid://93205297285245",
	["clock-plus"] = "rbxassetid://93367709263150",
	["clock"] = "rbxassetid://121808839832144",
	["closed-caption"] = "rbxassetid://99832644030788",
	["cloud-alert"] = "rbxassetid://91967273658626",
	["cloud-check"] = "rbxassetid://97318598202432",
	["cloud-cog"] = "rbxassetid://96497764065749",
	["cloud-download"] = "rbxassetid://121435581993566",
	["cloud-drizzle"] = "rbxassetid://139525315752605",
	["cloud-fog"] = "rbxassetid://76650233148776",
	["cloud-hail"] = "rbxassetid://72320462748242",
	["cloud-lightning"] = "rbxassetid://133517088924849",
	["cloud-moon-rain"] = "rbxassetid://127667837827018",
	["cloud-moon"] = "rbxassetid://71938114737914",
	["cloud-off"] = "rbxassetid://131907154501444",
	["cloud-rain-wind"] = "rbxassetid://107414583736721",
	["cloud-rain"] = "rbxassetid://105547081967408",
	["cloud-snow"] = "rbxassetid://72307126270226",
	["cloud-sun-rain"] = "rbxassetid://99041604425705",
	["cloud-sun"] = "rbxassetid://86114208148727",
	["cloud-upload"] = "rbxassetid://93307473217005",
	["cloud"] = "rbxassetid://121226497050352",
	["cloudy"] = "rbxassetid://105360479023346",
	["clover"] = "rbxassetid://74925550436750",
	["club"] = "rbxassetid://108490365816628",
	["code-xml"] = "rbxassetid://130150477351734",
	["code"] = "rbxassetid://107380207681249",
	["codepen"] = "rbxassetid://135643965971885",
	["codesandbox"] = "rbxassetid://106911852964823",
	["coffee"] = "rbxassetid://106864403231093",
	["cog"] = "rbxassetid://116544501716299",
	["coins"] = "rbxassetid://116510979641930",
	["columns-2"] = "rbxassetid://113004100221850",
	["columns-3-cog"] = "rbxassetid://121589691981064",
	["columns-3"] = "rbxassetid://115223357399375",
	["columns-4"] = "rbxassetid://130807991968419",
	["combine"] = "rbxassetid://79908476334048",
	["command"] = "rbxassetid://93648221906330",
	["compass"] = "rbxassetid://115123411028382",
	["component"] = "rbxassetid://110027788875080",
	["computer"] = "rbxassetid://77480056459407",
	["concierge-bell"] = "rbxassetid://140384259310436",
	["cone"] = "rbxassetid://97759550688437",
	["construction"] = "rbxassetid://106539489968173",
	["contact-round"] = "rbxassetid://71907624112229",
	["contact"] = "rbxassetid://75868297719012",
	["container"] = "rbxassetid://91507237573499",
	["contrast"] = "rbxassetid://112796643981497",
	["cookie"] = "rbxassetid://73159504540002",
	["cooking-pot"] = "rbxassetid://94959783129799",
	["copy-check"] = "rbxassetid://91177247988892",
	["copy-minus"] = "rbxassetid://109524509933035",
	["copy-plus"] = "rbxassetid://113618379616952",
	["copy-slash"] = "rbxassetid://93805787810390",
	["copy-x"] = "rbxassetid://106557557978061",
	["copy"] = "rbxassetid://78979572434545",
	["copyleft"] = "rbxassetid://78559055698593",
	["copyright"] = "rbxassetid://129433635747111",
	["corner-down-left"] = "rbxassetid://90473561177832",
	["corner-down-right"] = "rbxassetid://86512767702085",
	["corner-left-down"] = "rbxassetid://139876989150630",
	["corner-left-up"] = "rbxassetid://126228268096099",
	["corner-right-down"] = "rbxassetid://89237035551302",
	["corner-right-up"] = "rbxassetid://112851237026705",
	["corner-up-left"] = "rbxassetid://84669279763024",
	["corner-up-right"] = "rbxassetid://115099889693145",
	["cpu"] = "rbxassetid://77549309870247",
	["creative-commons"] = "rbxassetid://90408210735312",
	["credit-card"] = "rbxassetid://99163352872346",
	["croissant"] = "rbxassetid://130710485559420",
	["crop"] = "rbxassetid://116344601101413",
	["cross"] = "rbxassetid://101833377863588",
	["crosshair"] = "rbxassetid://134242818164054",
	["crown"] = "rbxassetid://127843403295538",
	["cuboid"] = "rbxassetid://75618807946111",
	["cup-soda"] = "rbxassetid://121098640829562",
	["currency"] = "rbxassetid://90551250119972",
	["cylinder"] = "rbxassetid://90569677179169",
	["dam"] = "rbxassetid://76874486231393",
	["database-backup"] = "rbxassetid://103403210984699",
	["database-zap"] = "rbxassetid://131199921258418",
	["database"] = "rbxassetid://126791525623846",
	["decimals-arrow-left"] = "rbxassetid://120198500638749",
	["decimals-arrow-right"] = "rbxassetid://118263047146797",
	["delete"] = "rbxassetid://126279426372342",
	["dessert"] = "rbxassetid://71508133278830",
	["diameter"] = "rbxassetid://97429051503783",
	["diamond-minus"] = "rbxassetid://128989071438290",
	["diamond-percent"] = "rbxassetid://107717860105959",
	["diamond-plus"] = "rbxassetid://134701163723675",
	["diamond"] = "rbxassetid://105846996304890",
	["dice-1"] = "rbxassetid://112650149591038",
	["dice-2"] = "rbxassetid://112278274566793",
	["dice-3"] = "rbxassetid://118526270626312",
	["dice-4"] = "rbxassetid://113365650364004",
	["dice-5"] = "rbxassetid://72768312430593",
	["dice-6"] = "rbxassetid://85376239182543",
	["dices"] = "rbxassetid://81268120302865",
	["diff"] = "rbxassetid://135052708609715",
	["disc-2"] = "rbxassetid://91419420404185",
	["disc-3"] = "rbxassetid://135470554736048",
	["disc-album"] = "rbxassetid://74693460404344",
	["disc"] = "rbxassetid://101908120120777",
	["divide"] = "rbxassetid://136678191878278",
	["dna-off"] = "rbxassetid://89612426361540",
	["dna"] = "rbxassetid://74007982981741",
	["dock"] = "rbxassetid://121997427160252",
	["dog"] = "rbxassetid://71920105558570",
	["dollar-sign"] = "rbxassetid://127320961224019",
	["donut"] = "rbxassetid://72204922742657",
	["door-closed-locked"] = "rbxassetid://74027613267551",
	["door-closed"] = "rbxassetid://136249099949073",
	["door-open"] = "rbxassetid://91306356501736",
	["dot"] = "rbxassetid://137321056643916",
	["download"] = "rbxassetid://134814648082393",
	["drafting-compass"] = "rbxassetid://99701976182841",
	["drama"] = "rbxassetid://110297795801577",
	["dribbble"] = "rbxassetid://80231809663849",
	["drill"] = "rbxassetid://108644821412796",
	["drone"] = "rbxassetid://117299095794783",
	["droplet-off"] = "rbxassetid://119365002225172",
	["droplet"] = "rbxassetid://100597455015098",
	["droplets"] = "rbxassetid://140111846025180",
	["drum"] = "rbxassetid://136979060344890",
	["drumstick"] = "rbxassetid://104662462521709",
	["dumbbell"] = "rbxassetid://80277236776212",
	["ear-off"] = "rbxassetid://87421916192807",
	["ear"] = "rbxassetid://121894949934209",
	["earth-lock"] = "rbxassetid://88814147073745",
	["earth"] = "rbxassetid://76231597751076",
	["eclipse"] = "rbxassetid://114829622118222",
	["egg-fried"] = "rbxassetid://90622538210545",
	["egg-off"] = "rbxassetid://92288321309285",
	["egg"] = "rbxassetid://117851493400222",
	["ellipsis-vertical"] = "rbxassetid://117978708573781",
	["ellipsis"] = "rbxassetid://140019550645825",
	["equal-approximately"] = "rbxassetid://105382689698323",
	["equal-not"] = "rbxassetid://76864449458032",
	["equal"] = "rbxassetid://123467780715624",
	["eraser"] = "rbxassetid://133957773112410",
	["ethernet-port"] = "rbxassetid://75391715149314",
	["euro"] = "rbxassetid://72229646524456",
	["ev-charger"] = "rbxassetid://97906158859623",
	["expand"] = "rbxassetid://137492887754537",
	["external-link"] = "rbxassetid://129331830773832",
	["eye-closed"] = "rbxassetid://111063268625789",
	["eye-off"] = "rbxassetid://135928786788378",
	["eye"] = "rbxassetid://100033680381365",
	["facebook"] = "rbxassetid://72098528632192",
	["factory"] = "rbxassetid://102170024318039",
	["fan"] = "rbxassetid://78391400440696",
	["fast-forward"] = "rbxassetid://121615540167909",
	["feather"] = "rbxassetid://91872927606406",
	["fence"] = "rbxassetid://123451565578029",
	["ferris-wheel"] = "rbxassetid://79729205796176",
	["figma"] = "rbxassetid://134182122852301",
	["file-archive"] = "rbxassetid://77018106869967",
	["file-axis-3d"] = "rbxassetid://133912328009885",
	["file-badge"] = "rbxassetid://74564895394477",
	["file-box"] = "rbxassetid://119264004071690",
	["file-braces-corner"] = "rbxassetid://77253337986109",
	["file-braces"] = "rbxassetid://95314128621234",
	["file-chart-column-increasing"] = "rbxassetid://134449481172067",
	["file-chart-column"] = "rbxassetid://82048481252560",
	["file-chart-line"] = "rbxassetid://71954360551345",
	["file-chart-pie"] = "rbxassetid://81072193564497",
	["file-check-corner"] = "rbxassetid://76295552859171",
	["file-check"] = "rbxassetid://82604001452455",
	["file-clock"] = "rbxassetid://102325208830990",
	["file-code-corner"] = "rbxassetid://78293841184371",
	["file-code"] = "rbxassetid://130978036895504",
	["file-cog"] = "rbxassetid://101385347151368",
	["file-diff"] = "rbxassetid://96147216772241",
	["file-digit"] = "rbxassetid://89220220354580",
	["file-down"] = "rbxassetid://120650154178290",
	["file-exclamation-point"] = "rbxassetid://102821865889635",
	["file-headphone"] = "rbxassetid://100533735901986",
	["file-heart"] = "rbxassetid://132214916401696",
	["file-image"] = "rbxassetid://123334057511782",
	["file-input"] = "rbxassetid://124728604166044",
	["file-key"] = "rbxassetid://118790255921100",
	["file-lock"] = "rbxassetid://72170228691242",
	["file-minus-corner"] = "rbxassetid://119263271735124",
	["file-minus"] = "rbxassetid://111014798459222",
	["file-music"] = "rbxassetid://134948051536671",
	["file-output"] = "rbxassetid://92146832572911",
	["file-pen-line"] = "rbxassetid://104622936345006",
	["file-pen"] = "rbxassetid://79556179730240",
	["file-play"] = "rbxassetid://89006821567838",
	["file-plus-corner"] = "rbxassetid://76544604043974",
	["file-plus"] = "rbxassetid://78881710800060",
	["file-question-mark"] = "rbxassetid://127617422859576",
	["file-scan"] = "rbxassetid://129480105228213",
	["file-search-corner"] = "rbxassetid://90974165234008",
	["file-search"] = "rbxassetid://97780235974933",
	["file-signal"] = "rbxassetid://122070252538165",
	["file-sliders"] = "rbxassetid://85787771732439",
	["file-spreadsheet"] = "rbxassetid://134501869359270",
	["file-stack"] = "rbxassetid://138929929862605",
	["file-symlink"] = "rbxassetid://91865722036510",
	["file-terminal"] = "rbxassetid://116757454755476",
	["file-text"] = "rbxassetid://90496405707281",
	["file-type-corner"] = "rbxassetid://124902230275209",
	["file-type"] = "rbxassetid://115272552799361",
	["file-up"] = "rbxassetid://131173039312748",
	["file-user"] = "rbxassetid://99552018455009",
	["file-video-camera"] = "rbxassetid://81719056173960",
	["file-volume"] = "rbxassetid://111264764438958",
	["file-x-corner"] = "rbxassetid://87554136773609",
	["file-x"] = "rbxassetid://107333775515154",
	["file"] = "rbxassetid://74748492079329",
	["files"] = "rbxassetid://102806336233202",
	["film"] = "rbxassetid://120978945609706",
	["fingerprint"] = "rbxassetid://112173305232811",
	["fire-extinguisher"] = "rbxassetid://111643493006960",
	["fish-off"] = "rbxassetid://89756724887508",
	["fish-symbol"] = "rbxassetid://118475177681618",
	["fish"] = "rbxassetid://124360663785796",
	["flag-off"] = "rbxassetid://112944528856799",
	["flag-triangle-left"] = "rbxassetid://88045221285272",
	["flag-triangle-right"] = "rbxassetid://108292480304566",
	["flag"] = "rbxassetid://78183383236196",
	["flame-kindling"] = "rbxassetid://139728976917928",
	["flame"] = "rbxassetid://98218034436456",
	["flashlight-off"] = "rbxassetid://79780362871740",
	["flashlight"] = "rbxassetid://100286985600444",
	["flask-conical-off"] = "rbxassetid://112597970025298",
	["flask-conical"] = "rbxassetid://128406680901165",
	["flask-round"] = "rbxassetid://127508287324940",
	["flip-horizontal-2"] = "rbxassetid://103726993598186",
	["flip-horizontal"] = "rbxassetid://122937530107837",
	["flip-vertical-2"] = "rbxassetid://103836358956328",
	["flip-vertical"] = "rbxassetid://108003917346888",
	["flower-2"] = "rbxassetid://72934574245145",
	["flower"] = "rbxassetid://86129438272762",
	["focus"] = "rbxassetid://87493973153317",
	["fold-horizontal"] = "rbxassetid://92835712442240",
	["fold-vertical"] = "rbxassetid://108873727253656",
	["folder-archive"] = "rbxassetid://97312009460206",
	["folder-check"] = "rbxassetid://128492920904557",
	["folder-clock"] = "rbxassetid://111964836738545",
	["folder-closed"] = "rbxassetid://118286209350843",
	["folder-code"] = "rbxassetid://70624096349370",
	["folder-cog"] = "rbxassetid://85299519462846",
	["folder-dot"] = "rbxassetid://138687772725278",
	["folder-down"] = "rbxassetid://118044108459225",
	["folder-git-2"] = "rbxassetid://101394054141166",
	["folder-git"] = "rbxassetid://121885778095158",
	["folder-heart"] = "rbxassetid://79104747211105",
	["folder-input"] = "rbxassetid://90699920697871",
	["folder-kanban"] = "rbxassetid://78313285104072",
	["folder-key"] = "rbxassetid://85270407596791",
	["folder-lock"] = "rbxassetid://119201572260567",
	["folder-minus"] = "rbxassetid://85648718999010",
	["folder-open-dot"] = "rbxassetid://74741494767354",
	["folder-open"] = "rbxassetid://76018996254888",
	["folder-output"] = "rbxassetid://101532447937612",
	["folder-pen"] = "rbxassetid://112770491173911",
	["folder-plus"] = "rbxassetid://91865663406119",
	["folder-root"] = "rbxassetid://103333751154693",
	["folder-search-2"] = "rbxassetid://71276453442655",
	["folder-search"] = "rbxassetid://110568075123861",
	["folder-symlink"] = "rbxassetid://127485747227189",
	["folder-sync"] = "rbxassetid://91544602659796",
	["folder-tree"] = "rbxassetid://85577554337861",
	["folder-up"] = "rbxassetid://72008269765857",
	["folder-x"] = "rbxassetid://91699618247635",
	["folder"] = "rbxassetid://80846616596607",
	["folders"] = "rbxassetid://110351216219061",
	["footprints"] = "rbxassetid://139192589041315",
	["forklift"] = "rbxassetid://72030930983101",
	["forward"] = "rbxassetid://97545944739523",
	["frame"] = "rbxassetid://109080612832751",
	["framer"] = "rbxassetid://108384807262391",
	["frown"] = "rbxassetid://124407301067982",
	["fuel"] = "rbxassetid://106447647274511",
	["fullscreen"] = "rbxassetid://77793665526178",
	["funnel-plus"] = "rbxassetid://100780233821928",
	["funnel-x"] = "rbxassetid://70984385812555",
	["funnel"] = "rbxassetid://108829540827529",
	["gallery-horizontal-end"] = "rbxassetid://74672430161161",
	["gallery-horizontal"] = "rbxassetid://80004001442122",
	["gallery-thumbnails"] = "rbxassetid://136219289862706",
	["gallery-vertical-end"] = "rbxassetid://106461402088317",
	["gallery-vertical"] = "rbxassetid://119299431466725",
	["gamepad-2"] = "rbxassetid://92483947987410",
	["gamepad-directional"] = "rbxassetid://84342305212226",
	["gamepad"] = "rbxassetid://121607283959010",
	["gauge"] = "rbxassetid://110273524101447",
	["gavel"] = "rbxassetid://78952298198456",
	["gem"] = "rbxassetid://112904952151156",
	["georgian-lari"] = "rbxassetid://98084432591687",
	["ghost"] = "rbxassetid://113822048130017",
	["gift"] = "rbxassetid://109855212076373",
	["git-branch-minus"] = "rbxassetid://97385010649411",
	["git-branch-plus"] = "rbxassetid://125944221134316",
	["git-branch"] = "rbxassetid://90490195516649",
	["git-commit-horizontal"] = "rbxassetid://133646041800147",
	["git-commit-vertical"] = "rbxassetid://122098032990350",
	["git-compare-arrows"] = "rbxassetid://84874426520216",
	["git-compare"] = "rbxassetid://91945124438792",
	["git-fork"] = "rbxassetid://89954992404765",
	["git-graph"] = "rbxassetid://86166832019304",
	["git-merge"] = "rbxassetid://131833355158059",
	["git-pull-request-arrow"] = "rbxassetid://94507974577439",
	["git-pull-request-closed"] = "rbxassetid://78070600389091",
	["git-pull-request-create-arrow"] = "rbxassetid://127422677061091",
	["git-pull-request-create"] = "rbxassetid://105929577383926",
	["git-pull-request-draft"] = "rbxassetid://76173459869943",
	["git-pull-request"] = "rbxassetid://138463010991471",
	["github"] = "rbxassetid://120349554354380",
	["gitlab"] = "rbxassetid://114054627192933",
	["glass-water"] = "rbxassetid://115526102400988",
	["glasses"] = "rbxassetid://87936407455373",
	["globe-lock"] = "rbxassetid://134065526704402",
	["globe"] = "rbxassetid://114238209622913",
	["goal"] = "rbxassetid://120517954878160",
	["gpu"] = "rbxassetid://95577823614219",
	["graduation-cap"] = "rbxassetid://93771896340220",
	["grape"] = "rbxassetid://134760640415561",
	["grid-2x2-check"] = "rbxassetid://138468840220821",
	["grid-2x2-plus"] = "rbxassetid://91811610580247",
	["grid-2x2-x"] = "rbxassetid://72407303981388",
	["grid-2x2"] = "rbxassetid://99050491897640",
	["grid-3x2"] = "rbxassetid://95528684210010",
	["grid-3x3"] = "rbxassetid://70419024781206",
	["grip-horizontal"] = "rbxassetid://136255899715930",
	["grip-vertical"] = "rbxassetid://137183678565296",
	["grip"] = "rbxassetid://109058783556768",
	["group"] = "rbxassetid://107643418926671",
	["guitar"] = "rbxassetid://75915531867926",
	["ham"] = "rbxassetid://74465607934635",
	["hamburger"] = "rbxassetid://93086916815495",
	["hammer"] = "rbxassetid://83545120140895",
	["hand-coins"] = "rbxassetid://126990543175462",
	["hand-fist"] = "rbxassetid://83341608917591",
	["hand-grab"] = "rbxassetid://88867162163985",
	["hand-heart"] = "rbxassetid://117507367668412",
	["hand-helping"] = "rbxassetid://89897738419446",
	["hand-metal"] = "rbxassetid://113619498548713",
	["hand-platter"] = "rbxassetid://88594727743168",
	["hand"] = "rbxassetid://130703864968637",
	["handbag"] = "rbxassetid://135675846264061",
	["handshake"] = "rbxassetid://78442115255814",
	["hard-drive-download"] = "rbxassetid://73913801230614",
	["hard-drive-upload"] = "rbxassetid://85762133615118",
	["hard-drive"] = "rbxassetid://88183305858463",
	["hard-hat"] = "rbxassetid://128050846767382",
	["hash"] = "rbxassetid://82890331678520",
	["hat-glasses"] = "rbxassetid://101165538224815",
	["haze"] = "rbxassetid://108857561768901",
	["hdmi-port"] = "rbxassetid://103693661037020",
	["heading-1"] = "rbxassetid://118129315662110",
	["heading-2"] = "rbxassetid://110209069670094",
	["heading-3"] = "rbxassetid://90267885237062",
	["heading-4"] = "rbxassetid://129625620307602",
	["heading-5"] = "rbxassetid://120386663181267",
	["heading-6"] = "rbxassetid://90959079775093",
	["heading"] = "rbxassetid://129254312067735",
	["headphone-off"] = "rbxassetid://85038251615641",
	["headphones"] = "rbxassetid://118833729589183",
	["headset"] = "rbxassetid://129269236787694",
	["heart-crack"] = "rbxassetid://110987638564119",
	["heart-handshake"] = "rbxassetid://111483078692002",
	["heart-minus"] = "rbxassetid://96827380163326",
	["heart-off"] = "rbxassetid://89748414415617",
	["heart-plus"] = "rbxassetid://94877796283249",
	["heart-pulse"] = "rbxassetid://129352925579546",
	["heart"] = "rbxassetid://116559368303288",
	["heater"] = "rbxassetid://140478466880916",
	["helicopter"] = "rbxassetid://111557171735930",
	["hexagon"] = "rbxassetid://127592089339199",
	["highlighter"] = "rbxassetid://77411555641113",
	["history"] = "rbxassetid://123980022019922",
	["hop-off"] = "rbxassetid://103386036934034",
	["hop"] = "rbxassetid://82778923997672",
	["hospital"] = "rbxassetid://105868763850707",
	["hotel"] = "rbxassetid://132283390859718",
	["hourglass"] = "rbxassetid://86160434939203",
	["house-heart"] = "rbxassetid://136054771868597",
	["house-plug"] = "rbxassetid://71438263712075",
	["house-plus"] = "rbxassetid://118495165208309",
	["house-wifi"] = "rbxassetid://126495519725698",
	["house"] = "rbxassetid://98755624629571",
	["ice-cream-bowl"] = "rbxassetid://124867218454386",
	["ice-cream-cone"] = "rbxassetid://90751397288639",
	["id-card-lanyard"] = "rbxassetid://90761480469224",
	["id-card"] = "rbxassetid://75354294622640",
	["image-down"] = "rbxassetid://78972295741235",
	["image-minus"] = "rbxassetid://101066016918565",
	["image-off"] = "rbxassetid://81934811700938",
	["image-play"] = "rbxassetid://129501806784210",
	["image-plus"] = "rbxassetid://70391970623917",
	["image-up"] = "rbxassetid://126610009605241",
	["image-upscale"] = "rbxassetid://106963545024679",
	["images"] = "rbxassetid://79350649395557",
	["import"] = "rbxassetid://116545008906029",
	["inbox"] = "rbxassetid://112591360302868",
	["indian-rupee"] = "rbxassetid://113038778381805",
	["infinity"] = "rbxassetid://98083086936965",
	["info"] = "rbxassetid://124560466474914",
	["inspection-panel"] = "rbxassetid://70905313146088",
	["instagram"] = "rbxassetid://119864798614855",
	["italic"] = "rbxassetid://96220378864282",
	["iteration-ccw"] = "rbxassetid://140221832794083",
	["iteration-cw"] = "rbxassetid://95534489554662",
	["japanese-yen"] = "rbxassetid://106362863465813",
	["joystick"] = "rbxassetid://99416790224739",
	["kanban"] = "rbxassetid://125934100055431",
	["kayak"] = "rbxassetid://136107544609389",
	["key-round"] = "rbxassetid://83619031955390",
	["key-square"] = "rbxassetid://94621420033649",
	["key"] = "rbxassetid://96510194465420",
	["keyboard-music"] = "rbxassetid://121058541758636",
	["keyboard-off"] = "rbxassetid://92466375369772",
	["keyboard"] = "rbxassetid://121474456068237",
	["lamp-ceiling"] = "rbxassetid://80032758469141",
	["lamp-desk"] = "rbxassetid://85290686983238",
	["lamp-floor"] = "rbxassetid://104585881375892",
	["lamp-wall-down"] = "rbxassetid://91271394132073",
	["lamp-wall-up"] = "rbxassetid://132141464337445",
	["lamp"] = "rbxassetid://110730830653382",
	["land-plot"] = "rbxassetid://96449039620294",
	["landmark"] = "rbxassetid://76885079756393",
	["languages"] = "rbxassetid://90816903776498",
	["laptop-minimal-check"] = "rbxassetid://114352019833865",
	["laptop-minimal"] = "rbxassetid://136705765566068",
	["laptop"] = "rbxassetid://111387063244975",
	["lasso-select"] = "rbxassetid://105609719912753",
	["lasso"] = "rbxassetid://121072936884007",
	["laugh"] = "rbxassetid://104491311361166",
	["layers-2"] = "rbxassetid://70536710516357",
	["layers"] = "rbxassetid://81973586053257",
	["layout-dashboard"] = "rbxassetid://139929981863901",
	["layout-grid"] = "rbxassetid://81344910161871",
	["layout-list"] = "rbxassetid://87462136296578",
	["layout-panel-left"] = "rbxassetid://125092469751491",
	["layout-panel-top"] = "rbxassetid://91943941515944",
	["layout-template"] = "rbxassetid://115564446417985",
	["leaf"] = "rbxassetid://119951075637174",
	["leafy-green"] = "rbxassetid://105146290493154",
	["lectern"] = "rbxassetid://106166425183862",
	["library-big"] = "rbxassetid://106794530191412",
	["library"] = "rbxassetid://114334671982047",
	["life-buoy"] = "rbxassetid://81168450671956",
	["ligature"] = "rbxassetid://111397873269411",
	["lightbulb-off"] = "rbxassetid://83795722296178",
	["lightbulb"] = "rbxassetid://103871245626488",
	["line-squiggle"] = "rbxassetid://109555164424447",
	["link-2-off"] = "rbxassetid://76885956296867",
	["link-2"] = "rbxassetid://86072351557466",
	["link"] = "rbxassetid://131607023382430",
	["linkedin"] = "rbxassetid://132842789255788",
	["list-check"] = "rbxassetid://72374358471156",
	["list-checks"] = "rbxassetid://99809353635593",
	["list-chevrons-down-up"] = "rbxassetid://137409641500711",
	["list-chevrons-up-down"] = "rbxassetid://81825351389084",
	["list-collapse"] = "rbxassetid://124505247702401",
	["list-end"] = "rbxassetid://77650610048119",
	["list-filter-plus"] = "rbxassetid://96385120752336",
	["list-filter"] = "rbxassetid://103321376129527",
	["list-indent-decrease"] = "rbxassetid://137879979228193",
	["list-indent-increase"] = "rbxassetid://79051053161201",
	["list-minus"] = "rbxassetid://138507965142671",
	["list-music"] = "rbxassetid://126380635781840",
	["list-ordered"] = "rbxassetid://83212528113913",
	["list-plus"] = "rbxassetid://112384738137814",
	["list-restart"] = "rbxassetid://91703153577421",
	["list-start"] = "rbxassetid://84828348299727",
	["list-todo"] = "rbxassetid://132980603752108",
	["list-tree"] = "rbxassetid://97685396239010",
	["list-video"] = "rbxassetid://93648525452489",
	["list-x"] = "rbxassetid://113025303988861",
	["list"] = "rbxassetid://113179976918783",
	["loader-circle"] = "rbxassetid://116535712789945",
	["loader-pinwheel"] = "rbxassetid://108513357940900",
	["loader"] = "rbxassetid://78408734580845",
	["locate-fixed"] = "rbxassetid://137367361548433",
	["locate-off"] = "rbxassetid://73729216338137",
	["locate"] = "rbxassetid://84467676590391",
	["lock-keyhole-open"] = "rbxassetid://110863509313073",
	["lock-keyhole"] = "rbxassetid://78672912777756",
	["lock-open"] = "rbxassetid://93597915325122",
	["lock"] = "rbxassetid://134724289526879",
	["log-in"] = "rbxassetid://103768533135201",
	["log-out"] = "rbxassetid://84895399304975",
	["logs"] = "rbxassetid://89772091251787",
	["lollipop"] = "rbxassetid://84681611583044",
	["luggage"] = "rbxassetid://76619236486400",
	["magnet"] = "rbxassetid://135162361226972",
	["mail-check"] = "rbxassetid://86921536259917",
	["mail-minus"] = "rbxassetid://81989813236553",
	["mail-open"] = "rbxassetid://122785416858638",
	["mail-plus"] = "rbxassetid://104886401588341",
	["mail-question-mark"] = "rbxassetid://126540170949819",
	["mail-search"] = "rbxassetid://135616173775287",
	["mail-warning"] = "rbxassetid://81495303676089",
	["mail-x"] = "rbxassetid://74607841705644",
	["mail"] = "rbxassetid://103945161245599",
	["mailbox"] = "rbxassetid://82765503320335",
	["mails"] = "rbxassetid://90673453450080",
	["map-minus"] = "rbxassetid://129525760577747",
	["map-pin-check-inside"] = "rbxassetid://107130529843809",
	["map-pin-check"] = "rbxassetid://118110914690154",
	["map-pin-house"] = "rbxassetid://80546885029816",
	["map-pin-minus-inside"] = "rbxassetid://79005529692964",
	["map-pin-minus"] = "rbxassetid://74518762643623",
	["map-pin-off"] = "rbxassetid://82474689391020",
	["map-pin-pen"] = "rbxassetid://113515395277504",
	["map-pin-plus-inside"] = "rbxassetid://134639656514430",
	["map-pin-plus"] = "rbxassetid://91875228967029",
	["map-pin-x-inside"] = "rbxassetid://126235934252379",
	["map-pin-x"] = "rbxassetid://101085273547316",
	["map-pin"] = "rbxassetid://84279202219901",
	["map-pinned"] = "rbxassetid://103963788475034",
	["map-plus"] = "rbxassetid://129388826743495",
	["map"] = "rbxassetid://95107167260947",
	["mars-stroke"] = "rbxassetid://131973193186828",
	["mars"] = "rbxassetid://111287112372511",
	["martini"] = "rbxassetid://82977695401058",
	["maximize-2"] = "rbxassetid://73085922906397",
	["maximize"] = "rbxassetid://76045941763188",
	["medal"] = "rbxassetid://79016002264450",
	["megaphone-off"] = "rbxassetid://124280774193935",
	["megaphone"] = "rbxassetid://118759541854879",
	["meh"] = "rbxassetid://132197867028557",
	["memory-stick"] = "rbxassetid://93212591343119",
	["menu"] = "rbxassetid://77021539815611",
	["merge"] = "rbxassetid://126201866476775",
	["message-circle-code"] = "rbxassetid://112865244991651",
	["message-circle-dashed"] = "rbxassetid://81525157881897",
	["message-circle-heart"] = "rbxassetid://101990756073677",
	["message-circle-more"] = "rbxassetid://92856823884663",
	["message-circle-off"] = "rbxassetid://134955643890328",
	["message-circle-plus"] = "rbxassetid://106562979649273",
	["message-circle-question-mark"] = "rbxassetid://107700302759934",
	["message-circle-reply"] = "rbxassetid://137071749508334",
	["message-circle-warning"] = "rbxassetid://119020096067894",
	["message-circle-x"] = "rbxassetid://126843387725536",
	["message-circle"] = "rbxassetid://127255077587058",
	["message-square-code"] = "rbxassetid://110968863152123",
	["message-square-dashed"] = "rbxassetid://107653455516238",
	["message-square-diff"] = "rbxassetid://75472190472625",
	["message-square-dot"] = "rbxassetid://127806382463916",
	["message-square-heart"] = "rbxassetid://75612811742074",
	["message-square-lock"] = "rbxassetid://81268215619563",
	["message-square-more"] = "rbxassetid://120139782405970",
	["message-square-off"] = "rbxassetid://99961019005789",
	["message-square-plus"] = "rbxassetid://76934450256199",
	["message-square-quote"] = "rbxassetid://116670768629340",
	["message-square-reply"] = "rbxassetid://130985622754637",
	["message-square-share"] = "rbxassetid://131017005324026",
	["message-square-text"] = "rbxassetid://94899503194205",
	["message-square-warning"] = "rbxassetid://138432903962261",
	["message-square-x"] = "rbxassetid://137285463279462",
	["message-square"] = "rbxassetid://83881670383280",
	["messages-square"] = "rbxassetid://97532166733358",
	["mic-off"] = "rbxassetid://82123034444822",
	["mic-vocal"] = "rbxassetid://99082286164362",
	["mic"] = "rbxassetid://89640799126523",
	["microchip"] = "rbxassetid://73937907669903",
	["microscope"] = "rbxassetid://116875530102782",
	["microwave"] = "rbxassetid://108411735353008",
	["milestone"] = "rbxassetid://101618292325920",
	["milk-off"] = "rbxassetid://72388480962742",
	["milk"] = "rbxassetid://96221903896918",
	["minimize-2"] = "rbxassetid://116269596042539",
	["minimize"] = "rbxassetid://121304296213645",
	["minus"] = "rbxassetid://118026365011536",
	["monitor-check"] = "rbxassetid://86651948439229",
	["monitor-cloud"] = "rbxassetid://85931096038318",
	["monitor-cog"] = "rbxassetid://94345128715799",
	["monitor-dot"] = "rbxassetid://130394010063680",
	["monitor-down"] = "rbxassetid://97466933743423",
	["monitor-off"] = "rbxassetid://74395526657953",
	["monitor-pause"] = "rbxassetid://76002184067562",
	["monitor-play"] = "rbxassetid://133018824306217",
	["monitor-smartphone"] = "rbxassetid://84335680433378",
	["monitor-speaker"] = "rbxassetid://81744810060380",
	["monitor-stop"] = "rbxassetid://98708958984757",
	["monitor-up"] = "rbxassetid://96035360858377",
	["monitor-x"] = "rbxassetid://126265210441423",
	["monitor"] = "rbxassetid://72664649203050",
	["moon-star"] = "rbxassetid://82782200506348",
	["moon"] = "rbxassetid://83380517901735",
	["motorbike"] = "rbxassetid://94580787368233",
	["mountain-snow"] = "rbxassetid://105315495740588",
	["mountain"] = "rbxassetid://73269957566415",
	["mouse-off"] = "rbxassetid://75267871697595",
	["mouse-pointer-2-off"] = "rbxassetid://104701076865632",
	["mouse-pointer-2"] = "rbxassetid://117093892862228",
	["mouse-pointer-ban"] = "rbxassetid://106849413057133",
	["mouse-pointer-click"] = "rbxassetid://107150227368485",
	["mouse-pointer"] = "rbxassetid://72322454962935",
	["mouse"] = "rbxassetid://73096068864710",
	["move-3d"] = "rbxassetid://103365982054003",
	["move-diagonal-2"] = "rbxassetid://117298577948096",
	["move-diagonal"] = "rbxassetid://101433481954184",
	["move-down-left"] = "rbxassetid://102819433534567",
	["move-down-right"] = "rbxassetid://101479760041877",
	["move-down"] = "rbxassetid://70510115135583",
	["move-horizontal"] = "rbxassetid://88513523439149",
	["move-left"] = "rbxassetid://137614740247980",
	["move-right"] = "rbxassetid://132455779472989",
	["move-up-left"] = "rbxassetid://139079815540148",
	["move-up-right"] = "rbxassetid://105885140592646",
	["move-up"] = "rbxassetid://84505444262658",
	["move-vertical"] = "rbxassetid://86234730730899",
	["move"] = "rbxassetid://116138709011735",
	["music-2"] = "rbxassetid://134397426600888",
	["music-3"] = "rbxassetid://94466120066498",
	["music-4"] = "rbxassetid://132459323665838",
	["music"] = "rbxassetid://113343203848535",
	["navigation-2-off"] = "rbxassetid://116569611780763",
	["navigation-2"] = "rbxassetid://81889066747907",
	["navigation-off"] = "rbxassetid://87003270290777",
	["navigation"] = "rbxassetid://79308213542922",
	["network"] = "rbxassetid://127410729922644",
	["newspaper"] = "rbxassetid://123479530460544",
	["nfc"] = "rbxassetid://76822396542242",
	["non-binary"] = "rbxassetid://78442360386235",
	["notebook-pen"] = "rbxassetid://140380614761023",
	["notebook-tabs"] = "rbxassetid://127371085570083",
	["notebook-text"] = "rbxassetid://93061585217270",
	["notebook"] = "rbxassetid://136132108664987",
	["notepad-text-dashed"] = "rbxassetid://135793446376219",
	["notepad-text"] = "rbxassetid://93404682958966",
	["nut-off"] = "rbxassetid://78795397311573",
	["nut"] = "rbxassetid://127146410705656",
	["octagon-alert"] = "rbxassetid://140438367956051",
	["octagon-minus"] = "rbxassetid://74720436795421",
	["octagon-pause"] = "rbxassetid://103161463909039",
	["octagon-x"] = "rbxassetid://90498161006311",
	["octagon"] = "rbxassetid://120803515514852",
	["omega"] = "rbxassetid://70414080018786",
	["option"] = "rbxassetid://100776883894054",
	["orbit"] = "rbxassetid://108926136860562",
	["origami"] = "rbxassetid://136020626667101",
	["package-2"] = "rbxassetid://70394974762575",
	["package-check"] = "rbxassetid://102374216055130",
	["package-minus"] = "rbxassetid://114492858789692",
	["package-open"] = "rbxassetid://132890233237818",
	["package-plus"] = "rbxassetid://129261988138366",
	["package-search"] = "rbxassetid://95465120894145",
	["package-x"] = "rbxassetid://70818501607442",
	["package"] = "rbxassetid://97261141732706",
	["paint-bucket"] = "rbxassetid://124275586663284",
	["paint-roller"] = "rbxassetid://115248074358348",
	["paintbrush-vertical"] = "rbxassetid://105151296591292",
	["paintbrush"] = "rbxassetid://125572663700289",
	["palette"] = "rbxassetid://86350350950064",
	["panda"] = "rbxassetid://132509022802512",
	["panel-bottom-close"] = "rbxassetid://74287004071159",
	["panel-bottom-dashed"] = "rbxassetid://131084651621603",
	["panel-bottom-open"] = "rbxassetid://107768659586540",
	["panel-bottom"] = "rbxassetid://132127145048511",
	["panel-left-close"] = "rbxassetid://126579818823552",
	["panel-left-dashed"] = "rbxassetid://75536606374585",
	["panel-left-open"] = "rbxassetid://111075816195767",
	["panel-left-right-dashed"] = "rbxassetid://110100707973959",
	["panel-left"] = "rbxassetid://97419752870313",
	["panel-right-close"] = "rbxassetid://139528655524132",
	["panel-right-dashed"] = "rbxassetid://94959793877311",
	["panel-right-open"] = "rbxassetid://118114419142794",
	["panel-right"] = "rbxassetid://116365035443156",
	["panel-top-bottom-dashed"] = "rbxassetid://134737235653344",
	["panel-top-close"] = "rbxassetid://83578325777808",
	["panel-top-dashed"] = "rbxassetid://70522913169237",
	["panel-top-open"] = "rbxassetid://137959875507454",
	["panel-top"] = "rbxassetid://75838479462875",
	["panels-left-bottom"] = "rbxassetid://72996856149149",
	["panels-right-bottom"] = "rbxassetid://90659068960726",
	["panels-top-left"] = "rbxassetid://79858853850600",
	["paperclip"] = "rbxassetid://92088291163453",
	["parentheses"] = "rbxassetid://78950955173096",
	["parking-meter"] = "rbxassetid://84652733960568",
	["party-popper"] = "rbxassetid://111626795712193",
	["pause"] = "rbxassetid://74873705394436",
	["paw-print"] = "rbxassetid://112218825427601",
	["pc-case"] = "rbxassetid://122978648019101",
	["pen-line"] = "rbxassetid://109108135755303",
	["pen-off"] = "rbxassetid://84807123119438",
	["pen-tool"] = "rbxassetid://106145404953445",
	["pen"] = "rbxassetid://72037878096321",
	["pencil-line"] = "rbxassetid://88392917053533",
	["pencil-off"] = "rbxassetid://103330927652832",
	["pencil-ruler"] = "rbxassetid://110120288284597",
	["pencil"] = "rbxassetid://137986121120732",
	["pentagon"] = "rbxassetid://79184802179890",
	["percent"] = "rbxassetid://130155041032013",
	["person-standing"] = "rbxassetid://125020872044147",
	["philippine-peso"] = "rbxassetid://91173798254675",
	["phone-call"] = "rbxassetid://70555587592860",
	["phone-forwarded"] = "rbxassetid://113269614319737",
	["phone-incoming"] = "rbxassetid://82863576359288",
	["phone-missed"] = "rbxassetid://130156165198376",
	["phone-off"] = "rbxassetid://133318623553383",
	["phone-outgoing"] = "rbxassetid://104576478735825",
	["phone"] = "rbxassetid://128804946640049",
	["pi"] = "rbxassetid://74936036243146",
	["piano"] = "rbxassetid://85008880789520",
	["pickaxe"] = "rbxassetid://105888023317688",
	["picture-in-picture-2"] = "rbxassetid://112803319544468",
	["picture-in-picture"] = "rbxassetid://80579597835123",
	["piggy-bank"] = "rbxassetid://79498575790721",
	["pilcrow-left"] = "rbxassetid://103803000849583",
	["pilcrow-right"] = "rbxassetid://104881733911870",
	["pilcrow"] = "rbxassetid://139512780392871",
	["pill-bottle"] = "rbxassetid://118394692404597",
	["pill"] = "rbxassetid://73280534813448",
	["pin-off"] = "rbxassetid://127696372451750",
	["pin"] = "rbxassetid://120978111007514",
	["pipette"] = "rbxassetid://133167932934404",
	["pizza"] = "rbxassetid://126964453193501",
	["plane-landing"] = "rbxassetid://122555692211889",
	["plane-takeoff"] = "rbxassetid://117179478829575",
	["plane"] = "rbxassetid://126985561580989",
	["play"] = "rbxassetid://135609604299893",
	["plug-2"] = "rbxassetid://97912386476366",
	["plug-zap"] = "rbxassetid://74506269884055",
	["plug"] = "rbxassetid://99782373064495",
	["plus"] = "rbxassetid://111774323017047",
	["pocket-knife"] = "rbxassetid://134075428063965",
	["pocket"] = "rbxassetid://136686762542964",
	["podcast"] = "rbxassetid://109577075549215",
	["pointer-off"] = "rbxassetid://95488389312794",
	["pointer"] = "rbxassetid://92615117311099",
	["popcorn"] = "rbxassetid://139446511232750",
	["popsicle"] = "rbxassetid://112696318077073",
	["pound-sterling"] = "rbxassetid://127482649469130",
	["power-off"] = "rbxassetid://118768311012214",
	["power"] = "rbxassetid://96479131758775",
	["presentation"] = "rbxassetid://106134583757890",
	["printer-check"] = "rbxassetid://130273549443689",
	["printer"] = "rbxassetid://76080649734247",
	["projector"] = "rbxassetid://103281856385283",
	["proportions"] = "rbxassetid://130046855997237",
	["puzzle"] = "rbxassetid://136837798892463",
	["pyramid"] = "rbxassetid://107811442374127",
	["qr-code"] = "rbxassetid://105329945723350",
	["quote"] = "rbxassetid://103271711590001",
	["rabbit"] = "rbxassetid://98580518804206",
	["radar"] = "rbxassetid://138528222906635",
	["radiation"] = "rbxassetid://104499586848433",
	["radical"] = "rbxassetid://132758286926047",
	["radio-receiver"] = "rbxassetid://129598303378835",
	["radio-tower"] = "rbxassetid://93958663130054",
	["radio"] = "rbxassetid://85611589536956",
	["radius"] = "rbxassetid://89814505307129",
	["rail-symbol"] = "rbxassetid://134295386306962",
	["rainbow"] = "rbxassetid://132488862841895",
	["rat"] = "rbxassetid://127400975953159",
	["ratio"] = "rbxassetid://126369423897295",
	["receipt-cent"] = "rbxassetid://91557573925201",
	["receipt-euro"] = "rbxassetid://94015722210295",
	["receipt-indian-rupee"] = "rbxassetid://89718170439990",
	["receipt-japanese-yen"] = "rbxassetid://132472560758851",
	["receipt-pound-sterling"] = "rbxassetid://73934967569625",
	["receipt-russian-ruble"] = "rbxassetid://105164576936853",
	["receipt-swiss-franc"] = "rbxassetid://72503668620116",
	["receipt-text"] = "rbxassetid://138483536013737",
	["receipt-turkish-lira"] = "rbxassetid://91950765836342",
	["receipt"] = "rbxassetid://77877895901792",
	["rectangle-circle"] = "rbxassetid://100642423153903",
	["rectangle-ellipsis"] = "rbxassetid://112919953980965",
	["rectangle-goggles"] = "rbxassetid://98605436666727",
	["rectangle-horizontal"] = "rbxassetid://90224199814966",
	["rectangle-vertical"] = "rbxassetid://117277050590967",
	["recycle"] = "rbxassetid://140417023381961",
	["redo-2"] = "rbxassetid://70451039017914",
	["redo-dot"] = "rbxassetid://94252981719732",
	["redo"] = "rbxassetid://116150342119054",
	["refresh-ccw-dot"] = "rbxassetid://106702246753270",
	["refresh-ccw"] = "rbxassetid://117913330389477",
	["refresh-cw-off"] = "rbxassetid://140179498843054",
	["refresh-cw"] = "rbxassetid://138133190015277",
	["refrigerator"] = "rbxassetid://102614042652753",
	["regex"] = "rbxassetid://100727200791841",
	["remove-formatting"] = "rbxassetid://112833162022628",
	["repeat-1"] = "rbxassetid://130144534857095",
	["repeat-2"] = "rbxassetid://85927537182704",
	["repeat"] = "rbxassetid://121886242955173",
	["replace-all"] = "rbxassetid://127862728198635",
	["replace"] = "rbxassetid://128404082279430",
	["reply-all"] = "rbxassetid://71723137343562",
	["reply"] = "rbxassetid://109788633497028",
	["rewind"] = "rbxassetid://95205297521988",
	["ribbon"] = "rbxassetid://94265331526851",
	["rocket"] = "rbxassetid://87412317685854",
	["rocking-chair"] = "rbxassetid://110420269495360",
	["roller-coaster"] = "rbxassetid://112426178972099",
	["rose"] = "rbxassetid://126336840238769",
	["rotate-3d"] = "rbxassetid://76300551576392",
	["rotate-ccw-key"] = "rbxassetid://74976035240976",
	["rotate-ccw-square"] = "rbxassetid://90515853170424",
	["rotate-ccw"] = "rbxassetid://110116685948665",
	["rotate-cw-square"] = "rbxassetid://77095448159303",
	["rotate-cw"] = "rbxassetid://84183336178654",
	["route-off"] = "rbxassetid://106350402024079",
	["route"] = "rbxassetid://89968303228953",
	["router"] = "rbxassetid://102130331994471",
	["rows-2"] = "rbxassetid://112556185960101",
	["rows-3"] = "rbxassetid://117215586961375",
	["rows-4"] = "rbxassetid://125646021959055",
	["rss"] = "rbxassetid://131789058984793",
	["ruler-dimension-line"] = "rbxassetid://70673861371412",
	["ruler"] = "rbxassetid://81432445547423",
	["russian-ruble"] = "rbxassetid://126357936542156",
	["sailboat"] = "rbxassetid://87110567187540",
	["salad"] = "rbxassetid://128864507821603",
	["sandwich"] = "rbxassetid://104573187458917",
	["satellite-dish"] = "rbxassetid://136742443888305",
	["satellite"] = "rbxassetid://134967053164645",
	["saudi-riyal"] = "rbxassetid://102282769104635",
	["save-all"] = "rbxassetid://116946975799440",
	["save-off"] = "rbxassetid://87085435778560",
	["save"] = "rbxassetid://126116963775616",
	["scale-3d"] = "rbxassetid://72414199620352",
	["scale"] = "rbxassetid://108203682317477",
	["scaling"] = "rbxassetid://122360365318466",
	["scan-barcode"] = "rbxassetid://96889457154761",
	["scan-eye"] = "rbxassetid://99244790601968",
	["scan-face"] = "rbxassetid://109959345069668",
	["scan-heart"] = "rbxassetid://106280819776142",
	["scan-line"] = "rbxassetid://126544908146540",
	["scan-qr-code"] = "rbxassetid://105409149549927",
	["scan-search"] = "rbxassetid://80009010551347",
	["scan-text"] = "rbxassetid://73702396787766",
	["scan"] = "rbxassetid://123104789658180",
	["school"] = "rbxassetid://76351530290068",
	["scissors-line-dashed"] = "rbxassetid://122237447974173",
	["scissors"] = "rbxassetid://118665510911274",
	["screen-share-off"] = "rbxassetid://107677572669805",
	["screen-share"] = "rbxassetid://85137895705653",
	["scroll-text"] = "rbxassetid://97321022666868",
	["scroll"] = "rbxassetid://74072101474951",
	["search-check"] = "rbxassetid://75442076191356",
	["search-code"] = "rbxassetid://117114794592802",
	["search-slash"] = "rbxassetid://96483932261041",
	["search-x"] = "rbxassetid://137319957522951",
	["search"] = "rbxassetid://121018724060431",
	["section"] = "rbxassetid://91732188298948",
	["send-horizontal"] = "rbxassetid://111734392411664",
	["send-to-back"] = "rbxassetid://75340312862253",
	["send"] = "rbxassetid://127751956873796",
	["separator-horizontal"] = "rbxassetid://84864453699927",
	["separator-vertical"] = "rbxassetid://84031801478581",
	["server-cog"] = "rbxassetid://138470287250966",
	["server-crash"] = "rbxassetid://132810618000212",
	["server-off"] = "rbxassetid://114048751507723",
	["server"] = "rbxassetid://92188766517878",
	["settings-2"] = "rbxassetid://135684703553372",
	["settings"] = "rbxassetid://80758916183665",
	["shapes"] = "rbxassetid://129989433311409",
	["share-2"] = "rbxassetid://71210767962065",
	["share"] = "rbxassetid://87340985053299",
	["sheet"] = "rbxassetid://134902122480171",
	["shell"] = "rbxassetid://140212943563599",
	["shield-alert"] = "rbxassetid://114995877719925",
	["shield-ban"] = "rbxassetid://108765041044649",
	["shield-check"] = "rbxassetid://87354736164608",
	["shield-ellipsis"] = "rbxassetid://114794739892123",
	["shield-half"] = "rbxassetid://117842634172647",
	["shield-minus"] = "rbxassetid://89965059528921",
	["shield-off"] = "rbxassetid://133426959132690",
	["shield-plus"] = "rbxassetid://100664857995498",
	["shield-question-mark"] = "rbxassetid://135722075265150",
	["shield-user"] = "rbxassetid://124832775645347",
	["shield-x"] = "rbxassetid://73370117343811",
	["shield"] = "rbxassetid://110987169760162",
	["ship-wheel"] = "rbxassetid://130797795829448",
	["ship"] = "rbxassetid://83995100553930",
	["shirt"] = "rbxassetid://106579555405966",
	["shopping-bag"] = "rbxassetid://71885477293226",
	["shopping-basket"] = "rbxassetid://138646411956433",
	["shopping-cart"] = "rbxassetid://128420521375441",
	["shovel"] = "rbxassetid://102465000512056",
	["shower-head"] = "rbxassetid://75884944024117",
	["shredder"] = "rbxassetid://122125164414463",
	["shrimp"] = "rbxassetid://102625900815307",
	["shrink"] = "rbxassetid://90953687918880",
	["shrub"] = "rbxassetid://127326280714343",
	["shuffle"] = "rbxassetid://132382786975101",
	["sigma"] = "rbxassetid://126884244870899",
	["signal-high"] = "rbxassetid://130436670012270",
	["signal-low"] = "rbxassetid://73674683500458",
	["signal-medium"] = "rbxassetid://125003021367019",
	["signal-zero"] = "rbxassetid://130045332414754",
	["signal"] = "rbxassetid://78424889355261",
	["signature"] = "rbxassetid://114402748013000",
	["signpost-big"] = "rbxassetid://115780185675001",
	["signpost"] = "rbxassetid://106584743791433",
	["siren"] = "rbxassetid://134210267818039",
	["skip-back"] = "rbxassetid://70466132711334",
	["skip-forward"] = "rbxassetid://124844823753990",
	["skull"] = "rbxassetid://137726256442333",
	["slack"] = "rbxassetid://96089719516736",
	["slash"] = "rbxassetid://117792185664263",
	["slice"] = "rbxassetid://95810504278179",
	["sliders-horizontal"] = "rbxassetid://85538382643347",
	["sliders-vertical"] = "rbxassetid://101190569086853",
	["smartphone-charging"] = "rbxassetid://102837532613995",
	["smartphone-nfc"] = "rbxassetid://82326425754446",
	["smartphone"] = "rbxassetid://96623008834511",
	["smile-plus"] = "rbxassetid://131981881472144",
	["smile"] = "rbxassetid://105880397565283",
	["snail"] = "rbxassetid://70904536548363",
	["snowflake"] = "rbxassetid://101235206534566",
	["soap-dispenser-droplet"] = "rbxassetid://77258480479465",
	["sofa"] = "rbxassetid://114427687218324",
	["solar-panel"] = "rbxassetid://132448188047921",
	["soup"] = "rbxassetid://115092551871618",
	["space"] = "rbxassetid://87072088914178",
	["spade"] = "rbxassetid://131444449466462",
	["sparkle"] = "rbxassetid://111044800239623",
	["sparkles"] = "rbxassetid://138635884129147",
	["speaker"] = "rbxassetid://96227183003618",
	["speech"] = "rbxassetid://87013139446349",
	["spell-check-2"] = "rbxassetid://81556731785534",
	["spell-check"] = "rbxassetid://91913483031334",
	["spline-pointer"] = "rbxassetid://84842840956804",
	["spline"] = "rbxassetid://129406685807412",
	["split"] = "rbxassetid://105112438805988",
	["spool"] = "rbxassetid://124541981347743",
	["spotlight"] = "rbxassetid://77571742539344",
	["spray-can"] = "rbxassetid://128372039366326",
	["sprout"] = "rbxassetid://100091687832508",
	["square-activity"] = "rbxassetid://89496630185293",
	["square-arrow-down-left"] = "rbxassetid://108194680296901",
	["square-arrow-down-right"] = "rbxassetid://99403846801050",
	["square-arrow-down"] = "rbxassetid://135962519626588",
	["square-arrow-left"] = "rbxassetid://111671474549238",
	["square-arrow-out-down-left"] = "rbxassetid://125714881756353",
	["square-arrow-out-down-right"] = "rbxassetid://89971003001390",
	["square-arrow-out-up-left"] = "rbxassetid://103759986579087",
	["square-arrow-out-up-right"] = "rbxassetid://91221896066807",
	["square-arrow-right"] = "rbxassetid://113920471701361",
	["square-arrow-up-left"] = "rbxassetid://112424670290693",
	["square-arrow-up-right"] = "rbxassetid://76602291406940",
	["square-arrow-up"] = "rbxassetid://106998604646718",
	["square-asterisk"] = "rbxassetid://89186832353625",
	["square-bottom-dashed-scissors"] = "rbxassetid://79076980104803",
	["square-chart-gantt"] = "rbxassetid://104034017316411",
	["square-check-big"] = "rbxassetid://115320390907184",
	["square-check"] = "rbxassetid://134682053539509",
	["square-chevron-down"] = "rbxassetid://91032307924592",
	["square-chevron-left"] = "rbxassetid://73143404829510",
	["square-chevron-right"] = "rbxassetid://90612077729930",
	["square-chevron-up"] = "rbxassetid://85565910197337",
	["square-code"] = "rbxassetid://81604576616881",
	["square-dashed-bottom-code"] = "rbxassetid://100354801563230",
	["square-dashed-bottom"] = "rbxassetid://101102319625624",
	["square-dashed-kanban"] = "rbxassetid://90388067649847",
	["square-dashed-mouse-pointer"] = "rbxassetid://121016142178467",
	["square-dashed-top-solid"] = "rbxassetid://117157577548540",
	["square-dashed"] = "rbxassetid://136905537847606",
	["square-divide"] = "rbxassetid://99894657101970",
	["square-dot"] = "rbxassetid://116613421354866",
	["square-equal"] = "rbxassetid://110283363706707",
	["square-function"] = "rbxassetid://86075219551088",
	["square-kanban"] = "rbxassetid://114537101260131",
	["square-library"] = "rbxassetid://73810931222081",
	["square-m"] = "rbxassetid://117662700410577",
	["square-menu"] = "rbxassetid://104067089444415",
	["square-minus"] = "rbxassetid://116764432015770",
	["square-mouse-pointer"] = "rbxassetid://76141850603920",
	["square-parking-off"] = "rbxassetid://100857293535141",
	["square-parking"] = "rbxassetid://133116656122387",
	["square-pause"] = "rbxassetid://86608552787615",
	["square-pen"] = "rbxassetid://120239476110475",
	["square-percent"] = "rbxassetid://87111930314567",
	["square-pi"] = "rbxassetid://75383328781618",
	["square-pilcrow"] = "rbxassetid://131854284699367",
	["square-play"] = "rbxassetid://108186325238481",
	["square-plus"] = "rbxassetid://114713264461873",
	["square-power"] = "rbxassetid://129240437805187",
	["square-radical"] = "rbxassetid://132645931868292",
	["square-round-corner"] = "rbxassetid://104592745113567",
	["square-scissors"] = "rbxassetid://110601255612411",
	["square-sigma"] = "rbxassetid://113231244246816",
	["square-slash"] = "rbxassetid://105477013908757",
	["square-split-horizontal"] = "rbxassetid://76095370148660",
	["square-split-vertical"] = "rbxassetid://88589192032058",
	["square-square"] = "rbxassetid://136555087357875",
	["square-stack"] = "rbxassetid://100463396619394",
	["square-star"] = "rbxassetid://94506958703720",
	["square-stop"] = "rbxassetid://80018708472943",
	["square-terminal"] = "rbxassetid://83969264476798",
	["square-user-round"] = "rbxassetid://86484997229302",
	["square-user"] = "rbxassetid://70771214183445",
	["square-x"] = "rbxassetid://125136183850190",
	["square"] = "rbxassetid://86304921356806",
	["squares-exclude"] = "rbxassetid://102345385822324",
	["squares-intersect"] = "rbxassetid://120869602570119",
	["squares-subtract"] = "rbxassetid://131484650948795",
	["squares-unite"] = "rbxassetid://96673080107843",
	["squircle-dashed"] = "rbxassetid://129936702532522",
	["squircle"] = "rbxassetid://82426632573807",
	["squirrel"] = "rbxassetid://112864252085343",
	["stamp"] = "rbxassetid://92370779813368",
	["star-half"] = "rbxassetid://117449275562979",
	["star-off"] = "rbxassetid://75742832732503",
	["star"] = "rbxassetid://136141469398409",
	["step-back"] = "rbxassetid://108672750005121",
	["step-forward"] = "rbxassetid://126131872136145",
	["stethoscope"] = "rbxassetid://122331031702148",
	["sticker"] = "rbxassetid://79938203791608",
	["sticky-note"] = "rbxassetid://111894074643919",
	["store"] = "rbxassetid://90338129673705",
	["stretch-horizontal"] = "rbxassetid://87665042192343",
	["stretch-vertical"] = "rbxassetid://95265463417122",
	["strikethrough"] = "rbxassetid://103417324549613",
	["subscript"] = "rbxassetid://74553514785183",
	["sun-dim"] = "rbxassetid://129141645592715",
	["sun-medium"] = "rbxassetid://130278807964710",
	["sun-moon"] = "rbxassetid://75752898854559",
	["sun-snow"] = "rbxassetid://112791898014579",
	["sun"] = "rbxassetid://110150589884127",
	["sunrise"] = "rbxassetid://134705665494098",
	["sunset"] = "rbxassetid://75904872203588",
	["superscript"] = "rbxassetid://96887696590118",
	["swatch-book"] = "rbxassetid://126786244872453",
	["swiss-franc"] = "rbxassetid://113497920041625",
	["switch-camera"] = "rbxassetid://76841154349737",
	["sword"] = "rbxassetid://124448418211665",
	["swords"] = "rbxassetid://81872698913435",
	["syringe"] = "rbxassetid://123891270479254",
	["table-2"] = "rbxassetid://95751552281545",
	["table-cells-merge"] = "rbxassetid://95363715175258",
	["table-cells-split"] = "rbxassetid://114799086088649",
	["table-columns-split"] = "rbxassetid://111011625447949",
	["table-of-contents"] = "rbxassetid://135044763275414",
	["table-properties"] = "rbxassetid://125062886015372",
	["table-rows-split"] = "rbxassetid://96443733673997",
	["table"] = "rbxassetid://109109148250737",
	["tablet-smartphone"] = "rbxassetid://133680859813404",
	["tablet"] = "rbxassetid://128403991264386",
	["tablets"] = "rbxassetid://80835787970735",
	["tag"] = "rbxassetid://129104970103940",
	["tags"] = "rbxassetid://107179263080798",
	["tally-1"] = "rbxassetid://115301298241643",
	["tally-2"] = "rbxassetid://110363186864027",
	["tally-3"] = "rbxassetid://97655344572540",
	["tally-4"] = "rbxassetid://102633494371890",
	["tally-5"] = "rbxassetid://88031817475886",
	["tangent"] = "rbxassetid://123263132981724",
	["target"] = "rbxassetid://87563802520297",
	["telescope"] = "rbxassetid://91755049143647",
	["tent-tree"] = "rbxassetid://76698322463977",
	["tent"] = "rbxassetid://109779587826330",
	["terminal"] = "rbxassetid://106783148545356",
	["test-tube-diagonal"] = "rbxassetid://75662704378840",
	["test-tube"] = "rbxassetid://98801015650164",
	["test-tubes"] = "rbxassetid://92555361447433",
	["text-align-center"] = "rbxassetid://84051028246390",
	["text-align-end"] = "rbxassetid://130041738343555",
	["text-align-justify"] = "rbxassetid://80279880143030",
	["text-align-start"] = "rbxassetid://134489585487649",
	["text-cursor-input"] = "rbxassetid://107551944047171",
	["text-cursor"] = "rbxassetid://115984654447300",
	["text-initial"] = "rbxassetid://129458097472087",
	["text-quote"] = "rbxassetid://139278366448736",
	["text-search"] = "rbxassetid://92345384671606",
	["text-select"] = "rbxassetid://117087320884956",
	["text-wrap"] = "rbxassetid://114804318314018",
	["theater"] = "rbxassetid://108558145549163",
	["thermometer-snowflake"] = "rbxassetid://121876188028425",
	["thermometer-sun"] = "rbxassetid://106693240074310",
	["thermometer"] = "rbxassetid://106546011492311",
	["thumbs-down"] = "rbxassetid://87794009914015",
	["thumbs-up"] = "rbxassetid://111137070767020",
	["ticket-check"] = "rbxassetid://105428777212507",
	["ticket-minus"] = "rbxassetid://78966299769328",
	["ticket-percent"] = "rbxassetid://80834774406405",
	["ticket-plus"] = "rbxassetid://110086734392189",
	["ticket-slash"] = "rbxassetid://89045681172265",
	["ticket-x"] = "rbxassetid://88674114109926",
	["ticket"] = "rbxassetid://126527071492145",
	["tickets-plane"] = "rbxassetid://100367018248695",
	["tickets"] = "rbxassetid://135268612687833",
	["timer-off"] = "rbxassetid://110916370767271",
	["timer-reset"] = "rbxassetid://110052125369932",
	["timer"] = "rbxassetid://85473888890506",
	["toggle-left"] = "rbxassetid://85887872573050",
	["toggle-right"] = "rbxassetid://90411952142550",
	["toilet"] = "rbxassetid://80930782432931",
	["tool-case"] = "rbxassetid://87533537832522",
	["tornado"] = "rbxassetid://88358291515768",
	["torus"] = "rbxassetid://70855707283051",
	["touchpad-off"] = "rbxassetid://78784008075456",
	["touchpad"] = "rbxassetid://74882354908014",
	["tower-control"] = "rbxassetid://95937619060532",
	["toy-brick"] = "rbxassetid://86293483924633",
	["tractor"] = "rbxassetid://103376704722051",
	["traffic-cone"] = "rbxassetid://74110220470369",
	["train-front-tunnel"] = "rbxassetid://105194827005114",
	["train-front"] = "rbxassetid://125237934215370",
	["train-track"] = "rbxassetid://77451032453723",
	["tram-front"] = "rbxassetid://93315182364998",
	["transgender"] = "rbxassetid://135530817673639",
	["trash-2"] = "rbxassetid://109843431391323",
	["trash"] = "rbxassetid://106723740584310",
	["tree-deciduous"] = "rbxassetid://123124389219004",
	["tree-palm"] = "rbxassetid://103846705893963",
	["tree-pine"] = "rbxassetid://124662547202594",
	["trees"] = "rbxassetid://121203841375919",
	["trello"] = "rbxassetid://130987241149527",
	["trending-down"] = "rbxassetid://139309232226438",
	["trending-up-down"] = "rbxassetid://85083293981691",
	["trending-up"] = "rbxassetid://81819858538839",
	["triangle-alert"] = "rbxassetid://125920361880643",
	["triangle-dashed"] = "rbxassetid://124324079103935",
	["triangle-right"] = "rbxassetid://116930791412791",
	["triangle"] = "rbxassetid://126330486745540",
	["trophy"] = "rbxassetid://131545003268773",
	["truck-electric"] = "rbxassetid://111873446387359",
	["truck"] = "rbxassetid://86662707764771",
	["turkish-lira"] = "rbxassetid://114589876174070",
	["turntable"] = "rbxassetid://129870346487856",
	["turtle"] = "rbxassetid://118295081560334",
	["tv-minimal-play"] = "rbxassetid://99201833426972",
	["tv-minimal"] = "rbxassetid://100382201729427",
	["tv"] = "rbxassetid://135687724791776",
	["twitch"] = "rbxassetid://71383308134888",
	["twitter"] = "rbxassetid://88791703276842",
	["type-outline"] = "rbxassetid://80108627791690",
	["type"] = "rbxassetid://133543553793564",
	["umbrella-off"] = "rbxassetid://72395143739955",
	["umbrella"] = "rbxassetid://127502210274589",
	["underline"] = "rbxassetid://123709229216544",
	["undo-2"] = "rbxassetid://113885292059932",
	["undo-dot"] = "rbxassetid://132055277744844",
	["undo"] = "rbxassetid://111258459077271",
	["unfold-horizontal"] = "rbxassetid://117128358526398",
	["unfold-vertical"] = "rbxassetid://116593025265499",
	["ungroup"] = "rbxassetid://106674800451003",
	["university"] = "rbxassetid://84652528263642",
	["unlink-2"] = "rbxassetid://128131898892572",
	["unlink"] = "rbxassetid://139835795227752",
	["unplug"] = "rbxassetid://90171381619874",
	["upload"] = "rbxassetid://138212042425501",
	["usb"] = "rbxassetid://117230058949613",
	["user-check"] = "rbxassetid://81775205032725",
	["user-cog"] = "rbxassetid://92795491530865",
	["user-lock"] = "rbxassetid://78892639693821",
	["user-minus"] = "rbxassetid://126976941957511",
	["user-pen"] = "rbxassetid://87445472574836",
	["user-plus"] = "rbxassetid://118514469915884",
	["user-round-check"] = "rbxassetid://118794737621941",
	["user-round-cog"] = "rbxassetid://78239503290053",
	["user-round-minus"] = "rbxassetid://98944176636447",
	["user-round-pen"] = "rbxassetid://108155244324878",
	["user-round-plus"] = "rbxassetid://113301899567470",
	["user-round-search"] = "rbxassetid://71565774381870",
	["user-round-x"] = "rbxassetid://122367980560930",
	["user-round"] = "rbxassetid://136485052187963",
	["user-search"] = "rbxassetid://101335649828115",
	["user-star"] = "rbxassetid://98777846316000",
	["user-x"] = "rbxassetid://139748155894754",
	["user"] = "rbxassetid://81589895647169",
	["users-round"] = "rbxassetid://103005444008339",
	["users"] = "rbxassetid://115398113982385",
	["utensils-crossed"] = "rbxassetid://109520762270383",
	["utensils"] = "rbxassetid://139952569804235",
	["utility-pole"] = "rbxassetid://101965541238242",
	["variable"] = "rbxassetid://104743088438151",
	["vault"] = "rbxassetid://108049164599845",
	["vector-square"] = "rbxassetid://86713728565344",
	["vegan"] = "rbxassetid://119489190688082",
	["venetian-mask"] = "rbxassetid://102636443033920",
	["venus-and-mars"] = "rbxassetid://120227752103771",
	["venus"] = "rbxassetid://82891342220859",
	["vibrate-off"] = "rbxassetid://113446447326246",
	["vibrate"] = "rbxassetid://108330910738733",
	["video-off"] = "rbxassetid://132239189859305",
	["video"] = "rbxassetid://107587444636945",
	["videotape"] = "rbxassetid://114816894323398",
	["view"] = "rbxassetid://118717253976805",
	["voicemail"] = "rbxassetid://134313454010227",
	["volleyball"] = "rbxassetid://83889351124153",
	["volume-1"] = "rbxassetid://98514588731639",
	["volume-2"] = "rbxassetid://89344380902620",
	["volume-off"] = "rbxassetid://103047478058767",
	["volume-x"] = "rbxassetid://139252359189540",
	["volume"] = "rbxassetid://103236289817396",
	["vote"] = "rbxassetid://89409762851246",
	["wallet-cards"] = "rbxassetid://129728715308337",
	["wallet-minimal"] = "rbxassetid://137800448816116",
	["wallet"] = "rbxassetid://132331555762628",
	["wallpaper"] = "rbxassetid://74682121235494",
	["wand-sparkles"] = "rbxassetid://82546429942392",
	["wand"] = "rbxassetid://114580617777835",
	["warehouse"] = "rbxassetid://78388887451080",
	["washing-machine"] = "rbxassetid://104194127573858",
	["watch"] = "rbxassetid://130544621618405",
	["waves-ladder"] = "rbxassetid://101808619355514",
	["waves"] = "rbxassetid://96340135183647",
	["waypoints"] = "rbxassetid://102450133666017",
	["webcam"] = "rbxassetid://104148487911129",
	["webhook-off"] = "rbxassetid://96370548093471",
	["webhook"] = "rbxassetid://112812457747322",
	["weight"] = "rbxassetid://103860559844854",
	["wheat-off"] = "rbxassetid://133294844612307",
	["wheat"] = "rbxassetid://85261952080359",
	["whole-word"] = "rbxassetid://90111083954485",
	["wifi-cog"] = "rbxassetid://110500263326209",
	["wifi-high"] = "rbxassetid://81954601342139",
	["wifi-low"] = "rbxassetid://138217335635913",
	["wifi-off"] = "rbxassetid://74113634330106",
	["wifi-pen"] = "rbxassetid://91290205064712",
	["wifi-sync"] = "rbxassetid://84043971055177",
	["wifi-zero"] = "rbxassetid://124286465246123",
	["wifi"] = "rbxassetid://104669375183960",
	["wind-arrow-down"] = "rbxassetid://127753987414870",
	["wind"] = "rbxassetid://114551690399915",
	["wine-off"] = "rbxassetid://108294164302317",
	["wine"] = "rbxassetid://115743721332829",
	["workflow"] = "rbxassetid://99186544029189",
	["worm"] = "rbxassetid://115752311548091",
	["wrench"] = "rbxassetid://112148279212860",
	["x"] = "rbxassetid://110786993356448",
	["youtube"] = "rbxassetid://123663668456341",
	["zap-off"] = "rbxassetid://81385483183652",
	["zap"] = "rbxassetid://130551565616516",
	["zoom-in"] = "rbxassetid://127956924984803",
	["zoom-out"] = "rbxassetid://108334162607319",
	["balloon"] = "rbxassetid://97489111621526",
	["beef-off"] = "rbxassetid://99869959725200",
	["book-search"] = "rbxassetid://132585409504950",
	["calendars"] = "rbxassetid://130944763042289",
	["cannabis-off"] = "rbxassetid://101938500363812",
	["cctv-off"] = "rbxassetid://75925370187295",
	["cigarette"] = "rbxassetid://137149549886852",
	["circle-pile"] = "rbxassetid://116353155251541",
	["cloud-backup"] = "rbxassetid://111649579696132",
	["cloud-sync"] = "rbxassetid://79393911188593",
	["database-search"] = "rbxassetid://92017137080138",
	["ellipse"] = "rbxassetid://71559658267482",
	["fingerprint-pattern"] = "rbxassetid://80934710831288",
	["fishing-hook"] = "rbxassetid://121038780855899",
	["fishing-rod"] = "rbxassetid://71754848048049",
	["form"] = "rbxassetid://72999643971000",
	["git-merge-conflict"] = "rbxassetid://85677801675703",
	["globe-off"] = "rbxassetid://77775243585824",
	["globe-x"] = "rbxassetid://109268097029296",
	["hd"] = "rbxassetid://71682790698278",
	["image"] = "rbxassetid://112751259236831",
	["layers-plus"] = "rbxassetid://77587765623057",
	["lens-concave"] = "rbxassetid://94819631937027",
	["lens-convex"] = "rbxassetid://74736504195474",
	["line-dot-right-horizontal"] = "rbxassetid://104718593155221",
	["line-style"] = "rbxassetid://90176717785772",
	["map-pin-search"] = "rbxassetid://89065012915078",
	["message-circle-check"] = "rbxassetid://132772297689418",
	["message-square-check"] = "rbxassetid://125789987055668",
	["metronome"] = "rbxassetid://101991829345965",
	["mirror-rectangular"] = "rbxassetid://109046769760336",
	["mirror-round"] = "rbxassetid://121534049429097",
	["mouse-left"] = "rbxassetid://99144293708743",
	["mouse-right"] = "rbxassetid://88331710212594",
	["printer-x"] = "rbxassetid://103002721801548",
	["radio-off"] = "rbxassetid://80359258046586",
	["road"] = "rbxassetid://120251329173530",
	["scooter"] = "rbxassetid://100035452787934",
	["search-alert"] = "rbxassetid://127597984617505",
	["shelving-unit"] = "rbxassetid://80116568514793",
	["shield-cog-corner"] = "rbxassetid://111694066132698",
	["shield-cog"] = "rbxassetid://129235695057857",
	["sport-shoe"] = "rbxassetid://120495992692630",
	["square-arrow-right-enter"] = "rbxassetid://138867831495334",
	["square-arrow-right-exit"] = "rbxassetid://133688575845430",
	["square-centerline-dashed-horizontal"] = "rbxassetid://77780104374341",
	["square-centerline-dashed-vertical"] = "rbxassetid://107878435803525",
	["stone"] = "rbxassetid://135161057497830",
	["toolbox"] = "rbxassetid://85341033903792",
	["towel-rack"] = "rbxassetid://125223915620991",
	["user-key"] = "rbxassetid://105403041782190",
	["user-round-key"] = "rbxassetid://124547549008939",
	["van"] = "rbxassetid://122066377022942",
	["waves-arrow-down"] = "rbxassetid://129215220911792",
	["waves-arrow-up"] = "rbxassetid://102314705716217",
	["weight-tilde"] = "rbxassetid://112081212176951",
	["x-line-top"] = "rbxassetid://140592656289509",
	["zodiac-aquarius"] = "rbxassetid://74560047770362",
	["zodiac-aries"] = "rbxassetid://73255859670234",
	["zodiac-cancer"] = "rbxassetid://131985162532947",
	["zodiac-capricorn"] = "rbxassetid://97859568140652",
	["zodiac-gemini"] = "rbxassetid://80997588122992",
	["zodiac-leo"] = "rbxassetid://75509406718106",
	["zodiac-libra"] = "rbxassetid://113222735060218",
	["zodiac-ophiuchus"] = "rbxassetid://129180108892480",
	["zodiac-pisces"] = "rbxassetid://95845819440327",
	["zodiac-sagittarius"] = "rbxassetid://82651026742181",
	["zodiac-scorpio"] = "rbxassetid://113640924054631",
	["zodiac-taurus"] = "rbxassetid://123053219704400",
	["zodiac-virgo"] = "rbxassetid://99462994613661",
}

local TAB_ICON = {
    Home = "house", Overview = "layout-dashboard", Main = "fish-symbol", Routine = "fish-symbol",
    Shop = "store", Exchange = "arrow-left-right", Quests = "scroll-text",
    Ascend = "trending-up", Upgrade = "trending-up", Teleport = "map-pin",
    Settings = "settings", Character = "user",
}
local TAB_ASSET = {
    Settings = "rbxassetid://120090449970711",
}

local function resolveIcon(name, iconArg)
    if type(iconArg) == "number" then return "rbxassetid://" .. tostring(iconArg) end
    if type(iconArg) == "string" then
        if iconArg:find("rbxassetid://", 1, true) then return iconArg end
        if LUCIDE[iconArg] then return LUCIDE[iconArg] end
    end
    if type(name) == "string" and TAB_ASSET[name] then return TAB_ASSET[name] end
    local key = TAB_ICON[name] or (type(name) == "string" and name:lower()) or "circle"
    if LUCIDE[key] then return LUCIDE[key] end
    for _, try in ipairs({ "circle", "box", "star" }) do
        if LUCIDE[try] then return LUCIDE[try] end
    end
    return "rbxassetid://0"
end

local function make(className, props, parent)
    local o = Instance.new(className)
    for k, v in pairs(props or {}) do pcall(function() o[k] = v end) end
    if parent then o.Parent = parent end
    return o
end
local function corner(p, r) return make("UICorner", { CornerRadius = UDim.new(0, r or 12) }, p) end
local function stroke(p, c, t, tr)
    return make("UIStroke", {
        Color = c or Color3.fromRGB(55, 55, 65), Thickness = t or 1,
        Transparency = tr or 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, p)
end
local function gradient(parent, c0, c1, rot)
    return make("UIGradient", { Color = ColorSequence.new(c0, c1), Rotation = rot or 90 }, parent)
end
local function hoverScale(btn, factor)
    factor = factor or 0.96
    if not btn then return end
    local scaleObj = btn:FindFirstChild("__KhfreshHoverScale")
    if not scaleObj then
        scaleObj = Instance.new("UIScale")
        scaleObj.Name = "__KhfreshHoverScale"
        scaleObj.Scale = 1
        scaleObj.Parent = btn
    end
    btn.MouseEnter:Connect(function()
        TweenService:Create(scaleObj, TweenInfo.new(0.14, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Scale = factor}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(scaleObj, TweenInfo.new(0.14, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Scale = 1}):Play()
    end)
end

local C = {
    Bar = Color3.fromRGB(18, 18, 24),
    Panel = Color3.fromRGB(22, 22, 28),
    PanelDeep = Color3.fromRGB(14, 14, 20),
    Row = Color3.fromRGB(30, 30, 38),
    Text = Color3.fromRGB(245, 245, 250),
    Muted = Color3.fromRGB(145, 145, 158),
    Stroke = Color3.fromRGB(55, 55, 68),
    Accent = Color3.fromRGB(26, 148, 255),
}

local BAR_COLORS = {
    Color3.fromRGB(120, 90, 220), Color3.fromRGB(40, 140, 220),
    Color3.fromRGB(220, 100, 60), Color3.fromRGB(40, 180, 100),
    Color3.fromRGB(200, 60, 100), Color3.fromRGB(90, 100, 200),
    Color3.fromRGB(180, 140, 50), Color3.fromRGB(70, 160, 180),
}

local SiriusChar = {
    Noclip = false, Flight = false, Visibility = false,
    FlightSpeed = 3, WalkSpeed = 16,
    BarPosition = "Bottom",
    UIMode = "TaskBar", -- TaskBar | Minimalist
    BarCollapsed = false,
    Keybinds = {
        ToggleUI = Enum.KeyCode.RightAlt,
        Flight = nil, Noclip = nil, Respawn = nil, Visibility = nil,
    },
}
local movers, noclipDefaults, characterParts = {}, {}, {}

local Library = { _theme = C, SiriusChar = SiriusChar, _ConfigControls = {}, _ApplyingConfig = false }
env.KhfreshSiriusChar = SiriusChar
env.KhfreshLib = Library

function Library:SetTheme(theme)
    if type(theme) ~= "table" then return end
    for k, v in pairs(theme) do C[k] = v; Library._theme[k] = v end
end

-- Toast notifications (Sirius-like)
local notifyGui
local notifyQueue = {}
local function ensureNotifyGui()
    if notifyGui and notifyGui.Parent then return notifyGui end
    local parent = (getHiddenUI and getHiddenUI()) or CoreGui
    notifyGui = make("ScreenGui", {
        Name = "KhfreshNotify", ResetOnSpawn = false, DisplayOrder = 5000, IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = true,
    }, parent)
    return notifyGui
end

function Library:Notify(data)
    data = data or {}
    local title = tostring(data.Title or "Khfresh")
    local msg = tostring(data.Content or data.Message or data.Text or "")
    local dur = tonumber(data.Duration) or 3
    local gui = ensureNotifyGui()
    local card = make("Frame", {
        BackgroundColor3 = Color3.fromRGB(22, 22, 28), BackgroundTransparency = 1,
        BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -18, 0, 18 + #notifyQueue * 82),
        Size = UDim2.fromOffset(320, 72), ZIndex = 1000,
    }, gui)
    corner(card, 14)
    stroke(card, C.Stroke, 1, 0.35)
    gradient(card, Color3.fromRGB(36, 36, 46), Color3.fromRGB(18, 18, 24), 100)
    make("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 20),
        Font = Enum.Font.GothamBold, Text = title, TextColor3 = C.Text, TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left, TextTransparency = 1, ZIndex = 51,
    }, card)
    make("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 32), Size = UDim2.new(1, -28, 0, 28),
        Font = Enum.Font.Gotham, Text = msg, TextColor3 = C.Muted, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, TextTransparency = 1, ZIndex = 51,
    }, card)
    table.insert(notifyQueue, card)
    for _, d in ipairs(card:GetDescendants()) do
        if d:IsA("TextLabel") then
            TweenService:Create(d, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
        end
    end
    TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Quint), {
        BackgroundTransparency = 0.08, Position = UDim2.new(1, -18, 0, 18 + (#notifyQueue - 1) * 82),
    }):Play()
    task.delay(dur, function()
        TweenService:Create(card, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
        for _, d in ipairs(card:GetDescendants()) do
            if d:IsA("TextLabel") then TweenService:Create(d, TweenInfo.new(0.25), { TextTransparency = 1 }):Play() end
        end
        task.delay(0.3, function()
            card:Destroy()
            for i, v in ipairs(notifyQueue) do
                if v == card then table.remove(notifyQueue, i); break end
            end
            for i, v in ipairs(notifyQueue) do
                TweenService:Create(v, TweenInfo.new(0.2), {
                    Position = UDim2.new(1, -18, 0, 18 + (i - 1) * 82),
                }):Play()
            end
        end)
    end)
end

local function installSiriusAntiKick()
    if env.khfreshSiriusAntiKick then return end
    if not (hookMetamethod and getnamecallmethod) then return end
    env.khfreshSiriusAntiKick = true
    pcall(function()
        local originalNamecall
        originalNamecall = hookMetamethod(game, "__namecall", function(self, ...)
            if self == LocalPlayer and tostring(getnamecallmethod()):lower() == "kick" then
                Library:Notify({ Title = "Anti-Kick", Message = "Blocked client kick.", Duration = 3 })
                return
            end
            return originalNamecall(self, ...)
        end)
        local originalIndex
        originalIndex = hookMetamethod(game, "__index", function(self, key)
            if self == LocalPlayer and type(key) == "string" and key:lower() == "kick" then
                return function()
                    Library:Notify({ Title = "Anti-Kick", Message = "Blocked Kick().", Duration = 3 })
                end
            end
            return originalIndex(self, key)
        end)
    end)
end

local function siriusRespawn()
    local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if h then h:ChangeState(Enum.HumanoidStateType.Dead) end
end

local function applyVisibility(on)
    SiriusChar.Visibility = on and true or false
    local char = LocalPlayer.Character
    if not char then return end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") or d:IsA("Decal") then
            pcall(function() d.LocalTransparencyModifier = on and 1 or 0 end)
        end
    end
end

local function setFlight(on)
    SiriusChar.Flight = on and true or false
    local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then humanoid.PlatformStand = SiriusChar.Flight end
    if not SiriusChar.Flight then
        if movers[1] then pcall(function() movers[1].Parent = nil end) end
        if movers[2] then pcall(function() movers[2].Parent = nil end) end
    end
end

local function setNoclip(on) SiriusChar.Noclip = on and true or false end

local function trackCharacterParts(character)
    table.clear(characterParts); table.clear(noclipDefaults)
    if not character then return end
    for _, d in ipairs(character:GetDescendants()) do
        if d:IsA("BasePart") then
            characterParts[d] = true; noclipDefaults[d] = d.CanCollide
        end
    end
    character.DescendantAdded:Connect(function(part)
        if part:IsA("BasePart") then
            characterParts[part] = true
            if noclipDefaults[part] == nil then noclipDefaults[part] = part.CanCollide end
        end
    end)
end

local function startSiriusRuntime()
    if env.khfreshSiriusRuntime then return end
    env.khfreshSiriusRuntime = true
    installSiriusAntiKick()
    -- Spatial Shield (Sirius-style): mute very loud sounds
    pcall(function()
        Workspace.DescendantAdded:Connect(function(obj)
            if obj:IsA("Sound") then
                task.defer(function()
                    pcall(function()
                        if obj.Volume and obj.Volume > 2 then
                            obj.Volume = math.min(obj.Volume, 0.5)
                        end
                    end)
                end)
            end
        end)
    end)
    if LocalPlayer.Character then trackCharacterParts(LocalPlayer.Character) end
    LocalPlayer.CharacterAdded:Connect(function(c)
        trackCharacterParts(c)
        if SiriusChar.Visibility then task.defer(applyVisibility, true) end
        if SiriusChar.Flight then
            task.defer(function()
                local h = c:FindFirstChildOfClass("Humanoid")
                if h then h.PlatformStand = true end
            end)
        end
        task.defer(function()
            local h = c:FindFirstChildOfClass("Humanoid")
            if h then h.WalkSpeed = SiriusChar.WalkSpeed end
        end)
    end)

    local noclipWasActive = false
    RunService.Stepped:Connect(function()
        local active = SiriusChar.Noclip
        if not active and not noclipWasActive then return end
        for part in pairs(characterParts) do
            if part.Parent then
                if active then part.CanCollide = false
                else
                    local d = noclipDefaults[part]
                    part.CanCollide = (d == nil) and true or d
                end
            end
        end
        noclipWasActive = active
    end)

    RunService.Heartbeat:Connect(function()
        local character = LocalPlayer.Character
        local primaryPart = character and character.PrimaryPart
        if not primaryPart then return end
        local bodyVelocity, bodyGyro = movers[1], movers[2]
        if bodyVelocity then
            local alive = pcall(function() local _ = bodyVelocity.Parent end)
            if not alive then movers = {}; bodyVelocity, bodyGyro = nil, nil end
        end
        if not bodyVelocity then
            bodyVelocity = Instance.new("BodyVelocity")
            bodyVelocity.MaxForce = Vector3.one * 9e9
            bodyGyro = Instance.new("BodyGyro")
            bodyGyro.MaxTorque = Vector3.one * 9e9
            bodyGyro.P = 9e4
            movers = { bodyVelocity, bodyGyro }
        end
        if SiriusChar.Flight then
            local camCFrame = Camera.CFrame
            local velocity = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then velocity = velocity + camCFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then velocity = velocity - camCFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then velocity = velocity + camCFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then velocity = velocity - camCFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then velocity = velocity + Vector3.yAxis end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
                velocity = velocity - Vector3.yAxis
            end
            -- Classic BodyVelocity flight (no tween — was causing fall)
            local spd = (tonumber(SiriusChar.FlightSpeed) or 3) * 50
            if velocity.Magnitude > 0 then
                velocity = velocity.Unit * spd
            end
            bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            bodyVelocity.Velocity = velocity
            bodyVelocity.Parent = primaryPart
            bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            bodyGyro.P = 9e4
            bodyGyro.CFrame = CFrame.new(primaryPart.Position, primaryPart.Position + camCFrame.LookVector)
            bodyGyro.Parent = primaryPart
            local hum = character:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.PlatformStand = true
            end
        else
            bodyVelocity.Velocity = Vector3.zero
            bodyVelocity.Parent = nil
            bodyGyro.Parent = nil
        end
    end)
end

Library.SetFlight = setFlight
Library.SetNoclip = setNoclip
Library.SetVisibility = applyVisibility
Library.Respawn = siriusRespawn

local function buildWindow(config)
    config = config or {}
    startSiriusRuntime()

    local function clamp(n, a, b)
        if n < a then return a end
        if n > b then return b end
        return n
    end
    local function getVP()
        local cam = workspace.CurrentCamera
        if cam and cam.ViewportSize then return cam.ViewportSize end
        return Vector2.new(1280, 720)
    end

    -- Adaptive sizing: one responsive system for PC, tablet and phone.
    -- We scale the *container targets* from the viewport instead of applying an
    -- extra UIScale, preventing the double-shrinking seen in earlier builds.
    local function getResponsiveMetrics()
        local vs = getVP()
        local shortest = math.min(vs.X, vs.Y)
        local margin = clamp(math.floor(shortest * 0.014), 10, 20)
        -- Keep the responsive system, but restore the larger V68 SmartBar proportions.
        return {
            Viewport = vs, Scale = 1, Margin = margin,
            BarH = 68, BarIcon = 34, BarGap = 18,
        }
    end
    local function fitBarSize(nButtons)
        local m = getResponsiveMetrics()
        local n = math.max(nButtons or 1, 1)
        local viewportW = math.max(360, m.Viewport.X - m.Margin * 2)
        local desired = 168 + n * 48
        local w = math.min(math.max(550, desired), math.min(680, viewportW))
        return math.floor(w), m.BarH, m.BarIcon
    end

    -- Panels stay compact on large desktops while growing enough for larger
    -- viewports. Heights follow the same scale so the UI feels proportional.
    local PANEL_MIN_W, PANEL_MAX_W = 560, 920
    local function fitPanelSize(kind)
        local m = getResponsiveMetrics()
        local vs = m.Viewport
        local pos = (SiriusChar and SiriusChar.BarPosition) or "Bottom"
        local edge = m.Margin
        local thick = m.BarH
        local gap = m.BarGap
        local maxW, maxH
        if pos == "Center" then
            maxW = vs.X - edge * 2
            maxH = vs.Y - edge * 2
        elseif pos == "Left" or pos == "Right" then
            maxW = vs.X - thick - gap - edge * 2
            maxH = vs.Y - edge * 2
        else
            maxW = vs.X - edge * 2
            maxH = vs.Y - thick - gap - edge * 2
        end
        maxW = math.max(300, maxW)
        maxH = math.max(260, maxH)
        local baseW, baseH = 760, 540
        if kind == "home" then baseW, baseH = 835, 585
        elseif kind == "settings" then baseW, baseH = 650, 520 end
        local wTarget = math.floor(baseW * m.Scale + 0.5)
        local hTarget = math.floor(baseH * m.Scale + 0.5)
        local w = math.min(wTarget, maxW, PANEL_MAX_W)
        local h = math.min(hTarget, maxH)
        if maxW >= PANEL_MIN_W then
            w = clamp(w, PANEL_MIN_W, math.min(PANEL_MAX_W, maxW))
        else
            w = maxW
        end
        return math.floor(w), math.floor(math.max(290, h))
    end

    -- Action feedback is deliberately tiny and throttled per control so it can be
    -- enabled across both UI surfaces without turning fast interactions into spam.
    local uiActionLast = {}
local function notifyUIAction(controlName, message)
        local key = tostring(controlName or "Control")
        pcall(function()
            Library:Notify({Title = "Khfresh UI", Message = tostring(message or ("Clicked: " .. key)), Duration = 1.35})
        end)
    end

    local function bindUIAction(button, callback)
        if not button or type(callback) ~= "function" then return end
        local busy = false
        local function fire()
            if busy then return end
            busy = true
            pcall(callback)
            task.defer(function() busy = false end)
        end
        button.MouseButton1Click:Connect(fire)
        button.Activated:Connect(fire)
    end

    -- One callback path for every library control. This guarantees that an action
    -- always produces visible feedback even when the consumer callback is nil or errors.
    local function runUIActionCallback(config, actionName, payload, message)
        actionName = tostring(actionName or "Control")
        if not Library._ApplyingConfig then
            notifyUIAction(actionName, message or ("Running: " .. actionName))
        end
        local cb = type(config) == "table" and config.Callback or nil
        if type(cb) ~= "function" then
            return true
        end
        local ok, err = pcall(cb, payload)
        if not ok and not Library._ApplyingConfig then
            notifyUIAction(actionName .. " Error", "Failed: " .. tostring(err))
        end
        return ok
    end

    local function markCustomFeedback(inst)
        if inst then pcall(function() inst:SetAttribute("__KhfreshCustomFeedback", true) end) end
        return inst
    end
    -- Resize every grid owned by this shell from its actual container width.
    -- No fixed 175/200px cells: each grid chooses a column count and cell width
    -- that fit the current viewport/container.
    local function refreshResponsiveGrids(root)
        if not root then return end
        for _, grid in ipairs(root:GetDescendants()) do
            if grid:IsA("UIGridLayout") then
                local parent = grid.Parent
                if parent and parent:IsA("GuiObject") and parent.AbsoluteSize.X > 0 then
                    local width = parent.AbsoluteSize.X
                    local gap = tonumber(grid:GetAttribute("KhfreshGap")) or 10
                    local target = tonumber(grid:GetAttribute("KhfreshTargetCell")) or 185
                    local cellH = tonumber(grid:GetAttribute("KhfreshCellHeight")) or math.max(44, math.floor(target * 0.34))
                    local cols = math.max(1, math.floor((width + gap) / (target + gap)))
                    cols = math.min(cols, tonumber(grid:GetAttribute("KhfreshMaxColumns")) or 4)
                    local cellW = math.floor((width - gap * (cols - 1)) / cols)
                    cellW = math.max(90, cellW)
                    if cellW * cols + gap * (cols - 1) > width then
                        cols = math.max(1, cols - 1)
                        cellW = math.floor((width - gap * (cols - 1)) / cols)
                    end
                    grid.CellPadding = UDim2.fromOffset(gap, gap)
                    grid.CellSize = UDim2.fromOffset(cellW, cellH)
                end
            end
        end
    end

    local function installUniversalClickFeedback(root)
        if not root then return end
        local function bind(inst)
            if not inst or not inst:IsA("GuiButton") then return end
            if inst:GetAttribute("__KhfreshCustomFeedback") then return end
            if inst:GetAttribute("__KhfreshClickFeedback") then return end
            inst:SetAttribute("__KhfreshClickFeedback", true)
            inst.Activated:Connect(function()
                if inst:GetAttribute("__KhfreshCustomFeedback") then return end
                local label = inst:GetAttribute("KhfreshActionName") or inst.Name or "Control"
                notifyUIAction(label, "Clicked: " .. tostring(label))
            end)
        end
        bind(root)
        for _, inst in ipairs(root:GetDescendants()) do bind(inst) end
        root.DescendantAdded:Connect(function(inst) task.defer(function() bind(inst) end) end)
    end

    pcall(function()
        TeleportService.TeleportInitFailed:Connect(function(player, result, errorMessage)
            if player == LocalPlayer then
                Library:Notify({Title="Server Hop", Message="Teleport failed: " .. tostring(result) .. " — " .. tostring(errorMessage or "Unknown error"), Duration=4})
            end
        end)
    end)

local guiParent = (getHiddenUI and getHiddenUI()) or CoreGui
    local old = guiParent:FindFirstChild("KhfreshSiriusShell")
    if old then old:Destroy() end

    local ScreenGui = make("ScreenGui", {
        Name = "KhfreshSiriusShell", ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999, IgnoreGuiInset = true,
    }, guiParent)

    -- Covers both the SmartBar and the center/minimalist hub because both are
    -- children of this ScreenGui.
    installUniversalClickFeedback(ScreenGui)

    -- ===== SMART BAR (V68-sized, clean glass) =====
    local _barW, _barH, _barBtn = fitBarSize(7)
    local smartBar = make("Frame", {
        Name = "SmartBar", BackgroundColor3 = C.Bar, BackgroundTransparency = 0.08,
        BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -20), Size = UDim2.fromOffset(_barW, _barH), ZIndex = 30,
        ClipsDescendants = false,
    }, ScreenGui)
    corner(smartBar, 16)
    stroke(smartBar, C.Stroke, 1, 0.45)
    gradient(smartBar, Color3.fromRGB(34, 34, 42), Color3.fromRGB(14, 14, 18), 90)

    -- Collapse arrows (Sirius-style)
    local function chevronIcon(dir)
        local map = {
            up = LUCIDE["chevron-up"] or LUCIDE["arrow-up"],
            down = LUCIDE["chevron-down"] or LUCIDE["arrow-down"],
            left = LUCIDE["chevron-left"] or LUCIDE["arrow-left"],
            right = LUCIDE["chevron-right"] or LUCIDE["arrow-right"],
        }
        return map[dir] or "rbxassetid://0"
    end
    local collapseBtn = make("ImageButton", {
        Name = "Collapse", BackgroundColor3 = Color3.fromRGB(36, 36, 46), BackgroundTransparency = 0.2,
        BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.fromOffset(34, 18),
        Image = chevronIcon("down"), ImageColor3 = Color3.fromRGB(220, 220, 230),
        ScaleType = Enum.ScaleType.Fit, AutoButtonColor = true, ZIndex = 40,
        Active = true, Visible = true,
    }, smartBar)
    corner(collapseBtn, 8)
    make("UIPadding", {
        PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3),
        PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
    }, collapseBtn)
    stroke(collapseBtn, Color3.fromRGB(70, 70, 85), 1, 0.4)

    local timeLabel = make("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 0), Size = UDim2.fromOffset(52, 64),
        Font = Enum.Font.GothamBold, Text = os.date("%H:%M"), TextColor3 = C.Text, TextSize = 14, ZIndex = 31,
    }, smartBar)
    task.spawn(function()
        while smartBar.Parent do timeLabel.Text = os.date("%H:%M"); task.wait(15) end
    end)

    local buttonsHost = make("Frame", {
        Name = "Buttons", BackgroundTransparency = 1,
        Position = UDim2.fromOffset(72, 14), Size = UDim2.new(1, -130, 0, 36), ZIndex = 31,
    }, smartBar)
    local buttonsLayout = make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 7),
        VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
    }, buttonsHost)

    -- Gear only (no Settings tab on bar)
    local gearWrap = make("Frame", {
        BackgroundColor3 = Color3.fromRGB(45, 45, 55), BackgroundTransparency = 0,
        BorderSizePixel = 0, Position = UDim2.new(1, -48, 0.5, -17), Size = UDim2.fromOffset(34, 34), ZIndex = 32,
    }, smartBar)
    corner(gearWrap, 11)
    gradient(gearWrap, Color3.fromRGB(80, 80, 92), Color3.fromRGB(22, 22, 28), 135)
    stroke(gearWrap, Color3.fromRGB(100, 100, 115), 1, 0.35)
    local gearBtn = make("ImageButton", {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        Image = "rbxassetid://120090449970711",
        ImageColor3 = Color3.fromRGB(235, 235, 245),
        ScaleType = Enum.ScaleType.Fit, AutoButtonColor = false, ZIndex = 33,
    }, gearWrap)
    make("UIPadding", {
        PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7),
        PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7),
    }, gearBtn)
    hoverScale(gearWrap, 0.9)

    local panels, openName, animToken, colorIdx = {}, nil, 0, 0
    local dropdownLayer = make("Folder", { Name = "DropdownLayer" }, ScreenGui)
    local openDropdowns = {}
    local function closeAllDropdowns()
        for _, menu in ipairs(openDropdowns) do
            if menu and menu.Parent then menu.Visible = false end
        end
    end
    local barVisibleSize = UDim2.fromOffset(520, 64)

    local updateCollapseIcon
    -- v64 edge-layout core: Top/Bottom horizontal; Left/Right vertical.
    local function applyBarLayout()
        local pos = SiriusChar.BarPosition
        local n = math.max(colorIdx, 1)
        local barW, barH, btnSz = fitBarSize(n)
        barVisibleSize = UDim2.fromOffset(barW, barH)
        if SiriusChar.BarCollapsed then
            smartBar.Visible = false
            return
        end
        if SiriusChar.BarPosition == "Center" or (SiriusChar.UIMode == "Minimalist") then
            smartBar.Visible = false
            return
        end

        if pos == "Top" or pos == "Bottom" then
            local timeW = 58
            local gearW = 38
            local sidePad = 12
            local y = math.floor((barH - btnSz) / 2)
            smartBar.Size = UDim2.fromOffset(barW, barH)
            if pos == "Top" then
                smartBar.AnchorPoint = Vector2.new(0.5, 0)
                smartBar.Position = UDim2.new(0.5, 0, 0, 20)
                collapseBtn.Image = chevronIcon("up")
                collapseBtn.AnchorPoint = Vector2.new(0.5, 0)
                collapseBtn.Position = UDim2.new(0.5, 0, 1, 4)
            else
                smartBar.AnchorPoint = Vector2.new(0.5, 1)
                smartBar.Position = UDim2.new(0.5, 0, 1, -20)
                collapseBtn.Image = chevronIcon("down")
                collapseBtn.AnchorPoint = Vector2.new(0.5, 1)
                collapseBtn.Position = UDim2.new(0.5, 0, 0, -4)
            end
            buttonsLayout.FillDirection = Enum.FillDirection.Horizontal
            buttonsHost.Position = UDim2.fromOffset(timeW + 6, y)
            buttonsHost.Size = UDim2.new(1, -(timeW + gearW + 26), 0, btnSz)
            gearWrap.AnchorPoint = Vector2.new(1, 0.5)
            gearWrap.Position = UDim2.new(1, -sidePad, 0.5, 0)
            gearWrap.Size = UDim2.fromOffset(34, 34)
            timeLabel.Position = UDim2.fromOffset(12, 0)
            timeLabel.Size = UDim2.fromOffset(timeW, barH)
            timeLabel.TextXAlignment = Enum.TextXAlignment.Left
            timeLabel.TextYAlignment = Enum.TextYAlignment.Center
            return
        end

        -- Edge dock: always vertical. The dock is narrow and every icon is centered
        -- in the same fixed-width track, so it cannot become a horizontal strip.
        local m = getResponsiveMetrics()
        local sideW = math.max(62, math.min(68, m.BarH + 4))
        local vs = getVP()
        local maxH = math.max(260, vs.Y - 40)
        local desiredH = math.floor((96 + n * 42) * m.Scale)
        local len = math.min(maxH, math.max(300, desiredH))
        smartBar.Size = UDim2.fromOffset(sideW, len)

        buttonsLayout.FillDirection = Enum.FillDirection.Vertical
        buttonsHost.Position = UDim2.new(0.5, -btnSz / 2, 0, 56)
        buttonsHost.Size = UDim2.fromOffset(btnSz, math.max(44, len - 112))
        gearWrap.Size = UDim2.fromOffset(34, 34)
        gearWrap.AnchorPoint = Vector2.new(0.5, 1)
        gearWrap.Position = UDim2.new(0.5, 0, 1, -10)
        timeLabel.Position = UDim2.fromOffset(4, 8)
        timeLabel.Size = UDim2.fromOffset(sideW - 8, 30)
        timeLabel.TextXAlignment = Enum.TextXAlignment.Center
        timeLabel.TextYAlignment = Enum.TextYAlignment.Center

        if pos == "Left" then
            smartBar.AnchorPoint = Vector2.new(0, 0.5)
            smartBar.Position = UDim2.new(0, 20, 0.5, 0)
            collapseBtn.Image = chevronIcon("left")
            collapseBtn.AnchorPoint = Vector2.new(0, 0.5)
            collapseBtn.Position = UDim2.new(1, 4, 0.5, 0)
        else
            smartBar.AnchorPoint = Vector2.new(1, 0.5)
            smartBar.Position = UDim2.new(1, -20, 0.5, 0)
            collapseBtn.Image = chevronIcon("right")
            collapseBtn.AnchorPoint = Vector2.new(1, 0.5)
            collapseBtn.Position = UDim2.new(0, -4, 0.5, 0)
        end
    end
        if type(updateCollapseIcon) == "function" then updateCollapseIcon() end

    local collapseBusy = false
    local updateCenterMode = function() end
    local applyUIMode = function() end
    local showTabInHub, rebuildSideNav, sizeCenterHub
    local centerHub, centerToggle, hubVisible
    local draggingBar, barDragStart, barStartPos = false, nil, nil

    updateCollapseIcon = function()
        local pos = SiriusChar.BarPosition or "Bottom"
        local hidden = SiriusChar.BarCollapsed == true
        collapseBtn.Visible = true
        collapseBtn.Active = true
        collapseBtn.ImageTransparency = 0
        collapseBtn.BackgroundTransparency = 0.2
        collapseBtn.Size = UDim2.fromOffset(36, 18)

        if hidden then
            -- Only when bar is hidden: floating arrow to restore BAR only
            collapseBtn.Parent = ScreenGui
            collapseBtn.ZIndex = 200
            collapseBtn.Image = chevronIcon(
                (pos == "Bottom" and "up") or (pos == "Top" and "down")
                or (pos == "Left" and "right") or "left"
            )
            if pos == "Bottom" then
                collapseBtn.AnchorPoint = Vector2.new(0.5, 1)
                collapseBtn.Position = UDim2.new(0.5, 0, 1, -8)
            elseif pos == "Top" then
                collapseBtn.AnchorPoint = Vector2.new(0.5, 0)
                collapseBtn.Position = UDim2.new(0.5, 0, 0, 8)
            elseif pos == "Left" then
                collapseBtn.AnchorPoint = Vector2.new(0, 0.5)
                collapseBtn.Position = UDim2.new(0, 8, 0.5, 0)
            else
                collapseBtn.AnchorPoint = Vector2.new(1, 0.5)
                collapseBtn.Position = UDim2.new(1, -8, 0.5, 0)
            end
        else
            -- Arrow outside bar edge (not over icons)
            collapseBtn.Parent = smartBar
            collapseBtn.ZIndex = 40
            collapseBtn.Image = chevronIcon(
                (pos == "Bottom" and "down") or (pos == "Top" and "up")
                or (pos == "Left" and "left") or "right"
            )
            if pos == "Bottom" then
                collapseBtn.AnchorPoint = Vector2.new(0.5, 1)
                collapseBtn.Position = UDim2.new(0.5, 0, 0, -2)
            elseif pos == "Top" then
                collapseBtn.AnchorPoint = Vector2.new(0.5, 0)
                collapseBtn.Position = UDim2.new(0.5, 0, 1, 2)
            elseif pos == "Left" then
                collapseBtn.AnchorPoint = Vector2.new(0, 0.5)
                collapseBtn.Position = UDim2.new(1, 2, 0.5, 0)
            else
                collapseBtn.AnchorPoint = Vector2.new(1, 0.5)
                collapseBtn.Position = UDim2.new(0, -2, 0.5, 0)
            end
        end
    end


    -- ONLY hide/show the TAB BAR (not panels)
    local function toggleBarCollapse()
        if collapseBusy then return end
        collapseBusy = true
        draggingBar = false
        task.delay(0.4, function() collapseBusy = false end)

        local pos = SiriusChar.BarPosition or "Bottom"
        local TI = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

        if not SiriusChar.BarCollapsed then
            SiriusChar.BarCollapsed = true
            local hidePos
            if pos == "Bottom" then hidePos = UDim2.new(0.5, 0, 1, 90)
            elseif pos == "Top" then hidePos = UDim2.new(0.5, 0, 0, -90)
            elseif pos == "Left" then hidePos = UDim2.new(0, -90, 0.5, 0)
            else hidePos = UDim2.new(1, 90, 0.5, 0)
            end
            TweenService:Create(smartBar, TI, {
                Position = hidePos,
                BackgroundTransparency = 1,
            }):Play()
            task.delay(0.28, function()
                smartBar.Visible = false
                updateCollapseIcon()
                collapseBusy = false
            end)
            -- show arrow immediately so user can open again
            updateCollapseIcon()
        else
            SiriusChar.BarCollapsed = false
            applyBarLayout()
            local target = smartBar.Position
            local startPos
            if pos == "Bottom" then startPos = UDim2.new(0.5, 0, 1, 90)
            elseif pos == "Top" then startPos = UDim2.new(0.5, 0, 0, -90)
            elseif pos == "Left" then startPos = UDim2.new(0, -90, 0.5, 0)
            else startPos = UDim2.new(1, 90, 0.5, 0)
            end
            smartBar.Visible = true
            smartBar.Position = startPos
            smartBar.BackgroundTransparency = 1
            TweenService:Create(smartBar, TI, {
                Position = target,
                BackgroundTransparency = 0.05,
            }):Play()
            updateCollapseIcon()
            task.delay(0.3, function() collapseBusy = false end)
        end
    end

markCustomFeedback(collapseBtn)
    collapseBtn:SetAttribute("KhfreshActionName", "Collapse Tab Bar")
    bindUIAction(collapseBtn, function()
        notifyUIAction("Collapse Tab Bar", "Toggling tab bar")
        toggleBarCollapse()
    end)

    -- DRAG SMART BAR (ignore when collapsed / when pressing buttons)
    smartBar.InputBegan:Connect(function(input)
        if SiriusChar.BarCollapsed or collapseBusy then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingBar = true
            barDragStart = input.Position
            barStartPos = smartBar.Position
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if not draggingBar then return end
            draggingBar = false
            -- CRITICAL: do not snap/show bar while collapsed (this caused hide→bounce back)
            if SiriusChar.BarCollapsed or collapseBusy or not smartBar.Visible then return end
            local abs = smartBar.AbsolutePosition
            local sz = smartBar.AbsoluteSize
            local vx = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1920, 1080)
            local dist = {
                Bottom = vx.Y - (abs.Y + sz.Y),
                Top = abs.Y,
                Left = abs.X,
                Right = vx.X - (abs.X + sz.X),
            }
            local best, bestD = "Bottom", dist.Bottom
            for k, v in pairs(dist) do
                if v < bestD then best, bestD = k, v end
            end
            local mode = SiriusChar.UIMode or "Automatic"
            -- Automatic + TaskBar: only 4 edges (NO center snap — was breaking UI)
            if mode == "Minimalist" then
                best = "Center"
            end
            SiriusChar.BarPosition = best
            applyBarLayout()
            pcall(applyUIMode)
            if openName and panels[openName] and panels[openName].panel and best ~= "Center" then
                local pd = panels[openName]
                pd.panel.Position = panelOpenPos(pd.panel, pd.isHome)
            end
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if SiriusChar.BarCollapsed or not smartBar.Visible then draggingBar = false return end
        if draggingBar and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - barDragStart
            smartBar.Position = UDim2.new(
                barStartPos.X.Scale, barStartPos.X.Offset + delta.X,
                barStartPos.Y.Scale, barStartPos.Y.Offset + delta.Y
            )
        end
    end)

        local function panelOpenPos(p, isHomeFlag)
        local vs = getVP()
        local w = p.Size.X.Offset
        local h = p.Size.Y.Offset
        local pos = SiriusChar.BarPosition or "Bottom"
        local edge = 16
        local thick = getResponsiveMetrics().BarH
        local gap = 24

        -- Center mode: panel centered on screen (no bar)
        if pos == "Center" or isHomeFlag then
            local x = (vs.X - w) / 2
            local y = (vs.Y - h) / 2
            x = clamp(x, edge, math.max(edge, vs.X - w - edge))
            y = clamp(y, edge, math.max(edge, vs.Y - h - edge))
            return UDim2.fromOffset(math.floor(x), math.floor(y))
        end

        local x, y
        if pos == "Top" then
            x = (vs.X - w) / 2
            y = edge + thick + gap
        elseif pos == "Left" then
            -- panel to the RIGHT of vertical bar
            x = edge + thick + gap
            y = (vs.Y - h) / 2
        elseif pos == "Right" then
            -- panel to the LEFT of vertical bar
            x = vs.X - edge - thick - gap - w
            y = (vs.Y - h) / 2
        else -- Bottom
            x = (vs.X - w) / 2
            y = vs.Y - edge - thick - gap - h
        end
        x = clamp(x, edge, math.max(edge, vs.X - w - edge))
        y = clamp(y, edge, math.max(edge, vs.Y - h - edge))
        -- Extra: never sit under vertical bar
        if pos == "Left" and x < thick + gap then
            x = thick + gap + edge
        elseif pos == "Right" and (x + w) > (vs.X - thick - gap) then
            x = vs.X - thick - gap - edge - w
        end
        return UDim2.fromOffset(math.floor(x), math.floor(y))
    end

local function panelRestPos(p, isHomeFlag)
        local w, h = p.Size.X.Offset, p.Size.Y.Offset
        local pos = SiriusChar.BarPosition
        if isHomeFlag then
            if pos == "Top" then return UDim2.new(0.5, -w / 2, 0, -h - 40)
            elseif pos == "Left" then return UDim2.new(0, -w - 40, 0.5, -h / 2)
            elseif pos == "Right" then return UDim2.new(1, 40, 0.5, -h / 2)
            end
            return UDim2.new(0.5, -w / 2, 1, 60)
        end
        if pos == "Top" then return UDim2.new(0.5, -w / 2, 0, -h - 40)
        elseif pos == "Left" then return UDim2.new(0, -w - 40, 0.5, -h / 2)
        elseif pos == "Right" then return UDim2.new(1, 40, 0.5, -h / 2)
        end
        return UDim2.new(0.5, -w / 2, 1, 60)
    end
local function animateClose(name, token)
        local data = panels[name]
        if not data or not data.panel.Visible then return end
        local p = data.panel
        TweenService:Create(p, TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
            Position = panelRestPos(p, data.isHome), BackgroundTransparency = 1,
        }):Play()
        task.delay(0.34, function()
            if token ~= animToken then return end
            if openName ~= name then p.Visible = false; p.BackgroundTransparency = data.isHome and 0.08 or 0.04 end
        end)
    end
    local function animateOpen(name, token)
        local data = panels[name]
        if not data then return end
        local p = data.panel
        p.BackgroundTransparency = data.isHome and 0.08 or 0.04
        p.Position = panelRestPos(p, data.isHome)
        p.Visible = true
        p.Active = true
        p.ZIndex = 80
        if data.body then data.body.Visible = true; data.body.ZIndex = 81 end
        TweenService:Create(p, TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Position = panelOpenPos(p, data.isHome), BackgroundTransparency = data.isHome and 0.08 or 0.04,
        }):Play()
    end
    local function openPanel(name)
        closeAllDropdowns()
        if not panels[name] then
            notifyUIAction("Tab: " .. tostring(name), "Panel missing: " .. tostring(name))
            return
        end
        if SiriusChar.BarPosition == "Center" then
            smartBar.Visible = false
            openName = name
            -- updateCenterMode / showTabInHub defined later; call when ready
            task.defer(function()
                pcall(function()
                    hubVisible = true
                    if centerHub then centerHub.Visible = true end
                    if centerToggle then centerToggle.Visible = false end
                    if type(sizeCenterHub) == "function" then sizeCenterHub() end
                    if type(rebuildSideNav) == "function" then rebuildSideNav() end
                    if type(showTabInHub) == "function" then
                        showTabInHub(name)
                    else
                        pcall(updateCenterMode)
                    end
                end)
            end)
            return
        end
        if SiriusChar.BarCollapsed then
            SiriusChar.BarCollapsed = false
            collapseBusy = false
            smartBar.Visible = true
            smartBar.BackgroundTransparency = 0.05
            pcall(applyBarLayout)
            pcall(updateCollapseIcon)
        end
        animToken = animToken + 1
        local token = animToken
        if openName == name then
            local closing = openName; openName = nil
            animateClose(closing, token)
            return
        end
        local previous = openName
        openName = name
        local target = panels[name].panel
        target.Visible = true
        target.Active = true
        target.ZIndex = 80
        if previous then
            animateClose(previous, token)
            task.delay(0.1, function() if token == animToken then animateOpen(name, token) end end)
        else
            animateOpen(name, token)
        end
    end

    
    -- ===== MINIMALIST HUB — golden ratio + liquid glass (fully separate from TaskBar) =====
    local PHI = 1.6180339887
    local SIDE_W = 108
    local LOGO_ID = "rbxassetid://120090449970711"
    local TAB_ICONS = {
        Home = "house", Settings = "settings", Main = "fish-symbol", Shop = "shopping-bag",
        Quests = "scroll-text", Teleport = "map-pin", Ascend = "arrow-up",
        Exchange = "arrow-left-right", Character = "user",
    }

    local function glassStroke(inst, thick)
        stroke(inst, Color3.fromRGB(255, 255, 255), thick or 1, 0.82)
    end

    centerHub = make("Frame", {
        Name = "MinimalistHub", BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.92, BorderSizePixel = 0, Visible = false,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.fromOffset(900, 600), ZIndex = 50, ClipsDescendants = true,
    }, ScreenGui)
    corner(centerHub, 22)
    glassStroke(centerHub, 1)
    -- layered glass tint
    local glassBg = make("Frame", {
        BackgroundColor3 = Color3.fromRGB(16, 18, 24), BackgroundTransparency = 0.42,
        Size = UDim2.fromScale(1, 1), ZIndex = 50, BorderSizePixel = 0,
    }, centerHub)
    corner(glassBg, 22)
    -- no strong color gradient — pure glass
    local glassSheen = make("Frame", {
        BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.86,
        Size = UDim2.new(1, 0, 0.4, 0), ZIndex = 50, BorderSizePixel = 0,
    }, centerHub)
    corner(glassSheen, 22)
    gradient(glassSheen, Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255), 90)

    -- Header / drag bar
    local hubHeader = make("Frame", {
        Name = "Header", BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.92, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 44), ZIndex = 52,
    }, centerHub)
    local logoImg = make("ImageLabel", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 6),
        Size = UDim2.fromOffset(32, 32), Image = LOGO_ID, ScaleType = Enum.ScaleType.Fit, ZIndex = 53,
    }, hubHeader)
    local hubTitle = make("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(50, 0),
        Size = UDim2.new(1, -100, 1, 0), Font = Enum.Font.GothamBold,
        Text = "Khfresh", TextSize = 15, TextColor3 = Color3.fromRGB(250, 250, 255),
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 53,
    }, hubHeader)

    local hubClose = make("TextButton", {
        BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.85,
        BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(26, 26),
        Font = Enum.Font.GothamBold, Text = "×", TextSize = 14,
        TextColor3 = Color3.fromRGB(240, 240, 250), AutoButtonColor = false, ZIndex = 54,
    }, hubHeader)
    corner(hubClose, 8)
    glassStroke(hubClose, 1)

    -- Left nav (icons + short labels)
    local sideNav = make("ScrollingFrame", {
        Name = "SideNav", BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.93, BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 44), Size = UDim2.new(0, SIDE_W, 1, -44),
        ScrollBarThickness = 3, ScrollBarImageColor3 = Color3.fromRGB(220, 220, 230),
        CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ZIndex = 51, ClipsDescendants = true,
    }, centerHub)
    glassStroke(sideNav, 1)
    make("UIListLayout", {
        Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
    }, sideNav)
    make("UIPadding", {
        PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
    }, sideNav)

    local contentHost = make("ScrollingFrame", {
        Name = "Content", BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(SIDE_W + 8, 52), Size = UDim2.new(1, -(SIDE_W + 16), 1, -60),
        ScrollBarThickness = 4, ScrollBarImageColor3 = Color3.fromRGB(230, 230, 240),
        ScrollBarImageTransparency = 0.3, CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 51, ClipsDescendants = true,
    }, centerHub)

    local contentTitle = make("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(SIDE_W + 12, 48),
        Size = UDim2.fromOffset(1, 1), Visible = false, ZIndex = 1,
    }, centerHub)

    -- Resize grip (bottom-right) golden-ratio friendly
    local hubGrip = make("TextButton", {
        Name = "ResizeGrip", BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.75, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -8, 1, -8),
        Size = UDim2.fromOffset(18, 18), Text = "", AutoButtonColor = false, ZIndex = 55,
    }, centerHub)
    corner(hubGrip, 5)
    glassStroke(hubGrip, 1)

    centerToggle = make("ImageButton", {
        Name = "CenterToggle", BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.05, BorderSizePixel = 0, Visible = false,
        AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -18),
        Size = UDim2.fromOffset(52, 52), Image = LOGO_ID,
        ImageColor3 = Color3.new(1, 1, 1), ScaleType = Enum.ScaleType.Fit,
        AutoButtonColor = true, ZIndex = 60,
    }, ScreenGui)
    corner(centerToggle, 16)
    stroke(centerToggle, Color3.fromRGB(255, 255, 255), 1, 0.5)
    make("UIPadding", {
        PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
    }, centerToggle)
    gradient(centerToggle, Color3.fromRGB(255, 255, 255), Color3.fromRGB(10, 10, 12), 135)

    local centerActiveTab = nil
    hubVisible = true

    local function restoreBody(data)
        if not data or not data.body then return end
        data.body.Parent = data.panel
        data.body.Position = data.bodyPos or UDim2.fromOffset(16, 44)
        data.body.Size = data.bodySize or UDim2.new(1, -32, 1, -56)
    end

    -- Apply liquid-glass look to controls inside mounted body
    local function styleGlassTree(root)
        for _, d in ipairs(root:GetDescendants()) do
            pcall(function()
                -- strip TaskBar color gradients (red/green/blue tiles)
                if d:IsA("UIGradient") then
                    local p = d.Parent
                    if p and (p:IsA("Frame") or p:IsA("TextButton") or p:IsA("ImageButton")) then
                        d:Destroy()
                    end
                    return
                end
                if d:IsA("Frame") or d:IsA("TextButton") or d:IsA("ImageButton") then
                    -- neutral glass fill
                    if d.Name ~= "Knob" and d.Name ~= "Fill" then
                        d.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                        if d.BackgroundTransparency < 0.7 then
                            d.BackgroundTransparency = 0.82
                        end
                    end
                    local st = d:FindFirstChildOfClass("UIStroke")
                    if st then
                        st.Color = Color3.fromRGB(255, 255, 255)
                        st.Transparency = 0.78
                        st.Thickness = 1
                    end
                elseif d:IsA("ScrollingFrame") then
                    d.ScrollBarImageColor3 = Color3.fromRGB(240, 240, 250)
                    d.ScrollBarImageTransparency = 0.25
                    d.ScrollBarThickness = 4
                    d.BackgroundTransparency = 1
                elseif d:IsA("TextLabel") or d:IsA("TextButton") then
                    if d.TextColor3.R < 0.5 and d.TextColor3.G < 0.5 and d.TextColor3.B < 0.5 then
                        d.TextColor3 = Color3.fromRGB(230, 232, 240)
                    end
                end
                -- hide TaskBar-only layout rows inside Settings when Minimalist
                if d:IsA("TextLabel") or d:IsA("TextButton") then
                    local tx = string.lower(tostring(d.Text or ""))
                    if tx:find("smartbar", 1, true) or tx:find("bar position", 1, true) then
                        local row = d.Parent
                        if row and row:IsA("Frame") then
                            row.Visible = false
                        end
                    end
                end
            end)
        end
    end

    showTabInHub = function(name)
        local data = panels[name]
        if not data then return end
        if centerActiveTab and panels[centerActiveTab] then
            restoreBody(panels[centerActiveTab])
            panels[centerActiveTab].panel.Visible = false
        end
        centerActiveTab = name
        openName = name
        for _, d in pairs(panels) do
            if d.panel then d.panel.Visible = false end
        end
        local body = data.body
        body.Parent = contentHost
        body.Position = UDim2.fromOffset(12, 8)
        body.Size = UDim2.new(1, -16, 0, 0)
        body.AutomaticSize = Enum.AutomaticSize.Y
        body.Visible = true
        styleGlassTree(body)
        -- fade-in animation
        body.BackgroundTransparency = 1
        for _, d in ipairs(body:GetDescendants()) do
            pcall(function()
                if d:IsA("TextLabel") or d:IsA("TextButton") then
                    d:SetAttribute("TT", d.TextTransparency)
                    d.TextTransparency = 1
                elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
                    d:SetAttribute("IT", d.ImageTransparency)
                    d.ImageTransparency = 1
                elseif d:IsA("Frame") or d:IsA("TextButton") then
                    d:SetAttribute("BT", d.BackgroundTransparency)
                    d.BackgroundTransparency = 1
                end
            end)
        end
        local TI = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        for _, d in ipairs(body:GetDescendants()) do
            pcall(function()
                if d:IsA("TextLabel") or d:IsA("TextButton") then
                    TweenService:Create(d, TI, { TextTransparency = d:GetAttribute("TT") or 0 }):Play()
                elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
                    TweenService:Create(d, TI, { ImageTransparency = d:GetAttribute("IT") or 0 }):Play()
                elseif d:IsA("GuiObject") and d:GetAttribute("BT") ~= nil then
                    TweenService:Create(d, TI, { BackgroundTransparency = d:GetAttribute("BT") or 0.82 }):Play()
                end
            end)
        end
        for _, ch in ipairs(sideNav:GetChildren()) do
            if ch:IsA("GuiButton") then
                local on = ch.Name == name
                ch.BackgroundTransparency = on and 0.55 or 0.88
                local tlab = ch:FindFirstChild("Lbl")
                if tlab then
                    tlab.TextColor3 = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(190, 195, 210)
                end
            end
        end
    end

    rebuildSideNav = function()
        for _, ch in ipairs(sideNav:GetChildren()) do
            if ch:IsA("GuiButton") then ch:Destroy() end
        end
        local names = {}
        for name, _ in pairs(panels) do names[#names + 1] = name end
        table.sort(names, function(a, b)
            if a == "Home" then return true end
            if b == "Home" then return false end
            if a == "Settings" then return false end
            if b == "Settings" then return true end
            return a < b
        end)
        for i, name in ipairs(names) do
            local iconKey = TAB_ICONS[name] or "circle"
            local b = make("TextButton", {
                Name = name, BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                BackgroundTransparency = 0.88, BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 40), Text = "", AutoButtonColor = false,
                LayoutOrder = i, ZIndex = 52,
            }, sideNav)
            corner(b, 12)
            glassStroke(b, 1)
            local ic = make("ImageLabel", {
                BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
                Position = UDim2.new(0.5, 0, 0, 3), Size = UDim2.fromOffset(16, 16),
                Image = resolveIcon(name, iconKey), ImageColor3 = Color3.fromRGB(240, 240, 250),
                ScaleType = Enum.ScaleType.Fit, ZIndex = 53,
            }, b)
            local lbl = make("TextLabel", {
                Name = "Lbl", BackgroundTransparency = 1,
                Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 16),
                Font = Enum.Font.GothamMedium, Text = name, TextSize = 9,
                TextColor3 = Color3.fromRGB(190, 195, 210), ZIndex = 53,
            }, b)
            b:SetAttribute("KhfreshActionName", "Hub Tab • " .. tostring(name))
            markCustomFeedback(b)
            bindUIAction(b, function()
                notifyUIAction("Hub Tab • " .. tostring(name), "Opening: " .. tostring(name))
                showTabInHub(name)
            end)
        end
    end

    sizeCenterHub = function()
        local m = getResponsiveMetrics()
        local vs = m.Viewport
        -- Fluid center hub sizing follows the real viewport.
        local HUB_MIN_W, HUB_MAX_W = 520, 900
        local HUB_MIN_H, HUB_MAX_H = 420, 640
        local w = clamp(math.floor(vs.X * 0.55), HUB_MIN_W, HUB_MAX_W)
        local h = clamp(math.floor(vs.Y * 0.64), HUB_MIN_H, HUB_MAX_H)
        w = math.min(w, math.max(300, vs.X - m.Margin * 2))
        h = math.min(h, math.max(290, vs.Y - m.Margin * 2))
        centerHub.Size = UDim2.fromOffset(math.floor(w), math.floor(h))
        if not centerHub:GetAttribute("UserDragged") then
            centerHub.AnchorPoint = Vector2.new(0.5, 0.5)
            centerHub.Position = UDim2.new(0.5, 0, 0.5, 0)
        end
    end

    local function enterHubMode()
        smartBar.Visible = false
        collapseBtn.Visible = false
        sizeCenterHub()
        rebuildSideNav()
        for _, d in pairs(panels) do
            if d.panel then d.panel.Visible = false end
        end
        centerToggle.Visible = true -- always show floating logo toggle
        if hubVisible then
            centerHub.Visible = true
            centerHub.BackgroundTransparency = 1
            local TI = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
            TweenService:Create(centerHub, TI, { BackgroundTransparency = 0.92 }):Play()
            local first = centerActiveTab
            if not first or not panels[first] then
                first = panels["Home"] and "Home" or next(panels)
            end
            if first then showTabInHub(first) end
        else
            centerHub.Visible = false
        end
    end

    local function leaveHubMode()
        if centerActiveTab and panels[centerActiveTab] then
            restoreBody(panels[centerActiveTab])
        end
        for _, d in pairs(panels) do
            restoreBody(d)
            if d.panel then d.panel.Visible = false end
        end
        centerActiveTab = nil
        openName = nil
        centerHub.Visible = false
        centerToggle.Visible = false
        hubVisible = true
        SiriusChar.BarCollapsed = false
        if SiriusChar.BarPosition == "Center" then
            SiriusChar.BarPosition = "Bottom"
        end
        smartBar.Visible = true
        smartBar.BackgroundTransparency = 0.05
        collapseBtn.Visible = true
        applyBarLayout()
        pcall(updateCollapseIcon)
    end

    applyUIMode = function()
        local mode = SiriusChar.UIMode or "Automatic"
        if mode == "Minimalist" then
            SiriusChar.BarPosition = "Center"
            enterHubMode()
        else
            if SiriusChar.BarPosition == "Center" then
                SiriusChar.BarPosition = "Bottom"
            end
            leaveHubMode()
        end
    end
    updateCenterMode = applyUIMode

    -- Minimize: hide hub, keep floating toggle
    local hubMin = make("TextButton", {
        BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.85,
        BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -42, 0.5, 0), Size = UDim2.fromOffset(26, 26),
        Font = Enum.Font.GothamBold, Text = "–", TextSize = 16,
        TextColor3 = Color3.fromRGB(240, 240, 250), AutoButtonColor = false, ZIndex = 54,
    }, hubHeader)
    corner(hubMin, 8)
    glassStroke(hubMin, 1)

    markCustomFeedback(hubMin)
    hubMin:SetAttribute("KhfreshActionName", "Minimize Hub")
    hubMin.MouseButton1Click:Connect(function()
        notifyUIAction("Minimize Hub", "Minimizing hub")
        hubVisible = false
        centerHub.Visible = false
        centerToggle.Visible = true
    end)

    -- Close (X): full unload UI + stop autofarm + destroy toggle
    markCustomFeedback(hubClose)
    hubClose:SetAttribute("KhfreshActionName", "Close Hub")
    hubClose.MouseButton1Click:Connect(function()
        notifyUIAction("Close Hub", "Closing hub")
        pcall(function()
            -- stop farms / flight
            if Fishing and Fishing.Flags then
                for k in pairs(Fishing.Flags) do Fishing.Flags[k] = false end
            end
            if KhfreshState then
                KhfreshState.SelectedAutoFarmFishRunning = false
                if KhfreshState.AutoFarm then KhfreshState.AutoFarm.enabled = false end
            end
            SiriusChar.Flight = false
            SiriusChar.Noclip = false
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = false end
            if movers[1] then pcall(function() movers[1]:Destroy() end) end
            if movers[2] then pcall(function() movers[2]:Destroy() end) end
            movers = {}
        end)
        pcall(function() ScreenGui:Destroy() end)
        pcall(function() env.khfreshSiriusRuntime = false end)
        pcall(function() env.KhfreshUIAlive = false end)
    end)

    -- Floating toggle ALWAYS visible in Minimalist; click toggles hub
    markCustomFeedback(centerToggle)
    centerToggle:SetAttribute("KhfreshActionName", "Floating Hub Toggle")
    bindUIAction(centerToggle, function()
        hubVisible = not centerHub.Visible
        notifyUIAction("Floating Hub Toggle", hubVisible and "Opening hub" or "Hiding hub")
        centerHub.Visible = hubVisible
        centerToggle.Visible = true -- always keep toggle
        if hubVisible then
            sizeCenterHub()
            rebuildSideNav()
            local first = centerActiveTab or (panels["Home"] and "Home") or next(panels)
            if first then showTabInHub(first) end
        end
    end)

    -- Drag floating toggle
    do
        local dragging, d0, p0 = false, nil, nil
        centerToggle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                d0 = input.Position
                p0 = centerToggle.AbsolutePosition
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
            local vs = getVP()
            local nx = p0.X + (input.Position.X - d0.X)
            local ny = p0.Y + (input.Position.Y - d0.Y)
            nx = clamp(nx, 0, vs.X - 52)
            ny = clamp(ny, 0, vs.Y - 52)
            centerToggle.AnchorPoint = Vector2.new(0, 0)
            centerToggle.Position = UDim2.fromOffset(math.floor(nx), math.floor(ny))
        end)
    end

    -- Drag entire header (WinUI-like)
    do
        local dragging, d0, p0 = false, nil, nil
        hubHeader.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                d0 = input.Position
                p0 = centerHub.AbsolutePosition
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if dragging then centerHub:SetAttribute("UserDragged", true) end
                dragging = false
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
            local vs = getVP()
            local nx = p0.X + (input.Position.X - d0.X)
            local ny = p0.Y + (input.Position.Y - d0.Y)
            nx = clamp(nx, 0, vs.X - centerHub.AbsoluteSize.X)
            ny = clamp(ny, 0, vs.Y - centerHub.AbsoluteSize.Y)
            centerHub.AnchorPoint = Vector2.new(0, 0)
            centerHub.Position = UDim2.fromOffset(math.floor(nx), math.floor(ny))
        end)
    end

    -- Resize grip
    do
        local resizing, s0, sz0 = false, nil, nil
        hubGrip.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                resizing = true
                s0 = input.Position
                sz0 = centerHub.AbsoluteSize
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                resizing = false
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if not resizing then return end
            if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
            local vs = getVP()
            local nw = clamp(math.floor(sz0.X + (input.Position.X - s0.X)), 380, math.floor(vs.X * 0.80))
            -- keep near golden ratio when resizing width
            local nh = clamp(math.floor(nw / PHI), 280, math.floor(vs.Y * 0.8))
            -- allow free height if user pulls more vertically
            local freeH = clamp(math.floor(sz0.Y + (input.Position.Y - s0.Y)), 280, math.floor(vs.Y * 0.85))
            nh = math.floor((nh + freeH) / 2)
            centerHub.Size = UDim2.fromOffset(nw, nh)
        end)
    end

markCustomFeedback(gearBtn)
    gearBtn:SetAttribute("KhfreshActionName", "Settings")
    bindUIAction(gearBtn, function()
        notifyUIAction("Settings", "Opening Settings")
        if panels["Settings"] then openPanel("Settings") else notifyUIAction("Settings", "Panel not ready: Settings") end
    end)

    UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local kb = SiriusChar.Keybinds
        if input.KeyCode == (kb.ToggleUI or Enum.KeyCode.RightAlt) or input.KeyCode == Enum.KeyCode.K then
            -- Toggle main hub visibility (not just bar collapse)
            if centerHub then
                local show = not centerHub.Visible
                centerHub.Visible = show
                hubVisible = show
                if centerToggle then centerToggle.Visible = not show end
                if show then
                    SiriusChar.BarCollapsed = false
                    if smartBar then smartBar.Visible = true end
                end
                notifyUIAction("Toggle UI", show and "UI ON" or "UI OFF")
            else
                notifyUIAction("Toggle UI", "Toggling bar")
                if SiriusChar.BarCollapsed then
                    SiriusChar.BarCollapsed = false
                    if collapseBtn then collapseBtn.Parent = ScreenGui end
                    applyBarLayout()
                else
                    toggleBarCollapse()
                end
            end
            return
        end
        if kb.Flight and input.KeyCode == kb.Flight then
            setFlight(not SiriusChar.Flight)
            Library:Notify({ Title = "Flight", Message = SiriusChar.Flight and "ON" or "OFF", Duration = 2 })
        elseif kb.Noclip and input.KeyCode == kb.Noclip then
            setNoclip(not SiriusChar.Noclip)
            Library:Notify({ Title = "Noclip", Message = SiriusChar.Noclip and "ON" or "OFF", Duration = 2 })
        elseif kb.Respawn and input.KeyCode == kb.Respawn then
            notifyUIAction("Respawn", "Respawning player")
            siriusRespawn()
        elseif kb.Visibility and input.KeyCode == kb.Visibility then
            applyVisibility(not SiriusChar.Visibility)
            Library:Notify({ Title = "Visibility", Message = SiriusChar.Visibility and "Hidden" or "Visible", Duration = 2 })
        end
    end)

    local WindowApi = {}

    function WindowApi:CreateTab(name, icon)
        local title = type(name) == "table" and tostring(name.Title or name.Name or "Tab") or tostring(name or "Tab")
        local iconArg = type(name) == "table" and (name.Icon or icon) or icon
        local isSettings = (title == "Settings")
        local isHome = (title == "Home" or title == "Overview")

        local col = BAR_COLORS[1]
        if not isSettings then
            colorIdx = colorIdx + 1
            col = BAR_COLORS[((colorIdx - 1) % #BAR_COLORS) + 1]
        end
        local image = resolveIcon(title, iconArg)

        -- Settings: NO bar button (gear only)
        local btn = nil
        if not isSettings then
            local _, _, tabBtnSize = fitBarSize(colorIdx)
            btn = make("ImageButton", {
                Name = title, BackgroundColor3 = col, BackgroundTransparency = 0.05,
                BorderSizePixel = 0, Size = UDim2.fromOffset(tabBtnSize, tabBtnSize), Image = image,
                ImageColor3 = Color3.new(1, 1, 1), ScaleType = Enum.ScaleType.Fit,
                AutoButtonColor = false, Active = true, Selectable = false, LayoutOrder = colorIdx, ZIndex = 90,
            }, buttonsHost)
            corner(btn, 9)
            make("UIPadding", {
                PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
                PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
            }, btn)
            gradient(btn, col, Color3.new(col.R * 0.4, col.G * 0.4, col.B * 0.4), 135)
            stroke(btn, Color3.new(math.min(col.R + 0.2, 1), math.min(col.G + 0.2, 1), math.min(col.B + 0.2, 1)), 1, 0.3)
            hoverScale(btn, 0.88)
            applyBarLayout()
        end

        -- Panel sizes: Home = near fullscreen; others larger
        local panelW, panelH
        if isHome then
            panelW, panelH = fitPanelSize("home")
        elseif isSettings then
            panelW, panelH = fitPanelSize("settings")
        else
            panelW, panelH = fitPanelSize("tab")
        end

        local panel = make("Frame", {
            Name = title .. "Panel", BackgroundColor3 = C.Panel, BackgroundTransparency = isHome and 0.08 or 0.04,
            BorderSizePixel = 0, Position = UDim2.new(0.5, -panelW / 2, 1, 50),
            Size = UDim2.fromOffset(panelW, panelH), Visible = false, ZIndex = 80, ClipsDescendants = true,
        }, ScreenGui)
        corner(panel, 20)
        stroke(panel, C.Stroke, 1, 0.28)
        gradient(panel, Color3.fromRGB(30, 30, 38), Color3.fromRGB(14, 14, 20), 115)

        -- Resize grip (bottom-right of panel)
        do
            local grip = make("TextButton", {
                Name = "ResizeGrip", BackgroundColor3 = Color3.fromRGB(80, 80, 100),
                BackgroundTransparency = 0.35, BorderSizePixel = 0,
                AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -6, 1, -6),
                Size = UDim2.fromOffset(16, 16), Text = "", AutoButtonColor = false, ZIndex = 40,
            }, panel)
            corner(grip, 4)
            local resizing, startPos, startSize = false, nil, nil
            grip.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    resizing = true
                    startPos = input.Position
                    startSize = panel.AbsoluteSize
                end
            end)
            UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    resizing = false
                end
            end)
            UserInputService.InputChanged:Connect(function(input)
                if not resizing then return end
                if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
                local dx = input.Position.X - startPos.X
                local dy = input.Position.Y - startPos.Y
                local vs = getVP()
                local nw = clamp(math.floor(startSize.X + dx), 280, vs.X - 32)
                local nh = clamp(math.floor(startSize.Y + dy), 200, vs.Y - 32)
                panel.Size = UDim2.fromOffset(nw, nh)
            end)
        end

        make("ImageLabel", {
            BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 12), Size = UDim2.fromOffset(18, 18),
            Image = image, ImageColor3 = C.Text, ScaleType = Enum.ScaleType.Fit, ZIndex = 18,
        }, panel)
        make("TextLabel", {
            BackgroundTransparency = 1, Position = UDim2.fromOffset(42, 8), Size = UDim2.new(1, -90, 0, 26),
            Font = Enum.Font.GothamBold, Text = isHome and ("Welcome home, " .. (LocalPlayer.DisplayName or LocalPlayer.Name)) or title,
            TextColor3 = C.Text, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 18,
        }, panel)

        local body = make("ScrollingFrame", {
            BackgroundTransparency = 1, BorderSizePixel = 0,
            Position = UDim2.fromOffset(16, 44), Size = UDim2.new(1, -32, 1, -56),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(0, 0, 0, 0),
            ScrollBarThickness = 6, ScrollBarImageColor3 = Color3.fromRGB(120, 120, 140),
            ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 81, ClipsDescendants = true,
            ElasticBehavior = Enum.ElasticBehavior.Never,
        }, panel)
        local bodyLayout = make("UIListLayout", {
            Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
        }, body)
        make("UIPadding", {
            PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 24),
            PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
        }, body)
        local function refreshCanvas()
            body.CanvasSize = UDim2.new(0, 0, 0, math.max(bodyLayout.AbsoluteContentSize.Y + 30, 1))
        end
        bodyLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshCanvas)
        task.defer(refreshCanvas)

        panels[title] = { panel = panel, body = body, isHome = isHome, bodyPos = body.Position, bodySize = body.Size }
        if btn then
            markCustomFeedback(btn)
            bindUIAction(btn, function()
                notifyUIAction("Tab: " .. title, "Opening: " .. title)
                if panels[title] then openPanel(title) else notifyUIAction("Tab: " .. title, "Panel not ready: " .. title) end
            end)
        end

        local sectionHost = body
        local settingsPages = nil

        -- Home: Sirius-style content only once (no feature duplicates later)
        if isHome then
            do
                local executorName = "Unknown"
                pcall(function()
                    if identifyexecutor then executorName = select(1, identifyexecutor())
                    elseif getexecutorname then executorName = tostring(getexecutorname())
                    end
                end)
                executorName = tostring(executorName or "Unknown")
                local hwid = "N/A"
                pcall(function()
                    hwid = tostring(game:GetService("RbxAnalyticsService"):GetClientId())
                end)
                local joinClock = os.clock()

                local profile = make("Frame", {
                    BackgroundColor3 = Color3.fromRGB(32, 28, 48), BackgroundTransparency = 0,
                    Size = UDim2.new(1, 0, 0, 92), ZIndex = 16,
                }, body)
                corner(profile, 16)
                gradient(profile, Color3.fromRGB(60, 45, 100), Color3.fromRGB(22, 20, 36), 110)
                stroke(profile, Color3.fromRGB(120, 90, 180), 1, 0.35)

                local avatar = make("ImageLabel", {
                    BackgroundColor3 = Color3.fromRGB(50, 50, 60), BorderSizePixel = 0,
                    Position = UDim2.fromOffset(14, 16), Size = UDim2.fromOffset(60, 60), ZIndex = 17,
                }, profile)
                corner(avatar, 12)
                task.spawn(function()
                    local ok, content = pcall(function()
                        return Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
                    end)
                    if ok and content then avatar.Image = content end
                end)

                make("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.fromOffset(88, 16), Size = UDim2.new(1, -100, 0, 22),
                    Font = Enum.Font.GothamBold, Text = tostring(LocalPlayer.DisplayName or LocalPlayer.Name),
                    TextColor3 = Color3.new(1,1,1), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 17,
                }, profile)
                make("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.fromOffset(88, 40), Size = UDim2.new(1, -100, 0, 18),
                    Font = Enum.Font.Gotham, Text = "@" .. tostring(LocalPlayer.Name) .. "  |  " .. executorName,
                    TextColor3 = Color3.fromRGB(180, 180, 195), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 17,
                }, profile)
                make("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.fromOffset(88, 60), Size = UDim2.new(1, -100, 0, 18),
                    Font = Enum.Font.Code, Text = "HWID: " .. string.sub(tostring(hwid), 1, 24),
                    TextColor3 = Color3.fromRGB(150, 150, 170), TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 17,
                }, profile)

                local serverCard = make("Frame", {
                    BackgroundColor3 = Color3.fromRGB(18, 48, 42), BackgroundTransparency = 0,
                    Size = UDim2.new(1, 0, 0, 280), ZIndex = 16, LayoutOrder = 2, ClipsDescendants = true,
                }, body)
                corner(serverCard, 16)
                gradient(serverCard, Color3.fromRGB(30, 90, 75), Color3.fromRGB(12, 32, 28), 95)
                stroke(serverCard, Color3.fromRGB(50, 150, 120), 1, 0.3)
                make("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 20),
                    Font = Enum.Font.GothamBold, Text = "Server", TextColor3 = Color3.new(1,1,1), TextSize = 15,
                    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 17,
                }, serverCard)

                local grid = make("Frame", {
                    BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 40),
                    Size = UDim2.new(1, -24, 0, 230), ZIndex = 17,
                }, serverCard)
                make("UIGridLayout", {
                    CellSize = UDim2.fromOffset(210, 70), CellPadding = UDim2.fromOffset(12, 12),
                    SortOrder = Enum.SortOrder.LayoutOrder,
                }, grid)

                local function mini(titleText, valueText, c0, c1)
                    local f = make("Frame", {
                        BackgroundColor3 = c0, BackgroundTransparency = 0, ZIndex = 18,
                    }, grid)
                    corner(f, 12)
                    gradient(f, c0, c1, 120)
                    stroke(f, c0, 1, 0.4)
                    make("TextLabel", {
                        BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -24, 0, 16),
                        Font = Enum.Font.GothamBold, Text = titleText, TextColor3 = Color3.new(1,1,1), TextSize = 12,
                        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 19,
                    }, f)
                    local vl = make("TextLabel", {
                        BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -24, 0, 20),
                        Font = Enum.Font.Gotham, Text = valueText, TextColor3 = Color3.fromRGB(220, 220, 230), TextSize = 12,
                        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 19,
                    }, f)
                    return vl
                end

                mini("Players", tostring(#Players:GetPlayers()) .. " / " .. tostring(Players.MaxPlayers), Color3.fromRGB(40, 130, 95), Color3.fromRGB(18, 45, 32))
                mini("Place ID", tostring(game.PlaceId), Color3.fromRGB(55, 100, 160), Color3.fromRGB(20, 35, 55))
                mini("Job ID", string.sub(tostring(game.JobId), 1, 16) .. "...", Color3.fromRGB(140, 90, 40), Color3.fromRGB(45, 28, 12))
                mini("Executor", executorName, Color3.fromRGB(110, 60, 150), Color3.fromRGB(35, 20, 50))
                local timeLbl = mini("Time in Server", "0s", Color3.fromRGB(160, 55, 80), Color3.fromRGB(50, 18, 28))
                task.spawn(function()
                    while timeLbl.Parent do
                        local sec = math.floor(os.clock() - joinClock)
                        timeLbl.Text = string.format("%dm %02ds", math.floor(sec / 60), sec % 60)
                        task.wait(1)
                    end
                end)

                local socialTitle = make("TextLabel", {
                    BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28),
                    Font = Enum.Font.GothamBold, Text = "Community", TextColor3 = Color3.new(1,1,1), TextSize = 15,
                    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 16, LayoutOrder = 3,
                }, body)

                local socialRow = make("Frame", {
                    BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56), ZIndex = 16, LayoutOrder = 4,
                }, body)
                make("UIListLayout", {
                    FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12),
                    HorizontalAlignment = Enum.HorizontalAlignment.Left,
                }, socialRow)

                local function socialBtn(label, url, c0, c1)
                    local b = make("TextButton", {
                        BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.82, BorderSizePixel = 0,
                        Size = UDim2.fromOffset(150, 48), Font = Enum.Font.GothamBold, Text = label,
                        TextColor3 = Color3.new(1,1,1), TextSize = 14, AutoButtonColor = false, ZIndex = 17,
                    }, socialRow)
                    corner(b, 14)
                    stroke(b, Color3.fromRGB(255, 255, 255), 1, 0.75)
                    gradient(b, c0, c1, 125)
                    stroke(b, c0, 1, 0.3)
                    hoverScale(b, 0.95)
                    b.MouseButton1Click:Connect(function()
                        local sc = setclipboard or toclipboard or set_clipboard
                        if sc then
                            pcall(sc, url)
                            Library:Notify({ Title = label, Message = "Copied!", Duration = 2 })
                        else
                            Library:Notify({ Title = label, Message = tostring(url), Duration = 4 })
                        end
                    end)
                end
                socialBtn("Discord", "https://discord.gg/WWyZqKw3yC", Color3.fromRGB(88, 101, 242), Color3.fromRGB(35, 40, 100))
                socialBtn("YouTube", "https://www.youtube.com/@unixfunni", Color3.fromRGB(220, 45, 45), Color3.fromRGB(90, 18, 18))
                socialBtn("TikTok", "https://www.tiktok.com/@khangleminh001", Color3.fromRGB(45, 45, 55), Color3.fromRGB(18, 18, 22))
            end
        end

        if isSettings then
            settingsPages = {}
            local header = make("Frame", {
                BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                LayoutOrder = -200, ZIndex = 16,
            }, body)
            make("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, header)
            local tiles = make("Frame", {
                BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 130), ZIndex = 17,
            }, header)
            make("UIPadding", { PaddingTop = UDim.new(0, 8) }, tiles)
            make("UIGridLayout", {
                CellSize = UDim2.fromOffset(165, 50), CellPadding = UDim2.fromOffset(10, 10),
                KhfreshTargetCell = 165, KhfreshCellHeight = 50, KhfreshGap = 10, KhfreshMaxColumns = 4,
            }, tiles)
            local cats = {
                { "GENERAL", Color3.fromRGB(30, 80, 140) },
                { "KEYBINDS", Color3.fromRGB(30, 120, 80) },
                { "CHARACTER", Color3.fromRGB(140, 50, 40) },
                { "LAYOUT", Color3.fromRGB(100, 70, 30) },
                { "ANTI-BAN", Color3.fromRGB(120, 30, 40) },
            }
            for _, catDef in ipairs(cats) do
                local page = make("Frame", {
                    BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                    Visible = false, LayoutOrder = -50, ZIndex = 16,
                }, body)
                make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, page)
                make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 6) }, page)
                settingsPages[catDef[1]] = page
                local tile = make("TextButton", {
                    BackgroundColor3 = catDef[2], BackgroundTransparency = 0.12, BorderSizePixel = 0,
                    Text = catDef[1], Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.Text,
                    AutoButtonColor = false, ZIndex = 18,
                }, tiles)
                corner(tile, 14)
                gradient(tile, catDef[2], Color3.new(catDef[2].R * 0.25, catDef[2].G * 0.25, catDef[2].B * 0.25), 120)
                stroke(tile, catDef[2], 1, 0.35)
                hoverScale(tile, 0.94)
                tile.MouseButton1Click:Connect(function()
                    for n, p in pairs(settingsPages) do
                        if n == catDef[1] then
                            p.Visible = true
                            p.BackgroundTransparency = 1
                            for _, ch in ipairs(p:GetDescendants()) do
                                if ch:IsA("TextLabel") or ch:IsA("TextButton") then
                                    local tr = ch.TextTransparency
                                    ch.TextTransparency = 1
                                    TweenService:Create(ch, TweenInfo.new(0.28, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
                                end
                            end
                        else
                            p.Visible = false
                        end
                    end
                end)
            end
            sectionHost = settingsPages["GENERAL"]
            if sectionHost then sectionHost.Visible = true end

            -- KEYBINDS / CHARACTER / LAYOUT / ANTI-BAN (same as v40 simplified)
            do
                local kbPage = settingsPages["KEYBINDS"]
                local function keybindProp(label, keyName)
                    local r = make("Frame", {
                        BackgroundColor3 = C.Row, BackgroundTransparency = 0.18, BorderSizePixel = 0,
                        Size = UDim2.new(1, 0, 0, 42), ZIndex = 17,
                    }, kbPage)
                    corner(r, 12)
                    make("TextLabel", {
                        BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.5, 0, 1, 0),
                        Font = Enum.Font.Gotham, Text = label, TextColor3 = C.Text, TextSize = 13,
                        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 18,
                    }, r)
                    local b = make("TextButton", {
                        BackgroundColor3 = C.PanelDeep, BorderSizePixel = 0,
                        Position = UDim2.new(1, -124, 0.5, -15), Size = UDim2.fromOffset(112, 30),
                        Font = Enum.Font.GothamMedium,
                        Text = SiriusChar.Keybinds[keyName] and SiriusChar.Keybinds[keyName].Name or "None",
                        TextColor3 = C.Text, TextSize = 12, AutoButtonColor = false, ZIndex = 18,
                    }, r)
                    corner(b, 9)
                    local listening = false
                    b.MouseButton1Click:Connect(function()
                        if listening then return end
                        listening = true
                        b.Text = "Press key…"
                        local conn
                        conn = UserInputService.InputBegan:Connect(function(input)
                            if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
                            if input.KeyCode == Enum.KeyCode.Escape then
                                SiriusChar.Keybinds[keyName] = nil; b.Text = "None"
                            else
                                SiriusChar.Keybinds[keyName] = input.KeyCode; b.Text = input.KeyCode.Name
                            end
                            listening = false; conn:Disconnect()
                        end)
                    end)
                end
                keybindProp("Toggle UI", "ToggleUI")
                keybindProp("Flight", "Flight")
                keybindProp("Noclip", "Noclip")
                keybindProp("Respawn", "Respawn")
                keybindProp("Visibility", "Visibility")
            end

            do
                local ch = settingsPages["CHARACTER"]
                local function mkSlider(label, minV, maxV, default, color, cb)
                    local r = make("Frame", {
                        BackgroundColor3 = C.Row, BackgroundTransparency = 0.15, BorderSizePixel = 0,
                        Size = UDim2.new(1, 0, 0, 56), ZIndex = 17,
                    }, ch)
                    corner(r, 12)
                    make("TextLabel", {
                        BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(0.7, 0, 0, 16),
                        Font = Enum.Font.Gotham, Text = label, TextColor3 = C.Text, TextSize = 13,
                        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 18,
                    }, r)
                    local valLbl = make("TextLabel", {
                        BackgroundTransparency = 1, Position = UDim2.new(1, -60, 0, 8), Size = UDim2.fromOffset(48, 16),
                        Font = Enum.Font.GothamBold, Text = tostring(default), TextColor3 = C.Muted, TextSize = 12,
                        TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 18,
                    }, r)
                    local bar = make("Frame", {
                        BackgroundColor3 = Color3.fromRGB(40, 40, 50), BorderSizePixel = 0,
                        Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -28, 0, 12), ZIndex = 18,
                    }, r)
                    corner(bar, 6)
                    local val = default
                    local fill = make("Frame", {
                        BackgroundColor3 = color, BorderSizePixel = 0,
                        Size = UDim2.new((val - minV) / (maxV - minV), 0, 1, 0), ZIndex = 19,
                    }, bar)
                    corner(fill, 6)
                    make("UIGradient", {
                        Color = ColorSequence.new({
                            ColorSequenceKeypoint.new(0, Color3.new(math.min(color.R * 1.35, 1), math.min(color.G * 1.35, 1), math.min(color.B * 1.35, 1))),
                            ColorSequenceKeypoint.new(0.55, color),
                            ColorSequenceKeypoint.new(1, Color3.new(color.R * 0.4, color.G * 0.4, color.B * 0.4)),
                        }),
                        Rotation = 0,
                    }, fill)
                    local dragging = false
                    local function setFromX(x)
                        local rel = clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
                        val = math.floor(minV + rel * (maxV - minV) + 0.5)
                        fill.Size = UDim2.new((val - minV) / (maxV - minV), 0, 1, 0)
                        valLbl.Text = tostring(val)
                        cb(val)
                    end
                    bar.InputBegan:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                            dragging = true; setFromX(input.Position.X)
                        end
                    end)
                    UserInputService.InputEnded:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                            dragging = false
                        end
                    end)
                    UserInputService.InputChanged:Connect(function(input)
                        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                            setFromX(input.Position.X)
                        end
                    end)
                end
                mkSlider("Walk Speed", 0, 300, 16, Color3.fromRGB(44, 153, 93), function(v)
                    SiriusChar.WalkSpeed = v
                    pcall(function() LocalPlayer.Character.Humanoid.WalkSpeed = v end)
                end)
                mkSlider("Flight Speed", 1, 25, 3, Color3.fromRGB(170, 37, 46), function(v)
                    SiriusChar.FlightSpeed = v
                end)
                local function charToggle(label, get, set)
                    local r = make("Frame", {
                        BackgroundColor3 = C.Row, BackgroundTransparency = 0.15, BorderSizePixel = 0,
                        Size = UDim2.new(1, 0, 0, 42), ZIndex = 17,
                    }, ch)
                    corner(r, 12)
                    make("TextLabel", {
                        BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.6, 0, 1, 0),
                        Font = Enum.Font.Gotham, Text = label, TextColor3 = C.Text, TextSize = 13,
                        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 18,
                    }, r)
                    local on = get()
                    local track = make("Frame", {
                        BackgroundColor3 = on and C.Accent or Color3.fromRGB(55, 55, 65),
                        BackgroundTransparency = 0.25, BorderSizePixel = 0,
                        Position = UDim2.new(1, -58, 0.5, -13), Size = UDim2.fromOffset(46, 26), ZIndex = 18,
                    }, r)
                    corner(track, 13)
                    stroke(track, Color3.fromRGB(220, 220, 235), 1, 0.65)
                    local knob = make("Frame", {
                        BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.05,
                        BorderSizePixel = 0, Size = UDim2.fromOffset(20, 20),
                        Position = on and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10), ZIndex = 19,
                    }, track)
                    corner(knob, 10)
                    local hit = make("TextButton", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Text = "", ZIndex = 20 }, track)
                    markCustomFeedback(hit)
                    hit:SetAttribute("KhfreshActionName", label)
                    bindUIAction(hit, function()
                        on = not on; set(on)
                        track.BackgroundColor3 = on and C.Accent or Color3.fromRGB(55, 55, 65)
                        notifyUIAction(label, label .. " → " .. (on and "ON" or "OFF"))
                        TweenService:Create(knob, TweenInfo.new(0.18, Enum.EasingStyle.Quint), {
                            Position = on and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10),
                        }):Play()
                    end)
                end
                charToggle("Flight", function() return SiriusChar.Flight end, setFlight)
                charToggle("Noclip", function() return SiriusChar.Noclip end, setNoclip)
                charToggle("Visibility", function() return SiriusChar.Visibility end, applyVisibility)
                local resp = make("TextButton", {
                    BackgroundColor3 = Color3.fromRGB(49, 88, 193), BackgroundTransparency = 0.12, BorderSizePixel = 0,
                    Size = UDim2.new(1, 0, 0, 40), Font = Enum.Font.GothamBold, Text = "Respawn",
                    TextColor3 = C.Text, TextSize = 13, AutoButtonColor = false, ZIndex = 17,
                }, ch)
                corner(resp, 12)
                hoverScale(resp, 0.96)
                resp.MouseButton1Click:Connect(function() notifyUIAction("Respawn", "Running: Respawn"); pcall(siriusRespawn) end)
            end

            do
                local lp = settingsPages["LAYOUT"]
                local row = make("Frame", {
                    BackgroundColor3 = C.Row, BackgroundTransparency = 0.15, BorderSizePixel = 0,
                    Size = UDim2.new(1, 0, 0, 48), ZIndex = 17,
                }, lp)
                corner(row, 12)
                make("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.45, 0, 1, 0),
                    Font = Enum.Font.Gotham, Text = "SmartBar Position", TextColor3 = C.Text, TextSize = 13,
                    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 18,
                }, row)
                local dd = make("TextButton", {
                    BackgroundColor3 = C.PanelDeep, BorderSizePixel = 0,
                    Position = UDim2.new(0.48, 0, 0.5, -16), Size = UDim2.new(0.5, -14, 0, 32),
                    Font = Enum.Font.GothamMedium, Text = SiriusChar.BarPosition or "Bottom",
                    TextColor3 = C.Text, TextSize = 12, AutoButtonColor = false, ZIndex = 18,
                }, row)
                corner(dd, 10)
                stroke(dd, C.Stroke, 1, 0.35)
                gradient(dd, Color3.fromRGB(50, 50, 60), Color3.fromRGB(22, 22, 28), 90)
                local menu = make("Frame", {
                    BackgroundColor3 = Color3.fromRGB(24, 24, 32), BorderSizePixel = 0,
                    Position = UDim2.new(0, 0, 1, 6), Size = UDim2.new(1, 0, 0, 0), Visible = false, ZIndex = 50,
                }, dd)
                corner(menu, 10)
                stroke(menu, C.Stroke, 1, 0.3)
                make("UIListLayout", { Padding = UDim.new(0, 2) }, menu)
                for _, posName in ipairs({ "Bottom", "Top", "Left", "Right" }) do
                    local ib = make("TextButton", {
                        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30),
                        Font = Enum.Font.Gotham, Text = posName, TextColor3 = C.Text, TextSize = 12,
                        AutoButtonColor = false, ZIndex = 51,
                    }, menu)
                    bindUIAction(ib, function()
                        SiriusChar.BarPosition = posName
                        SiriusChar.BarCollapsed = false
                        if SiriusChar.UIMode == "Minimalist" then
                            SiriusChar.UIMode = "TaskBar"
                        end
                        applyBarLayout()
                        pcall(applyUIMode)
                        dd.Text = posName
                        menu.Visible = false
                        if openName and panels[openName] and SiriusChar.BarPosition ~= "Center" then
                            local p = panels[openName].panel
                            p.Position = panelOpenPos(p, panels[openName].isHome)
                        end
                        notifyUIAction("Layout: Bar Position", "Bar → " .. posName)
                        Library:Notify({ Title = "Layout", Message = "Bar → " .. posName, Duration = 2 })
                    end)
                end
                dd.MouseButton1Click:Connect(function()
                    menu.Visible = not menu.Visible
                    if menu.Visible then menu.Size = UDim2.new(1, 0, 0, 128) end
                end)
            end

            -- UI Mode: TaskBar / Minimalist / Automatic
            do
                local row = make("Frame", {
                    BackgroundColor3 = C.PanelDeep, BackgroundTransparency = 0.15, BorderSizePixel = 0,
                    Size = UDim2.new(1, -8, 0, 48), ZIndex = 17,
                }, lp)
                corner(row, 12)
                make("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0),
                    Size = UDim2.new(0.45, 0, 1, 0), Font = Enum.Font.Gotham,
                    Text = "UI Mode", TextColor3 = C.Text, TextSize = 13,
                    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 18,
                }, row)
                local dd2 = make("TextButton", {
                    BackgroundColor3 = C.PanelDeep, BorderSizePixel = 0,
                    Position = UDim2.new(0.48, 0, 0.5, -16), Size = UDim2.new(0.5, -14, 0, 32),
                    Font = Enum.Font.GothamMedium, Text = SiriusChar.UIMode or "Automatic",
                    TextColor3 = C.Text, TextSize = 12, AutoButtonColor = false, ZIndex = 18,
                }, row)
                corner(dd2, 10)
                stroke(dd2, C.Stroke, 1, 0.35)
                local menu2 = make("Frame", {
                    BackgroundColor3 = Color3.fromRGB(24, 24, 32), BorderSizePixel = 0,
                    Position = UDim2.new(0, 0, 1, 6), Size = UDim2.new(1, 0, 0, 0), Visible = false, ZIndex = 50,
                }, dd2)
                corner(menu2, 10)
                stroke(menu2, C.Stroke, 1, 0.3)
                make("UIListLayout", { Padding = UDim.new(0, 2) }, menu2)
                for _, modeName in ipairs({ "TaskBar", "Minimalist" }) do
                    local ib = make("TextButton", {
                        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30),
                        Font = Enum.Font.Gotham, Text = modeName, TextColor3 = C.Text, TextSize = 12,
                        AutoButtonColor = false, ZIndex = 51,
                    }, menu2)
                    ib.MouseButton1Click:Connect(function()
                        SiriusChar.UIMode = modeName
                        if modeName == "Minimalist" then
                            SiriusChar.BarPosition = "Center"
                        elseif modeName == "TaskBar" and SiriusChar.BarPosition == "Center" then
                            SiriusChar.BarPosition = "Bottom"
                        end
                        dd2.Text = modeName
                        menu2.Visible = false
                        pcall(applyUIMode)
                        notifyUIAction("UI Mode", "Mode → " .. modeName)
                        Library:Notify({ Title = "UI Mode", Message = modeName, Duration = 2 })
                    end)
                end
                dd2.MouseButton1Click:Connect(function()
                    menu2.Visible = not menu2.Visible
                    if menu2.Visible then menu2.Size = UDim2.new(1, 0, 0, 64) end
                end)
            end

            do
                local ab = settingsPages["ANTI-BAN"]
                local AntiState = {
                    AntiKick = true,
                    SpatialShield = true,
                    Anonymous = true,
                    BlockTeleportKick = true,
                }
                local function abToggle(label, key, desc)
                    local r = make("Frame", {
                        BackgroundColor3 = C.Row, BackgroundTransparency = 0.12, BorderSizePixel = 0,
                        Size = UDim2.new(1, 0, 0, 52), ZIndex = 17,
                    }, ab)
                    corner(r, 12)
                    gradient(r, Color3.fromRGB(40, 30, 35), Color3.fromRGB(18, 14, 16), 90)
                    make("TextLabel", {
                        BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 6), Size = UDim2.new(0.7, 0, 0, 18),
                        Font = Enum.Font.GothamBold, Text = label, TextColor3 = C.Text, TextSize = 13,
                        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 18,
                    }, r)
                    make("TextLabel", {
                        BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 26), Size = UDim2.new(0.7, 0, 0, 18),
                        Font = Enum.Font.Gotham, Text = desc, TextColor3 = C.Muted, TextSize = 11,
                        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 18,
                    }, r)
                    local on = AntiState[key]
                    local track = make("Frame", {
                        BackgroundColor3 = on and Color3.fromRGB(40, 180, 100) or Color3.fromRGB(55, 55, 65),
                        BackgroundTransparency = 0.2, BorderSizePixel = 0,
                        Position = UDim2.new(1, -58, 0.5, -13), Size = UDim2.fromOffset(46, 26), ZIndex = 18,
                    }, r)
                    corner(track, 13)
                    stroke(track, Color3.fromRGB(220, 220, 235), 1, 0.65)
                    local knob = make("Frame", {
                        BackgroundColor3 = Color3.new(1,1,1), BorderSizePixel = 0, Size = UDim2.fromOffset(20, 20),
                        Position = on and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10), ZIndex = 19,
                    }, track)
                    corner(knob, 10)
                    local hit = make("TextButton", { BackgroundTransparency = 1, Size = UDim2.new(1,0,1,0), Text = "", ZIndex = 20 }, track)
                    hit.MouseButton1Click:Connect(function()
                        on = not on
                        AntiState[key] = on
                        notifyUIAction(label, label .. " → " .. (on and "ON" or "OFF"))
                        track.BackgroundColor3 = on and Color3.fromRGB(40, 180, 100) or Color3.fromRGB(55, 55, 65)
                        TweenService:Create(knob, TweenInfo.new(0.18, Enum.EasingStyle.Quint), {
                            Position = on and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10),
                        }):Play()
                    end)
                end
                abToggle("Client Anti-Kick", "AntiKick", "Block LocalPlayer:Kick (Sirius)")
                abToggle("Spatial Shield", "SpatialShield", "Suppress loud in-game audio")
                abToggle("Anonymous Client", "Anonymous", "Reduce identifiable client signals")
                abToggle("Protective Hooks", "BlockTeleportKick", "Extra namecall/index guards")
                make("TextLabel", {
                    BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Font = Enum.Font.Gotham,
                    Text = "All anti-ban protections default ON (Sirius-style).",
                    TextColor3 = Color3.fromRGB(40, 180, 100), TextSize = 12,
                    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 17,
                }, ab)
            end
        end

        local tab = { Page = body, _title = title, _isHome = isHome }

        -- Home: swallow extra feature sections to avoid duplicates
        function tab:CreateSection(c)
            if isHome then
                return {
                    CreateButton = function() return end,
                    CreateToggle = function() return {} end,
                    CreateSlider = function() return {} end,
                    CreateTextbox = function() return end,
                    CreateInput = function() return end,
                    CreateDropdown = function() return end,
                    CreateLabel = function() return self end,
                    CreateHeader = function() return self end,
                }
            end
            local text = type(c) == "table" and (c.Title or c.Name) or c
            local sectionLocked = type(c) == "table" and c.Locked == true
            local sectionIcon = type(c) == "table" and c.Icon or nil
            local host = sectionHost or body
            if host and host:IsA("GuiObject") then
                host.Visible = true
            end
            local section = make("Frame", {
                BackgroundColor3 = sectionLocked and Color3.fromRGB(18, 18, 24) or Color3.fromRGB(22, 22, 30),
                BackgroundTransparency = sectionLocked and 0.04 or 0,
                BorderSizePixel = 0,
                Size = UDim2.new(1, -8, 0, 48), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 16,
            }, host)
            section:SetAttribute("KhfreshLocked", sectionLocked)
            corner(section, 14)
            stroke(section, sectionLocked and Color3.fromRGB(95, 95, 110) or Color3.fromRGB(70, 70, 85), 1, sectionLocked and 0.48 or 0.35)
            gradient(section, sectionLocked and Color3.fromRGB(26, 26, 33) or Color3.fromRGB(32, 32, 42), Color3.fromRGB(16, 16, 22), 100)
            if sectionIcon then
                make("ImageLabel", {
                    BackgroundTransparency = 1,
                    Position = UDim2.fromOffset(14, 7),
                    Size = UDim2.fromOffset(24, 24),
                    Image = resolveIcon(tostring(text or "section"), sectionIcon),
                    ImageColor3 = sectionLocked and Color3.fromRGB(150, 150, 165) or Color3.fromRGB(210, 210, 225),
                    ImageTransparency = sectionLocked and 0.05 or 0,
                    ZIndex = 18,
                }, section)
            end
            make("TextLabel", {
                BackgroundTransparency = 1, Position = UDim2.fromOffset(sectionIcon and 44 or 14, 10),
                Size = UDim2.new(1, sectionLocked and -132 or (sectionIcon and -64 or -28), 0, 18),
                Font = Enum.Font.GothamBold, Text = string.upper(tostring(text or "SECTION")),
                TextColor3 = sectionLocked and Color3.fromRGB(135, 135, 150) or Color3.fromRGB(170, 170, 185),
                TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 17,
            }, section)
            if sectionLocked then
                local badge = make("Frame", {
                    BackgroundColor3 = Color3.fromRGB(48, 48, 58), BackgroundTransparency = 0.05,
                    BorderSizePixel = 0, Position = UDim2.new(1, -94, 0, 7), Size = UDim2.fromOffset(80, 24), ZIndex = 18,
                }, section)
                corner(badge, 8)
                stroke(badge, Color3.fromRGB(120, 120, 135), 1, 0.45)
                make("ImageLabel", {
                    BackgroundTransparency = 1, Position = UDim2.fromOffset(7, 4), Size = UDim2.fromOffset(16, 16),
                    Image = resolveIcon("lock", "lock"), ImageColor3 = Color3.fromRGB(175, 175, 190), ZIndex = 19,
                }, badge)
                make("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.fromOffset(27, 0), Size = UDim2.new(1, -30, 1, 0),
                    Font = Enum.Font.GothamBold, Text = "LOCKED", TextColor3 = Color3.fromRGB(165, 165, 180),
                    TextSize = 9, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 19,
                }, badge)
            end
            local holder = make("Frame", {
                BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 34),
                Size = UDim2.new(1, -20, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 17,
            }, section)
            local holderLayout = make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
            make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 12), ZIndex = 17 }, holder)
            task.defer(function()
                if bodyLayout then
                    body.CanvasSize = UDim2.new(0, 0, 0, bodyLayout.AbsoluteContentSize.Y + 30)
                end
            end)

            local sectionObj = { Holder = holder, Locked = sectionLocked }
            local function row(label)
                local r = make("Frame", {
                    BackgroundColor3 = sectionLocked and Color3.fromRGB(31, 31, 40) or Color3.fromRGB(36, 36, 46),
                    BackgroundTransparency = sectionLocked and 0.12 or 0,
                    BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 44), ZIndex = 17,
                }, holder)
                corner(r, 11)
                stroke(r, sectionLocked and Color3.fromRGB(72, 72, 84) or Color3.fromRGB(60, 60, 75), 1, 0.5)
                make("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.48, -14, 1, 0),
                    Font = Enum.Font.Gotham, Text = tostring(label or ""),
                    TextColor3 = sectionLocked and Color3.fromRGB(150, 150, 165) or Color3.fromRGB(245, 245, 250),
                    TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 18,
                }, r)
                return r
            end

            function sectionObj:CreateButton(c)
                c = c or {}
                local r = row(c.Name or c.Title)
                local b = make("TextButton", {
                    BackgroundColor3 = Color3.fromRGB(48, 48, 58), BackgroundTransparency = 0.06,
                    BorderSizePixel = 0, Position = UDim2.new(1, -104, 0.5, -15), Size = UDim2.fromOffset(94, 30),
                    Font = Enum.Font.GothamMedium, Text = c.ButtonText or "Run", TextColor3 = C.Text,
                    TextSize = 12, AutoButtonColor = false, ZIndex = 18,
                }, r)
                corner(b, 10)
                stroke(b, C.Stroke, 1, 0.28)
                hoverScale(b, 0.94)
                local actionName = tostring(c.Name or c.Title or "Button")
                markCustomFeedback(b)
                b:SetAttribute("KhfreshActionName", actionName)
                bindUIAction(b, function()
                    runUIActionCallback(c, actionName, nil, "Running: " .. actionName)
                end)
                return b
            end

            function sectionObj:CreateToggle(c)
                c = c or {}
                local r = row(c.Name or c.Title)
                local on = c.Default == true or c.CurrentValue == true or c.Value == true
                -- Solid only: ON = accent blue, OFF = solid gray (never transparent)
                local track = make("Frame", {
                    BackgroundColor3 = on and Color3.fromRGB(30, 140, 255) or Color3.fromRGB(72, 74, 86),
                    BackgroundTransparency = 0, BorderSizePixel = 0,
                    Position = UDim2.new(1, -58, 0.5, -13), Size = UDim2.fromOffset(46, 26), ZIndex = 18,
                }, r)
                corner(track, 13)
                stroke(track, on and Color3.fromRGB(100, 180, 255) or Color3.fromRGB(90, 92, 102), 1, 0)
                local knob = make("Frame", {
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0,
                    BorderSizePixel = 0, Size = UDim2.fromOffset(20, 20),
                    Position = on and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10), ZIndex = 19,
                }, track)
                corner(knob, 10)
                local actionName = tostring(c.Name or c.Title or "Toggle")
                local locked = sectionLocked
                if locked then on = false end
                r:SetAttribute("KhfreshActionName", actionName)
                local api = {}
                local ON_COL = Color3.fromRGB(30, 140, 255)
                local OFF_COL = Color3.fromRGB(72, 74, 86)
                local function paint()
                    track.BackgroundTransparency = 0
                    knob.BackgroundTransparency = 0
                    track.BackgroundColor3 = locked and Color3.fromRGB(58, 58, 68) or (on and ON_COL or OFF_COL)
                    local strokeObj = track:FindFirstChildOfClass("UIStroke")
                    if strokeObj then
                        strokeObj.Transparency = 0
                        strokeObj.Color = on and Color3.fromRGB(100, 180, 255) or Color3.fromRGB(90, 92, 102)
                    end
                    TweenService:Create(knob, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
                        Position = on and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10),
                    }):Play()
                end
                paint() -- force correct color immediately
                function api:Set(v)
                    if locked then
                        on = false
                        paint()
                        return
                    end
                    on = v and true or false
                    paint()
                    runUIActionCallback(c, actionName, on, actionName .. " → " .. (on and "ON" or "OFF"))
                end
                function api:Get()
                    return on
                end
                local controlKey = actionName
                local n = 1
                while Library._ConfigControls[controlKey] do
                    n = n + 1
                    controlKey = actionName .. "#" .. tostring(n)
                end
                Library._ConfigControls[controlKey] = { Kind = "toggle", Control = api, Config = c }
                local hit = make("TextButton", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Text = "", ZIndex = 20 }, track)
                markCustomFeedback(hit)
                hit:SetAttribute("KhfreshActionName", actionName)
                hit.MouseButton1Click:Connect(function()
                    if locked then
                        notifyUIAction(actionName, "Locked: temporarily unavailable")
                        return
                    end
                    on = not on
                    paint()
                    runUIActionCallback(c, actionName, on, actionName .. " → " .. (on and "ON" or "OFF"))
                end)
                return api
            end

            function sectionObj:CreateSlider(c)
                c = c or {}
                local r = make("Frame", {
                    BackgroundColor3 = C.Row, BackgroundTransparency = 0.15, BorderSizePixel = 0,
                    Size = UDim2.new(1, 0, 0, 56), ZIndex = 17,
                }, holder)
                corner(r, 11)
                local minV = (c.Range and c.Range[1]) or c.Min or 0
                local maxV = (c.Range and c.Range[2]) or c.Max or 100
                local val = tonumber(c.Default or c.CurrentValue or c.Value or minV) or minV
                local accent = c.Color or C.Accent
                make("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(0.7, 0, 0, 16),
                    Font = Enum.Font.Gotham, Text = tostring(c.Name or c.Title or "Slider"),
                    TextColor3 = C.Text, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 18,
                }, r)
                local valLbl = make("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.new(1, -60, 0, 8), Size = UDim2.fromOffset(48, 16),
                    Font = Enum.Font.GothamBold, Text = tostring(val), TextColor3 = C.Muted, TextSize = 12,
                    TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 18,
                }, r)
                local bar = make("Frame", {
                    BackgroundColor3 = Color3.fromRGB(40, 40, 50), BorderSizePixel = 0,
                    Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -28, 0, 12), ZIndex = 18,
                }, r)
                corner(bar, 6)
                local fill = make("Frame", {
                    BackgroundColor3 = accent, BorderSizePixel = 0,
                    Size = UDim2.new(clamp((val - minV) / math.max(maxV - minV, 1), 0, 1), 0, 1, 0), ZIndex = 19,
                }, bar)
                corner(fill, 6)
                make("UIGradient", {
                    Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, Color3.new(math.min(accent.R * 1.4, 1), math.min(accent.G * 1.4, 1), math.min(accent.B * 1.4, 1))),
                        ColorSequenceKeypoint.new(0.5, accent),
                        ColorSequenceKeypoint.new(1, Color3.new(accent.R * 0.45, accent.G * 0.45, accent.B * 0.45)),
                    }),
                    Rotation = 0,
                }, fill)
                local dragging = false
                local function setFromX(x)
                    local rel = clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
                    val = minV + rel * (maxV - minV)
                    if c.Increment then val = math.floor(val / c.Increment + 0.5) * c.Increment end
                    val = clamp(val, minV, maxV)
                    fill.Size = UDim2.new((val - minV) / math.max(maxV - minV, 1), 0, 1, 0)
                    valLbl.Text = tostring(math.floor(val * 100 + 0.5) / 100)
                    -- Callback runs continuously while dragging, but the user gets
                    -- a throttled visible notification at drag start/end.
                    local cb = type(c.Callback) == "function" and c.Callback or nil
                    if cb then pcall(cb, val) end
                end
                local sliderActionName = tostring(c.Name or c.Title or "Slider")
                bar.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        dragging = true
                        notifyUIAction(sliderActionName, "Adjusting: " .. sliderActionName)
                        setFromX(input.Position.X)
                    end
                end)
                UserInputService.InputEnded:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        if dragging then
                            notifyUIAction(sliderActionName, sliderActionName .. " → " .. tostring(math.floor(val * 100 + 0.5) / 100))
                        end
                        dragging = false
                    end
                end)
                UserInputService.InputChanged:Connect(function(input)
                    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                        setFromX(input.Position.X)
                    end
                end)
                local api = {
                    Set = function(_, v)
                        val = clamp(tonumber(v) or val, minV, maxV)
                        fill.Size = UDim2.new((val - minV) / math.max(maxV - minV, 1), 0, 1, 0)
                        valLbl.Text = tostring(val)
                        runUIActionCallback(c, sliderActionName, val, sliderActionName .. " → " .. tostring(val))
                    end,
                    Get = function()
                        return val
                    end,
                }
                Library._ConfigControls[sliderActionName] = { Kind = "slider", Control = api, Config = c }
                return api
            end

            function sectionObj:CreateTextbox(c)
                c = c or {}
                local r = row(c.Name or c.Title)
                local box = make("TextBox", {
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.88, BorderSizePixel = 0,
                    Position = UDim2.new(0.48, 0, 0.5, -15), Size = UDim2.new(0.52, -12, 0, 30),
                    Font = Enum.Font.Code, TextSize = 12, TextColor3 = C.Text, PlaceholderColor3 = C.Muted,
                    PlaceholderText = c.Placeholder or c.PlaceholderText or "",
                    Text = tostring(c.Default or c.CurrentValue or c.Value or ""), ClearTextOnFocus = false, ZIndex = 18,
                }, r)
                corner(box, 10)
                stroke(box, Color3.fromRGB(255, 255, 255), 1, 0.7)
                corner(box, 9)
                stroke(box, C.Stroke, 1, 0.35)
                local actionName = tostring(c.Name or c.Title or "Input")
                markCustomFeedback(box)
                box:SetAttribute("KhfreshActionName", actionName)
                box.Focused:Connect(function()
                    notifyUIAction(actionName, "Editing: " .. actionName)
                end)
                local function fireText()
                    runUIActionCallback(c, actionName, box.Text, "Submitted: " .. actionName)
                end
                box.FocusLost:Connect(fireText)
                box:GetPropertyChangedSignal("Text"):Connect(function()
                    -- live update for amount fields (mobile may not FocusLost cleanly)
                    if type(c.Callback) == "function" then
                        pcall(c.Callback, box.Text)
                    end
                end)
                Library._ConfigControls[actionName] = { Kind = "textbox", Control = box, Config = c }
                return box
            end
            sectionObj.CreateInput = sectionObj.CreateTextbox

            function sectionObj:CreateDropdown(c)
                c = c or {}
                local r = row(c.Name or c.Title)
                local opts = c.Options or c.Values or {}
                if type(opts) ~= "table" then opts = {} end
                local labels = {}
                for _, item in ipairs(opts) do
                    local text = type(item) == "table" and (item.Title or item.Name or item.Value or item.Text or item[1]) or item
                    labels[#labels + 1] = tostring(text or "")
                end
                local isMulti = c.Multi == true or c.MultiDropdown == true or c.AllowMulti == true
                local selectedSet = {}
                local selectedList = {}
                local function setFromDefault()
                    selectedSet = {}
                    selectedList = {}
                    local def = c.Default or c.CurrentOption or c.CurrentValue
                    if isMulti then
                        if type(def) == "table" then
                            for _, v in ipairs(def) do
                                local s = tostring(v)
                                if s ~= "" and not selectedSet[s] then
                                    selectedSet[s] = true
                                    selectedList[#selectedList + 1] = s
                                end
                            end
                        elseif def ~= nil and tostring(def) ~= "" then
                            local s = tostring(def)
                            selectedSet[s] = true
                            selectedList[1] = s
                        end
                    else
                        if type(def) == "table" then def = def[1] end
                        if def ~= nil then
                            local s = tostring(def)
                            selectedSet[s] = true
                            selectedList[1] = s
                        end
                    end
                end
                setFromDefault()
                local function labelText()
                    if #selectedList == 0 then return "Select..." end
                    if isMulti then
                        if #selectedList <= 4 then return table.concat(selectedList, ", ") end
                        return tostring(#selectedList) .. " selected"
                    end
                    return selectedList[1] or "Select..."
                end
                local actionName = tostring(c.Name or c.Title or "Dropdown")
                local locked = sectionLocked
                if locked then
                    selectedSet = {}
                    selectedList = {}
                end
                local b = make("TextButton", {
                    BackgroundColor3 = locked and Color3.fromRGB(45, 45, 54) or C.PanelDeep, BackgroundTransparency = locked and 0.15 or 0.04, BorderSizePixel = 0,
                    Position = UDim2.new(0.48, 0, 0.5, -15), Size = UDim2.new(0.52, -12, 0, 30),
                    Font = Enum.Font.Gotham, TextColor3 = C.Text, TextSize = 12, Text = labelText(),
                    AutoButtonColor = false, ZIndex = 18, TextTruncate = Enum.TextTruncate.AtEnd,
                }, r)
                markCustomFeedback(b)
                b:SetAttribute("KhfreshActionName", actionName)
                corner(b, 9)
                stroke(b, C.Stroke, 1, 0.35)

                local nOpts = math.max(#labels, 1)
                local maxH = math.min(220, nOpts * 32 + 40)
                local menu = make("Frame", {
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.1,
                    BorderSizePixel = 0, Size = UDim2.fromOffset(240, maxH), Visible = false, ZIndex = 120,
                    ClipsDescendants = true,
                }, dropdownLayer)
                corner(menu, 14)
                stroke(menu, Color3.fromRGB(255, 255, 255), 1, 0.85)
                do
                    local menuTint = make("Frame", {
                        BackgroundColor3 = Color3.fromRGB(20, 22, 30), BackgroundTransparency = 0.28,
                        Size = UDim2.fromScale(1, 1), ZIndex = 120, BorderSizePixel = 0,
                    }, menu)
                    corner(menuTint, 14)
                end

                -- Scrollable list (scrollbar)
                local scroll = make("ScrollingFrame", {
                    BackgroundTransparency = 1, BorderSizePixel = 0,
                    Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, isMulti and -36 or -8),
                    CanvasSize = UDim2.new(0, 0, 0, nOpts * 32),
                    ScrollBarThickness = 6, ScrollBarImageColor3 = Color3.fromRGB(140, 140, 160),
                    ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 121,
                    ElasticBehavior = Enum.ElasticBehavior.Never,
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                }, menu)
                local list = make("UIListLayout", {
                    Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder,
                }, scroll)
                list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                    scroll.CanvasSize = UDim2.new(0, 0, 0, list.AbsoluteContentSize.Y + 8)
                end)

                local itemButtons = {}
                local function fireCallback()
                    local payload = isMulti and selectedList or selectedList[1]
                    runUIActionCallback(c, actionName, payload, actionName .. " → " .. labelText())
                end
                local function refreshItemStyles()
                    for _, ib in ipairs(itemButtons) do
                        local on = selectedSet[ib.Text] == true
                        ib.TextColor3 = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 210)
                        ib.Font = on and Enum.Font.GothamBold or Enum.Font.Gotham
                        ib.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                        ib.BackgroundTransparency = on and 0.75 or 0.92
                    end
                    b.Text = labelText()
                end

                for _, text in ipairs(labels) do
                    local ib = make("TextButton", {
                        BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.9,
                        Size = UDim2.new(1, -4, 0, 30), Font = Enum.Font.Gotham,
                        Text = text, TextColor3 = Color3.fromRGB(235, 235, 245), TextSize = 12, AutoButtonColor = false, ZIndex = 122,
                    }, scroll)
                    corner(ib, 8)
                    itemButtons[#itemButtons + 1] = ib
                    ib.MouseButton1Click:Connect(function()
                        if locked then
                            notifyUIAction(actionName, "Locked: temporarily unavailable")
                            return
                        end
                        if isMulti then
                            if selectedSet[text] then
                                selectedSet[text] = nil
                                local nextList = {}
                                for _, v in ipairs(selectedList) do
                                    if v ~= text then nextList[#nextList + 1] = v end
                                end
                                selectedList = nextList
                            else
                                selectedSet[text] = true
                                selectedList[#selectedList + 1] = text
                            end
                            refreshItemStyles()
                            fireCallback()
                            -- keep menu open for multi
                        else
                            selectedSet = {[text] = true}
                            selectedList = {text}
                            refreshItemStyles()
                            menu.Visible = false
                            fireCallback()
                        end
                    end)
                end
                refreshItemStyles()

                if isMulti then
                    local done = make("TextButton", {
                        BackgroundColor3 = Color3.fromRGB(40, 120, 90), BackgroundTransparency = 0.15,
                        BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1),
                        Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.new(1, -12, 0, 28),
                        Font = Enum.Font.GothamBold, Text = "Done", TextColor3 = Color3.new(1,1,1),
                        TextSize = 12, AutoButtonColor = false, ZIndex = 123,
                    }, menu)
                    corner(done, 8)
                    markCustomFeedback(done)
                    done:SetAttribute("KhfreshActionName", actionName .. " Done")
                    bindUIAction(done, function()
                        menu.Visible = false
                        notifyUIAction(actionName .. " Done", "Confirmed: " .. labelText())
                        fireCallback()
                    end)
                end

                table.insert(openDropdowns, menu)
                bindUIAction(b, function()
                    if locked then
                        notifyUIAction(actionName, "Locked: temporarily unavailable")
                        return
                    end
                    local was = menu.Visible
                    notifyUIAction(actionName, was and ("Closed: " .. actionName) or ("Opened: " .. actionName))
                    closeAllDropdowns()
                    if not was then
                        menu.Visible = true
                        local abs = b.AbsolutePosition
                        local sz = b.AbsoluteSize
                        local h = maxH
                        local vx = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1920, 1080)
                        -- Prefer open UPWARD so it does not cover the toggle below / bar
                        local y = abs.Y - h - 6
                        if y < 8 then
                            y = abs.Y + sz.Y + 4
                        end
                        local x = abs.X
                        if x + math.max(sz.X, 220) > vx.X - 8 then
                            x = vx.X - math.max(sz.X, 220) - 8
                        end
                        menu.Position = UDim2.fromOffset(x, y)
                        menu.Size = UDim2.fromOffset(math.max(sz.X, 220), h)
                    end
                end)

                -- click outside closes (next frame)
                local function rebuildOptions(newOpts, keepSelection)
                    for _, ib in ipairs(itemButtons) do
                        pcall(function() ib:Destroy() end)
                    end
                    itemButtons = {}
                    labels = {}
                    if type(newOpts) ~= "table" then newOpts = {} end
                    for _, item in ipairs(newOpts) do
                        local text = type(item) == "table" and (item.Title or item.Name or item.Value or item.Text or item[1]) or item
                        labels[#labels + 1] = tostring(text or "")
                    end
                    if not keepSelection then
                        selectedSet = {}
                        selectedList = {}
                    end
                    nOpts = #labels
                    local maxH2 = math.min(280, 8 + nOpts * 32 + (isMulti and 36 or 0))
                    scroll.CanvasSize = UDim2.new(0, 0, 0, nOpts * 32)
                    menu.Size = UDim2.fromOffset(math.max(menu.AbsoluteSize.X, 220), maxH2)
                    for _, text in ipairs(labels) do
                        local ib = make("TextButton", {
                            BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.92,
                            Size = UDim2.new(1, -4, 0, 30), Font = Enum.Font.Gotham,
                            Text = text, TextColor3 = Color3.fromRGB(200, 200, 210), TextSize = 12,
                            AutoButtonColor = false, ZIndex = 122,
                        }, scroll)
                        corner(ib, 8)
                        itemButtons[#itemButtons + 1] = ib
                        ib.MouseButton1Click:Connect(function()
                            if locked then
                                notifyUIAction(actionName, "Locked: temporarily unavailable")
                                return
                            end
                            if isMulti then
                                if selectedSet[text] then
                                    selectedSet[text] = nil
                                    for i = #selectedList, 1, -1 do
                                        if selectedList[i] == text then table.remove(selectedList, i) end
                                    end
                                else
                                    selectedSet[text] = true
                                    selectedList[#selectedList + 1] = text
                                end
                            else
                                selectedSet = {[text] = true}
                                selectedList = {text}
                                menu.Visible = false
                                fireCallback()
                            end
                            if isMulti then
                                refreshItemStyles()
                                fireCallback()
                            else
                                refreshItemStyles()
                            end
                        end)
                    end
                    refreshItemStyles()
                end

                local api = {
                    Set = function(_, values)
                        if locked then
                            selectedSet = {}
                            selectedList = {}
                            refreshItemStyles()
                            menu.Visible = false
                            return
                        end
                        selectedSet = {}
                        selectedList = {}
                        if isMulti then
                            for _, v in ipairs(type(values) == "table" and values or {values}) do
                                local s = tostring(v)
                                selectedSet[s] = true
                                selectedList[#selectedList + 1] = s
                            end
                        else
                            local s = tostring(type(values) == "table" and values[1] or values)
                            selectedSet[s] = true
                            selectedList[1] = s
                        end
                        refreshItemStyles()
                        fireCallback()
                        if not Library._ApplyingConfig then
                            notifyUIAction(actionName, "Set: " .. labelText())
                        end
                    end,
                    Get = function()
                        if isMulti then
                            return selectedList
                        end
                        return selectedList[1]
                    end,
                    Refresh = function(_, newOpts, clearSelection)
                        rebuildOptions(newOpts, clearSelection ~= true)
                    end,
                    SetValues = function(_, newOpts)
                        rebuildOptions(newOpts, false)
                    end,
                    Row = r,
                    SetVisible = function(_, vis)
                        local show = vis and true or false
                        pcall(function() r.Visible = show end)
                        if not show then
                            pcall(function() menu.Visible = false end)
                        end
                    end,
                }
                Library._ConfigControls[actionName] = { Kind = isMulti and "multidropdown" or "dropdown", Control = api, Config = c }
                return api
            end

            function sectionObj:CreateLabel(c)
                c = c or {}
                make("TextLabel", {
                    BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), Font = Enum.Font.Gotham,
                    Text = tostring(c.Name or c.Title or c.Text or ""), TextColor3 = C.Muted, TextSize = 12,
                    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 18,
                }, holder)
                return sectionObj
            end
            function sectionObj:CreateHeader() return self end
            return sectionObj
        end

        function tab:CreateHeader(c)
            if isHome then return self end
            return self:CreateSection({ Title = (c and c.Title) or "Header" })
        end
        function tab:CreateButton(c)
            if isHome then return end
            return self:CreateSection({ Title = "Actions" }):CreateButton(c)
        end
        function tab:CreateToggle(c)
            if isHome then return {} end
            return self:CreateSection({ Title = "Settings" }):CreateToggle(c)
        end
        function tab:CreateDropdown(c)
            if isHome then return end
            return self:CreateSection({ Title = "Selection" }):CreateDropdown(c)
        end
        function tab:CreateTextbox(c)
            if isHome then return end
            return self:CreateSection({ Title = "Input" }):CreateTextbox(c)
        end
        function tab:CreateInput(c) return self:CreateTextbox(c) end
        function tab:CreateSlider(c)
            if isHome then return {} end
            return self:CreateSection({ Title = "Slider" }):CreateSlider(c)
        end
        function tab:CreateLabel(c)
            if isHome then return self end
            return self:CreateSection({ Title = "Info" }):CreateLabel(c)
        end

        return tab
    end

    function WindowApi:Toggle()
        if SiriusChar.BarCollapsed then
            SiriusChar.BarCollapsed = false
            collapseBtn.Parent = ScreenGui
            applyBarLayout()
        else
            toggleBarCollapse()
        end
    end
    function WindowApi:Destroy() ScreenGui:Destroy() end
    function WindowApi:SelectTab() end

    SiriusChar.BarCollapsed = false
    applyBarLayout()
    smartBar.Visible = true
    smartBar.BackgroundTransparency = 0.05
    task.defer(function()
        refreshResponsiveGrids(ScreenGui)
        if centerHub and centerHub.Parent then refreshResponsiveGrids(centerHub) end
    end)

    -- Reflow panels on viewport resize (ratio-based, no device checks)
    local function reflowUI()
        if not SiriusChar.BarCollapsed then
            applyBarLayout()
        end
        if centerHub and centerHub.Parent and not centerHub:GetAttribute("UserDragged") then
            pcall(sizeCenterHub)
        end
        pcall(updateCollapseIcon)
        refreshResponsiveGrids(ScreenGui)
        if centerHub and centerHub.Parent then refreshResponsiveGrids(centerHub) end
        for name, data in pairs(panels) do
            local p = data.panel
            if p then
                local kind = data.isHome and "home" or (name == "Settings" and "settings" or "tab")
                local w, h = fitPanelSize(kind)
                p.Size = UDim2.fromOffset(w, h)
                if openName == name and p.Visible and not SiriusChar.BarCollapsed then
                    p.Position = panelOpenPos(p, data.isHome)
                elseif openName == name and p.Visible and SiriusChar.BarCollapsed then
                    -- keep panel on-screen even if bar hidden
                    local vs = getVP()
                    local x = clamp((vs.X - w) / 2, 8, math.max(8, vs.X - w - 8))
                    local y = clamp((vs.Y - h) / 2, 8, math.max(8, vs.Y - h - 8))
                    p.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
                end
            end
        end
    end
    pcall(function()
        local cam = workspace.CurrentCamera
        if cam then
            cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                task.defer(reflowUI)
            end)
        end
        workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
            task.defer(reflowUI)
        end)
    end)

    updateCollapseIcon()

    -- ===== STARTUP UI MODE PICKER =====
    smartBar.Visible = false
    collapseBtn.Visible = false
    if centerHub then centerHub.Visible = false end
    if centerToggle then centerToggle.Visible = false end

    local pickerGui = make("Frame", {
        Name = "UIModePicker", BackgroundColor3 = Color3.fromRGB(8, 8, 12),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1), ZIndex = 200, Visible = true,
    }, ScreenGui)
    local dim = make("Frame", {
        BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), ZIndex = 200,
    }, pickerGui)
    local card = make("Frame", {
        BackgroundColor3 = Color3.fromRGB(22, 24, 32), BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.55, 0),
        Size = UDim2.fromOffset(420, 230), ZIndex = 201, BorderSizePixel = 0,
    }, pickerGui)
    corner(card, 20)
    stroke(card, Color3.fromRGB(255, 255, 255), 1, 0.9)
    gradient(card, Color3.fromRGB(36, 38, 52), Color3.fromRGB(14, 14, 20), 120)

    local title = make("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 20),
        Size = UDim2.new(1, 0, 0, 28), Font = Enum.Font.GothamBold,
        Text = "Choose UI Mode", TextSize = 20, TextColor3 = Color3.fromRGB(245, 245, 255),
        ZIndex = 202, TextTransparency = 1,
    }, card)
    local sub = make("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 52),
        Size = UDim2.new(1, -40, 0, 36), Font = Enum.Font.Gotham,
        Text = "Pick how Khfresh Hub looks. You can change this later in Settings → Layout.",
        TextSize = 12, TextColor3 = Color3.fromRGB(170, 175, 190), TextWrapped = true,
        ZIndex = 202, TextTransparency = 1,
    }, card)

    local modes = {
        { id = "TaskBar", label = "TaskBar", desc = "Sirius smartBar · 4 corners" },
        { id = "Minimalist", label = "Minimalist", desc = "Liquid glass hub · independent UI" },
    }
    local btns = {}
    for i, mdef in ipairs(modes) do
        local b = make("TextButton", {
            BackgroundColor3 = Color3.fromRGB(40, 44, 58), BackgroundTransparency = 1,
            BorderSizePixel = 0, Position = UDim2.new(0.5, -170, 0, 100 + (i - 1) * 52),
            Size = UDim2.fromOffset(340, 46), Font = Enum.Font.GothamBold,
            Text = "", AutoButtonColor = false, ZIndex = 203,
        }, card)
        corner(b, 12)
        stroke(b, Color3.fromRGB(255, 255, 255), 1, 0.88)
        gradient(b, Color3.fromRGB(55, 58, 78), Color3.fromRGB(22, 24, 34), 90)
        local lbl = make("TextLabel", {
            BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 4),
            Size = UDim2.new(1, -24, 0, 22), Font = Enum.Font.GothamBold,
            Text = mdef.label, TextSize = 15, TextColor3 = Color3.fromRGB(255, 255, 255),
            TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 204, TextTransparency = 1,
        }, b)
        local dsc = make("TextLabel", {
            BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 24),
            Size = UDim2.new(1, -24, 0, 16), Font = Enum.Font.Gotham,
            Text = mdef.desc, TextSize = 11, TextColor3 = Color3.fromRGB(160, 165, 180),
            TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 204, TextTransparency = 1,
        }, b)
        btns[#btns + 1] = { btn = b, lbl = lbl, dsc = dsc, id = mdef.id }
        markCustomFeedback(b)
        b:SetAttribute("KhfreshActionName", "UI Mode: " .. mdef.id)
        b.MouseButton1Click:Connect(function()
            notifyUIAction("UI Mode: " .. mdef.id, "Selecting: " .. mdef.id)
            SiriusChar.UIMode = mdef.id
            if mdef.id == "Minimalist" then
                SiriusChar.BarPosition = "Center"
            else
                if SiriusChar.BarPosition == "Center" then
                    SiriusChar.BarPosition = "Bottom"
                end
            end
            -- fade out picker
            local TI = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
            TweenService:Create(dim, TI, { BackgroundTransparency = 1 }):Play()
            TweenService:Create(card, TI, { BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0.45, 0) }):Play()
            for _, x in ipairs(btns) do
                TweenService:Create(x.btn, TI, { BackgroundTransparency = 1 }):Play()
                TweenService:Create(x.lbl, TI, { TextTransparency = 1 }):Play()
                TweenService:Create(x.dsc, TI, { TextTransparency = 1 }):Play()
            end
            TweenService:Create(title, TI, { TextTransparency = 1 }):Play()
            TweenService:Create(sub, TI, { TextTransparency = 1 }):Play()
            task.delay(0.38, function()
                pickerGui:Destroy()
                pcall(applyUIMode)
                Library:Notify({ Title = "UI Mode", Message = mdef.id, Duration = 2 })
            end)
        end)
    end

    -- smooth entrance
    task.defer(function()
        local TI = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        TweenService:Create(dim, TI, { BackgroundTransparency = 0.45 }):Play()
        TweenService:Create(card, TI, { BackgroundTransparency = 0.08, Position = UDim2.new(0.5, 0, 0.5, 0) }):Play()
        TweenService:Create(title, TI, { TextTransparency = 0 }):Play()
        TweenService:Create(sub, TI, { TextTransparency = 0 }):Play()
        for i, x in ipairs(btns) do
            task.delay(0.06 * i, function()
                TweenService:Create(x.btn, TI, { BackgroundTransparency = 0.12 }):Play()
                TweenService:Create(x.lbl, TI, { TextTransparency = 0 }):Play()
                TweenService:Create(x.dsc, TI, { TextTransparency = 0 }):Play()
            end)
        end
    end)

    return WindowApi
end

function Library:CreateWindow(config)
    return buildWindow(config)
end

return Library

]====]

local __uiChunk, __uiErr = loadstring(__SIRIUS_UI_SOURCE, "@KhfreshUI_SiriusBase")
if not __uiChunk then error("Khfresh Sirius UI compile failed: " .. tostring(__uiErr)) end
local KhfreshLib = __uiChunk()
if type(KhfreshLib) ~= "table" then error("Khfresh Sirius UI did not return a library table") end
__SIRIUS_UI_SOURCE = nil
__uiChunk = nil




-- Shared palette requested by the hub: #d6e8ee, no purple.
pcall(function()
    KhfreshLib:SetTheme({
        Background = Color3.fromRGB(14,15,18),
        Surface = Color3.fromRGB(22,23,27),
        Surface2 = Color3.fromRGB(29,30,35),
        Surface3 = Color3.fromRGB(39,40,46),
        Stroke = Color3.fromRGB(92,102,108),
        Text = Color3.fromRGB(242,243,246),
        Muted = Color3.fromRGB(151,154,164),
        Accent = Color3.fromRGB(26,148,255),
        AccentDark = Color3.fromRGB(155,181,190),
        Icon = Color3.fromRGB(214,232,238),
    })
end)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local function getInitialUISize()
    local cam = workspace.CurrentCamera
    local vs = cam and cam.ViewportSize or Vector2.new(1440, 900)
    local scale = math.clamp(math.min(vs.X / 1440, vs.Y / 900), 0.78, 1.05)
    local w = math.clamp(math.floor(760 * scale), 520, 840)
    local h = math.clamp(math.floor(540 * scale), 360, 600)
    return w, h
end
local initialW, initialH = getInitialUISize()

-- ===== EARLY BENTO WINDOW =====
local Window
-- ===== PRE-UI CLEANUP (before CreateWindow) =====
pcall(function()
    local env = (type(getgenv) == "function" and getgenv()) or _G
    if type(env.KhfreshLib) == "table" then
        pcall(function() if env.KhfreshLib.SetFlight then env.KhfreshLib.SetFlight(false) end end)
        pcall(function() if env.KhfreshLib.SetNoclip then env.KhfreshLib.SetNoclip(false) end end)
    end
    if type(env.KhfreshSiriusChar) == "table" then
        env.KhfreshSiriusChar.Flight = false
        env.KhfreshSiriusChar.Noclip = false
    end
    local lp = game:GetService("Players").LocalPlayer
    local char = lp and lp.Character
    if char then
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BodyVelocity") or d:IsA("BodyGyro") or d:IsA("BodyPosition") or d:IsA("BodyAngularVelocity") then
                pcall(function() d:Destroy() end)
            end
        end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = false end
    end
    local guiParent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
    for _, name in ipairs({"KhfreshSiriusShell", "KhfreshNotify"}) do
        local old = guiParent:FindFirstChild(name)
        if old then pcall(function() old:Destroy() end) end
    end
end)

local okWindow, windowOrErr = pcall(function()
    return KhfreshLib:CreateWindow({
        Name = "KhfreshUI",
        Title = "Khfresh Hub",
        Subtitle = "by Ngmankhoi x Khfresh",
        Theme = "Bento",
        Size = UDim2.fromOffset(initialW, initialH),
        PerformanceProfile = "Auto",
        Keybind = Enum.KeyCode.RightAlt,
        ScrollBarEnabled = true,
    })
end)
if okWindow and type(windowOrErr) == "table" then
    Window = windowOrErr
else
    warn("[Khfresh] CreateWindow failed: " .. tostring(windowOrErr))
    local ok2, win2 = pcall(function() return KhfreshLib:CreateWindow({ Name = "Khfresh Hub" }) end)
    if ok2 and type(win2) == "table" then
        Window = win2
    else
        error("Khfresh CreateWindow failed: " .. tostring(windowOrErr) .. " | " .. tostring(win2))
    end
end

-- Compatibility notify wrapper for the existing feature source.
local __nativeNotify = KhfreshLib.Notify
KhfreshLib.Notify = function(selfOrConfig, maybeConfig)
    local config = maybeConfig or selfOrConfig or {}
    if type(config) ~= "table" then config = {Content=tostring(config)} end
    if config.Content == nil and config.Message ~= nil then config.Content = config.Message end
    return pcall(function() return __nativeNotify(KhfreshLib, config) end)
end

-- ===== SESSION EPOCH =====
runtimeEnv.KhfreshEpoch = (runtimeEnv.KhfreshEpoch or 0) + 1
local MY_EPOCH = runtimeEnv.KhfreshEpoch
local function alive() return runtimeEnv.KhfreshEpoch == MY_EPOCH end

-- ===== SERVICES =====
local Services = {
    Players = game:GetService("Players"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    RunService = game:GetService("RunService"),
    VirtualUser = game:GetService("VirtualUser"),
    UserInputService = game:GetService("UserInputService"),
    Lighting = game:GetService("Lighting"),
    TweenService = game:GetService("TweenService"),
    Workspace = game:GetService("Workspace"),
    Camera = game:GetService("Workspace").CurrentCamera,
    HttpService = game:GetService("HttpService"),
    GuiService = game:GetService("GuiService"),
    TeleportService = game:GetService("TeleportService"),
    RbxAnalyticsService = game:GetService("RbxAnalyticsService"),
}
local Players = Services.Players
local ReplicatedStorage = Services.ReplicatedStorage
local RunService = Services.RunService
local VirtualUser = Services.VirtualUser
local UserInputService = Services.UserInputService
local Lighting = Services.Lighting
local TweenService = Services.TweenService
local Workspace = Services.Workspace
local Camera = Services.Camera

local LocalPlayer = Players.LocalPlayer

-- ===== HARD RESET previous script instance (fly / farm / movers) =====
local function khHardResetPreviousSession()
    local env = (type(getgenv) == "function" and getgenv()) or _G
    pcall(function()
        print("[Khfresh] FULL SESSION RESET (re-execute) — kill old loops/state")

        -- Epoch already bumped; kill any leftover named threads/connections from prior run
        local killConn = {
            "AntiAFKConnection", "AntiAFKThread",
            "_khAnchorRender", "_khAnchorHeart", "_khQTERender", "_khQTEHeart", "_khLagShield",
            "KhfreshNamelessFallSpeed", "KhfreshRhyStart", "KhfreshRhyStop", "KhfreshRhyLoop",
            "KhfreshBossFightThread", "KhfreshFrameThread", "KhfreshFrameConnection",
            "__KhfreshFlyConn", "__KhfreshNoclipConn",
        }
        for _, key in ipairs(killConn) do
            local v = env[key]
            if v then
                pcall(function()
                    if typeof(v) == "RBXScriptConnection" then v:Disconnect()
                    elseif type(v) == "thread" then task.cancel(v) end
                end)
                env[key] = nil
            end
        end

        -- Stop Sirius character systems from previous run
        if type(env.KhfreshLib) == "table" then
            if type(env.KhfreshLib.SetFlight) == "function" then env.KhfreshLib.SetFlight(false) end
            if type(env.KhfreshLib.SetNoclip) == "function" then env.KhfreshLib.SetNoclip(false) end
            if type(env.KhfreshLib.SetVisibility) == "function" then env.KhfreshLib.SetVisibility(false) end
            if type(env.KhfreshLib.SiriusChar) == "table" then
                env.KhfreshLib.SiriusChar.Flight = false
                env.KhfreshLib.SiriusChar.Noclip = false
                env.KhfreshLib.SiriusChar.Visibility = false
            end
        end
        if type(env.KhfreshSiriusChar) == "table" then
            env.KhfreshSiriusChar.Flight = false
            env.KhfreshSiriusChar.Noclip = false
            env.KhfreshSiriusChar.Visibility = false
        end

        -- Clear ALL previous hub state (tele CF, quest, farm, threads) — stand still, no TP back
        local st = env.KhfreshState or env.__KhfreshState
        if type(st) == "table" then
            st.flying = false
            st.autoDoRunning = false
            st.autoClaimRunning = false
            st.ticketDailyDone = false
            st.ticketQuestActive = false
            st.ticketQuestClaimed = false
            st.ticketFarmCFrame = nil
            st.ticketLastFire = 0
            st.ticketLastTurnIn = 0
            st.ticketFailCount = 0
            st._ticketFishingApplied = false
            st.isDoingUseBaitQuest = false
            st.savedRoutineFlags = nil
            st.lastPosition = nil
            st.SmartWeather = st.SmartWeather or {}
            st.SmartWeather.enabled = false
            st.SmartWeather.activeOverride = false
            st.SmartWeather.savedCFrame = nil
            if st.bg then pcall(function() st.bg:Destroy() end); st.bg = nil end
            if st.bv then pcall(function() st.bv:Destroy() end); st.bv = nil end
            if st.flyRenderConnection then
                pcall(function() st.flyRenderConnection:Disconnect() end)
                st.flyRenderConnection = nil
            end
            -- Cancel quest/farm threads if still referenced
            for _, key in ipairs({ "autoDoThread", "autoClaimThread", "autoRecommendThread", "autoRebirthThread", "autoCraftThread", "autoGachaThread", "autoFishForMaterialsThread", "autoCraftRodThread" }) do
                local th = st[key]
                if th then
                    pcall(function() task.cancel(th) end)
                    st[key] = nil
                end
            end
            if type(st.Fishing) == "table" then
                if type(st.Fishing.Flags) == "table" then
                    for k, v in pairs(st.Fishing.Flags) do
                        if type(v) == "boolean" then st.Fishing.Flags[k] = false end
                    end
                end
                if type(st.Fishing.BossFarm) == "table" then
                    st.Fishing.BossFarm.CurrentTarget = nil
                    st.Fishing.BossFarm.CurrentToken = nil
                    st.Fishing.BossFarm.HasHooked = false
                    st.Fishing.BossFarm.PendingCancel = false
                end
            end
            if type(st.AutoFarm) == "table" then
                st.AutoFarm.enabled = false
                st.AutoFarm.inYourPosition = false
                st.AutoFarm.inYourPositionCFrame = nil
                st.AutoFarm.inYourPositionStartedFarm = false
                st.AutoFarm.teleported = false
                st.AutoFarm.oldPosition = nil
                -- keep selectedIsland name only
            end
            -- Shop tele state — clear without TP back
            for _, key in ipairs({ "Reroll", "buyRod", "learnSkill", "upgradeSkill", "exchange", "upgradeCharacter" }) do
                local block = st[key]
                if type(block) == "table" then
                    block.teleported = false
                    block.oldPosition = nil
                    block.running = false
                    if block.thread then
                        pcall(function() task.cancel(block.thread) end)
                        block.thread = nil
                    end
                end
            end
        end

        -- Strip leftover BodyMovers / force on character (NO teleport)
        local char = LocalPlayer.Character
        if char then
            for _, d in ipairs(char:GetDescendants()) do
                if d:IsA("BodyVelocity") or d:IsA("BodyGyro") or d:IsA("BodyPosition")
                    or d:IsA("BodyAngularVelocity") or d:IsA("LinearVelocity") or d:IsA("AngularVelocity") then
                    pcall(function() d:Destroy() end)
                end
            end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.PlatformStand = false
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
            end
            local root = char:FindFirstChild("HumanoidRootPart")
            if root then
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
        end

        if type(env.MiscFlags) == "table" then
            for k, v in pairs(env.MiscFlags) do
                if type(v) == "boolean" then env.MiscFlags[k] = false end
            end
        end
        if type(env.Fishing) == "table" and type(env.Fishing.Flags) == "table" then
            for k, v in pairs(env.Fishing.Flags) do
                if type(v) == "boolean" then env.Fishing.Flags[k] = false end
            end
        end
        env.AutoFarm = false
        print("[Khfresh] FULL SESSION RESET done — stand still, toggles start OFF")
    end)
end
khHardResetPreviousSession()

local function safeRestorePosition(state)
    if not state or not state.teleported then return end
    local pos = state.oldPosition
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    if typeof(pos) == "Vector3" then
        root.CFrame = CFrame.new(pos.X, pos.Y, pos.Z)
    elseif typeof(pos) == "CFrame" then
        root.CFrame = pos
    end
    state.oldPosition = nil
    state.teleported = false
end


-- ===== GAME DATA =====
runtimeEnv.KhfreshStage("waiting for game data (Events/MainGui/Info/Data)")
local Events = runtimeEnv.KhfreshNeedChild(ReplicatedStorage, "Events", 8)
if not Events then
    warn("[Khfresh] Events not found yet — continuing UI boot (features may be limited)")
    setKhfreshLoadProgress(52, "Events pending...")
end

-- Remote helpers: missing/late remotes never break the UI or spam the console.
local function getEvent(name)
    if not Events then return nil end
    return Events:FindFirstChild(name)
end
local function safeFire(name, ...)
    local remote = getEvent(name)
    if not remote then return false end
    local args = table.pack(...)
    local ok = pcall(function()
        remote:FireServer(table.unpack(args, 1, args.n))
    end)
    return ok
end
local function safeInvoke(name, ...)
    local remote = getEvent(name)
    if not remote then return nil end
    local args = table.pack(...)
    local ok, result = pcall(function()
        return remote:InvokeServer(table.unpack(args, 1, args.n))
    end)
    return ok and result or nil
end
local StartBossFight = Events and Events:FindFirstChild("StartBossFight")
local MainGui = runtimeEnv.KhfreshNeedChild(runtimeEnv.KhfreshNeedChild(LocalPlayer, "PlayerGui", 6), "MainGui", 6)
if not MainGui then
    warn("[Khfresh] MainGui not ready — UI will still open")
end
local Info = runtimeEnv.KhfreshNeedChild(ReplicatedStorage, "Info", 6)
if not Info then
    warn("[Khfresh] Info not ready — UI will still open")
end
local Data = runtimeEnv.KhfreshNeedChild(ReplicatedStorage, "Data", 6)
if not Data then
    warn("[Khfresh] Data not ready — UI will still open")
end

for _, v in pairs((LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:GetChildren()) or {}) do
    if v.Name:find("MobileToggle") then v:Destroy() end
end
pcall(function()
    for _, v in pairs(game:GetService("CoreGui"):GetChildren()) do
        if v.Name:find("MobileToggle") then v:Destroy() end
    end
end)

local CODES = {
    "BigUPD", "23MVisits", "24MVisits", "25MVisits", "26MVisits",
    "42KLikes", "43KLikes", "44KLikes", "45KLikes", "UIBUG",
    "33MVisits", "31MVisits", "32MVisits"
}

-- ===== USER CONFIG / AUTO SAVE / AUTO EXECUTE =====
-- Uses the executor file API when available. The file is stored in the
-- executor workspace as KhfreshHub/KhfreshHub_UserConfig.json.
local KH_CONFIG_PATH = "KhfreshHub/KhfreshHub_UserConfig.txt"
local KH_CONFIG_FALLBACK_PATH = "KhfreshHub_UserConfig.txt"
local KH_CONFIG_JSON_PATH = "KhfreshHub/KhfreshHub_UserConfig.json"
local KH_CONFIG_JSON_FALLBACK = "KhfreshHub_UserConfig.json"
local KH_AUTO_EXECUTE_URL = "https://bombaus-auth.phu-tho-vn.workers.dev/raw/khfresh-hub.lua"
local KH_AUTO_SAVE_INTERVAL = 5

-- Primary persistent configuration table. Every value here is JSON-safe.
local Config = {
    AutoFarm = false,
    AutoSkill = false,
    AutoTicket = false,
    AutoSell = false,
    AutoBuy = false,
    AntiAFK = true,
    WalkSpeed = 16,
    JumpPower = 50,
    TeleportPlace = "Main",
    ServerHopMode = "Least Players",
    WeatherHopTarget = "Thunderstorm",
    WeatherHopEnabled = false,
    WeatherHopTriedServers = {},
    EventHopTarget = "Taoist",
    EventHopEnabled = false,
    EventHopTriedServers = {},
    AutoEquipMethod = "Default",
    NamelessMode = "x1 Note",
    NamelessNoteFallSpeed = 1,
    TeleportToQuestGiver = true,
    AutoExecute = false,
    Language = "auto",
    TicketQuestMode = "Easy",
    SelectedSkills = {Z=true, X=true, C=true, V=true},
    SmartWeather = {
        ["Island 2"] = true, ["Island 3"] = true, ["Island 5"] = true,
        ["Island 6"] = true, ["Island 7"] = true, ["Island 8"] = true,
        ["Island 9"] = true, ["Island 12"] = true, ["Island 13"] = true,
    },
    WeatherIslandNames = { ["Island 9"] = "Blood", ["Island 12"] = "", ["Island 13"] = "" },
    UIControls = {},
    AntiBan = true,
    AutoFarmBoss = false,
    AutoFarmSecretBoss = false,
    AutoEnzo = false,
    AutoEnzoFightMode = "Normal",
    AutoEnzoHitCooldown = 0.15,
    AutoLongDiaohaiFightMode = "Normal",
    AutoLongDiaohaiHitCooldown = 0.15,
    AutoEquipBait = false,
    AutoNameless = false,
    AutoFavourite = false,
    PraySpirit = false,
    AutoFarmSelectedFish = false,
    AutoCraftRod = false,
    AutoBuyBait = false,
    AutoCraftBait = false,
    AutoGacha = false,
    AutoClaimTicketQuest = false,
    AutoDoTicketQuest = false,
    AutoDoDailyQuest = false,
    AutoFarmBaitMaterials = false,
    AutoRecommendIsland = false,
    AutoAscend = false,
    AutoGiveFish2M = false,
    AutoFarm2M = false,
    FlyMode = false,
    Noclip = false,
    InfiniteJump = false,
    WalkOnWater = false,
    FullBright = false,
    NotificationsEnabled = true,
    FakeNameDisplay = false,
    AntiReport = false,
    AntiKick = false,
    AntiDetection = false,
    StaffWatch = false,
    meta = {}
}

-- Backwards-compatible name used by the existing Hub code.
local KhfreshUserConfig = Config
local khAutoSaveEnabled = false -- always off

local function khGetGlobalEnv()
    local env
    pcall(function()
        if type(getgenv) == "function" then env = getgenv() end
    end)
    if type(env) ~= "table" then env = _G end
    return env
end

local function khEnsureConfigFolder()
    if type(makefolder) ~= "function" then return true end
    local ok = pcall(function()
        if type(isfolder) == "function" then
            if not isfolder("KhfreshHub") then makefolder("KhfreshHub") end
        else
            -- Some executors expose makefolder but not isfolder.
            pcall(makefolder, "KhfreshHub")
        end
    end)
    return ok
end

local function khEncodeConfig()
    local http = game:GetService("HttpService")
    local snapshot = {}
    for key, value in pairs(KhfreshUserConfig) do
        if type(value) == "table" then
            local sub = {}
            for k, v in pairs(value) do
                if type(v) ~= "function" and typeof(v) ~= "Instance" then sub[k] = v end
            end
            snapshot[key] = sub
        elseif type(value) ~= "function" and typeof(value) ~= "Instance" then
            snapshot[key] = value
        end
    end
    return http:JSONEncode(snapshot)
end

local function khWriteConfigRaw(encoded)
    local lastErr = "writefile unavailable"
    local writers = {
        type(writefile) == "function" and writefile or nil,
        type(write_file) == "function" and write_file or nil,
    }
    local paths = {
        KH_CONFIG_PATH,
        KH_CONFIG_FALLBACK_PATH,
        KH_CONFIG_JSON_PATH,
        KH_CONFIG_JSON_FALLBACK,
    }
    local anyOk, firstPath = false, nil
    for _, writer in ipairs(writers) do
        if writer then
            khEnsureConfigFolder()
            for _, path in ipairs(paths) do
                local ok, err = pcall(writer, path, encoded)
                if ok then
                    anyOk = true
                    if not firstPath then firstPath = path end
                else
                    lastErr = tostring(err)
                end
            end
            if anyOk then return true, firstPath end
        end
    end
    return false, lastErr
end

local function khSaveUserConfig()
    local env = khGetGlobalEnv()
    env.__KhfreshUserConfig = Config

    local okEncode, encoded = pcall(khEncodeConfig)
    if not okEncode then
        warn("[Khfresh] JSON encode failed:", encoded)
        return false, nil
    end

    -- Write both .txt and .json (same JSON content)
    local okWrite, pathOrErr = khWriteConfigRaw(encoded)
    if okWrite then
        env.__KhfreshLastConfigPath = pathOrErr
        env.__KhfreshUserConfigJSON = encoded
        return true, pathOrErr
    end

    -- Session fallback when executor has no writefile
    pcall(function() env.__KhfreshUserConfigJSON = encoded end)
    warn("[Khfresh] File save unavailable; session config fallback active:", pathOrErr)
    return false, nil
end

local function khSaveConfigNow(reason)
    -- Config save disabled by request
    return false, "save disabled"
end

local function khQueueAutoExecute()
    local queue = (type(queue_on_teleport) == "function" and queue_on_teleport)
        or (type(queueonteleport) == "function" and queueonteleport)
    if not queue then return false, "queue_on_teleport is unavailable in this executor." end
    local code = 'pcall(function() loadstring(game:HttpGet(' .. string.format("%q", KH_AUTO_EXECUTE_URL) .. '))() end)'
    local ok, err = pcall(queue, code)
    if not ok then return false, tostring(err) end
    return true
end

-- Start from script defaults; configuration files are not auto-loaded or auto-saved.
khAutoSaveEnabled = false
Config.meta = Config.meta or {}
pcall(function() khGetGlobalEnv().__KhfreshUserConfig = Config end)

-- ===== STATE TABLE =====
local KhfreshState
KhfreshState = {
    Fishing = {
        Flags = {
            MainFarm = false,
            AutoCast = false,
            AutoSkill = false,
            AutoFarmSkill = false,
            SelectedSkills = (function()
                local t = (type(KhfreshUserConfig.SelectedSkills) == "table" and KhfreshUserConfig.SelectedSkills) or {}
                return { Z = t.Z ~= false, X = t.X ~= false, C = t.C ~= false, V = t.V ~= false }
            end)(),
            AutoFarmBoss = KhfreshUserConfig.AutoFarmBoss == true,
            AutoFarmSecretBoss = KhfreshUserConfig.AutoFarmSecretBoss == true,
            AnchorLock = true,
            AntiAFK = KhfreshUserConfig.AntiAFK ~= false,
            AutoSkillCheck = KhfreshUserConfig.AutoEnzo == true,
            BossFightThread = nil,
            LastCancel = 0,
            LastFastCancel = 0,
            LastProgress = 0,
            LastNotify = ""
        },
        BossFarm = {
            CurrentTarget = nil,
            CurrentType = nil,
            CurrentToken = nil,
            CurrentRunId = 0,
            HasHooked = false,
            PendingCancel = false,
            LastCast = 0,
            LastCancel = 0,
            LastFastCancel = 0,
            LastProgress = 0,
            LastNotify = ""
        }
    },
    MiscFlags = {
        FlyMode = false,
        Noclip = false,
        InfiniteJump = false,
        WalkOnWater = false,
        FullBright = false,
        AutoSell = KhfreshUserConfig.AutoSell == true,
        AutoBuy = KhfreshUserConfig.AutoBuy == true,
        AutoEquipBait = KhfreshUserConfig.AutoEquipBait == true,
        AutoEquipRod = false,
    },
    islands = {
        -- Exactly 13 isles. Labels: "Name | Isle N" (no duplicate World Angler / Weather buttons)
        { name = "Beginning Isle | Isle 1",      cframe = CFrame.new(-297, 9, 12),        power = 0,   islandNumber = 1 },
        { name = "Bamboo Isle | Isle 2",         cframe = CFrame.new(-1274, 21, -270),    power = 17,  islandNumber = 2 },
        { name = "Fallout Isle | Isle 3",        cframe = CFrame.new(57, 9, 1115),        power = 28,  islandNumber = 3 },
        { name = "Sovereign Isle | Isle 4",      cframe = CFrame.new(-1343, 9, 1083),     power = 35,  islandNumber = 4 },
        { name = "Perch Isle | Isle 5",          cframe = CFrame.new(-12, 9, -1696),      power = 45,  islandNumber = 5 },
        { name = "Frost Isle | Isle 6",          cframe = CFrame.new(-1184, 20, -1652),   power = 55,  islandNumber = 6 },
        { name = "Coconut Isle | Isle 7",        cframe = CFrame.new(1470, 9, -1685),     power = 62,  islandNumber = 7 },
        { name = "Amber Isle | Isle 8",          cframe = CFrame.new(1130, 9, 1364),      power = 72,  islandNumber = 8 },
        { name = "Battlefield Isle | Isle 9",    cframe = CFrame.new(1459, 8, -248),      power = 90,  islandNumber = 9 },
        { name = "Mistpeak Isle | Isle 10",      cframe = CFrame.new(3028, 16, -124),     power = 100, islandNumber = 10 },
        { name = "World Angler Isle | Isle 11",  cframe = CFrame.new(-2348.2, 9.6, -204.4), power = 110, islandNumber = 11 },
        { name = "Weather Isle | Isle 12",       cframe = CFrame.new(-2845.62, 9.28, 1235.31), power = 120, islandNumber = 12 },
        { name = "Mystic Reef Isle | Isle 13",   cframe = CFrame.new(-2561.22, 9.28, -1293.07), power = 130, islandNumber = 13 },
    },
    Reroll = { method = "Instant", teleported = false, oldPosition = nil, running = false, thread = nil },
    buyRod = { method = "Instant", teleported = false, oldPosition = nil },
    learnSkill = { method = "Instant", teleported = false, oldPosition = nil },
    upgradeSkill = { method = "Instant", teleported = false, oldPosition = nil },
    exchange = { method = "Instant", teleported = false, oldPosition = nil },
    upgradeCharacter = { method = "Instant", teleported = false, oldPosition = nil },
    favorites = { selectedFish = {}, autoEnabled = false, thread = nil },
    AutoFarm = {
        enabled = KhfreshUserConfig.AutoFarm == true,
        selectedIsland = nil,
        filter1 = nil,
        filter2 = nil,
        filters = { Boss = false, SecretBoss = false, AntiAFK = true },
        teleported = false,
        thread = nil,
        inYourPosition = false,
        inYourPositionCFrame = nil,
        inYourPositionStartedFarm = false,
    },
    LastMaoshan = false,
    LastTaoist = false,
    LastSpirit = false,
    LastWeather = nil,
    reportedJobId = game.JobId,
    autoRecommendRunning = false,
    autoRecommendThread = nil,
    autoRebirthRunning = false,
    autoRebirthThread = nil,
    autoCraftRunning = false,
    autoCraftThread = nil,
    autoGachaRunning = false,
    autoGachaThread = nil,
    autoDoRunning = false,
    autoDoThread = nil,
    autoClaimRunning = false,
    autoClaimThread = nil,
    ticketTargetCount = 0,
    ticketCurrentCount = 0,
    ticketQuestActive = false,
    ticketQuestClaimed = false,
    ticketFarmCFrame = nil,
    ticketCooldownNoticeAt = 0,
    ticketCooldownWarningShown = false,
    ticketTeleportToGiver = true,
    ticketTurnInBusy = false,
    ticketLastTurnIn = 0,
    savedRoutineFlags = nil,
    craftBaitQuantity = 1,
    craftBaitName = "Rainbow Bait",
    selectedBait = nil,
    buyBaitQuantity = 100,
    buyBaitThreshold = 5,
    selectedOptions = { "Cash", "Level" },
    UpgradeCharacter = nil,
    flying = false,
    flySpeed = 50,
    bg = nil,
    bv = nil,
    flyInputConnection = nil,
    flyInputEndConnection = nil,
    flyKeys = { Up = false, Down = false },
    waterY = nil,
    waterPart = nil,
    waterPartsList = {},
    waterWalkConnection = nil,
    waterWalkEnabled = false,
    BossKeywords = { "boss", "raid", "giant", "king", "lord" },
    SecretBossKeywords = { "secret", "hidden", "mythic", "event", "rare" },
    BossNameSet = {},
    SecretBossNameSet = {},
    materialBaitName = "Rainbow Bait",
    autoFishForMaterialsRunning = false,
    autoFishForMaterialsThread = nil,
    materialFarmingSavedFlags = nil,
    materialCurrentTarget = nil,
    autoCraftRodRunning = false,
    autoCraftRodThread = nil,
    enzoHitIndex = 0,
    enzoPhaseActive = false,
    enzoPrevC = nil,
    enzoPrevT = nil,
    enzoNextClick = 0,
    fullBrightApplied = false,
    enzoPrevP = nil,
    enzoDir = 0,
    autoGachaToggleRef = nil,
    sellMethod1 = "Spam",
    sellMethod2 = "Instant",
    lastPosition = nil,
    sellCooldown = 0,
    claimTicketMethod = "Teleport",
    lastQuestPosition = nil,
    craftRodMethod = "Instant",
    lastCraftPosition = nil,
    craftBaitMethod = "Instant",
    buyBaitMethod = "Instant",
    lastCraftBaitPosition = nil,
    lastBuyBaitPosition = nil,
    spectateToggle = false,
    notificationsEnabled = true,
    manualIslandDropdown = false,
    fakeNameEnabled = false,
    fakeName = "KhfreshPlayer",
    fakeDisplayName = "KhfreshPlayer",
    fakeUserId = "0",
    currentLanguage = "auto",
    selectedAutoFarmFish = (type(KhfreshUserConfig.SelectedAutoFarmFish) == "table" and KhfreshUserConfig.SelectedAutoFarmFish) or {},
    selectedAutoFarmFishRunning = false,
    SmartWeather = {
        enabled = false,
        selectedIslands = {
            ["Island 2"] = true,
            ["Island 3"] = true,
            ["Island 5"] = true,
            ["Island 6"] = true,
            ["Island 7"] = true,
            ["Island 8"] = true,
            ["Island 9"] = true,
            ["Island 12"] = true,
            ["Island 13"] = true,
        },
        weatherNames = type(KhfreshUserConfig.WeatherIslandNames) == "table"
            and KhfreshUserConfig.WeatherIslandNames or { ["Island 9"] = "Blood", ["Island 12"] = "", ["Island 13"] = "" },
        activeOverride = false,
        savedCFrame = nil,
        savedFlags = nil,
        targetIsland = nil,
    },
    questFarmingIsland = "Auto (Recommend)",
    autoExecuteOnHop = (KhfreshUserConfig.autoExecute == true) or (KhfreshUserConfig.meta and KhfreshUserConfig.meta.autoExecute == true),

    EventNPC = {
        AutoSave = (KhfreshUserConfig.EventNPC and KhfreshUserConfig.EventNPC.AutoSave == true) or (KhfreshUserConfig.meta and KhfreshUserConfig.meta.eventNpcAutoSave == true),
        HopTarget = tostring((KhfreshUserConfig.EventNPC and KhfreshUserConfig.EventNPC.HopTarget) or (KhfreshUserConfig.meta and KhfreshUserConfig.meta.eventNpcHopTarget) or ""),
        WeatherTarget = tostring((KhfreshUserConfig.EventNPC and KhfreshUserConfig.EventNPC.WeatherTarget) or (KhfreshUserConfig.meta and KhfreshUserConfig.meta.eventNpcWeatherTarget) or "Thunderstorm"),
        Running = false,
        Found = false,
        FoundType = nil,
        Thread = nil,
        LastHop = 0,
        LastJob = nil,
        NamelessRunning = false,
        NamelessThread = nil,
        NamelessFightSeen = false,
        NamelessFightStarted = false,
        NamelessLastActive = 0,
    },
    isDoingUseBaitQuest = false,
    antiBanEnabled = true,
    antiBanConnection = nil,
    antiBanThread = nil,
    InstantCatchEnabled = false,
    InstantCatchMode = "Fast",
    InstantCatchAttempts = 0,
    InstantCatchLast = 0,
    InstantCatchLastFish = "",

    AutoEnzoHitCooldown = math.clamp(tonumber(KhfreshUserConfig.AutoEnzoHitCooldown) or 0.15, 0.01, 1),
    AutoLongDiaohaiHitCooldown = math.clamp(tonumber(KhfreshUserConfig.AutoLongDiaohaiHitCooldown) or 0.15, 0.01, 1),
    AutoEnzoFightMode = (KhfreshUserConfig.AutoEnzoFightMode == "Hard"
        or KhfreshUserConfig.AutoEnzoFightMode == "Nightmare")
        and KhfreshUserConfig.AutoEnzoFightMode or "Normal",
    AutoLongDiaohaiFightMode = (KhfreshUserConfig.AutoLongDiaohaiFightMode == "Hard"
        or KhfreshUserConfig.AutoLongDiaohaiFightMode == "Nightmare")
        and KhfreshUserConfig.AutoLongDiaohaiFightMode or "Normal",
    NamelessNoteFallSpeed = math.clamp(tonumber(KhfreshUserConfig.NamelessNoteFallSpeed) or 2, 1, 10),
    AutoEquipMethod = KhfreshUserConfig.AutoEquipMethod == "Best Rod" and "Best Rod" or "Default",
    WeatherHop = {
        enabled = KhfreshUserConfig.WeatherHopEnabled == true,
        target = tostring(KhfreshUserConfig.WeatherHopTarget or "Thunderstorm"),
        triedServers = type(KhfreshUserConfig.WeatherHopTriedServers) == "table"
            and KhfreshUserConfig.WeatherHopTriedServers or {},
    },
    EventHop = {
        enabled = KhfreshUserConfig.EventHopEnabled == true,
        target = tostring(KhfreshUserConfig.EventHopTarget or "Taoist"),
        triedServers = type(KhfreshUserConfig.EventHopTriedServers) == "table"
            and KhfreshUserConfig.EventHopTriedServers or {},
    },
}

-- Resolve known island names to direct map coordinates, with live landmarks as fallback.
local KH_ISLAND_NUMBERS = {
    ["island 1"] = 1, ["island 2"] = 2, ["island 3"] = 3, ["island 4"] = 4,
    ["island 5"] = 5, ["island 6"] = 6, ["island 7"] = 7, ["island 8"] = 8,
    ["island 9"] = 9, ["island 10"] = 10, ["island 11"] = 11,
    ["island 12"] = 12, ["island 13"] = 13,
    ["beginning isle"] = 1, ["bamboo isle"] = 2, ["fallout isle"] = 3,
    ["sovereign isle"] = 4, ["perch isle"] = 5, ["frost isle"] = 6,
    ["coconut isle"] = 7, ["amber isle"] = 8, ["battlefield isle"] = 9,
    ["mistpeak isle"] = 10, ["world angler isle"] = 11,
    ["weather isle"] = 12, ["mystic reef isle"] = 13,
}
local KH_ISLAND_LABELS = {
    [1] = "Beginning Isle | Isle 1", [2] = "Bamboo Isle | Isle 2", [3] = "Fallout Isle | Isle 3",
    [4] = "Sovereign Isle | Isle 4", [5] = "Perch Isle | Isle 5", [6] = "Frost Isle | Isle 6",
    [7] = "Coconut Isle | Isle 7", [8] = "Amber Isle | Isle 8", [9] = "Battlefield Isle | Isle 9",
    [10] = "Mistpeak Isle | Isle 10", [11] = "World Angler Isle | Isle 11",
    [12] = "Weather Isle | Isle 12", [13] = "Mystic Reef Isle | Isle 13",
}
local function khIslandShortName(label)
    local s = tostring(label or "")
    local a = s:match("^(.-)%s*|")
    return (a and a:match("^%s*(.-)%s*$")) or s
end
local khRuntimeIslandCache = {}
local function khIslandNumber(value)
    if type(value) == "number" then
        local n = math.floor(value)
        if n >= 1 and n <= 13 then return n end
        return nil
    end
    local key = string.lower(tostring(value or "")):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    local nPipe = tonumber(key:match("|%s*isle%s*(%d+)%s*$")) or tonumber(key:match("|%s*island%s*(%d+)%s*$"))
    if nPipe and nPipe >= 1 and nPipe <= 13 then return nPipe end
    local short = key:match("^(.-)%s*|") or key
    short = short:match("^%s*(.-)%s*$") or short
    if KH_ISLAND_NUMBERS[key] then return KH_ISLAND_NUMBERS[key] end
    if KH_ISLAND_NUMBERS[short] then return KH_ISLAND_NUMBERS[short] end
    local n = tonumber(key:match("^island%s+(%d+)$")) or tonumber(key:match("^isle%s+(%d+)$"))
        or tonumber(key:match("isle%s*(%d+)%s*$"))
    if n and n >= 1 and n <= 13 then return n end
    return nil
end
local function khInstanceCFrame(inst)
    if not inst then return nil end
    local ok, cf = pcall(function()
        if inst:IsA("BasePart") then return inst.CFrame end
        if inst:IsA("Model") then return inst:GetPivot() end
        for _, child in ipairs(inst:GetDescendants()) do
            if child:IsA("BasePart") then return child.CFrame end
            if child:IsA("Model") then return child:GetPivot() end
        end
        return nil
    end)
    if ok and typeof(cf) == "CFrame" then return cf end
    return nil
end

local function khTeleportToIslandCoordinates(entry)
    if not entry then return false, "no island" end
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "no hrp" end
    local islandBase = entry.islandCFrame or entry.cframe
    if not islandBase then return false, "no cframe" end
    hrp.CFrame = CFrame.new(islandBase.Position + Vector3.new(0, 4, 0))
    return true, "island"
end

local function khResolveIslandEntry(value)
    local number = khIslandNumber(value)
    local rawName = tostring(value or "")
    local nameLower = string.lower(rawName):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    if not number then number = KH_ISLAND_NUMBERS[nameLower] end

    if number and KhfreshState.islands and KhfreshState.islands[number] then
        local staticEntry = KhfreshState.islands[number]
        if staticEntry.cframe then
            local label = KH_ISLAND_LABELS[number] or staticEntry.name
            local shortName = khIslandShortName(label)
            return {
                name = label,
                displayName = label,
                shortName = shortName,
                islandNumber = number,
                cframe = staticEntry.cframe,
                islandCFrame = staticEntry.cframe,
                power = staticEntry.power or ((number or 1) * 10),
            }
        end
    end

    local targetName = (number and KH_ISLAND_LABELS[number]) or rawName
    if targetName == "" then return nil end
    local cache = khRuntimeIslandCache[targetName]
    if cache and cache.instance and cache.instance.Parent then
        local cf = khInstanceCFrame(cache.instance)
        if cf then
            local shortName = khIslandShortName(targetName)
            return {
                name = targetName,
                displayName = targetName,
                shortName = shortName,
                islandNumber = number,
                cframe = cf,
                islandCFrame = cf,
                instance = cache.instance,
                power = (number or 1) * 10,
            }
        end
    elseif cache and cache.failedUntil and tick() < cache.failedUntil then
        return nil
    end

    local shortName = khIslandShortName(targetName)
    local aliases = {
        [string.lower(targetName)] = true,
        [string.lower(shortName)] = true,
        [string.lower(shortName):gsub("%s+", "")] = true,
    }
    if number then
        aliases["island " .. tostring(number)] = true
        aliases["isle " .. tostring(number)] = true
        aliases["isle" .. tostring(number)] = true
    end
    if number == 11 then aliases["worldanglerisle"] = true end
    if number == 12 then aliases["weatherisle"] = true end
    if number == 13 then aliases["mysticreefisle"] = true end
    local found = nil
    pcall(function()
        for _, inst in ipairs(Workspace:GetDescendants()) do
            local instName = string.lower(tostring(inst.Name or ""))
            local compact = instName:gsub("%s+", "")
            if aliases[instName] or aliases[compact] then
                local cf = khInstanceCFrame(inst)
                if cf then found = inst; break end
            end
        end
    end)

    if found then
        khRuntimeIslandCache[targetName] = {instance = found}
        local cf = khInstanceCFrame(found)
        return {
            name = targetName,
            displayName = targetName,
            shortName = shortName,
            islandNumber = number,
            cframe = cf,
            islandCFrame = cf,
            instance = found,
            power = (number or 1) * 10,
        }
    end

    khRuntimeIslandCache[targetName] = {failedUntil = tick() + 4}
    return nil
end

local function khGetSupportedWeatherNames()
    local names, seen = {}, {}
    local weatherRoot
    pcall(function()
        local clientModules = ReplicatedStorage:FindFirstChild("ClientModule")
        local weatherModule = clientModules and clientModules:FindFirstChild("Weather")
        weatherRoot = weatherModule and weatherModule:FindFirstChild("Weather")
    end)
    if weatherRoot then
        for _, child in ipairs(weatherRoot:GetChildren()) do
            local name = tostring(child.Name or ""):gsub("%-", " ")
            if string.lower(name) ~= "clear" and name ~= "" and not seen[string.lower(name)] then
                seen[string.lower(name)] = true
                names[#names + 1] = name
            end
        end
    end
    if #names == 0 then
        names = {"Blazing Sun", "Blood", "Foggy", "Rainy", "Snowy", "Thunderstorm", "Windy"}
    end
    table.sort(names)
    return names
end

do
    -- Notifications are global: every UI action may surface a toast.
    if KhfreshLib and KhfreshLib.Notify then
        local originalNotify = KhfreshLib.Notify
        KhfreshLib.Notify = function(selfOrConfig, maybeConfig)
            if KhfreshState and KhfreshState.notificationsEnabled == false then
                return
            end
            local config = maybeConfig
            if not config and type(selfOrConfig) == "table" then
                config = selfOrConfig
            end
            config = config or {}
            return originalNotify(KhfreshLib, config)
        end
    end
end

-- ===== KHFRESH ANTI-BAN =====
-- Removes only the BanPlayer-style remote(s) inside ReplicatedStorage.Remotes.
-- This is client-side protection: server-side enforcement is not changed.
local function isBanPlayerRemote(inst)
    if not inst then return false end
    local n = string.lower(tostring(inst.Name or "")):gsub("[%s%p]", "")
    if not (inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction")) then return false end
    return n == "banplayer" or n == "playerban" or n == "banplayerremote"
end

local function purgeBanPlayerRemotes()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then
        pcall(function() remotes = ReplicatedStorage:WaitForChild("Remotes", 5) end)
    end
    if not remotes then return 0 end
    local removed = 0
    for _, inst in ipairs(remotes:GetDescendants()) do
        if isBanPlayerRemote(inst) then
            removed = removed + 1
            pcall(function() inst:Destroy() end)
        end
    end
    return removed
end

initAntiBan = function()
    if KhfreshState.antiBanConnection then
        pcall(function() KhfreshState.antiBanConnection:Disconnect() end)
        KhfreshState.antiBanConnection = nil
    end
    if KhfreshState.antiBanThread then
        pcall(function() task.cancel(KhfreshState.antiBanThread) end)
        KhfreshState.antiBanThread = nil
    end

    KhfreshState.antiBanEnabled = true
    purgeBanPlayerRemotes()

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        KhfreshState.antiBanConnection = remotes.DescendantAdded:Connect(function(inst)
            if KhfreshState.antiBanEnabled and isBanPlayerRemote(inst) then
                pcall(function() inst:Destroy() end)
            end
        end)
    end

    KhfreshState.antiBanThread = task.spawn(function()
        while alive() and KhfreshState.antiBanEnabled do
            pcall(purgeBanPlayerRemotes)
            task.wait(1)
        end
        KhfreshState.antiBanThread = nil
    end)
    return true
end

stopAntiBan = function()
    KhfreshState.antiBanEnabled = false
    if KhfreshState.antiBanConnection then
        pcall(function() KhfreshState.antiBanConnection:Disconnect() end)
        KhfreshState.antiBanConnection = nil
    end
    if KhfreshState.antiBanThread then
        pcall(function() task.cancel(KhfreshState.antiBanThread) end)
        KhfreshState.antiBanThread = nil
    end
end

-- Fast minigame timings (Enzo / Octopus / progression)
KhfreshState.SafeMinigame = {
    Enabled = true,
    EnzoRetry = 0.25,        -- original speed
    ProgressGap = 0.2,       -- original normal fish pace
    BossProgressGap = 0.04,  -- original boss pace
    SlamDelay = 0.1,         -- original-ish
}

-- ===== AUTO LANGUAGE =====
-- Local locale gives an instant fallback; IP geo refines it once after boot.
local HttpService = Services.HttpService or game:GetService("HttpService")
local function detectLocaleLanguage()
    local lang = "en"
    pcall(function()
        local ls = Services.LocalizationService or game:GetService("LocalizationService")
        local locale = ls.RobloxLocaleId or ls.SystemLocaleId
        if type(locale) == "string" then lang = locale:sub(1,2):lower() end
    end)
    local supported = {vi=true,en=true,es=true,pt=true,th=true,id=true}
    return supported[lang] and lang or "en"
end
local function detectCountryLanguageIP()
    local result
    pcall(function()
        local raw = game:HttpGet("https://ipwho.is/?fields=success,country_code")
        local data = HttpService:JSONDecode(raw)
        local cc = data and string.upper(tostring(data.country_code or ""))
        if data and data.success ~= false then
            result = ({VN="vi",ES="es",BR="pt",PT="pt",TH="th",ID="id"})[cc] or "en"
        end
    end)
    return result
end
local detectedCountryLanguage = detectLocaleLanguage()
KhfreshState.detectedLanguage = detectedCountryLanguage

-- ===== AUTO LANGUAGE (I18N) =====
I18n = {}
do
    local LocalizationService = Services.LocalizationService or game:GetService("LocalizationService")
    local rawLocale = "en"
    pcall(function()
        rawLocale = string.lower(
            LocalizationService.RobloxLocaleId
            or LocalizationService.SystemLocaleId
            or (LocalizationService.GetRobloxLocaleId and LocalizationService:GetRobloxLocaleId())
            or (LocalizationService.GetSystemLocaleId and LocalizationService:GetSystemLocaleId())
            or "en"
        )
    end)

    -- Country detection is the primary rule requested by the user:
    -- Vietnam -> Vietnamese; every other country -> English.
    -- Roblox locale is only a fallback when the IP lookup cannot be completed.
    local autoLang = detectedCountryLanguage
    local supported = {vi=true, en=true, es=true, pt=true, th=true, id=true}
    if not supported[autoLang] then
        local locale2 = rawLocale:sub(1,2)
        autoLang = supported[locale2] and locale2 or "en"
    end

    KhfreshState.detectedLanguage = autoLang

    local DICTIONARY = {
        vi = {
            ["Overview"] = "Tổng quan",
                        ["Update log"] = "Nhật ký cập nhật",
            ["Community"] = "Cộng đồng",
            ["About"] = "Thông tin",
            ["Discord"] = "Discord",
            ["YouTube"] = "YouTube",
            ["TikTok"] = "TikTok",
            ["Auto (Locale)"] = "Tự động (Khu vực)",
            ["Session"] = "Tổng quan",
            ["Main"] = "Chính",
            ["Auto Skill"] = "Tự động dùng kỹ năng",
            ["Skills to spam (Z / X / C / V)"] = "Kỹ năng spam (Z / X / C / V)",
            ["Auto Farm Skill"] = "Tự động farm kỹ năng",
            ["Visual Dupe"] = "Nhân bản hiển thị",
            ["Visual target (KG)"] = "Mục tiêu hiển thị (KG)",
            ["Scan Visual Inventory"] = "Quét túi đồ hiển thị",
            ["Create 10 Visual Copies"] = "Tạo 10 bản sao hiển thị",
            ["Clear Visual Copies"] = "Xóa bản sao hiển thị",
            ["Shop"] = "Cửa hàng",
            ["Exchange"] = "Đổi đồ",
            ["Quests"] = "Nhiệm vụ",
            ["Ascend"] = "Thăng cấp",
            ["Teleport"] = "Dịch chuyển",
            ["Settings"] = "Cài đặt",
            ["Session overview"] = "Tổng quan phiên chơi",
            ["Live instruments for "] = "Bảng điều khiển cho ",
            ["Release notes"] = "Nhật ký cập nhật",
            ["Fishing routine"] = "Cơ chế câu cá",
            ["Smart Secret Weather Override"] = "Tự săn Boss theo thời tiết",
            ["Skill profile"] = "Cấu hình kỹ năng",
            ["Auto Equip"] = "Tự động trang bị",
            ["Auto Nameless Octoparasite"] = "Tự săn Bạch tuộc Vô danh",
            ["Auto Favorite Fish"] = "Tự khóa/ưa thích cá",
            ["Auto Pray Spirit"] = "Tự cầu nguyện Linh hồn",
            ["Auto Farm"] = "Tự động Farm",
            ["Index"] = "Sách cá (Index)",
            ["Upgrade Skill"] = "Nâng cấp kỹ năng",
            ["Craft Rod"] = "Chế tạo cần câu",
            ["Auto Buy Bait"] = "Tự mua mồi câu",
            ["Auto Buy Rod"] = "Tự mua cần câu",
            ["Learn Skills"] = "Học kỹ năng",
            ["Trait Reroll"] = "Reroll nội tại",
            ["Craft Bait"] = "Chế tạo mồi câu",
            ["Auto Gacha"] = "Quay Gacha tự động",
            ["Exchange Items"] = "Đổi vật phẩm",
            ["Auto Claim Ticket Quest"] = "Tự nhận Ticket Quest",
            ["Daily Quests"] = "Nhiệm vụ hàng ngày",
            ["Material Farming"] = "Farm nguyên liệu chế cần",
            ["Auto Do Ticket Quest"] = "Tự làm nhiệm vụ Ticket",
            ["Character Upgrade"] = "Nâng cấp nhân vật",
            ["Character"] = "Nhân vật",
            ["World & Misc"] = "Thế giới & Tiện ích",
            ["Streamer Mode (Fake Name)"] = "Chế độ Streamer (Tên giả)",
            ["Language & Localization"] = "Ngôn ngữ & Bản địa hóa",
            ["Khfresh Shield"] = "Khiên bảo vệ Khfresh",
            ["Staff Watch"] = "Cảnh báo Staff / Admin",
            ["ESP"] = "Định vị ESP",
            ["Lock catch bar"] = "Khóa thanh câu",
            ["Auto Cast"] = "Tự quăng cần",
            ["Auto Farm Boss"] = "Tự săn Boss",
            ["Auto Farm Secret Boss"] = "Tự săn Secret Boss",
            ["Auto Skill"] = "Tự dùng chiêu",
            ["Auto Sell Fish"] = "Tự bán cá",
            ["Auto Enzo"] = "Tự giải QTE Enzo",
            ["Anti AFK"] = "Chống AFK",
            ["Auto Override On Weather"] = "Tự đổi đảo theo thời tiết",
            ["Auto Equip Best Bait"] = "Tự lắp mồi xịn nhất",
            ["Auto Equip Fishing Rod (Slot 1)"] = "Tự cầm cần câu (Slot 1)",
            ["Auto Nameless"] = "Tự farm Vô danh",
            ["Auto Favourite Fishes"] = "Tự ưa thích cá",
            ["Auto Teleport + Interact (Pray) Spirit"] = "Tự bay đến cầu nguyện Linh hồn",
            ["Enable Auto Farm Fish"] = "Bật Auto Farm Cá",
            ["Auto Do Daily Quest"] = "Tự làm Quest hàng ngày",
            ["Auto Do Ticket Quest (Fast)"] = "Tự làm Ticket Quest (Nhanh)",
            ["Auto Claim Ticket Quest (Fast)"] = "Tự nhận Ticket Quest (Nhanh)",
            ["Auto Ascend"] = "Tự động Thăng cấp",
            ["Auto craft bait"] = "Tự chế mồi câu",
            ["Auto craft selected rod"] = "Tự chế cần đã chọn",
            ["Auto fish for bait materials"] = "Tự câu nguyên liệu mồi",
            ["Fly Mode"] = "Chế độ Bay (Fly)",
            ["Walk On Water"] = "Đi trên mặt nước",
            ["Infinite Jump"] = "Nhảy vô hạn",
            ["Noclip"] = "Đi xuyên tường",
            ["Full Bright"] = "Tăng sáng màn hình",
            ["Fake Name Display"] = "Bật ẩn tên Streamer",
            ["Anti-Report Khfresh Users"] = "Chặn report người dùng Khfresh",
            ["Enable Staff Watch"] = "Bật dò tìm Staff",
            ["Enable Notifications"] = "Bật thông báo",
            ["Ignore Locked"] = "Bỏ qua đồ bị khóa",
            ["Performance Mod"] = "Chế độ mượt (FPS)",
            ["NPCs ESP"] = "ESP NPC",
            ["Secret Rod ESP"] = "ESP Cần Bí Ẩn",
            ["Boat ESP"] = "ESP Thuyền",
            ["God ESP"] = "ESP Boss Thần",
            ["Review update v2.2"] = "Xem thông tin bản v2.2",
            ["Equip Best Rod"] = "Cầm cần xịn nhất",
            ["Equip Best Orb"] = "Trang bị Orb tốt nhất",
            ["Teleport to Nameless Octoparasite"] = "Bay tới Vô danh",
            ["Unlock all fish"] = "Mở khóa toàn bộ cá",
            ["Upgrade Selected Skill"] = "Nâng cấp chiêu đã chọn",
            ["Craft rod now"] = "Chế cần ngay",
            ["Buy Now"] = "Mua ngay",
            ["Buy Selected Rod"] = "Mua cần đã chọn",
            ["Learn Selected Skills"] = "Học chiêu đã chọn",
            ["Reroll Until Trait"] = "Reroll đến khi ra",
            ["Craft bait now"] = "Chế mồi ngay",
            ["Exchange now"] = "Đổi ngay",
            ["Claim Daily Rewards"] = "Nhận thưởng hàng ngày",
            ["Check Resources"] = "Kiểm tra tài nguyên",
            ["Redeem All Codes"] = "Nhập toàn bộ Code",
            ["Refresh List"] = "Làm mới danh sách",
            ["Delete Job ID"] = "Xóa Job ID",
            ["Check Current Players"] = "Kiểm tra người chơi",
            ["Teleport to Player"] = "Bay tới người chơi",
            ["Spectate Player"] = "Xem người chơi",
            ["Teleport To Current Weather"] = "Bay tới đảo có thời tiết",
            ["Teleport to Recommend Island"] = "Bay tới đảo phù hợp",
            ["Teleport to selected NPC"] = "Bay tới NPC đã chọn",
            ["Teleport to selected Secret Rod"] = "Bay tới Cần Secret",
            ["TP to Maoshan"] = "Bay tới Mao Sơn",
            ["TP to Spirit"] = "Bay tới Linh Hồn",
            ["TP to Taoist"] = "Bay tới Đạo Sĩ",
            ["UI Language"] = "Ngôn ngữ UI",
            ["Select Island"] = "Chọn đảo",
            ["Island Selection Mode"] = "Chế độ chọn đảo",
            ["Select Bait to Buy"] = "Chọn mồi cần mua",
            ["Select Rod to Buy"] = "Chọn cần cần mua",
            ["Select Rod to Craft"] = "Chọn cần cần chế",
            ["Buy Method"] = "Cách thức mua",
            ["Craft Method"] = "Cách thức chế",
            ["Upgrade Method"] = "Cách thức nâng",
            ["Learn Method"] = "Cách thức học",
            ["Exchange Method"] = "Cách thức đổi",
            ["Reroll Method"] = "Cách thức reroll",
            ["Method Claim"] = "Cách nhận thưởng",
            ["Method Sell #1"] = "Phương pháp bán 1",
            ["Method Sell #2"] = "Phương pháp bán 2",
            ["Nameless Mode"] = "Chế độ Vô Danh",
            ["Filter #1"] = "Bộ lọc 1",
            ["Select Banner"] = "Chọn Banner",
            ["Select Player"] = "Chọn người chơi",
            ["Select Quest Type"] = "Chọn loại nhiệm vụ",
            ["Select Skill"] = "Chọn kỹ năng",
            ["Target Trait"] = "Nội tại mục tiêu",
            ["Choose a Bait"] = "Chọn loại mồi",
            ["Choose an island"] = "Chọn một đảo",
            ["Choose an item"] = "Chọn một món đồ",
            ["Buy Amount"] = "Số lượng mua",
            ["Buy When Below"] = "Mua khi dưới mức",
            ["Number of baits to craft"] = "Số mồi cần chế",
            ["Quantity"] = "Số lượng",
            ["Tickets per roll"] = "Ticket mỗi lượt quay",
            ["Fly Speed"] = "Tốc độ bay",
            ["Walk Speed"] = "Tốc độ chạy",
            ["Risk hits/sec (1-200)"] = "Tốc độ bấm/giây",
            ["Safe band (0.01-0.17)"] = "Vùng an toàn",
            ["Fake Username"] = "Tên tài khoản giả",
            ["Fake Display Name"] = "Tên hiển thị giả",
            ["Name Of The Fish (Optional)"] = "Tên cá (Tùy chọn)",
            ["Select bait for material farming"] = "Chọn mồi câu nguyên liệu",
            ["Choose A Skill That Needs To Upgrade"] = "Chọn chiêu cần nâng cấp",
            ["Learn Skill NPC"] = "Chọn NPC học chiêu",
            ["Secret Rods"] = "Chọn Cần Bí Ẩn",
            ["Misc NPCs"] = "NPC Khác",
            ["Players"] = "Danh sách người chơi",
            ["Allowed Weather Islands"] = "Đảo cho phép theo thời tiết",
            ["Skills to press"] = "Chiêu cần bấm",
            ["Select fish to auto-favourite"] = "Chọn cá tự khóa/ưa thích",
            ["Select Skills to Learn"] = "Chọn chiêu để học",
            ["Select 2 upgrade options"] = "Chọn 2 tùy chọn nâng cấp"
        },
        es = {
            ["Session"] = "Sesión",
            ["Main"] = "Pesca",
            ["Shop"] = "Tienda",
            ["Exchange"] = "Intercambio",
            ["Quests"] = "Misiones",
            ["Ascend"] = "Mejoras",
            ["Teleport"] = "Teletransporte",
            ["Settings"] = "Ajustes",
            ["Session overview"] = "Resumen de la sesión",
            ["Release notes"] = "Notas de la versión",
            ["Fishing routine"] = "Rutina de pesca",
            ["Smart Secret Weather Override"] = "Auto Farm por Clima",
            ["Skill profile"] = "Perfil de habilidades",
            ["Auto Equip"] = "Auto Equipar",
            ["Auto Nameless Octoparasite"] = "Auto Pulpo Sin Nombre",
            ["Auto Favorite Fish"] = "Auto Favorito de Peces",
            ["Auto Pray Spirit"] = "Auto Rezar al Espíritu",
            ["Auto Farm"] = "Auto Farm",
            ["Index"] = "Índice de Peces",
            ["Upgrade Skill"] = "Mejorar Habilidad",
            ["Craft Rod"] = "Fabricar Caña",
            ["Auto Buy Bait"] = "Auto Comprar Cebo",
            ["Auto Buy Rod"] = "Auto Comprar Caña",
            ["Learn Skills"] = "Aprender Habilidades",
            ["Trait Reroll"] = "Reroll de Rasgos",
            ["Craft Bait"] = "Fabricar Cebo",
            ["Auto Gacha"] = "Auto Gacha",
            ["Exchange Items"] = "Intercambiar Objetos",
            ["Auto Claim Ticket Quest"] = "Auto Reclamar Misión Ticket",
            ["Daily Quests"] = "Misiones Diarias",
            ["Material Farming"] = "Farm de Materiales",
            ["Auto Do Ticket Quest"] = "Auto Hacer Misión Ticket",
            ["Character Upgrade"] = "Mejorar Personaje",
            ["Character"] = "Personaje",
            ["World & Misc"] = "Mundo y Varios",
            ["Streamer Mode (Fake Name)"] = "Modo Streamer (Nombre Falso)",
            ["Language & Localization"] = "Idioma y Localización",
            ["Khfresh Shield"] = "Escudo Khfresh",
            ["Staff Watch"] = "Vigilancia de Staff",
            ["ESP"] = "ESP",
            ["Lock catch bar"] = "Bloquear barra de captura",
            ["Auto Cast"] = "Auto Lanzar",
            ["Auto Farm Boss"] = "Auto Farm Boss",
            ["Auto Farm Secret Boss"] = "Auto Farm Secret Boss",
            ["Auto Skill"] = "Auto Habilidad",
            ["Auto Sell Fish"] = "Auto Vender Peces",
            ["Auto Enzo"] = "Auto Enzo QTE",
            ["Anti AFK"] = "Anti AFK",
            ["Auto Override On Weather"] = "Auto Farm por Clima",
            ["Auto Equip Best Bait"] = "Auto Equipar Mejor Cebo",
            ["Auto Equip Fishing Rod (Slot 1)"] = "Auto Equipar Caña (Slot 1)",
            ["Auto Nameless"] = "Auto Sin Nombre",
            ["Auto Favourite Fishes"] = "Auto Favorito de Peces",
            ["Auto Teleport + Interact (Pray) Spirit"] = "Auto Rezar Espíritu",
            ["Enable Auto Farm Fish"] = "Activar Auto Farm",
            ["Auto Do Daily Quest"] = "Auto Misión Diaria",
            ["Auto Do Ticket Quest (Fast)"] = "Auto Misión Ticket (Rápido)",
            ["Auto Claim Ticket Quest (Fast)"] = "Auto Reclamar Ticket (Rápido)",
            ["Auto Ascend"] = "Auto Renacimiento",
            ["Auto craft bait"] = "Auto fabricar cebo",
            ["Auto craft selected rod"] = "Auto fabricar caña",
            ["Auto fish for bait materials"] = "Auto pescar materiales",
            ["Fly Mode"] = "Modo Vuelo",
            ["Walk On Water"] = "Caminar Sobre Agua",
            ["Infinite Jump"] = "Salto Infinito",
            ["Noclip"] = "Noclip",
            ["Full Bright"] = "Brillo Máximo",
            ["Fake Name Display"] = "Nombre Falso Activo",
            ["Anti-Report Khfresh Users"] = "Anti-Reporte Usuarios Khfresh",
            ["Enable Staff Watch"] = "Activar Vigilancia Staff",
            ["Enable Notifications"] = "Activar Notificaciones",
            ["UI Language"] = "Idioma de la UI",
            ["Skill Mode"] = "Modo de Habilidad",
            ["Skill Sequence Order"] = "Orden de Habilidades",
            ["Skill Delay (seconds)"] = "Retraso de Habilidad (s)",
            ["Select Island"] = "Seleccionar Isla",
            ["Buy Now"] = "Comprar Ahora",
            ["Craft rod now"] = "Fabricar Caña Ahora",
            ["Craft bait now"] = "Fabricar Cebo Ahora",
            ["Exchange now"] = "Intercambiar Ahora"
        },
        pt = {
            ["Session"] = "Sessão",
            ["Main"] = "Pescaria",
            ["Shop"] = "Loja",
            ["Exchange"] = "Troca",
            ["Quests"] = "Missões",
            ["Ascend"] = "Melhorias",
            ["Teleport"] = "Teleporte",
            ["Settings"] = "Configurações",
            ["Session overview"] = "Visão geral da sessão",
            ["Release notes"] = "Notas da versão",
            ["Fishing routine"] = "Rotina de pescaria",
            ["Smart Secret Weather Override"] = "Auto Farm por Clima",
            ["Skill profile"] = "Perfil de habilidades",
            ["Auto Equip"] = "Auto Equipar",
            ["Auto Nameless Octoparasite"] = "Auto Polvo Sem Nome",
            ["Auto Favorite Fish"] = "Auto Favoritar Peixes",
            ["Auto Pray Spirit"] = "Auto Orar ao Espírito",
            ["Auto Farm"] = "Auto Farm",
            ["Index"] = "Índice de Peixes",
            ["Upgrade Skill"] = "Melhorar Habilidade",
            ["Craft Rod"] = "Criar Vara",
            ["Auto Buy Bait"] = "Auto Comprar Isca",
            ["Auto Buy Rod"] = "Auto Comprar Vara",
            ["Learn Skills"] = "Aprender Habilidades",
            ["Trait Reroll"] = "Reroll de Traço",
            ["Craft Bait"] = "Criar Isca",
            ["Auto Gacha"] = "Auto Gacha",
            ["Exchange Items"] = "Trocar Itens",
            ["Auto Claim Ticket Quest"] = "Auto Resgatar Missão Ticket",
            ["Daily Quests"] = "Missões Diárias",
            ["Material Farming"] = "Farm de Materiais",
            ["Auto Do Ticket Quest"] = "Auto Fazer Missão Ticket",
            ["Character Upgrade"] = "Melhorar Personagem",
            ["Character"] = "Personagem",
            ["World & Misc"] = "Mundo e Diversos",
            ["Streamer Mode (Fake Name)"] = "Modo Streamer (Nome Falso)",
            ["Language & Localization"] = "Idioma e Localização",
            ["Khfresh Shield"] = "Escudo Khfresh",
            ["Staff Watch"] = "Alerta de Staff",
            ["ESP"] = "ESP",
            ["Lock catch bar"] = "Travar barra de captura",
            ["Auto Cast"] = "Auto Lançar",
            ["Auto Farm Boss"] = "Auto Farm Boss",
            ["Auto Farm Secret Boss"] = "Auto Farm Secret Boss",
            ["Auto Skill"] = "Auto Habilidade",
            ["Auto Sell Fish"] = "Auto Vender Peixes",
            ["Auto Enzo"] = "Auto Enzo QTE",
            ["Anti AFK"] = "Anti AFK",
            ["Auto Override On Weather"] = "Auto Farm por Clima",
            ["Auto Equip Best Bait"] = "Auto Equipar Melhor Isca",
            ["Auto Equip Fishing Rod (Slot 1)"] = "Auto Equipar Vara (Slot 1)",
            ["Auto Nameless"] = "Auto Sem Nome",
            ["Auto Favourite Fishes"] = "Auto Favoritar Peixes",
            ["Auto Teleport + Interact (Pray) Spirit"] = "Auto Orar Espírito",
            ["Enable Auto Farm Fish"] = "Ativar Auto Farm",
            ["Auto Do Daily Quest"] = "Auto Missão Diária",
            ["Auto Do Ticket Quest (Fast)"] = "Auto Missão Ticket (Rápido)",
            ["Auto Claim Ticket Quest (Fast)"] = "Auto Resgatar Ticket (Rápido)",
            ["Auto Ascend"] = "Auto Renascimento",
            ["Auto craft bait"] = "Auto criar isca",
            ["Auto craft selected rod"] = "Auto criar vara",
            ["Auto fish for bait materials"] = "Auto pescar materiais",
            ["Fly Mode"] = "Modo Voo",
            ["Walk On Water"] = "Andar na Água",
            ["Infinite Jump"] = "Pulo Infinito",
            ["Noclip"] = "Noclip",
            ["Full Bright"] = "Brilho Total",
            ["Fake Name Display"] = "Nome Falso Ativo",
            ["Anti-Report Khfresh Users"] = "Anti-Denúncia Usuários Khfresh",
            ["Enable Staff Watch"] = "Ativar Alerta de Staff",
            ["Enable Notifications"] = "Ativar Notificações",
            ["UI Language"] = "Idioma da UI",
            ["Skill Mode"] = "Modo de Habilidade",
            ["Skill Sequence Order"] = "Ordem das Habilidades",
            ["Skill Delay (seconds)"] = "Atraso de Habilidade (s)",
            ["Select Island"] = "Selecionar Ilha",
            ["Buy Now"] = "Comprar Agora",
            ["Craft rod now"] = "Criar Vara Agora",
            ["Craft bait now"] = "Criar Isca Agora",
            ["Exchange now"] = "Trocar Agora"
        },
        th = {
            ["Session"] = "ภาพรวม",
            ["Main"] = "ตกปลา",
            ["Shop"] = "ร้านค้า",
            ["Exchange"] = "แลกเปลี่ยน",
            ["Quests"] = "เควสต์",
            ["Ascend"] = "อัปเกรด",
            ["Teleport"] = "วาร์ป",
            ["Settings"] = "การตั้งค่า",
            ["Session overview"] = "ภาพรวมเซสชัน",
            ["Release notes"] = "บันทึกการอัปเดต",
            ["Fishing routine"] = "ระบบตกปลา",
            ["Smart Secret Weather Override"] = "ฟาร์มอัตโนมัติตามสภาพอากาศ",
            ["Skill profile"] = "ตั้งค่าสกิล",
            ["Auto Equip"] = "สวมใส่อัตโนมัติ",
            ["Auto Nameless Octoparasite"] = "ออโต้บอสปลาหมึกไร้นาม",
            ["Auto Favorite Fish"] = "ล็อกปลาโปรดอัตโนมัติ",
            ["Auto Pray Spirit"] = "ออโต้วิหารวิญญาณ",
            ["Auto Farm"] = "ฟาร์มอัตโนมัติ",
            ["Index"] = "สารานุกรมปลา",
            ["Upgrade Skill"] = "อัปเกรดสกิล",
            ["Craft Rod"] = "คราฟต์เบ็ดตกปลา",
            ["Auto Buy Bait"] = "ซื้อเหยื่ออัตโนมัติ",
            ["Auto Buy Rod"] = "ซื้อเบ็ดอัตโนมัติ",
            ["Learn Skills"] = "เรียนรู้สกิล",
            ["Trait Reroll"] = "รีโรลพลังแฝง",
            ["Craft Bait"] = "คราฟต์เหยื่อ",
            ["Auto Gacha"] = "สุ่มกาชาอัตโนมัติ",
            ["Exchange Items"] = "แลกเปลี่ยนไอเทม",
            ["Auto Claim Ticket Quest"] = "รับเควสต์ตั๋วอัตโนมัติ",
            ["Daily Quests"] = "เควสต์รายวัน",
            ["Material Farming"] = "ฟาร์มวัตถุดิบ",
            ["Auto Do Ticket Quest"] = "ทำเควสต์ตั๋วอัตโนมัติ",
            ["Character Upgrade"] = "อัปเกรดตัวละคร",
            ["Character"] = "ตัวละคร",
            ["World & Misc"] = "โลกและอื่นๆ",
            ["Streamer Mode (Fake Name)"] = "โหมดสตรีมเมอร์ (ชื่อปลอม)",
            ["Language & Localization"] = "ภาษาและการแปล",
            ["Khfresh Shield"] = "โล่ป้องกัน Khfresh",
            ["Staff Watch"] = "ตรวจจับ Staff / แอดมิน",
            ["ESP"] = "ESP",
            ["Lock catch bar"] = "ล็อกแถบจับปลา",
            ["Auto Cast"] = "เหวี่ยงเบ็ดอัตโนมัติ",
            ["Auto Farm Boss"] = "ฟาร์มบอสอัตโนมัติ",
            ["Auto Farm Secret Boss"] = "ฟาร์มซีเคร็ตบอสอัตโนมัติ",
            ["Auto Skill"] = "ใช้สกิลอัตโนมัติ",
            ["Auto Sell Fish"] = "ขายปลาอัตโนมัติ",
            ["Auto Enzo"] = "แก้ Enzo QTE อัตโนมัติ",
            ["Anti AFK"] = "ป้องกัน AFK",
            ["Auto Override On Weather"] = "วาร์ปฟาร์มตามสภาพอากาศ",
            ["Auto Equip Best Bait"] = "ใส่เหยื่อที่ดีที่สุด",
            ["Auto Equip Fishing Rod (Slot 1)"] = "ถือเบ็ดตกปลาอัตโนมัติ",
            ["Auto Nameless"] = "ออโต้ไร้นาม",
            ["Auto Favourite Fishes"] = "ล็อกปลาโปรดอัตโนมัติ",
            ["Auto Teleport + Interact (Pray) Spirit"] = "วาร์ปไปสวดวิญญาณอัตโนมัติ",
            ["Enable Auto Farm Fish"] = "เปิดฟาร์มปลาอัตโนมัติ",
            ["Auto Do Daily Quest"] = "ทำเควสต์รายวันอัตโนมัติ",
            ["Auto Do Ticket Quest (Fast)"] = "ทำเควสต์ตั๋ว (ด่วน)",
            ["Auto Claim Ticket Quest (Fast)"] = "รับเควสต์ตั๋ว (ด่วน)",
            ["Auto Ascend"] = "จุติตัวละครอัตโนมัติ",
            ["Auto craft bait"] = "คราฟต์เหยื่ออัตโนมัติ",
            ["Auto craft selected rod"] = "คราฟต์เบ็ดที่เลือกอัตโนมัติ",
            ["Auto fish for bait materials"] = "ตกปลาหาวัตถุดิบเหยื่อ",
            ["Fly Mode"] = "โหมดบิน (Fly)",
            ["Walk On Water"] = "เดินบนผิวน้ำ",
            ["Infinite Jump"] = "กระโดดไม่จำกัด",
            ["Noclip"] = "เดินทะลุกำแพง",
            ["Full Bright"] = "เปิดแสงสว่างเต็มที่",
            ["Fake Name Display"] = "เปิดชื่อปลอมสตรีมเมอร์",
            ["Anti-Report Khfresh Users"] = "บล็อกการรายงานผู้ใช้ Khfresh",
            ["Enable Staff Watch"] = "เปิดตรวจจับ Staff",
            ["Enable Notifications"] = "เปิดการแจ้งเตือน",
            ["UI Language"] = "ภาษา UI",
            ["Skill Mode"] = "โหมดสกิล",
            ["Skill Sequence Order"] = "ลำดับสกิล",
            ["Skill Delay (seconds)"] = "หน่วงเวลาสกิล (วินาที)",
            ["Select Island"] = "เลือกเกาะ",
            ["Buy Now"] = "ซื้อทันที",
            ["Craft rod now"] = "คราฟต์เบ็ดทันที",
            ["Craft bait now"] = "คราฟต์เหยื่อทันที",
            ["Exchange now"] = "แลกเปลี่ยนทันที"
        },
        id = {
            ["Session"] = "Sesi",
            ["Main"] = "Memancing",
            ["Shop"] = "Toko",
            ["Exchange"] = "Tukar",
            ["Quests"] = "Misi",
            ["Ascend"] = "Peningkatan",
            ["Teleport"] = "Teleportasi",
            ["Settings"] = "Pengaturan",
            ["Session overview"] = "Ringkasan Sesi",
            ["Release notes"] = "Catatan Pembaruan",
            ["Fishing routine"] = "Rutinitas Memancing",
            ["Smart Secret Weather Override"] = "Auto Farm Cuaca Rahasia",
            ["Skill profile"] = "Profil Skill",
            ["Auto Equip"] = "Auto Pasang",
            ["Auto Nameless Octoparasite"] = "Auto Gurita Tanpa Nama",
            ["Auto Favorite Fish"] = "Auto Favoritkan Ikan",
            ["Auto Pray Spirit"] = "Auto Doa ke Roh",
            ["Auto Farm"] = "Auto Farm",
            ["Index"] = "Indeks Ikan",
            ["Upgrade Skill"] = "Tingkatkan Skill",
            ["Craft Rod"] = "Buat Pancingan",
            ["Auto Buy Bait"] = "Auto Beli Umpan",
            ["Auto Buy Rod"] = "Auto Beli Pancingan",
            ["Learn Skills"] = "Pelajari Skill",
            ["Trait Reroll"] = "Reroll Sifat",
            ["Craft Bait"] = "Buat Umpan",
            ["Auto Gacha"] = "Auto Gacha",
            ["Exchange Items"] = "Tukar Barang",
            ["Auto Claim Ticket Quest"] = "Auto Klaim Misi Tiket",
            ["Daily Quests"] = "Misi Harian",
            ["Material Farming"] = "Farm Bahan",
            ["Auto Do Ticket Quest"] = "Auto Jalankan Misi Tiket",
            ["Character Upgrade"] = "Tingkatkan Karakter",
            ["Character"] = "Karakter",
            ["World & Misc"] = "Dunia & Lainnya",
            ["Streamer Mode (Fake Name)"] = "Mode Streamer (Nama Palsu)",
            ["Language & Localization"] = "Bahasa & Lokalisasi",
            ["Khfresh Shield"] = "Perisai Khfresh",
            ["Staff Watch"] = "Deteksi Staff",
            ["ESP"] = "ESP",
            ["Lock catch bar"] = "Kunci bilah tangkapan",
            ["Auto Cast"] = "Lempar Otomatis",
            ["Auto Farm Boss"] = "Auto Farm Boss",
            ["Auto Farm Secret Boss"] = "Auto Farm Secret Boss",
            ["Auto Skill"] = "Auto Skill",
            ["Auto Sell Fish"] = "Auto Jual Ikan",
            ["Auto Enzo"] = "Auto Enzo QTE",
            ["Anti AFK"] = "Anti AFK",
            ["Auto Override On Weather"] = "Auto Farm Berdasarkan Cuaca",
            ["Auto Equip Best Bait"] = "Pasang Umpan Terbaik",
            ["Auto Equip Fishing Rod (Slot 1)"] = "Pegang Pancingan Otomatis",
            ["Auto Nameless"] = "Auto Tanpa Nama",
            ["Auto Favourite Fishes"] = "Auto Favoritkan Ikan",
            ["Auto Teleport + Interact (Pray) Spirit"] = "Auto Doa Roh",
            ["Enable Auto Farm Fish"] = "Aktifkan Auto Farm",
            ["Auto Do Daily Quest"] = "Auto Misi Harian",
            ["Auto Do Ticket Quest (Fast)"] = "Auto Misi Tiket (Cepat)",
            ["Auto Claim Ticket Quest (Fast)"] = "Auto Klaim Tiket (Cepat)",
            ["Auto Ascend"] = "Auto Kelahiran Kembali",
            ["Auto craft bait"] = "Auto buat umpan",
            ["Auto craft selected rod"] = "Auto buat pancingan",
            ["Auto fish for bait materials"] = "Auto pancing bahan umpan",
            ["Fly Mode"] = "Mode Terbang",
            ["Walk On Water"] = "Berjalan di Atas Air",
            ["Infinite Jump"] = "Lompat Tak Terbatas",
            ["Noclip"] = "Noclip",
            ["Full Bright"] = "Kecerahan Penuh",
            ["Fake Name Display"] = "Nama Palsu Aktif",
            ["Anti-Report Khfresh Users"] = "Anti-Laporkan Pengguna Khfresh",
            ["Enable Staff Watch"] = "Aktifkan Deteksi Staff",
            ["Enable Notifications"] = "Aktifkan Notifikasi",
            ["UI Language"] = "Bahasa UI",
            ["Skill Mode"] = "Mode Skill",
            ["Skill Sequence Order"] = "Urutan Skill",
            ["Skill Delay (seconds)"] = "Jeda Skill (detik)",
            ["Select Island"] = "Pilih Pulau",
            ["Buy Now"] = "Beli Sekarang",
            ["Craft rod now"] = "Buat Pancingan Sekarang",
            ["Craft bait now"] = "Buat Umpan Sekarang",
            ["Exchange now"] = "Tukar Sekarang"
        }
    }

    function I18n.getCurrentLanguage()
        if KhfreshState.currentLanguage == "auto" then
            return KhfreshState.detectedLanguage or "en"
        end
        return KhfreshState.currentLanguage or "en"
    end

    function I18n.get(key, fallback)
        if not key or type(key) ~= "string" then return fallback or key end
        local lang = I18n.getCurrentLanguage()
        if lang == "en" then return fallback or key end
        local dict = DICTIONARY[lang]
        if dict and dict[key] then return dict[key] end
        return fallback or key
    end

    local function translateObject(obj)
        if not obj then return end
        pcall(function()
            if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                local currentText = obj.Text
                if not currentText or #currentText == 0 then return end

                local lang = I18n.getCurrentLanguage()
                local dict = DICTIONARY[lang]

                local orig = obj:GetAttribute("KhfreshOrigText")
                if not orig or (dict and dict[currentText]) then
                    orig = currentText
                    obj:SetAttribute("KhfreshOrigText", orig)
                end

                if orig and #orig > 0 then
                    if lang == "en" then
                        if obj.Text ~= orig then
                            obj.Text = orig
                        end
                    else
                        local trans = dict and dict[orig]
                        if trans and obj.Text ~= trans then
                            obj.Text = trans
                        end
                    end
                end
            end
        end)
    end

    local function applyLanguageToGui(gui)
        if not gui then return end
        pcall(function()
            for _, desc in ipairs(gui:GetDescendants()) do
                translateObject(desc)
            end
        end)
    end

    function I18n.applyLanguage()
        local lang = I18n.getCurrentLanguage()
        local dict = DICTIONARY[lang] or {}
        local reverse = {}
        for key, value in pairs(dict) do
            reverse[value] = key
        end

        local function translateRoot(root)
            if not root then return end
            pcall(function()
                for _, obj in ipairs(root:GetDescendants()) do
                    if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                        local text = obj.Text
                        if text and #text > 0 then
                            local orig = obj:GetAttribute("KhfreshOrigText")
                            if not orig then
                                orig = reverse[text] or text
                                obj:SetAttribute("KhfreshOrigText", orig)
                            end
                            if lang == "en" then
                                obj.Text = orig
                            else
                                obj.Text = dict[orig] or orig
                            end
                        end
                    end
                end
            end)
        end

        -- One-shot scan only. No permanent DescendantAdded connection.
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        translateRoot(pg and pg:FindFirstChild("KhfreshUI"))
        pcall(function()
            local cg = game:GetService("CoreGui")
            translateRoot(cg and (cg:FindFirstChild("Redz") or cg:FindFirstChild("KhfreshUI")))
        end)
    end

    function I18n.initListeners()
        -- Intentionally empty: translation is applied at control creation time.
    end
end

-- One-shot IP refinement; never blocks UI creation.
task.spawn(function()
    task.wait(1.5)
    if not alive() or KhfreshState.currentLanguage ~= "auto" then return end
    local ipLang = detectCountryLanguageIP()
    if ipLang and KhfreshState.currentLanguage == "auto" and ipLang ~= KhfreshState.detectedLanguage then
        KhfreshState.detectedLanguage = ipLang
        pcall(function() I18n.applyLanguage() end)
    end
end)

-- ===== FAKE NAME (STREAMER MODE) CORE =====
do
    local realName = LocalPlayer.Name
    local realDisplayName = LocalPlayer.DisplayName
    local fakeNameConn = nil
    local fakeNameThread = nil
    local maskIdsInText -- forward declare (dinh nghia ben duoi)

    local function replaceTextInObject(obj)
        if not KhfreshState.fakeNameEnabled then return end
        if not obj then return end
        pcall(function()
            if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                local text = obj.Text
                if text and #text > 0 then
                    local updated = false
                    if realDisplayName ~= "" and string.find(text, realDisplayName, 1, true) then
                        text = string.gsub(text, realDisplayName, KhfreshState.fakeDisplayName or "KhfreshPlayer")
                        updated = true
                    end
                    if realName ~= "" and string.find(text, realName, 1, true) then
                        text = string.gsub(text, realName, KhfreshState.fakeName or "KhfreshPlayer")
                        updated = true
                    end
                    -- Che luon ID (UserId / PlaceId / JobId) chu khong chi ten
                    if maskIdsInText then
                        local masked, idChanged = maskIdsInText(text)
                        if idChanged then
                            text = masked
                            updated = true
                        end
                    end
                    if updated then
                        obj.Text = text
                    end
                end
            end
        end)
    end

    -- Che ID: doi ten khong thoi van bi report vi nguoi ta doc UserId / PlaceId /
    -- JobId tren man hinh (hoac trong anh chup). Nen phai che luon cac ID nay.
    local realUserId = tostring(LocalPlayer.UserId)
    local realPlaceId = tostring(game.PlaceId)

    function maskIdsInText(text)
        if not KhfreshState.fakeNameEnabled then return text, false end
        local changed = false
        if #realUserId >= 5 and string.find(text, realUserId, 1, true) then
            text = string.gsub(text, realUserId, tostring(KhfreshState.fakeUserId or "0"))
            changed = true
        end
        if #realPlaceId >= 5 and string.find(text, realPlaceId, 1, true) then
            text = string.gsub(text, realPlaceId, "0000000000")
            changed = true
        end
        local guidPat = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"
        if string.find(text, guidPat) then
            text = string.gsub(text, guidPat, "********-****-****-****-************")
            changed = true
        end
        return text, changed
    end

    local function applyFakeNameToAll()
        if not KhfreshState.fakeNameEnabled then return end
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            for _, v in ipairs(pg:GetDescendants()) do
                replaceTextInObject(v)
            end
        end
        local char = LocalPlayer.Character
        if char then
            for _, v in ipairs(char:GetDescendants()) do
                replaceTextInObject(v)
            end
        end
        pcall(function()
            local cg = game:GetService("CoreGui")
            if cg then
                for _, v in ipairs(cg:GetDescendants()) do
                    replaceTextInObject(v)
                end
            end
        end)
    end

    function KhfreshState.enableFakeName()
        if KhfreshState.fakeNameEnabled then return end
        KhfreshState.fakeNameEnabled = true
        applyFakeNameToAll()

        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            fakeNameConn = pg.DescendantAdded:Connect(function(desc)
                if KhfreshState.fakeNameEnabled then
                    task.wait(0.05)
                    replaceTextInObject(desc)
                end
            end)
        end

        KhfreshLib:Notify({ Title = "Streamer Mode", Message = "Fake name active: " .. tostring(KhfreshState.fakeName), Duration = 2 })
    end

    function KhfreshState.disableFakeName()
        KhfreshState.fakeNameEnabled = false
        if fakeNameConn then
            fakeNameConn:Disconnect(); fakeNameConn = nil
        end
        if fakeNameThread then
            task.cancel(fakeNameThread); fakeNameThread = nil
        end
        KhfreshLib:Notify({ Title = "Streamer Mode", Message = "Fake name disabled", Duration = 2 })
    end
end

-- Chong "cau tren troi": khi dang bay / vua teleport, player lo lung tren khong
-- nen phao khong roi trung nuoc -> cast phi hoai. Raycast xuong kiem tra nuoc.
local function isWaterHit(hit)
    if not hit then return false end
    if hit.Instance == Workspace.Terrain and hit.Material == Enum.Material.Water then
        return true
    end
    local n = string.lower(tostring(hit.Instance and hit.Instance.Name or ""))
    if string.find(n, "water", 1, true) or string.find(n, "ocean", 1, true) or string.find(n, "sea", 1, true) or string.find(n, "lake", 1, true) then
        return true
    end
    return false
end

-- Scan a grid around origin for real water. Returns stand CFrame on water, or nil.
function KhfreshState.findWaterNear(origin, maxRadius)
    origin = typeof(origin) == "Vector3" and origin or (typeof(origin) == "CFrame" and origin.Position or nil)
    if not origin then return nil end
    maxRadius = tonumber(maxRadius) or 80

    local char = LocalPlayer.Character
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { char }
    params.IgnoreWater = false

    local function probe(x, z)
        local from = Vector3.new(x, origin.Y + 80, z)
        local hit = Workspace:Raycast(from, Vector3.new(0, -250, 0), params)
        if isWaterHit(hit) then
            -- Stand slightly above water surface
            return CFrame.new(hit.Position + Vector3.new(0, 3.2, 0))
        end
        return nil
    end

    -- Center first
    local cf = probe(origin.X, origin.Z)
    if cf then return cf end

    -- Expanding rings
    for r = 6, maxRadius, 6 do
        local steps = math.max(8, math.floor(r / 3))
        for i = 0, steps - 1 do
            local ang = (i / steps) * math.pi * 2
            cf = probe(origin.X + math.cos(ang) * r, origin.Z + math.sin(ang) * r)
            if cf then return cf end
        end
    end
    return nil
end

function KhfreshState.isOverWater()
    local ok, result = pcall(function()
        local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not root then return false end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { LocalPlayer.Character }
        params.IgnoreWater = false
        local hit = Workspace:Raycast(root.Position + Vector3.new(0, 5, 0), Vector3.new(0, -120, 0), params)
        return isWaterHit(hit)
    end)
    if not ok then return false end
    return result == true
end


-- Move player onto water near a point (island or current pos). Returns true if on water.
function KhfreshState.ensureOnWater(nearPos)
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    if KhfreshState.isOverWater() then return true end

    local searchFrom = nearPos or root.Position
    local waterCF = KhfreshState.findWaterNear(searchFrom, 100)
    if not waterCF then
        -- fallback: search from current position
        waterCF = KhfreshState.findWaterNear(root.Position, 60)
    end
    if waterCF then
        root.CFrame = waterCF
        return true
    end
    return false
end

-- ===== UNIVERSAL BAIT MERCHANT LOCATOR =====
local function findBaitMerchantHRP()
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local myPos = root and root.Position or Vector3.new(0, 0, 0)
    local bestHRP = nil
    local bestDist = math.huge

    pcall(function()
        local npcFolder = Workspace:FindFirstChild("NPC")
        if npcFolder then
            local bb = npcFolder:FindFirstChild("BuyBait")
            if bb then
                for _, model in ipairs(bb:GetChildren()) do
                    if model:IsA("Model") then
                        local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or
                        model.PrimaryPart
                        if hrp then
                            local dist = (hrp.Position - myPos).Magnitude
                            if dist < bestDist then
                                bestDist = dist
                                bestHRP = hrp
                            end
                        end
                    end
                end
            end
            local func = npcFolder:FindFirstChild("Function")
            if func then
                for _, model in ipairs(func:GetChildren()) do
                    if model:IsA("Model") and (string.find(model.Name:lower(), "bait") or string.find(model.Name:lower(), "shop") or string.find(model.Name:lower(), "merchant")) then
                        local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or
                        model.PrimaryPart
                        if hrp then
                            local dist = (hrp.Position - myPos).Magnitude
                            if dist < bestDist then
                                bestDist = dist
                                bestHRP = hrp
                            end
                        end
                    end
                end
            end
            if not bestHRP then
                for _, desc in ipairs(npcFolder:GetDescendants()) do
                    if desc:IsA("Model") and string.find(desc.Name:lower(), "bait") then
                        local hrp = desc:FindFirstChild("HumanoidRootPart") or desc:FindFirstChild("Torso") or
                        desc.PrimaryPart
                        if hrp then
                            local dist = (hrp.Position - myPos).Magnitude
                            if dist < bestDist then
                                bestDist = dist
                                bestHRP = hrp
                            end
                        end
                    end
                end
            end
        end
    end)
    return bestHRP
end

-- ===== SELECTED FISH FARM — SINGLE SOURCE OF TRUTH =====
-- Selected Fish flow is isolated from Boss Farm / normal Auto Farm.
-- SOURCE OF TRUTH FOR FISH VALIDATION:
--   MainGui > Fishing > ProgressionBar > FishName
--
-- Runtime flow:
--   1) teleport to selected island
--   2) equip fishing rod
--   3) cast once
--   4) wait for the real minigame start
--   5) read ProgressionBar > FishName
--   6) exact normalized match -> keep + UpdateFishProgression
--   7) wrong name -> cancel that cast only
--   8) after completion, stay on the island until EVERY selected fish for that
--      island has been caught once; only then advance to the next selected island.

local function normalizeSelectedFishName(name)
    name = tostring(name or "")
    name = name:gsub("<[^>]+>", "")
    -- Dropdown labels and ProgressionBar can use: "Fish Name | Isle N"
    -- The island suffix is presentation only and NEVER participates in matching.
    name = name:gsub("%s*|%s*[Ii]sle%s*%d+%s*$", "")
    name = name:gsub("^%s*(.-)%s*$", "%1")
    name = name:gsub("%s+", " ")
    return string.lower(name)
end

local function getSelectedFishNameLabel()
    local fishing = MainGui and MainGui:FindFirstChild("Fishing")
    local progression = fishing and fishing:FindFirstChild("ProgressionBar")
    return progression and progression:FindFirstChild("FishName")
end

local function readProgressFishName()
    local label = getSelectedFishNameLabel()
    if not label then return "" end
    local raw = tostring(label.Text or "")
    raw = raw:gsub("<[^>]+>", "")
    return normalizeSelectedFishName(raw)
end

local function isSelectedFishPlaceholder(name)
    return name == "" or name == "???" or name == "?" or name == "nil" or name == "none"
end

-- ===== AUTO FARM HELPERS =====
-- Check whether Auto Farm Boss is enabled
local function bossFarmEnabled()
    return KhfreshState.Fishing.Flags.AutoFarmBoss or KhfreshState.Fishing.Flags.AutoFarmSecretBoss
end

-- Reset Boss Farm state
local function resetBossFarmTarget()
    KhfreshState.Fishing.BossFarm.CurrentTarget = nil
    KhfreshState.Fishing.BossFarm.CurrentType = nil
    KhfreshState.Fishing.BossFarm.CurrentToken = nil
    KhfreshState.Fishing.BossFarm.HasHooked = false
    KhfreshState.Fishing.BossFarm.PendingCancel = false
end

-- Read info about the target currently biting
local function getCurrentHookTarget()
    local target = KhfreshState.Fishing.BossFarm.CurrentTarget
    local info = { Name = nil, Data = nil, Instance = nil, Boss = false, SecretBoss = false }

    if type(target) == "table" then
        info.Data = target
        info.Name = target.FishName or target.Name or target.fishName
        info.Boss = target.Boss == true or target.SpecialBoss == true or target.SecretBoss == true
        info.SecretBoss = target.SecretBoss == true
    elseif typeof and typeof(target) == "Instance" then
        info.Instance = target
        info.Name = target:GetAttribute("FishName") or target.Name
        info.Boss = target:GetAttribute("Boss") == true or target:GetAttribute("SpecialBoss") == true or
        target:GetAttribute("SecretBoss") == true
        info.SecretBoss = target:GetAttribute("SecretBoss") == true
    elseif type(target) == "string" then
        info.Name = target
    end

    local fishId = LocalPlayer:GetAttribute("FishID")
    local fishes = Workspace:FindFirstChild("Fishes")
    local fishInstance = fishId and fishes and fishes:FindFirstChild(tostring(fishId))

    if fishInstance then
        info.Instance = fishInstance
        info.Name = info.Name or fishInstance:GetAttribute("FishName") or fishInstance.Name
        info.Boss = info.Boss or fishInstance:GetAttribute("Boss") == true or
        fishInstance:GetAttribute("SpecialBoss") == true or fishInstance:GetAttribute("SecretBoss") == true
        info.SecretBoss = info.SecretBoss or fishInstance:GetAttribute("SecretBoss") == true
    end

    local fishingGui = MainGui:FindFirstChild("Fishing")
    local progression = fishingGui and fishingGui:FindFirstChild("ProgressionBar")
    local fishNameLabel = progression and progression:FindFirstChild("FishName")

    if (not info.Name or info.Name == "" or info.Name == "???") and fishNameLabel and fishNameLabel.Text ~= "" then
        info.Name = fishNameLabel.Text
    end

    return info
end

local function textHasKeyword(text, keywords)
    text = string.lower(tostring(text or ""))
    for _, keyword in ipairs(keywords) do
        if string.find(text, keyword, 1, true) then return true end
    end
    return false
end

-- Check whether the target is a Secret Boss
local function isSecretBossTarget(target)
    local current = target or getCurrentHookTarget()
    local name = string.lower(tostring(current.Name or ""))
    return current.SecretBoss or KhfreshState.SecretBossNameSet[name] or
    textHasKeyword(name, KhfreshState.SecretBossKeywords)
end

-- Check whether the target is a Boss
local function isBossTarget(target)
    local current = target or getCurrentHookTarget()
    local name = string.lower(tostring(current.Name or ""))
    if isSecretBossTarget(current) then return true end
    return current.Boss or KhfreshState.BossNameSet[name] or textHasKeyword(name, KhfreshState.BossKeywords)
end

-- Decide whether this target should be farmed
local function shouldFarmBossTarget(target)
    local current = target or getCurrentHookTarget()
    if isSecretBossTarget(current) then return true, "Secret Boss" end
    if KhfreshState.Fishing.Flags.AutoFarmSecretBoss and not KhfreshState.Fishing.Flags.AutoFarmBoss then return false,
            "Normal" end
    if KhfreshState.Fishing.Flags.AutoFarmBoss and isBossTarget(current) then return true, "Boss" end
    return false, "Normal"
end

-- Cancel the cast or release a common fish (boss farm only)
local function cancelOrReleaseNormalFish()
    if KhfreshState.SelectedAutoFarmFishRunning == true then return false end
    if not bossFarmEnabled() then return false end
    local character = LocalPlayer.Character
    if not character then return false end
    if not character:GetAttribute("Fishing") then
        resetBossFarmTarget(); return true
    end

    KhfreshState.Fishing.BossFarm.PendingCancel = true

    pcall(function()
        local fishingGui = MainGui:FindFirstChild("Fishing")
        local barFrame = fishingGui and fishingGui:FindFirstChild("BarFrame")
        local bar = barFrame and barFrame:FindFirstChild("Bar")
        if bar then bar.Position = UDim2.new(-0.15, 0, bar.Position.Y.Scale, bar.Position.Y.Offset) end
    end)

    if KhfreshState.Fishing.BossFarm.CurrentToken and tick() - KhfreshState.Fishing.BossFarm.LastFastCancel > 0.5 then
        KhfreshState.Fishing.BossFarm.LastFastCancel = tick()
        pcall(function() safeFire("FishingMinigame", false, KhfreshState.Fishing.BossFarm.CurrentToken) end)
    end

    if not character:GetAttribute("Retractable") then return false end
    if tick() - KhfreshState.Fishing.BossFarm.LastCancel < 0.35 then return false end

    KhfreshState.Fishing.BossFarm.LastCancel = tick()
    pcall(function()
        local root = character:FindFirstChild("HumanoidRootPart")
        if root then safeFire("Fishing", root.CFrame) end
    end)

    return false
end

-- textHasKeyword helper (if not defined yet)
if not textHasKeyword then
    local function textHasKeyword(text, keywords)
        text = string.lower(tostring(text or ""))
        for _, keyword in ipairs(keywords) do
            if string.find(text, keyword, 1, true) then return true end
        end
        return false
    end
end

local function loadBossNameSets()
    for k in pairs(KhfreshState.BossNameSet) do KhfreshState.BossNameSet[k] = nil end
    for k in pairs(KhfreshState.SecretBossNameSet) do KhfreshState.SecretBossNameSet[k] = nil end
    local infoFolder = ReplicatedStorage:FindFirstChild("Info")
    if not infoFolder then return end

    pcall(function()
        local areaRarity = infoFolder:FindFirstChild("FishingAreaRarity")
        if areaRarity then
            local rarityData = require(areaRarity)
            if type(rarityData) == "table" and type(rarityData["Secret Boss"]) == "table" then
                for fishName in pairs(rarityData["Secret Boss"]) do
                    local name = string.lower(tostring(fishName))
                    KhfreshState.SecretBossNameSet[name] = true
                    KhfreshState.BossNameSet[name] = true
                end
            end
        end
    end)

    pcall(function()
        local inventory = infoFolder:FindFirstChild("Inventory")
        if inventory then
            for _, module in pairs(inventory:GetChildren()) do
                if module:IsA("ModuleScript") then
                    local ok, itemData = pcall(require, module)
                    if ok and type(itemData) == "table" then
                        local name = string.lower(tostring(itemData.FishName or module.Name))
                        if itemData.Boss == true or itemData.SpecialBoss == true or itemData.SecretBoss == true then
                            KhfreshState.BossNameSet[name] = true
                        end
                        if itemData.SecretBoss == true then
                            KhfreshState.SecretBossNameSet[name] = true
                        end
                    end
                end
            end
        end
    end)
end
task.defer(loadBossNameSets)

-- ===== BUILD MAIN UI (reuse early Window if present) =====
runtimeEnv.KhfreshStage("dung UI")
setKhfreshLoadProgress(72, "Building Bento tabs...")
if not Window then
    local winOk, winOrErr = pcall(function()
        return KhfreshLib:CreateWindow({
            Title = "Khfresh Hub",
            Icon = "layout-dashboard",
            Author = "by Ngmankhoi x Khfresh",
            Theme = "Bento",
            Size = UDim2.fromOffset(initialW, initialH),
            PerformanceProfile = "Auto",
            Keybind = Enum.KeyCode.RightAlt,
        })
    end)
    if not winOk or not winOrErr then
        warn("[Khfresh] CreateWindow error: " .. tostring(winOrErr))
        setKhfreshLoadProgress(100, "Window failed")
        pcall(closeKhfreshLoadingScreen)
        return
    end
    Window = winOrErr
    print("[Khfresh] Late window created OK")
end
for _ = 1, 4 do task.wait() end

local Fishing = KhfreshState.Fishing
local MiscFlags = KhfreshState.MiscFlags

-- Forward declarations used by UI callbacks created before the implementations.
local initAntiAFK
local stopAntiAFK
local initAntiBan
local stopAntiBan
local ticketGoFire
local runTicketQuestDialogue

-- Snapshot every UI control with a persistent value. The UI library exposes
-- toggle/dropdown/slider/textbox state through _ConfigControls.
local khSnapshotUIControls

khSnapshotUIControls = function()
    local registry = KhfreshLib and KhfreshLib._ConfigControls
    if type(registry) ~= "table" then return end
    local out = { Toggles = {}, Values = {} }
    for name, entry in pairs(registry) do
        if type(entry) == "table" then
            local kind, control = entry.Kind, entry.Control
            if kind == "toggle" and control and control.Get then
                out.Toggles[name] = control:Get() == true
            elseif (kind == "dropdown" or kind == "multidropdown" or kind == "slider") and control and control.Get then
                local value = control:Get()
                if type(value) == "table" then
                    local copy = {}
                    for i, v in ipairs(value) do copy[i] = v end
                    out.Values[name] = copy
                else
                    out.Values[name] = value
                end
            elseif kind == "textbox" and control then
                out.Values[name] = tostring(control.Text or "")
            end
        end
    end
    KhfreshUserConfig.UIControls = out
end

local function khApplyRuntimeConfig()
    local cfg = KhfreshUserConfig or {}
    Fishing.Flags.SelectedSkills = (function()
        local t = type(cfg.SelectedSkills) == "table" and cfg.SelectedSkills or {}
        return {Z = t.Z ~= false, X = t.X ~= false, C = t.C ~= false, V = t.V ~= false}
    end)()
    Fishing.Flags.AntiAFK = cfg.AntiAFK ~= false
    KhfreshState.AutoFarm.filters.Boss = cfg.AutoFarmBoss == true
    KhfreshState.AutoFarm.filters.SecretBoss = cfg.AutoFarmSecretBoss == true
    KhfreshState.AutoFarm.filters.AntiAFK = cfg.AntiAFK ~= false
    KhfreshState.ticketTeleportToGiver = true
    KhfreshState.currentLanguage = cfg.Language or "auto"
    KhfreshState.autoExecuteOnHop = cfg.AutoExecute == true or (cfg.meta and cfg.meta.autoExecute == true)
    KhfreshState.AutoEquipMethod = cfg.AutoEquipMethod == "Best Rod" and "Best Rod" or "Default"
    KhfreshState.AutoEnzoFightMode = (cfg.AutoEnzoFightMode == "Hard" or cfg.AutoEnzoFightMode == "Nightmare")
        and cfg.AutoEnzoFightMode or "Normal"
    KhfreshState.AutoLongDiaohaiFightMode =
        (cfg.AutoLongDiaohaiFightMode == "Hard" or cfg.AutoLongDiaohaiFightMode == "Nightmare")
        and cfg.AutoLongDiaohaiFightMode or "Normal"
    KhfreshState.AutoEnzoHitCooldown = math.clamp(tonumber(cfg.AutoEnzoHitCooldown) or 0.15, 0.01, 1)
    KhfreshState.AutoLongDiaohaiHitCooldown = math.clamp(tonumber(cfg.AutoLongDiaohaiHitCooldown) or 0.15, 0.01, 1)
    KhfreshState.NamelessNoteFallSpeed = math.clamp(tonumber(cfg.NamelessNoteFallSpeed) or 2, 1, 10)
    KhfreshState.WeatherHop.enabled = cfg.WeatherHopEnabled == true
    KhfreshState.WeatherHop.target = tostring(cfg.WeatherHopTarget or "Thunderstorm")
    KhfreshState.WeatherHop.triedServers = type(cfg.WeatherHopTriedServers) == "table"
        and cfg.WeatherHopTriedServers or {}
    KhfreshState.EventHop.enabled = cfg.EventHopEnabled == true
    KhfreshState.EventHop.target = tostring(cfg.EventHopTarget or "Taoist")
    KhfreshState.EventHop.triedServers = type(cfg.EventHopTriedServers) == "table"
        and cfg.EventHopTriedServers or {}
    -- Auto Save removed — manual Save Config only
    khAutoSaveEnabled = false
    KhfreshState.antiBanEnabled = true
    if type(cfg.SmartWeather) == "table" then
        KhfreshState.SmartWeather.selectedIslands = {
            ["Island 2"] = true, ["Island 3"] = true, ["Island 5"] = true,
            ["Island 6"] = true, ["Island 7"] = true, ["Island 8"] = true,
            ["Island 9"] = true, ["Island 12"] = true, ["Island 13"] = true,
        }
        for island, enabled in pairs(cfg.SmartWeather) do
            KhfreshState.SmartWeather.selectedIslands[island] = enabled == true
        end
        if type(cfg.WeatherIslandNames) == "table" then
            KhfreshState.SmartWeather.weatherNames = {}
            for island, weatherName in pairs(cfg.WeatherIslandNames) do
                KhfreshState.SmartWeather.weatherNames[island] = tostring(weatherName or ""):lower()
            end
        end
    end
    if type(cfg.SelectedAutoFarmFish) == "table" then
        KhfreshState.selectedAutoFarmFish = cfg.SelectedAutoFarmFish
    end
end

-- Snapshot every important live setting before writing. This is deliberately
-- independent from the UI library's internal config system so it also works when a
-- control callback does not expose its value to Redz's own saver.
local function khSnapshotRuntimeConfig()
    KhfreshUserConfig.SelectedSkills = Fishing.Flags.SelectedSkills or KhfreshUserConfig.SelectedSkills or {Z=true,X=true,C=true,V=true}
    KhfreshUserConfig.SelectedAutoFarmFish = KhfreshState and KhfreshState.selectedAutoFarmFish or KhfreshUserConfig.SelectedAutoFarmFish or {}
    KhfreshUserConfig.AutoFarm = Fishing.Flags.MainFarm == true
    KhfreshUserConfig.AutoCast = Fishing.Flags.AutoCast == true
    KhfreshUserConfig.AutoSkill = Fishing.Flags.AutoFarmSkill == true
    KhfreshUserConfig.AutoFarmBoss = Fishing.Flags.AutoFarmBoss == true
    KhfreshUserConfig.AutoFarmSecretBoss = Fishing.Flags.AutoFarmSecretBoss == true
    KhfreshUserConfig.AntiAFK = Fishing.Flags.AntiAFK ~= false
    KhfreshUserConfig.AutoTicket = Fishing.Flags.AutoTicket == true
    KhfreshUserConfig.AutoSell = MiscFlags.AutoSell == true
    KhfreshUserConfig.AutoBuy = MiscFlags.AutoBuy == true
    KhfreshUserConfig.TicketTeleportToGiver = KhfreshState.ticketTeleportToGiver == true
    KhfreshUserConfig.Language = KhfreshState.currentLanguage or KhfreshUserConfig.Language
    KhfreshUserConfig.autoExecute = KhfreshState.autoExecuteOnHop == true
    KhfreshUserConfig.AutoExecute = KhfreshState.autoExecuteOnHop == true
    KhfreshUserConfig.AutoEnzoHitCooldown = KhfreshState.AutoEnzoHitCooldown
    KhfreshUserConfig.AutoLongDiaohaiHitCooldown = KhfreshState.AutoLongDiaohaiHitCooldown
    KhfreshUserConfig.AutoEnzoFightMode = KhfreshState.AutoEnzoFightMode
    KhfreshUserConfig.AutoLongDiaohaiFightMode = KhfreshState.AutoLongDiaohaiFightMode
    KhfreshUserConfig.NamelessNoteFallSpeed = KhfreshState.Rhythm
        and KhfreshState.Rhythm.FallSpeed or KhfreshState.NamelessNoteFallSpeed
    KhfreshUserConfig.ServerHopMode = "Least Players"
    KhfreshUserConfig.meta = KhfreshUserConfig.meta or {}
    KhfreshUserConfig.meta.autoExecute = KhfreshUserConfig.autoExecute
    KhfreshUserConfig.meta.lastSnapshot = os.time()
    KhfreshUserConfig.AntiBan = KhfreshState.antiBanEnabled == true
    if khSnapshotUIControls then
        khSnapshotUIControls()
        local u = KhfreshUserConfig.UIControls or {}
        local t = u.Toggles or {}
        local map = {
            AutoFarm = "Enable Auto Farm Fish",
            AutoFarmBoss = "Auto Farm Boss",
            AutoFarmSecretBoss = "Auto Farm Secret Boss",
            AntiAFK = "Anti AFK",
            AutoSell = "Auto Sell Fish",
            AutoEnzo = "Auto Enzo",
            AutoSkill = "Auto Skill",
            AutoEquipBait = "Auto Equip Best Bait",
            AutoNameless = "Auto Nameless",
            AutoFavourite = "Auto Favourite Fishes",
            PraySpirit = "Auto Teleport + Interact (Pray) Spirit",
            AutoFarmSelectedFish = "Enable Auto Farm Selected Fish",
            AutoCraftRod = "Auto craft selected rod",
            AutoBuyBait = "Auto Buy Bait",
            AutoCraftBait = "Auto craft bait",
            AutoGacha = "Auto Gacha",
            AutoClaimTicketQuest = "Auto Claim Ticket Quest (Fast)",
            AutoDoTicketQuest = "Auto Do Ticket Quest (Fast)",
            AutoDoDailyQuest = "Auto Do Daily Quest",
            AutoFarmBaitMaterials = "Auto fish for bait materials",
            AutoRecommendIsland = "Teleport to Recommend Island",
            AutoAscend = "Auto Ascend",
            AutoGiveFish2M = "Auto Give Fish > 2M kg",
            AutoFarm2M = "Auto Farm 2M+ kg Fish",
            FlyMode = "Fly Mode",
            Noclip = "Noclip",
            InfiniteJump = "Infinite Jump",
            WalkOnWater = "Walk On Water",
            FullBright = "Full Bright",
            NotificationsEnabled = "Enable Notifications",
            FakeNameDisplay = "Fake Name Display",
            AntiReport = "Anti-Report Khfresh Users",
            AntiKick = "Anti-Kick Shield",
            AntiDetection = "Anti-Detection Metamethod",
            AntiBan = "Anti-Ban (BanPlayer Remote)",
            StaffWatch = "Enable Staff Watch",
        }
        for key, controlName in pairs(map) do
            if t[controlName] ~= nil then
                KhfreshUserConfig[key] = t[controlName] == true
            end
        end
    end
    if KhfreshState.SmartWeather and KhfreshState.SmartWeather.selectedIslands then
        KhfreshUserConfig.SmartWeather = KhfreshState.SmartWeather.selectedIslands
    end
end

local function khSnapshotAndSave(reason)
    if KhfreshLib and KhfreshLib._ApplyingConfig then return true, nil end
    khSnapshotRuntimeConfig()
    khGetGlobalEnv().__KhfreshUserConfig = KhfreshUserConfig
    return true, nil
end

khApplyRuntimeConfig()

-- ===== SHARED HELPERS (DECLARED UP FRONT) =====

-- ===== HUB VISIBILITY CONTROL =====
-- The embedded Bento-style window owns the floating K toggle and PC hotkey.
-- Do not create a second floating ScreenGui here; duplicate hitboxes were the
-- source of the mouse-jump / stuck-dropdown behavior in older builds.

local function GetPlayerData()
    if not Data then return nil end
    return Data:FindFirstChild(tostring(LocalPlayer.UserId))
end

local function GetModule(folder, name)
    local m = folder:FindFirstChild(name)
    if m then
        local ok, mod = pcall(require, m)
        if ok and type(mod) == "table" then return mod end
    end
    return nil
end

local function GetAvailableBaits()
    local p = GetPlayerData()
    if not p then return {} end
    local baits = {}
    local baitFolder = p:FindFirstChild("Bait")
    if not baitFolder then return {} end
    for _, b in pairs(baitFolder:GetChildren()) do
        if b:IsA("NumberValue") and b.Value > 0 then
            table.insert(baits, b.Name)
        end
    end
    return baits
end

local function GetBaitStats(baitName)
    local mod = GetModule(Info.Bait, baitName)
    if mod then return { Luck = mod.Luck or 0 } end
    return { Luck = 0 }
end

local function GetBestBait()
    local baits = GetAvailableBaits()
    local best, bestLuck = nil, -1
    for _, name in ipairs(baits) do
        local s = GetBaitStats(name)
        if s.Luck > bestLuck then
            bestLuck = s.Luck; best = name
        end
    end
    return best
end

local function EquipBait(baitName)
    if not baitName then return false end
    return pcall(function() safeInvoke("EquipBait", baitName) end)
end

local function GetOwnedRods()
    local p = GetPlayerData()
    if not p then return {} end
    local rods = {}
    for _, f in pairs(p.FishingRodInventory:GetChildren()) do
        if f:IsA("Folder") and f.Owned and f.Owned.Value == true then
            table.insert(rods, f.Name)
        end
    end
    return rods
end

local function GetRodStats(rodName)
    local mod = GetModule(Info.Inventory, rodName)
    if mod then return { Power = mod.Power or 0, Luck = mod.Luck or 0 } end
    return { Power = 0, Luck = 0 }
end

local function GetBestRod()
    local rods = GetOwnedRods()
    local best, bestScore = nil, -1
    for _, name in ipairs(rods) do
        local s = GetRodStats(name)
        local score = s.Power + s.Luck
        if score > bestScore then
            bestScore = score; best = name
        end
    end
    return best
end

local function EquipRod(rodName)
    if not rodName then return false end
    return pcall(function() safeInvoke("EquipFishingRod", rodName) end)
end

local function GetAvailableOrbs()
    local p = GetPlayerData()
    if not p then return {} end
    local orbs = {}
    local orbFolder = p:FindFirstChild("Orb")
    if not orbFolder then return {} end
    for _, f in pairs(orbFolder:GetChildren()) do
        if f:IsA("Folder") then
            local eq = f:FindFirstChild("Equipping")
            if eq and eq.Value == false then
                table.insert(orbs, f.Name)
            end
        end
    end
    return orbs
end

local function GetOrbStats(orbName)
    local p = GetPlayerData()
    if not p then return {} end
    local f = p.Orb:FindFirstChild(orbName)
    if not f then return {} end
    local stats = {}
    for _, child in pairs(f:GetChildren()) do
        if child:IsA("NumberValue") and child.Name ~= "Equipping" and child.Name ~= "Favorite" then
            stats[child.Name] = child.Value
        end
    end
    return stats
end

local function GetBestOrb()
    local orbs = GetAvailableOrbs()
    local best, bestScore = nil, -1
    for _, name in ipairs(orbs) do
        local s = GetOrbStats(name)
        local score = (s.Damage or 0) * 2 + (s.Luck or 0) * 1.5 + (s.Cash or 0) * 0.5
        if score > bestScore then
            bestScore = score; best = name
        end
    end
    return best
end

local function EquipOrb(orbName)
    if not orbName then return false end
    return pcall(function() safeInvoke("EquipOrb", orbName) end)
end

local function GetBuyableBaits()
    local baits = {}
    if not Info or not Info:FindFirstChild("Bait") then return { "No bait available" } end
    for _, child in pairs(Info.Bait:GetChildren()) do
        if child:IsA("ModuleScript") then
            local success, mod = pcall(require, child)
            if success and type(mod) == "table" and mod.Price and mod.Price > 0 then
                table.insert(baits, child.Name)
            end
        end
    end
    if #baits == 0 then return { "No bait available" } end
    return baits
end

local function saveRoutineFlags()
    KhfreshState.savedRoutineFlags = {
        AutoCast = Fishing.Flags.AutoCast,
        AnchorLock = Fishing.Flags.AnchorLock,
        AutoSkill = Fishing.Flags.AutoSkill,
        AutoSell = MiscFlags.AutoSell,
        AutoSkillCheck = Fishing.Flags.AutoSkillCheck,
        AntiAFK = Fishing.Flags.AntiAFK,
        AutoFarmBoss = Fishing.Flags.AutoFarmBoss,
        AutoFarmSecretBoss = Fishing.Flags.AutoFarmSecretBoss,
        AutoBuy = MiscFlags.AutoBuy,
        AutoEquipBait = MiscFlags.AutoEquipBait,
        AutoEquipRod = MiscFlags.AutoEquipRod,
    }
end

local function restoreRoutineFlags()
    if KhfreshState.savedRoutineFlags then
        Fishing.Flags.AutoCast = KhfreshState.savedRoutineFlags.AutoCast
        Fishing.Flags.AnchorLock = KhfreshState.savedRoutineFlags.AnchorLock
        Fishing.Flags.AutoSkill = KhfreshState.savedRoutineFlags.AutoSkill
        MiscFlags.AutoSell = KhfreshState.savedRoutineFlags.AutoSell
        Fishing.Flags.AutoSkillCheck = KhfreshState.savedRoutineFlags.AutoSkillCheck
        Fishing.Flags.AntiAFK = KhfreshState.savedRoutineFlags.AntiAFK
        Fishing.Flags.AutoFarmBoss = KhfreshState.savedRoutineFlags.AutoFarmBoss
        Fishing.Flags.AutoFarmSecretBoss = KhfreshState.savedRoutineFlags.AutoFarmSecretBoss
        MiscFlags.AutoBuy = KhfreshState.savedRoutineFlags.AutoBuy
        MiscFlags.AutoEquipBait = KhfreshState.savedRoutineFlags.AutoEquipBait
        MiscFlags.AutoEquipRod = KhfreshState.savedRoutineFlags.AutoEquipRod
        KhfreshState.savedRoutineFlags = nil
    else
        Fishing.Flags.AutoFarmBoss = false
        Fishing.Flags.AutoFarmSecretBoss = false
    end
end

local function isRodTool(tool)
    if not tool or not tool:IsA("Tool") then return false end
    local typ = tostring(tool:GetAttribute("Type") or ""):lower()
    local name = tool.Name:lower()
    if typ:find("fishing rod", 1, true) or typ == "fishingrod" then return true end
    if name:find("rod", 1, true) or name:find("cần", 1, true) then return true end
    return false
end

local function isCurrentlyHoldingRod()
    local char = LocalPlayer.Character
    if not char then return false end
    -- Attribute used by game
    local typ = char:GetAttribute("Type")
    if typ and string.lower(tostring(typ)):find("fishing rod", 1, true) then return true end
    -- Tool parented to character
    for _, child in ipairs(char:GetChildren()) do
        if isRodTool(child) then return true end
    end
    return false
end

local function ensureRodEquipped()
    if isCurrentlyHoldingRod() then return true end

    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

    -- 1) Equip tool already in backpack
    if hum and backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if isRodTool(tool) then
                pcall(function() hum:EquipTool(tool) end)
                task.wait(0.2)
                if isCurrentlyHoldingRod() then return true end
            end
        end
    end

    -- 2) Equip best rod via remote (puts rod into hotbar/inventory state)
    local best = GetBestRod()
    if best then
        pcall(function() EquipRod(best) end)
        task.wait(0.35)
        -- Try backpack again after remote
        backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum and backpack then
            for _, tool in ipairs(backpack:GetChildren()) do
                if isRodTool(tool) then
                    pcall(function() hum:EquipTool(tool) end)
                    task.wait(0.2)
                    if isCurrentlyHoldingRod() then return true end
                end
            end
        end
    end

    -- 3) Nexus-style: ToggleHotbar slot 1 (main method that works in-game)
    local toggleHotbar = Events and Events:FindFirstChild("ToggleHotbar")
    if toggleHotbar then
        pcall(function()
            if toggleHotbar:IsA("RemoteFunction") then
                toggleHotbar:InvokeServer("1", nil)
            elseif toggleHotbar:IsA("RemoteEvent") then
                toggleHotbar:FireServer("1", nil)
            end
        end)
        task.wait(0.25)
        if isCurrentlyHoldingRod() then return true end
        -- Some servers use number 1 not string
        pcall(function()
            if toggleHotbar:IsA("RemoteFunction") then
                toggleHotbar:InvokeServer(1, nil)
            end
        end)
        task.wait(0.2)
    end

    return isCurrentlyHoldingRod()
end

-- Equip rod ONCE when feature turns on (no spam / no block inventory)
local function forceEquipRodOnce()
    if isCurrentlyHoldingRod() then return true end
    if KhfreshState.AutoEquipMethod == "Best Rod" then
        local ok, err = pcall(ensureRodEquipped)
        if not ok then warn("[Khfresh][AutoEquip] Best Rod failed:", tostring(err)) end
    else
        local ok, err = pcall(function()
            local vim = game:GetService("VirtualInputManager")
            vim:SendKeyEvent(true, Enum.KeyCode.One, false, game)
            vim:SendKeyEvent(false, Enum.KeyCode.One, false, game)
        end)
        if not ok then warn("[Khfresh][AutoEquip] Default key 1 failed:", tostring(err)) end
        task.wait(0.2)
    end
    return isCurrentlyHoldingRod()
end

local function enableBasicFishing(enableSkill)
    -- Only apply once per ticket-farm session so UI toggles can turn features OFF
    if KhfreshState._ticketFishingApplied then
        if enableSkill == true and Fishing.Flags.AutoSkill ~= true then
            Fishing.Flags.AutoSkill = true
        end
        return
    end
    KhfreshState._ticketFishingApplied = true
    if not KhfreshState.savedRoutineFlags then saveRoutineFlags() end
    Fishing.Flags.MainFarm = true
    Fishing.Flags.AutoCast = true
    Fishing.Flags.AnchorLock = true
    if enableSkill == true then
        Fishing.Flags.AutoSkill = true
    end
    -- Do NOT force AntiAFK here — respect Settings toggle
    MiscFlags.AutoEquipRod = true
    task.defer(function()
        pcall(forceEquipRodOnce)
    end)
end

local function disableAllFishing()
    KhfreshState._ticketFishingApplied = false
    restoreRoutineFlags()
end

-- Hard reset when toggling OFF — clear saved CF, stop threads, stop remote spam
local function khHardResetTicketQuestState()
    KhfreshState.autoDoRunning = false
    KhfreshState.ticketDailyDone = false
    KhfreshState.ticketQuestActive = false
    KhfreshState.ticketQuestClaimed = false
    KhfreshState.ticketTargetCount = 0
    KhfreshState.ticketCurrentCount = 0
    KhfreshState.ticketFailCount = 0
    KhfreshState.ticketLastFire = 0
    KhfreshState.ticketLastTurnIn = 0
    KhfreshState.ticketFarmCFrame = nil
    KhfreshState.ticketObjectiveText = nil
    KhfreshState.isDoingUseBaitQuest = false
    KhfreshState._ticketFishingApplied = false
    -- Clear saved flags so restoreRoutineFlags cannot turn farm back ON
    KhfreshState.savedRoutineFlags = nil
    if KhfreshState.autoDoThread then
        pcall(function() task.cancel(KhfreshState.autoDoThread) end)
        KhfreshState.autoDoThread = nil
    end
    if KhfreshState.autoClaimThread then
        pcall(function() task.cancel(KhfreshState.autoClaimThread) end)
        KhfreshState.autoClaimThread = nil
    end
    pcall(function()
        Fishing.Flags.MainFarm = false
        Fishing.Flags.AutoCast = false
        Fishing.Flags.AutoSkill = false
        Fishing.Flags.AutoFarmBoss = false
        Fishing.Flags.AutoFarmSecretBoss = false
        Fishing.Flags.AutoSkillCheck = false
        Fishing.Flags.AnchorLock = false
        MiscFlags.AutoEquipRod = false
    end)
    pcall(function()
        if resetBossFarmTarget then resetBossFarmTarget() end
    end)
    print("[Khfresh][TicketQuest] HARD RESET — state cleared, threads stopped")
end

local function khHardResetAutoFarmState()
    local AutoFarm = KhfreshState.AutoFarm
    if AutoFarm then
        AutoFarm.enabled = false
        AutoFarm.inYourPosition = false
        AutoFarm.inYourPositionCFrame = nil
        AutoFarm.inYourPositionStartedFarm = false
        AutoFarm.teleported = false
        AutoFarm.oldPosition = nil
    end
    -- Clear saved positions only — DO NOT teleport character back
    KhfreshState.lastPosition = nil
    if not KhfreshState.autoDoRunning then
        KhfreshState.ticketFarmCFrame = nil
        KhfreshState._ticketFishingApplied = false
    end
    KhfreshState.savedRoutineFlags = nil
    pcall(function()
        Fishing.Flags.MainFarm = false
        Fishing.Flags.AutoCast = false
        Fishing.Flags.AnchorLock = false
        Fishing.Flags.AutoFarmBoss = false
        Fishing.Flags.AutoFarmSecretBoss = false
        MiscFlags.AutoEquipRod = false
    end)
    pcall(function()
        if resetBossFarmTarget then resetBossFarmTarget() end
    end)
    print("[Khfresh][AutoFarm] HARD RESET — flags cleared, stand still (no TP back)")
end


local function getTotalPower()
    local total = 0
    local char = LocalPlayer.Character
    if char then
        local stats = char:FindFirstChild("Stats")
        if stats then
            local rp = stats:FindFirstChild("RodPower")
            if rp and rp:IsA("NumberValue") then total = total + rp.Value end
            local fp = stats:FindFirstChild("FishPower")
            if fp and fp:IsA("NumberValue") then total = total + fp.Value end
        end
        local attr = char:GetAttribute("RodPower")
        if attr and type(attr) == "number" and attr > 0 and total == 0 then total = attr end
    end
    if total == 0 then
        local userId = LocalPlayer.UserId
        local userData = Data:FindFirstChild(tostring(userId))
        if userData then
            local rodNameValue = userData:FindFirstChild("FishingRod")
            if rodNameValue then
                local rodName = rodNameValue.Value
                if rodName and rodName ~= "" then
                    local rodModule = Info:FindFirstChild("Inventory") and Info.Inventory:FindFirstChild(rodName)
                    if rodModule then
                        local success, rodData = pcall(require, rodModule)
                        if success and type(rodData) == "table" then
                            total = rodData.Power or 0
                        end
                    end
                end
            end
        end
    end
    return total
end

local function getRecommendedIsland()
    local currentPower = getTotalPower()
    local eligible = {}
    for _, island in ipairs(KhfreshState.islands) do
        if (island.power or 0) <= currentPower then
            local resolved = island
            if not resolved.cframe and type(khResolveIslandEntry) == "function" then
                resolved = khResolveIslandEntry(island.name)
            end
            -- Never return a new-island placeholder without a live position.
            if resolved and resolved.cframe then
                table.insert(eligible, resolved)
            end
        end
    end
    table.sort(eligible, function(a, b) return (a.power or 0) > (b.power or 0) end)
    return eligible[2] or eligible[1]
end

local function isHoldingFishingRod()
    local char = LocalPlayer.Character
    if not char then return false end
    local typ = char:GetAttribute("Type")
    if typ and string.lower(tostring(typ)) == "fishing rod" then return true end
    return false
end

-- ===== SESSION / OVERVIEW =====
do
print("[Khfresh] Building Overview content...")
local SessionTab
do
    local ok, tabOrErr = pcall(function()
        return Window:CreateTab({Title="Home",Icon="house"})
    end)
    if not ok then
        warn("[Khfresh] Home tab failed: " .. tostring(tabOrErr))
        ok, tabOrErr = pcall(function()
            return Window:CreateTab({Title="Overview",Icon="layout-dashboard"})
        end)
    end
    if ok then
        SessionTab = tabOrErr
        print("[Khfresh] Session tab OK")
    end
end
if not SessionTab then
    warn("[Khfresh] Session tab missing — skip overview content")
else
    local function safeCopy(url,label)
        if setclipboard then
            pcall(setclipboard,url)
            KhfreshLib:Notify({Title=label,Content="Link copied to clipboard.",Icon="copy",Duration=2})
        else
            KhfreshLib:Notify({Title=label,Content=url,Icon="external-link",Duration=4})
        end
    end

    local __hwid = "N/A"
    pcall(function() __hwid = tostring(Services.RbxAnalyticsService:GetClientId()) end)
    SessionTab:CreateHeader({
        Title=tostring(LocalPlayer.DisplayName),
        Subtitle="@"..tostring(LocalPlayer.Name).."  •  HWID: "..string.sub(__hwid,1,18),
        Icon="user-round",
        Avatar = true,
    })
    SessionTab:CreateButton({
        Name="Copy HWID",
        Icon="copy",
        Callback=function()
            if setclipboard then pcall(setclipboard,__hwid); KhfreshLib:Notify({Title="HWID",Content="Copied.",Icon="copy",Duration=2}) end
        end
    })

    SessionTab:CreateSection({Title="Update log",Icon="history"})
    SessionTab:CreateHeader({
        Title="Khfresh Hub",
        Subtitle="Bento Grid UI • Overview • smoother navigation",
        Icon="sparkles"
    })
    SessionTab:CreateHeader({
        Title="UI Update",
        Subtitle="Session stats removed from Overview. Only profile, updates and social links remain.",
        Icon="panels-top-left"
    })
    SessionTab:CreateHeader({
        Title="Icon Update",
        Subtitle="Features now use specific Lucide icons.",
        Icon="shapes"
    })

    SessionTab:CreateSection({Title="Community",Icon="users-round"})
    SessionTab:CreateButton({
        Name="Discord",
        Icon="message-circle",
        Callback=function() safeCopy("https://discord.gg/WWyZqKw3yC","Discord") end
    })
    SessionTab:CreateButton({
        Name="YouTube",
        Icon="play",
        Callback=function() safeCopy("https://www.youtube.com/@unixfunni","YouTube") end
    })
    SessionTab:CreateButton({
        Name="TikTok",
        Icon="music-2",
        Callback=function() safeCopy("https://www.tiktok.com/@khangleminh001","TikTok") end
    })

    SessionTab:CreateSection({Title="About",Icon="info"})
    SessionTab:CreateHeader({
        Title="Khfresh Hub",
        Subtitle="by Ngmankhoi x Khfresh",
        Icon="badge-check"
    })
end

-- ===== MAIN TAB =====
do
    local FarmingTab = Window:CreateTab("Main")
    local ConfigSection = FarmingTab:CreateSection("Config")
    local BossDifficultySection = FarmingTab:CreateSection("Boss Fight Difficulty")
    BossDifficultySection:CreateDropdown({
        Name = "Enzo Fight Difficulty",
        Options = { "Normal", "Hard", "Nightmare" },
        Default = KhfreshState.AutoEnzoFightMode,
        Callback = function(value)
            KhfreshState.AutoEnzoFightMode =
                (value == "Hard" or value == "Nightmare") and value or "Normal"
            KhfreshUserConfig.AutoEnzoFightMode = KhfreshState.AutoEnzoFightMode
            khSnapshotAndSave("enzo fight mode")
        end
    })
    BossDifficultySection:CreateDropdown({
        Name = "Long Diaohai Fight Difficulty",
        Options = { "Normal", "Hard", "Nightmare" },
        Default = KhfreshState.AutoLongDiaohaiFightMode,
        Callback = function(value)
            KhfreshState.AutoLongDiaohaiFightMode =
                (value == "Hard" or value == "Nightmare") and value or "Normal"
            KhfreshUserConfig.AutoLongDiaohaiFightMode = KhfreshState.AutoLongDiaohaiFightMode
            khSnapshotAndSave("long diaohai fight mode")
        end
    })
    local AutoFarmFilters = KhfreshState.AutoFarm.filters

    ConfigSection:CreateToggle({
        Name = "Auto Farm Boss", Default = AutoFarmFilters.Boss == true,
        Callback = function(V)
            AutoFarmFilters.Boss = V == true
            Fishing.Flags.AutoFarmBoss = AutoFarmFilters.Boss
            if not AutoFarmFilters.Boss then resetBossFarmTarget() end
        end
    })
    ConfigSection:CreateToggle({
        Name = "Auto Farm Secret Boss", Default = AutoFarmFilters.SecretBoss == true,
        Callback = function(V)
            AutoFarmFilters.SecretBoss = V == true
            Fishing.Flags.AutoFarmSecretBoss = AutoFarmFilters.SecretBoss
            if not AutoFarmFilters.SecretBoss then resetBossFarmTarget() end
        end
    })
    ConfigSection:CreateToggle({
        Name = "Anti AFK", Default = true,
        Callback = function(V)
            AutoFarmFilters.AntiAFK = V == true
            Fishing.Flags.AntiAFK = AutoFarmFilters.AntiAFK
            if Fishing.Flags.AntiAFK then
                if initAntiAFK then initAntiAFK() end
            elseif stopAntiAFK then
                stopAntiAFK()
            end
        end
    })

    ConfigSection:CreateToggle({ Name = "Auto Sell Fish", Default = KhfreshUserConfig.AutoSell == true, Callback = function(V) MiscFlags.AutoSell = V end })
    ConfigSection:CreateDropdown({
        Name = "Method Sell #1",
        Options = { "Spam", "When full" },
        Default = "Spam",
        Callback = function(value) KhfreshState.sellMethod1 = value end
    })
    ConfigSection:CreateDropdown({
        Name = "Method Sell #2",
        Options = { "Instant", "Teleport" },
        Default = "Instant",
        Callback = function(value) KhfreshState.sellMethod2 = value end
    })

    local autoBossEnabled = { Enzo = false, ["Long Diaohai"] = false, ["Black Tortoise Bloodline"] = false }
    local autoBossThreads = {}

    local function isAnyBossMinigameVisible()
        local fishing = MainGui and MainGui:FindFirstChild("Fishing")
        local bossBar = fishing and fishing:FindFirstChild("BossFightBar")
        return bossBar ~= nil and bossBar.Visible == true
    end

    local function isNamedBossInFight(bossName)
        local active = false
        pcall(function()
            local npc = Workspace:FindFirstChild("NPC")
            local boss = npc and npc:FindFirstChild(bossName, true)
            if boss and boss:GetAttribute("InFight") == true then active = true end
        end)
        return active or isAnyBossMinigameVisible()
    end

    local function refreshAutoBossSkillCheck()
        local anyEnabled = autoBossEnabled.Enzo == true
            or autoBossEnabled["Long Diaohai"] == true
            or autoBossEnabled["Black Tortoise Bloodline"] == true
        Fishing.Flags.AutoSkillCheck = anyEnabled
        KhfreshState.AutoEnzoEnabled = autoBossEnabled.Enzo == true
        KhfreshState.AutoLongDiaohaiEnabled = autoBossEnabled["Long Diaohai"] == true
        KhfreshState.AutoBlackTortoiseEnabled = autoBossEnabled["Black Tortoise Bloodline"] == true
    end

    local function setAutoBoss(bossName, enabled)
        enabled = enabled == true
        autoBossEnabled[bossName] = enabled
        refreshAutoBossSkillCheck()

        local oldThread = autoBossThreads[bossName]
        if oldThread then pcall(task.cancel, oldThread); autoBossThreads[bossName] = nil end

        if not enabled then
            return
        end
        if not StartBossFight then
            KhfreshLib:Notify({Title="Auto Boss", Message="StartBossFight remote is unavailable.", Duration=3})
            return
        end
        task.defer(function()
            if autoBossEnabled[bossName] and not forceEquipRodOnce() then
                KhfreshLib:Notify({
                    Title = "Auto Equip",
                    Message = "Could not equip a rod with method " .. tostring(KhfreshState.AutoEquipMethod) .. ".",
                    Duration = 3
                })
            end
        end)

        autoBossThreads[bossName] = task.spawn(function()
            local lastRequest = 0
            while alive() and autoBossEnabled[bossName] do
                if not isNamedBossInFight(bossName) and tick() - lastRequest >= 4.0 then
                    local fightMode = "Normal"
                    if bossName == "Enzo" then
                        fightMode = KhfreshState.AutoEnzoFightMode or "Normal"
                    elseif bossName == "Long Diaohai" then
                        fightMode = KhfreshState.AutoLongDiaohaiFightMode or "Normal"
                    elseif bossName == "Black Tortoise Bloodline" then
                        fightMode = "Hard"
                    end
                    local ok = pcall(function() StartBossFight:FireServer(bossName, fightMode or "Normal") end)
                    if ok then lastRequest = tick() end
                    task.wait(4.0)
                else
                    task.wait(0.35)
                end
            end
            autoBossThreads[bossName] = nil
        end)

        if enabled then
            KhfreshLib:Notify({Title="Auto Boss", Message="Auto start + minigame enabled: "..bossName, Duration=3})
        end
    end

    local function setAutoEnzo(value)
        setAutoBoss("Enzo", value)
        Fishing.BossFightThread = autoBossThreads.Enzo
        runtimeEnv.KhfreshBossFightThread = autoBossThreads.Enzo
    end

    ConfigSection:CreateToggle({ Name = "Auto Enzo", Icon = "zap", Default = false, Callback = function(V) setAutoEnzo(V == true) end })
    ConfigSection:CreateSlider({
        Name = "Auto Enzo Hit Cooldown (s)",
        Range = {0.01, 1},
        Default = KhfreshState.AutoEnzoHitCooldown,
        Increment = 0.01,
        Callback = function(value)
            KhfreshState.AutoEnzoHitCooldown = math.clamp(tonumber(value) or 0.15, 0.01, 1)
            KhfreshUserConfig.AutoEnzoHitCooldown = KhfreshState.AutoEnzoHitCooldown
        end
    })
    ConfigSection:CreateToggle({
        Name = "Auto Long Diaohai Minigame", Icon = "zap", Default = false,
        Callback = function(V) setAutoBoss("Long Diaohai", V == true) end
    })
    ConfigSection:CreateSlider({
        Name = "Long Diaohai Hit Cooldown (s)",
        Range = {0.01, 1},
        Default = KhfreshState.AutoLongDiaohaiHitCooldown,
        Increment = 0.01,
        Callback = function(value)
            KhfreshState.AutoLongDiaohaiHitCooldown = math.clamp(tonumber(value) or 0.15, 0.01, 1)
            KhfreshUserConfig.AutoLongDiaohaiHitCooldown = KhfreshState.AutoLongDiaohaiHitCooldown
        end
    })
    local SecretWeatherSection = FarmingTab:CreateSection("Smart Secret Weather Override")
    SecretWeatherSection:CreateToggle({
        Name = "Auto Override On Weather",
        Default = false,
        Callback = function(V)
            KhfreshState.SmartWeather.enabled = V
            if V then
                KhfreshLib:Notify({
                    Title = "Smart Weather",
                    Message = "Auto-hop to the Secret island when the weather starts, then hop back when it ends!",
                    Duration = 3
                })
            else
                if KhfreshState.SmartWeather.activeOverride then
                    pcall(function()
                        local char = LocalPlayer.Character
                        local hrp = char and char:FindFirstChild("HumanoidRootPart")
                        if KhfreshState.SmartWeather.savedCFrame and hrp then
                            hrp.CFrame = KhfreshState.SmartWeather.savedCFrame
                        end
                        if KhfreshState.SmartWeather.savedFlags then
                            local s = KhfreshState.SmartWeather.savedFlags
                            Fishing.Flags.AutoCast = s.AutoCast
                            Fishing.Flags.AutoFarmBoss = s.AutoFarmBoss
                            Fishing.Flags.AutoFarmSecretBoss = s.AutoFarmSecretBoss
                        end
                    end)
                    KhfreshState.SmartWeather.activeOverride = false
                end
            end
        end
    })

    local weatherIslandOptions = {
        "Island 2 (Thunderstorm)",
        "Island 3 (Rainy)",
        "Island 5 (Windy)",
        "Island 6 (Snowy)",
        "Island 7 (Foggy)",
        "Island 8 (Blazing Sun)",
        "Island 9 (Blood)",
        "Island 12 (Select Weather)",
        "Island 13 (Select Weather)",
    }
    SecretWeatherSection:CreateDropdown({
        Name = "Allowed Weather Islands",
        Multi = true,
        Options = weatherIslandOptions,
        Default = weatherIslandOptions,
        Callback = function(values)
            local set = {}
            for _, val in ipairs(values) do
                local isl = val:match("Island %d+")
                if isl then set[isl] = true end
            end
            KhfreshState.SmartWeather.selectedIslands = set
            KhfreshUserConfig.SmartWeather = set
            pcall(function() khSnapshotAndSave("weather island selection") end)
        end
    })
    local weatherNameOptions = {"Disabled"}
    for _, weatherName in ipairs(khGetSupportedWeatherNames()) do
        weatherNameOptions[#weatherNameOptions + 1] = weatherName
    end
    for _, islandNumber in ipairs({9, 12, 13}) do
        local islandKey = "Island " .. tostring(islandNumber)
        local configuredName = tostring(KhfreshState.SmartWeather.weatherNames[islandKey] or "")
        local selectedName = "Disabled"
        for _, weatherName in ipairs(weatherNameOptions) do
            if string.lower(weatherName) == string.lower(configuredName) then
                selectedName = weatherName
                break
            end
        end
        SecretWeatherSection:CreateDropdown({
            Name = islandKey .. " weather",
            Options = weatherNameOptions,
            Default = selectedName,
            Callback = function(value)
                local weatherName = value == "Disabled" and "" or string.lower(tostring(value or ""))
                KhfreshState.SmartWeather.weatherNames[islandKey] = weatherName
                KhfreshUserConfig.WeatherIslandNames = KhfreshUserConfig.WeatherIslandNames or {}
                KhfreshUserConfig.WeatherIslandNames[islandKey] = weatherName
                pcall(function() khSnapshotAndSave("weather name mapping") end)
            end
        })
    end

    local SkillSection = FarmingTab:CreateSection("Auto Skill")

        -- Redz multi dropdown: selected skills are still executed in fixed order Z -> X -> C -> V.
    local savedSkills = (type(KhfreshUserConfig.SelectedSkills) == "table" and KhfreshUserConfig.SelectedSkills) or {}
    local skillOptions = {"Z", "X", "C", "V"}
    local savedSkillList = {}
    for _, key in ipairs(skillOptions) do
        if savedSkills[key] ~= false then savedSkillList[#savedSkillList + 1] = key end
    end
    SkillSection:CreateDropdown({
        Name = "Select Skills",
        Multi = true,
        Options = skillOptions,
        Default = savedSkillList,
        Callback = function(values)
            Fishing.Flags.SelectedSkills = {Z = false, X = false, C = false, V = false}
            if type(values) == "string" then
                values = {values}
            end
            if type(values) == "table" then
                -- array style
                for _, key in ipairs(values) do
                    key = tostring(key)
                    if Fishing.Flags.SelectedSkills[key] ~= nil then
                        Fishing.Flags.SelectedSkills[key] = true
                    end
                end
                -- map style fallback
                for key, on in pairs(values) do
                    if type(key) == "string" and Fishing.Flags.SelectedSkills[key] ~= nil and on then
                        Fishing.Flags.SelectedSkills[key] = true
                    end
                end
            end
            KhfreshUserConfig.SelectedSkills = Fishing.Flags.SelectedSkills
            pcall(function() khSnapshotAndSave("callback") end)
        end
    })
    SkillSection:CreateToggle({
        Name = "Auto Skill", Default = KhfreshUserConfig.AutoSkill == true,
        Callback = function(value)
            value = value == true
            Fishing.Flags.AutoFarmSkill = value
            Fishing.Flags.AutoSkill = value
            KhfreshUserConfig.AutoSkill = value
            if value then
                local sel = Fishing.Flags.SelectedSkills
                local any = false
                if type(sel) == "table" then
                    for _, k in ipairs({"Z","X","C","V"}) do
                        if sel[k] then any = true break end
                    end
                end
                if not any then
                    Fishing.Flags.SelectedSkills = {Z = true, X = true, C = true, V = true}
                end
            end
            pcall(function() khSnapshotAndSave("callback") end)
            if value then
                KhfreshLib:Notify({ Title = "Auto Skill", Message = "Using selected skills when ready", Duration = 2 })
            else
                KhfreshLib:Notify({ Title = "Auto Skill", Message = "Disabled", Duration = 2 })
            end
        end
    })

    local EquipSection = FarmingTab:CreateSection("Auto Equip")

    EquipSection:CreateDropdown({
        Name = "Auto Equip Method",
        Options = { "Default", "Best Rod" },
        Default = KhfreshState.AutoEquipMethod,
        Callback = function(value)
            KhfreshState.AutoEquipMethod = value == "Best Rod" and "Best Rod" or "Default"
            KhfreshUserConfig.AutoEquipMethod = KhfreshState.AutoEquipMethod
            pcall(function() khSnapshotAndSave("auto equip method") end)
        end
    })

    EquipSection:CreateToggle({
        Name = "Auto Equip Best Bait",
        Default = KhfreshUserConfig.AutoEquipBait == true,
        Callback = function(value)
            MiscFlags.AutoEquipBait = value
            if value then
                KhfreshLib:Notify({ Title = "Auto Equip", Message = "Best bait will be equipped automatically", Duration = 2 })
            else
                KhfreshLib:Notify({ Title = "Auto Equip", Message = "Disabled", Duration = 2 })
            end
        end
    })


    EquipSection:CreateButton({
        Name = "Equip Best Rod",
        Callback = function()
            local best = GetBestRod()
            if best then
                if EquipRod(best) then
                    KhfreshLib:Notify({ Title = "Equip Rod", Message = "Equipped best rod: " .. best, Duration = 2 })
                else
                    KhfreshLib:Notify({ Title = "Equip Rod", Message = "Failed to equip rod", Duration = 2 })
                end
            else
                KhfreshLib:Notify({ Title = "Equip Rod", Message = "No rod available", Duration = 2 })
            end
        end
    })

    EquipSection:CreateButton({
        Name = "Equip Best Orb",
        Callback = function()
            local best = GetBestOrb()
            if best then
                if EquipOrb(best) then
                    KhfreshLib:Notify({ Title = "Equip Orb", Message = "Equipped best orb: " .. best, Duration = 2 })
                else
                    KhfreshLib:Notify({ Title = "Equip Orb", Message = "Failed to equip orb", Duration = 2 })
                end
            else
                KhfreshLib:Notify({ Title = "Equip Orb", Message = "No orb available", Duration = 2 })
            end
        end
    })

    task.spawn(function()
        while task.wait(3) do
            if MiscFlags.AutoEquipBait then
                pcall(function()
                    local userId = LocalPlayer.UserId
                    local userData = Data:FindFirstChild(tostring(userId))
                    if not userData then return end
                    local equippedBaitValue = userData:FindFirstChild("EquippedBait")
                    if not equippedBaitValue then return end
                    local currentBait = equippedBaitValue.Value or ""
                    local best = GetBestBait()
                    if best and best ~= currentBait then
                        if EquipBait(best) then
                            KhfreshLib:Notify({ Title = "Auto Equip", Message = "Equipped best bait: " .. best, Duration = 2 })
                        end
                    end
                end)
            end
        end
    end)

    -- ===== AUTO NAMELESS OCTOPARASITE =====
    do
        local NAMELESS_NAME = "Nameless Octoparasite"
        -- Nexus-style Rhythm (Safe): lag-compensated band + key/firesignal press
        -- Also used by Black Tortoise Bloodline when Rhythm UI is active
        local RHY_LANES = { "A", "S", "D" }
        local RHY_KEYS = { A = Enum.KeyCode.A, S = Enum.KeyCode.S, D = Enum.KeyCode.D }
        local RHY_WINDOW = 0.22
        local RHY_SPEED = 1.15 / 1.4 -- game note fall: t += dt/1.4 ; y = -0.05 + 1.15*t
        local RHY_BAR_FALLBACK = 0.85

        KhfreshState.Rhythm = {
            Enabled = false,
            Mode = "Safe", -- Nexus Safe only (no Risk remote spam)
            Band = 0.08,
            Lag = 0.03,
            Active = false,
            SignalUntil = 0,
            Config = nil,
            Method = nil,
            NextPress = {},
            Stats = { hit = 0, spam = 0 },
            FallSpeed = 1,
            ExtraSpawn = false,
            NoteLimit = 9999,
        }
        local Rhy = KhfreshState.Rhythm

        local function rhyFindNameless()
            local roots = {}
            local ocean = Workspace:FindFirstChild("Ocean")
            if ocean then
                local boss = ocean:FindFirstChild("Boss")
                if boss then
                    local fn = boss:FindFirstChild("FishName")
                    if fn then table.insert(roots, fn) end
                    table.insert(roots, boss)
                end
                table.insert(roots, ocean)
            end
            local fishes = Workspace:FindFirstChild("Fishes")
            if fishes then table.insert(roots, fishes) end
            for _, root in ipairs(roots) do
                local ok, found = pcall(function() return root:FindFirstChild(NAMELESS_NAME, true) end)
                if ok and found then return found end
            end
            return nil
        end

        local function rhyPivotOf(inst)
            if not inst then return nil end
            local ok, cf = pcall(function()
                if inst:IsA("BasePart") then return inst.CFrame end
                if inst:IsA("Model") then
                    if inst.PrimaryPart then return inst.PrimaryPart.CFrame end
                    return inst:GetPivot()
                end
                local part = inst:FindFirstChildWhichIsA("BasePart", true)
                if part then return part.CFrame end
                return nil
            end)
            if ok and cf then return cf end
            return nil
        end

        local function rhyTeleportToNameless()
            local model = rhyFindNameless()
            if not model then
                KhfreshLib:Notify({ Title = "Nameless", Message = "Cannot find " .. NAMELESS_NAME .. " (not spawned?)", Duration = 3 })
                return
            end
            local cf = rhyPivotOf(model)
            if not cf then
                KhfreshLib:Notify({ Title = "Nameless", Message = "Found boss but no position!", Duration = 3 })
                return
            end
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then
                KhfreshLib:Notify({ Title = "Nameless", Message = "Character not found!", Duration = 2 })
                return
            end
            pcall(function()
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.CFrame = cf + Vector3.new(0, 6, 10)
            end)
            KhfreshLib:Notify({ Title = "Nameless", Message = "Teleported to " .. NAMELESS_NAME, Duration = 2 })
        end

        local function rhyPress(laneFrame, lane)
            local keyCode = RHY_KEYS[lane]
            if not keyCode then return false end
            local methods = {
                function()
                    if type(firesignal) ~= "function" then return false end
                    local btn = laneFrame and laneFrame:FindFirstChild("Button")
                    if not (btn and (btn:IsA("TextButton") or btn:IsA("ImageButton"))) then return false end
                    firesignal(btn.MouseButton1Click)
                    return true
                end,
                function()
                    local vim = game:GetService("VirtualInputManager")
                    vim:SendKeyEvent(true, keyCode, false, game)
                    vim:SendKeyEvent(false, keyCode, false, game)
                    return true
                end,
                function()
                    local vim = game:GetService("VirtualInputManager")
                    vim:SendKeyEvent(true, keyCode, false, nil)
                    vim:SendKeyEvent(false, keyCode, false, nil)
                    return true
                end,
            }
            if Rhy.Method then
                local ok, res = pcall(methods[Rhy.Method])
                if ok and res then return true end
                Rhy.Method = nil
            end
            for i, fn in ipairs(methods) do
                local ok, res = pcall(fn)
                if ok and res then
                    Rhy.Method = i
                    return true
                end
            end
            return false
        end

        local function rhyGui()
            local fishing = MainGui and MainGui:FindFirstChild("Fishing")
            if not fishing then return nil, nil end
            return fishing:FindFirstChild("Rhythm"), fishing
        end

        local function rhyUiActive()
            local gui, fishing = rhyGui()
            if not gui or not fishing then return false end
            return gui.Visible == true and fishing.Visible == true
        end

        local function rhyMaxBand()
            local m = RHY_WINDOW - RHY_SPEED * (Rhy.Lag or 0) - 0.02
            if m < 0.01 then m = 0.01 end
            return m
        end

        -- Hard-mode trap notes = pure red BackgroundColor3 (255,40,40). Hitting = miss.
        local function rhyIsTrapNote(note)
            if not note or not note:IsA("GuiObject") then return false end
            local ok, c = pcall(function() return note.BackgroundColor3 end)
            if not ok or typeof(c) ~= "Color3" then return false end
            return c.R >= 0.85 and c.G <= 0.25 and c.B <= 0.25
        end

        -- Nexus Safe scan: predict note position with lag, press when in band (skip red traps)
        local function rhyScan(now)
            local gui = rhyGui()
            if not gui then return end
            local band = math.clamp(tonumber(Rhy.Band) or 0.08, 0.01, rhyMaxBand())
            local lag = tonumber(Rhy.Lag) or 0.03
            for _, lane in ipairs(RHY_LANES) do
                local laneFrame = gui:FindFirstChild("Progression" .. lane)
                if laneFrame then
                    local barY = RHY_BAR_FALLBACK
                    local barFrame = laneFrame:FindFirstChild("BarFrame")
                    if barFrame then
                        local okB, y = pcall(function() return barFrame.Position.Y.Scale end)
                        if okB and type(y) == "number" then barY = y end
                    end
                    local inWindow = 0
                    for _, note in ipairs(laneFrame:GetChildren()) do
                        if note.Name == "Note_FX" and not rhyIsTrapNote(note) then
                            local okP, y = pcall(function() return note.Position.Y.Scale end)
                            if okP and type(y) == "number" then
                                -- compensate fall speed so we press slightly early (Nexus)
                                if math.abs((y + RHY_SPEED * lag) - barY) <= band then
                                    inWindow = inWindow + 1
                                end
                            end
                        end
                    end
                    if inWindow > 5 then inWindow = 5 end
                    for _ = 1, inWindow do
                        if rhyPress(laneFrame, lane) then
                            Rhy.Stats.hit = Rhy.Stats.hit + 1
                        end
                    end
                end
            end
        end

        if runtimeEnv.KhfreshRhyStart then pcall(function() runtimeEnv.KhfreshRhyStart:Disconnect() end) end
        if runtimeEnv.KhfreshRhyStop then pcall(function() runtimeEnv.KhfreshRhyStop:Disconnect() end) end
        if runtimeEnv.KhfreshRhyLoop then pcall(function() runtimeEnv.KhfreshRhyLoop:Disconnect() end) end
        if runtimeEnv.KhfreshNamelessBGM then pcall(function() runtimeEnv.KhfreshNamelessBGM:Disconnect() end) end
        if runtimeEnv.KhfreshNamelessP2 then pcall(function() runtimeEnv.KhfreshNamelessP2:Disconnect() end) end
        if runtimeEnv.KhfreshNamelessFallSpeed then
            pcall(function() runtimeEnv.KhfreshNamelessFallSpeed:Disconnect() end)
            runtimeEnv.KhfreshNamelessFallSpeed = nil
        end

        pcall(function()
            local evStart = Events:FindFirstChild("RhythmStart")
            if evStart then
                runtimeEnv.KhfreshRhyStart = evStart.OnClientEvent:Connect(function(cfg)
                    if not alive() then return end
                    Rhy.Config = cfg
                    Rhy.Active = true
                    Rhy.SignalUntil = tick() + 12
                    Rhy.Stats = { hit = 0, spam = 0 }
                    if Rhy.Enabled then
                        local hp = cfg and (cfg.FinalMaxHP or cfg.HPFinalPhase)
                        KhfreshLib:Notify({
                            Title = "Auto Rhythm",
                            Message = "Rhythm started" .. (hp and (" | HP " .. tostring(hp)) or ""),
                            Duration = 3,
                        })
                    end
                end)
            end
            local evStop = Events:FindFirstChild("RhythmStop")
            if evStop then
                runtimeEnv.KhfreshRhyStop = evStop.OnClientEvent:Connect(function()
                    Rhy.Active = false
                    Rhy.SignalUntil = 0
                end)
            end
        end)

        -- Arm even when RhythmStart is late (Nexus): BossPhaseBGM + BossPhase2Setup
        pcall(function()
            local evBGM = Events:FindFirstChild("BossPhaseBGM")
            if evBGM then
                runtimeEnv.KhfreshNamelessBGM = evBGM.OnClientEvent:Connect(function(bossName, _sound)
                    if not alive() then return end
                    local name = bossName ~= nil and tostring(bossName) or ""
                    -- Nameless or Black Tortoise (same Rhythm UI)
                    if name ~= "" and name ~= NAMELESS_NAME and name ~= "Black Tortoise Bloodline" then
                        return
                    end
                    Rhy.Active = true
                    Rhy.SignalUntil = tick() + 12
                    if Rhy.Enabled then
                        KhfreshLib:Notify({
                            Title = "Auto Rhythm",
                            Message = "Boss signal: " .. (name ~= "" and name or "phase"),
                            Duration = 2,
                        })
                    end
                end)
            end
            local evP2 = Events:FindFirstChild("BossPhase2Setup")
            if evP2 then
                runtimeEnv.KhfreshNamelessP2 = evP2.OnClientEvent:Connect(function()
                    if not alive() then return end
                    Rhy.Active = true
                    Rhy.SignalUntil = tick() + 12
                end)
            end
        end)

        -- Heartbeat loop (Nexus) — not RenderStepped position rewrite
        runtimeEnv.KhfreshRhyLoop = RunService.Heartbeat:Connect(function()
            if not alive() or not Rhy.Enabled then return end
            local now = tick()
            Rhy.Active = rhyUiActive() or now < (Rhy.SignalUntil or 0)
            if not Rhy.Active then return end
            rhyScan(now)
        end)

        local NamelessSection = FarmingTab:CreateSection("Auto Nameless Octoparasite")
        NamelessSection:CreateButton({ Name = "Teleport to Nameless Octoparasite", Callback = function() pcall(
            rhyTeleportToNameless) end })
        NamelessSection:CreateToggle({
            Name = "Auto Nameless",
            Default = KhfreshUserConfig.AutoNameless == true,
            Callback = function(value)
                Rhy.Enabled = value == true
                Rhy.Mode = "Safe"
                Rhy.Band = 0.08
                Rhy.Lag = 0.03
                KhfreshUserConfig.AutoNameless = Rhy.Enabled
                pcall(function() khSnapshotAndSave("auto nameless") end)
                if value then
                    KhfreshLib:Notify({
                        Title = "Auto Nameless",
                        Message = "ON — Nexus Safe rhythm (lag band + skip red notes)",
                        Duration = 3,
                    })
                else
                    Rhy.Active = false
                    Rhy.SignalUntil = 0
                    KhfreshLib:Notify({ Title = "Auto Nameless", Message = "Disabled", Duration = 2 })
                end
            end
        })
    end

    -- ===== AUTO BLACK TORTOISE BLOODLINE =====
    -- Auto Minigame = ONLY Rhythm x1 + Boss QTE (no TP / no farm)
    -- Auto Black Tortoise = FULL: TP + equip + cast + minigame
    do
        local TORTOISE_NAME = "Black Tortoise Bloodline"
        local tortoiseFullOn = false
        local tortoiseMiniOn = false
        local tortoiseThread = nil

        local function findTortoiseModel()
            local roots = {}
            local ocean = Workspace:FindFirstChild("Ocean")
            if ocean then
                local boss = ocean:FindFirstChild("Boss")
                if boss then table.insert(roots, boss) end
                table.insert(roots, ocean)
            end
            local fishes = Workspace:FindFirstChild("Fishes")
            if fishes then table.insert(roots, fishes) end
            local npc = Workspace:FindFirstChild("NPC")
            if npc then table.insert(roots, npc) end
            table.insert(roots, Workspace)
            for _, root in ipairs(roots) do
                local ok, found = pcall(function()
                    return root:FindFirstChild(TORTOISE_NAME, true)
                end)
                if ok and found then return found end
            end
            return nil
        end

        local function tortoisePivot(inst)
            if not inst then return nil end
            local ok, cf = pcall(function()
                if inst:IsA("BasePart") then return inst.CFrame end
                if inst:IsA("Model") then
                    if inst.PrimaryPart then return inst.PrimaryPart.CFrame end
                    return inst:GetPivot()
                end
                local part = inst:FindFirstChildWhichIsA("BasePart", true)
                return part and part.CFrame or nil
            end)
            return (ok and cf) or nil
        end

        local function teleportToTortoise()
            local model = findTortoiseModel()
            if not model then return false, "not found" end
            local cf = tortoisePivot(model)
            if not cf then return false, "no pivot" end
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then return false, "no hrp" end
            pcall(function()
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.CFrame = cf + Vector3.new(0, 6, 10)
            end)
            return true, "ok"
        end

        -- Minigame only: Rhythm notes (A/S/D) + BossFightBar QTE
        local function setTortoiseMinigame(on)
            tortoiseMiniOn = on == true
            KhfreshState.AutoBlackTortoiseMinigame = tortoiseMiniOn
            -- QTE path (BossPhase2Action) — does NOT call StartBossFight
            pcall(function()
                autoBossEnabled[TORTOISE_NAME] = tortoiseMiniOn or tortoiseFullOn
                if refreshAutoBossSkillCheck then refreshAutoBossSkillCheck() end
                Fishing.Flags.AutoSkillCheck = tortoiseMiniOn
                    or tortoiseFullOn
                    or autoBossEnabled.Enzo == true
                    or autoBossEnabled["Long Diaohai"] == true
            end)
            KhfreshState.AutoBlackTortoiseEnabled = tortoiseMiniOn or tortoiseFullOn
            -- Rhythm x1 (same UI as Nameless InsaneGame)
            if KhfreshState.Rhythm then
                if tortoiseMiniOn or tortoiseFullOn then
                    KhfreshState.Rhythm.Enabled = true
                    KhfreshState.Rhythm.Mode = "Safe"
                    KhfreshState.Rhythm.Band = 0.08
                    KhfreshState.Rhythm.Lag = 0.03
                elseif not (KhfreshUserConfig and KhfreshUserConfig.AutoNameless) then
                    KhfreshState.Rhythm.Enabled = false
                end
            end
        end

        local function stopTortoiseFullLoop()
            tortoiseFullOn = false
            if tortoiseThread then
                pcall(function() task.cancel(tortoiseThread) end)
                tortoiseThread = nil
            end
        end

        local TortoiseSection = FarmingTab:CreateSection("Auto Black Tortoise Bloodline")
        TortoiseSection:CreateButton({
            Name = "Teleport to Black Tortoise Bloodline",
            Callback = function()
                local ok, reason = teleportToTortoise()
                KhfreshLib:Notify({
                    Title = "Black Tortoise",
                    Message = ok and "Teleported to boss." or ("Cannot TP: " .. tostring(reason)),
                    Duration = 3
                })
            end
        })

        -- Toggle 1: MINIGAME ONLY
        TortoiseSection:CreateToggle({
            Name = "Auto Minigame (Rhythm + QTE)",
            Default = false,
            Callback = function(value)
                setTortoiseMinigame(value == true)
                KhfreshLib:Notify({
                    Title = "Black Tortoise Minigame",
                    Message = (value and "ON — Nexus Safe rhythm + QTE (no TP)" or "OFF"),
                    Duration = 3
                })
            end
        })

        -- Toggle 2: FULL auto
        TortoiseSection:CreateToggle({
            Name = "Auto Black Tortoise (Full)",
            Default = false,
            Callback = function(value)
                value = value == true
                if not value then
                    stopTortoiseFullLoop()
                    -- If minigame toggle still on, keep minigame; else turn all off
                    if not tortoiseMiniOn then
                        setTortoiseMinigame(false)
                    else
                        KhfreshState.AutoBlackTortoiseEnabled = true
                    end
                    KhfreshLib:Notify({ Title = "Black Tortoise Full", Message = "OFF", Duration = 2 })
                    return
                end
                tortoiseFullOn = true
                -- Full always includes minigame
                setTortoiseMinigame(true)
                KhfreshLib:Notify({
                    Title = "Black Tortoise Full",
                    Message = "ON — TP + farm + minigame (Rhythm + QTE)",
                    Duration = 3
                })
                if tortoiseThread then
                    pcall(function() task.cancel(tortoiseThread) end)
                    tortoiseThread = nil
                end
                tortoiseThread = task.spawn(function()
                    local lastTp = 0
                    while alive() and tortoiseFullOn do
                        pcall(function()
                            Fishing.Flags.MainFarm = true
                            Fishing.Flags.AutoCast = true
                            Fishing.Flags.AnchorLock = true
                            MiscFlags.AutoEquipRod = true
                            if KhfreshState.Rhythm then
                                KhfreshState.Rhythm.Enabled = true
                            end
                            local model = findTortoiseModel()
                            if model then
                                local cf = tortoisePivot(model)
                                local char = LocalPlayer.Character
                                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                                if cf and hrp then
                                    local dist = (hrp.Position - cf.Position).Magnitude
                                    local fishing = MainGui and MainGui:FindFirstChild("Fishing")
                                    local inMini = fishing and fishing.Visible == true
                                    if dist > 80 and not inMini and (tick() - lastTp) > 6 then
                                        lastTp = tick()
                                        hrp.CFrame = cf + Vector3.new(0, 6, 10)
                                    end
                                end
                            end
                        end)
                        task.wait(1.25)
                    end
                    tortoiseThread = nil
                end)
            end
        })
    end

    -- ===== FAVORITES =====
    do
        local FavSection = FarmingTab:CreateSection("Auto Favorite Fish")
        local allFishNames = {}
        pcall(function()
            local rarityModule = require(Info.FishingAreaRarity)
            if type(rarityModule) == "table" then
                for _, fishTable in pairs(rarityModule) do
                    if type(fishTable) == "table" then
                        for fishName in pairs(fishTable) do
                            if type(fishName) == "string" and fishName ~= "" then
                                table.insert(allFishNames, fishName)
                            end
                        end
                    end
                end
            end
        end)
        local uniqueFish = {}
        for _, name in ipairs(allFishNames) do uniqueFish[name] = true end
        local fishOptions = {}
        for name in pairs(uniqueFish) do table.insert(fishOptions, name) end
        table.sort(fishOptions)

        local fishDropdown = FavSection:CreateDropdown({
            Name = "Select fish to auto-favourite",
        Multi = true,
            Options = fishOptions,
            Default = KhfreshState.favorites.selectedFish or {},
            Callback = function(values) KhfreshState.favorites.selectedFish = values end
        })

        local autoFavToggle = FavSection:CreateToggle({
            Name = "Auto Favourite Fishes",
            Default = false,
            Callback = function(value)
                KhfreshState.favorites.autoEnabled = value
                if value then
                    if KhfreshState.favorites.thread then
                        task.cancel(KhfreshState.favorites.thread)
                        KhfreshState.favorites.thread = nil
                    end
                    KhfreshState.favorites.thread = task.spawn(function()
                        local favoriteEvent = Events:FindFirstChild("FavoriteItem")
                        if not favoriteEvent then
                            KhfreshLib:Notify({ Title = "Auto Favourite", Message = "FavoriteItem remote not found!", Duration = 3 })
                            KhfreshState.favorites.autoEnabled = false
                            if autoFavToggle and type(autoFavToggle.SetValue) == "function" then
                                autoFavToggle:SetValue(false)
                            end
                            return
                        end
                        while KhfreshState.favorites.autoEnabled do
                            pcall(function()
                                local userId = LocalPlayer.UserId
                                local userData = Data:FindFirstChild(tostring(userId))
                                if not userData then return end
                                local inventory = userData:FindFirstChild("Inventory")
                                if not inventory then return end
                                local selected = KhfreshState.favorites.selectedFish or {}
                                if #selected == 0 then return end
                                local selectedSet = {}
                                for _, name in ipairs(selected) do selectedSet[name] = true end
                                for _, item in pairs(inventory:GetChildren()) do
                                    local fullName = item.Name
                                    if not string.find(fullName, "| Favorite$") then
                                        local fishName = fullName:match("^(.-)%s*|") or fullName
                                        if selectedSet[fishName] then
                                            favoriteEvent:FireServer(fullName)
                                        end
                                    end
                                end
                            end)
                            task.wait(0.3)
                        end
                    end)
                    KhfreshLib:Notify({ Title = "Auto Favourite", Message = "Enabled - scanning every 0.3s", Duration = 2 })
                else
                    if KhfreshState.favorites.thread then
                        task.cancel(KhfreshState.favorites.thread)
                        KhfreshState.favorites.thread = nil
                    end
                    KhfreshLib:Notify({ Title = "Auto Favourite", Message = "Disabled", Duration = 2 })
                end
            end
        })
    end
    -- ===== AUTO PRAY SPIRIT =====
    do
        local PraySection = FarmingTab:CreateSection("Auto Pray Spirit")
        local prayEnabled = false
        local prayThread = nil
        local lastInteractTime = 0
        local cooldown = 2

        local function getSpiritRoot(model, prompt)
            local root = model:FindFirstChild("HumanoidRootPart", true)
            if root and root:IsA("BasePart") then return root end
            if model.PrimaryPart then return model.PrimaryPart end
            local talk = model:FindFirstChild("Talk", true)
            if talk and talk:IsA("BasePart") then return talk end
            local parent = prompt and prompt.Parent
            if parent and parent:IsA("BasePart") then return parent end
            return nil
        end

        local function findSpiritPrompt(godFolder)
            -- Prefer the known game hierarchy: NPC > God > SpiritModel > HumanoidRootPart > Talk > ProximityPrompt.
            for _,model in ipairs(godFolder:GetDescendants()) do
                if model:IsA("Model") then
                    local hrp = model:FindFirstChild("HumanoidRootPart", true)
                    local talk = hrp and hrp:FindFirstChild("Talk")
                    local prompt = talk and talk:FindFirstChild("ProximityPrompt")
                    if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
                        return model, prompt, hrp
                    end
                end
            end
            -- Fallback: any enabled ProximityPrompt inside God.
            local prompt = godFolder:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt and prompt.Enabled then
                local model = prompt:FindFirstAncestorOfClass("Model") or godFolder
                return model, prompt, getSpiritRoot(model, prompt)
            end
            return nil, nil, nil
        end

        local function fireSpiritPrompt(prompt)
            if not prompt then return false end
            pcall(function()
                prompt.RequiresLineOfSight = false
                prompt.HoldDuration = 0
                prompt.MaxActivationDistance = math.max(prompt.MaxActivationDistance, 25)
            end)

            if type(fireproximityprompt)=="function" then
                local ok = pcall(function() fireproximityprompt(prompt) end)
                if ok then return true end
            end

            if type(firesignal)=="function" then
                local ok = pcall(function()
                    if prompt.PromptButtonHoldBegan then firesignal(prompt.PromptButtonHoldBegan) end
                    task.wait(0.08)
                    if prompt.PromptButtonHoldEnded then firesignal(prompt.PromptButtonHoldEnded) end
                end)
                if ok then return true end
            end

            return false
        end

        local function scanAndPray()
            local npcFolder = Workspace:FindFirstChild("NPC")
            local godFolder = npcFolder and npcFolder:FindFirstChild("God")
            if not godFolder then return false, "God folder not found" end
            if tick() - lastInteractTime < cooldown then return false, nil end

            local model, prompt, spiritRoot = findSpiritPrompt(godFolder)
            if not prompt or not spiritRoot then return false, "Spirit prompt not found" end

            local char = LocalPlayer.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if not root then return false, "Character not ready" end

            -- Grounded, small offset instead of a large vertical teleport.
            root.CFrame = CFrame.new(spiritRoot.Position + Vector3.new(0, 2, 0))
            task.wait(0.12)

            local ok = fireSpiritPrompt(prompt)
            if ok then
                lastInteractTime = tick()
                return true, "Prayed to " .. tostring(model and model.Name or "Spirit")
            end
            return false, "Could not trigger spirit prompt"
        end

        local function startPray()
            if prayEnabled then return end
            prayEnabled = true
            prayThread = task.spawn(function()
                while prayEnabled and alive() do
                    local ok, msg = scanAndPray()
                    if ok then
                        KhfreshLib:Notify({Title="Auto Pray", Message=msg, Duration=2})
                    end
                    task.wait(1.0)
                end
            end)
            KhfreshLib:Notify({Title="Auto Pray", Message="Enabled", Duration=2})
        end

        local function stopPray()
            prayEnabled = false
            if prayThread then
                pcall(function() task.cancel(prayThread) end)
                prayThread = nil
            end
            KhfreshLib:Notify({Title="Auto Pray", Message="Disabled", Duration=2})
        end

        PraySection:CreateToggle({
            Name="Auto Teleport + Interact (Pray) Spirit",
            Icon="hand-heart",
            Default=false,
            Callback=function(value)
                if value==true then startPray() else stopPray() end
            end
        })
    end
    -- ===== AUTO FARM =====
    do
        -- ===== AUTO FARM SELECTED FISH =====
        do
            -- Clean Selected-Fish pipeline.
            -- ONLY responsibilities:
            --   1) determine selected fish + their selected island entries
            --   2) teleport to the current selected island
            --   3) equip rod
            --   4) cast exactly once
            --   5) wait for the real FishingMinigame event
            --   6) read Fishing > ProgressionBar > FishName
            --   7) exact fish-name match: keep; mismatch: cancel once
            --   8) only move to next island after EVERY selected fish entry
            --      on the current island has been caught at least once

            local FishFarmSection = FarmingTab:CreateSection({Title="Auto Farm Selected Fish", Icon="fish-symbol", Locked=false})
            local selectedFishEntries = {}
            local selectedFishLabels = {}
            local selectedFishByIsland = {}
            local selectedIslandList = {}
            local selectedIslandIndex = 1
            local fishFarmRunning = false
            local fishFarmThread = nil
            local selectedLastIsland = nil

            local ISLAND_NAME_MAP = {
                ["Island 1"] = 1, ["Island 2"] = 2, ["Island 3"] = 3, ["Island 4"] = 4,
                ["Island 5"] = 5, ["Island 6"] = 6, ["Island 7"] = 7, ["Island 8"] = 8,
                ["Island 9"] = 9, ["Island 10"] = 10, ["Island 11"] = 11,
                ["Island 12"] = 12, ["Island 13"] = 13,
                ["Beginning Isle"] = 1, ["Bamboo Isle"] = 2, ["Fallout Isle"] = 3,
                ["Sovereign Isle"] = 4, ["Perch Isle"] = 5, ["Frost Isle"] = 6,
                ["Coconut Isle"] = 7, ["Amber Isle"] = 8, ["Battlefield Isle"] = 9,
                ["Mistpeak Isle"] = 10, ["World Angler Isle"] = 11,
                ["Weather Isle"] = 12, ["Mystic Reef Isle"] = 13,
            }

            local fishEntries = {}
            local labelToEntry = {}

            KhfreshState.SelectedAutoFarmCastToken = nil
            KhfreshState.SelectedAutoFarmCastSerial = 0
            KhfreshState.SelectedAutoFarmActiveCastSerial = 0
            KhfreshState.SelectedAutoFarmIslandIndex = 1
            KhfreshState.SelectedAutoFarmIslands = {}
            KhfreshState.SelectedAutoFarmCaughtByIsland = {}
            KhfreshState.SelectedAutoFarmFishByIsland = {}
            KhfreshState.SelectedAutoFarmPhase = "Idle"
            KhfreshState.SelectedAutoFarmCastIssuedAt = 0
            KhfreshState.SelectedAutoFarmLastCancelAt = 0
            KhfreshState.SelectedAutoFarmCurrentIsland = nil
            KhfreshState.SelectedAutoFarmFishNameAtCast = ""

            local function islandOf(raw)
                local key = tostring(raw or "")
                local n = ISLAND_NAME_MAP[key]
                if n then return n end
                n = tonumber(key:match("(%d+)"))
                if n and n >= 1 and n <= 13 then return n end
                return nil
            end

            local function pureFishName(label)
                return normalizeSelectedFishName(label)
            end

            local function buildFishEntries()
                table.clear(fishEntries)
                table.clear(labelToEntry)
                pcall(function()
                    local mod = Info and Info:FindFirstChild("FishingAreaRarity")
                    local data = mod and require(mod)
                    if type(data) ~= "table" then return end
                    for rawIsland, fishTable in pairs(data) do
                        local islandNum = islandOf(rawIsland)
                        if islandNum and type(fishTable) == "table" then
                            for fishName in pairs(fishTable) do
                                if type(fishName) == "string" and fishName ~= "" then
                                    local label = fishName .. " | Isle " .. tostring(islandNum)
                                    local entry = {Name=fishName, Island=islandNum, Label=label}
                                    fishEntries[#fishEntries+1] = entry
                                    labelToEntry[label] = entry
                                end
                            end
                        end
                    end
                end)
                table.sort(fishEntries, function(a,b)
                    if a.Island ~= b.Island then return a.Island > b.Island end
                    return string.lower(a.Name) < string.lower(b.Name)
                end)
                local options = {}
                for _, entry in ipairs(fishEntries) do options[#options+1] = entry.Label end
                if #options == 0 then options = {"No fish data (rejoin)"} end
                return options
            end

            local fishOptions = buildFishEntries()

            local function clearCaughtState()
                KhfreshState.SelectedAutoFarmCaughtByIsland = {}
                for islandNumber in pairs(selectedFishByIsland) do
                    KhfreshState.SelectedAutoFarmCaughtByIsland[islandNumber] = {}
                end
            end

            local function rebuildSelectedStateFromEntries(entries)
                selectedFishEntries = {}
                selectedFishLabels = {}
                selectedFishByIsland = {}
                selectedIslandList = {}
                local seenEntry, seenIsland = {}, {}

                for _, entry in ipairs(entries or {}) do
                    if type(entry) == "table" and type(entry.Name) == "string" and entry.Name ~= "" and entry.Island then
                        local key = tostring(entry.Label or (entry.Name .. " | Isle " .. tostring(entry.Island)))
                        if not seenEntry[key] then
                            seenEntry[key] = true
                            selectedFishEntries[#selectedFishEntries+1] = entry
                            selectedFishLabels[key] = true
                            local n = normalizeSelectedFishName(entry.Name)
                            if n ~= "" then
                                selectedFishByIsland[entry.Island] = selectedFishByIsland[entry.Island] or {}
                                selectedFishByIsland[entry.Island][n] = true
                                if not seenIsland[entry.Island] then
                                    seenIsland[entry.Island] = true
                                    selectedIslandList[#selectedIslandList+1] = entry.Island
                                end
                            end
                        end
                    end
                end

                table.sort(selectedIslandList, function(a,b) return a > b end)
                KhfreshState.SelectedAutoFarmIslands = {}
                for i, islandNumber in ipairs(selectedIslandList) do
                    KhfreshState.SelectedAutoFarmIslands[i] = islandNumber
                end
                KhfreshState.SelectedAutoFarmFishByIsland = {}
                for islandNumber, fishSet in pairs(selectedFishByIsland) do
                    KhfreshState.SelectedAutoFarmFishByIsland[islandNumber] = {}
                    for fishName in pairs(fishSet) do
                        KhfreshState.SelectedAutoFarmFishByIsland[islandNumber][fishName] = true
                    end
                end
                KhfreshState.SelectedAutoFarmFishSet = {}
                for _, entry in ipairs(selectedFishEntries) do
                    KhfreshState.SelectedAutoFarmFishSet[entry.Name] = true
                end
                clearCaughtState()
            end

            local function valuesToEntries(values)
                local out, seen = {}, {}
                if type(values) ~= "table" then return out end
                local function push(value)
                    if type(value) ~= "string" or value == "" or value == "No fish data (rejoin)" then return end
                    local entry = labelToEntry[value]
                    if not entry then
                        local wanted = pureFishName(value)
                        for _, candidate in ipairs(fishEntries) do
                            if pureFishName(candidate.Name) == wanted then
                                entry = candidate
                                break
                            end
                        end
                    end
                    if entry and not seen[entry.Label] then
                        seen[entry.Label] = true
                        out[#out+1] = entry
                    end
                end
                for i=1,#values do push(values[i]) end
                if #out == 0 then
                    for k,v in pairs(values) do
                        if v == true then push(k)
                        elseif type(v) == "string" then push(v) end
                    end
                end
                return out
            end

            local defaultLabels = {}
            do
                local savedEntries = KhfreshState.SelectedAutoFarmFishEntries
                if type(savedEntries) == "table" then
                    for _, saved in ipairs(savedEntries) do
                        if type(saved) == "table" and saved.Label then
                            defaultLabels[#defaultLabels+1] = saved.Label
                        end
                    end
                end
                if #defaultLabels == 0 then
                    local savedNames = KhfreshState.selectedAutoFarmFish
                    if type(savedNames) == "table" then
                        local wanted = {}
                        for _, savedName in ipairs(savedNames) do
                            if type(savedName) == "string" then wanted[normalizeSelectedFishName(savedName)] = true end
                        end
                        for _, entry in ipairs(fishEntries) do
                            if wanted[normalizeSelectedFishName(entry.Name)] then
                                defaultLabels[#defaultLabels+1] = entry.Label
                            end
                        end
                    end
                end
            end

            local fishDropdownApi = FishFarmSection:CreateDropdown({
                Name="Select Fish (Multi)", Multi=true, Options=fishOptions, Default=defaultLabels,
                Callback=function(values)
                    rebuildSelectedStateFromEntries(valuesToEntries(values))
                    KhfreshState.selectedAutoFarmFish = {}
                    KhfreshState.SelectedAutoFarmFishEntries = {}
                    for _, entry in ipairs(selectedFishEntries) do
                        KhfreshState.selectedAutoFarmFish[#KhfreshState.selectedAutoFarmFish+1] = entry.Name
                        KhfreshState.SelectedAutoFarmFishEntries[#KhfreshState.SelectedAutoFarmFishEntries+1] = {
                            Name=entry.Name, Island=entry.Island, Label=entry.Label
                        }
                    end
                    pcall(function() khSnapshotAndSave("selected fish changed") end)
                    KhfreshLib:Notify({
                        Title="Selected Fish",
                        Message="Selected "..tostring(#selectedFishEntries).." fish entries across "..tostring(#selectedIslandList).." island(s)",
                        Duration=2,
                    })
                end,
            })
            if #defaultLabels > 0 then rebuildSelectedStateFromEntries(valuesToEntries(defaultLabels)) end

            -- Instant Catch = file riêng: Khfresh_InstantCatch_Standalone.lua


            local function getIslandEntry(islandNumber)
                return khResolveIslandEntry(islandNumber)
            end

            local function teleportToSelectedIsland(islandNumber, force)
                local island = khResolveIslandEntry(islandNumber) or getIslandEntry(islandNumber)
                if not island or not island.cframe then return false end
                local char = LocalPlayer.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if not hrp then return false end
                local targetPos = island.cframe.Position + Vector3.new(0, 4, 0)
                local dist = (hrp.Position - targetPos).Magnitude
                if dist <= 20 and not force then return true end
                if char:GetAttribute("Fishing") or char:GetAttribute("Retractable") then return false end
                local ok = select(1, khTeleportToIslandCoordinates(island))
                task.wait()
                local verify = (hrp.Position - targetPos).Magnitude
                return ok == true or verify <= 40
            end

            local function waitForFishingIdle(timeout)
                local deadline = tick() + (timeout or 2)
                while tick() < deadline and alive() do
                    local char = LocalPlayer.Character
                    if not char then return false end
                    if not char:GetAttribute("Fishing") and not char:GetAttribute("Retractable") then
                        return true
                    end
                    task.wait(0.05)
                end
                return false
            end

            local function cancelExistingCastBeforeStart()
                local char = LocalPlayer.Character
                if not char then return end
                if not char:GetAttribute("Fishing") and not char:GetAttribute("Retractable") then return end
                local token = KhfreshState.SelectedAutoFarmCastToken or Fishing.BossFarm.CurrentToken
                if token ~= nil then
                    pcall(function() safeFire("FishingMinigame", false, token, "SelectedFishSwitch") end)
                else
                    -- No token exists yet (for example during countdown); keep the game's
                    -- existing rod-cancel fallback only for this pre-minigame case.
                    local root = char:FindFirstChild("HumanoidRootPart")
                    if root then pcall(function() safeFire("Fishing", root.CFrame) end) end
                end
                waitForFishingIdle(2)
            end

            local function selectedFishEquipRod()
                if isCurrentlyHoldingRod() or isHoldingFishingRod() then return true end
                pcall(forceEquipRodOnce)
                if isCurrentlyHoldingRod() or isHoldingFishingRod() then return true end
                task.wait(0.15)
                return isCurrentlyHoldingRod() or isHoldingFishingRod()
            end

            local function selectedCurrentIsland()
                if #selectedIslandList == 0 then return nil end
                local idx = tonumber(selectedIslandIndex) or 1
                if idx < 1 or idx > #selectedIslandList then idx = 1 end
                selectedIslandIndex = idx
                KhfreshState.SelectedAutoFarmIslandIndex = idx
                return selectedIslandList[idx]
            end

            local function selectedIslandComplete(islandNumber)
                local wanted = selectedFishByIsland[islandNumber] or {}
                local caught = KhfreshState.SelectedAutoFarmCaughtByIsland[islandNumber] or {}
                local total, done = 0, 0
                for fishName in pairs(wanted) do
                    total += 1
                    if caught[fishName] then done += 1 end
                end
                return total > 0 and done >= total, done, total
            end

            local function selectedAdvanceIsland()
                if #selectedIslandList <= 1 then return end
                local idx = tonumber(selectedIslandIndex) or 1
                idx += 1
                if idx > #selectedIslandList then
                    idx = 1
                    clearCaughtState()
                end
                selectedIslandIndex = idx
                KhfreshState.SelectedAutoFarmIslandIndex = idx
                KhfreshState.SelectedAutoFarmCurrentIsland = selectedIslandList[idx]
            end

            local function selectedFishAutoCast()
                if not fishFarmRunning or KhfreshState.SelectedAutoFarmFishRunning ~= true then return false end
                if KhfreshState.SelectedAutoFarmPhase ~= "Idle" then return false end
                local char = LocalPlayer.Character
                if not char then return false end
                if char:GetAttribute("Fishing") or char:GetAttribute("Retractable") then return false end
                local islandNumber = tonumber(KhfreshState.SelectedAutoFarmCurrentIsland) or selectedCurrentIsland()
                if not islandNumber then return false end

                local island = getIslandEntry(islandNumber)
                local root = char:FindFirstChild("HumanoidRootPart")
                if not island or not island.cframe or not root then return false end
                local targetPos = island.cframe.Position + Vector3.new(0,3,0)
                if (root.Position-targetPos).Magnitude > 35 then return false end
                if not selectedFishEquipRod() then return false end

                KhfreshState.SelectedAutoFarmCastSerial = (tonumber(KhfreshState.SelectedAutoFarmCastSerial) or 0)+1
                local serial = KhfreshState.SelectedAutoFarmCastSerial
                KhfreshState.SelectedAutoFarmActiveCastSerial = serial
                KhfreshState.SelectedAutoFarmCastToken = nil
                KhfreshState.SelectedAutoFarmCastIssuedAt = tick()
                KhfreshState.SelectedAutoFarmPhase = "WaitingForMinigame"
                KhfreshState.SelectedAutoFarmKeepCurrent = false
                KhfreshState.SelectedAutoFarmFishNameAtCast = readProgressFishName()

                -- This mode owns casting itself. Do not enable the generic AutoCast flag.
                pcall(function() safeFire("Fishing", root.CFrame) end)
                warn("[Khfresh][SelectedFish] CAST serial="..tostring(serial).." island="..tostring(islandNumber))
                return true
            end

            local function startSelectedFishFarm()
                local got
                pcall(function()
                    if fishDropdownApi and type(fishDropdownApi.Get)=="function" then got=fishDropdownApi.Get() end
                end)
                if got then
                    local entries=valuesToEntries(got)
                    if #entries>0 then rebuildSelectedStateFromEntries(entries) end
                end
                if #selectedFishEntries==0 and #defaultLabels>0 then rebuildSelectedStateFromEntries(valuesToEntries(defaultLabels)) end
                if #selectedFishEntries==0 then
                    KhfreshLib:Notify({Title="Selected Fish",Message="Select at least one fish first.",Duration=3})
                    return false
                end

                fishFarmRunning=true
                KhfreshState.SelectedAutoFarmFishRunning=true
                KhfreshState.SelectedAutoFarmCastSerial=0
                KhfreshState.SelectedAutoFarmActiveCastSerial=0
                KhfreshState.SelectedAutoFarmCastToken=nil
                selectedIslandIndex=1
                KhfreshState.SelectedAutoFarmIslandIndex=1
                selectedLastIsland=nil
                clearCaughtState()
                KhfreshState.SelectedAutoFarmPhase="Idle"
                KhfreshState.SelectedAutoFarmCurrentIsland=selectedCurrentIsland()
                KhfreshState.SelectedAutoFarmCastIssuedAt=0
                KhfreshState.SelectedAutoFarmLastCancelAt=0

                -- Selected Fish is exclusive: stop every generic fishing owner from
                -- issuing a cast or moving the catch bar underneath this state machine.
                Fishing.Flags.MainFarm=false
                Fishing.Flags.AutoCast=false
                Fishing.Flags.AutoFarmBoss=false
                Fishing.Flags.AutoFarmSecretBoss=false
                Fishing.Flags.AnchorLock=false
                MiscFlags.AutoEquipRod=true
                Fishing.BossFarm.PendingCancel=false
                Fishing.BossFarm.HasHooked=false
                Fishing.BossFarm.CurrentToken=nil

                cancelExistingCastBeforeStart()
                waitForFishingIdle(1.5)

                local islandNumber=selectedCurrentIsland()
                if islandNumber then
                    local tpOk=teleportToSelectedIsland(islandNumber,true)
                    warn("[Khfresh][SelectedFish] START island="..tostring(islandNumber).." teleport="..tostring(tpOk))
                    if tpOk then
                        task.wait(0.25)
                        selectedFishEquipRod()
                        selectedLastIsland=islandNumber
                    end
                end
                return true
            end

            local function stopSelectedFishFarm()
                fishFarmRunning=false
                KhfreshState.SelectedAutoFarmFishRunning=false
                KhfreshState.SelectedAutoFarmFishSet={}
                KhfreshState.SelectedAutoFarmFishByIsland={}
                KhfreshState.SelectedAutoFarmCaughtByIsland={}
                KhfreshState.SelectedAutoFarmCastToken=nil
                KhfreshState.SelectedAutoFarmActiveCastSerial=0
                KhfreshState.SelectedAutoFarmCastSerial=(tonumber(KhfreshState.SelectedAutoFarmCastSerial) or 0)+1
                KhfreshState.SelectedAutoFarmPhase="Idle"
                KhfreshState.SelectedAutoFarmKeepCurrent=false
                KhfreshState.SelectedAutoFarmCurrentIsland=nil
                KhfreshState.SelectedAutoFarmCastIssuedAt=0
                Fishing.BossFarm.PendingCancel=false
                Fishing.BossFarm.HasHooked=false
                Fishing.BossFarm.CurrentToken=nil
                Fishing.Flags.MainFarm=false
                Fishing.Flags.AutoCast=false
                MiscFlags.AutoEquipRod=false
                if fishFarmThread then pcall(task.cancel,fishFarmThread) fishFarmThread=nil end
            end

            FishFarmSection:CreateToggle({
                Name="Enable Auto Farm Selected Fish", Default=false,
                Callback=function(value)
                    value=value==true
                    if not value then
                        stopSelectedFishFarm()
                        KhfreshLib:Notify({Title="Selected Fish",Message="Stopped.",Duration=2})
                        return
                    end
                    if not startSelectedFishFarm() then return end
                    if fishFarmThread then pcall(task.cancel,fishFarmThread) end
                    fishFarmThread=task.spawn(function()
                        while fishFarmRunning and alive() do
                            pcall(function()
                                if #selectedFishEntries==0 then stopSelectedFishFarm(); return end
                                local islandNumber=tonumber(KhfreshState.SelectedAutoFarmCurrentIsland) or selectedCurrentIsland()
                                if not islandNumber then return end

                                local phase=KhfreshState.SelectedAutoFarmPhase or "Idle"
                                local char=LocalPlayer.Character
                                if not char then return end

                                if phase=="Idle" then
                                    local island=getIslandEntry(islandNumber)
                                    local hrp=char:FindFirstChild("HumanoidRootPart")
                                    if not island or not island.cframe or not hrp then
                                        if islandNumber >= 12 and (tick() - (KhfreshState.SelectedAutoFarmLastIslandWarn or 0)) > 4 then
                                            KhfreshState.SelectedAutoFarmLastIslandWarn = tick()
                                            KhfreshLib:Notify({Title="Selected Fish", Message="Waiting for live position of "..tostring(KH_ISLAND_LABELS[islandNumber] or islandNumber)..".", Duration=4})
                                        end
                                        return
                                    end
                                    local targetPos=island.cframe.Position+Vector3.new(0,3,0)
                                    local dist=(hrp.Position-targetPos).Magnitude
                                    if dist>35 then
                                        local tpOk=teleportToSelectedIsland(islandNumber,false)
                                        if tpOk then
                                            selectedLastIsland=islandNumber
                                            task.wait(0.2)
                                            selectedFishEquipRod()
                                        elseif islandNumber >= 12 and (tick() - (KhfreshState.SelectedAutoFarmLastIslandWarn or 0)) > 4 then
                                            KhfreshState.SelectedAutoFarmLastIslandWarn = tick()
                                            KhfreshLib:Notify({Title="Selected Fish", Message="Waiting for live position of "..tostring(KH_ISLAND_LABELS[islandNumber] or islandNumber).." in Workspace; no coordinates were guessed.", Duration=4})
                                        end
                                        return
                                    end
                                    if selectedLastIsland~=islandNumber then
                                        selectedLastIsland=islandNumber
                                        selectedFishEquipRod()
                                    end
                                    selectedFishAutoCast()
                                    return
                                end

                                if phase=="WaitingForMinigame" then
                                    local age=tick()-(tonumber(KhfreshState.SelectedAutoFarmCastIssuedAt) or tick())
                                    if age>=7 and not char:GetAttribute("Fishing") and not char:GetAttribute("Retractable") then
                                        warn("[Khfresh][SelectedFish] CAST timeout -> retry same island")
                                        KhfreshState.SelectedAutoFarmPhase="Idle"
                                    end
                                    return
                                end

                                if phase=="Minigame" then return end

                                if phase=="Cancelling" then
                                    local age=tick()-(tonumber(KhfreshState.SelectedAutoFarmLastCancelAt) or tick())
                                    if age>=0.25 and not char:GetAttribute("Fishing") and not char:GetAttribute("Retractable") then
                                        KhfreshState.SelectedAutoFarmPhase="Idle"
                                    end
                                    return
                                end
                            end)
                            task.wait(0.1)
                        end
                    end)
                end,
            })
        end

        local AutoFarm = KhfreshState.AutoFarm
        local AutoFarmSection = FarmingTab:CreateSection("Auto Farm")

        -- Island selection dropdown
        local islandOptions = {}
        for _, island in ipairs(KhfreshState.islands) do
            table.insert(islandOptions, island.name)
        end
        -- Exactly 13 labels from islands table (no extra World Angler / Weather duplicates)
        local islandDropdown = AutoFarmSection:CreateDropdown({
            Name = "Select Island",
            Options = islandOptions,
            Default = AutoFarm.selectedIsland or islandOptions[1] or "Beginning Isle | Isle 1",
            Callback = function(value)
                AutoFarm.selectedIsland = value
            end
        })
        if not AutoFarm.selectedIsland then
            AutoFarm.selectedIsland = islandOptions[1] or "Beginning Isle | Isle 1"
        end



        -- Toggle Enable
        local autoFarmToggle = AutoFarmSection:CreateToggle({
            Name = "Enable Auto Farm Fish",
            Default = AutoFarm.enabled == true,
            Callback = function(value)
                value = value == true
                AutoFarm.enabled = value
                if value then
                    -- Normal Auto Farm takes ownership and re-enables island teleport mode.
                    AutoFarm.inYourPosition = false
                    AutoFarm.inYourPositionCFrame = nil
                    AutoFarm.inYourPositionStartedFarm = false
                    -- Auto Farm always owns the core fishing pipeline. Filters are optional.
                    Fishing.Flags.MainFarm = true
                    Fishing.Flags.AutoCast = true
                    Fishing.Flags.AnchorLock = true
                    MiscFlags.AutoEquipRod = true
                    Fishing.Flags.AutoFarmBoss = AutoFarmFilters.Boss == true
                    Fishing.Flags.AutoFarmSecretBoss = AutoFarmFilters.SecretBoss == true
                    Fishing.Flags.AntiAFK = AutoFarmFilters.AntiAFK == true
                    enableBasicFishing(false)
                    -- Auto Farm must not silently enable Auto Skill.
                    Fishing.Flags.AutoSkill = (KhfreshState.savedRoutineFlags and KhfreshState.savedRoutineFlags.AutoSkill) == true
                    -- Basic Auto Farm is valid with zero filters: that means normal fish.
                    -- Boss/Secret filters only narrow the target when their switches are enabled.
                    KhfreshLib:Notify({
                        Title = "Auto Farm",
                        Message = "Enabled: Auto Equip Rod + Auto Cast + Lock Catch Bar",
                        Duration = 3
                    })
                else
                    khHardResetAutoFarmState()
                    KhfreshLib:Notify({ Title = "Auto Farm", Message = "Disabled — state reset", Duration = 2 })
                end
            end
        })
        KhfreshState.autoFarmToggle = autoFarmToggle

        -- Farm at the exact position where the player is standing.
        -- This is a MODE switch for Auto Farm: it keeps Auto Equip Rod + Auto Cast,
        -- but completely disables the island teleport loop while enabled.
        local autoFarmPositionToggle = AutoFarmSection:CreateToggle({
            Name = "Auto Farm In Your Position",
            Icon = "map-pin",
            Default = AutoFarm.inYourPosition == true,
            Callback = function(value)
                value = value == true
                if value then
                    local char = LocalPlayer.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    if not hrp then
                        KhfreshLib:Notify({
                            Title = "Auto Farm In Your Position",
                            Message = "HumanoidRootPart not found.",
                            Duration = 3
                        })
                        return
                    end

                    AutoFarm.inYourPosition = true
                    AutoFarm.inYourPositionCFrame = hrp.CFrame
                    AutoFarm.inYourPositionStartedFarm = not AutoFarm.enabled
                    AutoFarm.enabled = true

                    Fishing.Flags.MainFarm = true
                    Fishing.Flags.AutoCast = true
                    Fishing.Flags.AnchorLock = true
                    MiscFlags.AutoEquipRod = true
                    Fishing.Flags.AutoFarmBoss = AutoFarmFilters.Boss == true
                    Fishing.Flags.AutoFarmSecretBoss = AutoFarmFilters.SecretBoss == true
                    Fishing.Flags.AntiAFK = AutoFarmFilters.AntiAFK == true
                    enableBasicFishing(false)
                    Fishing.Flags.AutoSkill = (KhfreshState.savedRoutineFlags and KhfreshState.savedRoutineFlags.AutoSkill) == true

                    pcall(forceEquipRodOnce)
                    KhfreshLib:Notify({
                        Title = "Auto Farm In Your Position",
                        Message = "Farming at your current position — no teleport.",
                        Duration = 3
                    })
                else
                    local wasOwner = AutoFarm.inYourPositionStartedFarm == true
                    AutoFarm.inYourPosition = false
                    AutoFarm.inYourPositionCFrame = nil
                    AutoFarm.inYourPositionStartedFarm = false
                    KhfreshState.lastPosition = nil

                    if wasOwner then
                        khHardResetAutoFarmState()
                    end

                    KhfreshLib:Notify({
                        Title = "Auto Farm In Your Position",
                        Message = wasOwner and "Disabled — state reset." or "Position mode off — normal Auto Farm may stay on.",
                        Duration = 2
                    })
                end
            end
        })
        KhfreshState.autoFarmPositionToggle = autoFarmPositionToggle

        -- No continuous rod-equip loop (blocks inventory). Equip only once on enable.

        -- Island farm loop: teleport to selected island (original position)
        task.spawn(function()
            local lastNotifiedIsland = nil
            local lastTPAt = 0
            while alive() do
                if AutoFarm.enabled and AutoFarm.inYourPosition then
                    -- no teleport in position mode
                elseif AutoFarm.enabled and AutoFarm.selectedIsland then
                    local targetIsland = khResolveIslandEntry(AutoFarm.selectedIsland)
                    if targetIsland and targetIsland.cframe then
                        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            local targetPos = targetIsland.cframe.Position + Vector3.new(0, 4, 0)
                            local targetDisplayName = targetIsland.displayName or targetIsland.name
                            -- Horizontal distance only (ignore Y jitter / falling)
                            local flat = Vector3.new(hrp.Position.X - targetPos.X, 0, hrp.Position.Z - targetPos.Z)
                            local needTP = flat.Magnitude > 120
                            local now = tick()
                            -- At most one TP every 8s; never spam
                            if needTP and (now - lastTPAt) > 8 then
                                lastTPAt = now
                                khTeleportToIslandCoordinates(targetIsland)
                                if lastNotifiedIsland ~= targetDisplayName then
                                    lastNotifiedIsland = targetDisplayName
                                    KhfreshLib:Notify({
                                        Title = "Auto Farm",
                                        Message = "Teleported to " .. tostring(targetDisplayName),
                                        Duration = 2
                                    })
                                end
                            end
                        end
                    end
                else
                    lastNotifiedIsland = nil
                    lastTPAt = 0
                end
                task.wait(1.5)
            end
        end)
    end
end

-- ===== SHOP TAB =====
do
    local ShopTab = Window:CreateTab("Shop")

    -- Index
    do
        local IndexSection = ShopTab:CreateSection("Index")
        IndexSection:CreateButton({
            Name = "Unlock all fish",
            Callback = function()
                local userData = Data:FindFirstChild(tostring(LocalPlayer.UserId))
                if not userData then
                    KhfreshLib:Notify({ Title = "Index", Message = "User data not found!", Duration = 2 })
                    return
                end
                local indexFolder = userData:FindFirstChild("Index")
                if not indexFolder then
                    KhfreshLib:Notify({ Title = "Index", Message = "Index folder not found!", Duration = 2 })
                    return
                end
                local count = 0
                for _, child in ipairs(indexFolder:GetChildren()) do
                    if child:IsA("NumberValue") or child:IsA("IntValue") then
                        child.Value = 1
                        count = count + 1
                    elseif child:IsA("BoolValue") then
                        child.Value = true
                        count = count + 1
                    end
                end
                KhfreshLib:Notify({ Title = "Index", Message = "Unlocked " .. count .. " fish!", Duration = 3 })
            end
        })
    end

    -- Upgrade Skill
    do
        local UpgradeSkillSection = ShopTab:CreateSection("Upgrade Skill")
        local function GetOwnedSkills()
            local userId = LocalPlayer and LocalPlayer.UserId
            if not userId then return {} end
            local userData = Data and Data:FindFirstChild(tostring(userId))
            if not userData then return {} end
            local skillFolder = userData:FindFirstChild("Skill")
            if not skillFolder then return {} end
            local ownedSkills = {}
            for _, child in pairs(skillFolder:GetChildren()) do
                if child:IsA("Folder") then
                    local owned = child:FindFirstChild("Owned")
                    if owned and owned:IsA("BoolValue") and owned.Value == true then
                        table.insert(ownedSkills, child.Name)
                    end
                end
            end
            return ownedSkills
        end

        local skillOptions = GetOwnedSkills()
        if #skillOptions == 0 then skillOptions = { "No skill owned" } end
        local selectedSkill = skillOptions[1] or "No skill owned"

        local skillDropdown = UpgradeSkillSection:CreateDropdown({
            Name = "Choose A Skill That Needs To Upgrade",
            Options = skillOptions,
            Default = selectedSkill,
            Callback = function(value) selectedSkill = value end
        })

        local upgradeSkillMethodDropdown = UpgradeSkillSection:CreateDropdown({
            Name = "Upgrade Method",
            Options = { "Instant", "Teleport" },
            Default = KhfreshState.upgradeSkill.method or "Instant",
            Callback = function(value) KhfreshState.upgradeSkill.method = value end
        })

        UpgradeSkillSection:CreateButton({
            Name = "Upgrade Selected Skill",
            Callback = function()
                if selectedSkill == "No skill owned" or not selectedSkill then
                    KhfreshLib:Notify({ Title = "Upgrade Skill", Message = "No skill selected!", Duration = 2 })
                    return
                end
                local userId = LocalPlayer and LocalPlayer.UserId
                if not userId then
                    KhfreshLib:Notify({ Title = "Upgrade Skill", Message = "Player not ready!", Duration = 2 })
                    return
                end
                local userData = Data and Data:FindFirstChild(tostring(userId))
                if not userData then
                    KhfreshLib:Notify({ Title = "Upgrade Skill", Message = "User data not found!", Duration = 2 })
                    return
                end
                local essenceOrb = userData:FindFirstChild("EssenceOrb")
                if not essenceOrb or not essenceOrb:IsA("NumberValue") then
                    KhfreshLib:Notify({ Title = "Upgrade Skill", Message = "EssenceOrb not found!", Duration = 2 })
                    return
                end
                if essenceOrb.Value <= 0 then
                    KhfreshLib:Notify({ Title = "Upgrade Skill", Message = "Not enough EssenceOrb!", Duration = 2 })
                    return
                end
                if not Events or not Events.UpgradeSkill then
                    KhfreshLib:Notify({ Title = "Upgrade Skill", Message = "UpgradeSkill remote not found!", Duration = 2 })
                    return
                end

                KhfreshState.upgradeSkill.teleported = false
                KhfreshState.upgradeSkill.oldPosition = nil
                if KhfreshState.upgradeSkill.method == "Teleport" then
                    local npc = Workspace:FindFirstChild("NPC")
                    if npc then
                        local func = npc:FindFirstChild("Function")
                        if func then
                            local zengTianguo = func:FindFirstChild("Zeng Tianguo")
                            if zengTianguo and zengTianguo:IsA("Model") then
                                local hrp = zengTianguo:FindFirstChild("HumanoidRootPart")
                                if hrp then
                                    local char = LocalPlayer.Character
                                    if char then
                                        local root = char:FindFirstChild("HumanoidRootPart")
                                        if root then
                                            KhfreshState.upgradeSkill.oldPosition = root.Position
                                            root.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 3, 0))
                                            KhfreshState.upgradeSkill.teleported = true
                                            task.wait(0.3)
                                        end
                                    end
                                end
                            end
                        end
                    end
                    if not KhfreshState.upgradeSkill.teleported then
                        KhfreshLib:Notify({ Title = "Upgrade Skill", Message =
                        "Could not find Zeng Tianguo, teleport failed. Continuing anyway.", Duration = 3 })
                    end
                end

                local success, err = pcall(function()
                    return safeInvoke("UpgradeSkill", selectedSkill)
                end)

                if KhfreshState.upgradeSkill.teleported and KhfreshState.upgradeSkill.oldPosition then
                    task.wait(0.2)
                    local char = LocalPlayer.Character
                    if char then
                        safeRestorePosition(KhfreshState.upgradeSkill)
                    end
                end

                if success then
                    KhfreshLib:Notify({ Title = "Upgrade Skill", Message = "Upgraded " .. selectedSkill .. "!", Duration = 2 })
                else
                    KhfreshLib:Notify({ Title = "Upgrade Skill", Message = "Failed: " .. tostring(err), Duration = 2 })
                end
            end
        })
    end

    -- Craft Rod
    do
        local CraftRodSection = ShopTab:CreateSection("Craft Rod")
        local ROD_RECIPES = {
            ["Heavenpiercer Rod"] = {
                { name = "Flying Fish Emperor",  minKg = 1000000, maxKg = 3000000 },
                { name = "Flying Fish Empress",  minKg = 1000000, maxKg = 3000000 },
                { name = "Heavenpiercer Turtle", minKg = 3000000, maxKg = 6000000 },
                { name = "Rainbow Dragonfish",   minKg = 5000000, maxKg = 8000000 },
            },
            ["Pure Diamond Rod"] = {
                { name = "Frost Kingfish",  minKg = 4000000, maxKg = 7000000 },
                { name = "Frost Queenfish", minKg = 4000000, maxKg = 8000000 },
                { name = "Sanguine Fish",   minKg = 3000000, maxKg = 6000000 },
                { name = "Draconic Koi",    minKg = 1000000, maxKg = 3000000 },
            },
            ["Sacred Bamboo Rod"] = {
                { name = "Nameless Octoparasite", minKg = 6000000, maxKg = 9000000 },
                { name = "Reborn Puffer Beast",   minKg = 4000000, maxKg = 6000000 },
                { name = "Ascended Perch",        minKg = 900000,  maxKg = 1000000 },
                { name = "Mountain Fish",         minKg = 1000000, maxKg = 5000000 },
            }
        }

        local rodOptions = { "Heavenpiercer Rod", "Pure Diamond Rod", "Sacred Bamboo Rod" }
        local selectedRod = rodOptions[1]

        local rodDropdown = CraftRodSection:CreateDropdown({
            Name = "Select Rod to Craft",
            Options = rodOptions,
            Default = selectedRod,
            Callback = function(value) selectedRod = value end
        })

        CraftRodSection:CreateDropdown({
            Name = "Craft Method",
            Options = { "Instant", "Teleport" },
            Default = "Instant",
            Callback = function(value) KhfreshState.craftRodMethod = value end
        })

        local function checkRodMaterials(rodName)
            local recipe = ROD_RECIPES[rodName]
            if not recipe then return false, "Recipe not found for " .. rodName end
            local userData = Data:FindFirstChild(tostring(LocalPlayer.UserId))
            if not userData then return false, "Player data not found" end
            local inventory = userData:FindFirstChild("Inventory")
            if not inventory then return false, "Inventory not found" end
            local fishCount = {}
            for _, req in ipairs(recipe) do fishCount[req.name] = 0 end
            for _, item in pairs(inventory:GetChildren()) do
                local fishName = item.Name
                if fishName and fishName ~= "" then
                    local req = nil
                    for _, r in ipairs(recipe) do
                        if r.name == fishName then
                            req = r; break
                        end
                    end
                    if req then
                        local weightString = nil
                        if item:IsA("StringValue") then
                            local parts = {}
                            for part in string.gmatch(item.Value, "[^|]+") do table.insert(parts, part) end
                            if #parts >= 2 then weightString = parts[2]:gsub("^%s+", ""):gsub("%s+$", "") end
                        elseif item:IsA("NumberValue") or item:IsA("IntValue") then
                            weightString = tostring(item.Value)
                        end
                        if weightString then
                            local weight = tonumber(weightString)
                            if weight and weight >= req.minKg and weight <= req.maxKg then
                                fishCount[req.name] = fishCount[req.name] + 1
                            end
                        end
                    end
                end
            end
            local missing = {}
            for _, req in ipairs(recipe) do
                local count = fishCount[req.name] or 0
                if count < 1 then
                    table.insert(missing, req.name .. " (need 1, have " .. count .. ")")
                end
            end
            if #missing > 0 then
                return false, "Missing materials: " .. table.concat(missing, ", ")
            end
            return true, "All materials ready!"
        end

        local function craftRod()
            local ok, msg = checkRodMaterials(selectedRod)
            if not ok then
                KhfreshLib:Notify({ Title = "Craft Rod", Message = msg, Duration = 4 })
                return
            end
            local method = KhfreshState.craftRodMethod or "Instant"
            local teleported = false
            if method == "Teleport" then
                local npc = Workspace:FindFirstChild("NPC")
                if npc then
                    local buyRod = npc:FindFirstChild("BuyFishingRod")
                    if buyRod then
                        local biaoDi = buyRod:FindFirstChild("Biao Di")
                        if biaoDi and biaoDi:IsA("Model") then
                            local hrp = biaoDi:FindFirstChild("HumanoidRootPart")
                            if hrp then
                                local char = LocalPlayer.Character
                                if char then
                                    local root = char:FindFirstChild("HumanoidRootPart")
                                    if root then
                                        KhfreshState.lastCraftPosition = root.Position
                                        root.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 3, 0))
                                        teleported = true
                                        task.wait(0.3)
                                    end
                                end
                            end
                        end
                    end
                end
            end
            local success, err = pcall(function()
                safeFire("CraftRod", selectedRod)
            end)
            if success then
                KhfreshLib:Notify({ Title = "Craft Rod", Message = "Crafted " .. selectedRod .. " successfully!", Duration = 2 })
            else
                KhfreshLib:Notify({ Title = "Craft Rod", Message = "Failed: " .. tostring(err), Duration = 2 })
            end
            if teleported and KhfreshState.lastCraftPosition then
                task.wait(0.3)
                local char = LocalPlayer.Character
                if char then
                    local root = char:FindFirstChild("HumanoidRootPart")
                    if root then
                        root.CFrame = CFrame.new(KhfreshState.lastCraftPosition)
                        KhfreshState.lastCraftPosition = nil
                    end
                end
            end
        end

        CraftRodSection:CreateButton({ Name = "Craft rod now", Callback = craftRod })
        local autoCraftRodToggle = CraftRodSection:CreateToggle({
            Name = "Auto craft selected rod",
            Default = false,
            Callback = function(value)
                KhfreshState.autoCraftRodRunning = value
                if value then
                    if KhfreshState.autoCraftRodThread then
                        task.cancel(KhfreshState.autoCraftRodThread)
                        KhfreshState.autoCraftRodThread = nil
                    end
                    KhfreshState.autoCraftRodThread = task.spawn(function()
                        while KhfreshState.autoCraftRodRunning do
                            pcall(craftRod)
                            task.wait(5)
                        end
                    end)
                else
                    if KhfreshState.autoCraftRodThread then
                        task.cancel(KhfreshState.autoCraftRodThread)
                        KhfreshState.autoCraftRodThread = nil
                    end
                end
            end
        })
    end

    -- Auto Buy Bait
    do
        local BuySection = ShopTab:CreateSection("Auto Buy Bait")

        local buyableBaits = GetBuyableBaits()
        -- Locked state: always used by FireServer (dropdown/textbox only write here)
        local buyState = {
            name = (KhfreshState.selectedBait and KhfreshState.selectedBait ~= "No bait available")
                and KhfreshState.selectedBait or (buyableBaits[1] or "No bait available"),
            qty = math.clamp(math.floor(tonumber(KhfreshState.buyBaitQuantity) or 100), 1, 100),
            threshold = math.floor(tonumber(KhfreshState.buyBaitThreshold) or 5),
            method = KhfreshState.buyBaitMethod or "Instant",
        }
        KhfreshState.selectedBait = buyState.name
        KhfreshState.buyBaitQuantity = buyState.qty

        local function resolveBaitName(raw)
            if type(raw) == "table" then
                raw = raw[1] or raw.Name or raw.Value or raw.Text
            end
            local want = tostring(raw or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if want == "" or want == "No bait available" then return nil end
            -- Exact match first
            for _, n in ipairs(buyableBaits) do
                if n == want then return n end
            end
            -- Case-insensitive
            local lower = string.lower(want)
            for _, n in ipairs(buyableBaits) do
                if string.lower(n) == lower then return n end
            end
            -- Partial
            for _, n in ipairs(buyableBaits) do
                if string.find(string.lower(n), lower, 1, true) then return n end
            end
            return want
        end

        local function fireBuyBait(name, qty)
            name = resolveBaitName(name)
            qty = math.clamp(math.floor(tonumber(qty) or 1), 1, 100)
            if not name or name == "No bait available" then
                return false, "no bait"
            end
            print("[Khfresh][BuyBait] FireServer", name, "x", qty)
            local remote = Events and Events:FindFirstChild("BuyBait")
            if not remote then return false, "no remote" end
            local ok, err = pcall(function()
                remote:FireServer(name, qty)
            end)
            return ok, err
        end

        BuySection:CreateDropdown({
            Name = "Select Bait to Buy",
            Options = buyableBaits,
            Default = buyState.name,
            Callback = function(value)
                local name = resolveBaitName(value)
                if name then
                    buyState.name = name
                    KhfreshState.selectedBait = name
                    print("[Khfresh][BuyBait] selected =", name)
                end
            end
        })

        BuySection:CreateTextbox({
            Name = "Buy Amount",
            Placeholder = "100",
            Default = tostring(buyState.qty),
            Callback = function(value)
                local num = tonumber(tostring(value):match("%d+") or "")
                if num and num >= 1 then
                    buyState.qty = math.clamp(math.floor(num), 1, 100)
                    KhfreshState.buyBaitQuantity = buyState.qty
                    print("[Khfresh][BuyBait] qty =", buyState.qty)
                end
            end
        })

        BuySection:CreateTextbox({
            Name = "Buy When Below",
            Placeholder = "5",
            Default = tostring(buyState.threshold),
            Callback = function(value)
                local num = tonumber(tostring(value):match("%d+") or "")
                if num and num >= 0 then
                    buyState.threshold = math.floor(num)
                    KhfreshState.buyBaitThreshold = buyState.threshold
                end
            end
        })

        BuySection:CreateDropdown({
            Name = "Buy Method",
            Options = { "Instant", "Teleport" },
            Default = buyState.method,
            Callback = function(value)
                buyState.method = tostring(value or "Instant")
                KhfreshState.buyBaitMethod = buyState.method
            end
        })

        BuySection:CreateButton({
            Name = "Buy Now",
            Callback = function()
                local baitName = buyState.name
                local qty = buyState.qty
                if not baitName or baitName == "No bait available" then
                    KhfreshLib:Notify({ Title = "Buy Bait", Message = "No bait selected", Duration = 2 })
                    return
                end
                local baitMerchant = findBaitMerchantHRP()
                local char = LocalPlayer.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                local origCFrame = root and root.CFrame
                if (buyState.method == "Teleport" or true) and baitMerchant and root then
                    root.CFrame = CFrame.new(baitMerchant.Position + Vector3.new(0, 2, 0))
                    task.wait(0.2)
                end
                local ok, err = fireBuyBait(baitName, qty)
                if origCFrame and root then
                    task.wait(0.15)
                    root.CFrame = origCFrame
                end
                if ok then
                    KhfreshLib:Notify({
                        Title = "Buy Bait",
                        Message = "Bought " .. tostring(qty) .. "x " .. tostring(baitName),
                        Duration = 2
                    })
                else
                    KhfreshLib:Notify({ Title = "Buy Bait", Message = "Failed: " .. tostring(err), Duration = 2 })
                end
            end
        })

        local autoBuyToggle = BuySection:CreateToggle({
            Name = "Auto Buy Bait",
            Default = false,
            Callback = function(value)
                MiscFlags.AutoBuy = value
                if value then
                    KhfreshLib:Notify({ Title = "Auto Buy", Message = "[ON] Buy " ..
                    KhfreshState.buyBaitQuantity ..
                    " " .. KhfreshState.selectedBait .. " when below " .. KhfreshState.buyBaitThreshold, Duration = 3 })
                else
                    KhfreshLib:Notify({ Title = "Auto Buy", Message = "OFF", Duration = 2 })
                end
            end
        })

        task.spawn(function()
            local lastBuyTick = 0
            while task.wait(1) do
                if not alive() then break end
                if MiscFlags.AutoBuy and (tick() - lastBuyTick) > 3 then
                    local baitName = buyState.name
                    local qty = buyState.qty
                    local threshold = buyState.threshold
                    if baitName and baitName ~= "No bait available" then
                        local count = -1
                        pcall(function()
                            local userData = Data:FindFirstChild(tostring(LocalPlayer.UserId))
                            if not userData then return end
                            local baitFolder = userData:FindFirstChild("Bait")
                            if not baitFolder then return end
                            local bait = baitFolder:FindFirstChild(baitName)
                            if not bait then return end
                            if bait:IsA("NumberValue") or bait:IsA("IntValue") then
                                count = bait.Value
                            else
                                local amt = bait:FindFirstChild("Amount") or bait:FindFirstChild("Value") or bait:FindFirstChild("Count")
                                if amt and (amt:IsA("NumberValue") or amt:IsA("IntValue")) then
                                    count = amt.Value
                                elseif bait:GetAttribute("Amount") then
                                    count = tonumber(bait:GetAttribute("Amount")) or -1
                                end
                            end
                        end)
                        if count >= 0 and count < threshold then
                            lastBuyTick = tick()
                            local baitMerchant = findBaitMerchantHRP()
                            local char = LocalPlayer.Character
                            local root = char and char:FindFirstChild("HumanoidRootPart")
                            local origCFrame = root and root.CFrame
                            if baitMerchant and root then
                                root.CFrame = CFrame.new(baitMerchant.Position + Vector3.new(0, 2, 0))
                                task.wait(0.2)
                            end
                            fireBuyBait(buyState.name, buyState.qty)
                            if origCFrame and root then
                                task.wait(0.15)
                                root.CFrame = origCFrame
                            end
                            KhfreshLib:Notify({
                                Title = "Auto Buy",
                                Message = buyState.name .. ": " .. count .. " left → bought x" .. tostring(buyState.qty),
                                Duration = 2
                            })
                        end
                    end
                end
            end
        end)
    end

    -- Auto Buy Rod
    do
        local RodSection = ShopTab:CreateSection("Auto Buy Rod")
        local function GetBuyableRods()
            local p = Data and Data:FindFirstChild(tostring(LocalPlayer.UserId))
            if not p then return { "No rod available" } end
            local rods = {}
            local inv = p:FindFirstChild("FishingRodInventory")
            if not inv then return { "No rod available" } end
            for _, rodFolder in pairs(inv:GetChildren()) do
                if rodFolder:IsA("Folder") then
                    local owned = rodFolder:FindFirstChild("Owned")
                    if owned and owned.Value == false then
                        local mod = Info and Info.Inventory and Info.Inventory:FindFirstChild(rodFolder.Name)
                        if mod then
                            table.insert(rods, rodFolder.Name)
                        end
                    end
                end
            end
            if #rods == 0 then return { "No rod available" } end
            return rods
        end

        local buyableRods = GetBuyableRods()
        local selectedRod = buyableRods[1] or "No rod available"

        local rodDropdown = RodSection:CreateDropdown({
            Name = "Select Rod to Buy",
            Options = buyableRods,
            Default = selectedRod,
            Callback = function(value) selectedRod = value end
        })

        local buyRodMethodDropdown = RodSection:CreateDropdown({
            Name = "Buy Method",
            Options = { "Instant", "Teleport" },
            Default = KhfreshState.buyRod.method or "Instant",
            Callback = function(value) KhfreshState.buyRod.method = value end
        })

        RodSection:CreateButton({
            Name = "Buy Selected Rod",
            Callback = function()
                if selectedRod == "No rod available" then
                    KhfreshLib:Notify({ Title = "Buy Rod", Message = "No rod available to buy", Duration = 2 })
                    return
                end
                KhfreshState.buyRod.teleported = false
                KhfreshState.buyRod.oldPosition = nil
                if KhfreshState.buyRod.method == "Teleport" then
                    local npc = Workspace:FindFirstChild("NPC")
                    if npc then
                        local buyFishingRod = npc:FindFirstChild("BuyFishingRod")
                        if buyFishingRod then
                            local biaoDi = buyFishingRod:FindFirstChild("Biao Di")
                            if biaoDi and biaoDi:IsA("Model") then
                                local hrp = biaoDi:FindFirstChild("HumanoidRootPart")
                                if hrp then
                                    local char = LocalPlayer.Character
                                    if char then
                                        local root = char:FindFirstChild("HumanoidRootPart")
                                        if root then
                                            KhfreshState.buyRod.oldPosition = root.Position
                                            root.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 3, 0))
                                            KhfreshState.buyRod.teleported = true
                                            task.wait(0.3)
                                        end
                                    end
                                end
                            end
                        end
                    end
                    if not KhfreshState.buyRod.teleported then
                        KhfreshLib:Notify({ Title = "Buy Rod", Message =
                        "Could not find Biao Di, teleport failed. Continuing anyway.", Duration = 3 })
                    end
                end
                pcall(function()
                    safeFire("BuyFishingRod", selectedRod)
                    KhfreshLib:Notify({ Title = "Buy Rod", Message = "Bought " .. selectedRod, Duration = 2 })
                end)
                if KhfreshState.buyRod.teleported and KhfreshState.buyRod.oldPosition then
                    task.wait(0.2)
                    local char = LocalPlayer.Character
                    if char then
                        safeRestorePosition(KhfreshState.buyRod)
                    end
                end
            end
        })
    end

    -- Learn Skills
    do
        local LearnSection = ShopTab:CreateSection("Learn Skills")
        local function GetLearnableSkills()
            local p = Data and Data:FindFirstChild(tostring(LocalPlayer.UserId))
            if not p then return { "No skill available" } end
            local skills = {}
            for _, skillFolder in pairs(p.Skill:GetChildren()) do
                if skillFolder:IsA("Folder") then
                    local owned = skillFolder:FindFirstChild("Owned")
                    if owned and owned.Value == false then
                        local mod = Info and Info.Skill and Info.Skill:FindFirstChild(skillFolder.Name)
                        if mod then
                            local ok, m = pcall(require, mod)
                            if ok and m and m.Price and m.Price > 0 then
                                table.insert(skills, skillFolder.Name)
                            end
                        end
                    end
                end
            end
            if #skills == 0 then return { "No skill available" } end
            return skills
        end

        local learnableSkills = GetLearnableSkills()
        local selectedLearnSkills = {}

        local learnDropdown = LearnSection:CreateDropdown({
            Name = "Select Skills to Learn",
        Multi = true,
            Options = learnableSkills,
            Default = {},
            Callback = function(values) selectedLearnSkills = values end
        })

        local learnMethodDropdown = LearnSection:CreateDropdown({
            Name = "Learn Method",
            Options = { "Instant", "Teleport" },
            Default = KhfreshState.learnSkill.method or "Instant",
            Callback = function(value) KhfreshState.learnSkill.method = value end
        })

        LearnSection:CreateButton({
            Name = "Learn Selected Skills",
            Callback = function()
                if #selectedLearnSkills == 0 then
                    KhfreshLib:Notify({ Title = "Learn Skills", Message = "No skills selected", Duration = 2 })
                    return
                end
                KhfreshState.learnSkill.teleported = false
                KhfreshState.learnSkill.oldPosition = nil
                if KhfreshState.learnSkill.method == "Teleport" then
                    local npc = Workspace:FindFirstChild("NPC")
                    if npc then
                        local learnSkill = npc:FindFirstChild("LearnSkill")
                        if learnSkill then
                            local sageYijiu = learnSkill:FindFirstChild("Sage Yijiu")
                            if sageYijiu and sageYijiu:IsA("Model") then
                                local hrp = sageYijiu:FindFirstChild("HumanoidRootPart")
                                if hrp then
                                    local char = LocalPlayer.Character
                                    if char then
                                        local root = char:FindFirstChild("HumanoidRootPart")
                                        if root then
                                            KhfreshState.learnSkill.oldPosition = root.Position
                                            root.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 3, 0))
                                            KhfreshState.learnSkill.teleported = true
                                            task.wait(0.3)
                                        end
                                    end
                                end
                            end
                        end
                    end
                    if not KhfreshState.learnSkill.teleported then
                        KhfreshLib:Notify({ Title = "Learn Skills", Message =
                        "Could not find Sage Yijiu, teleport failed. Continuing anyway.", Duration = 3 })
                    end
                end
                local learnedCount = 0
                for _, skillName in ipairs(selectedLearnSkills) do
                    local success, err = pcall(function()
                        safeFire("BuySkill", skillName)
                    end)
                    if success then
                        learnedCount = learnedCount + 1
                        KhfreshLib:Notify({ Title = "Learn Skills", Message = "Learned " .. skillName, Duration = 2 })
                    else
                        KhfreshLib:Notify({ Title = "Learn Skills", Message = "Failed to learn " ..
                        skillName .. ": " .. tostring(err), Duration = 2 })
                    end
                    task.wait(0.3)
                end
                if KhfreshState.learnSkill.teleported and KhfreshState.learnSkill.oldPosition then
                    task.wait(0.2)
                    local char = LocalPlayer.Character
                    if char then
                        safeRestorePosition(KhfreshState.learnSkill)
                    end
                end
                KhfreshLib:Notify({ Title = "Learn Skills", Message = "Learned " .. learnedCount .. " skill(s)!", Duration = 3 })
            end
        })
    end

    -- Trait Reroll
    do
        local TraitSection = ShopTab:CreateSection("Trait Reroll")
        local function GetOwnedSkillNames()
            local p = Data and Data:FindFirstChild(tostring(LocalPlayer.UserId))
            if not p then return { "No skill owned" } end
            local skills = {}
            for _, f in pairs(p.Skill:GetChildren()) do
                if f:IsA("Folder") and f.Owned and f.Owned.Value == true then
                    table.insert(skills, f.Name)
                end
            end
            if #skills == 0 then return { "No skill owned" } end
            return skills
        end

        local function GetTraitNames()
            local traits = {}
            if not Info or not Info:FindFirstChild("Trait") then return { "No trait available" } end
            for _, child in pairs(Info.Trait:GetChildren()) do
                if child:IsA("ModuleScript") then
                    local ok, mod = pcall(require, child)
                    if ok and type(mod) == "table" and mod.Name then
                        table.insert(traits, mod.Name)
                    end
                end
            end
            if #traits == 0 then return { "No trait available" } end
            return traits
        end

        local ownedSkills = GetOwnedSkillNames()
        local selectedSkillForReroll = ownedSkills[1] or "No skill owned"
        local traitNames = GetTraitNames()
        local selectedTargetTrait = traitNames[1] or "No trait available"
        local ignoreLocked = false

        local traitSkillDropdown = TraitSection:CreateDropdown({
            Name = "Select Skill",
            Options = ownedSkills,
            Default = selectedSkillForReroll,
            Callback = function(value) selectedSkillForReroll = value end
        })

        local targetTraitDropdown = TraitSection:CreateDropdown({
            Name = "Target Trait",
            Options = traitNames,
            Default = selectedTargetTrait,
            Callback = function(value) selectedTargetTrait = value end
        })

        local ignoreLockedToggle = TraitSection:CreateToggle({ Name = "Ignore Locked", Default = false, Callback = function(
            value) ignoreLocked = value end })

        local rerollMethodDropdown = TraitSection:CreateDropdown({
            Name = "Reroll Method",
            Options = { "Instant", "Teleport" },
            Default = KhfreshState.Reroll.method or "Instant",
            Callback = function(value) KhfreshState.Reroll.method = value end
        })

        local RerollTrait = Events:FindFirstChild("RerollTrait")

        TraitSection:CreateButton({
            Name = "Reroll Until Trait",
            Callback = function()
                if KhfreshState.Reroll.running then
                    KhfreshState.Reroll.running = false
                    if KhfreshState.Reroll.thread then
                        task.cancel(KhfreshState.Reroll.thread)
                        KhfreshState.Reroll.thread = nil
                    end
                    if KhfreshState.Reroll.teleported and KhfreshState.Reroll.oldPosition then
                        local char = LocalPlayer.Character
                        if char then
                            safeRestorePosition(KhfreshState.Reroll)
                        end
                    end
                    KhfreshLib:Notify({ Title = "Reroll", Message = "Stopped", Duration = 2 })
                    return
                end

                local skillName = selectedSkillForReroll
                local targetTrait = selectedTargetTrait
                if not skillName or skillName == "" or skillName == "No skill owned" then
                    KhfreshLib:Notify({ Title = "Reroll", Message = "Select a valid skill", Duration = 2 })
                    return
                end
                if not targetTrait or targetTrait == "" or targetTrait == "No trait available" then
                    KhfreshLib:Notify({ Title = "Reroll", Message = "Select a target trait", Duration = 2 })
                    return
                end
                if not RerollTrait then
                    KhfreshLib:Notify({ Title = "Reroll", Message = "RerollTrait event not found", Duration = 2 })
                    return
                end
                local p = Data and Data:FindFirstChild(tostring(LocalPlayer.UserId))
                local rerollCount = p and p:FindFirstChild("Trait Reroll")
                if rerollCount and rerollCount.Value <= 0 then
                    KhfreshLib:Notify({ Title = "Reroll", Message = "No rerolls left!", Duration = 2 })
                    return
                end

                KhfreshState.Reroll.teleported = false
                KhfreshState.Reroll.oldPosition = nil
                if KhfreshState.Reroll.method == "Teleport" then
                    local npc = Workspace:FindFirstChild("NPC")
                    if npc then
                        local func = npc:FindFirstChild("Function")
                        if func then
                            local nanjiang = func:FindFirstChild("Nanjiang")
                            if nanjiang and nanjiang:IsA("Model") then
                                local hrp = nanjiang:FindFirstChild("HumanoidRootPart")
                                if hrp then
                                    local char = LocalPlayer.Character
                                    if char then
                                        local root = char:FindFirstChild("HumanoidRootPart")
                                        if root then
                                            KhfreshState.Reroll.oldPosition = root.Position
                                            root.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 3, 0))
                                            KhfreshState.Reroll.teleported = true
                                            task.wait(0.3)
                                        end
                                    end
                                end
                            end
                        end
                    end
                    if not KhfreshState.Reroll.teleported then
                        KhfreshLib:Notify({ Title = "Reroll", Message =
                        "Could not find Nanjiang, teleport failed. Continuing anyway.", Duration = 3 })
                    end
                end

                KhfreshState.Reroll.running = true
                KhfreshLib:Notify({ Title = "Reroll", Message = "Reroll started... Target: " .. targetTrait, Duration = 2 })

                KhfreshState.Reroll.thread = task.spawn(function()
                    local successCount = 0
                    while KhfreshState.Reroll.running do
                        local p2 = Data and Data:FindFirstChild(tostring(LocalPlayer.UserId))
                        local count = p2 and p2:FindFirstChild("Trait Reroll")
                        if count and count.Value <= 0 then
                            KhfreshLib:Notify({ Title = "Reroll", Message = "No rerolls left, stopping", Duration = 2 })
                            break
                        end
                        local success, result = pcall(function()
                            return RerollTrait:InvokeServer(skillName, ignoreLocked)
                        end)
                        if not success or not result then
                            KhfreshLib:Notify({ Title = "Reroll", Message = "Reroll failed, stopping", Duration = 2 })
                            break
                        end
                        successCount = successCount + 1
                        local traitName = result.Name
                        if traitName == targetTrait then
                            KhfreshLib:Notify({ Title = "Reroll", Message = "Got " ..
                            targetTrait .. " on " .. skillName .. " after " .. successCount .. " rerolls!", Duration = 3 })
                            break
                        end
                        task.wait(0.15)
                    end

                    if KhfreshState.Reroll.teleported and KhfreshState.Reroll.oldPosition then
                        local char = LocalPlayer.Character
                        if char then
                            safeRestorePosition(KhfreshState.Reroll)
                        end
                    end
                    KhfreshState.Reroll.running = false
                    KhfreshState.Reroll.thread = nil
                    KhfreshLib:Notify({ Title = "Reroll", Message = "Stopped", Duration = 2 })
                end)
            end
        })
    end

    -- Craft Bait
    do
        local CraftSection = ShopTab:CreateSection("Craft Bait")
        CraftSection:CreateTextbox({
            Name = "Number of baits to craft",
            Placeholder = "1",
            Default = "1",
            Callback = function(value)
                local num = tonumber(value)
                if num and num >= 1 then
                    KhfreshState.craftBaitQuantity = math.floor(num)
                else
                    KhfreshState.craftBaitQuantity = 1
                end
            end
        })

        CraftSection:CreateDropdown({
            Name = "Choose a Bait",
            Options = { "Rainbow Bait", "Frost Bait", "Nameless Bait" },
            Default = "Rainbow Bait",
            Callback = function(value) KhfreshState.craftBaitName = value end
        })

        CraftSection:CreateDropdown({
            Name = "Craft Method",
            Options = { "Instant", "Teleport" },
            Default = "Instant",
            Callback = function(value) KhfreshState.craftBaitMethod = value end
        })

        local BAIT_RECIPES = {
            ["Rainbow Bait"] = {
                { name = "Colossal Tigerfish",   minKg = 3000000, maxKg = 6000000 },
                { name = "Heavenpiercer Turtle", minKg = 3000000, maxKg = 6000000 },
                { name = "Golden Guardian Fish", minKg = 1000000, maxKg = 3000000 },
                { name = "Crimson Electric Eel", minKg = 3000000, maxKg = 4000000 },
            },
            ["Frost Bait"] = {
                { name = "Frost Kingfish",              minKg = 4000000, maxKg = 7000000 },
                { name = "Ascended Perch",              minKg = 900000,  maxKg = 1000000 },
                { name = "Primordial Kunfish Overlord", minKg = 1000000, maxKg = 1600000 },
                { name = "Warbringer Shark",            minKg = 500000,  maxKg = 800000 },
            },
            ["Nameless Bait"] = {
                { name = "Mountain Fish",      minKg = 1000000, maxKg = 5000000 },
                { name = "Tiger Mirefish",     minKg = 1000000, maxKg = 3000000 },
                { name = "Mirage Lanternfish", minKg = 3000000, maxKg = 5000000 },
                { name = "Octoparasitic Fish", minKg = 3000000, maxKg = 5000000 },
            }
        }

        local function checkMaterials(baitName, quantity)
            local recipe = BAIT_RECIPES[baitName]
            if not recipe then return false, "No recipe found for " .. baitName end
            local userData = Data:FindFirstChild(tostring(LocalPlayer.UserId))
            if not userData then return false, "Player data not found" end
            local inventory = userData:FindFirstChild("Inventory")
            if not inventory then return false, "Inventory not found" end
            local fishCount = {}
            for _, req in ipairs(recipe) do fishCount[req.name] = 0 end
            for _, item in pairs(inventory:GetChildren()) do
                local fishName = item.Name
                if fishName and fishName ~= "" then
                    local req = nil
                    for _, r in ipairs(recipe) do
                        if r.name == fishName then
                            req = r; break
                        end
                    end
                    if req then
                        local weightString = nil
                        if item:IsA("StringValue") then
                            local parts = {}
                            for part in string.gmatch(item.Value, "[^|]+") do table.insert(parts, part) end
                            if #parts >= 2 then weightString = parts[2]:gsub("^%s+", ""):gsub("%s+$", "") end
                        elseif item:IsA("NumberValue") or item:IsA("IntValue") then
                            weightString = tostring(item.Value)
                        end
                        if weightString then
                            local weight = tonumber(weightString)
                            if weight and weight >= req.minKg and weight <= req.maxKg then
                                fishCount[req.name] = fishCount[req.name] + 1
                            end
                        end
                    end
                end
            end
            local missing = {}
            for _, req in ipairs(recipe) do
                local count = fishCount[req.name] or 0
                if count < quantity then
                    table.insert(missing, req.name .. " (can " .. quantity .. ", co " .. count .. ")")
                end
            end
            if #missing > 0 then
                return false, "Missing materials: " .. table.concat(missing, ", ")
            end
            return true, "Materials are sufficient!"
        end

        local function craftBait()
            local qty = KhfreshState.craftBaitQuantity
            local ok, msg = checkMaterials(KhfreshState.craftBaitName, qty)
            if not ok then
                KhfreshLib:Notify({ Title = "Craft Bait", Message = msg, Duration = 4 })
                return
            end
            local method = KhfreshState.craftBaitMethod or "Instant"
            local teleported = false
            if method == "Teleport" then
                local npc = Workspace:FindFirstChild("NPC")
                if npc then
                    local buyBait = npc:FindFirstChild("BuyBait")
                    if buyBait then
                        local children = buyBait:GetChildren()
                        if #children >= 5 then
                            local targetModel = children[5]
                            if targetModel and targetModel:IsA("Model") then
                                local hrp = targetModel:FindFirstChild("HumanoidRootPart")
                                if hrp then
                                    local char = LocalPlayer.Character
                                    if char then
                                        local root = char:FindFirstChild("HumanoidRootPart")
                                        if root then
                                            KhfreshState.lastCraftBaitPosition = root.Position
                                            root.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 3, 0))
                                            teleported = true
                                            task.wait(0.3)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            local success, err = pcall(function()
                safeFire("CraftBait", KhfreshState.craftBaitName, qty)
            end)
            if success then
                KhfreshLib:Notify({ Title = "Craft Bait", Message = "Crafted " ..
                qty .. "x " .. KhfreshState.craftBaitName, Duration = 2 })
            else
                KhfreshLib:Notify({ Title = "Craft Bait", Message = "Failed: " .. tostring(err), Duration = 2 })
            end
            if teleported and KhfreshState.lastCraftBaitPosition then
                task.wait(0.3)
                local char = LocalPlayer.Character
                if char then
                    local root = char:FindFirstChild("HumanoidRootPart")
                    if root then
                        root.CFrame = CFrame.new(KhfreshState.lastCraftBaitPosition)
                        KhfreshState.lastCraftBaitPosition = nil
                    end
                end
            end
        end

        local autoCraftToggle = CraftSection:CreateToggle({
            Name = "Auto craft bait",
            Default = false,
            Callback = function(value)
                KhfreshState.autoCraftRunning = value
                if value then
                    if KhfreshState.autoCraftThread then
                        task.cancel(KhfreshState.autoCraftThread)
                        KhfreshState.autoCraftThread = nil
                    end
                    KhfreshState.autoCraftThread = task.spawn(function()
                        while KhfreshState.autoCraftRunning do
                            pcall(craftBait)
                            task.wait(5)
                        end
                    end)
                else
                    if KhfreshState.autoCraftThread then
                        task.cancel(KhfreshState.autoCraftThread)
                        KhfreshState.autoCraftThread = nil
                    end
                end
            end
        })

        CraftSection:CreateButton({ Name = "Craft bait now", Callback = craftBait })
    end

    -- Gacha
    do
        local gachaSection = ShopTab:CreateSection("Auto Gacha")
        local function GetTicketCount()
            local userData = Data:FindFirstChild(tostring(LocalPlayer.UserId))
            if not userData then return 0 end
            local gachaData = userData:FindFirstChild("Gacha")
            if not gachaData then return 0 end
            local tickets = gachaData:FindFirstChild("Tickets")
            if tickets and tickets:IsA("NumberValue") then
                return tickets.Value
            end
            return 0
        end

        local function GetCrystals()
            local userData = Data:FindFirstChild(tostring(LocalPlayer.UserId))
            if not userData then return 0 end
            local names = { "Crystals", "Gems", "Diamonds", "Crystal", "Gem" }
            for _, name in ipairs(names) do
                local val = userData:FindFirstChild(name)
                if val and val:IsA("NumberValue") then
                    return val.Value
                end
            end
            local currency = userData:FindFirstChild("Currency")
            if currency then
                for _, name in ipairs(names) do
                    local val = currency:FindFirstChild(name)
                    if val and val:IsA("NumberValue") then
                        return val.Value
                    end
                end
            end
            return 0
        end

        local bannerOptions = { "Egoless Banner", "Celestial Banner" }
        local selectedBanner = bannerOptions[1]
        local amountOptions = { "1", "10" }
        local selectedAmount = "1"

        local bannerDropdown = gachaSection:CreateDropdown({
            Name = "Select Banner",
            Options = bannerOptions,
            Default = selectedBanner,
            Callback = function(value) selectedBanner = value end
        })
        local amountDropdown = gachaSection:CreateDropdown({
            Name = "Tickets per roll",
            Options = amountOptions,
            Default = selectedAmount,
            Callback = function(value) selectedAmount = value end
        })

        local autoGachaToggle = gachaSection:CreateToggle({
            Name = "Auto Gacha",
            Default = false,
            Callback = function(value)
                KhfreshState.autoGachaRunning = value
                if value then
                    if KhfreshState.autoGachaThread then
                        task.cancel(KhfreshState.autoGachaThread)
                        KhfreshState.autoGachaThread = nil
                    end
                    KhfreshState.autoGachaThread = task.spawn(function()
                        while KhfreshState.autoGachaRunning do
                            pcall(function()
                                local ticketCount = GetTicketCount()
                                local needed = tonumber(selectedAmount) or 1
                                local crystalCount = GetCrystals()
                                local canRoll = false
                                if ticketCount >= needed then
                                    canRoll = true
                                else
                                    local missing = needed - ticketCount
                                    local crystalsNeeded = missing * 5
                                    if crystalCount >= crystalsNeeded then
                                        canRoll = true
                                    else
                                        KhfreshLib:Notify({
                                            Title = "Gacha",
                                            Message = "Not enough tickets/crystals! Need " ..
                                            crystalsNeeded .. " crystals (have " .. crystalCount .. "). Stopping.",
                                            Duration = 4
                                        })
                                        KhfreshState.autoGachaRunning = false
                                        return
                                    end
                                end
                                if canRoll then
                                    local isTen = (selectedAmount == "10")
                                    safeFire("Gacha", isTen, selectedBanner)
                                    KhfreshLib:Notify({
                                        Title = "Gacha",
                                        Message = "Rolled " .. selectedAmount .. " ticket(s) on " .. selectedBanner,
                                        Duration = 2
                                    })
                                end
                            end)
                            task.wait(2)
                        end
                    end)
                else
                    if KhfreshState.autoGachaThread then
                        task.cancel(KhfreshState.autoGachaThread)
                        KhfreshState.autoGachaThread = nil
                    end
                    KhfreshLib:Notify({ Title = "Gacha", Message = "Stopped", Duration = 2 })
                end
            end
        })
    end
end

-- ===== EXCHANGE TAB =====
do
    local ExchangeTab = Window:CreateTab("Exchange")
    local ExchangeSection = ExchangeTab:CreateSection("Exchange Items")

    local exchangeAmount = 1
    local exchangeType = "Trait Reroll"

    ExchangeSection:CreateTextbox({
        Name = "Quantity",
        Placeholder = "1",
        Default = "1",
        Callback = function(value)
            local num = tonumber(value)
            if num and num >= 1 then
                exchangeAmount = math.floor(num)
            else
                exchangeAmount = 1
            end
        end
    })

    ExchangeSection:CreateDropdown({
        Name = "Choose an item",
        Options = { "Trait Reroll", "EssenceOrb" },
        Default = "Trait Reroll",
        Callback = function(value) exchangeType = value end
    })

    local exchangeMethodDropdown = ExchangeSection:CreateDropdown({
        Name = "Exchange Method",
        Options = { "Instant", "Teleport" },
        Default = KhfreshState.exchange.method or "Instant",
        Callback = function(value) KhfreshState.exchange.method = value end
    })

    ExchangeSection:CreateButton({
        Name = "Exchange now",
        Callback = function()
            local userId = LocalPlayer.UserId
            local userData = Data:FindFirstChild(tostring(userId))
            if not userData then
                KhfreshLib:Notify({ Title = "Exchange", Message = "Player data not found!", Duration = 2 })
                return
            end
            local crystal = userData:FindFirstChild("Crystal")
            local cash = userData:FindFirstChild("Cash")
            if not crystal or not cash then
                KhfreshLib:Notify({ Title = "Exchange", Message = "Crystal or Cash not found!", Duration = 2 })
                return
            end
            local qty = exchangeAmount
            local crystalNeed = qty * 5
            local cashNeed = qty * 5000000
            if crystal.Value < crystalNeed then
                KhfreshLib:Notify({ Title = "Exchange", Message = "Not enough Crystals! Need " ..
                crystalNeed .. ", have " .. crystal.Value, Duration = 3 })
                return
            end
            if cash.Value < cashNeed then
                KhfreshLib:Notify({ Title = "Exchange", Message = "Not enough Cash! Need " ..
                cashNeed .. ", have " .. cash.Value, Duration = 3 })
                return
            end

            KhfreshState.exchange.teleported = false
            KhfreshState.exchange.oldPosition = nil
            if KhfreshState.exchange.method == "Teleport" then
                local npc = Workspace:FindFirstChild("NPC")
                if npc then
                    local func = npc:FindFirstChild("Function")
                    if func then
                        local nanjiang = func:FindFirstChild("Nanjiang")
                        if nanjiang and nanjiang:IsA("Model") then
                            local hrp = nanjiang:FindFirstChild("HumanoidRootPart")
                            if hrp then
                                local char = LocalPlayer.Character
                                if char then
                                    local root = char:FindFirstChild("HumanoidRootPart")
                                    if root then
                                        KhfreshState.exchange.oldPosition = root.Position
                                        root.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 3, 0))
                                        KhfreshState.exchange.teleported = true
                                        task.wait(0.3)
                                    end
                                end
                            end
                        end
                    end
                end
                if not KhfreshState.exchange.teleported then
                    KhfreshLib:Notify({ Title = "Exchange", Message =
                    "Could not find Nanjiang, teleport failed. Continuing anyway.", Duration = 3 })
                end
            end

            local success, err = pcall(function()
                safeFire("Exchange", exchangeType, qty)
            end)

            if KhfreshState.exchange.teleported and KhfreshState.exchange.oldPosition then
                task.wait(0.2)
                local char = LocalPlayer.Character
                if char then
                    safeRestorePosition(KhfreshState.exchange)
                end
            end

            if success then
                KhfreshLib:Notify({ Title = "Exchange", Message = "Exchanged " .. qty .. " " .. exchangeType .. "!", Duration = 2 })
            else
                KhfreshLib:Notify({ Title = "Exchange", Message = "Exchange failed: " .. tostring(err), Duration = 2 })
            end
        end
    })
end

-- ===== QUESTS TAB =====
do
    local QuestsTab = Window:CreateTab("Quests")

    -- Auto Claim section REMOVED — claim is built into Auto Do Ticket Quest (full loop)

    -- ===== DAILY QUESTS =====
    do
        local DailySection = QuestsTab:CreateSection("Daily Quests")
        local dailyRunning = false
        local dailyThread = nil

        local function teleportToIsland(island)
            if not island then return false end
            if not island.cframe then
                island = khResolveIslandEntry(island.name)
            end
            if not island or not island.cframe then return false end
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then return false end
            local target = island.cframe.Position + Vector3.new(0, 3, 0)
            hrp.CFrame = CFrame.new(target)
            return true
        end

        local function doDailyQuest()
            local userData = Data:FindFirstChild(tostring(LocalPlayer.UserId))
            if not userData then
                KhfreshLib:Notify({ Title = "Daily Quest", Message = "User data not found!", Duration = 2 })
                return
            end
            local dailyFolder = userData:FindFirstChild("Quest") and userData.Quest:FindFirstChild("Daily")
            if not dailyFolder then
                KhfreshLib:Notify({ Title = "Daily Quest", Message = "Daily quest folder not found!", Duration = 2 })
                return
            end
            local questFolders = {}
            for _, child in pairs(dailyFolder:GetChildren()) do
                if child:IsA("Folder") then
                    table.insert(questFolders, child)
                end
            end
            if #questFolders == 0 then
                KhfreshLib:Notify({ Title = "Daily Quest", Message = "No daily quests available!", Duration = 2 })
                return
            end
            local selectedFolder = questFolders[math.random(1, #questFolders)]
            local questId = selectedFolder.Name
            local progression = selectedFolder:FindFirstChild("Progression")
            local questType = selectedFolder:FindFirstChild("QuestType")
            if not progression or not questType then
                KhfreshLib:Notify({ Title = "Daily Quest", Message = "Missing Progression or QuestType in quest " ..
                questId, Duration = 2 })
                return
            end
            local currentProgress = progression:IsA("NumberValue") and progression.Value or 0
            local qType = questType:IsA("StringValue") and questType.Value or ""

            KhfreshLib:Notify({
                Title = "Daily Quest",
                Message = "Selected quest " .. questId .. " | Type: " .. qType .. " | Progress: " .. currentProgress,
                Duration = 4
            })

            if qType == "PlayTime" then
                KhfreshLib:Notify({ Title = "Daily Quest", Message = "PlayTime quest: just play for 30 minutes!", Duration = 3 })
                return
            end

            if qType == "Fishing" then
                local island = getRecommendedIsland()
                if not island then
                    KhfreshLib:Notify({ Title = "Daily Quest", Message = "No suitable island found!", Duration = 2 })
                    return
                end
                if not teleportToIsland(island) then
                    KhfreshLib:Notify({ Title = "Daily Quest", Message = "Teleport failed!", Duration = 2 })
                    return
                end
                enableBasicFishing(true)
                Fishing.Flags.AutoFarmBoss = false
                Fishing.Flags.AutoFarmSecretBoss = false
                KhfreshLib:Notify({ Title = "Daily Quest", Message = "Fishing daily started on " .. island.name, Duration = 2 })
                while dailyRunning do
                    local newProgress = selectedFolder:FindFirstChild("Progression")
                    if newProgress and newProgress:IsA("NumberValue") then
                        if newProgress.Value >= 100 then
                            KhfreshLib:Notify({ Title = "Daily Quest", Message = "Fishing daily completed!", Duration = 3 })
                            break
                        end
                    end
                    task.wait(2)
                end
            elseif qType == "BossQuest" then
                local island = getRecommendedIsland()
                if not island then
                    KhfreshLib:Notify({ Title = "Daily Quest", Message = "No suitable island found!", Duration = 2 })
                    return
                end
                if not teleportToIsland(island) then
                    KhfreshLib:Notify({ Title = "Daily Quest", Message = "Teleport failed!", Duration = 2 })
                    return
                end
                enableBasicFishing(true)
                Fishing.Flags.AutoFarmBoss = true
                Fishing.Flags.AutoFarmSecretBoss = false
                KhfreshLib:Notify({ Title = "Daily Quest", Message = "Boss daily started on " .. island.name, Duration = 2 })
                while dailyRunning do
                    local newProgress = selectedFolder:FindFirstChild("Progression")
                    if newProgress and newProgress:IsA("NumberValue") then
                        if newProgress.Value >= 10 then
                            KhfreshLib:Notify({ Title = "Daily Quest", Message = "Boss daily completed!", Duration = 3 })
                            break
                        end
                    end
                    task.wait(2)
                end
            elseif qType == "Bait" then
                KhfreshLib:Notify({ Title = "Daily Quest", Message = "Bait daily: buying Basic Bait...", Duration = 2 })
                local buyEvent = Events:FindFirstChild("BuyBait")
                if not buyEvent then
                    KhfreshLib:Notify({ Title = "Daily Quest", Message = "BuyBait remote not found!", Duration = 2 })
                    return
                end
                while dailyRunning do
                    local newProgress = selectedFolder:FindFirstChild("Progression")
                    if newProgress and newProgress:IsA("NumberValue") then
                        if newProgress.Value >= 25 then
                            KhfreshLib:Notify({ Title = "Daily Quest", Message = "Bait daily completed!", Duration = 3 })
                            break
                        end
                    end
                    pcall(function() buyEvent:FireServer("Basic Bait", 1) end)
                    task.wait(0.5)
                end
            else
                KhfreshLib:Notify({ Title = "Daily Quest", Message = "Unknown quest type: " .. qType, Duration = 2 })
            end
            restoreRoutineFlags()
        end

        -- Toggle Auto Do Daily Quest
        local autoDailyToggle = DailySection:CreateToggle({
            Name = "Auto Do Daily Quest",
            Default = false,
            Callback = function(value)
                dailyRunning = value
                if value then
                    if dailyThread then
                        task.cancel(dailyThread)
                        dailyThread = nil
                    end
                    dailyThread = task.spawn(function()
                        while dailyRunning do
                            pcall(doDailyQuest)
                            if dailyRunning then
                                task.wait(5)
                            end
                        end
                    end)
                    KhfreshLib:Notify({ Title = "Daily Quest", Message = "Auto Daily started!", Duration = 2 })
                else
                    if dailyThread then
                        task.cancel(dailyThread)
                        dailyThread = nil
                    end
                    restoreRoutineFlags()
                    KhfreshLib:Notify({ Title = "Daily Quest", Message = "Auto Daily stopped", Duration = 2 })
                end
            end
        })

        -- ===== CLAIM DAILY REWARDS BUTTON =====
        DailySection:CreateButton({
            Name = "Claim Daily Rewards",
            Callback = function()
                local dailyRewardEvent = Events:FindFirstChild("DailyReward")
                if not dailyRewardEvent then
                    KhfreshLib:Notify({ Title = "Daily Rewards", Message = "DailyReward remote not found!", Duration = 3 })
                    return
                end
                KhfreshLib:Notify({ Title = "Daily Rewards", Message = "Claiming all 7 daily rewards...", Duration = 2 })
                task.spawn(function()
                    for i = 1, 7 do
                        pcall(function()
                            dailyRewardEvent:FireServer(i)
                        end)
                        task.wait(0.5)
                    end
                    KhfreshLib:Notify({ Title = "Daily Rewards", Message = "All 7 daily rewards claimed!", Duration = 3 })
                end)
            end
        })
    end

    -- ===== MATERIAL FARMING =====
    do
        local MaterialSection = QuestsTab:CreateSection("Material Farming")
        local MatFishingAreaRarity
        pcall(function()
            MatFishingAreaRarity = require(Info.FishingAreaRarity)
        end)
        if not MatFishingAreaRarity then
            MatFishingAreaRarity = {
                ["Beginning Isle"] = {},
                ["Bamboo Isle"] = {},
                ["Fallout Isle"] = {},
                ["Sovereign Isle"] = {},
                ["Perch Isle"] = {},
                ["Frost Isle"] = {},
                ["Coconut Isle"] = {},
                ["Amber Isle"] = {},
                ["Battlefield Isle"] = {},
                ["Mistpeak Isle"] = {},
                ["Island 11"] = {},
                ["World Angler Isle"] = {},
                ["Weather Isle"] = {},
                ["Mystic Reef Isle"] = {},
                ["Exclusive"] = {},
                ["Secret Boss"] = {},
            }
        end

        local matIslandDisplayNames = {
            ["Beginning Isle"] = "Island 1",
            ["Bamboo Isle"] = "Island 2",
            ["Fallout Isle"] = "Island 3",
            ["Sovereign Isle"] = "Island 4",
            ["Perch Isle"] = "Island 5",
            ["Frost Isle"] = "Island 6",
            ["Coconut Isle"] = "Island 7",
            ["Amber Isle"] = "Island 8",
            ["Battlefield Isle"] = "Island 9",
            ["Mistpeak Isle"] = "Island 10",
            ["Island 11"] = "Island 11",
            ["World Angler Isle"] = "Island 11",
            ["Weather Isle"] = "Weather Isle",
            ["Mystic Reef Isle"] = "Mystic Reef Isle",
            ["Exclusive"] = "Exclusive",
            ["Secret Boss"] = "Secret Boss"
        }
        local matIslandOrder = {
            "Beginning Isle", "Bamboo Isle", "Fallout Isle", "Sovereign Isle", "Perch Isle", "Frost Isle",
            "Coconut Isle", "Amber Isle", "Battlefield Isle", "Mistpeak Isle", "Island 11",
            "World Angler Isle", "Weather Isle", "Mystic Reef Isle", "Exclusive", "Secret Boss"
        }
        local matIslandNameToIsland = {}
        for _, island in ipairs(KhfreshState.islands) do matIslandNameToIsland[island.name] = island end
        for rarityName, displayName in pairs(matIslandDisplayNames) do
            for _, island in ipairs(KhfreshState.islands) do
                if island.name == displayName then matIslandNameToIsland[rarityName] = island end
            end
        end

        local function matGetIslandsForFish(fishName)
            local result = {}
            for _, islandName in ipairs(matIslandOrder) do
                local fishList = MatFishingAreaRarity[islandName]
                if fishList and fishList[fishName] then table.insert(result, islandName) end
            end
            return result
        end

        local function matGetMaterialCount(fishName, minKg, maxKg)
            local userData = Data:FindFirstChild(tostring(LocalPlayer.UserId))
            if not userData then return 0 end
            local inventory = userData:FindFirstChild("Inventory")
            if not inventory then return 0 end
            local count = 0
            for _, item in pairs(inventory:GetChildren()) do
                if item.Name == fishName then
                    local weightString = nil
                    if item:IsA("StringValue") then
                        local parts = {}
                        for part in string.gmatch(item.Value, "[^|]+") do table.insert(parts, part) end
                        if #parts >= 2 then weightString = parts[2]:gsub("^%s+", ""):gsub("%s+$", "") end
                    elseif item:IsA("NumberValue") or item:IsA("IntValue") then
                        weightString = tostring(item.Value)
                    end
                    if weightString then
                        local weight = tonumber(weightString)
                        if weight and weight >= minKg and weight <= maxKg then
                            count = count + 1
                        end
                    end
                end
            end
            return count
        end

        local function matTeleportToIsland(islandName)
            local island = khResolveIslandEntry(islandName) or matIslandNameToIsland[islandName]
            if not island or not island.cframe then
                local now = tick()
                if now - (KhfreshState.materialLastIslandWarn or 0) > 4 then
                    KhfreshState.materialLastIslandWarn = now
                    KhfreshLib:Notify({Title="Material Farming", Message="No live position found for "..tostring(islandName)..".", Duration=3})
                end
                return false
            end
            local ok = select(1, khTeleportToIslandCoordinates(island))
            return ok == true
        end

        local function matGetWeather()
            local mg = LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("MainGui")
            if mg then
                local info = mg:FindFirstChild("Info")
                local infoFrame = info and info:FindFirstChild("Info")
                local weatherFrame = infoFrame and infoFrame:FindFirstChild("Weather")
                local val = weatherFrame and weatherFrame:FindFirstChild("Value")
                if val then
                    local text = val:IsA("TextLabel") and val.Text or val.Value
                    return (text:gsub("Weather:%s*", ""))
                end
            end
            return "Clear"
        end

        local function matCancelFishing()
            local char = LocalPlayer.Character
            if not char then return end
            if not char:GetAttribute("Fishing") then return end
            local root = char:FindFirstChild("HumanoidRootPart")
            if root then pcall(function() safeFire("Fishing", root.CFrame) end) end
            if Fishing.BossFarm.CurrentToken then
                pcall(function() safeFire("FishingMinigame", false, Fishing.BossFarm.CurrentToken) end)
            end
        end

        local function matEnableFishing()
            if not KhfreshState.materialFarmingSavedFlags then
                KhfreshState.materialFarmingSavedFlags = {
                    AutoCast = Fishing.Flags.AutoCast,
                    AnchorLock = Fishing.Flags.AnchorLock,
                    AutoSkill = Fishing.Flags.AutoSkill,
                    AutoSkillCheck = Fishing.Flags.AutoSkillCheck,
                    AntiAFK = Fishing.Flags.AntiAFK,
                    AutoFarmBoss = Fishing.Flags.AutoFarmBoss,
                    AutoFarmSecretBoss = Fishing.Flags.AutoFarmSecretBoss,
                    AutoEquipRod = MiscFlags.AutoEquipRod,
                }
            end
            Fishing.Flags.AutoCast = true
            Fishing.Flags.AnchorLock = true
            Fishing.Flags.AutoSkill = true
            Fishing.Flags.AutoSkillCheck = true
            Fishing.Flags.AntiAFK = true
            MiscFlags.AutoEquipRod = true
        end

        local function matDisableFishing()
            if KhfreshState.materialFarmingSavedFlags then
                Fishing.Flags.AutoCast = KhfreshState.materialFarmingSavedFlags.AutoCast
                Fishing.Flags.AnchorLock = true
                Fishing.Flags.AutoSkill = KhfreshState.materialFarmingSavedFlags.AutoSkill
                Fishing.Flags.AutoSkillCheck = KhfreshState.materialFarmingSavedFlags.AutoSkillCheck
                Fishing.Flags.AntiAFK = KhfreshState.materialFarmingSavedFlags.AntiAFK
                Fishing.Flags.AutoFarmBoss = KhfreshState.materialFarmingSavedFlags.AutoFarmBoss
                Fishing.Flags.AutoFarmSecretBoss = KhfreshState.materialFarmingSavedFlags.AutoFarmSecretBoss
                MiscFlags.AutoEquipRod = KhfreshState.materialFarmingSavedFlags.AutoEquipRod
                KhfreshState.materialFarmingSavedFlags = nil
            else
                Fishing.Flags.AutoCast = false
                Fishing.Flags.AnchorLock = true
                Fishing.Flags.AutoSkill = false
                Fishing.Flags.AutoFarmBoss = false
                Fishing.Flags.AutoFarmSecretBoss = false
            end
        end

        local BAIT_RECIPES = {
            ["Rainbow Bait"] = {
                { name = "Colossal Tigerfish",   minKg = 3000000, maxKg = 6000000 },
                { name = "Heavenpiercer Turtle", minKg = 3000000, maxKg = 6000000 },
                { name = "Golden Guardian Fish", minKg = 1000000, maxKg = 3000000 },
                { name = "Crimson Electric Eel", minKg = 3000000, maxKg = 4000000 },
            },
            ["Frost Bait"] = {
                { name = "Frost Kingfish",              minKg = 4000000, maxKg = 7000000 },
                { name = "Ascended Perch",              minKg = 900000,  maxKg = 1000000 },
                { name = "Primordial Kunfish Overlord", minKg = 1000000, maxKg = 1600000 },
                { name = "Warbringer Shark",            minKg = 500000,  maxKg = 800000 },
            },
            ["Nameless Bait"] = {
                { name = "Mountain Fish",      minKg = 1000000, maxKg = 5000000 },
                { name = "Tiger Mirefish",     minKg = 1000000, maxKg = 3000000 },
                { name = "Mirage Lanternfish", minKg = 3000000, maxKg = 5000000 },
                { name = "Octoparasitic Fish", minKg = 3000000, maxKg = 5000000 },
            }
        }

        local ROD_RECIPES = {
            ["Heavenpiercer Rod"] = {
                { name = "Flying Fish Emperor",  minKg = 1000000, maxKg = 3000000 },
                { name = "Flying Fish Empress",  minKg = 1000000, maxKg = 3000000 },
                { name = "Heavenpiercer Turtle", minKg = 3000000, maxKg = 6000000 },
                { name = "Rainbow Dragonfish",   minKg = 5000000, maxKg = 8000000 },
            },
            ["Pure Diamond Rod"] = {
                { name = "Frost Kingfish",  minKg = 4000000, maxKg = 7000000 },
                { name = "Frost Queenfish", minKg = 4000000, maxKg = 8000000 },
                { name = "Sanguine Fish",   minKg = 3000000, maxKg = 6000000 },
                { name = "Draconic Koi",    minKg = 1000000, maxKg = 3000000 },
            },
            ["Sacred Bamboo Rod"] = {
                { name = "Nameless Octoparasite", minKg = 6000000, maxKg = 9000000 },
                { name = "Reborn Puffer Beast",   minKg = 4000000, maxKg = 6000000 },
                { name = "Ascended Perch",        minKg = 900000,  maxKg = 1000000 },
                { name = "Mountain Fish",         minKg = 1000000, maxKg = 5000000 },
            }
        }

        local MAT_WEATHER_REQUIRED = {
            ["Frost Kingfish"] = { weathers = { snowy = true, frost = true }, island = "Frost Isle", label = "Snowy" },
            ["Heavenpiercer Turtle"] = { weathers = { foggy = true }, island = "Coconut Isle", label = "Foggy" },
            ["Crimson Electric Eel"] = { weathers = { thunderstorm = true }, island = "Bamboo Isle", label = "Thunderstorm" },
        }
        local MAT_FISH_CFRAME = {
            ["Crimson Electric Eel"] = CFrame.new(-1311.6228, 9.27561855, -17.8612099, 0.74382472, 5.44192353e-08,
                0.668374717, -9.6746561e-08, 1, 2.6247621e-08, -0.668374717, -8.41865813e-08, 0.74382472),
            ["Heavenpiercer Turtle"] = CFrame.new(1372.05164, 9.27561855, -1458.41187, 0.0626300573, 2.49723797e-08,
                0.998036802, -3.82936918e-08, 1, -2.26184476e-08, -0.998036802, -3.6801918e-08, 0.0626300573),
        }

        local function matRunCycle()
            if not KhfreshState.autoFishForMaterialsRunning then return end
            local char = LocalPlayer.Character
            if not char then return end

            local recipe = BAIT_RECIPES[KhfreshState.materialBaitName] or ROD_RECIPES[KhfreshState.materialBaitName]
            if not recipe or #recipe == 0 then return end

            local targetReq, minCount = nil, math.huge
            for _, req in ipairs(recipe) do
                local c = matGetMaterialCount(req.name, req.minKg, req.maxKg)
                if c < minCount then
                    minCount = c; targetReq = req
                end
            end
            if not targetReq then return end

            local fishName = targetReq.name
            local weather = string.lower(tostring(matGetWeather()))
            local req = MAT_WEATHER_REQUIRED[fishName]

            if req then
                local ok = false
                for w, _ in pairs(req.weathers) do if weather == w then
                        ok = true; break
                    end end
                if not ok then
                    KhfreshState.materialCurrentTarget = nil
                    KhfreshLib:Notify({ Title = "Material Farming", Message = fishName ..
                    " can weather " .. req.label .. ". Waiting to join the server...", Duration = 3 })
                    pcall(function()
                        Services.TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
                    end)
                    task.wait(3)
                    return
                end
                local fishCF = MAT_FISH_CFRAME[fishName]
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if fishCF and hrp then
                    if (hrp.Position - fishCF.Position).Magnitude > 5 then
                        if char:GetAttribute("Fishing") then
                            matCancelFishing(); task.wait(0.1)
                        end
                        hrp.CFrame = fishCF
                    end
                else
                    matTeleportToIsland(req.island)
                end
                matEnableFishing()
                Fishing.Flags.AutoFarmSecretBoss = true
                MiscFlags.AutoEquipRod = true
                KhfreshState.materialCurrentTarget = fishName
                return
            end

            local islandsForFish = matGetIslandsForFish(fishName)
            if #islandsForFish == 0 then return end
            local targetIslandName = islandsForFish[1]
            if targetIslandName == "Secret Boss" then
                matEnableFishing()
                Fishing.Flags.AutoFarmSecretBoss = true
                MiscFlags.AutoEquipRod = true
                KhfreshState.materialCurrentTarget = fishName
                return
            end
            local targetIsland = khResolveIslandEntry(targetIslandName) or matIslandNameToIsland[targetIslandName]
            if not targetIsland or not targetIsland.cframe then
                -- Weather/Mystic positions are only usable when the live map exposes them.
                matTeleportToIsland(targetIslandName)
                return
            end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            if (hrp.Position - targetIsland.cframe.Position).Magnitude > 0.5 then
                if char:GetAttribute("Fishing") then
                    matCancelFishing(); task.wait(0.1)
                end
                matTeleportToIsland(targetIslandName)
            end
            matEnableFishing()
            Fishing.Flags.AutoFarmSecretBoss = false
            KhfreshState.materialCurrentTarget = fishName
        end

        MaterialSection:CreateDropdown({
            Name = "Select bait for material farming",
            Options = { "Rainbow Bait", "Frost Bait", "Nameless Bait", "Heavenpiercer Rod", "Pure Diamond Rod", "Sacred Bamboo Rod" },
            Default = "Rainbow Bait",
            Callback = function(value) KhfreshState.materialBaitName = value end
        })

        MaterialSection:CreateToggle({
            Name = "Auto fish for bait materials",
            Default = false,
            Callback = function(value)
                KhfreshState.autoFishForMaterialsRunning = value
                if value then
                    if KhfreshState.autoFishForMaterialsThread then
                        task.cancel(KhfreshState.autoFishForMaterialsThread)
                        KhfreshState.autoFishForMaterialsThread = nil
                    end
                    KhfreshState.materialCurrentTarget = nil
                    KhfreshState.autoFishForMaterialsThread = task.spawn(function()
                        while KhfreshState.autoFishForMaterialsRunning do
                            pcall(matRunCycle)
                            task.wait(0.5)
                        end
                        if not KhfreshState.autoFishForMaterialsRunning then matDisableFishing() end
                    end)
                    KhfreshLib:Notify({ Title = "Material Farming", Message = "Started", Duration = 2 })
                else
                    if KhfreshState.autoFishForMaterialsThread then
                        task.cancel(KhfreshState.autoFishForMaterialsThread)
                        KhfreshState.autoFishForMaterialsThread = nil
                    end
                    matDisableFishing()
                    KhfreshState.materialCurrentTarget = nil
                    KhfreshLib:Notify({ Title = "Material Farming", Message = "Stopped", Duration = 2 })
                end
            end
        })
    end
    -- ===== AUTO DO TICKET QUEST (FULL: claim + do + turn-in + re-claim) =====
    local DoSection = QuestsTab:CreateSection("Auto Do Ticket Quest")

    -- Quest type: Easy / Hard — only this + island mode needed
    local ticketQuestTypes = { "Easy Quest", "Hard Quest" }
    local selectedTicketQuest = ticketQuestTypes[1]
    DoSection:CreateDropdown({
        Name = "Select Quest Type",
        Options = ticketQuestTypes,
        Default = selectedTicketQuest,
        Callback = function(value)
            selectedTicketQuest = value or "Easy Quest"
            KhfreshLib:Notify({ Title = "Ticket Quest", Message = "Selected: " .. tostring(selectedTicketQuest), Duration = 2 })
        end
    })

    -- Store the dynamic controls
    local islandModeDropdown = nil
    local islandDropdown = nil
    local islandDropdownFrame = nil
    local selectedIslandMode = "Choose Island Manual"
    local selectedIslandName = "Beginning Isle | Isle 1"
    local islandList = {
        "Beginning Isle | Isle 1", "Bamboo Isle | Isle 2", "Fallout Isle | Isle 3",
        "Sovereign Isle | Isle 4", "Perch Isle | Isle 5", "Frost Isle | Isle 6",
        "Coconut Isle | Isle 7", "Amber Isle | Isle 8", "Battlefield Isle | Isle 9",
        "Mistpeak Isle | Isle 10", "World Angler Isle | Isle 11",
        "Weather Isle | Isle 12", "Mystic Reef Isle | Isle 13",
    }

    -- Remove the island dropdown (if present)
    local function clearIslandDropdown()
        if islandDropdownFrame and islandDropdownFrame._frame then
            pcall(function()
                if type(islandDropdownFrame.Destroy) == "function" then
                    islandDropdownFrame:Destroy()
                elseif islandDropdownFrame._frame and type(islandDropdownFrame._frame.Destroy) == "function" then
                    islandDropdownFrame._frame:Destroy()
                end
            end)
        end
        islandDropdownFrame = nil
        islandDropdown = nil
    end

    -- Create the island dropdown
    local function createIslandDropdown()
        clearIslandDropdown()
        islandDropdown = DoSection:CreateDropdown({
            Name = "Ticket & daily-limit farm island",
            Options = islandList,
            Default = selectedIslandName,
            Callback = function(value)
                selectedIslandName = value
            end
        })
        islandDropdownFrame = islandDropdown
    end

    -- Create the mode dropdown
    local modeDropdown = DoSection:CreateDropdown({
        Name = "Island Selection Mode",
        Options = { "Auto Select Island", "Choose Island Manual" },
        Default = "Choose Island Manual",
        Callback = function(value)
            selectedIslandMode = value
            if value == "Choose Island Manual" then
                createIslandDropdown()
            else
                clearIslandDropdown()
            end
        end
    })

    -- Always show manual island dropdown by default
    task.defer(function()
        pcall(createIslandDropdown)
    end)

    -- ===== Target island resolver =====
    -- Never steal Auto Farm island: if Main AutoFarm is on, farm THAT island only.
    local function getTargetIsland()
        if KhfreshState.AutoFarm and KhfreshState.AutoFarm.enabled and KhfreshState.AutoFarm.selectedIsland then
            local af = khResolveIslandEntry(KhfreshState.AutoFarm.selectedIsland)
            if af then return af end
        end
        if selectedIslandMode == "Auto Select Island" then
            return getRecommendedIsland()
        end
        return khResolveIslandEntry(selectedIslandName)
    end

    -- Daily quest limit REMOVED — never block accept
    local function isTicketQuestDailyLimitReached()
        return false, 0, 999
    end
    local function getTicketQuestsCompletedToday()
        return 0, { count = 0 }
    end
    local function printTicketLimitStatus() end
    local function stopTicketQuestFully() end

    local resumeTicketFarmDuringCooldown

    local function farmAtTicketTargetIsland()
        if KhfreshState.ticketDailyDone then return false end
        local targetIsland = getTargetIsland()
        if not targetIsland or not targetIsland.cframe then
            warn("[Khfresh][TicketQuest] farm island not resolved")
            return false
        end
        KhfreshState.ticketFarmCFrame = targetIsland.cframe + Vector3.new(0, 3, 0)
        return resumeTicketFarmDuringCooldown(true)
    end

    -- ===== parse / getCurrentQuestProgress helpers (unchanged) =====
    local function parseQuestString(str)
        if not str or str == "" then return nil, nil end
        local parts = {}
        for part in string.gmatch(str, "[^,]+") do table.insert(parts, part) end
        if #parts >= 3 then
            local target = nil
            local typ = nil
            if string.find(parts[1], "Boss") then
                target = tonumber(parts[3])
                typ = parts[1]
            else
                target = tonumber(parts[2])
                typ = parts[3]
            end
            if target and typ then return target, typ end
        end
        return nil, nil
    end

    local function getCurrentQuestProgress()
        local userData = Data:FindFirstChild(tostring(LocalPlayer.UserId))
        if not userData then return nil end
        local quest = userData:FindFirstChild("Quest")
        if not quest then return nil end
        local main = quest:FindFirstChild("Main")
        if not main then return nil end
        for _, folder in pairs(main:GetChildren()) do
            if folder:IsA("Folder") and (folder.Name == "Easy Ticket Quest" or folder.Name == "Hard Ticket Quest") then
                local current = nil
                local target = nil
                local typ = nil
                local questName = folder.Name
                for _, child in pairs(folder:GetChildren()) do
                    if child:IsA("NumberValue") or child:IsA("IntValue") then
                        if child.Name == "1" then
                            current = child.Value
                        end
                    end
                end
                local objective = folder:FindFirstChild("Objective")
                if objective then
                    for _, child in pairs(objective:GetChildren()) do
                        if child:IsA("StringValue") and child.Name == "1" then
                            local val = child.Value
                            if val and val ~= "" then
                                local t, ty = parseQuestString(val)
                                if t and ty then
                                    target = t
                                    typ = ty
                                end
                            end
                        end
                    end
                end
                if current and target and typ then
                    return current, target, questName, typ
                end
            end
        end
        return nil
    end

    -- Nexus-style ticketGoFire: TP to giver, fire ChooseDialogueOption remote, return
    ticketGoFire = function(action)
        if not Events then
            warn("[Khfresh][TicketQuest] Events nil")
            return false
        end
        local sd = Events:FindFirstChild("StartDialogue")
        local cd = Events:FindFirstChild("ChooseDialogueOption")
        if not sd then sd = Events:FindFirstChild("StartDialog") end
        if not cd then cd = Events:FindFirstChild("ChooseDialogOption") end
        if not sd or not cd then
            warn("[Khfresh][TicketQuest] dialogue remotes missing", sd, cd)
            return false
        end

        local giver = nil
        pcall(function()
            local npc = Workspace:FindFirstChild("NPC")
            local npcFunc = npc and npc:FindFirstChild("Function")
            giver = npcFunc and npcFunc:FindFirstChild("Ticket Quest Giver")
        end)
        -- Fallback: scan workspace (name can be nested differently after updates)
        if not giver then
            pcall(function()
                for _, inst in ipairs(Workspace:GetDescendants()) do
                    if inst.Name == "Ticket Quest Giver" then
                        giver = inst
                        break
                    end
                end
            end)
        end
        if not giver then
            warn("[Khfresh][TicketQuest] Ticket Quest Giver NOT in workspace")
            return false
        end

        local giverPos = nil
        pcall(function()
            if giver:IsA("Model") then
                local hrp = giver:FindFirstChild("HumanoidRootPart") or giver:FindFirstChild("HumanoidRootPart", true)
                if hrp then giverPos = hrp.Position
                elseif giver.PrimaryPart then giverPos = giver.PrimaryPart.Position
                else giverPos = giver:GetPivot().Position end
            elseif giver:IsA("BasePart") then
                giverPos = giver.Position
            else
                local part = giver:FindFirstChildWhichIsA("BasePart", true)
                if part then giverPos = part.Position end
            end
        end)

        local charNow = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local root = charNow and (charNow:FindFirstChild("HumanoidRootPart") or charNow:WaitForChild("HumanoidRootPart", 5))
        if not root or not giverPos then
            warn("[Khfresh][TicketQuest] TP abort root/pos", root ~= nil, giverPos)
            return false
        end

        local dest = CFrame.new(giverPos + Vector3.new(0, 3, 0))
        for _ = 1, 3 do
            pcall(function()
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                root.CFrame = dest
            end)
            pcall(function()
                if charNow.PivotTo then charNow:PivotTo(dest) end
            end)
            task.wait(0.2)
            if (root.Position - giverPos).Magnitude < 25 then break end
        end
        print("[Khfresh][TicketQuest] TP dist=", math.floor((root.Position - giverPos).Magnitude))

        -- ProximityPrompt open (some builds need this before StartDialogue)
        pcall(function()
            local prompt = giver:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt then
                if fireproximityprompt then
                    fireproximityprompt(prompt)
                elseif firesignal and prompt.Triggered then
                    firesignal(prompt.Triggered, LocalPlayer)
                end
            end
        end)
        task.wait(0.15)

        local extraData = { giver }
        pcall(function() sd:FireServer("Ticket Quest Giver", giver) end)
        task.wait(0.3)

        local actions = type(action) == "table" and action or { action }
        for _, act in ipairs(actions) do
            pcall(function() cd:FireServer("Ticket Quest Giver", 1, act, extraData) end)
            task.wait(0.2)
        end
        task.wait(0.25)
        return true
    end

    -- Keep old name as alias so any leftover callers still work
    runTicketQuestDialogue = function()
        return ticketGoFire("Quest")
    end

    local function getTicketQuestGiver()
        local npc = Workspace:FindFirstChild("NPC")
        local func = npc and npc:FindFirstChild("Function")
        local giver = func and func:FindFirstChild("Ticket Quest Giver")
        if not giver then return nil, nil end
        local root = giver:FindFirstChild("HumanoidRootPart", true)
        if not root and giver:IsA("BasePart") then root = giver end
        return giver, root
    end

    local function teleportToTicketQuestGiver()
        local giver, root = getTicketQuestGiver()
        if not giver or not root then return false end
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
        hrp.CFrame = CFrame.new(root.Position + Vector3.new(0, 3, 0))
        return true
    end

    local function hasTicketQuestFolder()
        local userData = Data:FindFirstChild(tostring(LocalPlayer.UserId))
        local main = userData and userData:FindFirstChild("Quest") and userData.Quest:FindFirstChild("Main")
        if not main then return false end
        return main:FindFirstChild("Easy Ticket Quest") ~= nil
            or main:FindFirstChild("Hard Ticket Quest") ~= nil
    end

    local function getAcceptAction()
        return (selectedTicketQuest == "Hard Quest") and "HardAcceptQuest" or "EasyAcceptQuest"
    end

    local function hasAnyTicketQuest()
        local userData = Data:FindFirstChild(tostring(LocalPlayer.UserId))
        if not userData then return false end
        local quest = userData:FindFirstChild("Quest")
        if not quest then return false end
        local main = quest:FindFirstChild("Main")
        if not main then return false end
        for _, child in pairs(main:GetChildren()) do
            if child:IsA("Folder") then
                local name = child.Name
                if name == "Easy Ticket Quest" or name == "Hard Ticket Quest" then
                    return true
                end
            end
        end
        return false
    end

    local function getTicketQuestCooldownRemaining()
        local userData = Data:FindFirstChild(tostring(LocalPlayer.UserId))
        local cooldown = userData and userData:FindFirstChild("TicketQuestCooldown")
        if not cooldown or not (cooldown:IsA("NumberValue") or cooldown:IsA("IntValue")) then
            if not KhfreshState.ticketCooldownWarningShown then
                KhfreshState.ticketCooldownWarningShown = true
                warn("[Khfresh][TicketQuest] Data.TicketQuestCooldown is unavailable; using throttled retries.")
            end
            return nil
        end
        KhfreshState.ticketCooldownWarningShown = false
        return math.max(0, cooldown.Value - Workspace:GetServerTimeNow())
    end

    resumeTicketFarmDuringCooldown = function(forceTargetIsland)
        if not KhfreshState.autoDoRunning then return false end
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return false end

        if forceTargetIsland or not KhfreshState.ticketFarmCFrame then
            local targetIsland = getTargetIsland()
            if targetIsland and targetIsland.cframe then
                KhfreshState.ticketFarmCFrame = targetIsland.cframe + Vector3.new(0, 3, 0)
            else
                KhfreshState.ticketFarmCFrame = root.CFrame
            end
        end

        -- Avoid TP spam / island-1 bounce: only if far AND not just visited NPC
        local justNpc = (tick() - (KhfreshState.ticketLastFire or 0)) < 6
        local dist = (root.Position - KhfreshState.ticketFarmCFrame.Position).Magnitude
        if not justNpc and not char:GetAttribute("Fishing") and dist > 90 then
            root.CFrame = KhfreshState.ticketFarmCFrame
        end

        KhfreshState.isDoingUseBaitQuest = false
        Fishing.Flags.AutoFarmBoss = false
        Fishing.Flags.AutoFarmSecretBoss = false
        if KhfreshState.savedRoutineFlags then
            MiscFlags.AutoBuy = KhfreshState.savedRoutineFlags.AutoBuy
            MiscFlags.AutoEquipBait = KhfreshState.savedRoutineFlags.AutoEquipBait
        end
        enableBasicFishing(false)
        return true
    end

    -- No quest → respect server cooldown and farm at the last quest spot | active → farm | done → turn in
    local function updateQuestStatus()
        if KhfreshState.ticketDailyDone or not KhfreshState.autoDoRunning then
            return
        end
        local current, target, questName, typ = getCurrentQuestProgress()

        -- No active quest: keep farming locally while the authoritative server cooldown runs.
        if not current or not target or not questName then
            if KhfreshState.ticketQuestActive then
                KhfreshState.ticketQuestActive = false
                KhfreshState.ticketTargetCount = 0
                KhfreshState.ticketCurrentCount = 0
            end
            KhfreshState.isDoingUseBaitQuest = false
            KhfreshState.ticketQuestClaimed = false

            if not hasAnyTicketQuest() then

                local cooldownRemaining = getTicketQuestCooldownRemaining()
                if cooldownRemaining and cooldownRemaining > 0 then
                    farmAtTicketTargetIsland()
                    local now = tick()
                    if now - (KhfreshState.ticketCooldownNoticeAt or 0) >= 30 then
                        KhfreshState.ticketCooldownNoticeAt = now
                        KhfreshLib:Notify({
                            Title = "Ticket Quest Cooldown",
                            Message = string.format("Waiting %d:%02d; farming at your selected island.",
                                math.floor(cooldownRemaining / 60), math.floor(cooldownRemaining % 60)),
                            Duration = 3
                        })
                    end
                    return
                end

                local now = tick()
                local claimRetryInterval = cooldownRemaining == nil and 5 or 2
                -- Nexus Auto Claim style: every 3s TP + StartDialogue + Accept
                if now - (KhfreshState.ticketLastFire or 0) < 3 then
                    farmAtTicketTargetIsland()
                    return
                end
                KhfreshState.ticketLastFire = now
                local action = getAcceptAction()
                local okFire = false
                pcall(function() okFire = ticketGoFire(action) end)
                task.wait(0.8)
                local claimed = hasAnyTicketQuest()
                if not claimed then
                    local alt = (action == "EasyAcceptQuest") and "HardAcceptQuest" or "EasyAcceptQuest"
                    pcall(function() ticketGoFire(alt) end)
                    task.wait(0.8)
                    claimed = hasAnyTicketQuest()
                end
                if claimed then
                    KhfreshState.ticketFailCount = 0
                    KhfreshLib:Notify({
                        Title = "Ticket Quest",
                        Message = "Accepted " .. tostring(selectedTicketQuest),
                        Duration = 2
                    })
                else
                    KhfreshState.ticketFailCount = (KhfreshState.ticketFailCount or 0) + 1
                    -- Stay productive: farm chosen island between accepts
                    farmAtTicketTargetIsland()
                    if (KhfreshState.ticketFailCount % 5) == 1 then
                        KhfreshLib:Notify({
                            Title = "Ticket Quest",
                            Message = "Accept retry (TP NPC). Fail#" .. tostring(KhfreshState.ticketFailCount),
                            Duration = 2
                        })
                    end
                end
            end
            return
        end

        -- Has active quest
        KhfreshState.ticketTargetCount = target
        KhfreshState.ticketCurrentCount = current
        KhfreshState.ticketQuestActive = true

        -- Completed → turn in + re-claim same Easy/Hard
        if current >= target then
            local now = tick()
            if not KhfreshState.ticketQuestClaimed
                and now - (KhfreshState.ticketLastTurnIn or 0) >= 3 then
                KhfreshState.ticketLastTurnIn = now
                local char = LocalPlayer.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if root then KhfreshState.ticketFarmCFrame = root.CFrame end
                KhfreshLib:Notify({ Title = "Quest", Message = "Complete! Turning in...", Duration = 2 })
                if ticketGoFire("Quest") then
                    local turnedIn = false
                    for _ = 1, 10 do
                        task.wait(0.3)
                        if not getCurrentQuestProgress() then
                            turnedIn = true
                            break
                        end
                    end
                    if turnedIn then
                        KhfreshState.ticketQuestClaimed = true
                        KhfreshState.ticketQuestActive = false
                        KhfreshState.ticketTargetCount = 0
                        KhfreshState.ticketCurrentCount = 0
                        farmAtTicketTargetIsland()
                        local cooldownRemaining = getTicketQuestCooldownRemaining()
                        local cooldownMessage
                        if cooldownRemaining and cooldownRemaining > 0 then
                            cooldownMessage = string.format("Cooldown %d:%02d; farming continues at the same spot.",
                                math.floor(cooldownRemaining / 60), math.floor(cooldownRemaining % 60))
                        else
                            cooldownMessage = "Turned in. Waiting for the server to allow the next quest."
                        end
                        KhfreshLib:Notify({
                            Title = "Ticket Quest",
                            Message = cooldownMessage,
                            Duration = 2
                        })
                    else
                        KhfreshLib:Notify({ Title = "Quest", Message = "Turn-in failed, retrying...", Duration = 2 })
                    end
                else
                    KhfreshLib:Notify({ Title = "Quest", Message = "Giver not found, retrying...", Duration = 2 })
                end
            end
            KhfreshState.ticketQuestActive = false
            return
        end

        KhfreshState.ticketQuestClaimed = false

        -- Teleport to farm island only if far (prevent NPC <-> island bounce)
        local targetIsland = getTargetIsland()
        if targetIsland and targetIsland.cframe then
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local targetPos = targetIsland.cframe.Position + Vector3.new(0, 3, 0)
                local justNpc = (tick() - (KhfreshState.ticketLastFire or 0)) < 6
                local dist = (hrp.Position - targetPos).Magnitude
                if not justNpc and dist > 90 then
                    hrp.CFrame = CFrame.new(targetPos)
                end
                KhfreshState.ticketFarmCFrame = CFrame.new(targetPos)
            end
        end

        if typ and string.find(typ:lower(), "boss") then
            KhfreshState.isDoingUseBaitQuest = false
            enableBasicFishing(true)
            Fishing.Flags.AutoFarmBoss = true
            Fishing.Flags.AutoFarmSecretBoss = false
        elseif typ == "Fishing" then
            KhfreshState.isDoingUseBaitQuest = false
            enableBasicFishing(true)
            Fishing.Flags.AutoFarmBoss = false
            Fishing.Flags.AutoFarmSecretBoss = false
            pcall(function() safeFire("UpdateFishProgression") end)
        elseif typ == "UseBait" then
            KhfreshState.isDoingUseBaitQuest = true
            enableBasicFishing(true)
            Fishing.Flags.AutoFarmBoss = false
            Fishing.Flags.AutoFarmSecretBoss = false
            MiscFlags.AutoBuy = true
            local buyable = GetBuyableBaits()
            local found = false
            for _, name in ipairs(buyable) do
                if name == "Basic Bait" then
                    KhfreshState.selectedBait = name
                    found = true
                    break
                end
            end
            if not found then
                KhfreshState.selectedBait = buyable[1] or "No bait available"
            end
            MiscFlags.AutoEquipBait = true
        else
            KhfreshState.isDoingUseBaitQuest = false
            enableBasicFishing(true)
            Fishing.Flags.AutoFarmBoss = false
            Fishing.Flags.AutoFarmSecretBoss = false
        end
    end

    local function startAutoDoLoop()
        if KhfreshState.autoDoThread then return end
        KhfreshState.autoDoThread = task.spawn(function()
            while KhfreshState.autoDoRunning do
                pcall(updateQuestStatus)
                task.wait(0.5)
            end
            KhfreshState.autoDoThread = nil
        end)
        -- Dedicated claim loop (Nexus Auto Claim) — always tries accept when no quest
        if KhfreshState.autoClaimThread then
            pcall(function() task.cancel(KhfreshState.autoClaimThread) end)
            KhfreshState.autoClaimThread = nil
        end
        KhfreshState.ticketDailyDone = false
        KhfreshState.autoClaimThread = task.spawn(function()
            print("[Khfresh][TicketQuest] Auto-claim thread STARTED")
            while KhfreshState.autoDoRunning do
                local okLoop, errLoop = pcall(function()
                    local cooldownRemaining = getTicketQuestCooldownRemaining()
                    print("[Khfresh][TicketQuest] tick cd=", tostring(cooldownRemaining), "hasQuest=", tostring(hasAnyTicketQuest()))
                    if cooldownRemaining and cooldownRemaining > 0 then
                        -- Cooldown: farm only (no NPC spam)
                        farmAtTicketTargetIsland()
                        return
                    end

                    if hasAnyTicketQuest() then
                        return -- updateQuestStatus handles farm / turn-in
                    end

                    if tick() - (KhfreshState.ticketLastFire or 0) < 4 then
                        return
                    end
                    KhfreshState.ticketLastFire = tick()

                    local action = getAcceptAction()
                    print("[Khfresh][TicketQuest] ACCEPT", tostring(action))
                    local ok = ticketGoFire(action)
                    task.wait(0.7)
                    if hasAnyTicketQuest() then
                        KhfreshState.ticketFailCount = 0
                        print("[Khfresh][TicketQuest] CLAIMED OK")
                        KhfreshLib:Notify({
                            Title = "Ticket Quest",
                            Message = "Claimed " .. tostring(selectedTicketQuest),
                            Duration = 2
                        })
                        -- Return to farm island ONCE after claim (not every tick)
                        task.wait(0.4)
                        farmAtTicketTargetIsland()
                    else
                        KhfreshState.ticketFailCount = (KhfreshState.ticketFailCount or 0) + 1
                        print("[Khfresh][TicketQuest] accept FAIL fireOk=", tostring(ok), "fail#", KhfreshState.ticketFailCount)
                        -- Only return to farm if far from NPC for a while — avoid bounce
                        if KhfreshState.ticketFailCount % 2 == 0 then
                            farmAtTicketTargetIsland()
                        end
                    end
                end)
                if not okLoop then
                    warn("[Khfresh][TicketQuest] claim loop error:", tostring(errLoop))
                end
                if KhfreshState.ticketDailyDone then break end
                task.wait(1.2)
            end
            print("[Khfresh][TicketQuest] Auto-claim thread STOPPED")
            KhfreshState.autoClaimThread = nil
        end)
    end

    local autoDoToggle = DoSection:CreateToggle({
        Name = "Auto Do Ticket Quest (Fast)",
        Default = false,
        Callback = function(value)
            KhfreshState.autoDoRunning = value == true
            if value then
                if KhfreshState.autoDoThread then
                    task.cancel(KhfreshState.autoDoThread)
                    KhfreshState.autoDoThread = nil
                end
                KhfreshState.ticketDailyDone = false
                startAutoDoLoop()
                KhfreshLib:Notify({
                    Title = "Auto Do Quest",
                    Message = "ON — claim+do+turn-in (" .. tostring(selectedTicketQuest) .. ")",
                    Duration = 3
                })
            else
                khHardResetTicketQuestState()
                KhfreshLib:Notify({ Title = "Auto Do Quest", Message = "Stopped — state reset", Duration = 2 })
            end
        end
    })

    -- ===== TELEPORT RECOMMEND ISLAND (trong DoSection) =====
    Events.PowerWarning.OnClientEvent:Connect(function() end)
    local lastTeleportedPowerIsland = nil
    local RecommendToggle = DoSection:CreateToggle({
        Name = "Teleport to Recommend Island",
        Default = false,
        Callback = function(value)
            KhfreshState.autoRecommendRunning = value
            if value then
                if KhfreshState.autoRecommendThread then
                    task.cancel(KhfreshState.autoRecommendThread)
                    KhfreshState.autoRecommendThread = nil
                end
                KhfreshState.autoRecommendThread = task.spawn(function()
                    while KhfreshState.autoRecommendRunning do
                        pcall(function()
                            local bestIsland = getRecommendedIsland()
                            if KhfreshState.AutoFarm and KhfreshState.AutoFarm.enabled then
                                -- Auto Farm island locked — do not TP to recommended
                            elseif bestIsland and bestIsland.cframe and (not lastTeleportedPowerIsland or lastTeleportedPowerIsland ~= bestIsland.name) then
                                local hrp = LocalPlayer.Character and
                                LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                                if hrp then
                                    local targetPos = bestIsland.cframe.Position + Vector3.new(0, 3, 0)
                                    hrp.CFrame = CFrame.new(targetPos)
                                    lastTeleportedPowerIsland = bestIsland.name
                                    KhfreshLib:Notify({
                                        Title = "Recommend",
                                        Message = "Teleported to " ..
                                        bestIsland.name .. " (Power " .. (bestIsland.power or 0) .. ")",
                                        Duration = 2
                                    })
                                end
                            end
                        end)
                        task.wait(3)
                    end
                end)
            else
                if KhfreshState.autoRecommendThread then
                    task.cancel(KhfreshState.autoRecommendThread)
                    KhfreshState.autoRecommendThread = nil
                end
                lastTeleportedPowerIsland = nil
            end
        end
    })
end

-- ===== ASCEND TAB =====
do
    local UpgradeTab = Window:CreateTab("Ascend")
    local UpgradeSection = UpgradeTab:CreateSection("Ascend")

    local optionsList = { "Cash", "Level", "Crystal", "Ticket" }
    KhfreshState.UpgradeCharacter = Events:FindFirstChild("UpgradeCharacter")

    local multiDropdown = UpgradeSection:CreateDropdown({
        Name = "Select 2 upgrade options",
        Multi = true,
        Options = optionsList,
        Default = KhfreshState.selectedOptions or { "Cash", "Level" },
        Callback = function(values)
            if #values > 2 then
                KhfreshLib:Notify({ Title = "Upgrade", Message = "You can only select 2 options!", Duration = 2 })
                local newValues = {}
                for i = #values - 1, #values do table.insert(newValues, values[i]) end
                KhfreshState.selectedOptions = newValues
            else
                KhfreshState.selectedOptions = values
            end
        end
    })

    local upgradeCharMethodDropdown = UpgradeSection:CreateDropdown({
        Name = "Upgrade Method",
        Options = { "Instant", "Teleport" },
        Default = KhfreshState.upgradeCharacter.method or "Instant",
        Callback = function(value) KhfreshState.upgradeCharacter.method = value end
    })

    local function checkResources(option1, option2)
        local userData = Data:FindFirstChild(tostring(LocalPlayer.UserId))
        if not userData then return false, "Player data not found" end
        local resources = {
            Cash = { path = userData:FindFirstChild("Cash"), needed = 5000000000 },
            Level = { path = userData:FindFirstChild("Level") and userData.Level:FindFirstChild("Level"), needed = 500 },
            Crystal = { path = userData:FindFirstChild("Crystal"), needed = 1000 },
            Ticket = { path = userData:FindFirstChild("Ticket"), needed = 200 }
        }
        local function getValue(res)
            if res and res.path then
                if res.path:IsA("NumberValue") or res.path:IsA("IntValue") then
                    return res.path.Value
                end
            end
            return 0
        end
        local need1 = resources[option1]
        local need2 = resources[option2]
        if not need1 or not need2 then return false, "Invalid option" end
        local val1 = getValue(need1)
        local val2 = getValue(need2)
        if val1 >= need1.needed and val2 >= need2.needed then
            return true, "Enough"
        else
            local msg = option1 ..
            " (" .. val1 .. "/" .. need1.needed .. ") or " .. option2 .. " (" .. val2 .. "/" .. need2.needed .. ")"
            return false, "Not enough: " .. msg
        end
    end

    local autoToggle = UpgradeSection:CreateToggle({
        Name = "Auto Ascend",
        Default = false,
        Callback = function(value)
            KhfreshState.autoRebirthRunning = value
            if value then
                if KhfreshState.autoRebirthThread then
                    task.cancel(KhfreshState.autoRebirthThread)
                    KhfreshState.autoRebirthThread = nil
                end
                KhfreshState.autoRebirthThread = task.spawn(function()
                    while KhfreshState.autoRebirthRunning do
                        pcall(function()
                            if #KhfreshState.selectedOptions ~= 2 then
                                KhfreshLib:Notify({ Title = "Auto Ascend", Message = "Please select exactly 2 options!", Duration = 2 })
                                task.wait(2)
                                return
                            end
                            local ok, msg = checkResources(KhfreshState.selectedOptions[1],
                                KhfreshState.selectedOptions[2])
                            if ok then
                                KhfreshState.upgradeCharacter.teleported = false
                                KhfreshState.upgradeCharacter.oldPosition = nil
                                if KhfreshState.upgradeCharacter.method == "Teleport" then
                                    local npc = Workspace:FindFirstChild("NPC")
                                    if npc then
                                        local func = npc:FindFirstChild("Function")
                                        if func then
                                            local theShadow = func:FindFirstChild("The Shadow")
                                            if theShadow and theShadow:IsA("Model") then
                                                local hrp = theShadow:FindFirstChild("HumanoidRootPart")
                                                if hrp then
                                                    local char = LocalPlayer.Character
                                                    if char then
                                                        local root = char:FindFirstChild("HumanoidRootPart")
                                                        if root then
                                                            KhfreshState.upgradeCharacter.oldPosition = root.Position
                                                            root.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 3, 0))
                                                            KhfreshState.upgradeCharacter.teleported = true
                                                            task.wait(0.3)
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                    if not KhfreshState.upgradeCharacter.teleported then
                                        KhfreshLib:Notify({ Title = "Auto Ascend", Message =
                                        "Could not find The Shadow, teleport failed. Continuing anyway.", Duration = 3 })
                                    end
                                end

                                local result = KhfreshState.UpgradeCharacter and KhfreshState.UpgradeCharacter:InvokeServer(KhfreshState.selectedOptions)
                                if result and result.ok then
                                    KhfreshLib:Notify({ Title = "Auto Ascend", Message = "Upgraded successfully!", Duration = 2 })
                                else
                                    KhfreshLib:Notify({ Title = "Auto Ascend", Message = "Upgrade failed: " ..
                                    (result and result.msg or "unknown error"), Duration = 3 })
                                end

                                if KhfreshState.upgradeCharacter.teleported and KhfreshState.upgradeCharacter.oldPosition then
                                    local char = LocalPlayer.Character
                                    if char then
                                        safeRestorePosition(KhfreshState.upgradeCharacter)
                                    end
                                end
                            else
                                if math.random(1, 5) == 1 then
                                    KhfreshLib:Notify({ Title = "Auto Ascend", Message = msg, Duration = 3 })
                                end
                            end
                        end)
                        task.wait(2)
                    end
                end)
            else
                if KhfreshState.autoRebirthThread then
                    task.cancel(KhfreshState.autoRebirthThread)
                    KhfreshState.autoRebirthThread = nil
                end
                if KhfreshState.upgradeCharacter.teleported and KhfreshState.upgradeCharacter.oldPosition then
                    local char = LocalPlayer.Character
                    if char then
                        safeRestorePosition(KhfreshState.upgradeCharacter)
                    end
                end
                KhfreshLib:Notify({ Title = "Auto Ascend", Message = "Stopped", Duration = 2 })
            end
        end
    })

    local function displayStats()
        local userData = Data:FindFirstChild(tostring(LocalPlayer.UserId))
        if not userData then return end
        local cash = userData:FindFirstChild("Cash") and userData.Cash.Value or 0
        local level = userData:FindFirstChild("Level") and userData.Level:FindFirstChild("Level") and
        userData.Level.Level.Value or 0
        local crystal = userData:FindFirstChild("Crystal") and userData.Crystal.Value or 0
        local ticket = userData:FindFirstChild("Ticket") and userData.Ticket.Value or 0
        KhfreshLib:Notify({
            Title = "Resources",
            Message = string.format("Cash: %.2fB | Level: %d | Crystal: %d | Ticket: %d", cash / 1e9, level, crystal,
                ticket),
            Duration = 4
        })
    end
    UpgradeSection:CreateButton({ Name = "Check Resources", Callback = displayStats })
end

-- ===== TELEPORT TAB =====
do
    local TeleportTab = Window:CreateTab("Teleport")
    local ServersTab = Window:CreateTab("Servers")
    local TPSection = TeleportTab:CreateSection("NPC & Weather", "Left")

    TPSection:CreateButton({
        Name = "TP to Taoist",
        Callback = function()
            local taoist = nil
            for _, v in pairs(Workspace:GetDescendants()) do
                if v:IsA("Model") and string.find(v.Name:lower(), "taoist") and v:FindFirstChild("HumanoidRootPart") then
                    taoist = v
                    break
                end
            end
            if taoist and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                LocalPlayer.Character.HumanoidRootPart.CFrame = taoist.HumanoidRootPart.CFrame * CFrame.new(0, 0, 4)
                KhfreshLib:Notify({ Title = "Taoist", Message = "Teleported!", Duration = 3 })
            else
                KhfreshLib:Notify({ Title = "Taoist", Message = "Not found!", Duration = 3 })
            end
        end
    })

    TPSection:CreateButton({
        Name = "TP to Maoshan",
        Callback = function()
            local maoshan = nil
            for _, v in pairs(Workspace:GetDescendants()) do
                if v:IsA("Model") and (string.find(v.Name:lower(), "maoshan") or string.find(v.Name:lower(), "merchant")) and v:FindFirstChild("HumanoidRootPart") then
                    maoshan = v
                    break
                end
            end
            if maoshan and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                LocalPlayer.Character.HumanoidRootPart.CFrame = maoshan.HumanoidRootPart.CFrame * CFrame.new(0, 0, 4)
                KhfreshLib:Notify({ Title = "Maoshan", Message = "Teleported!", Duration = 3 })
            else
                KhfreshLib:Notify({ Title = "Maoshan", Message = "Not found!", Duration = 3 })
            end
        end
    })

    TPSection:CreateButton({
        Name = "TP to Spirit",
        Callback = function()
            local godFolder = Workspace:FindFirstChild("NPC") and Workspace.NPC:FindFirstChild("God")
            if not godFolder then
                KhfreshLib:Notify({ Title = "Spirit", Message = "Folder God not found!", Duration = 3 })
                return
            end
            local target = nil
            for _, child in pairs(godFolder:GetChildren()) do
                if child:IsA("Model") then
                    local hrp = child:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        target = hrp
                        break
                    end
                elseif child:IsA("BasePart") then
                    target = child
                    break
                end
            end
            if not target then
                KhfreshLib:Notify({ Title = "Spirit", Message = "No Spirit found!", Duration = 3 })
                return
            end
            local char = LocalPlayer.Character
            if not char then return end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = target.CFrame + Vector3.new(0, 3, 0)
                KhfreshLib:Notify({ Title = "Spirit", Message = "Teleported to Spirit!", Duration = 3 })
            end
        end
    })

    -- ===== NPC TELEPORT + GIVE FISH (Duan Gan / Dumb guy) =====
    do
        local GiveSection = TeleportTab:CreateSection("Quest NPC & Give Fish", "Right")

        local function npcRoot()
            return Workspace:FindFirstChild("NPC")
        end

        local function findNpcHrp(npcName)
            local hrp = nil
            pcall(function()
                local npcFolder = npcRoot()
                if not npcFolder then return end
                local f = npcFolder:FindFirstChild("Function")
                local m = (f and f:FindFirstChild(npcName)) or npcFolder:FindFirstChild(npcName)
                if m then hrp = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso") end
            end)
            return hrp
        end

        local function teleportNearNpc(npcName, offset)
            local hrp = findNpcHrp(npcName)
            local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not hrp or not root then return false end
            pcall(function()
                root.CFrame = CFrame.new(hrp.Position + (offset or Vector3.new(0, 3, 0)))
            end)
            return true
        end

        local function getFishKg(item)
            local w = 0
            pcall(function()
                if item:IsA("StringValue") then
                    local parts = {}
                    for part in string.gmatch(item.Value, "[^|]+") do table.insert(parts, part) end
                    if #parts >= 2 then w = tonumber((parts[2]:gsub("%D", ""))) or 0 end
                elseif item:IsA("NumberValue") or item:IsA("IntValue") then
                    w = tonumber(item.Value) or 0
                end
            end)
            return w
        end

        local function collectBigFish(minKg)
            local out = {}
            local userData = Data:FindFirstChild(tostring(LocalPlayer.UserId))
            local inv = userData and userData:FindFirstChild("Inventory")
            if not inv then return out end
            for _, item in pairs(inv:GetChildren()) do
                local kg = getFishKg(item)
                if kg >= minKg then
                    table.insert(out, { item = item, name = item.Name, kg = kg })
                end
            end
            table.sort(out, function(a, b) return a.kg > b.kg end)
            return out
        end

        local function giveFishToDumbGuy(entry)
            if not entry or not entry.item then return false end
            local model = nil
            pcall(function()
                local npcFolder = npcRoot()
                local f = npcFolder and npcFolder:FindFirstChild("Function")
                model = f and f:FindFirstChild("Dumb guy")
            end)
            local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            local origCF = root and root.CFrame
            if teleportNearNpc("Dumb guy", Vector3.new(0, 3, 0)) then task.wait(0.4) end

            pcall(function() safeFire("StartDialogue", "Dumb guy", model) end)
            task.wait(0.15)

            -- Server co the nhan nhieu dang extraData khac nhau -> thu lan luot
            local shapes = {
                { model,     entry.item },
                { model,     entry.name,      entry.kg },
                { model,     entry.item.Name, entry.item.Value },
                { entry.item },
            }
            local fired = false
            for _, extra in ipairs(shapes) do
                local ok = pcall(function()
                    safeFire("ChooseDialogueOption", "Dumb guy", 1, "GiveFish", extra)
                end)
                if ok then fired = true end
                task.wait(0.12)
            end

            if origCF and root and root.Parent then
                task.wait(0.3)
                pcall(function() root.CFrame = origCF end)
            end
            return fired
        end
        GiveSection:CreateButton({
            Name = "Teleport To Duan Gan NPC",
            Callback = function()
                if teleportNearNpc("Duan Gan", Vector3.new(0, 3, 0)) then
                    KhfreshLib:Notify({ Title = "Duan Gan", Message = "Teleported!", Duration = 3 })
                else
                    KhfreshLib:Notify({ Title = "Duan Gan", Message = "NPC not found!", Duration = 3 })
                end
            end
        })

        GiveSection:CreateButton({
            Name = "Teleport To Dumb Guy NPC",
            Callback = function()
                if teleportNearNpc("Dumb guy", Vector3.new(0, 3, 0)) then
                    KhfreshLib:Notify({ Title = "Dumb Guy", Message = "Teleported!", Duration = 3 })
                else
                    KhfreshLib:Notify({ Title = "Dumb Guy", Message = "NPC not found!", Duration = 3 })
                end
            end
        })

        GiveSection:CreateButton({
            Name = "Give 1 Fish > 2M kg",
            Callback = function()
                local list = collectBigFish(2000000)
                if #list == 0 then
                    KhfreshLib:Notify({ Title = "Give Fish", Message = "No fish over 2M kg in inventory!", Duration = 3 })
                    return
                end
                local e = list[1]
                if giveFishToDumbGuy(e) then
                    KhfreshLib:Notify({ Title = "Give Fish", Message = "Gave " ..
                    e.name .. " (" .. tostring(e.kg) .. " kg)", Duration = 3 })
                else
                    KhfreshLib:Notify({ Title = "Give Fish", Message = "Failed to give fish!", Duration = 3 })
                end
            end
        })

        KhfreshState.autoGiveFishRunning = false
        KhfreshState.autoGiveFishThread = nil

        GiveSection:CreateToggle({
            Name = "Auto Give Fish > 2M kg",
            Default = false,
            Callback = function(value)
                KhfreshState.autoGiveFishRunning = value
                if KhfreshState.autoGiveFishThread then
                    pcall(task.cancel, KhfreshState.autoGiveFishThread)
                    KhfreshState.autoGiveFishThread = nil
                end
                if not value then return end
                KhfreshState.autoGiveFishThread = task.spawn(function()
                    while KhfreshState.autoGiveFishRunning do
                        pcall(function()
                            local list = collectBigFish(2000000)
                            if #list > 0 then giveFishToDumbGuy(list[1]) end
                        end)
                        task.wait(2)
                    end
                end)
            end
        })

        -- ===== AUTO FARM CA 2M+ KG =====
        KhfreshState.autoFarm2MRunning = false
        KhfreshState.autoFarm2MThread = nil

        local function findBigKgIsland()
            local best, bestKg = nil, 0
            pcall(function()
                local rarity = Info:FindFirstChild("FishingAreaRarity")
                if not rarity then return end
                for _, area in pairs(rarity:GetChildren()) do
                    local maxKg = area:FindFirstChild("MaxKg")
                    local v = maxKg and tonumber(maxKg.Value) or 0
                    if v >= 2000000 and v > bestKg then
                        bestKg = v
                        best = area.Name
                    end
                end
            end)
            return best, bestKg
        end

        GiveSection:CreateToggle({
            Name = "Auto Farm 2M+ kg Fish",
            Default = false,
            Callback = function(value)
                KhfreshState.autoFarm2MRunning = value
                if KhfreshState.autoFarm2MThread then
                    pcall(task.cancel, KhfreshState.autoFarm2MThread)
                    KhfreshState.autoFarm2MThread = nil
                end
                if not value then return end

                local islandName, kg = findBigKgIsland()
                if islandName then
                    local isl = khResolveIslandEntry(islandName)
                    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if isl and isl.cframe and root then
                        pcall(function() root.CFrame = isl.cframe end)
                        KhfreshLib:Notify({
                            Title = "Auto Farm 2M+",
                            Message = "Farming at " .. tostring(isl.displayName or islandName) .. " (max " .. tostring(kg) .. " kg)",
                            Duration = 3
                        })
                    else
                        KhfreshLib:Notify({
                            Title = "Auto Farm 2M+",
                            Message = "Found " .. tostring(islandName) .. " but its live position is unavailable.",
                            Duration = 4
                        })
                    end
                else
                    KhfreshLib:Notify({ Title = "Auto Farm 2M+", Message = "No 2M+ zone found, farming here.", Duration = 3 })
                end

                KhfreshState.autoFarm2MThread = task.spawn(function()
                    while KhfreshState.autoFarm2MRunning do
                        pcall(function()
                            local c = LocalPlayer.Character
                            if c and not c:GetAttribute("Fishing") then
                                safeFire("Fishing")
                            end
                        end)
                        task.wait(0.6)
                    end
                end)
            end
        })
    end

    local weatherIslands = {
        ["foggy"] = "Island 7",
        ["blazing sun"] = "Island 8",
        ["snowy"] = "Island 6",
        ["windy"] = "Island 5",
        ["rainy"] = "Island 3",
        ["thunderstorm"] = "Island 2"
    }

    local function getCurrentWeather()
        local info = MainGui:FindFirstChild("Info")
        if info then
            local infoFrame = info:FindFirstChild("Info")
            if infoFrame then
                local weatherFrame = infoFrame:FindFirstChild("Weather")
                if weatherFrame then
                    local val = weatherFrame:FindFirstChild("Value")
                    if val then
                        local text = val:IsA("TextLabel") and val.Text or val.Value
                        return text:gsub("Weather:%s*", "")
                    end
                end
            end
        end
        return "Clear"
    end

    TPSection:CreateButton({
        Name = "Teleport To Current Weather",
        Callback = function()
            local currentWeather = getCurrentWeather()
            if currentWeather:lower() == "clear" or currentWeather == "" then
                KhfreshLib:Notify({ Title = "Weather TP", Message = "Server weather is Clear, no event to TP!", Duration = 3 })
                return
            end
            local targetIslandName = weatherIslands[currentWeather:lower()]
            if targetIslandName then
                local v = khResolveIslandEntry(targetIslandName)
                local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if v and v.cframe and hrp then
                    hrp.CFrame = CFrame.new(v.cframe.Position) + Vector3.new(0, 5, 0)
                    KhfreshLib:Notify({ Title = "Weather TP", Message = "Teleported to " ..
                    tostring(v.displayName or targetIslandName) .. " for " .. currentWeather, Duration = 4 })
                else
                    KhfreshLib:Notify({Title="Weather TP", Message="Could not resolve live position for "..tostring(targetIslandName)..".", Duration=3})
                end
            else
                KhfreshLib:Notify({ Title = "Weather TP", Message = "Unknown weather island mapping for: " ..
                currentWeather, Duration = 4 })
            end
        end
    })

    -- ===== ISLAND TELEPORTS (RESTORED) =====
    do
        local IslandSection = TeleportTab:CreateSection("Islands", "Right")
        -- One island dropdown and direct coordinate teleport.
        local tpIslandOptions = {}
        for i = 1, 13 do
            table.insert(tpIslandOptions, KH_ISLAND_LABELS[i] or ("Isle " .. tostring(i)))
        end
        local selectedTpIsland = tpIslandOptions[1]
        IslandSection:CreateDropdown({
            Name = "Select Island",
            Options = tpIslandOptions,
            Default = selectedTpIsland,
            Callback = function(value)
                selectedTpIsland = value or selectedTpIsland
            end
        })
        IslandSection:CreateButton({
            Name = "Teleport to Island",
            Callback = function()
                local char = LocalPlayer.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if not hrp then
                    KhfreshLib:Notify({Title="Teleport", Message="Character not ready.", Duration=2})
                    return
                end
                local island = khResolveIslandEntry(selectedTpIsland)
                if not island or not island.cframe then
                    KhfreshLib:Notify({Title="Teleport", Message="No live map position for "..tostring(selectedTpIsland)..".", Duration=3})
                    return
                end
                local ok, kind = khTeleportToIslandCoordinates(island)
                KhfreshLib:Notify({
                    Title = "Teleport",
                    Message = ok and ("Teleported to " .. tostring(island.displayName or selectedTpIsland))
                        or ("Failed: " .. tostring(kind)),
                    Duration = 3
                })
            end
        })
    end

    -- Server
    do
        local ServerSection = ServersTab:CreateSection("Server Hop", "Left")
        -- Hop = Nexus-style relay list, random join, no public/private filter
        local Http = Services.HttpService
        local TeleportService = Services.TeleportService
        KhfreshState.serverHopApiBase = KhfreshState.serverHopApiBase or "http://103.28.35.190:8000"
        KhfreshState.serverHopApiKey = KhfreshState.serverHopApiKey or ""
        KhfreshState.serverHopCategory = KhfreshState.serverHopCategory or "Taoist"
        KhfreshState.serverHopWeather = KhfreshState.serverHopWeather
            or (KhfreshState.WeatherHop and KhfreshState.WeatherHop.target)
            or "Thunderstorm"
        KhfreshState.serverHopServers = KhfreshState.serverHopServers or {}
        local hopJobIdInput = ""
        local lastHopAt = 0

        local categories = {
            "Taoist",
            "Maoshan",
            "Spirit",
            "Weather",
            "Vermilion Birdblood",
            "Black Tortoise Bloodline",
        }

        local function hopApi(path, method, body)
            local fn = (syn and syn.request) or http_request or request
                or (http and http.request) or (fluxus and fluxus.request)
            if type(fn) ~= "function" then return nil, "HTTP unavailable" end
            local base = tostring(KhfreshState.serverHopApiBase or ""):gsub("/$", "")
            local ok, res = pcall(function()
                return fn({
                    Url = base .. path,
                    Method = method or "GET",
                    Timeout = 12,
                    Headers = {
                        ["Content-Type"] = "application/json",
                        ["X-API-Key"] = tostring(KhfreshState.serverHopApiKey or ""),
                    },
                    Body = body,
                })
            end)
            if not ok or not res then return nil, "Relay request failed" end
            local code = tonumber(res.StatusCode or res.Status)
            if code and (code < 200 or code >= 300) then
                return nil, "Relay HTTP " .. tostring(code)
            end
            local raw = res.Body or res.body
            local good, data = pcall(function() return Http:JSONDecode(raw) end)
            if not good or type(data) ~= "table" then return nil, "Invalid relay response" end
            return data
        end

        local function readCurrentWeather()
            local result = "Clear"
            pcall(function()
                local attribute = Workspace:GetAttribute("Weather")
                if type(attribute) == "string" and attribute ~= "" then
                    result = attribute
                    return
                end
                local info = MainGui and MainGui:FindFirstChild("Info")
                local details = info and info:FindFirstChild("Info")
                local weather = details and details:FindFirstChild("Weather")
                local value = weather and weather:FindFirstChild("Value")
                if value then
                    local raw = value:IsA("TextLabel") and value.Text or value.Value
                    result = tostring(raw or "Clear"):gsub("Weather:%s*", ""):gsub("^%s+", ""):gsub("%s+$", "")
                end
            end)
            return result
        end

        local function scanLocalEventTags()
            local tags = { event = "", boss = "", npc = "" }
            local roots = {}
            for _, n in ipairs({ "Ocean", "Fishes", "NPC", "Map" }) do
                local r = Workspace:FindFirstChild(n)
                if r then roots[#roots + 1] = r end
            end
            if #roots == 0 then roots[1] = Workspace end
            local found = {}
            pcall(function()
                for _, root in ipairs(roots) do
                    for _, inst in ipairs(root:GetDescendants()) do
                        local name = string.lower(tostring(inst.Name or ""))
                        if name:find("taoist", 1, true) then found.taoist = true end
                        if name:find("maoshan", 1, true) then found.maoshan = true end
                        if name:find("spirit", 1, true) or name == "god" then found.spirit = true end
                        if name:find("vermilion", 1, true) or name:find("birdblood", 1, true) then found.vermilion = true end
                        if name:find("tortoise", 1, true) then found.tortoise = true end
                        for _, attr in ipairs({ "Event", "Boss", "NPC", "FishName" }) do
                            local v = inst:GetAttribute(attr)
                            if type(v) == "string" then
                                local low = string.lower(v)
                                if low:find("taoist", 1, true) then found.taoist = true end
                                if low:find("maoshan", 1, true) then found.maoshan = true end
                                if low:find("spirit", 1, true) then found.spirit = true end
                                if low:find("vermilion", 1, true) or low:find("birdblood", 1, true) then found.vermilion = true end
                                if low:find("tortoise", 1, true) then found.tortoise = true end
                            end
                        end
                    end
                end
            end)
            if found.vermilion then
                tags.event = "VermilionBirdblood"
                tags.boss = "Vermilion Birdblood"
            end
            if found.tortoise then
                tags.event = (tags.event ~= "" and tags.event .. "," or "") .. "BlackTortoise"
                tags.boss = "Black Tortoise Bloodline"
            end
            if found.taoist then tags.npc = "Taoist" end
            if found.maoshan then tags.npc = (tags.npc ~= "" and tags.npc .. "," or "") .. "Maoshan" end
            if found.spirit then tags.npc = (tags.npc ~= "" and tags.npc .. "," or "") .. "God" end
            return tags
        end

        local function publishHeartbeat()
            local tags = scanLocalEventTags()
            local payload = Http:JSONEncode({
                job_id = game.JobId,
                place_id = game.PlaceId,
                playing = #Players:GetPlayers(),
                max_players = Players.MaxPlayers,
                attributes = {
                    weather = readCurrentWeather(),
                    event = tags.event,
                    boss = tags.boss,
                    npc = tags.npc,
                },
                source = "khfresh_hub",
            })
            return hopApi("/v1/servers/update", "POST", payload) ~= nil
        end

        -- Same as Nexus kind() + Vermilion / Tortoise
        local function kindOf(s)
            local a = s.attributes or {}
            local event = string.lower(tostring(a.event or ""))
            local boss = string.lower(tostring(a.boss or ""))
            local npc = string.lower(tostring(a.npc or ""))
            local blob = event .. " " .. boss .. " " .. npc
            -- Events first (exact game names)
            if blob:find("vermilion", 1, true) or blob:find("birdblood", 1, true) then
                return "Vermilion Birdblood"
            end
            if blob:find("tortoise", 1, true) or blob:find("blacktortoise", 1, true) then
                return "Black Tortoise Bloodline"
            end
            -- NPC events (Nexus order / tags)
            if blob:find("taoist", 1, true) then return "Taoist" end
            if blob:find("maoshan", 1, true) then return "Maoshan" end
            -- Spirit: spirit / god / pray (Nexus: npc=="god")
            if blob:find("spirit", 1, true) or blob:find("god", 1, true) or npc == "god" then
                return "Spirit"
            end
            local w = tostring(a.weather or "")
            if w ~= "" and string.lower(w) ~= "clear" then return "Weather" end
            return "Other"
        end

        local function weatherMatch(s, wanted)
            local a = s.attributes or {}
            local w = string.lower(tostring(a.weather or "")):gsub("%-", " "):gsub("%s+", " ")
            local want = string.lower(tostring(wanted or "")):gsub("%-", " "):gsub("%s+", " ")
            if want == "" then return false end
            return w == want or (w ~= "" and (w:find(want, 1, true) or want:find(w, 1, true)))
        end

        -- Nexus join rules: not empty job, not current, not full — then random
        local function isJoinable(s)
            local job = tostring(s.job_id or s.jobId or s.id or "")
            if job == "" or job == tostring(game.JobId) then return false end
            local n = tonumber(s.playing) or 0
            local m = tonumber(s.max_players or s.maxPlayers) or 0
            if m > 0 and n >= m then return false end
            return true
        end

        local function pickRandom(list)
            if type(list) ~= "table" or #list == 0 then return nil end
            return list[math.random(1, #list)]
        end

        local function joinJob(job)
            job = tostring(job or "")
            if job == "" then
                KhfreshLib:Notify({ Title = "Server Hop", Message = "No valid Job ID.", Duration = 3 })
                return false
            end
            if job == tostring(game.JobId) then
                KhfreshLib:Notify({ Title = "Server Hop", Message = "Already in this server.", Duration = 2 })
                return false
            end
            lastHopAt = tick()
            KhfreshLib:Notify({
                Title = "Server Hop",
                Message = "Joining " .. string.sub(job, 1, 10) .. "...",
                Duration = 3,
            })
            local ok, err = pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, job, LocalPlayer)
            end)
            if not ok then
                KhfreshLib:Notify({ Title = "Server Hop", Message = "Join failed: " .. tostring(err), Duration = 4 })
                return false
            end
            return true
        end

        local function hopByCategory(category)
            category = tostring(category or KhfreshState.serverHopCategory or "Taoist")
            if tick() - lastHopAt < 2 then
                KhfreshLib:Notify({ Title = "Server Hop", Message = "Wait a moment...", Duration = 2 })
                return
            end

            KhfreshLib:Notify({
                Title = "Server Hop",
                Message = "Loading " .. category .. "...",
                Duration = 2,
            })
            pcall(publishHeartbeat)
            local data, err = hopApi(string.format("/v1/servers?place_id=%d", game.PlaceId))
            if not data or type(data.servers) ~= "table" then
                KhfreshLib:Notify({
                    Title = "Server Hop",
                    Message = "No server found" .. (err and (" (" .. err .. ")") or ""),
                    Duration = 4,
                })
                return
            end
            KhfreshState.serverHopServers = data.servers

            local matched = {}
            for _, s in ipairs(data.servers) do
                if isJoinable(s) then
                    if category == "Weather" then
                        if weatherMatch(s, KhfreshState.serverHopWeather) then
                            matched[#matched + 1] = s
                        end
                    elseif kindOf(s) == category then
                        matched[#matched + 1] = s
                    end
                end
            end

            local target = pickRandom(matched)
            if not target then
                KhfreshLib:Notify({
                    Title = "Server Hop",
                    Message = "No server found",
                    Duration = 4,
                })
                return
            end

            local job = tostring(target.job_id or target.jobId or target.id or "")
            local n = tonumber(target.playing) or 0
            local m = tonumber(target.max_players or target.maxPlayers) or 0
            KhfreshLib:Notify({
                Title = "Server Hop",
                Message = string.format("%s | %d/%d | %s", category, n, m, string.sub(job, 1, 8)),
                Duration = 3,
            })
            joinJob(job)
        end

        -- ===== UI =====
        ServerSection:CreateTextbox({
            Name = "Job ID",
            Placeholder = "Paste JobId here",
            Default = "",
            Callback = function(value)
                hopJobIdInput = tostring(value or ""):gsub("%s+", "")
            end,
        })
        ServerSection:CreateButton({
            Name = "Join Job ID",
            Callback = function()
                if hopJobIdInput == "" then
                    KhfreshLib:Notify({ Title = "Server", Message = "Enter a Job ID first", Duration = 3 })
                    return
                end
                joinJob(hopJobIdInput)
            end,
        })
        ServerSection:CreateButton({
            Name = "Copy Current Job ID",
            Callback = function()
                local jid = tostring(game.JobId or "")
                pcall(function()
                    if setclipboard then setclipboard(jid)
                    elseif toclipboard then toclipboard(jid)
                    end
                end)
                KhfreshLib:Notify({ Title = "Server", Message = "JobId: " .. jid, Duration = 3 })
            end,
        })

        local weatherOptions = {}
        pcall(function()
            if type(khGetSupportedWeatherNames) == "function" then
                weatherOptions = khGetSupportedWeatherNames() or {}
            end
        end)
        if type(weatherOptions) ~= "table" or #weatherOptions == 0 then
            weatherOptions = { "Thunderstorm", "Rain", "Sunny", "Cloudy", "Fog", "Windy", "Snow" }
        end
        local weatherDefault = tostring(KhfreshState.serverHopWeather or "")
        if not table.find(weatherOptions, weatherDefault) then
            weatherDefault = weatherOptions[1]
            KhfreshState.serverHopWeather = weatherDefault
        end

        local weatherDropdownHandle = nil
        local function setWeatherDropdownVisible(vis)
            local show = vis and true or false
            if not weatherDropdownHandle then return end
            pcall(function()
                local h = weatherDropdownHandle
                if type(h) == "table" and type(h.SetVisible) == "function" then
                    h:SetVisible(show)
                    return
                end
                if type(h) == "table" and h.Row and h.Row.Visible ~= nil then
                    h.Row.Visible = show
                    return
                end
            end)
        end

        ServerSection:CreateDropdown({
            Name = "Category",
            Options = categories,
            Default = table.find(categories, KhfreshState.serverHopCategory)
                and KhfreshState.serverHopCategory or categories[1],
            Callback = function(v)
                if type(v) == "table" then v = v[1] end
                KhfreshState.serverHopCategory = tostring(v or "Taoist")
                setWeatherDropdownVisible(KhfreshState.serverHopCategory == "Weather")
            end,
        })

        weatherDropdownHandle = ServerSection:CreateDropdown({
            Name = "Weather Target",
            Options = weatherOptions,
            Default = weatherDefault,
            Callback = function(v)
                if type(v) == "table" then v = v[1] end
                KhfreshState.serverHopWeather = tostring(v or weatherDefault)
                if KhfreshState.WeatherHop then
                    KhfreshState.WeatherHop.target = KhfreshState.serverHopWeather
                end
            end,
        })
        -- Hidden until Category == Weather
        setWeatherDropdownVisible(false)
        task.defer(function()
            setWeatherDropdownVisible(KhfreshState.serverHopCategory == "Weather")
        end)

        ServerSection:CreateButton({
            Name = "Hop",
            Callback = function()
                hopByCategory(KhfreshState.serverHopCategory)
            end,
        })
        ServerSection:CreateButton({
            Name = "Refresh List",
            Callback = function()
                task.spawn(function()
                    local ok = publishHeartbeat()
                    local data, err = hopApi(string.format("/v1/servers?place_id=%d", game.PlaceId))
                    local n = (data and type(data.servers) == "table") and #data.servers or 0
                    KhfreshLib:Notify({
                        Title = "Server Hop",
                        Message = string.format(
                            "Servers: %d | HB: %s%s",
                            n,
                            ok and "ok" or "fail",
                            err and (" | " .. err) or ""
                        ),
                        Duration = 4,
                    })
                end)
            end,
        })

        task.spawn(function()
            while alive() do
                pcall(publishHeartbeat)
                task.wait(15)
            end
        end)
        task.defer(function() pcall(publishHeartbeat) end)

        KhfreshState._eventHopStep = function() end
        KhfreshState._weatherHopStep = function() end
        runtimeEnv.KhfreshResumeServerSearch = function() end
    end


    -- ===== RECOMMEND ISLAND TELEPORT =====
    do
        local RecommendTeleportSection = TeleportTab:CreateSection("Recommended Island", "Left")
        RecommendTeleportSection:CreateButton({
            Name = "Teleport to Recommend Island",
            Callback = function()
                local ok, bestIsland = pcall(getRecommendedIsland)
                if not ok or not bestIsland then
                    KhfreshLib:Notify({Title="Recommend", Message="No recommended island found.", Duration=2})
                    return
                end
                local char = LocalPlayer.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if not root then return end
                if not bestIsland.cframe then
                    KhfreshLib:Notify({Title="Recommend", Message="Live position is unavailable for this island.", Duration=3})
                    return
                end
                root.CFrame = CFrame.new(bestIsland.cframe.Position + Vector3.new(0, 3, 0))
                KhfreshLib:Notify({Title="Recommend", Message="Teleported to " .. tostring(bestIsland.name), Duration=2})
            end
        })
    end

-- ===== PLAYERS SECTION =====
    do
        local PlayerSection = TeleportTab:CreateSection("Players", "Right")

        local selectedPlayer = nil
        local playerDropdown = nil -- Keep a reference to the dropdown
        local playerList = {}

        -- List refresh helper
        local function refreshPlayerList()
            -- Read the player list
            playerList = {}
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    table.insert(playerList, player.Name)
                end
            end
            if #playerList == 0 then
                table.insert(playerList, "No other players")
                selectedPlayer = "No other players"
            else
                selectedPlayer = playerList[1]
            end

            -- Refresh in-place (never create a second Select Player dropdown)
            if playerDropdown and type(playerDropdown.Refresh) == "function" then
                playerDropdown:Refresh(playerList, true)
                if type(playerDropdown.Set) == "function" then
                    pcall(function() playerDropdown:Set(selectedPlayer) end)
                end
            elseif playerDropdown and type(playerDropdown.SetValues) == "function" then
                playerDropdown:SetValues(playerList)
            else
                playerDropdown = PlayerSection:CreateDropdown({
                    Name = "Select Player",
                    Options = playerList,
                    Default = selectedPlayer,
                    Callback = function(value)
                        if type(value) == "table" then value = value[1] end
                        selectedPlayer = tostring(value or "")
                    end
                })
            end
        end

        -- Create the dropdown for the first time only
        refreshPlayerList()

        -- Refresh List button
        PlayerSection:CreateButton({
            Name = "Refresh List",
            Callback = function()
                refreshPlayerList()
                KhfreshLib:Notify({
                    Title = "Players",
                    Message = "Player list refreshed! Found " .. #playerList .. " players.",
                    Duration = 2
                })
            end
        })

        -- Teleport to Player button
        PlayerSection:CreateButton({
            Name = "Teleport to Player",
            Callback = function()
                if not selectedPlayer or selectedPlayer == "No other players" then
                    KhfreshLib:Notify({ Title = "Teleport", Message = "No valid player selected!", Duration = 2 })
                    return
                end

                local targetPlayer = nil
                for _, player in ipairs(Players:GetPlayers()) do
                    if player.Name == selectedPlayer then
                        targetPlayer = player
                        break
                    end
                end

                if not targetPlayer then
                    KhfreshLib:Notify({ Title = "Teleport", Message = "Player not found! Try refreshing.", Duration = 2 })
                    return
                end

                local character = targetPlayer.Character
                if not character then
                    KhfreshLib:Notify({ Title = "Teleport", Message = targetPlayer.Name .. " has no character!", Duration = 2 })
                    return
                end

                local hrp = character:FindFirstChild("HumanoidRootPart")
                if not hrp then
                    KhfreshLib:Notify({ Title = "Teleport", Message = "Cannot find HumanoidRootPart!", Duration = 2 })
                    return
                end

                local myChar = LocalPlayer.Character
                if not myChar then return end
                local myHrp = myChar:FindFirstChild("HumanoidRootPart")
                if not myHrp then return end

                myHrp.CFrame = hrp.CFrame + Vector3.new(0, 3, 0)

                KhfreshLib:Notify({
                    Title = "Teleport",
                    Message = "Teleported to " .. targetPlayer.Name,
                    Duration = 2
                })
            end
        })
        -- ===== SPECTATE PLAYER =====
        local spectateEnabled = false
        local spectateTarget = nil
        local oldSubject = nil
        local oldCameraType = nil
        local espConnections = {}

        -- Start spectate
        local function startSpectate()
            if spectateEnabled then return end

            -- Find the first player other than yourself
            local targetPlayer = nil
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    targetPlayer = player
                    break
                end
            end

            if not targetPlayer then
                KhfreshLib:Notify({ Title = "Spectate", Message = "No other players to spectate!", Duration = 2 })
                if KhfreshState.spectateToggle then
                    KhfreshState.spectateToggle:Set(false)
                end
                return
            end

            -- Check whether the target has a character
            if not targetPlayer.Character then
                KhfreshLib:Notify({ Title = "Spectate", Message = targetPlayer.Name .. " has no character!", Duration = 2 })
                if KhfreshState.spectateToggle then
                    KhfreshState.spectateToggle:Set(false)
                end
                return
            end

            local targetHrp = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not targetHrp then
                KhfreshLib:Notify({ Title = "Spectate", Message = "Cannot find HumanoidRootPart of " .. targetPlayer
                .Name, Duration = 2 })
                if KhfreshState.spectateToggle then
                    KhfreshState.spectateToggle:Set(false)
                end
                return
            end

            spectateEnabled = true
            spectateTarget = targetPlayer

            local camera = workspace.CurrentCamera
            oldSubject = camera.CameraSubject
            oldCameraType = camera.CameraType

            -- Lock the camera onto the target
            camera.CameraSubject = targetHrp
            camera.CameraType = Enum.CameraType.Custom

            KhfreshLib:Notify({ Title = "Spectate", Message = "Spectating " .. targetPlayer.Name, Duration = 2 })
        end

        -- Stop spectate
        local function stopSpectate()
            spectateEnabled = false
            spectateTarget = nil

            -- Reset the camera back to the local player
            pcall(function()
                local camera = workspace.CurrentCamera
                if oldSubject then
                    camera.CameraSubject = oldSubject
                    oldSubject = nil
                end
                if oldCameraType then
                    camera.CameraType = oldCameraType
                    oldCameraType = nil
                end
            end)

            KhfreshLib:Notify({ Title = "Spectate", Message = "Stopped spectating", Duration = 2 })
        end

        -- Toggle Spectate Player
        local spectateToggle = PlayerSection:CreateToggle({
            Name = "Spectate Player",
            Default = false,
            Callback = function(value)
                if value then
                    startSpectate()
                else
                    stopSpectate()
                end
            end
        })

        -- Persist the toggle in KhfreshState
        KhfreshState.spectateToggle = spectateToggle

        -- Handle the target leaving or their character resetting
        local function onTargetCharacterAdded()
            if spectateEnabled and spectateTarget then
                local char = spectateTarget.Character
                if char then
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        workspace.CurrentCamera.CameraSubject = hrp
                    end
                end
            end
        end

        -- Listen for the target's character changing
        local charAddedConn = nil
        local playerRemovingConn = Players.PlayerRemoving:Connect(function(player)
            if spectateEnabled and player == spectateTarget then
                stopSpectate()
                if KhfreshState.spectateToggle then
                    KhfreshState.spectateToggle:Set(false)
                end
            end
        end)

        -- While spectating, watch the target's CharacterAdded
        local function monitorTarget()
            if spectateEnabled and spectateTarget then
                if charAddedConn then charAddedConn:Disconnect() end
                charAddedConn = spectateTarget.CharacterAdded:Connect(function()
                    task.wait(0.5)
                    onTargetCharacterAdded()
                end)
            else
                if charAddedConn then
                    charAddedConn:Disconnect()
                    charAddedConn = nil
                end
            end
        end

        -- Wrap startSpectate to attach the monitor
        local originalStart = startSpectate
        startSpectate = function()
            originalStart()
            monitorTarget()
        end

        -- Wrap stopSpectate to clean up
        local originalStop = stopSpectate
        stopSpectate = function()
            originalStop()
            if charAddedConn then
                charAddedConn:Disconnect()
                charAddedConn = nil
            end
        end

        table.insert(espConnections, { conn = playerRemovingConn })
    end
    -- ===== NPCs SECTION =====
    do
        local NpcSection = TeleportTab:CreateSection("NPCs", "Right")

        -- NPC list helper (models parented to a Folder under workspace.NPC.Function)
        local function getNpcList()
            local npcs = {}
            local funcFolder = workspace:FindFirstChild("NPC") and workspace.NPC:FindFirstChild("Function")
            if not funcFolder then return npcs end

            for _, child in ipairs(funcFolder:GetDescendants()) do
                if child:IsA("Model") and child.Parent and child.Parent:IsA("Folder") then
                    table.insert(npcs, child.Name)
                end
            end
            return npcs
        end

        local npcList = getNpcList()
        if #npcList == 0 then
            table.insert(npcList, "No NPCs found")
        end

        local selectedNpc = npcList[1]

        -- Create the dropdown
        local npcDropdown = NpcSection:CreateDropdown({
            Name = "Misc NPCs",
            Options = npcList,
            Default = selectedNpc,
            Callback = function(value)
                selectedNpc = value
            end
        })

        -- Teleport to selected NPC button
        NpcSection:CreateButton({
            Name = "Teleport to selected NPC",
            Callback = function()
                if not selectedNpc or selectedNpc == "No NPCs found" then
                    KhfreshLib:Notify({ Title = "NPC Teleport", Message = "No NPC selected!", Duration = 2 })
                    return
                end

                local funcFolder = workspace:FindFirstChild("NPC") and workspace.NPC:FindFirstChild("Function")
                if not funcFolder then
                    KhfreshLib:Notify({ Title = "NPC Teleport", Message = "NPC.Function folder not found!", Duration = 2 })
                    return
                end

                local targetModel = nil
                for _, child in ipairs(funcFolder:GetDescendants()) do
                    if child:IsA("Model") and child.Name == selectedNpc and child.Parent and child.Parent:IsA("Folder") then
                        targetModel = child
                        break
                    end
                end

                if not targetModel then
                    KhfreshLib:Notify({ Title = "NPC Teleport", Message = "NPC not found!", Duration = 2 })
                    return
                end

                local hrp = targetModel:FindFirstChild("HumanoidRootPart") or targetModel.PrimaryPart
                if not hrp then
                    hrp = targetModel:FindFirstChildWhichIsA("BasePart")
                end
                if not hrp then
                    KhfreshLib:Notify({ Title = "NPC Teleport", Message = "Cannot find part to teleport to!", Duration = 2 })
                    return
                end

                local myChar = LocalPlayer.Character
                if not myChar then return end
                local myHrp = myChar:FindFirstChild("HumanoidRootPart")
                if not myHrp then return end

                myHrp.CFrame = hrp.CFrame + Vector3.new(0, 3, 0)

                KhfreshLib:Notify({ Title = "NPC Teleport", Message = "Teleported to " .. selectedNpc, Duration = 2 })
            end
        })
        -- ===== LEARN SKILL NPC =====
        local selectedLearnNpc = "Sage Yijiu"

        -- Dropdown with a single option
        local learnDropdown = NpcSection:CreateDropdown({
            Name = "Learn Skill NPC",
            Options = { "Sage Yijiu" },
            Default = "Sage Yijiu",
            Callback = function(value)
                selectedLearnNpc = value
            end
        })

        -- Teleport to selected NPC button
        NpcSection:CreateButton({
            Name = "Teleport to selected NPC",
            Callback = function()
                local targetModel = workspace:FindFirstChild("NPC")
                    and workspace.NPC:FindFirstChild("LearnSkill")
                    and workspace.NPC.LearnSkill:FindFirstChild("Sage Yijiu")

                if not targetModel then
                    KhfreshLib:Notify({ Title = "Learn Skill", Message = "Sage Yijiu not found!", Duration = 2 })
                    return
                end

                local hrp = targetModel:FindFirstChild("HumanoidRootPart") or targetModel.PrimaryPart
                if not hrp then
                    hrp = targetModel:FindFirstChildWhichIsA("BasePart")
                end
                if not hrp then
                    KhfreshLib:Notify({ Title = "Learn Skill", Message = "Cannot find part to teleport to!", Duration = 2 })
                    return
                end

                local myChar = LocalPlayer.Character
                if not myChar then return end
                local myHrp = myChar:FindFirstChild("HumanoidRootPart")
                if not myHrp then return end

                myHrp.CFrame = hrp.CFrame + Vector3.new(0, 3, 0)

                KhfreshLib:Notify({ Title = "Learn Skill", Message = "Teleported to Sage Yijiu", Duration = 2 })
            end
        })
        -- ===== SECRET RODS SECTION =====
        -- Secret Rod list (models parented to a Folder under workspace.SecretRod)
        local function getSecretRodList()
            local rods = {}
            local secretRodFolder = workspace:FindFirstChild("SecretRod")
            if not secretRodFolder then return rods end

            for _, child in ipairs(secretRodFolder:GetDescendants()) do
                if child:IsA("Model") and child.Parent and child.Parent:IsA("Folder") then
                    table.insert(rods, child.Name)
                end
            end
            return rods
        end

        local rodList = getSecretRodList()
        if #rodList == 0 then
            table.insert(rodList, "No Secret Rods found")
        end

        local selectedRod = rodList[1]

        -- Dropdown
        local rodDropdown = NpcSection:CreateDropdown({
            Name = "Secret Rods",
            Options = rodList,
            Default = selectedRod,
            Callback = function(value)
                selectedRod = value
            end
        })

        -- Teleport button
        NpcSection:CreateButton({
            Name = "Teleport to selected Secret Rod",
            Callback = function()
                if not selectedRod or selectedRod == "No Secret Rods found" then
                    KhfreshLib:Notify({ Title = "Secret Rod", Message = "No Secret Rod selected!", Duration = 2 })
                    return
                end

                local secretRodFolder = workspace:FindFirstChild("SecretRod")
                if not secretRodFolder then
                    KhfreshLib:Notify({ Title = "Secret Rod", Message = "SecretRod folder not found!", Duration = 2 })
                    return
                end

                local targetModel = nil
                for _, child in ipairs(secretRodFolder:GetDescendants()) do
                    if child:IsA("Model") and child.Name == selectedRod and child.Parent and child.Parent:IsA("Folder") then
                        targetModel = child
                        break
                    end
                end

                if not targetModel then
                    KhfreshLib:Notify({ Title = "Secret Rod", Message = "Secret Rod not found!", Duration = 2 })
                    return
                end

                local hrp = targetModel:FindFirstChild("HumanoidRootPart") or targetModel.PrimaryPart
                if not hrp then
                    hrp = targetModel:FindFirstChildWhichIsA("BasePart")
                end
                if not hrp then
                    KhfreshLib:Notify({ Title = "Secret Rod", Message = "Cannot find part to teleport to!", Duration = 2 })
                    return
                end

                local myChar = LocalPlayer.Character
                if not myChar then return end
                local myHrp = myChar:FindFirstChild("HumanoidRootPart")
                if not myHrp then return end

                myHrp.CFrame = hrp.CFrame + Vector3.new(0, 3, 0)

                KhfreshLib:Notify({ Title = "Secret Rod", Message = "Teleported to " .. selectedRod, Duration = 2 })
            end
        })
    end
end


-- ===== SETTINGS TAB =====
do
    local SettingsTab = Window:CreateTab("Settings")
    local CharSection = SettingsTab:CreateSection("Character")

    CharSection:CreateSlider({
        Name = "Walk Speed",
        Range = {0, 300},
        Default = tonumber(KhfreshUserConfig.WalkSpeed) or 16,
        Increment = 1,
        Color = Color3.fromRGB(44, 153, 93),
        Callback = function(V)
            if KhfreshLib.SiriusChar then KhfreshLib.SiriusChar.WalkSpeed = V end
            pcall(function() LocalPlayer.Character.Humanoid.WalkSpeed = V end)
        end
    })

    local function startFly()
        local c = LocalPlayer.Character
        if not c or not c:FindFirstChild("HumanoidRootPart") then return end
        if KhfreshState.flying then return end
        if KhfreshState.bg then KhfreshState.bg:Destroy() end
        if KhfreshState.bv then KhfreshState.bv:Destroy() end
        local h = c.HumanoidRootPart
        KhfreshState.bg = Instance.new("BodyGyro", h)
        KhfreshState.bg.P = 9e4
        KhfreshState.bg.maxTorque = Vector3.new(9e9, 9e9, 9e9)
        KhfreshState.bg.cframe = h.CFrame
        KhfreshState.bv = Instance.new("BodyVelocity", h)
        KhfreshState.bv.velocity = Vector3.new(0, 0, 0)
        KhfreshState.bv.maxForce = Vector3.new(9e9, 9e9, 9e9)
        KhfreshState.flying = true
        if KhfreshState.flyRenderConnection then KhfreshState.flyRenderConnection:Disconnect() end
        KhfreshState.flyRenderConnection = RunService.RenderStepped:Connect(function()
            if not KhfreshState.flying or not KhfreshState.bg or not KhfreshState.bv then return end
            local character = LocalPlayer.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if not root then return end
            local look = Camera.CFrame.LookVector
            local move = character.Humanoid and character.Humanoid.MoveDirection or Vector3.zero
            local horizontal = Vector3.new(move.X, 0, move.Z)
            local vertical = (KhfreshState.flyKeys.Up and 1 or 0) - (KhfreshState.flyKeys.Down and 1 or 0)
            KhfreshState.bv.Velocity = horizontal * KhfreshState.flySpeed + Vector3.new(0, vertical * KhfreshState.flySpeed, 0)
            local flatLook = Vector3.new(look.X, 0, look.Z)
            if flatLook.Magnitude > 0.01 then
                KhfreshState.bg.CFrame = CFrame.lookAt(root.Position, root.Position + flatLook.Unit)
            end
        end)
        local humanoid = c:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid.PlatformStand = true end
        if KhfreshState.flyInputConnection then KhfreshState.flyInputConnection:Disconnect() end
        if KhfreshState.flyInputEndConnection then KhfreshState.flyInputEndConnection:Disconnect() end
        KhfreshState.flyInputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if input.KeyCode == Enum.KeyCode.Space then KhfreshState.flyKeys.Up = true end
            if input.KeyCode == Enum.KeyCode.LeftControl then KhfreshState.flyKeys.Down = true end
        end)
        KhfreshState.flyInputEndConnection = UserInputService.InputEnded:Connect(function(input)
            if input.KeyCode == Enum.KeyCode.Space then KhfreshState.flyKeys.Up = false end
            if input.KeyCode == Enum.KeyCode.LeftControl then KhfreshState.flyKeys.Down = false end
        end)
    end

    local function stopFly()
        KhfreshState.flying = false
        if KhfreshState.flyRenderConnection then
            KhfreshState.flyRenderConnection:Disconnect()
            KhfreshState.flyRenderConnection = nil
        end
        KhfreshState.flyKeys.Up, KhfreshState.flyKeys.Down = false, false
        if KhfreshState.flyInputConnection then
            KhfreshState.flyInputConnection:Disconnect(); KhfreshState.flyInputConnection = nil
        end
        if KhfreshState.flyInputEndConnection then
            KhfreshState.flyInputEndConnection:Disconnect(); KhfreshState.flyInputEndConnection = nil
        end
        if KhfreshState.bg then
            KhfreshState.bg:Destroy(); KhfreshState.bg = nil
        end
        if KhfreshState.bv then
            KhfreshState.bv:Destroy(); KhfreshState.bv = nil
        end
        local c = LocalPlayer.Character
        if c then
            local humanoid = c:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid.PlatformStand = false end
        end
    end

    CharSection:CreateToggle({
        Name = "Fly Mode",
        Default = false,
        Callback = function(V)
            MiscFlags.FlyMode = V
            if KhfreshLib.SetFlight then
                KhfreshLib.SetFlight(V)
            else
                if V then startFly() else stopFly() end
            end
        end
    })
    CharSection:CreateSlider({
        Name = "Fly Speed",
        Range = {1, 25},
        Default = 3,
        Increment = 1,
        Color = Color3.fromRGB(170, 37, 46),
        Callback = function(V)
            if KhfreshLib.SiriusChar then KhfreshLib.SiriusChar.FlightSpeed = V end
            KhfreshState.flySpeed = V * 15
        end
    })
    CharSection:CreateToggle({
        Name = "Noclip",
        Default = false,
        Callback = function(V)
            MiscFlags.Noclip = V
            if KhfreshLib.SetNoclip then KhfreshLib.SetNoclip(V) end
        end
    })
    CharSection:CreateToggle({ Name = "Infinite Jump", Default = false, Callback = function(V) MiscFlags.InfiniteJump = V end })

    local function findWaterParts()
        local parts = {}
        for _, v in pairs(Workspace:GetDescendants()) do
            if v:IsA("BasePart") then
                local name = v.Name:lower()
                if name:match("water") or name:match("ocean") or v.Material == Enum.Material.Water then
                    table.insert(parts, v)
                end
            end
        end
        return parts
    end

    local function enableWaterWalk()
        if KhfreshState.waterWalkEnabled then return end
        KhfreshState.waterWalkEnabled = true
        KhfreshState.waterPartsList = findWaterParts()
        for _, part in ipairs(KhfreshState.waterPartsList) do part.CanCollide = true end
        KhfreshState.waterPart = Instance.new("Part")
        KhfreshState.waterPart.Size = Vector3.new(16, 1, 16)
        KhfreshState.waterPart.Transparency = 1
        KhfreshState.waterPart.Anchored = true
        KhfreshState.waterPart.CanCollide = true
        KhfreshState.waterPart.Name = "WaterWalkPart"
        KhfreshState.waterPart.Parent = Workspace
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            KhfreshState.waterY = char.HumanoidRootPart.Position.Y - 3.2
        else
            KhfreshState.waterY = 0
        end
        if KhfreshState.waterWalkConnection then KhfreshState.waterWalkConnection:Disconnect() end
        KhfreshState.waterWalkConnection = RunService.RenderStepped:Connect(function()
            if not KhfreshState.waterWalkEnabled then return end
            local char = LocalPlayer.Character
            if not char then return end
            local root = char:FindFirstChild("HumanoidRootPart")
            if not root then return end
            if KhfreshState.waterPart then
                KhfreshState.waterPart.Position = Vector3.new(root.Position.X, KhfreshState.waterY, root.Position.Z)
            end
        end)
    end

    local function disableWaterWalk()
        if not KhfreshState.waterWalkEnabled then return end
        KhfreshState.waterWalkEnabled = false
        if KhfreshState.waterWalkConnection then
            KhfreshState.waterWalkConnection:Disconnect()
            KhfreshState.waterWalkConnection = nil
        end
        if KhfreshState.waterPart then
            KhfreshState.waterPart:Destroy()
            KhfreshState.waterPart = nil
        end
        for _, part in ipairs(KhfreshState.waterPartsList) do
            if part and part.Parent then
                part.CanCollide = false
            end
        end
        KhfreshState.waterPartsList = {}
    end

    CharSection:CreateToggle({
        Name = "Walk On Water",
        Default = false,
        Callback = function(V)
            MiscFlags.WalkOnWater = V
            if V then enableWaterWalk() else disableWaterWalk() end
        end
    })

    -- World & Misc
    do
        local WorldSection = SettingsTab:CreateSection("World & Misc")
        local origA, origB, origT, origBr, origOA = Lighting.Ambient, Lighting.ColorShift_Bottom, Lighting
        .ColorShift_Top, Lighting.Brightness, Lighting.OutdoorAmbient
        local function applyFullBright(on)
            MiscFlags.FullBright = on == true
            if on then
                pcall(function()
                    Lighting.Ambient = Color3.new(1, 1, 1)
                    Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
                    Lighting.ColorShift_Bottom = Color3.new(1, 1, 1)
                    Lighting.ColorShift_Top = Color3.new(1, 1, 1)
                    Lighting.Brightness = 3
                    Lighting.FogEnd = 9e9
                    Lighting.FogStart = 0
                    Lighting.GlobalShadows = false
                    Lighting.ClockTime = 12
                    KhfreshState.fullBrightApplied = true
                end)
            else
                pcall(function()
                    Lighting.Ambient = origA
                    Lighting.ColorShift_Bottom = origB
                    Lighting.ColorShift_Top = origT
                    Lighting.Brightness = origBr
                    Lighting.OutdoorAmbient = origOA
                    Lighting.GlobalShadows = true
                    KhfreshState.fullBrightApplied = false
                end)
            end
        end
        WorldSection:CreateToggle({
            Name = "Full Bright",
            Default = false,
            Callback = function(V)
                applyFullBright(V == true)
            end
        })
        -- Keep Full Bright forced while enabled (game may reset Lighting)
        task.spawn(function()
            while alive() do
                if MiscFlags.FullBright then
                    pcall(function()
                        Lighting.Ambient = Color3.new(1, 1, 1)
                        Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
                        Lighting.Brightness = 3
                        Lighting.FogEnd = 9e9
                        Lighting.GlobalShadows = false
                    end)
                end
                task.wait(0.5)
            end
        end)

        local function ExecuteRedeemAllCodes()
            task.spawn(function()
                local dataFolder = ReplicatedStorage:FindFirstChild("Data")
                if not dataFolder then
                    KhfreshLib:Notify({Title="Codes", Message="Data folder not found.", Duration=3})
                    return
                end

                local codeFolder = dataFolder:FindFirstChild("Code", true)
                local redeemEvent = Events and Events:FindFirstChild("RedeemCode")
                if not codeFolder then
                    KhfreshLib:Notify({Title="Codes", Message="Code folder not found.", Duration=3})
                    return
                end
                if not redeemEvent or not redeemEvent:IsA("RemoteEvent") then
                    KhfreshLib:Notify({Title="Codes", Message="RedeemCode event not found.", Duration=3})
                    return
                end

                local codesFound = 0
                for _, item in ipairs(codeFolder:GetChildren()) do
                    local codeName = item.Name
                    if codeName and codeName ~= "" then
                        codesFound = codesFound + 1
                        pcall(function() redeemEvent:FireServer(codeName) end)
                        task.wait(0.25)
                    end
                end

                if codesFound == 0 then
                    KhfreshLib:Notify({Title="Codes", Message="No codes found.", Duration=3})
                else
                    KhfreshLib:Notify({Title="Codes", Message="Redeemed "..tostring(codesFound).." code(s).", Duration=3})
                end
            end)
        end

        WorldSection:CreateButton({
            Name = "Redeem All Codes",
            Callback = ExecuteRedeemAllCodes
        })

        WorldSection:CreateButton({
            Name = "Performance Mod",
            Callback = function()
                pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
                local t = Workspace:FindFirstChildOfClass("Terrain")
                if t then
                    t.WaterWaveSize = 0
                    t.WaterWaveSpeed = 0
                    t.WaterReflectance = 0
                    t.WaterTransparency = 1
                end
                Lighting.GlobalShadows = false
                Lighting.FogEnd = 9e9
                Lighting.ShadowSoftness = 0
                Lighting.EnvironmentDiffuseScale = 0
                Lighting.EnvironmentSpecularScale = 0
                for _, v in pairs(Lighting:GetChildren()) do
                    if v:IsA("BlurEffect") or v:IsA("SunRaysEffect") or v:IsA("ColorCorrectionEffect") or v:IsA("BloomEffect") or v:IsA("DepthOfFieldEffect") then
                        v:Destroy()
                    end
                end
                for _, v in pairs(Workspace:GetDescendants()) do
                    if v:IsA("BasePart") then
                        v.Material = Enum.Material.SmoothPlastic
                        v.Reflectance = 0
                        v.CastShadow = false
                    elseif v:IsA("Decal") or v:IsA("Texture") or v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Fire") or v:IsA("Smoke") or v:IsA("Sparkles") then
                        v:Destroy()
                    end
                end
                KhfreshLib:Notify({ Title = "Performance", Message = "Optimized Game!", Duration = 3 })
            end
        })
        WorldSection:CreateToggle({
            Name = "Enable Notifications",
            Default = true,
            Callback = function(value)
                KhfreshState.notificationsEnabled = value
            end
        })
    end

    -- ===== STREAMER MODE (FAKE NAME) & LANGUAGE & KHFRESH SHIELD =====
    do
        local StreamerSection = SettingsTab:CreateSection("Streamer Mode (Fake Name)")
        StreamerSection:CreateToggle({
            Name = "Fake Name Display",
            Default = false,
            Callback = function(value)
                if value then
                    KhfreshState.enableFakeName()
                else
                    KhfreshState.disableFakeName()
                end
            end
        })

        StreamerSection:CreateTextbox({
            Name = "Fake Username",
            Placeholder = "KhfreshPlayer",
            Default = KhfreshState.fakeName or "KhfreshPlayer",
            Callback = function(value)
                if value and #value > 0 then
                    KhfreshState.fakeName = value
                end
            end
        })

        StreamerSection:CreateTextbox({
            Name = "Fake Display Name",
            Placeholder = "KhfreshPlayer",
            Default = KhfreshState.fakeDisplayName or "KhfreshPlayer",
            Callback = function(value)
                if value and #value > 0 then
                    KhfreshState.fakeDisplayName = value
                end
            end
        })

        -- Doi ten ma khong che ID thi van bi report -> them o nhap UserId gia.
        -- PlaceId va JobId duoc che tu dong (khong can nhap).
        StreamerSection:CreateTextbox({
            Name = "Fake User ID",
            Placeholder = "0",
            Default = KhfreshState.fakeUserId or "0",
            Callback = function(value)
                if value and #tostring(value) > 0 then
                    KhfreshState.fakeUserId = tostring(value)
                end
            end
        })

        local VisualDupeSection = SettingsTab:CreateSection("Visual Dupe")
        local VisualDupeTarget, VisualDupeName = nil, "None"
        local function scanVisualInventory()
            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            local options, seen = {}, {}
            if not pg then return options end
            for _, v in ipairs(pg:GetDescendants()) do
                if (v:IsA("TextLabel") or v:IsA("TextButton")) and v.Visible then
                    local text = tostring(v.Text or "")
                    if text:match("%d+%.?%d*%s*[Kk][Gg]") and not seen[text] then seen[text]=true; table.insert(options,text) end
                end
            end
            table.sort(options); return options
        end
        local vd=VisualDupeSection:CreateDropdown({Name="Visual target (KG)",Options={"None"},Default="None",Callback=function(value)
            VisualDupeName=tostring(value or "None"); VisualDupeTarget=nil
            local pg=LocalPlayer:FindFirstChildOfClass("PlayerGui"); if not pg then return end
            for _,v in ipairs(pg:GetDescendants()) do
                if (v:IsA("TextLabel") or v:IsA("TextButton")) and v.Visible and tostring(v.Text or "")==VisualDupeName then VisualDupeTarget=v:FindFirstAncestorOfClass("Frame") or v.Parent; break end
            end
        end})
        VisualDupeSection:CreateButton({Name="Scan Visual Inventory",Callback=function()
            local opts = scanVisualInventory()
            if #opts == 0 then
                KhfreshLib:Notify({Title="Visual Dupe", Message="No KG labels found in inventory UI. Open your bag first.", Duration=3})
                return
            end
            local ok = pcall(function()
                if vd.Refresh then vd:Refresh(opts, true)
                elseif vd.SetValues then vd:SetValues(opts)
                end
            end)
            KhfreshLib:Notify({Title="Visual Dupe", Message=ok and ("Found "..#opts.." items") or "Dropdown refresh failed", Duration=3})
        end})
        VisualDupeSection:CreateButton({Name="Create 10 Visual Copies",Callback=function()
            if not VisualDupeTarget or not VisualDupeTarget.Parent then return end
            for _=1,10 do local clone=VisualDupeTarget:Clone(); clone:SetAttribute("KhfreshVisualOnly",true); clone.Parent=VisualDupeTarget.Parent; if clone:IsA("GuiObject") then clone.Visible=true end end
        end})
        VisualDupeSection:CreateButton({Name="Clear Visual Copies",Callback=function()
            local pg=LocalPlayer:FindFirstChildOfClass("PlayerGui"); if not pg then return end
            for _,v in ipairs(pg:GetDescendants()) do if v:GetAttribute("KhfreshVisualOnly")==true then pcall(function() v:Destroy() end) end end
        end})

        local LangSection = SettingsTab:CreateSection("Language & Localization")
        local langOptions = { "Auto (Locale)", "Tieng Viet", "English", "Español", "Português", "ภาษาไทย", "Bahasa Indonesia" }
        local langMap = {
            ["Auto (Locale)"] = "auto",
            ["Tieng Viet"] = "vi",
            ["English"] = "en",
            ["Español"] = "es",
            ["Português"] = "pt",
            ["ภาษาไทย"] = "th",
            ["Bahasa Indonesia"] = "id"
        }
        LangSection:CreateDropdown({
            Name = "UI Language",
            Options = langOptions,
            Default = (function()
                local saved = KhfreshUserConfig.Language
                local reverse = {auto="Auto (Locale)", vi="Tiếng Việt", en="English", es="Español", pt="Português", th="ภาษาไทย", id="Bahasa Indonesia"}
                return reverse[saved] or "Auto (Locale)"
            end)(),
            Callback = function(value)
                KhfreshState.currentLanguage = langMap[value] or "auto"
                KhfreshUserConfig.Language = KhfreshState.currentLanguage
                pcall(function() khSnapshotAndSave("callback") end)
                pcall(function()
                    if I18n and I18n.applyLanguage then
                        I18n.applyLanguage()
                    end
                end)
            end
        })


        -- ===== KHFRESH SHIELD SETTINGS =====
        -- Settings controls restored from the source. Gameplay remote interception
        -- remains disabled in this build for performance/stability.
        do
            local ShieldSection = SettingsTab:CreateSection("Khfresh Shield")
            ShieldSection:CreateToggle({
                Name = "Anti-Report Khfresh Users",
                Default = KhfreshState.antiReportEnabled == true,
                Callback = function(value)
                    KhfreshState.antiReportEnabled = value == true
                    KhfreshUserConfig.meta = KhfreshUserConfig.meta or {}
                    KhfreshUserConfig.meta.antiReportEnabled = KhfreshState.antiReportEnabled
                    pcall(function() khSnapshotAndSave("anti-report setting") end)
                    KhfreshLib:Notify({Title="Khfresh Shield", Message=value and "Anti-Report setting enabled." or "Anti-Report setting disabled.", Duration=2})
                end
            })
            ShieldSection:CreateToggle({
                Name = "Anti-Kick Shield",
                Default = KhfreshState.antiKickEnabled == true,
                Callback = function(value)
                    KhfreshState.antiKickEnabled = value == true
                    KhfreshUserConfig.meta = KhfreshUserConfig.meta or {}
                    KhfreshUserConfig.meta.antiKickEnabled = KhfreshState.antiKickEnabled
                    pcall(function() khSnapshotAndSave("anti-kick setting") end)
                    KhfreshLib:Notify({Title="Khfresh Shield", Message=value and "Anti-Kick setting enabled." or "Anti-Kick setting disabled.", Duration=2})
                end
            })
            ShieldSection:CreateToggle({
                Name = "Anti-Detection Metamethod",
                Default = KhfreshState.antiDetectionEnabled == true,
                Callback = function(value)
                    KhfreshState.antiDetectionEnabled = value == true
                    KhfreshUserConfig.meta = KhfreshUserConfig.meta or {}
                    KhfreshUserConfig.meta.antiDetectionEnabled = KhfreshState.antiDetectionEnabled
                    pcall(function() khSnapshotAndSave("anti-detection setting") end)
                    KhfreshLib:Notify({Title="Khfresh Shield", Message=value and "Anti-Detection setting enabled." or "Anti-Detection setting disabled.", Duration=2})
                end
            })
            ShieldSection:CreateToggle({
                Name = "Anti AFK",
                Default = true,
                Callback = function(value)
                    Fishing.Flags.AntiAFK = value ~= false
                    if AutoFarmFilters then AutoFarmFilters.AntiAFK = Fishing.Flags.AntiAFK end
                    if Fishing.Flags.AntiAFK then
                        if initAntiAFK then pcall(initAntiAFK) end
                    elseif stopAntiAFK then
                        pcall(stopAntiAFK)
                    end
                    KhfreshLib:Notify({
                        Title = "Khfresh Shield",
                        Message = Fishing.Flags.AntiAFK and "Anti-AFK enabled." or "Anti-AFK disabled.",
                        Duration = 2
                    })
                end
            })
            ShieldSection:CreateToggle({
                Name = "Anti-Ban (BanPlayer Remote)",
                Default = true,
                Callback = function(value)
                    -- Always keep protection available; user can still toggle visually
                    KhfreshState.antiBanEnabled = value ~= false
                    KhfreshUserConfig.AntiBan = KhfreshState.antiBanEnabled
                    if KhfreshState.antiBanEnabled then
                        if initAntiBan then
                            initAntiBan()
                        end
                    elseif stopAntiBan then
                        stopAntiBan()
                    end
                    pcall(function() khSnapshotAndSave("anti-ban setting") end)
                    KhfreshLib:Notify({
                        Title = "Khfresh Shield",
                        Message = value and "BanPlayer remote protection enabled." or "Anti-Ban disabled.",
                        Duration = 2
                    })
                end
            })
        end

        local ConfigSection = SettingsTab:CreateSection("Config & Auto Execute")
        ConfigSection:CreateLabel("Config save is disabled.")
        ConfigSection:CreateToggle({
            Name = "Auto Execute After Server Hop", Default = KhfreshState.autoExecuteOnHop == true,
            Callback = function(value)
                KhfreshState.autoExecuteOnHop = value == true
                KhfreshUserConfig.autoExecute = KhfreshState.autoExecuteOnHop
                KhfreshUserConfig.meta = KhfreshUserConfig.meta or {}
                KhfreshUserConfig.meta.autoExecute = KhfreshState.autoExecuteOnHop
                khSaveConfigNow()
                KhfreshLib:Notify({Title="Auto Execute", Message=KhfreshState.autoExecuteOnHop and "Will re-run Khfresh Hub after server hop." or "Disabled.", Duration=2})
            end
        })
        ConfigSection:CreateButton({Name="Test Auto Execute Queue",Callback=function()
            local ok,reason=khQueueAutoExecute()
            KhfreshLib:Notify({Title="Auto Execute",Message=ok and "Queue on teleport is ready." or tostring(reason),Duration=4})
        end})
        ConfigSection:CreateLabel("Auto Execute uses the built-in Khfresh Hub loader URL. No URL input is required.")

        local UiSection = SettingsTab:CreateSection("Giao Diện & Giấu UI")
        UiSection:CreateButton({ Name = "Show / Hide UI", Icon = "panels-top-left", Callback = function() toggleKhfreshUI() end })
        UiSection:CreateToggle({
            Name = "Stealth UI", Icon = "eye-off",
            Default = false,
            Callback = function(value)
                if value then
                    toggleKhfreshUI(false)
                    if UiController.FloatingBtn then UiController.FloatingBtn.Enabled = false end
                    KhfreshLib:Notify({
                        Title = "Stealth Mode",
                        Message = "Đã giấu UI! Nhấn RightAlt/RightControl/Insert để mở lại.",
                        Duration = 5
                    })
                else
                    toggleKhfreshUI(true)
                    if UiController.FloatingBtn then UiController.FloatingBtn.Enabled = true end
                end
            end
        })
        UiSection:CreateToggle({
            Name = "Floating Toggle", Icon = "panel-left",
            Default = true,
            Callback = function(value)
                if UiController.FloatingBtn then
                    UiController.FloatingBtn.Enabled = value
                end
            end
        })
    end

    -- Security (Staff Watch)
    do
        local SecuritySection = SettingsTab:CreateSection("Staff Watch")
        local STAFF_GROUP_ID = 32032540
        local MIN_STAFF_RANK = 246
        local STAFF_RANK_NAMES = {
            ["Content Creator"] = 246,
            ["Contributor"] = 247,
            ["QA Tester"] = 248,
            ["Moderator"] = 249,
            ["Contractor"] = 250,
            ["Community Manager"] = 251,
            ["Lady"] = 254,
            ["Owner"] = 255,
        }
        local staffWatchState = {
            enabled = false,
            connections = {},
            checkInterval = nil,
        }

        local HttpService = Services.HttpService

        local function getUserRank(userId)
            local url = "https://groups.roblox.com/v1/groups/" .. STAFF_GROUP_ID .. "/users/" .. userId
            local success, result = pcall(function() return HttpService:GetAsync(url) end)
            if not success then return 0 end
            local ok, data = pcall(function() return HttpService:JSONDecode(result) end)
            if not ok or not data then return 0 end
            if data.isInGroup == false then return 0 end
            return data.role and data.role.rank or 0
        end

        local function isStaff(player)
            if player.UserId == LocalPlayer.UserId then return false end
            local rank = getUserRank(player.UserId)
            return rank >= MIN_STAFF_RANK
        end

        local function onStaffDetected(player)
            local roleName = "Staff"
            for name, rank in pairs(STAFF_RANK_NAMES) do
                if getUserRank(player.UserId) == rank then
                    roleName = name
                    break
                end
            end
            KhfreshLib:Notify({
                Title = "⚠️ Staff Detected",
                Message = string.format("%s (%s) joined. Staff Watch notification only.", player.Name, roleName),
                Duration = 5,
            })
        end

        local function startStaffWatch()
            if staffWatchState.enabled then return end
            staffWatchState.enabled = true
            task.spawn(function()
                for _, player in ipairs(Players:GetPlayers()) do
                    if isStaff(player) then
                        onStaffDetected(player)
                        return
                    end
                end
            end)
            local conn = Players.PlayerAdded:Connect(function(player)
                task.wait(1)
                if isStaff(player) then
                    onStaffDetected(player)
                end
            end)
            table.insert(staffWatchState.connections, conn)
            staffWatchState.checkInterval = task.spawn(function()
                while staffWatchState.enabled do
                    task.wait(30)
                    for _, player in ipairs(Players:GetPlayers()) do
                        if isStaff(player) then
                            onStaffDetected(player)
                            return
                        end
                    end
                end
            end)
            KhfreshLib:Notify({ Title = "Staff Watch", Message = "Enabled! Watching for staff...", Duration = 3 })
        end

        local function stopStaffWatch()
            staffWatchState.enabled = false
            for _, conn in ipairs(staffWatchState.connections) do
                pcall(function() conn:Disconnect() end)
            end
            staffWatchState.connections = {}
            if staffWatchState.checkInterval then
                task.cancel(staffWatchState.checkInterval)
                staffWatchState.checkInterval = nil
            end
            KhfreshLib:Notify({ Title = "Staff Watch", Message = "Disabled!", Duration = 2 })
        end

        SecuritySection:CreateToggle({ Name = "Enable Staff Watch", Default = false, Callback = function(value) if value then
                startStaffWatch() else stopStaffWatch() end end })

        SecuritySection:CreateButton({
            Name = "Check Current Players",
            Callback = function()
                KhfreshLib:Notify({ Title = "Staff Watch", Message = "Checking...", Duration = 2 })
                for _, player in ipairs(Players:GetPlayers()) do
                    if isStaff(player) then
                        onStaffDetected(player)
                        return
                    end
                end
                KhfreshLib:Notify({ Title = "Staff Watch", Message = "No staff in this server!", Duration = 3 })
            end
        })
    end
    -- ===== ESP SECTION =====
    do
        local EspSection = SettingsTab:CreateSection("ESP")

        -- ===== ESP PLAYERS =====
        local espEnabled = false
        local espThread = nil
        local espConnections = {}
        local ReplicatedStorage = game:GetService("ReplicatedStorage")

        local function getPlayerStats(player)
            local stats = {
                Level = "N/A",
                Cash = "N/A",
                Rod = "N/A",
                Crystal = "N/A",
                EssenceOrb = "N/A",
                Bait = "N/A",
                FishCaught = "N/A",
                Ticket = "N/A",
                TraitReroll = "N/A"
            }
            local dataFolder = ReplicatedStorage:FindFirstChild("Data")
            if not dataFolder then return stats end
            local playerData = dataFolder:FindFirstChild(tostring(player.UserId))
            if not playerData then return stats end

            local levelFolder = playerData:FindFirstChild("Level")
            if levelFolder then
                local levelVal = levelFolder:FindFirstChild("Level")
                if levelVal then stats.Level = tostring(levelVal.Value) end
            end
            local cashVal = playerData:FindFirstChild("Cash")
            if cashVal then stats.Cash = tostring(cashVal.Value) end
            local rodVal = playerData:FindFirstChild("FishingRod")
            if rodVal then stats.Rod = tostring(rodVal.Value) end
            local crystalVal = playerData:FindFirstChild("Crystal")
            if crystalVal then stats.Crystal = tostring(crystalVal.Value) end
            local essenceVal = playerData:FindFirstChild("EssenceOrb")
            if essenceVal then stats.EssenceOrb = tostring(essenceVal.Value) end
            local baitVal = playerData:FindFirstChild("EquippedBait")
            if baitVal then stats.Bait = tostring(baitVal.Value) end
            local fishCaughtVal = playerData:FindFirstChild("FishCaught")
            if fishCaughtVal then stats.FishCaught = tostring(fishCaughtVal.Value) end
            local ticketVal = playerData:FindFirstChild("Ticket")
            if ticketVal then stats.Ticket = tostring(ticketVal.Value) end
            local traitRerollVal = playerData:FindFirstChild("Trait Reroll")
            if traitRerollVal then stats.TraitReroll = tostring(traitRerollVal.Value) end
            return stats
        end

        local function createEspForPlayer(player)
            if player == LocalPlayer then return end
            local character = player.Character
            if not character then return end
            local head = character:FindFirstChild("Head")
            if not head then return end
            if head:FindFirstChild("EspBillboard") then return end

            local stats = getPlayerStats(player)
            local billboard = Instance.new("BillboardGui")
            billboard.Name = "EspBillboard"
            billboard.Size = UDim2.new(0, 300, 0, 110)
            billboard.StudsOffset = Vector3.new(0, 3, 0)
            billboard.AlwaysOnTop = true
            billboard.Parent = head

            local frame = Instance.new("Frame")
            frame.Size = UDim2.new(1, 0, 1, 0)
            frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            frame.BackgroundTransparency = 0.6
            frame.BorderSizePixel = 0
            frame.Parent = billboard

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 4)
            corner.Parent = frame

            local nameLabel = Instance.new("TextLabel")
            nameLabel.Size = UDim2.new(1, 0, 0, 18)
            nameLabel.Position = UDim2.new(0, 0, 0, 0)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.TextSize = 16
            nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            nameLabel.Text = player.Name
            nameLabel.TextXAlignment = Enum.TextXAlignment.Center
            nameLabel.Parent = frame

            local lines = {
                string.format("Lv:%s | Cash:%s", stats.Level, stats.Cash),
                string.format("Rod:%s", stats.Rod),
                string.format("Bait:%s", stats.Bait),
                string.format("Cry:%s | Ess:%s | Tick:%s | Reroll:%s", stats.Crystal, stats.EssenceOrb, stats.Ticket,
                    stats.TraitReroll),
                string.format("Fish:%s", stats.FishCaught)
            }

            local yOffset = 18
            for _, line in ipairs(lines) do
                local label = Instance.new("TextLabel")
                label.Size = UDim2.new(1, 0, 0, 16)
                label.Position = UDim2.new(0, 0, 0, yOffset)
                label.BackgroundTransparency = 1
                label.Font = Enum.Font.Gotham
                label.TextSize = 12
                label.TextColor3 = Color3.fromRGB(200, 200, 200)
                label.Text = line
                label.TextXAlignment = Enum.TextXAlignment.Center
                label.Parent = frame
                yOffset = yOffset + 16
            end

            table.insert(espConnections, { player = player, billboard = billboard })
        end

        local function removeEspForPlayer(player)
            local character = player.Character
            if not character then return end
            local head = character:FindFirstChild("Head")
            if not head then return end
            local billboard = head:FindFirstChild("EspBillboard")
            if billboard then billboard:Destroy() end
            for i, conn in ipairs(espConnections) do
                if conn.player == player then
                    table.remove(espConnections, i)
                    break
                end
            end
        end

        local function clearAllEsp()
            for _, conn in ipairs(espConnections) do
                pcall(function()
                    if conn.billboard and conn.billboard.Parent then
                        conn.billboard:Destroy()
                    end
                end)
            end
            espConnections = {}
        end

        local function updateAllEsp()
            if not espEnabled then return end
            clearAllEsp()
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    pcall(function() createEspForPlayer(player) end)
                end
            end
        end

        local function startEsp()
            if espEnabled then return end
            espEnabled = true
            updateAllEsp()

            local playerAddedConn = Players.PlayerAdded:Connect(function(player)
                if espEnabled then
                    task.wait(0.5)
                    pcall(function() createEspForPlayer(player) end)
                end
            end)
            table.insert(espConnections, { conn = playerAddedConn })

            local playerRemovingConn = Players.PlayerRemoving:Connect(function(player)
                pcall(function() removeEspForPlayer(player) end)
            end)
            table.insert(espConnections, { conn = playerRemovingConn })

            local characterAddedConn = Players.PlayerAdded:Connect(function(player)
                if espEnabled then
                    player.CharacterAdded:Connect(function()
                        task.wait(0.5)
                        pcall(function() createEspForPlayer(player) end)
                    end)
                end
            end)
            table.insert(espConnections, { conn = characterAddedConn })

            espThread = task.spawn(function()
                while espEnabled do
                    task.wait(10)
                    if espEnabled then
                        pcall(updateAllEsp)
                    end
                end
            end)

            KhfreshLib:Notify({ Title = "ESP", Message = "Players ESP enabled!", Duration = 2 })
        end

        local function stopEsp()
            espEnabled = false
            if espThread then
                task.cancel(espThread)
                espThread = nil
            end
            clearAllEsp()
            for _, conn in ipairs(espConnections) do
                if conn.conn then
                    pcall(function() conn.conn:Disconnect() end)
                end
            end
            espConnections = {}
            KhfreshLib:Notify({ Title = "ESP", Message = "Players ESP disabled!", Duration = 2 })
        end

        EspSection:CreateToggle({
            Name = "Players",
            Default = false,
            Callback = function(value)
                if value then
                    startEsp()
                else
                    stopEsp()
                end
            end
        })

        -- ===== BOAT ESP =====
        do
            local boatEspEnabled = false
            local boatEspThread = nil
            local boatEspHighlights = {}
            local boatFolder = workspace:FindFirstChild("Boat")

            local function createBoatEsp(boatModel)
                if not boatModel or not boatModel:IsA("Model") then return end
                if boatEspHighlights[boatModel] then return end

                -- Only handle it when the parent is a Folder
                if not boatModel.Parent or not boatModel.Parent:IsA("Folder") then return end

                local attachPart = boatModel:FindFirstChildWhichIsA("BasePart")
                if not attachPart then
                    attachPart = boatModel:FindFirstChildWhichIsA("BasePart", true)
                end
                if not attachPart then return end

                local parentName = "Boat"
                local parent = boatModel.Parent
                if parent and parent ~= boatFolder then
                    parentName = parent.Name
                end

                local highlight = Instance.new("Highlight")
                highlight.FillColor = Color3.fromRGB(0, 150, 255)
                highlight.FillTransparency = 0.5
                highlight.OutlineColor = Color3.fromRGB(0, 255, 255)
                highlight.OutlineTransparency = 0.3
                highlight.Adornee = boatModel
                highlight.Parent = boatModel

                local billboard = Instance.new("BillboardGui")
                billboard.Name = "BoatEspBillboard"
                billboard.Size = UDim2.new(0, 150, 0, 30)
                billboard.StudsOffset = Vector3.new(0, 2, 0)
                billboard.AlwaysOnTop = true
                billboard.Parent = attachPart

                local frame = Instance.new("Frame")
                frame.Size = UDim2.new(1, 0, 1, 0)
                frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                frame.BackgroundTransparency = 0.5
                frame.BorderSizePixel = 0
                frame.Parent = billboard

                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 4)
                corner.Parent = frame

                local label = Instance.new("TextLabel")
                label.Size = UDim2.new(1, 0, 1, 0)
                label.BackgroundTransparency = 1
                label.Font = Enum.Font.GothamBold
                label.TextSize = 14
                label.TextColor3 = Color3.fromRGB(0, 0, 255)
                label.Text = "Boat | " .. parentName
                label.TextScaled = false
                label.TextXAlignment = Enum.TextXAlignment.Center
                label.TextYAlignment = Enum.TextYAlignment.Center
                label.Parent = frame

                boatEspHighlights[boatModel] = {
                    highlight = highlight,
                    billboard = billboard,
                    attachPart = attachPart,
                }
            end

            local function removeBoatEsp(boatModel)
                local data = boatEspHighlights[boatModel]
                if data then
                    if data.highlight then data.highlight:Destroy() end
                    if data.billboard then data.billboard:Destroy() end
                    boatEspHighlights[boatModel] = nil
                end
            end

            local function clearAllBoatEsp()
                for model, data in pairs(boatEspHighlights) do
                    pcall(function()
                        if data.highlight then data.highlight:Destroy() end
                        if data.billboard then data.billboard:Destroy() end
                    end)
                end
                boatEspHighlights = {}
            end

            local function scanAllBoats()
                if not boatFolder then return end
                for _, child in ipairs(boatFolder:GetDescendants()) do
                    if child:IsA("Model") and child.Parent and child.Parent:IsA("Folder") then
                        if not boatEspHighlights[child] then
                            pcall(function() createBoatEsp(child) end)
                        end
                    end
                end
            end

            local function startBoatEsp()
                if boatEspEnabled then return end
                boatEspEnabled = true
                scanAllBoats()

                if boatFolder then
                    local boatAddedConn = boatFolder.DescendantAdded:Connect(function(desc)
                        if boatEspEnabled and desc:IsA("Model") and desc.Parent and desc.Parent:IsA("Folder") then
                            task.wait(0.1)
                            pcall(function()
                                if not boatEspHighlights[desc] then
                                    createBoatEsp(desc)
                                end
                            end)
                        end
                    end)
                    table.insert(espConnections, { conn = boatAddedConn })
                end

                boatEspThread = task.spawn(function()
                    while boatEspEnabled do
                        task.wait(10)
                        if boatEspEnabled then
                            pcall(function()
                                for model, data in pairs(boatEspHighlights) do
                                    if not model.Parent then
                                        removeBoatEsp(model)
                                    end
                                end
                                scanAllBoats()
                            end)
                        end
                    end
                end)

                KhfreshLib:Notify({ Title = "Boat ESP", Message = "Boat ESP enabled!", Duration = 2 })
            end

            local function stopBoatEsp()
                boatEspEnabled = false
                if boatEspThread then
                    task.cancel(boatEspThread)
                    boatEspThread = nil
                end
                clearAllBoatEsp()
                KhfreshLib:Notify({ Title = "Boat ESP", Message = "Boat ESP disabled!", Duration = 2 })
            end

            EspSection:CreateToggle({
                Name = "Boat ESP",
                Default = false,
                Callback = function(value)
                    if value then
                        startBoatEsp()
                    else
                        stopBoatEsp()
                    end
                end
            })
        end

        -- ===== SECRET ROD ESP =====
        do
            local secretRodEspEnabled = false
            local secretRodEspThread = nil
            local secretRodEspHighlights = {}
            local secretRodFolder = workspace:FindFirstChild("SecretRod")

            local function createSecretRodEsp(rodModel)
                if not rodModel or not rodModel:IsA("Model") then return end
                if secretRodEspHighlights[rodModel] then return end

                if not rodModel.Parent or not rodModel.Parent:IsA("Folder") then return end

                local attachPart = rodModel:FindFirstChildWhichIsA("BasePart")
                if not attachPart then
                    attachPart = rodModel:FindFirstChildWhichIsA("BasePart", true)
                end
                if not attachPart then return end

                local highlight = Instance.new("Highlight")
                highlight.FillColor = Color3.fromRGB(255, 215, 0)
                highlight.FillTransparency = 0.5
                highlight.OutlineColor = Color3.fromRGB(255, 255, 0)
                highlight.OutlineTransparency = 0.3
                highlight.Adornee = rodModel
                highlight.Parent = rodModel

                local billboard = Instance.new("BillboardGui")
                billboard.Name = "SecretRodEspBillboard"
                billboard.Size = UDim2.new(0, 150, 0, 30)
                billboard.StudsOffset = Vector3.new(0, 2, 0)
                billboard.AlwaysOnTop = true
                billboard.Parent = attachPart

                local frame = Instance.new("Frame")
                frame.Size = UDim2.new(1, 0, 1, 0)
                frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                frame.BackgroundTransparency = 0.5
                frame.BorderSizePixel = 0
                frame.Parent = billboard

                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 4)
                corner.Parent = frame

                local label = Instance.new("TextLabel")
                label.Size = UDim2.new(1, 0, 1, 0)
                label.BackgroundTransparency = 1
                label.Font = Enum.Font.GothamBold
                label.TextSize = 14
                label.TextColor3 = Color3.fromRGB(255, 215, 0)
                label.Text = rodModel.Name
                label.TextScaled = false
                label.TextXAlignment = Enum.TextXAlignment.Center
                label.TextYAlignment = Enum.TextYAlignment.Center
                label.Parent = frame

                secretRodEspHighlights[rodModel] = {
                    highlight = highlight,
                    billboard = billboard,
                    attachPart = attachPart,
                }
            end

            local function removeSecretRodEsp(rodModel)
                local data = secretRodEspHighlights[rodModel]
                if data then
                    if data.highlight then data.highlight:Destroy() end
                    if data.billboard then data.billboard:Destroy() end
                    secretRodEspHighlights[rodModel] = nil
                end
            end

            local function clearAllSecretRodEsp()
                for model, data in pairs(secretRodEspHighlights) do
                    pcall(function()
                        if data.highlight then data.highlight:Destroy() end
                        if data.billboard then data.billboard:Destroy() end
                    end)
                end
                secretRodEspHighlights = {}
            end

            local function scanAllSecretRods()
                if not secretRodFolder then return end
                for _, child in ipairs(secretRodFolder:GetDescendants()) do
                    if child:IsA("Model") and child.Parent and child.Parent:IsA("Folder") then
                        if not secretRodEspHighlights[child] then
                            pcall(function() createSecretRodEsp(child) end)
                        end
                    end
                end
            end

            local function startSecretRodEsp()
                if secretRodEspEnabled then return end
                secretRodEspEnabled = true
                scanAllSecretRods()

                if secretRodFolder then
                    local rodAddedConn = secretRodFolder.DescendantAdded:Connect(function(desc)
                        if secretRodEspEnabled and desc:IsA("Model") and desc.Parent and desc.Parent:IsA("Folder") then
                            task.wait(0.1)
                            pcall(function()
                                if not secretRodEspHighlights[desc] then
                                    createSecretRodEsp(desc)
                                end
                            end)
                        end
                    end)
                    table.insert(espConnections, { conn = rodAddedConn })
                end

                secretRodEspThread = task.spawn(function()
                    while secretRodEspEnabled do
                        task.wait(10)
                        if secretRodEspEnabled then
                            pcall(function()
                                for model, data in pairs(secretRodEspHighlights) do
                                    if not model.Parent then
                                        removeSecretRodEsp(model)
                                    end
                                end
                                scanAllSecretRods()
                            end)
                        end
                    end
                end)

                KhfreshLib:Notify({ Title = "Secret Rod ESP", Message = "Secret Rod ESP enabled!", Duration = 2 })
            end

            local function stopSecretRodEsp()
                secretRodEspEnabled = false
                if secretRodEspThread then
                    task.cancel(secretRodEspThread)
                    secretRodEspThread = nil
                end
                clearAllSecretRodEsp()
                KhfreshLib:Notify({ Title = "Secret Rod ESP", Message = "Secret Rod ESP disabled!", Duration = 2 })
            end

            EspSection:CreateToggle({
                Name = "Secret Rod ESP",
                Default = false,
                Callback = function(value)
                    if value then
                        startSecretRodEsp()
                    else
                        stopSecretRodEsp()
                    end
                end
            })
        end

        -- ===== GOD ESP =====
        do
            local godEspEnabled = false
            local godEspThread = nil
            local godEspHighlights = {}
            local godFolder = workspace:FindFirstChild("NPC") and workspace.NPC:FindFirstChild("God")

            local function createGodEsp(godModel)
                if not godModel or not godModel:IsA("Model") then return end
                if godEspHighlights[godModel] then return end

                if not godModel.Parent or not godModel.Parent:IsA("Folder") then return end

                local attachPart = godModel:FindFirstChildWhichIsA("BasePart")
                if not attachPart then
                    attachPart = godModel:FindFirstChildWhichIsA("BasePart", true)
                end
                if not attachPart then return end

                local highlight = Instance.new("Highlight")
                highlight.FillColor = Color3.fromRGB(255, 215, 0)
                highlight.FillTransparency = 0.4
                highlight.OutlineColor = Color3.fromRGB(255, 255, 100)
                highlight.OutlineTransparency = 0.2
                highlight.Adornee = godModel
                highlight.Parent = godModel

                local billboard = Instance.new("BillboardGui")
                billboard.Name = "GodEspBillboard"
                billboard.Size = UDim2.new(0, 200, 0, 30)
                billboard.StudsOffset = Vector3.new(0, 2.5, 0)
                billboard.AlwaysOnTop = true
                billboard.Parent = attachPart

                local frame = Instance.new("Frame")
                frame.Size = UDim2.new(1, 0, 1, 0)
                frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                frame.BackgroundTransparency = 0.5
                frame.BorderSizePixel = 0
                frame.Parent = billboard

                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 4)
                corner.Parent = frame

                local label = Instance.new("TextLabel")
                label.Size = UDim2.new(1, 0, 1, 0)
                label.BackgroundTransparency = 1
                label.Font = Enum.Font.GothamBold
                label.TextSize = 14
                label.TextColor3 = Color3.fromRGB(255, 215, 0)
                label.Text = "☀️ " .. godModel.Name
                label.TextScaled = false
                label.TextXAlignment = Enum.TextXAlignment.Center
                label.TextYAlignment = Enum.TextYAlignment.Center
                label.Parent = frame

                godEspHighlights[godModel] = {
                    highlight = highlight,
                    billboard = billboard,
                    attachPart = attachPart,
                }
            end

            local function removeGodEsp(godModel)
                local data = godEspHighlights[godModel]
                if data then
                    if data.highlight then data.highlight:Destroy() end
                    if data.billboard then data.billboard:Destroy() end
                    godEspHighlights[godModel] = nil
                end
            end

            local function clearAllGodEsp()
                for model, data in pairs(godEspHighlights) do
                    pcall(function()
                        if data.highlight then data.highlight:Destroy() end
                        if data.billboard then data.billboard:Destroy() end
                    end)
                end
                godEspHighlights = {}
            end

            local function scanAllGods()
                if not godFolder then return end
                for _, child in ipairs(godFolder:GetDescendants()) do
                    if child:IsA("Model") and child.Parent and child.Parent:IsA("Folder") then
                        if not godEspHighlights[child] then
                            pcall(function() createGodEsp(child) end)
                        end
                    end
                end
            end

            local function startGodEsp()
                if godEspEnabled then return end
                godEspEnabled = true
                scanAllGods()

                if godFolder then
                    local godAddedConn = godFolder.DescendantAdded:Connect(function(desc)
                        if godEspEnabled and desc:IsA("Model") and desc.Parent and desc.Parent:IsA("Folder") then
                            task.wait(0.1)
                            pcall(function()
                                if not godEspHighlights[desc] then
                                    createGodEsp(desc)
                                end
                            end)
                        end
                    end)
                    table.insert(espConnections, { conn = godAddedConn })
                end

                godEspThread = task.spawn(function()
                    while godEspEnabled do
                        task.wait(10)
                        if godEspEnabled then
                            pcall(function()
                                for model, data in pairs(godEspHighlights) do
                                    if not model.Parent then
                                        removeGodEsp(model)
                                    end
                                end
                                scanAllGods()
                            end)
                        end
                    end
                end)

                KhfreshLib:Notify({ Title = "God ESP", Message = "God ESP enabled!", Duration = 2 })
            end

            local function stopGodEsp()
                godEspEnabled = false
                if godEspThread then
                    task.cancel(godEspThread)
                    godEspThread = nil
                end
                clearAllGodEsp()
                KhfreshLib:Notify({ Title = "God ESP", Message = "God ESP disabled!", Duration = 2 })
            end

            EspSection:CreateToggle({
                Name = "God ESP",
                Default = false,
                Callback = function(value)
                    if value then
                        startGodEsp()
                    else
                        stopGodEsp()
                    end
                end
            })
        end

        -- ===== NPCs ESP =====
        do
            local npcEspEnabled = false
            local npcEspThread = nil
            local npcEspHighlights = {}
            local npcFolder = workspace:FindFirstChild("NPC") and workspace.NPC:FindFirstChild("Function")

            local function createNpcEsp(npcModel)
                if not npcModel or not npcModel:IsA("Model") then return end
                if npcEspHighlights[npcModel] then return end

                if not npcModel.Parent or not npcModel.Parent:IsA("Folder") then return end

                local attachPart = npcModel:FindFirstChildWhichIsA("BasePart")
                if not attachPart then
                    attachPart = npcModel:FindFirstChildWhichIsA("BasePart", true)
                end
                if not attachPart then return end

                local highlight = Instance.new("Highlight")
                highlight.FillColor = Color3.fromRGB(255, 100, 0)
                highlight.FillTransparency = 0.4
                highlight.OutlineColor = Color3.fromRGB(255, 200, 50)
                highlight.OutlineTransparency = 0.2
                highlight.Adornee = npcModel
                highlight.Parent = npcModel

                local billboard = Instance.new("BillboardGui")
                billboard.Name = "NpcEspBillboard"
                billboard.Size = UDim2.new(0, 200, 0, 30)
                billboard.StudsOffset = Vector3.new(0, 2.5, 0)
                billboard.AlwaysOnTop = true
                billboard.Parent = attachPart

                local frame = Instance.new("Frame")
                frame.Size = UDim2.new(1, 0, 1, 0)
                frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                frame.BackgroundTransparency = 0.5
                frame.BorderSizePixel = 0
                frame.Parent = billboard

                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 4)
                corner.Parent = frame

                local label = Instance.new("TextLabel")
                label.Size = UDim2.new(1, 0, 1, 0)
                label.BackgroundTransparency = 1
                label.Font = Enum.Font.GothamBold
                label.TextSize = 14
                label.TextColor3 = Color3.fromRGB(255, 150, 50)
                label.Text = "NPC | " .. npcModel.Name
                label.TextScaled = false
                label.TextXAlignment = Enum.TextXAlignment.Center
                label.TextYAlignment = Enum.TextYAlignment.Center
                label.Parent = frame

                npcEspHighlights[npcModel] = {
                    highlight = highlight,
                    billboard = billboard,
                    attachPart = attachPart,
                }
            end

            local function removeNpcEsp(npcModel)
                local data = npcEspHighlights[npcModel]
                if data then
                    if data.highlight then data.highlight:Destroy() end
                    if data.billboard then data.billboard:Destroy() end
                    npcEspHighlights[npcModel] = nil
                end
            end

            local function clearAllNpcEsp()
                for model, data in pairs(npcEspHighlights) do
                    pcall(function()
                        if data.highlight then data.highlight:Destroy() end
                        if data.billboard then data.billboard:Destroy() end
                    end)
                end
                npcEspHighlights = {}
            end

            local function scanAllNpcs()
                if not npcFolder then return end
                for _, child in ipairs(npcFolder:GetDescendants()) do
                    if child:IsA("Model") and child.Parent and child.Parent:IsA("Folder") then
                        if not npcEspHighlights[child] then
                            pcall(function() createNpcEsp(child) end)
                        end
                    end
                end
            end

            local function startNpcEsp()
                if npcEspEnabled then return end
                npcEspEnabled = true
                scanAllNpcs()

                if npcFolder then
                    local npcAddedConn = npcFolder.DescendantAdded:Connect(function(desc)
                        if npcEspEnabled and desc:IsA("Model") and desc.Parent and desc.Parent:IsA("Folder") then
                            task.wait(0.1)
                            pcall(function()
                                if not npcEspHighlights[desc] then
                                    createNpcEsp(desc)
                                end
                            end)
                        end
                    end)
                    table.insert(espConnections, { conn = npcAddedConn })
                end

                npcEspThread = task.spawn(function()
                    while npcEspEnabled do
                        task.wait(10)
                        if npcEspEnabled then
                            pcall(function()
                                for model, data in pairs(npcEspHighlights) do
                                    if not model.Parent then
                                        removeNpcEsp(model)
                                    end
                                end
                                scanAllNpcs()
                            end)
                        end
                    end
                end)

                KhfreshLib:Notify({ Title = "NPCs ESP", Message = "NPCs ESP enabled!", Duration = 2 })
            end

            local function stopNpcEsp()
                npcEspEnabled = false
                if npcEspThread then
                    task.cancel(npcEspThread)
                    npcEspThread = nil
                end
                clearAllNpcEsp()
                KhfreshLib:Notify({ Title = "NPCs ESP", Message = "NPCs ESP disabled!", Duration = 2 })
            end

            EspSection:CreateToggle({
                Name = "NPCs ESP",
                Default = false,
                Callback = function(value)
                    if value then
                        startNpcEsp()
                    else
                        stopNpcEsp()
                    end
                end
            })
        end
    end
end

-- ===== ANTI-AFK (Nexus-style: Idled + AFK remote + ClickButton2 / Button2Down) =====
-- Methods (all pcall'd):
--   1) LocalPlayer.Idled -> nudge (Nexus primary)
--   2) Events.AFK:FireServer() (game remote, no click)
--   3) VirtualUser CaptureController + ClickButton2 + Button2Down/Up (Nexus)
--   4) Micro camera yaw (no input steal) as idle heartbeat
--   5) Slow interval 55-65s — never spam
local _khLastAfkFire = 0
local _khAfkCamNudge = 0

local function khPlayerIsMoving()
    local moving = false
    pcall(function()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local md = hum and hum.MoveDirection
        if md and (math.abs(md.X) + math.abs(md.Z) > 0.05) then
            moving = true
        end
    end)
    return moving
end

local function khFireAfkRemote()
    if not alive() then return end
    if Fishing.Flags.AntiAFK == false then return end
    local now = tick()
    if now - _khLastAfkFire < 25 then return end
    _khLastAfkFire = now
    pcall(function()
        local afkEvent = Events and Events:FindFirstChild("AFK")
        if not afkEvent then return end
        -- Nexus: FireServer() no args. Also try string variant once.
        pcall(function() afkEvent:FireServer() end)
        pcall(function() afkEvent:FireServer("Stay Active") end)
    end)
end

-- VirtualUser: CaptureController + ClickButton2 (Nexus also uses Button2Down/Up)
local function khAntiAfkVirtualUser()
    pcall(function()
        local vu = VirtualUser or game:GetService("VirtualUser")
        if not vu then return end
        pcall(function() vu:CaptureController() end)
        -- Classic AFK path
        pcall(function() vu:ClickButton2(Vector2.new()) end)
        -- Nexus path: Button2Down/Up with camera CFrame
        pcall(function()
            local cam = workspace.CurrentCamera
            local cf = cam and cam.CFrame
            if cf then
                vu:Button2Down(Vector2.new(0, 0), cf)
                task.wait(0.15)
                vu:Button2Up(Vector2.new(0, 0), cf)
            end
        end)
    end)
end

local function khAntiAfkCameraNudge()
    -- Tiny yaw on CurrentCamera — keeps session "active" without mouse click
    pcall(function()
        local cam = workspace.CurrentCamera
        if not cam then return end
        local now = tick()
        if now - _khAfkCamNudge < 20 then return end
        _khAfkCamNudge = now
        local cf = cam.CFrame
        cam.CFrame = cf * CFrame.Angles(0, 0.0008, 0)
        task.defer(function()
            pcall(function()
                if workspace.CurrentCamera == cam then
                    cam.CFrame = cf
                end
            end)
        end)
    end)
end

local function khAntiAfkNudge(reason)
    if not alive() or Fishing.Flags.AntiAFK == false then return end
    -- Nexus: skip if player already moving
    if khPlayerIsMoving() then return end
    pcall(khAntiAfkVirtualUser)
    pcall(khFireAfkRemote)
    pcall(khAntiAfkCameraNudge)
end

initAntiAFK = function()
    if not alive() then return false end
    if not LocalPlayer then
        runtimeEnv.AntiAFKInitialized = false
        return false
    end

    -- Always rebind clean (prevent double Idled / crash on re-exec)
    if runtimeEnv.AntiAFKConnection then
        pcall(function() runtimeEnv.AntiAFKConnection:Disconnect() end)
        runtimeEnv.AntiAFKConnection = nil
    end
    if runtimeEnv.AntiAFKThread then
        pcall(function() task.cancel(runtimeEnv.AntiAFKThread) end)
        runtimeEnv.AntiAFKThread = nil
    end

    Fishing.Flags.AntiAFK = true
    if AutoFarmFilters then AutoFarmFilters.AntiAFK = true end
    runtimeEnv.AntiAFKInitialized = true

    -- Primary: Roblox Idled (same as Nexus)
    local okConn, conn = pcall(function()
        return LocalPlayer.Idled:Connect(function()
            if not alive() or Fishing.Flags.AntiAFK == false then return end
            _khLastAfkFire = 0 -- allow immediate remote on real Idled
            khAntiAfkNudge("Idled")
        end)
    end)
    if okConn and conn then
        runtimeEnv.AntiAFKConnection = conn
    end

    -- Backup heartbeat: every ~60s fire remote only (no click, no lag)
    runtimeEnv.AntiAFKThread = task.spawn(function()
        while alive() do
            local waitSec = 55 + math.random() * 10
            task.wait(waitSec)
            if not alive() then break end
            if Fishing.Flags.AntiAFK == false then
                -- stay alive loop but idle until toggled back
            else
                pcall(khAntiAfkNudge, "interval")
            end
        end
        runtimeEnv.AntiAFKThread = nil
    end)

    task.defer(function()
        if alive() and Fishing.Flags.AntiAFK ~= false then
            _khLastAfkFire = 0
            khAntiAfkNudge("boot")
            print("[Khfresh][AntiAFK] armed Nexus-style (Idled + AFK remote + ClickButton2)")
        end
    end)
    return true
end

stopAntiAFK = function()
    if runtimeEnv.AntiAFKConnection then
        pcall(function() runtimeEnv.AntiAFKConnection:Disconnect() end)
        runtimeEnv.AntiAFKConnection = nil
    end
    if runtimeEnv.AntiAFKThread then
        pcall(function() task.cancel(runtimeEnv.AntiAFKThread) end)
        runtimeEnv.AntiAFKThread = nil
    end
    runtimeEnv.AntiAFKInitialized = false
end

-- ===== MOVEMENT & UTILITY NATIVE TASKS =====
do
    local noclipCachedParts = nil
    local noclipCachedChar = nil
    RunService.Stepped:Connect(function()
        if not alive() then return end
        if not MiscFlags.Noclip then return end
        local char = LocalPlayer.Character
        if not char then return end
        if noclipCachedChar ~= char then
            noclipCachedChar = char
            noclipCachedParts = {}
            for _, v in ipairs(char:GetDescendants()) do
                if v:IsA("BasePart") then noclipCachedParts[#noclipCachedParts + 1] = v end
            end
        end
        for _, v in ipairs(noclipCachedParts) do
            if v.Parent and v.CanCollide then v.CanCollide = false end
        end
    end)

    UserInputService.JumpRequest:Connect(function()
        if MiscFlags.InfiniteJump and LocalPlayer.Character then
            local h = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
        end
    end)

end

-- Event scanner removed: no always-on NPC/weather scans or webhook traffic.

-- Automatic config saving and loading are disabled; saving is manual only.
khAutoSaveEnabled = false

-- ===== MAIN LOOPS (Boss Farm, Auto Sell, GUI QTE) =====
local function GetInventoryLimit()
    local userFolder = GetPlayerData()
    if not userFolder then return 0 end
    local sum = 0
    pcall(function()
        for _, v in pairs(userFolder.Inventory:GetChildren()) do sum = sum + 1 end
        for _, v in pairs(userFolder.Hotbar:GetChildren()) do sum = sum + v.Quantity.Value end
    end)
    return sum
end

local function IsInventoryFull()
    local userFolder = GetPlayerData()
    if not userFolder then return false end
    local limit = 0
    pcall(function() limit = userFolder.InventoryLimit.Value end)
    return GetInventoryLimit() >= limit
end

local GuiService = Services.GuiService
local khfreshPanel = LocalPlayer.PlayerGui:FindFirstChild("KhfreshPanel")

local function DisableKhfreshKeyboardActivation(object)
    if object:IsA("GuiObject") then
        object.Selectable = false
    end
end

if runtimeEnv.KhfreshSpaceGuardConnection then
    runtimeEnv.KhfreshSpaceGuardConnection:Disconnect()
    runtimeEnv.KhfreshSpaceGuardConnection = nil
end
if runtimeEnv.KhfreshSelectableGuardConnection then
    runtimeEnv.KhfreshSelectableGuardConnection:Disconnect()
    runtimeEnv.KhfreshSelectableGuardConnection = nil
end

if khfreshPanel then
    DisableKhfreshKeyboardActivation(khfreshPanel)
    for _, object in ipairs(khfreshPanel:GetDescendants()) do
        DisableKhfreshKeyboardActivation(object)
    end
    runtimeEnv.KhfreshSelectableGuardConnection = khfreshPanel.DescendantAdded:Connect(function(object)
        task.defer(DisableKhfreshKeyboardActivation, object)
    end)
end

runtimeEnv.KhfreshSpaceGuardConnection = UserInputService.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Space then
        local selected = GuiService.SelectedObject
        if selected and khfreshPanel and selected:IsDescendantOf(khfreshPanel) then
            GuiService.SelectedObject = nil
        end
    end
end)

local function castRod()
    if not (bossFarmEnabled() or (KhfreshState.AutoFarm and KhfreshState.AutoFarm.enabled)) then return false end
    local character = LocalPlayer.Character
    if not character then return false end
    if character:GetAttribute("Fishing") and not character:GetAttribute("Retractable") then return false end
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    Fishing.BossFarm.LastCast = tick()
    resetBossFarmTarget()
    pcall(function()
        safeFire("Fishing", root.CFrame)
    end)
    return true
end

local function farmHookedBoss(target)
    if not bossFarmEnabled() then return end
    local shouldFarm, targetType = shouldFarmBossTarget(target)
    if not shouldFarm then return end
    Fishing.BossFarm.CurrentType = targetType
    local notifyKey = targetType .. tostring(target.Name)
    if Fishing.BossFarm.LastNotify ~= notifyKey then
        Fishing.BossFarm.LastNotify = notifyKey
        KhfreshLib:Notify({ Title = "Boss Farm", Message = "Farming " ..
        targetType .. ": " .. tostring(target.Name or "Unknown"), Duration = 3 })
    end
    Fishing.BossFarm.LastProgress = tick()
    pcall(function() safeFire("UpdateFishProgression") end)
end

-- MAIN LOOPS
-- Heartbeat-driven gameplay loop. No cooldown gate is used for normal fishing/skills.
do
    local skillOrder = {"Z", "X", "C", "V"}

    runtimeEnv.KhfreshFishingHeartbeat = RunService.Heartbeat:Connect(function()
        if not alive() then return end
        if KhfreshState.SelectedAutoFarmFishRunning == true then return end

        local farmSkill = Fishing.Flags.AutoFarmSkill == true
        local autoCast = Fishing.Flags.AutoCast == true
        local mainFarm = Fishing.Flags.MainFarm == true

        if not (mainFarm or autoCast or farmSkill or Fishing.Flags.AntiAFK) then return end

        local char = LocalPlayer.Character
        if not char then return end

        if autoCast then
            pcall(function()
                -- Fast Auto Farm: Heartbeat-driven, no client-side cooldown/jitter/movement gate.
                -- The only state gate is Roblox's Fishing attribute so we do not cast twice
                -- while the current cast is still active.
                if not char:GetAttribute("Fishing") then
                    local remote = Events and Events:FindFirstChild("Fishing")
                    if remote then
                        remote:FireServer()
                    end
                elseif KhfreshState.isDoingUseBaitQuest and MainGui:FindFirstChild("Fishing") and MainGui.Fishing.Visible then
                    local remote = Events and Events:FindFirstChild("Fishing")
                    if remote then
                        remote:FireServer()
                    end
                end
            end)
        end

        if Fishing.Flags.AntiAFK then
            pcall(function() safeFire("AFK") end)
        end
    end)

    -- ===== NEXUS-STYLE AUTO SKILL LOOP =====
    task.spawn(function()
        local warnedMissingRemote = false
        while alive() do
            task.wait(0.5 + math.random(0, 30) / 100)
            if not alive() then break end
            local fishingGui = MainGui and MainGui:FindFirstChild("Fishing")
            if (Fishing.Flags.AutoFarmSkill == true or Fishing.Flags.AutoSkill == true)
                and fishingGui and fishingGui.Visible then
                local char = LocalPlayer.Character
                local skillsFolder = char and char:FindFirstChild("Skills")
                local useSkill = Events and Events:FindFirstChild("UseSkill")
                if skillsFolder and useSkill and useSkill:IsA("RemoteEvent") then
                    local readySkills = {}
                    for _, skill in ipairs(skillsFolder:GetChildren()) do
                        if skill:IsA("NumberValue") and skill.Value <= 0 then
                            local key = skill:GetAttribute("Key")
                            if type(key) == "string" then readySkills[key] = true end
                        end
                    end
                    local selected = Fishing.Flags.SelectedSkills
                    if type(selected) ~= "table" then
                        selected = {Z = true, X = true, C = true, V = true}
                    end
                    for _, key in ipairs(skillOrder) do
                        if selected[key] == true and readySkills[key] then
                            local ok, err = pcall(function() useSkill:FireServer(key) end)
                            if not ok and not warnedMissingRemote then
                                warnedMissingRemote = true
                                warn("[Khfresh][AutoSkill] UseSkill request failed:", tostring(err))
                            end
                        end
                    end
                elseif not warnedMissingRemote then
                    warnedMissingRemote = true
                    warn("[Khfresh][AutoSkill] UseSkill RemoteEvent or character Skills folder is unavailable.")
                end
            end
        end
    end)
end

-- SMART SECRET WEATHER OVERRIDE LOOP
task.spawn(function()
    local weatherIslandsMap = {
        ["thunderstorm"] = "Island 2",
        ["rainy"]        = "Island 3",
        ["windy"]        = "Island 5",
        ["snowy"]        = "Island 6",
        ["frost"]        = "Island 6",
        ["foggy"]        = "Island 7",
        ["blazing sun"]  = "Island 8",
    }

    local function normalizeWeatherName(value)
        return string.lower(tostring(value or "")):gsub("%-", " "):gsub("%s+", " ")
            :gsub("^%s+", ""):gsub("%s+$", "")
    end

    local function getActiveWeather()
        local workspaceWeather = Workspace:GetAttribute("Weather")
        if type(workspaceWeather) == "string" and workspaceWeather ~= "" then
            return normalizeWeatherName(workspaceWeather)
        end
        local info = MainGui:FindFirstChild("Info")
        if info then
            local infoFrame = info:FindFirstChild("Info")
            if infoFrame then
                local weatherFrame = infoFrame:FindFirstChild("Weather")
                if weatherFrame then
                    local val = weatherFrame:FindFirstChild("Value")
                    if val then
                        local text = val:IsA("TextLabel") and val.Text or val.Value
                        return normalizeWeatherName(text:gsub("Weather:%s*", ""))
                    end
                end
            end
        end
        return "clear"
    end

    local function findWeatherIsland(weather)
        local configuredWeatherNames = KhfreshState.SmartWeather.weatherNames or {}
        for _, island in ipairs({"Island 9", "Island 12", "Island 13"}) do
            local name = configuredWeatherNames[island]
            if name ~= "" and normalizeWeatherName(name) == weather then
                return island
            end
        end
        return weatherIslandsMap[weather]
    end

    while true do
        task.wait(1.5)
        if not alive() then break end
        if KhfreshState.SmartWeather and KhfreshState.SmartWeather.enabled
            and not (KhfreshState.AutoFarm and KhfreshState.AutoFarm.enabled) then
            pcall(function()
                local currentWeather = getActiveWeather()
                local matchedIsland = findWeatherIsland(currentWeather)

                if matchedIsland and (currentWeather ~= "clear" and currentWeather ~= "") and KhfreshState.SmartWeather.selectedIslands[matchedIsland] then
                    if not KhfreshState.SmartWeather.activeOverride then
                        local char = LocalPlayer.Character
                        local hrp = char and char:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            KhfreshState.SmartWeather.savedCFrame = hrp.CFrame
                            KhfreshState.SmartWeather.savedFlags = {
                                AutoCast = Fishing.Flags.AutoCast,
                                AutoFarmBoss = Fishing.Flags.AutoFarmBoss,
                                AutoFarmSecretBoss = Fishing.Flags.AutoFarmSecretBoss,
                                AnchorLock = Fishing.Flags.AnchorLock,
                                AutoSkill = Fishing.Flags.AutoSkill,
                                AutoSkillCheck = Fishing.Flags.AutoSkillCheck,
                                AntiAFK = Fishing.Flags.AntiAFK,
                            }
                            KhfreshState.SmartWeather.activeOverride = true
                            KhfreshState.SmartWeather.targetIsland = matchedIsland

                            local weatherIsland = khResolveIslandEntry(matchedIsland)
                            if weatherIsland and weatherIsland.cframe then
                                hrp.CFrame = CFrame.new(weatherIsland.cframe.Position + Vector3.new(0, 3, 0))
                            else
                                KhfreshLib:Notify({Title="Smart Secret Weather", Message="Live position unavailable for "..tostring(matchedIsland)..".", Duration=3})
                            end

                            Fishing.Flags.AutoCast = false
                            Fishing.Flags.AutoFarmBoss = false
                            Fishing.Flags.AutoFarmSecretBoss = true
                            Fishing.Flags.AnchorLock = true
                            Fishing.Flags.AutoSkill = true
                            Fishing.Flags.AutoSkillCheck = true
                            Fishing.Flags.AntiAFK = true

                            KhfreshLib:Notify({
                                Title = "Smart Secret Weather",
                                Message = "Weather detected: " ..
                                currentWeather:upper() .. "! Auto-hopping to " .. matchedIsland .. " cau Secret.",
                                Duration = 4
                            })
                        end
                    end
                else
                    if KhfreshState.SmartWeather.activeOverride then
                        KhfreshLib:Notify({
                            Title = "Smart Secret Weather",
                            Message = "Weather ended! Returning to the original farm...",
                            Duration = 3
                        })
                        local char = LocalPlayer.Character
                        local hrp = char and char:FindFirstChild("HumanoidRootPart")
                        if KhfreshState.SmartWeather.savedCFrame and hrp then
                            hrp.CFrame = KhfreshState.SmartWeather.savedCFrame
                        end
                        if KhfreshState.SmartWeather.savedFlags then
                            local s = KhfreshState.SmartWeather.savedFlags
                            Fishing.Flags.AutoCast = s.AutoCast
                            Fishing.Flags.AutoFarmBoss = s.AutoFarmBoss
                            Fishing.Flags.AutoFarmSecretBoss = s.AutoFarmSecretBoss
                            Fishing.Flags.AnchorLock = s.AnchorLock
                            Fishing.Flags.AutoSkill = s.AutoSkill
                            Fishing.Flags.AutoSkillCheck = s.AutoSkillCheck
                            Fishing.Flags.AntiAFK = s.AntiAFK
                        end
                        KhfreshState.SmartWeather.activeOverride = false
                        KhfreshState.SmartWeather.savedCFrame = nil
                        KhfreshState.SmartWeather.savedFlags = nil
                        KhfreshState.SmartWeather.targetIsland = nil
                    end
                end
            end)
        end
    end
end)

task.spawn(function()
    while task.wait(0.2) do
        if not alive() then break end
        if KhfreshState.SelectedAutoFarmFishRunning ~= true and bossFarmEnabled() then
            local character = LocalPlayer.Character
            local fishingGui = MainGui and MainGui:FindFirstChild("Fishing")
            if character and character:GetAttribute("Fishing") then
                if Fishing.BossFarm.PendingCancel then
                    cancelOrReleaseNormalFish()
                elseif Fishing.BossFarm.HasHooked and fishingGui and fishingGui.Visible then
                    local target = getCurrentHookTarget()
                    local shouldFarm = shouldFarmBossTarget(target)
                    if shouldFarm then
                        Fishing.BossFarm.PendingCancel = false
                        farmHookedBoss(target)
                    elseif target.Name and target.Name ~= "???" then
                        Fishing.BossFarm.PendingCancel = true
                        cancelOrReleaseNormalFish()
                    end
                end
            else
                resetBossFarmTarget()
                castRod()
            end
        end
    end
end)

-- AUTO SELL
do
    local function getInventoryCount()
        local userData = Data:FindFirstChild(tostring(LocalPlayer.UserId))
        if not userData then return 0 end
        local inv = userData:FindFirstChild("Inventory")
        if not inv then return 0 end
        local count = 0
        for _ in pairs(inv:GetChildren()) do count = count + 1 end
        return count
    end

    local function getInventoryLimit()
        local userData = Data:FindFirstChild(tostring(LocalPlayer.UserId))
        if not userData then return 0 end
        local limit = userData:FindFirstChild("InventoryLimit")
        if limit and limit:IsA("NumberValue") then return limit.Value end
        return 0
    end

    local function getSellSofa()
        local map = Workspace:FindFirstChild("Map")
        if map then
            local map1 = map:FindFirstChild("Map 1")
            if map1 then
                local build = map1:FindFirstChild("Build")
                if build then
                    local sellFish = build:FindFirstChild("SellFish")
                    if sellFish then
                        return sellFish:FindFirstChild("Sofa")
                    end
                end
            end
        end
        return nil
    end

    local function getSofaPosition()
        local sofa = getSellSofa()
        if sofa then
            local hrp = sofa:FindFirstChild("HumanoidRootPart")
            if hrp then return hrp.Position end
            local primary = sofa.PrimaryPart
            if primary then return primary.Position end
            for _, part in ipairs(sofa:GetDescendants()) do
                if part:IsA("BasePart") then
                    return part.Position
                end
            end
        end
        return nil
    end

    local function teleportToSofa()
        local pos = getSofaPosition()
        if not pos then return false end
        local char = LocalPlayer.Character
        if not char then return false end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
        KhfreshState.lastPosition = hrp.Position
        hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
        return true
    end

    local function teleportBack()
        if not KhfreshState.lastPosition then return end
        local char = LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        hrp.CFrame = CFrame.new(KhfreshState.lastPosition)
        KhfreshState.lastPosition = nil
    end

    local function doSell()
        if not MiscFlags.AutoSell then return end
        if tick() - (KhfreshState.sellCooldown or 0) < 0.5 then return end
        KhfreshState.sellCooldown = tick()
        local method1 = KhfreshState.sellMethod1 or "Spam"
        local method2 = KhfreshState.sellMethod2 or "Instant"
        if method1 == "When full" then
            local count = getInventoryCount()
            local limit = getInventoryLimit()
            if limit == 0 then return end
            if count < limit - 3 then return end
        end
        local teleported = false
        if method2 == "Teleport" then
            teleported = teleportToSofa()
            if teleported then task.wait(0.3) end
        end
        pcall(function() safeFire("SellFish", "All") end)
        if teleported then
            task.wait(0.2)
            teleportBack()
        end
    end

    task.spawn(function()
        while task.wait(1) do
            if not alive() then break end
            pcall(doSell)
        end
    end)
end

local function selectedFarmCurrentIslandFromState()
    local islands = KhfreshState.SelectedAutoFarmIslands or {}
    if #islands == 0 then return nil end
    local index = tonumber(KhfreshState.SelectedAutoFarmIslandIndex) or 1
    if index < 1 or index > #islands then index = 1 end
    KhfreshState.SelectedAutoFarmIslandIndex = index
    return islands[index]
end

local function selectedFarmIslandCompleteFromState(islandNumber)
    local wanted = (KhfreshState.SelectedAutoFarmFishByIsland or {})[islandNumber] or {}
    local caught = (KhfreshState.SelectedAutoFarmCaughtByIsland or {})[islandNumber] or {}
    local total, done = 0, 0
    for fishName in pairs(wanted) do
        total += 1
        if caught[fishName] then done += 1 end
    end
    return total > 0 and done >= total, done, total
end

local function selectedFarmAdvanceIslandFromState()
    local islands = KhfreshState.SelectedAutoFarmIslands or {}
    if #islands <= 1 then return end
    local index = tonumber(KhfreshState.SelectedAutoFarmIslandIndex) or 1
    index += 1
    if index > #islands then
        index = 1
        KhfreshState.SelectedAutoFarmCaughtByIsland = {}
        for islandNumber in pairs(KhfreshState.SelectedAutoFarmFishByIsland or {}) do
            KhfreshState.SelectedAutoFarmCaughtByIsland[islandNumber] = {}
        end
    end
    KhfreshState.SelectedAutoFarmIslandIndex = index
end

local function tryInstantCatch(token, context)
    if KhfreshState.InstantCatchEnabled ~= true or token == nil then return false end
    if bossFarmEnabled() then return false end
    local ok = false
    pcall(function()
        -- The dump's DoCleanUp(true, nil) calls FireServer(true, token, nil).
        ok = safeFire("FishingMinigame", true, token, nil)
    end)
    if ok then
        warn("[Khfresh][InstantCatch] success packet attempted for "..tostring(context or "fish").."; server validation may reject it")
    end
    return ok
end

Events.FishingMinigame.OnClientEvent:Connect(function(p1, p2, p3)
    -- The game source sends a table containing FishName for a real minigame.
    -- Cleanup/cancel packets are not new casts and must never enter this handler.
    if type(p1) ~= "table" or type(p2) ~= "table" then return end

    if KhfreshState.SelectedAutoFarmFishRunning == true then
        if KhfreshState.SelectedAutoFarmPhase ~= "WaitingForMinigame" then return end

        local serial = tonumber(KhfreshState.SelectedAutoFarmCastSerial) or 0
        if serial <= 0 or serial ~= tonumber(KhfreshState.SelectedAutoFarmActiveCastSerial) then return end

        KhfreshState.SelectedAutoFarmCastToken = p3
        Fishing.BossFarm.CurrentToken = p3
        KhfreshState.SelectedAutoFarmPhase = "Minigame"

        task.spawn(function()
            -- FishName can lag behind the minigame event or still contain the previous
            -- catch. Wait briefly for the actual ProgressionBar label to settle.
            local baseline = normalizeSelectedFishName(KhfreshState.SelectedAutoFarmFishNameAtCast or "")
            local eventFishName = normalizeSelectedFishName(p1.FishName or p1.Name or "")
            local fishName = ""
            local started = tick()
            local deadline = started + 1.0
            while tick() < deadline and KhfreshState.SelectedAutoFarmFishRunning == true do
                if serial ~= tonumber(KhfreshState.SelectedAutoFarmCastSerial) then return end
                fishName = readProgressFishName()
                if not isSelectedFishPlaceholder(fishName) then
                    -- ProgressionBar is the displayed label. The game's own minigame
                    -- payload is used only to reject a stale label from the previous cast.
                    if eventFishName ~= "" then
                        if fishName == eventFishName or tick() - started >= 0.25 then break end
                    elseif baseline == "" or fishName ~= baseline or tick() - started >= 0.45 then
                        break
                    end
                end
                task.wait(0.05)
            end

            if serial ~= tonumber(KhfreshState.SelectedAutoFarmCastSerial) then return end
            if KhfreshState.SelectedAutoFarmFishRunning ~= true then return end
            if isSelectedFishPlaceholder(fishName) and eventFishName == "" then
                warn("[Khfresh][SelectedFish] Both ProgressionBar.FishName and event FishName unavailable; NO CANCEL")
                KhfreshState.SelectedAutoFarmPhase = "Minigame"
                return
            end
            if eventFishName ~= "" and fishName ~= eventFishName then
                warn("[Khfresh][SelectedFish] stale UI label=["..tostring(fishName).."], event FishName=["..tostring(p1.FishName).."]")
                fishName = eventFishName
            end

            local wanted = normalizeSelectedFishName(fishName)
            local selectedSet = KhfreshState.SelectedAutoFarmFishSet or {}
            local keep = false
            for selectedName, enabled in pairs(selectedSet) do
                if enabled == true and normalizeSelectedFishName(selectedName) == wanted then
                    keep = true
                    break
                end
            end

            warn("[Khfresh][SelectedFish] ProgressionBar.FishName=["..tostring(fishName).."] -> "..(keep and "KEEP" or "CANCEL"))

            if not keep then
                -- Wrong fish: one cancel, then wait for a fully idle state before recast.
                KhfreshState.SelectedAutoFarmKeepCurrent = false
                KhfreshState.SelectedAutoFarmPhase = "Cancelling"
                KhfreshState.SelectedAutoFarmLastCancelAt = tick()
                local token = KhfreshState.SelectedAutoFarmCastToken or p3
                if token ~= nil then
                    -- Matches the official client DoCleanUp(false, reason) packet shape.
                    pcall(function() safeFire("FishingMinigame", false, token, "SelectedFishWrong") end)
                else
                    warn("[Khfresh][SelectedFish] No minigame token; will not send a risky cast toggle")
                    KhfreshState.SelectedAutoFarmPhase = "Minigame"
                end
                return
            end

            -- Correct fish: lock the catch bar only for this accepted catch.
            KhfreshState.SelectedAutoFarmKeepCurrent = true
            if KhfreshState.InstantCatchEnabled == true and p3 ~= nil then
                -- Experimental: identical argument layout to the game's successful DoCleanUp(true, nil).
                -- Continue ordinary progression as a fallback if the server rejects this request.
                task.delay(0.12, function()
                    if KhfreshState.SelectedAutoFarmFishRunning == true
                        and serial == tonumber(KhfreshState.SelectedAutoFarmCastSerial)
                        and KhfreshState.SelectedAutoFarmKeepCurrent == true then
                        tryInstantCatch(p3, fishName)
                    end
                end)
            end
            local timeoutAt = tick() + 45
            while serial == tonumber(KhfreshState.SelectedAutoFarmCastSerial)
                and KhfreshState.SelectedAutoFarmFishRunning == true do
                local character = LocalPlayer.Character
                local fishingGui = MainGui and MainGui:FindFirstChild("Fishing")
                local active = character and character:GetAttribute("Fishing") and fishingGui and fishingGui.Visible
                if not active then break end
                pcall(function() safeFire("UpdateFishProgression") end)
                if tick() >= timeoutAt then
                    warn("[Khfresh][SelectedFish] Progress timeout; STAY on current island")
                    return
                end
                task.wait(0.08)
            end

            if serial ~= tonumber(KhfreshState.SelectedAutoFarmCastSerial) then return end
            if KhfreshState.SelectedAutoFarmFishRunning ~= true then return end

            local currentIsland = tonumber(KhfreshState.SelectedAutoFarmCurrentIsland) or selectedFarmCurrentIslandFromState()
            if not currentIsland then
                KhfreshState.SelectedAutoFarmPhase = "Idle"
                return
            end

            KhfreshState.SelectedAutoFarmCaughtByIsland = KhfreshState.SelectedAutoFarmCaughtByIsland or {}
            KhfreshState.SelectedAutoFarmCaughtByIsland[currentIsland] = KhfreshState.SelectedAutoFarmCaughtByIsland[currentIsland] or {}
            KhfreshState.SelectedAutoFarmCaughtByIsland[currentIsland][wanted] = true

            local complete, doneCount, totalCount = selectedFarmIslandCompleteFromState(currentIsland)
            if complete then
                warn("[Khfresh][SelectedFish] Island "..tostring(currentIsland).." COMPLETE "..tostring(doneCount).."/"..tostring(totalCount))
                selectedFarmAdvanceIslandFromState()
                KhfreshState.SelectedAutoFarmCurrentIsland = selectedFarmCurrentIslandFromState()
                selectedLastIsland = nil
            else
                warn("[Khfresh][SelectedFish] Island "..tostring(currentIsland).." progress "..tostring(doneCount).."/"..tostring(totalCount).." — STAY")
            end

            KhfreshState.SelectedAutoFarmPhase = "Idle"
        end)
        return
    end

    -- Experimental instant-catch attempt for ordinary fish. The game dump contains
    -- the client packet shape but omits the server listener, so normal progression remains active.
    if KhfreshState.InstantCatchEnabled == true and not bossFarmEnabled()
        and p3 ~= nil and p1.Boss ~= true and p1.SecretBoss ~= true then
        task.delay(0.12, function()
            if alive() and KhfreshState.InstantCatchEnabled == true and not bossFarmEnabled() then
                tryInstantCatch(p3, p1.FishName or "normal fish")
            end
        end)
    end

    -- Normal/Boss fishing path.
    Fishing.BossFarm.CurrentTarget = p1
    Fishing.BossFarm.CurrentToken = p3
    Fishing.BossFarm.HasHooked = true
    Fishing.BossFarm.PendingCancel = false
    Fishing.BossFarm.CurrentRunId = Fishing.BossFarm.CurrentRunId + 1
    local runId = Fishing.BossFarm.CurrentRunId
    local target = getCurrentHookTarget()
    local shouldFarm = shouldFarmBossTarget(target)
    if bossFarmEnabled() and not shouldFarm then
        Fishing.BossFarm.PendingCancel = true
        task.delay(0.15, cancelOrReleaseNormalFish)
        return
    end
    if Fishing.Flags.AutoCast or (bossFarmEnabled() and shouldFarm) then
        task.spawn(function()
            local minigameActive = true
            local connection
            connection = MainGui.Fishing:GetPropertyChangedSignal("Visible"):Connect(function()
                if not MainGui.Fishing.Visible then
                    minigameActive = false
                    if connection then connection:Disconnect() end
                end
            end)
            while minigameActive do
                if not alive() then break end
                if bossFarmEnabled() then
                    if runId ~= Fishing.BossFarm.CurrentRunId then break end
                    target = getCurrentHookTarget()
                    shouldFarm = shouldFarmBossTarget(target)
                    if not shouldFarm then
                        Fishing.BossFarm.PendingCancel = true
                        cancelOrReleaseNormalFish()
                        break
                    end
                    farmHookedBoss(target)
                    task.wait(0.08)
                else
                    pcall(function() safeFire("UpdateFishProgression") end)
                    task.wait(0.2)
                end
            end
            if bossFarmEnabled() and runId == Fishing.BossFarm.CurrentRunId then
                resetBossFarmTarget()
            end
        end)
    end
end)

Events.Slam.OnClientEvent:Connect(function(cb)
    if Fishing.Flags.MainFarm or (KhfreshState.AutoFarm and KhfreshState.AutoFarm.enabled) then
        task.spawn(function()
            -- No anti-ban/humanization delay. Complete immediately.
            pcall(function() cb:FireServer("Perfect") end)
            local tc = MainGui:FindFirstChild("Fishing") and MainGui.Fishing:FindFirstChild("TrashCan")
            if tc and tc:FindFirstChild("Slam") then pcall(function() tc.Slam:Destroy() end) end
        end)
    end
end)

-- ===== AUTO ENZO / LONG DIAOHAI — REAL HITS + FAST GREEN HITBOX =====
-- Uses the game's BossPhase2Action hit packet and advances the hit index on success.
local lastQTEClick = 0
local qteHitIndex = 0
local qteBarWasVisible = false
local BossPhase2Action = Events and Events:FindFirstChild("BossPhase2Action")

pcall(function()
    local setup = Events and Events:FindFirstChild("BossPhase2Setup")
    if setup and setup:IsA("RemoteEvent") then
        setup.OnClientEvent:Connect(function()
            qteHitIndex = 1
            qteBarWasVisible = true
            lastQTEClick = 0
        end)
    end
end)

local function qteTeleportGreenHitbox(bossBar)
    if not bossBar then return end
    local hitbox = bossBar:FindFirstChild("Hitbox")
    if not (hitbox and hitbox:IsA("GuiObject")) then return end
    local bar = bossBar:FindFirstChild("Bar")
    local width = hitbox.Size.X.Scale
    if width < 0.04 or width > 0.35 then
        width = 0.11
        if bar and bar:IsA("GuiObject") then
            local barWidth = bar.Size.X.Scale
            if type(barWidth) == "number" and barWidth > 0.04 and barWidth < 0.35 then
                width = barWidth
            end
        end
    end
    local pad = 0.02
    local leftMax = math.max(pad, 1 - width - pad)
    local previousLeft = hitbox.Position.X.Scale - width * hitbox.AnchorPoint.X
    local left
    for _ = 1, 4 do
        left = pad + math.random() * (leftMax - pad)
        if math.abs(left - previousLeft) > 0.12 or leftMax - pad < 0.15 then
            break
        end
    end
    hitbox.Visible = true
    hitbox.Size = UDim2.new(width, 0, hitbox.Size.Y.Scale, hitbox.Size.Y.Offset)
    hitbox.Position = UDim2.new(
        left + width * hitbox.AnchorPoint.X, 0,
        hitbox.Position.Y.Scale, hitbox.Position.Y.Offset
    )

    local bad = bossBar:FindFirstChild("HitboxBad")
    if bad and bad:IsA("GuiObject") and bad.Visible then
        local badWidth = bad.Size.X.Scale
        if badWidth > 0.02 and badWidth < 0.4 then
            local badLeft = pad + math.random() * math.max(0.01, leftMax - pad)
            if math.abs(badLeft - left) < width + 0.05 then
                badLeft = left + width + 0.08
                if badLeft > leftMax then badLeft = pad end
            end
            bad.Position = UDim2.new(
                badLeft + badWidth * bad.AnchorPoint.X, 0,
                bad.Position.Y.Scale, bad.Position.Y.Offset
            )
        end
    end
end

local function pressBossPerfectRemote(bossBar)
    if not BossPhase2Action then
        BossPhase2Action = Events and Events:FindFirstChild("BossPhase2Action")
    end
    if not (BossPhase2Action and BossPhase2Action:IsA("RemoteEvent")) then return false end
    local index = math.max(1, tonumber(qteHitIndex) or 1)
    if math.random(1, 50) == 1 then
        local ok, err = pcall(function()
            BossPhase2Action:FireServer({ Hit = false })
        end)
        if not ok then warn("[Khfresh][AutoEnzo] Miss action failed:", tostring(err)) end
        return ok
    end
    local ok, err = pcall(function()
        BossPhase2Action:FireServer({ Hit = true, Index = index })
    end)
    if ok then
        qteHitIndex = index + 1
        local moved, moveError = pcall(qteTeleportGreenHitbox, bossBar)
        if not moved then warn("[Khfresh][AutoEnzo] Hitbox update failed:", tostring(moveError)) end
    else
        warn("[Khfresh][AutoEnzo] Hit action failed:", tostring(err))
    end
    return ok
end

local function runBossQTETick()
    if not alive() then return end
    local qteEnabled = Fishing.Flags.AutoSkillCheck == true
        or KhfreshState.AutoEnzoEnabled == true
        or KhfreshState.AutoLongDiaohaiEnabled == true
        or KhfreshState.AutoBlackTortoiseEnabled == true
    if not qteEnabled then return end

    local fishing = MainGui and MainGui:FindFirstChild("Fishing")
    local bossBar = fishing and fishing:FindFirstChild("BossFightBar")
    if not (fishing and bossBar and bossBar.Visible == true) then
        if qteBarWasVisible then
            qteBarWasVisible = false
            qteHitIndex = 0
        end
        return
    end

    if not qteBarWasVisible then
        qteBarWasVisible = true
        if qteHitIndex < 1 then qteHitIndex = 1 end
        lastQTEClick = 0
        local ok, err = pcall(qteTeleportGreenHitbox, bossBar)
        if not ok then warn("[Khfresh][AutoEnzo] Initial hitbox update failed:", tostring(err)) end
    end

    local now = tick()
    local hitCooldown = KhfreshState.AutoLongDiaohaiEnabled == true
        and KhfreshState.AutoLongDiaohaiHitCooldown
        or KhfreshState.AutoEnzoHitCooldown
    hitCooldown = math.clamp(tonumber(hitCooldown) or 0.15, 0.01, 1)
    if now - lastQTEClick < hitCooldown then return end
    lastQTEClick = now
    pressBossPerfectRemote(bossBar)
end

pcall(function()
    if runtimeEnv._khQTERender then runtimeEnv._khQTERender:Disconnect() end
    if runtimeEnv._khQTEHeart then runtimeEnv._khQTEHeart:Disconnect() end
    if runtimeEnv._khLagShield then runtimeEnv._khLagShield:Disconnect() end
end)
runtimeEnv._khQTEHeart = RunService.Heartbeat:Connect(function()
    local ok, err = pcall(runBossQTETick)
    if not ok then warn("[Khfresh][AutoEnzo] Heartbeat failed:", tostring(err)) end
end)
runtimeEnv._khQTERender = nil
runtimeEnv._khLagShield = nil

local function updateHubFrameWork(dt)
    if not alive() then return false end
    if MiscFlags.FullBright and not KhfreshState.fullBrightApplied then
        pcall(function()
            Lighting.Ambient = Color3.new(1,1,1)
            Lighting.ColorShift_Bottom = Color3.new(1,1,1)
            Lighting.ColorShift_Top = Color3.new(1,1,1)
            Lighting.Brightness = 2
            Lighting.OutdoorAmbient = Color3.new(1,1,1)
            KhfreshState.fullBrightApplied = true
        end)
    elseif not MiscFlags.FullBright and KhfreshState.fullBrightApplied then
        KhfreshState.fullBrightApplied = false
    end
    return true
end

-- ===== ALWAYS-ON CATCH BAR LOCK =====
local _anchorCenter = UDim2.new(0.5, 0, 0.5, 0)
local function khForceBarCenter(bar)
    if not bar or not bar:IsA("GuiObject") then return end
    if bar.Parent and bar.Parent.Name == "BossFightBar" then return end
    bar.Visible = true
    bar.AnchorPoint = Vector2.new(0.5, 0.5)
    bar.Position = _anchorCenter
end

local function khShouldAnchorLock()
    local fishing = MainGui and MainGui:FindFirstChild("Fishing")
    if not fishing or not fishing.Visible then return false end
    local bossBar = fishing:FindFirstChild("BossFightBar")
    if bossBar and bossBar.Visible then return false end
    local rhythm = fishing:FindFirstChild("Rhythm")
    if rhythm and rhythm.Visible then return false end
    local character = LocalPlayer.Character
    if character and character:GetAttribute("Phase2") == true then return false end
    local barFrame = fishing:FindFirstChild("BarFrame")
    return barFrame ~= nil and barFrame:IsA("GuiObject") and barFrame.Visible ~= false
end

local function khRunAnchorLock()
    if not alive() or not khShouldAnchorLock() then return end
    local fishing = MainGui and MainGui:FindFirstChild("Fishing")
    local barFrame = fishing and fishing:FindFirstChild("BarFrame")
    if not (barFrame and barFrame:IsA("GuiObject")) then return end
    if barFrame.Size.X.Scale ~= 1 then
        barFrame.Size = UDim2.new(1, 0, barFrame.Size.Y.Scale, barFrame.Size.Y.Offset)
    end
    local bar = barFrame:FindFirstChild("Bar")
    if bar and bar.Parent == barFrame then
        khForceBarCenter(bar)
    end
end

pcall(function()
    if runtimeEnv._khAnchorRender then runtimeEnv._khAnchorRender:Disconnect() end
    if runtimeEnv._khAnchorHeart then runtimeEnv._khAnchorHeart:Disconnect() end
end)
runtimeEnv._khAnchorRender = RunService.RenderStepped:Connect(function()
    local ok, err = pcall(khRunAnchorLock)
    if not ok then warn("[Khfresh][CatchBarLock] RenderStepped failed:", tostring(err)) end
end)
runtimeEnv._khAnchorHeart = RunService.Heartbeat:Connect(function()
    local ok, err = pcall(khRunAnchorLock)
    if not ok then warn("[Khfresh][CatchBarLock] Heartbeat failed:", tostring(err)) end
end)

local _anchorBarHooked = nil
local function khHookAnchorBar(bar)
    if not bar or bar == _anchorBarHooked then return end
    if bar.Parent and bar.Parent.Name == "BossFightBar" then return end
    _anchorBarHooked = bar
    bar:GetPropertyChangedSignal("Position"):Connect(function()
        if not khShouldAnchorLock() then return end
        local position = bar.Position
        if math.abs(position.X.Scale - 0.5) > 0.001
            or math.abs(position.Y.Scale - 0.5) > 0.001 then
            khForceBarCenter(bar)
        end
    end)
end

pcall(function()
    local fishing = MainGui and MainGui:FindFirstChild("Fishing")
    if fishing then
        fishing:GetPropertyChangedSignal("Visible"):Connect(function()
            if fishing.Visible then
                local barFrame = fishing:FindFirstChild("BarFrame")
                local bar = barFrame and barFrame:FindFirstChild("Bar")
                if bar then khHookAnchorBar(bar) end
            end
        end)
        local barFrame = fishing:FindFirstChild("BarFrame")
        local bar = barFrame and barFrame:FindFirstChild("Bar")
        if bar then khHookAnchorBar(bar) end
        fishing.ChildAdded:Connect(function(child)
            if child.Name == "BarFrame" then
                local newBar = child:FindFirstChild("Bar")
                if newBar then khHookAnchorBar(newBar) end
                child.ChildAdded:Connect(function(newChild)
                    if newChild.Name == "Bar" then khHookAnchorBar(newChild) end
                end)
            end
        end)
    end
end)

-- Selected Fish farm hides only the visual Bar. The Bar object remains alive so
-- the game's minigame logic continues to run normally.
-- Selected fish: keep bar visible (hiding it broke the fishing line)
local _selectedFishBarVisibilityConn = nil

    if MiscFlags.FullBright and not KhfreshState.fullBrightApplied then
        pcall(function()
            Lighting.Ambient = Color3.new(1,1,1)
            Lighting.ColorShift_Bottom = Color3.new(1,1,1)
            Lighting.ColorShift_Top = Color3.new(1,1,1)
            Lighting.Brightness = 2
            Lighting.OutdoorAmbient = Color3.new(1,1,1)
            KhfreshState.fullBrightApplied = true
        end)
    elseif not MiscFlags.FullBright and KhfreshState.fullBrightApplied then
        KhfreshState.fullBrightApplied = false
    end
    return true
end

runtimeEnv.KhfreshFrameThread = task.spawn(function()
    while alive() do
        local t0 = os.clock()
        if not updateHubFrameWork(0.08) then break end
        local elapsed = os.clock() - t0
        task.wait(math.max(0.08 - elapsed, 0.02))
    end
end)


-- Redz creates the UI immediately; no separate library Init call is required.

-- ===== FINALIZE & BOOT COMPLETE =====
-- Auto-load already ran at top; re-apply UI after all controls exist.
task.defer(function()
    task.wait(0.35)
    if not alive() then return end

    if type(runtimeEnv.KhfreshResumeServerSearch) == "function" then
        pcall(runtimeEnv.KhfreshResumeServerSearch)
    end

    khAutoSaveEnabled = false
    -- Reset session flags so UI Default matches backend (no phantom ON)
    KhfreshState.autoDoRunning = false
    KhfreshState._ticketFishingApplied = false
    if KhfreshState.AutoFarm then KhfreshState.AutoFarm.enabled = false end

    -- Protection defaults ON only if state says so (toggle Default=true will Callback-sync)
    if Fishing.Flags.AntiAFK ~= false then
        Fishing.Flags.AntiAFK = true
        if initAntiAFK then pcall(initAntiAFK) end
        -- Resume Event/Weather Hop after teleport (getgenv, no file)
        task.defer(function()
            if not alive() then return end
            pcall(function()
                local env = (getgenv and getgenv()) or _G
                local h = env.__KhfreshHop
                if type(h) == "table" then
                    if h.eventEnabled then
                        KhfreshState.EventHop.enabled = true
                        KhfreshState.EventHop.target = tostring(h.eventTarget or KhfreshState.EventHop.target)
                        if type(h.eventTried) == "table" then
                            KhfreshState.EventHop.triedServers = h.eventTried
                        end
                    end
                    if h.weatherEnabled then
                        KhfreshState.WeatherHop.enabled = true
                        KhfreshState.WeatherHop.target = tostring(h.weatherTarget or KhfreshState.WeatherHop.target)
                        if type(h.weatherTried) == "table" then
                            KhfreshState.WeatherHop.triedServers = h.weatherTried
                        end
                    end
                end
            end)
            task.wait(2.5)
            if not alive() then return end
            if KhfreshState.EventHop and KhfreshState.EventHop.enabled then
                local step = KhfreshState._eventHopStep
                if type(step) == "function" then pcall(step) end
            end
            if KhfreshState.WeatherHop and KhfreshState.WeatherHop.enabled then
                local step = KhfreshState._weatherHopStep
                if type(step) == "function" then pcall(step) end
            end
        end)
    end
    if KhfreshState.antiBanEnabled ~= false then
        KhfreshState.antiBanEnabled = true
        if initAntiBan then pcall(initAntiBan) end
    end

    runtimeEnv.AutoFarm = false

    KhfreshLib:Notify({
        Title = "Khfresh Hub",
        Message = "Ready. Config save off. Toggle state reset.",
        Duration = 2
    })
end)

]===============]

function __KhfreshRunHub()
    local chunk, err = loadstring(__KH_HUB_SRC, "@KhfreshHub")
    if not chunk then
        error("Khfresh Hub compile error: " .. tostring(err))
    end
    local ok, runErr = pcall(chunk)
    if not ok then
        error("Khfresh Hub runtime error: " .. tostring(runErr))
    end
end

executeEmbeddedScript = function()
    if not verified then
        return false
    end

    if not FREE_DAY_UTC then
        Status.Text = "● Key verified - loading script..."
        Status.TextColor3 = Color3.fromRGB(112, 220, 148)
        Verify.Text = "LOADING..."
    else
        Status.Text = "● FREE ACCESS • " .. CURRENT_UTC_DAY .. " UTC"
        Status.TextColor3 = Color3.fromRGB(112, 220, 148)
        Verify.Text = "FREE ACCESS"
    end

    local runOk, runErr = pcall(function()
        if type(__KhfreshRunHub) == "function" then
            __KhfreshRunHub()
        else
            error("Hub loader missing")
        end
    end)

    if not runOk then
        Status.Text = "● Embedded script runtime error"
        Status.TextColor3 = Color3.fromRGB(255, 90, 90)
        Verify.Text = "RETRY VERIFY"
        warn("[KHFRESH] Embedded script runtime error:", runErr)
        return false
    end

    Status.Text = "● Script loaded successfully"
    Status.TextColor3 = Color3.fromRGB(112, 220, 148)
    Verify.Text = "ACCESS GRANTED"

    if FREE_DAY_UTC then
        task.delay(0.08, function()
            hideKeySystem()
        end)
    end

    return true
end

--// ============================================================================
--// UTC FREE DAYS
--// Thursday / Friday UTC only: launch directly, no key required.
--// Sunday / Monday / Tuesday / Wednesday UTC: normal key verification.
--// ============================================================================
if FREE_DAY_UTC then
    verified = true
    Status.Text = "● FREE DAY • " .. CURRENT_UTC_DAY .. " UTC"
    Status.TextColor3 = Color3.fromRGB(112, 220, 148)
    Verify.Text = "FREE ACCESS"

    task.delay(0.05, function()
        local ok, err = pcall(function()
            executeEmbeddedScript()
        end)

        if not ok then
            warn("[KHFRESH] Free-day launch failed:", err)
        end
    end)
else
    -- Normal days: key is required. Saved key can still auto-login.
    Status.Text = "● " .. CURRENT_UTC_DAY .. " UTC • KEY REQUIRED"
    Status.TextColor3 = Color3.fromRGB(118, 118, 130)
    autoLoginSavedKey()
end

return Gui
