# A Different Hunting (API)

My pet project designed to mass scan Bug Bounty targets for API vulnerabilities using Cloud/DevOps/SRE best practices.

This repository is public so curious people can understand my hacking methodology and
to showcase my knowledge in Cloud DevOps Engineering for job interviews :stuck_out_tongue_winking_eye:

**It is intended for personal use, so there is no extensive documentation provided.**

> This project is licensed under the MIT license, so feel free to fork and customize it as you wish.

## How to Run

### Development / Testing

1. This will deploy everything locally with [kind](https://kind.sigs.k8s.io). Simply run:
```sh
./ops/apply.sh -e dev
```

2. To destroy the cluster once you're done run:
```sh
./ops/dev/delete_cluster.sh
```
