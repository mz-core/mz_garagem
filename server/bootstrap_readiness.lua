MZGaragemBootstrapReadiness = MZGaragemBootstrapReadiness or {}

local DEFAULT_TIMEOUT_MS = 120000
local DEFAULT_POLL_INTERVAL_MS = 50

local function defaultProbe()
  local resourceState = GetResourceState('mz_org')
  if resourceState == 'missing' or resourceState == 'stopped' or resourceState == 'stopping' then
    return {
      ready = false,
      terminal = true,
      reason = 'organization_owner_unavailable'
    }
  end

  if resourceState ~= 'started' then
    return {
      ready = false,
      terminal = false,
      reason = 'organization_owner_starting'
    }
  end

  local ok, result = pcall(function()
    return exports['mz_org']:GetOrganizationReadiness()
  end)
  if not ok or type(result) ~= 'table' then
    return {
      ready = false,
      terminal = false,
      reason = 'organization_readiness_contract_unavailable'
    }
  end

  return result
end

function MZGaragemBootstrapReadiness.wait(options)
  options = type(options) == 'table' and options or {}

  local probe = type(options.probe) == 'function' and options.probe or defaultProbe
  local clock = type(options.clock) == 'function' and options.clock or GetGameTimer
  local yield = type(options.yield) == 'function' and options.yield or Wait
  local timeoutMs = tonumber(options.timeoutMs) or DEFAULT_TIMEOUT_MS
  local pollIntervalMs = tonumber(options.pollIntervalMs) or DEFAULT_POLL_INTERVAL_MS
  local startedAt = clock()
  local attempts = 0

  while true do
    attempts = attempts + 1
    local state = probe()
    if type(state) == 'table' and state.ready == true then
      return true, {
        attempts = attempts,
        elapsedMs = clock() - startedAt,
        reason = 'ready'
      }
    end

    if type(state) == 'table' and state.terminal == true then
      return false, tostring(state.reason or 'organization_owner_failed')
    end

    if clock() - startedAt >= timeoutMs then
      return false, 'organization_readiness_timeout'
    end

    yield(pollIntervalMs)
  end
end

function MZGaragemBootstrapReadiness.runWhenReady(callback, options)
  if type(callback) ~= 'function' then
    return false, 'invalid_bootstrap_callback'
  end

  local ready, result = MZGaragemBootstrapReadiness.wait(options)
  if not ready then
    return false, result
  end

  callback()
  return true, result
end
