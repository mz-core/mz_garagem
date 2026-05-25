MZGaragemAccess = MZGaragemAccess or {}

local VALID_KINDS = {
  public = true,
  org = true,
  service = true,
  house = true
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

local function shouldLogGarageOpenDebug(garage)
  local garageId = tostring(type(garage) == 'table' and garage.id or garage or '')
  return MZGaragemConfig and MZGaragemConfig.debug == true
    and (garageId == 'police_org' or garageId == 'police_service')
end

local function logAccessOpenDebug(stage, source, garage, org, err)
  if not shouldLogGarageOpenDebug(garage) then
    return
  end

  garage = type(garage) == 'table' and garage or {}
  local access = type(garage.access) == 'table' and garage.access or {}
  local grade = type(org) == 'table' and type(org.grade) == 'table' and org.grade.level or nil

  print(('[mz_garagem][open_access][%s][source:%s] garage_id=%s | kind=%s | org_code=%s | require_membership=%s | require_duty=%s | membership_found=%s | duty=%s | grade_level=%s | fleet_id=%s | error=%s'):format(
    tostring(stage or 'unknown'),
    tostring(source or 'unknown'),
    tostring(garage.id or ''),
    tostring(garage.kind or ''),
    tostring(garage.org_code or ''),
    tostring(access.require_membership),
    tostring(access.require_duty),
    tostring(type(org) == 'table'),
    tostring(type(org) == 'table' and org.duty or nil),
    tostring(grade),
    tostring(garage.fleet_id or ''),
    tostring(err or '')
  ))
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

local function normalizeHouseContext(context)
  context = type(context) == 'table' and context or {}

  return {
    garageType = tostring(context.garageType or context.type or ''),
    token = tostring(context.token or ''),
    houseCode = tostring(context.houseCode or context.house_code or '')
  }
end

function MZGaragemAccess.resolve(source, garageId, requestContext)
  local player = getPlayer(source)
  if not player then
    return false, 'player_not_loaded'
  end

  local garage = MZGaragemAccess.getGarage(garageId)
  if not garage then
    return false, 'garage_not_found'
  end

  logAccessOpenDebug('garage_loaded', source, garage, nil, nil)

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

  if garage.kind == 'house' then
    local houseContext = normalizeHouseContext(requestContext)
    local house = type(garage.house) == 'table' and garage.house or {}
    local sessions = type(house.sessions) == 'table' and house.sessions or {}
    local session = sessions[tonumber(source) or 0]
    local expiresAt = type(session) == 'table' and tonumber(session.expires_at) or 0
    local sessionToken = type(session) == 'table' and tostring(session.token or '') or ''

    if not session or expiresAt <= os.time() then
      sessions[tonumber(source) or 0] = nil
      if MZGaragemHouseSessions then
        MZGaragemHouseSessions[tonumber(source) or 0] = nil
      end
      return false, 'house_garage_expired'
    end

    if houseContext.garageType ~= 'house' then
      return false, 'house_garage_session_invalid'
    end

    if houseContext.token == '' or sessionToken == '' or houseContext.token ~= sessionToken then
      return false, 'house_garage_token_invalid'
    end

    if houseContext.houseCode ~= '' and tostring(house.code or '') ~= houseContext.houseCode then
      return false, 'house_garage_access_denied'
    end

    -- Renovar a sessao enquanto a UI/callbacks da garagem ainda estao em uso.
    session.expires_at = os.time() + (tonumber(house.session_seconds) or 300)
    if MZGaragemHouseSessions and MZGaragemHouseSessions[tonumber(source) or 0] then
      MZGaragemHouseSessions[tonumber(source) or 0].expires_at = session.expires_at
    end

    context.house = house
    context.houseSession = session
    return true, context
  end

  local orgCode = tostring(garage.org_code or '')
  if orgCode == '' then
    logAccessOpenDebug('resolve_ok_no_org_code', source, garage, nil, nil)
    return true, context
  end

  local org = MZGaragemAccess.resolveOrgMembership(source, orgCode)
  logAccessOpenDebug('membership_lookup', source, garage, org, nil)
  if not org then
    logAccessOpenDebug('resolve_error', source, garage, org, 'org_membership_required')
    return false, 'org_membership_required'
  end

  local access = garage.access or {}
  if access.require_membership ~= false and not org then
    logAccessOpenDebug('resolve_error', source, garage, org, 'org_membership_required')
    return false, 'org_membership_required'
  end

  if access.require_duty == true and org.duty ~= true then
    logAccessOpenDebug('resolve_error', source, garage, org, 'org_duty_required')
    return false, 'org_duty_required'
  end

  if access.primary_only == true and org.isPrimary ~= true then
    logAccessOpenDebug('resolve_error', source, garage, org, 'org_primary_required')
    return false, 'org_primary_required'
  end

  local minGradeLevel = tonumber(access.min_grade_level or 0) or 0
  local currentGradeLevel = tonumber(org.grade and org.grade.level or 0) or 0
  if currentGradeLevel < minGradeLevel then
    logAccessOpenDebug('resolve_error', source, garage, org, 'org_grade_too_low')
    return false, 'org_grade_too_low'
  end

  local requiredPermissions = access.required_org_permissions or {}
  for _, permission in ipairs(requiredPermissions) do
    if type(org.permissions) ~= 'table' or org.permissions[permission] ~= true then
      logAccessOpenDebug('resolve_error', source, garage, org, 'org_permission_required')
      return false, 'org_permission_required'
    end
  end

  context.org = org
  logAccessOpenDebug('resolve_ok', source, garage, org, nil)

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
