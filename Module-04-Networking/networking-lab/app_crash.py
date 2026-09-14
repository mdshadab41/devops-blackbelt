from flask import Flask, request
import sys, os

app = Flask(__name__)
port = int(sys.argv[1])

@app.route('/')
def home():
    return f'Hello from Flask instance on port {port}!\n'

@app.route('/crash')
def crash():
    os._exit(1)  # kills the ENTIRE process immediately, no cleanup, no exception handling possible

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=port)
