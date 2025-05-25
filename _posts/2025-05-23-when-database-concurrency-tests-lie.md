---
layout: post
date: 2025-05-23 10:00:00 -0600
title: "Database Concurrency Tests: Fix PostgreSQL Race Conditions"
slug: "when-database-concurrency-tests-lie"
canonical_url: "https://whittakertech.com/blog/when-database-concurrency-tests-lie/"
description: >-
  Debug PostgreSQL concurrency issues where RSpec tests pass but database logic fails. Real case study with FOR UPDATE
  SKIP LOCKED and thread synchronization solutions.
og_title: "When RSpec Tests Pass But Your Database Logic Fails"
headline: >-
  When Database Concurrency Tests Lie: How Passing RSpec Tests Hid Critical Race Conditions in a High-Stakes Legal
  System
categories: ["Ruby on Rails", "Software Development", "Database Architecture"]
tags: ["Database concurrency", "PostgreSQL locking", "Race conditions", "RSpec testing", "FOR UPDATE SKIP LOCKED",
       "Thread synchronization", "Test reliability", "ActiveRecord", "Database transactions", "Production debugging",
       "Critical systems", "Queue management", "Polymorphic associations", "CI/CD pipeline", "Test-driven development"]
---

*How we exposed a dangerous scenario where comprehensive RSpec tests consistently passed while critical task assignment
logic silently failed, preventing double-bookings in a high-stakes hearing scheduling system.*

## The Challenge

Picture this scenario: A legal firm's hearing scheduling system processes hundreds of weekly hearings across multiple
jurisdictions. Multiple court clerks simultaneously assign hearing tasks from a shared queue, and the system must
absolutely prevent the same hearing from being double-booked to different judges or courtrooms. When concurrency
controls fail in legal proceedings, double-booked hearings can delay justice for months and cost firms thousands in
rescheduling fees, expert witness re-coordination, and client relationship damage.

The development team had built what appeared to be a robust solution using PostgreSQL's `FOR UPDATE SKIP LOCKED`
mechanism—a row-level locking feature that allows one transaction to skip records already locked by another, preventing
deadlocks while ensuring exclusive access. Their comprehensive RSpec test suite consistently passed, validating that
concurrent assignment attempts would never assign the same task to multiple users.

But there was a critical flaw hiding in plain sight: the tests were giving false confidence while the actual assignment
logic was completely broken. Tasks weren't being assigned at all, despite the method returning `success: true`. This
created the most dangerous scenario in software development—broken code protected by passing tests, ready to fail
spectacularly in production.

## The Obstacles

### Test Design Assumptions

The original test made a fundamental assumption about how ActiveRecord collections behave across threads. The developers
assumed that after modifying tasks in separate threads, querying the original `unassigned_tasks` collection would
reflect the database changes:

```ruby
# The misleading test approach
it "prevents double assignment under concurrency" do
  unassigned_tasks = Task.where(id: unassigned_queue_tasks.pluck(:task_id))
  
  # Threads modify tasks here...
  thread1.join
  thread2.join
  
  # This checks stale in-memory data, not actual database state
  expect(unassigned_tasks.pluck(:assigned_to_id).uniq).to eq([assigned_to.id])
end
```

ActiveRecord collections don't automatically refresh when the underlying database records change in separate
connections. The test was checking stale, in-memory data rather than the actual post-operation database state, creating
an illusion of correctness while the real functionality remained untested.

### Silent Success Reporting

The assignment method reported success based solely on whether exceptions occurred, not whether any meaningful work was
performed:

```ruby
# The silent failure method
def self.assign_to_user(to, by, count)
  error_message = nil
  begin
    transaction do
      available_for_assignment(count)
        .lock("FOR UPDATE SKIP LOCKED")
        .each do |task|
          task.update!(assigned_to: to, 
                       assigned_by: by, 
                       assigned_at: Time.zone.now)
        end
    end
  rescue StandardError => error
    error_message = error.message
  end
  error_message.nil? ? { success: true } : { success: false, error: error_message }
end
```

When no tasks were available for assignment, this method would complete its empty loop without errors and confidently
return `{ success: true }`. The calling code had no way to distinguish between "successfully assigned 5 tasks" and
"successfully assigned 0 tasks because none were available."

### Complex Data Dependencies

