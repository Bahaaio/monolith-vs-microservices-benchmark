#set page(paper: "a4", margin: 2.5cm)
#set par(justify: true)
#set heading(numbering: "1.")

#let title = "A Comparative Analysis of Monolithic and Microservices Architectures: Evaluating Fault Isolation and Database Resource Contention through Experimental Stress Testing"
#let authors = "Ahmad Louay, Bahaa El Deen Mohamed, Youssef Khaled"
#let institution = "Sadat Academy for Management Sciences"

#align(center)[
  #text(18pt, weight: "bold")[#title]

  #v(0.5em)
  #authors \
  #institution
]

// #set page(columns: 2)

#v(1em)

= Abstract

Microservices are widely adopted in large systems for organizational scalability and service-level autonomy. However, this architectural style can introduce data-tier and network-level costs that are not always visible in high-level design discussions. In this work, we compare monolithic and microservices implementations of the same e-commerce workload under controlled, repeatable experiments. Both systems share equivalent business logic, identical datasets, and comparable application-level compute budgets.

We evaluate four scenario families: baseline load, deterministic endpoint failure, fixed latency injection, and database connection pool exhaustion. Measurements are collected using Apache JMeter and analyzed using per-run and cross-scenario statistics, including means, confidence intervals, architecture deltas, and degradation relative to baseline.

Results show that the monolith delivers substantially higher baseline throughput and lower tail latency in our environment, while microservices exhibit greater sensitivity to downstream degradation in order-processing paths. Under latency injection, both architectures degrade sharply, but microservices show stronger tail-latency inflation and higher error rates. Pool-size sweeps reveal non-linear contention behavior and architecture-dependent tuning effects, reinforcing the need for explicit data-tier capacity planning.

= Introduction

The term “monolith” implies something large and glacial, which perfectly implies the truth of a monolith architecture for software design, as it has one codebase which makes it easier to: deployment, tracing, , local testing and it has a better performance than microservices at most cases #link("https://www.atlassian.com/microservices/microservices-architecture/microservices-vs-monolith")[\[1\]].
This advantages makes monolithic architecture a very reasonable choice for basic projects or startups as it also easy to learn , cheap and requires less technical knowledge to use. On the other hand adapting to microservices can be complex and costly and needs deeper domain knowledge, as discussed in Section 5 (p. 772) #link("https://www.sciencedirect.com/science/article/pii/S1877050926006411")[\[2\]].
But every rose has its thorn, monolithic can be a bad choice in the long term as it can be difficult to adapt to new technologies because its tightly coupled and usually the monolithic application must be retooled completely to accept the new addition, in addition to that scalability is a big drawback in Monolithic applications as you may have to rebuild the system to expand its scale#link("https://www.volitioncapital.com/news/microservices-software-architecture/")[\[3\]].

Because of monolithic architecture drawbacks which can significantly affect projects, more and more companies shift to microservices architecture which tends to splits the application into smaller sized independent parts so that each part has its own responsibility, each part is called a service and all services serve the application as a whole#link("https://www.volitioncapital.com/news/microservices-software-architecture/")[\[4\]].

However, the decentralization inherent in microservices does not come without operational costs. While functional logic is easily partitioned, the data tier often remains a point of contention. In a monolithic system, database interactions are managed through a unified connection pool, optimizing resource utilization. Conversely, a microservices deployment requires each independent service to maintain its own connection overhead. As the number of services scales, this leads to 'connection sprawl,' where the aggregate demand for database handles can exhaust system resources even if the underlying hardware is underutilized.

Furthermore, while microservices are designed to prevent cascading failures—ensuring that a bug in one module does not collapse the entire ecosystem—the inter-service communication overhead introduces new latency patterns. Under peak load, the P95 latency (the time within which 95% of requests are completed) can degrade significantly due to network hops and resource competition, a phenomenon that is often less pronounced in the shared-memory environment of a monolith.

