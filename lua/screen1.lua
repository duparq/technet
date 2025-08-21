
--  Affichage par défaut pour une station
--  
SCREEN = function ( )
   display:clearBuffer()
   display:setFont(u8g2.font_9x18B_tf)

   display:drawStr( 0, 0, string.format("%s-%s", SSID, station))

   local t = tmr.time()
   local s = t % 60
   local m = math.floor(t/60) % 60
   local h = math.floor(t/3600)
   display:setFont(u8g2.font_6x10_tf)
   display:drawStr( 0, 16, string.format("Up %d:%02d:%02d heap:%5d", h, m, s, node.heap()))
   display:sendBuffer()
end
