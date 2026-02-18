#!/bin/bash
set -o errexit

reg_name='kind-registry'

kind delete cluster
docker stop $reg_name
docker rm $reg_name
