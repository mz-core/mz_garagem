MZGaragemNUI = MZGaragemNUI or {
  isOpen = false,
  busy = false,
  currentGarage = nil,
  currentEntries = {},
  currentEntriesById = {}
}

local WITHDRAW_ERROR_MESSAGES = {
  prepare = {
    garage_not_found = 'Garagem nao encontrada para spawn.',
    invalid_vehicle_model = 'O modelo recebido para este veiculo e invalido.',
    invalid_model = 'O modelo deste veiculo e invalido.',
    invalid_model_type = 'O tipo do modelo recebido para este veiculo e invalido.',
    invalid_model_hash = 'O hash gerado para este modelo e invalido.',
    model_not_found = 'O modelo deste veiculo nao foi encontrado.',
    model_timeout = 'O carregamento do modelo do veiculo expirou.',
    unknown_model_error = 'Falha ao carregar o modelo do veiculo.',
    spawn_blocked = 'Nao ha ponto livre para spawnar este veiculo.',
    mz_vehicles_unavailable = 'O modulo mz_vehicles nao esta disponivel.',
    mz_vehicles_export_failed = 'O modulo mz_vehicles falhou ao preparar o spawn.'
  },
  server_access = {
    player_not_loaded = 'Seu personagem ainda nao terminou de carregar.',
    garage_not_found = 'Garagem nao encontrada.',
    org_membership_required = 'Voce nao pertence a organizacao desta garagem.',
    org_duty_required = 'Voce precisa estar em servico para usar esta garagem.',
    org_primary_required = 'Esta garagem exige organizacao principal.',
    org_grade_too_low = 'Seu cargo na organizacao nao permite usar esta garagem.',
    org_permission_required = 'Voce nao tem permissao para usar esta garagem.'
  },
  server_withdraw = {
    vehicle_blocked = 'Este modelo esta bloqueado nesta garagem.',
    vehicle_category_not_allowed = 'A categoria deste veiculo nao e permitida aqui.',
    vehicle_access_denied = 'Voce nao tem acesso a este veiculo.',
    vehicle_not_found = 'O veiculo nao foi encontrado.',
    vehicle_already_out = 'Este veiculo ja esta fora da garagem.',
    vehicle_missing_outside = 'Este veiculo esta marcado como fora, mas nao foi localizado. Use recuperacao/depot ou procure o suporte.',
    vehicle_spawn_blocked = 'Este veiculo ja possui uma entidade fora da garagem.',
    restore_disabled = 'A restauracao automatica deste veiculo esta desativada.',
    vehicle_impounded = 'Este veiculo esta no impound.',
    vehicle_wrong_garage = 'Este veiculo pertence a outra garagem.',
    service_vehicle_active = 'Voce ja possui um veiculo de servico ativo nesta garagem.',
    service_entry_not_found = 'A entrada de servico nao foi encontrada.',
    invalid_kind = 'Tipo de garagem invalido para retirar veiculo.'
  },
  spawn = {
    invalid_spawn_payload = 'Payload de spawn invalido.',
    spawn_failed = 'Falha ao criar a entidade do veiculo.',
    mz_vehicles_unavailable = 'O modulo mz_vehicles nao esta disponivel para spawn.',
    mz_vehicles_export_failed = 'O modulo mz_vehicles falhou ao executar o spawn.'
  },
  rollback = {
    rollback_not_supported = 'Rollback nao suportado para esta garagem.',
    vehicle_access_denied = 'Falha ao restaurar o estado do veiculo.',
    vehicle_not_found = 'Rollback falhou porque o veiculo nao foi encontrado.',
    unknown_error = 'Falha ao restaurar o estado do veiculo apos erro no spawn.'
  }
}

local function indexEntries(entries)
  local out = {}
  for _, entry in ipairs(entries or {}) do
    out[tostring(entry.entry_id or '')] = entry
  end
  return out
end

local function getEntry(entryId)
  return MZGaragemNUI.currentEntriesById[tostring(entryId or '')]
end

