# Spec Guidelines — Abstraction Discipline

> **Spec mô tả WHAT và WHY, không phải HOW.**
> Một spec đúng abstraction level khi Claude Code có thể implement nó đúng — pass full `acceptance.md` — trên 3 stack khác biệt trong cùng family mà KHÔNG cần sửa spec.

File này là kim chỉ nam cho mọi block. Mọi PR sửa/thêm block phải pass self-check ở cuối file.

---

## 1. Core Principle

| Loại | Định nghĩa | Ai quyết? |
|---|---|---|
| **WHAT** | Behavior, contract, invariant — thứ phải đúng bất kể stack | Domain + external party |
| **WHY** | Lý do tồn tại của constraint — threat model, business rule | Spec author |
| **HOW** | Framework, syntax, ORM, file structure | Merchant project (qua Claude Code) |

Spec viết WHAT + WHY → Claude Code chọn HOW dựa trên context merchant.

**Test thử**: Đọc 1 đoạn spec, hỏi *"Đoạn này quy định behavior hay quy định cách viết code?"* — Nếu là quy định cách viết code → quá HOW → trừu tượng hoá.

---

## 2. Ba lớp Abstraction trong một file spec

### L1 — Semantic (WHAT + WHY) — **luôn concrete**

Thứ phải đúng bất kể stack:

- **Data model**: tên column + **logical type** (xem mục 5) + semantic + constraint + index intent
- **Sequence flows**: ai gọi ai, với data gì, theo thứ tự nào
- **State machines**: explicit transitions, terminal states, invalid transitions
- **Business invariants**: tenant isolation, uniqueness rules, idempotency keys
- **External protocol contracts** (xem mục 3) — cryptographic algorithm, JWT claim names, webhook header names, parameter ordering rules
- **Security threats + mitigation logic**: threat → mitigation (logic, không phải code)
- **Acceptance criteria**: how to verify done

### L2 — Mechanism (HOW) — **luôn abstract**

Thứ Claude Code phải tự quyết theo merchant context:

- Framework syntax (Express vs Hono vs Fastify — không viết `app.use(...)`, viết "middleware verify HMAC")
- ORM choice (Drizzle vs Prisma vs raw SQL)
- SQL dialect features (xem mục 5 — dùng logical types)
- Test framework (Vitest vs Jest vs Bun test)
- Error handling style (throw vs `Result<T, E>` vs callback)
- File/folder convention
- Naming convention (camelCase vs snake_case ở code level — DB column name vẫn concrete vì là contract)

### L3 — Illustrative (reference) — **concrete nhưng marked**

Code snippet để minh hoạ pattern, không phải để copy-paste. Mọi snippet phải có marker:

```typescript
// <!-- PATTERN: hmac-verification -->
// <!-- PURPOSE: verify Shopify-signed payload using constant-time compare -->
// <!-- REFERENCE: runtime=node18+ crypto=node-builtin -->
// <!-- ADAPT: replace `crypto` import per runtime; swap `timingSafeEqual` equivalent -->
import { createHmac, timingSafeEqual } from "node:crypto";

function verifyShopifyHmac(secret: string, body: Buffer, expected: string): boolean {
  const computed = createHmac("sha256", secret).update(body).digest();
  const expectedBuf = Buffer.from(expected, "base64");
  if (computed.length !== expectedBuf.length) return false;
  return timingSafeEqual(computed, expectedBuf);
}
```

Rule cho L3 snippet:
- ≤30 dòng/snippet (vượt = đang viết implementation, không phải spec)
- Phải có cả 4 marker: `PATTERN`, `PURPOSE`, `REFERENCE`, `ADAPT`
- `ADAPT` phải liệt kê **rõ** cái gì merchant cần đổi — không viết "adapt to your stack" mơ hồ

---

## 3. External Protocol Contract — Carve-out đặc biệt

> **Thứ do bên ngoài dictate phải concrete, vì merchant không có quyền chọn.**

Discriminator: **"Ai quyết?"**
- Nếu **Shopify / Google / external standard** quyết → **concrete trong spec**
- Nếu **merchant project** quyết → abstract

