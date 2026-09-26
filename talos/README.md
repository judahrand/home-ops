# Talos

Declarative [Talos Linux](https://www.talos.dev) machine configuration for the cluster, built from
composable multi-document patches. Nothing in this directory is applied automatically; configs are
rendered on demand and pushed to nodes with `talosctl`.

## Layout

| Path                                          | Purpose                                                                   |
| --------------------------------------------- | ------------------------------------------------------------------------- |
| `cluster.yaml.j2`                             | Documents applied to every node                                           |
| `controlplane.yaml.j2`                        | Control-plane-only documents, including `machine.type`                    |
| `workers.yaml.j2`                             | Worker-only documents (does not exist yet; created with the first worker) |
| `nodes/controlplane/<node>.yaml.j2`           | Per-node documents (hostname, install disk, bond, labels)                 |
| `nodes/controlplane/<node>.schematic.yaml.j2` | Per-node [Image Factory](https://factory.talos.dev) schematic             |
| `mod.just`                                    | Recipes (`just talos ...`)                                                |

There is no shared `schematic.yaml.j2`: the nodes are different shapes, so each one has its own
schematic. `k8s-1` and `k8s-2` are currently byte-identical Intel builds, but they are kept separate
on purpose so either can diverge.

## Rendering

`just talos render-config <node>` builds the final machine config in three layers:

```
talosctl machineconfig patch <(cluster.yaml.j2) \
    -p @<(controlplane.yaml.j2 | workers.yaml.j2) \
    -p @<(nodes/<role>/<node>.yaml.j2)
```

Each layer passes through `minijinja-cli` (strict Jinja templating; the schematic ID arrives as a
`-D` define) and `op inject` (1Password secret resolution) before `talosctl` merges them. Later patches
strategically merge into earlier ones: documents with the same kind/name are deep-merged, new
documents are appended.

Three conventions keep the layers honest:

- **Directory placement is the single source of truth for a node's role.** The role patch is chosen
  by which `nodes/<role>/` directory contains the node file, and `machine.type` is set by the role
  patch, not the node file. A node cannot claim one role by filename and another by content.
- **Secrets never live in this repo.** All sensitive values are `op://kubernetes/talos/...`
  references resolved at render time.
- **Per-node differences live in the node layer.** The install disk differs per node, so
  `UnattendedInstallConfig` lives in `nodes/<role>/<node>.yaml.j2` rather than `cluster.yaml.j2`.

## Schematics

The schematic defines the Image Factory build (system extensions, kernel args). `just talos
gen-schematic-id <node>` POSTs it to the factory and gets back a content-addressed ID, which is
templated into that node's `UnattendedInstallConfig` installer image and used by `upgrade-node`.

## Gotchas

- `machine.ca` and `cluster.ca` merge as a cert+key **unit**: a patch supplying only `key` blanks
  `crt`. This is why `controlplane.yaml.j2` repeats the `crt` references alongside the keys.
- **The apiserver requires two documents that the v1alpha1 config used to default.** Without
  `KubeAuthorizerConfig` (`type: Node` and `type: RBAC`) it exits with _"authorizers: Required
  value: at least one authorization mode must be defined"_; without `KubeAuthenticationConfig` Talos
  writes an empty `authentication-config.yaml` and it exits with _"Object 'Kind' is missing in
  '{}'"_. Either one takes the whole control plane down.
- `cluster.network.cni.name: none` is expressed by **omitting** `KubeFlannelCNIConfig` — Flannel is
  opt-in in the multi-document model, so its absence is what disables it (Cilium is installed by
  Flux).
- `cluster.apiServer.certSANs` became `KubeAPIServerConfig.certExtraSANs`, which _appends_ to the
  default SANs rather than replacing them.
- `machine.kubelet.disableManifestsDirectory` is locked to `true` in the multi-document model and
  cannot be set.
- Rendering a worker before `workers.yaml.j2` and `nodes/workers/` exist fails loudly. Adding the
  first worker means creating `workers.yaml.j2` (with `machine: { type: worker }` and a `ca` block
  carrying `crt` only) plus `nodes/workers/<node>.yaml.j2`.
- `/etc/nfsmount.conf` is currently written by both the old `machine.files` and the new
  `EtcFileConfig` and the file is busy, so `files.EtcFileController` logs a recurring error. It is
  harmless but persistent until the node is rebooted.

## Common tasks

```sh
just talos render-config <node>        # render a node's full machine config to stdout
just talos apply-node <node>           # render and apply (talosctl apply-config)
just talos gen-schematic-id <node>     # print a node's Image Factory schematic ID
just talos upgrade-node <node>         # upgrade Talos using the node's schematic image
just talos upgrade-k8s <version>       # upgrade Kubernetes across the cluster
just talos download-image <version> <schematic-id>   # fetch a metal ISO from the Image Factory
```

## Verifying a change

`apply-config --dry-run` diffs the _submitted documents_, not the normalised configuration, so a
field-form to document-form refactor will always show a diff — it validates the schema but cannot
prove equivalence. To verify a change for real:

1. Apply to **one** node (`just talos apply-node <node>`), then confirm
   `talosctl -n <node> containers --namespace cri` shows `kube-apiserver`,
   `kube-controller-manager` and `kube-scheduler` as `CONTAINER_RUNNING`, and that the node's own
   endpoint (`kubectl --server=https://<node-ip>:6443 get nodes`) serves.
2. Check `talosctl -n <node> read /proc/net/tcp` still has a listener on `:7445` (KubePrism).
3. Only then apply to the remaining nodes, one at a time.

The previous configuration is always recoverable with `git show HEAD:talos/...` and the same
render-and-apply, so keep a rollback terminal open.
