#set page(paper: "a4", margin: 2.5cm, numbering: "1")
#set par(justify: true)
#set heading(numbering: "1.")

#let title = "Monolith vs. Microservices Under Stress: A Controlled Benchmark of Fault Propagation, Latency, and Database Contention"
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
Latency injection produces the largest degradation in both architectures; aggregate P95 inflation is larger for the monolith, while microservices exhibits higher overall error and stronger order-path failure amplification. Pool-size sweeps reveal non-monotonic, architecture-dependent trade-offs between throughput, tail latency, and timeout-driven errors.
These findings indicate that architecture choice and resilience tuning should be guided by workload characteristics, reliability targets, and empirical performance evidence rather than style preference alone.

= Introduction

The term "monolith" implies something large and tightly integrated, which reflects a key practical advantage of monolithic software design: one codebase usually simplifies deployment, tracing, and local testing, and often delivers strong baseline performance in many environments @atlassian_microservices_vs_monolith @fowler_monolith_first.
These properties make monolithic architecture a practical choice for early-stage products, where development speed, lower operational complexity, and lower platform overhead are important. In contrast, moving to microservices can be complex and costly and usually requires stronger domain boundaries and operational maturity @taibi2017processes @jamshidi2018microservices.
However, monolithic systems can become harder to evolve at large scale. Tight coupling can slow technology adoption and independent scaling, and major changes may require broad system-level modification rather than service-level evolution @newman_microservices @dragoni_microservices.

Because of these long-term limitations, many organizations shift toward microservices, which decompose the system into smaller independently deployable services with clearer responsibility boundaries @newman_microservices @richardson_microservices.

However, the decentralization inherent in microservices does not come without operational costs. While functional logic is easily partitioned, the data tier often remains a point of contention. In a monolithic system, database interactions are managed through a unified connection pool, optimizing resource utilization. Conversely, a microservices deployment requires each independent service to maintain its own connection overhead. As the number of services scales, this leads to 'connection sprawl,' where the aggregate demand for database handles can exhaust system resources even if the underlying hardware is underutilized.

Furthermore, while microservices are designed to prevent cascading failures—ensuring that a bug in one module does not collapse the entire ecosystem—the inter-service communication overhead introduces new latency patterns. Under peak load, the P95 latency (the time within which 95% of requests are completed) can degrade significantly due to network hops and resource competition, a phenomenon that is often less pronounced in the shared-memory environment of a monolith.


This study quantifies these trade-offs using a controlled benchmark campaign across monolithic and microservices implementations of the same domain. This paper focuses on latency, throughput, error behavior, and connection-pool stress to provide evidence-based guidance on when architectural decomposition introduces measurable infrastructure cost. The evaluated deployment topologies are illustrated in @fig-arch-monolith and @fig-arch-microservices.


Despite the volume of existing work on microservices performance, most published benchmarks either target cloud-native multi-node deployments or focus on a single stress dimension in isolation. Studies that examine fault propagation, latency injection, and connection-pool contention together — under a unified workload and on the same dataset — remain scarce. Our experiment is specifically designed to fill that gap. Rather than measuring peak throughput alone, we want to understand how each architecture degrades: whether failures stay contained, how quickly tail latency compounds, and whether connection-pool tuning behaves predictably across deployment styles. These are the questions that actually matter when an engineering team is deciding whether to break apart an existing service.

The rest of this paper is organized as follows. Section 3 describes the methodology, including the systems under test, the four experimental scenarios, and how we controlled for the single-host deployment constraint. Section 4 presents the results across baseline, fault, latency, and pool-exhaustion conditions. Section 5 discusses the three main findings — including the counterintuitive pool-sweep behavior and the failure amplification pattern in microservices order paths. Section 6 concludes with architecture-selection guidance, and Section 7 provides supplementary diagnostic figures. The experiment is fully reproducible from our public repository [26].

= Related Work

Research on microservices performance and architectural trade-offs has grown substantially since the mid-2010s, driven by widespread industry adoption. This section situates our work relative to the most relevant prior studies.

