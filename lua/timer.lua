
-- ncalls = 0

local timer

function run ( )

   -- local timer
   local lncalls

   print("TIMER1",timer)

   -- if lncalls == nil then lncalls=0 end

   -- if timer ~= nil then print("watcher already started") return end

   local function update ( )
      -- ncalls = ncalls + 1
      lncalls = (lncalls or 0) + 1
      -- print(string.format("%d %d %f",lncalls,ncalls,tmr:now()/1000000))
      print(string.format("%d %f",lncalls,tmr:now()/1000000))

      if lncalls < 10 then
	 timer:start()
      else
	 timer:unregister()
	 timer = nil
      end
   end

   timer = tmr.create()
   timer:register(500, tmr.ALARM_SEMI, update)
   timer:start()
end


run()
run()
