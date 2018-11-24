---
layout: post
title: "Mutual auth with GRPC & Node: start to finish"
date: 2017-10-27 21:12:00 +0100
categories: grpc node nodejs mutual authentication ssl
---
Setting up mutual authentication can be a little daunting, especially when the
docs for a library you&rsquo;re using don&rsquo;t always have a good example. Top it off
with having to make your own certificates, and the whole process can be a real
PITA! To make it easier, we&rsquo;re going to be using a tool from the great people
at Square, [certstrap](https://github.com/square/certstrap). If you&rsquo;ve ever
used the `easyrsa` utility bundled with OpenVPN, it will feel very familiar as
it makes generating your own [PKI](https://en.wikipedia.org/wiki/Public_key_infrastructure)
much simpler than manually using OpenSSL.

## Generating a root certificate authority

The client and server will both trust the same, private root certificate. We&rsquo;re
generating this manually for this example but you could alternatively use an
existing PKI, for example from a MS Windows Server Domain Controller.

Find a release of certstrap for your operating system from their
[releases page](https://github.com/square/certstrap/releases). Once you&rsquo;ve
downloaded the binary, rename it to something more convenient and make it
executable (if applicable).

```bash
wget https://github.com/square/certstrap/releases/download/v1.1.1/certstrap-v1.1.1-linux-amd64
mv certstrap-v1.1.1-linux-amd64 certstrap
chmod +x certstrap
```

Generate the certificate authority with a name that makes sense for your use
case:

```bash
$ ./certstrap init --organization "Widgets Inc" \
                   --common-name "Snazzy Microservices"

Enter passphrase (empty for no passphrase):

Enter same passphrase again:

Created out/Snazzy_Microservices.key
Created out/Snazzy_Microservices.crt
Created out/Snazzy_Microservices.crl

# Want to set more information, choose an expiration date or key size? See...
./certstrap init -h
```

As you can see above, we&rsquo;ve now generated the main certificate that we&rsquo;ll be
trusting on both the client and the server (`out/Snazzy_Microservices.crt`).

## Generating a server certificate

The hostname of the server&rsquo;s certificate will be validated upon connection so
ensure that the common name and DNS name match the hostname of your service.
Generating a server certificate for your services is as easy as:

```bash
$ ./certstrap request-cert --common-name "login.services.widgets.inc" \
                           --domain "login.services.widgets.inc"

Enter passphrase (empty for no passphrase):

Enter same passphrase again:

Created out/login.services.widgets.inc.key
Created out/login.services.widgets.inc.csr
```

This will create the private key and certificate signing *request*, but not the
certificate itself. We can sign the service&rsquo;s certificate as follows:

```bash
$ ./certstrap sign --CA Snazzy_Microservices "login.services.widgets.inc"

Created out/login.services.widgets.inc.crt from out/login.services.widgets.inc.csr signed by out/Snazzy_Microservices.key
```

## Setting up the GRPC server

In development, you&rsquo;ll likely be using something like this:

```javascript
var server = new grpc.Server();
server.addProtoService(hello_proto.Greeter.service,
                       {sayHello: sayHello, sayHelloAgain: sayHelloAgain});
server.bind('0.0.0.0:50051', grpc.ServerCredentials.createInsecure());
server.start();
```

With SSL, the `server.bind` line becomes:

```javascript
server.bind('0.0.0.0:50051', grpc.ServerCredentials.createSsl({
      rootCerts: fs.readFileSync(path.join(process.cwd, "server-certs", "Snazzy_Microservices.crt")),
      keyCertPairs: {
            privateKey: fs.readFileSync(path.join(process.cwd, "server-certs", "login.services.widgets.inc.key")),
            certChain: fs.readFileSync(path.join(process.cwd, "server-certs", "login.services.widgets.inc.crt"))
      },
      checkClientCertificate: true
}));
```

As you&rsquo;ll probably want to keep the existing setup for testing, we can choose a
setup based on the current `process.env.NODE_ENV`:

```javascript
if (process.env.NODE_ENV === "production") {
      server.bind('0.0.0.0:50051', grpc.ServerCredentials.createSsl({
            // ... as above
      }));
} else {
      server.bind('0.0.0.0:50051', grpc.ServerCredentials.createInsecure());
}
```

Additionally, you may want to name your files differently so that they&rsquo;re
consistent between services, e.g. `ca.crt`, `service.crt` and `service.key`.

## Setting up the GRPC client

Like the server, we also need to generate a certificate for the client. This
time, we don&rsquo;t need a DNS name and can use any common name we like:

```bash
$ ./certstrap request-cert --common-name "client-1010101"

Enter passphrase (empty for no passphrase):

Enter same passphrase again:

Created out/client-1010101.key
Created out/client-1010101.csr

$ ./certstrap sign --CA Snazzy_Microservices "client-1010101"

Created out/client-1010101.crt from out/client-1010101.csr signed by out/Snazzy_Microservices.key
```

As with the server, we must provide the certificate authority, client cert and
private key:

```
if (process.env.NODE_ENV === "production") {
      client = new hello_proto.Greeter('localhost:50051', grpc.credentials.createSsl(
      fs.readFileSync(path.join(process.cwd(), "client-certs", "Snazzy_Microservices.crt")),
      fs.readFileSync(path.join(process.cwd(), "client-certs", "client-1010101.key")),
      fs.readFileSync(path.join(process.cwd(), "client-certs", "client-1010101.crt"))
      ));
} else {
      client = new hello_proto.Greeter('localhost:50051', grpc.credentials.createInsecure());
}
```

## Full example

You can see a full example of the client and server setup [on GitHub](https://github.com/jSherz/node-grpc-mutual-auth-example).

## Troubleshooting

If at any stage the above doesn&rsquo;t work, try turning on verbose logging:

```
export GRPC_TRACE=all
export GRPC_VERBOSITY=DEBUG

node server
```

## Other considerations

To distribute certificates and keys to hosts, you could either bake them into
a virtual machine image, pull them down from a central store (e.g. S3 with
encrypted objects and restrictive permissions) or store the keys in your source
code repository and decrypt them at runtime.

As you may have noticed above, we&rsquo;ve not specified any expiration dates and we
have no method of revoking certificates. If this is a concern for you, you
could set a short expiration date on client / server certificates and frequently
rotate them or load balance your GRPC servers behind another server that
includes revocation checks (e.g. nginx).
