from fastapi import FastAPI
import redis
import psycopg2
import os

app = FastAPI()

# Docker Compose will let us connect using the container service names as hostnames
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:password@localhost:5432/postgres")

# We will use the container's short ID or hostname to identify it
INSTANCE_NAME = os.getenv("HOSTNAME", "unknown_instance")

@app.get("/health")
def health_check():
    health_status = {"status": "healthy", "dependencies": {}}
    
    # 1. Test Redis
    try:
        r = redis.Redis(host=REDIS_HOST, port=6379, socket_connect_timeout=2)
        r.ping()
        health_status["dependencies"]["redis"] = "CONNECTED"
    except Exception as e:
        health_status["status"] = "unhealthy"
        health_status["dependencies"]["redis"] = f"FAILED: {str(e)}"

    # 2. Test Postgres
    try:
        conn = psycopg2.connect(DATABASE_URL, connect_timeout=2)
        cur = conn.cursor()
        cur.execute("SELECT 1;")
        cur.close()
        conn.close()
        health_status["dependencies"]["postgres"] = "CONNECTED"
    except Exception as e:
        health_status["status"] = "unhealthy"
        health_status["dependencies"]["postgres"] = f"FAILED: {str(e)}"

    return health_status

@app.get("/hit")
def trigger_hit():
    r = redis.Redis(host=REDIS_HOST, port=6379, decode_responses=True)
    # Increment a global counter in Redis
    total_hits = r.incr("global_hit_counter")
    
    return {
        "message": "Hello from the cluster!",
        "handled_by_instance": INSTANCE_NAME,
        "global_hit_count": total_hits
    }