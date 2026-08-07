--[[
  UNDETEK — open source / non-obfusqué
  Secours de France RP + AC Probe (optionnel)
  PlaceId 8392374718 · v1.4.9
  AC-aware: propulsion client soft (pas de Body* legacy)
  v1.4.9: Improve-loop — Car Speed look horizontal · Beauty↔FPS restore ·
    steer quasi-arret · flyConn sans leak track · remote miss-cache ·
    newcclosure fallback AC · Silent vs Aimbot gate · UI Info allégée
  v1.4.8: AC probe friction loop — plus de `continue` (compat executor fragile)
  v1.4.7: Lock/Unlock retirés · FOV caméra · Beauty pack (GFX soft) à l'exec
  v1.4.6: Propulsion → Car Speed · Motor mode (Smooth/Normal/Sport) · Accélération UI retirée
  v1.4.5: AC probe intégré (Info > AC Probe, OFF par défaut) — un seul exec
  v1.4.4: Fly perso retiré (instable) — fly voiture only (soft-cap).
  Combat: ESP + Aimbot damp+FOV · Silent LMB assist · Cuff aura (Handcuff_Function)
  Vehicule: Car Speed + Motor mode + steer · fly car CFrame/ALV · Repair/Fuel/Bring
  Boot: UI + mild renderBoost + Beauty pack (pas de wipe / FPS Pack = manuel).
  Unload: getgenv().UNDETEK_SF_UNLOAD() ou Info > UNLOAD
  Discord: https://discord.gg/cgRsTMUa9J
]]

do
  local allowed = { "8392374718" }
  local ok = false
  local pid = tostring(game.PlaceId)
  for _, id in ipairs(allowed) do
    if pid == id then ok = true break end
  end
  if not ok and not (getgenv and getgenv().__XHUB_FORCE) then
    warn("[UNDETEK] Secours: wrong PlaceId (" .. pid .. ")")
    return
  end
end

do
  local env = (typeof(getgenv) == "function" and getgenv()) or _G
  local lock = "XHubSecoursFrance_" .. tostring(game.PlaceId)
  if env[lock] == true then
    warn("[UNDETEK] Secours already loaded")
    return
  end
  env[lock] = true
  env.__XHUB_SECOURS_UNLOAD = function()
    env[lock] = nil
    if env.__XHUB_SECOURS_CLEAN then pcall(env.__XHUB_SECOURS_CLEAN) end
  end
  env.UNDETEK_SF_UNLOAD = env.__XHUB_SECOURS_UNLOAD
end

local UIS = game:GetService("UserInputService")
local RunS = game:GetService("RunService")
local Players = game:GetService("Players")
local WS = workspace
local RS = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer
local Camera = WS.CurrentCamera
local VERSION = "1.4.9"

local M = { conns = {}, touch = {}, esp = {}, rf = {}, ac = { on = false, conns = {} } }
M._hasDrawing = (Drawing ~= nil)
M.state = {
  -- Car Speed (ex-propulsion). Motor mode = Smooth/Normal/Sport. Pas de slider Accélération (inutile).
  propulsion = false, power = 95, accelMode = "Normal", _speed = 0,
  steerAssist = true,
  steerForce = 0.7,
  steerMaxSpeed = 38,
  steerMinSpeed = 2,
  steerCurve = "Smooth",
  steerMode = "Hybrid",
  steerLatDamp = true,
  flyCar = false, flyCarSpeed = 90, flyCarSlow = 28, slowFly = false,
  bodyColor = Color3.fromRGB(220, 38, 38), rainbow = false, rainbowSpeed = 4,
  fpsPack = false, beautyPack = true, renderBoost = true, decorClean = false,
  fov = 70,
  aimbot = false, aimFov = 140, aimSmooth = 0.28, aimPart = "Head", aimVisible = true,
  aimFovCircle = true,
  silentAssist = false, silentFov = 180,
  cuffAura = false, cuffRange = 12, cuffInterval = 0.8,
  espBox = false, espName = false, espHealth = false, espDistance = false, espTracer = false,
  espMaxDist = 1200, espTeamCheck = false, espColor = Color3.fromRGB(220, 50, 50),
  espTeamColor = Color3.fromRGB(60, 140, 255),
  acProbe = false,
  tab = "Vehicule",
}

local function track(c)
  if c then table.insert(M.conns, c) end
  return c
end

-- Notifications OFF by default (were spamming on every toggle).
-- Set getgenv().UNDETEK_SECOURS_TOAST = true to re-enable rare toasts.
local function toast(_title, _text)
  local env = (typeof(getgenv) == "function" and getgenv()) or _G
  if env.UNDETEK_SECOURS_TOAST ~= true then return end
  pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
      Title = _title, Text = _text, Duration = 1.5,
    })
  end)
end

-- #region agent log
-- Debug logging OFF by default (HTTP/writefile spam = lag). Enable: getgenv().UNDETEK_SF_DBG = true
local __DBG_URL = "http://127.0.0.1:7839/ingest/bc9b9cea-368b-46f8-a502-c70b8776efb2"
local function agentLog(hypothesisId, location, message, data)
  local env = (typeof(getgenv) == "function" and getgenv()) or _G
  if env.UNDETEK_SF_DBG ~= true then
    M._lastDbg = tostring(hypothesisId) .. "|" .. tostring(location) .. "|" .. tostring(message)
    return
  end
  pcall(function()
    local payload = {
      sessionId = "68cbc4",
      runId = "secours-stable",
      hypothesisId = tostring(hypothesisId or "?"),
      location = tostring(location or "?"),
      message = tostring(message or ""),
      data = data or {},
      timestamp = os.time() * 1000,
    }
    local body = game:GetService("HttpService"):JSONEncode(payload)
    print("[SF-DBG]", hypothesisId, location, message)
    if appendfile then pcall(appendfile, "sf_dbg_68cbc4.ndjson", body .. "\n") end
    local req = (syn and syn.request) or http_request or request
    if typeof(req) == "function" then
      req({
        Url = __DBG_URL,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json", ["X-Debug-Session-Id"] = "68cbc4" },
        Body = body,
      })
    end
    M._lastDbg = tostring(hypothesisId) .. "|" .. tostring(location) .. "|" .. tostring(message)
  end)
end
-- #endregion

local function getChar(plr)
  plr = plr or LocalPlayer
  return plr.Character
end
local function getHum(plr)
  local c = getChar(plr)
  return c and c:FindFirstChildOfClass("Humanoid")
end
local function getRoot(plr)
  local c = getChar(plr)
  return c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart)
end
local function alive(plr)
  local h = getHum(plr)
  return h and h.Health > 0
end

-- ── Remotes ──────────────────────────────────────────────────────
function M.getInstanceFolder()
  if M._instFolder and M._instFolder.Parent then return M._instFolder end
  local ok, folder = pcall(function()
    local sm = require(RS:WaitForChild("SharedServices"):WaitForChild("ServiceManager"))
    return sm:GetService("Instance")
  end)
  if ok and folder then
    M._instFolder = folder
    return folder
  end
  return nil
end

function M.getRemote(name)
  local cached = M.rf[name]
  if cached and cached.Parent then return cached end
  M.rfMiss = M.rfMiss or {}
  local missAt = M.rfMiss[name]
  if missAt and (tick() - missAt) < 4 then return nil end -- evite WaitForChild spam
  local folder = M.getInstanceFolder()
  if folder then
    local r = folder:FindFirstChild(name)
    if not r then
      local ok, waited = pcall(function()
        return folder:WaitForChild(name, 0.6)
      end)
      if ok then r = waited end
    end
    if r and (r:IsA("RemoteFunction") or r:IsA("RemoteEvent")) then
      M.rf[name] = r
      M.rfMiss[name] = nil
      return r
    end
  end
  for _, d in ipairs(RS:GetDescendants()) do
    if d.Name == name and (d:IsA("RemoteFunction") or d:IsA("RemoteEvent")) then
      M.rf[name] = d
      M.rfMiss[name] = nil
      return d
    end
  end
  M.rfMiss[name] = tick()
  return nil
end

function M.carInvoke(action, ...)
  local rf = M.getRemote("Car_Function")
  if not rf then toast("Car", "Car_Function introuvable"); return end
  local args = { ... }
  pcall(function()
    if #args > 0 then
      local unpackFn = table.unpack or unpack
      rf:InvokeServer(action, unpackFn(args))
    else
      rf:InvokeServer(action)
    end
  end)
end

function M.handcuffInvoke(action, targetName)
  local rf = M.getRemote("Handcuff_Function")
  if not rf then return false end
  local ok = pcall(function()
    if targetName then rf:InvokeServer(action, targetName) else rf:InvokeServer(action) end
  end)
  return ok
end

-- ── Car resolve ──────────────────────────────────────────────────
function M.isCar(m)
  return typeof(m) == "Instance" and m:IsA("Model") and m:FindFirstChild("DriveSeat") ~= nil
end

function M.getSeatedCar()
  local char = LocalPlayer.Character
  if not char then return nil end
  local hum = char:FindFirstChildOfClass("Humanoid")
  if not hum or not hum.SeatPart then return nil end
  local m = hum.SeatPart:FindFirstAncestorWhichIsA("Model")
  while m and not m:FindFirstChild("DriveSeat") do
    m = m:FindFirstAncestorWhichIsA("Model")
  end
  return m
end

