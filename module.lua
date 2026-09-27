local Root = Instance.new("ScreenGui")
local CommandList = Instance.new("Frame")
local UICorner = Instance.new("UICorner")
local ListContainer = Instance.new("ScrollingFrame")
local UIListLayout = Instance.new("UIListLayout")
local UIPadding_2 = Instance.new("UIPadding")

local InputBox = Instance.new("Frame")
local Ghost = Instance.new("TextLabel")
local TextBox = Instance.new("TextBox")
local UICorner_2 = Instance.new("UICorner")
local SuggestionCaption = Instance.new("TextLabel")

local CommandListScale = Instance.new("UIScale")
local InputBoxScale = Instance.new("UIScale")

local Players = game.Players
local TweenService = game:GetService("TweenService")
local Run = game.RunService
local UIS = game.UserInputService
local Commands = {}
local CommandArgs = {}

-- === Loop bookkeeping (used by the loop/breakloop/listloops commands) ===
local ActiveLoops = {}
local LoopCounter = 0

local POP_IN_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

function GetPlr()
    local Plr = Players.LocalPlayer
    return Plr
end

function GetChar()
    local Char = GetPlr().Character
    return Char
end

function GetHumanoid()
    local Hum = GetChar().Humanoid
    return Hum
end

function GetHRP()
    local HRP = GetChar().HumanoidRootPart
    return HRP
end

