
import { SerialPort } from 'serialport';


async function test( portPath, baudRate )
{
  return new Promise((resolve) => {
    const port = new SerialPort({ path: portPath, baudRate: baudRate }, (err) => {
      if (err) {
        resolve(null);
      } else {
        resolve(port);
      }
    });
  });
}


//  Retourne le premier port série disponible et raccordé à un NodeMCU. Le port
//  est ouvert.
//
export async function getSerialPort ( baudRate )
{
  const ids = [ "1a86-7523",	//  CH341
		"1a86-55d3",	//  ESP32
		"1a86-55d4"	//  "USB Single Serial" (ESP32 + LCD) 115200 bps
	      ];

  let ports = await SerialPort.list();
  ports = ports.filter( port => ( ids.includes( `${port.vendorId}-${port.productId}`.toLowerCase() ) ) );
  ports = ports.sort( (p1,p2) => p2.path < p1.path ? 1 : -1 );
  
  for (const port of ports) {
    const serialPort = await test(port.path,baudRate);

    if (serialPort) {
      console.log(`Liaison série ${port.path} ${baudRate} bps.`);
      
      serialPort.on('close', ()=>{
	console.error(`Port ${port.path} fermé`);
	process.exit(1);
      }) ;

      serialPort.on('error', e =>{ console.error(`ERREUR PORT SÉRIE: %s`, e); });

      return serialPort;
    }
  }

  throw( new Error('Aucun port série disponible.') );
  process.exit(1);
}
