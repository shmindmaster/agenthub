# Scoring

Read when computing a score or a band.

All three scores run 0 to 100. Round to a whole number. Record the component ratings beside the total so a later run can see what moved.

## 1. Product fit

How well one product matches one opportunity.

Rate each fit criterion 0 to 5, multiply by its weight, and scale the weighted sum to 0 to 100. The criteria and weights are the ones recorded in the newest `Portfolio Funding Strategy` file. Reuse them unchanged so scores stay comparable between runs.

If that file names the criteria without listing them, ask the owner for the list once, write it into the new strategy file under the matrix, and score from there. Do not invent criteria or weights, and leave `fit_score` empty until they are known.

Rate from recorded evidence. A criterion with no evidence scores 0, not a guess at the middle.

## 2. Strategic priority

Whether the opportunity is worth the effort now.

| Component | Weight | Rate 0 to 100 on |
|---|---|---|
| Product fit | 60% | The fit score of the best product |
| Net funding value | 20% | Cash after equity given up, fees, cost share, travel and the hours the application takes. Credits and in-kind support count only where they replace real spend |
| Application feasibility | 10% | Whether the required artifacts, registrations and partners can exist by the deadline |
| Long-term value | 10% | What a win or a serious attempt leaves behind: reusable narrative, a funder relationship, a credential |

Bands: P1 is 85 and above, P2 is 70 to 84, P3 is 55 to 69, P4 is below 55.

Confidence is separate from the score: High when every deciding fact is CONFIRMED, Medium when one is EXPECTED or FORECAST, Low when one is UNVERIFIED.

Decisions follow the band and the calendar: apply, prepare (worth it, not yet reachable), monitor (terms or dates not published), or skip with a reopen condition.

## 3. Engineering reprioritization

Whether a piece of engineering or preparation work should move up because funding depends on it.

| Component | Weight | Rate 0 to 100 on |
|---|---|---|
| Funding impact | 35% | How many scored opportunities it unblocks or strengthens, weighted by their priority |
| Commercial value | 25% | Whether customers need it regardless of any funder |
| Feasibility | 25% | Effort and elapsed time against the nearest deadline it serves |
| Reuse | 15% | Whether other products or applications can use the result |

Score a change only when a named opportunity depends on it. Work that serves no opportunity and no customer goes on the defer list without a score. Owner-only prerequisites, such as a registration or an ownership record, are listed with their lead time and marked as owner actions.

A change that scores high on funding impact and low on commercial value is a warning, not a recommendation: say that it bends the product toward a funder.
