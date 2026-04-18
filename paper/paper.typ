#set page(paper: "a4", margin: 2.5cm, numbering: "1")
#set par(justify: true)
#set heading(numbering: "1.")

#let title = "A Comparative Analysis of Monolithic and Microservices Architectures: Evaluating Fault Isolation and Database Resource Contention Through Experimental Stress Testing"
#let authors = "Ahmad Louay, Bahaa El Deen Mohamed, Youssef Khaled"
#let institution = "Sadat Academy for Management Sciences"

#align(center)[
  #text(18pt, weight: "bold")[#title]

  #v(0.5em)
  #authors \
  #institution
]

#v(1em)

= Abstract

Microservices are widely adopted for organizational scalability and service autonomy, but decomposition can introduce additional latency, failure-propagation, and data-tier coordination costs.
This paper presents a controlled benchmark of monolithic and microservices implementations of the same e-commerce workload under equivalent business logic, identical datasets, and comparable compute budgets.
The evaluation covers four scenario families: baseline load, deterministic endpoint failure, fixed latency injection, and database connection pool stress.
Measurements are collected with Apache JMeter and analyzed at run and cross-scenario levels using throughput, latency percentiles, error rates, confidence intervals, architecture deltas, and degradation relative to baseline.

Results show a clear baseline efficiency advantage for the monolith in this environment, while the microservices variant exhibits stronger downstream amplification in composite order flows under injected stress.
Latency injection produces the largest degradation in both architectures, and pool-size sweeps reveal non-monotonic, architecture-dependent trade-offs between throughput, tail latency, and timeout-driven errors.
These findings indicate that architecture choice and resilience tuning should be guided by workload characteristics, reliability targets, and empirical performance evidence rather than style preference alone.

= Introduction

The term "monolith" implies something large and tightly integrated, which reflects a key practical advantage of monolithic software design: one codebase usually simplifies deployment, tracing, and local testing, and often delivers strong baseline performance in many environments @atlassian_microservices_vs_monolith @fowler_monolith_first.
These properties make monolithic architecture a practical choice for early-stage products, where development speed, lower operational complexity, and lower platform overhead are important. In contrast, moving to microservices can be complex and costly and usually requires stronger domain boundaries and operational maturity @taibi2017processes @jamshidi2018microservices.
However, monolithic systems can become harder to evolve at large scale. Tight coupling can slow technology adoption and independent scaling, and major changes may require broad system-level modification rather than service-level evolution @newman_microservices @dragoni_microservices.

Because of these long-term limitations, many organizations shift toward microservices, which decompose the system into smaller independently deployable services with clearer responsibility boundaries @newman_microservices @richardson_microservices.

However, the decentralization inherent in microservices does not come without operational costs. While functional logic is easily partitioned, the data tier often remains a point of contention. In a monolithic system, database interactions are managed through a unified connection pool, optimizing resource utilization. Conversely, a microservices deployment requires each independent service to maintain its own connection overhead. As the number of services scales, this leads to 'connection sprawl,' where the aggregate demand for database handles can exhaust system resources even if the underlying hardware is underutilized.

Furthermore, while microservices are designed to prevent cascading failures—ensuring that a bug in one module does not collapse the entire ecosystem—the inter-service communication overhead introduces new latency patterns. Under peak load, the P95 latency (the time within which 95% of requests are completed) can degrade significantly due to network hops and resource competition, a phenomenon that is often less pronounced in the shared-memory environment of a monolith.


This study quantifies these trade-offs using a controlled benchmark campaign across monolithic and microservices implementations of the same domain. This paper focuses on latency, throughput, error behavior, and connection-pool stress to provide evidence-based guidance on when architectural decomposition introduces measurable infrastructure cost.

= Methodology

== Study Design

This study follows a controlled comparative design to isolate architectural effects under equivalent workload conditions. Experimental interpretation follows standard performance-analysis practice, emphasizing repeatability, controlled variables, and statistical summaries @jain_performance.