function M.getOwnedCar()
  local name = LocalPlayer.Name .. "'s Car"
  local m = WS:FindFirstChild(name)
  if M.isCar(m) then return m end
  local hum = getHum()
  for _, ch in ipairs(WS:GetChildren()) do
    if M.isCar(ch) then
      if ch.Name:find(LocalPlayer.Name, 1, true) then return ch end
      local seat = ch:FindFirstChild("DriveSeat")
      if hum and seat and seat:IsA("VehicleSeat") and seat.Occupant == hum then
        return ch
      end
      -- AC6 Values ownership hints
      local vals = seat and seat:FindFirstChild("Values")
      if vals then
        local owner = vals:FindFirstChild("Owner") or vals:FindFirstChild("Player")
        if owner and typeof(owner.Value) == "string" and owner.Value == LocalPlayer.Name then
          return ch
        end
        if owner and typeof(owner.Value) == "Instance" and owner.Value == LocalPlayer then
          return ch
        end
      end
      local attrOwner = nil
      pcall(function() attrOwner = ch:GetAttribute("Owner") end)
      if attrOwner == LocalPlayer.Name or attrOwner == LocalPlayer.UserId then
        return ch
      end
    end
  end
  return nil
end

function M.currentCar()
  local seated = M.getSeatedCar()
  if seated then return seated, true end
  return M.getOwnedCar(), false
end

function M.carRoot(car)
  if not car then return nil end
  local seat = car:FindFirstChild("DriveSeat")
  if seat and seat:IsA("BasePart") then return seat.AssemblyRootPart or seat end
  return car.PrimaryPart or car:FindFirstChildWhichIsA("BasePart", true)
end

function M.carValues(car)
  local seat = car and car:FindFirstChild("DriveSeat")
  return seat and seat:FindFirstChild("Values")
end

function M.carInput()
  local thr, steer = 0, 0
  if UIS:IsKeyDown(Enum.KeyCode.W) or UIS:IsKeyDown(Enum.KeyCode.Up) or M.touch.fwd then thr = 1
  elseif UIS:IsKeyDown(Enum.KeyCode.S) or UIS:IsKeyDown(Enum.KeyCode.Down) or M.touch.back then thr = -1 end
  if UIS:IsKeyDown(Enum.KeyCode.A) or M.touch.left then steer = -1
  elseif UIS:IsKeyDown(Enum.KeyCode.D) or M.touch.right then steer = 1 end
  return thr, steer
end

-- ── Paint STRICT ─────────────────────────────────────────────────
local SKIP = {
  "glass", "vitre", "window", "windshield", "parebrise", "verre",
  "wheel", "rim", "jante", "tire", "tyre", "pneu", "roue",
  "light", "lumiere", "phare", "feu", "headlight", "taillight", "blinker", "clignotant", "gyro", "gyrophare", "siren",
  "mirror", "retro", "logo", "badge", "emblem", "sticker", "decal", "grille", "grill",
  "exhaust", "echappement", "plate", "plaque", "immat", "neon", "handle", "chrome",
  "interior", "interieur", "seat", "siege", "steering", "volant", "dash", "brancard",
  "humanoid", "head", "torso", "arm", "leg", "hand", "foot",
}

local function nameHas(n, words)
  for _, w in ipairs(words) do if n:find(w, 1, true) then return true end end
  return false
end

local function isSkipPart(p)
  local n = p.Name:lower()
  if nameHas(n, SKIP) then return true end
  if p.Material == Enum.Material.Glass or p.Material == Enum.Material.Neon or p.Material == Enum.Material.ForceField then return true end
  if p.Transparency >= 0.45 then return true end
  local model = p:FindFirstAncestorOfClass("Model")
  if model and model:FindFirstChildOfClass("Humanoid") then return true end
  for _, ch in ipairs(p:GetChildren()) do
    if ch:IsA("Decal") or ch:IsA("Texture") or ch:IsA("SurfaceAppearance") then return true end
  end
  return false
end

function M.bodyPaintParts(car)
  local body = {}
  if not car then return body end
  for _, p in ipairs(car:GetDescendants()) do
    if p:IsA("BasePart") and not isSkipPart(p) then
      local under = false
      local anc = p
      while anc and anc ~= car do
        local nm = string.lower(tostring(anc.Name))
        if nm:find("carrosserie", 1, true) or nm:find("body", 1, true) then under = true break end
        anc = anc.Parent
      end
      local editable = false
      pcall(function() editable = p:GetAttribute("Editable") == true end)
      if under or editable then table.insert(body, p) end
    end
  end
  return body
end

function M.applyBodyPaint(color, silent)
  local car = select(1, M.currentCar())
  if not car then if not silent then toast("Couleur", "Aucun véhicule") end return end
  local parts = M.bodyPaintParts(car)
  if #parts == 0 then if not silent then toast("Couleur", "Pas de Carrosserie/Editable") end return end
  for _, p in ipairs(parts) do pcall(function() p.Color = color end) end
  if not silent then toast("Couleur", #parts .. " panneaux") end
end

function M.startRainbow()
  if M._rainbowRunning then return end
  M._rainbowRunning = true
  task.spawn(function()
    local hue = 0
    while M.state.rainbow do
      hue = (hue + 0.025 * M.state.rainbowSpeed) % 1
      M.applyBodyPaint(Color3.fromHSV(hue, 0.85, 1), true)
      task.wait(0.35)
    end
    M._rainbowRunning = false
  end)
end

-- ── Car Speed + Steer (steer independant de Car Speed) ───────────
-- Motor mode (Smooth/Normal/Sport) module la rampe interne; pas de contrôle Accélération exposé.
function M.stepPropulsion(dt, car, root, values)
  if not M.state.propulsion then M.state._speed = 0; return end
  local gear = values and values:FindFirstChild("Gear")
  if gear and gear.Value < 0 then M.state._speed = 0; return end
  local throttleAmt = 0
  local throttle = values and values:FindFirstChild("Throttle")
  if throttle then throttleAmt = math.clamp(throttle.Value, 0, 1)
  elseif UIS:IsKeyDown(Enum.KeyCode.W) or UIS:IsKeyDown(Enum.KeyCode.Up) then throttleAmt = 1 end
  local power = math.clamp(M.state.power, 20, 180)
  local mode = M.state.accelMode
  local baseRamp = 220 -- fixe (ex-slider Accélération retiré — ne changeait rien d'utile)
  local target, rampUp, rampDown
  if mode == "Smooth" then target = power * throttleAmt; rampUp = baseRamp * 0.45; rampDown = baseRamp
  elseif mode == "Sport" then target = power * throttleAmt; rampUp = baseRamp * 1.6; rampDown = baseRamp * 1.6
  else target = power * throttleAmt; rampUp = baseRamp; rampDown = baseRamp * 1.8 end
  if M.state._speed < target then M.state._speed = math.min(target, M.state._speed + rampUp * dt)
  else M.state._speed = math.max(target, M.state._speed - rampDown * dt) end
  if M.state._speed > 0.1 then
    local vel = root.AssemblyLinearVelocity
    -- Look horizontal only — LookVector.Y en pente = "jump" involontaire / friction AC
    local look3 = root.CFrame.LookVector
    local look = Vector3.new(look3.X, 0, look3.Z)
    if look.Magnitude < 0.05 then return end
    look = look.Unit
    local fwd = vel:Dot(look)
    if fwd < M.state._speed then
      pcall(function()
        local add = look * (M.state._speed - fwd)
        root.AssemblyLinearVelocity = Vector3.new(vel.X + add.X, vel.Y, vel.Z + add.Z)
      end)
    end
  end
end

-- Master vehicle tick: une seule passe assis (prop + steer), pas de double Heartbeat
function M.stepVehicle(dt)
  if M.state.flyCar then
    M.state._speed = 0
    return
  end
  local car = M.getSeatedCar()
  if not car then
    M.state._speed = 0
    return
  end
  local root = M.carRoot(car)
  if not root then
    M.state._speed = 0
    return
  end
  local values = M.carValues(car)
  M.stepPropulsion(dt, car, root, values)
  if M.state.steerAssist then
    M.stepSteerAssist(car, root, values, dt)
  end
end

function M.steerFalloff(speed)
  local minS = M.state.steerMinSpeed or 2
  local maxS = math.max(M.state.steerMaxSpeed or 38, minS + 1)
  -- Assist leger au quasi-arret (demarrage virage) — avant: 0 sous minS = steer mort
  if speed < minS then
    return math.clamp(0.35 + (speed / math.max(minS, 0.01)) * 0.35, 0.35, 0.7)
  end
  if speed >= maxS then return 0 end
  local t = (speed - minS) / (maxS - minS) -- 0 at min, 1 at max
  local curve = M.state.steerCurve or "Smooth"
  if curve == "LowOnly" then
    -- plein jusqu'à ~40% de la plage, puis chute nette
    if t < 0.35 then return 1 end
    return math.clamp(1 - ((t - 0.35) / 0.65) ^ 0.7, 0, 1)
  elseif curve == "Linear" then
    return 1 - t
  else -- Smooth: reste utile un peu au milieu, mort à haute vitesse
    local x = 1 - t
    return x * x -- quadratic falloff
  end
end

function M.stepSteerAssist(car, root, values, dt)
  local _, steer = M.carInput()
  if steer == 0 then
    -- léger frein de lacet pour stabiliser après virage
    pcall(function()
      local av = root.AssemblyAngularVelocity
      root.AssemblyAngularVelocity = Vector3.new(av.X, av.Y * 0.88, av.Z)
    end)
    return
  end

  local speed = root.AssemblyLinearVelocity.Magnitude
  local fall = M.steerFalloff(speed)
  if fall <= 0.01 then return end

  local force = math.clamp(M.state.steerForce or 0.7, 0.1, 2.0)
  local amount = steer * force * fall -- -1..1 scaled
  local mode = M.state.steerMode or "Hybrid"

  -- 1) Steer input jeu (AC6) — principal, stable
  if mode == "Steer" or mode == "Hybrid" then
    local seat = car:FindFirstChild("DriveSeat")
    if seat and seat:IsA("VehicleSeat") then
      pcall(function()
        local cur = seat.SteerFloat
        seat.SteerFloat = cur + (amount - cur) * math.clamp(dt * 14, 0, 1)
      end)
    end
    local sv = values and (values:FindFirstChild("Steer") or values:FindFirstChild("Steering"))
    if sv and typeof(sv.Value) == "number" then
      pcall(function()
        sv.Value = sv.Value + (amount - sv.Value) * math.clamp(dt * 14, 0, 1)
      end)
    end
  end

  -- 2) Soft yaw — seulement si fall élevé (basse vitesse), plafonné
  if mode == "Yaw" or mode == "Hybrid" then
    local yawCap = 1.15 * force * fall -- max rad/s-ish scale
    local targetYaw = -amount * yawCap
    pcall(function()
      local av = root.AssemblyAngularVelocity
      local ny = av.Y + (targetYaw - av.Y) * math.clamp(dt * 6, 0, 1)
      -- hard clamp anti-spin
      ny = math.clamp(ny, -2.2, 2.2)
      root.AssemblyAngularVelocity = Vector3.new(av.X * 0.95, ny, av.Z * 0.95)
    end)
  end

  -- 3) Damp latéral seulement à basse/moyenne vitesse (réduit drift)
  if M.state.steerLatDamp and fall > 0.25 then
    pcall(function()
      local vel = root.AssemblyLinearVelocity
      local look3 = root.CFrame.LookVector
      local look = Vector3.new(look3.X, 0, look3.Z)
      if look.Magnitude < 0.05 then return end
      look = look.Unit
      local right = Vector3.new(root.CFrame.RightVector.X, 0, root.CFrame.RightVector.Z)
      if right.Magnitude < 0.05 then return end
      right = right.Unit
      local fwd = look * vel:Dot(look)
      local lat = right * vel:Dot(right)
      local keep = 1 - (0.35 * fall) -- plus on est lent, plus on coupe le latéral
      local flat = fwd + lat * keep
      root.AssemblyLinearVelocity = Vector3.new(flat.X, vel.Y, flat.Z)
    end)
  end
