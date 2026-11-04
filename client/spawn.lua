MZGaragemSpawn = MZGaragemSpawn or {}

local DestroyedVisualApplied = {}
local InitialDestroyedProtectionByPlate = {}
local INITIAL_DESTROYED_PROTECTION_MS = 7000

local function round(value, decimals)
  local power = 10 ^ (decimals or 0)
  return math.floor((tonumber(value) or 0) * power + 0.5) / power
end

local function trimScalarString(value)
  local valueType = type(value)
  if valueType == 'string' or valueType == 'number' or valueType == 'boolean' then
    return tostring(value):gsub('^%s+', ''):gsub('%s+$', '')
  end

  return ''
end

local function canUseVehiclesExports()
  return GetResourceState('mz_vehicles') == 'started'
end

local function canUseFuelExports()
  return GetResourceState('mz_fuel') == 'started'
end

local function isGarageDebug()
  return MZGaragemConfig and MZGaragemConfig.debug == true
end

local function normalizeNumber(value)
  local numericValue = tonumber(value)
  if numericValue == nil then
    return nil
  end

  return numericValue + 0.0
end

local function normalizeVehicleHealth(value)
  local numericValue = tonumber(value)
  if numericValue == nil then
    return 1000.0
  end

  if numericValue < 0.0 then
    return 0.0
  end

  if numericValue > 1000.0 then
    return 1000.0
  end

  return numericValue + 0.0
end

local function getPayloadTankHealth(payload)
  if type(payload) ~= 'table' then
    return nil
  end

  return payload.tank or payload.tank_health or payload.petrol_tank_health or payload.petrolTankHealth
end

local function clampFuel(value)
  local fuel = tonumber(value) or 100.0
  if fuel < 0.0 then
    return 0.0
  end
  if fuel > 100.0 then
    return 100.0
  end
  return fuel + 0.0
end

local function getVehicleFuel(vehicle)
  if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and canUseFuelExports() then
    local ok, fuel = pcall(function()
      return exports['mz_fuel']:GetFuel(vehicle)
    end)

    if ok and tonumber(fuel) ~= nil then
      return clampFuel(fuel)
    end
  end

  if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
    return clampFuel(GetVehicleFuelLevel(vehicle))
  end

  return 100.0
end

local function setVehicleFuel(vehicle, fuel)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return false
  end

  fuel = clampFuel(fuel)

  if canUseFuelExports() then
    local ok, result = pcall(function()
      return exports['mz_fuel']:SetFuel(vehicle, fuel)
    end)

    if ok and result ~= false then
      return true
    end
  end

  SetVehicleFuelLevel(vehicle, fuel)
  return true
end

local function normalizeSpawnPoint(point)
  local pointType = type(point)
  if pointType ~= 'table' and pointType ~= 'vector3' and pointType ~= 'vector4' then
    return nil
  end

  local x = normalizeNumber(point.x)
  local y = normalizeNumber(point.y)
  local z = normalizeNumber(point.z)
  if x == nil or y == nil or z == nil then
    return nil
  end

  local normalized = {
    x = x,
    y = y,
    z = z
  }

  local heading = normalizeNumber(point.w or point.heading)
  if heading ~= nil then
    normalized.w = heading
  end

  return normalized
end

local function logSpawnBridgeError(message, detail)
  print(('[mz_garagem][spawn] %s: %s'):format(
    tostring(message or 'unknown'),
    tostring(detail or 'unknown_error')
  ))
end

local function logVehicleWorld(message)
  if not isGarageDebug() then
    return
  end

  print(('[mz_vehicle_world] %s'):format(tostring(message or '')))
end

local function applyDestroyedVisualOnce(vehicle, plate)
  plate = trimScalarString(plate):upper()
  if plate == '' or DestroyedVisualApplied[plate] == true then
    return false
  end

  DestroyedVisualApplied[plate] = true
  logVehicleWorld(('apply destroyed visual once %s'):format(plate))

  if type(SetVehicleTyreBurst) ~= 'function' then
    return true
  end

  for tyre = 0, 7 do
    local alreadyBurst = false
    if type(IsVehicleTyreBurst) == 'function' then
      local ok, result = pcall(IsVehicleTyreBurst, vehicle, tyre, false)
      alreadyBurst = ok and result == true
    end

    if alreadyBurst ~= true then
      pcall(SetVehicleTyreBurst, vehicle, tyre, true, 1000.0)
    end
  end

  return true
end

