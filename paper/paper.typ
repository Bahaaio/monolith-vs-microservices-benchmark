#set page(paper: "a4", margin: 2.5cm)
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

Microservices are widely adopted in large systems for organizational scalability and service-level autonomy. However, this architectural style can introduce data-tier and network-level costs that are not
always visible in high-level design discussions. In this work, we compare monolithic and microservices
implementations of the same e-commerce workload under controlled, repeatable experiments. Both
systems share equivalent business logic, identical datasets, and comparable application-level compute
budgets.
We evaluate four scenario families: baseline load, deterministic endpoint failure, fixed latency injection,
and database connection pool exhaustion. Measurements are collected using Apache JMeter and analyzed using per-run and cross-scenario statistics, including means, confidence intervals, architecture
deltas, and degradation relative to baseline.
Results show that the monolith delivers substantially higher baseline throughput and lower tail
latency in our environment, while microservices exhibit greater sensitivity to downstream degradation
in order-processing paths. Under latency injection, both architectures degrade sharply, but microservices show stronger tail-latency inflation and higher error rates. Pool-size sweeps reveal non-linear
contention behavior and architecture-dependent tuning effects, reinforcing the need for explicit data-tier capacity planning.

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

We evaluate four scenario families.

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

For pool stress tests, maximum pool size is varied while request concurrency is held constant. This isolates database-handle scarcity from other factors.

- Pool sizes tested: #raw("2, 5, 10")
- Per-size repeated runs are executed and analyzed independently for both architectures
- Per-run environment is reset to avoid state carry-over
- Pool and connection limits are interpreted with reference to pool configuration behavior and database connection ceilings @hikaricp @postgres_max_connections

== Metrics and Statistical Treatment

We focus on the following outcome variables:

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

This section reports the final campaign at #raw("300") concurrent threads with three repeated runs per scenario. Metrics are presented as architecture-level means with 95% confidence intervals (CI).

== Baseline Performance

Under baseline load, the monolith achieved substantially higher throughput and lower tail latency than the microservices deployment.

- Monolith mean throughput: #raw("3420.1 req/s") (CI #raw("+-18.9"))
- Microservices mean throughput: #raw("1291.1 req/s") (CI #raw("+-33.4"))
- Throughput delta (micro vs mono): #raw("-62.25%")
- Monolith mean P95: #raw("199.0 ms") (CI #raw("+-1.13"))
- Microservices mean P95: #raw("493.7 ms") (CI #raw("+-102.4"))

Baseline error behavior also differs. Monolith remained effectively error-free at aggregate level, while microservices showed non-zero baseline errors concentrated in #raw("POST /orders"), indicating that the composite order path is the dominant fragility point under high concurrency.

#figure(
  image("figures/scenario_comparison_ci.png", width: 100%),
  caption: [Cross-scenario comparison of throughput, P95 latency, and error rate (mean with 95% confidence intervals).],
)

#figure(
  image("figures/scenario_boxplots.png", width: 100%),
  caption: [Run-level metric distributions by scenario and architecture.],
)

== Deterministic Endpoint Failure

Deterministic fault injection used the fixed ID set #raw("3, 7, 11, 12"), which represents #raw("4/30 = 13.33%") of product IDs. Observed product-read error rates match this expected fault share in both architectures.

- #raw("GET /products/{id}") error rate: #raw("13.36%") (microservices) vs #raw("13.33%") (monolith)
- Scenario-level error rate: #raw("10.78%") (microservices) vs #raw("9.33%") (monolith)
- Throughput: #raw("1144.6 req/s") (microservices) vs #raw("3326.4 req/s") (monolith)
- P95 latency: #raw("732.3 ms") (microservices) vs #raw("203.7 ms") (monolith)

Endpoint-level decomposition shows stronger downstream amplification in microservices order creation.

#figure(
  image("figures/fault_per_endpoint_error_rate.png", width: 85%),
  caption: [Per-endpoint error rates during deterministic endpoint failure runs.],
)

== Latency Injection

Latency injection produced the strongest degradation in both architectures, with severe tail-latency growth and error-rate increases.

