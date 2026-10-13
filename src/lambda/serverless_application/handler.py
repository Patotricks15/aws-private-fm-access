"""serverless_application: runs inside VPC #1's private subnet.

Fetches a customer record from the private customer database (DynamoDB) and
then invokes a foundation model over the private VPC endpoint path — the
"Endpoint" in VPC #1, across the private connection (VPC peering, standing in
for PrivateLink), through to the "Access FM models" endpoint in VPC #2 — so
that no traffic ever traverses the public internet.
"""
import json
import os

import boto3

REGION = os.environ.get("REGION", "us-east-1")
CUSTOMER_TABLE_NAME = os.environ["CUSTOMER_TABLE_NAME"]
TEXT_MODEL_ID = os.environ["TEXT_MODEL_ID"]

_boto_kwargs = {
    "region_name": REGION,
    # In a real deployment this would resolve to the private DNS name of the
    # VPC interface endpoint (app_access) instead of a public endpoint; this
    # fixed URL targets the local floci emulator that simulates it.
    "endpoint_url": "http://localhost:4566",
    "aws_access_key_id": "test",
    "aws_secret_access_key": "test",
}

dynamodb = boto3.resource("dynamodb", **_boto_kwargs)
bedrock = boto3.client("bedrock-runtime", **_boto_kwargs)

customer_table = dynamodb.Table(CUSTOMER_TABLE_NAME)


def _fetch_customer(customer_id):
    item = customer_table.get_item(Key={"customerId": customer_id}).get("Item")
    if not item:
        return None
    return item


def _invoke_foundation_model(prompt):
    body = json.dumps({
        "inputText": prompt,
        "textGenerationConfig": {
            "maxTokenCount": 512,
            "temperature": 0.5,
        },
    })
    response = bedrock.invoke_model(
        modelId=TEXT_MODEL_ID,
        body=body,
        contentType="application/json",
        accept="application/json",
    )
    payload = json.loads(response["body"].read())
    results = payload.get("results", [])
    return results[0]["outputText"] if results else ""


def lambda_handler(event, context):
    customer_id = event.get("customerId")
    prompt = event.get("prompt")

    if not customer_id:
        return {"error": "'customerId' is required."}

    customer = _fetch_customer(customer_id)
    if not customer:
        return {"error": f"Customer {customer_id} not found."}

    if not prompt:
        prompt = f"Write a one-sentence, {customer.get('tier', 'STANDARD')}-tier greeting for {customer.get('name', 'the customer')}."

    model_output = _invoke_foundation_model(prompt)

    return {
        "customer": customer,
        "model": TEXT_MODEL_ID,
        "output": model_output,
    }
