local function openGarageList(source, access)
  if access.kind == 'public' then
    return MZGaragemOwned.list(source, access)
  end

  if access.kind == 'org' then
    return MZGaragemOrg.list(source, access)
  end

  if access.kind == 'service' then
    return MZGaragemService.list(source, access)
  end

  return false, 'invalid_kind'
end

local function isGarageDebug()
  return MZGaragemConfig and MZGaragemConfig.debug == true
end

local function logGarageFlow(stage, source, detail, extra)
  if not isGarageDebug() then
    return
  end

  print(('[mz_garagem][%s][source:%s] %s%s'):format(
    tostring(stage or 'flow'),
    tostring(source or 'unknown'),
    tostring(detail or 'unknown'),
    extra and (' | ' .. tostring(extra)) or ''
  ))
end

local function logOpenGarageCallback(stage, source, garage, detail)
  if not isGarageDebug() then
    return
  end

  garage = type(garage) == 'table' and garage or {}
  detail = type(detail) == 'table' and detail or {}

  local access = type(garage.access) == 'table' and garage.access or {}

  print(('[mz_garagem][open_callback][%s][source:%s] garage_id=%s | kind=%s | org_code=%s | require_membership=%s | require_duty=%s | fleet_id=%s | entries_count=%s | error=%s'):format(
    tostring(stage or 'unknown'),
    tostring(source or 'unknown'),
    tostring(garage.id or detail.garage_id or ''),
    tostring(garage.kind or ''),
    tostring(garage.org_code or ''),
    tostring(access.require_membership),
    tostring(access.require_duty),
    tostring(garage.fleet_id or ''),
    tostring(detail.entries_count or 0),
    tostring(detail.error or '')
  ))
end

local function errorResponse(stage, err, extra)
  local payload = {
    ok = false,
    stage = tostring(stage or 'unknown'),
    error = tostring(err or 'unknown_error')
  }

  if type(extra) == 'table' then
    for key, value in pairs(extra) do
      payload[key] = value
    end
  end

  return payload
end

