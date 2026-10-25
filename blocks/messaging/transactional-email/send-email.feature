Feature: Send Transactional Email
  As a platform
  I want to send transactional emails triggered by business events
  So that end users receive timely notifications (order confirmations, welcome emails, etc.)

  Background:
    Given the app is configured with EMAIL_PROVIDER "resend"
    And the app is configured with EMAIL_PROVIDER_API_KEY "re_test_abc123"
    And the app is configured with FROM_EMAIL "hello@merchant.com"
    And the app is configured with FROM_NAME "Merchant Store"
    And the current shop_id is "shop_001"

  @happy
  Scenario: Send welcome email on user.created event
    Given an active email template with slug "welcome" exists for shop "shop_001"
    And the template subject is "Welcome to {{shop_name}}, {{user_name}}!"
    And the template body contains "<h1>Hello {{user_name}}</h1><p>Welcome aboard!</p>"
    And the recipient "alice@example.com" is not on the suppression list
    And the email provider returns success with message_id "msg_welcome_001"
    When the event "user.created" fires with:
      | field          | value              |
      | event_id       | evt_u_001          |
      | customer_email | alice@example.com  |
      | user_name      | Alice              |
      | shop_name      | Merchant Store     |
    Then an email_log entry is created with idempotency_key "evt_u_001:welcome:alice@example.com"
    And the email_log status transitions from "queued" to "sent"
    And the email_log provider_message_id is "msg_welcome_001"
    And the email_log subject is "Welcome to Merchant Store, Alice!"
    And the email provider received a request with to "alice@example.com"
    And an "email.sent" event is emitted with template_slug "welcome"

  @happy
  Scenario: Send order confirmation on order.created event
    Given an active email template with slug "order-confirmation" exists for shop "shop_001"
    And the template subject is "Order #{{order_number}} confirmed"
    And the recipient "bob@example.com" is not on the suppression list
    And the email provider returns success with message_id "msg_order_001"
    When the event "order.created" fires with:
      | field          | value             |
      | event_id       | evt_o_042         |
      | customer_email | bob@example.com   |
      | order_number   | 1042              |
      | order_total    | $89.99            |
    Then an email_log entry is created with idempotency_key "evt_o_042:order-confirmation:bob@example.com"
    And the email_log status is "sent"
    And the rendered subject is "Order #1042 confirmed"

  @happy
  Scenario: Template variable injection renders correctly
    Given an active email template with slug "shipping-notification" exists for shop "shop_001"
    And the template subject is "Your order is on its way!"
    And the template body contains "<p>Hi {{customer_name}}, tracking: {{tracking_number}} via {{carrier}}</p>"
    And the email provider returns success with message_id "msg_ship_001"
    When the event "order.shipped" fires with:
      | field           | value               |
      | event_id        | evt_s_010           |
      | customer_email  | carol@example.com   |
      | customer_name   | Carol               |
      | tracking_number | 1Z999AA10123456784  |
      | carrier         | UPS                 |
    Then the email body sent to the provider contains "tracking: 1Z999AA10123456784 via UPS"
    And the email body sent to the provider contains "Hi Carol"

  @happy
  Scenario: Merchant-specific template overrides platform default
    Given a platform default template with slug "welcome" exists (shop_id is null)
    And a merchant-specific template with slug "welcome" exists for shop "shop_001"
    And the merchant template subject is "Welcome to OUR store, {{user_name}}!"
    And the email provider returns success
    When the event "user.created" fires for shop "shop_001"
    Then the rendered subject uses the merchant-specific template
    And the rendered subject is NOT from the platform default

  @error
  Scenario: Provider returns permanent error (4xx)
    Given an active email template with slug "welcome" exists for shop "shop_001"
    And the email provider returns 422 with error "Invalid 'to' address"
    When the event "user.created" fires with customer_email "not-an-email"
    Then the email_log status is "failed"
    And the email_log error contains "Invalid 'to' address"
    And the email provider is called exactly 1 time (no retry on 4xx)
    And an "email.failed" event is emitted

  @error
  Scenario: Provider returns transient error then recovers
    Given an active email template with slug "welcome" exists for shop "shop_001"
    And the email provider returns 500 on the first call
    And the email provider returns 503 on the second call
    And the email provider returns success with message_id "msg_retry_001" on the third call
    When the event "user.created" fires with customer_email "alice@example.com"
    Then the email provider is called 3 times
    And the email_log status is "sent"
    And the email_log provider_message_id is "msg_retry_001"

  @error
  Scenario: Provider fails all retry attempts
    Given an active email template with slug "welcome" exists for shop "shop_001"
    And EMAIL_MAX_RETRIES is 3
    And the email provider returns 500 on all calls
    When the event "user.created" fires with customer_email "alice@example.com"
    Then the email provider is called 3 times
    And the email_log status is "failed"
    And the email_log error indicates max retries exceeded
    And an "email.failed" event is emitted

  @edge
  Scenario: Skip send if template is inactive
    Given an email template with slug "welcome" exists for shop "shop_001" with active=false
    When the event "user.created" fires with customer_email "alice@example.com"
    Then no email is sent via the provider
    And no email_log entry is created with status "queued"

  @edge
  Scenario: Skip send if template does not exist
    Given no email template with slug "welcome" exists for shop "shop_001"
    And no platform default template with slug "welcome" exists
    When the event "user.created" fires with customer_email "alice@example.com"
    Then no email is sent via the provider

  @edge
  Scenario: Duplicate event does not send twice (idempotency)
    Given an active email template with slug "welcome" exists for shop "shop_001"
    And an email_log entry already exists with idempotency_key "evt_u_001:welcome:alice@example.com"
    When the event "user.created" fires again with event_id "evt_u_001" and customer_email "alice@example.com"
    Then no email is sent via the provider
    And no new email_log entry is created

  @edge
  Scenario: Skip send for suppressed recipient
    Given an active email template with slug "welcome" exists for shop "shop_001"
    And "alice@example.com" is on the suppression list for shop "shop_001" with reason "hard_bounce"
    When the event "user.created" fires with customer_email "alice@example.com"
    Then no email is sent via the provider
    And an email_log entry is created with status "failed" and error containing "suppressed"

  @security
  Scenario: Rate limit per shop enforced
    Given an active email template with slug "welcome" exists for shop "shop_001"
    And EMAIL_RATE_LIMIT_PER_SHOP is 2
    And 2 emails have already been sent for shop "shop_001" in the current hour
    When the event "user.created" fires with customer_email "newuser@example.com"
    Then no email is sent via the provider
    And the error indicates "rate_limit_exceeded"

  @security
  Scenario: Rate limit per recipient enforced
    Given an active email template with slug "order-confirmation" exists for shop "shop_001"
    And EMAIL_RATE_LIMIT_PER_RECIPIENT is 3
    And 3 emails have already been sent to "alice@example.com" for shop "shop_001" in the current hour
    When the event "order.created" fires with customer_email "alice@example.com"
    Then no email is sent via the provider
    And the error indicates "rate_limit_exceeded"

  @security
  Scenario: CRLF injection in recipient rejected
    Given an active email template with slug "welcome" exists for shop "shop_001"
    When the event "user.created" fires with customer_email "alice@example.com\r\nBCC:attacker@evil.com"
    Then no email is sent via the provider
    And the error indicates invalid recipient
