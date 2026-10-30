version=v20261029

docker build --network host \
  --build-arg PHORGE_CACHEBUST="$(date +%s)" \
  -t harbor.michaelapp.com/library/phorge-zh:$version .

docker push harbor.michaelapp.com/library/phorge-zh:$version

