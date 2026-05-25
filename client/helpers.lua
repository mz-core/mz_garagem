MZGaragemClient = MZGaragemClient or {
  serviceVehiclesByPlate = {}
}

MZGaragemClientHelpers = MZGaragemClientHelpers or {}

local function trimScalarString(value)
  local valueType = type(value)
  if valueType == 'string' or valueType == 'number' or valueType == 'boolean' then
    return tostring(value):gsub('^%s+', ''):gsub('%s+$', '')
  end

  return ''
end

local function normalizePlateText(value)
  return trimScalarString(value):upper()
end

local function readPlateDirect(vehicle)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return ''
  end

  return normalizePlateText(GetVehicleNumberPlateText(vehicle) or '')
end

local function normalizeEntityHandle(vehicle)
  local normalizedVehicle = tonumber(vehicle)
  if normalizedVehicle and normalizedVehicle > 0 then
    return normalizedVehicle
  end

  return 0
end

local function normalizeNotifyType(notifyType)
  notifyType = tostring(notifyType or 'info'):lower()

  if notifyType == 'success' or notifyType == 'error' or notifyType == 'warning' or notifyType == 'info' then
    return notifyType
  end

  if notifyType == 'inform' then
    return 'info'
  end

  return 'info'
end

local function getNotifyTitle(customTitle)
  if customTitle and tostring(customTitle) ~= '' then
    return tostring(customTitle)
  end

  return tostring(MZGaragemConfig.ui and MZGaragemConfig.ui.title or 'Garagem')
end

local function isGarageDebug()
  return MZGaragemConfig and MZGaragemConfig.debug == true
end

local function canUseVehiclesExports()
  return GetResourceState('mz_vehicles') == 'started'
end

local function logVehiclesBridgeError(exportName, err)
  print(('[mz_garagem][vehicles_bridge] export "%s" failed: %s'):format(
    tostring(exportName or 'unknown'),
    tostring(err or 'unknown_error')
  ))
end

local function logDeleteBridge(stage, rawVehicle, normalizedVehicle)
  if not isGarageDebug() then
    return
  end

  local rawExists = rawVehicle ~= nil and rawVehicle ~= 0 and DoesEntityExist(rawVehicle) or false
  local normalizedExists = normalizedVehicle ~= 0 and DoesEntityExist(normalizedVehicle) or false

  print(('[mz_garagem][delete_bridge][%s] raw_entity=%s | raw_type=%s | normalized_entity=%s | raw_exists=%s | normalized_exists=%s'):format(
    tostring(stage or 'unknown'),
    tostring(rawVehicle),
    tostring(type(rawVehicle)),
    tostring(normalizedVehicle),
    tostring(rawExists),
    tostring(normalizedExists)
  ))
end

local function callVehiclesExport(exportName, ...)
  if not canUseVehiclesExports() then
    return false, nil, nil, 'mz_vehicles_unavailable'
  end

  local ok, a, b = pcall(function(...)
    return exports['mz_vehicles'][exportName](...)
  end, ...)

  if not ok then
    logVehiclesBridgeError(exportName, a)
    return false, nil, nil, 'mz_vehicles_export_failed'
  end

  return true, a, b, nil
end

local function callVehiclesLoadModelExport(model)
  if not canUseVehiclesExports() then
    return false, nil, nil, 'mz_vehicles_unavailable'
  end

  local ok, exportOk, modelHash, modelErr = pcall(function()
    return exports['mz_vehicles']:LoadModel(model)
  end)

  if not ok then
    logVehiclesBridgeError('LoadModel', exportOk)
    return false, nil, nil, 'mz_vehicles_export_failed'
  end

  return true, exportOk, modelHash, modelErr, nil
end

local function callVehiclesDeleteExport(target)
  if not canUseVehiclesExports() then
    return false, nil, nil, 'mz_vehicles_unavailable'
  end

  local ok, deleted, detail = pcall(function()
    return exports['mz_vehicles']:DeleteVehicleSafely(target)
  end)

  if not ok then
    logVehiclesBridgeError('DeleteVehicleSafely', deleted)
    return false, nil, nil, 'mz_vehicles_export_failed'
  end

  return true, deleted, detail, nil
end