*Benchmarking distributed systeml at scale:* Dean and Barroso @dean_tail_at_scale established the theoretical basis for understanding tail latency in distributed systems, showing that as the number of chained service calls grows, the probability of hitting a slow component — what they call a "straggler" — compounds multiplicatively. Our results in Section 5 directly reflect this: the microservices P95 latency under baseline load (493.7 ms) is more than double the monolith's (199.0 ms), despite identical business logic, and the gap widens further under latency injection. Gan et al. @deathstarbench extended this line of work with DeathStarBench, an open-source benchmark suite for microservices that targets cloud-native, multi-node deployments. Where DeathStarBench focuses on end-to-end cloud infrastructure characterization, our study deliberately targets a constrained single-host environment to isolate architectural overhead from infrastructure scale effects.

*Migration challenges and operational cost:* Taibi et al. @taibi2017processes surveyed practitioners migrating from monolithic to microservices architectures, identifying data-tier coordination and operational complexity as the two most commonly reported challenges. Our pool-exhaustion sweep results (Section 4.4) provide direct empirical evidence for the data-tier concern: connection-pool behavior is non-monotonic and architecture-specific, meaning that tuning strategies cannot be shared between deployment styles. Jamshidi et al. @jamshidi2018microservices examined the broader journey of microservices adoption and identified lack of empirical benchmarking as a recurring gap in the literature — a gap this study directly addresses.

*Fault tolerance and resilience patterns:* Newman @newman_microservices and Richardson @richardson_microservices both argue that microservices should improve fault isolation because service boundaries limit blast radius. Our deterministic fault injection results qualify this claim: while the product-endpoint error rate was nearly identical between architectures (13.33% vs 13.36%), the scenario-level error rate was higher for microservices (10.78% vs 9.33%), driven entirely by amplification in the POST /orders path. This aligns with the cascading-failure patterns documented by Beyer et al. @google_sre in the context of large-scale production systems, and reinforces Nygard's @resilience_patterns argument that circuit breakers and bulkheads are not optional resilience controls for synchronous microservices — they are necessary ones.

*Connection pool management:* Nor Sobri et al. @nor2022database examined database connection pool behaviour specifically in microservice architectures, establishing that per-service pool fragmentation creates aggregate demand that can exhaust database handles even when individual services are lightly loaded. Our pool-sweep results confirm this in a controlled benchmark setting and extend the finding by showing that the response to pool-size changes is non-monotonic: microservices throughput peaked at pool size 2 before degrading — a behaviour that a simple fragmentation model would not predict.

Taken together, prior work establishes the theoretical mechanisms (tail latency compounding, connection sprawl, failure amplification) but typically studies them in isolation or at cloud scale. Our contribution is a controlled, reproducible benchmark that measures all three stress dimensions simultaneously under an identical workload, making the trade-offs directly comparable within a single experimental campaign.

= Methodology

== Study Design

This study follows a controlled comparative design to isolate architectural effects under equivalent workload conditions. Experimental interpretation follows standard performance-analysis practice, emphasizing repeatability, controlled variables, and statistical summaries @jain_performance.

== Systems Under Test

Both systems implement the same domain entities (users, products, and orders) and the same business rules for read and order-creation paths.

- The monolith is a single Spring Boot service @spring_boot backed by one relational database and one application connection pool @hikaricp.
- The microservices system includes user, product, and order services behind an API gateway @nginx_gateway; each service owns its database and connection pool.
- Inter-service communication in the microservices variant uses synchronous HTTP principles aligned with REST architecture @rest_fielding.

The architecture diagrams for both implementations are shown in @fig-arch-monolith and @fig-arch-microservices.

#figure(
  image("figures/arch_monolith.png", width: 100%),
  caption: [Monolithic architecture used in the benchmark setup (adapted from Figure 1 in @nor2022database).],
) <fig-arch-monolith>

