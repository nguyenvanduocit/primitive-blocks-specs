# Acceptance Checklist — Shopify Metafields

Claude Code runs this checklist after implementation, before reporting done.

## Database

- [ ] Migration runs successfully (`metafield_definitions` table created)
- [ ] `UNIQUE` constraint on `(shop_id, namespace, key, owner_type)` is active
- [ ] `idx_metafield_defs_shop` index exists on `shop_id`
- [ ] `idx_metafield_defs_owner` index exists on `(shop_id, owner_type)`
- [ ] `ON DELETE CASCADE` from `shops(id)` is active — shop uninstall purges all definitions
- [ ] All queries include `shop_id` in WHERE clause (tenant isolation)

## Definition Sync

- [ ] POST /api/metafields/sync-definitions calls `metafieldDefinitionCreate` for each configured definition
- [ ] Each mutation includes `namespace`, `key`, `name`, `type`, `ownerType`, and `pin` fields
- [ ] `TAKEN` userError from Shopify is treated as success (definition already exists)
- [ ] Non-TAKEN errors are logged as warnings and do not abort the full sync
- [ ] Local `metafield_definitions` records are upserted with `shopify_gid` and `synced_at`
- [ ] Existing records are not duplicated on re-sync (ON CONFLICT DO UPDATE)
- [ ] `metafield.synced` event is emitted after successful sync
- [ ] Empty `METAFIELD_DEFINITIONS` config returns `{ synced: 0 }` without calling Shopify

## Read Metafields

- [ ] GET /api/metafields/:ownerType/:ownerId sends correct GraphQL query for each owner type (PRODUCT, ORDER, CUSTOMER)
- [ ] `namespace` query param scopes the metafields fetch when provided
- [ ] Without `namespace` query param, all metafields for the resource are returned
- [ ] URL-encoded GID in the path parameter is correctly decoded before use in GraphQL
- [ ] Unsupported `ownerType` returns 400 `unsupported_owner_type`

## Write Metafields

- [ ] POST /api/metafields/:ownerType/:ownerId looks up type from local `metafield_definitions` for the authenticated shop
- [ ] Type is fetched from the database, never trusted from the client request body
- [ ] Value is validated against the registered type before any Shopify API call
- [ ] `metafieldsSet` mutation is called with correct `ownerId`, `namespace`, `key`, `type`, `value`
- [ ] Shopify `userErrors` in the mutation response are surfaced as 422 responses
- [ ] `metafield.set` event is emitted after successful write
- [ ] 404 `definition_not_found` returned when namespace+key+ownerType not in local registry for this shop

## Delete Metafield

- [ ] DELETE /api/metafields/:ownerType/:ownerId/:namespace/:key first fetches the metafield GID from Shopify
- [ ] `metafieldDelete` mutation is called with the GID
- [ ] 404 `metafield_not_found` returned when Shopify returns null for the metafield query
- [ ] Successful delete returns 204 with no body
- [ ] `metafield.deleted` event is emitted

## Batch Write

- [ ] POST /api/metafields/batch accepts 1–25 metafield entries
- [ ] 400 `batch_size_exceeded` returned for more than 25 entries (no Shopify call made)
- [ ] 400 `metafields_required` returned for empty array (no Shopify call made)
- [ ] Each entry's value is validated against its registered type before any Shopify call
- [ ] If any entry fails type validation, the entire batch is rejected (no partial writes)
- [ ] All valid entries are sent in a single `metafieldsSet` mutation call

## List Definitions

- [ ] GET /api/metafield-definitions returns all definitions for the authenticated shop
- [ ] Results are scoped to `shop_id` from the session token
- [ ] Results include `namespace`, `key`, `owner_type`, `type`, `name`, `description`, `shopify_gid`, `synced_at`

## Type Validation

- [ ] `number_integer`: rejects non-integer strings (decimals, words, empty)
- [ ] `number_decimal`: rejects non-numeric strings
- [ ] `boolean`: accepts only "true" or "false" (case-sensitive), rejects "yes"/"no"/"1"/"0"
- [ ] `date`: accepts only YYYY-MM-DD format, rejects human-readable dates
- [ ] `date_time`: accepts valid ISO datetime strings
- [ ] `json`: rejects invalid JSON syntax (bare keys, trailing commas, plain strings)
- [ ] `url`: rejects non-URL strings
- [ ] `color`: accepts only 6-digit hex (#rrggbb), rejects named colors
- [ ] `list.*`: requires a valid JSON array, rejects non-array values
- [ ] Unknown/reference types are passed through (Shopify validates GIDs)

## Security

- [ ] All endpoints require valid session token (401 for missing/invalid token)
- [ ] `shop_id` is always derived from the verified session token, never from client input
- [ ] Namespace from client request is validated against `METAFIELD_NAMESPACE` config (no arbitrary namespace access)
- [ ] Shopify API calls use the shop's access token from the encrypted `shops` table record
- [ ] No metafield values are stored in the app's database (values live in Shopify only)

## Configuration

- [ ] `METAFIELD_NAMESPACE` is required and non-empty
- [ ] `METAFIELD_DEFINITIONS` defaults to empty array (no sync attempted)
- [ ] `METAFIELD_PIN_TO_ADMIN` defaults to `true`
- [ ] Required scope validation warns if `SHOPIFY_SCOPES` missing `write_products` when PRODUCT definitions are configured

## Type Safety & Build

- [ ] `tsc --noEmit` passes (or equivalent type check)
- [ ] No `any` types without justification
- [ ] Zod (or equivalent) validates request bodies at the API boundary
- [ ] `ownerType` is typed as a union or enum, not a raw string
