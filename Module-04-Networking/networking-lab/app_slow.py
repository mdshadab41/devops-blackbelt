from flask import Flask
import time, sys

app = Flask(__name__)
port = int(sys.argv[1])

@app.route('/')
def home():
    if port == 5001:
        time.sleep(3)  # simulate slow processing
    return f'Hello from Flask instance on port {port}!\n'

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=port)
