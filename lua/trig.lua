
-- Envoie un message à chaque basculement de la broche D1
do
   local pin = 1
   local function cb(level,tim,cnt)
      -- print(string.format("D1=%d %d",level,cnt))
      print(string.format("D1=%d %d",gpio.read(pin),cnt))
      gpio.trig(pin, level == gpio.HIGH and "down" or "up")
   end
   gpio.mode(pin, gpio.INT, gpio.PULLUP)
   gpio.trig(pin, "both", cb)
end