While 85% of large organizations have adopted microservices for their perceived scalability, the architectural shift is frequently executed without a full understanding of the underlying resource trade-offs. This research aims to quantify these trade-offs—specifically regarding database efficiency and fault recovery—by subjecting both architectures to rigorous stress testing. By evaluating performance metrics such as connection exhaustion and P95 latency, this study provides a data-driven framework for determining when the 'infrastructure tax' of microservices outweighs their organizational benefits. #link("https://www.volitioncapital.com/news/microservices-software-architecture/")[\[5\]].

= Methodology

== Study Design

This study follows a controlled comparative design. We evaluate a monolithic implementation and a microservices implementation of the same e-commerce workload under identical request patterns and equivalent application-level compute budgets. The goal is to isolate architectural effects on latency, throughput, error behavior, and database contention.

== Systems Under Test

Both systems implement the same domain entities (users, products, and orders) and the same business rules for read and order-creation paths.

- The monolith is a single Spring Boot service backed by one relational database and one application connection pool.
- The microservices system is composed of user, product, and order services behind an API gateway; each service owns its database and connection pool.
- Inter-service communication in the microservices variant is synchronous HTTP.

To preserve fairness, the two deployments use the same dataset and comparable total CPU and memory limits at the application tier.

== Workload Model

Load is generated with Apache JMeter using a read-heavy profile intended to represent typical catalog traffic.

#table(
  columns: (2fr, 1fr),
  align: (left, center),
  table.header([Operation class], [Share]),
  [Product reads], [50%],
  [User reads], [30%],
  [Order creation], [20%],
)

Each run consists of ramp-up, warm-up, and steady-state phases. Warm-up samples are excluded from all reported metrics.

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

Fault and latency injection are implemented at the same logical point in both architectures (product-read path) and controlled by runtime properties: #raw("chaos.enabled"), #raw("chaos.mode"), #raw("chaos.fault-ids"), and #raw("chaos.latency-ms").

For deterministic failure runs, a request fails if and only if its product ID belongs to the configured fixed set. This avoids random sampling noise and guarantees reproducibility across repeated runs and across architectures.

== Connection Pool Exhaustion Protocol

For pool stress tests, the maximum pool size is varied while request concurrency is held constant. This isolates the effect of database-handle scarcity from other factors.

- Pool sizes tested: #raw("2, 5, 10")
- Per-size repeated runs are executed and analyzed independently for both architectures
- Per-run environment is reset to avoid state carry-over

== Metrics and Statistical Treatment

The primary outcome variables are:

- Throughput (requests/second)
- Latency percentiles (P50, P95, P99)
- Error rate and error count
- Time-series behavior for throughput and tail latency

For each scenario, results are reported at run level and as architecture-level aggregates. The analysis pipeline computes means, standard deviations, and 95% confidence intervals, then reports architecture deltas and degradation relative to baseline when baseline data is available.

== Execution and Reproducibility

Each run is executed in isolation using Docker Compose.

1. Start architecture and wait for health checks
2. Execute the JMeter plan
3. Persist raw #raw(".jtl") output and HTML report
4. Tear down containers and volumes
5. Apply cooldown before the next run

Outputs are organized by timestamp and scenario for traceability. Scenario metadata is persisted for every run, and both raw measurements and processed summaries are retained at scenario level and at experiment-aggregate level.

= Experimental Results

This section reports the final experimental campaign. Scenario-level statistics are summarized with repeated-run aggregates, confidence intervals, and architecture deltas.

== Baseline Performance

Under baseline load, the monolith achieved substantially higher throughput and lower tail latency than the microservices deployment.

- Monolith mean throughput: #raw("3558 req/s")
- Microservices mean throughput: #raw("1011 req/s")
- Throughput delta (micro vs mono): #raw("-71.58%")
- Monolith mean P95: #raw("88 ms")
- Microservices mean P95: #raw("199 ms")

These differences are consistent across repeated runs, with narrow confidence intervals for both architectures.

#figure(
  image("figures/scenario_comparison_ci.png", width: 100%),
  caption: [Cross-scenario comparison of throughput, P95 latency, and error rate (mean with 95% confidence intervals).],
)