#figure(
  image("figures/arch_micro.png", width: 100%),
  caption: [Microservices architecture used in the benchmark setup (adapted from Figure 2 in @nor2022database).],
) <fig-arch-microservices>

To preserve fairness, both deployments use the same dataset and comparable total CPU and memory limits at the application tier.

== Execution Environment

Running both architectures on a single host is an acknowledged constraint of this study, driven by the practical reality that dedicated cloud infrastructure was outside our budget as undergraduate researchers. We want to be upfront about what this means for the results: on a shared machine, both architectures compete for the same CPU cores and memory, which means the throughput gap we observe is not a pure measure of architectural overhead — it also includes whatever resource contention the OS introduces. We partially controlled for this by isolating runs in Docker Compose with per-container resource limits, resetting state between runs, and applying cooldown periods. Still, the absolute throughput figures should be interpreted with this constraint in mind. The relative degradation patterns — how each architecture responds to injected stress compared to its own baseline — are more reliable indicators than cross-architecture throughput comparisons alone, and that relative analysis is where we focus most of our interpretation.

- CPU: 12th Gen Intel Core i5-1235U (10 physical cores, 12 logical threads)
- Memory: 24 GB RAM (approximately 23 GiB visible to the OS)
- Platform: Linux x86_64

== Workload Model
#table(
  columns: (2fr, 1fr),
  align: (left, center),
  table.header([Operation class], [Share]),
  [Product reads], [50%],
  [User reads], [30%],
  [Order creation], [20%],
  stroke: 0.5pt + gray,
)

The table above illustrates the Workload Model used to test the monolithic and microservices architectures.
It shows a read-heavy profile designed to simulate e-commerce catalog traffic, which was generated using the Apache JMeter tool @jmeter.
The workload mix was designed to reflect a read-heavy e-commerce traffic profile, where catalog browsing significantly outnumbers purchases. The 50/30/20 split — product reads, user reads, and order creation respectively — approximates the general shape reported in industry analyses of web retail traffic, where checkout events typically represent 15–25% of session activity while product browsing dominates. We weighted product reads highest because the product service is the shared dependency across all three stress scenarios: it is the target of fault injection, the source of latency injection, and a consumer of the shared connection pool. Concentrating load on this path ensures that injected failures and delays have a clear propagation path to measure, rather than being diluted across endpoints that don't interact.

== Experimental Scenarios
To systematically evaluate the performance and resilience of the monolithic and microservices architectures, this research defines four experimental scenario families,the scenarios range from a Baseline to complex Data-tier contention tests as detailed in the next table.
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

  fill: (x, y) => if y == 0 { gray.lighten(60%) },
  stroke: 0.5pt + gray,
)

Fault and latency injection are implemented with the same logic in both architectures (product-read path) and controlled by runtime properties: #raw("chaos.enabled"), #raw("chaos.mode"), #raw("chaos.fault-ids"), and #raw("chaos.latency-ms") @chaos_engineering_principles.
A request fails only if its product ID belongs to a configured fixed set. This avoids random sampling noise and improves reproducibility across repeated runs and across every architecture.

== Connection Pool Stress Protocol

For pool stress tests, maximum pool size is varied while request concurrency is set constant. This isolates database-handle scarcity from other factors.

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

#table(
  columns: (1.55fr, 1.2fr, 1fr, 1fr, 1fr),
  align: (left, left, right, right, right),
  table.header([Scenario], [Architecture], [Throughput (req/s)], [P95 (ms)], [Error rate (%)]),
  [Baseline], [Monolith], [3420.1], [199.0], [0.00],
  [Baseline], [Microservices], [1291.1], [493.7], [0.77],
  [Deterministic fault], [Monolith], [3326.4], [203.7], [9.33],
  [Deterministic fault], [Microservices], [1144.6], [732.3], [10.78],
  [Latency injection], [Monolith], [107.5], [3175.0], [41.18],
  [Latency injection], [Microservices], [198.7], [2450.9], [47.44],
  [Pool exhaustion (agg)], [Monolith], [3171.9], [157.8], [0.00],
  [Pool exhaustion (agg)], [Microservices], [1305.2], [479.9], [0.28],
  fill: (x, y) => if y == 0 { gray.lighten(60%) },
  stroke: 0.5pt + gray,
)

