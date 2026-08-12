#!/bin/bash
# Patch arcanist's AWS client so it works with custom S3 endpoints on
# non-standard ports over plain HTTP (e.g. RustFS/MinIO on :9000).
#
#  1. PhutilAWSFuture: allow explicit http:// / https:// schemes in the
#     configured endpoint (upstream hardcodes https://).
#  2. PhutilAWSv4Signature: include the port in the SigV4 "Host" header when
#     the endpoint uses a non-default port, otherwise signature verification
#     fails on servers that strictly validate the Host header.
set -e

cd /var/www/phorge/arcanist/src/future/aws

python3 << 'PYEOF'
path = "/var/www/phorge/arcanist/src/future/aws/PhutilAWSFuture.php"
src = open(path).read()
old = """      $uri = id(new PhutilURI("https://{$host}/", $params))
        ->setPath($path);"""
new = """      if (preg_match('#^https?://#', $host)) {
        $uri = id(new PhutilURI($host.'/', $params))
          ->setPath($path);
      } else {
        $uri = id(new PhutilURI("https://{$host}/", $params))
          ->setPath($path);
      }"""
assert old in src, "PhutilAWSFuture.php: pattern not found"
open(path, "w").write(src.replace(old, new))
print("patched PhutilAWSFuture.php")
PYEOF

python3 << 'PYEOF'
path = "/var/www/phorge/arcanist/src/future/aws/PhutilAWSv4Signature.php"
src = open(path).read()
old = """  private function getHost(HTTPSFuture $future) {
    $uri = new PhutilURI($future->getURI());
    return $uri->getDomain();
  }"""
new = """  private function getHost(HTTPSFuture $future) {
    $uri = new PhutilURI($future->getURI());
    $host = $uri->getDomain();
    $port = $uri->getPort();
    // The Host header must match the authority actually used by the HTTP
    // client (host:port for non-default ports). Without this, custom S3
    // endpoints on non-standard ports (e.g. MinIO/RustFS on :9000) fail
    // SigV4 signature verification.
    if ($port !== null && $port != "80" && $port != "443") {
      $host = $host.":".$port;
    }
    return $host;
  }"""
assert old in src, "PhutilAWSv4Signature.php: pattern not found"
open(path, "w").write(src.replace(old, new))
print("patched PhutilAWSv4Signature.php")
PYEOF

php -l /var/www/phorge/arcanist/src/future/aws/PhutilAWSFuture.php
php -l /var/www/phorge/arcanist/src/future/aws/PhutilAWSv4Signature.php
