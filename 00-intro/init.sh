#!/bin/bash

set -e

# base64 miscellaneous methods
base64variable() {
  printf "$1" | base64stream
}

base64stream() {
  base64 | tr '/+' '_-' | tr -d '=\n'
}

# get token from GCP
key_file="gckey.json"
auth_scope="https://www.googleapis.com/auth/cloud-platform"
valid_for="${3:-3600}"
private_key=$(jq -r .private_key $key_file)
client_email=$(jq -r .client_email $key_file)

header='{"alg":"RS256","typ":"JWT"}'
claim=$(
  cat <<EOF
  {
    "iss": "$client_email",
    "scope": "$auth_scope",
    "aud": "https://www.googleapis.com/oauth2/v4/token",
    "exp": $(($(date +%s) + $valid_for)),
    "iat": $(date +%s)
  }
EOF
)
request_body="$(base64variable "$header").$(base64variable "$claim")"
signature=$(openssl dgst -sha256 -sign <(echo "$private_key") <(printf "$request_body") | base64stream)

token=$(curl -s -X POST https://www.googleapis.com/oauth2/v4/token \
  --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' \
  --data-urlencode "assertion=$request_body.$signature" |
  jq -r .access_token)

echo $0

# call GCP to create cluster
post_data=$(
  cat <<EOF
{
  "cluster": {
    "name": "$2",
    "network": "projects/apitest-298120/global/networks/default",
    "subnetwork": "projects/apitest-298120/regions/us-central1/subnetworks/default",
    "nodePools": [
      {
        "name": "default-pool",
        "config": {
          "machineType": "e2-micro",
          "diskSizeGb": 10,
          "oauthScopes": [
            "https://www.googleapis.com/auth/devstorage.read_only",
            "https://www.googleapis.com/auth/logging.write",
            "https://www.googleapis.com/auth/monitoring",
            "https://www.googleapis.com/auth/servicecontrol",
            "https://www.googleapis.com/auth/service.management.readonly",
            "https://www.googleapis.com/auth/trace.append"
          ],
          "imageType": "COS",
          "diskType": "pd-standard",
          "shieldedInstanceConfig": {
            "enableIntegrityMonitoring": true
          }
        },
        "initialNodeCount": 1,
        "version": "1.16.15-gke.4300"
      }
    ],
    "ipAllocationPolicy": {
      "useIpAliases": true
    },
    "databaseEncryption": {
      "state": "DECRYPTED"
    },
    "clusterTelemetry": {
      "type": "ENABLED"
    },
    "initialClusterVersion": "1.16.15-gke.4300",
    "location": "us-central1-c"
  }
}
EOF
)

curl -X POST -H "Authorization: Bearer $token" -H "Content-Type:application/json" \
  --data "$post_data" \
  "https://container.googleapis.com/v1beta1/projects/apitest-298120/zones/us-central1-a/clusters"
