from flask import Flask, request
import sys, os

app = Flask(__name__)
port = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else int(os.environ.get('PORT', 5000))

@app.route('/')
def home():
    return f'Hello from Flask instance on port {port}!\n'

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=port)
