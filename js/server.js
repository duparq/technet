
//  Crée le serveur TCP réalisant la passerelle entre un PC client du LAN et le
//  point d'accès NodeMCU
//
//  Crée également un émetteur UDP qui diffuse l'adresse et le port d'écoute du
//  serveur afin que les clients puissent se connecter sans configuration
//  manuelle.
//
//       TCP             SERIAL         UDP
//  PC ------> Technet ----------> AP ------> STA
//  PC <------ Technet <---------- AP <------ STA
//
//    NOTE: il n'est pas possible de créer une socket UDP4 qui écoute/diffuse
//    sur tous les ports simultanément. Par conséquent, le serveur et les
//    clients doivent convenir d'un port. Si ce port est occupé, il faut le
//    changer dans le fichier de configuration.
//
//  TODO: voir les protocoles Zeroconf SSDP, UPnP.


import dgram from 'dgram';
import net from 'node:net' ;
import os from 'node:os' ;


const UDP_PORT = 39000;
const BROADCAST_INTERVAL = 1000;


let tcpServer;
let currentTcpPort;
let udpSocket;
let broadcastInterval;


// function cleanup() {
//   console.log('CLEANUP');
//   if (broadcastInterval) clearInterval(broadcastInterval);
//   if (udpSocket) udpSocket.close();
//   if (tcpServer) tcpServer.close();

//   process.exit(1);
// }

// process.on('SIGINT', cleanup);
// process.on('SIGTERM', cleanup);


function getLocalIp()
{
  const interfaces = os.networkInterfaces();
  for (const iface of Object.values(interfaces)) {
    for (const alias of iface) {
      if (alias.family === 'IPv4' && !alias.internal) {
        return alias.address;
      }
    }
  }
  return '0.0.0.0';
}


//   Diffuse les paramètres de connexion au serveur
//
function startUdpBroadcast()
{
  const localIp = getLocalIp();

  broadcastInterval = setInterval(() => {
    const message = JSON.stringify({
      domain: "TECHNET",
      ap: localIp,
      port: currentTcpPort,
      t: Date.now()
    });

    //  sudo tcpdump -i any -s0 'udp and ip broadcast' -X
    //  sudo tcpdump -i any -s0 'udp and ip broadcast' -t -A
    // console.log(`BROADCAST: ${message}`);

    udpSocket.send( message, UDP_PORT, '255.255.255.255', (err) => {
      if (err) console.error(`Erreur lors du broadcast: ${err}`);
    });
  }, BROADCAST_INTERVAL) ;
}


function createUDPSocket ( )
{
  return new Promise((resolve, reject) => {

    udpSocket = dgram.createSocket('udp4');

    udpSocket.on('error', e=>{
      udpSocket.close();
      reject(new Error(`Impossible de créer la socket UDP: ${e.message}`));
    });

    udpSocket.on('listening', () => {
      udpSocket.setBroadcast(true);
      resolve(udpSocket);
    });

    // udpSocket.bind(UDP_PORT);
    udpSocket.bind(0);
  });
}


export async function startTcpServer() {

  //  Crée la socket UDP qui diffusera l'adresse du serveur aux clients
  //
  try {
    udpSocket = await createUDPSocket();
  }
  catch ( e ) {
    console.error(e.message);
    process.exit(1);
  }
  
  let port = UDP_PORT+1;

  tcpServer = await createTcpServer(port);
  currentTcpPort = port;
  startUdpBroadcast();
  return tcpServer ;

  // let retries = 0;
  // const maxRetries = 10;

  // while (retries < maxRetries) {
  //   try {
  //     tcpServer = await createTcpServer(port);
  //     currentTcpPort = port;
  //     startUdpBroadcast();
  //     return tcpServer ;
  //   } catch (err) {
  //     if (err.code === 'EADDRINUSE') {
  //       // port = Math.floor(Math.random() * (MAX_PORT - MIN_PORT + 1)) + MIN_PORT;
  // 	port++ ;
  //       retries++;
  //       // await new Promise(resolve => setTimeout(resolve, PORT_RETRY_DELAY));
  //     } else {
  //       throw err;
  //     }
  //   }
  // }

  // throw new Error(`Impossible de trouver un port disponible après ${maxRetries} tentatives`);
}


//  Crée le serveur TCP
//
function createTcpServer(port)
{
  return new Promise((resolve, reject) => {

    const server = net.createServer();

    server.on('error', (err) => {
      if (err.code === 'EADDRINUSE') {
        reject(new Error(`Impossible de créer le serveur: le port ${port} est occupé.`));
      } else {
        console.error(`Erreur serveur TCP: ${err}`);
        reject(err);
      }
    });

    // server.on('error', e=>{ reject(e) });
    server.on('error', reject);

    server.listen({ host: '0.0.0.0',
		    port: port },
		  ()=>
		  {
		    console.log(`Serveur à l'écoute sur localhost:${port}.`);
		    resolve(server);
		  });
  });
}


//  Écoute le LAN pour découvrir l'adresse et le port de la passerelle Technet.
//  FIXME: ajouter un timeout.
//
//  Retourne { host: IP, port: N }
//
export function findAP ( )
{
  return new Promise((resolve, reject) => {

    setTimeout( ()=>{ reject(new Error("timeout")) }, 5000 );

    const socket = dgram.createSocket('udp4');

    socket.on('listening', () => {
      socket.setBroadcast(true);
      console.log('Recherche du serveur...');
    });

    socket.on('message', (msg, rinfo) => {

      // console.log(`BROADCAST: ${msg}`);

      let data ;
      try {
	data = JSON.parse(msg);
      } catch (e) {
	return ;
      }

      if ( data.domain && data.domain === "TECHNET" && data.ap && data.port ) {
	socket.close();
	resolve({ host: data.ap, port: data.port });
      }
    });

    socket.bind(UDP_PORT);
  });
}
