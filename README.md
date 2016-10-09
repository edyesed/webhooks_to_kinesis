# Webhooks to Kinesis
Perhaps you want to be able to take in arbitrary webhooks, and then do whatever
the hell you want to do with those events afterwards. ( pair this with [edyesed/kinesis-lambda-notifier](github.com/edyesed/kinesis-lambda-notifier)

There are tactical, if not strategic, reasons one might not want to handline input and output in something like a lambda ( multiplexing, asynchronous processing ). Or maybe you're willing to drink some [CQRS koolaid](http://www.confluent.io/blog/event-sourcing-cqrs-stream-processing-apache-kafka-whats-connection/).

:farnsworth: Good News Everyone! AWS makes this crazy easy. 

## Setup Stream + API Gateway ( inputs )
The way this system will work is input comes from API gateway to Kinesis Stream.

You actually don't have to do much of anything to make this much work.
0. *IAM Policy for creating these things*

0. `
