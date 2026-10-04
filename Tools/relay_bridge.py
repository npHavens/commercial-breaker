#!/usr/bin/env python3
"""Paired loopback setup endpoint for the Skybox Safari extension."""
import json
import secrets
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

if __package__:
    from .hls_relay import Relay, RelayError, Upstream, Server, Handler, lan_address
else:
    from hls_relay import Relay, RelayError, Upstream, Server, Handler, lan_address


class Bridge(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, pairing_code, relay_factory=None):
        self.relay_server = None
        super().__init__(address, BridgeHandler)
        self.pairing_code = pairing_code
        self.relay_factory = relay_factory or start_relay
        self.relay_server = None
        self.setup_lock = threading.Lock()

    def server_close(self):
        if self.relay_server:
            self.relay_server.shutdown()
            self.relay_server.server_close()
        super().server_close()


def start_relay(payload):
    if not isinstance(payload, dict) or set(payload) != {'playlist', 'token'}:
        raise RelayError('Expected playlist and token.')
    if not all(isinstance(v, str) and 0 < len(v) <= 16384 for v in payload.values()):
        raise RelayError('Invalid session details.')
    relay = Relay(payload['playlist'], Upstream(payload['token']))
    server = Server((lan_address(), 0), Handler)
    try:
        server.relay = relay
        relay.origin = 'http://%s:%s' % server.server_address
        relay.preflight()
        threading.Thread(target=server.serve_forever, daemon=True).start()
        return server, relay.origin + relay.prefix
    except Exception:
        server.server_close()
        raise


class BridgeHandler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(5)

    def log_message(self, *args):
        pass

    def reply(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        # No CORS permission: ordinary webpages cannot submit authenticated JSON.
        if (self.headers.get('Host') != '127.0.0.1:%s' % self.server.server_port
                or self.path != '/session'):
            self.reply(403, {'error': 'Unexpected endpoint.'})
            return
        supplied = self.headers.get('Authorization', '')
        if not secrets.compare_digest(supplied.encode('utf-8'), ('Bearer ' + self.server.pairing_code).encode('ascii')):
            self.reply(403, {'error': 'Pairing code did not match. Check the helper window.'})
            return
        if self.headers.get('Content-Type') != 'application/json' or self.headers.get('Transfer-Encoding'):
            self.reply(400, {'error': 'Expected bounded JSON.'})
            return
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 40000:
                raise ValueError()
            payload = json.loads(self.rfile.read(length))
        except (ValueError, TimeoutError, OSError):
            self.reply(400, {'error': 'Invalid setup request.'})
            return
        if not self.server.setup_lock.acquire(blocking=False):
            self.reply(409, {'error': 'Relay setup is already running.'})
            return
        try:
            if self.server.relay_server:
                self.reply(409, {'error': 'This helper already has a relay. Restart the helper to create a new session.'})
                return
            server, url = self.server.relay_factory(payload)
            self.server.relay_server = server
            self.reply(200, {'url': url})
        except (RelayError, OSError, ValueError, TypeError):
            self.reply(502, {'error': 'Playlist or key check failed. Capture a fresh Paramount session and retry.'})
        finally:
            self.server.setup_lock.release()


def main():
    code = secrets.token_urlsafe(24)
    try:
        with Bridge(('127.0.0.1', 8766), code) as server:
            print('Skybox extension helper is ready. Pairing code:\n' + code, flush=True)
            print('Paste this code in Skybox’s Paramount setup. Keep this window open. Ctrl+C stops its relay.', flush=True)
            server.serve_forever()
    except KeyboardInterrupt:
        print('\nHelper stopped.')
    except OSError:
        print('Could not start helper on port 8766. Close an older helper first.')


if __name__ == '__main__':
    main()
