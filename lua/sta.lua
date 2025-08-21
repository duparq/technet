
--  STATION TECHNNET
--
--  Se connecte au réseau Wi-Fi ouvert "TECHNET".
--  Ouvre une socket UDP à l'écoute des messages de la passerelle sur le
--  port 1.
--
--  Destination des messages arrivant de la socket:
--
--   * la station répond aux messages de contrôle ENQ par un ACK. Cela permet
--     à la passerelle de déterminer l'état des stations TECHNET. Lorsque la station 
--
--   * si la station est en mode "telnet", X==true:
--
--      * le message de contrôle ETX sort la station du mode "telnet":
--
--         * la fonction de redirection de la sortie de l'interpréteur est
--           déposée (sortie normale vers le port série)
--
--         * la station répond à son tour avec un ETX
--
--      * les messages normaux sont transmis à l'interpréteur Lua.
--
--   * sinon, X==false:
--
--      * le message de contrôle STX bascule la station en mode "telnet":
--
--         * la sortie de l'interpréteur Lua est redirigée vers une fonction qui
--           envoie les messages à la passerelle via la socket UDP sur le port
--           1.
--
--         * la station répond à son tour avec un STX
--
--         * l'entrée du port série n'est pas redirigée pour permettre la
--           reprise de contrôle manuel en cas de besoin
--
--      * aucun autre message ne devrait arriver.
--
--  Destination des messages arrivant du port série:
--
--   * l'interpréteur Lua reçoit automatiquement les messages. Si la station est
--     en mode "telnet", X==true, ceux-ci peuvent interférer avec les messages
--     du client connecté, d'autant plus que la sortie de Lua est redirigée vers
--     le client, mais cela permet une prise de contrôle manuelle pour la mise
--     au point.


node.setcpufreq(node.CPU160MHZ)


--  Messages de contrôle
--
-- STX="[STX]"		--  Start of text (début de session "telnet")
-- ETX="[ETX]"		--  End of text (fin de session "telnet")
ENQ="[ENQ]"		--  Enquiry (PING)
ACK="[ACK]"		--  Acknowledge (PING, OK...)
NAK="[NAK]"		--  Negative acknowledge


--  Variables globales
--
NAME = "Wi-Fi ?"	--  Nom du module (sera "TECHNET-?" après connexion)
-- station = "?"		--  Numéro de la station: dernier octet de l'adresse IP
GW = ""			--  Adresse IP de la passerelle
X = false		--  'true' quand une session "façon telnet" est ouverte


function U(s)		--  Emet s sur la liaison série
   uart.write(0,s)
end


--  Remplace les caractères de contrôle d'une chaîne par leur code décimal
--
function sanitize(s)
   local result = {}
   for i=1, #s do
      local char = s:sub(i, i)
      local code = char:byte()
      if code <= 31 or code == 127 then
	 table.insert(result, string.format("<%02X>", code))
      else
	 table.insert(result, char)
      end
   end
   return table.concat(result)
end


--  Force la déconnexion
--
function etx ( )
   X = false
   node.output()		-- Dépose la redirection
   U("[ETX]\r\n")
   node.input('\n')		-- Déclenche l'émission d'un prompt local
end


