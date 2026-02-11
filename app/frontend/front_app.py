from flask import Flask, render_template_string
import requests
import os

app = Flask(__name__)
BACKEND_URL = os.environ.get('BACKEND_URL')
# APP_VERSION = os.environ.get('APP_VERSION', 'v1.0.1')
APP_VERSION = "v1.0.2"

@app.route('/')
def home():
    try:
        response = requests.get(f"{BACKEND_URL}/api/data")
        data = response.json().get('message', 'Error')
    except:
        data = "Backend Unreachable"
    
    html = f"<html><body><h1>Frontend Version: {APP_VERSION}</h1><h2>Backend Says: {data}</h2></body></html>"
    return render_template_string(html)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)