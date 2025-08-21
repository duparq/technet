
TechNet : réseau Wi-Fi de modules NodeMCU / Esp8266
===================================================

Un module "AP" (access point) crée un réseau Wi-Fi ouvert "TECHNET". Les modules
"STATION" clients se connectent à ce réseau.

L'application 'technet' permet :

 * d'ouvrir une console avec un module connecté à un port série
 * de programmer un module connecté à un port série
 * de fournir une passerelle entre les PC du réseau local et les stations TECHNET
 * de programmer une station à distance

Exemples :

    ./technet
    ./technet X
    ./technet reset
    ./technet inject lua/screen1.lua
    ./technet inject 2 lua/screen1.lua


Documentation

  Lua : 
  NodeMCU : https://nodemcu.readthedocs.io


Configuration du firmware NodeMCU  https://nodemcu.readthedocs.io
=================================

Le code source du firmware est disponible sur https://github.com/nodemcu/nodemcu-firmware .

Télécharger la dernière release (3.0.0-release_20240225):

  git clone --recurse-submodules --depth 1 https://github.com/nodemcu/nodemcu-firmware.git


Éditer les fichiers

 * nodemcu-firmware/app/include/user_config.h :

#define BIT_RATE_DEFAULT BIT_RATE_460800

 * nodemcu-firmware/app/include/user_modules.h :

        `#define LUA_USE_MODULES_GPIO_PULSE
		//#define LUA_USE_MODULES_MQTT
		#define LUA_USE_MODULES_PWM
		#define LUA_USE_MODULES_PWM2

		#define LUA_USE_MODULES_COLOR_UTILS
		#define LUA_USE_MODULES_PIXBUF
		#define LUA_USE_MODULES_WS2812
		#define LUA_USE_MODULES_WS2812_EFFECTS
`

 * nodemcu-firmware/app/include/u8g2_fonts.h

`    #define U8G2_FONT_TABLE \
		U8G2_FONT_TABLE_ENTRY(font_6x10_tf) \
		U8G2_FONT_TABLE_ENTRY(font_9x18_tf) \
		U8G2_FONT_TABLE_ENTRY(font_9x18B_tf) \
		U8G2_FONT_TABLE_ENTRY(font_unifont_t_symbols) \
`

  make -j 8 LUA=53 USER_PROLOG="TECHNET" clean all	(~44s)

  (téléchargera également le SDK Espressif la première fois)


Installation du firmware
========================

Le firmware doit être installé sur tous les modules.

Raccorder un module au PC puis depuis le répertoire nodemcu-firmware:

  esptool write_flash -fm dio 0x00000 bin/0x00000.bin	(~5s)
  esptool write_flash -fm dio 0x10000 bin/0x10000.bin	(~33s)

Une fois le firware installé, l'application technet peut communiquer avec le module :

  technet


Installation du point d'accès TECHNET
=====================================

Raccorder un module.

./technet inject sta.lua

L'écran du point d'accès TECHNET s'allume et affiche "TECHNET-X ----".


Installation d'une station
==========================

Raccorder un module.

./technet inject sta.lua
./technet inject display.lua
./technet inject screen2.lua

L'écran de la station devrait afficher une horloge. La station se connecte à la
passerelle, qui affiche alors "TECHNET-X 2---", le "2" signifiant que la station
n° 2 est disponible.


Installation rémanente
======================

'technet inject' transmet le code d'un programme qui sera chargé et exécuté en
RAM. Par conséquent, ce programme disparait à l'extinction du module.

NodeMCU fournit un système de fichier en mémoire Flash qui permet de stocker des
programmes. Au démarrage, le module charge automatiquement le programme
'init.lua' s'il existe.

Installer le programme du point d'accès :

nodemcu-tool -p /dev/ttyUSB1 -b 460800 upload lua/ap.lua
nodemcu-tool -p /dev/ttyUSB1 -b 460800 upload lua/init.lua

Installer le programme d'une station :

nodemcu-tool -p /dev/ttyUSB1 -b 460800 upload lua/sta.lua
nodemcu-tool -p /dev/ttyUSB1 -b 460800 upload lua/init.lua


ATTENTION: technet désactive l'écho sur la liaison série, ce qui empêche
nodemcu-tool d'accéder au module.


Installation à distance
=======================

Une fois le programme sta.lua installé sur un module, il est possible de le
programmer à distance depuis n'import quelle station du réseau local.

Raccorder le point d'accès à un PC et lancer 'technet X' pour démarrer le
serveur passerelle.

Alimenter la station.

Vérifier que la station s'est bien connectée au réseau TECHNET.

Sur un PC du réseau local :

	./technet inject 2 display.lua
	./technet inject 2 screen2.lua

La station affiche une horloge si les deux fichiers ont été transmis correctement.


Gérer les fichiers depuis un module
===================================

Le module 'file' de NodeMCU permet de manipuler des fichiers:

	> file.rename("init.lua","init-0.lua")

	> dofile("sta.lua") permet de charger un fichier pour l'exécuter


Compiler un fichier lua
=======================

	$ nodemcu-firmware/luac.cross -o sta.lc lua/sta.lua
	$ nodemcu-tool -p /dev/ttyUSB1 -b 460800 upload sta.lc

	> dofile("sta.lc")

	> node.LFS.reload("lfs.img")


Exemples
========

https://github.com/nodemcu/nodemcu-firmware/tree/dev/lua_examples
