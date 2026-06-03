

Step 1: Write a single backend app locally that connects to PostgreSQL and Redis. Make sure your endpoints work.

Step 2: Write the Dockerfile for your backend app.

Step 3: Draft the docker-compose.yml file. Spin up Postgres, Redis, and two instances of your backend app on different internal ports.

Step 4: Add the NGINX container to the compose file, map it to public port 8080, and configure its nginx.conf upstream block to point to your two backend containers.

stop all containers
docker stop $(docker ps -q)