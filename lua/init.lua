if file.open("sta.lc") then
   dofile("sta.lc")
elseif file.open("sta.lua") then
   dofile("sta.lua")
elseif file.open("ap.lc") then
   dofile("ap.lc")
elseif file.open("ap.lua") then
   dofile("ap.lua")
end
