Feature: Server day, time zones and clock manipulation
  As a player who travels or changes the device clock
  I want the day to be decided by the server from my account's zone
  So that neither a flight nor a clock change gives or takes a day unfairly

  Background:
    Given the app is configured for tenant "tenant-001"
    And the calendar and settings from fixtures/calendar-config.json
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario Outline: The same instant is a different date in different zones
    Given the row "<instant>" in zone "<zone>" in fixtures/timezone-vectors.json instant_to_day_key
    When day_key is computed
    Then the result is "<day_key>"

    Examples:
      | zone                | instant              | day_key    |
      | America/Los_Angeles | 2026-10-27T12:00:00Z | 2026-10-27 |
      | Asia/Tokyo          | 2026-10-27T12:00:00Z | 2026-10-27 |
      | Pacific/Kiritimati  | 2026-10-27T12:00:00Z | 2026-10-28 |
      | Etc/UTC             | 2026-12-31T23:59:59Z | 2026-12-31 |
      | Etc/UTC             | 2027-01-01T00:00:00Z | 2027-01-01 |

  @edge
  Scenario Outline: Daylight-saving days last 23 or 25 hours and stay one day
    Given the row for zone "<zone>" and day "<day_key>" in fixtures/timezone-vectors.json day_bounds
    When day_start and day_end are computed
    Then the day runs from "<starts_at>" to "<ends_at>" and lasts <hours> hours
    And ends_at in the view equals that end instant

    Examples:
      | zone                | day_key    | starts_at            | ends_at              | hours |
      | America/New_York    | 2026-03-08 | 2026-03-08T05:00:00Z | 2026-03-09T04:00:00Z | 23    |
      | America/New_York    | 2025-11-02 | 2025-11-02T04:00:00Z | 2025-11-03T05:00:00Z | 25    |
      | America/Havana      | 2026-03-08 | 2026-03-08T05:00:00Z | 2026-03-09T04:00:00Z | 23    |
      | Australia/Lord_Howe | 2026-10-04 | 2026-10-03T13:30:00Z | 2026-10-04T13:00:00Z | 23.5  |
      | Australia/Lord_Howe | 2026-04-05 | 2026-04-04T13:00:00Z | 2026-04-05T13:30:00Z | 24.5  |

  @edge
  Scenario: Two claims inside one 23-hour day are one day
    Given "acc-ann" has zone "America/New_York" and 1 qualifying action
    And the clock is "2026-03-08T05:00:00Z"
    When I send POST /api/streak/claim and then again at "2026-03-09T03:59:59Z"
    Then the second response is already_claimed true
    When the clock is "2026-03-09T04:00:00Z" and I send POST /api/streak/claim
    Then a new claim for "2026-03-09" is created and the streak grows by 1

  @edge
  Scenario Outline: Month ends, year ends and the leap day are single days
    Given the pair "<from>" to "<to>" in fixtures/timezone-vectors.json consecutive_pairs
    When day_index differences are computed
    Then the difference is <difference> and missed_days is <missed>

    Examples:
      | from       | to         | difference | missed |
      | 2026-10-31 | 2026-11-01 | 1          | 0      |
      | 2026-12-31 | 2027-01-01 | 1          | 0      |
      | 2027-02-28 | 2027-03-01 | 1          | 0      |
      | 2028-02-28 | 2028-02-29 | 1          | 0      |
      | 2028-02-29 | 2028-03-01 | 1          | 0      |
      | 2028-02-28 | 2028-03-01 | 2          | 1      |

  @edge
  Scenario: A date the zone skipped is not a missed day
    Given the case skipped_date in fixtures/timezone-vectors.json for zone "Pacific/Apia"
    And a streak of 5 credited on "2011-12-29"
    When a claim arrives at "2011-12-30T22:00:00Z" with day_key "2011-12-31"
    Then the calendar difference is 2 and the missed days after exclusion are 0
    And the streak is 6

  @happy
  Scenario: The first zone set is free and later changes are rate-limited
    Given the sequence timezone_rate_limit in fixtures/timezone-vectors.json
    When each request arrives at its listed instant
    Then each answer equals the listed expect value
    And the rejected answers carry the listed next_change_at

  @security
  Scenario Outline: Offsets, abbreviations and free text are not zones
    When I send PUT /api/streak/timezone with { "timezone": "<value>" }
    Then the response status is 422 with error "invalid_timezone"

    Examples:
      | value              |
      |                    |
      | Mars/Olympus_Mons  |
      | UTC+2              |
      | +02:00             |
      | europe/berlin      |

  @edge
  Scenario Outline: A zone change never ends the day in progress
    Given the switch case "<note>" in fixtures/timezone-vectors.json timezone_switch
    When the player in "<old_zone>" requests "<new_zone>" at "<requested_at>"
    Then timezone_effective_at is "<effective_at>"
    And the new zone's date at that instant is "<new_day_key>"
    And the excused dates are <excused>

    Examples:
      | note             | old_zone            | new_zone            | requested_at         | effective_at         | new_day_key | excused      |
      | flying east      | America/Los_Angeles | Asia/Tokyo          | 2026-10-28T04:00:00Z | 2026-10-28T07:00:00Z | 2026-10-28  | none         |
      | flying west      | Asia/Tokyo          | America/Los_Angeles | 2026-10-27T12:00:00Z | 2026-10-27T15:00:00Z | 2026-10-27  | none         |
      | 25-hour offset   | Pacific/Pago_Pago   | Pacific/Kiritimati  | 2026-10-27T20:00:00Z | 2026-10-28T11:00:00Z | 2026-10-29  | 2026-10-28   |

  @edge
  Scenario: A day still unclaimed at request time stays claimable until it ends in the old zone
    Given "acc-ann" is in "America/Los_Angeles", has a streak of 4 settled through "2026-10-26" and 1 qualifying action
    And she requested "Asia/Tokyo" at "2026-10-28T04:00:00Z"
    When she claims at "2026-10-28T05:00:00Z"
    Then the claim is for day_key "2026-10-27" and the streak is 5

  @security
  Scenario: The device clock changes nothing
    Given the device clock is set to "2030-01-01T00:00:00Z" and every request header Date says so
    When I send GET /api/streak and POST /api/streak/claim
    Then the day_key used is "2026-10-27" from the server clock
    And the view's ends_at is computed from the server clock

  @security
  Scenario: A claim whose date is more than one day from the UTC date is refused
    Given a fault makes the computed day_key "2026-10-30" at the server instant "2026-10-27T12:00:00Z"
    When a claim is attempted
    Then the claim is refused, an alert is raised, and no row is written
