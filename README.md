# zcrun
a simple linux container runtime built with zig


# Features
- namespaces:
  - isolate network, pid, mount, and uts namespace
- cgroups:
  - support cgroups v2
  - limit memory, cpu, or pids (# of procs).
- internet access inside containers using SNAT

# Usage
NOTE: make sure that ip forwarding is enabled to be able to access the internet inside containers.

```sh
$ mkdir rootfs
# export container rootfs dir using docker
$ docker export $(docker create busybox) | tar -C rootfs -xvf -
# run the container using zcrun
# zcrun run <name>  <rootfs> <cmd>
$ zcrun run busybox rootfs   sh
```

# Dependencies:
- The `iptables` command.
- Zig. This branch was tested using version `0.12.0-dev.3191+9cf28d1e9`.
