local registeredGaragePoints = {}
local registeredGarageStorePoints = {}
local storePointsActive = nil

local function wantsMzInteract()
  return MZGaragemConfig and MZGaragemConfig.UseMzInteract == true
end

local function canUseMzInteract()
  return wantsMzInteract() and GetResourceState('mz_interact') == 'started'
end

local function countRegisteredPoints()
  local count = 0
  for _ in pairs(registeredGaragePoints) do
    count = count + 1
  end
  return count
end

local function getGarageCoords(garage)
  if type(garage) ~= 'table' then
    return nil
  end

  if garage.coords then return garage.coords end
  if garage.markerCoords then return garage.markerCoords end
  if garage.position then return garage.position end
  if garage.location then return garage.location end
  if type(garage.zone) == 'table' and garage.zone.coords then return garage.zone.coords end

  return nil
end

local function getStoreConfig(garage)
  if type(garage) ~= 'table' or type(garage.store) ~= 'table' or garage.store.enabled ~= true then
    return nil
  end

  return garage.store
end

local function getStoreCoords(store)
  if type(store) ~= 'table' then
    return nil
  end

  return store.coords or store.position or store.location
end

local function getGarageInteractConfig(garage)
  if type(garage) ~= 'table' or type(garage.interact) ~= 'table' then
    return {}
  end

  return garage.interact
end

local function cloneTable(source)
  local copy = {}
  for key, value in pairs(type(source) == 'table' and source or {}) do
    copy[key] = value
  end
  return copy
end

local function fallbackIcon()
  return 'mod_icon', 'garage'
end

local function iconFromConfig(icon)
  if type(icon) ~= 'table' then
    return nil, nil
  end

  if icon.textureDict == nil and icon.textureName == nil then
    return nil, nil
  end

  local fallbackDict, fallbackName = fallbackIcon()
  return tostring(icon.textureDict or fallbackDict), tostring(icon.textureName or fallbackName)
end

local function resolveGarageIcon(garage)
  local interact = getGarageInteractConfig(garage)

  local textureDict, textureName = iconFromConfig(type(interact.marker) == 'table' and interact.marker or nil)
  if textureDict then return textureDict, textureName end

  textureDict, textureName = iconFromConfig(interact.icon)
  if textureDict then return textureDict, textureName end

  textureDict, textureName = iconFromConfig({ textureDict = interact.textureDict, textureName = interact.textureName })
  if textureDict then return textureDict, textureName end

  textureDict, textureName = iconFromConfig(MZGaragemConfig.DefaultInteractIcon)
  if textureDict then return textureDict, textureName end

  return fallbackIcon()
end

local function resolveStoreIcon(garage)
  local garageInteract = getGarageInteractConfig(garage)
  local store = getStoreConfig(garage) or {}
  local storeInteract = type(store.interact) == 'table' and store.interact or {}

  local textureDict, textureName = iconFromConfig(type(storeInteract.marker) == 'table' and storeInteract.marker or nil)
  if textureDict then return textureDict, textureName end

  textureDict, textureName = iconFromConfig(storeInteract.icon)
  if textureDict then return textureDict, textureName end

  textureDict, textureName = iconFromConfig({ textureDict = storeInteract.textureDict, textureName = storeInteract.textureName })
  if textureDict then return textureDict, textureName end

  textureDict, textureName = iconFromConfig(type(garageInteract.marker) == 'table' and garageInteract.marker or nil)
  if textureDict then return textureDict, textureName end

  textureDict, textureName = iconFromConfig(garageInteract.icon)
  if textureDict then return textureDict, textureName end

  textureDict, textureName = iconFromConfig({ textureDict = garageInteract.textureDict, textureName = garageInteract.textureName })
  if textureDict then return textureDict, textureName end

  textureDict, textureName = iconFromConfig(MZGaragemConfig.DefaultStoreIcon)
  if textureDict then return textureDict, textureName end

  textureDict, textureName = iconFromConfig(MZGaragemConfig.DefaultInteractIcon)
  if textureDict then return textureDict, textureName end

  return fallbackIcon()
end

