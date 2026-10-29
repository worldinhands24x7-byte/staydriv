const http = require('http');

const ALB_HOST = 'staydr20260917190326134500000018-1656960596.ap-south-2.elb.amazonaws.com';

function postJson(path, payload) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(payload);
    const req = http.request({
      hostname: ALB_HOST,
      port: 80,
      path: path,
      method: 'POST',
      headers: {
        'User-Agent': 'StayDrivApp/1.0.28',
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(data)
      }
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: JSON.parse(body) });
        } catch (e) {
          resolve({ status: res.statusCode, body });
        }
      });
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

function getFile(path) {
  return new Promise((resolve, reject) => {
    const req = http.request({
      hostname: ALB_HOST,
      port: 80,
      path: path,
      method: 'GET',
      headers: {
        'User-Agent': 'StayDrivApp/1.0.28'
      }
    }, (res) => {
      let chunks = [];
      res.on('data', chunk => chunks.push(chunk));
      res.on('end', () => {
        resolve({
          status: res.statusCode,
          contentType: res.headers['content-type'],
          contentLength: res.headers['content-length'],
          length: Buffer.concat(chunks).length
        });
      });
    });
    req.on('error', reject);
    req.end();
  });
}

async function run() {
  console.log('--- Testing Document Uploads to GridFS ---');
  
  // 1. Test JPG upload
  const sampleJpgBase64 = Buffer.from('Fake JPEG binary content for Aadhaar test 12345').toString('base64');
  const jpgRes = await postJson('/api/upload', {
    uid: 'test_pilot_9876543210',
    fileName: 'aadhaar_front.jpg',
    fileData: sampleJpgBase64,
    documentType: 'aadhaarFront',
    mimeType: 'image/jpeg'
  });
  console.log('JPG Upload Result:', jpgRes);

  if (jpgRes.body && jpgRes.body.fileId) {
    const fetchRes = await getFile('/api/files/' + jpgRes.body.fileId);
    console.log('Fetch JPG File Result:', fetchRes);
  }

  // 2. Test PDF upload
  const samplePdfBase64 = Buffer.from('%PDF-1.4 Fake PDF content for Driving License').toString('base64');
  const pdfRes = await postJson('/api/upload', {
    uid: 'test_pilot_9876543210',
    fileName: 'license.pdf',
    fileData: samplePdfBase64,
    documentType: 'licenseFront',
    mimeType: 'application/pdf'
  });
  console.log('PDF Upload Result:', pdfRes);

  if (pdfRes.body && pdfRes.body.fileId) {
    const fetchRes = await getFile('/api/files/' + pdfRes.body.fileId);
    console.log('Fetch PDF File Result:', fetchRes);
  }

  console.log('--- All Live Upload Tests Completed ---');
}

run().catch(console.error);
