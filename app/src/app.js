const express = require('express');
const crypto = require('crypto');
 
const app = express();
app.use(express.json());
 
// Simple JSON request logging. CloudWatch will collect stdout/stderr.
app.use((req, res, next) => {
  const started = Date.now();
  res.on('finish', () => {
    console.log(JSON.stringify({
      timestamp: new Date().toISOString(),
      method: req.method,
      path: req.path,
      status: res.statusCode,
      duration_ms: Date.now() - started
    }));
  });
  next();
});
 
app.get('/', (req, res) => {
  res.json({
    message: 'ECS/Fargate portfolio API is running',
    service: 'ecs-portfolio-api'
  });
});
 
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    service: 'ecs-portfolio-api',
    version: process.env.APP_VERSION || 'local'
  });
});
 
app.get('/api/info', (req, res) => {
  res.json({
    service: 'ecs-portfolio-api',
    version: process.env.APP_VERSION || 'local',
    environment: process.env.NODE_ENV || 'development',
    platform: process.env.AWS_EXECUTION_ENV || 'local'
  });
});
 
// DEMO ONLY: deliberately CPU-heavy endpoint used to trigger ECS Auto Scaling.
// iterations is capped to prevent an accidental unlimited loop.
app.get('/work', (req, res) => {
  const requested = Number.parseInt(req.query.iterations || '10000', 10);
  const iterations = Math.min(Math.max(requested, 1000), 100000);
 
  let value = 'ecs-fargate-portfolio';
  for (let i = 0; i < iterations; i += 1) {
    value = crypto.createHash('sha256').update(`${value}:${i}`).digest('hex');
  }
 
  res.json({
    ok: true,
    iterations,
    sample: value.slice(0, 16)
  });
});
 
module.exports = app;
