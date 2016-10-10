#!/usr/bin/env sh
#
#
# OHAI, you're reading this? 
# set an  ENV variable named 
# PROFILE to run as not-default
## 
## Everything is in us-west-2. change that if you need to
## 
if [[ -z $PROFILE ]]; then
  IAM_PROFILE=""
else
  IAM_PROFILE=" --profile ${PROFILE} "
fi
which aws >/dev/null || { echo "Install aws cli"; exit 1; }
which curl >/dev/null || { echo "Install curl"; exit 1; }

STREAM_NAME="webhooks"

### Make an IAM role for the api-gateway to run as
AWS=`aws iam create-role ${IAM_PROFILE} --role-name api_kinesis_post --assume-role-policy-document '{ "Version": "2012-10-17", "Statement": [ { "Sid": "", "Effect": "Allow", "Principal": { "Service": "apigateway.amazonaws.com" }, "Action": "sts:AssumeRole" } ] }' 2>&1`
EXIT=$?
if [[ ${EXIT} -eq 0 ]]; then
  # XXX come back and parse this shit
  ROLEARN=`echo ${AWS} | python -c 'import sys, json; print json.load(sys.stdin)["Role"]["Arn"];'`
else 
  if echo ${AWS} | grep 'already exists\.$' >/dev/null; then
    # null operator because it already exists
    ROLEARN=`aws iam get-role ${IAM_PROFILE}  --role-name api_kinesis_post | grep Arn | awk '{print $(NF)}' | sed -e 's/"//g'`
  else
    echo "${AWS}"
    exit ${EXIT}
  fi
fi
echo "Created IAM role ${ROLEARN}"
echo ""

### Since we want to write, it needs kind of a lot of perms, 
###  api gateway will assume this role
AWS=`aws iam attach-role-policy ${IAM_PROFILE} --role-name api_kinesis_post --policy-arn arn:aws:iam::aws:policy/AmazonKinesisFullAccess 2>&1`
EXIT=$?
if [[ ${EXIT} -eq 0 ]]; then
  :
else 
  if echo ${AWS} | grep 'already exists\.$' >/dev/null; then
    # null operator because it already exists
    :
  else
    echo "${AWS}"
    exit ${EXIT}
  fi
fi
echo "Attached arn:aws:iam::aws:policy/AmazonKinesisFullAccess to ${ROLEARN}"
echo ""

### Trust me, you want logs
AWS=`aws iam attach-role-policy ${IAM_PROFILE} --role-name api_kinesis_post --policy-arn arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs 2>&1`
EXIT=$?
if [[ ${EXIT} -eq 0 ]]; then
  :
else 
  if echo ${AWS} | grep 'already exists\.$' >/dev/null; then
    # null operator because it already exists
    :
  else
    echo "${AWS}"
    exit ${EXIT}
  fi
fi
echo "Attached arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs to ${ROLEARN}"
echo ""

### And we need a stream
AWS=`aws kinesis create-stream ${IAM_PROFILE} --stream-name ${STREAM_NAME} --shard-count 1 2>&1`
EXIT=$?
if [[ ${EXIT} -eq 0 ]]; then
  :
else 
  if echo ${AWS} | grep 'already exists\.$' >/dev/null; then
    # null operator because it already exists
    :
  else
    echo "${AWS}"
    exit ${EXIT}
  fi
fi
echo "Created kinesis stream ${STREAM_NAME}"
echo ""

### get that rest API
### or create it
### This is gross. welcome to shell
APIS=`aws apigateway get-rest-apis ${IAM_PROFILE} 2>&1`
EXIT=$?
if [[ ${EXIT} -eq 0 ]]; then
  :
  NUMAPIS=`echo ${APIS} | python -c 'import sys, json; ins=(json.load(sys.stdin)["items"]); apis=[ d["'"id"'"] for d in ins if d["'"name"'"] == "webhooks_to_kinesis"]; print len(apis);'`
  if [[ ${NUMAPIS} -gt 1 ]]; then
    echo "There were ${NUMAPIS} apis with the name 'webhooks_to_kinesis', should be zero or one"
    exit ${EXIT}
  elif [[ ${NUMAPIS} -eq 0 ]]; then
    ### Then a API Gateway REST api
    AWS=`aws apigateway create-rest-api ${IAM_PROFILE} --name webhooks_to_kinesis 2>&1`
    EXIT=$?
    if [[ ${EXIT} -eq 0 ]]; then
      :
      OURAPI=`echo ${AWS} | python -c 'import sys, json; print json.load(sys.stdin)["id"];'`
    else 
      if echo ${AWS} | grep 'already exists\.$' >/dev/null; then
        # null operator because it already exists
        :
      else
        echo "${AWS}"
        exit ${EXIT}
      fi
    fi
  elif [[ ${NUMAPIS} -eq 1 ]]; then
    OURAPI=`echo ${APIS} | python -c 'import sys, json; ins=(json.load(sys.stdin)["items"]); apis=[ d["'"id"'"] for d in ins if d["'"name"'"] == "webhooks_to_kinesis"]; print apis[0];'`
  fi 
