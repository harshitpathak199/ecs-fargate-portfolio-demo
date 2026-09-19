
const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const app = require('../src/app');

test('GET /health returns HTTP 200 and healthy status', async () => {

  const server = app.listen(0, '127.0.0.1');

  try {

    // Wait until the server is ready
    await once(server, 'listening');

    // Get the dynamically assigned port
    const address = server.address();

    const response = await fetch(
      `http://127.0.0.1:${address.port}/health`
    );

    const body = await response.json();

    assert.equal(response.status, 200);
    assert.equal(body.status, 'healthy');
    assert.equal(body.service, 'ecs-portfolio-api');

  } finally {

    // Close the test server
    if (server.listening) {
      await new Promise((resolve, reject) => {
        server.close((error) => {
          if (error) reject(error);
          else resolve();
        });
      });
    }

  }

});