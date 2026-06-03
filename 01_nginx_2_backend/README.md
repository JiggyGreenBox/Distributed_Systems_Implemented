# nginx load balance 2 backends
 - Route requests between the 2 backend instances
### commands
```sh
docker compose down
docker compose up --build
```
```sh
curl http://localhost:8080/hit

# nginx is serving between the 2 servers in round robin manner
{"message":"Hello from the cluster!","handled_by_instance":"92fe1a91a699","global_hit_count":1}
{"message":"Hello from the cluster!","handled_by_instance":"8b59fbe18119","global_hit_count":2}
{"message":"Hello from the cluster!","handled_by_instance":"92fe1a91a699","global_hit_count":3}
{"message":"Hello from the cluster!","handled_by_instance":"8b59fbe18119","global_hit_count":4}
```