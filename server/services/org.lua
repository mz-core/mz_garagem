MZGaragemOrg = MZGaragemOrg or {}

local function categoryAllowed(garage, vehicle)
  local allowed = garage.filters and garage.filters.categories or nil
  if type(allowed) ~= 'table' or #allowed == 0 then
    return true
  end

  local vehicleCategory = tostring(vehicle.category or 'car')
  for _, category in ipairs(allowed) do
    if tostring(category) == vehicleCategory then
      return true
    end
  end

  return false
end

local function orgOwnsVehicle(orgCode, plate)
  return exports['mz_core']:OrgOwnsVehicle(orgCode, plate) == true
end

local function getVehicleOrError(plate)
  local ok, vehicle = exports['mz_core']:GetVehicleByPlate(plate)
  if not ok then
    return false, vehicle
  end

  return true, vehicle
end

local function vehicleBlocked(model)
  if not MZGaragemBlocklist or type(MZGaragemBlocklist.isBlocked) ~= 'function' then
    return false, nil
  end

  return MZGaragemBlocklist.isBlocked(model)
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

function MZGaragemOrg.list(source, access)
  local ok, vehicles = exports['mz_core']:GetOrgVehicles(access.garage.org_code)
  if not ok then
    return false, vehicles
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

  local policyOk, policyErr = validateGaragePolicy(access, vehicle, 'withdraw')
  if not policyOk then
    return false, policyErr
  end

  local expectedGarage = MZGaragemAccess.getExpectedGarageId(access.garage)
  local takeOutOk, updatedVehicle = exports['mz_core']:TakeOutVehicle(source, plate, expectedGarage)
  if not takeOutOk then
    return false, updatedVehicle
  end

  return true, {
    kind = 'persistent',
    plate = tostring(updatedVehicle.plate or ''),
    model = tostring(updatedVehicle.model or ''),
    props = updatedVehicle.props_json or {},
    fuel = tonumber(updatedVehicle.fuel) or 100,
    engine = tonumber(updatedVehicle.engine) or 1000,
    body = tonumber(updatedVehicle.body) or 1000
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

  local policyOk, policyErr = validateGaragePolicy(access, vehicle, 'release')
  if not policyOk then
    return false, policyErr
  end

  local releaseOk, result = exports['mz_core']:ReleaseImpoundVehicle(plate, access.garage.id, source)
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

  local policyOk, policyErr = validateGaragePolicy(access, vehicle, 'store')
  if not policyOk then
    return false, policyErr
  end

  local storedOk, storedVehicle = exports['mz_core']:StoreVehicle(
    source,
    payload.plate,
    access.garage.id,
    payload.props or {},
    payload.fuel,
    payload.engine,
    payload.body
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

  local ok = exports['mz_core']:SetVehicleStored(plate, true)
  if ok ~= true then
    return false, ok
  end

  return true
end
