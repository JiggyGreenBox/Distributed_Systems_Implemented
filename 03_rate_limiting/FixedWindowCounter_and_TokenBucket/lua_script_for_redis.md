In a system design interview, this is the exact moment you transition from an intermediate engineer to a senior engineer.

When multiple replicas execute a **Read-Modify-Write** sequence on a shared database simultaneously, you hit a classic distributed race condition. If `rate_limiter_1` and `rate_limiter_2` both read the hash simultaneously, they will compute identical state updates based on stale data, and both will allow the traffic, breaching your strict rate limit.

The hint points directly to the industry-standard solution for this problem: **Redis Lua Scripts**.

---

## The Solution: Atomic Execution via Lua

Redis is fundamentally **single-threaded** when executing commands. If you can move your entire token bucket calculation *inside* Redis itself, Redis will execute the entire script as a single, uninterrupted atomic block.

While a Lua script is running on a user's key, no other backend replica can read or write to that key. It completely eliminates the race condition without requiring heavy distributed locks (like Redlock).

---

## Implementing the Atomic Token Bucket

Instead of writing complex python code that pulls data back and forth over the network, we condense the logic into a Lua script string and send it to Redis using the `eval` or `register_script` mechanism.

### 1. The Lua Script Logic

Here is what the Lua script looks like conceptually. It receives the key, the current timestamp, the capacity, and the refill rate as arguments:

```lua
local key = KEYS[1]
local current_time = tonumber(ARGV[1])
local capacity = tonumber(ARGV[2])
local refill_rate = tonumber(ARGV[3])

-- 1. Fetch current bucket state from the Hash
local state = redis.call('HMGET', key, 'tokens', 'last_updated')
local current_tokens = tonumber(state[1])
local last_updated = tonumber(state[2])

-- If the key doesn't exist yet, initialize it full
if not current_tokens then
    current_tokens = capacity
    last_updated = current_time
end

-- 2. Lazy Refill calculation
local time_passed = current_time - last_updated
local generated = time_passed * refill_rate
local refilled_tokens = math.min(capacity, current_tokens + generated)

-- 3. Evaluate the request
if refilled_tokens >= 1.0 then
    local new_balance = refilled_tokens - 1.0
    -- Save atomically
    redis.call('HMSET', key, 'tokens', new_balance, 'last_updated', current_time)
    redis.call('EXPIRE', key, 60) -- Automatically clean up idle users
    return {1, tostring(new_balance)} -- 1 means ALLOWED
else
    -- Bucket is empty, save the current refilled state anyway
    redis.call('HMSET', key, 'tokens', refilled_tokens, 'last_updated', current_time)
    return {0, tostring(refilled_tokens)} -- 0 means BLOCKED
end

```

---

## 2. Integrating Lua into FastAPI (`app/main.py`)

Let’s refactor the `token_bucket` portion of your `process_request` endpoint to run this script. PyRedis makes executing Lua scripts incredibly simple via `r.register_script()`.

Update the token bucket block in your `app/main.py`:

```python
# Define the Lua Script as a Python triple-quoted string
LUA_TOKEN_BUCKET = """
local key = KEYS[1]
local current_time = tonumber(ARGV[1])
local capacity = tonumber(ARGV[2])
local refill_rate = tonumber(ARGV[3])

local state = redis.call('HMGET', key, 'tokens', 'last_updated')
local current_tokens = tonumber(state[1])
local last_updated = tonumber(state[2])

if not current_tokens then
    current_tokens = capacity
    last_updated = current_time
end

local time_passed = current_time - last_updated
local generated = time_passed * refill_rate
local refilled_tokens = math.min(capacity, current_tokens + generated)

if refilled_tokens >= 1.0 then
    local new_balance = refilled_tokens - 1.0
    redis.call('HMSET', key, 'tokens', new_balance, 'last_updated', current_time)
    redis.call('EXPIRE', key, 60)
    return {1, tostring(new_balance)}
else
    redis.call('HMSET', key, 'tokens', refilled_tokens, 'last_updated', current_time)
    return {0, tostring(refilled_tokens)}
end
"""

# Register the script once when the app boots
lua_script = r.register_script(LUA_TOKEN_BUCKET)

@app.post("/request")
def process_request(payload: RequestPayload):
    user_id = payload.user_id
    current_time = time.time()
    
    if payload.algorithm == "fixed_window":
        # ... (keep your existing fixed_window code here)
        pass

    elif payload.algorithm == "token_bucket":
        redis_key = f"rl:token_bucket:{user_id}"
        
        # Execute the script atomically inside Redis
        # Keys go in the first list, normal arguments in the second
        status, tokens_left = lua_script(
            keys=[redis_key], 
            args=[current_time, BUCKET_CAPACITY, REFILL_RATE_PER_SECOND]
        )
        
        if status == 1:
            r.incr("metric:global_allowed_requests")
            return {
                "status": "ALLOWED",
                "handled_by": INSTANCE_NAME,
                "tokens_remaining": round(float(tokens_left), 2)
            }
        else:
            r.incr("metric:global_blocked_requests")
            raise HTTPException(
                status_code=429,
                detail=f"Rate limited! Bucket empty. Tokens remaining: {round(float(tokens_left), 2)}"
            )

```

---

## Why Interviewers Value This Answer

If you explain this implementation details in a design loop, you hit three major talking points:

1. **Reduced Network Overhead:** Instead of making multiple network round trips (`HGETALL` followed by logic followed by `HMSET`), you send exactly **one** network request to Redis. The computation happens directly where the data lives.
2. **True Transactional Isolation:** Because Redis executes Lua sequentially, you guarantee absolute accuracy across thousands of concurrent app instances without dealing with manual database locking protocols.
3. **Optimized Scripts (SHA1 Caching):** Under the hood, `register_script` doesn't send the raw text every time; it sends a small SHA1 hash of the script, keeping payloads incredibly tiny.

Now that your Rate-Limiting sandbox handles both **Fixed Window** and **Atomic Token Bucket**, you have built a complete edge-protection system.

How does it feel running this script over the cluster? Are you ready to see how the final algorithm (**Sliding Window Logs**) uses Redis Sorted Sets to prevent the boundary burst problem completely?