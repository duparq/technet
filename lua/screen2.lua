
SCREEN = function ( )
   local t = tmr.time()
   local s = t % 60
   local m = math.floor(t/60) % 60
   local h = math.floor(t/3600)
   display:clearBuffer()
   display:setFont(u8g2.font_9x18B_tf)
   display:drawStr( 28, 24, string.format("%02d:%02d:%02d", h, m, s))
   display:updateDisplayArea( 3, 3, 10, 2 );
end
