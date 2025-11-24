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
AUTO_MODE = os.getenv('AUTO_MODE', 'false').strip().lower() in ('true', '1', 'yes', 'on')

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

def find_dokploy_container():
    try:
        result = subprocess.run(
            ['docker', 'ps', '--format', '{{.ID}}\t{{.Image}}\t{{.Names}}'],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode != 0:
            logger.error(f"Failed to list containers: {result.stderr}")
            return None
        
        lines = result.stdout.strip().split('\n')
        if not lines or lines == ['']:
            logger.warning("No running containers found")
            return None
        
        for line in lines:
            if not line.strip():
                continue
            parts = line.split('\t')
            if len(parts) >= 3:
                container_id = parts[0].strip()
                image = parts[1].strip()
                names = parts[2].strip()

                if 'dokploy/dokploy' in image.lower():
                    logger.info(f"Found Dokploy container by image: ID={container_id}, Image={image}, Names={names}")
                    return container_id
        
        for line in lines:
            if not line.strip():
                continue
            parts = line.split('\t')
            if len(parts) >= 3:
                container_id = parts[0].strip()
                image = parts[1].strip()
                names = parts[2].strip()
                
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
        data = request.get_json() or {}
        
        has_container_id = bool(data.get('DOKPLOY_ID_DOCKER') or data.get('container_id'))
        
        has_explicit_mode = 'auto_mode' in data or 'mode' in data
        
        if has_explicit_mode:
            auto_mode = data.get('auto_mode', 'false').lower() in ('true', '1', 'yes', 'on')
            mode = data.get('mode', '').lower()
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
                return jsonify({
                    'success': False,
                    'error': 'Dokploy container not found. Make sure Dokploy container is running or use manual mode with container_id.'
                }), 404
            logger.info(f"Auto mode: found container {container_id}")
        else:
            container_id = data.get('DOKPLOY_ID_DOCKER') or data.get('container_id')
            if not container_id:
                return jsonify({
                    'success': False,
                    'error': 'container_id or DOKPLOY_ID_DOCKER is required in manual mode. Use auto_mode=true for automatic search.'
                }), 400
            logger.info(f"Manual mode: using container {container_id}")
        
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
                    'password': password,
                    'container_id': container_id,
                    'mode': 'auto' if auto_mode else 'manual'
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
        'version': '1.1.13',
        'endpoints': {
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

if __name__ == '__main__':
    port_str = os.getenv('API_PORT', '').strip()
    if not port_str:
        port = 11292
        logger.info(f"API_PORT not set, using default: {port}")
    else:
        try:
            port = int(port_str)
        except (ValueError, TypeError):
            port = 11292
            logger.warning(f"Invalid API_PORT '{port_str}', using default: {port}")
    
    if not API_KEY:
        logger.warning("API_KEY not set! API is unprotected. Set API_KEY in .env file or environment variable for security.")
    
    logger.info(f"Starting API server on 0.0.0.0:{port}")
    try:
        app.run(host='0.0.0.0', port=port, debug=False)
    except Exception as e:
        logger.error(f"Failed to start server: {e}")
        raise
