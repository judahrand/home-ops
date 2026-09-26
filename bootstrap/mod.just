set default-script
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

bootstrap_dir := justfile_dir() + '/bootstrap'
kubernetes_dir := justfile_dir() + '/kubernetes'
controller := `talosctl config info -o yaml | yq -e '.endpoints[0]'`
nodes := `talosctl config info -o yaml | yq -e '.nodes | join (" ")'`

[confirm('Bootstrap cluster? [y|N]')]
[private]
default: talos k8s (kubeconfig "node") base apps verify kubeconfig

# Supports per-node address overrides when a freshly reset node is not reachable
# at its DNS-resolved address, e.g. `just bootstrap talos k8s-2=10.0.42.214`.
[doc('Install Talos')]
talos *overrides:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    for n in {{ nodes }}; do
        addr=""
        if [[ -n "{{ overrides }}" ]]; then
            for e in {{ overrides }}; do
                if [[ "$e" == "$n="* ]]; then addr="${e#$n=}"; fi
            done
        fi
        if ! op=$(TALOS_APPLY_ADDR="$addr" just --yes talos apply-node "$n" --insecure 2>&1); then
            if [[ "$op" == *"certificate required"* ]]; then
                just log info "Talos already configured, skipping apply of config" "stage" "{{ recipe_name() }}" "node" "$n"
                continue
            fi
            just log fatal "Failed to apply Talos configuration" "stage" "{{ recipe_name() }}" "node" "$n" "output" "$op"
        fi
    done

[doc('Install Kubernetes')]
k8s:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    until op=$(talosctl -n "{{ controller }}" bootstrap 2>&1 || true) && [[ "$op" == *"AlreadyExists"* ]]; do
        just log info "Kubernetes bootstrap in progress. Retrying in 5 seconds..." "stage" "{{ recipe_name() }}"
        sleep 5
    done

[doc('Fetch kubeconfig')]
kubeconfig lb="cilium":
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    if ! talosctl kubeconfig -n "{{ controller }}" -f --force-context-name main {{ justfile_dir() }}; then
        just log fatal "Failed to fetch kubeconfig" "stage" "{{ recipe_name() }}"
    fi
    if [[ "{{ lb }}" != "cilium" ]]; then
        if ! kubectl config set-cluster main --server "https://{{ controller }}:6443"; then
            just log fatal "Failed to set kubectl cluster server address" "stage" "{{ recipe_name() }}"
        fi
    fi

# Wait until the Kubernetes API server is ready. The `kubeconfig` stage points
# kubectl at the control plane node directly (bypassing the load-balancer, which
# is not up until bootstrap completes) and provides valid credentials, which the
# apiserver requires even for the readiness endpoint.
[doc('Wait for the Kubernetes API to be ready')]
[private]
api-ready:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    until [[ "$(kubectl get --raw '/readyz' 2>/dev/null)" == "ok" ]]; do
        just log info "Waiting for kube-apiserver. Retrying in 5 seconds..." "stage" "{{ recipe_name() }}"
        sleep 5
    done

# Nodes register as Ready=False until the CNI is deployed, so wait until every node
# is visible to the API server before applying namespaces and CRDs.
[doc('Wait for every node to register with the Kubernetes API')]
[private]
nodes-ready:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    if ! kubectl wait nodes --for=condition=Ready=True --all --timeout=10s &>/dev/null; then
        until kubectl wait nodes --for=condition=Ready=False --all --timeout=10s &>/dev/null; do
            just log info "Nodes not available, waiting for nodes to be available. Retrying in 5 seconds..." "stage" "{{ recipe_name() }}"
            sleep 5
        done
    fi

[doc('Apply Kubernetes namespaces')]
namespaces:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    find "{{ kubernetes_dir }}/apps" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r dir; do
        if ! kustomize build "$dir" | yq ea -e 'select(.kind == "Namespace")' | kubectl apply --server-side --field-manager bootstrap --force-conflicts -f -; then
            just log fatal "Failed to apply namespace" "stage" "{{ recipe_name() }}" "namespace" "$(basename "$dir")"
        fi
    done

[doc('Apply personal manifests')]
resources:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    if ! kustomize build "{{ bootstrap_dir }}/kustomize/personal" | just template - | kubectl apply --server-side --field-manager bootstrap --force-conflicts -f -; then
        just log fatal "Failed to apply personal manifests" "stage" "{{ recipe_name() }}"
    fi

[doc('Apply Helmfile CRDs')]
crds:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    if ! helmfile -f "{{ bootstrap_dir }}/helmfile.d/00-crds.yaml" template -q | yq ea -e 'select(.kind == "CustomResourceDefinition")' | kubectl apply --server-side --field-manager bootstrap --force-conflicts -f -; then
        just log fatal "Failed to apply crds" "stage" "{{ recipe_name() }}"
    fi

# Apply the bootstrap base (namespaces, secrets and CRDs) once the API is ready.
[doc('Apply the base Kubernetes resources')]
[private]
base: api-ready nodes-ready namespaces resources crds

[doc('Apply Helmfile Apps')]
apps:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    if ! helmfile -f "{{ bootstrap_dir }}/helmfile.d/01-apps.yaml" sync --hide-notes; then
        just log fatal "Failed to sync helmfile" "stage" "{{ recipe_name() }}"
    fi

[doc('Verify the cluster is healthy')]
verify:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    if ! kubectl wait nodes --for=condition=Ready=True --all --timeout=15m; then
        just log fatal "Nodes did not become Ready within 15 minutes" "stage" "{{ recipe_name() }}"
    fi
    kubectl get nodes -o wide
