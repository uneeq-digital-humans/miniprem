. /h/scenarios/_pre.sh
mkenv
sed -i 's/^DHOP_APIKEY=.*/DHOP_APIKEY=old_key_0123456789/' docker/docker-compose.env
echo eu > .miniprem_region; echo cloud > .miniprem_deployment_target
