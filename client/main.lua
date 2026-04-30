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

local function drawStoreMarker(store)
  local interact = type(store.interact) == 'table' and store.interact or {}
  local marker = type(interact.marker) == 'table' and interact.marker or {}
  if marker.enabled == false then
    return
  end

  local coords = getStoreCoords(store)
  if not coords then
    return
  end

  local size = marker.size or vec3(3.5, 3.5, 0.18)
  local color = marker.color or {}

  DrawMarker(
    tonumber(marker.type) or 1,
    coords.x, coords.y, coords.z,
    0.0, 0.0, 0.0,
    0.0, 0.0, 0.0,
    size.x or 3.5, size.y or 3.5, size.z or 0.18,
    color.r or 80, color.g or 210, color.b or 255, color.a or 70,
    marker.bobUpAndDown == true,
    marker.faceCamera == true,
    2,
    marker.rotate == true,
    nil,
    nil,
    false
  )
end

local function getNearestGarage()
  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)
  local nearestGarage = nil
  local nearestDistance = nil

  for garageId, garage in pairs(MZGaragemGarages or {}) do
    garage.id = garage.id or garageId

    local garageCoords = getGarageCoords(garage)
    if not garageCoords then
      goto continue
    end

    local distance = #(coords - garageCoords)
    if distance <= tonumber(MZGaragemConfig.marker_draw_distance or 18.0) then
      MZGaragemClientHelpers.drawGarageMarker(garage)
    end

    if distance <= tonumber(MZGaragemConfig.interaction_distance or 3.0) then
      if not nearestDistance or distance < nearestDistance then
        nearestGarage = garage
        nearestDistance = distance
      end
    end

    ::continue::
  end

  return nearestGarage, nearestDistance
end

local function getNearestStoreGarage(vehicle)
  if not vehicle or vehicle == 0 then
    return nil, nil
  end

  local coords = GetEntityCoords(vehicle)
  local nearestGarage = nil
  local nearestDistance = nil

  for garageId, garage in pairs(MZGaragemGarages or {}) do
    garage.id = garage.id or garageId

    local store = getStoreConfig(garage)
    local storeCoords = getStoreCoords(store)
    if not storeCoords then
      goto continue
    end

    local interact = type(store.interact) == 'table' and store.interact or {}
    local drawDistance = tonumber(interact.drawDistance or MZGaragemConfig.marker_draw_distance) or 18.0
    local interactDistance = tonumber(interact.interactDistance or store.radius or MZGaragemConfig.interaction_distance) or 4.0
    local distance = #(coords - storeCoords)

    if distance <= drawDistance then
      drawStoreMarker(store)
    end

    if distance <= interactDistance then
      if not nearestDistance or distance < nearestDistance then
        nearestGarage = garage
        nearestDistance = distance
      end
    end

    ::continue::
  end

  return nearestGarage, nearestDistance
end

local function isMzInteractActive()
  return MZGaragemConfig.UseMzInteract == true and GetResourceState('mz_interact') == 'started'
end

local function shouldUseLegacyInteraction()
  if isMzInteractActive() then
    return false
  end

  if MZGaragemConfig.UseMzInteract == true then
    return MZGaragemConfig.FallbackToLegacyMarkers == true
  end

  return true
end

local function logOpenGarageClient(stage, garage, detail)
  garage = type(garage) == 'table' and garage or {}
  detail = type(detail) == 'table' and detail or {}

  local access = type(garage.access) == 'table' and garage.access or {}

  print(('[mz_garagem][open_client][%s] garage_id=%s | kind=%s | org_code=%s | require_membership=%s | require_duty=%s | fleet_id=%s | entries_count=%s | response_stage=%s | error=%s'):format(
    tostring(stage or 'unknown'),
    tostring(garage.id or ''),
    tostring(garage.kind or ''),
    tostring(garage.org_code or ''),
    tostring(access.require_membership),
    tostring(access.require_duty),
    tostring(garage.fleet_id or ''),
    tostring(detail.entries_count or 0),
    tostring(detail.response_stage or ''),
    tostring(detail.error or '')
  ))
end

local function openGarage(garageId)
  local garage = MZGaragemGarages and MZGaragemGarages[garageId] or {}
  garage.id = garage.id or garageId

  logOpenGarageClient('request', garage)

  local response = lib.callback.await('mz_garagem:server:openGarage', false, garageId)
  if not response or response.ok ~= true then
    logOpenGarageClient('response_error', garage, {
      response_stage = response and response.stage or 'client_nil_response',
      error = response and response.error or 'client_nil_response'
    })
    MZGaragemClientHelpers.notify('Nao foi possivel abrir a garagem.', 'error')
    return
  end

  logOpenGarageClient('response_ok', garage, {
    entries_count = type(response.entries) == 'table' and #response.entries or 0
  })

  MZGaragemNUI.open(response)
