"""Security regression tests for api_server.py.

Run with: pytest tests/test_api_server.py -v

These tests exercise the Flask app directly via its test client (no real
network listener, no real Docker/systemd/root required) and mock
subprocess.run so no real `docker exec` ever runs.
"""
import os
import subprocess
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault('API_KEY', 'test-key-for-import-only')
import api_server  # noqa: E402


@pytest.fixture(autouse=True)
def reset_state(monkeypatch):
    """Give every test a known API key and a clean rate limiter."""
    monkeypatch.setattr(api_server, 'API_KEY', 'correct-horse-battery-staple')
    fresh_limiter = api_server.RateLimiter(
        api_server.RATE_LIMIT_MAX_REQUESTS, api_server.RATE_LIMIT_WINDOW_SECONDS
    )
    monkeypatch.setattr(api_server, 'reset_rate_limiter', fresh_limiter)
    yield


@pytest.fixture
def client():
    api_server.app.testing = True
    return api_server.app.test_client()


def fake_helper_success(*args, **kwargs):
    return subprocess.CompletedProcess(args=args, returncode=0, stdout='New password: sup3rSecr3t\n', stderr='')


def fake_helper_not_found(*args, **kwargs):
    return subprocess.CompletedProcess(args=args, returncode=1, stdout='', stderr='Error: No such container')


# ---------------------------------------------------------------------------
# Authentication: missing / empty / wrong / malformed / correct key
# ---------------------------------------------------------------------------

class TestAuthentication:
    def test_missing_key_rejected(self, client):
        resp = client.post('/api/v1/reset-password', json={'container_id': 'abc123'})
        assert resp.status_code == 401
        assert resp.get_json()['success'] is False

    def test_empty_header_key_rejected(self, client):
        resp = client.post(
            '/api/v1/reset-password',
            json={'container_id': 'abc123'},
            headers={'X-API-Key': ''},
        )
        assert resp.status_code == 401

    def test_wrong_key_rejected(self, client):
        resp = client.post(
            '/api/v1/reset-password',
            json={'container_id': 'abc123'},
            headers={'X-API-Key': 'totally-wrong-key'},
        )
        assert resp.status_code == 401

    def test_malformed_key_in_body_does_not_crash(self, client, monkeypatch):
        """A non-string api_key field (e.g. a JSON number) must fail auth
        cleanly, not raise TypeError from hmac.compare_digest."""
        resp = client.post(
            '/api/v1/reset-password',
            json={'container_id': 'abc123', 'api_key': 12345},
        )
        assert resp.status_code == 401

    def test_correct_key_in_header_accepted(self, client, monkeypatch):
        monkeypatch.setattr(api_server.subprocess, 'run', fake_helper_success)
        resp = client.post(
            '/api/v1/reset-password',
            json={'container_id': 'abc123'},
            headers={'X-API-Key': 'correct-horse-battery-staple'},
        )
        assert resp.status_code == 200
        assert resp.get_json()['success'] is True

    def test_correct_key_in_body_accepted(self, client, monkeypatch):
        monkeypatch.setattr(api_server.subprocess, 'run', fake_helper_success)
        resp = client.post(
            '/api/v1/reset-password',
            json={'container_id': 'abc123', 'api_key': 'correct-horse-battery-staple'},
        )
        assert resp.status_code == 200

    def test_bearer_token_accepted(self, client, monkeypatch):
        monkeypatch.setattr(api_server.subprocess, 'run', fake_helper_success)
        resp = client.post(
            '/api/v1/reset-password',
            json={'container_id': 'abc123'},
            headers={'Authorization': 'Bearer correct-horse-battery-staple'},
        )
        assert resp.status_code == 200

    def test_fails_closed_when_api_key_unset(self, client, monkeypatch):
        """This is the F7 fix: no API_KEY configured must reject everything,
        never silently allow it."""
        monkeypatch.setattr(api_server, 'API_KEY', '')
        resp = client.post(
            '/api/v1/reset-password',
            json={'container_id': 'abc123'},
            headers={'X-API-Key': 'anything'},
        )
        assert resp.status_code == 401
        assert resp.get_json()['success'] is False


# ---------------------------------------------------------------------------
# Authorization (this API has exactly one authorization decision: the key)
# ---------------------------------------------------------------------------