The table above shows that the two architectures respond to stress very differently. Under baseline and pool conditions, the monolith maintains a throughput advantage of roughly 2.6× and a P95 latency advantage of roughly 2.5×. Under latency injection, that advantage reverses in one dimension: the monolith's throughput collapses more severely (107.5 vs 198.7 req/s) while its tail latency grows larger (3175 vs 2450 ms), even though microservices accumulates a higher overall error rate. Neither architecture dominates across all scenarios — the pattern depends on which stress dimension you measure.

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

- Monolith mean throughput: #raw("3420.1 req/s")
- Microservices mean throughput: #raw("1291.1 req/s")
- Throughput delta (micro vs mono): #raw("-62.25%")
- Monolith mean P95: #raw("199.0 ms")
- Microservices mean P95: #raw("493.7 ms")

These differences are consistent across repeated runs. Throughput confidence intervals are narrow for both architectures, while microservices show wider P95 uncertainty. Baseline endpoint behavior and throughput stability are shown in @fig-baseline-endpoint-comparison and @fig-baseline-throughput-over-time.

#figure(
  image("figures/per_endpoint_comparison.png", width: 100%),
  caption: [Baseline endpoint comparison between architectures (throughput and latency characteristics by API path) confirming that the performance gap is consistent across all three endpoints, not isolated to a single path.],
) <fig-baseline-endpoint-comparison>

#figure(
  image("figures/throughput_over_time.png", width: 100%),
  caption: [Baseline throughput over normalized run time (mean across runs) showing that the performance gap is not a warm-up artefact but a persistent steady-state difference.],
) <fig-baseline-throughput-over-time>

== Deterministic Endpoint Failure

Deterministic fault injection used the fixed ID set #raw("3, 7, 11, 12"), which represents #raw("4/30 = 13.33%") of product IDs.

- #raw("GET /products/{id}") error rate: #raw("13.33%") (monolith) vs #raw("13.36%") (microservices)
- Scenario-level error rate: #raw("9.33%") (monolith) vs #raw("10.78%") (microservices)
- Throughput: #raw("3326.4 req/s") (monolith) vs #raw("1144.6 req/s") (microservices)
- P95 latency: #raw("203.7 ms") (monolith) vs #raw("732.3 ms") (microservices)

Endpoint-level decomposition shows stronger downstream amplification in microservices order creation, as illustrated in @fig-fault-per-endpoint-error-rate.

#figure(
  image("figures/fault_per_endpoint_error_rate.png", width: 85%),
  caption: [While product-endpoint error rates are nearly identical between architectures (≈13.3%), the microservices POST /orders endpoint shows significantly higher failure — evidence that synchronous inter-service dependency amplifies upstream faults into composite operations.],
) <fig-fault-per-endpoint-error-rate>

== Latency Injection

Latency injection produced the strongest degradation in both architectures, with severe tail-latency growth and error-rate increases.

- Monolith: #raw("107.5 req/s"), #raw("P95 3175.0 ms"), #raw("41.18% errors")
- Microservices: #raw("198.7 req/s"), #raw("P95 2450.9 ms"), #raw("47.44% errors")

Although throughput collapsed in both systems under this stress, aggregate P95 latency was higher for the monolith, while microservices showed higher overall error and stronger end-to-end failure in order processing. Endpoint-level errors are shown in @fig-latency-per-endpoint-error-rate, and temporal endpoint latency behavior is shown in @fig-latency-endpoint-over-time.

#figure(
  image("figures/latency_per_endpoint_error_rate.png", width: 85%),
  caption: [Per-endpoint error rates under latency injection showing that injected latency on the product path cascades into total order-creation failure when services are synchronously chained.],
) <fig-latency-per-endpoint-error-rate>