end

-- ── Fly Car (AC-safe) ────────────────────────────────────────────
local FLY_CAR_SPEED_MAX = 110

function M.setFlyCar(on)
  on = on == true
  if on == M.state.flyCar then return end
  M.state.flyCar = on
  -- Connexion gérée hors M.conns (évite accumulation ghost à chaque toggle ON/OFF)
  if M._flyConn then pcall(function() M._flyConn:Disconnect() end); M._flyConn = nil end
  if not on then
    pcall(function() UIS.MouseBehavior = Enum.MouseBehavior.Default; UIS.MouseIconEnabled = true end)
    toast("Fly Car", "OFF"); M.refreshUi(); return
  end
  M.state.flyCarSpeed = math.clamp(M.state.flyCarSpeed, 40, FLY_CAR_SPEED_MAX)
  M.state.flyCarSlow = math.clamp(M.state.flyCarSlow, 12, 40)
  toast("Fly Car", "ON (soft-cap " .. tostring(M.state.flyCarSpeed) .. ")")
  M._flyConn = RunS.RenderStepped:Connect(function(dt)
    if not M.state.flyCar then return end
    if not UIS.TouchEnabled then
      pcall(function() UIS.MouseBehavior = Enum.MouseBehavior.LockCenter; UIS.MouseIconEnabled = false end)
    end
    local car = M.getSeatedCar() or select(1, M.currentCar())
    local root = car and M.carRoot(car)
    if not root then return end
    local cam = Camera or WS.CurrentCamera
    if not cam then return end
    local thr, steer = M.carInput()
    local move = cam.CFrame.LookVector * thr + cam.CFrame.RightVector * steer
    if UIS:IsKeyDown(Enum.KeyCode.Space) then move = move + Vector3.yAxis end
    if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then move = move - Vector3.yAxis end
    local slow = M.state.slowFly or UIS:IsKeyDown(Enum.KeyCode.LeftAlt)
    local spd = math.min(slow and M.state.flyCarSlow or M.state.flyCarSpeed, FLY_CAR_SPEED_MAX)
    -- soft ramp (pas teleport); vitesse plafonnée
    local target = (move.Magnitude > 0.05) and (move.Unit * spd) or Vector3.zero
    local accel = (move.Magnitude > 0.05) and 8 or 5
    local blended = root.AssemblyLinearVelocity:Lerp(target, math.clamp(dt * accel, 0, 1))
    pcall(function()
      root.AssemblyLinearVelocity = blended
      root.AssemblyAngularVelocity = Vector3.zero
      local look = cam.CFrame.LookVector
      local flat = Vector3.new(look.X, 0, look.Z)
      if flat.Magnitude > 0.05 then
        root.CFrame = root.CFrame:Lerp(CFrame.lookAt(root.Position, root.Position + flat.Unit), math.clamp(dt * 6, 0, 1))
      end
    end)
  end)
  M.refreshUi()
end

function M.toggleFlySmart()
  if M.getSeatedCar() then
    M.setFlyCar(not M.state.flyCar)
  else
    toast("Fly", "Fly voiture only — monte en voiture.")
  end
end

function M.bringCar()
  local car = M.getOwnedCar()
  local hrp = getRoot()
  if not car or not hrp then toast("Bring", "Voiture/perso introuvable"); return end
  local cf = hrp.CFrame * CFrame.new(0, 1, -12)
  pcall(function()
    if car.PivotTo then car:PivotTo(cf) else
      local root = M.carRoot(car)
      if root then root.CFrame = cf end
    end
  end)
  toast("Bring", "Voiture amenée")
end

-- ── Render / FPS / Decor wipe ────────────────────────────────────
function M.applyRenderBoost(on)
  M.state.renderBoost = on == true
  if not on then
    M._streamKeep = false
    return
  end
  -- LIGHT only — gros StreamingTarget + wipe map = freeze / micro-lag
  pcall(function()
    -- Beauty pack gère le look Lighting ; ne pas casser les ombres si beauté ON
    if not M.state.beautyPack then
      Lighting.FogEnd = math.max(Lighting.FogEnd, 2000)
      Lighting.GlobalShadows = false
    end
  end)
  pcall(function()
    if typeof(WS.StreamingMinRadius) == "number" then
      WS.StreamingMinRadius = math.clamp(math.max(WS.StreamingMinRadius, 256), 64, 512)
    end
    if typeof(WS.StreamingTargetRadius) == "number" then
      -- ne pas monter à 2048 (force le jeu à stream trop d'objets = lag)
      WS.StreamingTargetRadius = math.clamp(math.max(WS.StreamingTargetRadius, 384), 128, 768)
    end
  end)
  if setfpscap then pcall(function() setfpscap(240) end) end
end

-- Mots décor / train (match Name:lower). Jamais DriveChair / DriveSeat / voiture joueur.
local DECOR_WORDS = {
  "tree", "arbre", "poteau", "bush", "buisson", "plant", "plante", "planter",
  "chair", "banc", "bench", "fence", "barriere", "barrière",
  "lampadaire", "streetlight", "foliage", "flower", "fleur", "herbe", "grass",
  "hedge", "sapin", "palm", "fern", "weed", "exotic tree", "littletree", "flattree",
  "deckchair", "loungechair", "office chair", "bushes", "buissons",
  "traina", "trainb", "trainsys", "trainengine", "trainbrake", "trainidle",
  "trains", "tgv", "tramway",
}
local DECOR_EXACT = {
  Tree = true, Trees = true, Arbre = true, Arbres = true, Poteau = true, Poteau2 = true,
  Bush = true, Bush2 = true, Bushes = true, Buissons = true, Plant = true, Plante = true,
  Chair = true, Chairs = true, Banc = true, Bancs = true, BancMetal = true,
  TrainA = true, TrainB = true, Trains = true, TrainSYS = true,
  TrainEngine = true, TrainBrake = true, TrainIdle = true,
  ExoticTree = true, LittleTree = true, S_ExoticTree = true, S_FlatTree = true,
  S_LittleTree = true, S_PalmTree = true,
}
local DECOR_SKIP = {
  "drivechair", "driveseat", "humanoid", "carrosserie", "a-chassis", "ac6",
  "values", "wheel", "constraint", "attachment", "bone",
}

function M.isDecorJunk(inst)
  if not inst or not inst.Parent then return false end
  if inst:IsA("Terrain") or inst == WS or inst == Lighting then return false end
  if LocalPlayer.Character and inst:IsDescendantOf(LocalPlayer.Character) then return false end
  local owned = M.getOwnedCar and M.getOwnedCar()
  if owned and (inst == owned or inst:IsDescendantOf(owned)) then return false end
  local seated = M.getSeatedCar and M.getSeatedCar()
  if seated and (inst == seated or inst:IsDescendantOf(seated)) then return false end

  local name = tostring(inst.Name)
  if DECOR_EXACT[name] then return true end
  local n = string.lower(name)
  for _, s in ipairs(DECOR_SKIP) do
    if n:find(s, 1, true) then return false end
  end
  if n == "train" or n == "trains" or n:match("^train[ab]$") or n:find("trainsys", 1, true)
    or n:find("trainengine", 1, true) or n:find("trainbrake", 1, true) then
    return true
  end
  for _, w in ipairs(DECOR_WORDS) do
    if n:find(w, 1, true) then
      if w == "chair" and n:find("drive", 1, true) then return false end
      return true
    end
  end
  return false
end

function M.destroyDecor(inst)
  if not M.isDecorJunk(inst) then return false end
  pcall(function() inst:Destroy() end)
  return true
end

-- Wipe léger opt-in: Models/Folders priority, throttle ~35 destroys
function M.runDecorClean()
  if not M.state.decorClean then return end
  if M._decorRunning then return end
  M._decorRunning = true
  task.spawn(function()
    local n = 0
    local function bump()
      n = n + 1
      if n % 35 == 0 then task.wait() end
    end
    -- 1) top-level Models/Folders first (gros packs décor/train)
    local tops = {}
    for _, o in ipairs(WS:GetChildren()) do
      if o:IsA("Model") or o:IsA("Folder") then
        table.insert(tops, o)
      end
    end
    for _, o in ipairs(tops) do
      if not M.state.decorClean then break end
      if M.destroyDecor(o) then bump() end
    end
    -- 2) autres top-level
    for _, o in ipairs(WS:GetChildren()) do
      if not M.state.decorClean then break end
      if not (o:IsA("Model") or o:IsA("Folder")) and M.destroyDecor(o) then bump() end
    end
    -- 3) un seul passage descendants plafonné (Models/Folders only)
    local cap = 8000
    local seen = 0
    for _, o in ipairs(WS:GetDescendants()) do
      if not M.state.decorClean then break end
      seen = seen + 1
      if seen > cap then break end
      if (o:IsA("Model") or o:IsA("Folder")) and M.destroyDecor(o) then bump() end
    end
    M._decorRunning = false
  end)
