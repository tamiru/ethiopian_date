# EthiopianDate 3.0 — API redesign

Status: proposal · Target version: 3.0.0 · Current version: 2.3.1

## 1. Why

Today the gem is a module of mixin methods (`fromEthiopicToGregorian`,
`fromGregorianToEthiopic`, `to_gregorian`, `ethiopic_date_format`) that callers
`include` into their own classes. Running the current code shows these problems:

| # | Problem | Evidence |
|---|---------|----------|
| 1 | `to_gregorian` crashes outside Rails | `"7/3/2019".present?` → `NoMethodError` (`present?` is ActiveSupport) |
| 2 | Invalid dates are accepted silently and roll over | `fromEthiopicToGregorian(2016, 13, 6)` → 2024‑09‑11 (2016 has only 5 Pagume days); `(2016, 14, 40)` → 2024‑11‑14 |
| 3 | The two directions return different types | Ethiopic→Gregorian returns a `Date`; Gregorian→Ethiopic returns the String `"2019-3-7"` |
| 4 | A public constant is mutated at runtime | `gregorian_from_jdn` writes `MonthDays[2] = 29`, which is not thread-safe and breaks once the constant is frozen |
| 5 | Namespace pollution | `include EthiopianDate` puts camelCase methods and constants into the caller's class |
| 6 | Hand-rolled Gregorian↔JDN maths | ~40 lines reimplement what `Date#jd` / `Date.jd` already do correctly |
| 7 | No tests, placeholder README and gemspec summary | `spec/` and `test/` don't exist; the README still has the bundler TODOs |
| 8 | `AmharicDays` is defined but never used, and there is no way to get the weekday name | — |

## 2. Goals and non-goals

**Goals**
- A small immutable value object, `EthiopianDate::Date`, that behaves like Ruby's `::Date`.
- Symmetric conversion with the same return types in both directions.
- Strict validation that raises `EthiopianDate::InvalidDateError`.
- Amharic and transliterated formatting, including weekday names and Ge'ez numerals as an option.
- No runtime dependencies (only stdlib `date`), so it works in and out of Rails.
- Keep 2.x callers working through deprecated shims for the whole 3.x series.

**Non-goals (for 3.0)**
- Time of day / Ethiopian clock hours (the 6-hour offset). Possible 3.x add-on.
- Amete Alem (pre-year-1) era arithmetic. Today's code branches on it but
  doesn't round-trip correctly. 3.0 supports Amete Mihret years ≥ 1 and raises
  for others (see Open questions).
- Parsing free-form Amharic text.

## 3. Calendar rules the code relies on

- 13 months: months 1–12 have 30 days; month 13 (ጳጉሜን, Pagume) has 5 days,
  or 6 in a leap year.
- Leap year (Amete Mihret): `year % 4 == 3`. For example, 2015 is a leap year,
  so 2015‑13‑06 is valid and 2016‑13‑06 is not.
- Epoch: JDN of 1 Meskerem 1 AM = `1_724_221` (the current
  `JD_EPOCH_OFFSET_AMETE_MIHRET + 365`).
- Ethiopic → JDN: `EPOCH + 365*(y-1) + y/4 + 30*(m-1) + (d-1)`.
- JDN → Ethiopic: `r = (jdn - 1_723_856) % 1461`, `n = r % 365 + 365*(r/1460)`,
  `y = 4*((jdn-1_723_856)/1461) + r/365 - r/1460`, `m = n/30 + 1`, `d = n%30 + 1`.
  This is the existing formula, kept.
- Gregorian ↔ JDN: delegate to `::Date#jd` and `::Date.jd`. Watch out for
  calendar reform. Ruby's `::Date` defaults to `Date::ITALY`, which uses
  Julian dates before 1582‑10‑15, while the current hand-rolled code produces
  proleptic-Gregorian y/m/d and then feeds it to `Date.new`. Before 1582 the
  result is therefore off by days: Ethiopic 1‑1‑1 comes out as JDN 1 724 219,
  not 1 724 221. 3.0 always converts by JDN, so the JDN is right whatever
  calendar `::Date` uses. `to_gregorian(start = ::Date::ITALY)` lets callers
  pass `::Date::GREGORIAN` to get proleptic dates.

Using JDN as the single pivot lets one class do comparison, arithmetic, weekday
and conversion.

## 4. Public API