The task assignment relied on a sophisticated chain of database relationships and scopes. A single missing link would
result in zero tasks being found, but the failure was completely silent:

```ruby
# The complex query chain that could silently break
def self.available_for_assignment(count)
  where(id: QueueEntry.schedulable_task_ids(count))
end

def self.schedulable_task_ids(bount)
  schedulable.limit(count.clamp(1, 30)).pluck(:task_id)
end

scope :schedulable, -> { unassigned.where(schedulable: true) }
scope :unassigned, -> { where(task_status: STATUSES.unassigned) }
```

If tasks weren't properly set up with corresponding `QueueEntry` records, or if they had the wrong status or type, the
entire assignment process would find nothing to work with. The method would report success while accomplishing nothing.

### Thread Synchronization Complexity

Testing concurrent database operations requires precise coordination between threads. The original approach used simple
timing assumptions that created unpredictable test behavior:

```ruby
# Brittle thread coordination
thread2 = Thread.new do
  sleep 0.1  # Hope thread1 starts first
  controller.send(:assign_tasks, assigned_to_2, 5, current_user)
end
```

This approach fails under different timing conditions—high system load, slower CI environments, or even minor Ruby VM
scheduling differences could cause threads to execute in unexpected orders, leading to intermittent test failures that
developers would dismiss as "flaky tests."

### Database Transaction Isolation

The interaction between Rails' connection pooling, PostgreSQL's transaction isolation levels, and row-level locking
created subtle edge cases. Without explicit connection management, threads might share connections inappropriately,
or isolation levels might prevent threads from seeing each other's work in ways that masked real concurrency issues.

## Our Approach

We developed a systematic debugging methodology that transforms opaque concurrency failures into clear, actionable
insights.

### Data Flow Verification

Instead of assuming test data meets method requirements, we implemented explicit verification at each step of the data
pipeline:

```ruby
# Explicit verification approach
it "debugs the complete assignment pipeline" do
  # Verify test data setup
  unassigned_tasks = Task.where(id: unassigned_queue.pluck(:task_id))
  task_ids = unassigned_tasks.pluck(:id)
  expect(task_ids.count).to eq(5)
  
  # Verify the assignment method can actually find these tasks
  available_task_ids = HearingTask.available_for_assignment(5).pluck(:id)
  expect(available_task_ids).to match_array(task_ids)
  
  # Now test with confidence that data flows correctly
end
```

This approach immediately revealed that test fixtures weren't creating the required `QueueEntry` records, causing
`available_for_assignment` to return empty results despite having tasks in the database.

### Thread-Safe Test Architecture

We replaced brittle timing-based synchronization with mutex-controlled coordination:

```ruby
# Deterministic thread synchronization
it "prevents double assignment with proper coordination" do
  mutex = Mutex.new
  thread1_started = false
  
  thread1 = Thread.new do
    ActiveRecord::Base.connection_pool.with_connection do
      mutex.synchronize { thread1_started = true }
      controller.send(:assign_tasks, assigned_to, 5, current_user)
    end
  end
  
  thread2 = Thread.new do
    ActiveRecord::Base.connection_pool.with_connection do
      # Wait until thread1 has definitely started
      mutex.synchronize { sleep 0.01 until thread1_started }
      controller.send(:assign_tasks, assigned_to_2, 5, current_user)
    end
  end
  
  thread1.join
  thread2.join
  # Verify results by querying fresh data from database...
end
```

This ensures consistent thread execution order regardless of system conditions while properly managing database
connections across threads.

### Database State Inspection

We added comprehensive logging that traces data state throughout the entire assignment process:

```ruby
# Enhanced assignment method with state tracking
def self.assign_to_user_with_debug(to, by, count)
  pre_tasks = available_for_assignment(count).to_a
  updates_performed = 0
  
  transaction do
    locked_tasks = available_for_assignment(count).lock("FOR UPDATE SKIP LOCKED").to_a
    
    locked_tasks.each do |task|
      task.update!(assigned_to: to, assigned_by: by, assigned_at: Time.zone.now)
      updates_performed += 1
    end
    
    # Verify changes are visible within transaction
    in_tx_state = Task.where(id: locked_tasks.map(&:id)).reload
  end
  
  { success: true, tasks_found: pre_tasks.count, updates_performed: updates_performed }
end
```

