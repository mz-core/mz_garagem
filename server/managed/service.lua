MZGaragemManaged = MZGaragemManaged or {
  ready = false,
  loadError = nil,
  staticIds = {},
  managedIds = {}
}

local VALID_TOP_LEVEL_KEYS = {
  code = true,
  label = true,
  kind = true,
  orgCode = true,
  entry = true,
  spawn = true,
  store = true,
  settings = true
}

local VALID_CATEGORY_MODES = {
  car = { 'car' },
  bike = { 'bike' },
  car_bike = { 'car', 'bike' },
  boat = { 'boat' },
  plane = { 'plane' }
}

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function clone(value)
  if type(value) ~= 'table' then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = clone(item) end
  return out
end

local function onlyKeys(value, allowed)
  if type(value) ~= 'table' then return false end
  for key in pairs(value) do
    if allowed[key] ~= true then return false end
  end
  return true
end

local function finiteNumber(value, minValue, maxValue)
  value = tonumber(value)
  if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
  if value < minValue or value > maxValue then return nil end
  return value + 0.0
end

local function coordinate(value, heading)
  if type(value) ~= 'table' then return nil end
  local x = finiteNumber(value.x or value[1], -10000.0, 10000.0)
  local y = finiteNumber(value.y or value[2], -10000.0, 10000.0)
  local z = finiteNumber(value.z or value[3], -1000.0, 3000.0)
  if not x or not y or not z then return nil end

  local out = { x = x, y = y, z = z }
  if heading then
    local w = finiteNumber(value.w or value.heading or value[4] or 0.0, -36000.0, 36000.0)
    if not w then return nil end
    out.w = ((w % 360.0) + 360.0) % 360.0
  end
  return out
end

local function distance(left, right)
  local dx = left.x - right.x
  local dy = left.y - right.y
  local dz = left.z - right.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function bool(value, fallback)
  if value == true then return true end
  if value == false then return false end
  return fallback == true
end

local function asBool(value)
  if value == true or value == 1 then return true end
  return type(value) == 'string' and (value == '1' or value:lower() == 'true')
end

local function hasPermission(source, permission)
  local ok, allowed = pcall(function()
    return exports['mz_core']:HasGlobalPermission(source, permission)
  end)
  return ok and allowed == true
end

local function decode(value)
  local ok, decoded = pcall(json.decode, value or '')
  return ok and type(decoded) == 'table' and decoded or nil
end

local function encode(value)
  local ok, encoded = pcall(json.encode, value)
  return ok and encoded or nil
end

local function clientDefinition(definition)
  local out = clone(definition)
  out._managed = true
  return out
end