function GetName(Target)
    if not Target then return nil end
    for _, v in next, game:GetService("Players"):GetPlayers() do
        if v.Name:lower():sub(1, #Target) == Target:lower() or v.DisplayName:lower():sub(1, #Target) == Target:lower() then
            return v.Name
        end
    end
end

function GetPlayer(Target)
    if not Target then return nil end
    for _, v in next, game:GetService("Players"):GetPlayers() do
        if v.Name:lower():sub(1, #Target) == Target:lower() or v.DisplayName:lower():sub(1, #Target) == Target:lower() then
            return v
        end
    end
end

function GetCmd(Target)
    if not Target then return nil end
    for i, v in pairs(Commands) do
        if string.find(Target, i) then
            return string.find(Target, i)
        end
    end
end

function NoMoVelocity(cframe)
    for i = 1, 10 do
        GetHRP().CFrame = cframe
        GetHRP().Velocity = Vector3.new(0, 0, 0)
        GetHRP().RotVelocity = Vector3.new(0, 0, 0)
        GetHRP().AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        GetHRP().AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        GetHumanoid():ChangeState(Enum.HumanoidStateType.GettingUp)
        task.wait()
    end
end

function dragify(Frame)
    local dragToggle = nil
    local dragSpeed = .25
    local dragInput = nil
    local dragStart = nil
    local startPos = nil

    local function updateInput(input)
        local Delta = input.Position - dragStart
        local Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + Delta.X, startPos.Y.Scale, startPos.Y.Offset + Delta.Y)
        TweenService:Create(Frame, TweenInfo.new(dragSpeed), {Position = Position}):Play()
    end

    Frame.InputBegan:Connect(function(input)
        if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            dragToggle = true
            dragStart = input.Position
            startPos = Frame.Position
            input.Changed:Connect(function()
                if (input.UserInputState == Enum.UserInputState.End) then
                    dragToggle = false
                end
            end)
        end
    end)

    Frame.InputChanged:Connect(function(input)
        if (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            dragInput = input
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if (input == dragInput and dragToggle) then
            updateInput(input)
        end
    end)
end

local function popIn(frame, scale)
    frame.Visible = true
    scale.Scale = 0.85
    frame.BackgroundTransparency = 1

    if frame:GetAttribute("_origBGTransparency") == nil then
        frame:SetAttribute("_origBGTransparency", frame.BackgroundTransparency == 1 and 0 or frame.BackgroundTransparency)
    end

    local targetTransparency = frame:GetAttribute("_origBGTransparency") or 0

    TweenService:Create(scale, POP_IN_INFO, {Scale = 1}):Play()
    TweenService:Create(frame, POP_IN_INFO, {BackgroundTransparency = targetTransparency}):Play()
end

local function popOut(frame, scale, onDone)
    local tweenScale = TweenService:Create(scale, POP_OUT_INFO, {Scale = 0.85})
    local tweenBG = TweenService:Create(frame, POP_OUT_INFO, {BackgroundTransparency = 1})

    tweenScale:Play()
    tweenBG:Play()

    tweenBG.Completed:Once(function()
        frame.Visible = false
        if onDone then onDone() end
    end)
end

function GetBestMatch(partial)
    if not partial or partial == "" then return nil end
    local lowerPartial = partial:lower()

    if Commands[partial] then
        return partial
    end

    local best = nil

    for name, _ in pairs(Commands) do
        if name:lower():sub(1, #lowerPartial) == lowerPartial then
            if not best or #name < #best then
                best = name
            end
        end
    end

    return best
end

function GetArgCandidates(cmdName, argIndex)
    local defs = CommandArgs[cmdName]
    if not defs then return nil end

    local spec = defs[argIndex]
    if not spec then return nil end

    if spec == "player" then
        local names = {}

        for _, v in next, Players:GetPlayers() do
            table.insert(names, v.Name)

            if v.DisplayName and v.DisplayName ~= "" and v.DisplayName ~= v.Name then
                table.insert(names, v.DisplayName)
            end
        end

        return names
    elseif spec == "command" then
        -- Used by commands like `loop`/`alias` whose argument is itself a command name
        local names = {}

        for name in pairs(Commands) do
            table.insert(names, name)
        end

        return names
    elseif spec == "loop" then
        -- Used by `breakloop` so it can suggest currently active loop ids
        local ids = {}

        for id in pairs(ActiveLoops) do
            table.insert(ids, id)
        end

        return ids
    elseif type(spec) == "function" then
        local ok, result = pcall(spec)
        return ok and result or nil
    elseif type(spec) == "table" then
        return spec
    end

    return nil
end

local function BestMatchFromList(list, partial)
    if not list or partial == "" then return nil end

    local lowerPartial = partial:lower()
    local best = nil

    for _, name in ipairs(list) do
        if name:lower() == lowerPartial then
            return name
        end

        if name:lower():sub(1, #lowerPartial) == lowerPartial then
            if not best or #name < #best then
                best = name
            end
        end
    end

    return best
end

local function SplitWords(text)
    local parts = {}

    for word in text:gmatch("%S+") do
        table.insert(parts, word)
    end

    return parts
end

local function GetSuggestionInfo(text)
    if text == "" then return nil end

    local endsWithSpace = text:sub(-1) == " "
    local parts = SplitWords(text)

    if #parts == 0 then return nil end

    if #parts == 1 and not endsWithSpace then
        return {
            kind = "command",
            typed = parts[1],
            match = GetBestMatch(parts[1])
        }
    end

    local resolvedCmd = GetBestMatch(parts[1])
    if not resolvedCmd then return nil end

    local argIndex, partial, priorArgs

    if endsWithSpace then
        argIndex = #parts
        partial = ""
        priorArgs = {table.unpack(parts, 2, #parts)}
    else
        argIndex = #parts - 1
        partial = parts[#parts]
        priorArgs = {table.unpack(parts, 2, #parts - 1)}
    end

    local candidates = GetArgCandidates(resolvedCmd, argIndex)
    local match = BestMatchFromList(candidates, partial)

    return {
        kind = "arg",
        resolvedCmd = resolvedCmd,
        priorArgs = priorArgs,
        partial = partial,
        match = match
    }
end

local function UpdateSuggestion()
    local text = TextBox.Text
    local info = GetSuggestionInfo(text)

    if not info then
        Ghost.Text = ""
        SuggestionCaption.Text = ""
        SuggestionCaption.Visible = false
        return
    end

    if info.kind == "command" then
        if info.match and #info.match > #info.typed then
            local suffix = info.match:sub(#info.typed + 1)
            Ghost.Text = text .. suffix
            SuggestionCaption.Text = "Enter → " .. info.match
            SuggestionCaption.Visible = true
        elseif info.match then
            Ghost.Text = text
            SuggestionCaption.Text = "Enter → " .. info.match
            SuggestionCaption.Visible = true
        else
            Ghost.Text = ""
            SuggestionCaption.Text = ""
            SuggestionCaption.Visible = false
        end

        return
    end

    if info.partial == "" or not info.match then
        Ghost.Text = text
        SuggestionCaption.Text = ""
        SuggestionCaption.Visible = false
        return
    end

    local suffix = info.match:sub(#info.partial + 1)
    Ghost.Text = text .. suffix

    local prefix = info.resolvedCmd

    if #info.priorArgs > 0 then
        prefix = prefix .. " " .. table.concat(info.priorArgs, " ")
    end

    SuggestionCaption.Text = "Enter → " .. prefix .. " " .. info.match
    SuggestionCaption.Visible = true
end

Root.Name = "Root"
Root.Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui")
Root.ResetOnSpawn = false

CommandList.Name = "CommandList"
CommandList.Parent = Root
CommandList.BackgroundColor3 = Color3.fromRGB(33, 33, 33)
CommandList.BorderColor3 = Color3.fromRGB(0, 0, 0)
CommandList.BorderSizePixel = 0
CommandList.Position = UDim2.new(0.0358422957, 0, 0.0744047612, 0)
CommandList.Size = UDim2.new(0, 200, 0, 300)
CommandList.Visible = false
CommandList.Active = false
CommandList.ClipsDescendants = true

dragify(CommandList)

CommandListScale.Parent = CommandList

UICorner.Parent = CommandList

ListContainer.Name = "ListContainer"
ListContainer.Parent = CommandList
ListContainer.Active = true
ListContainer.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
ListContainer.BackgroundTransparency = 1.000
ListContainer.BorderColor3 = Color3.fromRGB(0, 0, 0)
ListContainer.BorderSizePixel = 0
ListContainer.Size = UDim2.new(0, 200, 0, 300)
ListContainer.ScrollBarThickness = 0

UIListLayout.Parent = ListContainer
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 5)

-- Keep the scrolling frame's canvas in sync with how many commands are registered,
-- since the list now grows with the new utility commands below.
UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    ListContainer.CanvasSize = UDim2.new(0, 0, 0, UIListLayout.AbsoluteContentSize.Y + 20)
end)

UIPadding_2.Parent = ListContainer
UIPadding_2.PaddingLeft = UDim.new(0, 10)
UIPadding_2.PaddingRight = UDim.new(0, 10)
UIPadding_2.PaddingTop = UDim.new(0, 10)

InputBox.Name = "InputBox"
InputBox.Parent = Root
InputBox.BackgroundColor3 = Color3.fromRGB(33, 33, 33)
InputBox.BorderColor3 = Color3.fromRGB(0, 0, 0)
InputBox.BorderSizePixel = 0
InputBox.AnchorPoint = Vector2.new(0.5, 0.5)
InputBox.Position = UDim2.new(0.5, 0, 0.85, 0)
InputBox.Size = UDim2.new(0, 220, 0, 30)
InputBox.Visible = false
InputBox.ClipsDescendants = true

InputBoxScale.Parent = InputBox

UICorner_2.CornerRadius = UDim.new(0, 5)
UICorner_2.Parent = InputBox

Ghost.Name = "Ghost"
Ghost.Parent = InputBox
Ghost.BackgroundTransparency = 1
Ghost.Position = UDim2.new(0, 8, 0, 0)
Ghost.Size = UDim2.new(1, -16, 1, 0)
Ghost.Font = Enum.Font.SourceSans
Ghost.Text = ""
Ghost.TextColor3 = Color3.fromRGB(140, 140, 140)
Ghost.TextSize = 16
Ghost.TextXAlignment = Enum.TextXAlignment.Left
Ghost.TextYAlignment = Enum.TextYAlignment.Center
Ghost.ZIndex = 2

TextBox.Parent = InputBox
TextBox.Active = false
TextBox.BackgroundTransparency = 1
TextBox.BorderSizePixel = 0
TextBox.Position = UDim2.new(0, 8, 0, 0)
TextBox.Size = UDim2.new(1, -16, 1, 0)
TextBox.Font = Enum.Font.SourceSans
TextBox.PlaceholderText = "Type a command..."
TextBox.PlaceholderColor3 = Color3.fromRGB(180, 180, 180)
TextBox.Text = ""
TextBox.TextColor3 = Color3.fromRGB(255, 255, 255)
TextBox.TextScaled = false
TextBox.TextSize = 16
TextBox.TextWrapped = true
TextBox.TextXAlignment = Enum.TextXAlignment.Left
TextBox.TextYAlignment = Enum.TextYAlignment.Center
TextBox.ClearTextOnFocus = false
TextBox.ZIndex = 3

SuggestionCaption.Name = "SuggestionCaption"
SuggestionCaption.Parent = InputBox
SuggestionCaption.AnchorPoint = Vector2.new(0.5, 1)
SuggestionCaption.Position = UDim2.new(0.5, 0, 0, -4)
SuggestionCaption.Size = UDim2.new(1, 0, 0, 18)
SuggestionCaption.BackgroundTransparency = 1
SuggestionCaption.Font = Enum.Font.SourceSansItalic
SuggestionCaption.Text = ""
SuggestionCaption.TextColor3 = Color3.fromRGB(120, 220, 140)
SuggestionCaption.TextSize = 14
SuggestionCaption.TextXAlignment = Enum.TextXAlignment.Center
SuggestionCaption.Visible = false
SuggestionCaption.ZIndex = 3

-- === Toast notification (lightweight in-game feedback for command results) ===
local ToastLabel = Instance.new("TextLabel")
ToastLabel.Name = "Toast"
ToastLabel.Parent = Root
ToastLabel.AnchorPoint = Vector2.new(0.5, 1)
ToastLabel.Position = UDim2.new(0.5, 0, 0.8, -10)
ToastLabel.Size = UDim2.new(0, 320, 0, 24)
ToastLabel.BackgroundTransparency = 1
ToastLabel.TextTransparency = 1
ToastLabel.Font = Enum.Font.SourceSansBold
ToastLabel.TextColor3 = Color3.fromRGB(120, 220, 140)
ToastLabel.TextSize = 16
ToastLabel.Text = ""
ToastLabel.TextXAlignment = Enum.TextXAlignment.Center
ToastLabel.TextWrapped = true
ToastLabel.ZIndex = 5

local toastToken = 0
local function Toast(text, duration)
    duration = duration or 1.5
    toastToken += 1
    local myToken = toastToken

    ToastLabel.Text = text
    TweenService:Create(ToastLabel, TweenInfo.new(0.15), {TextTransparency = 0}):Play()

    task.delay(duration, function()
        if myToken ~= toastToken then return end
        TweenService:Create(ToastLabel, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
    end)
end

UIS.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.Quote then
        if CommandList.Visible then
            popOut(CommandList, CommandListScale)
        else
            popIn(CommandList, CommandListScale)
        end
    end
end)

UIS.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.Semicolon then
        if not InputBox.Visible then
            popIn(InputBox, InputBoxScale)
        end

        task.wait(0.05)
        TextBox:CaptureFocus()
    end
end)

UIS.InputBegan:Connect(function(input, gameProcessed)
    if input.KeyCode == Enum.KeyCode.Escape then
        if TextBox:IsFocused() then
            TextBox:ReleaseFocus()
        end

        if CommandList.Visible then
            popOut(CommandList, CommandListScale)
        end
    end
end)

UIS.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Tab and TextBox:IsFocused() then
        local info = GetSuggestionInfo(TextBox.Text)

        if not info then return end

        if info.kind == "command" and info.match then
            TextBox.Text = info.match .. " "
        elseif info.kind == "arg" and info.match then
            local prefix = info.resolvedCmd

            if #info.priorArgs > 0 then
                prefix = prefix .. " " .. table.concat(info.priorArgs, " ")
            end

            TextBox.Text = prefix .. " " .. info.match .. " "
        end
    end
end)

TextBox:GetPropertyChangedSignal("Text"):Connect(UpdateSuggestion)

function CommandsADD(Name, Function, ArgSpecs)
    local Item = Instance.new("TextLabel")
    local UIPadding = Instance.new("UIPadding")

    Commands[Name] = Function

    if ArgSpecs then
        CommandArgs[Name] = ArgSpecs
    end

    Item.Name = Name .. " Item"
    Item.Parent = ListContainer
    Item.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    Item.BackgroundTransparency = 1.000
    Item.BorderColor3 = Color3.fromRGB(0, 0, 0)
    Item.BorderSizePixel = 0
    Item.Size = UDim2.new(1, 0, 0, 25)
    Item.Font = Enum.Font.SourceSans
    Item.Text = Name
    Item.TextColor3 = Color3.fromRGB(255, 255, 255)
    Item.TextSize = 20.000
    Item.TextStrokeColor3 = Color3.fromRGB(85, 85, 85)
    Item.TextStrokeTransparency = 0.000
    Item.TextWrapped = true

    UIPadding.Parent = Item
    UIPadding.PaddingLeft = UDim.new(0, 10)
end

-- === Utility commands ===

-- loop <interval> <command> [args...]
-- Repeats an existing command on a fixed interval until stopped with breakloop/breakloopall.
CommandsADD("loop", function(interval, cmdName, ...)
    local seconds = tonumber(interval)

    if not seconds or not cmdName then
        Toast("Usage: loop <seconds> <command> [args...]", 2.5)
        return
    end

    local resolved = GetBestMatch(cmdName)
    if not resolved or not Commands[resolved] then
        Toast("Unknown command: " .. tostring(cmdName), 2)
        return
    end

    local cmdArgs = {...}

    LoopCounter += 1
    local loopId = "loop" .. LoopCounter
    ActiveLoops[loopId] = true

    task.spawn(function()
        while ActiveLoops[loopId] do
            local ok, err = pcall(Commands[resolved], unpack(cmdArgs))
            if not ok then
                warn("[Loop " .. loopId .. "] Error: " .. tostring(err))
            end
            task.wait(seconds)
        end
    end)

    print("[Loop] Started " .. loopId .. " running '" .. resolved .. "' every " .. seconds .. "s")
    Toast("Started " .. loopId .. " (" .. resolved .. " every " .. seconds .. "s)", 2)
end, {nil, "command"})

-- breakloop <id>
-- Stops one specific loop started with `loop`.
CommandsADD("breakloop", function(loopId)
    if loopId and ActiveLoops[loopId] then
        ActiveLoops[loopId] = nil
        print("[Loop] Stopped " .. loopId)
        Toast("Stopped " .. loopId, 1.5)
    else
        Toast("No active loop named " .. tostring(loopId), 1.5)
    end
end, {"loop"})

-- breakloopall
-- Stops every currently running loop.
CommandsADD("breakloopall", function()
    local count = 0

    for id in pairs(ActiveLoops) do
        ActiveLoops[id] = nil
        count += 1
    end

    print("[Loop] Stopped " .. count .. " loop(s)")
    Toast("Stopped " .. count .. " loop(s)", 1.5)
end)

-- listloops
-- Shows the ids of all currently running loops.
CommandsADD("listloops", function()
    local ids = {}

    for id in pairs(ActiveLoops) do
        table.insert(ids, id)
    end

    table.sort(ids)

    if #ids == 0 then
        Toast("No active loops", 1.5)
    else
        Toast("Active: " .. table.concat(ids, ", "), 2.5)
    end
end)

-- wait <seconds>
-- Simple delay, mainly useful as a building block for aliases.
CommandsADD("wait", function(seconds)
    local s = tonumber(seconds) or 1
    task.wait(s)
    Toast("Resumed after " .. s .. "s", 1.5)
end)

-- echo <text...>
-- Prints and toasts arbitrary text, handy for testing binds/aliases.
CommandsADD("echo", function(...)
    local text = table.concat({...}, " ")
    print("[Echo] " .. text)
    Toast(text, 2)
end)

-- help
-- Lists every registered command name to the developer console.
CommandsADD("help", function()
    local names = {}

    for name in pairs(Commands) do
        table.insert(names, name)
    end

    table.sort(names)

    print("[Help] Available commands: " .. table.concat(names, ", "))
    Toast("Command list printed to console (F9)", 2)
end)

-- alias <new> <existing>
-- Registers a new command name that runs an already-existing command.
CommandsADD("alias", function(newName, existingName)
    if not newName or not existingName then
        Toast("Usage: alias <new> <existing>", 2)
        return
    end

    local resolved = GetBestMatch(existingName)
    if not resolved or not Commands[resolved] then
        Toast("Unknown command: " .. tostring(existingName), 2)
        return
    end

    CommandsADD(newName, Commands[resolved], CommandArgs[resolved])
    print("[Alias] " .. newName .. " -> " .. resolved)
    Toast("Alias created: " .. newName .. " -> " .. resolved, 2)
end, {nil, "command"})

-- clear
-- Dismisses the current toast immediately.
CommandsADD("clear", function()
    toastToken += 1
    TweenService:Create(ToastLabel, TweenInfo.new(0.1), {TextTransparency = 1}):Play()
end)

TextBox.FocusLost:Connect(function(enterPressed)
    local oldText = TextBox.Text

    TextBox.Text = ""
    Ghost.Text = ""
    SuggestionCaption.Text = ""
    SuggestionCaption.Visible = false

    if enterPressed and oldText ~= "" then
        local TextString = SplitWords(oldText)
        local Name = TextString[1]
        local Args = {table.unpack(TextString, 2)}

        local resolved = GetBestMatch(Name) or Name

        if resolved and Commands[resolved] then
            -- Run off the UI thread so `wait`/`loop` (or a bug in any command)
            -- can never freeze the input box, and catch errors so one bad
            -- command can't break the whole console.
            task.spawn(function()
                local ok, err = pcall(Commands[resolved], unpack(Args))
                if not ok then
                    warn("[Command Error] " .. tostring(err))
                    Toast("Error running '" .. resolved .. "'", 2)
                end
            end)
        else
            Toast("Unknown command: " .. tostring(Name), 1.5)
        end
    end

    if InputBox.Visible then
        popOut(InputBox, InputBoxScale)
    end
end)
