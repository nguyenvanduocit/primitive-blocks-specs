Feature: Device tokens and provider handling
  As the push service
  I want one live token per account and device, removed when a provider says it is dead
  So that sends reach real devices and never hit a token that belongs to someone else

  Background:
    Given the app is configured for tenant "tenant-001"
    And the profiles from fixtures/profiles.json exist
    And the defaults from fixtures/config-defaults.json
    And the clock is fixed at "2026-10-21T12:00:00Z"

  @happy
  Scenario: First upload registers an active token
    Given I am authenticated as the owner of "acc-gus" and the age status of "acc-gus" is now "adult"
    When I send PUT /api/push/tokens with installation_id "inst-gus-1", provider "apns", target_kind "apns_token", apns_environment "production", a token and permission_state "authorized"
    Then the response status is 200 with token_status "active"
    And one device_tokens row exists with last_registered_at "2026-10-21T12:00:00Z"

  @happy
  Scenario: Rotation updates the same row
    Given I am authenticated as the owner of "acc-ann"
    When I send PUT /api/push/tokens for installation_id "inst-ann-1" with a new token value
    Then the row "tok-ann-1" keeps its id, holds the new token and last_registered_at "2026-10-21T12:00:00Z"
    And no second row exists for "inst-ann-1"

  @edge
  Scenario: A token registered under another account deactivates the old row
    Given "acc-ben" registers the token value of "tok-ann-1" with the same provider
    Then the row "tok-ann-1" becomes inactive with inactive_reason "superseded"
    And the new row under "acc-ben" is active
    And at most one active row exists for that (provider, token)

  @happy
  Scenario: Logout removes the token and fails its queued deliveries
    Given a queued delivery exists for the device "tok-ann-1"
    When I send DELETE /api/push/tokens/inst-ann-1
    Then the response status is 204
    And the row "tok-ann-1" is inactive with inactive_reason "logout"
    And the queued delivery is failed with provider_status "token_removed"
    When I send the same DELETE again
    Then the response status is 204 and nothing changes

  @edge
  Scenario: A denied report deactivates the token and a later grant reactivates it
    When the device of "acc-ann" reports permission_state "denied" without a token
    Then the row "tok-ann-1" is inactive with inactive_reason "permission_denied"
    When the same install later reports "authorized" with a token
    Then the row is active again and inactive_reason is cleared

  @security
  Scenario: A player whose age is not decided cannot register a device
    Given I am authenticated as the owner of "acc-gus" and UNKNOWN_AGE_POLICY is "block"
    When I send PUT /api/push/tokens with a valid body
    Then the response status is 403 with error "age_not_eligible"
    And no device_tokens row exists for "acc-gus"

  @edge
  Scenario Outline: An APNs answer changes the token and the delivery by the documented rule
    Given a queued delivery to the APNs token "tok-ann-1" registered at "<registered>"
    When APNs answers as in fixtures/provider-responses.json case "<case>"
    Then the delivery status is "<delivery>" and the token action is "<token>"
    And a retry is scheduled: <retry>

    Examples:
      | case                                    | registered           | delivery | token      | retry                              |
      | A01-accepted                            | 2026-10-18T05:00:00Z | sent     | keep       | none                               |
      | A02-unregistered-after-registration     | 2026-10-18T05:00:00Z | failed   | deactivate | none                               |
      | A03-unregistered-but-registered-later   | 2026-10-21T09:00:00Z | failed   | keep       | none                               |
      | A05-bad-device-token                    | 2026-10-18T05:00:00Z | failed   | deactivate | none                               |
      | A07-expired-provider-token              | 2026-10-18T05:00:00Z | queued   | keep       | after refreshing the provider JWT  |
      | A10-payload-too-large                   | 2026-10-18T05:00:00Z | failed   | keep       | none                               |
      | A11-service-unavailable                 | 2026-10-18T05:00:00Z | queued   | keep       | not before 900 seconds             |

  @edge
  Scenario Outline: An FCM answer separates an invalid token from a bad payload
    Given a queued delivery to the FCM device "tok-ben-1"
    When FCM answers as in fixtures/provider-responses.json case "<case>"
    Then the delivery status is "<delivery>" and the token action is "<token>"
    And the earliest retry is <retry>

    Examples:
      | case                                    | delivery | token      | retry                                   |
      | F01-accepted                            | sent     | keep       | none                                    |
      | F02-unregistered                        | failed   | deactivate | none                                    |
      | F03-invalid-argument-invalid-token      | failed   | deactivate | none                                    |
      | F04-invalid-argument-payload            | failed   | keep       | none                                    |
      | F05-sender-id-mismatch                  | failed   | deactivate | none                                    |
      | F07-quota-exceeded-with-retry-after     | queued   | keep       | 120 seconds                             |
      | F08-quota-exceeded-no-header            | queued   | keep       | 60 seconds                              |
      | F09-unavailable-with-retry-after        | queued   | keep       | 30 seconds                              |
      | F10-internal                            | queued   | keep       | 10 seconds, exponential with jitter     |

  @edge
  Scenario: A burst of configuration errors pauses the lane and keeps the token table
    Given 60 sends to APNs in the sliding window, 15 of them answered "BadDeviceToken"
    And 15 tokens were deactivated with inactive_reason "bad_token" inside that window
    When the breaker evaluates the window as in fixtures/provider-responses.json case "B01-trips"
    Then the APNs lane is paused for 15 minutes and push_lane_paused fires
    And those 15 tokens are active again
    And fewer than 50 attempts, or fewer than 20 percent config-class answers, do not pause the lane (cases B02 and B03)

  @happy
  Scenario: The APNs request carries the documented headers and a sandbox token goes to the sandbox host
    Given the device "tok-ann-1" has apns_environment "sandbox"
    When the dispatcher builds the request for an "events" intent with expires_at "2026-10-21T18:00:00Z"
    Then the URL host is "api.sandbox.push.apple.com" and the path starts with "/3/device/"
    And the headers include authorization "bearer ...", apns-push-type "alert", apns-topic equal to APNS_TOPIC, apns-priority "10", apns-expiration "1792605600" and an apns-id that is a canonical UUID
    And apns-collapse-id is at most 64 bytes
    And the JSON body is at most 4096 bytes and holds send_id, category, route and rp

  @happy
  Scenario: The FCM request targets by the kind of identifier and sets the channel and the lifetime
    Given the device "tok-ben-1" has target_kind "fcm_fid"
    When the dispatcher builds the request for a "timers" intent with 3600 seconds left
    Then the URL is "https://fcm.googleapis.com/v1/projects/{FCM_PROJECT_ID}/messages:send"
    And the message has "fid" and no "token", android.priority "normal", android.ttl "3600s" and android.notification.channel_id "timers.v1"
    And message.data holds only string values and no reserved key
    When the device has target_kind "fcm_registration_token"
    Then the message has "token" and no "fid"

  @edge
  Scenario: A retry never outlives the intent
    Given a queued delivery whose intent expires at "2026-10-21T12:05:00Z" and FCM answered 503 with Retry-After 600
    When the dispatcher plans the retry
    Then the delivery becomes failed with provider_status "expired" and no request is sent after "2026-10-21T12:05:00Z"

  @security
  Scenario: Tokens never leave the server
    When I send GET /api/push/state as the owner of "acc-ann"
    Then the response contains no token value
    And the logs and analytics events of a full send contain no token, JWT or access token
