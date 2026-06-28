import json
import os
import boto3

ses = boto3.client("ses")
SENDER = os.environ["SES_SENDER_EMAIL"]
ENV = os.environ.get("ENVIRONMENT", "prod")


def lambda_handler(event, context):
    for record in event.get("Records", []):
        try:
            body = json.loads(record["body"])
            patient_email = body.get("patient_email", "")
            doctor_email = body.get("doctor_email", "")
            patient_name = body.get("patient_name", "Patient")
            doctor_name = body.get("doctor_name", "Doctor")
            status = body.get("status", "updated")
            appointment_id = body.get("appointment_id", "")

            subject = f"[Arogya] Appointment {status.capitalize()} — {appointment_id[:8]}"
            body_text = (
                f"Hello,\n\n"
                f"Your appointment has been {status}.\n\n"
                f"Patient : {patient_name}\n"
                f"Doctor  : {doctor_name}\n"
                f"Status  : {status.upper()}\n\n"
                f"Log in to Arogya to view details.\n\n"
                f"— Arogya Health Platform"
            )

            recipients = [e for e in [patient_email, doctor_email] if e]
            if recipients:
                ses.send_email(
                    Source=SENDER,
                    Destination={"ToAddresses": recipients},
                    Message={
                        "Subject": {"Data": subject},
                        "Body": {"Text": {"Data": body_text}},
                    },
                )
        except Exception as e:
            print(f"Error processing record: {e}")
            raise

    return {"statusCode": 200}
