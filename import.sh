#!/bin/bash

export CLOUDSDK_CORE_DISABLE_PROMPTS=1

CASTAI_API_URL="${CASTAI_API_URL:-https://api.cast.ai}"

if [ ! -z "$FOLDER_ID" ]; then
  PROJECTS=$(gcloud projects list --filter="parent.id=$FOLDER_ID" --format="value(projectId)")
else
  PROJECTS=${PROJECTS:- $(gcloud projects list --format="value(projectId)")}
fi

PROJECTS=$(echo "$PROJECTS" | awk -F, '{ for(i=1; i<=NF; i++) print $i }') # convert comma-delimited values to new-line

if [ -z $CASTAI_API_TOKEN ] || [ -z $CASTAI_API_URL ]; then
  echo "CASTAI_API_TOKEN or CASTAI_API_URL variables were not provided"
  exit 1
fi

echo "Collecting data from: $(echo "$PROJECTS" | awk '{printf "%s%s",sep,$0; sep=", "}')"

project_data=()
for project in $PROJECTS
do
  commitments=$(gcloud compute commitments list --project $project --format json 2>/dev/null)
  echo -n "${project}: "
  if [ "$commitments" != "[]" ];
  then
    project_data+=("$commitments")
    echo "found $(echo $commitments | jq length) commitments "
  else
    echo "no commitments"
  fi
done

if [ ${#project_data[@]} -eq 0 ]; then
  echo "No commitments found"
  exit 0
fi

echo ""

project_data_json="[$(IFS=,; echo "${project_data[*]}")]"
flattened_project_data_json=$(echo $project_data_json | jq 'flatten')
project_data_json=$(echo $flattened_project_data_json | jq '.')

echo "Sending collected data to CAST AI API"
response_code=$(curl -X POST -s -o /dev/null -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "X-Api-Key: ${CASTAI_API_TOKEN}" \
  -d "$project_data_json" \
  "${CASTAI_API_URL}/v1/savings/commitments/import/gcp/cud?behaviour=OVERWRITE"\
)

if [[ "$response_code" -eq 200 ]]; then
  echo "Done."
else
  echo "Error: upload failed ($response_code)."
  exit 1
fi
