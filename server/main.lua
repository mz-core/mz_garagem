MZGaragem = MZGaragem or {
  state = {
    bootstrapped = false,
    garage_count = 0,
    service_garage_count = 0,
    fleet_count = 0
  }
}

MZGaragemHouseSessions = MZGaragemHouseSessions or {}

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function isGarageDebug()
  return MZGaragemConfig and MZGaragemConfig.debug == true
end

local function makeHouseGarageToken(source, houseCode)
  return ('house:%s:%s:%s:%s'):format(
    trim(houseCode),
    tostring(source or 0),
    tostring(os.time()),
    tostring(math.random(100000, 999999))
  )
end

local function normalizeGarageMode(value)
  value = trim(value):lower()
  if value == 'shared' then
    return 'shared'
  end

  return 'private'
end

local function asVector3(value)
  if type(value) == 'vector3' then
    return value
  end

  if type(value) == 'vector4' then
    return vector3(value.x, value.y, value.z)
  end

  if type(value) == 'table' then
    local x = tonumber(value.x or value[1])
    local y = tonumber(value.y or value[2])
    local z = tonumber(value.z or value[3])
    if x and y and z then
      return vector3(x, y, z)
    end
  end

  return nil
end

local function asVector4(value)
  if type(value) == 'vector4' then
    return value
  end

  if type(value) == 'vector3' then
    return vector4(value.x, value.y, value.z, 0.0)
  end

  if type(value) == 'table' then
    local x = tonumber(value.x or value[1])
    local y = tonumber(value.y or value[2])
    local z = tonumber(value.z or value[3])
    local w = tonumber(value.w or value.h or value.heading or value[4]) or 0.0
    if x and y and z then
      return vector4(x, y, z, w)
    end
  end

  return nil
end

local function vector3Payload(value)
  local coords = asVector3(value)
  if not coords then return nil end

  return {
    x = coords.x + 0.0,
    y = coords.y + 0.0,
    z = coords.z + 0.0
  }
end

local function vector4Payload(value)
  local coords = asVector4(value)
  if not coords then return nil end

  return {
    x = coords.x + 0.0,
    y = coords.y + 0.0,
    z = coords.z + 0.0,
    w = coords.w + 0.0
  }
end

local function safeJson(value)
  local ok, encoded = pcall(json.encode, value)
  if ok then
    return encoded
  end

  return tostring(encoded)
end

