#!/usr/bin/env python3
"""Local, single-session Paramount HLS experiment. Python 3.9+, stdlib only."""

import argparse
from collections import deque
import getpass
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
from pathlib import Path
import re
import secrets
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

if __package__:
    from .commercial_timing import classify_playback, finite, parse_timeline
else:
    from commercial_timing import classify_playback, finite, parse_timeline


ROOT = Path(__file__).resolve().parents[1]
PLAYLIST_HOST = 'dai.google.com'
KEY_HOST = 'cbsi.live.ott.irdeto.com'


class RelayError(Exception):
    """Messages are safe to show: no URLs, tokens, or upstream response bodies."""


def https_url(value, host=None):
    try:
        url = urllib.parse.urlsplit(value)
        valid = (url.scheme == 'https' and url.hostname and
                 url.port in (None, 443) and not url.username and
                 not url.password and not url.fragment and
                 not re.search(r'[\s\x00-\x1f\x7f]', value) and '{$' not in value)
        if not valid or (host and url.hostname != host):
            raise ValueError()
    except ValueError:
        raise RelayError('Unsupported upstream URL or host.') from None
    return value


def bearer_token(value):
    value = value.strip()
    if value.lower().startswith('bearer '):
        value = value[7:].strip()
    if not value or not re.fullmatch(r'[A-Za-z0-9._~+/=-]+', value):
        raise RelayError('Paste the bearer token or Bearer header value, without quotes.')
    return value


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # In particular, never forward Authorization to a redirect destination.
        return None


class Upstream:
    def __init__(self, token):
        self._token = bearer_token(token)

    def fetch(self, url, kind):
        https_url(url, KEY_HOST if kind == 'key' else PLAYLIST_HOST)
        headers = {'Accept-Encoding': 'identity', 'Cache-Control': 'no-cache'}
        if kind == 'key':
            headers['Authorization'] = 'Bearer ' + self._token
        request = urllib.request.Request(url, headers=headers)
        limit = 16 if kind == 'key' else 2 * 1024 * 1024
        # A separate opener per request avoids shared mutable handler state.
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirects())
        try:
            with opener.open(request, timeout=15) as response:
                if response.status != 200:
                    raise RelayError(f'{kind.title()} returned HTTP {response.status}.')
                data = response.read(limit + 1)
        except urllib.error.HTTPError as error:
            code = error.code
            error.close()
            hint = ' Copy a fresh token from the working Paramount key request and restart.' if kind == 'key' and code in (401, 403) else ''
            raise RelayError(f'{kind.title()} returned HTTP {code}.{hint}') from None
        except (OSError, urllib.error.URLError):
            raise RelayError(f'{kind.title()} request failed or timed out.') from None
        if len(data) > limit or (kind == 'key' and len(data) != 16):
            raise RelayError('Key response was not a 16-byte AES key.' if kind == 'key'
                             else 'Playlist exceeds the 2 MiB size limit.')
        return data


def attributes(text):
    values = {}
    pattern = re.compile(r'([A-Z0-9-]+)=("[^"\r\n]*"|[^,\r\n]+)(?:,|$)')
    position = 0
    for match in pattern.finditer(text):
        if match.start() != position or match[1] in values:
            raise RelayError('Malformed or duplicate key attributes.')
        values[match[1]] = match[2].strip('"')
        position = match.end()
    if position != len(text):
        raise RelayError('Malformed key attributes.')
    return values


