Configure DGRAPH environment variables
```sh
export DGRAPH_ALPHA_HOST="$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' | head -n1)"
export DGRAPH_ALPHA_HTTP_PORT="$(kubectl get svc dgraph-alpha -n adh-api -o jsonpath='{.spec.ports[0].nodePort}')"
```

Count URLs
```sh
./database_query.sh -o /dev/stdout -t dql -q '{
    result(func: has(Url.value)) {
        count(uid)
    }
}'
```

Delete all HttpResponses
```sh
./database_query.sh -o /dev/stdout -t dql -q '
    upsert {
      query {
        q(func: type(HttpResponse)) {
          v as uid
        }
      }

      mutation {
        delete {
          uid(v) * * .
        }
      }
    }
'
```
