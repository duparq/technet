
import fs from 'node:fs' ;
import path from 'node:path' ;
import readline from 'node:readline';

const echobuf = null ;
let hasPrompt = false ;
let rl ;
let socket ;
let LUAERROR = false ;

//  VOIR: nodemcu-tool/lib/transport/serial-terminal.js


//  Envoie une commande à l'interpréteur Lua.
//  Assure que la chaîne transmise se termine par "\r\n".
//
//  Si la commande commence par "* ", elle est affichée à l'écran et le reste
//  est envoyé.
//
function command ( line )
{
  if ( !line.endsWith('\n') )
    line += '\r\n' ;

  if ( line.startsWith('* ') ) {
    process.stdout.write(line);
    line = line.slice(2);
  }

  //    Enregistre la commande dans le tampon d'écho pour pouvoir éviter son affichage en double.
  // if ( echobuf )
  //   echobuf = echobuf + line;

  hasPrompt = false ;
  serialport.write( line, error => { if (error) { console.log("Erreur lors de l'envoi:", error.message); } } );
}


function nextCommand ( )
{
  if ( !hasPrompt || LUAERROR ) {
    // commands = [] ;
    return false ;
  }

  // LUAERROR = false ;

  if ( commands.length > 0 ) {
    command( commands.shift() );
    return true ;
  }

  return false ;
}


