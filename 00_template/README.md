# hello world
 - this is a basic fastapi webserver that returns the health of a connected postgres and redis instance
### commands
```sh
docker compose up --build
```
```sh
curl http://localhost:8000/health

{
  "status": "healthy",
  "dependencies": {
    "redis": "CONNECTED",
    "postgres": "CONNECTED"
  }
}
```

```sh
# stop redis
docker stop 0_template-redis_cache-1

curl http://localhost:8000/health

{
  "status": "unhealthy",
  "dependencies": {
    "redis": "FAILED: Error -3 connecting to redis_cache:6379. Temporary failure in name resolution.",
    "postgres": "CONNECTED"
  }
}
```