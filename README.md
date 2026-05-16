# Primitive Block Interface

## Primitive Block là gì

Primitive Block là **bản thiết kế hoàn chỉnh** cho một feature/capability. Nó KHÔNG phải code sẵn — nó là specification + design + code patterns + standards mà Claude Code đọc và implement vào hệ thống của merchant.

Analogy: Primitive Block = bản vẽ kiến trúc chi tiết. Claude Code = thợ xây có tay nghề đọc bản vẽ và xây theo context thực tế của công trình.

## Tại sao không phải code sẵn

| Code sẵn (paradigm cũ) | Blueprint (paradigm mới) |
|---|---|
| Rigid — chỉ customize qua config JSON | Flexible — Claude Code adapt toàn bộ |
| Phải fit 1 runtime cố định | Fit bất kỳ stack nào merchant dùng |
| Lỗi = lỗi ở pre-built code, khó debug | Lỗi = Claude Code sửa trực tiếp |
| Thêm feature = viết code mới | Thêm feature = viết spec mới |
| AI pick + fill config (surface area nhỏ) | AI implement full feature (surface area lớn, quality cao hơn với Claude Code) |

### Triết lý: Vấn đề hiện đại, giải pháp hiện đại

Đừng giải quyết vấn đề của thời đại agentic AI bằng giải pháp của thời đại cổ điển.

Việc đóng gói feature thành các package code cố định — dù gọi là "primitive", "component", hay "module" — bản chất vẫn là hệ thống cũ. Khả năng của hệ thống đúng bằng tổng số block có sẵn. Mọi vấn đề kinh điển lập tức quay lại: custom khó (chỉ thay đổi được trong phạm vi config cho phép), composition phức tạp (làm sao để N block hoạt động đúng khi ghép chung), versioning, breaking changes, abstraction leak. Đây là vấn đề cổ điển của software engineering — đã tồn tại 40 năm và chưa bao giờ được giải quyết triệt để.

Khi có agentic AI (Claude Code với full filesystem access, chạy command, iterate), hãy để AI giải quyết vấn đề trực tiếp. Primitive Block không phải code sẵn để ghép — nó là **kiến thức** để AI hiểu feature cần build và implement đúng vào context thực tế của merchant. AI đọc blueprint, hiểu codebase hiện tại, viết code phù hợp, chạy test, sửa lỗi, iterate cho tới khi đúng.

Độ tin cậy ban đầu có thể thấp hơn so với pre-built code (code sẵn pass 100% test vì test viết cho chính nó). Nhưng đây là trade-off có hướng cải thiện rõ ràng:

- **Code mẫu tốt hơn** → AI output chính xác hơn (reference patterns trong block)
- **Prompting tốt hơn** → AI hiểu context rõ hơn (CLAUDE.md + block spec)
- **Unit test** → catch lỗi logic ngay tại implementation time
- **Integration test** → catch lỗi composition khi feature chạy cùng nhau
- **Mỗi block iteration** cải thiện block spec → snowball effect

Hướng cải thiện này không có ceiling — model tốt hơn, block spec tốt hơn, testing tốt hơn → quality tăng liên tục. Code sẵn có ceiling cố định: đúng bằng những gì đã viết.

## Ai consume Primitive Block

**Claude Code instance** — chạy trong workspace riêng của merchant. Claude Code đọc Primitive Block như reference doc, rồi implement feature vào codebase merchant. Claude Code có full filesystem access, chạy được commands (tsc, test, lint), iterate khi lỗi.

## Block = Folder

```
primitive-blocks/
  INTERFACE.md                        ← bạn đang đọc file này
  {category}/
    {feature-name}/                   ← mỗi block = 1 folder
      README.md                       # Identity, overview, data model, config, architecture
      frontend.md                     # Frontend implementation guide + patterns
      backend.md                      # Backend implementation guide + patterns
      security.md                     # Threat model, validation, secrets
      *.feature                       # Gherkin scenarios (BDD) — human + machine readable
      fixtures/                       # Test data, mock responses, seed data
        *.json
      tests/                          # Actual test code patterns
        unit.ts                       # Unit test patterns
        integration.ts                # Integration test patterns
      acceptance.md                   # Verification checklist
```

Tách files theo concern — mỗi file phục vụ 1 mục đích rõ ràng. Claude Code đọc files theo nhu cầu, không phải load 1 monolith.

---

## Abstraction Discipline

> **Spec mô tả WHAT và WHY, KHÔNG phải HOW.**
> Spec đúng abstraction level khi Claude Code có thể implement nó đúng — pass full `acceptance.md` — trên 3 stack SQL-family khác biệt mà KHÔNG cần sửa spec.

Đây là tension cốt lõi của blueprint paradigm: quá abstract → Claude Code không có guidance đủ → mỗi merchant ra 1 implementation khác; quá concrete → spec biến thành code mặc áo markdown → mất tính stack-agnostic. Để cân bằng, mỗi spec có **3 lớp**:

