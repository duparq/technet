
--  Met à jour l'affichage.
--  Le contenu peut être préparé par une fonction 'SCREEN'.
--  Sinon le contenu par défaut s'affiche.
--
function initDisplay()

   local function update()
      if type(SCREEN) == "function" then
	 SCREEN()
      end
      displayTimer:start()
   end

   if displayTimer == nil then
      local sla = 0x3C
      local scl = 6
      local sda = 5
      i2c.setup(0, sda, scl, i2c.FAST)
      display = u8g2.ssd1306_i2c_128x64_noname(0, sla)
      display:setFontRefHeightExtendedText()
      display:setDrawColor(1)
      display:setFontPosTop()
      display:setFontDirection(0)
      displayTimer = tmr.create()
      displayTimer:register(250, tmr.ALARM_SEMI, update)
      displayTimer:start()
   end
end

initDisplay()
