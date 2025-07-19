# Fix Database Migration in Render Shell

## The Problem
The shell isn't using your DATABASE_URL environment variable properly.

## Solution 1: Use DATABASE_URL Directly

In Render Shell, run:
```bash
DATABASE_URL=$DATABASE_URL bundle exec rails db:migrate
```

## Solution 2: Check Environment First

1. First, verify DATABASE_URL is set:
```bash
echo $DATABASE_URL
```

If it's empty, you need to:
1. Go to Render Dashboard → Your database
2. Copy the "Internal Database URL"
3. In shell, run:
```bash
export DATABASE_URL="postgresql://username:password@host:port/database"
bundle exec rails db:migrate
```

## Solution 3: Run Migration via Rails Console

```bash
bundle exec rails console
```

Then in console:
```ruby
ActiveRecord::Base.connection.execute("SELECT 1") # Test connection
ActiveRecord::Migration.verbose = true
ActiveRecord::MigrationContext.new("db/migrate").migrate
```

## Solution 4: Use Rails Runner

```bash
bundle exec rails runner "ActiveRecord::Base.connection.migration_context.migrate"
```

## If All Else Fails: Manual Migration

Since it's just adding a column, you can run this in Rails console:
```ruby
ActiveRecord::Base.connection.execute("ALTER TABLE pull_requests ADD COLUMN head_sha VARCHAR")
ActiveRecord::Base.connection.execute("CREATE INDEX index_pull_requests_on_head_sha ON pull_requests (head_sha)")
```

## Why This Happens

Render shells sometimes don't inherit all environment variables properly. The DATABASE_URL needs to be explicitly set or the Rails app defaults to looking for a local PostgreSQL.