export function terminal ( )
{
  const superCommands = {
    ':bootloader': ()=>{
      //
      //  Redémarre le module vers le bootloader.
      //
      serialport.update({ baudRate: 74480 });
      serialport.set({ dtr: false, rts: true });	//  Reset NodeMCU
      serialport.set({ dtr: true, rts: false });	//  Boot bootloader
    },
    ':heap': ()=>{
      //
      //  Affiche la mémoire disponible
      //
      command('print(string.format("%d heap bytes free.", node.heap()))' );
    },
    ':resetmodule': ()=>{
      //
      //  Redémarre le module vers l'interpréteur lua.
      //
      serialport.update({ baudRate: config.baudrate });
      serialport.set({ dtr: false, rts: true });	//  Reset NodeMCU
      serialport.set({ dtr: false, rts: false });	//  Boot normal
      // commands=[ `uart.setup(0,${config.baudrate},8,uart.PARITY_NONE,uart.STOPBITS_1,0)` ];
    },
    ':inject': {
      //
      //  Injecte un fichier ligne à ligne
      //
      'completer': (line)=>{
	//
	//  Fournit un compléteur pour readline: liste des fichiers du répertoire lua/.
	//
	const dir = fs.readdirSync(path.join(import.meta.dirname,"..","lua"))
	      .filter(name => name.endsWith('.lua')||name.endsWith('.lc') );
	const comps = dir.map( name => `:inject ${name}` );
	const hits = comps.filter( c => c.startsWith(line) );
	return [ hits, line ] ;
      },
      'run': (args)=>{
	if ( args.length !== 1 ) {
	  console.error('ERREUR DE SYNTAXE');
	  rl.prompt(true);
	  return ;
	}

	const p = path.join(import.meta.dirname,"..","lua",args[0]);
	let lines ;
	try {
	  lines = fs.readFileSync( p ).toString();
	}
	catch(e) {
	  if ( e.code === 'ENOENT' )
	    console.error(`ERREUR: ${p} n'existe pas.`);
	  else
	    console.error(e);
	  rl.prompt(true);
	  return ;
	}
	commands = lines.split('\n').map( line => line.endsWith('\r') ? line.slice(0,-1) : line );
	commands = commands.filter( line => line.trim() != '' ) // Supprime les lignes blanches
	commands = commands.filter( line => !line.trim().startsWith('--') ) // Supprime les lignes commentaires
	commands = commands.map( line => `* ${line}` );
	nextCommand();
      }
    },

    ':table': (args)=>{
      //
      //  Affiche le contenu d'une table
      //
      if ( args.length !== 1 ) {
	console.error('ERREUR DE SYNTAXE');
	rl.prompt(true);
	return ;
      }
      // for k,v in pairs(_G) do print (k,v) end
      // commands.push(`for k,v in pairs(${args[0]}) do print (k,v) end`);
      // nextCommand();
      command( `for k,v in pairs(${args[0]}) do print (k,v) end` );
      // rl.prompt(true);
    },
    ':echooff': ()=>{
      //
      //  Configure l'UART du module pour ne pas renvoyer les caractères reçus
      //
      command( `uart.setup(0,${config.baudrate},8,uart.PARITY_NONE,uart.STOPBITS_1,0)` );
    },
  };


  //  FIXME
  //
  if (process.stdin.isTTY) {
    // console.log('RAW MODE');
    process.stdin.setRawMode(true);
  }

  //  ReadLine: saisie de commandes ligne par ligne avec historique et
  //  complétion des "supercommandes".
  //
  rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    history: config.history,
    removeHistoryDuplicates: true,

    completer: line=>{
      if ( line.indexOf(' ') == -1 ) {
	const hits = Object.keys(superCommands).sort().filter((c) => c.startsWith(line));
	if ( hits.length == 1 && typeof superCommands[ hits[0] ] == 'object' )
	  return [ [hits[0]+' '], line ]
	return [ hits, line];
      }
      const cmd = line.split(' ')[0] ;
      const scmd = superCommands[ cmd ] ;
      if ( scmd && scmd.completer )
	return scmd.completer( line );
      return [ [], line ];
    }
  });

  //  Lance l'exécution d'une ligne de commande.
  //   * supercommande -> exécution locale
  //   * commande normale -> transmission au NodeMCU
  //
  rl.on('line', line=>{
    if ( line.startsWith(':') ) {
      const words = line.split(' ') ;
      const f = superCommands[ words[0] ];
      if ( typeof f === 'function' )
	f( words.slice(1) );
      else if ( typeof f === 'object' && f.run )
	f.run( words.slice(1) );
      else {
	console.error(`ERREUR: commande inconnue.`);
	rl.prompt(true);
      }
    }
    else {
      LUAERROR = false ;
      command(line);
    }
  });

  //  Ferme la console. Enregistre l'historique.
  //
  rl.on('close', ()=>{
    serialport.close();
    config.history = rl.history ;
    fs.writeFileSync( configpath, JSON.stringify(config,null,2) );
    process.exit(0);
  });

  //  Ctrl+C annule la saisie en cours.
  //
  rl.on('SIGINT', ()=>{
    rl.clearLine( rl.output, 0 );
    rl.prompt(true);	
  });

  //  Données arrivant du port série.
  //
  serialport.on('data', data=>{

    data = data.toString();

    //  Élimine l'écho de la commande envoyée.
    //  TODO: éliminer le risque de téléscopage avec des données reçues juste avant l'écho.
    //
    if ( echobuf ) {
      const l = Math.min( echobuf.length, data.length );
      for ( let i=0 ; i<l ; i++ ) {
	const c1 = recode( data[i] );
	const c2 = recode( echobuf[i] );
	if ( c1 !== c2 ) {
	  // if ( c1 == '<0A>' && c2 == '<0D>' )	// ESP32
	  //   break ;
	  console.error(`\nEXPECTED '${c2}' instead of '${c1}' in echo at position ${i}.`);
	  console.error(`DATA: ${recode(data)}`)
	  console.error(`ECHO: ${recode(echobuf)}`)
	  echobuf = '' ;
	  break ;
	}
      }
      data = data.slice(l);
      echobuf = echobuf.slice(l);
    }


    //  Serveur TCP connecté -> reçoit les données
    //
    //  FIXME: il faudrait gérer la situation proprement entre console et
    //  serveur.
    //
    if ( socket !== undefined ) {
      socket.write( data );
      return ;
    }

    if ( data.startsWith("Lua error:") )
      LUAERROR = true ;

    if ( data.endsWith( '> ' ) ) {
    // if ( data==="> " || data===">> " ) {
      hasPrompt = true ;

      if ( data === 'cannot open init.lua: \r\n> ') {
	//
	//  Le module a redémarré
	//
	LUAERROR = false ;
	commands = [];
	if ( echobuf )
	  console.log("\nNODEMCU a redémarré");
	else {
	  console.log("\nNODEMCU a redémarré, suppression de l'écho:");
	  // commands = [ `uart.setup(0,${config.baudrate},8,uart.PARITY_NONE,uart.STOPBITS_1,0)` ] ;
	  commands.push( `uart.setup(0,${config.baudrate},8,uart.PARITY_NONE,uart.STOPBITS_1,0)\r\n` );
	}
	commands.push( 'print(string.format("\\n%s\\n%d heap bytes free.\\n", _VERSION, node.heap()))\r\n' );
	commands.push( '\r\n' );
      }

      if ( nextCommand() )
	return ;

      //  Remplace le prompt
      //
      // if ( data.endsWith( '>> ' ) ) {
      //   process.stdout.write(data.slice(0,-3));
      //   rl.setPrompt('>> ');
      //   rl.prompt(true);
      //   return ;
      // }
      // process.stdout.write(data.slice(0,-2));
      // rl.setPrompt('$ ');
      // rl.prompt(true);
      // return ;
    }
    else
      hasPrompt = false ;

    process.stdout.write(data);	//  Messages produits par NodeMCU
  });


  //  Reconfigure l'UART du module pour supprimer l'écho.
  //  La commande sera envoyée après la réception du prompt.
  //
  if ( !echobuf ) {
    const echooff = `uart.setup(0,${config.baudrate},8,uart.PARITY_NONE,uart.STOPBITS_1,0)`;
    commands = [ echooff ];
  }


  //  Déclenche l'émission d'un prompt (si tout va bien pour le MCU)
  //
  serialport.write("\r\n");
}
