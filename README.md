# What

A docker image for [CoreDNS](https://coredns.io/).

 * multi-architecture (linux/amd64, linux/arm64, linux/arm/v7, linux/arm/v6)
 * based on debian:buster-slim
 * no cap needed
 * running as a non-root user
 * lightweight (~40MB)

## Run

```bash
chown -R 1000:1000 "[host_path]"

docker run -d \
    --net=bridge \
    --volume [host_path]:/config \
    --publish 53:1053/udp \
    --publish 853:1853 \
    --cap-drop ALL \
    dubodubonduponey/coredns:v1
```

## Notes

### Network

 * if you intend on running on port 53, you must use `bridge` and publish the port
 * if using `host` or `macvlan`, you will not be able to use a privileged port

### Configuration

A default CoreDNS config file will be created in `/config/config.conf` if one does not already exist.

This default file sets-up a forwarder to DNS-over-TLS cloudflare-dns.com.

### Advanced configuration

You can rebuild the image using the following arguments:

 * BUILD_UID
 * BUILD_GID

At runtime, you may tweak the following environment variables:

 * UPSTREAM_NAME
 * UPSTREAM_SERVERS
 
To modify the upstream DNS servers that the resolver is using.

Additionally, OVERWRITE_CONFIG controls whether an existing config file would be overwritten or not (default is not).

Or even tweak the following for control over which internal ports are being used

 * DNS_PORT
 * TLS_PORT

Also, any additional arguments when running the image will get fed to the `coredns` binary.
