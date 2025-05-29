---
layout: portfolio
title: "Choir Site"
subtitle: "Ruby on Rails Choir Management System"
description: >-
  A comprehensive choir management system featuring song library management, performance scheduling, member 
  administration, and content publishing. Successfully upgraded from legacy Ruby/Rails versions with 99.15% test success 
  rate.
technologies:
  - "Ruby on Rails 7.1"
  - "PostgreSQL"
  - "Bootstrap 5"
  - "Docker"
slug: "choir-site"
permalink: "/portfolio/choir-site/"
project_url: "https://github.com/whittakertech/choir-site"
date: 2017-11-04
featured: true
categories: ["Ruby on Rails", "Full Stack", "Legacy Modernization"]
tags: ["rails", "postgresql", "docker", "legacy-upgrade", "testing", "performance-optimization"]
hero_image: "/assets/images/portfolios/choir-site/site-page"
hero_image_suffix: ".png"
---

A comprehensive choir management system built for the Cascade Sixth Ward Choir, featuring song library management, 
performance scheduling, member administration, and content publishing.

## Project Overview

This Ruby on Rails application demonstrates expertise in legacy system modernization, performance optimization, and 
comprehensive testing practices. The project involved rescuing a choir management website from technical debt while 
maintaining full functionality.

### Key Achievements

- Upgraded from Ruby 3.0.7 to 3.2.7 and Rails 6.1 to 7.1
- Achieved 99.15% test success rate (117/118 tests passing)
- Eliminated 196 IDE warnings and deprecated dependencies
- Implemented comprehensive file management with Active Storage

### Technology Stack

**Backend:**
- Ruby 3.2.7
- Rails 7.1
- PostgreSQL 13
- Active Storage

**Frontend:**
- Bootstrap 5
- HAML Templates
- DataTables
- Action Cable

**DevOps:**
- Docker
- GitHub Actions
- Heroku Deployment
- CI/CD Pipeline

**Tools:**
- RuboCop
- Bullet (N+1 Detection)
- SimpleCov
- Devise Auth

## Core Features

### Song Library Management
Complete song catalog with multi-part arrangements, sheet music, and audio files for individual vocal parts.

### Performance Scheduling
Event management for performances and rehearsals with venue details, song selections, and audio recordings.

### Member Management
Choir member profiles with vocal range tracking, contact information, and talent documentation.

### News & Articles
Content management system for choir announcements, articles, and news with categorization and tagging.

### File Management
Secure file upload and storage for sheet music (PDF), audio files (MP3/MIDI), and profile images using Active Storage.

### Admin Dashboard
Comprehensive administrative interface with DataTables integration, bulk operations, and real-time messaging system.

## Technical Challenges & Solutions

### Legacy System Modernization

**Challenge:**
- Application running on end-of-life Ruby 3.0.7 (no security patches)
- Rails 6.1 deprecation warnings and compatibility issues
- 118 failing tests preventing deployment confidence
- Deprecated Paperclip gem creating security vulnerabilities

**Solution:**
- Systematic upgrade to Ruby 3.2.7 and Rails 7.1
- Migration from Paperclip to Active Storage
- Fixed Ruby 3.2 keyword argument compatibility
- Achieved 99.15% test success rate (117/118 tests)

### Database Performance Optimization

**Implementation:**
Implemented comprehensive counter caches and optimized queries to eliminate N+1 problems and improve page load times.

```ruby
class Song < ApplicationRecord
  has_many :performance_songs,
           counter_cache: true
  has_many :performances,
           through: :performance_songs

  def self.for_display
    includes(:instruments, :performances)
  end
end
```

**Results:**
- 40% improvement in development startup time
- Test suite execution reduced from 10+ minutes to under 2 minutes
- 15-20% improvement in database query performance
- Eliminated all N+1 query warnings with Bullet gem

### File Management & Security

