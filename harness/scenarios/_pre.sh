# Helper functions sourced by scenario pre.sh files (cwd = /work, before the baseline manifest).
mkenv() {      # docker/docker-compose.env with Harbor creds present (so no Harbor prompt)
    cp docker/docker-compose.env.example docker/docker-compose.env
    sed -i 's/^HARBOR_USERNAME=.*/HARBOR_USERNAME=robot$$cust/; s/^HARBOR_PASSWORD=.*/HARBOR_PASSWORD=secret/' docker/docker-compose.env
}
mkenv_noharbor() { cp docker/docker-compose.env.example docker/docker-compose.env; }
mkcustom() { cp docker/docker-compose.custom.yml.example docker/docker-compose.custom.yml; }
mkcns()    { touch kubernetes/scripts/cns/.cns_config; }
mkdup()    { mkdir -p /opt/miniprem-old; }
mkcustom_conflict() {   # service-name conflict with the official 'renny' service
    cat > docker/docker-compose.custom.yml <<'YML'
services:
  renny:
    image: custom/renny:1
  custom-api:
    image: node:20
    ports:
      - "3100:3000"
volumes:
  api_data:
YML
}
mkcustom_invalid() { printf 'services:\n  broken: [unclosed\n' > docker/docker-compose.custom.yml; }
mkcustom_empty()   { printf 'services: {}\n' > docker/docker-compose.custom.yml; }
mkcustom_postgres() { printf 'services:\n  postgres:\n    image: postgres:15\n    ports:\n      - "5432:5432"\n' > docker/docker-compose.custom.yml; }
