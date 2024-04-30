# Local Env Installation
## Prerequisites
### Build `quote-serch`
```shell
git clone --branch VEC-95  https://github.com/aerospike/proximus-examples.git
cd ./proximus-examples/quote-semantic-search
docker build -f "Dockerfile-quote-search" -t "quote-search" .

```
### Create Local Env
```shell
./install-kind.sh
```

### Run `qoute-serch` Example App
```shell
./run-quote-search.sh
```

### Destroy Local Env
```shell
./uninstall-kind.sh
```
