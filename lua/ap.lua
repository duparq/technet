
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
--      * Si la station est connectée à un client, state=3, le message est
--        envoyé sur le port série avec le préfixe "--N ".
--
--      * Si la station n'est connectée à un client, state=1, le message est
--        envoyé sur le port série (sauf si c'est un ACK puisque c'est la
--        réponse à un ENQ).
--
--      * Si la station est dans un autre état, un message d'information est
--        envoyé sur le port série.
--


--  TODO:
--   *  supprimer le codage en dur "192.168.4"


--  Autre possibilité pour les messages de contrôle: utiliser les caractères
--  ASCII inférieurs à 32 qui ne peuvent pas apparaître dans le code d'un
--  programme Lua.
--
--    STX="\02"		--  Start of text (début de session "telnet")
--    ETX="\03"		--  End of text (fin de session "telnet")
--    ENQ="\05"		--  Enquiry (PING)
--    ACK="\06"		--  Acknowledge (PING, OK...)
--    NAK="\21"		--  Negative acknowledge


--  Messages de contrôle
--
STX="[STX]"		--  Start of text (début de session "telnet")
ETX="[ETX]"		--  End of text (fin de session "telnet")
ENQ="[ENQ]"		--  Enquiry (PING)
ACK="[ACK]"		--  Acknowledge (PING, OK...)
NAK="[NAK]"		--  Negative acknowledge


function U(s)		--  Emet s sur la liaison série
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

node.setcpufreq(node.CPU160MHZ)

--  Apparemment jamais utilisée
--
-- node.setonerror (
--    function(s)
--       U("\n\nERROR: "..s.."\n\n")
--       node.restart()
--    end
-- )


--  Table des stations ayant émis au moins un message
--    Clé: adresse IP
--    Valeur: âge du dernier message, en nombre de pings.
--
pings = {}

X = ""	-- IP de la station connectée ("telnet")

--  États des stations (par leur IP, par exemple: 'state["192.168.4.2"]' ):
--
--   * nil:
--   * 0:
--   * 1: disponible (répond aux pings)
--   * 2: STX envoyé (demande ouverture telnet)
--   * 3: STX reçu (telnet établi)
--   * 4: ETX envoyé (demande de fin de telnet)
--
--  Une station dont le state est > 1 ne doit pas être "pinguée".
--
state = {}


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


function updateDisplay()
   display:clearBuffer()
   display:setFont(u8g2.font_9x18B_tf)

   local function stattos ( N )
      local ip = "192.168.4."..N
      local s = state[ip] or 0
      if s == 0 then
	 s = "-"
      elseif s == 1 then
	 s = N
      elseif s > 1 then
	 s = "X"
      end
      return s
   end

   display:drawStr( 0, 0, string.format("TECHNET-X %s%s%s%s",stattos(2),stattos(3),stattos(4),stattos(5) ))

   local t = tmr.time()
   local s = t % 60
   local m = math.floor(t/60) % 60
   local h = math.floor(t/3600)
   display:setFont(u8g2.font_6x10_tf)
   display:drawStr( 0, 16, string.format("Up %d:%02d:%02d heap:%5d", h, m, s, node.heap()))
   display:updateDisplayArea( 0, 0, 16, 4 );
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

      -- if ip ~= X then -- ne dérange la station en session "telnet"
      if (state[ip] or 0) < 2 then
	 local n = pings[ip] or 0
	 -- U(string.format("ENQ%d %s\r\n",n,ip))
	 if n < 5 then
	    --
	    --  Ajoute 1 au compte de pings une fois le datagramme envoyé
	    --
	    -- socket:send( 1, ip, ENQ, function() pings[ip] = n + 1 end )
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


--  Tâches répétées
--
-- ncalls = 0
timer = tmr.create()

function ontimer ( )
   -- ncalls = ncalls + 1
   -- if ncalls == 2 then updateDisplay() end
   -- if ncalls == 4 then
   updateDisplay()
   ping()
   --    ncalls = 0
   -- end
   -- collectgarbage("setstepmul", 250)
   collectgarbage()
   timer:start()
end

timer:register( 500, tmr.ALARM_SEMI, ontimer )
timer:start()

--  En dernier pour ne pas perturber :inject
--
--  Dirige les messages provenant du port série vers la fonction de traitement
--   * attend une ligne complète
--   * n'envoie pas de copie à Lua, sinon interprétation en double !
--  	
uart.on( "data",'\n', srlmsg, 0 )