```ruby
require "ethiopian_date"

# Construction
ed = EthiopianDate::Date.new(2019, 3, 7)        # raises InvalidDateError if invalid
EthiopianDate::Date.valid?(2016, 13, 6)          # => false
EthiopianDate::Date.today                        # uses ::Date.today
EthiopianDate::Date.from_gregorian(::Date.new(2026, 11, 16))  # also accepts Time / DateTime
EthiopianDate::Date.from_jd(2_461_361)
EthiopianDate::Date.parse("2019-03-07")          # ISO-like y-m-d
EthiopianDate::Date.parse("07/03/2019", format: :dmy)  # legacy 2.x slash form

# Readers
ed.year   # => 2019
ed.month  # => 3
ed.day    # => 7
ed.jd     # => 2461361
ed.wday   # => 1 (0 = Sunday, same as ::Date)
ed.leap?  # => false

# Conversion
ed.to_gregorian   # => #<Date: 2026-11-16>  (a ::Date)
ed.to_date        # alias of to_gregorian, so it duck-types with Rails helpers
::Date.new(2026, 11, 16).to_ethiopian   # opt-in refinement, see §6

# Arithmetic and comparison (Comparable, by jd)
ed + 10           # => EthiopianDate::Date (2019-03-17)
ed - 7            # => EthiopianDate::Date
ed - other_ed     # => Integer (days between)
ed.next_month     # clamps the day (e.g. 13-06 → next year's 01-06 is fine; 30th → Pagume 5/6)
ed.next_year      # Pagume 6 in a leap year → Pagume 5 in a common year
ed < other_ed; (a..b).each { }   # Range support via #succ

# Formatting
ed.to_s                     # => "2019-03-07"
ed.month_name               # => "ኅዳር"
ed.month_name(:latin)       # => "Hidar"
ed.day_name                 # => "ሰኞ"
ed.strftime("%B %d ቀን %Y ዓ.ም")   # => "ኅዳር 07 ቀን 2019 ዓ.ም"
ed.strftime("%A, %B %-d, %Y", locale: :latin)  # => "Segno, Hidar 7, 2019"
ed.to_geez                  # => "ኅዳር ፯ ፳፻፲፱"  (Ge'ez numerals)
ed.inspect                  # => "#<EthiopianDate::Date 2019-03-07 (2026-11-16)>"

# Hash / equality — usable as Hash keys, == by jd
ed == EthiopianDate::Date.new(2019, 3, 7)  # => true
```

### strftime directives

| Directive | Meaning |
|-----------|---------|
| `%Y` `%y` | year, 2‑digit year |
| `%m` `%-m` | month number, padded or unpadded |
| `%d` `%-d` `%e` | day |
| `%B` | month name in the locale |
| `%b` | abbreviated month name |
| `%A` / `%a` | weekday name, full or short |
| `%j` | day of year (1–366) |
| `%F` | `%Y-%m-%d` |
| `%%` | literal `%` |

The Gregorian-specific directives (`%U`, `%W`, `%G`, …) are unsupported and
raise `ArgumentError`.

### Errors

```ruby
module EthiopianDate
  class Error < StandardError; end              # already exists, keep it
  class InvalidDateError < Error; end           # bad y/m/d, out-of-range era
  class ParseError < InvalidDateError; end      # unparseable string
end
```

Every constructor validates its input. Nothing rolls over silently.

## 5. Internal structure

```
lib/
  ethiopian_date.rb               # requires, errors, legacy shim include
  ethiopian_date/version.rb
  ethiopian_date/calendar.rb      # pure functions: leap?, days_in_month, jd_from_ymd, ymd_from_jd
  ethiopian_date/date.rb          # value class (Comparable), arithmetic, conversion
  ethiopian_date/locale.rb        # frozen month/day name tables (:amharic, :latin)
  ethiopian_date/formatter.rb     # strftime + Ge'ez numerals
  ethiopian_date/core_ext.rb      # opt-in refinement: ::Date#to_ethiopian
  ethiopian_date/legacy.rb        # 2.x method names, deprecated
```

- `Calendar` is a `module_function` module: stateless, with no mutable
  constants. Every table is `.freeze`d, and the files use
  `# frozen_string_literal: true`.
- `Date` stores only `@jd`, plus `@year/@month/@day` computed once in
  `initialize`, and then freezes itself.
- `Formatter` keeps the string handling out of the date class.

## 6. Core extensions are opt-in

Monkey-patching `::Date` globally is surprising, so it's offered as a refinement:

```ruby
using EthiopianDate::CoreExt
::Date.today.to_ethiopian   # => EthiopianDate::Date
```

