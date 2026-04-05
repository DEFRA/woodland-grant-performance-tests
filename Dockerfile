FROM grafana/k6

COPY scenarios/ ./scenarios/
COPY entrypoint.sh .
COPY generate-report.sh .

ENV S3_ENDPOINT=https://s3.eu-west-2.amazonaws.com
ENV GENERATE_REPORT=true

USER root

RUN apk add --no-cache aws-cli
RUN chmod +x generate-report.sh

RUN mkdir -p /reports
RUN chown -R k6:k6 /reports
VOLUME reports

USER k6

ENTRYPOINT [ "./entrypoint.sh" ]