local function getGarageMarker(garage, interact)
  local textureDict, textureName = resolveGarageIcon(garage)

  if type(interact.marker) == 'table' then
    local marker = cloneTable(interact.marker)
    if marker.textureDict == nil then marker.textureDict = textureDict end
    if marker.textureName == nil then marker.textureName = textureName end
    return marker
  end

  return {
    enabled = true,
    type = 9,
    textureDict = textureDict,
    textureName = textureName,
    size = vec3(0.75, 0.75, 0.75),
    color = { r = 255, g = 255, b = 255, a = 230 },
    rotate = true,
    bobUpAndDown = true,
    faceCamera = true
  }
end

local function getGarageBlip(garage, interact)
  if type(interact.blip) == 'table' then
    return interact.blip
  end

  local blip = type(garage.blip) == 'table' and garage.blip or {}
  return {
    enabled = garage.blip ~= false and blip.enabled == true,
    sprite = blip.sprite or garage.blipSprite or 357,
    color = blip.color or garage.blipColor or 3,
    scale = blip.scale or garage.blipScale or 0.75,
    label = blip.label or garage.label or garage.name or 'Garagem'
  }
end

local function getGarageText(interact)
  if type(interact.text) == 'table' then
    return interact.text
  end

  return {
    enabled = true,
    label = interact.label or '[E] Abrir garagem',
    offsetZ = 0.35
  }
end

local function getStoreMarker(garage, interact)
  if type(interact.marker) == 'table' then
    local marker = cloneTable(interact.marker)
    local markerType = tonumber(marker.type) or 1

    if markerType == 9 then
      local textureDict, textureName = resolveStoreIcon(garage)
      if marker.textureDict == nil then marker.textureDict = textureDict end
      if marker.textureName == nil then marker.textureName = textureName end
    end

    return marker
  end

  return {
    enabled = true,
    type = 1,
    size = vec3(3.5, 3.5, 0.18),
    color = { r = 80, g = 210, b = 255, a = 70 },
    bobUpAndDown = false,
    rotate = false,
    faceCamera = false
  }
end

local function getStoreText(interact)
  if type(interact.text) == 'table' then
    return interact.text
  end

  return {
    enabled = true,
    label = interact.label or '[E] Guardar veiculo',
    offsetZ = 0.45
  }
end

local function registerGaragePoint(garageId, garage)
  if not canUseMzInteract() or type(garage) ~= 'table' then
    return
  end

  local coords = getGarageCoords(garage)
  if not coords then
    print(('[mz_garagem] Garagem %s sem coords para mz_interact.'):format(tostring(garageId)))
    return
  end

  local interact = getGarageInteractConfig(garage)
  if interact.enabled == false then
    return
  end

  local pointId = ('mz_garagem:%s'):format(tostring(garageId))
  local zoneRadius = type(garage.zone) == 'table' and tonumber(garage.zone.radius) or nil
  local interactDistance = tonumber(interact.interactDistance or zoneRadius or MZGaragemConfig.interaction_distance) or 2.0

  local ok, err = exports['mz_interact']:AddPoint({
    id = pointId,
    coords = coords,
    drawDistance = tonumber(interact.drawDistance or MZGaragemConfig.marker_draw_distance) or 25.0,
    interactDistance = interactDistance,

    -- Permissao aqui e apenas visual. A seguranca real segue no server-side.
    permission = garage.permission or interact.permission,

    marker = getGarageMarker(garage, interact),
    blip = getGarageBlip(garage, interact),
    text = getGarageText(interact),

    event = {
      type = 'client',
      name = 'mz_garagem:client:openFromInteract',
      args = { garageId }
    }
  })

  if ok ~= true then
    print(('[mz_garagem] Falha ao registrar %s no mz_interact: %s'):format(pointId, tostring(err)))
    return
  end

  registeredGaragePoints[pointId] = true
end

