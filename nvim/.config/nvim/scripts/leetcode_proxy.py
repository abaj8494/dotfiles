#!/usr/bin/env python3
"""
LeetCode Proxy Script for leetcode.nvim
Bypasses Cloudflare protection by using proper headers and session management
"""

import sys
import json
import requests
from pathlib import Path
import time

def get_cookie_path():
    """Get the leetcode cookie file path"""
    return Path.home() / ".cache/nvim/leetcode/cookie"

def load_cookies():
    """Load cookies from the leetcode.nvim cookie file"""
    cookie_file = get_cookie_path()
    if not cookie_file.exists():
        return {}
    
    try:
        with open(cookie_file, 'r') as f:
            cookie_string = f.read().strip()
        
        cookies = {}
        for cookie in cookie_string.split('; '):
            if '=' in cookie:
                key, value = cookie.split('=', 1)
                cookies[key] = value
        
        return cookies
    except Exception as e:
        print(f"Error loading cookies: {e}")
        return {}

def make_request(url, method='GET', data=None):
    """Make a request with proper headers to bypass Cloudflare"""
    cookies = load_cookies()
    
    headers = {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Accept-Encoding': 'gzip, deflate, br',
        'Connection': 'keep-alive',
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'same-origin',
        'Referer': 'https://leetcode.com/',
        'Origin': 'https://leetcode.com',
    }
    
    if 'csrftoken' in cookies:
        headers['X-CSRFToken'] = cookies['csrftoken']
    
    session = requests.Session()
    session.cookies.update(cookies)
    
    try:
        if method.upper() == 'POST':
            response = session.post(url, headers=headers, json=data, timeout=30)
        else:
            response = session.get(url, headers=headers, timeout=30)
        
        return response
    except Exception as e:
        print(f"Request failed: {e}")
        return None

def test_connection():
    """Test if the connection works with current cookies"""
    url = "https://leetcode.com/api/problems/all/"
    response = make_request(url)
    
    if response and response.status_code == 200:
        print("✅ Connection successful!")
        return True
    else:
        print(f"❌ Connection failed. Status: {response.status_code if response else 'No response'}")
        return False

def run_test(problem_slug, test_data):
    """Run test for a specific problem"""
    url = f"https://leetcode.com/problems/{problem_slug}/interpret_solution/"
    
    data = {
        "data_input": test_data.get("data_input", ""),
        "lang": "python3",
        "question_id": test_data.get("question_id", ""),
        "typed_code": test_data.get("typed_code", "")
    }
    
    response = make_request(url, method='POST', data=data)
    
    if response and response.status_code == 200:
        result = response.json()
        print(json.dumps(result, indent=2))
        return result
    else:
        print(f"Test failed. Status: {response.status_code if response else 'No response'}")
        return None

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 leetcode_proxy.py <command> [args]")
        print("Commands:")
        print("  test - Test connection")
        print("  run <problem_slug> <test_data_json> - Run test")
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == "test":
        test_connection()
    elif command == "run" and len(sys.argv) >= 4:
        problem_slug = sys.argv[2]
        test_data = json.loads(sys.argv[3])
        run_test(problem_slug, test_data)
    else:
        print("Invalid command or arguments")
        sys.exit(1)