local function snapshot()
  local rows = {}
  for code in pairs(MZGaragemManaged.managedIds) do
    local garage = MZGaragemGarages and MZGaragemGarages[code] or nil
    if garage then rows[#rows + 1] = clientDefinition(garage) end
  end
  table.sort(rows, function(left, right) return tostring(left.id) < tostring(right.id) end)
  return rows
end

local function categoryModeFor(definition)
  local categories = definition
    and definition.filters
    and definition.filters.categories
    or {}
  if #categories == 2
    and tostring(categories[1]) == 'car'
    and tostring(categories[2]) == 'bike'
  then
    return 'car_bike'
  end
  local category = tostring(categories[1] or 'car')
  return VALID_CATEGORY_MODES[category] and category or 'car'
end

local function adminDefinition(row, definition)
  return {
    code = tostring(row.garage_code or definition.id or ''),
    label = tostring(row.label or definition.label or ''),
    kind = tostring(row.kind or definition.kind or ''),
    orgCode = row.org_code or definition.org_code,
    active = asBool(row.active),
    entry = clone(definition.zone and definition.zone.coords),
    spawn = clone(definition.spawn_points and definition.spawn_points[1]),
    store = clone(definition.store and definition.store.coords),
    settings = {
      categoryMode = categoryModeFor(definition),
      strictGarage = definition.rules and definition.rules.strict_garage == true,
      blipEnabled = type(definition.blip) == 'table' and definition.blip.enabled == true,
      allowImpounded = definition.rules and definition.rules.allow_impounded == true,
      requireDuty = definition.access and definition.access.require_duty == true,
      primaryOnly = definition.access and definition.access.primary_only == true,
      minGradeLevel = tonumber(definition.access and definition.access.min_grade_level) or 0
    },
    createdByName = tostring(row.created_by_name or ''),
    createdAt = row.created_at,
    updatedAt = row.updated_at
  }
end

local function normalizePersisted(row)
  local definition = decode(row.definition_json)
  if not definition then return nil, 'invalid_json' end

  definition.id = trim(row.garage_code)
  definition.label = trim(row.label)
  definition.kind = trim(row.kind)
  definition.org_code = trim(row.org_code) ~= '' and trim(row.org_code) or nil
  definition._managed = true

  if #definition.id < 3 or #definition.id > 64 or not definition.id:match('^[a-z][a-z0-9_-]*$') then
    return nil, 'invalid_code'
  end
  if #definition.label < 3 or #definition.label > 120 then return nil, 'invalid_label' end

  local entry = coordinate(definition.zone and definition.zone.coords, false)
  local spawn = coordinate(definition.spawn_points and definition.spawn_points[1], true)
  local store = coordinate(definition.store and definition.store.coords, false)
  if not entry or not spawn or not store then return nil, 'invalid_coordinates' end
  if distance(entry, spawn) > 250.0 or distance(entry, store) > 250.0 then
    return nil, 'coordinates_too_far'
  end
  definition.zone.coords = entry
  definition.spawn_points = { spawn }
  definition.store.coords = store

  if definition.kind == 'org' then
    local ok, org = pcall(function()
      return exports['mz_core']:GetOrgByCode(definition.org_code)
    end)
    if not ok or type(org) ~= 'table' then return nil, 'invalid_org' end
    if org.active ~= true then return nil, 'org_archived' end
  end

  local ok, err = MZGaragemAccess.validateGarageDefinition(definition.id, definition)
  if not ok then return nil, err end
  return definition
end

local function normalizePayload(payload)
  if not onlyKeys(payload, VALID_TOP_LEVEL_KEYS) then return nil, 'invalid_payload' end

  local code = trim(payload.code):lower()
  if #code < 3 or #code > 64 or not code:match('^[a-z][a-z0-9_-]*$') then
    return nil, 'invalid_code'
  end

  local kind = trim(payload.kind):lower()
  if kind ~= 'public' and kind ~= 'org' then return nil, 'invalid_kind' end

  local entry = coordinate(payload.entry, false)
  local spawn = coordinate(payload.spawn, true)
  local store = coordinate(payload.store, false)
  if not entry or not spawn or not store then return nil, 'invalid_coordinates' end
  if distance(entry, spawn) > 250.0 or distance(entry, store) > 250.0 then
    return nil, 'coordinates_too_far'
  end

  local settings = type(payload.settings) == 'table' and payload.settings or {}
  local categoryMode = trim(settings.categoryMode):lower()
  local categories = VALID_CATEGORY_MODES[categoryMode]
  if not categories then return nil, 'invalid_category' end

  local orgCode
  local organization
  if kind == 'org' then
    orgCode = trim(payload.orgCode):lower()
    if orgCode == '' or #orgCode > 64 then return nil, 'invalid_org' end
    local ok, org = pcall(function() return exports['mz_core']:GetOrgByCode(orgCode) end)
    if not ok or type(org) ~= 'table' then return nil, 'invalid_org' end
    if org.active ~= true then return nil, 'org_archived' end
    organization = org
  elseif trim(payload.orgCode) ~= '' then
    return nil, 'public_cannot_have_org'
  end

  local label = trim(payload.label)
  if label == '' then
    label = kind == 'public'
      and 'Garagem Pública'
      or ('Garagem - %s'):format(trim(organization and organization.name) ~= '' and trim(organization.name) or orgCode)
  end
  if #label < 3 or #label > 120 then return nil, 'invalid_label' end

  local strict = bool(settings.strictGarage, true)
  local blipEnabled = bool(settings.blipEnabled, kind == 'public')
  local minGrade = math.floor(tonumber(settings.minGradeLevel) or 0)
  if minGrade < 0 or minGrade > 1000 then return nil, 'invalid_min_grade' end

  local definition = {
    id = code,
    label = label,
    kind = kind,
    org_code = orgCode,
    zone = {
      coords = entry,
      radius = 3.0
    },
    spawn_points = { spawn },
    blip = {
      enabled = blipEnabled,
      sprite = 357,
      color = kind == 'org' and 3 or 38,
      scale = 0.6,
      label = label
    },
    interact = {
      icon = {
        textureDict = 'mod_icon',
        textureName = 'garage'
      }
    },
    store = {
      enabled = true,
      coords = store,
      radius = 3.5,
      interact = {
        enabled = true,
        drawDistance = 18.0,
        interactDistance = 4.0,
        marker = {
          enabled = true,
          type = 1,
          size = { x = 3.5, y = 3.5, z = 0.18 },
          color = { r = 80, g = 210, b = 255, a = 70 },
          bobUpAndDown = false,
          rotate = false,
          faceCamera = false
        },
        text = {
          enabled = true,
          label = '[E] Guardar veiculo',
          offsetZ = 0.45
        },
        blip = { enabled = false }
      }
    },
    filters = {
      categories = clone(categories)
    },
    rules = {
      strict_garage = strict,
      shared_pool = not strict,
      allow_impounded = kind == 'public' and bool(settings.allowImpounded, true) or false
    }
  }

  if kind == 'org' then
    definition.access = {
      require_membership = true,
      require_duty = bool(settings.requireDuty, false),
      min_grade_level = minGrade,
      primary_only = bool(settings.primaryOnly, false),
      required_org_permissions = {}
    }
  end

  local valid, validationError = MZGaragemAccess.validateGarageDefinition(code, definition)
  if not valid then return nil, validationError end
  return definition
end

local function actorFor(source)
  local ok, player = pcall(function() return exports['mz_core']:GetPlayerSnapshot(source) end)
  if not ok or type(player) ~= 'table' or trim(player.citizenid) == '' then
    return nil, 'player_not_loaded'
  end
  return {
    citizenid = trim(player.citizenid),
    name = trim(GetPlayerName(source)) ~= '' and trim(GetPlayerName(source)) or trim(player.citizenid)
  }
end

local function auditCreate(source, actor, definition)
  pcall(function()
    exports['mz_core']:CreateDetailedLog('garages', 'managed_garage_created', {
      actor = {
        type = 'player',
        source = source,
        citizenid = actor.citizenid,
        name = actor.name
      },
      target = {
        type = 'garage',
        id = definition.id,
        label = definition.label
      },
      context = {
        org_code = definition.org_code,
        kind = definition.kind
      },
      after = {
        garage_code = definition.id,
        label = definition.label,
        kind = definition.kind,
        org_code = definition.org_code
      }
    })
  end)
end

local function auditMutation(source, actor, action, before, after)
  pcall(function()
    local current = after or before or {}
    exports['mz_core']:CreateDetailedLog('garages', action, {
      actor = {
        type = 'player',
        source = source,
        citizenid = actor.citizenid,
        name = actor.name
      },
      target = {
        type = 'garage',
        id = current.code or current.id,
        label = current.label
      },
      context = {
        org_code = current.orgCode or current.org_code,
        kind = current.kind
      },
      before = before or {},
      after = after or {}
    })
  end)
end

for garageId in pairs(MZGaragemGarages or {}) do
  MZGaragemManaged.staticIds[tostring(garageId)] = true
end

function MZGaragemManaged.Initialize()
  MZGaragemManaged.ready = false
  MZGaragemManaged.loadError = nil

  local ok, err = pcall(function()
    MZGaragemManagedPrepare.run()
    local rows = MZGaragemManagedRepository.listActive()
    for _, row in ipairs(rows) do
      local code = trim(row.garage_code)
      if MZGaragemManaged.staticIds[code] then
        print(('[mz_garagem] definicao persistente "%s" ignorada: colide com garagem estatica'):format(code))
      else
        local definition, normalizeError = normalizePersisted(row)
        if definition then
          MZGaragemGarages[code] = definition
          MZGaragemManaged.managedIds[code] = true
        else
          print(('[mz_garagem] definicao persistente "%s" ignorada: %s'):format(code, tostring(normalizeError)))
        end
      end
    end
  end)

  if not ok then
    MZGaragemManaged.loadError = tostring(err)
    print(('[mz_garagem] repositorio de garagens administradas indisponivel: %s'):format(tostring(err)))
    return false, 'managed_repository_unavailable'
  end

  MZGaragemManaged.ready = true
  print(('[mz_garagem] %d garagem(ns) administrada(s) carregada(s)'):format(#snapshot()))
  return true
end

function MZGaragemManaged.Create(source, payload)
  source = tonumber(source)
  if not source or source <= 0 then return false, 'invalid_source' end
  if MZGaragemManaged.ready ~= true then return false, 'managed_repository_unavailable' end

  if not hasPermission(source, 'staff.garages.create') then return false, 'permission_denied' end

  local definition, validationError = normalizePayload(payload)
  if not definition then return false, validationError end
  if MZGaragemManaged.staticIds[definition.id] or MZGaragemManaged.managedIds[definition.id] then
    return false, 'garage_code_exists'
  end

  local actor, actorError = actorFor(source)
  if not actor then return false, actorError end

  local encoded = encode(definition)
  if not encoded then return false, 'encode_failed' end

  local insertOk, insertId = pcall(function()
    return MZGaragemManagedRepository.create({
      code = definition.id,
      label = definition.label,
      kind = definition.kind,
      org_code = definition.org_code,
      definition_json = encoded,
      created_by_citizenid = actor.citizenid,
      created_by_name = actor.name
    })
  end)
  if not insertOk or not insertId then
    local existingOk, existing = pcall(MZGaragemManagedRepository.getByCode, definition.id)
    return false, existingOk and existing and 'garage_code_exists' or 'database_error'
  end

  definition._managed = true
  MZGaragemGarages[definition.id] = definition
  MZGaragemManaged.managedIds[definition.id] = true
  if MZGaragem and MZGaragem.state then
    MZGaragem.state.garage_count = (tonumber(MZGaragem.state.garage_count) or 0) + 1
  end

  auditCreate(source, actor, definition)
  TriggerClientEvent('mz_garagem:client:managedGarageUpsert', -1, clientDefinition(definition))
  return true, clientDefinition(definition)
end

function MZGaragemManaged.ListForAdmin(source)
  source = tonumber(source)
  if not source or source <= 0 then return false, 'invalid_source' end
  if MZGaragemManaged.ready ~= true then return false, 'managed_repository_unavailable' end
  if not hasPermission(source, 'staff.garages.view') then return false, 'permission_denied' end

  local queryOk, rows = pcall(MZGaragemManagedRepository.listAll)
  if not queryOk then return false, 'database_error' end

  local out = {}
  for _, row in ipairs(rows or {}) do
    local definition = decode(row.definition_json)
    if type(definition) == 'table' then
      out[#out + 1] = adminDefinition(row, definition)
    end
  end
  return true, out
end

function MZGaragemManaged.Update(source, garageCode, payload)
  source = tonumber(source)
  garageCode = trim(garageCode):lower()
  if not source or source <= 0 or garageCode == '' then return false, 'invalid_request' end
  if MZGaragemManaged.ready ~= true then return false, 'managed_repository_unavailable' end
  if not hasPermission(source, 'staff.garages.manage') then return false, 'permission_denied' end

  local rowOk, row = pcall(MZGaragemManagedRepository.getByCode, garageCode)
  if not rowOk then return false, 'database_error' end
  if type(row) ~= 'table' then return false, 'garage_not_found' end
  if MZGaragemManaged.staticIds[garageCode] then return false, 'static_garage_protected' end

  payload = type(payload) == 'table' and payload or {}
  if trim(payload.code):lower() ~= garageCode then return false, 'garage_code_immutable' end
  local definition, validationError = normalizePayload(payload)
  if not definition then return false, validationError end
  if definition.kind ~= tostring(row.kind or '') then return false, 'garage_kind_immutable' end
  local currentOrgCode = trim(row.org_code)
  if trim(definition.org_code) ~= currentOrgCode then return false, 'garage_org_immutable' end

  local actor, actorError = actorFor(source)
  if not actor then return false, actorError end
  local encoded = encode(definition)
  if not encoded then return false, 'encode_failed' end

  local beforeDefinition = decode(row.definition_json) or {}
  local before = adminDefinition(row, beforeDefinition)
  local updateOk = pcall(MZGaragemManagedRepository.updateDefinition, garageCode, {
    label = definition.label,
    kind = definition.kind,
    org_code = definition.org_code,
    definition_json = encoded
  })
  if not updateOk then return false, 'database_error' end

  definition._managed = true
  if asBool(row.active) then
    MZGaragemGarages[garageCode] = definition
    MZGaragemManaged.managedIds[garageCode] = true
    TriggerClientEvent('mz_garagem:client:managedGarageUpsert', -1, clientDefinition(definition))
  end

  local updatedRow = clone(row)
  updatedRow.label = definition.label
  updatedRow.kind = definition.kind
  updatedRow.org_code = definition.org_code
  updatedRow.definition_json = encoded
  local after = adminDefinition(updatedRow, definition)
  auditMutation(source, actor, 'managed_garage_updated', before, after)
  return true, after
end

function MZGaragemManaged.SetActive(source, garageCode, active)
  source = tonumber(source)
  garageCode = trim(garageCode):lower()
  if not source or source <= 0 or garageCode == '' or type(active) ~= 'boolean' then
    return false, 'invalid_request'
  end
  if MZGaragemManaged.ready ~= true then return false, 'managed_repository_unavailable' end
  if not hasPermission(source, 'staff.garages.manage') then return false, 'permission_denied' end

  local rowOk, row = pcall(MZGaragemManagedRepository.getByCode, garageCode)
  if not rowOk then return false, 'database_error' end
  if type(row) ~= 'table' then return false, 'garage_not_found' end
  if MZGaragemManaged.staticIds[garageCode] then return false, 'static_garage_protected' end

  local currentActive = asBool(row.active)
  local rawDefinition = decode(row.definition_json)
  if type(rawDefinition) ~= 'table' then return false, 'invalid_persisted_definition' end
  if currentActive == active then return true, adminDefinition(row, rawDefinition) end

  local definition
  if active then
    local validationError
    definition, validationError = normalizePersisted(row)
    if not definition then
      return false, validationError or 'invalid_persisted_definition'
    end
  end

  local actor, actorError = actorFor(source)
  if not actor then return false, actorError end
  local updateOk = pcall(MZGaragemManagedRepository.setActive, garageCode, active)
  if not updateOk then return false, 'database_error' end

  if active then
    MZGaragemGarages[garageCode] = definition
    MZGaragemManaged.managedIds[garageCode] = true
    TriggerClientEvent('mz_garagem:client:managedGarageUpsert', -1, clientDefinition(definition))
  else
    MZGaragemGarages[garageCode] = nil
    MZGaragemManaged.managedIds[garageCode] = nil
    TriggerClientEvent('mz_garagem:client:managedGarageRemove', -1, garageCode)
  end

  if MZGaragem and MZGaragem.state then
    local count = tonumber(MZGaragem.state.garage_count) or 0
    MZGaragem.state.garage_count = math.max(0, count + (active and 1 or -1))
  end

  local before = adminDefinition(row, rawDefinition)
  row.active = active and 1 or 0
  local after = adminDefinition(row, definition or rawDefinition)
  auditMutation(source, actor, active and 'managed_garage_activated' or 'managed_garage_archived', before, after)
  return true, after
end

function MZGaragemManaged.Snapshot()
  return snapshot()
end

lib.callback.register('mz_garagem:server:getManagedGarages', function()
  if MZGaragemManaged.ready ~= true then
    return { ok = false, error = 'managed_repository_unavailable' }
  end
  return { ok = true, garages = snapshot() }
end)

exports('IsManagedGarageReady', function()
  return MZGaragemManaged.ready == true, MZGaragemManaged.loadError
end)

exports('CreateManagedGarage', function(source, payload)
  return MZGaragemManaged.Create(source, payload)
end)

exports('ListManagedGaragesForAdmin', function(source)
  return MZGaragemManaged.ListForAdmin(source)
end)

exports('UpdateManagedGarage', function(source, garageCode, payload)
  return MZGaragemManaged.Update(source, garageCode, payload)
end)

exports('SetManagedGarageActive', function(source, garageCode, active)
  return MZGaragemManaged.SetActive(source, garageCode, active)
end)

exports('ListManagedGarages', function()
  return snapshot()
end)
