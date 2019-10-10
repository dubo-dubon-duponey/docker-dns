# What

A "DNS over TLS" server docker image (based on [CoreDNS](https://coredns.io/), [Let's Encrypt](https://letsencrypt.org/) via [Lego](https://github.com/go-acme/lego)).

This is particularly useful in two scenarios:

 1. you want to encrypt all your laptop DNS traffic (forwarded to Cloudflare, Quad9, Google, or any other DoT public resolver)
 1. you want to run your own DNS or DoT service

## Image features

 * multi-architecture (linux/amd64, linux/arm64, linux/arm/v7, linux/arm/v6)
 * based on `debian:buster-slim`
 * no `cap` needed
 * running as a non-root user
 * lightweight

## Run

```bash
chown -R 1000:1000 "[host_path_for_config]"
chown -R 1000:1000 "[host_path_for_certificates]"

docker run -d \
    --net=bridge \
    --volume [host_path_for_config]:/config \
    --volume [host_path_for_certificates]:/certs \
    --publish 53:1053/udp \
    --publish 443:1443 \
    --publish 853:1853 \
    --env DOMAIN=dns.mydomain.com \
    --env EMAIL=me@mydomain.com \
    --cap-drop ALL \
    dubodubonduponey/coredns:v1
```

## Notes

### Network

 * if you intend on running on port 53, you should use `bridge` and publish the port (see example)
 * if you need to run with `host` or `macvlan`, you need to `--cap-add CAP_NET_BIND_SERVICE` (and see below for how to specific the ports)

### Configuration

A default CoreDNS config file will be created in `/config/config.conf` if one does not already exist.

This default file sets-up a DNS and DNS-over-TLS server, forwarding to DNS-over-TLS cloudflare-dns.com.

### Advanced configuration

#### Runtime

You may tweak the following environment variables:

 * UPSTREAM_SERVERS (eg: `tls://1.1.1.1 tls://1.0.0.1`)
 * UPSTREAM_NAME (eg: `cloudflare-dns.com`)
 * DOMAIN (eg: `dns.example.com`)
 * EMAIL (eg: `foo@bar.com`)
 * STAGING (empty by default)

Additionally, OVERWRITE_CONFIG controls whether an existing config file would be overwritten or not (default is not).

You can also tweak the following for control over which internal ports are being used (useful if intend to run with host/macvlan)

 * DNS_PORT
 * TLS_PORT
 * HTTPS_PORT

Of course using any privileged port for these requires CAP_NET_BIND_SERVICE.

Finally, any additional arguments when running the image will get fed to the `coredns` binary.

#### Build time

You can also rebuild the image using the following arguments:

 * BUILD_UID
 * BUILD_GID

## Caveats

 * unbound is currently not supported (PR welcome), meaning you have to forward requests to an upstream server
