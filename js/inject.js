
import net from 'node:net' ;
import { recode } from './recode.js';


//  Envoie des lignes de code à une station connectée par Wi-Fi à la passerelle
//  TECHNET
//
export function inject ( host, port, n, lines )
{
  const MTU = 132 ;	//  Taille maximale de chaîne transmise
  // const client = new net.Socket({family: 'IPv4'});
  const client = new net.Socket();
  let step = 0 ;
  let data0 = ""	//  Ce qui n'a pas pu être traité (messages incomplet)


  //  Rassemble les lignes de code pour former des paquets d'environ 1400
  //  octets, taille proche du MTU.
  //
  const trims = [];
  let current = '';
  for (const line of lines) {
    const l = line.trim();
    if ( l.length==0 || l.startsWith("--") )
      continue;
    const potential = current ? `${current} ${l}` : l ;
    if (potential.length < MTU )
      current = potential;
    else {
      trims.push(current);
      current = l;
    }
  }
  if (current)
    trims.push(current);

  //  Envoie la ligne suivante au serveur.
  //
  function sendLine ( ) {
    if ( trims.length > 0 ) {
      const line = trims.shift();
      console.log(`| ${line}`);
      client.write(`${line}\r\n`);
    }
    else {
      console.log("Injection terminée.");
      client.end()
    }
  }

  client.connect( port, host );

  client.setTimeout( 5000, ()=>{ console.log("Timeout"); client.end(); } );

  //  Traitement des messages reçus du serveur.
  //
  //  Les messages peuvent être fractionnés quand la station est chargée, par
  //  exemple avec un affichage à l'écran.
  //
  client.on('data', (data) => {

    //  Ajoute les nouvelles données à ce qui n'a pas été traité
    //  précédemment. Cela permet de fonctionner avec des messages fractionnés.
    //
    data = data0 + data.toString().trim();
    // console.log(`DATA:${data.length}:"${recode(data)}"`);

    //  La passerelle Technet envoie un message de bienvenue,
    //  on lui envoie la demande de connexion à la station.
    //
    if ( step == 0 ) {
      if ( data == "TECHNET" ) {
	step = 1
	console.log(`Connecté au serveur ${host}:${port}`);
	client.write(`CONNECT ${n.toString()}\r\n`);
      }
      else
      	client.end(); 

      return ;
    }

    if ( step == 1 && data === '--STX' ) {
      data0="";
      step = 2 ;
      sendLine();
      return ;
    }

    if ( step == 2 && (data===">" || data === ">>") ) {
      data0="";
      sendLine();
      return ;
    }

    data0=data;
  });

  client.on('close', () => {
    console.log('Connexion fermée.');
    process.exit(0);
  });

  client.on('error', (err) => {
    console.error('Erreur de connexion:', err.message);
  });
}
