# VendorTruth

Makes aux use the vendor prices **this server** actually pays, instead of a
static table compiled for vanilla.

You already have the detector. You did not have prices you could bet gold on.

## The short version

aux finds auctions worth buying to vendor. Search the auction house with:

```
vendor-profit/5g
```

That lists everything whose buyout is at least 5 gold below what a vendor pays
for it. `bid-vendor-profit/5g` does the same against the bid price.

The problem was never the finding. aux asks its own cache first — prices it
watched a vendor quote, so they are true here — and falls back to
`ShaguTweaks.SellValueDB`, about twenty thousand items compiled for
vanilla/Turtle. On OctoWoW that table is wrong in the direction that costs
money.

## What was wrong

Measured against prices recorded at real vendors on this realm:

| | items |
|---|---|
| Static table claims **more** than a vendor here pays | **1,251** — by up to 6g25s each |
| Static table prices items vendors here **refuse outright** | **223** — up to 18g88s each |
| Static table claims less than is paid | 801 — only hides opportunities |

The 223 are the dangerous ones. An item the table values at 18 gold looks like
the best flip on the auction house, and the vendor will not take it. Nothing
warns you; you simply own it. Across them the table advertises about **398
gold** of value that does not exist.

The overstatements are not random either — a whole run of items around
18830–18877 is overstated by a consistent factor of roughly 1.63, which is a
server that re-tuned its vendor prices and a table that never heard about it.

## What this does

The SellValue addon has been quietly recording what vendors actually pay as
you play, and aux never looks at it. This copies those prices over the static
ones before aux reads them, so the filter, ShaguTweaks' tooltips and its
sell-junk all work from what this server does.

On the current data:

```
  prices from this server now in use : 13795
  corrected from the static table    : 3904
  priced items vendors here refuse   : 217
  still static only, tooltip-flagged : 3241
```

A recorded zero is copied across as deliberately as a price is: SellValue
writes zero to mean *the vendor would not buy this*, which is a fact about this
server and the one the static table most needs correcting on.

Fractional prices — SellValue divides a stack's total by its size — are rounded
**down**. Understating a vendor price costs a missed flip; overstating it costs
gold, and that asymmetry is the entire reason this exists.

## What it cannot do

It cannot invent a price for an item nobody has sold here yet. Those **3,241**
keep the static value and get a line on their tooltip:

> vendor price unverified on this server

Only the unverified are flagged. If every item carried a warning it would be
noise, and noise gets read as decoration.

The honest way to clear one is to sell a single copy at a vendor and watch
SellValue record it. After that it is verified for good.

## `/vt watch` — what is actually worth looking for

Scanning the whole auction house for vendor profit costs minutes. On this
server the entire opportunity is a few silver an item, so that maths does not
work: you cannot spend ten minutes to make thirteen silver.

aux has already done the looking. Every scan it runs leaves the lowest buyout
it saw in its history, so the items that get listed below vendor price are
already on record. `/vt watch` compares that record against the corrected
vendor prices and lists them, best margin first — then you search for those
few by **name**, which is a Blizzard query and pulls only the matching pages.
Seconds instead of minutes.

### Set your expectations

Measured on 12,610 items of real scan history:

| | |
|---|---|
| Items ever listed below vendor | **68** |
| With a verified price, this character's faction | **40** |
| Best margin seen | **13s 60c** per unit |
| Average margin | **90c** per unit |

This is silver, not gold. `vendor-profit/5g` would return nothing — there has
never been a 5 gold vendor margin in the whole history. A realistic threshold
is `vendor-profit/10s`, and the honest use is checking the watchlist when you
are at the auction house anyway rather than making a trip for it.

Guesses are excluded by default. A margin of a few silver cannot absorb one
wrong vendor price, so only prices confirmed here are listed; `/vt watch all`
includes the unverified if you want them.

The list only knows what aux has already scanned. More scanning finds more.

## Sharing a scan between your accounts

A scan is minutes of work and the result is the same for everyone looking at
the same auction house, so doing it once per account is waste. **Scan on the
bank alt; the main on the other account has the prices without opening the
auction house at all.**

SavedVariables cannot cross accounts — the account name is in the path —
so this goes through Nampower's `CustomData`, which belongs to the
installation rather than the account. Same trick Bagertz uses for inventories.

It happens by itself. The scan is written out when you **close the auction
house** (a scan has just finished and the client is idle) and again at logout
as a backstop; the other account picks it up **at login**. `/vt share` and
`/vt pull` force either half if you do not want to relog.

**Scoped by realm, not by faction.** In vanilla the two factions have separate
auction houses and merging across them would mean prices from a market you
cannot visit — but this server runs a shared one, so a Horde scan is just
as true for an Alliance character. aux still files its history per faction
internally; the data is interchangeable here even though its storage is not,
which is why the file is read into whichever table the current character uses.
A scan from a different **realm** is refused outright.

Merging only ever **lowers** a price. What aux keeps is "the cheapest this was
seen for", so between two honest looks at the same auction house the lower one
is the answer — a merge that could raise a figure would be discarding
something that was really seen. Only that one field is touched; aux's push
schedule and its record of previous days are left exactly as it wrote them.

## Commands

| | |
|---|---|
| `/vt` | what was corrected, and how much is still unverified |
| `/vt watch` | items aux has seen listed below vendor price, best first |
| `/vt watch all` | the same, including unverified prices |
| `/vt share` | write this account's scan out now |
| `/vt pull` | take in another account's scan now |
| `/vt <shift-clicked item>` | what a vendor pays for it, and whether that figure has been confirmed here |

## Requires

- **SellValue** — the source of truth. Without it there is nothing to correct with.
- **ShaguTweaks** — provides the table aux falls back to.
- **aux** — optional. The corrections help its filter, but ShaguTweaks' own
  tooltips and sell-junk benefit either way.

Missing either of the first two and the addon says so rather than quietly doing
nothing, because silently failing would leave you believing your prices were
fixed.

## Tests

```bash
lua VendorTruth/tools/test_vendortruth.lua     # from the AddOns directory
```

Run against the **real** tables — the actual ShaguTweaks data and the actual
prices SellValue recorded here — rather than fixtures. Fixtures would prove the
code does what it was written to do; these prove it does the thing worth doing,
on the numbers that caused the problem. The two items it names are real: one
the table values at nearly nineteen gold that no vendor here will buy, and one
it overstates by six.

58 checks, mutation-checked twelve ways — including that aux's `next_push`
timestamp is never read as a price, which would make every item on the auction
house look like 170,000 gold of profit.
