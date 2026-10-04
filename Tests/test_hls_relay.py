import contextlib
import io
from pathlib import Path
import threading
import unittest
from unittest.mock import patch
import urllib.error
import urllib.request


from Tools import hls_relay as module

PLAYLIST_URL = 'https://dai.google.com/session/live.m3u8?session=example'
KEY_URL = 'https://cbsi.live.ott.irdeto.com/key?keyId=1'
PLAYLIST = f'''#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:50
#EXT-X-KEY:METHOD=AES-128,URI="{KEY_URL}",KEYFORMAT="identity",IV=0x00000000000000000000000000000001
#EXTINF:6,
https://cdn.example.com/segment50.ts?signed=yes
#EXT-X-CUE-OUT:30
#EXT-X-KEY:METHOD=NONE
#EXTINF:6,
segment51.ts
#EXT-X-CUE-IN
'''.encode()


class FakeUpstream:
    def __init__(self):
        self.calls = []
        self.failure = None
        self.playlist = PLAYLIST

    def fetch(self, url, kind):
        self.calls.append((url, kind))
        if self.failure:
            raise module.RelayError(self.failure)
        return self.playlist if kind == 'playlist' else b'0123456789abcdef'


class PlaylistTests(unittest.TestCase):
    def setUp(self):
        self.upstream = FakeUpstream()
        self.relay = module.Relay(PLAYLIST_URL, self.upstream)
        self.relay.origin = 'http://192.168.1.10:8765'

    def test_rewrites_only_keys_resolves_segments_and_preserves_timing(self):
        body, key_id = self.relay.rewrite(PLAYLIST)
        text = body.decode()
        self.assertNotIn(KEY_URL, text)
        self.assertIn(self.relay.origin + self.relay.prefix + 'key/' + key_id, text)
        self.assertIn('https://cdn.example.com/segment50.ts?signed=yes', text)
        self.assertIn('https://dai.google.com/session/segment51.ts', text)
        for line in ('#EXT-X-CUE-OUT:30', '#EXT-X-CUE-IN', '#EXT-X-KEY:METHOD=NONE',
                     '#EXT-X-MEDIA-SEQUENCE:50', 'IV=0x00000000000000000000000000000001'):
            self.assertIn(line, text)
        self.assertEqual(self.relay.key(key_id), b'0123456789abcdef')
        self.assertEqual(self.upstream.calls, [(KEY_URL, 'key')])

    def test_attribute_order_does_not_matter(self):
        body = PLAYLIST.replace(b'METHOD=AES-128,URI="', b'URI="', 1)
        body = body.replace(b'",KEYFORMAT=', b'",METHOD=AES-128,KEYFORMAT=', 1)
        result, _ = self.relay.rewrite(body)
        self.assertNotIn(KEY_URL.encode(), result)

    def test_key_rotation_preserves_old_ids_and_preflights_most_recent_key(self):
        self.relay.rewrite(PLAYLIST)
        rotated = PLAYLIST.replace(b'keyId=1', b'keyId=2')
        _, latest = self.relay.rewrite(rotated)
        self.assertEqual(len(self.relay.keys), 2)
        self.assertEqual(self.relay.keys[latest], KEY_URL.replace('=1', '=2'))
        self.upstream.playlist = rotated
        self.relay.preflight()
        self.assertEqual(self.upstream.calls[-1], (KEY_URL.replace('=1', '=2'), 'key'))

    def test_rejects_external_keys_and_non_identity_encryption_before_fetch(self):
        for bad in (
            PLAYLIST.replace(KEY_URL.encode(), b'https://attacker.example/key'),
            PLAYLIST.replace(b'METHOD=AES-128', b'METHOD=SAMPLE-AES'),
            PLAYLIST.replace(b'KEYFORMAT="identity"', b'KEYFORMAT="com.apple.streamingkeydelivery"'),
            PLAYLIST.replace(b'METHOD=AES-128,', b'METHOD=AES-128,METHOD=NONE,'),
        ):
            with self.subTest(playlist=bad[:30]), self.assertRaises(module.RelayError):
                self.relay.rewrite(bad)
        self.assertEqual(self.upstream.calls, [])
        self.assertEqual(self.relay.keys, {})

    def test_rejects_master_map_and_bad_segment_urls(self):
        for bad in (
            b'#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nvariant.m3u8\n',
            PLAYLIST + b'#EXT-X-MAP:URI="init.mp4"\n',
            PLAYLIST.replace(b'https://cdn.example.com/', b'http://cdn.example.com/'),
            b'<html>Login needed</html>',
        ):
            with self.subTest(playlist=bad[:30]), self.assertRaises(module.RelayError):
                self.relay.rewrite(bad)

    def test_unknown_key_cannot_be_used_as_an_open_proxy(self):
        with self.assertRaises(module.RelayError):
            self.relay.key('https://attacker.example/')
        self.assertEqual(self.upstream.calls, [])

    def test_commercial_state_uses_playhead_not_current_broadcast_time_and_reuses_snapshot(self):
        self.upstream.playlist = b'''#EXTM3U
#EXT-X-PROGRAM-DATE-TIME:2026-09-19T21:00:00Z
#EXT-X-CUE-OUT:6
#EXTINF:6,
https://cdn.example.com/ad.ts
#EXT-X-CUE-IN
#EXTINF:6,
https://cdn.example.com/program.ts
'''
        from datetime import datetime, timezone
        start = datetime(2026, 9, 19, 21, tzinfo=timezone.utc).timestamp() * 1000
        self.assertEqual(self.relay.commercial_state(start + 1000)['state'], 'ad')
        self.assertEqual(self.relay.commercial_state(start + 6000)['state'], 'program')
        self.assertEqual(self.relay.commercial_state(start + 13000)['state'], 'unknown')
        self.assertEqual(self.upstream.calls, [(PLAYLIST_URL, 'playlist')])
        self.relay.refreshed_at = module.time.monotonic() - 4
        self.upstream.failure = 'Playlist returned HTTP 403.'
        with self.assertRaises(module.RelayError):
            self.relay.commercial_state(start + 1000)


