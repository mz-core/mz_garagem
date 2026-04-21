local function getNearestGarage()
  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)
  local nearestGarage = nil
  local nearestDistance = nil

  for garageId, garage in pairs(MZGaragemGarages or {}) do
    garage.id = garage.id or garageId

    local distance = #(coords - garage.zone.coords)
    if distance <= tonumber(MZGaragemConfig.marker_draw_distance or 18.0) then
      MZGaragemClientHelpers.drawGarageMarker(garage)
    end

    if distance <= tonumber(MZGaragemConfig.interaction_distance or 3.0) then
      if not nearestDistance or distance < nearestDistance then
        nearestGarage = garage
        nearestDistance = distance
      end
    end
  end

  return nearestGarage, nearestDistance
end

local function openGarage(garageId)
  local response = lib.callback.await('mz_garagem:server:openGarage', false, garageId)
  if not response or response.ok ~= true then
    MZGaragemClientHelpers.notify('Nao foi possivel abrir a garagem.', 'error')
    return
  end

  MZGaragemNUI.open(response)
end

local function clearServiceTracking(plate)
  MZGaragemClient.serviceVehiclesByPlate[tostring(plate or '')] = nil
end

local function storeVehicleEntity(garage, vehicle)
  local plate = MZGaragemClientHelpers.getPlate(vehicle)
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
  local response = lib.callback.await('mz_garagem:server:storeVehicle', false, garage.id, payload)
  if not response or response.ok ~= true then
    MZGaragemClientHelpers.notify('Nao foi possivel guardar o veiculo.', 'error')
    return false
  end

  clearServiceTracking(plate)

  if MZGaragemConfig.delete_vehicle_on_store == true then
    MZGaragemClientHelpers.deleteVehicleSafely(vehicle)
  end

  MZGaragemClientHelpers.notify('Veiculo guardado com sucesso.', 'success')
  return true
end

local function storeCurrentVehicle(garage, vehicle)
  return storeVehicleEntity(garage, vehicle)
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

    if exports['mz_core']:GetPlayerData() ~= nil and MZGaragemNUI.isOpen ~= true then
      local garage = getNearestGarage()
      if garage then
        sleep = 0

        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
          if garage.kind == 'service' then
            local plate = MZGaragemClientHelpers.getPlate(vehicle)
            local serviceInfo = MZGaragemClient.serviceVehiclesByPlate[plate]
            if serviceInfo and tostring(serviceInfo.garage_id) == tostring(garage.id) then
              MZGaragemClientHelpers.showHelpText('Pressione ~INPUT_CONTEXT~ para guardar o veiculo de servico')
            else
              MZGaragemClientHelpers.showHelpText('Pressione ~INPUT_CONTEXT~ para tentar guardar o veiculo')
            end
          else
            MZGaragemClientHelpers.showHelpText('Pressione ~INPUT_CONTEXT~ para guardar o veiculo')
          end

          if IsControlJustReleased(0, 38) then
            storeCurrentVehicle(garage, vehicle)
          end
        else
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