else 
  if echo ${APIS} | grep 'already exists\.$' >/dev/null; then
    # null operator because it already exists
    :
  else
    echo "${APIS}"
    exit ${EXIT}
  fi
fi
echo "API created/found ${OURAPI}"
echo ""

### get that rest API's root resource
AWS=`aws apigateway get-resources ${IAM_PROFILE} --rest-api-id ${OURAPI} 2>&1`
EXIT=$?
if [[ ${EXIT} -eq 0 ]]; then
  PARENTID=`echo ${AWS} | python -c 'import sys, json; ins=(json.load(sys.stdin)["items"]); apis=[ d["'"id"'"] for d in ins if d["'"path"'"] == "/"]; print apis[0];'`
  STREAMSID=`echo ${AWS} | python -c 'import sys, json; ins=(json.load(sys.stdin)["items"]); apis=[ d["'"id"'"] for d in ins if d["'"path"'"] == "/islandstreams"]; print apis[0];' 2>/dev/null`
else 
  echo "${AWS}"
  exit ${EXIT}
fi
echo "API resources found. ParentId:${PARENTID} StreamsId:${STREAMSID}"
echo ""

# Create the /islandstreams path 
if [[ -z ${STREAMSID} ]]; then
  AWS=`aws apigateway create-resource ${IAM_PROFILE} --rest-api-id ${OURAPI} --parent-id ${PARENTID} --path-part islandstreams 2>&1`
  EXIT=$?
  if [[ ${EXIT} -eq 0 ]]; then
    # null operator because it already exists
    STREAMSID=`echo ${AWS} | python -c 'import sys, json; ins=json.load(sys.stdin)["id"]; print ins;' 2>/dev/null`
  else 
    if echo ${AWS} | grep 'Another resource with the same parent already has this name' >/dev/null; then
      :
    else
      echo "${AWS}"
      exit ${EXIT}
    fi
  fi
fi
echo "Created/Found path \"/islandstreams\" on API"
echo ""

if [[ -z ${STREAMSID} ]]; then
  echo "/islandstreams path in the api gateway was not found and was not created. ur screwed."
  exit 1
fi
if [[ -z ${ROLEARN} ]]; then
  echo "didn't make an iam role. cannot continue"
  exit 1
fi

# add the put method on the resource
AWS=`aws apigateway put-method ${IAM_PROFILE} --rest-api-id ${OURAPI} --resource-id ${STREAMSID} --http-method 'POST' --authorization-type 'NONE' --region us-west-2 2>&1`
EXIT=$?
if [[ ${EXIT} -eq 0 ]]; then
  # null operator because we just built it
  :
else 
  if echo ${AWS} | grep 'Method already exists for this resource' >/dev/null; then
    :
  else
    echo "${AWS}"
    exit ${EXIT}
  fi
fi
echo "Added POST method to ${OURAPI}"
echo ""


cat <<\EOT > /var/tmp/template.json.$$
{"application/json": "{     \"StreamName\": \"webhooks\",\n  \"Data\": \"$util.base64Encode($input.path('$'))\",\n  \"PartitionKey\": \"shardId-000000000000\" }"}
EOT
cat <<EOT > /var/tmp/req_parms.json.$$
{
            "integration.request.header.ContentType": "'application/x-amz-json-1.1'"
        }
EOT
# Now add the integration '
AWS=`aws apigateway put-integration ${IAM_PROFILE} --rest-api-id ${OURAPI} --resource-id ${STREAMSID} --http-method POST --type AWS --integration-http-method POST --uri arn:aws:apigateway:us-west-2:kinesis:action/PutRecord --credentials ${ROLEARN} --request-parameters file:///var/tmp/req_parms.json.$$ --request-templates file:///var/tmp/template.json.$$  2>&1`
EXIT=$?
if [[ ${EXIT} -eq 0 ]]; then
  # null operator because we just built it
  :
