# What

Docker image for a "DNS over TLS" server.

This is based on [CoreDNS](https://coredns.io/), and [Let's Encrypt](https://letsencrypt.org/) via [Lego](https://github.com/go-acme/lego)).

This is useful in two scenarios:

 1. you want to encrypt all your laptop DNS traffic (forwarded to Cloudflare, Quad9, Google, or any other DoT public resolver)
 1. you want to run your own DNS/DoT service

## Image features

 * multi-architecture:
    * [✓] linux/amd64
    * [✓] linux/arm64
    * [✓] linux/arm/v7
    * [✓] linux/arm/v6
 * hardened:
    * [✓] image runs read-only
    * [✓] image runs with no capabilities
    * [✓] process runs as a non-root user, disabled login, no shell
 * lightweight
    * [✓] based on `debian:buster-slim`
    * [✓] simple entrypoint script
    * [✓] multi-stage build with no installed dependencies for the runtime image

## Run

```bash
docker run -d \
    --env DOMAIN=something.mydomain.com \
    --env EMAIL=me@mydomain.com \
    --net=bridge \
    --publish 53:1053/udp \
    --publish 443:1443/tcp \
    --publish 853:1853/tcp \
    --cap-drop ALL \
    --read-only \
    dubodubonduponey/coredns:v1
```

You do need to expose port 443 publicly from your docker host so that LetsEncrypt can issue your certificate.

## Notes

### Custom configuration file

If you want to customize your CoreDNS config, mount a volume into `/config` on the container and customize `/config/coredns.conf`
(or `/config/coredns-no-tls.conf` if you do not want a TLS endpoint for your DNS server).

```bash
chown -R 1000:nogroup "[host_path_for_config]"

docker run -d \
    --volume [host_path_for_config]:/config:ro \
    --env DOMAIN=something.mydomain.com \
    --env EMAIL=me@mydomain.com \
    --net=bridge \
    --publish 53:1053/udp \
    --publish 443:1443 \
    --publish 853:1853 \
    --cap-drop ALL \
    --read-only \
    dubodubonduponey/coredns:v1
```

### Networking

If you want to use another networking mode but `bridge` (and run the service on standard ports), you have to run the container as `root`, grant the appropriate `cap` and set the ports:

```
docker run -d \
    --env DOMAIN=something.mydomain.com \
    --env EMAIL=me@mydomain.com \
    --net=host \
    --env DNS_PORT=53 \
    --env TLS_PORT=853 \
    --env HTTPS_PORT=443 \
    --cap-add=CAP_NET_BIND_SERVICE \
    --user=root \
    --cap-drop ALL \
    --read-only \
    dubodubonduponey/coredns:v1
```

### Configuration reference

The default setup uses a CoreDNS config file in `/config/coredns.conf` that sets-up a DNS and DNS-over-TLS server, forwarding to DNS-over-TLS cloudflare-dns.com.

 * the `/certs` folder is used to store letsencrypt certificates (it's a volume by default, which you may want to mount)
 * the `/config` folder holds the configuration

#### Runtime

You may specify the following environment variables at runtime:

 * DOMAIN (eg: `something.mydomain.com`) controls the domain name of your server
 * EMAIL (eg: `me@mydomain.com`) controls the email used to issue your server certificate
 * STAGING (empty by default) controls whether you want to use LetsEncrypt staging environment (useful when debugging so not to burn your quota)
 * UPSTREAM_SERVERS (eg: `tls://1.1.1.1`) controls the upstream forward address
 * UPSTREAM_NAME (eg: `cloudflare-dns.com`) controls the server name of the (TLS) upstream

You can also tweak the following for control over which internal ports are being used (useful if intend to run with host/macvlan, see above)

 * HTTPS_PORT
 * DNS_PORT
 * TLS_PORT

Of course using any privileged port for these requires CAP_NET_BIND_SERVICE and a root user.

Finally, any additional arguments provided when running the image will get fed to the `coredns` binary.

#### Build time

You can rebuild the image using the following build arguments:

 * BUILD_UID
 
So to control which user-id to assign to the in-container user.

## Caveats

 * unbound is currently not supported (PR welcome), meaning you DO have to forward requests to an upstream server