local function enforceDestroyedUndriveable(vehicle)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return false
  end

  pcall(SetVehicleEngineHealth, vehicle, -4000.0)
  pcall(SetVehicleBodyHealth, vehicle, 50.0)
  if type(SetVehiclePetrolTankHealth) == 'function' then
    pcall(SetVehiclePetrolTankHealth, vehicle, 0.0)
  end
  pcall(SetVehicleEngineOn, vehicle, false, true, true)
  pcall(SetVehicleUndriveable, vehicle, true)

  return true
end

local function applyDestroyedUndriveable(vehicle, plate)
  plate = trimScalarString(plate):upper()
  if plate == '' or not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return false
  end

  logVehicleWorld(('apply destroyed undriveable %s'):format(plate))
  applyDestroyedVisualOnce(vehicle, plate)
  enforceDestroyedUndriveable(vehicle)

  CreateThread(function()
    Wait(500)
    enforceDestroyedUndriveable(vehicle)
    Wait(1000)
    enforceDestroyedUndriveable(vehicle)
  end)

  return true
end

local function logSpawnPayloadSnapshot(stage, payload, point, modelHash)
  if not isGarageDebug() then
    return
  end

  local pointType = type(point)
  local hasX = point ~= nil and point.x ~= nil
  local hasY = point ~= nil and point.y ~= nil
  local hasZ = point ~= nil and point.z ~= nil
  local hasW = point ~= nil and point.w ~= nil

  print(('[mz_garagem][spawn][%s] vehicle_model=%s | model=%s | plate=%s | model_hash=%s | spawn_point=%s'):format(
    tostring(stage or 'snapshot'),
    type(payload) == 'table' and tostring(payload.vehicle_model or '') or 'nil',
    type(payload) == 'table' and tostring(payload.model or '') or 'nil',
    type(payload) == 'table' and tostring(payload.plate or '') or 'nil',
    tostring(modelHash),
    tostring(point)
  ))

  print(('[mz_garagem][spawn][%s] spawn_point_type=%s | has_x=%s value_x=%s | has_y=%s value_y=%s | has_z=%s value_z=%s | has_w=%s value_w=%s'):format(
    tostring(stage or 'snapshot'),
    tostring(pointType),
    tostring(hasX),
    tostring(hasX and point.x or nil),
    tostring(hasY),
    tostring(hasY and point.y or nil),
    tostring(hasZ),
    tostring(hasZ and point.z or nil),
    tostring(hasW),
    tostring(hasW and point.w or nil)
  ))
end

local function logHealthNormalization(stage, rawEngine, rawBody, rawTank, engine, body, tank)
  if not isGarageDebug() then
    return
  end

  print(('[mz_garagem][spawn][%s] raw_engine=%s | raw_body=%s | raw_tank=%s | normalized_engine=%s | normalized_body=%s | normalized_tank=%s'):format(
    tostring(stage or 'health'),
    tostring(rawEngine),
    tostring(rawBody),
    tostring(rawTank),
    tostring(engine),
    tostring(body),
    tostring(tank)
  ))
end

local function logDestroyedResolution(payloadDestroyed, snapshotDestroyed, finalDestroyed, ignoredInitialDestroyed)
  if not isGarageDebug() then
    return
  end

  print(('[mz_garagem][spawn][confirm] payload_destroyed=%s | snapshot_destroyed=%s | final_destroyed=%s | ignored_initial_destroyed=%s'):format(
    tostring(payloadDestroyed),
    tostring(snapshotDestroyed),
    tostring(finalDestroyed),
    tostring(ignoredInitialDestroyed)
  ))
end