class TestAuthorization:
    def test_unauthorized_reset_never_calls_docker(self, client, monkeypatch):
        called = {'value': False}

        def spy(*a, **k):
            called['value'] = True
            return fake_helper_success(*a, **k)

        monkeypatch.setattr(api_server.subprocess, 'run', spy)
        client.post('/api/v1/reset-password', json={'container_id': 'abc123'})
        assert called['value'] is False

    def test_authorized_reset_calls_docker(self, client, monkeypatch):
        called = {'value': False}

        def spy(*a, **k):
            called['value'] = True
            return fake_helper_success(*a, **k)

        monkeypatch.setattr(api_server.subprocess, 'run', spy)
        client.post(
            '/api/v1/reset-password',
            json={'container_id': 'abc123'},
            headers={'X-API-Key': 'correct-horse-battery-staple'},
        )
        assert called['value'] is True


# ---------------------------------------------------------------------------
# Input validation - container_id (Phase 7 / F5)
# ---------------------------------------------------------------------------

class TestContainerIdValidation:
    @pytest.mark.parametrize('value', [
        '9edaf0cc317c',
        'dokploy.1.abcdef123456',
        'a' * 128,
        'my-container_1.0',
    ])
    def test_valid_ids_accepted(self, value):
        assert api_server.is_valid_container_id(value) is True

    @pytest.mark.parametrize('value', [
        '--privileged',
        '-u',
        '-it',
        '--env=FOO=bar',
        '--workdir=/',
        '; rm -rf /',
        '$(whoami)',
        '`whoami`',
        '../../etc/passwd',
        '',
        '   ',
        'a' * 129,  # one over the defensive length cap
        'valid-but-\x00-embedded-nul',
        'héllo',  # non-ASCII
        None,
        123,
    ])
    def test_malicious_or_invalid_ids_rejected(self, value):
        assert api_server.is_valid_container_id(value) is False

    def test_api_rejects_flag_like_container_id(self, client, monkeypatch):
        called = {'value': False}
        monkeypatch.setattr(api_server.subprocess, 'run', lambda *a, **k: called.update(value=True) or fake_helper_success(*a, **k))
        resp = client.post(
            '/api/v1/reset-password',
            json={'container_id': '--privileged'},
            headers={'X-API-Key': 'correct-horse-battery-staple'},
        )
        assert resp.status_code == 400
        assert called['value'] is False  # never reached subprocess.run at all

    def test_api_rejects_empty_container_id_in_manual_mode(self, client):
        resp = client.post(
            '/api/v1/reset-password',
            json={'container_id': ''},
            headers={'X-API-Key': 'correct-horse-battery-staple'},
        )
        assert resp.status_code == 400

    def test_helper_script_failure_reported_cleanly(self, client, monkeypatch):
        monkeypatch.setattr(api_server.subprocess, 'run', fake_helper_not_found)
        resp = client.post(
            '/api/v1/reset-password',
            json={'container_id': 'nonexistent'},
            headers={'X-API-Key': 'correct-horse-battery-staple'},
        )
        assert resp.status_code == 500
        assert resp.get_json()['success'] is False


# ---------------------------------------------------------------------------
# Rate limiting (Phase 5)
# ---------------------------------------------------------------------------

