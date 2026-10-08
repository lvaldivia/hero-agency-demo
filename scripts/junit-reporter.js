// Reporter JUnit para Azure Pipelines (pestaña Tests).
// El reporter junit de Node deja los <testcase> sueltos dentro de <testsuites> cuando los
// tests no están en un describe(), y PublishTestResults los ignora. Aquí se envuelven en un <testsuite>.
const { junit } = require('node:test/reporters');

module.exports = async function* junitAzure(source) {
  let xml = '';
  for await (const chunk of junit(source)) xml += chunk;
  yield xml
    .replace('<testsuites>', '<testsuites>\n<testsuite name="Examen de Licencia">')
    .replace('</testsuites>', '</testsuite>\n</testsuites>');
};
