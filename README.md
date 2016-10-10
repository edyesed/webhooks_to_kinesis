# Webhooks to Kinesis
Perhaps you want to be able to take in arbitrary webhooks, and then do whatever
the hell you want to do with those events afterwards. 

There are tactical, if not strategic, reasons one might not want to handline input and output in something like a lambda ( multiplexing, asynchronous processing ). Or maybe you're willing to drink some [CQRS koolaid](http://www.confluent.io/blog/event-sourcing-cqrs-stream-processing-apache-kafka-whats-connection/).

:farnsworth: Good News Everyone! AWS makes this crazy easy. 

## Setup Stream + API Gateway ( inputs )
The way this system will work is input comes from API gateway to Kinesis Stream.

### Create an IAM user to create the stream and api gateway
0. Create an IAM user ( can delete after making these resources )
1. Copy the credentials
2. Attach this policy to the user
    1.  AdministratorAccess

### Run the script and build the Stream + API gateway ( or read it )
0. `./bin/build_pieces.sh`


### Delete that IAM user
0.  Use Console

### Kinesis
0. Goto [the lambda console](https://us-west-2.console.aws.amazon.com/lambda/home?region=us-west-2#/functions?display=list)
0. Create a lambda function
    1. *runtime*: `python`
    2. *Filter*: `kinesis`
    3. choose `kinesis-process-record-python`
0. Choose *webhooks* as the stream
0. Batch Size ( 1 or 2 )
0. Starting Position *Trim Horizon*
0. Enable Trigger
0. Next
0. Name *whatever*
0. Role *Create role from template*
0. Role *Create role from template*
0. Role Name *Whatever*
0. Policy Templates *Simple Microservice permissions*
0. Next
0. Create function


0. View the function
1. View logs in cloudwatch
2. `./bin/build_pieces.sh`
2. Watch the spice flow