| Lớp | Nội dung | Mức độ |
|---|---|---|
| **L1: Semantic** (WHAT + WHY) | Data model, sequence flows, state machines, invariants, external protocol contracts, threats + mitigations | **Concrete tối đa** |
| **L2: Mechanism** (HOW) | Framework, ORM, SQL dialect, test runner, error handling style, file convention | **Abstract — để Claude Code quyết** |
| **L3: Illustrative** (reference) | Code snippet ≤30 dòng, có marker `PATTERN`/`PURPOSE`/`REFERENCE`/`ADAPT` | **Concrete nhưng marked** |

### External Protocol Contract (carve-out)

Thứ do bên ngoài (Shopify, Google, OAuth standard) dictate phải **concrete** bất kể là Mechanism — vì merchant không có quyền chọn:

- Cryptographic algorithm dictated by protocol: `HMAC-SHA256` cho Shopify webhook (concrete) vs "encrypt token at rest" (abstract, merchant chọn)
- JWT claim names: `iss`, `dest`, `aud`, `exp` của App Bridge (concrete) vs JWT library (abstract)
- Header names: `X-Shopify-Hmac-Sha256` (concrete, case-sensitive) vs HTTP framework (abstract)
- Parameter ordering rules: "sort alphabetically trước HMAC" (concrete) vs query parser (abstract)

Discriminator đơn giản: **"Ai quyết?"** — external party → concrete; merchant project → abstract.

### Logical Types (data model)

Cột "Type" trong bảng định nghĩa data model dùng **logical type** (không phải SQL dialect): `unique_id`, `text`, `encrypted_text`, `integer`, `decimal`, `boolean`, `timestamp`, `json`, `enum`, `id_list`, `text_short`, `external_id`. SQL migration cụ thể (dùng `uuid`/`timestamptz`/`JSONB`) đặt ở section "Reference Migration" với marker `<!-- REFERENCE: dialect=postgres -->`.

Bảng map đầy đủ Logical → Postgres/MySQL/SQLite ở `docs/SPEC_GUIDELINES.md` mục 5.

### Supported Stack Scope

3-Stack test áp dụng cho **SQL-family**:
- **A**: Node 20 + Express + Postgres + Drizzle + Vitest
- **B**: Bun + Hono + SQLite + raw SQL + Bun test
- **C**: Deno 2 + Oak + Postgres + Prisma + Deno test

NoSQL (MongoDB/DynamoDB/Firestore) là **explicit non-goal** — merchant dùng NoSQL fork block và viết adaptation riêng.

### Đọc thêm

Full framework + Logical Types Table canonical + side-by-side examples + self-check checklist + migration guide ở **[`docs/SPEC_GUIDELINES.md`](docs/SPEC_GUIDELINES.md)**. Mọi block mới hoặc PR sửa block phải pass self-check trong file đó.

---

## File Contracts

### README.md — Block identity + architecture

Đây là file đầu tiên Claude Code đọc. Chứa:

**Frontmatter (YAML)**:
```yaml
---
id: "{category}.{feature-slug}"
name: "{Human-readable name}"
version: "1.0.0"
category: "{category}"
tags: [tag1, tag2, tag3]
prerequisites: []
complexity: low | medium | high
estimated_effort: "~30 min"
files:                              # manifest — Claude Code biết folder có gì
  - README.md
  - frontend.md
  - backend.md
  - security.md
  - login.feature
  - session.feature
  - fixtures/google-user.json
  - tests/unit.ts
  - tests/integration.ts
  - acceptance.md
---
```

**Required sections trong README.md**:

1. **Overview** — Problem statement, user stories, when to use / when not to use
2. **Data Model** — ERD (Mermaid), table definitions, migration SQL, indexes, seed data
3. **Data Flow** — Mermaid flowchart, data movement description
4. **Sequence Diagrams** — Ít nhất 2: happy path + error case (Mermaid)
5. **State Management** — Frontend state, server state, state transitions, persistence
6. **Integration Points** — Inbound, outbound, events, shared data
7. **Configuration Surface** — Table: key, type, default, description

Data model rules:
- Luôn có `id`, `created_at`, `updated_at`
- Luôn có tenant isolation column (`shop_id`, `account_id`)
- `text` cho IDs (distributed-safe), `timestamptz` cho timestamps

### frontend.md — Frontend implementation guide

Patterns + structure + key decisions. NOT complete code.

- **Component tree**: responsibilities, props interface
- **UI/UX patterns**: loading, error, empty states, success feedback
- **Code patterns**: TypeScript snippets (10-30 lines) with markers:
  ```
  <!-- PATTERN: name -->
  <!-- PURPOSE: what it solves -->
  <!-- ADAPT: what Claude Code changes per merchant -->
  ```
- **Anti-patterns**: "DON'T" examples with explanation
- **Styling guidance**: design tokens, responsive, accessibility

### backend.md — Backend implementation guide

- **API endpoints**: method, path, request/response shapes, status codes
- **Middleware patterns**: auth, validation, rate limiting
- **Business logic patterns**: core algorithms, edge case handling
- **Code patterns**: TypeScript snippets with PATTERN markers
- **Error handling**: error types, error responses, logging
- **Anti-patterns**: security pitfalls, performance traps

