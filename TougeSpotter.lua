local BEEP = (__dirname or '.') .. '/beep.wav'

--------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------

local DEFAULTS = {
  enabled     = true,
  range       = 300,    -- how far ahead along the road to warn about, metres
  volume      = 1.2,
  staticPitch = false,  -- true: hold basePitch; false: let it rise as cars near
  basePitch   = 0.95,   -- pitch of the beep at maximum range
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
local JUMP_MARGIN  = 8      -- slack, metres
local LOST_T       = 0.5    -- impossible readings -> a teleport

-- Beep character
local PITCH_RISE   = 0.55   -- how far the pitch climbs from max range to nil range
local BEEP_FAST    = 0.12   -- gap between beeps at nil range, seconds
local BEEP_SLOW    = 0.90   -- extra gap between beeps at max range, seconds

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
  if #points < 2 then return end
  along[1] = 0
  for i = 2, #points do
    local a, b = points[i - 1], points[i]
    local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
    along[i] = along[i - 1] + math.sqrt(dx*dx + dy*dy + dz*dz)
  end
  roadLen = along[#points]
end

local function loadTrack()
  points, along, roadLen, loadedFrom = {}, {}, 0, nil

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

local function playBeep(pitch, volume)
  if not (ac and ac.AudioEvent) then return end
  if beep ~= nil then beep:dispose() end
  beep = ac.AudioEvent.fromFile({ filename = BEEP, use3D = false, loop = false }, false)
  beep.pitch  = pitch
  beep.volume = volume
  beep:start()
end

-- Pitch for a car at normalised distance t (0 = on top, 1 = max range).
local function pitchFor(t)
  if settings.staticPitch then return settings.basePitch end
  return settings.basePitch + PITCH_RISE * (1 - t)
end

--------------------------------------------------------------------------
-- Locating cars on the road
--------------------------------------------------------------------------

local function nearestInRange(x, y, z, first, last)
  local bestIndex, bestSq
  for i = first, last do
    local p = points[i]
    local dx, dy, dz = x - p.x, y - p.y, z - p.z
    local sq = dx*dx + dy*dy + dz*dz
    if bestSq == nil or sq < bestSq then bestSq, bestIndex = sq, i end
  end
  return bestIndex, bestSq
end

-- Searches the whole road. Used only when a car has no known position yet.
local function locate(x, y, z)
  local index, sq = nearestInRange(x, y, z, 1, #points)
  if sq == nil or sq > MAX_SNAP_D * MAX_SNAP_D then return nil end
  return index
end

-- Searches near where the car was last seen, which keeps it from jumping to
-- the far side of a hairpin where the road passes close to itself.
local function locateNear(x, y, z, lastIndex)
  local index, sq = nearestInRange(x, y, z,
    math.max(1, lastIndex - SNAP_WIN), math.min(#points, lastIndex + SNAP_WIN))
  if sq == nil or sq > MAX_SNAP_D * MAX_SNAP_D then return nil end
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

local function forget(state, index)
  state.index = index
  state.dir   = 0
  state.mark  = index and along[index] or nil
  state.lost  = 0
end

-- Updates a car's direction from how its position along the road moves. The
-- mark trails the furthest point reached, so backtracking must exceed FLIP_M
-- before the direction reverses.
local function updateDirection(state)
  local here = along[state.index]
  if state.mark == nil then state.mark = here end

  if state.dir == 0 then
    local moved = here - state.mark
    if math.abs(moved) >= ACQUIRE_M then
      state.dir  = moved > 0 and 1 or -1
      state.mark = here
    end
  elseif state.dir > 0 then
    if here > state.mark then state.mark = here
    elseif here < state.mark - FLIP_M then state.dir, state.mark = -1, here end
  else
    if here < state.mark then state.mark = here
    elseif here > state.mark + FLIP_M then state.dir, state.mark = 1, here end
  end
end

-- Feeds one frame of position, discarding readings that cannot be real. A car
-- keeps its last known position while readings are being rejected, and is
-- relocated from scratch once they have been rejected for LOST_T.
local function trackCar(state, x, y, z, speedKmh, dt)
  if state.index == nil then
    forget(state, locate(x, y, z))
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

  state.lost  = 0
  state.index = candidate
  updateDirection(state)
end

--------------------------------------------------------------------------
-- Live update loop
--------------------------------------------------------------------------

local others    = {}   -- per-car tracking state, keyed by car index
local player    = { index = nil, dir = 0, mark = nil, lost = 0 }
local beepTimer = 0

-- Recording 'off' -> 'armed' (waiting to leave the pits) -> 'recording'
local recState, recPoints, recLength, recMessage = 'off', {}, 0, ''
local wasInPits, confirmOverwrite = false, false

-- Panel readout
local inPits       = false
local gapAhead     = nil   -- road distance to the nearest oncoming car ahead
local gapBehind    = nil   -- road distance to the nearest one already passed

local function directionWord(dir)
  -- Recording runs top to bottom, so advancing along the road is downhill.
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
  gapAhead, gapBehind = nil, nil

  local sim = ac.getSim(); if not sim then return end
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
    inPits = nowInPits
    return
  end

  if nowInPits then
    inPits = true
    beepTimer = 0
    forget(player, nil)          -- pitting invalidates status
    return
  end

  trackCar(player, pos.x, pos.y, pos.z, me.speedKmh, dt)
  if player.dir == 0 or player.index == nil then beepTimer = 0; return end

  local myDir   = player.dir
  local myAlong = along[player.index]
  local nearest = nil

  for _, car in ac.iterateCars.ordered() do
    if car.index ~= me.index then
      local state = others[car.index]
      if not state then
        state = { index = nil, dir = 0, mark = nil, lost = 0 }
        others[car.index] = state
      end

      if car.isInPitlane then
        forget(state, nil)
      else
        trackCar(state, car.position.x, car.position.y, car.position.z, car.speedKmh, dt)

        -- Only cars travelling the opposite way along the road are oncoming.
        -- A stopped car keeps the direction it had while moving, so one that
        -- crashed coming the other way still counts as a hazard ?
        if state.dir ~= 0 and state.index ~= nil and state.dir ~= myDir then
          -- Distance along the road, signed by our direction of travel:
          -- positive is ahead, negative means already passed it.
          local gap = (along[state.index] - myAlong) * myDir
          if gap > 0 then
            if gap <= settings.range and (nearest == nil or gap < nearest) then
              nearest = gap
            end
          elseif gapBehind == nil or -gap < gapBehind then
            gapBehind = -gap
          end
        end
      end
    end
  end

  ----------------------------------------------------------------- warning
  if nearest ~= nil then
    local t = math.saturate(nearest / settings.range)
    beepTimer = beepTimer - dt
    if beepTimer <= 0 then
      playBeep(pitchFor(t), settings.volume)
      beepTimer = BEEP_FAST + BEEP_SLOW * t
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
      ui.text('Overwrite existing recording? WARNING: PERMANENT')
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

  if ui.button(settings.staticPitch and 'Pitch: static' or 'Pitch: rises as it nears') then
    settings.staticPitch = not settings.staticPitch
  end
  settings.basePitch = ui.slider('##pitch', settings.basePitch, 0.5, 2.0, 'Base pitch: %.2f')
  settings.volume    = ui.slider('##vol', settings.volume, 0, 2, 'Volume: %.2f')

  if ui.button('Test beep') then playBeep(pitchFor(0.5), settings.volume) end

  ------------------------------------------------------------------ readout
  ui.text('Debug:')
  if recState == 'recording' then
    ui.text('detection paused while recording')
  elseif inPits then
    ui.text('in pits - detection paused')
  elseif #points < 2 then
    ui.text('no road recording - silent')
  else
    ui.text('moving: ' .. directionWord(player.dir))
    if gapAhead ~= nil then
      ui.text(string.format('>> ONCOMING  %.0f m up the road', gapAhead))
    elseif gapBehind ~= nil then
      ui.text(string.format('clear (last one %.0f m behind you)', gapBehind))
    else
      ui.text('clear')
    end
  end
end