--  Traite les messages (de la passerelle).
--
function msg ( s, data, port, ip )

   -- U("DGRAM\n")

   --  Répond ACK aux messages ENQ (PING)
   --
   if data == ENQ then
      -- U("[ENQ]")
      s:send(port,ip,ACK)
      return
   end

   --  Appelé par Lua pour effectuer une sortie:
   --    lit les données disponibles sur le pipe p et les envoie à la socket.
   --
   --  FIXME: on fait le pari que les messages émis par Lua sont lus en une
   --  seule fois et tiennent dans un seul paquet. Sinon, il faut gérer
   --  l'événement 'sent' de la socket et continuer de vider le pipe (voir
   --  node.telnet.lua). ATTENTION: 'sent' sera alors appelé après chaque
   --  réponse, par exemple à un PING.
   --
   local function output( p )
      local r = p:read(1400)
      if r and #r>0 then s:send(port,ip,r) end
      return false -- don't repost as the on:sent will do this
   end

   if data == "--STX\r\n" then		-- Débute une session "façon Telnet"
      X = true
      node.output(output, 0)		-- Installe une fonction de redirection de la sortie de Lua
      s:send(port,ip,data)		-- Signale le début de session
      U("\n[STX]\n")
      return
   end

   --  Une fois connecté, dirige les messages vers l'entrée standard de Lua.
   --
   --  La redirection de la sortie donnera une réponse à l'émetteur.
   --
   if X == true then
      if data == "--ETX\r\n" then	-- Fin de la session "façon Telnet"
	 X = false
	 node.output()			-- Dépose la redirection
	 s:send(port,ip,data)		-- Confirme la fin de session telnet
	 U("[ETX]\r\n")
	 node.input('\n')		-- Déclenche l'émission d'un prompt local
	 return
      end

      U("| ") U(data)			-- Affiche les messages reçus
      node.input(data)			-- Envoie les messages reçus à Lua

      return
   end

   --  Message inattendu
   --
   U(string.format('[%s:%d:"%s"]',ip,#data,sanitize(data)))
   node.input('\n') -- déclenche l'émission d'un prompt
   s:send(port,ip,NAK)
end


--  Connexion Wi-Fi
--
function onWiFiConnect(T)
   -- print(string.format("CONNECTÉ à '%s' canal %d", T.SSID, T.channel))
   U("CONNECTÉ à '") U(T.SSID) U("' canal ") U(tostring(T.channel)) U("\n")
   NAME = "TECHNET-?"
end

--  Déconnexion Wi-Fi
--
function onWiFiDisconnect(T)
   -- print(string.format("DÉCONNECTÉ (%s)",T.reason))
   U("DÉCONNECTÉ (") U(tostring(T.reason)) U(")\n")
   GW = ""
   NAME = "Wi-Fi ?"
end


--  Le module reçoit son IP.
--  Enregistre l'adresse de la passerelle.
--  Envoie un 'HELLO' à la passerelle pour qu'elle enregistre l'adresse IP de la station.
--
function onIP(T)
   GW = T.gateway
   -- print(string.format("IP=%s GW=%s",T.IP, GW))
   U("IP=") U(T.IP) U(" GW=") U(GW) U("\n")
   NAME = string.format("TECHNET-%s",string.match(T.IP,'%d+$'))
end

wem = wifi.eventmon
wem.register( wem.STA_CONNECTED, onWiFiConnect )
wem.register( wem.STA_DISCONNECTED, onWiFiDisconnect )
wem.register( wem.STA_GOT_IP, onIP )

wifi.setmode( wifi.STATION, false ) -- ne sauve pas le mode en Flash
-- wifi.setphymode( wifi.PHYMODE_G )
-- wifi.setmaxtxpower(34)
-- wifi.setcountry({country="FR", start_ch=1, end_ch=14, policy=wifi.COUNTRY_AUTO})
wifi.sta.config({ ssid="TECHNET", auth=wifi.OPEN, save=false }) -- ne sauve pas la config en Flash

--  Ouvre une socket UDP à l'écoute sur le port 1
--
socket = net.createUDPSocket()
socket:on("receive",msg)
socket:listen(1)


--  Initialise l'écran: sda=5 scl=6 sla=0x3C
--
i2c.setup(0, 5, 6, i2c.FAST)
display = u8g2.ssd1306_i2c_128x64_noname(0, 0x3C)
display:setFontRefHeightExtendedText()
display:setDrawColor(1)
display:setFontPosTop()
display:setFontDirection(0)


--  Tâches répétées : affichage, collectgarbage
--
timer = tmr.create()
function ontimer ( )
   if type(SCREEN) == "function" then SCREEN() end
   collectgarbage()
   timer:start()
end
timer:register( 500, tmr.ALARM_SEMI, ontimer )
timer:start()


--  Affichage par défaut pour une station
--  
SCREEN = function ( )
   display:clearBuffer()
   display:setFont(u8g2.font_9x18B_tf)

   display:drawStr( 0, 0, NAME)

   local t = tmr.time()
   local s = t % 60
   local m = math.floor(t/60) % 60
   local h = math.floor(t/3600)
   display:setFont(u8g2.font_6x10_tf)
   display:drawStr( 0, 16, string.format("Up %d:%02d:%02d heap:%5d", h, m, s, node.heap()))
   display:sendBuffer()
end


--  Affichage
--
--  :inject display.lua
--  :inject screen1.lua
