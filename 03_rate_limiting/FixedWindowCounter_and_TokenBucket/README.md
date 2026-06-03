# Fixed-Window-Counter
 - every user gets fixed requests per minute
 - it is possible to make many requests at 0:0:59 and again at 0:1:00

## how does this work?
* window_id = current_timestamp // WINDOW_SIZE_SECONDS
* this is floor division
```text
To perform floor division on a timestamp with 60, you must first 
convert the timestamp into a numeric value (like an integer or float 
representing epoch seconds) before using the // operator.This 
operation is commonly used to group timestamps into 1-minute 
(60-second) intervals.
```
* all requests made in the same minute have the same value
### commands
```sh
docker compose down && docker compose up --build
```
```sh
curl -s https://github.com | json_pp

curl -X POST http://localhost:8080/request \
     -H "Content-Type: application/json" \
     -d '{"user_id": "sourabh", "algorithm": "fixed_window"}' | json_pp


curl http://localhost:8080/stats | json_pp

curl http://localhost:8000/health
```

```text
"rl:fixed:sourabh:29536515"
  │    │     │         │
  │    │     │         └── The 60-second time block identifier
  │    │     └──────────── The unique user
  │    └────────────────── The algorithm name
  └─────────────────────── Prefix (Rate Limiter)
```

# token bucket
```sh
curl -X POST http://localhost:8080/request \
     -H "Content-Type: application/json" \
     -d '{"user_id": "sourabh", "algorithm": "token_bucket"}' | json_pp
```