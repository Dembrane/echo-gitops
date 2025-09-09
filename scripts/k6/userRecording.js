// Creator: Grafana k6 Browser Recorder 1.0.8

import { sleep, group } from 'k6'
import http from 'k6/http'

export const options = { vus: 10, duration: '5m' }

export default function main() {
  let response

  group(
    'page_1 - https://portal.dembrane.com/en-US/3cc62e6f-652e-46f8-a6df-e068dcdadf62/start',
    function () {
      response = http.options(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62/conversations/initiate',
        null,
        {
          headers: {
            accept: '*/*',
            'access-control-request-headers': 'baggage,content-type,sentry-trace',
            'access-control-request-method': 'POST',
            origin: 'https://portal.dembrane.com',
            'sec-fetch-mode': 'cors',
          },
        }
      )

      response = http.post(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62/conversations/initiate',
        '{"name":"User Talks","pin":"","tag_id_list":[],"user_agent":"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36","source":"PORTAL_AUDIO"}',
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            'content-type': 'application/json',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=05f2867cfe774d8f8e1cdd16ceaa0239,sentry-sample_rate=0.5,sentry-sampled=false',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': '05f2867cfe774d8f8e1cdd16ceaa0239-a0106e1e14913507-0',
          },
        }
      )
    }
  )

  group(
    'page_2 - https://portal.dembrane.com/en-US/3cc62e6f-652e-46f8-a6df-e068dcdadf62/conversation/5fd8d61f-706c-4397-8411-b22ca5e387c6',
    function () {
      response = http.options(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62',
        null,
        {
          headers: {
            accept: '*/*',
            'access-control-request-headers': 'baggage,sentry-trace',
            'access-control-request-method': 'GET',
            origin: 'https://portal.dembrane.com',
            'sec-fetch-mode': 'cors',
          },
        }
      )
      response = http.options(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6',
        null,
        {
          headers: {
            accept: '*/*',
            'access-control-request-headers': 'baggage,sentry-trace',
            'access-control-request-method': 'GET',
            origin: 'https://portal.dembrane.com',
            'sec-fetch-mode': 'cors',
          },
        }
      )
      response = http.get(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62',
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-ba8164a6815d173c-1',
          },
        }
      )
      response = http.get(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6',
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-af33b55a3bafa4db-1',
          },
        }
      )
      response = http.get(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/chunks',
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-b44a438570b8ebbc-1',
          },
        }
      )
      response = http.options(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/chunks',
        null,
        {
          headers: {
            accept: '*/*',
            'access-control-request-headers': 'baggage,sentry-trace',
            'access-control-request-method': 'GET',
            origin: 'https://portal.dembrane.com',
            'sec-fetch-mode': 'cors',
          },
        }
      )
      response = http.get(
        'https://directus.dembrane.com/items/conversation_reply?fields=id%2Ccontent_text%2Cdate_created%2Ctype&filter=%7B%22conversation_id%22%3A%7B%22_eq%22%3A%225fd8d61f-706c-4397-8411-b22ca5e387c6%22%7D%7D&sort=date_created',
        {
          headers: {
            'content-type': 'application/json',
            dnt: '1',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
          },
        }
      )
      response = http.options(
        'https://directus.dembrane.com/items/conversation_reply?fields=id%2Ccontent_text%2Cdate_created%2Ctype&filter=%7B%22conversation_id%22%3A%7B%22_eq%22%3A%225fd8d61f-706c-4397-8411-b22ca5e387c6%22%7D%7D&sort=date_created',
        null,
        {
          headers: {
            accept: '*/*',
            'access-control-request-headers': 'content-type',
            'access-control-request-method': 'GET',
            origin: 'https://portal.dembrane.com',
            'sec-fetch-mode': 'cors',
          },
        }
      )
      response = http.get(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62',
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb054c257179e13a-1',
          },
        }
      )
      response = http.get(
        'https://directus.dembrane.com/items/conversation_reply?fields=id%2Ccontent_text%2Cdate_created%2Ctype&filter=%7B%22conversation_id%22%3A%7B%22_eq%22%3A%225fd8d61f-706c-4397-8411-b22ca5e387c6%22%7D%7D&sort=date_created',
        {
          headers: {
            'content-type': 'application/json',
            dnt: '1',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
          },
        }
      )
      sleep(34.5)
      response = http.post(
        'https://api.dembrane.com/api/participant/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/upload-chunk',
        null,
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            'content-type': 'multipart/form-data; boundary=----WebKitFormBoundaryaAdAf0nDpOADZtPv',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb14b8b84ac3598d-1',
          },
        }
      )
      response = http.options(
        'https://api.dembrane.com/api/participant/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/upload-chunk',
        null,
        {
          headers: {
            accept: '*/*',
            'access-control-request-headers': 'baggage,sentry-trace',
            'access-control-request-method': 'POST',
            origin: 'https://portal.dembrane.com',
            'sec-fetch-mode': 'cors',
          },
        }
      )
      sleep(0.9)
      response = http.get(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/chunks',
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb14b8b84ac3598d-1',
          },
        }
      )
      sleep(24.6)
      response = http.get(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6',
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb14b8b84ac3598d-1',
          },
        }
      )
      sleep(4.5)
      response = http.post(
        'https://api.dembrane.com/api/participant/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/upload-chunk',
        null,
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            'content-type': 'multipart/form-data; boundary=----WebKitFormBoundaryI6bq2NygvLNnMZQt',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb14b8b84ac3598d-1',
          },
        }
      )
      sleep(2.4)
      response = http.get(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/chunks',
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb14b8b84ac3598d-1',
          },
        }
      )
      sleep(27.6)
      response = http.post(
        'https://api.dembrane.com/api/participant/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/upload-chunk',
        null,
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            'content-type': 'multipart/form-data; boundary=----WebKitFormBoundaryo7P8gwkpV1185zUK',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb14b8b84ac3598d-1',
          },
        }
      )
      sleep(1.2)
      response = http.get(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/chunks',
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb14b8b84ac3598d-1',
          },
        }
      )
      sleep(24.5)
      response = http.get(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6',
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb14b8b84ac3598d-1',
          },
        }
      )
      sleep(4.3)
      response = http.post(
        'https://api.dembrane.com/api/participant/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/upload-chunk',
        null,
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            'content-type': 'multipart/form-data; boundary=----WebKitFormBoundaryhczvNpjurdIzsefM',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb14b8b84ac3598d-1',
          },
        }
      )
      sleep(0.7)
      response = http.get(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/chunks',
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb14b8b84ac3598d-1',
          },
        }
      )
      sleep(29.3)
      response = http.post(
        'https://api.dembrane.com/api/participant/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/upload-chunk',
        null,
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            'content-type': 'multipart/form-data; boundary=----WebKitFormBoundaryGF2BUqmeWJLABQLe',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb14b8b84ac3598d-1',
          },
        }
      )
      sleep(0.9)
      response = http.get(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/chunks',
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb14b8b84ac3598d-1',
          },
        }
      )
      sleep(25.2)
      response = http.get(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6',
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb14b8b84ac3598d-1',
          },
        }
      )
      sleep(3.9)
      response = http.post(
        'https://api.dembrane.com/api/participant/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/upload-chunk',
        null,
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            'content-type': 'multipart/form-data; boundary=----WebKitFormBoundaryIA8SQBwCeixAWnmr',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb14b8b84ac3598d-1',
          },
        }
      )
      sleep(1.2)
      response = http.get(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/chunks',
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb14b8b84ac3598d-1',
          },
        }
      )
      sleep(28.8)
      response = http.post(
        'https://api.dembrane.com/api/participant/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/upload-chunk',
        null,
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            'content-type': 'multipart/form-data; boundary=----WebKitFormBoundaryOneSDbYIFz6U3q2b',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb14b8b84ac3598d-1',
          },
        }
      )
      sleep(0.7)
      response = http.get(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/chunks',
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb14b8b84ac3598d-1',
          },
        }
      )
      sleep(6.6)
      response = http.options(
        'https://api.dembrane.com/api/participant/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/finish',
        null,
        {
          headers: {
            accept: '*/*',
            'access-control-request-headers': 'baggage,sentry-trace',
            'access-control-request-method': 'POST',
            origin: 'https://portal.dembrane.com',
            'sec-fetch-mode': 'cors',
          },
        }
      )
      response = http.post(
        'https://api.dembrane.com/api/participant/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/finish',
        null,
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb14b8b84ac3598d-1',
          },
        }
      )
      response = http.post(
        'https://api.dembrane.com/api/participant/conversations/5fd8d61f-706c-4397-8411-b22ca5e387c6/upload-chunk',
        null,
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            'content-type': 'multipart/form-data; boundary=----WebKitFormBoundaryXT8xl0XSSAKFX3a6',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=db744aa543f24b2c9dc3978467982196,sentry-sample_rate=0.5,sentry-sampled=true',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': 'db744aa543f24b2c9dc3978467982196-bb14b8b84ac3598d-1',
          },
        }
      )
    }
  )

  group(
    'page_3 - https://portal.dembrane.com/en-US/3cc62e6f-652e-46f8-a6df-e068dcdadf62/conversation/5fd8d61f-706c-4397-8411-b22ca5e387c6/finish',
    function () {
      response = http.get(
        'https://api.dembrane.com/api/participant/projects/3cc62e6f-652e-46f8-a6df-e068dcdadf62',
        {
          headers: {
            accept: 'application/json, text/plain, */*',
            dnt: '1',
            baggage:
              'sentry-environment=production,sentry-release=dev,sentry-public_key=27d974229a95ca3dcd9894f4073af1f1,sentry-trace_id=937c3c9d1fc84169987743b4abf1b918,sentry-sample_rate=0.5,sentry-sampled=false',
            'sec-ch-ua': '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sentry-trace': '937c3c9d1fc84169987743b4abf1b918-bcc3fc0cd1bc0ea9-0',
          },
        }
      )
    }
  )
}