end

function M.setupDecorWatcher()
  if M._decorWatch then return end
  -- throttle: ne pas Destroy à chaque stream (cause le "bug à mort")
  local queue = {}
  M._decorWatch = track(WS.ChildAdded:Connect(function(o)
    if not M.state.decorClean then return end
    table.insert(queue, o)
  end))
  task.spawn(function()
    while M._decorWatch do
      if M.state.decorClean and #queue > 0 then
        local batch = math.min(8, #queue)
        for _ = 1, batch do
          local o = table.remove(queue, 1)
          if o then M.destroyDecor(o) end
        end
      end
      task.wait(0.35)
    end
  end)
end

function M.snapshotLighting()
  if M._origLighting then return end
  M._origLighting = {
    Brightness = Lighting.Brightness,
    FogEnd = Lighting.FogEnd,
    FogStart = Lighting.FogStart,
    FogColor = Lighting.FogColor,
    GlobalShadows = Lighting.GlobalShadows,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    ColorShift_Top = Lighting.ColorShift_Top,
    ColorShift_Bottom = Lighting.ColorShift_Bottom,
  }
  pcall(function()
    if typeof(Lighting.ShadowSoftness) == "number" then
      M._origLighting.ShadowSoftness = Lighting.ShadowSoftness
    end
  end)
end

function M.restoreLightingSnapshot()
  if not M._origLighting then return end
  for k, v in pairs(M._origLighting) do
    pcall(function() Lighting[k] = v end)
  end
end

function M.clearBeautyEffects()
  if M._beautyFx then
    for _, e in ipairs(M._beautyFx) do
      pcall(function() e:Destroy() end)
    end
    M._beautyFx = nil
  end
  if M._atmInst and M._origAtmosphere and M._atmInst.Parent then
    for k, v in pairs(M._origAtmosphere) do
      pcall(function() M._atmInst[k] = v end)
    end
  end
  M._atmInst = nil
  M._origAtmosphere = nil
end

-- Beauty pack = look soft/joli (pas le FPS pack potato). Léger, pas de GetDescendants wipe.
function M.setBeautyPack(on)
  M.state.beautyPack = on == true
  if on then
    M._beautyBeforeFps = nil -- choix explicite Beauty: annule le flag FPS
    if M.state.fpsPack then
      M.state.fpsPack = false
      if M._fpsAdd then pcall(function() M._fpsAdd:Disconnect() end); M._fpsAdd = nil end
    end
    M.snapshotLighting()
    M.clearBeautyEffects()
    M._beautyFx = {}
    local o = M._origLighting
    pcall(function()
      Lighting.Brightness = math.clamp((o and o.Brightness or 2) * 1.08, 1.4, 2.6)
      Lighting.GlobalShadows = true
      if typeof(Lighting.ShadowSoftness) == "number" then
        Lighting.ShadowSoftness = 0.45
      end
      Lighting.Ambient = Color3.fromRGB(88, 94, 108)
      Lighting.OutdoorAmbient = Color3.fromRGB(138, 144, 158)
      Lighting.FogStart = (o and o.FogStart) or 0
      local fogEnd = (o and o.FogEnd) or 1000
      if fogEnd < 100 then fogEnd = 900 end
      Lighting.FogEnd = math.clamp(fogEnd, 700, 2500)
      if o and o.FogColor then
        Lighting.FogColor = o.FogColor:Lerp(Color3.fromRGB(175, 192, 220), 0.3)
      else
        Lighting.FogColor = Color3.fromRGB(175, 192, 220)
      end
      Lighting.ColorShift_Top = Color3.fromRGB(255, 248, 240)
      Lighting.ColorShift_Bottom = Color3.fromRGB(210, 220, 235)
    end)

    local function addFx(className, name, props)
      local ok, fx = pcall(function()
        local e = Instance.new(className)
        e.Name = name
        for k, v in pairs(props) do e[k] = v end
        e.Parent = Lighting
        return e
      end)
      if ok and fx then table.insert(M._beautyFx, fx) end
    end

    addFx("BloomEffect", "UNDETEK_Beauty_Bloom", {
      Intensity = 0.32, Size = 22, Threshold = 1.05,
    })
    addFx("ColorCorrectionEffect", "UNDETEK_Beauty_CC", {
      Brightness = 0.025, Contrast = 0.11, Saturation = 0.14,
      TintColor = Color3.fromRGB(255, 250, 245),
    })
    addFx("SunRaysEffect", "UNDETEK_Beauty_SunRays", {
      Intensity = 0.07, Spread = 0.42,
    })

    local atm = Lighting:FindFirstChildOfClass("Atmosphere")
    if not atm then
      addFx("Atmosphere", "UNDETEK_Beauty_Atmosphere", {
        Density = 0.27, Offset = 0.12,
        Color = Color3.fromRGB(198, 210, 230),
        Decay = Color3.fromRGB(115, 128, 158),
        Glare = 0.12, Haze = 1.15,
      })
    else
      M._atmInst = atm
      M._origAtmosphere = {
        Density = atm.Density, Offset = atm.Offset,
        Color = atm.Color, Decay = atm.Decay,
        Glare = atm.Glare, Haze = atm.Haze,
      }
      pcall(function()
        atm.Density = math.clamp((atm.Density or 0.3) * 0.92 + 0.04, 0.18, 0.42)
        atm.Haze = math.clamp((atm.Haze or 0) + 0.45, 0, 2.4)
        atm.Glare = math.clamp((atm.Glare or 0) + 0.06, 0, 0.35)
        atm.Color = atm.Color:Lerp(Color3.fromRGB(200, 212, 232), 0.25)
      end)
    end
  else
    M._beautyBeforeFps = false -- OFF explicite: ne pas restaurer après FPS
    M.clearBeautyEffects()
    if not M.state.fpsPack then
      M.restoreLightingSnapshot()
      if M.state.renderBoost then M.applyRenderBoost(true) end
    end
  end
end

function M.applyFov(v)
  local n = math.clamp(tonumber(v) or 70, 70, 120)
  M.state.fov = n
  local cam = WS.CurrentCamera
  if cam then pcall(function() cam.FieldOfView = n end) end
end

function M.initFov()
  local cam = WS.CurrentCamera
  local cur = (cam and typeof(cam.FieldOfView) == "number") and cam.FieldOfView or 70
  if M._origFov == nil then M._origFov = cur end
  local start = math.clamp(cur, 70, 120)
  if cur < 70 or cur > 120 then start = 70 end
  M.applyFov(start)
  if not M._fovCamWatch then
    M._fovCamWatch = track(WS:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
      if M.state and M.state.fov then task.defer(function() M.applyFov(M.state.fov) end) end
    end))
  end
end

local function fpsApply(o)
  if o:IsA("ParticleEmitter") or o:IsA("Trail") or o:IsA("Smoke") or o:IsA("Fire") or o:IsA("Sparkles") then
    pcall(function() o.Enabled = false end)
  elseif o:IsA("BloomEffect") or o:IsA("SunRaysEffect") or o:IsA("DepthOfFieldEffect") or o:IsA("BlurEffect") then
    pcall(function() o.Enabled = false end)
  elseif o:IsA("ColorCorrectionEffect") then
    pcall(function() o.Enabled = false end)
  elseif o:IsA("Atmosphere") then
    -- Atmosphere n'a pas toujours Enabled — attenue densite au lieu de planter
    pcall(function()
      if typeof(o.Enabled) == "boolean" then o.Enabled = false
      else o.Density = 0; o.Haze = 0; o.Glare = 0 end
    end)
  end
end

function M.setFpsPack(on)
  M.state.fpsPack = on == true
  if on then
    -- Mémorise Beauty pour restore propre à l'OFF (évite look potato collé après FPS)
    if M.state.beautyPack then
      M._beautyBeforeFps = true
      M.state.beautyPack = false
      M.clearBeautyEffects()
    elseif M._beautyBeforeFps == nil then
      M._beautyBeforeFps = false
    end
    M.snapshotLighting()
    pcall(function()
      Lighting.GlobalShadows = false
      Lighting.FogEnd = 1e6
      Lighting.Brightness = 2
    end)
    for _, e in ipairs(Lighting:GetChildren()) do
      if e:IsA("PostEffect") or e:IsA("Atmosphere") then pcall(function() e.Enabled = false end) end
    end
    -- NE PAS scanner tout le Workspace (freeze). Seulement Lighting + FX locaux.
    if setfpscap then pcall(function() setfpscap(1000) end) end
    if M._fpsAdd then M._fpsAdd:Disconnect() end
    M._fpsAdd = track(Lighting.ChildAdded:Connect(function(o)
      if M.state.fpsPack then task.defer(fpsApply, o) end
    end))
    for _, e in ipairs(Lighting:GetChildren()) do fpsApply(e) end
  else
    if M._fpsAdd then M._fpsAdd:Disconnect(); M._fpsAdd = nil end
    M.restoreLightingSnapshot()
    local wantBeauty = M.state.beautyPack or M._beautyBeforeFps == true
    M._beautyBeforeFps = nil
    if wantBeauty then
      M.setBeautyPack(true)
    elseif M.state.renderBoost then
      M.applyRenderBoost(true)
    end
  end
