#set page(paper: "a4", margin: 1in)
#set par(justify: true, leading: 0.65em)
#set heading(numbering: "1.")

#align(center)[
  #text(17pt, weight: "bold")[
    Performance Comparison of Monolith and Microservices Applications: A Summary
  ]
]

= Overview:

== Setup:

The paper compares the performance of monolithic and microservices applications
based on RAM memory availability, CPU usage, and response time.

To evaluate the architectures, authors analyzed two similar online-shop web applications,
and five microservices, both applications were built using ASP .NET Core 3.1 and hosted on Microsoft Azure as web apps.

The monolithic app was a standard .NET Core MVC application, while the microservices-based app
acted as a client consuming the microservices.
Each microservice had its own Microsoft SQL database hosted on Azure,
and communicated with other microservices through REST API calls.

== Testing:

Automatic load tests were made using the JMeter tool,
which simulated both simple and more complicated requests for 2 to 3 minutes.

= Findings:

== Response time:

- The monolith application always performed better.
- In simpler test scenarios, the microservices' application's
  response time was 2 to 3 times higher than of the monolith app,
  it was caused by the number of network calls that was needed to be sent from the client application to the microservices.

- However, during a complex test scenarios, the results weren't so obvious and the gap was less significant.

== Resource consumption:

- The cumulative RAM and CPU usage of the microservices application was much higher
that the resources need for the monolith application.
- Although the microservices application had a larger footprint, authors noted that this
  should not be a problem, due to the relatively low overall usage, and resources available on modern servers.
- However, this larger microservices resource usage will lead to microservice applications being
  more expensive to host that the monolithic ones.