class Relay:
    def __init__(self, playlist_url, upstream):
        self.playlist_url = https_url(playlist_url, PLAYLIST_HOST)
        self.upstream = upstream
        self.prefix = '/session/' + secrets.token_urlsafe(32) + '/'
        self.origin = ''  # Set once, after binding the selected LAN interface.
        self.keys = {}
        self.lock = threading.Lock()
        self.events = deque(maxlen=20)
        self.playlist_lock = threading.Lock()
        self.timeline = []
        self.sampled_at_ms = None
        self.refreshed_at = 0

    def note(self, message):
        with self.lock:
            self.events.append(time.strftime('%H:%M:%S') + ' · ' + message)

    def rewrite(self, data):
        try:
            text = data.decode('utf-8-sig')
        except UnicodeError:
            raise RelayError('Playlist is not UTF-8.') from None
        lines = text.splitlines()
        if not lines or lines[0] != '#EXTM3U' or not any(x.startswith('#EXTINF:') for x in lines):
            raise RelayError('Expected an HLS media playlist containing EXTINF segments.')
        result, discovered = [], {}
        last_key = None
        for line in lines:
            if line.startswith(('#EXT-X-STREAM-INF:', '#EXT-X-I-FRAME-STREAM-INF:', '#EXT-X-DEFINE:')):
                raise RelayError('This test requires a media playlist, not a master or variable playlist.')
            if line.startswith('#EXT-X-KEY:'):
                values = attributes(line.partition(':')[2])
                method = values.get('METHOD')
                if method == 'NONE':
                    if len(values) != 1:
                        raise RelayError('Unexpected attributes on an unencrypted key tag.')
                elif method == 'AES-128' and values.get('KEYFORMAT', 'identity') == 'identity':
                    if not values.get('URI'):
                        raise RelayError('Encrypted playlist has no key URI.')
                    key_url = https_url(urllib.parse.urljoin(self.playlist_url, values['URI']), KEY_HOST)
                    key_id = hashlib.sha256(key_url.encode()).hexdigest()
                    discovered[key_id] = key_url
                    last_key = key_id
                    local_url = self.origin + self.prefix + 'key/' + key_id
                    line = re.sub(r'(^#EXT-X-KEY:|,)URI="[^"]*"',
                                  lambda match: match[1] + 'URI="' + local_url + '"', line)
                    # KEY URI is required to be quoted; do not silently leave an upstream URL.
                    if local_url not in line:
                        raise RelayError('Unsupported key URI syntax.')
                else:
                    raise RelayError('Only AES-128 identity keys are supported by this experiment.')
            elif line.startswith('#') and re.search(r'\bURI=', line):
                raise RelayError('Additional URI-bearing playlist tags are not supported by this test.')
            elif line and not line.startswith('#'):
                line = https_url(urllib.parse.urljoin(self.playlist_url, line))
            result.append(line)
        with self.lock:
            if len(self.keys.keys() | discovered.keys()) > 256:
                raise RelayError('Key rotation limit reached; restart the relay.')
            self.keys.update(discovered)
        return ('\n'.join(result) + '\n').encode(), last_key

    def playlist(self):
        with self.playlist_lock:
            return self.refresh_playlist()

    def refresh_playlist(self):
        # Caller holds playlist_lock, including when a native player refreshes.
        data = self.upstream.fetch(self.playlist_url, 'playlist')
        result = self.rewrite(data)
        self.timeline = parse_timeline(data.decode('utf-8-sig'))
        self.sampled_at_ms = time.time() * 1000
        self.refreshed_at = time.monotonic()
        return result

    def commercial_state(self, playhead_ms):
        if not finite(playhead_ms):
            raise RelayError('A finite playback timestamp is required.')
        with self.playlist_lock:
            if self.sampled_at_ms is None or time.monotonic() - self.refreshed_at >= 3:
                self.refresh_playlist()
            state = classify_playback(playhead_ms, self.timeline, self.sampled_at_ms, time.time() * 1000)
            covering = [segment for segment in self.timeline if segment['start_ms'] <= playhead_ms < segment['end_ms']]
            span = covering[0] if len(covering) == 1 else None
            return {'state': state, 'playheadMs': playhead_ms,
                    'sampledAtMs': self.sampled_at_ms, 'hasTimeline': bool(self.timeline),
                    'startMs': span['start_ms'] if span else None,
                    'endMs': span['end_ms'] if span else None}

    def key(self, key_id):
        with self.lock:
            url = self.keys.get(key_id)
        if url is None:
            raise RelayError('Unknown key identifier.')
        data = self.upstream.fetch(url, 'key')
        self.note('Authorized key request succeeded (16 bytes).')
        return data

    def preflight(self):
        _, key_id = self.playlist()
        if key_id:
            self.key(key_id)
        self.note('Playlist check passed.' + (' Key check passed.' if key_id else ' No encrypted key found in this snapshot.'))


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # Default logs would expose the session capability URL.

    def do_GET(self):
        self.respond(False)

    def do_HEAD(self):
        self.respond(True)

    def respond(self, head):
        relay = self.server.relay
        content_type = 'text/plain; charset=utf-8'
        status, data = 404, b'Not found.'
        expected_host = urllib.parse.urlsplit(relay.origin).netloc
        if self.headers.get('Host') != expected_host:
            status, data = 403, b'Unexpected host.'
        elif self.path.startswith(relay.prefix):
            request = urllib.parse.urlsplit(self.path[len(relay.prefix):])
            route = request.path
            try:
                if route == '':
                    data = (ROOT / 'Tools' / 'hls_player.html').read_bytes()
                    status, content_type = 200, 'text/html; charset=utf-8'
                elif route == 'live.m3u8':
                    data, _ = relay.playlist()
                    status, content_type = 200, 'application/vnd.apple.mpegurl'
                elif route.startswith('key/') and re.fullmatch(r'key/[a-f0-9]{64}', route):
                    data = relay.key(route[4:])
                    status, content_type = 200, 'application/octet-stream'
                elif route == 'status':
                    with relay.lock:
                        data = json.dumps(list(relay.events)).encode()
                    status, content_type = 200, 'application/json'
                elif route == 'commercial-controller.js':
                    data = (ROOT / 'Tools' / 'commercial-controller.js').read_bytes()
                    status, content_type = 200, 'text/javascript; charset=utf-8'
                elif route == 'commercial-state':
                    params = urllib.parse.parse_qs(request.query)
                    try:
                        if set(params) != {'playhead_ms'} or len(params['playhead_ms']) != 1:
                            raise ValueError()
                        playhead_ms = float(params['playhead_ms'][0])
                    except (KeyError, ValueError):
                        raise RelayError('A single playback timestamp is required.') from None
                    data = json.dumps(relay.commercial_state(playhead_ms), allow_nan=False).encode()
                    status, content_type = 200, 'application/json'
            except RelayError as error:
                relay.note(str(error))
                status, data = 502, str(error).encode()
            except OSError:
                status, data = 500, b'Local relay could not read its player page.'
        try:
            self.send_response(status)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Referrer-Policy', 'no-referrer')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('X-Frame-Options', 'DENY')
            self.end_headers()
            if not head:
                self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def handle_error(self, request, client_address):
        self.relay.note('Local request failed unexpectedly.')