end

-- ── Combat targets / visibility ──────────────────────────────────
function M.sameTeam(plr)
  if not plr or not LocalPlayer.Team then return false end
  return plr.Team == LocalPlayer.Team
end

function M.isVisible(part)
  if not part then return false end
  local origin = Camera.CFrame.Position
  local dir = part.Position - origin
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude
  params.FilterDescendantsInstances = { LocalPlayer.Character, select(1, M.currentCar()) }
  local hit = WS:Raycast(origin, dir, params)
  if not hit then return true end
  return hit.Instance:IsDescendantOf(part.Parent)
end

function M.targets()
  local out = {}
  for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LocalPlayer and alive(plr) then
      local root = getRoot(plr)
      local hum = getHum(plr)
      if root and hum then
        table.insert(out, {
          player = plr, model = plr.Character, root = root, hum = hum, name = plr.DisplayName or plr.Name,
          team = plr.Team, isTeam = M.sameTeam(plr),
        })
      end
    end
  end
  return out
end

function M.screenFovDist(worldPos)
  local v, on = Camera:WorldToViewportPoint(worldPos)
  if not on or v.Z < 0 then return 1e9, nil end
  local cx, cy = Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2
  local d = (Vector2.new(v.X, v.Y) - Vector2.new(cx, cy)).Magnitude
  return d, Vector2.new(v.X, v.Y)
end

function M.nearestInFov(fov, needVisible, skipTeam)
  local best, bestD = nil, fov or 180
  for _, t in ipairs(M.targets()) do
    if not (skipTeam and t.isTeam) then
      local part = (M.state.aimPart == "Head" and t.model:FindFirstChild("Head")) or t.root
      if part and not (needVisible and not M.isVisible(part)) then
        local d = M.screenFovDist(part.Position)
        if d < bestD then bestD = d; best = { tgt = t, part = part, fov = d } end
      end
    end
  end
  return best
end

-- ── Aimbot (damp dt-stable) ──────────────────────────────────────
function M.stepAimbot(dt)
  if not M.state.aimbot then return end
  if not Camera then Camera = WS.CurrentCamera end
  if not Camera then return end
  local hit = M.nearestInFov(M.state.aimFov, M.state.aimVisible, true)
  if not hit then return end
  local goal = CFrame.lookAt(Camera.CFrame.Position, hit.part.Position)
  -- smooth = fraction @60fps → damp independant du framerate
  local smooth = math.clamp(M.state.aimSmooth, 0.05, 1)
  local alpha = 1 - ((1 - smooth) ^ math.clamp((dt or 1 / 60) * 60, 0, 4))
  Camera.CFrame = Camera.CFrame:Lerp(goal, alpha)
end

-- Silent assist = snap cam to head on LMB (no gun remote in dump)
-- Si Aimbot deja ON: laisse le damp aimbot gerer (evite fight cam LMB)
function M.stepSilentAssist()
  if not M.state.silentAssist then return end
  if M.state.aimbot then return end
  local down = false
  pcall(function() down = UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end)
  if not down then return end
  local hit = M.nearestInFov(M.state.silentFov, M.state.aimVisible, true)
  if hit then
    pcall(function() Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, hit.part.Position) end)
  end
end

-- Cuff aura (proven Handcuff_Function)
function M.stepCuffAura()
  if not M.state.cuffAura then return end
  local now = tick()
  if M._cuffAt and (now - M._cuffAt) < M.state.cuffInterval then return end
  M._cuffAt = now
  local myRoot = getRoot()
  if not myRoot then return end
  local best, bestD = nil, M.state.cuffRange
  for _, t in ipairs(M.targets()) do
    if not t.isTeam then
      local d = (t.root.Position - myRoot.Position).Magnitude
      if d < bestD then bestD = d; best = t end
    end
  end
  if best then
    M.handcuffInvoke("Cuff", best.player.Name)
  end
end

-- ── ESP Drawing (Murder-style, no Highlight — safer on Xeno) ─────
local function newDraw(class, props)
  if not M._hasDrawing then return nil end
  local ok, o = pcall(function()
    local d = Drawing.new(class)
    if type(props) == "table" then for k, v in pairs(props) do pcall(function() d[k] = v end) end end
    return d
  end)
  return ok and o or nil
end

function M.stepFovCircle()
  if not M._hasDrawing then return end
  local show = M.state.aimbot and M.state.aimFovCircle
  if not show then
    if M._fovCircle then pcall(function() M._fovCircle.Visible = false end) end
    return
  end
  if not M._fovCircle then
    M._fovCircle = newDraw("Circle", {
      Thickness = 1, Filled = false, NumSides = 64, Visible = false,
      Color = Color3.fromRGB(220, 60, 60), Transparency = 0.65,
    })
  end
  if not M._fovCircle then return end
  local cam = Camera or WS.CurrentCamera
  if not cam then return end
  local vs = cam.ViewportSize
  M._fovCircle.Visible = true
  M._fovCircle.Position = Vector2.new(vs.X / 2, vs.Y / 2)
  M._fovCircle.Radius = M.state.aimFov
  M._fovCircle.Color = Color3.fromRGB(220, 60, 60)
end

function M.clearEsp()
  for _, bag in pairs(M.esp) do
    for _, o in pairs(bag) do pcall(function() o:Remove() end) end
  end
  M.esp = {}
end

function M.espBag(key)
  local bag = M.esp[key]
  if bag then return bag end
  bag = {
    box = newDraw("Square", { Thickness = 1, Filled = false, Visible = false }),
    name = newDraw("Text", { Size = 14, Center = true, Outline = true, Visible = false }),
    hp = newDraw("Line", { Thickness = 2, Visible = false }),
    dist = newDraw("Text", { Size = 12, Center = true, Outline = true, Visible = false }),
    tracer = newDraw("Line", { Thickness = 1, Visible = false }),
  }
  M.esp[key] = bag
  return bag
end

function M.stepEsp()
  local any = M.state.espBox or M.state.espName or M.state.espHealth or M.state.espDistance or M.state.espTracer
  if not any or not M._hasDrawing then
    if next(M.esp) then M.clearEsp() end
    return
  end
  local seen = {}
  local myRoot = getRoot()
  for _, t in ipairs(M.targets()) do
    if M.state.espTeamCheck and t.isTeam then
      -- skip allies
    else
    local key = t.player.UserId
    seen[key] = true
    local bag = M.espBag(key)
    local root = t.root
    local head = t.model:FindFirstChild("Head")
    local dist = myRoot and (root.Position - myRoot.Position).Magnitude or 0
    if dist > M.state.espMaxDist then
      for _, o in pairs(bag) do pcall(function() o.Visible = false end) end
    else
    local color = t.isTeam and M.state.espTeamColor or M.state.espColor
    local top = head and head.Position or (root.Position + Vector3.new(0, 2.5, 0))
    local bottom = root.Position - Vector3.new(0, 3, 0)
    local tl, on1 = Camera:WorldToViewportPoint(top + Vector3.new(-1.2, 0, 0))
    local br, on2 = Camera:WorldToViewportPoint(bottom + Vector3.new(1.2, 0, 0))
    local mid, on3 = Camera:WorldToViewportPoint(root.Position)
    local visible = on1 and on2 and tl.Z > 0 and br.Z > 0

    if bag.box then
      if M.state.espBox and visible then
        local x1, y1 = math.min(tl.X, br.X), math.min(tl.Y, br.Y)
        local x2, y2 = math.max(tl.X, br.X), math.max(tl.Y, br.Y)
        bag.box.Visible = true
        bag.box.Color = color
        bag.box.Position = Vector2.new(x1, y1)
        bag.box.Size = Vector2.new(math.max(2, x2 - x1), math.max(2, y2 - y1))
      else bag.box.Visible = false end
    end
    if bag.name then
      if M.state.espName and on3 and mid.Z > 0 then
        bag.name.Visible = true
        bag.name.Color = color
        bag.name.Text = t.name
        bag.name.Position = Vector2.new(mid.X, tl.Y - 14)
      else bag.name.Visible = false end
    end
    if bag.dist then
      if M.state.espDistance and on3 and mid.Z > 0 then
        bag.dist.Visible = true
        bag.dist.Color = Color3.fromRGB(230, 230, 230)
        bag.dist.Text = string.format("%dm", math.floor(dist))
        bag.dist.Position = Vector2.new(mid.X, br.Y + 2)
      else bag.dist.Visible = false end
    end
    if bag.hp then
      if M.state.espHealth and visible then
        local pct = math.clamp(t.hum.Health / math.max(t.hum.MaxHealth, 1), 0, 1)
        local x1 = math.min(tl.X, br.X) - 4
        local y1, y2 = math.min(tl.Y, br.Y), math.max(tl.Y, br.Y)
        local h = (y2 - y1) * pct
        bag.hp.Visible = true
        bag.hp.Color = Color3.fromRGB(80, 255, 100)
        bag.hp.From = Vector2.new(x1, y2)
        bag.hp.To = Vector2.new(x1, y2 - h)
      else bag.hp.Visible = false end
    end
    if bag.tracer then
      if M.state.espTracer and on3 and mid.Z > 0 then
        bag.tracer.Visible = true
        bag.tracer.Color = color
        bag.tracer.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
        bag.tracer.To = Vector2.new(mid.X, mid.Y)
      else bag.tracer.Visible = false end
    end
    end -- dist check
    end -- team check
  end
  for key, bag in pairs(M.esp) do
    if not seen[key] then
      for _, o in pairs(bag) do pcall(function() o:Remove() end) end
      M.esp[key] = nil
    end
  end