== Systems Under Test

Both systems implement the same domain entities (users, products, and orders) and the same business rules for read and order-creation paths.

- The monolith is a single Spring Boot service @spring_boot backed by one relational database and one application connection pool @hikaricp.
- The microservices system includes user, product, and order services behind an API gateway @nginx_gateway; each service owns its database and connection pool.
- Inter-service communication in the microservices variant uses synchronous HTTP principles aligned with REST architecture @rest_fielding.

To preserve fairness, both deployments use the same dataset and comparable total CPU and memory limits at the application tier.

== Execution Environment

All experiments were executed on a single Linux host for both architectures.

- CPU: 12th Gen Intel Core i5-1235U (10 physical cores, 12 logical threads)
- Memory: 24 GB RAM (approximately 23 GiB visible to the OS)
- Platform: Linux x86_64

== Workload Model

Load is generated with Apache JMeter @jmeter using a read-heavy profile intended to represent common catalog traffic.

#table(
  columns: (2fr, 1fr),
  align: (left, center),
  table.header([Operation class], [Share]),
  [Product reads], [50%],
  [User reads], [30%],
  [Order creation], [20%],
)

Each run includes ramp-up, warm-up, and steady-state phases. Warm-up samples are excluded from all reported metrics.

== Experimental Scenarios

This research evaluates four scenario families.

#table(
  columns: (2fr, 1.2fr, 3fr),
  align: (left, center, left),
  table.header([Scenario], [Intent], [Configuration summary]),
  [Baseline], [Reference], [No injected faults or delays; default pool settings],
  [Deterministic endpoint failure], [Failure propagation], [Product-read failures injected for a fixed ID set],
  [Latency injection], [Performance degradation], [Fixed delay injected on product-read path],
  [Pool exhaustion sweep],
  [Data-tier contention],
  [Connection pool sizes swept across #raw("2, 5, 10") with fixed request load],
)

Fault and latency injection are implemented at the same logical point in both architectures (product-read path) and controlled by runtime properties: #raw("chaos.enabled"), #raw("chaos.mode"), #raw("chaos.fault-ids"), and #raw("chaos.latency-ms") @chaos_engineering_principles.

For deterministic failure runs, a request fails if and only if its product ID belongs to a configured fixed set. This avoids random sampling noise and improves reproducibility across repeated runs and across architectures.

== Connection Pool Stress Protocol

For pool stress tests, maximum pool size is varied while request concurrency being constant. This isolates database-handle scarcity from other factors.

- Pool sizes tested: #raw("2, 5, 10")
- Per-size repeated runs are executed and analyzed independently for both architectures
- Per-run environment is reset to avoid state carry-over
- Connection timeout configured at #raw("2000 ms") during pool-stress runs; timeout breaches are counted as request errors
- Pool and connection limits are interpreted with reference to pool configuration behavior and database connection ceilings @hikaricp @postgres_max_connections

== Metrics and Statistical Treatment

This research focuses on the following outcome variables:

- Throughput (requests/second)
- Latency percentiles (P50, P95, P99)
- Error rate and error count
- Time-series behavior for throughput and tail latency

For each scenario, results are reported at run level and as architecture-level aggregates. The analysis pipeline computes means, standard deviations, and 95% confidence intervals, then reports architecture deltas and degradation relative to baseline where baseline data is available.

== Execution and Reproducibility

Each run is executed in isolation with Docker Compose @docker_compose.

1. Start architecture and wait for health checks
2. Execute the JMeter plan
3. Persist raw #raw(".jtl") output and HTML report
4. Tear down containers and volumes
5. Apply cooldown before the next run

Outputs are organized by timestamp and scenario for traceability. Scenario metadata is persisted for every run, and both raw measurements and processed summaries are retained at scenario and experiment-aggregate levels. Reproducibility practices follow the same rationale used in computational research workflows @peng_reproducible_research.

