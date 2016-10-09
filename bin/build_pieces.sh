#!/usr/bin/env sh
#
#
# OHAI, you're reading this? 
# set an  ENV variable named 
# PROFILE to run as not-default
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
  STREAMSID=`echo ${AWS} | python -c 'import sys, json; ins=(json.load(sys.stdin)["items"]); apis=[ d["'"id"'"] for d in ins if d["'"path"'"] == "/streams"]; print apis[0];' 2>/dev/null`
else 
  echo "${AWS}"
  exit ${EXIT}
fi

# Create the /streams path 
if [[ -z ${STREAMSID} ]]; then
  AWS=`aws apigateway create-resource ${IAM_PROFILE} --rest-api-id ${OURAPI} --parent-id ${PARENTID} --path-part streams 2>&1`
  EXIT=$?
  if [[ ${EXIT} -eq 0 ]]; then
    :
  else 
    if echo ${AWS} | grep 'Another resource with the same parent already has this name' >/dev/null; then
      # null operator because it already exists
      STREAMSID=`echo ${AWS} | python -c 'import sys, json; ins=(json.load(sys.stdin)["items"]); apis=[ d["'"id"'"] for d in ins if d["'"path"'"] == "/streams"]; print apis[0];' 2>/dev/null`
    else
      echo "${AWS}"
      exit ${EXIT}
    fi
  fi
fi

if [[ -z ${STREAMSID} ]]; then
  echo "/streams path in the api gateway was not found and was not created. ur screwed."
  exit 1
fi
