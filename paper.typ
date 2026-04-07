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

= Introduction
While 85% of large organizations have adopted micro-services for their perceived scalability, 
this research aims to uncover the often-ignored trade-offs in database efficiency and fault recovery that these organizations face during peak stress.

= Conclusion

Both architectures have advantages and disadvantages, all depends on the problem to be solved, with no clear better architecture.