function MZGaragemClientHelpers.notify(message, notifyType, title)
  local normalizedType = normalizeNotifyType(notifyType)
  local resourceState = GetResourceState('mz_notify')
  local payload = {
    type = normalizedType,
    title = getNotifyTitle(title),
    message = tostring(message or 'Unknown'),
    duration = 5000
  }

  if resourceState == 'started' then
    exports['mz_notify']:Notify(payload)
    return
  end

  if lib and type(lib.notify) == 'function' then
    lib.notify({
      title = payload.title,
      description = payload.message,
      type = normalizedType == 'info' and 'inform' or normalizedType
    })
    return
  end

  print(('[mz_garagem][%s] %s - %s'):format(normalizedType, payload.title, payload.message))
end

function MZGaragemClientHelpers.showHelpText(message)
  BeginTextCommandDisplayHelp('STRING')
  AddTextComponentSubstringPlayerName(tostring(message or ''))
  EndTextCommandDisplayHelp(0, false, false, -1)
end

function MZGaragemClientHelpers.drawGarageMarker(garage)
  if MZGaragemConfig.draw_markers ~= true then
    return
  end

  local marker = MZGaragemConfig.marker or {}
  local color = marker.color or {}
  local scale = marker.scale or vec3(0.5, 0.5, 0.5)
  local coords = garage.coords
    or garage.markerCoords
    or garage.position
    or garage.location
    or (type(garage.zone) == 'table' and garage.zone.coords or nil)

  if not coords then
    return
  end

  DrawMarker(
    marker.type or 36,
    coords.x, coords.y, coords.z,
    0.0, 0.0, 0.0,
    0.0, 0.0, 0.0,
    scale.x or 0.5, scale.y or 0.5, scale.z or 0.5,
    color.r or 57, color.g or 229, color.b or 140, color.a or 110,
    false, false, 2, true, nil, nil, false
  )
end

function MZGaragemClientHelpers.getPlate(vehicle, retryRead)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return ''
  end

  local attempts = retryRead == true and 5 or 1

  for attempt = 1, attempts do
    local ok, plate = callVehiclesExport('GetVehiclePlate', vehicle)
    local normalizedExportPlate = ok and normalizePlateText(plate) or ''
    if normalizedExportPlate ~= '' then
      return normalizedExportPlate
    end

    local normalizedDirectPlate = readPlateDirect(vehicle)
    if normalizedDirectPlate ~= '' then
      return normalizedDirectPlate
    end

    if attempt < attempts then
      Wait(0)
    end
  end

  return ''
end

function MZGaragemClientHelpers.loadModel(model)
  local modelType = type(model)
  local normalizedModel = trimScalarString(model)

  if modelType ~= 'number' and modelType ~= 'string' then
    return nil, 'invalid_vehicle_model'
  end

  if modelType == 'string' and normalizedModel == '' then
    return nil, 'invalid_vehicle_model'
  end

  local ok, exportOk, modelHash, modelErr, bridgeErr = callVehiclesLoadModelExport(
    modelType == 'string' and normalizedModel or model
  )

  if not ok then
    return nil, bridgeErr or 'mz_vehicles_export_failed'
  end

  if exportOk == true then
    local normalizedHash = tonumber(modelHash)
    if normalizedHash and normalizedHash ~= 0 then
      return normalizedHash, nil
    end

    return nil, 'invalid_model_hash'
  end

  local normalizedErr = trimScalarString(modelErr)
  if normalizedErr ~= '' then
    return nil, normalizedErr
  end

  return nil, 'unknown_model_error'
end

function MZGaragemClientHelpers.findAvailableSpawnPoint(garage)
  local points = garage.spawn_points or {}
  if #points == 0 then
    return nil
  end

  local function pointIsFree(point, radius)
    local vehicleNearby = GetClosestVehicle(point.x, point.y, point.z, radius, 0, 71)
    return (not vehicleNearby or vehicleNearby == 0)
  end

  local radii = { 2.0, 2.5, 3.0 }

  for _, radius in ipairs(radii) do
    for _, point in ipairs(points) do
      if pointIsFree(point, radius) then
        if isGarageDebug() then
          print(('[mz_garagem][spawn] point free (garage:%s radius:%.1f x:%.2f y:%.2f z:%.2f)'):format(
            tostring(garage.id or 'unknown'),
            radius,
            point.x, point.y, point.z
          ))
        end
        return point
      end
    end
  end

  if isGarageDebug() then
    print(('[mz_garagem][spawn] no free spawn point (garage:%s points:%d)'):format(
      tostring(garage.id or 'unknown'),
      #points
    ))
  end

  return nil
