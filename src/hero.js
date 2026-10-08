// Reglas de negocio del héroe.
// Deku no puede pasar del 100% sin romperse los brazos:
// powerLevel siempre debe quedar entre 0 y 100.
function powerLevel(percent) {
  return Math.max(0, Math.min(100, percent));
}

const SEMVER = /^\d+\.\d+\.\d+$/;

function isValidRelease(release) {
  return Boolean(
    release &&
      typeof release.hero === 'string' && release.hero.trim() !== '' &&
      typeof release.version === 'string' && SEMVER.test(release.version) &&
      typeof release.power === 'number'
  );
}

module.exports = { powerLevel, isValidRelease };