class UpstreamTests(unittest.TestCase):
    def response(self, data):
        response = io.BytesIO(data)
        response.status = 200
        return response

    @patch.object(module.urllib.request, 'build_opener')
    def test_bearer_sent_only_to_key_host(self, build):
        upstream = module.Upstream('Bearer example-token')
        build.return_value.open.side_effect = [self.response(b'#EXTM3U'), self.response(b'x' * 16)]
        upstream.fetch(PLAYLIST_URL, 'playlist')
        upstream.fetch(KEY_URL, 'key')
        requests = [call.args[0] for call in build.return_value.open.call_args_list]
        self.assertFalse(requests[0].has_header('Authorization'))
        self.assertEqual(requests[1].get_header('Authorization'), 'Bearer example-token')
        with self.assertRaises(module.RelayError):
            upstream.fetch('https://attacker.example/key', 'key')
        self.assertEqual(build.return_value.open.call_count, 2)

    def test_redirect_handler_refuses_to_construct_followup_request(self):
        request = urllib.request.Request(KEY_URL, headers={'Authorization': 'Bearer secret'})
        for code in (301, 302, 303, 307, 308):
            result = module.NoRedirects().redirect_request(request, None, code, '', {}, 'https://attacker.example')
            self.assertIsNone(result)

    @patch.object(module.urllib.request, 'build_opener')
    def test_key_length_and_upstream_errors_are_sanitized(self, build):
        upstream = module.Upstream('example-token')
        for invalid in (b'', b'short', b'x' * 17):
            build.return_value.open.return_value = self.response(invalid)
            with self.assertRaisesRegex(module.RelayError, '16-byte'):
                upstream.fetch(KEY_URL, 'key')
        build.return_value.open.side_effect = urllib.error.HTTPError(
            KEY_URL, 403, 'secret response', {}, io.BytesIO(b'private upstream body'))
        with self.assertRaises(module.RelayError) as caught:
            upstream.fetch(KEY_URL, 'key')
        message = str(caught.exception)
        self.assertIn('HTTP 403', message)
        self.assertNotIn('secret', message)
        self.assertNotIn(KEY_URL, message)

    def test_rejects_unsafe_addresses_and_header_injection(self):
        for value in ('Bearer token\r\nX-Injected: true', '', 'token with spaces'):
            with self.assertRaises(module.RelayError):
                module.bearer_token(value)
        for value in ('127.0.0.1', '0.0.0.0', '8.8.8.8', '169.254.1.2', '240.0.0.1'):
            with self.assertRaises(module.RelayError):
                module.private_address(value)
        self.assertEqual(module.private_address('192.168.1.2'), '192.168.1.2')