def lan_address():
    try:
        route = subprocess.run(['/sbin/route', '-n', 'get', 'default'],
                               capture_output=True, text=True, check=True, timeout=5)
        interface = re.search(r'^\s*interface:\s*(\S+)', route.stdout, re.MULTILINE)
        if not interface:
            raise ValueError()
        result = subprocess.run(['/usr/sbin/ipconfig', 'getifaddr', interface[1]],
                                capture_output=True, text=True, check=True, timeout=5)
        return private_address(result.stdout.strip())
    except (OSError, subprocess.SubprocessError, ValueError, RelayError):
        raise RelayError('Cannot determine LAN address. Pass --bind with this Mac\'s private IPv4 address.') from None


def private_address(value):
    try:
        address = ipaddress.IPv4Address(value)
        networks = ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')
        if not any(address in ipaddress.IPv4Network(network) for network in networks):
            raise ValueError()
    except ValueError:
        raise RelayError('--bind must be a private LAN IPv4 address reachable by Apple TV.') from None
    return str(address)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--playlist-url-file', type=Path, default=ROOT / 'playlist-url.txt')
    parser.add_argument('--prompt-playlist', action='store_true', help='Prompt for a fresh playlist URL without saving it.')
    parser.add_argument('--bind', help='Private LAN IPv4 address; defaults to the Mac default-route interface.')
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args()
    try:
        if not 1 <= args.port <= 65535:
            raise RelayError('Port must be between 1 and 65535.')
        address = private_address(args.bind) if args.bind else lan_address()
        if not sys.stdin.isatty():
            raise RelayError('Run in Terminal so session details can be entered without echo.')
        playlist_input = (getpass.getpass('Paste current media-playlist URL (hidden), then press Return: ')
                          if args.prompt_playlist else args.playlist_url_file.read_text().strip())
        playlist_url = https_url(playlist_input, PLAYLIST_HOST)
        token = getpass.getpass('Paste key-request bearer token (hidden), then press Return: ')
        relay = Relay(playlist_url, Upstream(token))
        del token
        with Server((address, args.port), Handler) as server:
            server.relay = relay
            relay.origin = f'http://{address}:{server.server_port}'
            print('Checking live playlist and authenticated key response…', flush=True)
            relay.preflight()
            print('Checks passed. Pause Paramount playback and turn off Screen Mirroring.')
            print('Open this address in Safari:\n' + relay.origin + relay.prefix, flush=True)
            print('Keep this terminal open. Ctrl+C stops the relay. Token is held only in memory.')
            print('Local HTTP test: anyone with this session URL on your LAN can access this stream.')
            server.serve_forever()
    except (RelayError, OSError) as error:
        print('Relay stopped: ' + (str(error) if isinstance(error, RelayError) else
              'Could not read the URL file or bind the LAN address/port.'), file=sys.stderr)
        return 1
    except (KeyboardInterrupt, EOFError):
        print('\nRelay stopped.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
