MZGaragemServiceStateRepository = MZGaragemServiceStateRepository or {}

local function decode(value)
  local ok, decoded = pcall(json.decode, value or '')
  return ok and type(decoded) == 'table' and decoded or {}
end

local function encode(value)
  local ok, encoded = pcall(json.encode, value)
  return ok and encoded or '{}'
end

local function normalizeNumber(value, fallback, minimum, maximum)
  local numeric = tonumber(value)
  if not numeric then
    return fallback
  end

  if minimum and numeric < minimum then numeric = minimum end
  if maximum and numeric > maximum then numeric = maximum end
  return numeric + 0.0
end

local function normalizeCitizenid(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function normalizeState(row)
  if type(row) ~= 'table' then
    return nil
  end

  local citizenid = normalizeCitizenid(row.citizenid)
  local garageId = tostring(row.garage_id or '')
  local entryId = tostring(row.entry_id or '')
  if citizenid == '' or garageId == '' or entryId == '' then
    return nil
  end

  local engine = normalizeNumber(row.engine, 1000.0, 0.0, 1000.0)
  local body = normalizeNumber(row.body, 1000.0, 0.0, 1000.0)

  return {
    citizenid = citizenid,
    garage_id = garageId,
    fleet_id = tostring(row.fleet_id or ''),
    entry_id = entryId,
    fuel = normalizeNumber(row.fuel, 100.0, 0.0, 100.0),
    engine = engine,
    body = body,
    props = decode(row.props_json),
    destroyed = row.destroyed == true or row.destroyed == 1 or row.destroyed == '1'
      or engine <= 50.0
      or body <= 100.0,
    updated_at = row.updated_at
  }
end

function MZGaragemServiceStateRepository.prepare()
  return MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS mz_garage_service_state (
      citizenid VARCHAR(64) NOT NULL,
      garage_id VARCHAR(64) NOT NULL,
      fleet_id VARCHAR(64) NOT NULL,
      entry_id VARCHAR(64) NOT NULL,
      fuel FLOAT NOT NULL DEFAULT 100,
      engine FLOAT NOT NULL DEFAULT 1000,
      body FLOAT NOT NULL DEFAULT 1000,
      props_json LONGTEXT NULL,
      destroyed TINYINT(1) NOT NULL DEFAULT 0,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (citizenid, garage_id, entry_id),
      KEY idx_mz_garage_service_state_fleet (garage_id, fleet_id, entry_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  ]])
end

function MZGaragemServiceStateRepository.loadForCitizen(citizenid)
  citizenid = normalizeCitizenid(citizenid)
  if citizenid == '' then
    return {}
  end

  local rows = MySQL.query.await([[
    SELECT citizenid, garage_id, fleet_id, entry_id, fuel, engine, body, props_json, destroyed, updated_at
    FROM mz_garage_service_state
    WHERE citizenid = ?
  ]], { citizenid }) or {}

  local out = {}
  for _, row in ipairs(rows) do
    local state = normalizeState(row)
    if state then
      out[#out + 1] = state
    end
  end
  return out
end

function MZGaragemServiceStateRepository.upsert(state)
  if type(state) ~= 'table' then
    return false, 'invalid_service_state'
  end

  local citizenid = normalizeCitizenid(state.citizenid)
  local garageId = tostring(state.garage_id or '')
  local entryId = tostring(state.entry_id or '')
  if citizenid == '' or garageId == '' or entryId == '' then
    return false, 'invalid_service_state'
  end

  local fleetId = tostring(state.fleet_id or '')
  local fuel = normalizeNumber(state.fuel, 100.0, 0.0, 100.0)
  local engine = normalizeNumber(state.engine, 1000.0, 0.0, 1000.0)
  local body = normalizeNumber(state.body, 1000.0, 0.0, 1000.0)
  local props = type(state.props) == 'table' and state.props or decode(state.props_json)
  local encodedProps = encode(props)
  local destroyed = state.destroyed == true
    or state.destroyed == 1
    or state.destroyed == '1'
    or engine <= 50.0
    or body <= 100.0

  return MySQL.insert.await([[
    INSERT INTO mz_garage_service_state (
      citizenid,
      garage_id,
      fleet_id,
      entry_id,
      fuel,
      engine,
      body,
      props_json,
      destroyed
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
      fleet_id = VALUES(fleet_id),
      fuel = VALUES(fuel),
      engine = VALUES(engine),
      body = VALUES(body),
      props_json = VALUES(props_json),
      destroyed = VALUES(destroyed),
      updated_at = CURRENT_TIMESTAMP
  ]], {
    citizenid,
    garageId,
    fleetId,
    entryId,
    fuel,
    engine,
    body,
    encodedProps,
    destroyed and 1 or 0
  })
end
