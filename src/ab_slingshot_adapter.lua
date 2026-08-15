-- NextOS controller adapter for Angry Birds Classic 8.0.3.
--
-- The original encrypted Slingshot.lua is still loaded verbatim from the
-- owner's APK.  This small wrapper only adds controller ownership around the
-- game's public SlingshotSystem methods; it contains no game data.

-- Execute the original script first through the loader inherited by this
-- script environment.  The host maps this private virtual path to the
-- untouched Slingshot.lua bytes from the owner's APK.
loadLuaFile("scripts/SlingshotNextOSOriginal.lua", "")

local originalGameUpdate = SlingshotSystem.gameUpdate
local controlDragging = false
local controlArmed = true
local filteredX = 0
local filteredY = 0

local function controllerPowerDrawer()
  local hud = menuManager and menuManager:getRoot()
  if not hud or hud.name ~= "gameHud" or not g_powerups_enabled or
     hud.hidePowerups then return end
  local slider = hud.powerup_slider
  if not slider and hud.getChild then
    slider = hud:getChild("powerup_button")
  end
  if not slider or slider.enabled == false or slider.visible == false then
    return
  end
  -- Drive the same button path as an actual tap. GameHud then applies its
  -- notification/child-lock guards, banner handling, sounds and persistent
  -- g_powerup_slider_default_open state itself.
  local x1, y1, x2, y2 = slider:getButtonBounds()
  if x1 and y1 and x2 and y2 then
    local x = (x1 + x2) * 0.5
    local y = (y1 + y2) * 0.5
    hud:onPointerEvent("LPRESS", x, y)
    hud:onPointerEvent("LRELEASE", x, y)
  end
end

local function controllerVision()
  -- R1 reproduz o clique no Mighty Eagle (o ícone de olho ao lado da barra),
  -- pela mesma rota do HUD. Não escolhe nenhum item da barra: esses continuam
  -- exclusivos do cursor.
  local hud = menuManager and menuManager:getRoot()
  local eye = hud and hud.name == "gameHud" and hud:getChild("eagleButton")
  if eye and eye.visible ~= false and not g_tutorialActive and
     (not notificationsFrame or
      not notificationsFrame:isAnyBlockingChildVisible()) then
    hud:onPointerEvent("LPRESS", eye.x, eye.y)
    hud:onPointerEvent("LRELEASE", eye.x, eye.y)
  end
end

local function controllerShockwave()
  local hud = menuManager and menuManager:getRoot()
  if hud and hud.name == "gameHud" and g_show_ingame_black_bird_button and
     g_powerups_enabled and not levelCompleted and not skipInput and
     not g_tutorialActive and hud:shouldShockwaveButtonBeVisible() and
     (not notificationsFrame or
      not notificationsFrame:isAnyBlockingChildVisible()) then
    local button = hud:getChild("blackBirdButton")
    if button and button.visible ~= false then
      -- Same UI dispatch as touching the real icon below Pause. This retains
      -- tutorial/modal/transition/inventory guards and normal click feedback.
      hud:onPointerEvent("LPRESS", button.x, button.y)
      hud:onPointerEvent("LRELEASE", button.x, button.y)
    end
  end
end

SlingshotSystem.gameUpdate = function(self, dt)
  originalGameUpdate(self, dt)

  -- os.clock is an otherwise unused native slot in this mobile build.  The
  -- host replaces it with an atomic controller snapshot: axes, ownership and
  -- three one-shot button edges.
  local rawX, rawY, blocked, pressL1, pressR1, pressTriangle, pressLaunch =
    _G.os.clock()
  local magnitude = _G.math.sqrt(rawX * rawX + rawY * rawY)
  local idleForUi = not blocked and not controlDragging and magnitude < 0.12

  -- UI actions never overlap an active sling, cursor or camera gesture, so one
  -- physical control can never cancel another.
  if pressL1 and idleForUi then controllerPowerDrawer() end
  if pressR1 and idleForUi then controllerVision() end
  if pressTriangle and idleForUi then controllerShockwave() end

  -- Ownership is immediate; only the target vector is smoothed. Releasing the
  -- physical stick therefore launches immediately instead of waiting for a
  -- filtered value to decay through the deadzone.
  if blocked then
    if controlDragging and self:isBirdDragged() then
      self:cancelBirdDrag()
    end
    controlDragging = false
    filteredX = 0
    filteredY = 0
    controlArmed = magnitude < 0.12
    return
  end

  -- Precision launch: keep the exact current stick vector and fire on A.
  -- The host suppresses A's pointer touch only while the left-stick gesture
  -- already owns the sling; this Lua state is the final proof that a real bird
  -- is being dragged. Releasing the stick remains available as a fallback.
  if pressLaunch and controlDragging and self:isBirdDragged() then
    self:releaseRubberBandToLaunchBird()
    controlDragging = false
    controlArmed = false
    filteredX = 0
    filteredY = 0
    return
  end

  if not controlDragging then
    if magnitude < 0.12 then
      controlArmed = true
    elseif controlArmed and magnitude > 0.22 and currentBirdName and
           birdReady and not levelCompleted and not skipInput and
           self:isSlingshotVisible() and self:isSlingshotAvailable() and
           not self:isBirdDragged() then
      local bird = objects.world[currentBirdName]
      if bird and not bird.shot then
        self:setDraggedBird(bird)
        controlDragging = self:isBirdDragged()
        controlArmed = false
        filteredX = 0
        filteredY = 0
      end
    end
  end

  if controlDragging then
    if magnitude < 0.12 then
      if self:isBirdDragged() then
        self:releaseRubberBandToLaunchBird()
      end
      controlDragging = false
      filteredX = 0
      filteredY = 0
      return
    end

    if not birdReady or levelCompleted or skipInput or
       not self:isSlingshotVisible() or not self:isBirdDragged() then
      if self:isBirdDragged() then self:cancelBirdDrag() end
      controlDragging = false
      filteredX = 0
      filteredY = 0
      return
    end

    -- Circular deadzone with radial rescale. Squaring only the magnitude gives
    -- fine aim near center while preserving all 360 degrees and diagonals.
    local unitX = rawX / magnitude
    local unitY = rawY / magnitude
    local force = (magnitude - 0.16) / 0.84
    if force < 0 then force = 0 end
    if force > 1 then force = 1 end
    force = force * force
    local targetX = unitX * force
    local targetY = unitY * force
    local blend = 1 - _G.math.exp(-14 * dt)
    filteredX = filteredX + (targetX - filteredX) * blend
    filteredY = filteredY + (targetY - filteredY) * blend
    local length = self:getRubberBandMaxLength()
    self:stretchRubberBand({x = -filteredX * length,
                            y = -filteredY * length})
  end
end
