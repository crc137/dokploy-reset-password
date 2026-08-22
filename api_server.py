#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import hmac
import json
import logging
import os
import re
import shutil
import subprocess
import threading
import time
import urllib.error
import urllib.request

from flask import Flask, request, jsonify
from waitress import serve

try:
    from dotenv import load_dotenv
    script_dir = os.path.dirname(os.path.abspath(__file__))
    env_path = os.path.join(script_dir, '.env')
    if os.path.exists(env_path):
        load_dotenv(dotenv_path=env_path, override=True)
    env_path_alt = os.path.join(script_dir, 'env')
    if os.path.exists(env_path_alt):
        load_dotenv(dotenv_path=env_path_alt, override=True)
except ImportError:
    pass

LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO').strip().upper()
logging.basicConfig(level=getattr(logging, LOG_LEVEL, logging.INFO),format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
HELPER_SCRIPT = os.path.join(SCRIPT_DIR, 'reset-password-helper.sh')

DOCKER_BIN = shutil.which('docker') or 'docker'

API_KEY = os.getenv('API_KEY', '').strip()
AUTO_MODE = os.getenv('AUTO_MODE', 'false').strip().lower() in ('true', '1', 'yes', 'on')
DOKPLOY_URL = os.getenv('DOKPLOY_URL', 'http://127.0.0.1:3000').strip().rstrip('/')
DOKPLOY_HEALTH_TIMEOUT = 5

CONTAINER_ID_RE = re.compile(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$')

RATE_LIMIT_MAX_REQUESTS = 10
RATE_LIMIT_WINDOW_SECONDS = 300

STATUS_RATE_LIMIT_MAX_REQUESTS = 30
STATUS_RATE_LIMIT_WINDOW_SECONDS = 60

class RateLimiter:
    def __init__(self, max_requests, window_seconds, time_func=time.monotonic):
        self._max = max_requests
        self._window = window_seconds
        self._time = time_func
        self._lock = threading.Lock()
        self._hits = {}

    def allow(self, key):
        now = self._time()
        with self._lock:
            timestamps = [t for t in self._hits.get(key, []) if now - t < self._window]
            if len(timestamps) >= self._max:
                self._hits[key] = timestamps
                retry_after = int(self._window - (now - timestamps[0])) + 1
                return False, retry_after
            timestamps.append(now)
            self._hits[key] = timestamps
            return True, 0

reset_rate_limiter = RateLimiter(RATE_LIMIT_MAX_REQUESTS, RATE_LIMIT_WINDOW_SECONDS)
status_rate_limiter = RateLimiter(STATUS_RATE_LIMIT_MAX_REQUESTS, STATUS_RATE_LIMIT_WINDOW_SECONDS)

def check_api_key():
    if not API_KEY:
        logger.error("API_KEY is not configured - refusing all requests until it is set")
        return False

    auth_header = request.headers.get('X-API-Key') or request.headers.get('Authorization', '').replace('Bearer ', '')
    if isinstance(auth_header, str) and auth_header:
        if hmac.compare_digest(auth_header, API_KEY):
            logger.info("API key verified from header")
            return True
        logger.warning(f"API key mismatch from header (length: {len(auth_header)})")

    if request.is_json:
        data = request.get_json(silent=True) or {}
        api_key_from_body = data.get('api_key')
        if isinstance(api_key_from_body, str) and api_key_from_body:
            if hmac.compare_digest(api_key_from_body, API_KEY):
                logger.info("API key verified from body")
                return True
            logger.warning(f"API key mismatch from body (length: {len(api_key_from_body)})")

    logger.warning("No valid API key found in request")
    return False

def check_dokploy_panel_open():
    if not (DOKPLOY_URL.startswith('http://') or DOKPLOY_URL.startswith('https://')):
        logger.error(f"DOKPLOY_URL must start with http:// or https:// (got: {DOKPLOY_URL!r})")
        return False, 'misconfigured'

    url = f"{DOKPLOY_URL}/api/settings.health"
    try:
        req = urllib.request.Request(url, method='GET')
        with urllib.request.urlopen(req, timeout=DOKPLOY_HEALTH_TIMEOUT) as resp:
            if resp.status != 200:
                return False, f"unhealthy (HTTP {resp.status})"
            body = json.loads(resp.read().decode('utf-8'))
            if isinstance(body, dict) and body.get('status') == 'ok':
                return True, 'ok'
            return False, 'unhealthy (unexpected response)'
    except urllib.error.HTTPError as e:
        return False, f"unhealthy (HTTP {e.code})"
    except (urllib.error.URLError, TimeoutError, ValueError):
        return False, 'unreachable'
    except Exception as e:
        logger.error(f"Unexpected error checking Dokploy panel status: {e}")
        return False, 'unreachable'

def is_valid_container_id(value):
    return isinstance(value, str) and bool(CONTAINER_ID_RE.match(value))

def find_dokploy_container():
    try:
        result = subprocess.run([DOCKER_BIN, 'ps', '--format', '{{.ID}}\t{{.Image}}\t{{.Names}}'],capture_output=True,text=True,timeout=10)

        if result.returncode != 0:
            logger.error(f"Failed to list containers: {result.stderr}")
            return None

        lines = result.stdout.strip().split('\n')
        if not lines or lines == ['']:
            logger.warning("No running containers found")
            return None

        image_re = re.compile(r'^dokploy/dokploy(:.*)?$')

        for line in lines:
            if not line.strip():
                continue
            parts = line.split('\t')
            if len(parts) >= 3:
                container_id, image, names = (p.strip() for p in parts[:3])
                if image_re.match(image.lower()):
                    logger.info(f"Found Dokploy container by image: ID={container_id}, Image={image}, Names={names}")
                    return container_id

        for line in lines:
            if not line.strip():
                continue
            parts = line.split('\t')
            if len(parts) >= 3:
                container_id, image, names = (p.strip() for p in parts[:3])
                if names.lower().startswith('dokploy.') or names.lower() == 'dokploy':
                    logger.info(f"Found Dokploy container by name: ID={container_id}, Image={image}, Names={names}")
                    return container_id

        logger.warning("Dokploy container not found in running containers")
        return None

    except subprocess.TimeoutExpired:
        logger.error("Timeout while searching for Dokploy container")
        return None
    except Exception as e:
        logger.error(f"Error searching for Dokploy container: {e}")
        return None

@app.route('/api/v1/reset-password', methods=['POST'])
def reset_password():
    allowed, retry_after = reset_rate_limiter.allow(request.remote_addr or 'unknown')
    if not allowed:
        logger.warning(f"Rate limit exceeded for {request.remote_addr}")
        response = jsonify({'success': False,'error': 'Too many requests. Please try again later.'})
        response.status_code = 429
        response.headers['Retry-After'] = str(retry_after)
        return response

    if not check_api_key():
        logger.warning(f"Unauthorized access attempt from {request.remote_addr}")
        return jsonify({'success': False,'error': 'Unauthorized: Invalid or missing API key'}), 401

    try:
        data = request.get_json(silent=True) or {}

        raw_container_id = data.get('DOKPLOY_ID_DOCKER') or data.get('container_id')
        has_container_id = bool(raw_container_id)

        has_explicit_mode = 'auto_mode' in data or 'mode' in data

        if has_explicit_mode:
            auto_mode_field = data.get('auto_mode', 'false')
            auto_mode = str(auto_mode_field).lower() in ('true', '1', 'yes', 'on')
            mode = str(data.get('mode', '')).lower()
            if mode == 'auto':
                auto_mode = True
            elif mode == 'manual':
                auto_mode = False
        elif has_container_id:
            auto_mode = False
        else:
            auto_mode = AUTO_MODE

        container_id = None

        if auto_mode:
            logger.info("Auto mode: searching for Dokploy container...")
            container_id = find_dokploy_container()
            if not container_id:
                return jsonify({'success': False,'error': 'Dokploy container not found. Make sure Dokploy container is running or use manual mode with container_id.'}), 404
            if not is_valid_container_id(container_id):
                logger.error(f"Auto-discovered container id failed validation: {container_id!r}")
                return jsonify({'success': False,'error': 'Auto-discovered container id was invalid.'}), 500
            logger.info(f"Auto mode: found container {container_id}")
        else:
            container_id = raw_container_id
            if not container_id:
                return jsonify({'success': False,'error': 'container_id or DOKPLOY_ID_DOCKER is required in manual mode. Use auto_mode=true for automatic search.'}), 400
            if not is_valid_container_id(container_id):
                logger.warning(f"Rejected malformed container_id from {request.remote_addr}")
                return jsonify({'success': False,'error': 'Invalid container_id. Must match a Docker container ID/name ''(letters, digits, and _.- only, starting with a letter or digit).'}), 400
            logger.info(f"Manual mode: using container {container_id}")

        logger.info(f"Resetting password for container: {container_id}")

        result = subprocess.run([HELPER_SCRIPT, container_id],capture_output=True,text=True,timeout=30)

        if result.returncode == 0:
            output = result.stdout.strip()
            password_match = re.search(r'New password:\s*(.+)', output)
            if password_match:
                password = password_match.group(1).strip()
                logger.info("Password reset successful")
                return jsonify({'success': True,'password': password,'container_id': container_id,'mode': 'auto' if auto_mode else 'manual'}), 200
            else:
                logger.error(f"Could not parse password from helper output (len={len(output)})")
                return jsonify({'success': False,'error': 'Password reset ran but the new password could not be parsed from the output.'}), 500
        else:
            error_output = result.stderr if result.stderr else result.stdout
            error_msg = (error_output or "Unknown error")[:500]
            logger.error(f"Helper script failed: {error_msg}")
            return jsonify({'success': False,'error': f"Helper script failed: {error_msg}"}), 500

    except subprocess.TimeoutExpired:
        logger.error("Helper script timeout")
        return jsonify({'success': False,'error': 'Helper script timeout'}), 500
    except Exception as e:
        logger.exception("Unhandled error while processing reset-password request")
        return jsonify({'success': False,'error': 'Internal server error'}), 500

@app.route('/api/v1/panel-status', methods=['GET'])
def panel_status():
    allowed, retry_after = status_rate_limiter.allow(request.remote_addr or 'unknown')
    if not allowed:
        response = jsonify({'success': False,'error': 'Too many requests. Please try again later.'})
        response.status_code = 429
        response.headers['Retry-After'] = str(retry_after)
        return response

    if not check_api_key():
        return jsonify({'success': False,'error': 'Unauthorized: Invalid or missing API key'}), 401

    open_, detail = check_dokploy_panel_open()
    return jsonify({'success': True,'open': open_,'detail': detail}), 200

@app.route('/', methods=['GET'])
def index():
    return jsonify({
        'service': 'Reset Password API Server for Dokploy',
        'version': '1.2.2',
        'endpoints': {
            '/api/v1/panel-status': {
                'method': 'GET',
                'description': 'Check whether the Dokploy panel is reachable and healthy',
                'required_headers': ['X-API-Key'],
                'response': {
                    'open': 'true if Dokploy answered healthy, false otherwise',
                    'detail': "'ok', 'unreachable', or an 'unhealthy (...)' reason"
                }
            },
            '/api/v1/reset-password': {
                'method': 'POST',
                'description': 'Reset Dokploy admin password',
                'required_headers': ['X-API-Key'],
                'body_options': {
                    'manual_mode': {
                        'container_id': 'Docker container ID (required in manual mode)',
                        'DOKPLOY_ID_DOCKER': 'Alternative field name for container ID'
                    },
                    'auto_mode': {
                        'auto_mode': 'true/false - Enable automatic container search',
                        'mode': 'auto/manual - Set operation mode'
                    },
                    'note': 'If auto_mode is not specified, uses AUTO_MODE from .env file'
                },
                'examples': {
                    'manual': {
                        'container_id': '9edaf0cc317c'
                    },
                    'auto': {
                        'auto_mode': True
                    }
                }
            }
        },
        'documentation': 'https://github.com/crc137/dokploy-reset-password'
    }), 200

def _resolve_port():
    port_str = os.getenv('API_PORT', '').strip()
    if not port_str:
        logger.info("API_PORT not set, using default: 11292")
        return 11292
    try:
        return int(port_str)
    except (ValueError, TypeError):
        logger.warning(f"Invalid API_PORT '{port_str}', using default: 11292")
        return 11292

if __name__ == '__main__':
    port = _resolve_port()
    host = '0.0.0.0'

    if not API_KEY:
        logger.error("API_KEY is not set. The server will start but will reject every request ""until API_KEY is configured in .env - this API no longer runs unauthenticated.")

    logger.info(f"Starting API server on {host}:{port} (waitress)")
    try:
        serve(app, host=host, port=port)
    except Exception as e:
        logger.error(f"Failed to start server: {e}")
        raise