else 
  if echo ${AWS} | grep 'Method already exists for this resource' >/dev/null; then
    :
  else
    echo "${AWS}"
    exit ${EXIT}
  fi
fi
echo "Linked up \"/islandstreams\" input to kinesis stream ${STREAM_NAME}"
echo ""

# And the integration response, because AWS is fucking craycray
AWS=`aws apigateway put-integration-response ${IAM_PROFILE} --rest-api-id ${OURAPI} --resource-id ${STREAMSID} --http-method POST --status-code 200 --response-templates '{ "application/json": ""}' 2>&1`;
EXIT=$?
if [[ ${EXIT} -eq 0 ]]; then
  # null operator because we just built it
  :
else 
  if echo ${AWS} | grep 'Method already exists for this resource' >/dev/null; then
    :
  else
    echo "${AWS}"
    exit ${EXIT}
  fi
fi
echo "Set up \"/islandstreams\" response mapping"
echo ""

# And the method response, because AWS is fucking craycray
AWS=`aws apigateway put-method-response ${IAM_PROFILE} --rest-api-id ${OURAPI} --resource-id ${STREAMSID} --http-method POST --status-code 200 --response-models '{ "application/json": "Empty" }' 2>&1`
EXIT=$?
if [[ ${EXIT} -eq 0 ]]; then
  # null operator because we just built it
  :
else 
  if echo ${AWS} | grep 'Response already exists for this resource' >/dev/null; then
    :
  else
    echo "${AWS}"
    exit ${EXIT}
  fi
fi
echo "Set up \"/islandstreams\" actual response"
echo ""

echo "Now we have to wait a 90 seconds for the dust to settle (really only needed on first run)"
sleep 90

# And then deploy because AWS -> AWS -> AWS -> AWS
AWS=`aws apigateway create-deployment ${IAM_PROFILE} --rest-api-id ${OURAPI} --stage-name prod 2>&1`
EXIT=$?
if [[ ${EXIT} -eq 0 ]]; then
  # null operator because we just built it
  :
else 
  if echo ${AWS} | grep 'Method already exists for this resource' >/dev/null; then
    :
  else
    echo "${AWS}"
    exit ${EXIT}
  fi
fi
echo "Created Deployment \"prod\" of the API"
echo ""

APIURL="https://${OURAPI}.execute-api.us-west-2.amazonaws.com/prod/islandstreams"

echo "APIURL is known to be ${APIURL}"
echo ""

CMD=`curl -XPOST -H "Content-type: application/json" -d '{"this": "test", "data": [ 1,2,3, "ok"], "objects": {"nested": true, "flat": false }}' ${APIURL} 2>/dev/null`
EXIT=$?
if [[ ${EXIT} -eq 0 ]]; then
  # null operator because we got the data in
  echo "Successfully CURLed data in at ${APIURL}, output on next line"
  echo "${CMD}"
  echo ""
else 
  echo "curl of our apigateway at ${APIURL} failed"
  exit ${EXIT}
fi


# kinesis leaves a little to be desired. 
# Gotta get a shard iterator then get records
#  futher, the shard name doesn't matter very much with one shard
AWS=`aws kinesis get-shard-iterator ${IAM_PROFILE} --stream-name ${STREAM_NAME} --shard-id shard-0000 --shard-iterator-type TRIM_HORIZON 2>&1`
EXIT=$?
if [[ ${EXIT} -eq 0 ]]; then
  # Get the right bit
  SHARDITER=`echo ${AWS} | python -c 'import sys, json; ins=json.load(sys.stdin)["ShardIterator"]; print ins;' 2>/dev/null`
else 
  if echo ${AWS} | grep 'Method already exists for this resource' >/dev/null; then
    :
  else
    echo "${AWS}"
    exit ${EXIT}
  fi
fi

# 
# With a shard iterator, you can get records
#  futher, the shard name doesn't matter very much with one shard
AWS=`aws kinesis get-records ${IAM_PROFILE} --shard-iterator ${SHARDITER} 2>&1`
EXIT=$?
if [[ ${EXIT} -eq 0 ]]; then
  # show success
  PARSEDOUTPUT=`echo ${AWS} | python -c 'import sys, json, base64, pprint; records=(json.load(sys.stdin)["Records"]); recordtexts=[ base64.b64decode(r["'"Data"'"]) for r in records]; pprint.pprint(recordtexts);'`
  echo "Successfully did get-records from webhooks kinesis stream"
  echo ""
  echo "${PARSEDOUTPUT}"
else 
  echo "${AWS}"
  exit ${EXIT}
fi



