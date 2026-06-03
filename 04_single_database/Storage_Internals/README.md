# hello world
 - this is a basic fastapi webserver that returns the health of a connected postgres and redis instance
### commands
```sh
docker compose up --build
docker compose up -d

http://localhost:5050
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

```text
Right-click Servers -> Register ->  Server.
Name: Sandbox DB
Connection Tab ->  Host name/address: postgres_db
Username: sandbox_user
Password: sandbox_password
```