= Experimental Results

This section reports the final experimental campaign. Scenario-level statistics are summarized with
repeated-run aggregates, confidence intervals, and architecture deltas.

Unless noted otherwise, numeric scores in this section come from the generated summary tables @scenario_architecture_stats_table @architecture_delta_by_scenario_table @pool_sweep_summary_table.

Cross-scenario aggregates provide a compact view of architecture-level differences across baseline, failure, latency, and pool-stress conditions, as shown in @fig-scenario-comparison and @fig-scenario-boxplots.

#figure(
  image("figures/scenario_comparison_ci.png", width: 100%),
  caption: [Cross-scenario comparison of throughput, P95 latency, and error rate (mean with 95% confidence intervals).],
) <fig-scenario-comparison>

#figure(
  image("figures/scenario_boxplots.png", width: 100%),
  caption: [Run-level metric distributions by scenario and architecture.],
) <fig-scenario-boxplots>

== Baseline Performance

Under baseline load, the monolith achieved substantially higher throughput and lower tail latency than the microservices deployment.

- Monolith mean throughput: #raw("3558 req/s")
- Microservices mean throughput: #raw("1011 req/s")
- Throughput delta (micro vs mono): #raw("-71.58%")
- Monolith mean P95: #raw("88 ms")
- Microservices mean P95: #raw("199 ms")

These differences are consistent across repeated runs, with narrow confidence intervals for both architectures; baseline endpoint behavior and throughput stability are shown in @fig-baseline-endpoint-comparison and @fig-baseline-throughput-over-time.

#figure(
  image("figures/per_endpoint_comparison.png", width: 100%),
  caption: [Baseline endpoint comparison between architectures (throughput and latency characteristics by API path).],
) <fig-baseline-endpoint-comparison>

#figure(
  image("figures/throughput_over_time.png", width: 100%),
  caption: [Baseline throughput over normalized run time (mean across runs).],
) <fig-baseline-throughput-over-time>

== Deterministic Endpoint Failure

In deterministic fault mode (fixed product ID set), monolith behavior remained close to baseline, while microservices showed measurable downstream error amplification.

- Monolith error rate remained #raw("0.0%")
- Microservices mean error rate increased to #raw("0.0326%")
- Most microservices errors appeared in order creation, not in direct product reads

Endpoint-level error decomposition shows that failures propagated primarily through the order path, as illustrated in @fig-fault-per-endpoint-error-rate.

#figure(
  image("figures/fault_per_endpoint_error_rate.png", width: 85%),
  caption: [Per-endpoint error rates during deterministic endpoint failure runs.],
) <fig-fault-per-endpoint-error-rate>

== Latency Injection

Latency injection produced the strongest degradation in both architectures, with severe tail-latency growth and error-rate increases.

- Monolith: #raw("68.3 req/s"), #raw("P95 2001 ms"), #raw("6.54% errors")
- Microservices: #raw("78.5 req/s"), #raw("P95 3491.9 ms"), #raw("12.94% errors")

Although throughput became similarly low in both systems under this stress, microservices exhibited
substantially worse tail latency and higher end-to-end failure in order processing. Endpoint-level errors are shown in @fig-latency-per-endpoint-error-rate, and temporal endpoint latency behavior is shown in @fig-latency-endpoint-over-time.

#figure(
  image("figures/latency_per_endpoint_error_rate.png", width: 85%),
  caption: [Per-endpoint error rates under latency injection.],
) <fig-latency-per-endpoint-error-rate>

#figure(
  image("figures/endpoint_latency_over_time.png", width: 100%),
  caption: [Latency injection time-series by endpoint and architecture (run-averaged).],
) <fig-latency-endpoint-over-time>

== Pool Exhaustion Sweep

Pool-size sweeps reveal architecture-dependent contention behavior.