### security.md — Security spec

- **Threat model**: 2-5 threats with impact + mitigation
- **Validation rules**: input validation, sanitization
- **Auth/authz**: permission checks
- **Secrets management**: env vars, what never goes in code

### *.feature — Gherkin scenarios (BDD)

Mỗi user flow = 1 file `.feature`. Gherkin format — human-readable, machine-parseable, Claude Code dùng để generate tests.

```gherkin
Feature: Google Login
  As a user
  I want to sign in with my Google account
  So that I can access the app without creating a password

  Scenario: New user logs in successfully
    Given the Google OAuth server returns a valid token for "alice@example.com"
    When I submit the auth callback with a valid code
    Then I should receive a 200 response with user data
    And a session cookie should be set
    And a new user "alice@example.com" should exist in the database
```

Rules:
- 1 file per feature area (login.feature, session.feature, admin.feature)
- Mỗi file: 3-8 scenarios
- Cover: happy path, error cases, edge cases, security cases
- Given/When/Then steps phải cụ thể đủ để generate test code
- Tag scenarios: `@happy`, `@error`, `@edge`, `@security`

### fixtures/ — Test data

JSON files chứa mock data mà tests và Claude Code reference:

- Mock API responses (Google token response, user profile)
- Seed data (test users, test sessions)
- Invalid data samples (expired tokens, malformed payloads)

Mỗi fixture file có comment block ở đầu giải thích context:
```json
{
  "_comment": "Valid Google ID token payload — use in tests that need authenticated user",
  "sub": "google-uid-123456",
  "email": "alice@example.com",
  ...
}
```

### tests/unit.ts — Unit test patterns

Actual runnable test code (vitest/jest). Claude Code adapt vào project's test framework.

Rules:
- Mỗi pattern ở frontend.md / backend.md phải có ít nhất 1 unit test
- Test structure: Arrange → Act → Assert
- Mock setup patterns ở đầu file
- Test phải runnable, không phải pseudocode
- Mark tests: `// TEST: name` + `// VERIFIES: pattern hoặc feature`

### tests/integration.ts — Integration test patterns

End-to-end flow tests: frontend → backend → database → external service.

Rules:
- Ít nhất 1 integration test cho mỗi .feature file scenario
- Setup/teardown patterns (test DB, mock servers)
- Tests phải idempotent + cleanup after
- Mock external services (OAuth provider, APIs)

### acceptance.md — Verification checklist

Checklist Claude Code chạy SAU khi implement, TRƯỚC khi report done:

```markdown
## Checklist

- [ ] Migration chạy thành công
- [ ] Tất cả unit tests pass
- [ ] Tất cả integration tests pass
- [ ] `tsc --noEmit` pass
- [ ] Không có hardcoded secrets
- [ ] Config surface exposed đúng
- [ ] Error handling cover mọi failure mode
- [ ] {block-specific criteria}
```

Bất kỳ item fail → iterate cho tới khi pass.

---

## How Claude Code Consumes a Block

1. **Read the block**: Claude Code reads the full markdown file
2. **Understand the merchant's stack**: check existing codebase (package.json, framework, DB, existing patterns)
3. **Adapt**: implement the block's design using merchant's conventions, NOT the block's exact code
4. **Validate**: run tsc, tests, lint — iterate until pass
5. **Report**: list what was created, what was configured, what needs manual setup (env vars, 3rd party config)

### CLAUDE.md injection pattern

Khi Foundry dispatch Claude Code cho merchant, CLAUDE.md include:

```markdown
## Current Task

Implement the following primitive block into this project.

### Block Spec
{content of primitive-blocks/{category}/{feature}.md}

### Merchant Context
- Framework: {detected from package.json}
- Database: {detected}
- Auth: {existing auth if any}
- Existing patterns: {detected conventions}

### Rules
- Follow the block spec's data model, flows, and patterns
- Adapt code patterns to this project's conventions
- Run `tsc --noEmit` before claiming done
- Run tests before claiming done
- Do NOT copy-paste from block — adapt to this codebase
```

---

## Block Quality Criteria

A good primitive block passes these checks:

1. **Self-contained**: Claude Code can implement it from this file alone (no external links that might break)
2. **Abstraction discipline**: data model dùng logical types, framework syntax không leak vào L1/L2, code snippet có đủ 4 marker. Pass self-check ở `docs/SPEC_GUIDELINES.md` mục 8
3. **3-Stack adaptability**: mental test (mục 7 của SPEC_GUIDELINES) cho stack A/B/C SQL-family đều "yes"
4. **External contracts concrete**: cryptographic algorithm, claim names, header names, parameter ordering — không mơ hồ
5. **Security-first**: security section covers OWASP Top 10 relevant threats
6. **Testable**: testing scenarios are specific enough to auto-generate test cases
7. **Mermaid diagrams render**: all diagrams valid Mermaid syntax
8. **Anti-patterns included**: "DON'T do this" is as valuable as "DO this"
9. **Edge cases explicit**: not just happy path — failure modes documented
