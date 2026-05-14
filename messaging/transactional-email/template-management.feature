Feature: Email Template Management
  As a merchant admin
  I want to manage email templates through the admin panel
  So that I can customize transactional emails my app sends

  Background:
    Given I am authenticated as an admin for shop "shop_001"
    And the API base URL is "/api/email-templates"

  @happy
  Scenario: List all templates for the shop
    Given the following email templates exist for shop "shop_001":
      | slug                | subject_template                       | active |
      | welcome             | Welcome, {{user_name}}!                | true   |
      | order-confirmation  | Order #{{order_number}} confirmed      | true   |
      | password-reset      | Reset your password                    | false  |
    When I send GET /api/email-templates
    Then the response status is 200
    And the response contains 3 templates
    And each template includes id, slug, subject_template, category, active, created_at

  @happy
  Scenario: Create a new template
    When I send POST /api/email-templates with:
      """json
      {
        "slug": "shipping-notification",
        "subject_template": "Your order has shipped!",
        "body_template": "<h1>Hi {{customer_name}}</h1><p>Tracking: {{tracking_number}}</p>",
        "category": "transactional"
      }
      """
    Then the response status is 201
    And the response contains the created template with id and timestamps
    And the template is associated with shop "shop_001"
    And the template active is true by default

  @happy
  Scenario: Update an existing template
    Given an email template with id "tmpl_001" and slug "welcome" exists for shop "shop_001"
    When I send PUT /api/email-templates/tmpl_001 with:
      """json
      {
        "subject_template": "Welcome aboard, {{user_name}}!",
        "body_template": "<h1>Welcome {{user_name}}</h1><p>New improved content.</p>"
      }
      """
    Then the response status is 200
    And the template subject_template is "Welcome aboard, {{user_name}}!"
    And the template updated_at is later than before the update

  @happy
  Scenario: Delete a template
    Given an email template with id "tmpl_001" and slug "welcome" exists for shop "shop_001"
    When I send DELETE /api/email-templates/tmpl_001
    Then the response status is 204
    And the template no longer appears in GET /api/email-templates

  @happy
  Scenario: Preview template with sample data
    Given an email template with id "tmpl_001" exists with:
      | subject_template | Order #{{order_number}} confirmed         |
      | body_template    | <p>Hi {{customer_name}}, total: {{order_total}}</p> |
    When I send POST /api/email-templates/tmpl_001/preview with:
      """json
      {
        "variables": {
          "order_number": "1042",
          "customer_name": "Alice",
          "order_total": "$89.99"
        }
      }
      """
    Then the response status is 200
    And the response contains rendered subject "Order #1042 confirmed"
    And the response contains rendered body with "Hi Alice, total: $89.99"

  @happy
  Scenario: Duplicate a template
    Given an email template with id "tmpl_001" and slug "welcome" exists for shop "shop_001"
    When I send POST /api/email-templates/tmpl_001/duplicate with:
      """json
      {
        "slug": "welcome-v2"
      }
      """
    Then the response status is 201
    And the response contains a new template with slug "welcome-v2"
    And the new template has a different id than "tmpl_001"
    And the new template body_template matches the original
    And both templates exist in the list

  @happy
  Scenario: Deactivate a template
    Given an email template with id "tmpl_001" and slug "welcome" exists with active=true
    When I send PUT /api/email-templates/tmpl_001 with:
      """json
      { "active": false }
      """
    Then the response status is 200
    And the template active is false
    And subsequent "user.created" events will not trigger the "welcome" email

  @error
  Scenario: Create template with duplicate slug rejected
    Given an email template with slug "welcome" already exists for shop "shop_001"
    When I send POST /api/email-templates with:
      """json
      {
        "slug": "welcome",
        "subject_template": "Another welcome",
        "body_template": "<p>Duplicate</p>"
      }
      """
    Then the response status is 409
    And the response body contains error "template_slug_exists"

  @error
  Scenario: Create template with invalid slug rejected
    When I send POST /api/email-templates with:
      """json
      {
        "slug": "INVALID SLUG!",
        "subject_template": "Test",
        "body_template": "<p>Test</p>"
      }
      """
    Then the response status is 400
    And the response body contains error "invalid_slug"

  @error
  Scenario: Update template from another shop rejected
    Given an email template with id "tmpl_other" exists for shop "shop_002"
    When I send PUT /api/email-templates/tmpl_other with:
      """json
      { "subject_template": "Hacked" }
      """
    Then the response status is 404
    And the template remains unchanged

  @error
  Scenario: Create template with empty body rejected
    When I send POST /api/email-templates with:
      """json
      {
        "slug": "empty-body",
        "subject_template": "Subject",
        "body_template": ""
      }
      """
    Then the response status is 400
    And the response body contains error "body_template_required"

  @edge
  Scenario: Preview escapes HTML in variable values
    Given an email template with body_template "<p>Hi {{name}}</p>"
    When I preview with variables { "name": "<script>alert('xss')</script>" }
    Then the rendered body contains "&lt;script&gt;" (escaped)
    And the rendered body does NOT contain "<script>" (raw)