end

-- Runtime combat sniffer (DBG only) — for future silent gun if remotes appear
function M.installCombatSniff()
  local env = (typeof(getgenv) == "function" and getgenv()) or _G
  if env.UNDETEK_SF_DBG ~= true then return end
  if M._combatSniff then return end
  M._combatSniff = true
  pcall(function()
    if not getrawmetatable then return end
    local wrap = (typeof(newcclosure) == "function" and newcclosure) or function(f) return f end
    local mt = getrawmetatable(game)
    local old = mt.__namecall
    setreadonly(mt, false)
    mt.__namecall = wrap(function(self, ...)
      local method = getnamecallmethod()
      if method == "FireServer" or method == "InvokeServer" then
        local n = typeof(self) == "Instance" and self.Name:lower() or ""
        if n:find("weapon") or n:find("damage") or n:find("hit") or n:find("shoot") or n:find("tir") or n:find("gun") or n:find("bullet") then
          print("[SF-COMBAT]", method, self:GetFullName())
        end
      end
      return old(self, ...)
    end)
    setreadonly(mt, true)
  end)
end

-- ── AC Probe (log only, OFF by default — Info tab) ───────────────
-- Read-only observation: BusLines, forbidden movers, friction>2, Kick/ban remotes.
-- Namecall hook is opt-in (can be noisy); does NOT bypass server AC.
local AC_BAD_MOVERS = {
  BodyVelocity = true, BodyGyro = true, BodyPosition = true, BodyForce = true,
  BodyThrust = true, LinearVelocity = true, AngularVelocity = true,
  VectorForce = true, AlignPosition = true, AlignOrientation = true,
}

local function acLog(...)
  print("[SF-AC]", ...)
end

function M.stopAcProbe()
  M.state.acProbe = false
  M.ac.on = false
  if M.ac.frictionLoop then
    M.ac.frictionLoop = false
  end
  for _, c in ipairs(M.ac.conns) do pcall(function() c:Disconnect() end) end
  M.ac.conns = {}
  if M.ac._oldNamecall and getrawmetatable then
    pcall(function()
      local mt = getrawmetatable(game)
      setreadonly(mt, false)
      mt.__namecall = M.ac._oldNamecall
      setreadonly(mt, true)
    end)
    M.ac._oldNamecall = nil
  end
  acLog("probe stopped")
end

function M.startAcProbe()
  if M.ac.on then return end
  M.ac.on = true
  M.state.acProbe = true
  acLog("probe start PlaceId=", game.PlaceId)

  pcall(function()
    local bl = RS:FindFirstChild("BusLines")
    if not bl then
      acLog("BusLines missing")
      return
    end
    table.insert(M.ac.conns, bl.ChildAdded:Connect(function(ch)
      acLog("BusLines ChildAdded:", ch.Name, ch.ClassName)
      if ch.Name == "CHEAT_DETECTED_ANTIEXPLOIT_REQUIRED" then
        acLog("!!! CHEAT_DETECTED channel — kick imminent")
      end
    end))
    acLog("watching BusLines")
  end)

  local function watch(inst, tag)
    if not inst then return end
    table.insert(M.ac.conns, inst.DescendantAdded:Connect(function(d)
      if AC_BAD_MOVERS[d.ClassName] then
        acLog("MOVER ADD", tag, d.ClassName, d:GetFullName())
      end
    end))
    for _, d in ipairs(inst:GetDescendants()) do
      if AC_BAD_MOVERS[d.ClassName] then
        acLog("MOVER EXIST", tag, d.ClassName, d:GetFullName())
      end
    end
  end

  local function watchChar(char)
    watch(char, "char")
  end
  if LocalPlayer.Character then watchChar(LocalPlayer.Character) end
  table.insert(M.ac.conns, LocalPlayer.CharacterAdded:Connect(watchChar))

  local function watchCar()
    local car = WS:FindFirstChild(LocalPlayer.Name .. "'s Car")
    if car then watch(car, "car") end
  end
  watchCar()
  table.insert(M.ac.conns, WS.ChildAdded:Connect(function(ch)
    if ch.Name == (LocalPlayer.Name .. "'s Car") then
      acLog("car spawned")
      watch(ch, "car")
    end
  end))

  M.ac.frictionLoop = true
  task.spawn(function()
    while M.ac.frictionLoop and M.ac.on do
      task.wait(2)
      local car = WS:FindFirstChild(LocalPlayer.Name .. "'s Car")
      if car then
        for _, p in ipairs(car:GetDescendants()) do
          if p:IsA("BasePart") then
            local ok, props = pcall(function() return p.CurrentPhysicalProperties end)
            if ok and props and props.Friction > 2.01 then
              acLog("FRICTION>2", p:GetFullName(), props.Friction)
            end
          end
        end
      end
    end
  end)

  pcall(function()
    if not getrawmetatable then acLog("no mt hook"); return end
    if M.ac._oldNamecall then return end
    local wrap = (typeof(newcclosure) == "function" and newcclosure) or function(f) return f end
    local mt = getrawmetatable(game)
    local old = mt.__namecall
    M.ac._oldNamecall = old
    setreadonly(mt, false)
    mt.__namecall = wrap(function(self, ...)
      local method = getnamecallmethod()
      if method == "Kick" or method == "FireServer" or method == "InvokeServer" then
        local n = typeof(self) == "Instance" and self.Name or "?"
        local nl = string.lower(n)
        if method == "Kick" or nl:find("ban") or nl:find("cheat") or nl:find("anti") or nl:find("packet") then
          local args = {}
          for i = 1, select("#", ...) do
            local a = select(i, ...)
            args[i] = typeof(a) == "Instance" and a:GetFullName() or tostring(a):sub(1, 80)
          end
          acLog(method, typeof(self) == "Instance" and self:GetFullName() or n, table.concat(args, " | "))
        end
      end
      return old(self, ...)
    end)
    setreadonly(mt, true)
    acLog("namecall hook OK")
  end)

  pcall(function()
    local key = tostring(LocalPlayer.UserId)
    table.insert(M.ac.conns, LocalPlayer:GetAttributeChangedSignal(key):Connect(function()
      acLog("UserId-attr changed — integrity channel?", LocalPlayer:GetAttribute(key))
    end))
  end)

  acLog("probe armed — open F9, use features, watch [SF-AC] lines")
  acLog("Known: old Fly BodyVelocity = ban. Grip Friction>2 = console clamp + risk.")
end

function M.setAcProbe(on)
  on = on == true
  if on then M.startAcProbe() else M.stopAcProbe() end
end

-- ── Loops / input (master Heartbeat multiplex) ───────────────────
track(RunS.Heartbeat:Connect(function(dt)
  M.stepVehicle(dt)
  M.stepCuffAura()
end))

track(RunS.RenderStepped:Connect(function(dt)
  Camera = WS.CurrentCamera
  M.stepAimbot(dt)
  M.stepSilentAssist()
  M.stepFovCircle()
  M.stepEsp()
end))

track(UIS.InputBegan:Connect(function(input, g)
  if g then return end
  if input.KeyCode == Enum.KeyCode.LeftShift then
    M.toggleFlySmart()
  elseif input.KeyCode == Enum.KeyCode.RightShift then
    if M.gui then M.gui.Enabled = not M.gui.Enabled end
  end
end))

-- Respawn: clear ESP bags + refresh Camera ref
track(LocalPlayer.CharacterAdded:Connect(function()
  Camera = WS.CurrentCamera
  M.clearEsp()
  if M.state.fov then task.defer(function() M.applyFov(M.state.fov) end) end
end))

-- ── UI ───────────────────────────────────────────────────────────
local UI_BG = Color3.fromRGB(248, 248, 250)
local UI_PANEL = Color3.fromRGB(232, 232, 236)
local UI_ON = Color3.fromRGB(40, 40, 44)
local UI_TEXT = Color3.fromRGB(18, 18, 20)
local UI_MUTED = Color3.fromRGB(110, 110, 118)

local function mkCorner(parent, r)
  local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = parent
end

local function clear(frame)
  for _, ch in ipairs(frame:GetChildren()) do
    if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then ch:Destroy() end
  end
end

function M.btn(parent, text, on, cb)
  local b = Instance.new("TextButton")
  b.Size = UDim2.new(1, 0, 0, 30)
  b.BackgroundColor3 = on and UI_ON or UI_PANEL
  b.Text = text
  b.TextColor3 = on and Color3.new(1, 1, 1) or UI_TEXT
  b.Font = Enum.Font.GothamMedium
  b.TextSize = 12
  b.Parent = parent
  mkCorner(b, 7)
  b.MouseButton1Click:Connect(function() cb(b); M.refreshUi() end)
  return b
end

function M.label(parent, text)
  local l = Instance.new("TextLabel")
  l.Size = UDim2.new(1, 0, 0, 16)
  l.BackgroundTransparency = 1
  l.Text = text
  l.TextColor3 = UI_MUTED
  l.Font = Enum.Font.Gotham
  l.TextSize = 10
  l.TextXAlignment = Enum.TextXAlignment.Left
  l.TextWrapped = true
  l.Parent = parent
  return l
end

