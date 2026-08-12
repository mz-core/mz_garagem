local function expect(condition, message)
  if not condition then error(message, 2) end
end

dofile('server/bootstrap_readiness.lua')

local now = 0
local yields = 0
local probes = 0
local queryCalls = 0
local sequence = {
  { ready = false, terminal = false, reason = 'organization_owner_preparing' },
  { ready = false, terminal = false, reason = 'organization_seed_pending' },
  { ready = true, terminal = false, reason = 'ready' }
}

local ok, result = MZGaragemBootstrapReadiness.runWhenReady(function()
  queryCalls = queryCalls + 1
  expect(probes == 3, 'organization query ran before readiness')
end, {
  probe = function()
    probes = probes + 1
    return sequence[probes]
  end,
  clock = function() return now end,
  yield = function(interval)
    yields = yields + 1
    now = now + interval
  end,
  timeoutMs = 100,
  pollIntervalMs = 10
})

expect(ok == true, 'bootstrap did not continue after readiness')
expect(type(result) == 'table' and result.attempts == 3, 'readiness attempt count is incorrect')
expect(queryCalls == 1, 'organization query did not run exactly once after readiness')
expect(yields == 2, 'polling did not remain readiness-conditioned')

local immediateYields = 0
local immediateQueries = 0
local immediateOk = MZGaragemBootstrapReadiness.runWhenReady(function()
  immediateQueries = immediateQueries + 1
end, {
  probe = function() return { ready = true, terminal = false, reason = 'ready' } end,
  clock = function() return 0 end,
  yield = function() immediateYields = immediateYields + 1 end
})

expect(immediateOk == true, 'already-ready bootstrap failed')
expect(immediateQueries == 1 and immediateYields == 0, 'already-ready bootstrap waited unnecessarily')

local blockedQueries = 0
local callOk, blockedOk, blockedReason = pcall(function()
  return MZGaragemBootstrapReadiness.runWhenReady(function()
    blockedQueries = blockedQueries + 1
  end, {
    probe = function()
      return { ready = false, terminal = true, reason = 'organization_schema_prepare_failed' }
    end,
    clock = function() return 0 end,
    yield = function() error('terminal failure must not yield') end
  })
end)

expect(callOk == true, 'not-ready owner broke garage bootstrap')
expect(blockedOk == false and blockedReason == 'organization_schema_prepare_failed', 'terminal owner failure was not explicit')
expect(blockedQueries == 0, 'organization query ran after terminal owner failure')

local timeoutNow = 0
local timeoutOk, timeoutReason = MZGaragemBootstrapReadiness.runWhenReady(function()
  error('timed-out bootstrap must not run')
end, {
  probe = function()
    return { ready = false, terminal = false, reason = 'organization_owner_preparing' }
  end,
  clock = function() return timeoutNow end,
  yield = function(interval) timeoutNow = timeoutNow + interval end,
  timeoutMs = 20,
  pollIntervalMs = 10
})

expect(timeoutOk == false and timeoutReason == 'organization_readiness_timeout', 'bounded timeout did not fail closed')

print('organization_readiness_bootstrap_harness: PASS delayed=1 immediate=1 terminal=1 timeout=1')
