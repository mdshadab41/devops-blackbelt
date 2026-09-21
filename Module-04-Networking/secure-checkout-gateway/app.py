from flask import Flask, request
import os

app = Flask(__name__)
PORT = int(os.environ.get('PORT', 5000))
INSTANCE_ID = os.environ.get('INSTANCE_ID', f'port-{PORT}')

@app.route('/')
def home():
    return f'Hello from secure-checkout-gateway, served by instance: {INSTANCE_ID}\n'

@app.route('/health')
def health():
    return 'OK\n', 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=PORT)
