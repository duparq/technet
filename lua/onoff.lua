
do
   lighton=0
   -- pin=4
   -- gpio.mode(pin,gpio.OUTPUT)            -- Assign GPIO to Output

   function blink()
      if lighton==0 then
	 lighton=1
	 -- gpio.write(pin,gpio.HIGH)     -- Assign GPIO On
	 print('ON')
      else
	 lighton=0
	 -- gpio.write(pin,gpio.LOW)     -- Assign GPIO off
	 print('OFF')
      end
   end

   tmr.create():alarm( 250, tmr.ALARM_AUTO, blink )
end
