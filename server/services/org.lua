MZGaragemOrg = MZGaragemOrg or {}

local function shouldLogOrgOpen(access)
  local garage = type(access) == 'table' and access.garage or access
  local garageId = tostring(type(garage) == 'table' and garage.id or '')
  return MZGaragemConfig and MZGaragemConfig.debug == true and garageId == 'police_org'
end

local function logOrgOpen(stage, source, access, detail)
  if not shouldLogOrgOpen(access) then
    return
  end

  detail = type(detail) == 'table' and detail or {}
  local garage = type(access) == 'table' and access.garage or {}

  print(('[mz_garagem][open_org][%s][source:%s] garage_id=%s | kind=%s | org_code=%s | strict_garage=%s | vehicles_total=%s | entries_count=%s | error=%s'):format(
    tostring(stage or 'unknown'),
    tostring(source or 'unknown'),
    tostring(garage.id or ''),
    tostring(garage.kind or ''),
    tostring(garage.org_code or ''),
    tostring(garage.rules and garage.rules.strict_garage == true),
    tostring(detail.vehicles_total or 0),
    tostring(detail.entries_count or 0),
    tostring(detail.error or '')
  ))
end

local function categoryAllowed(garage, vehicle)
  local allowed = garage.filters and garage.filters.categories or nil
  if type(allowed) ~= 'table' or #allowed == 0 then
    return true
  end

  local resolvedCatalog = MZGaragemVehicleDomain
    and type(MZGaragemVehicleDomain.resolveCatalog) == 'function'
    and MZGaragemVehicleDomain.resolveCatalog(vehicle.model, nil)
    or nil
  local vehicleCategory = tostring((type(resolvedCatalog) == 'table' and resolvedCatalog.category) or vehicle.category or 'car')
  for _, category in ipairs(allowed) do
    if tostring(category) == vehicleCategory or tostring(category) == tostring(vehicle.category or '') then
      return true
    end
  end

  return false
end

local function orgOwnsVehicle(orgCode, plate)
  return exports['mz_org']:OrganizationOwnsVehicle(orgCode, plate) == true
end

local function authorizeVehicle(source, plate)
  return exports['mz_org']:CanAccessVehicle(source, plate) == true
end

local function getVehicleOrError(plate)
  local ok, vehicle = exports['mz_vehicles']:GetVehicleByPlate(plate)
  if not ok then
    return false, vehicle
  end

  return true, vehicle
end

local function vehicleBlocked(model)
  if not MZGaragemVehicleDomain or type(MZGaragemVehicleDomain.isBlocked) ~= 'function' then
    return false, nil
  end

  return MZGaragemVehicleDomain.isBlocked(model)
end

local function validateGaragePolicy(access, vehicle, action)
  if not categoryAllowed(access.garage, vehicle) then
    return false, 'vehicle_category_not_allowed'
  end

  if action == 'withdraw' then
    local blocked = vehicleBlocked(vehicle.model)
    if blocked then
      return false, 'vehicle_blocked'
    end
  end

  if action == 'release' and access.garage.rules.allow_impounded ~= true then
    return false, 'impound_release_not_allowed'
  end

  return true
end

local function buildConditionPayload(vehicle)
  vehicle = type(vehicle) == 'table' and vehicle or {}
  local metadata = type(vehicle.metadata_json) == 'table' and vehicle.metadata_json or {}
  local world = type(metadata.world) == 'table' and metadata.world or {}
  local engine = tonumber(vehicle.engine) or 1000
  local body = tonumber(vehicle.body) or 1000
  local destroyed = engine <= 50.0
    or body <= 100.0

  return {
    destroyed = destroyed,
    world = {
      destroyed = destroyed,
      locked = world.locked,
      last_coords = world.last_coords,
      last_heading = world.last_heading
    }
  }
end

