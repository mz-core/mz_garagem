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

local function logGarageFlow(stage, source, detail, extra)
  print(('[mz_garagem][%s][source:%s] %s%s'):format(
    tostring(stage or 'flow'),
    tostring(source or 'unknown'),
    tostring(detail or 'unknown'),
    extra and (' | ' .. tostring(extra)) or ''
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

local function canUseVehicleAccessExports()
  return GetResourceState('mz_vehicles') == 'started'
end

local function grantVehicleAccess(source, access, payload)
  if not canUseVehicleAccessExports() or type(payload) ~= 'table' then
    return
  end

  local plate = tostring(payload.plate or '')
  if plate == '' then
    return
  end

  local ok, err = pcall(function()
    exports['mz_vehicles']:GrantVehicleAccess(source, plate, {
      kind = tostring(access.kind or ''),
      garage_id = tostring(access.garage and access.garage.id or ''),
      org_code = access.garage and access.garage.org_code and tostring(access.garage.org_code) or nil,
      model = tostring(payload.model or ''),
      runtime_id = payload.runtime_id and tostring(payload.runtime_id) or nil
    })
  end)

  if not ok then
    logGarageFlow('vehicle_access', source, 'grant_failed', err)
  end
end

local function revokeVehicleAccess(source, plate)
  if not canUseVehicleAccessExports() then
    return
  end

  local normalizedPlate = tostring(plate or '')
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

  local garageCoords = access.garage and access.garage.zone and access.garage.zone.coords or nil
  if not garageCoords then
    return false, 'garage_not_found'
  end

  local maxGarageDistance = tonumber(MZGaragemConfig.maxGarageDistance or 12.0) or 12.0
  local playerPed = GetPlayerPed(source)
  if not playerPed or playerPed == 0 then
    return false, 'player_not_found'
  end

  local playerCoords = GetEntityCoords(playerPed)
  if #(playerCoords - garageCoords) > maxGarageDistance then
    return false, 'player_too_far_from_garage'
  end

  local netId = tonumber(payload.net_id or 0) or 0
  if netId <= 0 then
    return true
  end

  local entity = NetworkGetEntityFromNetworkId(netId)
  if not entity or entity == 0 or not DoesEntityExist(entity) then
    return true
  end

  local vehicleCoords = GetEntityCoords(entity)
  if #(vehicleCoords - garageCoords) > maxGarageDistance then
    return false, 'vehicle_too_far_from_garage'
  end

  return true
end

lib.callback.register('mz_garagem:server:openGarage', function(source, garageId)
  local ok, access = MZGaragemAccess.resolve(source, garageId)
  if not ok then
    logGarageFlow('open', source, access, garageId)
    return errorResponse('server_access', access, { garage_id = tostring(garageId or '') })
  end

  local listOk, entries = openGarageList(source, access)
  if not listOk then
    logGarageFlow('open', source, entries, access.kind)
    return errorResponse('server_open_list', entries, {
      garage_id = tostring(garageId or ''),
      kind = tostring(access.kind or '')
    })
  end

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
