This pattern is called **Local Batching with Asynchronous Synchronization**, and it is exactly how systems handle massive scale without crushing Redis under a mountain of synchronous network calls.

Instead of treating Redis as a hard gatekeeper for every single HTTP request, the backend replicas treat Redis as a **wholesale bank**. Each replica checks out a "batch" of tokens to keep in its local, ultra-fast RAM. It doles those out locally, and only goes back to the bank when it runs dry or needs to report usage.

Here is the structured pseudocode for how a replica manages this balance using background threads.

---

## The Architecture Layout

Each backend replica maintains two local variables in its application memory per user:

1. `local_token_bucket`: The floating-point token count currently available inside this specific replica's memory.
2. `tokens_consumed_locally`: A simple integer counter tracking how many tokens this replica has successfully handed out since its last sync with Redis.

```
[ Incoming HTTP Requests ]
          ↓
┌──────────────────────────────────┐
│        Backend Replica 1         │
│                                  │
│  Check & Deduct Instantly        │
│  from Local RAM (Microseconds)   │
│                                  │
│  [Background Thread] ───────────┼────────┐
└──────────────────────────────────┘        │  Asynchronous Batch Sync
                                            ▼
                                  ┌──────────────────┐
                                  │   Shared Redis   │
                                  │ (Source of Truth)│
                                  └──────────────────┘

```

---

## 1. The Main Request Handler (Synchronous / Fast Path)

When a user hits the `/request` endpoint, the replica evaluates the request purely against its local RAM. There are no network calls made here, making this code execute in microseconds.

```python
# Thread-safe local memory storage inside Replica 1
LOCAL_MEMORY = {
    "sourabh": {
        "local_tokens": 0.0,       # Tokens currently available in this replica
        "tokens_consumed": 0       # How many we have handed out since last sync
    }
}

MAX_CAPACITY = 10.0
REFILL_RATE = 1.0 # 1 token per second

def handle_incoming_request(user_id):
    user_state = LOCAL_MEMORY.get(user_id)
    
    # If the user is completely unknown locally, we treat them as having 0 tokens
    # and let the background sync thread fetch their actual balance from Redis.
    if not user_state:
        LOCAL_MEMORY[user_id] = {"local_tokens": 0.0, "tokens_consumed": 0}
        user_state = LOCAL_MEMORY[user_id]

    # 1. First, lazily apply local refill logic based on the time passed since the last local check
    user_state["local_tokens"] = lazily_refill_local_bucket(user_state["local_tokens"])

    # 2. Evaluate the local token level
    if user_state["local_tokens"] >= 1.0:
        # Deduct the token locally
        user_state["local_tokens"] -= 1.0
        # Track that we consumed a token from our wholesale batch
        user_state["tokens_consumed"] += 1
        
        return "HTTP 200 OK (Allowed locally)"
    else:
        # If the local bucket is bone dry, fail immediately.
        # Alternatively, a highly robust system might trigger a forced synchronous sync 
        # to check if other replicas returned tokens to Redis, but for high throughput, we fail.
        return "HTTP 429 Too Many Requests (Blocked locally)"

```

---

## 2. The Background Sync Thread (Asynchronous / Periodic)

Every replica spawns a background worker thread that runs on a continuous loop (e.g., every 1 second or every 500 milliseconds). Its job is to flush local consumption metrics to Redis and check out the next batch of tokens.

```python
import time

def start_background_sync_loop():
    while True:
        time.sleep(1.0) # Run the sync every 1 second
        
        for user_id, state in LOCAL_MEMORY.items():
            # Skip users who haven't made any requests in the last second
            if state["tokens_consumed"] == 0:
                continue
                
            # Snapshot the local count to avoid race conditions with the main thread
            batch_to_report = state["tokens_consumed"]
            
            # Reset the local consumption tracker immediately so the main thread
            # can keep logging new requests while we talk to the network
            state["tokens_consumed"] = 0
            
            # Talk to Redis atomically via a Lua Script
            # We tell Redis: "Sourabh used X tokens. Tell me how many are left in the global bucket."
            global_allowed_balance = redis.call_lua_script(
                key=f"global_bucket:{user_id}",
                args=[batch_to_report, MAX_CAPACITY, REFILL_RATE]
            )
            
            # Update our local allocation based on what the central bank (Redis) says is left
            state["local_tokens"] = global_allowed_balance

```

---

## 3. The Centralized Redis Lua Script (The Token Bank)

When the background thread calls Redis, this script runs atomically on the Redis server. It subtracts the batch that the replica already handed out and reports back the remaining pool balance.

```lua
-- KEYS[1]: The global user key (e.g., "global_bucket:sourabh")
-- ARGV[1]: tokens_consumed_by_replica (e.g., 4)
-- ARGV[2]: max_capacity (e.g., 10)
-- ARGV[3]: refill_rate (e.g., 1.0)

local key = KEYS[1]
local consumed = tonumber(ARGV[1])
local capacity = tonumber(ARGV[2])
local refill_rate = tonumber(ARGV[3])

-- 1. Get current global state
local state = redis.call('HMGET', key, 'tokens', 'last_updated')
local global_tokens = tonumber(state[1])
local last_updated = tonumber(state[2])

local now = os.time()

if not global_tokens then
    global_tokens = capacity
    last_updated = now
end

-- 2. Apply global time refill
local time_passed = now - last_updated
local generated = time_passed * refill_rate
global_tokens = math.min(capacity, global_tokens + generated)

-- 3. Deduct the entire batch the replica already allowed
global_tokens = global_tokens - consumed

-- If the replica over-allocated tokens because it didn't know other replicas
-- were consuming tokens simultaneously, the balance might dip below zero.
-- We clamp it to 0 so the replica knows the bucket is empty.
if global_tokens < 0 then
    global_tokens = 0
end

-- 4. Save the new global reality back to Redis
redis.call('HMSET', key, 'tokens', global_tokens, 'last_updated', now)

-- 5. Return the new balance back to the replica's background thread
return global_tokens

```

---

## The Interview Trade-Off Analysis

If an interviewer asks you to defend this architecture, you must highlight the **Consistency vs. Performance** trade-off:

* **The Massive Win (Performance):** If your service receives 100,000 requests per second across 10 replicas, Redis only sees **10 requests per second** (1 sync per replica per second). You have effectively reduced database load by $99.99\%$.
* **The Compromise (Accuracy):** This design guarantees **Eventual Consistency**. If `Replica 1` and `Replica 2` both have a local balance of 5 tokens, but the global Redis pool only has 6 tokens left, they might collectively allow 10 requests before their next background synchronization cycle executes. For a DDoS protection framework or an analytics tracker, this slight over-allocation buffer is entirely negligible compared to the massive performance scaling gains.

```text
so in plain english, we reduce redis load by batching every 1 min or 60 seconds. since we have replicas load can go to other replicas as well. so over requests could max happen for 1 min or 60 seconds after which the system will block a user?

By changing the synchronization from real-time to a periodic heartbeat, you create a small time window where the system is intentionally "blind" to what the other replicas are doing.
```