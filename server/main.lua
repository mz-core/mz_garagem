MZGaragem = MZGaragem or {
  state = {
    bootstrapped = false,
    garage_count = 0,
    service_garage_count = 0,
    fleet_count = 0
  }
}

local function logInfo(message)
  print(('[mz_garagem] %s'):format(message))
end

local function logWarn(message)
  print(('[mz_garagem] warning: %s'):format(message))
end

local function validateFleetDefinition(fleetId, fleet)
  if type(fleet) ~= 'table' then
    return false, 'fleet_not_table'
  end

  if tostring(fleet.fleet_id or fleetId or '') == '' then
    return false, 'missing_fleet_id'
  end

  if type(fleet.entries) ~= 'table' or #fleet.entries == 0 then
    return false, 'missing_fleet_entries'
  end

  local seenEntryIds = {}

  for index, entry in ipairs(fleet.entries) do
    if type(entry) ~= 'table' then
      return false, ('fleet_entry_%s_not_table'):format(index)
    end

    local entryId = tostring(entry.entry_id or '')
    if entryId == '' then
      return false, ('fleet_entry_%s_missing_entry_id'):format(index)
    end

    if seenEntryIds[entryId] then
      return false, ('fleet_entry_%s_duplicate_entry_id'):format(entryId)
    end

    seenEntryIds[entryId] = true

    if tostring(entry.model or '') == '' then
      return false, ('fleet_entry_%s_missing_model'):format(entryId)
    end
  end

  return true
end

local function validateGarageReferences(garageId, garage)
  if garage.kind == 'service' then
    local fleet = MZGaragemServiceFleet and MZGaragemServiceFleet[garage.fleet_id] or nil
    local fleetOk, fleetErr = validateFleetDefinition(garage.fleet_id, fleet)
    if not fleetOk then
      error(('[mz_garagem] invalid service fleet for garage "%s": %s'):format(garageId, fleetErr))
    end
  end

  local orgCode = tostring(garage.org_code or '')
  if orgCode == '' then
    if garage.kind == 'service' and garage.access and (
      garage.access.require_membership == true or
      garage.access.require_duty == true or
      tonumber(garage.access.min_grade_level or 0) > 0 or
      garage.access.primary_only == true
    ) then
      logWarn(('garage "%s" has org access rules but no org_code; access falls back to public behavior'):format(garageId))
    end

    return
  end

  local org = exports['mz_core']:GetOrgByCode(orgCode)
  if not org then
    logWarn(('garage "%s" references org "%s" that was not found in mz_core; access will stay blocked until the org exists'):format(
      garageId,
      orgCode
    ))
  end
end

local function bootstrap()
  if MZGaragem.state.bootstrapped == true then
    return
  end

  local garageCount = 0
  local serviceGarageCount = 0
  local fleetIds = {}

  for garageId, garage in pairs(MZGaragemGarages or {}) do
    local ok, err = MZGaragemAccess.validateGarageDefinition(garageId, garage)
    if not ok then
      error(('[mz_garagem] invalid garage "%s": %s'):format(garageId, err))
    end

    validateGarageReferences(garageId, garage)

    garageCount = garageCount + 1
    if garage.kind == 'service' then
      serviceGarageCount = serviceGarageCount + 1
      fleetIds[tostring(garage.fleet_id or '')] = true
    end
  end

  for fleetId, fleet in pairs(MZGaragemServiceFleet or {}) do
    local ok, err = validateFleetDefinition(fleetId, fleet)
    if not ok then
      error(('[mz_garagem] invalid service fleet "%s": %s'):format(fleetId, err))
    end
  end

  math.randomseed((tonumber(GetGameTimer()) or 0) + os.time())

  MZGaragem.state.bootstrapped = true
  MZGaragem.state.garage_count = garageCount
  MZGaragem.state.service_garage_count = serviceGarageCount
  MZGaragem.state.fleet_count = 0

  for _ in pairs(fleetIds) do
    MZGaragem.state.fleet_count = MZGaragem.state.fleet_count + 1
  end

  logInfo(('ready with %d garage(s), %d service garage(s) and %d referenced fleet(s)'):format(
    MZGaragem.state.garage_count,
    MZGaragem.state.service_garage_count,
    MZGaragem.state.fleet_count
  ))
end

CreateThread(function()
  Wait(0)
  bootstrap()
end)

AddEventHandler('playerDropped', function()
  MZGaragemService.cleanupSource(source)
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then
    return
  end

  MZGaragemService.resetAll()
end)
