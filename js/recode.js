
//  Remplace les caractères non imprimables d'une chaîne par leur code en hexdécimal.
//
export function recode ( s )
{
  if ( typeof(s) === "string" )
    return s.split('').map( c => {
      const d = c.charCodeAt(0);
      if ( d < 32 || d > 127 )
	return `<${d.toString(16).padStart(2,'0').toUpperCase()}>` ;
      return c ;
    }).join('');
  else
    return(`type:${typeof(s)}`);
}