#figure(
  image("figures/endpoint_latency_over_time.png", width: 100%),
  caption: [Latency injection time-series by endpoint and architecture (run-averaged) indicating that tail latency compounds along the service chain rather than recovering over time.],
) <fig-latency-endpoint-over-time>

== Pool Exhaustion Sweep

Pool-size sweeps reveal architecture-dependent contention behavior.

- Monolith throughput dropped sharply at pool size #raw("2") compared with #raw("5") and #raw("10")
- The microservices architecture showed its highest throughput at pool size #raw("2") and its highest observed error rate at pool size #raw("10")

Given the fixed #raw("2000 ms") timeout, queueing pressure can convert into timeout-driven failures; however, the observed error response is non-monotonic and architecture-specific rather than a simple inverse function of pool size.

This pattern suggests that connection-pool tuning should be architecture-specific rather than transferred directly between deployment styles, consistent with the sweep trends in @fig-pool-sweep-metrics.

#figure(
  image("figures/pool_sweep_metrics.png", width: 100%),
  caption: [Pool-size response is non-monotonic and architecture-specific. The monolith loses throughput sharply below pool size 5, while microservices peaks at size 2 and accumulates errors at size 10 — indicating that connection governance strategies cannot be shared between deployment styles.],
) <fig-pool-sweep-metrics>

= Discussion

The results support three main observations.

The baseline throughput gap — 3420 vs 1291 req/s — was larger than we expected going in. We anticipated the monolith would be faster, but not by a factor of 2.6×. Part of that gap is almost certainly amplified by shared-host resource contention, as discussed in Section 4.3. But even accounting for that, the P95 latency difference (199 ms vs 493 ms) is hard to explain by resource competition alone — that's a 2.5× tail latency difference on what should be simple read operations. The most likely explanation is that the API gateway and inter-service HTTP hops introduce serialized wait time that compounds at the tail, which matches what Dean and Barroso describe as the "straggler" problem in distributed service graphs. For a team running on constrained hardware, this gap has real consequences: the microservices deployment is already using roughly half its performance budget before any stress is applied@dean_tail_at_scale @deathstarbench.

The failure injection results reveal something we found genuinely surprising: the product-endpoint error rate was nearly identical between architectures (13.33% vs 13.36%), yet the scenario-level error rate diverged — 9.33% for the monolith vs 10.78% for microservices. That 1.45 percentage point difference might look small, but it represents the amplification cost of synchronous inter-service calls. When a product lookup fails in the monolith, it fails for that request and stops there. In the microservices setup, the same failure propagates into the order service, which depends on a successful product validation before it can complete. We did not implement circuit breakers or retry logic in this experiment — partly because we wanted to measure the raw propagation behavior, and partly because adding those controls would have made the implementations less comparable. The implication is that microservices without explicit resilience patterns are not inherently more fault-tolerant at the request level; they just move where the failure lands@google_sre.

The pool sweep results were the most counterintuitive finding in the whole experiment. We expected a simple pattern: smaller pool = more contention = worse performance. Instead, microservices throughput was actually highest at pool size 2, then degraded as pool size increased. Our best explanation is that at pool size 2, the microservices gateway queues requests aggressively and processes them in tight batches, which may reduce overhead from partial transactions and context switching. As the pool opens up, more concurrent requests hit the database simultaneously, and the overhead of managing those connections outweighs the parallelism benefit — at least within the resource envelope of a single host. This is speculative, and it's exactly the kind of finding that warrants a follow-up experiment on dedicated hardware. What we can say with confidence is that you cannot take a connection-pool configuration from a monolith deployment and apply it to a microservices deployment and expect equivalent behavior@hikaricp @postgres_max_connections.

From an engineering perspective, these findings suggest that microservices require stricter reliability controls (timeouts, retry discipline, backpressure, and pool governance) to prevent localized degradation from becoming user-visible failure in composite paths @resilience_patterns @google_sre.

== Threats to Validity