local function registerGarageStorePoint(garageId, garage)
  if not canUseMzInteract() or type(garage) ~= 'table' then
    return
  end

  local store = getStoreConfig(garage)
  if not store then
    return
  end

  local coords = getStoreCoords(store)
  if not coords then
    print(('[mz_garagem] Garagem %s sem coords de store para mz_interact.'):format(tostring(garageId)))
    return
  end

  local interact = type(store.interact) == 'table' and store.interact or {}
  if interact.enabled == false then
    return
  end

  local pointId = ('mz_garagem:store:%s'):format(tostring(garageId))
  local ok, err = exports['mz_interact']:AddPoint({
    id = pointId,
    coords = coords,
    active = false,
    drawDistance = tonumber(interact.drawDistance or MZGaragemConfig.marker_draw_distance) or 18.0,
    interactDistance = tonumber(interact.interactDistance or store.radius or MZGaragemConfig.interaction_distance) or 4.0,

    -- Permissao aqui e apenas visual. A seguranca real segue no server-side.
    permission = garage.permission or interact.permission,

    marker = getStoreMarker(garage, interact),
    blip = type(interact.blip) == 'table' and interact.blip or { enabled = false },
    text = getStoreText(interact),

    event = {
      type = 'client',
      name = 'mz_garagem:client:storeFromInteract',
      args = { garageId }
    }
  })

  if ok ~= true then
    print(('[mz_garagem] Falha ao registrar %s no mz_interact: %s'):format(pointId, tostring(err)))
    return
  end

  registeredGaragePoints[pointId] = true
  registeredGarageStorePoints[pointId] = true
end

local function unregisterGaragePoints()
  if GetResourceState('mz_interact') ~= 'started' then
    registeredGaragePoints = {}
    registeredGarageStorePoints = {}
    storePointsActive = nil
    return
  end

  for pointId in pairs(registeredGaragePoints) do
    exports['mz_interact']:RemovePoint(pointId)
  end

  registeredGaragePoints = {}
  registeredGarageStorePoints = {}
  storePointsActive = nil
end

local function registerGaragePoints()
  if not wantsMzInteract() then
    unregisterGaragePoints()
    return
  end

  if not canUseMzInteract() then
    print('[mz_garagem] mz_interact nao iniciado. Pontos da garagem nao foram registrados.')
    unregisterGaragePoints()
    return
  end

  unregisterGaragePoints()

  for garageId, garage in pairs(MZGaragemGarages or {}) do
    garage.id = garage.id or garageId
    registerGaragePoint(garageId, garage)
    registerGarageStorePoint(garageId, garage)
  end

  if MZGaragemConfig.debug == true then
    print(('[mz_garagem] %s pontos registrados no mz_interact.'):format(countRegisteredPoints()))
  end
end

AddEventHandler('mz_garagem:client:definitionsRefreshed', function()
  registerGaragePoints()
end)

CreateThread(function()
  Wait(1000)
  registerGaragePoints()
end)

AddEventHandler('onClientResourceStart', function(resourceName)
  if resourceName == 'mz_interact' or resourceName == GetCurrentResourceName() then
    Wait(1000)
    registerGaragePoints()
  end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
  if resourceName == GetCurrentResourceName() then
    unregisterGaragePoints()
  elseif resourceName == 'mz_interact' then
    registeredGaragePoints = {}
    registeredGarageStorePoints = {}
    storePointsActive = nil
  end
end)

CreateThread(function()
  while true do
    Wait(750)

    if not canUseMzInteract() then
      storePointsActive = nil
    else
      local ped = PlayerPedId()
      local vehicle = GetVehiclePedIsIn(ped, false)
      local shouldBeActive = vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped

      if storePointsActive ~= shouldBeActive then
        storePointsActive = shouldBeActive
        for pointId in pairs(registeredGarageStorePoints) do
          exports['mz_interact']:SetPointActive(pointId, shouldBeActive)
        end
      end
    end
  end
end)

RegisterNetEvent('mz_garagem:client:openFromInteract', function(garageId)
  if not garageId then
    return
  end

  local garage = MZGaragemGarages and MZGaragemGarages[garageId] or nil
  if not garage then
    print(('[mz_garagem] Garagem invalida recebida do mz_interact: %s'):format(tostring(garageId)))
    return
  end

  local ped = PlayerPedId()
  local vehicle = GetVehiclePedIsIn(ped, false)
  if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
    if MZGaragemClientHelpers and type(MZGaragemClientHelpers.notify) == 'function' then
      MZGaragemClientHelpers.notify('Use o ponto de estacionamento para guardar o veiculo.', 'info')
    end
    return
  end

  if MZGaragemClient and type(MZGaragemClient.openGarage) == 'function' then
    MZGaragemClient.openGarage(garageId)
  end
end)

RegisterNetEvent('mz_garagem:client:storeFromInteract', function(garageId)
  if MZGaragemClient and type(MZGaragemClient.storeCurrentVehicle) == 'function' then
    MZGaragemClient.storeCurrentVehicle(garageId)
  end
end)