local function cloneHouseGarageForClient(garage)
  if type(garage) ~= 'table' then
    return nil
  end

  local store = type(garage.store) == 'table' and garage.store or {}
  local storeInteract = type(store.interact) == 'table' and store.interact or {}
  local storeMarker = type(storeInteract.marker) == 'table' and storeInteract.marker or {}
  local storeText = type(storeInteract.text) == 'table' and storeInteract.text or {}
  local storeBlip = type(storeInteract.blip) == 'table' and storeInteract.blip or {}

  local spawnPoints = {}
  for _, point in ipairs(garage.spawn_points or {}) do
    local normalizedPoint = vector4Payload(point)
    if normalizedPoint then
      spawnPoints[#spawnPoints + 1] = normalizedPoint
    end
  end

  return {
    id = tostring(garage.id or ''),
    label = tostring(garage.label or ''),
    kind = tostring(garage.kind or 'house'),
    zone = {
      coords = vector3Payload(garage.zone and garage.zone.coords),
      radius = tonumber(garage.zone and garage.zone.radius) or 3.0
    },
    spawn_points = spawnPoints,
    blip = false,
    store = {
      enabled = store.enabled == true,
      coords = vector3Payload(store.coords),
      radius = tonumber(store.radius) or 4.0,
      interact = {
        enabled = storeInteract.enabled == true,
        drawDistance = tonumber(storeInteract.drawDistance) or 18.0,
        interactDistance = tonumber(storeInteract.interactDistance) or tonumber(store.radius) or 4.0,
        marker = {
          enabled = storeMarker.enabled ~= false,
          type = tonumber(storeMarker.type) or 1,
          size = vector3Payload(storeMarker.size),
          color = storeMarker.color or { r = 80, g = 210, b = 255, a = 70 },
          bobUpAndDown = storeMarker.bobUpAndDown == true,
          rotate = storeMarker.rotate == true,
          faceCamera = storeMarker.faceCamera == true
        },
        text = {
          enabled = storeText.enabled ~= false,
          label = tostring(storeText.label or '[E] Guardar veiculo'),
          offsetZ = tonumber(storeText.offsetZ) or 0.45
        },
        blip = {
          enabled = storeBlip.enabled == true
        }
      }
    },
    filters = {
      categories = garage.filters and garage.filters.categories or { 'car', 'bike' }
    },
    rules = garage.rules or {
      strict_garage = false,
      shared_pool = true,
      allow_impounded = true
    },
    house = {
      code = garage.house and garage.house.code or nil,
      mode = garage.house and garage.house.mode or nil,
      slots = garage.house and garage.house.slots or nil,
      garage_id = garage.house and garage.house.garage_id or nil,
      session_seconds = garage.house and garage.house.session_seconds or nil
    }
  }
end

local function logInfo(message)
  print(('[mz_garagem] %s'):format(message))
end

local function logWarn(message)
  print(('[mz_garagem] warning: %s'):format(message))
end

local function validateFleetDefinition(fleetId, fleet)
  if type(fleet) ~= 'table' then
    return false, 'fleet_not_table'
  end

  if tostring(fleet.fleet_id or fleetId or '') == '' then
    return false, 'missing_fleet_id'
  end

  if type(fleet.entries) ~= 'table' or #fleet.entries == 0 then
    return false, 'missing_fleet_entries'
  end

  local seenEntryIds = {}

  for index, entry in ipairs(fleet.entries) do
    if type(entry) ~= 'table' then
      return false, ('fleet_entry_%s_not_table'):format(index)
    end

    local entryId = tostring(entry.entry_id or '')
    if entryId == '' then
      return false, ('fleet_entry_%s_missing_entry_id'):format(index)
    end

    if seenEntryIds[entryId] then
      return false, ('fleet_entry_%s_duplicate_entry_id'):format(entryId)
    end

    seenEntryIds[entryId] = true

    if tostring(entry.model or '') == '' then
      return false, ('fleet_entry_%s_missing_model'):format(entryId)
    end
  end

  return true
end

local function validateGarageReferences(garageId, garage)
  if garage.kind == 'service' then
    local fleet = MZGaragemServiceFleet and MZGaragemServiceFleet[garage.fleet_id] or nil
    local fleetOk, fleetErr = validateFleetDefinition(garage.fleet_id, fleet)
    if not fleetOk then
      error(('[mz_garagem] invalid service fleet for garage "%s": %s'):format(garageId, fleetErr))
    end
  end

  local orgCode = tostring(garage.org_code or '')
  if orgCode == '' then
    if garage.kind == 'service' and garage.access and (
      garage.access.require_membership == true or
      garage.access.require_duty == true or
      tonumber(garage.access.min_grade_level or 0) > 0 or
      garage.access.primary_only == true
    ) then
      logWarn(('garage "%s" has org access rules but no org_code; access falls back to public behavior'):format(garageId))
    end

    return
  end

  local org = exports['mz_core']:GetOrgByCode(orgCode)
  if not org then
    logWarn(('garage "%s" references org "%s" that was not found in mz_core; access will stay blocked until the org exists'):format(
      garageId,
      orgCode
    ))
  end
end

local function bootstrap()
  if MZGaragem.state.bootstrapped == true then
    return
  end

  local garageCount = 0
  local serviceGarageCount = 0
  local fleetIds = {}

  for garageId, garage in pairs(MZGaragemGarages or {}) do
    local ok, err = MZGaragemAccess.validateGarageDefinition(garageId, garage)
    if not ok then
      error(('[mz_garagem] invalid garage "%s": %s'):format(garageId, err))
    end

    validateGarageReferences(garageId, garage)

    garageCount = garageCount + 1
    if garage.kind == 'service' then
      serviceGarageCount = serviceGarageCount + 1
      fleetIds[tostring(garage.fleet_id or '')] = true
    end
  end

  for fleetId, fleet in pairs(MZGaragemServiceFleet or {}) do
    local ok, err = validateFleetDefinition(fleetId, fleet)
    if not ok then
      error(('[mz_garagem] invalid service fleet "%s": %s'):format(fleetId, err))
    end
  end

  math.randomseed((tonumber(GetGameTimer()) or 0) + os.time())

  MZGaragem.state.bootstrapped = true
  MZGaragem.state.garage_count = garageCount
  MZGaragem.state.service_garage_count = serviceGarageCount
  MZGaragem.state.fleet_count = 0

  for _ in pairs(fleetIds) do
    MZGaragem.state.fleet_count = MZGaragem.state.fleet_count + 1
  end

  logInfo(('ready with %d garage(s), %d service garage(s) and %d referenced fleet(s)'):format(
    MZGaragem.state.garage_count,
    MZGaragem.state.service_garage_count,
    MZGaragem.state.fleet_count
  ))
end

local function buildHouseGarage(descriptor, source)
  descriptor = type(descriptor) == 'table' and descriptor or {}

  local houseCode = trim(descriptor.houseCode)
  if houseCode == '' then
    return nil, 'invalid_house'
  end

  local entry = asVector3(descriptor.entry or descriptor.coords or descriptor.zone)
  local spawn = asVector4(descriptor.spawn)
  local store = asVector3(descriptor.store)

  if not entry then
    return nil, 'invalid_garage_entry'
  end

  if not spawn then
    return nil, 'invalid_garage_spawn'
  end

  if not store then
    return nil, 'invalid_garage_store'
  end

  local garageId = trim(descriptor.garageId or descriptor.garage_id)
  if garageId == '' then
    garageId = ('house:%s'):format(houseCode)
  end

  local garageMode = normalizeGarageMode(descriptor.garageMode or descriptor.mode)
  local slots = math.floor(tonumber(descriptor.slots) or 2)
  if slots < 1 then slots = 1 end

  local storeRadius = tonumber(descriptor.storeRadius) or 4.0
  local sessionSeconds = tonumber(descriptor.sessionSeconds) or 300
  local strictGarage = garageMode == 'private'

  return {
    id = garageId,
    label = trim(descriptor.label) ~= '' and trim(descriptor.label) or ('Garagem - ' .. houseCode),
    kind = 'house',
    zone = {
      coords = entry,
      radius = tonumber(descriptor.entryRadius) or 3.0
    },
    spawn_points = { spawn },
    blip = false,
    store = {
      enabled = true,
      coords = store,
      radius = storeRadius,
      interact = {
        enabled = true,
        drawDistance = math.max(18.0, storeRadius + 8.0),
        interactDistance = storeRadius,
        marker = {
          enabled = true,
          type = 1,
          size = vector3(storeRadius, storeRadius, 0.18),
          color = { r = 80, g = 210, b = 255, a = 70 },
          bobUpAndDown = false,
          rotate = false,
          faceCamera = false
        },
        text = {
          enabled = true,
          label = '[E] Guardar veiculo',
          offsetZ = 0.45
        },
        blip = {
          enabled = false
        }
      }
    },
    filters = {
      categories = type(descriptor.vehicleTypes) == 'table' and descriptor.vehicleTypes or { 'car', 'bike' }
    },
    rules = {
      strict_garage = strictGarage,
      shared_pool = not strictGarage,
      allow_impounded = true
    },
    house = {
      code = houseCode,
      mode = garageMode,
      slots = slots,
      garage_id = garageId,
      source = tonumber(source) or 0,
      session_seconds = sessionSeconds,
      sessions = {
        [tonumber(source) or 0] = {
          token = descriptor.token,
          expires_at = os.time() + sessionSeconds
        }
      }
    }
  }, nil, garageId
end

local function openHouseGarage(source, descriptor)
  local src = tonumber(source) or 0

  if isGarageDebug() then
    print(('[mz_garagem][OpenHouseGarage] called src=%s descriptorType=%s'):format(
      tostring(src),
      type(descriptor)
    ))
  end

  if src <= 0 then
    return {
      ok = false,
      error = 'invalid_source',
      detail = 'source must be a player server id'
    }
  end

  if type(descriptor) ~= 'table' then
    return {
      ok = false,
      error = 'invalid_descriptor',
      detail = 'descriptor must be a table'
    }
  end

  descriptor.token = trim(descriptor.token)
  if descriptor.token == '' then
    descriptor.token = makeHouseGarageToken(src, descriptor.houseCode)
  end

  if isGarageDebug() then
    print(('[mz_garagem][OpenHouseGarage] descriptor=%s'):format(safeJson({
      houseCode = descriptor.houseCode,
      garageId = descriptor.garageId or descriptor.garage_id,
      garageMode = descriptor.garageMode or descriptor.mode,
      slots = descriptor.slots,
      label = descriptor.label,
      entry = vector3Payload(descriptor.entry),
      spawn = vector4Payload(descriptor.spawn),
      store = vector3Payload(descriptor.store),
      storeRadius = descriptor.storeRadius,
      action = descriptor.action
    })))
  end

  local garage, err, garageId = buildHouseGarage(descriptor, src)
  if not garage then
    return {
      ok = false,
      error = err or 'invalid_house_garage',
      detail = 'house garage descriptor validation failed'
    }
  end

  MZGaragemGarages[garageId] = garage
  MZGaragemHouseSessions[src] = {
    token = descriptor.token,
    garage_id = garageId,
    garage_mode = garage.house and garage.house.mode or 'private',
    slots = garage.house and garage.house.slots or 2,
    house_code = garage.house and garage.house.code or descriptor.houseCode,
    expires_at = os.time() + (tonumber(garage.house and garage.house.session_seconds) or 300)
  }

  local clientGarage = cloneHouseGarageForClient(garage)
  if type(clientGarage) ~= 'table' or not clientGarage.zone.coords or #clientGarage.spawn_points == 0 or not clientGarage.store.coords then
    MZGaragemGarages[garageId] = nil
    return {
      ok = false,
      error = 'invalid_client_garage_payload',
      detail = 'failed to normalize house garage payload for client'
    }
  end

  clientGarage.context = {
    type = 'house',
    token = descriptor.token,
    houseCode = garage.house and garage.house.code or descriptor.houseCode,
    garageMode = garage.house and garage.house.mode or 'private',
    slots = garage.house and garage.house.slots or 2
  }

  clientGarage.house = clientGarage.house or {}
  clientGarage.house.token = descriptor.token

  local action = trim(descriptor.action) ~= '' and trim(descriptor.action) or 'open'
  TriggerClientEvent('mz_garagem:client:openHouseGarage', src, clientGarage, action)

  if isGarageDebug() then
    print(('[mz_garagem][house] session created source=%s house=%s garage=%s action=%s'):format(
      tostring(src),
      tostring(garage.house and garage.house.code or ''),
      tostring(garageId),
      tostring(action)
    ))
  end

  return {
    ok = true,
    garageId = garageId,
    houseCode = garage.house.code,
    garageMode = garage.house.mode,
    slots = garage.house.slots,
    token = descriptor.token
  }
end

exports('OpenHouseGarage', function(source, descriptor)
  local ok, result = xpcall(function()
    return openHouseGarage(source, descriptor)
  end, debug.traceback)

  if not ok then
    print(('[mz_garagem][house] OpenHouseGarage exception src=%s error=%s'):format(
      tostring(source),
      tostring(result)
    ))

    return {
      ok = false,
      error = 'house_garage_export_exception',
      detail = tostring(result)
    }
  end

  return result
end)

RegisterNetEvent('mz_garagem:server:closeHouseGarage', function(context)
  local src = source
  context = type(context) == 'table' and context or {}
  local token = tostring(context.token or '')
  local session = MZGaragemHouseSessions and MZGaragemHouseSessions[src] or nil

  if type(session) ~= 'table' or token == '' or tostring(session.token or '') ~= token then
    return
  end

  MZGaragemHouseSessions[src] = nil

  local garageId = tostring(session.garage_id or '')
  local garage = MZGaragemGarages and MZGaragemGarages[garageId] or nil
  if type(garage) == 'table' and garage.kind == 'house' and type(garage.house) == 'table' and type(garage.house.sessions) == 'table' then
    garage.house.sessions[src] = nil
    if next(garage.house.sessions) == nil then
      MZGaragemGarages[garageId] = nil
    end
  end
end)

CreateThread(function()
  Wait(0)
  if isGarageDebug() then
    print('[mz_garagem] house garage export debug loaded')
  end

  local ready, readinessResult = MZGaragemBootstrapReadiness.runWhenReady(function()
    if MZGaragemManaged and type(MZGaragemManaged.Initialize) == 'function' then
      MZGaragemManaged.Initialize()
    end

    bootstrap()
  end)

  if not ready then
    logWarn(('bootstrap blocked while organization owner is not ready: %s'):format(tostring(readinessResult)))
    return
  end

  logInfo(('organization readiness confirmed after %d probe(s) in %dms'):format(
    tonumber(readinessResult.attempts) or 0,
    tonumber(readinessResult.elapsedMs) or 0
  ))
end)

AddEventHandler('playerDropped', function()
  MZGaragemService.cleanupSource(source)
  MZGaragemHouseSessions[source] = nil

  for garageId, garage in pairs(MZGaragemGarages or {}) do
    if type(garage) == 'table' and garage.kind == 'house' and type(garage.house) == 'table' and type(garage.house.sessions) == 'table' then
      garage.house.sessions[source] = nil
      if next(garage.house.sessions) == nil then
        MZGaragemGarages[garageId] = nil
      end
    end
  end
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then
    return
  end

  MZGaragemService.resetAll()
end)