local function logWithdraw(stage, code, extra)
  print(('[mz_garagem][withdraw][%s] %s%s'):format(
    tostring(stage or 'unknown'),
    tostring(code or 'unknown_error'),
    extra and (' | ' .. tostring(extra)) or ''
  ))
end

local function resolveErrorMessage(stage, code, fallbackMessage)
  local stageKey = tostring(stage or 'unknown')
  local codeKey = tostring(code or 'unknown_error')
  local stageMap = WITHDRAW_ERROR_MESSAGES[stageKey] or nil
  if stageMap and stageMap[codeKey] then
    return stageMap[codeKey], codeKey
  end

  return tostring(fallbackMessage or 'Falha no fluxo da garagem.'), codeKey
end

function MZGaragemNUI.open(payload)
  MZGaragemNUI.currentGarage = payload.garage
  MZGaragemNUI.currentEntries = payload.entries or {}
  MZGaragemNUI.currentEntriesById = indexEntries(payload.entries or {})
  MZGaragemNUI.isOpen = true

  SetNuiFocus(true, true)
  SendNUIMessage({
    action = 'open',
    garage = payload.garage,
    entries = payload.entries or {},
    ui = {
      title = tostring(MZGaragemConfig.ui and MZGaragemConfig.ui.title or 'Garagem'),
      allowNearbyStore = MZGaragemConfig.allowNearbyStore == true,
      images = MZGaragemConfig.images or {}
    }
  })
end

function MZGaragemNUI.close()
  MZGaragemNUI.isOpen = false
  MZGaragemNUI.busy = false
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'close' })
end

function MZGaragemNUI.refresh()
  if not MZGaragemNUI.currentGarage or not MZGaragemNUI.currentGarage.id then
    return
  end

  local response = lib.callback.await('mz_garagem:server:openGarage', false, MZGaragemNUI.currentGarage.id)
  if not response or response.ok ~= true then
    MZGaragemClientHelpers.notify('Nao foi possivel atualizar a garagem.', 'error')
    return
  end

  MZGaragemNUI.open(response)
end

local function rollbackPersistentSpawn(garageId, spawnPayload)
  if not spawnPayload or not spawnPayload.plate then
    return { ok = false, stage = 'rollback', error = 'vehicle_not_found' }
  end

  local response = lib.callback.await('mz_garagem:server:rollbackWithdraw', false, garageId, spawnPayload.plate)
  if response and response.ok == true then
    return response
  end

  return response or { ok = false, stage = 'rollback', error = 'unknown_error' }
end