end

function MZGaragemClient.openGarage(garageId)
  return openGarage(garageId)
end

local function clearServiceTracking(plate)
  MZGaragemClient.serviceVehiclesByPlate[tostring(plate or '')] = nil
end

local function logStoreCleanup(stage, detail)
  detail = type(detail) == 'table' and detail or {}

  print(('[mz_garagem][store_cleanup][%s] entity=%s | net_id=%s | plate=%s | exists_before=%s | exists_after=%s | delete_result=%s'):format(
    tostring(stage or 'snapshot'),
    tostring(detail.entity or 0),
    tostring(detail.net_id or 0),
    tostring(detail.plate or ''),
    tostring(detail.exists_before),
    tostring(detail.exists_after),
    tostring(detail.delete_result)
  ))
end

local STORE_ERROR_MESSAGES = {
  player_too_far_from_garage = 'Voce esta longe do ponto de guardar.',
  vehicle_too_far_from_garage = 'O veiculo esta longe do ponto de guardar.',
  vehicle_category_not_allowed = 'A categoria deste veiculo nao e permitida nesta garagem.',
  vehicle_access_denied = 'Voce nao tem acesso a este veiculo.',
  vehicle_not_found = 'Este veiculo nao esta registrado.',
  garage_kind_mismatch = 'Este veiculo nao pertence ao tipo desta garagem.',
  invalid_plate = 'A placa do veiculo e invalida.',
  invalid_garage = 'A garagem e invalida.',
  vehicle_impounded = 'Este veiculo esta apreendido.',
  player_not_loaded = 'Seu personagem ainda nao foi carregado.',
  garage_not_found = 'Garagem nao encontrada.'
}

local function notifyStoreError(response)
  response = type(response) == 'table' and response or {}
  local stage = tostring(response.stage or 'client_nil_response')
  local err = tostring(response.error or 'unknown_error')
  local message = STORE_ERROR_MESSAGES[err] or 'Nao foi possivel guardar o veiculo.'

  print(('[mz_garagem][store_client_error] stage=%s | error=%s | garage_id=%s | kind=%s'):format(
    stage,
    err,
    tostring(response.garage_id or ''),
    tostring(response.kind or '')
  ))

  MZGaragemClientHelpers.notify(('%s [%s]'):format(message, err), 'error')
end

