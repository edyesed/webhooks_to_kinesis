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

### Make an IAM role for the api-gateway to run as
AWS=`aws iam create-role ${IAM_PROFILE} --role-name api_kinesis_post --assume-role-policy-document '{ "Version": "2012-10-17", "Statement": [ { "Sid": "", "Effect": "Allow", "Principal": { "Service": "apigateway.amazonaws.com" }, "Action": "sts:AssumeRole" } ] }' 2>&1`
EXIT=$?
if [[ ${EXIT} -eq 0 ]]; then
  # XXX come back and parse this shit
  ROLEARN=`echo ${AWS} | python -c 'import sys, json; print json.load(sys    .stdin)["arn"];'`
else 
  if echo ${AWS} | grep 'already exists\.$' >/dev/null; then
    # null operator because it already exists
    ROLEARN=`aws iam get-role ${IAM_PROFILE}  --role-name api_kinesis_post | grep Arn | awk '{print $(NF)}' | sed -e 's/"//g'`
  else
    echo "${AWS}"
    exit ${EXIT}
  fi
fi

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

### Trust me, you want logs
AWS=`aws iam attach-role-policy ${IAM_PROFILE} --role-name api_kinesis_post --policy-arn arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs
 2>&1`
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

### And we need a stream
AWS=`aws kinesis create-stream ${IAM_PROFILE} --stream-name webhooks --shard-count 1 2>&1`
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

### get that rest API
### or create it
### This is gross. welcome to shell
APIS=`aws apigateway get-rest-apis ${IAM_PROFILE} 2>&1`
EXIT=$?
if [[ ${EXIT} -eq 0 ]]; then
  :
  NUMAPIS=`echo ${APIS} | python -c 'import sys, json; ins=(json.load(sys.stdin)["items"]); apis=[ d["'"id"'"] for d in ins if d["'"name"'"] == "webhooks_to_kinesis"]; print len(apis);'`
  echo "NUMAPIS: ${NUMAPIS}"
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

if [[ -z ${STREAMSID} ]]; then
  echo "/islandstreams path in the api gateway was not found and was not created. ur screwed."
  exit 1
fi
if [[ -z ${ROLEARN} ]]; then
  echo "didn't make an iam role. cannot continue"
  exit 1
fi



### Some things have to be done by raw input
INPUTFILE="/var/tmp/put_method.json.$$"
cat <<EOT > ${INPUTFILE}
{
    "ApiKeyRequired": false,
    "AuthorizationType": "NONE",
    "HttpMethod": "POST",
    "MethodIntegration": {
        "integrationResponses": {
            "200": {
                "responseTemplates": {
                    "application/json": null
                },
                "statusCode": "200"
            }
        },
        "cacheKeyParameters": [],
        "requestParameters": {
            "integration.request.header.ContentType": "'application/x-amz-json-1.1'"
        },
        "uri": "arn:aws:apigateway:us-west-2:kinesis:action/PutRecord",
        "httpMethod": "POST",
        "requestTemplates": {
            "application/json": "{ \"StreamName\": \"webhooks\",\n  \"Data\": \"$util.base64Encode($input.path('$'))\",\n  \"PartitionKey\": \"shardId-000000000000\" }"
        },
        "cacheNamespace": "5eqljb",
        "credentials": "arn:aws:iam::*:role/apigateway_kinesis",
        "type": "AWS"
    },
    "requestParameters": {},
    "methodResponses": {
        "200": {
            "responseModels": {
                "application/json": "Empty"
            },
            "statusCode": "200"
        }
    }
}
EOT

# add the put method on the resource
AWS=`aws apigateway put-method ${IAM_PROFILE} --rest-api-id ${OURAPI} --resource-id ${STREAMSID} --http-method 'POST' --authorization-type 'NONE' --no-api-key-required --request-parameters "method.request.header.custom-header=false" --region us-west-2 2>&1`
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


cat <<EOT > /var/tmp/template.json.$$
{"application/json": "{     \"StreamName\": \"webhooks\",\n  \"Data\": \"$util.base64Encode($input.path    ('$'))\",\n  \"PartitionKey\": \"shardId-000000000000\" }"}
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