local function buildSpawnPayload(prepared, payload)
  local rawPoint = nil
  if type(payload) == 'table' and payload.spawn_point ~= nil then
    rawPoint = payload.spawn_point
  elseif type(prepared) == 'table' then
    rawPoint = prepared.spawn_point
  end

  logSpawnPayloadSnapshot('build_input', payload, rawPoint, type(prepared) == 'table' and prepared.model_hash or nil)

  if type(prepared) ~= 'table' or type(payload) ~= 'table' then
    return nil, 'invalid_spawn_payload'
  end

  local vehicleModel = trimScalarString(payload.vehicle_model or payload.model or prepared.vehicle_model)
  local plate = trimScalarString(payload.plate)
  local spawnPoint = normalizeSpawnPoint(payload.spawn_point or prepared.spawn_point)
  local modelHash = tonumber(prepared.model_hash)

  if vehicleModel == '' or plate == '' or not spawnPoint or not modelHash or modelHash == 0 then
    return nil, 'invalid_spawn_payload'
  end

  local rawEngine = payload.engine
  local rawBody = payload.body
  local rawTank = getPayloadTankHealth(payload)
  local engine = normalizeVehicleHealth(rawEngine)
  local body = normalizeVehicleHealth(rawBody)
  local tank = normalizeVehicleHealth(rawTank)

  logHealthNormalization('build_payload', rawEngine, rawBody, rawTank, engine, body, tank)

  return {
    kind = trimScalarString(payload.kind),
    runtime_id = trimScalarString(payload.runtime_id),
    garage_id = trimScalarString(payload.garage_id),
    org_code = trimScalarString(payload.org_code),
    vehicle_model = vehicleModel,
    model_hash = modelHash,
    spawn_point = spawnPoint,
    props = type(payload.props) == 'table' and payload.props or {},
    plate = plate,
    fuel = tonumber(payload.fuel) or 100,
    engine = engine,
    body = body,
    tank = tank,
    destroyed = payload.destroyed == true or (type(payload.world) == 'table' and payload.world.destroyed == true),
    world = type(payload.world) == 'table' and payload.world or nil,
    warp_into_vehicle = payload.warp_into_vehicle == true or MZGaragemConfig.warp_into_vehicle == true
  }
end

local function callVehiclesSpawnExport(spawnPayload)
  logSpawnPayloadSnapshot('export_payload', spawnPayload, type(spawnPayload) == 'table' and spawnPayload.spawn_point or nil, type(spawnPayload) == 'table' and spawnPayload.model_hash or nil)

  if not canUseVehiclesExports() then
    return false, nil, nil, 'mz_vehicles_unavailable'
  end

  local ok, a, b = pcall(function()
    return exports['mz_vehicles']:SpawnVehicleEntity(spawnPayload)
  end)

  if not ok then
    logSpawnBridgeError('mz_vehicles SpawnVehicleEntity failed', a)
    return false, nil, nil, 'mz_vehicles_export_failed'
  end

  return true, a, b, nil
end

local function getGarage(garageId)
  local garage = MZGaragemGarages and MZGaragemGarages[garageId] or nil
  if garage then
    garage.id = garage.id or garageId
  end
  return garage
end

function MZGaragemSpawn.prepareSpawn(garageId, model)
  local garage = getGarage(garageId)
  if not garage then
    logSpawnBridgeError('prepareSpawn', 'garage_not_found')
    return false, 'garage_not_found'
  end

  local modelType = type(model)
  local normalizedModel = modelType == 'string' and trimScalarString(model) or model
  if modelType ~= 'number' and (modelType ~= 'string' or normalizedModel == '') then
    logSpawnBridgeError('prepareSpawn', ('invalid model input type:%s value:%s'):format(
      tostring(modelType),
      tostring(model)
    ))
    return false, 'invalid_vehicle_model'
  end

  local modelHash, modelErr = MZGaragemClientHelpers.loadModel(normalizedModel)
  if not modelHash then
    logSpawnBridgeError('prepareSpawn', ('loadModel failed: %s | model_type:%s | model:%s'):format(
      tostring(modelErr or 'unknown_model_error'),
      tostring(modelType),
      tostring(normalizedModel)
    ))
    return false, modelErr or 'unknown_model_error'
  end

  local spawnPoint = MZGaragemClientHelpers.findAvailableSpawnPoint(garage)
  if not spawnPoint then
    SetModelAsNoLongerNeeded(modelHash)
    logSpawnBridgeError('prepareSpawn', 'findAvailableSpawnPoint returned nil for garage: ' .. tostring(garageId))
    return false, 'spawn_blocked'
  end

  return true, {
    garage = garage,
    model_hash = modelHash,
    vehicle_model = trimScalarString(normalizedModel),
    spawn_point = spawnPoint
  }
end

