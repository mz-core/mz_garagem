MZGaragemSpawn = MZGaragemSpawn or {}

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

local function normalizeNumber(value)
  local numericValue = tonumber(value)
  if numericValue == nil then
    return nil
  end

  return numericValue + 0.0
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

local function logSpawnPayloadSnapshot(stage, payload, point, modelHash)
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

  return {
    vehicle_model = vehicleModel,
    model_hash = modelHash,
    spawn_point = spawnPoint,
    props = type(payload.props) == 'table' and payload.props or {},
    plate = plate,
    fuel = tonumber(payload.fuel) or 100,
    engine = tonumber(payload.engine) or 1000,
    body = tonumber(payload.body) or 1000,
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
    return spawnedOk, spawnedResult
  end

  SetModelAsNoLongerNeeded(prepared.model_hash)
  return false, bridgeErr or 'mz_vehicles_spawn_failed'
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