Rails users who want it everywhere can call `require "ethiopian_date/core_ext/global"`.

## 7. Backward compatibility (2.x → 3.x)

`lib/ethiopian_date/legacy.rb` keeps every 2.x public method, with the same
signature and the same return type, and emits `warn(..., category: :deprecated)`
once per method:

| 2.x | 3.x replacement | 2.x behaviour kept |
|-----|-----------------|--------------------|
| `fromEthiopicToGregorian(y, m, d)` | `EthiopianDate::Date.new(y, m, d).to_gregorian` | returns `::Date` |
| `fromGregorianToEthiopic(y, m, d)` | `EthiopianDate::Date.from_gregorian(::Date.new(y, m, d))` | returns `"y-m-d"` String, unpadded |
| `to_gregorian("dd/mm/yyyy")` | `EthiopianDate::Date.parse(s, format: :dmy).to_gregorian` | returns `nil` for nil/blank, **without** needing ActiveSupport |
| `ethiopic_date_format("y-m-d")` | `#strftime("%B %d, %Y")` | same output string |
| `AmharicMonths`, `AmharicDays`, `Nmonths`, `MonthDays` | `EthiopianDate::Locale` | constants kept, now frozen |

There is one deliberate behaviour change, which is the reason for the major
version bump. The legacy methods now **raise `InvalidDateError`** on invalid
input instead of rolling over. If some callers need the old rollover, set
`EthiopianDate.legacy_lenient = true` to restore it for the shims only.

The shims are removed in 4.0.

## 8. Testing

Minitest (stdlib, no extra dependency), in `test/`:

1. **Known fixtures.** 1 Meskerem 2016 = 2023‑09‑12 (the year after a leap
   year), 1 Meskerem 2017 = 2024‑09‑11, 29 Tahsas 2018 (Genna) = 2026‑01‑07,
   and 7 Hidar 2019 = 2026‑11‑16 (JDN 2 461 361).
2. **Round-trip property.** For every JDN in a span of about 1000 years,
   `Date.from_jd(jd).jd == jd` and `from_gregorian(g).to_gregorian == g`.
3. **Validation.** Month 0 and 14, day 0 and 31, Pagume 6 in common years
   versus leap years, and year 0.
4. **Arithmetic edge cases.** `next_month` from day 30 into Pagume, and
   `next_year` from leap Pagume 6.
5. **Legacy shims.** Each one returns exactly what 2.3.1 returns for valid
   input, captured as golden values from the current code.
6. **No ActiveSupport.** The test suite runs without Rails loaded.

CI: add a GitHub Actions matrix for Ruby 2.7, 3.1, 3.3 and head. The gemspec
says `>= 2.6`, which is EOL, so raise it to `>= 2.7`.

## 9. Housekeeping in the same release

- Fill in the gemspec `summary`, and set `changelog_uri`.
- Remove the committed `ethiopian_date-1.1.0.gem` and `.idea/` from git, and
  add them to `.gitignore`.
- Rewrite the README with installation, quick start, the API table and a
  migration section.
- Bring `CHANGELOG.md` up to date. It still stops at 0.1.0.

## 10. Rollout

1. **3.0.0.pre1.** Add `Calendar`, `Date`, tests and the legacy shims (no
   deprecation warnings yet).
2. **3.0.0.** Add the formatter and locales, turn on the deprecation warnings,
   publish the README and migration guide.
3. **3.1.** Optionally add Ethiopian time of day and Amete Alem support.

## 11. Open questions

1. **Month and day spellings.** The current tables use ህዳር / ታህሳስ / ነሃሴ / ጳጉሜ
   and ሮብ / ሓሙስ / ኣርብ. The more common Amharic spellings are ኅዳር / ታኅሣሥ /
   ነሐሴ / ጳጉሜን and ረቡዕ / ሐሙስ / ዓርብ. Should 3.0 switch the `:amharic` locale
   and keep the old spellings available as `:amharic_legacy`, or keep them
   as they are?
2. **Amete Alem.** Is there real demand for pre-year-1 dates? If not, 3.0 raises
   for `year < 1`.
3. **Default `to_s`.** Should it be ISO-like `2019-03-07` (machine-friendly),
   or Amharic `ኅዳር 07, 2019` (what `ethiopic_date_format` produces today)?
   This proposal picks ISO.
4. **Lenient flag.** Is it needed at all, or can every caller live with
   strict validation?
