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
= Conclusion

Both architectures have advantages and disadvantages, all depends on the problem to be solved, with no clear better architecture.