function MZGaragemSpawn.spawn(prepared, payload)
  local entryPoint = nil
  if type(payload) == 'table' and payload.spawn_point ~= nil then
    entryPoint = payload.spawn_point
  elseif type(prepared) == 'table' then
    entryPoint = prepared.spawn_point
  end

  logSpawnPayloadSnapshot('spawn_entry', payload, entryPoint, type(prepared) == 'table' and prepared.model_hash or nil)

  if type(prepared) ~= 'table' or type(payload) ~= 'table' then
    return false, 'invalid_spawn_payload'
  end

  local spawnPayload, payloadErr = buildSpawnPayload(prepared, payload)
  if not spawnPayload then
    SetModelAsNoLongerNeeded(prepared.model_hash)
    return false, payloadErr or 'invalid_spawn_payload'
  end

  local exportOk, spawnedOk, spawnedResult, bridgeErr = callVehiclesSpawnExport(spawnPayload)
  if exportOk then
    if spawnedOk == true and type(spawnedResult) == 'table' and spawnedResult.vehicle then
      MZGaragemSpawn.finalizeSpawnedVehicle(spawnedResult.vehicle, spawnPayload)
      InitialDestroyedProtectionByPlate[trimScalarString(spawnPayload.plate):upper()] = {
        destroyed = spawnPayload.destroyed == true,
        expires_at = GetGameTimer() + INITIAL_DESTROYED_PROTECTION_MS
      }
    end

    return spawnedOk, spawnedResult
  end

  SetModelAsNoLongerNeeded(prepared.model_hash)
  return false, bridgeErr or 'mz_vehicles_spawn_failed'
end

function MZGaragemSpawn.captureStorePayload(vehicle, runtimeId)
  local props = MZGaragemClientHelpers.getVehicleProperties(vehicle)
  if type(props) == 'table' then
    props.engineHealth = nil
    props.bodyHealth = nil
    props.tankHealth = nil
    props.fuelLevel = nil
  end

  local coords = vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and GetEntityCoords(vehicle) or nil
  local engineHealth = vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and GetVehicleEngineHealth(vehicle) or 1000.0
  local bodyHealth = vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and GetVehicleBodyHealth(vehicle) or 1000.0
  local destroyed = vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and (
    IsEntityDead(vehicle)
      or (tonumber(engineHealth) or 1000.0) <= 50.0
      or (tonumber(bodyHealth) or 1000.0) <= 100.0
  ) or false

  return {
    plate = MZGaragemClientHelpers.getPlate(vehicle),
    props = props,
    fuel = round(getVehicleFuel(vehicle), 1),
    engine = round(engineHealth, 1),
    body = round(bodyHealth, 1),
    coords = coords and {
      x = round(coords.x, 3),
      y = round(coords.y, 3),
      z = round(coords.z, 3)
    } or nil,
    heading = vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and round(GetEntityHeading(vehicle), 2) or 0.0,
    locked = vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and GetVehicleDoorLockStatus(vehicle) or 0,
    destroyed = destroyed,
    runtime_id = runtimeId,
    net_id = NetworkGetNetworkIdFromEntity(vehicle)
  }
end

local function findVehicleByPlate(plate)
  plate = trimScalarString(plate):upper()
  if plate == '' then
    return 0
  end

  for _, vehicle in ipairs(GetGamePool('CVehicle')) do
    if DoesEntityExist(vehicle) and MZGaragemClientHelpers.getPlate(vehicle) == plate then
      return vehicle
    end
  end

  return 0
end

local function normalizeLockValue(value, oneMeansLocked)
  if value == true then
    return true
  end

  local numeric = tonumber(value)
  if numeric == nil then
    return false
  end

  if numeric == 1 then
    return oneMeansLocked == true
  end

  return numeric ~= 0
end

