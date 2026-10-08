const path = require('path');
const express = require('express');
const release = require('./release.json');
const { powerLevel } = require('./hero');

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, '..', 'public')));

// APP_ENV se configura como "slot setting" en App Service:
// el slot staging dice STAGING y producción dice PRODUCCION, aunque se haga swap.
const environment = process.env.APP_ENV || 'local';

// Votos en memoria: suficiente para una charla.
let round = 1;
let votes = { pasa: 0, rompe: 0 };

app.get('/health', (req, res) => {
  res.json({ status: 'ok', message: '¡Ya estoy aquí!', version: release.version });
});

app.get('/api/version', (req, res) => {
  res.json({ ...release, power: powerLevel(release.power), environment });
});

app.get('/api/votes', (req, res) => {
  res.json({ round, ...votes });
});

app.post('/api/vote', (req, res) => {
  const choice = req.body && req.body.choice;
  if (choice !== 'pasa' && choice !== 'rompe') {
    return res.status(400).json({ error: 'El voto debe ser "pasa" o "rompe".' });
  }
  votes[choice] += 1;
  res.json({ round, ...votes });
});

// Reinicia la votación para la siguiente misión.
// Solo funciona si ADMIN_TOKEN está configurado en el App Service.
app.post('/api/votes/reset', (req, res) => {
  const token = process.env.ADMIN_TOKEN;
  if (!token || req.query.token !== token) {
    return res.status(403).json({ error: 'Token inválido.' });
  }
  round += 1;
  votes = { pasa: 0, rompe: 0 };
  res.json({ round, ...votes });
});

const port = process.env.PORT || 3000;
if (require.main === module) {
  app.listen(port, () => {
    console.log(`Hero Agency ${release.version} (${environment}) en http://localhost:${port}`);
  });
}

module.exports = app;
