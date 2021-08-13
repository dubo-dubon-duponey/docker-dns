# What

Docker image for CoreDNS, with sample configuration for various "DNS over TLS" scenarios.

This is based on [CoreDNS](https://coredns.io/), and [Let's Encrypt](https://letsencrypt.org/) (via [Lego](https://github.com/go-acme/lego)).

This is useful in the following scenarios:

 1. you want to encrypt all your laptop DNS traffic (forwarded to Cloudflare, Quad9, Google, or any other DoT public resolver)
 1. you want to run your own DNS/DoT recursive service
 1. anything else you can do with CoreDNS

## Image features

* multi-architecture:
  * [x] linux/amd64
  * [x] linux/386
  * [x] linux/arm64
  * [x] linux/arm/v7
  * [x] linux/arm/v6
  * [x] linux/ppc64le
  * [x] linux/s390x
* hardened:
  * [x] image runs read-only
  * [x] image runs with no capabilities (unless you want it on a privileged port)
  * [x] process runs as a non-root user, disabled login, no shell
* lightweight
  * [x] based on our slim [Debian Bullseye](https://github.com/dubo-dubon-duponey/docker-debian)
  * [x] simple entrypoint script
  * [x] multi-stage build with no installed dependencies for the runtime image
* observable
  * [x] healthcheck
  * [x] log to stdout
  * [x] prometheus endpoint

## Run

You can run either a forwarding server (that will send requests to an upstream), or a recursive one 
(only available on AMD64 in the provided image - or ARM64 if you rebuild the image on an ARM64 node).

Then you can either expose a traditional DNS server, a TLS server, or both.

Examples:

### Traditional DNS server, forwarding

... to a TLS upstream (encrypted). Cloudflare in this example:

```bash
docker run -d \
    --env "UPSTREAM_NAME=cloudflare-dns.com"
    --env "UPSTREAM_SERVER_1=tls://1.1.1.1"
    --env "UPSTREAM_SERVER_2=tls://1.0.0.1"
    --net bridge \
    --publish 53:1053/udp \
    --cap-drop ALL \
    --read-only \
    dubodubonduponey/coredns
```

### TLS server, forwarding

... same as above

```bash
docker run -d \
    --env "DOMAIN=dev-null.farcloser.world"
    --env "EMAIL=dubo-dubon-duponey@farcloser.world"
    --env "UPSTREAM_NAME=cloudflare-dns.com"
    --env "UPSTREAM_SERVER_1=tls://1.1.1.1"
    --env "UPSTREAM_SERVER_2=tls://1.0.0.1"
    --net bridge \
    --publish 443:1443/tcp \
    --publish 853:1853/tcp \
    --cap-drop ALL \
    --read-only \
    dubodubonduponey/coredns
```

### Traditional DNS server, recursive

```bash
docker run -d \
    --net bridge \
    --publish 53:1053/udp \
    --cap-drop ALL \
    --read-only \
    dubodubonduponey/coredns
```

### TLS server, recursive

```bash
docker run -d \
    --env "DOMAIN=dev-null.farcloser.world"
    --env "EMAIL=dubo-dubon-duponey@farcloser.world"
    --net bridge \
    --publish 443:1443/tcp \
    --publish 853:1853/tcp \
    --cap-drop ALL \
    --read-only \
    dubodubonduponey/coredns
```

For TLS, you do need to expose port 443 publicly from your docker host so that LetsEncrypt can issue your certificate,
and of course, you need a DNS record that points to this ip.

## Notes

### Custom configuration file

If you want to customize your CoreDNS config, mount a volume into `/config` on the container
(and customize one of the files to your needs).

```bash
chown -R 1000:nogroup "[host_path_for_config]"

docker run -d \
    --volume [host_path_for_config]:/config:ro \
    --net bridge \
    --publish 53:1053/udp \
    --publish 443:1443/tcp \
    --publish 853:1853/tcp \
    --cap-drop ALL \
    --read-only \
    dubodubonduponey/coredns
```

### Networking

If you want to use another networking mode but `bridge` (and run the service on privileged ports), you have to run the container as `root`, grant the appropriate `cap` and set the ports:

```bash
docker run -d \
    --env DOMAIN=something.mydomain.com \
    --env EMAIL=me@mydomain.com \
    --net host \
    --env DNS_PORT=53 \
    --env TLS_PORT=853 \
    --env HTTPS_PORT=443 \
    --cap-add CAP_NET_BIND_SERVICE \
    --user root \
    --cap-drop ALL \
    --read-only \
    dubodubonduponey/coredns
```

### Configuration reference

The default setup use CoreDNS config files in `/config` that sets-up different scenarios based on the value of environment variables.

The `/certs` folder is used to store LetsEncrypt certificates (it's a volume by default, which you may want to mount), in case you configure a TLS server (through using the DOMAIN variable).

#### Runtime

You may specify the following environment variables at runtime:

 * DOMAIN (eg: `something.mydomain.com`) controls the domain name of your server if you want a TLS server
 * EMAIL (eg: `me@mydomain.com`) controls the email used to issue your server certificate
 * STAGING controls whether you want to use LetsEncrypt staging environment (useful when debugging so not to burn your quota)
 * UPSTREAM_NAME (eg: `cloudflare-dns.com`) controls the server name of the (TLS) upstream if you want a forwarding server
 * UPSTREAM_SERVER_1 and UPSTREAM_SERVER_2 (eg: `tls://1.1.1.1`) controls the upstream forward addresses

You can also tweak the following for control over which internal ports are being used (useful if intend to run with host/macvlan, see above)

 * DNS_PORT (default to 1053)
 * HTTPS_PORT (default to 1443)
 * TLS_PORT (default to 1853)
 * GRPC_PORT (default to 5553)
 * METRICS_PORT (default to 9253)

Of course using any privileged port for these requires CAP_NET_BIND_SERVICE and a root user.

Note that these environment variables are used solely in the default configuration files.
If you are rolling your own, it's up to you to use them or not.

Finally, any additional arguments provided when running the image will get fed to the `coredns` binary.

### Unbound and recursive server

Unbound support requires CGO, which requires the target platform to be the same as the build platform. 

Our images are built on linux/amd64.

If you want to run on arm64, you have to rebuild it yourself on an arm64 node.

### Prometheus

The default configuration files expose a Prometheus metrics endpoint on port 9253.

## Moar?

See [DEVELOP.md](DEVELOP.md)