This revealed exactly where the pipeline was breaking—no tasks were being found by `available_for_assignment`, leading
to empty update loops that still reported success.

### Multi-Level Result Validation

Instead of relying solely on method return values, we implemented validation at multiple application layers:

```ruby
# Comprehensive result validation
it "validates assignment at all levels" do
  # Database level: Query fresh data after operations
  updated_tasks = Task.where(id: task_ids).reload
  
  # ActiveRecord level: Check object states
  user1_task_count = updated_tasks.count { |t| 
    t.assigned_to_id == assigned_to.id && t.assigned_to_type == assigned_to.class.name 
  }
  
  # Business logic level: Verify method responses
  expect(thread1_result).to include("success" => true)
  expect(thread2_result).to include("success" => true)
  
  # Integration level: Confirm end-to-end behavior
  expect(user1_task_count).to eq(5)
  expect(user2_task_count).to eq(0)
end
```

## Code Transformation Examples

### Example A: From Misleading to Reliable Concurrency Testing

```ruby
# Before: Misleading test that checks stale data
it "prevents double assignment" do
  unassigned_tasks = Task.where(id: unassigned_queue.pluck(:task_id))
  
  thread1 = Thread.new { controller.send(:assign_tasks, user1, 5, current_user) }
  thread2 = Thread.new { 
    sleep 0.1
    controller.send(:assign_tasks, user2, 5, current_user) 
  }
  
  thread1.join
  thread2.join
  
  # This checks in-memory data, not database reality
  expect(unassigned_tasks.pluck(:assigned_to_id).uniq).to eq([user1.id])
end

# After: Reliable test with proper data verification
it "prevents double assignment with database verification" do
  # Verify data pipeline before testing
  task_ids = unassigned_queue.pluck(:task_id)
  available_ids = HearingTask.available_for_assignment(5).pluck(:id)
  expect(available_ids).to match_array(task_ids)
  
  # Coordinated thread execution
  mutex = Mutex.new
  thread1_started = false
  
  thread1 = Thread.new do
    ActiveRecord::Base.connection_pool.with_connection do
      mutex.synchronize { thread1_started = true }
      controller.send(:assign_tasks, user1, 5, current_user)
    end
  end
  
  thread2 = Thread.new do
    ActiveRecord::Base.connection_pool.with_connection do
      mutex.synchronize { sleep 0.01 until thread1_started }
      controller.send(:assign_tasks, user2, 5, current_user)
    end
  end
  
  thread1.join
  thread2.join
  
  # Query fresh database state
  final_tasks = Task.where(id: task_ids).reload
  user1_assignments = final_tasks.select { |t| t.assigned_to_id == user1.id }
  user2_assignments = final_tasks.select { |t| t.assigned_to_id == user2.id }
  
  expect(user1_assignments.count).to eq(5)
  expect(user2_assignments.count).to eq(0)
end
```

### Example B: From Silent Failure to Explicit Success Reporting

```ruby
# Before: Silent failure with misleading success reporting
def self.assign_to_user(to, by, count)
  error_message = nil
  begin
    transaction do
      available_for_assignment(count)
        .lock("FOR UPDATE SKIP LOCKED")
        .each { |task| task.update!(assigned_to: to,
                                    assigned_by: by,
                                    assigned_at: Time.zone.now) }
    end
  rescue StandardError => error
    error_message = error.message
  end
  error_message.nil? ? { success: true } : { success: false, error: error_message }
end

# After: Explicit validation with meaningful success reporting
def self.assign_to_user(to, by, count)
  tasks_assigned = 0
  error_message = nil
  
  begin
    transaction do
      available_tasks = available_for_assignment(count).lock("FOR UPDATE SKIP LOCKED")
      
      available_tasks.each do |task|
        task.update!(assigned_to: to, assigned_by: by, assigned_at: Time.zone.now)
        tasks_assigned += 1
      end
    end
  rescue StandardError => error
    error_message = error.message
    Rails.logger.error("Task assignment failed: #{error.message}")
  end
  
  if error_message
    { success: false, error: error_message, tasks_assigned: 0 }
  else
    { success: true, tasks_assigned: tasks_assigned, requested: count }
  end
end
```

### Example C: From Broken Data Pipeline to Verified Query Chain