class TestRateLimiter:
    def test_allows_up_to_the_limit(self):
        limiter = api_server.RateLimiter(3, 60)
        for _ in range(3):
            allowed, _ = limiter.allow('1.2.3.4')
            assert allowed is True

    def test_blocks_over_the_limit(self):
        limiter = api_server.RateLimiter(3, 60)
        for _ in range(3):
            limiter.allow('1.2.3.4')
        allowed, retry_after = limiter.allow('1.2.3.4')
        assert allowed is False
        assert retry_after > 0

    def test_keys_are_independent(self):
        limiter = api_server.RateLimiter(1, 60)
        allowed_a, _ = limiter.allow('1.1.1.1')
        allowed_b, _ = limiter.allow('2.2.2.2')
        assert allowed_a is True
        assert allowed_b is True

    def test_window_expiry_releases_budget(self):
        fake_now = [1000.0]
        limiter = api_server.RateLimiter(1, 60, time_func=lambda: fake_now[0])
        allowed1, _ = limiter.allow('1.2.3.4')
        allowed2, _ = limiter.allow('1.2.3.4')
        assert allowed1 is True
        assert allowed2 is False
        fake_now[0] += 61  # advance past the window
        allowed3, _ = limiter.allow('1.2.3.4')
        assert allowed3 is True

    def test_endpoint_returns_429_with_retry_after(self, client, monkeypatch):
        monkeypatch.setattr(api_server.subprocess, 'run', fake_helper_success)
        headers = {'X-API-Key': 'correct-horse-battery-staple'}
        for _ in range(api_server.RATE_LIMIT_MAX_REQUESTS):
            resp = client.post('/api/v1/reset-password', json={'container_id': 'abc123'}, headers=headers)
            assert resp.status_code == 200
        resp = client.post('/api/v1/reset-password', json={'container_id': 'abc123'}, headers=headers)
        assert resp.status_code == 429
        assert 'Retry-After' in resp.headers

    def test_rate_limit_applies_before_auth_check(self, client, monkeypatch):
        """Failed-auth guessing must also be throttled, not just successful calls."""
        monkeypatch.setattr(api_server.subprocess, 'run', fake_helper_success)
        for _ in range(api_server.RATE_LIMIT_MAX_REQUESTS):
            client.post('/api/v1/reset-password', json={'container_id': 'abc123'}, headers={'X-API-Key': 'wrong'})
        resp = client.post('/api/v1/reset-password', json={'container_id': 'abc123'}, headers={'X-API-Key': 'wrong'})
        assert resp.status_code == 429

    def test_rate_limit_keyed_on_remote_addr_not_forwarded_for(self, client, monkeypatch):
        """A caller can't reset their own budget by spoofing X-Forwarded-For."""
        monkeypatch.setattr(api_server.subprocess, 'run', fake_helper_success)
        headers_base = {'X-API-Key': 'correct-horse-battery-staple'}
        for _ in range(api_server.RATE_LIMIT_MAX_REQUESTS):
            client.post('/api/v1/reset-password', json={'container_id': 'abc123'}, headers=headers_base)
        spoofed_headers = dict(headers_base)
        spoofed_headers['X-Forwarded-For'] = '9.9.9.9'
        resp = client.post('/api/v1/reset-password', json={'container_id': 'abc123'}, headers=spoofed_headers)
        assert resp.status_code == 429


# ---------------------------------------------------------------------------
# Secrets: never in logs / responses / exceptions
# ---------------------------------------------------------------------------

class TestSecretHandling:
    def test_wrong_key_not_echoed_in_response(self, client):
        secret_guess = 'super-secret-guess-value'
        resp = client.post(
            '/api/v1/reset-password',
            json={'container_id': 'abc123'},
            headers={'X-API-Key': secret_guess},
        )
        assert secret_guess not in resp.get_data(as_text=True)

    def test_generic_exception_does_not_leak_internals(self, client, monkeypatch):
        def boom(*a, **k):
            raise RuntimeError('/etc/shadow-like-sensitive-path leaked here')

        monkeypatch.setattr(api_server.subprocess, 'run', boom)
        resp = client.post(
            '/api/v1/reset-password',
            json={'container_id': 'abc123'},
            headers={'X-API-Key': 'correct-horse-battery-staple'},
        )
        assert resp.status_code == 500
        body = resp.get_data(as_text=True)
        assert 'shadow-like-sensitive-path' not in body

    def test_password_only_appears_in_success_response(self, client, monkeypatch):
        monkeypatch.setattr(api_server.subprocess, 'run', fake_helper_success)
        resp = client.post(
            '/api/v1/reset-password',
            json={'container_id': 'abc123'},
            headers={'X-API-Key': 'correct-horse-battery-staple'},
        )
        assert resp.get_json()['password'] == 'sup3rSecr3t'


# ---------------------------------------------------------------------------
# Network defaults (Phase 2)
# ---------------------------------------------------------------------------

class TestNetworkDefaults:
    def test_default_host_is_localhost(self, monkeypatch):
        monkeypatch.delenv('PUBLIC_BIND', raising=False)
        assert api_server._resolve_host() == '127.0.0.1'

    @pytest.mark.parametrize('value', ['true', '1', 'yes', 'on', 'TRUE'])
    def test_public_bind_opts_in_to_all_interfaces(self, monkeypatch, value):
        monkeypatch.setenv('PUBLIC_BIND', value)
        assert api_server._resolve_host() == '0.0.0.0'

    @pytest.mark.parametrize('value', ['false', '0', 'no', '', 'garbage'])
    def test_non_true_values_stay_localhost(self, monkeypatch, value):
        monkeypatch.setenv('PUBLIC_BIND', value)
        assert api_server._resolve_host() == '127.0.0.1'