end

function MZGaragemClientHelpers.isVehicleEmpty(vehicle)
  local ok, isEmpty = callVehiclesExport('IsVehicleEmpty', vehicle)
  if ok then
    return isEmpty == true
  end

  return false
end

local function chooseBetterNearbyStoreCandidate(currentBest, candidate)
  if not currentBest then
    return candidate
  end

  if candidate.has_plate ~= currentBest.has_plate then
    return candidate.has_plate == true and candidate or currentBest
  end

  if candidate.garage_distance ~= currentBest.garage_distance then
    return candidate.garage_distance < currentBest.garage_distance and candidate or currentBest
  end

  if candidate.player_distance ~= currentBest.player_distance then
    return candidate.player_distance < currentBest.player_distance and candidate or currentBest
  end

  return currentBest
end

local function logNearbyStoreCandidate(stage, detail)
  if not isGarageDebug() then
    return
  end

  detail = type(detail) == 'table' and detail or {}

  print(('[mz_garagem][store_nearby][%s] entity=%s | plate=%s | dist_player=%s | dist_garage=%s | is_empty=%s | player_in_vehicle=%s | player_is_driver=%s | discard_reason=%s'):format(
    tostring(stage or 'candidate'),
    tostring(detail.entity or 0),
    tostring(detail.plate or ''),
    tostring(detail.dist_player),
    tostring(detail.dist_garage),
    tostring(detail.is_empty),
    tostring(detail.player_in_vehicle),
    tostring(detail.player_is_driver),
    tostring(detail.discard_reason or '')
  ))
end

