set default-script
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

talos_dir := justfile_dir() + '/talos'
controller := `talosctl config info -o yaml | yq -e '.endpoints[0]'`

[private]
default:
    just -l talos

# TALOS_APPLY_ADDR overrides the address talosctl dials (useful when a reset node
# is not reachable at its DNS-resolved address), while the config is still
# rendered for the named node.
[confirm('Apply Talos config to ' + node + ' [y|N] ?')]
[doc('Apply Talos config to a node')]
apply-node node *args:
    just talos render-config "{{ node }}" | talosctl -n "${TALOS_APPLY_ADDR:-{{ node }}}" apply-config -f /dev/stdin {{ args }}

[doc('Download Talos machine image')]
download-image version schematic:
    gum spin --title "Downloading Talos {{ version }} ..." -- \
        curl -sfL --remove-on-error --retry 5 --retry-delay 5 --retry-all-errors \
        -o "{{ talos_dir }}/talos-{{ version }}-{{ replace_regex(schematic, '^(.{8}).*', '$1') }}.iso" \
        "https://factory.talos.dev/image/{{ schematic }}/{{ version }}/metal-amd64.iso"
    just log info "Downloaded Talos" version "{{ version }}" schematic "{{ schematic }}"

[doc('Generate schematic ID from a node schematic')]
gen-schematic-id node:
    curl -sX POST --data-binary @<(just template "{{ talos_dir }}/nodes/controlplane/{{ node }}.schematic.yaml.j2") "https://factory.talos.dev/schematics" | jq -r '.id'

[confirm('Reboot node ' + node + ' [y|N] ?')]
[doc('Reboot a node')]
reboot-node node:
    talosctl -n {{ node }} reboot -m powercycle

# Renders the three layers: the documents shared by every node, the
# control-plane role documents, then the per-node documents. Later patches
# deep-merge into earlier ones by kind, and new documents are appended.
[doc('Render Talos config for a node')]
render-config node:
    schematic="$(just talos gen-schematic-id "{{ node }}")"
    talosctl machineconfig patch <(just template "{{ talos_dir }}/cluster.yaml.j2") \
        -p @<(just template "{{ talos_dir }}/controlplane.yaml.j2") \
        -p @<(just template "{{ talos_dir }}/nodes/controlplane/{{ node }}.yaml.j2" -D "schematic=${schematic}")

[confirm('Reset node ' + node + ' [y|N] ?')]
[doc('Reset a node')]
reset-node node *args:
    talosctl -n "{{ node }}" reset --system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL --system-labels-to-wipe u-local-hostpath --graceful=false {{ args }}

[confirm('Shutdown node ' + node + ' [y|N] ?')]
[doc('Shutdown a node')]
shutdown-node node *args:
    talosctl -n "{{ node }}" shutdown --force {{ args }}

[confirm('Upgrade Kubernetes to ' + version + ' [y|N] ?')]
[doc('Upgrade Kubernetes version on the cluster')]
upgrade-k8s version:
    talosctl -n "{{ controller }}" upgrade-k8s --to {{ version }}

[confirm('Upgrade node ' + node + ' [y|N] ?')]
[doc('Upgrade Talos version on a node')]
upgrade-node node *args:
    talosctl -n "{{ node }}" upgrade -i "$(just talos machine-image "{{ node }}")" -m powercycle --timeout=10m {{ args }}

[private]
machine-image node:
    schematic="$(just talos gen-schematic-id "{{ node }}")"
    just template "{{ talos_dir }}/nodes/controlplane/{{ node }}.yaml.j2" -D "schematic=${schematic}" \
        | yq -r -e 'select(.kind == "UnattendedInstallConfig") | .installer.image'