- External validity: findings reflect one domain model, one workload mix, and one implementation stack.
- Internal validity: deterministic injection improves reproducibility but does not represent random production-failure distributions.
- Construct validity: endpoint-level fault injection evaluates propagation behavior, not orchestrator-driven restart resilience.
- Resource validity is the most significant threat in this study. Both architectures ran on the same physical host, meaning the monolith and microservices deployments share underlying CPU and memory resources. This introduces implicit contention that we cannot fully eliminate. We mitigated this in three ways: applying Docker resource limits to cap each service's CPU and memory allocation, resetting container state between every run to avoid warm-cache advantages, and running each scenario in complete isolation with a cooldown period before the next run. However, we cannot claim these controls fully neutralize OS-level scheduling effects. Readers should treat absolute throughput numbers as indicative rather than definitive, and should weight the degradation-relative-to-baseline analysis more heavily, since relative comparisons within each architecture are not affected by the shared-host issue in the same way cross-architecture comparisons are. A follow-up study on isolated cloud instances (e.g., two separate EC2 t3.medium nodes) would be the natural next step to test whether the baseline gap narrows significantly.

== Reproducibility Artifact

Source code and experiment automation are available at:

the project repository:
Source code and experiment automation are publicly available @repo_artifact at: https://github.com/Bahaaio/monolith-vs-microservices-benchmark


== Results Conclusion
#table(
  columns: (1.8fr, 1.2fr, 1fr, 1fr, 1fr),
  inset: 8pt,
  align: (left, left, right, right, right),
  fill: (x, y) => if y == 0 { gray.lighten(60%) },
  stroke: 0.5pt + gray,

  table.header([*Scenario*], [*Architecture*], [*Throughput* \ (req/s)], [*P95* \ (ms)], [*Error Rate* \ (%)]),

  [Baseline], [Monolith], [3420.1], [199.0], [0.00],
  [], [Microservices], [1291.1], [493.7], [0.77],

  [Deterministic Fault], [Monolith], [3326.4], [203.7], [9.33],
  [], [Microservices], [1144.6], [732.3], [10.78],

  [Latency Injection], [Monolith], [107.5], [3175.0], [41.18],
  [], [Microservices], [198.7], [2450.9], [47.44],

  [Pool Exhaustion], [Monolith], [3171.9], [157.8], [0.00],
  [], [Microservices], [1305.2], [479.9], [0.28],
)
= Conclusion

This benchmark shows a consistent baseline efficiency advantage for the monolith under the tested workload and resource budget, with higher throughput and lower tail latency. Under injected stress, degradation patterns differ by architecture: aggregate tail-latency inflation can be larger in the monolith, while microservices preserves partial isolation on unrelated paths but exhibits stronger error amplification and order-path tail degradation.

Pool-stress results further indicate that tuning is architecture-specific. Throughput, latency, and timeout-driven error behavior do not change monotonically with pool size, so connection and timeout settings should be validated empirically for each deployment style rather than copied directly between systems.

These findings do not establish a universal winner. Monoliths remain strong for performance efficiency and lower operational overhead in this setting, while microservices retain organizational and deployment flexibility when supported by mature reliability controls. Architecture selection is therefore best treated as a workload- and operations-driven decision, guided by explicit performance targets, failure budgets, and reproducible benchmarking.

= Appendix

Additional diagnostic visualizations are provided for transparency and replication support; distributional and run-level tail-latency variability views are shown in @fig-appendix-latency-distribution and @fig-appendix-p95-boxplot.

#figure(
  image("figures/latency_distribution.png", width: 100%),
  caption: [Baseline latency distribution by architecture, the broader distribution means microservices users experience far more variability even under normal load.],
) <fig-appendix-latency-distribution>

#figure(
  image("figures/p95_latency_across_runs_boxplot.png", width: 100%),
  caption: [Baseline run-level P95 latency variability across repeated runs, the wider box confirms that microservices tail latency is not just higher on average but also less predictable run to run.],
) <fig-appendix-p95-boxplot>

#bibliography("references.bib", title: "References", style: "ieee")
