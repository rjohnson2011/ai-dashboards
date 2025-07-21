# Rails Runner Usage Guide

## Common Syntax Errors to Avoid

### 1. Never escape exclamation marks in double quotes

❌ **WRONG:**
```bash
rails runner "Model.create\!(name: 'test')"
rails runner "record.update\!(status: 'approved')"
rails runner "record.save\!"
```

✅ **CORRECT:**
```bash
rails runner "Model.create!(name: 'test')"
rails runner "record.update!(status: 'approved')"
rails runner "record.save!"
```

### 2. Prefer script files for complex operations

Instead of complex inline commands, create a script:

❌ **AVOID:**
```bash
rails runner "
  pr = PullRequest.find(123)
  pr.update!(status: 'approved')
  pr.reviews.each { |r| r.update!(processed: true) }
"
```

✅ **BETTER:**
```bash
# Create scripts/update_pr.rb
rails runner scripts/update_pr.rb 123
```

### 3. Common patterns that work

```bash
# Simple queries
rails runner "puts User.count"
rails runner "puts PullRequest.where(state: 'open').count"

# Simple updates (no escaping needed)
rails runner "PullRequest.find(123).update!(reviewed: true)"

# Using environment variables
rails runner "puts ENV['GITHUB_TOKEN'].present?"
```

### 4. When to use single vs double quotes

- Use double quotes for the rails runner command
- Use single quotes inside for string literals
- Never mix quote styles unnecessarily

```bash
# Good
rails runner "User.create!(name: 'John Doe')"

# Also good (but be careful with interpolation)
rails runner 'User.create!(name: "John Doe")'
```

### 5. Error patterns to watch for

If you see this error:
```
syntax error, unexpected backslash
Model.create\!(
            ^
```

It means you have an unnecessary backslash before the exclamation mark.

## Best Practices

1. **Test locally first** - Run your command in development before production
2. **Use scripts for complex logic** - Easier to debug and maintain
3. **Check syntax** - Ruby syntax errors will fail immediately
4. **Use proper error handling** - Wrap operations in begin/rescue blocks
5. **Log important operations** - Add puts statements for visibility

## Example Scripts

See the `scripts/` directory for examples:
- `update_pr_reviews.rb` - Update PR review status
- `check_backend_reviewers.rb` - Manage backend reviewers
- `update_pr_ci_status.rb` - Update CI status for a PR