function M.refreshUi()
  if not M.body then return end
  clear(M.body)
  local tab = M.state.tab

  if tab == "Vehicule" then
    M.label(M.body, "Car Speed (max 180) · pas de slider Accélération")
    M.btn(M.body, "Car Speed: " .. (M.state.propulsion and "ON" or "OFF"), M.state.propulsion, function()
      M.state.propulsion = not M.state.propulsion
    end)
    M.btn(M.body, "Motor mode: " .. M.state.accelMode, false, function()
      local o = { "Smooth", "Normal", "Sport" }
      local i = 1
      for k, v in ipairs(o) do if v == M.state.accelMode then i = k break end end
      M.state.accelMode = o[(i % #o) + 1]
    end)
    M.btn(M.body, "Puissance: " .. M.state.power, false, function()
      M.state.power = M.state.power + 15
      if M.state.power > 180 then M.state.power = 60 end
    end)
    M.btn(M.body, "Steer assist: " .. (M.state.steerAssist and "ON" or "OFF"), M.state.steerAssist, function()
      M.state.steerAssist = not M.state.steerAssist
    end)
    M.btn(M.body, "Steer force: " .. string.format("%.1f", M.state.steerForce), false, function()
      M.state.steerForce = math.floor((M.state.steerForce + 0.1) * 10 + 0.5) / 10
      if M.state.steerForce > 1.5 then M.state.steerForce = 0.3 end
    end)
    M.btn(M.body, "Steer max speed: " .. M.state.steerMaxSpeed, false, function()
      M.state.steerMaxSpeed = M.state.steerMaxSpeed + 5
      if M.state.steerMaxSpeed > 70 then M.state.steerMaxSpeed = 20 end
    end)
    M.btn(M.body, "Steer curve: " .. M.state.steerCurve, false, function()
      local o = { "LowOnly", "Smooth", "Linear" }
      local i = 1
      for k, v in ipairs(o) do if v == M.state.steerCurve then i = k break end end
      M.state.steerCurve = o[(i % #o) + 1]
    end)
    M.btn(M.body, "Steer mode: " .. M.state.steerMode, false, function()
      local o = { "Hybrid", "Steer", "Yaw" }
      local i = 1
      for k, v in ipairs(o) do if v == M.state.steerMode then i = k break end end
      M.state.steerMode = o[(i % #o) + 1]
    end)
    M.btn(M.body, "Anti-drift lat: " .. (M.state.steerLatDamp and "ON" or "OFF"), M.state.steerLatDamp, function()
      M.state.steerLatDamp = not M.state.steerLatDamp
    end)
    M.label(M.body, "Assist fort au ralenti → 0 à haute vitesse (indépendant Car Speed)")
    M.btn(M.body, "Repair", false, function() M.carInvoke("Repair"); toast("Car", "Repair") end)
    M.btn(M.body, "Essence", false, function()
      local car = M.getOwnedCar() or M.getSeatedCar()
      local amt = 100
      if car then
        local fuel = car:GetAttribute("Fuel") or car:GetAttribute("Energy")
        if typeof(fuel) == "number" then amt = math.max(1, 100 - fuel) end
      end
      -- dump: RefillFuel(delta, 100)
      M.carInvoke("RefillFuel", amt, 100); toast("Car", "Essence")
    end)
    M.btn(M.body, "Bring car", false, function() M.bringCar() end)

  elseif tab == "Fly" then
    M.label(M.body, "LeftShift = fly voiture si assis · fly perso supprimé (ban AC)")
    M.btn(M.body, "Fly Car: " .. (M.state.flyCar and "ON" or "OFF"), M.state.flyCar, function()
      M.setFlyCar(not M.state.flyCar)
    end)
    M.btn(M.body, "Slow: " .. (M.state.slowFly and "ON" or "OFF"), M.state.slowFly, function()
      M.state.slowFly = not M.state.slowFly
    end)
    M.btn(M.body, "Spd car: " .. M.state.flyCarSpeed .. " (max " .. FLY_CAR_SPEED_MAX .. ")", false, function()
      M.state.flyCarSpeed = M.state.flyCarSpeed + 10
      if M.state.flyCarSpeed > FLY_CAR_SPEED_MAX then M.state.flyCarSpeed = 50 end
    end)

  elseif tab == "Combat" then
    M.label(M.body, "Aimbot caméra · Silent = snap clic (pas de remote tir dump)")
    M.btn(M.body, "Aimbot: " .. (M.state.aimbot and "ON" or "OFF"), M.state.aimbot, function()
      M.state.aimbot = not M.state.aimbot
    end)
    M.btn(M.body, "Silent assist (LMB): " .. (M.state.silentAssist and "ON" or "OFF"), M.state.silentAssist, function()
      M.state.silentAssist = not M.state.silentAssist
      if M.state.silentAssist then M.installCombatSniff() end
    end)
    M.btn(M.body, "FOV aim: " .. M.state.aimFov, false, function()
      M.state.aimFov = M.state.aimFov + 20
      if M.state.aimFov > 300 then M.state.aimFov = 80 end
    end)
    M.btn(M.body, "Smooth: " .. string.format("%.2f", M.state.aimSmooth), false, function()
      M.state.aimSmooth = math.floor((M.state.aimSmooth + 0.1) * 10 + 0.5) / 10
      if M.state.aimSmooth > 1 then M.state.aimSmooth = 0.1 end
    end)
    M.btn(M.body, "Visible check: " .. (M.state.aimVisible and "ON" or "OFF"), M.state.aimVisible, function()
      M.state.aimVisible = not M.state.aimVisible
    end)
    M.btn(M.body, "FOV circle: " .. (M.state.aimFovCircle and "ON" or "OFF"), M.state.aimFovCircle, function()
      M.state.aimFovCircle = not M.state.aimFovCircle
    end)
    M.label(M.body, "Aura: Handcuff_Function only (pas de kill remote)")
    M.btn(M.body, "Cuff aura: " .. (M.state.cuffAura and "ON" or "OFF"), M.state.cuffAura, function()
      M.state.cuffAura = not M.state.cuffAura
    end)
    M.btn(M.body, "Cuff range: " .. M.state.cuffRange, false, function()
      M.state.cuffRange = M.state.cuffRange + 2
      if M.state.cuffRange > 25 then M.state.cuffRange = 8 end
    end)

  elseif tab == "ESP" then
    if not M._hasDrawing then M.label(M.body, "Drawing API manquante sur cet executor") end
    M.btn(M.body, "Box: " .. (M.state.espBox and "ON" or "OFF"), M.state.espBox, function() M.state.espBox = not M.state.espBox end)
    M.btn(M.body, "Name: " .. (M.state.espName and "ON" or "OFF"), M.state.espName, function() M.state.espName = not M.state.espName end)
    M.btn(M.body, "Health: " .. (M.state.espHealth and "ON" or "OFF"), M.state.espHealth, function() M.state.espHealth = not M.state.espHealth end)
    M.btn(M.body, "Distance: " .. (M.state.espDistance and "ON" or "OFF"), M.state.espDistance, function() M.state.espDistance = not M.state.espDistance end)
    M.btn(M.body, "Tracer: " .. (M.state.espTracer and "ON" or "OFF"), M.state.espTracer, function() M.state.espTracer = not M.state.espTracer end)
    M.btn(M.body, "Team check: " .. (M.state.espTeamCheck and "ON" or "OFF"), M.state.espTeamCheck, function()
      M.state.espTeamCheck = not M.state.espTeamCheck
    end)
    M.btn(M.body, "Max dist: " .. M.state.espMaxDist, false, function()
      M.state.espMaxDist = M.state.espMaxDist + 200
      if M.state.espMaxDist > 2500 then M.state.espMaxDist = 400 end
    end)

  elseif tab == "Couleur" then
    M.label(M.body, "Carrosserie/Editable only")
    M.btn(M.body, "Appliquer", false, function() M.applyBodyPaint(M.state.bodyColor, false) end)
    M.btn(M.body, "Rouge", false, function() M.state.bodyColor = Color3.fromRGB(200, 40, 40); M.applyBodyPaint(M.state.bodyColor, false) end)
    M.btn(M.body, "Blanc", false, function() M.state.bodyColor = Color3.fromRGB(245, 245, 248); M.applyBodyPaint(M.state.bodyColor, false) end)
    M.btn(M.body, "Noir", false, function() M.state.bodyColor = Color3.fromRGB(20, 20, 22); M.applyBodyPaint(M.state.bodyColor, false) end)
    M.btn(M.body, "Rainbow: " .. (M.state.rainbow and "ON" or "OFF"), M.state.rainbow, function()
      M.state.rainbow = not M.state.rainbow
      if M.state.rainbow then M.startRainbow() end
    end)

  elseif tab == "Graphics" then
    M.label(M.body, "Beauty = soft · FPS = potato · FOV cam 70–120 · exclusifs")
    M.btn(M.body, "Beauty pack: " .. (M.state.beautyPack and "ON" or "OFF"), M.state.beautyPack, function()
      M.setBeautyPack(not M.state.beautyPack)
    end)
    M.btn(M.body, "FOV caméra: " .. tostring(M.state.fov), false, function()
      local n = (M.state.fov or 70) + 5
      if n > 120 then n = 70 end
      M.applyFov(n)
    end)
    M.btn(M.body, "FPS Pack: " .. (M.state.fpsPack and "ON" or "OFF"), M.state.fpsPack, function()
      M.setFpsPack(not M.state.fpsPack)
    end)
    M.btn(M.body, "Distance map: " .. (M.state.renderBoost and "ON" or "OFF"), M.state.renderBoost, function()
      M.applyRenderBoost(not M.state.renderBoost)
    end)
    M.btn(M.body, "Wipe décor+train: " .. (M.state.decorClean and "ON" or "OFF"), M.state.decorClean, function()
      M.state.decorClean = not M.state.decorClean
      if M.state.decorClean then
        M.runDecorClean()
        M.setupDecorWatcher()
      end
    end)
    M.btn(M.body, "Relancer wipe décor", false, function()
      M.state.decorClean = true
      M.runDecorClean()
      M.setupDecorWatcher()
    end)

  else
    M.label(M.body, "UNDETEK open source v" .. VERSION)
    M.label(M.body, "Vehicule · Fly voiture · Combat · GFX Beauty/FOV")
    M.label(M.body, "Pas de fly perso · pas Lock/Unlock · pas autofarm")
    M.label(M.body, "Money: " .. tostring(LocalPlayer:GetAttribute("Money")))
    M.label(M.body, "AC Probe = logs F9 only (OFF = sûr)")
    M.btn(M.body, "AC Probe: " .. (M.state.acProbe and "ON" or "OFF"), M.state.acProbe, function()
      M.setAcProbe(not M.state.acProbe)
    end)
    M.btn(M.body, "UNLOAD", false, function()
      local env = (typeof(getgenv) == "function" and getgenv()) or _G
      if env.UNDETEK_SF_UNLOAD then env.UNDETEK_SF_UNLOAD()
      elseif env.__XHUB_SECOURS_UNLOAD then env.__XHUB_SECOURS_UNLOAD() end
    end)
  end
end

local function buildUi()
  -- anti double-GUI (reste apres unload partiel)
  pcall(function()
    local host = (gethui and gethui()) or LocalPlayer:FindFirstChild("PlayerGui")
    if host then
      local old = host:FindFirstChild("UNDETEK_Secours")
      if old then old:Destroy() end
    end
  end)
  local gui = Instance.new("ScreenGui")
  gui.Name = "UNDETEK_Secours"
  gui.ResetOnSpawn = false
  gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  gui.DisplayOrder = 120
  gui.Parent = (gethui and gethui()) or LocalPlayer:WaitForChild("PlayerGui")

  local frame = Instance.new("Frame")
  frame.Size = UDim2.fromOffset(300, 460)
  frame.Position = UDim2.new(0, 16, 0.5, -230)
  frame.BackgroundColor3 = UI_BG
  frame.BorderSizePixel = 0
  frame.Parent = gui
  mkCorner(frame, 12)
  local stroke = Instance.new("UIStroke")
  stroke.Color = Color3.fromRGB(210, 210, 215)
  stroke.Parent = frame

  local title = Instance.new("TextLabel")
  title.Size = UDim2.new(1, -16, 0, 26)
  title.Position = UDim2.fromOffset(12, 8)
  title.BackgroundTransparency = 1
  title.Text = "UNDETEK"
  title.TextColor3 = UI_TEXT
  title.Font = Enum.Font.GothamBold
  title.TextSize = 16
  title.TextXAlignment = Enum.TextXAlignment.Left
  title.Parent = frame

  local sub = Instance.new("TextLabel")
  sub.Size = UDim2.new(1, -16, 0, 14)
  sub.Position = UDim2.fromOffset(12, 32)
  sub.BackgroundTransparency = 1
  sub.Text = "UNDETEK · Secours FR · v" .. VERSION .. " · RightShift"
  sub.TextColor3 = UI_MUTED
  sub.Font = Enum.Font.Gotham
  sub.TextSize = 10
  sub.TextXAlignment = Enum.TextXAlignment.Left
  sub.Parent = frame

  local tabs = Instance.new("ScrollingFrame")
  tabs.Size = UDim2.new(1, -12, 0, 30)
  tabs.Position = UDim2.fromOffset(6, 50)
  tabs.BackgroundTransparency = 1
  tabs.ScrollBarThickness = 0
  tabs.CanvasSize = UDim2.fromOffset(420, 0)
  tabs.Parent = frame
  local tl = Instance.new("UIListLayout")
  tl.FillDirection = Enum.FillDirection.Horizontal
  tl.Padding = UDim.new(0, 4)
  tl.Parent = tabs

  local tabNames = {
    { "Veh", "Vehicule" }, { "Fly", "Fly" }, { "Cbt", "Combat" },
    { "ESP", "ESP" }, { "Col", "Couleur" }, { "GFX", "Graphics" }, { "Info", "Info" },
  }
  for _, spec in ipairs(tabNames) do
    local label, id = spec[1], spec[2]
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(42, 26)
    b.BackgroundColor3 = UI_PANEL
    b.Text = label
    b.TextColor3 = UI_TEXT
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 10
    b.Parent = tabs
    mkCorner(b, 6)
    b.MouseButton1Click:Connect(function()
      M.state.tab = id
      for _, ch in ipairs(tabs:GetChildren()) do
        if ch:IsA("TextButton") then ch.BackgroundColor3 = UI_PANEL; ch.TextColor3 = UI_TEXT end
      end
      b.BackgroundColor3 = UI_ON; b.TextColor3 = Color3.new(1, 1, 1)
      M.refreshUi()
    end)
  end

  local body = Instance.new("ScrollingFrame")
  body.Size = UDim2.new(1, -16, 1, -92)
  body.Position = UDim2.fromOffset(8, 86)
  body.BackgroundTransparency = 1
  body.ScrollBarThickness = 3
  body.AutomaticCanvasSize = Enum.AutomaticSize.Y
  body.CanvasSize = UDim2.new(0, 0, 0, 0)
  body.Parent = frame
  local bl = Instance.new("UIListLayout"); bl.Padding = UDim.new(0, 5); bl.Parent = body
  Instance.new("UIPadding", body).PaddingBottom = UDim.new(0, 8)

  M.gui = gui
  M.body = body
  local first = tabs:FindFirstChildOfClass("TextButton")
  if first then first.BackgroundColor3 = UI_ON; first.TextColor3 = Color3.new(1, 1, 1) end
  M.refreshUi()
end

buildUi()
-- #region agent log
agentLog("A", "boot:pre", "ui_built", {
  placeId = tostring(game.PlaceId),
  ver = VERSION,
  hasGui = M.gui ~= nil,
  hasDrawing = M._hasDrawing == true,
})
-- #endregion

local function safeCall(hyp, loc, fn)
  local ok, err = pcall(fn)
  -- #region agent log
  agentLog(hyp, loc, ok and "ok" or "fail", { err = ok and "" or tostring(err):sub(1, 180) })
  -- #endregion
  return ok, err
end

safeCall("C", "boot:snapshot", function() M.snapshotLighting() end)
safeCall("C", "boot:renderBoost", function() M.applyRenderBoost(true) end)
safeCall("C", "boot:beauty", function() M.setBeautyPack(true) end)
safeCall("C", "boot:fov", function() M.initFov() end)
-- Boot LIGHT: Beauty pack ON · pas de wipe décor / FPS pack / DescendantAdded

-- Runtime self-check (hypotheses A-E)
task.defer(function()
  local carFn = M.getRemote("Car_Function")
  local cuffFn = M.getRemote("Handcuff_Function")
  local smOk = M.getInstanceFolder() ~= nil
  local owned = M.getOwnedCar()
  local seated = M.getSeatedCar()
  -- #region agent log
  agentLog("B", "selfcheck:remotes", "service_manager", {
    smOk = smOk,
    carFn = carFn ~= nil and carFn.ClassName or "nil",
    cuffFn = cuffFn ~= nil and cuffFn.ClassName or "nil",
  })
  agentLog("D", "selfcheck:vehicle", "car_state", {
    owned = owned and owned.Name or "nil",
    seated = seated and seated.Name or "nil",
    prop = M.state.propulsion == true,
    steer = M.state.steerAssist == true,
  })
  agentLog("D", "selfcheck:combat", "flags", {
    aim = M.state.aimbot == true,
    espBox = M.state.espBox == true,
    drawing = M._hasDrawing == true,
    flyCar = M.state.flyCar == true,
  })
  -- smoke: one Heartbeat tick of vehicle (prop+steer) without error
  local okP, errP = pcall(function() M.stepVehicle(1 / 60) end)
  agentLog("D", "selfcheck:propulsionTick", okP and "ok" or "fail", { err = okP and "" or tostring(errP):sub(1, 160) })
  local okE, errE = pcall(function() M.stepEsp() end)
  agentLog("E", "selfcheck:espTick", okE and "ok" or "fail", { err = okE and "" or tostring(errE):sub(1, 160) })
  local okR, errR = pcall(function() M.refreshUi() end)
  agentLog("A", "selfcheck:refreshUi", okR and "ok" or "fail", { err = okR and "" or tostring(errR):sub(1, 160), tab = M.state.tab })
  agentLog("A", "selfcheck:done", "complete", { ver = VERSION })
  -- #endregion
end)

local env = (typeof(getgenv) == "function" and getgenv()) or _G
env.__XHUB_SECOURS_CLEAN = function()
  M.state.rainbow = false
  M.state.aimbot = false
  M.state.silentAssist = false
  M.state.cuffAura = false
  M.state.propulsion = false
  M.state.decorClean = false
  M._streamKeep = false
  M._decorRunning = false
  pcall(function() M.setAcProbe(false) end)
  pcall(function() M.setFlyCar(false) end)
  if M._flyConn then pcall(function() M._flyConn:Disconnect() end); M._flyConn = nil end
  pcall(function() M.setBeautyPack(false) end)
  M._beautyBeforeFps = nil
  pcall(function() M.setFpsPack(false) end)
  if M._origFov then
    local cam = WS.CurrentCamera
    if cam then pcall(function() cam.FieldOfView = M._origFov end) end
  end
  if M._fovCircle then pcall(function() M._fovCircle:Remove() end); M._fovCircle = nil end
  if M._decorWatch then
    pcall(function() M._decorWatch:Disconnect() end)
    M._decorWatch = nil
  end
  if M._fpsAdd then pcall(function() M._fpsAdd:Disconnect() end); M._fpsAdd = nil end
  M.clearEsp()
  for _, c in ipairs(M.conns) do pcall(function() c:Disconnect() end) end
  M.conns = {}
  M.rf = {}
  M.rfMiss = {}
  if M.gui then pcall(function() M.gui:Destroy() end); M.gui = nil end
  M.body = nil
end
env.UNDETEK_SF_UNLOAD = env.__XHUB_SECOURS_UNLOAD

warn("[UNDETEK] v" .. VERSION .. " open source — Secours+AC · fly voiture only")
toast("UNDETEK", "v" .. VERSION .. " open source")