local function NormalizePlate(plate)
  return tostring(plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
end

local function canUseVehicleAccessExports()
  return GetResourceState('mz_vehicles') == 'started'
end

local function grantVehicleAccess(source, access, payload)
  if not canUseVehicleAccessExports() or type(payload) ~= 'table' then
    return
  end

  local plate = NormalizePlate(payload.plate)
  if plate == '' then
    return
  end

  local ok, err = pcall(function()
    exports['mz_vehicles']:GrantVehicleAccess(source, plate, {
      kind = tostring(access.kind or ''),
      garage_id = tostring(access.garage and access.garage.id or ''),
      org_code = access.garage and access.garage.org_code and tostring(access.garage.org_code) or nil,
      model = tostring(payload.vehicle_model or payload.model or ''),
      runtime_id = payload.runtime_id and tostring(payload.runtime_id) or nil
    })
  end)

  if not ok then
    logGarageFlow('vehicle_access', source, 'grant_failed', err)
  end
end

local function grantRespawnVehicleAccess(source, vehicleData)
  if not canUseVehicleAccessExports() or type(vehicleData) ~= 'table' then
    return
  end

  local plate = NormalizePlate(vehicleData.plate)
  if plate == '' then
    return
  end

  local ok, err = pcall(function()
    exports['mz_vehicles']:GrantVehicleAccess(source, plate, {
      kind = tostring(vehicleData.owner_type or 'persistent'),
      garage_id = tostring(vehicleData.garage or ''),
      owner_type = vehicleData.owner_type and tostring(vehicleData.owner_type) or nil,
      owner_id = vehicleData.owner_id and tostring(vehicleData.owner_id) or nil,
      model = tostring(vehicleData.vehicle_model or vehicleData.model or ''),
      persistent = true
    })
  end)

  if not ok then
    logGarageFlow('vehicle_access', source, 'respawn_grant_failed', err)
  end
end

local function revokeVehicleAccess(source, plate)
  if not canUseVehicleAccessExports() then
    return
  end

  local normalizedPlate = NormalizePlate(plate)
  if normalizedPlate == '' then
    return
  end

  local ok, err = pcall(function()
    exports['mz_vehicles']:RevokeVehicleAccess(source, normalizedPlate)
  end)

  if not ok then
    logGarageFlow('vehicle_access', source, 'revoke_failed', err)
  end
end

local function validateStorePosition(source, access, payload)
  payload = type(payload) == 'table' and payload or {}

  local garage = access.garage or {}
  local maxGarageDistance = tonumber(MZGaragemConfig.maxGarageDistance or 12.0) or 12.0
  local validationPoints = {}

  if garage.zone and garage.zone.coords then
    validationPoints[#validationPoints + 1] = {
      coords = garage.zone.coords,
      distance = maxGarageDistance
    }
  end

  if type(garage.store) == 'table' and garage.store.enabled == true and garage.store.coords then
    local storeInteract = type(garage.store.interact) == 'table' and garage.store.interact or {}
    local storeDistance = tonumber(storeInteract.interactDistance or garage.store.radius or maxGarageDistance) or maxGarageDistance
    validationPoints[#validationPoints + 1] = {
      coords = garage.store.coords,
      distance = math.max(maxGarageDistance, storeDistance)
    }
  end

  if #validationPoints == 0 then
    return false, 'garage_not_found'
  end

  local playerPed = GetPlayerPed(source)
  if not playerPed or playerPed == 0 then
    return false, 'player_not_found'
  end

  local playerCoords = GetEntityCoords(playerPed)
  local netId = tonumber(payload.net_id or 0) or 0
  local vehicleCoords = nil

  if netId > 0 then
    local entity = 0
    if type(NetworkGetEntityFromNetworkId) == 'function' then
      local ok, result = pcall(NetworkGetEntityFromNetworkId, netId)
      if ok then
        entity = result or 0
      end
    end

    local exists = entity and entity ~= 0
    if exists and type(DoesEntityExist) == 'function' then
      local existsOk, existsResult = pcall(DoesEntityExist, entity)
      exists = existsOk and existsResult == true
    end

    if exists then
      vehicleCoords = GetEntityCoords(entity)
    end
  end

  for _, point in ipairs(validationPoints) do
    local playerNear = #(playerCoords - point.coords) <= point.distance
    local vehicleNear = not vehicleCoords or #(vehicleCoords - point.coords) <= point.distance

    if playerNear and vehicleNear then
      return true
    end
  end

  if vehicleCoords then
    return false, 'vehicle_too_far_from_garage'
  end

  return false, 'player_too_far_from_garage'
end

lib.callback.register('mz_garagem:server:openGarage', function(source, garageId)
  local requestedGarage = MZGaragemAccess.getGarage(garageId)
  logOpenGarageCallback('request', source, requestedGarage, {
    garage_id = tostring(garageId or '')
  })

  local ok, access = MZGaragemAccess.resolve(source, garageId)
  if not ok then
    logOpenGarageCallback('access_error', source, requestedGarage, {
      garage_id = tostring(garageId or ''),
      error = access
    })
    logGarageFlow('open', source, access, garageId)
    return errorResponse('server_access', access, { garage_id = tostring(garageId or '') })
  end

  local listOk, entries = openGarageList(source, access)
  if not listOk then
    logOpenGarageCallback('list_error', source, access.garage, {
      error = entries
    })
    logGarageFlow('open', source, entries, access.kind)
    return errorResponse('server_open_list', entries, {
      garage_id = tostring(garageId or ''),
      kind = tostring(access.kind or '')
    })
  end

  logOpenGarageCallback('success', source, access.garage, {
    entries_count = type(entries) == 'table' and #entries or 0
  })

  return {
    ok = true,
    garage = MZGaragemDTO.buildGaragePayload(access.garage),
    entries = entries
  }
end)

lib.callback.register('mz_garagem:server:withdraw', function(source, garageId, entryId)
  local ok, access = MZGaragemAccess.resolve(source, garageId)
  if not ok then
    logGarageFlow('withdraw', source, access, garageId)
    return errorResponse('server_access', access, { garage_id = tostring(garageId or '') })
  end

  local withdrawOk, payload
  if access.kind == 'public' then
    withdrawOk, payload = MZGaragemOwned.withdraw(source, access, entryId)
  elseif access.kind == 'org' then
    withdrawOk, payload = MZGaragemOrg.withdraw(source, access, entryId)
  elseif access.kind == 'service' then
    withdrawOk, payload = MZGaragemService.withdraw(source, access, entryId)
  else
    logGarageFlow('withdraw', source, 'invalid_kind', access.kind)
    return errorResponse('server_withdraw', 'invalid_kind', {
      garage_id = tostring(garageId or ''),
      kind = tostring(access.kind or '')
    })
  end

  if not withdrawOk then
    logGarageFlow('withdraw', source, payload, ('kind:%s entry:%s'):format(tostring(access.kind or ''), tostring(entryId or '')))
    return errorResponse('server_withdraw', payload, {
      garage_id = tostring(garageId or ''),
      kind = tostring(access.kind or '')
    })
  end

  grantVehicleAccess(source, access, payload)
  return { ok = true, spawn = payload }
end)

lib.callback.register('mz_garagem:server:releaseImpound', function(source, garageId, plate)
  local ok, access = MZGaragemAccess.resolve(source, garageId)
  if not ok then
    return { ok = false, error = access }
  end

  local releaseOk, result
  if access.kind == 'public' then
    releaseOk, result = MZGaragemOwned.releaseImpound(source, access, plate)
  elseif access.kind == 'org' then
    releaseOk, result = MZGaragemOrg.releaseImpound(source, access, plate)
  else
    return { ok = false, error = 'release_not_supported' }
  end

  if not releaseOk then
    return { ok = false, error = result }
  end

  return { ok = true }
end)

lib.callback.register('mz_garagem:server:storeVehicle', function(source, garageId, payload)
  local ok, access = MZGaragemAccess.resolve(source, garageId)
  if not ok then
    return errorResponse('server_access', access, { garage_id = tostring(garageId or '') })
  end

  local distanceOk, distanceErr = validateStorePosition(source, access, payload)
  if not distanceOk then
    return errorResponse('server_store_validate', distanceErr, {
      garage_id = tostring(garageId or ''),
      kind = tostring(access.kind or '')
    })
  end

  local storeOk, result
  if access.kind == 'public' then
    storeOk, result = MZGaragemOwned.store(source, access, payload or {})
  elseif access.kind == 'org' then
    storeOk, result = MZGaragemOrg.store(source, access, payload or {})
  elseif access.kind == 'service' then
    storeOk, result = MZGaragemService.store(source, access, payload or {})
  else
    return errorResponse('server_store', 'invalid_kind', {
      garage_id = tostring(garageId or ''),
      kind = tostring(access.kind or '')
    })
  end

  if not storeOk then
    return errorResponse('server_store', result, {
      garage_id = tostring(garageId or ''),
      kind = tostring(access.kind or '')
    })
  end

  revokeVehicleAccess(source, payload and payload.plate)
  return { ok = true }
end)

lib.callback.register('mz_garagem:server:rollbackWithdraw', function(source, garageId, plate)
  local ok, access = MZGaragemAccess.resolve(source, garageId)
  if not ok then
    logGarageFlow('rollback', source, access, garageId)
    return errorResponse('rollback', access, { garage_id = tostring(garageId or '') })
  end

  local rollbackOk, result
  if access.kind == 'public' then
    rollbackOk, result = MZGaragemOwned.rollbackWithdraw(access, plate)
  elseif access.kind == 'org' then
    rollbackOk, result = MZGaragemOrg.rollbackWithdraw(access, plate)
  else
    logGarageFlow('rollback', source, 'rollback_not_supported', access.kind)
    return errorResponse('rollback', 'rollback_not_supported', {
      garage_id = tostring(garageId or ''),
      kind = tostring(access.kind or '')
    })
  end

  if not rollbackOk then
    logGarageFlow('rollback', source, result, plate)
    return errorResponse('rollback', result, {
      garage_id = tostring(garageId or ''),
      kind = tostring(access.kind or '')
    })
  end

  revokeVehicleAccess(source, plate)
  return { ok = true }
end)

lib.callback.register('mz_garagem:server:getOutVehiclesForRespawn', function(source)
  local ok, vehicles = exports['mz_core']:GetOutVehiclesForRespawn(source)
  if not ok then
    return {
      ok = false,
      error = vehicles
    }
  end

  for _, vehicleData in ipairs(vehicles or {}) do
    grantRespawnVehicleAccess(source, vehicleData)
  end

  return {
    ok = true,
    vehicles = vehicles or {}
  }
end)

RegisterNetEvent('mz_garagem:server:persistentVehicleSpawned', function(plate, netId, snapshot)
  local src = source
  snapshot = type(snapshot) == 'table' and snapshot or {}
  snapshot.net_id = tonumber(netId or snapshot.net_id or snapshot.netId) or 0
  exports['mz_core']:RegisterOutVehicleEntity(src, plate, snapshot.net_id, snapshot)
end)

RegisterNetEvent('mz_garagem:server:persistentVehicleSnapshot', function(plate, snapshot)
  local src = source
  snapshot = type(snapshot) == 'table' and snapshot or {}
  if snapshot.destroyed == true then
    exports['mz_core']:MarkOutVehicleDestroyed(src, plate, snapshot)
    return
  end

  exports['mz_core']:UpdateOutVehicleSnapshot(src, plate, snapshot)
end)

RegisterNetEvent('mz_garagem:server:serviceConfirmSpawn', function(runtimeId, netId)
  MZGaragemService.confirmSpawn(source, runtimeId, netId)
end)

RegisterNetEvent('mz_garagem:server:serviceCancelSpawn', function(runtimeId)
  local ok, runtime = MZGaragemService.cancelPendingSpawn(source, runtimeId)
  if ok and type(runtime) == 'table' then
    revokeVehicleAccess(source, runtime.plate)
  end
end)

RegisterNetEvent('mz_garagem:server:serviceReleaseRuntime', function(runtimeId)
  local ok, runtime = MZGaragemService.releaseRuntime(source, runtimeId)
  if ok and type(runtime) == 'table' then
    revokeVehicleAccess(source, runtime.plate)
  end
end)
