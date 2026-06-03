from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import redis
import os
import time

app = FastAPI()

REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
INSTANCE_NAME = os.getenv("HOSTNAME", "unknown_replica")

# Connect to Redis
r = redis.Redis(host=REDIS_HOST, port=6379, decode_responses=True)

# FIXED WINDOW Configuration constants
LIMIT_PER_WINDOW = 5
WINDOW_SIZE_SECONDS = 60

# # TOKEN BUCKET Configuration constants
# BUCKET_CAPACITY = 5.0
# REFILL_RATE_PER_SECOND = 0.5  # 1 token every 2 seconds
# Token Bucket Configuration constants - Adjusted for manual curl testing
BUCKET_CAPACITY = 10.0
REFILL_RATE_PER_SECOND = 0.1  # 1 token every 10 seconds

class RequestPayload(BaseModel):
    user_id: str
    algorithm: str

@app.post("/request")
def process_request(payload: RequestPayload):

    user_id = payload.user_id
    current_time = time.time()

    # --- ALGORITHM 1: FIXED WINDOW ---
    if payload.algorithm == "fixed_window":                
        
        # Calculate the unique window identifier
        window_id = int(time.time()) // WINDOW_SIZE_SECONDS
        redis_key = f"rl:fixed:{user_id}:{window_id}"
        
        # INCR is atomic in Redis. If the key doesn't exist, it is initialized to 0 and incremented to 1.
        current_count = r.incr(redis_key)
        
        # If it's a brand new key, set a Time-To-Live (TTL) to clean up memory automatically after the window passes
        if current_count == 1:
            r.expire(redis_key, WINDOW_SIZE_SECONDS + 10) # 10 seconds buffer
        
        # Check if the user breached the threshold
        if current_count > LIMIT_PER_WINDOW:
            # Track a global block metric for our /stats endpoint
            r.incr("metric:global_blocked_requests")
            raise HTTPException(
                status_code=429,
                detail=f"Rate limit exceeded! Blocked by {INSTANCE_NAME}. Max {LIMIT_PER_WINDOW} requests/min."
            )
        
        # Track global allowed metrics
        r.incr("metric:global_allowed_requests")
        
        return {
            "status": "ALLOWED",
            "handled_by": INSTANCE_NAME,
            "current_count": current_count,
            "limit": LIMIT_PER_WINDOW,
            "ttl_seconds": r.ttl(redis_key)
        }
    
    # --- ALGORITHM 2: TOKEN BUCKET ---
    elif payload.algorithm == "token_bucket":

        redis_key = f"rl:token_bucket:{user_id}"
        
        # 1. Fetch current bucket state from Redis Hash
        # If it doesn't exist, initialize a full bucket
        state = r.hgetall(redis_key)
        
        if not state:
            current_tokens = BUCKET_CAPACITY
            last_updated = current_time
        else:
            current_tokens = float(state["tokens"])
            last_updated = float(state["last_updated"])
        
        # 2. LAZY REFILL: Calculate how many tokens were generated since the last request
        time_passed = current_time - last_updated
        generated_tokens = time_passed * REFILL_RATE_PER_SECOND
        
        # New balance cannot exceed the maximum bucket capacity
        refilled_tokens = min(BUCKET_CAPACITY, current_tokens + generated_tokens)
        
        # 3. EVALUATE: Do we have at least 1 token to allow this request?
        if refilled_tokens >= 1.0:
            # Deduct 1 token
            new_token_balance = refilled_tokens - 1.0
            
            # Save new state back to the Redis Hash
            r.hset(redis_key, mapping={
                "tokens": new_token_balance,
                "last_updated": current_time
            })
            
            # Set an expiration on the hash so dead users get automatically cleaned up
            r.expire(redis_key, 60)
            
            r.incr("metric:global_allowed_requests")
            return {
                "status": "ALLOWED",
                "handled_by": INSTANCE_NAME,
                "tokens_remaining": round(new_token_balance, 2),
                "refill_applied": round(generated_tokens, 2)
            }
        else:
            # Not enough tokens! Save the calculated refilled state anyway so we don't lose track of time
            r.hset(redis_key, mapping={
                "tokens": refilled_tokens,
                "last_updated": current_time
            })
            r.incr("metric:global_blocked_requests")
            raise HTTPException(
                status_code=429,
                detail=f"Rate limited by {INSTANCE_NAME}! Bucket empty. Tokens: {round(refilled_tokens, 2)}"
            )
    else:
        raise HTTPException(status_code=400, detail="Unsupported algorithm.")    

@app.get("/stats")
def get_stats():
    # Read global counters from Redis
    allowed = int(r.get("metric:global_allowed_requests") or 0)
    blocked = int(r.get("metric:global_blocked_requests") or 0)
    
    # Scan Redis to see how many active window keys exist right now
    active_rate_limit_keys = r.keys("rl:fixed:*")
    
    return {
        "global_allowed_traffic": allowed,
        "global_blocked_traffic": blocked,
        "active_user_windows": len(active_rate_limit_keys),
        "monitored_by_cluster_node": INSTANCE_NAME
    }