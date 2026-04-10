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
As of 2026, microservices have become the architectural standard for large-scale organizations, with adoption rates exceeding 85% among enterprise-level firms.
Despite this prevalence, the transition from monolithic to microservices architectures often introduces hidden complexities regarding infrastructure costs and data-tier bottlenecks. 
This paper presents a comparative analysis of monolithic and microservices architectures by implementing two applications with identical business logic. 
The research focuses on three critical dimensions: performance under peak load, fault isolation (resilience), and the "Database Connection Exhaustion" phenomenon. 
Through rigorous experimental stress testing, this study evaluates system behavior during simulated service failures and quantifies database resource contention. 
Preliminary findings suggest that while microservices offer superior fault isolation, they impose a significant "infrastructure tax" through connection sprawl, requiring higher-tier database resources compared to the monolithic model.

= Introduction <intro>
The term “monolith” implies something large and glacial, which perfectly implies the truth of a monolith architecture for software design, as it has one codebase which makes it easier to: deployment, tracing, , local testing and it has a better performance than microservices at most cases #link("https://www.atlassian.com/microservices/microservices-architecture/microservices-vs-monolith")[\[1\]].
This advantages makes monolithic architecture a very reasonable choice for basic projects or startups as it also easy to learn , cheap and requires less technical knowledge to use. On the other hand adapting to microservices can be complex and costly and needs deeper domain knowledge, as discussed in Section 5 (p. 772) #link("https://www.sciencedirect.com/science/article/pii/S1877050926006411")[\[2\]].
But every rose has its thorn, monolithic can be a bad choice in the long term as it can be difficult to adapt to new technologies because its tightly coupled and usually the monolithic application must be retooled completely to accept the new addition, in addition to that scalability is a big drawback in Monolithic applications as you may have to rebuild the system to expand its scale#link("https://www.volitioncapital.com/news/microservices-software-architecture/")[\[3\]].

Because of monolithic architecture drawbacks which can significantly affect projects, more and more companies shift to microservices architecture which tends to splits the application into smaller sized independent parts so that each part has its own responsibility, each part is called a service and all services serve the application as a whole#link("https://www.volitioncapital.com/news/microservices-software-architecture/")[\[4\]].

However, the decentralization inherent in microservices does not come without operational costs. While functional logic is easily partitioned, the data tier often remains a point of contention. In a monolithic system, database interactions are managed through a unified connection pool, optimizing resource utilization. Conversely, a microservices deployment requires each independent service to maintain its own connection overhead. As the number of services scales, this leads to 'connection sprawl,' where the aggregate demand for database handles can exhaust system resources even if the underlying hardware is underutilized.

Furthermore, while microservices are designed to prevent cascading failures—ensuring that a bug in one module does not collapse the entire ecosystem—the inter-service communication overhead introduces new latency patterns. Under peak load, the P95 latency (the time within which 95% of requests are completed) can degrade significantly due to network hops and resource competition, a phenomenon that is often less pronounced in the shared-memory environment of a monolith.

While 85% of large organizations have adopted microservices for their perceived scalability, the architectural shift is frequently executed without a full understanding of the underlying resource trade-offs. This research aims to quantify these trade-offs—specifically regarding database efficiency and fault recovery—by subjecting both architectures to rigorous stress testing. By evaluating performance metrics such as connection exhaustion and P95 latency, this study provides a data-driven framework for determining when the 'infrastructure tax' of microservices outweighs their organizational benefits. #link("https://www.volitioncapital.com/news/microservices-software-architecture/")[\[5\]].

= Methodology

System Architecture

To ensure a fair comparison, two functionally equivalent systems were implemented: a monolithic architecture and a microservices architecture. Both systems implement the same e-commerce domain consisting of three core entities: Users, Products, and Orders. Each system exposes identical REST APIs for retrieving users and products, and for creating orders.

The monolithic system is deployed as a single Spring Boot application with a shared database and a single database connection pool. In contrast, the microservices system is composed of three independent services (User Service, Product Service, and Order Service) behind an API Gateway. Each service maintains its own database and connection pool, and inter-service communication is performed synchronously via HTTP.

To ensure fairness, both architectures were allocated equivalent total system resources (CPU and memory), and identical datasets were used in all experiments.

Load Testing Setup

Performance evaluation was conducted using Apache JMeter. The workload simulates a typical read-heavy e-commerce scenario with the following distribution:

50% GET /products/{id}
30% GET /users/{id}
20% POST /orders

Each test run consists of:

a ramp-up period to gradually introduce load
a warm-up phase (excluded from analysis)
a steady-state execution phase where metrics are collected

The number of concurrent users (threads) is varied across experiments to evaluate system behavior under increasing load.

Fault Injection Design

To evaluate system resilience beyond steady-state performance, we introduce controlled fault injection scenarios. These faults are deterministic and reproducible, allowing systematic comparison between architectures.

1. Connection Pool Exhaustion

Connection pool exhaustion is simulated by increasing the number of concurrent requests while keeping the database connection pool size fixed. This creates contention for database connections, leading to queueing delays and potential request failures.

The objective of this experiment is to identify:

the load threshold at which performance degradation occurs
the impact on latency distribution (particularly tail latency)
differences in how resource contention manifests in monolithic vs microservice systems

In the monolith, all requests compete for a single connection pool. In the microservices architecture, each service maintains its own pool, potentially isolating or redistributing contention.

2. Partial Service Failure

To simulate runtime failures, controlled exceptions are injected into specific components of the system. In the microservices architecture, failures are introduced in a single service (e.g., Product Service), while in the monolith the same failure logic is applied within the corresponding module.

Failures are injected probabilistically (e.g., a fixed percentage of requests), ensuring consistent behavior across runs.

This experiment evaluates:

how failures propagate across system components
the impact on overall system availability and error rate
differences in fault isolation between architectures

In microservices, failures may remain localized or propagate through inter-service calls. In contrast, in a monolith, failures occur within a shared process and may affect all requests uniformly.

3. Artificial Latency Injection

In addition to hard failures, we simulate performance degradation by introducing artificial delays (e.g., thread sleep) in selected components. This models real-world scenarios such as slow database queries or network latency.

This experiment focuses on:

cascading latency effects across dependent components
queue buildup and thread contention
system behavior under degraded but non-failing conditions

This scenario is particularly relevant for microservices, where inter-service communication amplifies latency due to network overhead.

Metrics Collected

For each experiment, the following metrics are collected:

Throughput (requests per second)
Latency percentiles (P50, P95, P99)
Error rate (percentage of failed requests)
Latency over time (to observe degradation patterns)

Warm-up periods are excluded from analysis to ensure measurements reflect steady-state behavior.

Experimental Procedure

Each experiment is conducted in isolation for both architectures using identical configurations. The procedure is as follows:

Deploy the system using Docker Compose
Wait for all services to become healthy
Execute the JMeter test plan
Collect raw performance data
Tear down the environment
Repeat for the alternate architecture

A cooldown period is introduced between runs to avoid interference from residual system state.

= Conclusion

Both architectures have advantages and disadvantages, all depends on the problem to be solved, with no clear better architecture.