local BEEP = (__dirname or '.') .. '/beep.wav'                  -- 1 car beep
local BEEP_DOUBLE = (__dirname or '.') .. '/beep_double.wav'    -- 2+ car beep
local BEEP_SOLID = (__dirname or '.') .. '/beep_solid.wav'  -- stopped car

--------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------

local DEFAULTS = {
  enabled     = true,
  range       = 300,    -- how far ahead along the road to warn about, metres
  volume      = 1.4,
  beepSpeed   = 1.0,    -- multiplies how rapidly the beeps repeat
  multiWarn   = true,   -- double beep while two or more oncoming cars are in range
  rangeMulti = 100,    -- when a car is considered being followed, used for calculating carsAhead
  crashWarn   = true,   -- warn about cars stopped on the road ahead
  rangeSolid  = 100,    -- inside this zone the stopped-car warning goes to a solid tone
}

local ok, stored = pcall(ac.storage, DEFAULTS)
local settings = ok and stored or DEFAULTS

--------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------

local SAMPLE_M     = 3      -- distance between recorded road points, metres

local SNAP_WIN     = 40     -- points searched either side of a car's last position
local MAX_SNAP_D   = 40     -- beyond this distance from the road a car is unplaceable

-- Determine travel direction
local ACQUIRE_M    = 15     -- travel needed to learn a direction, metres
local FLIP_M       = 50     -- travel the other way needed to reverse one, metres

-- Rejecting impossible readings. Where the road folds back on itself the two
-- sides of a hairpin are far apart along the road but close in space, so a
-- misplaced car shows up as a huge jump. Anything implying a car moved
-- further than its own speed allows is discarded; if that keeps happening the
-- car really moved (pit respawn, teleport) and is relocated
local JUMP_FACTOR  = 2.5    -- multiple of its own speed a car may appear to move
local JUMP_MARGIN  = 8      -- plus this much slack, metres
local LOST_T       = 0.5    -- impossible readings for this long means a teleport

-- Searching the whole road is the one expensive operation here, so a car that
-- cannot be placed on it at all (parked in a paddock, spectating, sitting on
-- an unrecorded side road) is retried a few times a second rather than on
-- every frame.
local RELOCATE_T   = 0.4    -- seconds between full-road searches, per car

-- Check if a car is crashed rather than just normally progressing the course.
local STOP_V       = 4    -- m/s along the road, below this counts as stopped
local STOP_T       = 1.0    -- seconds it must hold before warning
local PROG_WINDOW  = 0.5    -- s: window the progress rate is measured over
local RECOVER_T    = 20     -- s after a stop that a car counts as manoeuvring

-- Beep
local BEEP_LEN     = 0.26   -- length of beep.wav, seconds
local BEEP_TAIL    = 0.02   -- breathing room after it finishes, seconds
local BEEP_MIN     = BEEP_LEN + BEEP_TAIL   -- a beep can never restart sooner
local BEEP_FAST    = 0.28   -- gap between beeps at nil range, seconds
local BEEP_SLOW    = 0.80   -- extra gap between beeps at max range, seconds

--------------------------------------------------------------------------
-- Road files
--------------------------------------------------------------------------

local APP_TRACKS = (__dirname or '.') .. '/tracks'
local DOC_TRACKS = nil
if ac.getFolder and ac.FolderID then
  local documents = ac.getFolder(ac.FolderID.ACDocuments)
  if documents then DOC_TRACKS = documents .. '/TougeSpotter' end
end

-- Track ID including layout, layout-dependant!
local function trackKey()
  if ac.getTrackFullID then
    local found, id = pcall(ac.getTrackFullID, '_')
    if found and id and #id > 0 then return id end
  end
  return 'unknown_track'
end

local KEY = trackKey()

local points     = {}    -- road as recorded, in driving order
local along      = {}    -- metres travelled along the road at each point
local pointCount = 0     -- kept alongside points so the search loop avoids #
local roadLen    = 0
local loadedFrom = nil   -- 'app' or 'documents', for the panel (incase app writing is blocked)

