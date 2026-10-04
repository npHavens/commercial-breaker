import json
import threading
import unittest
import urllib.request
import urllib.error
from Tools.relay_bridge import Bridge


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.server = Bridge(('127.0.0.1', 0), 'test-code', self.create)
        self.thread = threading.Thread(target=self.server.serve_forever)
        self.thread.start()

    def create(self, payload):
        self.calls.append(payload)
        return None, 'http://192.168.1.2:1234/session/example/'

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def post(self, code='test-code', host=None, body=None, content='application/json'):
        url = 'http://127.0.0.1:%s/session' % self.server.server_port
        headers = {'Authorization': 'Bearer ' + code, 'Content-Type': content}
        if host: headers['Host'] = host
        request = urllib.request.Request(url, data=body or b'{"playlist":"fixture","token":"synthetic"}', headers=headers)
        try:
            response = urllib.request.urlopen(request)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            return response.status, json.loads(response.read()), response.headers

    def test_pairing_required_before_credentials_are_processed(self):
        self.assertEqual(self.post(code='wrong')[0], 403)
        self.assertEqual(self.calls, [])

    def test_host_guard_rejects_rebinding(self):
        self.assertEqual(self.post(host='evil.example')[0], 403)
        self.assertEqual(self.calls, [])

    def test_valid_pair_returns_only_player_url(self):
        status, data, headers = self.post()
        self.assertEqual(status, 200)
        self.assertEqual(set(data), {'url'})
        self.assertEqual(self.calls, [{'playlist':'fixture', 'token':'synthetic'}])
        self.assertEqual(headers['Cache-Control'], 'no-store')
        self.assertNotIn('Access-Control-Allow-Origin', headers)

    def test_rejects_non_json_and_oversized_body(self):
        self.assertEqual(self.post(content='text/plain')[0], 400)
        self.assertEqual(self.post(body=b'x'*40001)[0], 400)
        self.assertEqual(self.calls, [])

    def test_busy_setup_does_not_create_second_relay(self):
        self.server.setup_lock.acquire()
        try: self.assertEqual(self.post()[0], 409)
        finally: self.server.setup_lock.release()
        self.assertEqual(self.calls, [])

    def test_error_does_not_echo_credentials(self):
        def fail(payload): raise ValueError(payload['token'])
        self.server.relay_factory = fail
        status, data, _ = self.post()
        self.assertEqual(status, 502)
        self.assertNotIn('synthetic', json.dumps(data))