| Loại | Ví dụ | Concrete hay abstract? |
|---|---|---|
| Cryptographic algorithm dictate bởi protocol | `HMAC-SHA256` cho Shopify webhook | **Concrete** (Shopify chọn) |
| Cryptographic algorithm tự chọn | "encrypt token at rest" | **Abstract** (merchant chọn AES-256-GCM hay chacha20) |
| JWT claim names | `iss`, `dest`, `aud`, `exp`, `nbf` của App Bridge | **Concrete** (Shopify chọn) |
| JWT verification library | `jose` vs `jsonwebtoken` | **Abstract** (merchant chọn) |
| HTTP header names | `X-Shopify-Hmac-Sha256` (case-sensitive) | **Concrete** (Shopify chọn) |
| OAuth callback parameter ordering | "Sort params alphabetically trước khi HMAC" | **Concrete** (Shopify rule) |
| Webhook response timeout | "Reply 200 trong 5 giây" | **Concrete** (Shopify rule) |
| Internal job queue framework | BullMQ vs Inngest vs PgQueue | **Abstract** (merchant chọn) |

**Anti-pattern**: viết "verify webhook using cryptographic hash" — quá abstract, Claude Code có thể chọn SHA-1 hoặc MD5 → sai contract → security hole.
**Correct**: viết "verify webhook using HMAC-SHA256 over raw body, compare base64 với header `X-Shopify-Hmac-Sha256` using constant-time comparison".

---

## 4. Supported Stack Scope

> **3-Stack Adaptability test áp dụng cho SQL-family.** NoSQL là explicit non-goal.

Stack mặc định để test mental adaptability của 1 spec:

| Stack | Runtime | Framework | DB | ORM | Test |
|---|---|---|---|---|---|
| A | Node 20 | Express | Postgres 16 | Drizzle | Vitest |
| B | Bun 1.x | Hono | SQLite | raw SQL | Bun test |
| C | Deno 2.x | Oak | Postgres 16 | Prisma | Deno test |

