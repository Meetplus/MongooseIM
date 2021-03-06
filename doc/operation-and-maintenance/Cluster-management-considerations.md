These apply to bare metal, virtualization, hypervisor, containers and other technologies.

## Single-node MongooseIM

With a single-node MongooseIM, one can set up a vertically scalable system, that is a function of the server resources. MongooseIM can scale from hundreds to tens of thousands of concurrent users.

Note that in a single-node MongooseIM, there is no load distribution, and no fallback or failover in case of a failure.

This architecture is suitable for low-scale deployments, such as testing and development environments on embedded devices, personal computers, or servers.

## Dual-node MongooseIM

With a dual-node MongooseIM, one can set up a vertically scalable system, that is a function of the servers' resources. We recommend that servers with the same power are used. Both nodes can handle different sets of services, given that these non-MongooseIM services consume roughly the same resources on both servers. In this setup, MongooseIM can scale up to hundred of thousands of concurrent users.

In a dual-node MongooseIM, there is a 50-50 load distribution - there is a possible fallback or failover in case of a node failure. Please keep in mind that to avoid degrading the service the remaining node should be able to handle the full load when necessary.

This setup is applicable to low to mid-scale deployments used f.e. for functional and load testing.
We recommend using real dedicated servers, although MongooseIM could run in a cluster mode with low-power machines, such as embedded devices.

This setup provides better fault tolerance and robustness than the single-node but it's not recommended for production environments.
The minimum recommended production setup is 3 nodes.

## Multi-node MongooseIM

With a multi-node MongooseIM, one can set up a system that is highly scalable both vertically and horizontally and that is still a function of the servers' resources.
We recommend that servers with the same power are used.
We also recommend that all the nodes handle the same set of services.
In this setup, MongooseIM can scale up to tens of millions of concurrent users.

In a multi-node MongooseIM, with `n` nodes, there is a `1/n` load distribution - there is a possible fallback or failover in case of a node failure.
To avoid degrading the service the remaining nodes should be able to handle  `1/(n-1)` load when necessary.

This setup fits mid and large-scale deployments, such as production environments. We recommend using real dedicated, powerful servers.

## Multi-datacenter MongooseIM

With a multi-datacenter MongooseIM, one can set up a system that is highly scalable both vertically and horizontally. The MongooseIM clusters are simply distributed across continents for local, low-lag client connections, and the clusters are interconnected via high-speed links. In this setup, MongooseIM can scale up to hundreds of millions of concurrent users.

This applies to large and very large-scale deployments.

We advise [contacting us](https://www.erlang-solutions.com/contact.html) in case of such a big deployment.

## Summary table

**Setup**: reflects the number of nodes in your cluster. <br/>
**Purpose**: is the goal and use of this cluster. <br/>
**Low-end**: number of concurrent users on low-power machines, such as laptops, embedded devices, entry-level cloud or bare metal.<br/>
**High-end**: number of concurrent users on powerful machines, with lots of memory, multi-core CPU, whether in cloud or bare metal.

Setup | Purpose | Low-end  | High-end
------|---------|---------:|---------:
Single-node | Functional testing, development       | 100  to  10k   | 100k to 500k
Dual-node | Low-end system, load testing            |   1k to 100k   |   1M to   3M
Multi-node | High-end production system             |  10k to   1M   |   2M to  10M
Multi-datacenter | Very large scale production system  | 100k to  10M   |  10M to 100M

### Important notes

Scalability highly depends on variables such as:

* machine's power, such as memory, CPU, I/O
* the type of concurrent users:
    * most iOS apps are not connected in the background, they use APNS to push info to the device
    * web clients use websockets, with fallback on BOSH (HTTP long-polling)
    * client-side and backend-side REST API
* how much archiving is needed and the latency for storage and querying, which depends a lot on storage backend architecture
* message throughput:
    * one-to-one
    * MUC
    * MUC light
    * PubSub
    * Presences
    * HTTP notifications (may include queuing systems such as RabbitMQ or Kafka)
* latency of messaging, both real-time and archived messages

### OS configuration

To achieve high scalability you have to adjust the configuration of your operating system.

First, set some network related parameters - this is what we use for load testing:

Parameter                    | Value
-----------------------------|----
net.ipv4.ip_local_port_range | 1024 65535
net.ipv4.tcp_mem             | 16777216 16777216 16777216
net.ipv4.tcp_wmem            | 4096 87380 16777216
net.ipv4.tcp_rmem            | 4096 87380 16777216

Then, you have to increase the number of file descriptors allowed for the user running your MongooseIM server process.
In Linux, this is most commonly done in `/etc/security/limits.conf`.
You should remember, though, that there is a limit to it ??? you can't increase it above an upper bound which is set by the `fs.file-max` kernel parameter.
And there is a limit to a possible increase in `fs.file-max` as well ??? you can't increase it beyond 1048576, which is 2^20 and is set by another kernel parameter, `fs.nr_open`.
Once you increase that one, you are good to go. 
