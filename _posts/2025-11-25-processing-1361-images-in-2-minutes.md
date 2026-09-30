---
layout: post
date: 2025-11-25 09:00:00 -0600
title: "Processing 1,361 Images in 2 Minutes: How We Transformed a Rails Bottleneck into an Asynchronous Pipeline"
card_title: "1,361 Images in 2 Minutes"
slug: "processing-1361-images-in-2-minutes"
canonical_url: "https://whittakertech.com/blog/processing-1361-images-in-2-minutes/"
description: >-
  How we rebuilt a legacy synchronous Paperclip + S3 image pipeline into a fully asynchronous architecture—cutting
  processing time from 11 hours to 2 minutes without scaling dynos or increasing infrastructure costs.
og_title: "Rails Image Processing at Scale: 11 Hours Cut to 2 Minutes"
image_key: "processing-photos"
headline: >-
  Processing 1,361 Images in 2 Minutes: The Architectural Shift That Turned a Slow Rails Pipeline into a High-Throughput,
  Asynchronous System
categories: ["Ruby on Rails", "Performance Engineering", "Async Architecture"]
tags: ["Rails", "Paperclip", "AWS S3", "Sidekiq", "Performance", "Architecture", "Image Processing", "Concurrency",
       "Async Pipelines", "DevOps", "Heroku", "Optimization"]
---

For years, a single architectural flaw quietly haunted one of our legacy Rails systems: **every uploaded image was being downloaded, decoded, processed, and saved inside the web dyno**. That meant every S3 fetch, every Paperclip decode, every write—even for 30MB images—ran *synchronously* in a request cycle.

The result?

- 10–30 second request times  
- Web dyno memory spiking beyond 4GB  
- H12 timeouts  
- Throughput collapsing under moderate load  
- Workers idle while the web tier melted  

And when a photographer uploaded **1,361 images**?

It took *between four hours and eleven hours* depending on image size.

This was unacceptable.

What follows is the story of how we turned a fragile, synchronous pipeline into a **fully asynchronous, high-throughput image ingestion system**—with a single architectural insight and one deceptively simple API option in the AWS SDK.

---

## 🚨 The Bottleneck: Paperclip + S3 + Rails Requests

Photographers uploaded images directly to S3 using presigned URLs. Good.  
But then the browser told Rails:

> “Okay, I uploaded it. Now fetch it, decode it, store it, generate styles, watermark it, and save everything.”

And the controller dutifully did exactly that.

That meant the web dyno:

- downloaded every image from S3  
- read it into memory  
- passed raw binary to Paperclip  
- triggered style generation  
- wrote out processed images  
- updated ActiveRecord  
- cleaned up the temporary S3 key  

Every. Single. Time.

Under load, this created a perfect storm of CPU spikes, RAM thrash, request backpressure, connection exhaustion, and timeouts.

It wasn’t a Rails problem.  
It was an architectural problem.

---

## 💡 The Breakthrough: *Stop Processing in the Request Cycle*

We realized something obvious in hindsight:

> **Uploading a file does not require processing a file.**

So we redesigned the pipeline:

1. Browser uploads directly to S3  
2. Browser notifies Rails  
3. Rails enqueues a Sidekiq job  
4. The worker handles *all processing*  
5. The controller immediately returns `202 Accepted`

That single change removed *all heavy lifting* from the web tier.

Requests dropped from 30 seconds to ~40 milliseconds.

But we weren’t done yet.

---

## ⚙️ The Hidden Gotcha: Paperclip Cannot Ingest Raw Binary

Our worker downloaded files from S3 like this:

```ruby
resp = Aws::S3::Client.new.get_object(...)
gi.image = resp.body.read
```

This seemed harmless.

Then Paperclip exploded:

```
Paperclip::AdapterRegistry::NoHandlerError:
No handler found for "\x89PNG\r\n..."
```

Why? Because Paperclip expects something “file-like.”  
Raw binary strings are not that.

