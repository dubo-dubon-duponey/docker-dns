# What

A "DNS over TLS" server docker image (based on [CoreDNS](https://coredns.io/), [Let's Encrypt](https://letsencrypt.org/) via [Lego](https://github.com/go-acme/lego)).

This is particularly useful in two scenarios:

 1. you want to encrypt all your laptop DNS traffic (forwarded to Cloudflare, Quad9, Google, or any other DoT public resolver)
 1. you want to run your own DoT service

## Image features

 * multi-architecture (linux/amd64, linux/arm64, linux/arm/v7, linux/arm/v6)
 * based on `debian:buster-slim`
 * no `cap` needed
 * running as a non-root user
 * lightweight (~40MB)

## Run

```bash
chown -R 1000:1000 "[host_path_for_config]"
chown -R 1000:1000 "[host_path_for_certificates]"

docker run -d \
    --net=bridge \
    --volume [host_path_for_config]:/config \
    --volume [host_path_for_certificates]:/data \
    --publish 53:1053/udp \
    --publish 853:1853 \
    --cap-drop ALL \
    dubodubonduponey/quark-dns:v1
```

```
docker run -d \
    --net=bridge \
    --volume [host_path_for_config]:/config \
    --volume [host_path_for_certificates]:/data \
    --publish 53:1053/udp \
    --publish 853:1853 \
    --cap-drop ALL \
    dubodubonduponey/quark-dns:v1
```


## Notes

### Network

 * if you intend on running on port 53, you must use `bridge` and publish the port
 * if using `host` or `macvlan`, you will not be able to use a privileged port (but see below)

### Configuration

A default CoreDNS config file will be created in `/config/config.conf` if one does not already exist.

This default file sets-up a forwarder to DNS-over-TLS cloudflare-dns.com.

### Advanced configuration

At runtime, you may tweak the following environment variables:

 * UPSTREAM_SERVERS (eg: `tls://1.1.1.1 tls://1.0.0.1`)
 * UPSTREAM_NAME
 * DOMAIN
 * EMAIL

ENV         DNS_PORT=1053
ENV         TLS_PORT=1853
ENV         HTTPS_PORT=1443
ENV         UPSTREAM_SERVERS="tls://1.1.1.1 tls://1.0.0.1"
ENV         UPSTREAM_NAME="cloudflare-dns.com"
ENV         OVERWRITE_CONFIG=""

ENV         DOMAIN="mydns.example.com"
ENV         EMAIL="foo@bar.com"
ENV         STAGING=""


You can rebuild the image using the following arguments:

 * BUILD_UID
 * BUILD_GID

To modify the upstream DNS servers that the resolver is using.

Additionally, OVERWRITE_CONFIG controls whether an existing config file would be overwritten or not (default is not).

Or even tweak the following for control over which internal ports are being used

 * DNS_PORT
 * TLS_PORT

Also, any additional arguments when running the image will get fed to the `coredns` binary.

## Caveats

* unbound is currently not supported (PR welcome), meaning you have to forward requests to an upstream server
