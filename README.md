# What

Easy to use CoreDNS container with reasonable defaults.

This is based on [CoreDNS](https://coredns.io/), and [Let's Encrypt](https://letsencrypt.org/) (via [Lego](https://github.com/go-acme/lego)).

This is useful in the following scenarios:

1. you want to run a *local* DNS server on your LAN (or your laptop) that will forward requests with encryption to an upstream resolver
    (like Cloudflare, Quad9, Google, or any other DoT public resolver)
1. you want to run your own DNS over TLS (recursive) service
1. other stuff

Before running this publicly on the internet, you should think twice though, and make sure you understand the implications.

## Image features

* multi-architecture (publishing):
  * [x] linux/amd64
  * [x] linux/arm64

* hardened:
  * [x] image runs read-only
  * [x] image runs with no capabilities (you need NET_BIND_SERVICE if you want to use privileged ports obviously)
  * [x] process runs as a non-root user, disabled login, no shell
* lightweight
  * [x] based on our slim [Debian Bookworm](https://github.com/dubo-dubon-duponey/docker-debian)
  * [x] simple entrypoint script
  * [x] multi-stage build with zero packages installed in the runtime image
* observable
  * [x] healthcheck
  * [x] log to stdout
  * [x] prometheus endpoint

## Run

You can run either a forwarding server (that will send requests to an upstream), or a recursive one.

Then you can either expose a traditional DNS server, a TLS server, or both.

Examples:

### Traditional DNS server, forwarding

... to a TLS upstream (encrypted). Cloudflare in this example:

```bash
docker run -d \
    --env "DNS_FORWARD_UPSTREAM_NAME=cloudflare-dns.com" \
    --env "DNS_FORWARD_UPSTREAM_IP_1=tls://1.1.1.1" \
    --env "DNS_FORWARD_UPSTREAM_IP_2=tls://1.0.0.1" \
    --net bridge \
    --publish 53:53/udp \
    --cap-drop ALL \
    --cap-add NET_BIND_SERVICE \
    --read-only \
    docker.io/dubodubonduponey/dns
```

### TLS server, forwarding

... same as above

```bash
docker run -d \
    --env "DNS_FORWARD_UPSTREAM_NAME=cloudflare-dns.com" \
    --env "DNS_FORWARD_UPSTREAM_IP_1=tls://1.1.1.1" \
    --env "DNS_FORWARD_UPSTREAM_IP_2=tls://1.0.0.1" \
    --env "DNS_OVER_TLS_ENABLED=true" \
    --env "DNS_OVER_TLS_DOMAIN=dev-null.farcloser.world" \
    --env "DNS_OVER_TLS_LEGO_EMAIL=dubo-dubon-duponey@farcloser.world" \
    --net bridge \
    --publish 443:443/tcp \
    --publish 853:853/tcp \
    --cap-drop ALL \
    --cap-add NET_BIND_SERVICE \
    --read-only \
    docker.io/dubodubonduponey/dns
```

### Recursive DNS server

```bash
docker run -d \
    --env "DNS_FORWARD_ENABLED=false" \
    --net bridge \
    --publish 53:53/udp \
    --cap-drop ALL \
    --cap-add NET_BIND_SERVICE \
    --read-only \
    docker.io/dubodubonduponey/dns
```

### TLS server, recursive

```bash
docker run -d \
    --env "DNS_FORWARD_ENABLED=false" \
    --env "DNS_OVER_TLS_ENABLED=true" \
    --env "DNS_OVER_TLS_DOMAIN=dev-null.farcloser.world" \
    --env "DNS_OVER_TLS_LEGO_EMAIL=dubo-dubon-duponey@farcloser.world"
    --net bridge \
    --publish 443:443/tcp \
    --publish 853:853/tcp \
    --cap-drop ALL \
    --cap-add NET_BIND_SERVICE \
    --read-only \
    docker.io/dubodubonduponey/dns
```

For TLS, you do need to expose port 443 publicly from your docker host so that LetsEncrypt can issue your certificate,
and of course, you need a DNS record that points to this ip.

## Notes

### Custom configuration file

If you want to customize your CoreDNS config, mount a volume into `/config` on the container
(and customize one of the files to your needs).

```bash
chown -R 2000:nogroup "[host_path_for_config]"

docker run -d \
    --volume [host_path_for_config]:/config:ro \
    ...
```

### Networking

You can control the various ports used by the service if you wish to:

```bash
docker run -d \
    --env DNS_PORT=53 \
    --env DNS_OVER_TLS_PORT=853 \
    --env DNS_OVER_TLS_LEGO_PORT=443 \
    ...
```

### Configuration reference

The default setup use CoreDNS config files in `/config` that sets-up different scenarios based on the value of environment variables.

The `/certs` folder is used to store LetsEncrypt certificates (it's a volume by default, which you may want to mount), in case you configure a DNS-over-TLS server.

#### Runtime

You may specify the following environment variables at runtime:

For DoT:
 * DNS_OVER_TLS_ENABLED: enable the DoT service
 * DNS_OVER_TLS_DOMAIN (eg: `something.mydomain.com`) controls the domain name of your server
 * DNS_OVER_TLS_LEGO_PORT: port that lego will use to listen on for LetsEncrypt response
 * DNS_OVER_TLS_LEGO_EMAIL (eg: `me@mydomain.com`) controls the email used to issue your server certificate
 * DNS_OVER_TLS_LE_USE_STAGING controls whether you want to use LetsEncrypt staging environment (useful when debugging so not to burn your quota)

For forwarding:
 * DNS_FORWARD_ENABLED: enable (default) or disable forwarding mode
 * DNS_FORWARD_UPSTREAM_NAME: if you forward to a DoT server, the domain name of that service
 * DNS_FORWARD_UPSTREAM_IP_1: the ip of the upstream
 * DNS_FORWARD_UPSTREAM_IP_2: the backup ip of the upstream

You can also tweak the following:

 * DNS_PORT (default to 53)
<!--
 * DNS_OVER_GRPC_PORT (default to 553)
-->
 * DNS_STUFF_MDNS: convenient little trick to respond for certain mDNS queries over traditional DNS
 * MOD_METRICS_BIND for Prometheus (default to :4242)

Of course using any privileged port for these requires CAP_NET_BIND_SERVICE.

Finally, any additional arguments provided when running the image will get fed to the `coredns` binary.

### Prometheus

The default configuration files expose a Prometheus metrics endpoint on port 4242.

## Moar?

See [DEVELOP.md](DEVELOP.md)
