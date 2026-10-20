#!/usr/bin/env bash
set -euo pipefail
KIND="${1:?plan|apply|refresh|import|destroy}"
log(){ printf '%s %s\n' "$(date -u +%FT%TZ)" "$*"; }
finish(){ # $1 state $2 summary-json
  jq -n --arg s "$1" --argjson sum "${2:-{}}" --arg at "$(date -u +%FT%TZ)" --arg run "$RUN_ID" \
     '{run_id:$run,state:$s,summary:$sum,finished_at:$at}' > /work/result.json
  gcsutil cp /work/result.json "${ARTIFACTS_URI}result.json" || true
  gcsutil cp /work/run.log "${ARTIFACTS_URI}run.log" || true
}
trap 'rc=$?; [ $rc -ne 0 ] && finish failed "{\"exit_code\":$rc}"' ERR
exec > >(tee -a /work/run.log) 2>&1

log "run=$RUN_ID attempt=$ATTEMPT kind=$KIND tenant=$TENANT_ID"
# 1. Fetch expected generation (rendered root module) — never modified here
gcsutil cp -r "$EXPECTED_URI" /work/expected/ || { finish failed '{"phase":"fetch"}'; exit 40; }
cd /work/expected
# 2. Init with the LOB bucket backend; impersonate the tenant SA for backend and provider (15-minute tokens)
cat > backend.override.hcl <<EOF
bucket = "${STATE_BUCKET}"
prefix = "${STATE_PREFIX}"
impersonate_service_account = "${TENANT_SA}"
EOF
terraform init -input=false -no-color -lockfile=readonly -backend-config=backend.override.hcl || { finish failed '{"phase":"init"}'; exit 20; }

case "$KIND" in
  plan|refresh|import)
    EXTRA=""; [ "$KIND" = refresh ] && EXTRA="-refresh-only"
    set +e; terraform plan -input=false -no-color -lock-timeout=5m -detailed-exitcode $EXTRA -out=plan.tfplan > plan.txt; rc=$?; set -e
    if [ $rc -eq 1 ]; then grep -qi 'Error acquiring the state lock' plan.txt && { finish failed '{"phase":"plan","class":"lock"}'; exit 30; }; finish failed '{"phase":"plan"}'; exit 20; fi
    terraform show -json plan.tfplan > plan.json
    # 3. Plan-stage policy (SSP-POL-2xx) with the pinned bundle
    gcsutil cp "$POLICY_BUNDLE_URI" /work/policy.tar.gz
    jq -n --arg t "$TENANT_ID" --argjson b "$BATCH_INSTANCES" --slurpfile p plan.json \
      '{stage:"plan",tenant:{tenant_id:$t},batch:{resource_instances:$b},plan:$p[0]}' > policy_input.json
    opa eval -b /work/policy.tar.gz -i policy_input.json -f json 'data.ssp.plan.decision' > policy.json
    RESULT=$(jq -r '.result[0].expressions[0].value.result' policy.json)
    SUMMARY=$(jq -c '{add:([.resource_changes[]?|select(.change.actions|index("create"))]|length),
                       change:([.resource_changes[]?|select(.change.actions|index("update"))]|length),
                       destroy:([.resource_changes[]?|select(.change.actions|index("delete"))]|length),
                       replace:([.resource_changes[]?|select(.change.actions==["delete","create"] or .change.actions==["create","delete"])]|length),
                       changed: ($rc!=0)}' --argjson rc $rc plan.json)
    for f in plan.tfplan plan.txt plan.json policy.json; do gcsutil cp $f "${ARTIFACTS_URI}$f"; done
    if [ "$RESULT" != "allow" ]; then finish denied "$(jq -c --argjson s "$SUMMARY" '.result[0].expressions[0].value + {plan:$s}' policy.json)"; exit 10; fi
    finish succeeded "$SUMMARY"; exit 0 ;;
  apply|destroy)
    # 4. Apply exactly the gated plan file from the plan run (SSP-WF-022)
    gcsutil cp "${PLAN_FROM_RUN}plan.tfplan" /work/expected/plan.tfplan || { finish failed '{"phase":"fetch-plan"}'; exit 40; }
    set +e; terraform apply -input=false -no-color -lock-timeout=5m plan.tfplan > apply.log; rc=$?; set -e
    gcsutil cp apply.log "${ARTIFACTS_URI}apply.log"
    if [ $rc -ne 0 ]; then grep -qi 'Error acquiring the state lock' apply.log && { finish failed '{"phase":"apply","class":"lock"}'; exit 30; }; finish failed '{"phase":"apply"}'; exit 20; fi
    terraform output -json > outputs.json           # worker filters to ServiceSpec.outputs (non-secret) before storing
    gcsutil cp outputs.json "${ARTIFACTS_URI}outputs.json"
    terraform state pull > state.json && jq '{serial, lineage, resources: [.resources[]|{module,type,name,instances:[.instances[]|{attributes:{id:.attributes.id,name:.attributes.name}}]}]}' state.json > observed.json
    gcsutil cp observed.json "${ARTIFACTS_URI}observed.json"; rm -f state.json
    finish succeeded "$(jq -c '{outputs_keys:[keys[]]}' outputs.json)"; exit 0 ;;
esac
