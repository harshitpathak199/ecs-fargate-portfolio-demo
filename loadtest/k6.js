import http from 'k6/http';
import { check, sleep } from 'k6';
 
export const options = {
  stages: [
    { duration: '1m', target: 10 },
    { duration: '3m', target: 25 },
    { duration: '1m', target: 0 }
  ],
  thresholds: {
    http_req_failed: ['rate<0.10']
  }
};
 
export default function () {
  const baseUrl = __ENV.BASE_URL;
  const response = http.get(`${baseUrl}/work?iterations=10000`, {
    timeout: '30s'
  });
 
  check(response, {
    'HTTP 200': (r) => r.status === 200
  });
 
  sleep(0.1);
}
