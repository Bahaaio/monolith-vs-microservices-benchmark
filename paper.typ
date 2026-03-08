#set page(paper: "a4", margin: 2.5cm)
#set par(justify: true)
#set heading(numbering: "1.")

#let title = "Microservices vs Monolithic architectures: Performance, resilience, and cost analysis"
#let authors = "Ahmed Loay, Bahaa El Deen Mohamed, Youssef Khaled"
#let institution = "SAMS"

#align(center)[
  #text(18pt, weight: "bold")[#title]

  #v(0.5em)
  #authors \
  #institution
]

// #set page(columns: 2)

#v(1em)

= Abstract

This paper compares monolithic and microservices architectures by testing
two applications with the same business logic focusing on performance, resilience, and cost.

= Introduction

With the increase in need for web services, they must be able to serve users simultaneously,
creating demand for architectures that are able to handle heavy workloads.
Historically, developers have always relied on the monolithic architecture,
which combines all software components, and deploys them as a single unit.
On the other hand, the microservices architecture structures and deploys the application
as a collection of small, independent services, has been gaining popularity as a modern solution
to address these growing demands.

= Conclusion

Both architectures have advantages and disadvantages, all depends on the problem to be solved, with no clear better architecture.