- Monolith throughput dropped sharply at pool size #raw("2") compared with #raw("5") and #raw("10")
- The microservices architecture showed its highest throughput at pool size #raw("2") and its highest observed error rate at pool size #raw("10")

Given the fixed #raw("2000 ms") timeout, queueing pressure can convert into timeout-driven failures; however, the observed error response is non-monotonic and architecture-specific rather than a simple inverse function of pool size.

This pattern suggests that connection-pool tuning should be architecture-specific rather than transferred directly between deployment styles, consistent with the sweep trends in @fig-pool-sweep-metrics.

#figure(
  image("figures/pool_sweep_metrics.png", width: 100%),
  caption: [Pool-size sweep: throughput, P95 latency, and error rate versus maximum pool size.],
) <fig-pool-sweep-metrics>

= Discussion

The results support three main observations.

First, under this workload and compute budget, the monolith provides stronger baseline efficiency. The gap appears in both throughput and tail latency, indicating lower orchestration and data-path overhead. This aligns with prior observations that distributed service graphs are sensitive to tail effects and cross-service dependencies @dean_tail_at_scale @deathstarbench.

Second, deterministic endpoint failure does not model process crash-restart recovery; instead, it captures failure-propagation dynamics. In our data, microservices concentrate additional failures in downstream order operations, while the monolith remains comparatively stable in error rate. This behavior is consistent with known cascading-failure patterns in distributed systems @google_sre.

Third, connection-pool stress is not monotonic across architectures. The monolith is more throughput-sensitive to aggressive pool reduction, whereas microservices show a more complex throughput-error trade-off as pool size changes. This reinforces the need for explicit connection-governance policies tied to architecture and database limits @hikaricp @postgres_max_connections.

From an engineering perspective, these findings suggest that microservices require stricter reliability controls (timeouts, retry discipline, backpressure, and pool governance) to prevent localized degradation from becoming user-visible failure in composite paths @resilience_patterns @google_sre.

== Threats to Validity

- External validity: findings reflect one domain model, one workload mix, and one implementation stack.
- Internal validity: deterministic injection improves reproducibility but does not represent random production-failure distributions.
- Construct validity: endpoint-level fault injection evaluates propagation behavior, not orchestrator-driven restart resilience.
- Resource validity: CPU and memory are balanced at the application tier, but architecture-intrinsic topology differences (single database vs service-owned databases) remain part of the treatment.

== Reproducibility Artifact

Source code and experiment automation are available at:

the project repository @repo_artifact.

= Conclusion

This benchmark shows a consistent baseline efficiency advantage for the monolith under the tested workload and resource budget, with higher throughput and lower tail latency. Under injected stress, degradation patterns differ by architecture: microservices preserve partial isolation on unrelated paths, but composite order flows show stronger error amplification and tail inflation.

Pool-stress results further indicate that tuning is architecture-specific. Throughput, latency, and timeout-driven error behavior do not change monotonically with pool size, so connection and timeout settings should be validated empirically for each deployment style rather than copied directly between systems.

These findings do not establish a universal winner. Monoliths remain strong for performance efficiency and lower operational overhead in this setting, while microservices retain organizational and deployment flexibility when supported by mature reliability controls. Architecture selection is therefore best treated as a workload- and operations-driven decision, guided by explicit performance targets, failure budgets, and reproducible benchmarking.

= Appendix

Additional diagnostic visualizations are provided for transparency and replication support; distributional and run-level tail-latency variability views are shown in @fig-appendix-latency-distribution and @fig-appendix-p95-boxplot.

#figure(
  image("figures/latency_distribution.png", width: 100%),
  caption: [Baseline latency distribution by architecture.],
) <fig-appendix-latency-distribution>

#figure(
  image("figures/p95_latency_across_runs_boxplot.png", width: 100%),
  caption: [Baseline run-level P95 latency variability across repeated runs.],
) <fig-appendix-p95-boxplot>

#bibliography("references.bib", title: "References", style: "ieee")