class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.upstream = FakeUpstream()
        self.relay = module.Relay(PLAYLIST_URL, self.upstream)
        self.server = module.Server(('127.0.0.1', 0), module.Handler)
        self.server.relay = self.relay
        self.relay.origin = f'http://127.0.0.1:{self.server.server_port}'
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop)

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, path, **kwargs):
        request = urllib.request.Request(self.relay.origin + path, **kwargs)
        return urllib.request.urlopen(request, timeout=3)

    def test_serves_live_playlist_registered_key_and_player_without_token_or_cache(self):
        with self.request(self.relay.prefix) as response:
            self.assertIn(b'Choose AirPlay', response.read())
            self.assertEqual(response.headers['Referrer-Policy'], 'no-referrer')
        for _ in range(2):
            with self.request(self.relay.prefix + 'live.m3u8') as response:
                self.assertIn(b'#EXTM3U', response.read())
                self.assertEqual(response.headers['Cache-Control'], 'no-store')
        self.assertEqual(self.upstream.calls.count((PLAYLIST_URL, 'playlist')), 2)
        key_id = next(iter(self.relay.keys))
        with self.request(self.relay.prefix + 'key/' + key_id) as response:
            self.assertEqual(response.read(), b'0123456789abcdef')
        with self.request(self.relay.prefix + 'key/' + key_id, method='HEAD') as response:
            self.assertEqual(response.headers['Content-Length'], '16')
            self.assertEqual(response.read(), b'')

    def test_missing_capability_and_wrong_host_never_reach_upstream(self):
        for path, headers, expected in (
            ('/live.m3u8', {}, 404),
            ('/session/wrong/live.m3u8', {}, 404),
            (self.relay.prefix + 'live.m3u8', {'Host': 'attacker.example'}, 403),
            (self.relay.prefix + '../playlist-url.txt', {}, 404),
        ):
            with self.assertRaises(urllib.error.HTTPError) as caught:
                self.request(path, headers=headers)
            self.assertEqual(caught.exception.code, expected)
            caught.exception.close()
        self.assertEqual(self.upstream.calls, [])

    def test_expired_auth_is_visible_without_logging_sensitive_requests(self):
        self.relay.rewrite(PLAYLIST)
        self.upstream.failure = 'Key returned HTTP 403.'
        key_id = next(iter(self.relay.keys))
        output = io.StringIO()
        with contextlib.redirect_stderr(output), self.assertRaises(urllib.error.HTTPError) as caught:
            self.request(self.relay.prefix + 'key/' + key_id)
        self.assertEqual(caught.exception.code, 502)
        caught.exception.close()
        self.assertEqual(output.getvalue(), '')
        with self.request(self.relay.prefix + 'status') as response:
            body = response.read()
            self.assertIn(b'HTTP 403', body)
            self.assertNotIn(KEY_URL.encode(), body)
            self.assertNotIn(self.relay.prefix.encode(), body)

    def test_commercial_endpoint_is_bounded_and_contains_no_upstream_urls(self):
        with self.request(self.relay.prefix + 'commercial-state?playhead_ms=1234') as response:
            data = response.read()
            self.assertIn(b'"state": "unknown"', data)
            self.assertNotIn(KEY_URL.encode(), data)
            self.assertNotIn(PLAYLIST_URL.encode(), data)
        for query in ('playhead_ms=nan', 'playhead_ms=1&playhead_ms=2', 'url=https://example.com'):
            with self.assertRaises(urllib.error.HTTPError) as caught:
                self.request(self.relay.prefix + 'commercial-state?' + query)
            self.assertEqual(caught.exception.code, 502)
            caught.exception.close()


if __name__ == '__main__':
    unittest.main()
