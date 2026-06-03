## The 5 Types of Rate Limiting Algorithms

### 1. Token Bucket

* **How it works:** A bucket holds a maximum number of tokens. Tokens are added back at a constant, predictable rate. Every incoming request takes a token. If the bucket is empty, the request is dropped.
* **Pros:** Allows for **short bursts of traffic** (if the bucket is full, a sudden rush of requests goes through immediately). Very memory efficient.
* **Cons:** Can be tricky to tune the combination of bucket size and refill rate.
* **Who uses it:** AWS API Gateway, Stripe.

### 2. Leaky Bucket

* **How it works:** Imagine a bucket with a small hole at the bottom. Requests are poured into the bucket at any speed, but they leak out of the bottom at a strict, constant rate to be processed by your backend. If the bucket overflows, new requests are rejected.
* **Pros:** Smooths out traffic spikes. It guarantees a **strictly stable request rate** to your core servers/databases.
* **Cons:** If a sudden burst of legitimate traffic arrives, requests sit in the bucket waiting to leak out, which introduces latency for the user.
* **Who uses it:** NGINX (the `limit_req` module uses this variant), Shopify.

### 3. Fixed Window Counter

* **How it works:** This is the one we built first. You divide time into fixed blocks (e.g., 12:00 to 12:01). You count requests in that block. When the clock hits 12:01, the counter completely resets to 0.
* **Pros:** Extremely simple to implement and very low memory footprint.
* **Cons:** **The Boundary Burst problem.** If a user dumps their entire limit at 11:59:59 and another full limit at 12:00:01, they successfully double-pump your servers in a two-second window.

### 4. Sliding Window Logs

* **How it works:** To fix the boundary burst problem, this algorithm logs the *exact timestamp* of every single request a user makes (usually in a sorted set in Redis). When a new request comes in, the system scans backward exactly 60 seconds from the current millisecond, counts the logs, and decides to allow or deny.
* **Pros:** **Perfectly accurate.** There are zero boundary burst loopholes.
* **Cons:** **Memory hog.** If a user is allowed 10,000 requests per hour, you have to store 10,000 timestamps in memory for that single user. It scales terribly under massive traffic.

### 5. Sliding Window Counter

* **How it works:** A hybrid approach that combines the memory efficiency of Fixed Window with the accuracy of Sliding Logs. It looks at the counter of the *current* window and the counter of the *previous* window, then calculates a weighted average based on how far along you are in the current timeline.
* **Pros:** Prevents boundary bursts but only requires storing two numbers per user (incredibly memory efficient).
* **Cons:** It assumes traffic in the previous window was evenly distributed, so it is a close *approximation* of a sliding window, not 100% mathematically exact.
* **Who uses it:** Cloudflare.

---

## Summary of Trade-offs for Interviews

When an interviewer asks you which one to pick, you can stand out by presenting this quick mental matrix:

| Algorithm | Memory Usage | Handles Bursts? | Accuracy | Good For... |
| --- | --- | --- | --- | --- |
| **Token Bucket** | Low | Yes | High | General APIs, SaaS endpoints |
| **Leaky Bucket** | Low | No | High | Protecting fragile background processors/DBs |
| **Fixed Window** | Extremely Low | Yes (Too much) | Low | Quick, low-stakes endpoints |
| **Sliding Log** | High | No | Perfect | Low-traffic, high-security endpoints |
| **Sliding Counter** | Low | No | Good | Large-scale edge protection (CDN level) |

---

---

# 1. Fixed Window Counter

Simplest approach.

Example:

```text
100 requests per minute
```

Store:

```text
user123 -> count
```

When the minute changes:

```text
count = 0
```

---

### Advantages

* Easy
* Fast
* Little memory

### Problems

Boundary issue:

```text
12:00:59 -> 100 requests
12:01:00 -> 100 requests
```

User effectively sends:

```text
200 requests in 2 seconds
```

---

# 2. Sliding Log

Store every request timestamp.

Example:

```text
10:00:01
10:00:03
10:00:07
10:00:09
...
```

For a new request:

```text
remove timestamps older than 60 sec
count remaining
```

---

### Advantages

Very accurate.

### Problems

Memory-heavy.

If a user sends:

```text
100k requests
```

you may store:

```text
100k timestamps
```

Not ideal.

---

# 3. Sliding Window Counter

Hybrid approach.

Instead of storing every request:

Store:

```text
current window count
previous window count
```

Then interpolate.

---

### Advantages

* Accurate enough
* Low memory

### Problems

Slightly more complex

---

This is commonly used in production.

---

# 4. Token Bucket

The one we discussed.

```text
Bucket size = burst capacity
Refill rate = sustained throughput
```

---

### Advantages

* Allows bursts
* Easy
* Efficient
* Widely used

---

Very common in:

* APIs
* gateways
* cloud services

---

# 5. Leaky Bucket

Imagine:

```text
Incoming requests
       ↓
   Bucket
       ↓
Constant output rate
```

Example:

```text
1000 requests arrive instantly
```

Output:

```text
10/sec
10/sec
10/sec
```

---

### Advantages

Smooth traffic

### Problems

Less burst-friendly

---

Used heavily in networking.

---

# For Interviews

Honestly:

| Algorithm      | Importance |
| -------------- | ---------- |
| Fixed Window   | High       |
| Sliding Window | Very High  |
| Token Bucket   | Very High  |
| Leaky Bucket   | Medium     |
| Sliding Log    | Medium     |

Those five cover most discussions.

---

# What Companies Actually Use

Real systems often use:

### API Gateways

* Token Bucket
* Sliding Window

Examples:

* Cloudflare
* Stripe
* Amazon

---

### Network Equipment

* Leaky Bucket
* Token Bucket

---

### Distributed Systems

Often:

* Redis-backed token bucket
* Redis-backed sliding window

---

# A Great Learning Project

Build a rate-limiter service.

```text
NGINX
  ↓
Backend Replica 1
Backend Replica 2
Backend Replica 3
  ↓
Redis
```

Endpoints:

```text
POST /request
GET /stats
```

Implement:

Version 1:

* Fixed Window

Version 2:

* Sliding Log

Version 3:

* Sliding Window

Version 4:

* Token Bucket

Version 5:

* Leaky Bucket

Then benchmark them.

---