function MZGaragemSpawn.finalizeSpawnedVehicle(vehicle, data)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return false, 'entity_not_found'
  end

  data = type(data) == 'table' and data or {}
  local world = type(data.world) == 'table' and data.world or {}
  local plate = trimScalarString(data.plate):upper()
  if plate == '' then
    plate = MZGaragemClientHelpers.getPlate(vehicle)
  end

  if plate ~= '' then
    SetVehicleNumberPlateText(vehicle, plate)
  end

  if type(data.props) == 'table' and GetResourceState('mz_vehicles') == 'started' then
    pcall(function()
      exports['mz_vehicles']:SetVehicleProperties(vehicle, data.props)
    end)
  end

  if data.fuel ~= nil then
    setVehicleFuel(vehicle, data.fuel)
  end

  if data.engine ~= nil then
    SetVehicleEngineHealth(vehicle, normalizeVehicleHealth(data.engine))
  end

  if data.body ~= nil then
    SetVehicleBodyHealth(vehicle, normalizeVehicleHealth(data.body))
  end

  local tankHealth = getPayloadTankHealth(data)
  if tankHealth ~= nil and type(SetVehiclePetrolTankHealth) == 'function' then
    SetVehiclePetrolTankHealth(vehicle, normalizeVehicleHealth(tankHealth))
  end

  local locked
  if world.locked ~= nil then
    locked = normalizeLockValue(world.locked, true)
  elseif data.locked ~= nil then
    locked = normalizeLockValue(data.locked, false)
  else
    locked = GetVehicleDoorLockStatus(vehicle) ~= 0 and GetVehicleDoorLockStatus(vehicle) ~= 1
  end

  SetVehicleDoorsLocked(vehicle, locked and 2 or 1)
  SetVehicleDoorsLockedForAllPlayers(vehicle, locked)
  local destroyed = data.destroyed == true or (type(data.world) == 'table' and data.world.destroyed == true)

  local entityState = Entity(vehicle).state
  if entityState then
    entityState:set('mz_plate', plate, true)
    local isService = data.kind == 'service'
    entityState:set('mz_persistent', not isService, true)
    if isService then
      entityState:set('mz_service_runtime_id', tostring(data.runtime_id or ''), true)
      entityState:set('mz_service_org_code', tostring(data.org_code or ''), true)
    end
    local vehicleId = tonumber(data.id or data.vehicle_id)
    if vehicleId then
      entityState:set('mz_vehicle_id', vehicleId, true)
    end
    if data.owner_type ~= nil and tostring(data.owner_type) ~= '' then
      entityState:set('mz_owner_type', tostring(data.owner_type), true)
    end
    if data.owner_id ~= nil and tostring(data.owner_id) ~= '' then
      entityState:set('mz_owner_id', tostring(data.owner_id), true)
    end
    entityState:set('mz_locked', locked, true)
    entityState:set('mz_lock_state', locked and 2 or 1, true)
    entityState:set('mz_destroyed', destroyed, true)
    entityState:set('mz_world_condition', {
      fuel = tonumber(data.fuel) or getVehicleFuel(vehicle),
      engine = data.engine ~= nil and normalizeVehicleHealth(data.engine) or GetVehicleEngineHealth(vehicle),
      body = data.body ~= nil and normalizeVehicleHealth(data.body) or GetVehicleBodyHealth(vehicle),
      tank = tankHealth ~= nil and normalizeVehicleHealth(tankHealth) or nil,
      locked = locked,
      destroyed = destroyed
    }, true)
  end

  if destroyed == true then
    applyDestroyedUndriveable(vehicle, plate)
  end

  logVehicleWorld(('finalize spawn %s locked=%s netId=%s'):format(
    plate,
    tostring(locked),
    tostring(NetworkGetNetworkIdFromEntity(vehicle))
  ))
  logVehicleWorld(('lock state applied %s locked=%s'):format(plate, tostring(locked)))

  return true, {
    plate = plate,
    locked = locked,
    net_id = NetworkGetNetworkIdFromEntity(vehicle)
  }
end

function MZGaragemSpawn.capturePersistentSnapshot(vehicle)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return nil
  end

  local payload = MZGaragemSpawn.captureStorePayload(vehicle)
  if not payload or tostring(payload.plate or '') == '' then
    return nil
  end

  return payload
end

function MZGaragemSpawn.reportPersistentVehicle(vehicle)
  local snapshot = MZGaragemSpawn.capturePersistentSnapshot(vehicle)
  if not snapshot then
    return false
  end

  TriggerServerEvent('mz_garagem:server:persistentVehicleSnapshot', snapshot.plate, snapshot)
  return true
end