We tried `StringIO`.  
We tried stubbing `original_filename`.  
We tried custom adapters.

Nothing worked cleanly.

And then—just a bit quietly—something clicked.

---

## 🌟 The Technical Revelation: `response_target:`  

AWS SDK has a parameter that saves the S3 object *directly to disk*, bypassing memory entirely:

```ruby
get(response_target: "/tmp/#{file_name}")
```

No buffering.  
No streaming into Ruby.  
No giant byte arrays.

Just: download → write file → done.

So we changed the worker:

```ruby
def self.new_from_url(parameters)
  s3 = Aws::S3::Resource.new
  temp_path = "/tmp/#{parameters['file_name']}"

  # Stream file straight to disk
  s3.bucket(Rails.application.secrets.s3_bucket_name)
    .object(parameters['path'])
    .get(response_target: temp_path)

  gi = find_or_initialize_by(image_file_name: parameters['file_name'])
  gi.is_update = gi.persisted?
  gi.image = File.open(temp_path)              # Proper file-like object
  gi.event_id = parameters['event_id']
  gi.s3_key_to_delete = parameters['path']     # Clean up original only if updating
  gi
end
```

That was the moment the system unlocked.

Paperclip accepted the file instantly.  
Memory usage plummeted.  
Workers processed images sequentially, predictably, and without thrash.

---

## 🗑️ Smart Cleanup: Delete Old S3 Keys Only for Updates

We added a simple rule:

- **If a new image replaces an existing one**, delete the old S3 object after save  
- **If it’s the first upload**, do nothing

```ruby
after_save :delete_from_s3, if: -> { is_update && s3_key_to_delete.present? }

def delete_from_s3
  Aws::S3::Client.new.delete_object(
    bucket: Rails.application.secrets.s3_bucket_name,
    key: s3_key_to_delete
  )
end
```

That kept S3 tidy without risking premature deletion.

---

## 📈 The Results: 300× Faster, 80% Less Memory, 100% Uptime

After deploying the asynchronous pipeline with direct-to-disk S3 ingestion, our metrics changed dramatically.

| Metric | Before | After |
|-------|--------|-------|
| **Full gallery upload (1,361 images)** | 4–11.3 hours | **~2 minutes** |
| **Throughput (sustained)** | ~11 images/hour | **~11 images/second** |
| **Median response time** | 5–30 seconds | **41–80 ms** |
| **Web dyno memory** | ~4GB (over limit) | **600–700MB** |
| **Failure rate** | Frequent timeouts | **Near-zero** |

No extra dynos.  
No new infrastructure.  
Just architecture.

This is the kind of improvement that feels almost unfair—like we found a secret lever someone hid in the server room.

---

## 🚀 What Makes This Work

### 1. **Requests stay light**
Controllers only enqueue jobs, never process files.

### 2. **Workers do the heavy lifting**
Sidekiq concurrency is predictable and tunable.

### 3. **Direct-to-disk downloading** avoids giant memory spikes
No more multi-megabyte Ruby strings thrashing the garbage collector.

### 4. **Paperclip receives actual file objects**
Exactly what it expects—no adapters, no hacks.

### 5. **S3 is used correctly**
Upload → confirm → worker handles everything.

The whole system feels calmer now.  
Rails applications like calm.

---

## 🧭 Lessons for Any Engineering Team

If you’re handling large uploads—or lots of them—and your web tier is showing memory pressure or timeouts during upload peaks, remember:

- File processing doesn’t belong in web requests  
- Paperclip, CarrierWave, ActiveStorage all expect file-like objects  
- S3’s `response_target:` can save you gigabytes of RAM  
- Background workers should orchestrate the workflow  
- Cleanup should be deferred until after successful processing  
- Asynchronous design wins—always

This wasn’t a cosmetic optimization.  
It was a fundamental architectural realignment.

And it turned a creaking, fragile subsystem into something robust, scalable, and *fast*.

That’s engineering.  
That’s architecture.  
That’s WhittakerTech.
