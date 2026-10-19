import { build } from 'esbuild';
import { copyFileSync } from 'node:fs';
await build({entryPoints:[new URL('./entry.js',import.meta.url).pathname],bundle:true,format:'iife',globalName:'HanDates',platform:'neutral',target:'es2022',minify:true,legalComments:'inline',outfile:new URL('../../Sources/HanSearchCore/Resources/NaturalDates.js',import.meta.url).pathname});
copyFileSync(new URL('./node_modules/chrono-node/LICENSE.txt',import.meta.url),new URL('../../Sources/HanSearchCore/Resources/Chrono-LICENSE.txt',import.meta.url));