function MZGaragemSpawn.confirmPersistentVehicleSpawn(vehicle, data)
  local payloadDestroyed = type(data) == 'table'
    and (data.destroyed == true or (type(data.world) == 'table' and data.world.destroyed == true))
    or nil

  if type(data) == 'table' then
    MZGaragemSpawn.finalizeSpawnedVehicle(vehicle, data)
  end

  local snapshot = MZGaragemSpawn.capturePersistentSnapshot(vehicle)
  if not snapshot then
    return false
  end

  local snapshotDestroyed = snapshot.destroyed == true
  local plate = trimScalarString(snapshot.plate):upper()
  local protection = InitialDestroyedProtectionByPlate[plate]
  local protectionActive = type(protection) == 'table' and GetGameTimer() <= (tonumber(protection.expires_at) or 0)
  if type(protection) == 'table' and not protectionActive then
    InitialDestroyedProtectionByPlate[plate] = nil
  end

  if protectionActive and payloadDestroyed == nil then
    payloadDestroyed = protection.destroyed == true
  end

  local ignoredInitialDestroyed = protectionActive and payloadDestroyed == false and snapshotDestroyed == true
  local finalDestroyed = snapshotDestroyed
  if payloadDestroyed ~= nil then
    finalDestroyed = payloadDestroyed == true
    if ignoredInitialDestroyed then
      snapshot.destroyed = false
    end
  end

  logDestroyedResolution(payloadDestroyed, snapshotDestroyed, finalDestroyed, ignoredInitialDestroyed)

  MZGaragemSpawn.finalizeSpawnedVehicle(vehicle, {
    plate = snapshot.plate,
    locked = snapshot.locked,
    fuel = snapshot.fuel,
    engine = type(data) == 'table' and data.engine or snapshot.engine,
    body = type(data) == 'table' and data.body or snapshot.body,
    tank = type(data) == 'table' and getPayloadTankHealth(data) or getPayloadTankHealth(snapshot),
    destroyed = finalDestroyed,
    id = type(data) == 'table' and data.id or nil,
    vehicle_id = type(data) == 'table' and data.vehicle_id or nil,
    owner_type = type(data) == 'table' and data.owner_type or nil,
    owner_id = type(data) == 'table' and data.owner_id or nil
  })

  TriggerServerEvent('mz_garagem:server:persistentVehicleSpawned', snapshot.plate, snapshot.net_id, snapshot)
  return true
end

function MZGaragemSpawn.respawnPersistentVehicle(data)
  if type(data) ~= 'table' then
    return false, 'invalid_payload'
  end

  local plate = trimScalarString(data.plate):upper()
  if plate == '' then
    return false, 'invalid_plate'
  end

  local existing = findVehicleByPlate(plate)
  if existing ~= 0 then
    logVehicleWorld(('skip duplicate %s'):format(plate))
    MZGaragemSpawn.confirmPersistentVehicleSpawn(existing, data)
    return true, {
      vehicle = existing,
      plate = plate,
      net_id = NetworkGetNetworkIdFromEntity(existing)
    }
  end

  local world = type(data.world) == 'table' and data.world or {}
  local coords = type(world.last_coords) == 'table' and world.last_coords or nil
  if not coords or coords.x == nil or coords.y == nil or coords.z == nil then
    logVehicleWorld(('respawn failed %s missing_coords'):format(plate))
    return false, 'missing_coords'
  end

  logVehicleWorld(('respawn attempt %s %s %.3f %.3f %.3f'):format(
    plate,
    tostring(data.model or ''),
    tonumber(coords.x) or 0.0,
    tonumber(coords.y) or 0.0,
    tonumber(coords.z) or 0.0
  ))

  local modelHash, modelErr = MZGaragemClientHelpers.loadModel(data.model)
  if not modelHash then
    logVehicleWorld(('respawn failed %s %s'):format(plate, tostring(modelErr or 'invalid_model')))
    return false, modelErr or 'invalid_model'
  end

  local spawnPayload = {
    vehicle_model = trimScalarString(data.model),
    model_hash = modelHash,
    spawn_point = {
      x = tonumber(coords.x) or 0.0,
      y = tonumber(coords.y) or 0.0,
      z = tonumber(coords.z) or 0.0,
      w = tonumber(world.last_heading) or 0.0
    },
    props = type(data.props) == 'table' and data.props or {},
    plate = plate,
    fuel = tonumber(data.fuel) or 100,
    engine = tonumber(data.engine) or 1000,
    body = tonumber(data.body) or 1000,
    warp_into_vehicle = false,
    engine_on = false
  }

  local exportOk, spawnedOk, spawnedResult, bridgeErr = callVehiclesSpawnExport(spawnPayload)
  if not exportOk then
    SetModelAsNoLongerNeeded(modelHash)
    logVehicleWorld(('respawn failed %s %s'):format(plate, tostring(bridgeErr or 'mz_vehicles_spawn_failed')))
    return false, bridgeErr or 'mz_vehicles_spawn_failed'
  end

  if spawnedOk ~= true or type(spawnedResult) ~= 'table' or not spawnedResult.vehicle then
    logVehicleWorld(('respawn failed %s %s'):format(plate, tostring(spawnedResult or 'spawn_failed')))
    return false, spawnedResult or 'spawn_failed'
  end

  MZGaragemSpawn.confirmPersistentVehicleSpawn(spawnedResult.vehicle, data)
  logVehicleWorld(('respawn success %s %s'):format(plate, tostring(NetworkGetNetworkIdFromEntity(spawnedResult.vehicle))))
  return true, spawnedResult
end