function MZGaragemOrg.list(source, access)
  local ok, vehicles = exports['mz_org']:GetOrganizationVehicles(access.garage.org_code)
  if not ok then
    logOrgOpen('list_error', source, access, {
      error = vehicles
    })
    return false, vehicles
  end

  if shouldLogOrgOpen(access) and #(vehicles or {}) == 0 then
    print(('[mz_garagem][open_org][empty] garage_id=%s org_code=%s | confirme em mz_vehicles: owner_type=org, owner_id=<id numerico da org> e garage=%s'):format(
      tostring(access.garage.id or ''),
      tostring(access.garage.org_code or ''),
      tostring(access.garage.id or '')
    ))
  end

  local rows = {}
  for _, vehicle in ipairs(vehicles or {}) do
    local state = tostring(vehicle.state or 'stored')
    local blocked = vehicleBlocked(vehicle.model)

    if not blocked and categoryAllowed(access.garage, vehicle) then
      if not (state == 'impounded' and access.garage.rules.allow_impounded ~= true) then
        if access.garage.rules.strict_garage ~= true or tostring(vehicle.garage or '') == tostring(access.garage.id or '') then
          rows[#rows + 1] = MZGaragemDTO.buildOrgEntry(access.garage, vehicle)
        end
      end
    end
  end

  if shouldLogOrgOpen(access) and #rows == 0 and #(vehicles or {}) > 0 then
    print(('[mz_garagem][open_org][filtered] garage_id=%s org_code=%s | %d veiculo(s) da org foram ocultados; confirme garage=%s no registro'):format(
      tostring(access.garage.id or ''),
      tostring(access.garage.org_code or ''),
      #vehicles,
      tostring(access.garage.id or '')
    ))
  end

  logOrgOpen('list_ok', source, access, {
    vehicles_total = type(vehicles) == 'table' and #vehicles or 0,
    entries_count = #rows
  })

  return true, MZGaragemDTO.sort(rows)
end

function MZGaragemOrg.withdraw(source, access, plate)
  local ok, vehicle = getVehicleOrError(plate)
  if not ok then
    return false, vehicle
  end

  if not orgOwnsVehicle(access.garage.org_code, plate) then
    return false, 'vehicle_access_denied'
  end
  if not authorizeVehicle(source, plate) then return false, 'vehicle_access_denied' end

  local policyOk, policyErr = validateGaragePolicy(access, vehicle, 'withdraw')
  if not policyOk then
    return false, policyErr
  end

  local expectedGarage = MZGaragemAccess.getExpectedGarageId(access.garage)
  local takeOutOk, updatedVehicle = exports['mz_vehicles']:TakeOutVehicle(source, plate, expectedGarage)
  if not takeOutOk then
    return false, updatedVehicle
  end

  local conditionPayload = buildConditionPayload(updatedVehicle)

  return true, {
    kind = 'persistent',
    plate = tostring(updatedVehicle.plate or ''),
    vehicle_model = tostring(updatedVehicle.model or ''),
    model = tostring(updatedVehicle.model or ''),
    props = updatedVehicle.props_json or {},
    fuel = tonumber(updatedVehicle.fuel) or 100,
    engine = tonumber(updatedVehicle.engine) or 1000,
    body = tonumber(updatedVehicle.body) or 1000,
    destroyed = conditionPayload.destroyed,
    world = conditionPayload.world
  }
end

function MZGaragemOrg.releaseImpound(source, access, plate)
  local ok, vehicle = getVehicleOrError(plate)
  if not ok then
    return false, vehicle
  end

  if not orgOwnsVehicle(access.garage.org_code, plate) then
    return false, 'vehicle_access_denied'
  end
  if not authorizeVehicle(source, plate) then return false, 'vehicle_access_denied' end

  local policyOk, policyErr = validateGaragePolicy(access, vehicle, 'release')
  if not policyOk then
    return false, policyErr
  end

  local releaseOk, result = exports['mz_vehicles']:ReleaseImpoundVehicle(plate, access.garage.id, source)
  if not releaseOk then
    return false, result
  end

  return true, result
end

function MZGaragemOrg.store(source, access, payload)
  local ok, vehicle = getVehicleOrError(payload.plate)
  if not ok then
    return false, vehicle
  end

  if vehicle.owner_type ~= 'org' then
    return false, 'garage_kind_mismatch'
  end

  if not orgOwnsVehicle(access.garage.org_code, payload.plate) then
    return false, 'vehicle_access_denied'
  end
  if not authorizeVehicle(source, payload.plate) then return false, 'vehicle_access_denied' end

  local policyOk, policyErr = validateGaragePolicy(access, vehicle, 'store')
  if not policyOk then
    return false, policyErr
  end

  local storedOk, storedVehicle = exports['mz_vehicles']:StoreVehicle(
    source,
    payload.plate,
    access.garage.id,
    payload.props or {},
    payload.fuel,
    payload.engine,
    payload.body,
    payload.destroyed
  )

  if not storedOk then
    return false, storedVehicle
  end

  return true, storedVehicle
end

function MZGaragemOrg.rollbackWithdraw(access, plate)
  if not orgOwnsVehicle(access.garage.org_code, plate) then
    return false, 'vehicle_access_denied'
  end

  local ok = exports['mz_vehicles']:SetVehicleStored(plate, true)
  if ok ~= true then
    return false, ok
  end

  return true
end
