import json
import os
import boto3

bedrock = boto3.client("bedrock-runtime", region_name=os.environ["REGION"])
sns = boto3.client("sns", region_name=os.environ["REGION"])
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
PROJECT = os.environ.get("PROJECT", "arogya")
ENV = os.environ.get("ENVIRONMENT", "prod")
MODEL_ID = "amazon.nova-lite-v1:0"


def lambda_handler(event, context):
    for record in event.get("Records", []):
        try:
            sns_msg = json.loads(record["Sns"]["Message"])
            alarm_name = sns_msg.get("AlarmName", "Unknown")
            alarm_desc = sns_msg.get("AlarmDescription", "")
            state = sns_msg.get("NewStateValue", "")
            reason = sns_msg.get("NewStateReason", "")

            prompt = (
                f"You are an AWS SRE assistant. A CloudWatch alarm fired:\n"
                f"Alarm: {alarm_name}\n"
                f"Description: {alarm_desc}\n"
                f"State: {state}\n"
                f"Reason: {reason}\n\n"
                f"In 3-5 bullet points, explain the likely cause and recommended remediation steps."
            )

            response = bedrock.invoke_model(
                modelId=MODEL_ID,
                body=json.dumps({
                    "messages": [{"role": "user", "content": [{"text": prompt}]}],
                    "inferenceConfig": {"maxTokens": 512, "temperature": 0.3},
                }),
                contentType="application/json",
                accept="application/json",
            )

            result = json.loads(response["body"].read())
            diagnosis = result["output"]["message"]["content"][0]["text"]

            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject=f"[AIOps] {alarm_name} — Diagnosis",
                Message=f"Alarm: {alarm_name}\nState: {state}\n\nDiagnosis:\n{diagnosis}",
            )

        except Exception as e:
            print(f"AIOps error: {e}")

    return {"statusCode": 200}
