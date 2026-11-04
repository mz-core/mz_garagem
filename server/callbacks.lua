local function openGarageList(source, access)
  if access.kind == 'public' or access.kind == 'house' then
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

local function garageActionAllowed(source)
  local ok, allowed, result = pcall(function() return exports['mz_core']:CanPlayerPerformAction(source, 'garage.use') end)
  return ok and allowed == true and type(result) == 'table' and result.allowed == true
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
    return false, 'mz_vehicles_unavailable'
  end

  local plate = NormalizePlate(payload.plate)
  if plate == '' then
    return false, 'invalid_plate'
  end

  local ok, granted, result = pcall(function()
    return exports['mz_vehicles']:GrantVehicleAccess(source, plate, {
      kind = tostring(access.kind or ''),
      garage_id = tostring(access.garage and access.garage.id or ''),
      org_code = access.garage and access.garage.org_code and tostring(access.garage.org_code) or nil,
      owner_type = access.kind == 'org' and 'org' or nil,
      owner_id = access.kind == 'org' and tostring(access.garage.org_code or '') or nil,
      model = tostring(payload.vehicle_model or payload.model or ''),
      runtime_id = payload.runtime_id and tostring(payload.runtime_id) or nil,
      persistent = access.kind ~= 'service'
    })
  end)

  if not ok then
    logGarageFlow('vehicle_access', source, 'grant_failed', granted)
    return false, 'vehicle_access_export_failed'
  end

  if granted ~= true then
    logGarageFlow('vehicle_access', source, 'grant_rejected', result)
    return false, result or 'vehicle_access_denied'
  end

  return true, result
end

local function bindServiceVehicle(source, runtime, netId)
  if not canUseVehicleAccessExports() or type(runtime) ~= 'table' then
    return false, 'mz_vehicles_unavailable'
  end

  local ok, bound, result = pcall(function()
    return exports['mz_vehicles']:BindServiceVehicleEntity(
      source,
      runtime.runtime_id,
      runtime.plate,
      runtime.model,
      netId
    )
  end)

  if not ok then
    logGarageFlow('service_bind', source, 'export_failed', bound)
    return false, 'vehicle_access_export_failed'
  end

  if bound ~= true then
    logGarageFlow('service_bind', source, 'bind_rejected', result)
    return false, result or 'service_vehicle_bind_failed'
  end

  return true, result
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

  local function asVector3(value)
    if type(value) == 'vector3' then return value end
    if type(value) == 'vector4' then return vector3(value.x, value.y, value.z) end
    if type(value) ~= 'table' then return nil end
    local x = tonumber(value.x or value[1])
    local y = tonumber(value.y or value[2])
    local z = tonumber(value.z or value[3])
    return x and y and z and vector3(x, y, z) or nil
  end

  if garage.zone and garage.zone.coords then
    local zoneCoords = asVector3(garage.zone.coords)
    if zoneCoords then
      validationPoints[#validationPoints + 1] = {
        coords = zoneCoords,
        distance = maxGarageDistance
      }
    end
  end

  if type(garage.store) == 'table' and garage.store.enabled == true and garage.store.coords then
    local storeInteract = type(garage.store.interact) == 'table' and garage.store.interact or {}
    local storeDistance = tonumber(storeInteract.interactDistance or garage.store.radius or maxGarageDistance) or maxGarageDistance
    local storeCoords = asVector3(garage.store.coords)
    if storeCoords then
      validationPoints[#validationPoints + 1] = {
        coords = storeCoords,
        distance = math.max(maxGarageDistance, storeDistance)
      }
    end
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

lib.callback.register('mz_garagem:server:openGarage', function(source, garageId, context)
  if not garageActionAllowed(source) then return errorResponse('player_state', 'player_state_blocked') end
  local requestedGarage = MZGaragemAccess.getGarage(garageId)
  logOpenGarageCallback('request', source, requestedGarage, {
    garage_id = tostring(garageId or '')
  })

  local ok, access = MZGaragemAccess.resolve(source, garageId, context)
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

  local garagePayload = MZGaragemDTO.buildGaragePayload(access.garage)
  if access.kind == 'house' then
    garagePayload.context = {
      type = 'house',
      garageType = 'house',
      token = context and context.token or access.houseSession and access.houseSession.token or nil,
      houseCode = access.house and access.house.code or nil
    }
  end

  return {
    ok = true,
    garage = garagePayload,
    entries = entries
  }
end)

lib.callback.register('mz_garagem:server:withdraw', function(source, garageId, entryId, context)
  if not garageActionAllowed(source) then return errorResponse('player_state', 'player_state_blocked') end
  local ok, access = MZGaragemAccess.resolve(source, garageId, context)
  if not ok then
    logGarageFlow('withdraw', source, access, garageId)
    return errorResponse('server_access', access, { garage_id = tostring(garageId or '') })
  end

  local withdrawOk, payload
  if access.kind == 'public' or access.kind == 'house' then
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

  local grantOk, grantErr = grantVehicleAccess(source, access, payload)
  if not grantOk then
    local rollbackOk, rollbackErr
    if access.kind == 'service' then
      rollbackOk, rollbackErr = MZGaragemService.cancelPendingSpawn(source, payload.runtime_id)
    elseif access.kind == 'org' then
      rollbackOk, rollbackErr = MZGaragemOrg.rollbackWithdraw(access, payload.plate)
    else
      rollbackOk, rollbackErr = MZGaragemOwned.rollbackWithdraw(access, payload.plate)
    end

    if rollbackOk ~= true then
      logGarageFlow('vehicle_access', source, 'rollback_failed', rollbackErr)
      return errorResponse('vehicle_access_rollback', rollbackErr or 'rollback_failed', {
        garage_id = tostring(garageId or ''),
        kind = tostring(access.kind or ''),
        access_error = tostring(grantErr or '')
      })
    end

    return errorResponse('vehicle_access', grantErr, {
      garage_id = tostring(garageId or ''),
      kind = tostring(access.kind or '')
    })
  end

  return { ok = true, spawn = payload }
end)

