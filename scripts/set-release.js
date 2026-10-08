// Uso: npm run release -- todoroki
// Copia releases/<nombre>.json a src/release.json
const fs = require('fs');
const path = require('path');

const name = process.argv[2];
const releasesDir = path.join(__dirname, '..', 'releases');
const available = fs.readdirSync(releasesDir).map((f) => f.replace('.json', ''));

if (!name || !available.includes(name)) {
  console.error(`Indica una versión: ${available.join(', ')}`);
  process.exit(1);
}

fs.copyFileSync(path.join(releasesDir, `${name}.json`), path.join(__dirname, '..', 'src', 'release.json'));
const release = require(path.join(releasesDir, `${name}.json`));
console.log(`Release lista: ${release.hero} v${release.version}`);