# ---------------------------------------------------------------------------
# auto_mode / mode-selection logic (behavioral regression - must not change)
# ---------------------------------------------------------------------------

class TestModeSelection:
    def test_explicit_container_id_uses_manual_mode(self, client, monkeypatch):
        monkeypatch.setattr(api_server.subprocess, 'run', fake_helper_success)
        resp = client.post(
            '/api/v1/reset-password',
            json={'container_id': 'abc123'},
            headers={'X-API-Key': 'correct-horse-battery-staple'},
        )
        assert resp.get_json()['mode'] == 'manual'

    def test_auto_mode_true_searches_for_container(self, client, monkeypatch):
        monkeypatch.setattr(api_server, 'find_dokploy_container', lambda: 'found123')
        monkeypatch.setattr(api_server.subprocess, 'run', fake_helper_success)
        resp = client.post(
            '/api/v1/reset-password',
            json={'auto_mode': True},
            headers={'X-API-Key': 'correct-horse-battery-staple'},
        )
        assert resp.get_json()['mode'] == 'auto'
        assert resp.get_json()['container_id'] == 'found123'

    def test_auto_mode_as_json_boolean_does_not_crash(self, client, monkeypatch):
        """Regression test: the ORIGINAL code called .lower() directly on
        data.get('auto_mode', 'false'), which raised AttributeError whenever
        auto_mode was sent as a real JSON boolean (`{"auto_mode": true}`) -
        exactly the example the README itself documents. Must work now."""
        monkeypatch.setattr(api_server, 'find_dokploy_container', lambda: 'found123')
        monkeypatch.setattr(api_server.subprocess, 'run', fake_helper_success)
        resp = client.post(
            '/api/v1/reset-password',
            json={'auto_mode': True},
            headers={'X-API-Key': 'correct-horse-battery-staple'},
        )
        assert resp.status_code == 200
        assert resp.get_json()['mode'] == 'auto'

    def test_auto_discovered_container_id_is_validated(self, client, monkeypatch):
        monkeypatch.setattr(api_server, 'find_dokploy_container', lambda: '--privileged')
        resp = client.post(
            '/api/v1/reset-password',
            json={'auto_mode': True},
            headers={'X-API-Key': 'correct-horse-battery-staple'},
        )
        assert resp.status_code == 500

    def test_auto_mode_not_found_returns_404(self, client, monkeypatch):
        monkeypatch.setattr(api_server, 'find_dokploy_container', lambda: None)
        resp = client.post(
            '/api/v1/reset-password',
            json={'auto_mode': True},
            headers={'X-API-Key': 'correct-horse-battery-staple'},
        )
        assert resp.status_code == 404

    def test_neither_container_id_nor_mode_falls_back_to_auto_mode_env(self, client, monkeypatch):
        monkeypatch.setattr(api_server, 'AUTO_MODE', False)
        resp = client.post(
            '/api/v1/reset-password',
            json={},
            headers={'X-API-Key': 'correct-horse-battery-staple'},
        )
        assert resp.status_code == 400  # manual mode, no container_id given


# ---------------------------------------------------------------------------
# find_dokploy_container image matching (F12/F13 tightened matching)
# ---------------------------------------------------------------------------

class TestContainerDiscovery:
    def test_exact_image_match(self, monkeypatch):
        fake = subprocess.CompletedProcess(
            args=[], returncode=0,
            stdout='abc123\tdokploy/dokploy:v0.21.5\tdokploy.1.xyz\n',
            stderr='',
        )
        monkeypatch.setattr(api_server.subprocess, 'run', lambda *a, **k: fake)
        assert api_server.find_dokploy_container() == 'abc123'

    def test_substring_lookalike_image_not_matched(self, monkeypatch):
        """An attacker-run image that merely CONTAINS the string
        'dokploy/dokploy' must not match (F12/F13 hardening)."""
        fake = subprocess.CompletedProcess(
            args=[], returncode=0,
            stdout='evil456\tattacker/not-dokploy/dokploy-lookalike\tsomename\n',
            stderr='',
        )
        monkeypatch.setattr(api_server.subprocess, 'run', lambda *a, **k: fake)
        assert api_server.find_dokploy_container() is None
