
function hd(buf)
   for byte=1, #buf, 16 do
      local chunk = buf:sub(byte, byte+15)
      uw(0,string.format('%04X  ',byte-1))
      chunk:gsub('.', function (c) uw(0,string.format('%02X ',string.byte(c))) end)
      uw(0,string.rep(' ',3*(16-#chunk)))
      uw(0,' ',chunk:gsub('%c','.'),"\n") 
   end
end
