---
name: backend-test
description: Backend development with test-driven verification. Use when implementing API endpoints, models, or business logic. Writes tests first or alongside implementation, runs them, and iterates until all pass.
user-invocable: true
allowed-tools: Bash, Read, Edit, Write, Glob, Grep
argument-hint: "[what to implement and test]"
---

# Backend Test-Driven Development

You are implementing backend functionality with mandatory test verification. You MUST NOT consider a task done until tests pass.

## Flow

### Step 1: Understand the Context

1. Read the backend directory structure to understand:
   - Framework in use (FastAPI, Express, Django, Flask, etc.)
   - Existing patterns (how routes, models, tests are organized)
   - Test framework and runner (pytest, jest, etc.)
   - Database setup if any
2. Check for database credentials:
   - Read `backend/.env` (or project root `.env`) for `DATABASE_URL`
   - If `.env` exists with a remote database URL, use it — tests should run against the real database
   - If no `.env` exists: check if you can pull credentials via `render` CLI (if available):
     ```bash
     render postgres list -o json 2>/dev/null
     ```
   - If credentials are unavailable, raise a blocker for the human to provide the DATABASE_URL
3. Understand the requirement: `$ARGUMENTS`

### Step 2: Plan the Implementation

Before writing code, determine:
- What files need to be created or modified
- What the API contract looks like (routes, request/response shapes)
- What test cases cover the requirement
- What edge cases matter

### Step 3: Implement

Write the implementation code. Follow existing patterns in the codebase:
- Models go where models are
- Routes go where routes are
- Match the existing code style

### Step 4: Write Tests

Write tests that verify the implementation. Tests MUST cover:
- **Happy path**: The main use case works correctly
- **Validation**: Invalid input is rejected with appropriate errors
- **Edge cases**: Empty data, missing fields, boundary values
- **Status codes**: Correct HTTP status codes for each scenario

Test file naming: follow existing convention, or use `test_{module}.py` / `{module}.test.js`.

### Step 5: Run Tests

```bash
# Detect and run appropriate test command
# Python/pytest:
cd backend && python -m pytest {test_file} -v

# Node/jest:
cd backend && npx jest {test_file} --verbose
```

### Step 6: Iterate

If tests fail:
1. Read the failure output carefully
2. Determine: is it a test bug or an implementation bug?
3. Fix the right thing
4. Re-run tests
5. Maximum 5 iterations. If still failing after 5, report what's passing and what's not.

If all tests pass: you are done. Report what was built and the test results.

## Testing with Authentication

If the project uses Clerk (check CLAUDE.md `Auth` field):

- **Auth-protected endpoints still need tests.** Do NOT skip them because they require auth.
- **Create a test auth helper** that bypasses Clerk verification in test mode. Common pattern for FastAPI:
  ```python
  # tests/conftest.py
  from backend.auth import get_current_user  # your auth dependency

  def override_auth():
      return {"user_id": "test-user-123", "email": "test@example.com"}

  app.dependency_overrides[get_current_user] = override_auth
  ```
- **Test both authenticated and unauthenticated access:**
  - Protected endpoint without auth → should return 401
  - Protected endpoint with test auth → should return expected data
- **Do NOT use real Clerk tokens in tests.** Override the auth dependency.

## Rules

- You MUST write at least one test file. No untested code.
- You MUST run the tests. Writing tests without running them is useless.
- You MUST NOT mock the database. Use the real database from `backend/.env` (DATABASE_URL). Integration tests against the real database catch what mocks miss. If no database credentials are available, raise a blocker.
- You MUST NOT modify test assertions to make them pass — fix the implementation instead.
- If you are in an orchestrated workflow, follow the worker protocol for progress reporting.

$ARGUMENTS