- Monolith: #raw("107.5 req/s"), #raw("P95 3175.0 ms"), #raw("41.18% errors")
- Microservices: #raw("198.7 req/s"), #raw("P95 2450.9 ms"), #raw("47.44% errors")

Compared with baseline, both architectures show major throughput collapse and tail-latency inflation. Endpoint decomposition also reveals architecture-specific coupling: #raw("GET /users/{id}") in microservices remains near-zero error under product-path latency, while #raw("POST /orders") becomes the dominant failure path in both systems.

#figure(
  image("figures/latency_per_endpoint_error_rate.png", width: 85%),
  caption: [Per-endpoint error rates under latency injection.],
)

== Pool Exhaustion Sweep

Pool-size sweeps reveal architecture-dependent contention behavior.

- Monolith throughput changes strongly with pool size: #raw("2482.6 -> 3514.2 -> 3518.9 req/s") for sizes #raw("2, 5, 10")
- Monolith P95 remains low at #raw("2/5") and increases at #raw("10"): #raw("138.3, 137.7, 197.3 ms")
- Microservices throughput varies within a narrower band: #raw("1382.1, 1243.8, 1289.6 req/s")
- Microservices error remains low at #raw("2/5") but rises at #raw("10"): #raw("0.0035%, 0.0013%, 0.8232%")

This non-linear pattern suggests that connection-pool tuning should be architecture-specific rather than transferred directly between deployment styles.

#figure(
  image("figures/pool_sweep_metrics.png", width: 100%),
  caption: [Pool-size sweep: throughput, P95 latency, and error rate versus maximum pool size.],
)

= Discussion

The final campaign supports four main observations.

First, under this workload and compute budget, monolith retains a clear baseline efficiency advantage in both throughput and tail latency. The magnitude of this gap indicates lower orchestration overhead and lower cross-service tail amplification in the monolithic path @dean_tail_at_scale @deathstarbench.

Second, deterministic fault injection now behaves as intended and is reproducible across architectures. Product-read error rates match the configured fault-ID share, which strengthens internal validity. Both architectures exhibit propagation into composite operations, but microservices show stronger downstream amplification in #raw("POST /orders") @google_sre.

Third, latency injection exposes different coupling characteristics. Microservices preserve near-zero error on unrelated #raw("GET /users/{id}") despite severe product-path degradation, while both architectures experience major failure in order creation. This indicates partial isolation benefits in microservices, but also substantial end-to-end fragility in composition-heavy paths @google_sre.

Fourth, pool-stress behavior is non-monotonic and architecture-specific. Monolith is highly sensitive to aggressive under-provisioning (#raw("pool=2")) and stabilizes at higher pool sizes; microservices show weaker throughput response but can incur higher tail latency and error emergence at larger pools. This confirms that pool policies should be tuned per architecture and endpoint criticality rather than copied across deployment styles @hikaricp @postgres_max_connections.

From an engineering perspective, both architectures require explicit SLO-oriented controls under stress (timeouts, bounded retries, backpressure, and connection governance). For microservices, resilience controls on composite order paths are especially important to prevent localized faults from becoming user-visible failures @resilience_patterns @google_sre.

== Threats to Validity

- External validity: findings reflect one domain model, one workload mix, and one implementation stack.
- Internal validity: deterministic injection improves reproducibility but does not represent random production-failure distributions.
- Construct validity: endpoint-level fault injection evaluates propagation behavior, not orchestrator-driven restart resilience.
- Resource validity: CPU and memory are balanced at the application tier, but architecture-intrinsic topology differences (single database vs service-owned databases) remain part of the treatment.

== Reproducibility Artifact

Source code and experiment automation are available at:

the project repository @repo_artifact.

= Conclusion

In this benchmark, the monolith delivered higher baseline throughput and lower tail latency, and it was less sensitive to injected downstream degradation. The microservices variant exposed stronger propagation and tail effects under stress, alongside architecture-dependent data-tier tuning behavior.

These results do not imply a universal winner. Microservices still offer organizational advantages, but they require stronger operational discipline and explicit resource governance to achieve stable runtime behavior. Architecture decisions should therefore be based on workload profile, team structure, reliability targets, and operational maturity rather than trend adoption.

#bibliography("references.bib", title: "References", style: "ieee")
