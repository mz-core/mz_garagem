MZGaragemSpawn = MZGaragemSpawn or {}

local function round(value, decimals)
  local power = 10 ^ (decimals or 0)
  return math.floor((tonumber(value) or 0) * power + 0.5) / power
end

local function canUseVehiclesExports()
  return GetResourceState('mz_vehicles') == 'started'
end

local function logSpawnBridgeError(message, detail)
  print(('[mz_garagem][spawn] %s: %s'):format(
    tostring(message or 'unknown'),
    tostring(detail or 'unknown_error')
  ))
end

local function callVehiclesSpawnExport(prepared, payload)
  if not canUseVehiclesExports() then
    return false, nil, nil, 'mz_vehicles_unavailable'
  end

  local ok, a, b = pcall(function()
    return exports['mz_vehicles']:SpawnVehicleEntity({
      model_hash = prepared.model_hash,
      spawn_point = prepared.spawn_point,
      props = payload.props or {},
      plate = payload.plate,
      fuel = payload.fuel,
      engine = payload.engine,
      body = payload.body,
      warp_into_vehicle = MZGaragemConfig.warp_into_vehicle == true
    })
  end)

  if not ok then
    logSpawnBridgeError('mz_vehicles SpawnVehicleEntity failed', a)
    return false, nil, nil, 'mz_vehicles_export_failed'
  end

  return true, a, b, nil
end

local function spawnLocally(prepared, payload)
  local point = prepared.spawn_point
  local vehicle = CreateVehicle(prepared.model_hash, point.x, point.y, point.z, point.w, true, false)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    SetModelAsNoLongerNeeded(prepared.model_hash)
    return false, 'spawn_failed'
  end

  SetEntityAsMissionEntity(vehicle, true, true)
  SetVehicleHasBeenOwnedByPlayer(vehicle, true)
  SetVehRadioStation(vehicle, 'OFF')

  MZGaragemClientHelpers.setVehicleProperties(vehicle, payload.props or {})

  if payload.plate then
    SetVehicleNumberPlateText(vehicle, tostring(payload.plate))
  end

  SetVehicleFuelLevel(vehicle, (tonumber(payload.fuel) or 100) + 0.0)
  SetVehicleEngineHealth(vehicle, (tonumber(payload.engine) or 1000) + 0.0)
  SetVehicleBodyHealth(vehicle, (tonumber(payload.body) or 1000) + 0.0)
  SetVehicleOnGroundProperly(vehicle)
  SetVehicleEngineOn(vehicle, true, true, false)

  if MZGaragemConfig.warp_into_vehicle == true then
    TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
  end

  SetModelAsNoLongerNeeded(prepared.model_hash)

  return true, {
    vehicle = vehicle,
    plate = MZGaragemClientHelpers.getPlate(vehicle),
    net_id = NetworkGetNetworkIdFromEntity(vehicle)
  }
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
    return false, 'garage_not_found'
  end

  local modelHash, modelErr = MZGaragemClientHelpers.loadModel(model)
  if not modelHash then
    return false, modelErr
  end

  local spawnPoint = MZGaragemClientHelpers.findAvailableSpawnPoint(garage)
  if not spawnPoint then
    SetModelAsNoLongerNeeded(modelHash)
    return false, 'spawn_blocked'
  end

  return true, {
    garage = garage,
    model_hash = modelHash,
    spawn_point = spawnPoint
  }
end

function MZGaragemSpawn.spawn(prepared, payload)
  if type(prepared) ~= 'table' or type(payload) ~= 'table' then
    return false, 'invalid_spawn_payload'
  end

  local exportOk, spawnedOk, spawnedResult, bridgeErr = callVehiclesSpawnExport(prepared, payload)
  if exportOk then
    return spawnedOk, spawnedResult
  end

  if bridgeErr ~= 'mz_vehicles_unavailable' then
    return false, bridgeErr or 'mz_vehicles_spawn_failed'
  end

  logSpawnBridgeError('temporary local spawn fallback activated', bridgeErr)
  return spawnLocally(prepared, payload)
end

function MZGaragemSpawn.captureStorePayload(vehicle, runtimeId)
  local props = MZGaragemClientHelpers.getVehicleProperties(vehicle)

  return {
    plate = MZGaragemClientHelpers.getPlate(vehicle),
    props = props,
    fuel = round(GetVehicleFuelLevel(vehicle), 1),
    engine = round(GetVehicleEngineHealth(vehicle), 1),
    body = round(GetVehicleBodyHealth(vehicle), 1),
    runtime_id = runtimeId,
    net_id = NetworkGetNetworkIdFromEntity(vehicle)
  }
end
