MZGaragemAccess = MZGaragemAccess or {}

local VALID_KINDS = {
  public = true,
  org = true,
  service = true
}

local function cloneTable(value)
  if type(value) ~= 'table' then
    return value
  end

  local out = {}
  for key, item in pairs(value) do
    out[key] = type(item) == 'table' and cloneTable(item) or item
  end

  return out
end

local function getPlayer(source)
  return exports['mz_core']:GetPlayer(source)
end

local function getPlayerOrgs(source)
  return exports['mz_core']:GetPlayerOrgs(source) or {}
end

local function normalizeRules(garage)
  local rules = cloneTable(garage.rules or {})
  local strictGarage = rules.strict_garage == true
  local sharedPool = rules.shared_pool == true

  if garage.kind ~= 'service' then
    if strictGarage then
      sharedPool = false
    else
      sharedPool = true
    end
  else
    strictGarage = false
    sharedPool = false
  end

  rules.strict_garage = strictGarage
  rules.shared_pool = sharedPool
  rules.allow_impounded = rules.allow_impounded == true

  return rules
end

function MZGaragemAccess.getGarage(garageId)
  local garage = MZGaragemGarages and MZGaragemGarages[garageId] or nil
  if not garage then
    return nil
  end

  garage.id = garage.id or garageId
  garage.rules = normalizeRules(garage)
  garage.access = garage.access or {}
  garage.filters = garage.filters or {}
  garage.service = garage.service or {}

  return garage
end

function MZGaragemAccess.validateGarageDefinition(garageId, garage)
  if type(garage) ~= 'table' then
    return false, 'garage_not_table'
  end

  local kind = tostring(garage.kind or '')
  if not VALID_KINDS[kind] then
    return false, 'invalid_kind'
  end

  if type(garage.zone) ~= 'table' or not garage.zone.coords then
    return false, 'missing_zone'
  end

  if type(garage.spawn_points) ~= 'table' or #garage.spawn_points == 0 then
    return false, 'missing_spawn_points'
  end

  if kind == 'public' and garage.org_code then
    return false, 'public_cannot_have_org_code'
  end

  if kind == 'org' and tostring(garage.org_code or '') == '' then
    return false, 'org_requires_org_code'
  end

  if kind == 'service' and tostring(garage.fleet_id or '') == '' then
    return false, 'service_requires_fleet_id'
  end

  if kind ~= 'service' then
    local rules = normalizeRules(garage)
    local validModes =
      (rules.strict_garage == true and rules.shared_pool == false) or
      (rules.strict_garage == false and rules.shared_pool == true)

    if not validModes then
      return false, 'invalid_rules_mode'
    end
  end

  return true
end

function MZGaragemAccess.resolveOrgMembership(source, orgCode)
  orgCode = tostring(orgCode or '')
  if orgCode == '' then
    return nil
  end

  for _, org in ipairs(getPlayerOrgs(source)) do
    if tostring(org.code or '') == orgCode then
      return org
    end
  end

  return nil
end

function MZGaragemAccess.resolve(source, garageId)
  local player = getPlayer(source)
  if not player then
    return false, 'player_not_loaded'
  end

  local garage = MZGaragemAccess.getGarage(garageId)
  if not garage then
    return false, 'garage_not_found'
  end

  local context = {
    source = source,
    player = player,
    citizenid = tostring(player.citizenid or ''),
    garage = garage,
    kind = garage.kind,
    org = nil
  }

  if garage.kind == 'public' then
    return true, context
  end

  local orgCode = tostring(garage.org_code or '')
  if orgCode == '' then
    return true, context
  end

  local org = MZGaragemAccess.resolveOrgMembership(source, orgCode)
  if not org then
    return false, 'org_membership_required'
  end

  local access = garage.access or {}
  if access.require_membership ~= false and not org then
    return false, 'org_membership_required'
  end

  if access.require_duty == true and org.duty ~= true then
    return false, 'org_duty_required'
  end

  if access.primary_only == true and org.isPrimary ~= true then
    return false, 'org_primary_required'
  end

  local minGradeLevel = tonumber(access.min_grade_level or 0) or 0
  local currentGradeLevel = tonumber(org.grade and org.grade.level or 0) or 0
  if currentGradeLevel < minGradeLevel then
    return false, 'org_grade_too_low'
  end

  local requiredPermissions = access.required_org_permissions or {}
  for _, permission in ipairs(requiredPermissions) do
    if type(org.permissions) ~= 'table' or org.permissions[permission] ~= true then
      return false, 'org_permission_required'
    end
  end

  context.org = org

  return true, context
end

function MZGaragemAccess.getExpectedGarageId(garage)
  garage = garage and MZGaragemAccess.getGarage(garage.id or garage) or nil
  if not garage then
    return nil
  end

  if garage.kind == 'service' then
    return nil
  end

  if garage.rules and garage.rules.strict_garage == true then
    return garage.id
  end

  return nil
end
