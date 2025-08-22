
--  PASSERELLE TECHNET (POINT D'ACCES)
--
--  Crée un réseau Wi-Fi ouvert "TECHNET". Établit un pont entre le port série
--  et le réseau TECHNET avec une socket UDP.
--
--  Démultiplexage des messages arrivant du port série:
--
--   * la sortie du port série (arrivée des messages) est redirigée vers une
--     fonction de traitement.
--
--      * Les messsages préfixés par "--N " sont destinés à la station n°N, N
--        correspondant au dernier octet de l'adresse IP de la station. Le
--        préfixe est supprimé et le reste du message est envoyé par la socket
--        UDP vers l'IP de la station sur le port 1.
--
--      * Les messages non préfixés sont transmis à l'interpréteur Lua local.
--
--  Multiplexage des messages arrivant de la socket UDP:
--
--   * l'adresse de l'émetteur indiqué par la socket permet de déterminer la
--     station N à l'origine du message.
--
--      * Si la station est connectée à un client (state==3) le message est
--        envoyé sur le port série avec le préfixe "--N ".
--
--      * Si la station n'est pas connectée à un client (state==1) le message
--        est envoyé sur le port série (sauf si c'est un ACK puisque c'est la
--        réponse à un ENQ qui permet de déterminer qu'une station est active).
--
--      * Si la station est dans un autre état, un message d'information est
--        envoyé sur le port série.
--

--  Compilation :  ./nodemcu-firmware/luac.cross -o ap.lc lua/ap.lua 
--  Installation : nodemcu-tool -p /dev/ttyUSB0 -b 460800 upload ap.lc 
--  Suppression depuis NodeMcu : > file.remove("ap.lc")


--  TODO:
--   *  supprimer le codage en dur "192.168.4"


node.setcpufreq(node.CPU160MHZ)

t0 = 0		-- dernier tmr:now()
h0 = 0		-- dernier node.heap()
ticks = 0	-- nombre d'appels à ontick


--  Table des stations ayant émis au moins un message
--    Clé: adresse IP
--    Valeur: âge du dernier message, en nombre de pings.
--
pings = {}


--  Table des états des stations
--    Clé: adresse IP
--    Valeur:
--      * nil:
--      * 0:
--      * 1: disponible (répond aux pings)
--      * 2: STX envoyé (demande ouverture telnet)
--      * 3: STX reçu (telnet établi)
--      * 4: ETX envoyé (demande de fin de telnet)
--
--  Une station dont le state est > 1 ne doit pas être "pinguée".
--
state = {}


--  Messages de contrôle
--
STX="[STX]"		--  Start of text (début de session "telnet")
ETX="[ETX]"		--  End of text (fin de session "telnet")
ENQ="[ENQ]"		--  Enquiry (PING)
ACK="[ACK]"		--  Acknowledge (PING, OK...)
NAK="[NAK]"		--  Negative acknowledge
--
--
--  Autre possibilité pour les messages de contrôle: utiliser les caractères
--  ASCII inférieurs à 32 qui ne peuvent pas apparaître dans le code d'un
--  programme Lua.
--
--    STX="\02"		--  Start of text (début de session "telnet")
--    ETX="\03"		--  End of text (fin de session "telnet")
--    ENQ="\05"		--  Enquiry (PING)
--    ACK="\06"		--  Acknowledge (PING, OK...)
--    NAK="\21"		--  Negative acknowledge


--  Apparemment jamais utilisée
--
-- node.setonerror (
--    function(s)
--       U("\n\nERROR: "..s.."\n\n")
--       node.restart()
--    end
-- )


function U(s)		--  Emet s sur la liaison série (sans CRLF)
   uart.write(0,s)
end


function sanitize(s)
   local result = {}
   for i=1, #s do
      local char = s:sub(i, i)
      local code = char:byte()
      if code <= 31 or code > 127 then
	 table.insert(result, string.format("<%02X>", code))
      else
	 table.insert(result, char)
      end
   end
   return table.concat(result)
end


--  Crée un réseau Wi-Fi ouvert "TECHNET"
--
function onWiFiConnect(T)
   print(("[%s REJOINT TECHNET]"):format(T.MAC))
end

function onWiFiDisconnect(T)
   print(("[%s QUITTE TECHNET]"):format(T.MAC))
end

wem = wifi.eventmon
wem.register( wem.AP_STACONNECTED, onWiFiConnect )
wem.register( wem.AP_STADISCONNECTED, onWiFiDisconnect )
wifi.setmode( wifi.SOFTAP, false )
-- wifi.setphymode( wifi.PHYMODE_G )
-- wifi.setmaxtxpower(34)
-- wifi.setcountry({country="FR", start_ch=1, end_ch=14, policy=wifi.COUNTRY_AUTO})
wifi.ap.config({ ssid="TECHNET", auth=wifi.OPEN, save=false })


--  Messages du port série
--
function srlmsg ( data )
   -- U(string.format('SERIAL:%d: "%s"\r\n',#data,sanitize(data)))
   local N = data:match("^%-%-(%d) ")
   if N == nil then
      node.input(data)			-- Message normal, envoi à Lua.
   else
      --
      --  Message au format "--N .*" destiné à la station N
      --
      local ip = "192.168.4."..N
      local msg = data:sub(5)

      if (state[ip] or 0) == 1 then	-- La station est active
	 if msg == "--STX\r\n" then
	    state[ip] = 2
	    socket:send(1,ip,msg)	-- Demande le passge en telnet
	    -- U("STX demande\r\n")
	 else
	    -- U(string.format('SERIAL:%d:"%s"\r\n',#data,sanitize(data)))
	    -- U(string.format("--%d ERROR: TRY [STX] FIRST (%d)\r\n",N,state[ip]))
	    node.input("\n")
	 end
	 return
      end

      if (state[ip] or 0) == 3 then	-- Station en mode telnet
	 if msg == "--ETX\r\n" then
	    -- U("ETX demande") node.input('\n')
	    state[ip] = 4
	    -- socket:send(1,ip,ETX)	-- Demande la sortie de telnet
	    socket:send(1,ip,msg)	-- Demande la sortie de telnet
	 else
	    socket:send(1,ip,msg)
	 end
	 return
      end

      if (state[ip] or 0) < 1 then
	 -- U(string.format("--%d ERROR: UNREACHABLE\r\n",N))
	 node.input("\n")
      end
   end
end


--  Messages de la socket
--
function sckmsg ( s, data, port, ip )

   --  Station en état "disponible"
   --    Enregistre l'ACK ou affiche le message
   --
   if (state[ip] or 0) <= 1 then
      if data == ACK then
	 pings[ip]=0
	 state[ip]=1
	 return
      else
	 U(data)
      end
   end

   local N=ip:match("%d+%.%d+%.%d+%.(%d+)")

   --  Station en état "telnet établi"
   --    Transfère le message au client
   --
   if state[ip] == 3 then
      U("--") U(N) U(" ") U(data)
      return
   end

   --  Station en état "telnet demandé"
   --
   if state[ip] == 2 then
      if data == "--STX\r\n" then
	 -- U("STX RECU\r\n")
	 state[ip]=3		-- connexion "telnet" établie
	 U("--") U(N) U(" ") U(data) node.input('\n')
      elseif data ~= ACK then
	 --  Pas d'erreur si on reçoit un ACK (qui répond à un ENQ pendant)
	 U(string.format('ERREUR: %s: %s attendu, %s reçu\r\n',ip,STX,data))
      end
      return
   end

   --  Station en état "fin de telnet demandé"
   --
   if state[ip] == 4 then
      if data == "--ETX\r\n" then
	 state[ip]=1		 -- Fin de telnet confirmée
	 U("--") U(N) U(" ") U(data) node.input("\n")
      else
	 U(string.format('ERREUR: %s: %s attendu, %s reçu\r\n',ip,ETX,data))
      end
      return
   end

   --  Message inattendu
   --
   U(string.format('[ERREUR:%s:%d:"%s" inattendu (%d)]\r\n',ip,#data,sanitize(data),state[ip]))

end


--  Raffraîchit l'affichage. Ne retrace que ce qui a changé.
--
function updateDisplay()

   --  Animation "-"		TODO: optimisable
   --    area: 48;20 95;20
   --
   local x = (ticks % 16)*3
   display:setDrawColor(0)
   display:drawHLine( 48, 20, 48 )		-- efface
   display:setDrawColor(1)
   display:drawHLine( 48+x, 20, 3, 20 )		-- trace
   display:updateDisplayArea( 6, 2, 6, 1 );	-- 8px units!

   display:setFont(u8g2.font_6x10_tf)

   --  Uptime, si changé
   --
   local t = tmr.time()
   if t ~= t0 then
      display:drawStr( 0, 16, string.format("T=%05d", t ))
      display:updateDisplayArea( 0, 2, 6, 1 );	-- 8px units!
      t0 = t
   end

   --  Heap, si changé
   --
   local h = math.floor(node.heap()/1000)
   if h ~= h0 then
      display:drawStr( 104, 16, string.format("H=%02d", h))
      display:updateDisplayArea( 13, 2, 3, 1 );	-- 8px units!
      h0 = h
   end

   --  État des stations (tous les 500ms)
   --    area: 92;0 128;12
   --
   if ticks%5 == 0 then
      local x = 92
      display:setDrawColor(0)
      display:drawBox( x, 0, 36, 12 )		-- efface
      display:setDrawColor(1)
      display:setFont(u8g2.font_9x18B_tf)	-- base line at 11
      for i=2,5 do
	 local ip = "192.168.4."..i
	 local s = state[ip] or 0
	 if s == 0 then
	    display:drawHLine( x+2, 7, 5 )	-- tiret
	 elseif s == 1 then
	    display:drawStr( x, 0, i )		-- n° de station
	 elseif s > 1 then
	    display:drawStr( x, 0, "X" )	-- X
	 end
	 x = x + 9
      end
      display:updateDisplayArea( 11, 0, 5, 2 );	-- 8px units!
   end
end


--  Surveille le fonctionnement des stations par des messages 'ENQ'. N'interroge
--  que les stations en state 0 ou 1.
--
--  Si une station ne répond toujours pas après 5 messages, elle est déconnectée
--  de force du réseau Wi-Fi.
--
--  NOTE: il semble qu'un intervalle de 500 ms soit trop court.
--
function ping ( )
   -- print("PING")

   for mac,ip in pairs(wifi.ap.getclient()) do
      -- U(string.format("%s\r\n",ip))

      if (state[ip] or 0) >= 2 then
	 pings[ip] = 0	-- station en telnet, raz le nombre de pings
      else
	 local n = pings[ip] or 0
	 -- U(string.format("ENQ%d %s\r\n",n,ip))
	 if n < 5 then
	    --
	    --  Ping la station
	    --
	    socket:send( 1, ip, ENQ )
	    pings[ip] = n + 1
	 else
	    --
	    --  Déconnecte la station qui ne répond plus
	    --
	    print(string.format("%s NE REPOND PAS (%d ENQ)", ip, n))
	    wifi.ap.deauth(mac)
	    pings[ip] = nil
	    state[ip] = nil
	 end
      end
   end
end


--  Ouvre une socket UDP sur le port 1 à l'écoute des stations.
--
--  Si les stations ne font que répondre aux messages de la passerelle, la même
--  socket peut être utilisée pour communiquer avec toutes les stations.
--  Sinon il vaut peut-être mieux créer une socket par station.
--
socket = net.createUDPSocket()
socket:on("receive", sckmsg )
socket:listen(1)


--  Initialise l'écran: sda=5 scl=6 sla=0x3C
--
i2c.setup(0, 5, 6, i2c.FAST)
display = u8g2.ssd1306_i2c_128x64_noname(0, 0x3C)
display:setFontRefHeightExtendedText()
display:setDrawColor(1)
display:setFontPosTop()
display:setFontDirection(0)
display:clearBuffer()
display:setFont(u8g2.font_9x18B_tf)
display:drawStr( 0, 0, "TECHNET-X")
display:sendBuffer()


--  Tâches répétées
--
function ontick ( )
   ticks = ticks + 1
   updateDisplay()
   if ticks%5 == 0 then
      ping()
      collectgarbage()
   end
   ticker:start()
end

ticker = tmr.create()
ticker:register( 100, tmr.ALARM_SEMI, ontick )
ticker:start()


--  Dirige les messages provenant du port série vers la fonction de traitement
--   * attend une ligne complète
--   * n'envoie pas de copie à Lua, sinon interprétation en double !
--  	
--  NOTE: en dernier pour ne pas perturber :inject
--
uart.on( "data",'\n', srlmsg, 0 )
