# MikroTik Manager rollout

## Data services

1. In the Kubernetes vault, create a 1Password item named `mikrotik-manager`.
   Add `postgres_password`, `redis_password`, `influxdb_admin_password`,
   `influxdb_token`, `jwt_secret`, and `encryption_key` as concealed fields.
   Generate each independently. Use at least 32 random characters for the JWT
   secret and exactly 32 ASCII characters for the encryption key. Keep the
   encryption key with the recovery material for the database.
2. Reconcile PostgreSQL, Valkey, and InfluxDB. Confirm the ExternalSecrets,
   PostgreSQL and data-store releases are Ready. Verify the Barman backup, Valkey
   authentication and persistence, and an authenticated write and query in
   InfluxDB's `metrics` bucket.
3. Reconcile the app and check that its migrations succeed on PostgreSQL 18.
   Verify Kopiur snapshots for the app and InfluxDB and rehearse a restore in
   isolation with the same encryption key.

## Internal UI and Kanidm

1. Run `kubectl -n mikrotik-manager port-forward svc/mikrotik-manager 8080:80`.
   Open `http://localhost:8080`, sign in as `admin` with the seeded password
   `admin`, then rotate the password and save the recovery credential in
   1Password.
2. Remove `suspend: true` from `mikrotik-manager-edge` in [ks.yaml](ks.yaml).
   Reconcile and check the HTTPRoute's `Accepted` and `ResolvedRefs` conditions.
3. In Settings → SSO / OIDC, enter issuer
   `https://auth.judahrand.net/oauth2/openid/mikrotik-manager`, client ID
   `mikrotik-manager`, and the `CLIENT_SECRET` from the operator-generated
   `mikrotik-manager-kanidm-oauth2-credentials` Secret. Set public base URL to
   `https://mikrotik-manager.judahrand.net`. Use scopes `openid profile email`,
   set the groups claim to `mikrotik_manager_roles`, and map `admin` to the app's
   admin role. Enable auto-provisioning for the scoped Kanidm group and leave
   verified-email linking disabled.
4. Verify HTTPS, Socket.IO, Kanidm administrator sign-in, denial for a user
   outside the group, and local recovery sign-in.

## RouterOS pilot and NetFlow

1. Enrol one router by its management IP over routed API-SSL on TCP `8729`
   using a dedicated polling account. Confirm polling and the source address
   RouterOS sees. Choose the same management IP as the IPFIX export source.
2. Recheck that `10.0.42.128` is available in Cilium IPAM and the network.
   Restrict access to UDP `2055` at the network boundary to the pilot exporter.
   Set `exporter_ip` in your shell to the pilot router's management IP and
   create the Flux input with that address as a `/32`.

    ```sh
    kubectl -n mikrotik-manager create configmap mikrotik-manager-netflow \
      --from-literal=NETFLOW_EXPORTER_CIDR="${exporter_ip}/32"
    ```

3. Remove `suspend: true` from `mikrotik-manager-netflow` in Git. Reconcile and
   confirm the VIP is assigned and advertised only by the node with the ready
   backend. Enable the collector on UDP `2055` in MikroTik Manager and keep
   unknown exporters disabled.
4. Configure the pilot router's Traffic Flow/IPFIX target as
   `10.0.42.128:2055`. Verify the collector sees the router's management IP,
   attributes traffic to that device, rejects unauthorized sources, and resumes
   ingestion after a backend restart.

To roll back exposure, remove the router's export target and remove the
HTTPRoute and UDP Service from Git so Flux prunes them. Suspending a
Kustomization freezes resources already applied. Keep the database, claims, and
secrets for recovery. If an upgrade changes the schema incompatibly, restore
the matching pre-upgrade database and application state before reverting the
images.