local function parseTrackFile(text)
  local out = {}
  for line in text:gmatch('[^\r\n]+') do
    if line:sub(1, 1) ~= '#' then
      local x, y, z = line:match('^%s*(-?[%d%.eE+]+)%s+(-?[%d%.eE+]+)%s+(-?[%d%.eE+]+)%s*$')
      if x then out[#out + 1] = { x = tonumber(x), y = tonumber(y), z = tonumber(z) } end
    end
  end
  return out
end

-- Measure the real distance between recorded points
local function measureRoad()
  along, roadLen = {}, 0
  pointCount = #points
  if pointCount < 2 then return end
  along[1] = 0
  for i = 2, #points do
    local a, b = points[i - 1], points[i]
    local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
    along[i] = along[i - 1] + math.sqrt(dx*dx + dy*dy + dz*dz)
  end
  roadLen = along[#points]
end

local function loadTrack()
  points, along, pointCount, roadLen, loadedFrom = {}, {}, 0, 0, nil

  local candidates = { APP_TRACKS .. '/' .. KEY .. '.txt' }
  if DOC_TRACKS then candidates[#candidates + 1] = DOC_TRACKS .. '/' .. KEY .. '.txt' end

  for _, path in ipairs(candidates) do
    if io.fileExists and io.fileExists(path) then
      local read, text = pcall(io.load, path)
      if read and text and #text > 0 then
        local parsed = parseTrackFile(text)
        if #parsed >= 2 then
          points = parsed
          measureRoad()
          loadedFrom = (path == candidates[1]) and 'app' or 'documents'
          return
        end
      end
    end
  end
end

-- Saves the track points into the app folder. If impossible, saves ino Documents folder
-- Returns the path used
local function saveTrack(recorded)
  local body = {
    '# TougeSpotter road recording',
    '# track: ' .. KEY,
    '# points: ' .. #recorded,
    '# format: x y z (world metres, in driving order)',
  }
  for i = 1, #recorded do
    body[#body + 1] = string.format('%.3f %.3f %.3f',
      recorded[i].x, recorded[i].y, recorded[i].z)
  end
  local text = table.concat(body, '\n')

  local targets = { { dir = APP_TRACKS, label = 'app' } }
  if DOC_TRACKS then targets[#targets + 1] = { dir = DOC_TRACKS, label = 'documents' } end

  for _, target in ipairs(targets) do
    pcall(io.createDir, target.dir)
    local path = target.dir .. '/' .. KEY .. '.txt'
    if pcall(io.save, path, text) and io.fileExists and io.fileExists(path) then
      return path, target.label
    end
  end
  return nil, nil
end

loadTrack()

--------------------------------------------------------------------------
-- Audio
--------------------------------------------------------------------------

local beep = nil

local function playBeep(volume, file)
  if not (ac and ac.AudioEvent) then return end
  if beep ~= nil then beep:dispose() end
  beep = ac.AudioEvent.fromFile({ filename = file or BEEP, use3D = false, loop = false }, false)
  beep.volume = volume
  beep:start()
  beep.volume = volume
end

local solid, solidOn = nil, false

local function setSolid(wanted)
  if wanted == solidOn then
    if solidOn and solid then solid.volume = settings.volume end
    return
  end
  solidOn = wanted
  if wanted then
    if solid ~= nil then
      local okv, valid = pcall(function() return solid:isValid() end)
      if okv and not valid then pcall(function() solid:dispose() end); solid = nil end
    end
    if solid == nil and ac and ac.AudioEvent then
      solid = ac.AudioEvent.fromFile({ filename = BEEP_SOLID, use3D = false, loop = true }, false)
    end
    if solid ~= nil then
      solid.volume = settings.volume
      solid:start()
      solid.volume = settings.volume
    end
  elseif solid ~= nil then
    solid:stop()
  end
end

-- Seconds until the next beep for a car at normalised distance t. 
-- Never shorter than the sample takes to play.
local function intervalFor(t)
  local interval = (BEEP_FAST + BEEP_SLOW * t) / math.max(settings.beepSpeed, 0.05)
  if interval < BEEP_MIN then return BEEP_MIN end
  return interval
end

--------------------------------------------------------------------------
-- Locating cars on the road
--------------------------------------------------------------------------

-- Squared distances throughout: comparing them orders points identically to
-- real distances and avoids a square root per point.
local MAX_SNAP_SQ = MAX_SNAP_D * MAX_SNAP_D

local function nearestInRange(x, y, z, first, last)
  local bestIndex, bestSq = nil, math.huge
  for i = first, last do
    local p = points[i]
    local dx, dy, dz = x - p.x, y - p.y, z - p.z
    local sq = dx*dx + dy*dy + dz*dz
    if sq < bestSq then bestSq, bestIndex = sq, i end
  end
  return bestIndex, bestSq         -- bestSq stays huge if the range was empty
end

-- Searches the whole road. Used only when a car has no known position yet.
local function locate(x, y, z)
  local index, sq = nearestInRange(x, y, z, 1, pointCount)
  if sq > MAX_SNAP_SQ then return nil end
  return index
end

-- Searches near where the car was last seen, which keeps it from jumping to
-- the far side of a hairpin where the road passes close to itself.
local function locateNear(x, y, z, lastIndex)
  local first = lastIndex - SNAP_WIN
  local last  = lastIndex + SNAP_WIN
  if first < 1 then first = 1 end
  if last > pointCount then last = pointCount end
  local index, sq = nearestInRange(x, y, z, first, last)
  if sq > MAX_SNAP_SQ then return nil end
  return index
end

--------------------------------------------------------------------------
-- Tracking a car's position and direction along the road
--------------------------------------------------------------------------

-- Per-car state:
--   index   most recent trusted road point
--   dir     +1 travelling the way the road was recorded, -1 against it, 0 unknown
--   mark    furthest point reached so far in the current direction, metres along
--   lost    seconds of consecutive impossible readings
--   retry   used on freshstart or failsafe against scanning 

local function forget(state, index)
  state.index = index
  state.dir   = 0
  state.mark  = index and along[index] or nil
  state.lost  = 0
  state.retry = 0
  state.prog    = STOP_V * 4   -- progress along the road, m/s (assume moving)
  state.still   = 0            -- seconds spent below STOP_V
  state.progRef = index and along[index] or 0
  state.progT   = 0
  state.recover = 0            -- s left of treating direction changes as cheap
end

-- Updates a car's direction from how its position along the road moves. The
-- mark trails the furthest point reached. Backtracking must exceed FLIP_M
-- before the direction reverses.
local function updateDirection(state)
  local here = along[state.index]
  if state.mark == nil then state.mark = here end

  -- mores sensitive direction change
  local flip = state.recover > 0 and ACQUIRE_M or FLIP_M

  if state.dir == 0 then
    local moved = here - state.mark
    if math.abs(moved) >= ACQUIRE_M then
      state.dir  = moved > 0 and 1 or -1
      state.mark = here
    end
  elseif state.dir > 0 then
    if here > state.mark then state.mark = here
    elseif here < state.mark - flip then state.dir, state.mark = -1, here end
  else
    if here < state.mark then state.mark = here
    elseif here > state.mark + flip then state.dir, state.mark = 1, here end
  end
end

-- Feeds one frame of position, discarding readings that cannot be real. A car
-- keeps its last known position while readings are being rejected, and is
-- relocated from scratch once they have been rejected for LOST_T.
local function trackCar(state, x, y, z, speedKmh, dt)
  if state.index == nil then
    state.retry = state.retry - dt
    if state.retry > 0 then return end
    state.retry = RELOCATE_T
    local found = locate(x, y, z)
    if found ~= nil then forget(state, found) end
    return
  end

  local candidate = locateNear(x, y, z, state.index)
  if candidate == nil then                      -- too far from the road to place
    state.lost = state.lost + dt
    if state.lost >= LOST_T then forget(state, locate(x, y, z)) end
    return
  end

  local moved   = math.abs(along[candidate] - along[state.index])
  local allowed = (speedKmh or 0) / 3.6 * dt * JUMP_FACTOR + JUMP_MARGIN
  if moved > allowed then                       -- faster than normally possible
    state.lost = state.lost + dt
    if state.lost >= LOST_T then forget(state, locate(x, y, z)) end
    return
  end

  -- Progress along the road, used to spot a car that has stopped. Road position over delta
  state.progT = state.progT + dt
  if state.progT >= PROG_WINDOW then
    state.prog = math.abs(along[candidate] - state.progRef) / state.progT
    state.progRef, state.progT = along[candidate], 0
  end
  if state.prog < STOP_V then state.still = state.still + dt else state.still = 0 end

  state.lost  = 0
  state.index = candidate

  -- Stopping is not evidence of a new direction, so the old one is kept: only
  -- a teleport or a pit visit, which make the position meaningless, clear it.
  -- What a stop does earn is the cheaper flip threshold above, which is what
  -- lets a car that spun or reversed while recovering be re-read quickly.
  if state.still >= STOP_T then
    state.recover = RECOVER_T
  elseif state.recover > 0 then
    state.recover = state.recover - dt
  end

  updateDirection(state)
end

--------------------------------------------------------------------------
-- Live state
--------------------------------------------------------------------------

local others    = {}   -- per-car tracking state, keyed by car index
local player    = { index = nil, dir = 0, mark = nil, lost = 0, retry = 0 }
local beepTimer = 0

-- Recording 'off' -> 'armed' (waiting to leave the pits) -> 'recording'
local recState, recPoints, recLength, recMessage = 'off', {}, 0, ''
local wasInPits, confirmOverwrite = false, false

-- Panel readout
local inPits       = false
local spectating   = false
local gapHazard    = nil   -- road distance to the nearest stopped car ahead
local gapAhead     = nil   -- road distance to the nearest oncoming car ahead
local gapBehind    = nil   -- road distance to the nearest one already passed
local carsAhead    = 0     -- how many oncoming cars are in range (this frame)

local function directionWord(dir)
  if dir > 0 then return 'downhill' elseif dir < 0 then return 'uphill' end
  return '?'
end

local function finishRecording()
  local path, label = saveTrack(recPoints)
  if path then
    recMessage = string.format('Saved %d points to %s folder', #recPoints, label)
    loadTrack()
  else
    recMessage = 'SAVE FAILED - could not write file'
  end
  recState = 'off'
end

--------------------------------------------------------------------------
function script.update(dt)
  inPits = false
  spectating = false
  gapAhead, gapBehind = nil, nil
  gapHazard = nil
  carsAhead = 0

  local sim = ac.getSim(); if not sim then return end

  -- Spectator beep fix
  if sim.focusedCar ~= 0 or sim.isReplayActive then
    spectating = true
    beepTimer = 0
    setSolid(false)
    forget(player, nil)
    return
  end

  local me  = ac.getCar(sim.focusedCar); if not me then return end

  local pos = me.position
  local nowInPits = me.isInPitlane and true or false

  ------------------------------------------------------------------ recording
  if recState == 'armed' then
    if not nowInPits then
      recState, recPoints, recLength, recMessage = 'recording', {}, 0, ''
      recPoints[1] = { x = pos.x, y = pos.y, z = pos.z }
    end

  elseif recState == 'recording' then
    local last = recPoints[#recPoints]
    local dx, dy, dz = pos.x - last.x, pos.y - last.y, pos.z - last.z
    local step = math.sqrt(dx*dx + dy*dy + dz*dz)
    if step >= SAMPLE_M then
      recPoints[#recPoints + 1] = { x = pos.x, y = pos.y, z = pos.z }
      recLength = recLength + step
    end
    -- Reaching a pit area at the far end ends the recording.
    if nowInPits and not wasInPits and #recPoints > 20 then finishRecording() end
  end
  wasInPits = nowInPits

  ------------------------------------------------------------------ detection
  if not settings.enabled or recState == 'recording' or #points < 2 then
    beepTimer = 0
    setSolid(false)
    inPits = nowInPits
    return
  end

  if nowInPits then
    inPits = true
    beepTimer = 0
    setSolid(false)
    forget(player, nil)          -- pitting invalidates status
    return
  end

  trackCar(player, pos.x, pos.y, pos.z, me.speedKmh, dt)
  if player.dir == 0 or player.index == nil then beepTimer = 0; setSolid(false); return end

  local myDir   = player.dir
  local myAlong = along[player.index]
  local nearest = nil

  for _, car in ac.iterateCars.ordered() do
    if car.index ~= me.index then
      local state = others[car.index]
      if not state then
        state = { index = nil, dir = 0, mark = nil, lost = 0, retry = 0 }
        others[car.index] = state
      end

      if car.isInPitlane then
        forget(state, nil)
      else
        trackCar(state, car.position.x, car.position.y, car.position.z, car.speedKmh, dt)
        -- Direction is required for the check. 
        -- Direction decides whether a moving car matters.
        -- Direction doesn't matter for a stopped car detection
        if state.dir ~= 0 and state.index ~= nil then
          local stopped = settings.crashWarn and state.still >= STOP_T
          local oncoming = state.dir ~= 0 and state.dir ~= myDir
          -- Distance along the road, signed by our direction of travel:
          -- positive is ahead, negative means already passed it.
          local gap = (along[state.index] - myAlong) * myDir
          if gap > 0 then
            if stopped then
              if gap <= settings.range and (gapHazard == nil or gap < gapHazard) then
                gapHazard = gap
              end
            end
            if oncoming then
              if gap <= settings.range + settings.rangeMulti then
                -- Count every oncoming car in range, not only the closest. 
                -- Once passed goes back to single beep
                carsAhead = carsAhead + 1
              end
            end
            -- A stopped car sets the beep rate
            if gap <= settings.range and (oncoming or stopped) then
              if nearest == nil or gap < nearest then nearest = gap end
            end
          elseif oncoming and (gapBehind == nil or -gap < gapBehind) then
            gapBehind = -gap
          end
        end
      end
    end
  end

  ----------------------------------------------------------------- warning
  -- A stopped car gets a beep priority
  local solidWanted = gapHazard ~= nil and gapHazard <= settings.rangeSolid
  setSolid(solidWanted)

  if solidWanted then
    beepTimer = 0
    gapAhead = nearest
  elseif nearest ~= nil then
    local t = math.saturate(nearest / settings.range)
    beepTimer = beepTimer - dt
    if beepTimer <= 0 then
      beepTimer = intervalFor(t)
      local sample = (settings.multiWarn and carsAhead > 1) and BEEP_DOUBLE or BEEP
      playBeep(settings.volume, sample)
    end
    gapAhead = nearest
  else
    beepTimer = 0                -- ready to beep on next
  end
end

--------------------------------------------------------------------------
function script.windowMain(dt)
  if ui.button(settings.enabled and 'Status: ON' or 'Status: OFF') then
    settings.enabled = not settings.enabled
  end

  ------------------------------------------------------------ road recording
  ui.text('')
  ui.text('Track: ' .. KEY)
  if #points >= 2 then
    ui.text(string.format('  road: %d points, %.0f m (%s)', #points, roadLen, loadedFrom or '?'))
  else
    ui.text('  NO RECORDING - press Record and drive the road')
  end

  if recState == 'off' then
    if confirmOverwrite then
      ui.text('Overwrite existing recording? WARNING: PERMANENT!')
      if ui.button('Yes, record again') then
        recState, confirmOverwrite, recMessage = 'armed', false, ''
      end
      if ui.button('Cancel') then confirmOverwrite = false end
    elseif ui.button('Record road') then
      if #points >= 2 then confirmOverwrite = true
      else recState, recMessage = 'armed', '' end
    end

  elseif recState == 'armed' then
    ui.text('ARMED - leave the pits to start recording')
    if ui.button('Cancel') then recState = 'off' end

  else
    ui.text(string.format('RECORDING  %d points  %.0f m', #recPoints, recLength))
    ui.text('  drive to the far end; pit area stops it')
    if ui.button('Stop and save') then finishRecording() end
  end

  if recMessage ~= '' then ui.text(recMessage) end

  ------------------------------------------------------------------ settings
  ui.text('')
  settings.range = ui.slider('##range', settings.range, 40, 600, 'Warn within: %.0f m of road')

  settings.beepSpeed = ui.slider('##speed', settings.beepSpeed, 0.1, 2.0, 'Beep speed: %.2fx')
  settings.volume    = ui.slider('##vol', settings.volume, 0, 2, 'Volume: %.2f')

  if ui.button(settings.multiWarn and 'Multiple cars: double beep' or 'Multiple cars: same beep') then
    settings.multiWarn = not settings.multiWarn
  end
  if settings.multiWarn then
    ui.text('Additional detection outside of range')
    settings.rangeMulti = ui.slider('##rangeMulti', settings.rangeMulti, 0, 300, 'Detection: %.0f m of road')
  end

  if ui.button(settings.crashWarn and 'Stopped cars: warn' or 'Stopped cars: ignore') then
    settings.crashWarn = not settings.crashWarn
    if not settings.crashWarn then setSolid(false) end
  end
  if settings.crashWarn then
    ui.text('Solid tone once this close to a stopped car')
    settings.rangeSolid = ui.slider('##rangeSolid', settings.rangeSolid, 20, 300, 'Solid within: %.0f m of road')
  end

  ui.text('')
  if ui.button('Test beep') then playBeep(settings.volume) end
  if ui.button('Test double beep') then playBeep(settings.volume, BEEP_DOUBLE) end
  if ui.button('Test solid beep') then playBeep(settings.volume, BEEP_SOLID) end

  ------------------------------------------------------------------ readout
  ui.text('')
  ui.text('Debug')
  if spectating then
    ui.text('spectating - detection paused')
  elseif recState == 'recording' then
    ui.text('detection paused while recording')
  elseif inPits then
    ui.text('in pits - detection paused')
  elseif #points < 2 then
    ui.text('no road recording - silent')
  else
    ui.text('moving: ' .. directionWord(player.dir))
    if gapHazard ~= nil then
      ui.text(string.format('>> STOPPED CAR  %.0f m up the road%s', gapHazard,
        gapHazard <= settings.rangeSolid and ' - solid tone' or ''))
    end
    if gapAhead ~= nil then
      ui.text(string.format('>> ONCOMING  %.0f m up the road', gapAhead))
      ui.text(string.format('   %d in range%s', carsAhead,
        carsAhead > 1 and ' - double beep' or ''))
    elseif gapBehind ~= nil then
      ui.text(string.format('clear (last one %.0f m behind you)', gapBehind))
    else
      ui.text('clear')
    end
  end
end