FROM python:3.12.0

RUN pip install \
    mlflow \
    pymysql \
    boto3

HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 CMD curl -f http://localhost:5000/ || exit 1
## Environment variables made available through the Fargate task.
## Do not enter values
CMD mlflow server \
    --host 0.0.0.0 \
    --port ${MLFLOW_PORT} \
    --default-artifact-root ${BUCKET} \
    --backend-store-uri mysql+pymysql://${USERNAME}:${PASSWORD}@${DB_ENDPOINT}/${DATABASE}