#figure(
  image("figures/scenario_boxplots.png", width: 100%),
  caption: [Run-level metric distributions by scenario and architecture.],
)

== Deterministic Endpoint Failure

In deterministic fault mode (fixed product ID set), monolith behavior remained close to baseline, while microservices showed measurable downstream error amplification.

- Monolith error rate remained #raw("0.0%")
- Microservices mean error rate increased to #raw("0.0326%")
- Most microservices errors appeared in order creation, not in direct product reads

Endpoint-level error decomposition indicates that failures propagated primarily through the order path.

#figure(
  image("figures/fault_per_endpoint_error_rate.png", width: 85%),
  caption: [Per-endpoint error rates during deterministic endpoint failure runs.],
)

== Latency Injection

Latency injection produced the strongest degradation in both architectures, with severe tail-latency growth and error-rate increases.

- Monolith: #raw("68.3 req/s"), #raw("P95 2001 ms"), #raw("6.54% errors")
- Microservices: #raw("78.5 req/s"), #raw("P95 3491.9 ms"), #raw("12.94% errors")

Although throughput became similarly low in both systems under this stress, microservices exhibited substantially worse tail latency and higher end-to-end failure in order processing.

#figure(
  image("figures/latency_per_endpoint_error_rate.png", width: 85%),
  caption: [Per-endpoint error rates under latency injection.],
)

== Pool Exhaustion Sweep

Pool-size sweeps reveal architecture-dependent contention behavior.

- Monolith throughput dropped sharply at pool size #raw("2") compared with #raw("5") and #raw("10")
- Microservices showed its highest throughput at pool size #raw("2") and highest observed error rate at pool size #raw("10")

This non-linear pattern suggests that connection-pool tuning must be architecture-specific rather than assumed transferable between deployment styles.

#figure(
  image("figures/pool_sweep_metrics.png", width: 100%),
  caption: [Pool-size sweep: throughput, P95 latency, and error rate versus maximum pool size.],
)

= Discussion

The results support three main observations.

First, in this workload and deployment budget, the monolith provides stronger baseline efficiency. The gap is visible in both throughput and tail latency, indicating lower orchestration and data-path overhead.

Second, deterministic endpoint failure does not resemble process crash/restart behavior; instead, it reveals failure propagation dynamics. In our data, microservices concentrate additional failures in downstream order operations, while the monolith remains comparatively stable in error rate. This is an important distinction for architectural claims: the experiment measures degradation coupling, not recovery orchestration.

Third, pool-exhaustion behavior is not monotonic across architectures. The monolith is more throughput-sensitive to aggressive pool reduction, whereas microservices exhibit more complex trade-offs between throughput and error emergence as pool size changes. This reinforces the practical need for scenario-driven tuning and architecture-specific connection budget policies.

From an engineering perspective, the findings suggest that microservices may require stricter SLO-oriented performance controls (timeouts, retries, backpressure, and pool governance) to avoid turning localized degradation into user-visible failure in composite paths.

== Threats to Validity

- External validity: findings reflect one domain model, one workload mix, and one implementation stack.
- Internal validity: deterministic injection improves reproducibility but does not model random production failure distributions.
- Construct validity: endpoint-level failure injection evaluates propagation behavior, not container restart resilience.
- Resource validity: CPU and memory were balanced at the application tier, but architecture-intrinsic topology differences (single DB vs service-owned DBs) remain part of the treatment.

== Reproducibility Artifact

Source code and experiment automation are available at:

#link(
  "https://github.com/Bahaaio/monolith-vs-microservices-benchmark",
)[https://github.com/Bahaaio/monolith-vs-microservices-benchmark]

The full artifact includes raw measurements, per-scenario summaries, and aggregate cross-scenario reports.

= Conclusion

Both architectures have advantages and disadvantages, all depends on the problem to be solved, with no clear better architecture.

= References

#bibliography("references.bib", title: none, full: true)
