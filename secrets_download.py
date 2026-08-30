import boto3
sm_client = boto3.client('secretsmanager', region_name='us-east-1')
# services_dict = {'admin': {'file_name': 'admin_secrets', 'secret_name': 'dev-us-admin-secrets'}, 'talech': {'file_name': 'talech_secrets', 'secret_name': 'dev-us-web-secrets'}, 'microsite': {'file_name': 'talech_secrets', 'secret_name': ''}}
services_dict = {'metrix-druid-master': {'file_name': 'metrix_druid_master_secrets', 'secret_name': 'dev-us-druid-secrets'}}
for service, values in services_dict.items():
    if values['secret_name'] != '':
        response = sm_client.get_secret_value(SecretId=values['secret_name'])
        secret_value = response['SecretString']

        with open(f'/opt/talech/config/{values["file_name"]}', 'w+') as f:
            f.write(secret_value)
        print(f"Secret {values['secret_name']} downloaded to /opt/talech/config/{values['file_name']}")