lib.callback.register('mz_garagem:server:releaseImpound', function(source, garageId, plate, context)
  if not garageActionAllowed(source) then return { ok = false, error = 'player_state_blocked' } end
  local ok, access = MZGaragemAccess.resolve(source, garageId, context)
  if not ok then
    return { ok = false, error = access }
  end

  local releaseOk, result
  if access.kind == 'public' or access.kind == 'house' then
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

local function resolveStoreAccess(source, garageId, context)
  local ok, access = MZGaragemAccess.resolve(source, garageId, context)
  if ok then
    return true, access
  end

  if access == 'org_duty_required'
    and MZGaragemService
    and type(MZGaragemService.getActiveRuntimeFor) == 'function'
    and MZGaragemService.getActiveRuntimeFor(source, garageId) then
    logGarageFlow('store', source, 'off_duty_return', garageId)
    return MZGaragemAccess.resolve(source, garageId, context, {
      allow_off_duty_return = true
    })
  end

  return false, access
end

lib.callback.register('mz_garagem:server:storeVehicle', function(source, garageId, payload, context)
  if not garageActionAllowed(source) then return errorResponse('player_state', 'player_state_blocked') end
  local ok, access = resolveStoreAccess(source, garageId, context)
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
  if access.kind == 'public' or access.kind == 'house' then
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

  local revokedPlate = payload and payload.plate
  if type(result) == 'table' and result.plate then
    revokedPlate = result.plate
  end

  revokeVehicleAccess(source, revokedPlate)
  return { ok = true }
end)

lib.callback.register('mz_garagem:server:rollbackWithdraw', function(source, garageId, plate, context)
  local ok, access = MZGaragemAccess.resolve(source, garageId, context)
  if not ok then
    logGarageFlow('rollback', source, access, garageId)
    return errorResponse('rollback', access, { garage_id = tostring(garageId or '') })
  end

  local rollbackOk, result
  if access.kind == 'public' or access.kind == 'house' then
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
  if not garageActionAllowed(source) then return { ok = false, error = 'player_state_blocked' } end
  local ok, vehicles = exports['mz_vehicles']:GetOutVehiclesForRespawn(source)
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
  if not garageActionAllowed(src) then return end
  snapshot = type(snapshot) == 'table' and snapshot or {}
  snapshot.net_id = tonumber(netId or snapshot.net_id or snapshot.netId) or 0
  local ok, err = exports['mz_vehicles']:RegisterOutVehicleEntity(src, plate, snapshot.net_id, snapshot)
  if ok ~= true then
    logGarageFlow('spawn', src, 'registration_rejected', ('plate=%s net_id=%s error=%s'):format(
      tostring(plate or ''),
      tostring(snapshot.net_id or 0),
      tostring(err or 'unknown_error')
    ))
  end
end)

RegisterNetEvent('mz_garagem:server:persistentVehicleSnapshot', function(plate, snapshot)
  local src = source
  if not garageActionAllowed(src) then return end
  snapshot = type(snapshot) == 'table' and snapshot or {}

  if snapshot.destroyed == true then
    local ok, err = exports['mz_vehicles']:MarkOutVehicleDestroyed(src, plate, snapshot)
    if ok ~= true then
      logGarageFlow('snapshot', src, 'destroyed_snapshot_rejected', ('plate=%s error=%s'):format(
        tostring(plate or ''),
        tostring(err or 'unknown_error')
      ))
    end
    return
  end

  local ok, err = exports['mz_vehicles']:UpdateOutVehicleSnapshot(src, plate, snapshot)
  if ok ~= true then
    logGarageFlow('snapshot', src, 'snapshot_rejected', ('plate=%s error=%s'):format(
      tostring(plate or ''),
      tostring(err or 'unknown_error')
    ))
  end
end)

local function confirmServiceSpawn(source, runtimeId, netId)
  if not garageActionAllowed(source) then
    return errorResponse('service_confirm', 'player_state_blocked')
  end

  local ok, runtime = MZGaragemService.confirmSpawn(source, runtimeId, netId)
  if not ok then
    return errorResponse('service_confirm', runtime)
  end

  local bindOk, bindErr
  local retryable = {
    vehicle_network_id_unavailable = true,
    vehicle_entity_not_found = true,
    vehicle_plate_mismatch = true
  }

  for attempt = 1, 15 do
    bindOk, bindErr = bindServiceVehicle(source, runtime, netId)
    if bindOk or retryable[tostring(bindErr or '')] ~= true then
      break
    end
    if attempt < 15 then Wait(100) end
  end

  if not bindOk then
    MZGaragemService.releaseRuntime(source, runtimeId)
    revokeVehicleAccess(source, runtime.plate)
    return errorResponse('service_confirm', bindErr)
  end

  return { ok = true }
end

lib.callback.register('mz_garagem:server:serviceConfirmSpawn', confirmServiceSpawn)

RegisterNetEvent('mz_garagem:server:serviceConfirmSpawn', function(runtimeId, netId)
  confirmServiceSpawn(source, runtimeId, netId)
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
