#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import subprocess
import re
import os
import logging
import time
import webbrowser
from flask import Flask, request, jsonify
from flask_cors import CORS

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

logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
HELPER_SCRIPT = os.path.join(SCRIPT_DIR, 'reset-password-helper.sh')

API_KEY = os.getenv('API_KEY', '').strip()

def check_api_key():
    if not API_KEY:
        logger.warning("API_KEY not set - API is unprotected!")
        return True
    
    auth_header = request.headers.get('X-API-Key') or request.headers.get('Authorization', '').replace('Bearer ', '')
    if auth_header:
        logger.info(f"Received API key from header: {auth_header[:20]}... (length: {len(auth_header)})")
        logger.info(f"Expected API key: {API_KEY[:20]}... (length: {len(API_KEY)})")
        if auth_header == API_KEY:
            logger.info("API key verified from header")
            return True
        else:
            logger.warning(f"API key mismatch. Received: {auth_header[:20]}..., Expected: {API_KEY[:20]}...")
    
    if request.is_json:
        data = request.get_json() or {}
        api_key_from_body = data.get('api_key')
        if api_key_from_body:
            logger.info(f"Received API key from body: {api_key_from_body[:20]}... (length: {len(api_key_from_body)})")
            if api_key_from_body == API_KEY:
                logger.info("API key verified from body")
                return True
            else:
                logger.warning(f"API key mismatch from body. Received: {api_key_from_body[:20]}...")
    
    logger.warning("No valid API key found in request")
    return False

@app.route('/api/v1/reset-password', methods=['POST'])
def reset_password():
    if not check_api_key():
        logger.warning(f"Unauthorized access attempt from {request.remote_addr}")
        time.sleep(3)
        try:
            webbrowser.open('https://www.youtube.com/watch?v=dQw4w9WgXcQ')
        except Exception:
            pass
        return jsonify({
            'success': False,
            'error': 'Unauthorized: Invalid or missing API key'
        }), 401
    
    try:
        data = request.get_json()
        container_id = data.get('DOKPLOY_ID_DOCKER') or data.get('container_id')
        
        if not container_id:
            return jsonify({
                'success': False,
                'error': 'DOKPLOY_ID_DOCKER or container_id is required'
            }), 400
        
        logger.info(f"Resetting password for container: {container_id}")
        
        result = subprocess.run(
            [HELPER_SCRIPT, container_id],
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if result.returncode == 0:
            output = result.stdout.strip()
            password_match = re.search(r'New password:\s*(.+)', output)
            if password_match:
                password = password_match.group(1).strip()
                logger.info("Password reset successful")
                return jsonify({
                    'success': True,
                    'password': password
                }), 200
            else:
                error_msg = f"Could not parse password from output: {output[:200]}"
                logger.error(error_msg)
                return jsonify({
                    'success': False,
                    'error': error_msg
                }), 500
        else:
            error_output = result.stderr if result.stderr else result.stdout
            error_msg = error_output[:500] if error_output else "Unknown error"
            
            if "No such container" in error_msg:
                error_msg = f"Error: Failed to reset password\nOutput: {error_msg}"
            
            logger.error(f"Helper script failed: {error_msg}")
            return jsonify({
                'success': False,
                'error': f"Helper script failed: {error_msg}"
            }), 500
            
    except subprocess.TimeoutExpired:
        error_msg = "Helper script timeout"
        logger.error(error_msg)
        return jsonify({
            'success': False,
            'error': error_msg
        }), 500
    except Exception as e:
        error_msg = f"Error: {str(e)}"
        logger.error(error_msg)
        return jsonify({
            'success': False,
            'error': error_msg
        }), 500

@app.route('/', methods=['GET'])
def index():
    return jsonify({
        'service': 'Reset Password API Server for Dokploy',
        'version': '1.0.0',
        'endpoints': {
            '/api/v1/reset-password': {
                'method': 'POST',
                'description': 'Reset Dokploy admin password',
                'required_headers': ['X-API-Key'],
                'required_body': {
                    'DOKPLOY_ID_DOCKER': 'Docker container ID'
                }
            }
        },
        'documentation': 'https://github.com/crc137/dokploy-reset-password'
    }), 200

if __name__ == '__main__':
    port_str = os.getenv('API_PORT', '').strip()
    if not port_str:
        port = 11291
        logger.info(f"API_PORT not set, using default: {port}")
    else:
        try:
            port = int(port_str)
        except (ValueError, TypeError):
            port = 11291
            logger.warning(f"Invalid API_PORT '{port_str}', using default: {port}")
    
    if not API_KEY:
        logger.warning("API_KEY not set! API is unprotected. Set API_KEY in .env file or environment variable for security.")
    
    logger.info(f"Starting API server on 0.0.0.0:{port}")
    try:
        app.run(host='0.0.0.0', port=port, debug=False)
    except Exception as e:
        logger.error(f"Failed to start server: {e}")
        raise
