const app = require('./app');
 
const port = Number.parseInt(process.env.PORT || '3000', 10);
const server = app.listen(port, '0.0.0.0', () => {
  console.log(JSON.stringify({
    event: 'server_started',
    port,
    version: process.env.APP_VERSION || 'local'
  }));
});
 
function shutdown(signal) {
  console.log(JSON.stringify({ event: 'shutdown_started', signal }));
  server.close(() => {
    console.log(JSON.stringify({ event: 'shutdown_complete' }));
    process.exit(0);
  });
 
  setTimeout(() => process.exit(1), 10000).unref();
}
 
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