local function storeVehicleEntity(garage, vehicle)
  local plate = MZGaragemClientHelpers.getPlate(vehicle, true)
  if plate == '' then
    MZGaragemClientHelpers.notify('Nao foi possivel identificar a placa do veiculo.', 'error')
    return false
  end

  local serviceInfo = MZGaragemClient.serviceVehiclesByPlate[plate]
  if garage.kind == 'service' then
    if not serviceInfo or tostring(serviceInfo.garage_id) ~= tostring(garage.id) then
      MZGaragemClientHelpers.notify('Este ponto guarda apenas veiculos de servico desta garagem.', 'error')
      return false
    end
  elseif serviceInfo then
    MZGaragemClientHelpers.notify('Veiculos de servico devem voltar para a garagem de servico.', 'error')
    return false
  end

  local payload = MZGaragemSpawn.captureStorePayload(vehicle, serviceInfo and serviceInfo.runtime_id or nil)
  payload.plate = plate
  local response = lib.callback.await('mz_garagem:server:storeVehicle', false, garage.id, payload)
  if not response or response.ok ~= true then
    notifyStoreError(response)
    return false
  end

  clearServiceTracking(plate)

  if MZGaragemConfig.delete_vehicle_on_store == true then
    local deleteDetail = {
      entity = tonumber(vehicle) or 0,
      net_id = vehicle ~= 0 and DoesEntityExist(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or 0,
      plate = plate,
      exists_before = vehicle ~= 0 and DoesEntityExist(vehicle) or false
    }

    logStoreCleanup('before_delete', deleteDetail)

    local deleted, helperDetail = MZGaragemClientHelpers.deleteVehicleSafely(vehicle)
    helperDetail = type(helperDetail) == 'table' and helperDetail or deleteDetail
    helperDetail.entity = helperDetail.entity or deleteDetail.entity
    helperDetail.net_id = helperDetail.net_id or deleteDetail.net_id
    helperDetail.plate = helperDetail.plate ~= '' and helperDetail.plate or plate
    helperDetail.exists_before = helperDetail.exists_before == true or deleteDetail.exists_before == true
    helperDetail.exists_after = vehicle ~= 0 and DoesEntityExist(vehicle) or false
    helperDetail.delete_result = deleted == true and helperDetail.exists_after ~= true

    logStoreCleanup('after_delete', helperDetail)

    if deleted ~= true or helperDetail.exists_after == true then
      MZGaragemClientHelpers.notify('Veiculo guardado no servidor, mas a entidade local nao foi removida.', 'error')
      return false
    end
  end

  MZGaragemClientHelpers.notify('Veiculo guardado com sucesso.', 'success')
  return true
end

local function storeCurrentVehicle(garage, vehicle)
  return storeVehicleEntity(garage, vehicle)
end

function MZGaragemClient.storeCurrentVehicle(garageId)
  local garage = MZGaragemGarages and MZGaragemGarages[garageId] or nil
  if not garage then
    MZGaragemClientHelpers.notify('Garagem nao encontrada para guardar o veiculo.', 'error')
    return false
  end

  garage.id = garage.id or garageId

  local ped = PlayerPedId()
  local vehicle = GetVehiclePedIsIn(ped, false)
  if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then
    MZGaragemClientHelpers.notify('Voce precisa estar dirigindo um veiculo para guardar.', 'warning')
    return false
  end

  return storeCurrentVehicle(garage, vehicle)
end

function MZGaragemClient.handleGarageInteraction(garageId)
  local garage = MZGaragemGarages and MZGaragemGarages[garageId] or nil
  if not garage then
    MZGaragemClientHelpers.notify('Garagem nao encontrada.', 'error')
    return false
  end

  garage.id = garage.id or garageId

  openGarage(garage.id)
  return true
end

function MZGaragemClient.storeNearbyVehicle(garageId)
  local garage = MZGaragemGarages and MZGaragemGarages[garageId] or nil
  if not garage then
    MZGaragemClientHelpers.notify('Garagem nao encontrada para guardar o veiculo.', 'error')
    return false
  end

  garage.id = garage.id or garageId

  local vehicle, err = MZGaragemClientHelpers.findNearbyVehicleForStore(garage)
  if not vehicle then
    if err == 'nearby_store_disabled' then
      MZGaragemClientHelpers.notify('Guardar veiculo proximo esta desativado.', 'warning')
    else
      MZGaragemClientHelpers.notify('Nenhum veiculo elegivel foi encontrado proximo da garagem.', 'error')
    end

    return false
  end

  return storeVehicleEntity(garage, vehicle)
end

CreateThread(function()
  while true do
    local sleep = 500

    if isMzInteractActive() then
      sleep = 1000
    elseif shouldUseLegacyInteraction() and exports['mz_core']:GetPlayerData() ~= nil and MZGaragemNUI.isOpen ~= true then
      local ped = PlayerPedId()
      local vehicle = GetVehiclePedIsIn(ped, false)
      local isDriver = vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped

      if isDriver then
        local storeGarage = getNearestStoreGarage(vehicle)
        if storeGarage then
          sleep = 0

          if storeGarage.kind == 'service' then
            local plate = MZGaragemClientHelpers.getPlate(vehicle)
            local serviceInfo = MZGaragemClient.serviceVehiclesByPlate[plate]
            if serviceInfo and tostring(serviceInfo.garage_id) == tostring(storeGarage.id) then
              MZGaragemClientHelpers.showHelpText('Pressione ~INPUT_CONTEXT~ para guardar o veiculo de servico')
            else
              MZGaragemClientHelpers.showHelpText('Pressione ~INPUT_CONTEXT~ para tentar guardar o veiculo')
            end
          else
            MZGaragemClientHelpers.showHelpText('Pressione ~INPUT_CONTEXT~ para guardar o veiculo')
          end

          if IsControlJustReleased(0, 38) then
            storeCurrentVehicle(storeGarage, vehicle)
          end
        end
      else
        local garage = getNearestGarage()
        if garage then
          sleep = 0

          MZGaragemClientHelpers.showHelpText('Pressione ~INPUT_CONTEXT~ para abrir a garagem')
          if IsControlJustReleased(0, 38) then
            openGarage(garage.id)
          end
        end
      end
    end

    Wait(sleep)
  end
end)

CreateThread(function()
  while true do
    Wait(tonumber(MZGaragemConfig.service.runtime_cleanup_interval_ms or 2000) or 2000)

    local toRemove = {}
    for plate, serviceInfo in pairs(MZGaragemClient.serviceVehiclesByPlate) do
      if not serviceInfo.vehicle or not DoesEntityExist(serviceInfo.vehicle) then
        TriggerServerEvent('mz_garagem:server:serviceReleaseRuntime', serviceInfo.runtime_id)
        toRemove[#toRemove + 1] = plate
      end
    end

    for _, plate in ipairs(toRemove) do
      clearServiceTracking(plate)
    end
  end
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then
    return
  end

  if MZGaragemNUI.isOpen then
    MZGaragemNUI.close()
  end
end)
