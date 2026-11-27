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
3. Confirm that `10.0.1.31` is free on VLAN 1 and reserve it outside the DHCP
   pool before merging the deployment. Check that the migrations succeed on
   PostgreSQL 18. Verify Kopiur snapshots for the app and InfluxDB and rehearse a
   restore in isolation with the same encryption key.

## Internal UI and Kanidm

1. Run `kubectl -n mikrotik-manager port-forward svc/mikrotik-manager 8080:80`.
   Open `http://localhost:8080`, sign in as `admin` with the seeded password
   `admin`, then rotate the password and save the recovery credential in
   1Password.
2. Set `route.app.enabled` to `true` in the app's
   [HelmRelease](app/helmrelease.yaml). Reconcile and check the HTTPRoute's
   `Accepted` and `ResolvedRefs` conditions.
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

## VLAN 1 discovery and NetFlow

1. Enrol one router by its management IP over routed API-SSL on TCP `8729`
   using a dedicated polling account. Confirm polling and the source address
   RouterOS sees. Choose the same management IP as the IPFIX export source.
2. Confirm the backend pod has `10.0.1.31/24` on `net1`. Run
   `arp-scan --localnet --quiet` in the backend container and check that it
   finds VLAN 1 neighbours. Confirm TCP `3001` is blocked when accessed via the
   VLAN 1 address and works through nginx.
3. Enable the collector on UDP `2055` in MikroTik Manager and keep unknown
   exporters disabled. The VLAN 1 network policy permits this port from
   `10.0.1.0/24`.
4. Configure the pilot router's Traffic Flow/IPFIX target as
   `10.0.1.31:2055`. Verify the collector sees the router's management IP,
   attributes traffic to that device, rejects unauthorized sources, and resumes
   ingestion after a backend restart.

To roll back NetFlow, remove the router's export target and disable the
collector in MikroTik Manager. To withdraw the web UI, set
`route.app.enabled` to `false` in Git. Keep the database, claims, and secrets
for recovery. If an upgrade changes the schema incompatibly, restore the
matching pre-upgrade database and application state before reverting the images.
