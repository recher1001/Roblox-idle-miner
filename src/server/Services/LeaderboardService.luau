--!strict
--[[
	LeaderboardService
	==================
	Zwei große Bestenlisten-Tafeln auf dem Platz (Top 10, alle Server):
	  💰 Meistes Geld        (Config.Leaderboards.MoneyStat)
	  💸 Meistes Geld/Sek.   (aktuelles Einkommen pro Sekunde)

	Gespeichert wird in OrderedDataStores. Die akzeptieren nur Ganzzahlen,
	deshalb steht dort log10(Wert) * 1e10 - so passen auch 1e300+ hinein
	und die Reihenfolge bleibt richtig.

	Alle Config.Leaderboards.UpdateInterval Sekunden werden die Werte der
	Spieler auf diesem Server gespeichert und die Top-Liste neu geladen.
	Dazwischen werden die Tafeln alle paar Sekunden mit den Live-Werten der
	anwesenden Spieler aufgefrischt. Ohne DataStore (Studio ohne API-Zugriff)
	zeigen die Tafeln nur die Spieler auf dem Server.

	Zusätzlich gibt es die Spalte "Pro Sek." in der Spielerliste (leaderstats).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)

local DataService = require(script.Parent.DataService)
local SessionService = require(script.Parent.SessionService)
local WorldSetup = require(script.Parent.Parent.World.WorldSetup)

type Session = SessionService.Session

local LeaderboardService = {}

local KEY_SCALE = 1e10
local LIVE_REFRESH = 5

type Row = { Frame: Frame, Rank: TextLabel, Avatar: ImageLabel, Name: TextLabel, Value: TextLabel }
type Board = {
	Id: string,
	Title: string,
	Subtitle: string,
	Color: Color3,
	Value: (Session) -> BigNum.BigNum,
	Format: (BigNum.BigNum) -> string,
	Store: OrderedDataStore?,
	Saved: { [number]: number }, -- UserId -> zuletzt gespeicherter Wert (kodiert)
	Top: { [number]: number }, -- UserId -> Wert aus dem DataStore (kodiert)
	Rows: { Row },
	Status: TextLabel?,
}

local boards: { Board } = {}
local names: { [number]: string } = {}

----------------------------------------------------------------------
-- Kodierung BigNum <-> Ganzzahl
----------------------------------------------------------------------
local function encode(value: BigNum.BigNum): number
	if BigNum.lt(value, BigNum.one()) then
		return 0
	end
	return math.floor(BigNum.log10(value) * KEY_SCALE + 0.5)
end

local function decode(score: number): BigNum.BigNum
	if score <= 0 then
		return BigNum.zero()
	end
	return BigNum.fromLog10(score / KEY_SCALE)
end

----------------------------------------------------------------------
-- Werte
----------------------------------------------------------------------
local function moneyOf(session: Session): BigNum.BigNum
	if Config.Leaderboards.MoneyStat == "Cash" then
		return session.Data.Cash
	end
	return session.Data.TotalCash
end

local function incomeOf(session: Session): BigNum.BigNum
	-- ohne Server-Event, damit Events die Liste nicht verfälschen
	local ctx = SessionService.context(session)
	ctx.EventCashMultiplier = 1
	ctx.EventSpeedMultiplier = 1
	return Formulas.incomePerSecond(session.Data, ctx, false)
end

local function formatMoney(value: BigNum.BigNum): string
	return BigNum.formatMoney(value, Config.CurrencySymbol)
end

local function formatIncome(value: BigNum.BigNum): string
	return BigNum.formatMoney(value, Config.CurrencySymbol) .. "/s"
end

----------------------------------------------------------------------
-- Namen (Anzeigename, mit Cache)
----------------------------------------------------------------------
local function resolveNames(userIds: { number })
	local missing = {}
	for _, id in userIds do
		if not names[id] then
			local player = Players:GetPlayerByUserId(id)
			if player then
				names[id] = player.DisplayName
			elseif id > 0 then
				table.insert(missing, id)
			end
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and type(infos) == "table" then
		for _, info in infos do
			if type(info) == "table" and type(info.Id) == "number" and type(info.DisplayName) == "string" then
				names[info.Id] = info.DisplayName
			end
		end
	end
	for _, id in missing do
		if not names[id] then
			local nameOk, name = pcall(function()
				return Players:GetNameFromUserIdAsync(id)
			end)
			names[id] = if nameOk and type(name) == "string" then name else "Spieler " .. id
		end
	end
end

----------------------------------------------------------------------
-- Tafel-Oberfläche (wird einmal gebaut, danach nur Texte geändert)
----------------------------------------------------------------------
local RANK_COLORS = {
	Color3.fromRGB(255, 196, 0),
	Color3.fromRGB(205, 215, 230),
	Color3.fromRGB(222, 128, 60),
}
local RANK_ICONS = { "🥇", "🥈", "🥉" }

local function text(props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(20, 8, 50)
	for k, v in props do
		(label :: any)[k] = v
	end
	return label
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function buildGui(board: Board, part: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.MaxDistance = 250
	gui.Parent = part

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, -40, 0, 190)
	header.Position = UDim2.fromOffset(20, 16)
	header.BackgroundColor3 = board.Color
	header.Parent = gui
	corner(header, 28)
	local gradient = Instance.new("UIGradient")
	gradient.Color =
		ColorSequence.new(board.Color:Lerp(Color3.new(1, 1, 1), 0.25), board.Color:Lerp(Color3.new(0, 0, 0), 0.3))
	gradient.Rotation = 90
	gradient.Parent = header
	text({
		Size = UDim2.new(1, -40, 0, 112),
		Position = UDim2.fromOffset(20, 12),
		Text = board.Title,
		Parent = header,
	})
	board.Status = text({
		Size = UDim2.new(1, -40, 0, 50),
		Position = UDim2.fromOffset(20, 128),
		Text = board.Subtitle,
		Parent = header,
	})

	local list = Instance.new("Frame")
	list.Size = UDim2.new(1, -40, 1, -240)
	list.Position = UDim2.fromOffset(20, 222)
	list.BackgroundTransparency = 1
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local size = Config.Leaderboards.Size
	local rowHeight = math.floor((1200 - 240 - (size - 1) * 10) / size)
	for i = 1, size do
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(1, 0, 0, rowHeight)
		frame.LayoutOrder = i
		frame.BackgroundColor3 = RANK_COLORS[i] or Color3.fromRGB(110, 70, 240)
		frame.BackgroundTransparency = if i <= 3 then 0.05 else (if i % 2 == 0 then 0.35 else 0.5)
		frame.Parent = list
		corner(frame, 18)
		local rank = text({
			Size = UDim2.new(0, 110, 1, -16),
			Position = UDim2.fromOffset(8, 8),
			Text = RANK_ICONS[i] or ("#" .. i),
			Parent = frame,
		})
		local avatar = Instance.new("ImageLabel")
		avatar.Size = UDim2.fromOffset(rowHeight - 14, rowHeight - 14)
		avatar.Position = UDim2.fromOffset(124, 7)
		avatar.BackgroundColor3 = Color3.fromRGB(30, 16, 80)
		avatar.Image = ""
		avatar.Parent = frame
		corner(avatar, rowHeight)
		local name = text({
			Size = UDim2.new(0.5, -140, 1, -24),
			Position = UDim2.fromOffset(124 + rowHeight, 12),
			Text = "-",
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		local value = text({
			Size = UDim2.new(0.42, -16, 1, -24),
			Position = UDim2.new(1, -16, 0, 12),
			AnchorPoint = Vector2.new(1, 0),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Color3.fromRGB(140, 255, 140),
			Parent = frame,
		})
		table.insert(board.Rows, { Frame = frame, Rank = rank, Avatar = avatar, Name = name, Value = value })
	end
end

----------------------------------------------------------------------
-- Aktualisieren
----------------------------------------------------------------------
local function render(board: Board)
	-- DataStore-Werte + Live-Werte der anwesenden Spieler zusammenführen
	local merged: { [number]: number } = table.clone(board.Top)
	for _, session in SessionService.all() do
		merged[session.Player.UserId] = encode(board.Value(session))
	end
	local entries = {}
	for userId, score in merged do
		if score > 0 then
			table.insert(entries, { UserId = userId, Score = score })
		end
	end
	table.sort(entries, function(a, b)
		if a.Score ~= b.Score then
			return a.Score > b.Score
		end
		return a.UserId < b.UserId
	end)
	local ids = {}
	for i = 1, math.min(#entries, #board.Rows) do
		table.insert(ids, entries[i].UserId)
	end
	resolveNames(ids)
	for i, row in board.Rows do
		local entry = entries[i]
		if entry then
			row.Name.Text = names[entry.UserId] or "?"
			row.Value.Text = board.Format(decode(entry.Score))
			row.Avatar.Image = if entry.UserId > 0
				then string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", entry.UserId)
				else ""
		else
			row.Name.Text = "-"
			row.Value.Text = ""
			row.Avatar.Image = ""
		end
	end
end

--- Werte speichern und Top-Liste neu laden (yieldet)
local function syncStore(board: Board)
	local store = board.Store
	if not store or DataService.isMock() then
		return
	end
	for _, session in SessionService.all() do
		local userId = session.Player.UserId
		local score = encode(board.Value(session))
		if userId > 0 and score > 0 and board.Saved[userId] ~= score then
			local ok, err = pcall(function()
				store:SetAsync(tostring(userId), score)
			end)
			if ok then
				board.Saved[userId] = score
			else
				warn("[Leaderboard] Speichern fehlgeschlagen:", err)
			end
		end
	end
	local ok, result = pcall(function()
		local pages = store:GetSortedAsync(false, Config.Leaderboards.Size)
		return pages:GetCurrentPage()
	end)
	if ok and type(result) == "table" then
		local top: { [number]: number } = {}
		for _, item in result do
			local userId = tonumber(item.key)
			if userId and type(item.value) == "number" then
				top[userId] = item.value
			end
		end
		board.Top = top
	else
		warn("[Leaderboard] Laden fehlgeschlagen:", result)
	end
end

local function updateLeaderstats()
	for _, session in SessionService.all() do
		local folder = session.Player:FindFirstChild("leaderstats")
		if folder then
			local value = folder:FindFirstChild("Pro Sek.")
			if not value then
				local v = Instance.new("StringValue")
				v.Name = "Pro Sek."
				v.Parent = folder
				value = v
			end
			if value and value:IsA("StringValue") then
				value.Value = formatIncome(incomeOf(session))
			end
		end
	end
end

function LeaderboardService.start()
	local version = Config.Leaderboards.StoreVersion
	local function store(id: string): OrderedDataStore?
		local ok, result = pcall(function()
			return DataStoreService:GetOrderedDataStore("IdleMiner_Leaderboard_" .. id .. "_" .. version)
		end)
		return if ok then result else nil
	end
	local moneyTitle = "💰 MEISTES GELD"
	local moneySub = if Config.Leaderboards.MoneyStat == "Cash"
		then "Kontostand • alle Server"
		else "insgesamt verdient • alle Server"
	boards = {
		{
			Id = "Money",
			Title = moneyTitle,
			Subtitle = moneySub,
			Color = Color3.fromRGB(255, 176, 0),
			Value = moneyOf,
			Format = formatMoney,
			Store = store("Money"),
			Saved = {},
			Top = {},
			Rows = {},
			Status = nil,
		},
		{
			Id = "Income",
			Title = "💸 GELD PRO SEKUNDE",
			Subtitle = "aktuelles Einkommen • alle Server",
			Color = Color3.fromRGB(0, 190, 255),
			Value = incomeOf,
			Format = formatIncome,
			Store = store("Income"),
			Saved = {},
			Top = {},
			Rows = {},
			Status = nil,
		},
	}

	task.spawn(function()
		-- warten, bis die Welt (und damit die Tafeln) gebaut ist
		local waited = 0
		while next(WorldSetup.LeaderboardBoards) == nil and waited < 30 do
			waited += task.wait(0.5)
		end
		for _, board in boards do
			local part = WorldSetup.LeaderboardBoards[board.Id]
			if part then
				buildGui(board, part)
			end
		end
		local sinceSync = math.huge
		while true do
			if sinceSync >= Config.Leaderboards.UpdateInterval then
				sinceSync = 0
				for _, board in boards do
					syncStore(board)
				end
			end
			for _, board in boards do
				if #board.Rows > 0 then
					local ok, err = pcall(function()
						render(board)
					end)
					if not ok then
						warn("[Leaderboard]", err)
					end
				end
			end
			updateLeaderstats()
			sinceSync += task.wait(LIVE_REFRESH)
		end
	end)

	-- beim Verlassen ein letztes Mal speichern
	SessionService.onEnd(20, function(session)
		for _, board in boards do
			local s = board.Store
			local userId = session.Player.UserId
			local score = encode(board.Value(session))
			if s and not DataService.isMock() and userId > 0 and score > 0 and board.Saved[userId] ~= score then
				task.spawn(function()
					pcall(function()
						s:SetAsync(tostring(userId), score)
					end)
				end)
			end
			board.Saved[userId] = nil
		end
	end)
end

return LeaderboardService