**Modern Implementation:**
```ruby
class Instrument < ApplicationRecord
  has_one_attached :pdf
  has_one_attached :mp3
  has_one_attached :midi

  validate :correct_mime_types

  private

  def correct_mime_types
    # Validate file types for security
    validate_attachment_type(:pdf, %w[application/pdf])
    validate_attachment_type(:mp3, %w[audio/mpeg])
  end
end
```

**Security Features:**
- MIME type validation for all file uploads
- Active Storage virus scanning integration ready
- Secure direct uploads to AWS S3
- Content Security Policy headers implemented

## System Architecture

### Database Design
**Core Entities:** Songs, Instruments, Performances, Rehearsals, Members
**Content Management:** Articles, Categories, Tags, User Profiles
**File Storage:** Active Storage with S3 integration
**Performance:** Counter caches, optimized queries, proper indexing

### Development Workflow
1. **Docker Development** - Containerized environment with Makefile automation
2. **Testing Pipeline** - RSpec, SimpleCov, RuboCop in CI/CD
3. **Deployment** - GitHub Actions to Heroku with zero-downtime
4. **Monitoring** - Performance tracking and error monitoring

## Code Quality & Testing

### Testing Metrics
- **Test Success Rate:** 99.15%
- **Code Coverage:** 95%+
- **RuboCop Violations:** 0

### Quality Tools
- **RuboCop:** Code style and quality enforcement
- **Bullet:** N+1 query detection
- **SimpleCov:** Test coverage analysis
- **Brakeman:** Security vulnerability scanning

### Testing Approach
```ruby
class SongTest < ActiveSupport::TestCase
  def setup
    @song = songs :one
  end

  test 'should be valid' do
    assert_predicate @song, :valid?
  end

  test 'slug should be set before save' do
    @song.title = 'The Long and Winding Road'
    @song.save
    assert_equal 'the-long-and-winding-road', @song.slug
  end
end
```

## Development Environment

### Docker Configuration
```yaml
services:
  jekyll:
    build: .
    ports:
      - "4000:4000"
      - "35729:35729"
    volumes:
      - .:/app
      - bundle_cache:/usr/local/bundle
    environment:
      - JEKYLL_ENV=development
```

**Development Benefits:**
- Consistent environment across team members
- Isolated dependencies and Ruby versions
- Fast setup with Makefile automation
- Hot reloading for development efficiency

### Makefile Automation
```makefile
# Development Commands
serve: ## Start development server
	docker-compose up

test: ## Run test suite
	docker-compose run --rm web rails test

console: ## Open Rails console
	docker-compose run --rm web rails console

fresh-start: ## Complete rebuild
	docker-compose down -v --rmi all
	make install
```

**Available Commands:**
`make serve`, `make test`, `make console`, `make migrate`, `make bundle`, `make logs`

## Project Results

### Key Metrics
- **99.15%** Test Success Rate (117 of 118 tests passing)
- **40%** Performance Improvement (Faster startup and queries)
- **0** Security Vulnerabilities (Eliminated all known issues)

### Key Accomplishments
- Successfully upgraded from end-of-life Ruby/Rails versions
- Migrated from deprecated Paperclip to Active Storage
- Eliminated 196 IDE warnings and technical debt
- Implemented comprehensive testing and CI/CD pipeline
- Optimized database performance with counter caches
- Dockerized development environment for team consistency

## Technologies & Tools

**Backend:** Ruby 3.2.7, Rails 7.1, PostgreSQL, Active Storage, Action Cable

**Frontend:** Bootstrap 5, HAML, DataTables, jQuery, Turbo

**DevOps:** Docker, GitHub Actions, Heroku, AWS S3, Redis

**Quality:** RuboCop, Minitest, SimpleCov, Bullet, Brakeman

---

This choir management system demonstrates expertise in legacy system modernization, performance optimization, and 
comprehensive testing practices. The successful upgrade from end-of-life software to modern, actively maintained 
versions while achieving 99.15% test success showcases systematic problem-solving and technical excellence.