(MySQL cũng support — substitute B's SQLite by MySQL nếu cần.)

Nếu Claude Code implement spec đúng (pass full acceptance.md) trên cả 3 stack mà **không cần sửa spec** → spec ở đúng abstraction level.

**Out of scope** (cần block-specific adaptation guidance riêng, không tự derive từ logical types):
- MongoDB / DynamoDB / Firestore (document NoSQL)
- Cassandra / ScyllaDB (wide-column)
- Redis as primary store

Merchant dùng các stack trên cần fork block và viết adaptation. Không phải spec failure.

---

## 5. Logical Types Table (Canonical)

> **"Logical type" có ý nghĩa cố định khi viết spec.** Dùng đúng từ trong cột "Logical" — không tạo từ mới.

| Logical | Semantic | Postgres ref | MySQL ref | SQLite ref |
|---|---|---|---|---|
| `unique_id` | PK, distributed-safe, ≥128-bit entropy, immutable | `uuid PRIMARY KEY DEFAULT gen_random_uuid()` | `BINARY(16) PRIMARY KEY` (store UUID) | `TEXT PRIMARY KEY` (uuid4 string) |
| `external_id` | ID provided by external system (Shopify GID, OAuth sub) | `text` | `VARCHAR(255)` | `TEXT` |
| `text` | UTF-8 string, unbounded length | `text` | `TEXT` | `TEXT` |
| `text_short` | UTF-8 string, ≤255 char | `varchar(255)` | `VARCHAR(255)` | `TEXT` |
| `encrypted_text` | text encrypted at rest by app before insert | `text` (ciphertext) | `TEXT` (ciphertext) | `TEXT` (ciphertext) |
| `integer` | 64-bit signed integer | `bigint` | `BIGINT` | `INTEGER` |
| `decimal` | fixed-point, precision/scale explicit | `numeric(p,s)` | `DECIMAL(p,s)` | `NUMERIC` |
| `boolean` | true/false | `boolean` | `TINYINT(1)` | `INTEGER 0/1` |
| `timestamp` | UTC instant, ≥microsecond precision | `timestamptz` | `DATETIME(6)` | `TEXT` (ISO 8601 with `Z`) |
| `json` | structured nested data, queryable by key | `JSONB` | `JSON` | `TEXT` (JSON string, no native query) |
| `enum` | string from fixed set — declare set in spec | `text CHECK (col IN (...))` or PG enum | `ENUM(...)` | `TEXT CHECK (col IN (...))` |
| `id_list` | ordered list of IDs (small, ≤1000) | `text[]` or `JSONB array` | `JSON array` | `TEXT` (JSON array) |

**Rules khi dùng:**
- Trong **data model table** (mục 2 của README): cột "Type" dùng **logical type** từ bảng này
- Trong **reference migration** (cuối README hoặc trong backend.md): SQL với marker `<!-- REFERENCE: dialect=postgres -->`
- KHÔNG dùng `uuid`, `timestamptz`, `JSONB` trong cột "Type" của bảng định nghĩa — chỉ trong reference migration
- Nếu cần type không có trong bảng → **mở PR thêm vào bảng này TRƯỚC**, không tự ad-hoc

### Notation conventions (special types)

**`decimal` — precision/scale**: Logical Type column dùng đơn thuần `decimal` (không kèm `(p,s)`). Precision + scale ghi ở cột **Notes**:
```markdown
| `price_amount` | `decimal` | NOT NULL | precision/scale: (10,2) for currency |
| `rating_avg`   | `decimal` | nullable | precision/scale: (2,1) for 0.0–5.0 |
```
Reference migration block dùng dialect-specific notation: Postgres `numeric(10,2)`, MySQL `DECIMAL(10,2)`, SQLite `NUMERIC` (precision không enforce, app validate).

**`enum` — value list**: Logical Type column dùng đơn thuần `enum`. Value set ghi:

- **Short list (≤6 values)**: trực tiếp ở cột **Notes** dạng pipe-separated:
  ```markdown
  | `status` | `enum` | NOT NULL | values: `pending|active|cancelled|frozen|declined` |
  | `interval` | `enum` | NOT NULL | external (Shopify): `EVERY_30_DAYS|ANNUAL` |
  ```
- **Long list (>6 values)**: pointer xuống section riêng trong file:
  ```markdown
  | `metafield_type` | `enum` | NOT NULL | values: see §7 "Supported Metafield Types" |
  ```
  Section riêng list đầy đủ values, group hợp lý nếu có (e.g., text types / numeric types / reference types).

**External vs internal enum**: Nếu enum values do external party dictate (Shopify, OAuth provider), ghi `external ({party}):` prefix ở Notes. Nếu merchant tự define (mirror state, internal status), không cần prefix. Discriminator giống mục 3.

Reference migration block dùng dialect-specific notation: Postgres `text CHECK (col IN ('a','b','c'))` hoặc native `CREATE TYPE name AS ENUM (...)`; MySQL `ENUM('a','b','c')`; SQLite `TEXT CHECK (col IN (...))`.

**`id_list` — internal vs external**:
- Internal IDs (FK to local table) → cột Notes: `list of unique_id; max ~1000`
- External IDs (from Shopify/Google/etc.) → cột Notes: `list of external_id from {party}; max ~1000`

Format giống `decimal`/`enum`: pointer trong Notes, dialect-specific representation trong reference migration (Postgres `text[]`/`uuid[]`, MySQL/SQLite `JSON` array hoặc join table).

### Reference Migration conventions

Reference Migration là **dialect translation**, không phải L3 illustrative pattern. Convention riêng:

| Aspect | L3 illustrative snippet | Reference Migration |
|---|---|---|
| Markers required | 4 (PATTERN, PURPOSE, REFERENCE, ADAPT) | **2** (REFERENCE, ADAPT only) |
| Length limit | ≤30 dòng strict | Recommended ≤30 per-table; split per-table khi block tổng >30 |
| Placement | Inline với prose mô tả pattern | Dedicated section cuối README data model (hoặc backend.md) |
| Naming | `kebab-case-pattern-name` | Section heading `### Reference Migration (Postgres)` hoặc tên dialect khác |

**Per-table split (recommended when >30 lines total)**:

```markdown
### Reference Migration (Postgres)

#### `shops` table

<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: ... -->
<sql block với CREATE TABLE shops + CREATE INDEX>

#### `oauth_nonces` table

<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: ... -->
<sql block với CREATE TABLE oauth_nonces + CREATE INDEX>
```

**Single block (acceptable when total ≤30 lines)**: 1 SQL block với 2 markers, chứa tất cả `CREATE TABLE` + `CREATE INDEX`.

**Lý do convention này**:
- Reference Migration không có "pattern + purpose" — nó là dialect translation, không phải design pattern
- Per-table split giúp merchant adapt từng table khi chuyển dialect (mỗi table có thể có dialect-specific construct riêng — JSONB column, array, enum)
- ADAPT cần liệt kê tất cả dialect-specific constructs (`uuid`, `timestamptz`, `JSONB`, `BIGINT[]`, `decimal(p,s)`, `ON CONFLICT`, etc.) với mapping cho MySQL/SQLite

---

## 6. Code Snippet Markers — Full Spec

Mọi code snippet ở L3 (illustrative) phải có 4 marker:

```
<!-- PATTERN: <short-kebab-case-name> -->
<!-- PURPOSE: <1-line what it solves> -->
<!-- REFERENCE: <key=value> [key=value]... -->
<!-- ADAPT: <comma-separated list of what to change per stack> -->
```

**`REFERENCE` keys hợp lệ:**

| Key | Values | When to use |
|---|---|---|
| `runtime` | `node18+`, `node20+`, `bun1+`, `deno2+` | Runtime version requirement |
| `framework` | `express`, `hono`, `fastify`, `oak`, `agnostic` | HTTP framework; `agnostic` for type-only or framework-portable snippets |
| `language` | `typescript`, `javascript` | When language-level features matter (e.g., regex snippet) |
| `dialect` | `postgres`, `mysql`, `sqlite` | SQL dialect of the snippet |
| `orm` | `drizzle`, `prisma`, `raw-sql`, `kysely` | ORM/query builder choice |
| `test` | `vitest`, `jest`, `bun-test`, `deno-test` | Test framework |
| `crypto` | `node-builtin`, `web-crypto`, `noble-hashes` | Crypto library |
| `http` | `fetch-builtin`, `undici`, `axios` | HTTP client |
| `algorithm` | `hmac-sha256`, `aes-256-gcm`, `rs256`, `hs256`, `ecdsa-sha256`, `sha1` | Cryptographic algorithm — duplicates info from prose but useful for grep/audit |
| `api` | `shopify-admin-graphql`, `shopify-storefront-graphql`, `google-oauth2`, etc. | External API the snippet integrates with |
| `api-version` | `2024-10`, `2024-10+`, `v3`, etc. | External API version snippet was tested against |
| `regex-flavor` | `ecmascript`, `pcre`, `posix` | Regex dialect (for regex-heavy snippets) |

**Rules:**
- Only include keys relevant to the snippet — không spam all keys
- Multiple values cho 1 key separate bằng `+`: `framework=express+hono`
- Cần thêm key mới → mở PR update bảng này TRƯỚC khi dùng trong block

**`ADAPT` rules:**
- Liệt kê cụ thể cái gì cần đổi — KHÔNG mơ hồ
- Bad: `ADAPT: adapt to your stack`
- Good: `ADAPT: replace 'node:crypto' import nếu chạy edge runtime; thay 'createHmac' bằng Web Crypto API (subtle.importKey + sign)`

---

## 7. 3-Stack Adaptability Test (mental)

Trước khi merge 1 spec mới hoặc 1 PR sửa spec, tự thực hiện test sau:

> "Nếu tôi đưa spec này cho 3 Claude Code instances, mỗi instance ở stack A/B/C (mục 4), có chạy hết acceptance.md được không **mà không phải sửa spec**?"

Cụ thể từng câu hỏi:
1. **Data model**: cả 3 dialect map logical types đúng được không? (kiểm bảng mục 5)
2. **Code snippet**: snippet ở runtime A có equivalent ở B, C không? (kiểm marker `ADAPT`)
3. **External contract**: claim/header/algorithm có concrete đủ để cả 3 instance verify đúng không?
4. **Sequence flow**: flow có depend vào tính năng cụ thể của 1 framework không?
5. **Acceptance**: acceptance criteria có verifiable trên cả 3 stack không?

Nếu trả lời "không" ở câu nào → fix spec trước khi merge.

---

## 8. Self-check trước khi merge (mandatory)

Checklist này phải pass trước khi merge bất kỳ block mới hoặc sửa block:

- [ ] **Data model**: cột "Type" trong bảng định nghĩa dùng logical types từ mục 5 (không `uuid`/`timestamptz`/`JSONB` trong cột Type)
- [ ] **Reference migration**: SQL dialect-specific có marker `<!-- REFERENCE: dialect=postgres -->` (hoặc dialect khác) và đặt ở section riêng cuối README hoặc trong backend.md
- [ ] **Code snippets**: mỗi snippet có đủ 4 marker (`PATTERN`, `PURPOSE`, `REFERENCE`, `ADAPT`); `ADAPT` liệt kê cụ thể, không mơ hồ
- [ ] **External contracts**: cryptographic algorithm, header names, claim names, parameter ordering rules đều concrete (theo mục 3)
- [ ] **No framework syntax ở L1/L2**: không có `app.use(...)`, `@Controller`, `app.get(...)` ở phần WHAT — chỉ ở L3 snippet
- [ ] **Snippet length**: mỗi snippet ≤30 dòng
- [ ] **3-Stack mental test**: trả lời "yes" cho cả 5 câu ở mục 7
- [ ] **Logical types table**: nếu dùng type mới không có trong mục 5 → đã update bảng

---

## 9. Side-by-side examples

### Example A — Data model

**❌ Too concrete (Postgres-only leak vào L1):**
```markdown
| Column | Type | Constraints |
|---|---|---|
| id | uuid | PK, default gen_random_uuid() |
| access_token | text | NOT NULL, encrypted using pgcrypto |
| installed_at | timestamptz | NOT NULL DEFAULT now() |
| metadata | JSONB | DEFAULT '{}' |
```

**✅ Just right:**
```markdown
| Column | Logical Type | Constraints | Notes |
|---|---|---|---|
| id | unique_id | PK | distributed-safe ID |
| access_token | encrypted_text | NOT NULL | app encrypts before insert; never store plaintext |
| installed_at | timestamp | NOT NULL, default = now | UTC instant |
| metadata | json | nullable, default empty object | queryable by key |
```

```sql
<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: see Logical Types Table for MySQL/SQLite equivalents -->
CREATE TABLE shops (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  access_token  text NOT NULL,
  installed_at  timestamptz NOT NULL DEFAULT now(),
  metadata      jsonb NOT NULL DEFAULT '{}'
);
```

**❌ Too abstract (Claude Code không có guidance đủ):**
```markdown
| Field | Purpose |
|---|---|
| id | unique identifier |
| token | the access token |
| time | when installed |
| extras | additional data |
```

### Example B — Security primitive

**❌ Too abstract (security hole — Claude Code có thể chọn SHA-1):**
```markdown
- Verify webhook authenticity using cryptographic hash of body + secret
```

**✅ Just right (external contract concrete):**
```markdown
- Verify webhook using **HMAC-SHA256** over raw request body
- Compute: `base64(hmac_sha256(SHOPIFY_API_SECRET, body))`
- Compare with header `X-Shopify-Hmac-Sha256` using **constant-time comparison**
- Reject with 401 if mismatch — never log body or computed HMAC

<!-- PATTERN: hmac-verify -->
<!-- PURPOSE: prevent forged webhook payloads -->
<!-- REFERENCE: runtime=node20+ crypto=node-builtin -->
<!-- ADAPT: edge runtime → swap node:crypto → Web Crypto SubtleCrypto; keep algorithm + encoding identical -->
import { createHmac, timingSafeEqual } from "node:crypto";

function verifyWebhook(secret: string, body: Buffer, header: string): boolean {
  const computed = createHmac("sha256", secret).update(body).digest("base64");
  const computedBuf = Buffer.from(computed);
  const headerBuf = Buffer.from(header);
  if (computedBuf.length !== headerBuf.length) return false;
  return timingSafeEqual(computedBuf, headerBuf);
}
```

**❌ Too concrete (Express-only middleware syntax ở L1):**
```markdown
- Add `app.use('/webhooks', verifyHmacMiddleware)` to Express app before route handler
```

### Example C — Sequence flow

**❌ Too concrete (framework leak):**
```markdown
1. `req.headers.authorization` chứa Bearer token
2. Express middleware `next()` chuyển control sau khi verify
3. Drizzle query `db.select().from(shops).where(eq(shops.domain, dest))`
```

**✅ Just right:**
```markdown
1. Extract bearer token from `Authorization` header (case-insensitive header name)
2. Decode JWT (base64url decode header + payload — no signature verify yet)
3. Verify HMAC-SHA256 signature over `<base64url(header)>.<base64url(payload)>` using `SHOPIFY_API_SECRET`
4. Validate claims:
   - `aud` === `SHOPIFY_API_KEY`
   - `iss` matches `dest` (same shop domain)
   - `exp` > now, `nbf` ≤ now (with ≤5s clock skew)
5. Look up shop record by `dest` domain
6. Attach `{ shopId, shopDomain, accessToken }` to request context for downstream handlers
7. If any check fails → respond 401, do not call downstream handler
```

---

## 10. Anti-patterns (must remove if found)

| Anti-pattern | Why bad | Fix |
|---|---|---|
| `gen_random_uuid()` trong cột "Type" của data model table | Postgres-specific leak vào L1 | Dùng `unique_id` logical, move SQL xuống reference migration |
| "Add middleware to your Express app" | Framework leak vào L1 | "Add HMAC-verify middleware before route handler" |
| Code snippet 50+ dòng | Đang viết implementation, không phải spec | Chia thành 2-3 PATTERN nhỏ hơn, hoặc move sang adaptation note |
| "Use cryptographic hash" / "use secure hash" | External contract không concrete | Tên thuật toán cụ thể: "HMAC-SHA256" |
| `ADAPT: adapt to your stack` | Không actionable | List cụ thể: "replace X import; swap Y function with Z equivalent" |
| Repeat full SQL migration ở mỗi block | Maintenance burden, dễ drift | Đặt 1 lần, reference từ block khác |
| "store as `JSONB`" trong table type column | Postgres leak | `json` logical type, reference migration ghi `JSONB`/`JSON`/`TEXT` |
| "use Drizzle's `.where()`" | ORM leak | "filter by `shop_id` WHERE clause" |
| Missing `REFERENCE` marker trên snippet | Reader không biết snippet test ở stack nào | Add marker đầy đủ |
| Snippet không có `ADAPT` list | Claude Code không biết cần đổi gì | Add explicit ADAPT list |

---

## 11. Migration guide — Refactor existing blocks

Áp dụng cho block đã viết trước khi guidelines này tồn tại.

**Step 1: Audit data model section**
- Tìm: `uuid`, `timestamptz`, `JSONB`, `gen_random_uuid()`, `numeric(p,s)` trong cột "Type" của bảng định nghĩa
- Thay bằng logical type tương ứng (bảng mục 5)
- Move SQL migration xuống section "Reference Migration" cuối README hoặc backend.md, gắn marker `<!-- REFERENCE: dialect=postgres -->`

**Step 2: Audit code snippets**
- Tìm snippet thiếu marker — add đủ `PATTERN`/`PURPOSE`/`REFERENCE`/`ADAPT`
- Audit `ADAPT` content — nếu mơ hồ → list cụ thể
- Snippet >30 dòng → chia nhỏ

**Step 3: Audit external contracts**
- Tìm "cryptographic hash" / "secure hash" / "verify signature" mơ hồ → tên thuật toán cụ thể
- Tìm header/claim names không concrete → liệt kê đầy đủ

**Step 4: Audit framework syntax**
- Grep `app.use`, `app.get`, `@Controller`, `req.body`, `res.json` ở L1/L2 → reformulate behavior-level
- Giữ ở L3 snippet (với marker)

**Step 5: Run 3-Stack mental test (mục 7)**
- Trả lời 5 câu hỏi
- Fix mọi "no"

**Step 6: Run Self-check (mục 8)**
- Tick từng item
- Mọi item phải pass

---

## 12. When to update this guide

Update `SPEC_GUIDELINES.md` khi:
- Logical Types Table thiếu type → add row, document semantic
- External protocol contract mới gặp → add row mục 3
- Anti-pattern mới phát hiện qua review → add row mục 10
- Stack scope thay đổi (e.g., support NoSQL) → update mục 4 + audit toàn bộ block

Đừng update guide mỗi khi 1 block có đặc thù riêng — đặc thù riêng để trong block, không leak ngược lên guide.
