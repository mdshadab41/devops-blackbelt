from flask import Flask, request
import sys

app = Flask(__name__)
port = int(sys.argv[1])

@app.route('/')
def home():
    return f'Hello from Flask instance on port {port}!\n'

@app.route('/divide')
def divide():
    num = int(request.args.get('num', 10))
    result = 100 / num  # BUG: no protection against num=0
    return f'100 / {num} = {result}\n'

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=port)