local function handleWithdraw(entryId)
  if MZGaragemNUI.busy or not MZGaragemNUI.currentGarage then
    return
  end

  local entry = getEntry(entryId)
  if not entry then
    MZGaragemClientHelpers.notify('Entrada da garagem nao encontrada.', 'error')
    return
  end

  local ok, prepared = MZGaragemSpawn.prepareSpawn(MZGaragemNUI.currentGarage.id, entry.vehicle_model)
  if not ok then
    local message, code = resolveErrorMessage('prepare', prepared, 'Falha ao preparar o spawn do veiculo.')
    logWithdraw('prepare', code, entry.vehicle_model)
    MZGaragemClientHelpers.notify(('%s [%s]'):format(message, code), 'error')
    return
  end

  MZGaragemNUI.busy = true

  local response = lib.callback.await('mz_garagem:server:withdraw', false, MZGaragemNUI.currentGarage.id, entry.entry_id)
  if not response or response.ok ~= true then
    SetModelAsNoLongerNeeded(prepared.model_hash)
    MZGaragemNUI.busy = false
    local stage = response and response.stage or 'server_withdraw'
    local errorCode = response and response.error or 'unknown_error'
    local message, code = resolveErrorMessage(stage, errorCode, 'Nao foi possivel retirar o veiculo.')
    logWithdraw(stage, code, entry.entry_id)
    MZGaragemClientHelpers.notify(('%s [%s]'):format(message, code), 'error')
    return
  end

  local spawnOk, spawned = MZGaragemSpawn.spawn(prepared, response.spawn)
  if not spawnOk then
    local rollbackResponse = nil
    if response.spawn.kind == 'service' and response.spawn.runtime_id then
      TriggerServerEvent('mz_garagem:server:serviceCancelSpawn', response.spawn.runtime_id)
    else
      rollbackResponse = rollbackPersistentSpawn(MZGaragemNUI.currentGarage.id, response.spawn)
    end

    MZGaragemNUI.busy = false
    local message, code = resolveErrorMessage('spawn', spawned, 'Falha ao spawnar o veiculo.')
    logWithdraw('spawn', code, response.spawn and response.spawn.plate)

    local notifyMessage = ('%s [%s]'):format(message, code)

    if rollbackResponse and rollbackResponse.ok ~= true then
      local rollbackMessage, rollbackCode = resolveErrorMessage(
        rollbackResponse.stage or 'rollback',
        rollbackResponse.error or 'unknown_error',
        'Falha ao restaurar o estado do veiculo.'
      )

      logWithdraw('rollback', rollbackCode, response.spawn and response.spawn.plate)
      notifyMessage = ('%s | rollback: %s [%s]'):format(notifyMessage, rollbackMessage, rollbackCode)
    end

    MZGaragemClientHelpers.notify(notifyMessage, 'error')
    return
  end

  if response.spawn.kind == 'service' and response.spawn.runtime_id then
    TriggerServerEvent('mz_garagem:server:serviceConfirmSpawn', response.spawn.runtime_id, spawned.net_id)
    MZGaragemClient.serviceVehiclesByPlate[spawned.plate] = {
      runtime_id = response.spawn.runtime_id,
      garage_id = MZGaragemNUI.currentGarage.id,
      vehicle = spawned.vehicle,
      net_id = spawned.net_id
    }
  elseif response.spawn.kind == 'persistent' and spawned.vehicle then
    MZGaragemSpawn.confirmPersistentVehicleSpawn(spawned.vehicle, response.spawn)
  end

  MZGaragemNUI.busy = false
  MZGaragemNUI.close()
  MZGaragemClientHelpers.notify('Veiculo retirado com sucesso.', 'success')
end

local function handleReleaseImpound(entryId)
  if MZGaragemNUI.busy or not MZGaragemNUI.currentGarage then
    return
  end

  local entry = getEntry(entryId)
  if not entry then
    MZGaragemClientHelpers.notify('Entrada da garagem nao encontrada.', 'error')
    return
  end

  MZGaragemNUI.busy = true
  local response = lib.callback.await('mz_garagem:server:releaseImpound', false, MZGaragemNUI.currentGarage.id, entry.plate)
  MZGaragemNUI.busy = false

  if not response or response.ok ~= true then
    MZGaragemClientHelpers.notify('Nao foi possivel liberar o veiculo do impound.', 'error')
    return
  end

  MZGaragemClientHelpers.notify('Veiculo liberado para a garagem atual.', 'success')
  MZGaragemNUI.refresh()
end

local function handleStoreNearby()
  if MZGaragemNUI.busy or not MZGaragemNUI.currentGarage or not MZGaragemClient.storeNearbyVehicle then
    return
  end

  MZGaragemNUI.busy = true
  local ok = MZGaragemClient.storeNearbyVehicle(MZGaragemNUI.currentGarage.id)
  MZGaragemNUI.busy = false

  if ok == true then
    MZGaragemNUI.refresh()
  end
end

RegisterNUICallback('close', function(_, cb)
  MZGaragemNUI.close()
  cb('ok')
end)

RegisterNUICallback('withdraw', function(data, cb)
  handleWithdraw(data and data.entry_id)
  cb('ok')
end)

RegisterNUICallback('releaseImpound', function(data, cb)
  handleReleaseImpound(data and data.entry_id)
  cb('ok')
end)

RegisterNUICallback('storeNearby', function(_, cb)
  handleStoreNearby()
  cb('ok')
end)
