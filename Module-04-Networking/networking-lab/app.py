from flask import Flask, request
app = Flask(__name__)

@app.route('/')
def home():
    real_ip = request.headers.get('X-Real-IP', 'NOT SET')
    host = request.headers.get('Host', 'NOT SET')
    return f'Hello! Received Host={host}, X-Real-IP={real_ip}'

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