```ruby
# Before: Unverified query chain that could silently return empty
def self.available_for_assignment(count)
  where(id: QueueEntry.schedulable_task_ids(count))
end

# The problem: If QueueEntry records don't exist, this returns []
# But the calling code has no way to know why

# After: Query chain with explicit validation and debugging support
def self.available_for_assignment(count)
  entry_ids = QueueEntry.schedulable_task_ids(count)
  
  if Rails.env.test? && entry_ids.empty?
    Rails.logger.warn("No schedulable QueueEntry records found. Check test data setup.")
  end
  
  available_tasks = where(id: entry_ids)
  
  if Rails.env.test? && available_tasks.count != entry_ids.count
    missing_ids = entry_ids - available_tasks.pluck(:id)
    Rails.logger.warn("Missing tasks for entry IDs: #{missing_ids}. Check task creation and relationships.")
  end
  
  available_tasks
end

# Supporting change: Enhance test data creation to ensure complete relationships
def create_assignable_hearing_tasks(count)
  tasks = create_list(:hearing_task, count,
    task_status: STATUSES.unassigned
  )
  
  # Ensure QueueEntry records exist
  tasks.each do |task|
    create(:queue_entry,
      task: task,
      task_id: task.id,
      schedulable: true
    )
  end
  
  tasks
end
```

## The Results

Our systematic debugging approach immediately revealed the root cause and delivered measurable improvements across
multiple dimensions.

### Immediate Impact

Within hours of implementing our debugging framework, the team identified that their test fixtures weren't creating the
required `QueueEntry` records that the assignment logic depended on. The `available_for_assignment` method was
consistently returning empty collections, causing assignment operations to complete successfully without performing any
work. This explained why tests passed (no exceptions occurred) while no actual assignments happened.

### Improved Test Reliability

The new thread synchronization approach eliminated unpredictable test behavior caused by timing assumptions. Tests now
execute deterministically regardless of system load or CI environment variations, providing consistent feedback to
developers about actual system behavior rather than environmental conditions.

### Production Safety

By implementing proper database state verification, the team caught multiple additional edge cases where assignment
logic could silently fail. The enhanced error reporting now distinguishes between "no tasks available" and "assignment
failed," preventing scenarios where operators would assume successful assignment when no work was actually performed.

### Developer Productivity

The comprehensive debugging framework dramatically reduced troubleshooting time for similar concurrency issues.
Developers can now quickly identify whether problems stem from test data setup, query logic, transaction behavior,
or thread coordination, rather than spending days debugging mysterious failures.

The enhanced method responses now include meaningful metrics (`tasks_assigned`, `requested`, `available_count`),
enabling calling code to make informed decisions about system behavior and alerting operators to potential issues
before they impact production workflows.

## Key Principles

Our experience solving this critical concurrency testing mystery revealed several fundamental principles that apply
to any system handling concurrent operations:

**1. Test What You Think You're Testing**: Verify that your tests actually exercise the code paths and data states you
believe they do. ActiveRecord collections, caching layers, and connection pooling can create illusions of correctness
when tests check stale or incorrect data.

**2. Verify Data Pipeline Assumptions**: Complex query chains with multiple scopes and relationships can silently break
when any component returns unexpected results. Implement explicit verification at each stage to catch pipeline failures
early.

**3. Synchronize Threads, Don't Race Them**: Use explicit coordination mechanisms like mutexes rather than timing
assumptions. Deterministic thread execution makes tests reliable and debugging tractable.

**4. Report Meaningful Success**: Distinguish between "completed without errors" and "accomplished the intended work."
Methods should report what they actually did, not just whether exceptions occurred.

**5. Validate at Multiple Levels**: Check results at the database level, ActiveRecord level, and business logic level.
Each layer can mask failures in others, and comprehensive validation catches issues that single-point checks miss.

**6. Make Failures Visible**: Silent failures are the most dangerous kind. Implement logging, metrics, and explicit
validation that surface issues before they impact production operations.

When database concurrency controls protect critical business processes, comprehensive testing isn't just about code
quality—it's about operational reliability and business continuity. The techniques we've outlined transform mysterious
concurrency failures into debuggable, fixable problems, ensuring that your tests provide genuine confidence in your
system's ability to handle real-world concurrent operations.