function MZGaragemClientHelpers.findNearbyVehicleForStore(garage)
  if MZGaragemConfig.allowNearbyStore ~= true then
    return nil, 'nearby_store_disabled'
  end

  if not garage or type(garage.zone) ~= 'table' or not garage.zone.coords then
    return nil, 'garage_not_found'
  end

  local ped = PlayerPedId()
  local currentVehicle = GetVehiclePedIsIn(ped, false)
  local playerInVehicle = currentVehicle ~= 0 and DoesEntityExist(currentVehicle)
  local playerCoords = GetEntityCoords(ped)
  local garageCoords = garage.zone.coords
  local maxVehicleDistance = tonumber(MZGaragemConfig.maxVehicleDistance or 8.0) or 8.0
  local maxGarageDistance = tonumber(MZGaragemConfig.maxGarageDistance or 12.0) or 12.0

  if #(playerCoords - garageCoords) > maxGarageDistance then
    logNearbyStoreCandidate('search_abort', {
      entity = 0,
      plate = '',
      dist_player = 0,
      dist_garage = #(playerCoords - garageCoords),
      is_empty = false,
      player_in_vehicle = playerInVehicle,
      player_is_driver = playerInVehicle and GetPedInVehicleSeat(currentVehicle, -1) == ped or false,
      discard_reason = 'garage_too_far'
    })
    return nil, 'garage_too_far'
  end

  if currentVehicle ~= 0 and DoesEntityExist(currentVehicle) and GetPedInVehicleSeat(currentVehicle, -1) == ped then
    local currentVehicleCoords = GetEntityCoords(currentVehicle)
    local currentGarageDistance = #(garageCoords - currentVehicleCoords)
    local currentPlate = readPlateDirect(currentVehicle)
    logNearbyStoreCandidate('current_vehicle', {
      entity = currentVehicle,
      plate = currentPlate,
      dist_player = #(playerCoords - currentVehicleCoords),
      dist_garage = currentGarageDistance,
      is_empty = MZGaragemClientHelpers.isVehicleEmpty(currentVehicle),
      player_in_vehicle = true,
      player_is_driver = true,
      discard_reason = currentGarageDistance <= maxGarageDistance and currentPlate ~= '' and 'selected_current_vehicle' or (
        currentGarageDistance > maxGarageDistance and 'current_vehicle_too_far_from_garage' or 'current_vehicle_missing_plate'
      )
    })

    if currentGarageDistance <= maxGarageDistance and currentPlate ~= '' then
      return currentVehicle
    end
  end

  local bestCandidate = nil

  for _, vehicle in ipairs(GetGamePool('CVehicle')) do
    local detail = {
      entity = vehicle,
      plate = '',
      dist_player = 0,
      dist_garage = 0,
      is_empty = false,
      player_in_vehicle = playerInVehicle,
      player_is_driver = false,
      discard_reason = ''
    }

    if vehicle == 0 or not DoesEntityExist(vehicle) then
      detail.discard_reason = 'entity_missing'
      logNearbyStoreCandidate('discard', detail)
    else
      local vehicleCoords = GetEntityCoords(vehicle)
      local playerDistance = #(playerCoords - vehicleCoords)
      local garageDistance = #(garageCoords - vehicleCoords)
      local isEmpty = MZGaragemClientHelpers.isVehicleEmpty(vehicle)
      local playerIsDriver = GetPedInVehicleSeat(vehicle, -1) == ped
      local plate = readPlateDirect(vehicle)

      detail.plate = plate
      detail.dist_player = playerDistance
      detail.dist_garage = garageDistance
      detail.is_empty = isEmpty
      detail.player_is_driver = playerIsDriver

      if plate == '' then
        detail.discard_reason = 'plate_missing'
        logNearbyStoreCandidate('discard', detail)
      elseif garageDistance > maxGarageDistance then
        detail.discard_reason = 'too_far_from_garage'
        logNearbyStoreCandidate('discard', detail)
      elseif playerDistance > maxVehicleDistance then
        detail.discard_reason = 'too_far_from_player'
        logNearbyStoreCandidate('discard', detail)
      else
        detail.discard_reason = 'candidate_with_plate'
        logNearbyStoreCandidate('candidate', detail)

        bestCandidate = chooseBetterNearbyStoreCandidate(bestCandidate, {
          vehicle = vehicle,
          player_distance = playerDistance,
          garage_distance = garageDistance,
          has_plate = plate ~= ''
        })
      end
    end
  end

  if not bestCandidate or not bestCandidate.vehicle then
    logNearbyStoreCandidate('search_result', {
      entity = 0,
      plate = '',
      dist_player = 0,
      dist_garage = 0,
      is_empty = false,
      player_in_vehicle = playerInVehicle,
      player_is_driver = playerInVehicle and GetPedInVehicleSeat(currentVehicle, -1) == ped or false,
      discard_reason = 'nearby_vehicle_not_found'
    })
    return nil, 'nearby_vehicle_not_found'
  end

  logNearbyStoreCandidate('search_result', {
    entity = bestCandidate.vehicle,
    plate = readPlateDirect(bestCandidate.vehicle),
    dist_player = bestCandidate.player_distance,
    dist_garage = bestCandidate.garage_distance,
    is_empty = MZGaragemClientHelpers.isVehicleEmpty(bestCandidate.vehicle),
    player_in_vehicle = playerInVehicle,
    player_is_driver = GetPedInVehicleSeat(bestCandidate.vehicle, -1) == ped,
    discard_reason = 'selected_best_candidate'
  })

  return bestCandidate.vehicle
end

function MZGaragemClientHelpers.getVehicleProperties(vehicle)
  local ok, props = callVehiclesExport('GetVehicleProperties', vehicle)
  if ok and type(props) == 'table' then
    return props
  end

  return {}
end

function MZGaragemClientHelpers.setVehicleProperties(vehicle, props)
  callVehiclesExport('SetVehicleProperties', vehicle, props)
end

function MZGaragemClientHelpers.deleteVehicleSafely(vehicle)
  local normalizedVehicle = normalizeEntityHandle(vehicle)
  logDeleteBridge('call_export', vehicle, normalizedVehicle)

  if normalizedVehicle == 0 then
    return false, {
      entity = 0,
      net_id = 0,
      plate = '',
      exists_before = false,
      exists_after = false,
      delete_result = false
    }
  end

  local deleteTarget = {
    entity = normalizedVehicle,
    net_id = DoesEntityExist(normalizedVehicle) and NetworkGetNetworkIdFromEntity(normalizedVehicle) or 0,
    plate = readPlateDirect(normalizedVehicle)
  }

  local ok, deleted, detail = callVehiclesDeleteExport(deleteTarget)
  if ok then
    return deleted == true, detail
  end

  return false, nil
end
