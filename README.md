# zcrun
a simple linux container runtime built with zig


# Features
- namespaces:
  - isolate user, network, pid, mount, ipc, and uts namespace
- cgroups:
  - support cgroups v2
  - limit memory, cpu, or pids (# of procs).
- internet access inside containers using SNAT

# Usage
> [!NOTE]
> make sure that ip forwarding is enabled to be able to access the internet inside containers.
> run `sysctl net.ipv4.ip_forward` to check if it is enabled.
> if not, run `sudo sysctl -w net.ipv4.ip_forward=1` to enable it.

> [!Important]
> zcrun must be run as root

```sh
$ mkdir rootfs
# export container rootfs dir using docker
$ docker export $(docker create busybox) | tar -C rootfs -xvf -
# run the container using zcrun
# zcrun run [-mem] [-cpu] [-pids] <name> <rootfs_path> <cmd>
$ zcrun run busybox rootfs   sh
```

# Dependencies:
- The `iptables` command.
- Zig. This branch was tested using version `0.12.0-dev.3191+9cf28d1e9`.
