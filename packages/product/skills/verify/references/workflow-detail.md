# Workflow detail

## Outcome metrics

- Set the metric, baseline, threshold and action on a miss before seeing results.
- Use completion without help, median and high-percentile time, error recovery, and retention by cohort. Page views and clicks do not count alone.
- For a shipped change, compare production telemetry before and after the deploy.


## Verdict

| Verdict | Issue it when |
|---|---|
| Pass | Every required check ran and met its criterion |
| Fail | Any check ran and missed its criterion |
| Blocked | Nothing failed, and a required check did not run |

Anything not run is Blocked. Fail outranks Blocked.
