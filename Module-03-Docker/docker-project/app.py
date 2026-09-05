import os
from flask import Flask, jsonify
import redis

app = Flask(__name__)

REDIS_HOST = os.environ.get("REDIS_HOST", "redis")
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))

cache = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, socket_connect_timeout=2)

@app.route("/")
def home():
    count = cache.incr("visits")
    return jsonify({"message": "Visit tracker", "visits": count})

@app.route("/health")
def health():
    try:
        cache.ping()
        return jsonify({"status": "healthy", "redis": "connected"}), 200
    except redis.exceptions.ConnectionError:
        return jsonify({"status": "unhealthy", "redis": "unreachable"}), 503

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
